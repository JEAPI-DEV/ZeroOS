//! VirtIO Driver Support.
//! Handles discovery and initialization of VirtIO devices.

const std = @import("std");
const serial = @import("serial.zig");
const pci = @import("pci.zig");
const virt = @import("../memory/virt.zig");

const x64 = @import("../cpu/x64.zig");

// Legacy IO Register Offsets
const REG_HOST_FEATURES = 0x00;
const REG_GUEST_FEATURES = 0x04;
const REG_QUEUE_PFN = 0x08;
const REG_QUEUE_SIZE = 0x0C;
const REG_QUEUE_SEL = 0x0E;
const REG_QUEUE_NOTIFY = 0x10;
const REG_STATUS = 0x12;
const REG_ISR = 0x13;

const STATUS_ACKNOWLEDGE = 1;
const STATUS_DRIVER = 2;
const STATUS_FAILED = 128;
const STATUS_FEATURES_OK = 8;
const STATUS_DRIVER_OK = 4;

// VirtIO Capability Types
const VIRTIO_PCI_CAP_COMMON_CFG = 1;
const VIRTIO_PCI_CAP_NOTIFY_CFG = 2;
const VIRTIO_PCI_CAP_ISR_CFG = 3;
const VIRTIO_PCI_CAP_DEVICE_CFG = 4;
const VIRTIO_PCI_CAP_PCI_CFG = 5;

pub const VENDOR_ID = 0x1AF4;

/// VirtIO Device IDs
pub const DeviceId = enum(u16) {
    Reserved = 0,
    Network = 1,
    Block = 2,
    Console = 3,
    Entropy = 4,
    Balloon = 5,
    IOMemory = 6,
    RProc = 7,
    SCSI = 8,
    p9 = 9,
    WLAN = 10,
    RProcSerial = 11,
    CAIF = 12,
    MemoryBalloon = 13,
    GPU = 16,
    Timer = 17,
    Input = 18,
    Socket = 19,
    Crypto = 20,
    SignalDist = 21,
    Pstore = 22,
    IOMMU = 23,
    Memo = 24,
    Sound = 25,
    FS = 26,
    PMEM = 27,
    RPMB = 28,

    // Legacy IDs (what QEMU uses by default for -device virtio-gpu-pci without disable-legacy=on)
    // Legacy IDs are 0x1000 + Device ID
    LegacyGPU = 0x1050,
    _,
};

pub fn init(bus: u8, slot: u8, func: u8, device_id: u16) void {
    serial.print("[VirtIO] Found device 0x{x} at {}:{}:{}\n", .{ device_id, bus, slot, func });

    // Iterate capabilities to find Common Config
    var cap_offset: u8 = 0;
    var common_cfg_addr: ?usize = null;

    // Check Status Register for Capabilities List bit
    const status_reg = pci.pciConfigReadUint16(bus, slot, func, 0x06);
    if (status_reg & 0x10 == 0) {
        return;
    }

    while (true) {
        const next_offset = pci.findCapability(bus, slot, func, 0x09, cap_offset); // Vendor Specific
        if (next_offset) |offset| {
            cap_offset = offset;

            const cfg_type = pci.pciConfigReadByte(bus, slot, func, offset + 3);
            const bar_idx = pci.pciConfigReadByte(bus, slot, func, offset + 4);
            const off_l = pci.pciConfigReadWord(bus, slot, func, offset + 8);

            if (cfg_type == VIRTIO_PCI_CAP_COMMON_CFG) {
                const bar_val = pci.getBar(bus, slot, func, bar_idx);
                const bar_addr = bar_val & 0xFFFFFFF0; // Mask flags
                const phys_addr = bar_addr + off_l;
                const virt_addr = virt.higherHalf(phys_addr);

                // Ensure page is mapped (uncached for MMIO)
                virt.mapPage(virt_addr, phys_addr, virt.WRITABLE | virt.PWT | virt.PCD);

                common_cfg_addr = virt_addr;
                break;
            }
        } else {
            break;
        }
    }

    if (common_cfg_addr) |addr| {
        const id = @as(DeviceId, @enumFromInt(device_id));
        if (id == .GPU or id == .LegacyGPU) {
            initGpu(addr);
        }
    } else {
        serial.print("[VirtIO] Could not find Common Configuration structure.\n", .{});
    }
}

fn initGpu(common_cfg_addr: usize) void {
    const status_ptr = @as(*volatile u8, @ptrFromInt(common_cfg_addr + 20)); // device_status is at offset 20 (0x14)

    serial.print("[VirtIO] Initializing GPU driver (Modern MMIO)...\n", .{});

    // 1. Reset
    status_ptr.* = 0;
    while (status_ptr.* != 0) {} // Wait for reset ?? Spec doesn't strictly say wait but good practice

    // 2. Set ACKNOWLEDGE
    status_ptr.* |= STATUS_ACKNOWLEDGE;

    // 3. Set DRIVER
    status_ptr.* |= STATUS_DRIVER;

    serial.print("[VirtIO] Device reset and acknowledged.\n", .{});
}
