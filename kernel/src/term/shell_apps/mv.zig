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

    // Find destination parent and name
    // If dest path exists and is a directory, move INTO it.
    // If dest path does not exist, rename TO it (implies parent is dest's parent).

    var dest_parent: *vfs.VfsNode = ctx.current_dir;
    var dest_name: []const u8 = dest_path;

    const dest_node_or_err = vfs.lookup(dest_path, ctx.current_dir);
    if (dest_node_or_err) |dest_node| {
        if (dest_node.node_type == .directory) {
            // Move into: new parent is dest_node, new name is src_name
            dest_parent = dest_node;
            dest_name = src_name;
        } else {
            // File exists? Overwrite? For now fail.
            term.print("mv: destination exists and is not a directory.\n", .{});
            return error.PathExists;
        }
    } else |err| {
        if (err == error.NotFound) {
            // Rename to dest_path
            const dest_last_slash = std.mem.lastIndexOfScalar(u8, dest_path, '/');
            if (dest_last_slash) |idx| {
                dest_parent = try vfs.lookup(dest_path[0..idx], ctx.current_dir);
                dest_name = dest_path[idx + 1 ..];
            } else {
                // Sibling in current dir
                dest_parent = ctx.current_dir;
                dest_name = dest_path;
            }
        } else {
            return err;
        }
    }

    // Perform rename/move
    try vfs.VfsNode.rename(src_parent, src_name, dest_parent, dest_name);
}
