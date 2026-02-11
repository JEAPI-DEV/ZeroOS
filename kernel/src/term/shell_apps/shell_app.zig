const std = @import("std");

pub const ShellApp = struct {
    name: []const u8,
    description: []const u8,
    run: *const fn (args: [][]const u8) anyerror!void,
};
