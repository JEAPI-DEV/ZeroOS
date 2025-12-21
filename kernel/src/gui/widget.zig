//! Widget system for Zen OS GUI.

const std = @import("std");
const gfx = @import("gfx.zig");

pub const WidgetType = enum {
    label,
    button,
    text_box,
};

pub const Widget = struct {
    widget_type: WidgetType,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: union(WidgetType) {
        label: Label,
        button: Button,
        text_box: TextBox,
    },

    pub fn draw(self: *Widget, canvas: *gfx.Canvas) void {
        switch (self.widget_type) {
            .label => self.data.label.draw(canvas, self.x, self.y),
            .button => self.data.button.draw(canvas, self.x, self.y, self.width, self.height),
            .text_box => self.data.text_box.draw(canvas, self.x, self.y, self.width, self.height),
        }
    }

    pub fn handleMouse(self: *Widget, mx: usize, my: usize, pressed: bool) bool {
        if (mx >= self.x and mx < self.x + self.width and my >= self.y and my < self.y + self.height) {
            switch (self.widget_type) {
                .button => return self.data.button.handleMouse(pressed),
                .text_box => return self.data.text_box.handleMouse(pressed),
                else => return false,
            }
        } else {
            if (self.widget_type == .text_box and pressed) {
                self.data.text_box.focused = false;
            }
        }
        return false;
    }

    pub fn handleKey(self: *Widget, key: u8) bool {
        if (self.widget_type == .text_box) {
            return self.data.text_box.handleKey(key);
        }
        return false;
    }
};

pub const Label = struct {
    text: []const u8,
    color: gfx.Color,

    pub fn draw(self: *const Label, canvas: *gfx.Canvas, x: usize, y: usize) void {
        canvas.drawString(self.text, x, y, self.color);
    }
};

pub const Button = struct {
    text: []const u8,
    pressed: bool = false,
    on_click: ?*const fn () void = null,

    pub fn draw(self: *const Button, canvas: *gfx.Canvas, x: usize, y: usize, w: usize, h: usize) void {
        const bg_color: gfx.Color = if (self.pressed) 0xAAAAAA else 0xCCCCCC;
        canvas.fillRect(x, y, w, h, bg_color);
        canvas.drawRect(x, y, w, h, 0x000000);

        // Center text
        const text_len = self.text.len * 8; // Assuming 8px font width
        const tx = x + (w - text_len) / 2;
        const ty = y + (h - 16) / 2; // Assuming 16px font height
        canvas.drawString(self.text, tx, ty, 0x000000);
    }

    pub fn handleMouse(self: *Button, pressed: bool) bool {
        if (pressed and !self.pressed) {
            self.pressed = true;
            return true;
        } else if (!pressed and self.pressed) {
            self.pressed = false;
            if (self.on_click) |click| click();
            return true;
        }
        return false;
    }
};

pub const TextBox = struct {
    text: [256]u8 = undefined,
    len: usize = 0,
    focused: bool = false,

    pub fn draw(self: *const TextBox, canvas: *gfx.Canvas, x: usize, y: usize, w: usize, h: usize) void {
        canvas.fillRect(x, y, w, h, 0xFFFFFF);
        const border_color: gfx.Color = if (self.focused) 0x0000FF else 0x000000;
        canvas.drawRect(x, y, w, h, border_color);

        canvas.drawString(self.text[0..self.len], x + 5, y + (h - 16) / 2, 0x000000);

        if (self.focused) {
            // Draw cursor
            const cx = x + 5 + self.len * 8;
            canvas.fillRect(cx, y + 5, 2, h - 10, 0x000000);
        }
    }

    pub fn handleMouse(self: *TextBox, pressed: bool) bool {
        if (pressed) {
            self.focused = true;
            return true;
        }
        return false;
    }

    pub fn handleKey(self: *TextBox, key: u8) bool {
        if (!self.focused) return false;

        if (key == '\x08') { // Backspace
            if (self.len > 0) {
                self.len -= 1;
            }
        } else if (key >= 32 and key <= 126) {
            if (self.len < 255) {
                self.text[self.len] = key;
                self.len += 1;
            }
        }
        return true;
    }
};
