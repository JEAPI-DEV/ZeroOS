const std = @import("std");

const vfs = @import("../../fs/vfs.zig");

pub const ShellApp = struct {
    name: []const u8,
    description: []const u8,
    run: *const fn (ctx: *ShellContext, args: [][]const u8) anyerror!void,
};

pub const ShellContext = struct {
    current_dir: *vfs.VfsNode,
    apps: []const ShellApp = &.{},
};
