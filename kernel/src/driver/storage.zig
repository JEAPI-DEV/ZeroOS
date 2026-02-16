//! Storage Abstraction Layer

const std = @import("std");

/// Error set for block device operations.
pub const BlockError = error{
    ReadError,
    WriteError,
    NotInitialized,
    DeviceError,
    Unsupported,
};

/// Interface for a Block Device.
pub const BlockDevice = struct {
    /// Pointer to the underlying driver/device context.
    context: ?*anyopaque,

    /// Reads a 512-byte sector.
    readSector: *const fn (ctx: ?*anyopaque, sector: u64, buf: *[512]u8) BlockError!void,

    /// Writes a 512-byte sector.
    writeSector: *const fn (ctx: ?*anyopaque, sector: u64, buf: *const [512]u8) BlockError!void,
};

/// Global list of registered block devices.
pub var devices: std.ArrayListUnmanaged(BlockDevice) = .{};
pub var allocator: std.mem.Allocator = undefined;

/// Initializes the storage subsystem.
pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
}

/// Registers a new block device.
pub fn register(device: BlockDevice) !void {
    try devices.append(allocator, device);
}

/// Returns the primary block device (first registered).
pub fn getPrimary() ?BlockDevice {
    if (devices.items.len > 0) {
        return devices.items[0];
    }
    return null;
}
