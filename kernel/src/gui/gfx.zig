//! Abstract graphical API for Zen OS.

const std = @import("std");
const fb = @import("../term/framebuffer.zig");
const font = @import("../term/font.zig");

pub const Color = fb.RgbColor;

pub const Canvas = struct {
    width: usize,
    height: usize,
    buffer: []volatile Color,

    pub fn putPixel(self: *Canvas, x: usize, y: usize, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        self.buffer[y * self.width + x] = color;
    }

    pub fn fillRect(self: *Canvas, x: usize, y: usize, w: usize, h: usize, color: Color) void {
        var dy: usize = 0;
        while (dy < h) : (dy += 1) {
            if (y + dy >= self.height) break;
            var dx: usize = 0;
            while (dx < w) : (dx += 1) {
                if (x + dx >= self.width) break;
                self.buffer[(y + dy) * self.width + (x + dx)] = color;
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
