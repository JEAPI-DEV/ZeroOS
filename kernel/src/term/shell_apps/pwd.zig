const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const pwd_app = ShellApp{
    .name = "pwd",
    .description = "Print current working directory",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    _ = args;
    var components: [32][]const u8 = undefined;
    var count: usize = 0;
    var current: ?*vfs.VfsNode = ctx.current_dir;

    while (current) |node| {
        if (node.name.len > 0) {
            if (count < components.len) {
                components[count] = node.name;
                count += 1;
            }
        }
        current = node.parent;
    }

    if (count == 0) {
        term.print("/\n", .{});
        return;
    }

    term.print("/", .{});
    var i: usize = count;
    while (i > 0) {
        i -= 1;
        term.print("{s}", .{components[i]});
        if (i > 0) term.print("/", .{});
    }
    term.print("\n", .{});
}
