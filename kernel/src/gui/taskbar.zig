//! Taskbar for Zen OS GUI.

const std = @import("std");
const gfx = @import("gfx.zig");
const wm = @import("wm.zig");

pub const TASKBAR_HEIGHT = 30;

pub const Taskbar = struct {
    allocator: std.mem.Allocator,
    frame_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Taskbar {
        return .{
            .allocator = allocator,
        };
    }

    pub fn draw(self: *Taskbar, screen: *gfx.Canvas) void {
        const y = screen.height - TASKBAR_HEIGHT;
        self.frame_count += 1;

        // Background
        screen.fillRect(0, y, screen.width, TASKBAR_HEIGHT, 0x333333);
        screen.drawRect(0, y, screen.width, 1, 0x000000);

        // "Start" button area
        screen.fillRect(5, y + 5, 60, TASKBAR_HEIGHT - 10, 0x555555);
        screen.drawString("Zen", 15, y + 7, 0xFFFFFF);

        // Clock area (simulated)
        const total_seconds = self.frame_count / 60; // Assuming ~60fps
        const minutes = (total_seconds / 60) % 60;
        const hours = (total_seconds / 3600) % 24;

        var clock_buf: [6]u8 = undefined;
        const clock_str = std.fmt.bufPrint(&clock_buf, "{d:0>2}:{d:0>2}", .{ hours, minutes }) catch "00:00";
        screen.drawString(clock_str, screen.width - 50, y + 7, 0xFFFFFF);

        // Window list
        var x: usize = 70;
        for (wm.global_wm.windows.items) |win| {
            const btn_w = 100;
            const is_active = (wm.global_wm.windows.items[wm.global_wm.windows.items.len - 1] == win);

            const bg_color: gfx.Color = if (is_active) 0x777777 else 0x555555;
            screen.fillRect(x, y + 5, btn_w, TASKBAR_HEIGHT - 10, bg_color);
            screen.drawRect(x, y + 5, btn_w, TASKBAR_HEIGHT - 10, 0x000000);

            // Truncate title if needed
            var title_buf: [10]u8 = undefined;
            const title = if (win.title.len > 8) blk: {
                @memcpy(title_buf[0..7], win.title[0..7]);
                @memcpy(title_buf[7..10], "...");
                break :blk title_buf[0..10];
            } else win.title;

            screen.drawString(title, x + 5, y + 7, 0xFFFFFF);
            x += btn_w + 5;
            if (x + btn_w > screen.width - 60) break;
        }
    }

    pub fn handleMouse(self: *Taskbar, mx: usize, my: usize, pressed: bool, screen_h: usize) bool {
        const y = screen_h - TASKBAR_HEIGHT;
        if (my < y) return false;
        if (!pressed) return false; // Don't consume mouse up if not on a button

        if (mx >= 5 and mx < 65) {
            // Start button clicked
            return true;
        }

        var x: usize = 70;
        for (wm.global_wm.windows.items) |win| {
            const btn_w = 100;
            if (mx >= x and mx < x + btn_w) {
                // Switch to this window
                // Find index
                for (wm.global_wm.windows.items, 0..) |w, i| {
                    if (w == win) {
                        const moved_win = wm.global_wm.windows.orderedRemove(i);
                        wm.global_wm.windows.append(self.allocator, moved_win) catch {};
                        break;
                    }
                }
                return true;
            }
            x += btn_w + 5;
        }

        return false; // Didn't hit anything in the taskbar
    }
};

pub var global_taskbar: Taskbar = undefined;

pub fn initialize(allocator: std.mem.Allocator) void {
    global_taskbar = Taskbar.init(allocator);
}
