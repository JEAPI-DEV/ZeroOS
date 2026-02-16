const std = @import("std");
const heap = @import("../memory/heap.zig");
const serial = @import("../driver/serial.zig");

// Wrap the kernel allocator
const allocator = heap.allocator;

pub export fn malloc(size: usize) ?*anyopaque {
    const ptr = allocator.alloc(u8, size) catch return null;
    serial.print("[MALLOC] Size: {} -> 0x{x}\n", .{ size, @intFromPtr(ptr.ptr) });
    return ptr.ptr;
}

pub export fn calloc(num: usize, size: usize) ?*anyopaque {
    const total = num * size;
    const ptr = allocator.alloc(u8, total) catch return null;
    @memset(ptr, 0);
    serial.print("[CALLOC] Size: {} -> 0x{x}\n", .{ total, @intFromPtr(ptr.ptr) });
    return ptr.ptr;
}

pub export fn free(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        serial.print("[FREE] 0x{x}\n", .{@intFromPtr(p)});
        heap.c_free(p);
    }
}
