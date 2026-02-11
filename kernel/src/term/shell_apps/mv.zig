const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const mv_app = ShellApp{
    .name = "mv",
    .description = "Move or rename a file",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len < 2) {
        term.print("Usage: mv <src> <dest>\n", .{});
        return;
    }

    const src_path = args[0];
    const dest_path = args[1];

    // Find source parent and name
    const src_last_slash = std.mem.lastIndexOfScalar(u8, src_path, '/');
    const src_parent = if (src_last_slash) |idx|
        try vfs.lookup(src_path[0..idx], ctx.current_dir)
    else
        ctx.current_dir;
    const src_name = if (src_last_slash) |idx| src_path[idx + 1 ..] else src_path;

    // TODO: Cross-directory move is not yet supported by VfsNode.rename (only supports sibling rename)
    // For now, if dest is a directory, move inside it.
    const dest_node_or_err = vfs.lookup(dest_path, ctx.current_dir);
    if (dest_node_or_err) |dest_node| {
        if (dest_node.node_type == .directory) {
            // Move into directory: Basically rename old_name to new_path/old_name
            // But rename vtable only takes a name.
            // So we'd need to support changing parents.
            // Let's just implement sibling rename for now.
            term.print("mv: cross-directory move not yet supported\n", .{});
            return;
        }
    } else |err| {
        if (err != error.NotFound) return err;
    }

    // Sibling rename
    try vfs.VfsNode.rename(src_parent, src_name, dest_path);
}
