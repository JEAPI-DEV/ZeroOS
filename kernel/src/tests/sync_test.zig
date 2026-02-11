//! Synchronization primitives test.

const std = @import("std");
const mutex = @import("../sync/mutex.zig");
const condition = @import("../sync/condition.zig");
const serial = @import("../driver/serial.zig");
const scheduler = @import("../proc/scheduler.zig");
const heap = @import("../memory/heap.zig");
const process = @import("../proc/process.zig");

var test_mutex = mutex.Mutex{};
var test_cond = condition.Condition{};
var ready: bool = false;
var data: usize = 0;

pub fn run() void {
    serial.print("[TEST] Starting Sync Test...\n", .{});

    const current_proc = scheduler.instance.current_thread.?.process;

    // Create a consumer thread.
    const consumer = current_proc.createThread(consumerThread, null, 16384, heap.allocator) catch unreachable;
    scheduler.instance.enqueue(consumer);

    // Create a producer thread.
    const producer = current_proc.createThread(producerThread, null, 16384, heap.allocator) catch unreachable;
    scheduler.instance.enqueue(producer);
}

fn consumerThread(_: ?*anyopaque) void {
    serial.print("[TEST] Consumer: Starting\n", .{});
    test_mutex.lock();
    serial.print("[TEST] Consumer: Acquired lock\n", .{});

    while (!ready) {
        serial.print("[TEST] Consumer: Waiting...\n", .{});
        test_cond.wait(&test_mutex);
        serial.print("[TEST] Consumer: Woke up!\n", .{});
    }

    serial.print("[TEST] Consumer: Data = {}\n", .{data});
    test_mutex.unlock();
    serial.print("[TEST] Consumer: Done\n", .{});

    // Loop forever to not crash for now (thread exit not fully robust yet in this context?)
    // threadExit() calls hang().
}

fn producerThread(_: ?*anyopaque) void {
    serial.print("[TEST] Producer: Starting\n", .{});

    // Simulate work
    var i: usize = 0;
    while (i < 1000000) : (i += 1) {
        asm volatile ("nop");
    }

    test_mutex.lock();
    serial.print("[TEST] Producer: Acquired lock\n", .{});

    data = 42;
    ready = true;

    serial.print("[TEST] Producer: Signaling...\n", .{});
    test_cond.notify();

    test_mutex.unlock();
    serial.print("[TEST] Producer: Done\n", .{});
}
