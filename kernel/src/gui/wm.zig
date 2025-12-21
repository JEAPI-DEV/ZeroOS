//! Window Manager for Zen OS.

const std = @import("std");
const gfx = @import("gfx.zig");
const widget = @import("widget.zig");

pub const Window = struct {
    title: []const u8,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    canvas: gfx.Canvas,
    allocator: std.mem.Allocator,
    dirty: bool = true,
    widgets: std.ArrayListUnmanaged(widget.Widget) = .{},

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

    pub fn addWidget(self: *Window, w: widget.Widget) !void {
        try self.widgets.append(self.allocator, w);
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
    last_mouse_x: usize = 0,
    last_mouse_y: usize = 0,
    dragging_window: ?*Window = null,
    last_buttons: u8 = 0,
    mouse_bg: [64]gfx.Color = undefined, // 8x8 mouse background
    dirty: bool = true,

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
        if (self.dirty) {
            // Draw background
            screen.fillRect(0, 0, screen.width, screen.height, 0x008080); // Teal background

            for (self.windows.items) |win| {
                // Draw decorations (title bar, etc.)
                win.drawDecorations(screen);

                // Draw window content using row-based copies for performance
                const start_y = win.y;
                const start_x = win.x;

                var dy: usize = 0;
                while (dy < win.height) : (dy += 1) {
                    const screen_y = start_y + dy;
                    if (screen_y >= screen.height) break;

                    const copy_width = if (start_x + win.width > screen.width)
                        screen.width - start_x
                    else
                        win.width;

                    if (copy_width == 0) continue;

                    const screen_offset = screen_y * screen.width + start_x;
                    const win_offset = dy * win.width;

                    // Use @memcpy for faster row copies
                    @memcpy(@as([*]gfx.Color, @ptrCast(@volatileCast(screen.buffer.ptr))) + screen_offset, win.canvas.buffer[win_offset .. win_offset + copy_width]);
                }

                // Draw widgets
                for (win.widgets.items) |*w| {
                    // Adjust widget coordinates to screen coordinates
                    const saved_x = w.x;
                    const saved_y = w.y;
                    w.x += win.x;
                    w.y += win.y;
                    w.draw(screen);
                    w.x = saved_x;
                    w.y = saved_y;
                }
            }
            self.dirty = false;

            // Save mouse background after full composite
            self.saveMouseBg(screen);
        } else {
            // Restore mouse background before moving
            self.restoreMouseBg(screen);
            self.saveMouseBg(screen);
        }

        self.last_mouse_x = self.mouse_x;
        self.last_mouse_y = self.mouse_y;
    }

    fn saveMouseBg(self: *WindowManager, screen: *gfx.Canvas) void {
        const mx = self.mouse_x;
        const my = self.mouse_y;
        for (0..8) |dy| {
            for (0..8) |dx| {
                if (mx + dx < screen.width and my + dy < screen.height) {
                    self.mouse_bg[dy * 8 + dx] = screen.buffer[(my + dy) * screen.width + (mx + dx)];
                }
            }
        }
    }

    fn restoreMouseBg(self: *WindowManager, screen: *gfx.Canvas) void {
        const mx = self.last_mouse_x;
        const my = self.last_mouse_y;
        for (0..8) |dy| {
            for (0..8) |dx| {
                if (mx + dx < screen.width and my + dy < screen.height) {
                    screen.buffer[(my + dy) * screen.width + (mx + dx)] = self.mouse_bg[dy * 8 + dx];
                }
            }
        }
    }

    pub fn drawMouse(self: *WindowManager, screen: *gfx.Canvas) void {
        const mx = self.mouse_x;
        const my = self.mouse_y;

        // Simple 8x8 arrow cursor
        screen.fillRect(mx, my, 2, 8, 0x000000); // Vertical
        screen.fillRect(mx, my, 8, 2, 0x000000); // Horizontal
        screen.putPixel(mx + 1, my + 1, 0xFFFFFF);
    }

    pub fn updateMouse(self: *WindowManager, dx: i32, dy: i32, buttons: u8, screen_w: usize, screen_h: usize) void {
        var new_x = @as(i32, @intCast(self.mouse_x)) + dx;
        var new_y = @as(i32, @intCast(self.mouse_y)) - dy; // Mouse Y is usually inverted in PS/2

        if (new_x < 0) new_x = 0;
        if (new_y < 0) new_y = 0;
        if (new_x >= @as(i32, @intCast(screen_w))) new_x = @as(i32, @intCast(screen_w)) - 1;
        if (new_y >= @as(i32, @intCast(screen_h))) new_y = @as(i32, @intCast(screen_h)) - 1;

        const old_x = self.mouse_x;
        const old_y = self.mouse_y;
        self.mouse_x = @intCast(new_x);
        self.mouse_y = @intCast(new_y);

        const left_pressed = (buttons & 1) != 0;
        const left_was_pressed = (self.last_buttons & 1) != 0;

        if (left_pressed and !left_was_pressed) {
            // Mouse down - check for window hit (title bar or content)
            self.dragging_window = null;
            // Iterate backwards to find the top-most window
            var i: usize = self.windows.items.len;
            while (i > 0) {
                i -= 1;
                const win = self.windows.items[i];
                const title_bar_height = 20;

                // Check title bar for dragging
                if (self.mouse_x >= win.x and self.mouse_x < win.x + win.width and
                    self.mouse_y >= win.y - title_bar_height and self.mouse_y < win.y)
                {
                    self.dragging_window = win;
                    self.dirty = true;
                    // Move to front
                    const moved_win = self.windows.orderedRemove(i);
                    self.windows.append(self.allocator, moved_win) catch {};
                    break;
                }

                // Check window content for widgets
                if (self.mouse_x >= win.x and self.mouse_x < win.x + win.width and
                    self.mouse_y >= win.y and self.mouse_y < win.y + win.height)
                {
                    // Hit window content, check widgets
                    for (win.widgets.items) |*w| {
                        if (w.handleMouse(self.mouse_x - win.x, self.mouse_y - win.y, true)) {
                            // Widget handled the event
                            self.dirty = true;
                            break;
                        }
                    }
                    // Move to front even if no widget hit
                    const moved_win = self.windows.orderedRemove(i);
                    self.windows.append(self.allocator, moved_win) catch {};
                    self.dirty = true;
                    break;
                }
            }
        } else if (!left_pressed and left_was_pressed) {
            // Mouse up - check widgets
            self.dragging_window = null;
            var i: usize = self.windows.items.len;
            while (i > 0) {
                i -= 1;
                const win = self.windows.items[i];
                if (self.mouse_x >= win.x and self.mouse_x < win.x + win.width and
                    self.mouse_y >= win.y and self.mouse_y < win.y + win.height)
                {
                    for (win.widgets.items) |*w| {
                        if (w.handleMouse(self.mouse_x - win.x, self.mouse_y - win.y, false)) {
                            self.dirty = true;
                        }
                    }
                    break;
                }
            }
        }

        if (self.dragging_window) |win| {
            const mdx = @as(i32, @intCast(self.mouse_x)) - @as(i32, @intCast(old_x));
            const mdy = @as(i32, @intCast(self.mouse_y)) - @as(i32, @intCast(old_y));

            if (mdx != 0 or mdy != 0) {
                var new_win_x = @as(i32, @intCast(win.x)) + mdx;
                var new_win_y = @as(i32, @intCast(win.y)) + mdy;

                if (new_win_x < 0) new_win_x = 0;
                if (new_win_y < 20) new_win_y = 20; // Keep title bar on screen

                win.x = @intCast(new_win_x);
                win.y = @intCast(new_win_y);
                self.dirty = true;
            }
        }

        self.last_buttons = buttons;
    }
};

pub var global_wm: WindowManager = undefined;

pub fn initialize(allocator: std.mem.Allocator) void {
    global_wm = WindowManager.init(allocator);
}
