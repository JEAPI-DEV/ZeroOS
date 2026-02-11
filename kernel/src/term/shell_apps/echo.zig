const std = @import("std");
const term = @import("../terminal.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const echo_app = ShellApp{
    .name = "echo",
    .description = "Print arguments",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    _ = ctx;
    for (args, 0..) |arg, i| {
        term.print("{s}", .{arg});
        if (i < args.len - 1) term.print(" ", .{});
    }
    term.print("\n", .{});
}
