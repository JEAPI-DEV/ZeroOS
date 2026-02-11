const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const cp_app = ShellApp{
    .name = "cp",
    .description = "Copy a file",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len < 2) {
        term.print("Usage: cp <src> <dest>\n", .{});
        return;
    }

    const src_path = args[0];
    const dest_path = args[1];

    const src_node = try vfs.lookup(src_path, ctx.current_dir);
    if (src_node.node_type != .file) {
        term.print("cp: {s}: Not a file\n", .{src_path});
        return;
    }

    // Read source
    var buf: [16384]u8 = undefined;
    const len = try vfs.VfsNode.read(src_node, 0, &buf);

    // Find/Create destination
    const dest_node = vfs.lookup(dest_path, ctx.current_dir) catch |err| {
        if (err == error.NotFound) {
            const last_slash = std.mem.lastIndexOfScalar(u8, dest_path, '/');
            const parent_node = if (last_slash) |idx|
                try vfs.lookup(dest_path[0..idx], ctx.current_dir)
            else
                ctx.current_dir;

            const name = if (last_slash) |idx| dest_path[idx + 1 ..] else dest_path;
            const new_node = try vfs.VfsNode.create(parent_node, name);
            new_node.parent = parent_node;
            _ = try vfs.VfsNode.write(new_node, 0, buf[0..len]);
            return;
        }
        return err;
    };

    if (dest_node.node_type != .file) {
        term.print("cp: {s}: Not a file\n", .{dest_path});
        return;
    }
    _ = try vfs.VfsNode.write(dest_node, 0, buf[0..len]);
}
