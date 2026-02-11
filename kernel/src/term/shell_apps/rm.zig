const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const rm_app = ShellApp{
    .name = "rm",
    .description = "Remove a file or directory",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        term.print("Usage: rm <path>\n", .{});
        return;
    }
    var path = args[0];
    if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
        path = path[1 .. path.len - 1];
    }

    // Find parent and basename
    const last_slash = std.mem.lastIndexOfScalar(u8, path, '/');
    const parent_node = if (last_slash) |idx|
        try vfs.lookup(path[0..idx], ctx.current_dir)
    else
        ctx.current_dir;

    if (parent_node.node_type != .directory) {
        term.print("rm: invalid path\n", .{});
        return error.NotADirectory;
    }

    const name = if (last_slash) |idx| path[idx + 1 ..] else path;
    try vfs.VfsNode.remove(parent_node, name);
}
