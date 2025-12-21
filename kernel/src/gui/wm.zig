//! Window Manager for Zen OS.

const std = @import("std");
const gfx = @import("gfx.zig");

pub const Window = struct {
    title: []const u8,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    canvas: gfx.Canvas,
    allocator: std.mem.Allocator,
    dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator, title: []const u8, x: usize, y: usize, w: usize, h: usize) !*Window {
        const self = try allocator.create(Window);
        const buffer = try allocator.alloc(gfx.Color, w * h);

        self.* = .{
            .title = try allocator.dupe(u8, title),
            .x = x,
            .y = y,
            .width = w,
            .height = h,
            .canvas = .{
                .width = w,
                .height = h,
                .buffer = buffer,
            },
            .allocator = allocator,
        };

        // Clear window background
        self.canvas.fillRect(0, 0, w, h, 0xFFFFFF); // White background
        return self;
    }

    pub fn drawDecorations(self: *Window, screen: *gfx.Canvas) void {
        // Title bar
        const title_bar_height = 20;
        screen.fillRect(self.x, self.y - title_bar_height, self.width, title_bar_height, 0x0000FF); // Blue title bar
        screen.drawString(self.title, self.x + 5, self.y - title_bar_height + 2, 0xFFFFFF); // White text

        // Border
        screen.drawRect(self.x - 1, self.y - title_bar_height - 1, self.width + 2, self.height + title_bar_height + 2, 0x000000);
    }
};

pub const WindowManager = struct {
    windows: std.ArrayListUnmanaged(*Window),
    allocator: std.mem.Allocator,
    mouse_x: usize = 0,
    mouse_y: usize = 0,

    pub fn init(allocator: std.mem.Allocator) WindowManager {
        return .{
            .windows = .{},
            .allocator = allocator,
        };
    }

    pub fn createWindow(self: *WindowManager, title: []const u8, x: usize, y: usize, w: usize, h: usize) !*Window {
        const win = try Window.init(self.allocator, title, x, y, w, h);
        try self.windows.append(self.allocator, win);
        return win;
    }

    pub fn composite(self: *WindowManager, screen: *gfx.Canvas) void {
        // Draw background
        screen.fillRect(0, 0, screen.width, screen.height, 0x008080); // Teal background

        for (self.windows.items) |win| {
            // Draw decorations (title bar, etc.)
            win.drawDecorations(screen);

            // Draw window content
            var dy: usize = 0;
            while (dy < win.height) : (dy += 1) {
                if (win.y + dy >= screen.height) break;
                var dx: usize = 0;
                while (dx < win.width) : (dx += 1) {
                    if (win.x + dx >= screen.width) break;
                    screen.putPixel(win.x + dx, win.y + dy, win.canvas.buffer[dy * win.width + dx]);
                }
            }
        }

        // Draw mouse cursor
        self.drawMouse(screen);
    }

    fn drawMouse(self: *WindowManager, screen: *gfx.Canvas) void {
        const mx = self.mouse_x;
        const my = self.mouse_y;

        // Simple 8x8 arrow cursor
        screen.fillRect(mx, my, 2, 8, 0x000000); // Vertical
        screen.fillRect(mx, my, 8, 2, 0x000000); // Horizontal
        screen.putPixel(mx + 1, my + 1, 0xFFFFFF);
    }

    pub fn updateMouse(self: *WindowManager, dx: i32, dy: i32, screen_w: usize, screen_h: usize) void {
        var new_x = @as(i32, @intCast(self.mouse_x)) + dx;
        var new_y = @as(i32, @intCast(self.mouse_y)) - dy; // Mouse Y is usually inverted in PS/2

        if (new_x < 0) new_x = 0;
        if (new_y < 0) new_y = 0;
        if (new_x >= @as(i32, @intCast(screen_w))) new_x = @as(i32, @intCast(screen_w)) - 1;
        if (new_y >= @as(i32, @intCast(screen_h))) new_y = @as(i32, @intCast(screen_h)) - 1;

        self.mouse_x = @intCast(new_x);
        self.mouse_y = @intCast(new_y);
    }
};

pub var global_wm: WindowManager = undefined;

pub fn initialize(allocator: std.mem.Allocator) void {
    global_wm = WindowManager.init(allocator);
}
