const std = @import("std");
const wm = @import("../wm.zig");

pub const DesktopApp = struct {
    name: []const u8,
    setup: *const fn (window: *wm.Window) anyerror!void,
};
