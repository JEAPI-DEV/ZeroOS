//! Desktop manager for Zen OS.

const std = @import("std");
const gfx = @import("gfx.zig");
const wm = @import("wm.zig");
const heap = @import("../memory/heap.zig");
const input = @import("../driver/input.zig");
const serial = @import("../driver/serial.zig");
const scheduler = @import("../proc/scheduler.zig");

pub fn start() !void {
    serial.print("[GUI] Initializing GFX...\n", .{});
    try gfx.initialize(heap.allocator);
    serial.print("[GUI] Initializing WM...\n", .{});
    wm.initialize(heap.allocator);

    // Create some example windows
    _ = try wm.global_wm.createWindow("Terminal", 50, 50, 400, 300);
    _ = try wm.global_wm.createWindow("Calculator", 500, 100, 200, 250);

    // Main GUI Loop
    var frame_count: usize = 0;
    while (true) {
        frame_count += 1;
        if (frame_count % 100 == 0) {
            serial.print("[GUI] Frame {}\n", .{frame_count});
        }
        // Poll mouse
        var dx: i32 = 0;
        var dy: i32 = 0;
        var buttons: u8 = 0;
        ps2.getMouseDelta(&dx, &dy, &buttons);

        if (dx != 0 or dy != 0) {
            serial.print("[GUI] Mouse move: dx={}, dy={}\n", .{ dx, dy });
            wm.global_wm.updateMouse(dx, dy, gfx.screen_canvas.width, gfx.screen_canvas.height);
        }

        wm.global_wm.composite(&gfx.screen_canvas);
        gfx.swap();

        // Yield to other threads
        scheduler.global_scheduler.yield();
    }
}
