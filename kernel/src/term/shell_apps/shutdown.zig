const term = @import("../terminal.zig");
const x64 = @import("../../cpu/x64.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const shutdown_app = ShellApp{
    .name = "shutdown",
    .description = "Shutdown the system",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    _ = ctx;
    _ = args;
    term.print("Shutting down...\n", .{});
    x64.outw(0x604, 0x2000);
    x64.outw(0xB004, 0x2000);
    x64.hang();
}
