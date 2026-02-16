const limine = @import("limine");
const std = @import("std");

const term = @import("../term/terminal.zig");
const x64 = @import("../cpu/x64.zig");
const serial = @import("../driver/serial.zig");

const assert = std.debug.assert;
const higherHalf = @import("./virt.zig").higherHalf;

// Memory constants.
pub const KILOBYTE = 1024;
pub const MEGABYTE = 1024 * KILOBYTE;
pub const GIGABYTE = 1024 * MEGABYTE;
/// x86-64 page size.
pub const PAGE_SIZE: usize = 4096;

/// Memory map request structure. Will be fullfilled by the Limine bootloader.
pub export var memory_map_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};

/// Bitmap to track physical memory usage. 1 bit per page.
/// 0 = Free, 1 = Used.
var bitmap: []u8 = undefined;
var total_pages: usize = 0;
// Optimization: start searching from here to skip used pages.
var last_free_index: usize = 0;

/// Initializes the physical memory manager.
pub fn initialize() void {
    term.step("Initializing physical memory manager (Bitmap)", .{});

    // Get the array of memory map entries from the bootloader.
    const entries = memory_map_request.response.?.entries();
    assert(entries.len > 0);

    // 1. Calculate highest usable address to determine bitmap size.
    var max_address: usize = 0;
    for (entries) |entry| {
        if (entry.kind == limine.MemoryMapEntryType.usable) {
            const end = entry.base + entry.length;
            if (end > max_address) {
                max_address = end;
            }
        }
    }

    total_pages = max_address / PAGE_SIZE;
    const bitmap_size = std.mem.alignForward(usize, total_pages, 8) / 8;

    // 2. Find a contiguous region to hold the bitmap.
    // We need 'bitmap_size' bytes.
    var bitmap_phys_base: usize = 0;
    var found_bitmap_region = false;

    for (entries) |entry| {
        if (entry.kind == limine.MemoryMapEntryType.usable) {
            if (entry.length >= bitmap_size) {
                bitmap_phys_base = entry.base;
                found_bitmap_region = true;
                break;
            }
        }
    }

    if (!found_bitmap_region) {
        @panic("Could not find memory for physical bitmap!");
    }

    // Map bitmap to higher half
    bitmap = @as([*]u8, @ptrFromInt(higherHalf(bitmap_phys_base)))[0..bitmap_size];

    // 3. Initialize Bitmap
    // Default to all USED (1) to be safe, then clear USABLE regions.
    @memset(bitmap, 0xFF);

    for (entries) |entry| {
        if (entry.kind == limine.MemoryMapEntryType.usable) {
            freeRegion(entry.base, entry.length);
        }
    }

    // 4. Mark Bitmap itself as USED
    reserveRegion(bitmap_phys_base, bitmap_size);

    // 5. Reserve page 0 (null pointer protection)
    reservePage(0);

    const available = getAvailable();
    term.stepOk("{} MB", .{available / MEGABYTE});
    serial.print("[PHYS] Initialized Bitmap. Total Memory: {} MB, Bitmap Size: {} KB\n", .{ max_address / MEGABYTE, bitmap_size / KILOBYTE });
}

/// Gets the amount of available physical memory.
pub fn getAvailable() usize {
    var free_count: usize = 0;
    for (0..total_pages) |i| {
        if (!isBitSet(i)) {
            free_count += 1;
        }
    }
    return free_count * PAGE_SIZE;
}

/// Allocates 'n' contiguous physical pages.
pub fn allocateContiguous(n: usize, align_n: usize) usize {
    // Determine limit
    const limit = total_pages;

    // Simple Next-Fit search
    var run_start: ?usize = null;
    var run_len: usize = 0;

    var i = last_free_index;

    // Align i up to align_n
    if (align_n > 1) {
        const r = i % align_n;
        if (r != 0) {
            i += (align_n - r);
        }
    }

    while (i < limit) {
        if (!isBitSet(i)) {
            // Found a free page
            if (run_start == null) {
                // Must be aligned (redundant check if we step correctly but safe)
                if (align_n > 1 and (i % align_n != 0)) {
                    run_start = null;
                    run_len = 0;
                } else {
                    run_start = i;
                }
            }

            if (run_start != null) {
                run_len += 1;
            }

            if (run_len == n) {
                // Found a run!
                const start_idx = run_start.?;
                const phys_addr = start_idx * PAGE_SIZE;

                // Mark as used
                for (start_idx..start_idx + n) |k| {
                    setBit(k);
                }

                // Update optimization hint
                if (start_idx == last_free_index) {
                    last_free_index = start_idx + n;
                }

                serial.print("[PHYS] Allocating {} pages ({d} KB) at 0x{x}\n", .{ n, (n * PAGE_SIZE) / 1024, phys_addr });

                return phys_addr;
            }
            i += 1;
        } else {
            // Found a used page, reset run
            run_start = null;
            run_len = 0;
            i += 1;

            // Alignment optimization: if we need alignment, jump to next aligned block?
            if (align_n > 1) {
                const r = i % align_n;
                if (r != 0) {
                    i += (align_n - r);
                }
            }
        }
    }

    // If we wrapped or failed (TODO: Implement wrap-around search if we want to be robust,
    // but for now simple linear from last_free is okay-ish until fragmentation hits.
    // Actually, let's just reset last_free if we hit end?)
    if (last_free_index > 0) {
        // Try searching from 0 one more time
        last_free_index = 0;
        return allocateContiguous(n, align_n);
    }

    @panic("Out of physical memory (contiguous)");
}

/// Frees a single page.
pub fn free(address: usize) void {
    freeContiguous(address, 1);
}

/// Frees 'n' contiguous pages.
pub fn freeContiguous(address: usize, n: usize) void {
    const start_page = address / PAGE_SIZE;
    for (start_page..start_page + n) |i| {
        clearBit(i);
    }

    // Update hint if we freed something earlier than current ptr
    if (start_page < last_free_index) {
        last_free_index = start_page;
    }
}

// --- Internal Bitmap Helpers ---

fn freeRegion(base: usize, length: usize) void {
    const start_page = pageAlignUp(base) / PAGE_SIZE;
    const end_page = pageAlignDown(base + length) / PAGE_SIZE;

    if (end_page > start_page) {
        for (start_page..end_page) |i| {
            clearBit(i);
        }
    }
}

fn reserveRegion(base: usize, length: usize) void {
    const start_page = base / PAGE_SIZE; // Round down to capture partial start? No, simplistic.
    const end_page = std.mem.alignForward(usize, base + length, PAGE_SIZE) / PAGE_SIZE;

    for (start_page..end_page) |i| {
        setBit(i);
    }
}

fn reservePage(page_idx: usize) void {
    setBit(page_idx);
}

inline fn setBit(idx: usize) void {
    const byte_idx = idx / 8;
    const bit_idx = @as(u3, @truncate(idx % 8));
    if (byte_idx < bitmap.len) {
        bitmap[byte_idx] |= (@as(u8, 1) << bit_idx);
    }
}

inline fn clearBit(idx: usize) void {
    const byte_idx = idx / 8;
    const bit_idx = @as(u3, @truncate(idx % 8));
    if (byte_idx < bitmap.len) {
        bitmap[byte_idx] &= ~(@as(u8, 1) << bit_idx);
    }
}

inline fn isBitSet(idx: usize) bool {
    const byte_idx = idx / 8;
    const bit_idx = @as(u3, @truncate(idx % 8));
    if (byte_idx < bitmap.len) {
        return (bitmap[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
    }
    return true; // Out of bounds is "used"
}

/// Aligns an address to the nearest page down.
pub inline fn pageAlignDown(address: usize) usize {
    return std.mem.alignBackward(usize, address, PAGE_SIZE);
}

/// Aligns an address to the nearest page up.
pub inline fn pageAlignUp(address: usize) usize {
    return std.mem.alignForward(usize, address, PAGE_SIZE);
}
