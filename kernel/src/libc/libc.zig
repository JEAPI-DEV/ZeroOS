//! Minimal LibC Implementation.
//! Provides standard C library functions by wrapping kernel subsystems.

const std = @import("std");
const serial = @import("../driver/serial.zig");
const heap = @import("../memory/heap.zig");
const process = @import("../proc/process.zig");
const scheduler = @import("../proc/scheduler.zig");

// --- stdio.h ---

/// Writes a character to the standard output (serial console).
pub export fn putchar(c: c_int) c_int {
    serial.print("{c}", .{@as(u8, @truncate(@as(u32, @bitCast(c))))});
    return c;
}

/// Helper for printf to use as a writer.
const SerialWriter = struct {
    pub const Error = error{};
    pub fn write(self: SerialWriter, bytes: []const u8) Error!usize {
        _ = self;
        for (bytes) |b| {
            serial.print("{c}", .{b});
        }
        return bytes.len;
    }
};

/// Prints formatted output to the standard output.
pub fn printf(fmt: [*:0]const u8, args: anytype) void {
    serial.print("{s}", .{std.mem.span(fmt)});
    _ = args;
}

// --- stdlib.h ---

/// Allocates size bytes of uninitialized storage.
pub export fn malloc(size: usize) ?*anyopaque {
    const ptr = heap.allocator.alloc(u8, size) catch return null;
    return ptr.ptr;
}

/// Deallocates the space previously allocated by malloc.
pub export fn free(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        heap.c_free(@ptrCast(@alignCast(p)));
    }
}

// --- string.h ---

/// Set `n` bytes of `s` to `c`.
pub export fn memset(s: ?*anyopaque, c: c_int, n: usize) ?*anyopaque {
    if (s) |ptr| {
        asm volatile ("rep stosb"
            :
            : [dest] "{rdi}" (ptr),
              [val] "{al}" (@as(u8, @truncate(@as(u32, @bitCast(c))))),
              [count] "{rcx}" (n),
            : .{ .memory = true, .rdi = true, .rcx = true }
        );
    }
    return s;
}

/// Copy `n` bytes from `src` to `dest`.
pub export fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque {
    if (dest != null and src != null) {
        asm volatile ("rep movsb"
            :
            : [dest] "{rdi}" (dest),
              [src] "{rsi}" (src),
              [count] "{rcx}" (n),
            : .{ .memory = true, .rdi = true, .rsi = true, .rcx = true }
        );
    }
    return dest;
}

/// Returns the length of the string `s`.
pub export fn strlen(s: ?[*:0]const u8) usize {
    if (s) |ptr| return std.mem.len(ptr);
    return 0;
}

// --- pthread.h ---

pub const pthread_t = usize;
pub const pthread_attr_t = anyopaque;

/// Creates a new thread.
pub export fn pthread_create(thread: *pthread_t, attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int {
    _ = attr;
    const entry: *const fn (?*anyopaque) void = @ptrCast(start_routine);
    const current_thread = scheduler.instance.current_thread orelse return -1;
    const proc = current_thread.process;
    const new_thread_ptr = proc.createThread(entry, arg, 32768, heap.allocator) catch return -1;
    thread.* = new_thread_ptr.id;
    scheduler.instance.enqueue(new_thread_ptr);
    return 0;
}

/// Waits for the specified thread to terminate.
pub export fn pthread_join(thread: pthread_t, retval: ?*?*anyopaque) c_int {
    _ = retval;
    const current_thread = scheduler.instance.current_thread orelse return -1;
    const proc = current_thread.process;
    var target_thread: ?*process.Thread = null;
    for (proc.threads[0..proc.thread_count]) |t| {
        if (t.id == thread) {
            target_thread = t;
            break;
        }
    }
    if (target_thread) |target| {
        while (target.state != .TERMINATED) {
            scheduler.instance.yield();
        }
        return 0;
    }
    return -1;
}
