const term = @import("../terminal.zig");
const vfs = @import("../../fs/vfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const mkdir_app = ShellApp{
    .name = "mkdir",
    .description = "Create a directory",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    if (args.len == 0) {
        term.print("Usage: mkdir <path>\n", .{});
        return;
    }
    var path = args[0];
    if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
        path = path[1 .. path.len - 1];
    }

    _ = try vfs.VfsNode.mkdir(ctx.current_dir, path);
}
