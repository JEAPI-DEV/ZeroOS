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
    _ = ctx;
    _ = args;
    // Note: The shell handles the actual 'help' rendering in the loop for now
    // to avoid circular dependencies or needing to pass the shell handle.
    // However, if we want it to be a real app, we might need a way to list apps.
    // For now, the shell's built-in help is preferred.
    term.print("Type 'help' for a list of commands.\n", .{});
}
