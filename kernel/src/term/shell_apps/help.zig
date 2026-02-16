const std = @import("std");
const term = @import("../terminal.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const help_app = ShellApp{
    .name = "help",
    .description = "Show available commands",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    _ = args;
    term.print("Available commands:\n", .{});
    term.print("  help      - Show this help message\n", .{});
    for (ctx.apps) |app| {
        term.print("  {s: <9} - {s}\n", .{ app.name, app.description });
    }
}
