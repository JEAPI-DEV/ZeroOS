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

    pub fn getOuterRect(self: *Window) gfx.Rect {
        const title_bar_height = 20;

        // Calculate border dimensions based on drawDecorations logic
        const border_x = if (self.x > 0) self.x - 1 else 0;
        const border_y = if (self.y > title_bar_height) self.y - title_bar_height - 1 else 0;

        const border_w = self.width + @as(usize, if (self.x > 0) 2 else 1);
        const border_h = self.height + title_bar_height + @as(usize, if (self.y > title_bar_height) 2 else 1);

        return gfx.Rect{ .x = border_x, .y = border_y, .w = border_w, .h = border_h };
    }

    pub fn drawDecorations(self: *Window, screen: *gfx.Canvas) void {
        // Title bar
        const title_bar_height = 20;
        screen.fillRect(self.x, self.y - title_bar_height, self.width, title_bar_height, 0x0000FF); // Blue title bar
        screen.drawString(self.title, self.x + 5, self.y - title_bar_height + 2, 0xFFFFFF); // White text

        // Border
        const outer = self.getOuterRect();
        screen.drawRect(outer.x, outer.y, outer.w, outer.h, 0x000000);
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
    dirty_rect: ?gfx.Rect = null,
    // mouse_bg removed

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

    pub fn invalidateRect(self: *WindowManager, x: usize, y: usize, w: usize, h: usize) void {
        const new_rect = gfx.Rect{ .x = x, .y = y, .w = w, .h = h };
        if (self.dirty_rect) |current| {
            // Unite
            const min_x = @min(current.x, new_rect.x);
            const min_y = @min(current.y, new_rect.y);
            const max_x = @max(current.x + current.w, new_rect.x + new_rect.w);
            const max_y = @max(current.y + current.h, new_rect.y + new_rect.h);
            self.dirty_rect = gfx.Rect{
                .x = min_x,
                .y = min_y,
                .w = max_x - min_x,
                .h = max_y - min_y,
            };
        } else {
            self.dirty_rect = new_rect;
        }
    }

    pub fn composite(self: *WindowManager, screen: *gfx.Canvas) ?gfx.Rect {
        const damage = self.dirty_rect orelse return null;

        // Clip damage to screen
        var d_x = damage.x;
        var d_y = damage.y;
        var d_w = damage.w;
        var d_h = damage.h;

        if (d_x >= screen.width) d_x = screen.width - 1;
        if (d_y >= screen.height) d_y = screen.height - 1;
        if (d_x + d_w > screen.width) d_w = screen.width - d_x;
        if (d_y + d_h > screen.height) d_h = screen.height - d_y;

        if (d_w == 0 or d_h == 0) {
            self.dirty_rect = null;
            return null;
        }

        screen.clip_rect = gfx.Rect{ .x = d_x, .y = d_y, .w = d_w, .h = d_h };

        // Draw background (clipped by gfx)
        screen.fillRect(d_x, d_y, d_w, d_h, 0x008080); // Teal background

        for (self.windows.items) |win| {
            // Draw decorations (clipped by gfx)
            win.drawDecorations(screen);

            // Draw window content using row-based copies for performance, respecting damage rect
            // Intersect window content rect with damage rect
            const win_x = win.x;
            const win_y = win.y;
            const win_w = win.width;
            const win_h = win.height;

            const min_x = @max(win_x, d_x);
            const min_y = @max(win_y, d_y);
            const max_x = @min(win_x + win_w, d_x + d_w);
            const max_y = @min(win_y + win_h, d_y + d_h);

            if (min_x < max_x and min_y < max_y) {
                const draw_x = min_x;
                const draw_y = min_y;
                const draw_w = max_x - min_x;
                const draw_h = max_y - min_y;

                var dy: usize = 0;
                while (dy < draw_h) : (dy += 1) {
                    const screen_y = draw_y + dy;
                    const screen_x = draw_x; // Copy starts here

                    const screen_offset = screen_y * screen.width + screen_x;
                    const win_offset = (screen_y - win_y) * win.width + (screen_x - win_x);

                    @memcpy(@as([*]gfx.Color, @ptrCast(@volatileCast(screen.buffer.ptr))) + screen_offset, win.canvas.buffer[win_offset .. win_offset + draw_w]);
                }
            }

            // Draw widgets (clipped by gfx)
            for (win.widgets.items) |*w| {
                const saved_x = w.x;
                const saved_y = w.y;
                w.x += win.x;
                w.y += win.y;
                w.draw(screen);
                w.x = saved_x;
                w.y = saved_y;
            }
        }

        screen.clip_rect = null; // Clear clipping
        self.dirty_rect = null;

        self.last_mouse_x = self.mouse_x;
        self.last_mouse_y = self.mouse_y;

        return gfx.Rect{ .x = d_x, .y = d_y, .w = d_w, .h = d_h };
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
                    // Invalidate old window area
                    const old_rect = win.getOuterRect();
                    self.invalidateRect(old_rect.x, old_rect.y, old_rect.w, old_rect.h);

                    // Move to front
                    const moved_win = self.windows.orderedRemove(i);
                    self.windows.append(self.allocator, moved_win) catch {};

                    // Invalidate new window area (same here, but order changes z-index)
                    const new_rect = win.getOuterRect();
                    self.invalidateRect(new_rect.x, new_rect.y, new_rect.w, new_rect.h);
                    break;
                }

                // Check window content for widgets
                if (self.mouse_x >= win.x and self.mouse_x < win.x + win.width and
                    self.mouse_y >= win.y and self.mouse_y < win.y + win.height)
                {
                    // Hit window content, check widgets
                    for (win.widgets.items) |*w| {
                        if (w.handleMouse(self.mouse_x - win.x, self.mouse_y - win.y, true)) {
                            // Widget handled the event. Invalidate widget area.
                            self.invalidateRect(win.x + w.x, win.y + w.y, w.width, w.height);
                            break;
                        }
                    }
                    // Move to front even if no widget hit
                    const moved_win = self.windows.orderedRemove(i);
                    self.windows.append(self.allocator, moved_win) catch {};
                    const outer = win.getOuterRect();
                    self.invalidateRect(outer.x, outer.y, outer.w, outer.h);
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
                            self.invalidateRect(win.x + w.x, win.y + w.y, w.width, w.height);
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
                // Invalidate old position
                const old_rect = win.getOuterRect();
                self.invalidateRect(old_rect.x, old_rect.y, old_rect.w, old_rect.h);

                var new_win_x = @as(i32, @intCast(win.x)) + mdx;
                var new_win_y = @as(i32, @intCast(win.y)) + mdy;

                if (new_win_x < 0) new_win_x = 0;
                if (new_win_y < 20) new_win_y = 20; // Keep title bar on screen

                win.x = @intCast(new_win_x);
                win.y = @intCast(new_win_y);

                // Invalidate new position
                const new_rect = win.getOuterRect();
                self.invalidateRect(new_rect.x, new_rect.y, new_rect.w, new_rect.h);
            }
        }

        // Invalidate mouse areas
        self.invalidateRect(old_x, old_y, 10, 10);
        self.invalidateRect(self.mouse_x, self.mouse_y, 10, 10);

        self.last_buttons = buttons;
    }
};

pub var global_wm: WindowManager = undefined;

pub fn initialize(allocator: std.mem.Allocator) void {
    global_wm = WindowManager.init(allocator);
}
