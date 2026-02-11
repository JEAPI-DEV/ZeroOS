const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const ls_app = ShellApp{
    .name = "ls",
    .description = "List directory contents",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    var path: []const u8 = ".";
    if (args.len > 0) {
        path = args[0];
        // Strip quotes
        if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
            path = path[1 .. path.len - 1];
        }
    }

    const node = try vfs.lookup(path, ctx.current_dir);
    if (node.node_type != .directory) {
        term.print("{s}\n", .{node.name});
        return;
    }

    var i: usize = 0;
    while (try vfs.VfsNode.readdir(node, i)) |child| : (i += 1) {
        if (child.node_type == .directory) {
            term.colorPrint(.blue, "{s}/  ", .{child.name});
        } else {
            term.print("{s}  ", .{child.name});
        }
    }
    term.print("\n", .{});
}
