const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const cat_app = ShellApp{
    .name = "cat",
    .description = "Read file contents",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        term.print("Usage: cat <path>\n", .{});
        return;
    }
    var path = args[0];
    if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
        path = path[1 .. path.len - 1];
    }

    const node = try vfs.lookup(path, ctx.current_dir);
    if (node.node_type != .file) {
        term.print("cat: {s}: Not a file\n", .{path});
        return;
    }

    var buf: [4096]u8 = undefined;
    const bytes_read = try vfs.VfsNode.read(node, 0, &buf);
    term.print("{s}\n", .{buf[0..bytes_read]});
}
