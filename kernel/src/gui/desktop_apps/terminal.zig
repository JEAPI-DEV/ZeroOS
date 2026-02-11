const std = @import("std");
const wm = @import("../wm.zig");
const DesktopApp = @import("desktop_app.zig").DesktopApp;

pub const terminal_app = DesktopApp{
    .name = "Terminal",
    .setup = setup,
};

fn setup(window: *wm.Window) anyerror!void {
    try window.addWidget(.{
        .widget_type = .label,
        .x = 10,
        .y = 10,
        .width = 100,
        .height = 20,
        .data = .{ .label = .{ .text = "Welcome to Zen OS!", .color = 0x000000 } },
    });
    try window.addWidget(.{
        .widget_type = .text_box,
        .x = 10,
        .y = 40,
        .width = 300,
        .height = 30,
        .data = .{ .text_box = .{} },
    });
}
