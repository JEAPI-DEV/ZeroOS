const std = @import("std");
const serial = @import("serial.zig");
const storage = @import("storage.zig");
const phys = @import("../memory/phys.zig");
const virt = @import("../memory/virt.zig");
const heap = @import("../memory/heap.zig");
const x64 = @import("../cpu/x64.zig");

// Device Status Bits
const STATUS_ACKNOWLEDGE = 1;
const STATUS_DRIVER = 2;
const STATUS_FAILED = 128;
const STATUS_FEATURES_OK = 8;
const STATUS_DRIVER_OK = 4;

// Feature Bits
// const VIRTIO_BLK_F_RO = 5; // Unused

// Request Types
const VIRTIO_BLK_T_IN = 0;
const VIRTIO_BLK_T_OUT = 1;

const VirtIOBlockReq = extern struct {
    type: u32,
    reserved: u32,
    sector: u64,
};

// We need a queue. For simplicity, we'll implement a basic polled queue.
// VirtQ Descriptor
const VirtqDesc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const VIRTQ_DESC_F_NEXT = 1;
const VIRTQ_DESC_F_WRITE = 2;

// VirtQ Available
const VirtqAvail = extern struct {
    flags: u16,
    idx: u16,
    ring: [QUEUE_SIZE]u16,
    used_event: u16,
};

// VirtQ Used Elem
const VirtqUsedElem = extern struct {
    id: u32,
    len: u32,
};

// VirtQ Used
const VirtqUsed = extern struct {
    flags: u16,
    idx: u16,
    ring: [QUEUE_SIZE]VirtqUsedElem,
    avail_event: u16,
};

const QUEUE_SIZE = 16; // Keep it small for now

var base_addr: usize = 0;
// Make these volatile so compiler doesn't optimize out memory accesses during polling/updates
var queue_desc: *volatile [QUEUE_SIZE]VirtqDesc = undefined;
var queue_avail: *volatile VirtqAvail = undefined;
var queue_used: *volatile VirtqUsed = undefined;
var free_head: u16 = 0;
var initialized = false;

var notify_base: usize = 0;
var notify_multiplier: u32 = 0;

pub fn init(addr: usize, notify_addr: usize, multiplier: u32) void {
    base_addr = addr;
    notify_base = notify_addr;
    notify_multiplier = multiplier;
    const status_ptr = @as(*volatile u8, @ptrFromInt(base_addr + 0x14));

    serial.print("[VirtIO Blk] Initializing at 0x{x} (NotifyBase: 0x{x}, Mul: {d})...\n", .{ base_addr, notify_base, notify_multiplier });

    // 1. Reset
    status_ptr.* = 0;
    while (status_ptr.* != 0) {}

    // 2. Acknowledge & Driver
    status_ptr.* |= STATUS_ACKNOWLEDGE;
    status_ptr.* |= STATUS_DRIVER;

    // 3. Features
    // We MUST negotiate VIRTIO_F_VERSION_1 (Bit 32) to use the Modern MMIO interface used here.
    // If we don't, the device defaults to Legacy (I/O ports), and our MMIO writes might be ignored.

    const dev_feat_sel = @as(*volatile u32, @ptrFromInt(base_addr + 0x00));
    const dev_feat = @as(*volatile u32, @ptrFromInt(base_addr + 0x04));
    const drv_feat_sel = @as(*volatile u32, @ptrFromInt(base_addr + 0x08));
    const drv_feat = @as(*volatile u32, @ptrFromInt(base_addr + 0x0C));

    // Check if device offers Version 1 (Bit 32)
    dev_feat_sel.* = 1; // Select features 32-63
    const feats_high = dev_feat.*;

    if (feats_high & 1 != 0) {
        // Device supports Version 1. Enable it.
        serial.print("[VirtIO Blk] Negotiating VIRTIO_F_VERSION_1...\n", .{});
        drv_feat_sel.* = 1; // Select features 32-63
        drv_feat.* = 1; // Enable Bit 32 (Version 1)
    } else {
        serial.print("[VirtIO Blk] WARNING: Device does not support VIRTIO_F_VERSION_1. Modern MMIO might fail.\n", .{});
        // We might need to fail here if strictly modern logic is used.
    }

    // Legacy support (Bit 0-31)? We can just enable 0 for now unless we need specific features.
    drv_feat_sel.* = 0;
    drv_feat.* = 0;

    status_ptr.* |= STATUS_FEATURES_OK;

    // Re-check if device accepted features
    if (status_ptr.* & STATUS_FEATURES_OK == 0) {
        serial.print("[VirtIO Blk] Feature negotiation failed (Device rejected FEATURES_OK).\n", .{});
        status_ptr.* |= STATUS_FAILED;
        return;
    }

    // 4. Setup Queue 0
    // Select Queue 0
    const q_select = @as(*volatile u16, @ptrFromInt(base_addr + 0x18));
    q_select.* = 0;

    // Set Queue Size
    const q_size = @as(*volatile u16, @ptrFromInt(base_addr + 0x1A));
    q_size.* = QUEUE_SIZE;

    // Allocate Queue Memory
    serial.print("[VirtIO Blk] Allocating queue memory...\n", .{});

    // Use the kernel heap allocator (standard "malloc" style)
    // We need 4KB (1 page) alignment for the queue.
    const queue_slice = heap.allocator.alignedAlloc(u8, 4096, 4096) catch |err| {
        serial.print("[VirtIO Blk] Failed to allocate queue: {s}\n", .{@errorName(err)});
        return;
    };

    const page_virt = @intFromPtr(queue_slice.ptr);
    const page_phys = virt.virtToPhys(page_virt) orelse {
        serial.print("[VirtIO Blk] Failed to get physical address for queue!\n", .{});
        return;
    };

    serial.print("[VirtIO Blk] Queue allocated: Virt=0x{x}, Phys=0x{x}\n", .{ page_virt, page_phys });

    // It's already mapped by the heap, but we need to ensure flags if strictly required?
    // Heap memory is WRITABLE. PWT/PCD (Cache Disable) might be needed for DMA coherency?
    // If so, we remap it.
    virt.remapPage(page_virt, virt.WRITABLE | virt.PWT | virt.PCD);

    // Zero it out
    serial.print("[VirtIO Blk] Zeroing queue memory...\n", .{});
    const ptr = @as([*]u8, @ptrFromInt(page_virt));
    for (0..4096) |i| {
        ptr[i] = 0;
    }

    const desc_phys = page_phys;
    const avail_phys = page_phys + 1024; // Arbitrary offset
    const used_phys = page_phys + 2048;

    queue_desc = @as(*volatile [QUEUE_SIZE]VirtqDesc, @ptrFromInt(page_virt));
    queue_avail = @as(*volatile VirtqAvail, @ptrFromInt(page_virt + 1024));
    queue_used = @as(*volatile VirtqUsed, @ptrFromInt(page_virt + 2048));

    // Initialize free list
    for (0..QUEUE_SIZE - 1) |i| {
        queue_desc[i].next = @as(u16, @intCast(i + 1));
    }
    queue_desc[QUEUE_SIZE - 1].next = 0; // End

    // Write physical addresses to registers
    const q_desc = @as(*align(1) volatile u64, @ptrFromInt(base_addr + 0x22));
    q_desc.* = desc_phys;

    const q_avail = @as(*align(1) volatile u64, @ptrFromInt(base_addr + 0x2A));
    q_avail.* = avail_phys;

    const q_used = @as(*align(1) volatile u64, @ptrFromInt(base_addr + 0x32));
    q_used.* = used_phys;

    // Enable Queue
    const q_enable = @as(*volatile u16, @ptrFromInt(base_addr + 0x1E));
    q_enable.* = 1;

    // 5. Driver OK
    status_ptr.* |= STATUS_DRIVER_OK;

    initialized = true;
    serial.print("[VirtIO Blk] Driver initialized.\n", .{});

    // Register as Block Device
    serial.print("[VirtIO Blk] Registering block device...\n", .{});
    const blk_dev = storage.BlockDevice{
        .context = null,
        .readSector = readSectorWrapper,
        .writeSector = writeSectorWrapper,
    };
    storage.register(blk_dev) catch |err| {
        serial.print("[VirtIO Blk] Failed to register storage device: {s}\n", .{@errorName(err)});
    };
}

pub fn readSector(sector: u64, buf: *[512]u8) !void {
    if (!initialized) return error.NotInitialized;
    try performRequest(VIRTIO_BLK_T_IN, sector, buf);
}

pub fn writeSector(sector: u64, buf: *const [512]u8) !void {
    if (!initialized) return error.NotInitialized;
    const ptr = @as([*]u8, @constCast(buf))[0..512];
    try performRequest(VIRTIO_BLK_T_OUT, sector, ptr);
}

fn performRequest(type_: u32, sector: u64, buf: []u8) !void {
    const head_idx = 0;
    const data_idx = 1;
    const status_idx = 2;

    // Setup Header
    const req = VirtIOBlockReq{
        .type = type_,
        .reserved = 0,
        .sector = sector,
    };

    @memcpy(static_req_buf[0..@sizeOf(VirtIOBlockReq)], std.mem.asBytes(&req));

    // Header Descriptor
    const req_phys = virt.virtToPhys(@intFromPtr(&static_req_buf)) orelse return error.PhysAddrFailed;
    queue_desc[head_idx].addr = req_phys;
    queue_desc[head_idx].len = @sizeOf(VirtIOBlockReq);
    queue_desc[head_idx].flags = VIRTQ_DESC_F_NEXT;
    queue_desc[head_idx].next = data_idx;

    // Data Descriptor
    const buf_phys = virt.virtToPhys(@intFromPtr(buf.ptr)) orelse return error.PhysAddrFailed;
    queue_desc[data_idx].addr = buf_phys;
    queue_desc[data_idx].len = 512;
    queue_desc[data_idx].flags = VIRTQ_DESC_F_NEXT | if (type_ == VIRTIO_BLK_T_IN) @as(u16, VIRTQ_DESC_F_WRITE) else 0;
    queue_desc[data_idx].next = status_idx;

    // Status Descriptor
    const status_phys = req_phys + @sizeOf(VirtIOBlockReq);
    static_req_buf[@sizeOf(VirtIOBlockReq)] = 111; // Init with garbage
    queue_desc[status_idx].addr = status_phys;
    queue_desc[status_idx].len = 1;
    queue_desc[status_idx].flags = VIRTQ_DESC_F_WRITE;
    queue_desc[status_idx].next = 0;

    // Put in Available Ring
    const avail_idx = queue_avail.idx % QUEUE_SIZE;
    queue_avail.ring[avail_idx] = head_idx;

    // Increment idx
    queue_avail.idx += 1;

    // Notify Device
    const notify_off = @as(*volatile u16, @ptrFromInt(base_addr + 0x20)).*;
    const notify_addr = notify_base + @as(usize, notify_off) * notify_multiplier;
    const notify_ptr = @as(*volatile u16, @ptrFromInt(notify_addr));

    // serial.print("Notifying Addr=0x{x} (Off={d})...\n", .{notify_addr, notify_off});
    notify_ptr.* = 0;
    // serial.print("Notified.\n", .{});

    // Poll for completion
    const current_used_idx = queue_used.idx;
    var timeout: usize = 0;

    while (queue_used.idx == current_used_idx) {
        x64.pause();
        timeout += 1;
        if (timeout > 10000000) { // Reduced to 10M (~0.1s)
            serial.print("TIMEOUT! Avail: {d}, Used: {d}\n", .{ queue_avail.idx, queue_used.idx });
            serial.print("Notify Dbg: Base=0x{x} Off={d} Mul={d} Addr=0x{x}\n", .{ notify_base, notify_off, notify_multiplier, notify_addr });
            return error.Timeout;
        }
    }

    // Check status
    if (static_req_buf[@sizeOf(VirtIOBlockReq)] != 0) {
        return error.DiskIOError;
    }
}

// Align buffer to page size
var static_req_buf: [512]u8 align(4096) = undefined;

fn readSectorWrapper(ctx: ?*anyopaque, sector: u64, buf: *[512]u8) storage.BlockError!void {
    _ = ctx;
    readSector(sector, buf) catch |err| {
        serial.print("[VirtIO Blk] Read Error: {s}\n", .{@errorName(err)});
        return storage.BlockError.ReadError;
    };
}

fn writeSectorWrapper(ctx: ?*anyopaque, sector: u64, buf: *const [512]u8) storage.BlockError!void {
    _ = ctx;
    writeSector(sector, buf) catch |err| {
        serial.print("[VirtIO Blk] Write Error: {s}\n", .{@errorName(err)});
        return storage.BlockError.WriteError;
    };
}
