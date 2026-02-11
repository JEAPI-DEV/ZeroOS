const std = @import("std");
const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const ShellApp = @import("shell_app.zig").ShellApp;

pub const mkdir_app = ShellApp{
    .name = "mkdir",
    .description = "Create a directory",
    .run = runMkdir,
};

pub const touch_app = ShellApp{
    .name = "touch",
    .description = "Create an empty file",
    .run = runTouch,
};

pub const cat_app = ShellApp{
    .name = "cat",
    .description = "Read file contents",
    .run = runCat,
};

pub const write_app = ShellApp{
    .name = "write",
    .description = "Write text to a file",
    .run = runWrite,
};

fn stripQuotes(path: []const u8) []const u8 {
    if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
        return path[1 .. path.len - 1];
    }
    return path;
}

fn runMkdir(args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        term.print("Usage: mkdir <path>\n", .{});
        return;
    }
    const path = stripQuotes(args[0]);
    const root = vfs.getRoot();
    _ = try vfs.VfsNode.mkdir(root, path);
}

fn runTouch(args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        term.print("Usage: touch <path>\n", .{});
        return;
    }
    const path = stripQuotes(args[0]);
    const root = vfs.getRoot();
    _ = try vfs.VfsNode.create(root, path);
}

fn runCat(args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        term.print("Usage: cat <path>\n", .{});
        return;
    }
    const path = stripQuotes(args[0]);
    const node = try vfs.lookup(path);
    if (node.node_type != .file) {
        term.print("cat: {s}: Not a file\n", .{path});
        return;
    }
    var buf: [1024]u8 = undefined;
    const bytes_read = try vfs.VfsNode.read(node, 0, &buf);
    term.print("{s}\n", .{buf[0..bytes_read]});
}

fn runWrite(args: [][]const u8) anyerror!void {
    if (args.len < 2) {
        term.print("Usage: write <path> <text>\n", .{});
        return;
    }
    const path = stripQuotes(args[0]);

    // Join remaining args as text
    var text_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&text_buf);
    const allocator = fba.allocator();

    const text = std.mem.join(allocator, " ", args[1..]) catch |err| {
        term.print("Error joining text: {s}\n", .{@errorName(err)});
        return;
    };
    const node = try vfs.lookup(path);
    if (node.node_type != .file) {
        term.print("write: {s}: Not a file\n", .{path});
        return;
    }
    _ = try vfs.VfsNode.write(node, 0, text);
}
