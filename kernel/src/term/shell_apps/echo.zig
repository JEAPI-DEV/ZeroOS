const std = @import("std");
const term = @import("../terminal.zig");
const ShellApp = @import("shell_app.zig").ShellApp;

pub const echo_app = ShellApp{
    .name = "echo",
    .description = "Print arguments",
    .run = run,
};

fn run(args: [][]const u8) anyerror!void {
    for (args, 0..) |arg, i| {
        term.print("{s}", .{arg});
        if (i < args.len - 1) term.print(" ", .{});
    }
    term.print("\n", .{});
}
