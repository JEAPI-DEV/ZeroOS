//! Abstract graphical API for Zen OS.

const std = @import("std");
const fb = @import("../term/framebuffer.zig");
const font = @import("../term/font.zig");

pub const Color = fb.RgbColor;

pub const Rect = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,
};

pub const Canvas = struct {
    width: usize,
    height: usize,
    buffer: []volatile Color,
    clip_rect: ?Rect = null,

    pub fn putPixel(self: *Canvas, x: usize, y: usize, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        if (self.clip_rect) |cr| {
            if (x < cr.x or x >= cr.x + cr.w or y < cr.y or y >= cr.y + cr.h) return;
        }
        self.buffer[y * self.width + x] = color;
    }

    pub fn fillRect(self: *Canvas, x: usize, y: usize, w: usize, h: usize, color: Color) void {
        var rx = x;
        var ry = y;
        var rw = w;
        var rh = h;

        if (self.clip_rect) |cr| {
            const min_x = @max(rx, cr.x);
            const min_y = @max(ry, cr.y);
            const max_x = @min(rx + rw, cr.x + cr.w);
            const max_y = @min(ry + rh, cr.y + cr.h);

            if (min_x >= max_x or min_y >= max_y) return;

            rx = min_x;
            ry = min_y;
            rw = max_x - min_x;
            rh = max_y - min_y;
        }

        var dy: usize = 0;
        while (dy < rh) : (dy += 1) {
            if (ry + dy >= self.height) break;
            var dx: usize = 0;
            while (dx < rw) : (dx += 1) {
                if (rx + dx >= self.width) break;
                self.buffer[(ry + dy) * self.width + (rx + dx)] = color;
            }
        }
    }

    pub fn drawRect(self: *Canvas, x: usize, y: usize, w: usize, h: usize, color: Color) void {
        // Top and bottom
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            self.putPixel(x + dx, y, color);
            self.putPixel(x + dx, y + h - 1, color);
        }
        // Left and right
        var dy: usize = 0;
        while (dy < h) : (dy += 1) {
            self.putPixel(x, y + dy, color);
            self.putPixel(x + w - 1, y + dy, color);
        }
    }

    pub fn drawChar(self: *Canvas, c: u8, x: usize, y: usize, fg: Color) void {
        if (c >= font.NUM_GLYPHS) return;
        const glyph = font.BITMAP[c];
        for (0..font.HEIGHT) |dy| {
            for (0..font.WIDTH) |dx| {
                const mask: u8 = @as(u8, 1) << @intCast(font.WIDTH - dx - 1);
                if (glyph[dy] & mask != 0) {
                    self.putPixel(x + dx, y + dy, fg);
                }
            }
        }
    }

    pub fn drawString(self: *Canvas, s: []const u8, x: usize, y: usize, fg: Color) void {
        var cur_x = x;
        for (s) |c| {
            self.drawChar(c, cur_x, y, fg);
            cur_x += font.WIDTH;
        }
    }
};

pub var screen_canvas: Canvas = undefined;
var back_buffer: []Color = undefined;

pub fn initialize(allocator: std.mem.Allocator) !void {
    fb.initialize();
    const serial = @import("../driver/serial.zig");
    serial.print("[GFX] Framebuffer: {}x{} @ 32bpp\n", .{ fb.width, fb.height });

    const size = fb.width * fb.height;
    serial.print("[GFX] Allocating back buffer ({} bytes)...\n", .{size * @sizeOf(Color)});
    back_buffer = try allocator.alignedAlloc(Color, .@"8", size);
    serial.print("[GFX] Allocation successful\n", .{});

    screen_canvas = .{
        .width = fb.width,
        .height = fb.height,
        .buffer = back_buffer,
    };
}

pub fn swap() void {
    const front_ptr: [*]volatile u64 = @ptrCast(@alignCast(fb.framebuffer_request.response.?.framebuffers()[0].address));
    const back_ptr: [*]const u64 = @ptrCast(@alignCast(back_buffer.ptr));

    const size = (fb.width * fb.height * @sizeOf(Color)) / 8;
    var i: usize = 0;
    while (i < size) : (i += 1) {
        front_ptr[i] = back_ptr[i];
    }
}

pub fn swapRect(x: usize, y: usize, w: usize, h: usize) void {
    const fb_ptr: [*]volatile u32 = @ptrCast(@alignCast(fb.framebuffer_request.response.?.framebuffers()[0].address));
    const back_ptr: [*]const u32 = back_buffer.ptr;
    const stride = fb.width;

    var cur_y = y;
    const end_y = y + h;
    while (cur_y < end_y) : (cur_y += 1) {
        if (cur_y >= fb.height) break;

        const offset = cur_y * stride + x;
        const len = if (x + w > fb.width) fb.width - x else w;
        if (len == 0) continue;

        @memcpy(@as([*]u32, @ptrCast(@volatileCast(fb_ptr))) + offset, back_ptr[offset .. offset + len]);
    }
}
