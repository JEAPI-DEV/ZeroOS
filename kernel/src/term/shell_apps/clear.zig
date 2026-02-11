const std = @import("std");
const term = @import("../terminal.zig");
const ShellApp = @import("shell_app.zig").ShellApp;

pub const clear_app = ShellApp{
    .name = "clear",
    .description = "Clear the screen",
    .run = run,
};

fn run(args: [][]const u8) anyerror!void {
    _ = args;
    term.clear();
}
