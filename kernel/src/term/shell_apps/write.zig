const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const write_app = ShellApp{
    .name = "write",
    .description = "Write text to a file (creates if not exists)",
    .run = run,
};

fn stripQuotes(path: []const u8) []const u8 {
    if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
        return path[1 .. path.len - 1];
    }
    return path;
}

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len < 2) {
        term.print("Usage: write <path> <text>\n", .{});
        return;
    }
    const path = stripQuotes(args[0]);

    // Join remaining args as text
    var text_buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&text_buf);
    const allocator = fba.allocator();

    const text = std.mem.join(allocator, " ", args[1..]) catch |err| {
        term.print("Error joining text: {s}\n", .{@errorName(err)});
        return;
    };

    const node = vfs.lookup(path, ctx.current_dir) catch |err| {
        if (err == error.NotFound) {
            // Find parent and basename
            const last_slash = std.mem.lastIndexOfScalar(u8, path, '/');
            const parent_node = if (last_slash) |idx|
                try vfs.lookup(path[0..idx], ctx.current_dir)
            else
                ctx.current_dir;

            if (parent_node.node_type != .directory) {
                term.print("write: parent is not a directory\n", .{});
                return error.NotADirectory;
            }

            const name = if (last_slash) |idx| path[idx + 1 ..] else path;
            const new_node = try vfs.VfsNode.create(parent_node, name);
            new_node.parent = parent_node;
            _ = try vfs.VfsNode.write(new_node, 0, text);
            return;
        }
        return err;
    };

    if (node.node_type != .file) {
        term.print("write: {s}: Not a file\n", .{path});
        return;
    }
    _ = try vfs.VfsNode.write(node, 0, text);
}
