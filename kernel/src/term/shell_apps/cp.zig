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

    // Copy loop
    var buf: [4096]u8 = undefined;
    var offset: u64 = 0;

    // Create destination if needed
    const dest_node_opt = vfs.lookup(dest_path, ctx.current_dir) catch |err| block: {
        if (err == error.NotFound) {
            const last_slash = std.mem.lastIndexOfScalar(u8, dest_path, '/');
            const parent_node = if (last_slash) |idx|
                try vfs.lookup(dest_path[0..idx], ctx.current_dir)
            else
                ctx.current_dir;

            const name = if (last_slash) |idx| dest_path[idx + 1 ..] else dest_path;
            const new_node = try vfs.VfsNode.create(parent_node, name);
            new_node.parent = parent_node;
            break :block new_node;
        }
        return err;
    };

    const dest_node = dest_node_opt; // It might be valid node from lookup or new node

    // If we just looked it up, we need to check if it's a directory?
    // cp <file> <dir> -> cp <file> <dir>/<filename>
    // My previous implementation didn't handle that fully (implied exact path).
    // Let's stick to exact path for now or basic file check.

    if (dest_node.node_type != .file) {
        // If directory, try to append filename?
        // For now, error.
        term.print("cp: {s}: Not a file\n", .{dest_path});
        return;
    }

    // Now loop copy
    while (true) {
        const len = try vfs.VfsNode.read(src_node, offset, &buf);
        if (len == 0) break;
        _ = try vfs.VfsNode.write(dest_node, offset, buf[0..len]);
        offset += len;
    }
}
