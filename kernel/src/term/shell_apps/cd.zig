const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const cd_app = ShellApp{
    .name = "cd",
    .description = "Change current directory",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        ctx.current_dir = vfs.getRoot();
        return;
    }

    var path = args[0];
    // Strip quotes
    if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
        path = path[1 .. path.len - 1];
    }

    const node = try vfs.lookup(path, ctx.current_dir);
    if (node.node_type != .directory) {
        term.print("cd: {s}: Not a directory\n", .{path});
        return;
    }

    ctx.current_dir = node;
}
