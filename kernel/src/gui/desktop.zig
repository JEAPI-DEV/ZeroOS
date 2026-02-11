//! Desktop manager for Zen OS.

const std = @import("std");
const gfx = @import("gfx.zig");
const wm = @import("wm.zig");
const heap = @import("../memory/heap.zig");
const input = @import("../driver/input.zig");
const serial = @import("../driver/serial.zig");
const scheduler = @import("../proc/scheduler.zig");
const taskbar = @import("taskbar.zig");
const widget = @import("widget.zig");

// Desktop Apps
const desktop_apps = struct {
    pub const terminal = @import("desktop_apps/terminal.zig").terminal_app;
    pub const calculator = @import("desktop_apps/calculator.zig").calculator_app;
};

const DesktopApp = @import("desktop_apps/desktop_app.zig").DesktopApp;

const apps = [_]DesktopApp{
    desktop_apps.terminal,
    desktop_apps.calculator,
};

pub fn start() !void {
    serial.print("[GUI] Initializing GFX...\n", .{});
    try gfx.initialize(heap.allocator);
    serial.print("[GUI] Initializing WM...\n", .{});
    wm.initialize(heap.allocator);
    taskbar.initialize(heap.allocator);

    // Create applications
    for (apps, 0..) |app, i| {
        const x: usize = 50 + @as(usize, @intCast(i)) * 100;
        const y: usize = 50 + @as(usize, @intCast(i)) * 50;
        // Default sizes, apps can adjust or we can add size to DesktopApp
        const win = try wm.global_wm.createWindow(app.name, x, y, 400, 300);
        try app.setup(win);
    }

    // Main GUI Loop
    while (true) {
        // Poll mouse
        var dx: i32 = 0;
        var dy: i32 = 0;
        var buttons: u8 = 0;
        input.getMouseDelta(&dx, &dy, &buttons);

        if (dx != 0 or dy != 0 or buttons != 0) {
            const mouse_handled = taskbar.global_taskbar.handleMouse(wm.global_wm.mouse_x, wm.global_wm.mouse_y, (buttons & 1) != 0, gfx.screen_canvas.height);
            if (!mouse_handled) {
                wm.global_wm.updateMouse(dx, dy, buttons, gfx.screen_canvas.width, gfx.screen_canvas.height);
            } else {
                // Still update mouse position for movement even if click was handled by taskbar
                wm.global_wm.updateMouse(dx, dy, buttons & ~@as(u8, 1), gfx.screen_canvas.width, gfx.screen_canvas.height);
            }
        }

        // Invalidate taskbar area every frame to ensure clock updates are drawn
        // Optimization: Taskbar could track its own dirty state, but this is small enough.
        wm.global_wm.invalidateRect(0, gfx.screen_canvas.height - taskbar.TASKBAR_HEIGHT, gfx.screen_canvas.width, taskbar.TASKBAR_HEIGHT);

        const dirty_rect = wm.global_wm.composite(&gfx.screen_canvas);
        taskbar.global_taskbar.draw(&gfx.screen_canvas);
        wm.global_wm.drawMouse(&gfx.screen_canvas);

        if (dirty_rect) |r| {
            gfx.swapRect(r.x, r.y, r.w, r.h);
        }
        const key = input.getGuiKey();
        if (key != 0) {
            if (wm.global_wm.windows.items.len > 0) {
                const active_win = wm.global_wm.windows.items[wm.global_wm.windows.items.len - 1];
                for (active_win.widgets.items) |*w| {
                    if (w.handleKey(key)) {
                        wm.global_wm.invalidateRect(active_win.x + w.x, active_win.y + w.y, w.width, w.height);
                        break;
                    }
                }
            }
        }

        // Yield to other threads
        scheduler.instance.yield();
    }
}
