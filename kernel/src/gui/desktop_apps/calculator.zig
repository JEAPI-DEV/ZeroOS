const std = @import("std");
const wm = @import("../wm.zig");
const widget = @import("../widget.zig");
const DesktopApp = @import("desktop_app.zig").DesktopApp;
const serial = @import("../../driver/serial.zig");

pub const calculator_app = DesktopApp{
    .name = "Calculator",
    .setup = setup,
};

const CalcState = struct {
    window: *wm.Window,
    display: *widget.TextBox,
    accumulator: i64 = 0,
    pending_op: ?u8 = null,
    clear_on_next: bool = true,

    fn invalidateDisplay(self: *CalcState) void {
        const display_widget = &self.window.widgets.items[0];
        wm.global_wm.invalidateRect(self.window.x + display_widget.x, self.window.y + display_widget.y, display_widget.width, display_widget.height);
    }

    fn addDigit(self: *CalcState, digit: u8) void {
        if (self.clear_on_next) {
            self.display.len = 0;
            self.clear_on_next = false;
        }
        if (self.display.len < 15) {
            self.display.text[self.display.len] = digit;
            self.display.len += 1;
        }
        self.invalidateDisplay();
    }

    fn applyOp(self: *CalcState, op: u8) void {
        const current_val = if (self.display.len > 0) std.fmt.parseInt(i64, self.display.text[0..self.display.len], 10) catch 0 else 0;

        if (self.pending_op) |pending| {
            switch (pending) {
                '+' => self.accumulator += current_val,
                '-' => self.accumulator -= current_val,
                '*' => self.accumulator *= current_val,
                '/' => {
                    if (current_val != 0) {
                        self.accumulator = @divTrunc(self.accumulator, current_val);
                    }
                },
                else => {},
            }
        } else {
            self.accumulator = current_val;
        }

        if (op == '=') {
            var buf: [32]u8 = undefined;
            const res = std.fmt.bufPrint(&buf, "{}", .{self.accumulator}) catch "Error";
            @memcpy(self.display.text[0..res.len], res);
            self.display.len = res.len;
            self.pending_op = null;
        } else {
            self.pending_op = op;
        }
        self.clear_on_next = true;
        self.invalidateDisplay();
    }

    fn clear(self: *CalcState) void {
        self.display.len = 1;
        self.display.text[0] = '0';
        self.accumulator = 0;
        self.pending_op = null;
        self.clear_on_next = true;
        self.invalidateDisplay();
    }
};

var global_state: CalcState = undefined;

fn Handler(comptime c: u8) type {
    return struct {
        fn click() void {
            switch (c) {
                '0'...'9' => global_state.addDigit(c),
                '+', '-', '*', '/', '=' => global_state.applyOp(c),
                'C' => global_state.clear(),
                else => unreachable,
            }
        }
    };
}

fn setup(window: *wm.Window) anyerror!void {
    // Resize window for calculator
    window.width = 220;
    window.height = 280;

    // Display
    try window.addWidget(.{
        .widget_type = .text_box,
        .x = 10,
        .y = 10,
        .width = 200,
        .height = 30,
        .data = .{ .text_box = .{ .text = undefined, .len = 0, .focused = false } },
    });

    const buttons = [_][]const u8{
        "7", "8", "9", "/",
        "4", "5", "6", "*",
        "1", "2", "3", "-",
        "C", "0", "=", "+",
    };

    for (buttons, 0..) |label, i| {
        const row = i / 4;
        const col = i % 4;
        const char = label[0];

        try window.addWidget(.{
            .widget_type = .button,
            .x = 10 + col * 50,
            .y = 50 + row * 50,
            .width = 40,
            .height = 40,
            .data = .{ .button = .{ .text = label, .on_click = switch (char) {
                inline '0'...'9', '+', '-', '*', '/', '=', 'C' => |c| Handler(c).click,
                else => unreachable,
            } } },
        });
    }

    global_state.window = window;
    global_state.display = &window.widgets.items[0].data.text_box;
    global_state.display.text[0] = '0';
    global_state.display.len = 1;
    global_state.accumulator = 0;
    global_state.pending_op = null;
    global_state.clear_on_next = true;
}
