const term = @import("../terminal.zig");
const ramfs = @import("../../fs/ramfs.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const sync_app = ShellApp{
    .name = "sync",
    .description = "Flush filesystem to disk",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    _ = ctx;
    _ = args;
    term.print("Syncing filesystems...\n", .{});
    ramfs.saveToDisk() catch |err| {
        term.print("Sync failed: {s}\n", .{@errorName(err)});
        return;
    };
    term.print("Sync complete.\n", .{});
}
