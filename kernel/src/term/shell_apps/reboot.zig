const term = @import("../terminal.zig");
const x64 = @import("../../cpu/x64.zig");
const shell_app = @import("shell_app.zig");
const ShellApp = shell_app.ShellApp;
const ShellContext = shell_app.ShellContext;

pub const reboot_app = ShellApp{
    .name = "reboot",
    .description = "Reboot the system",
    .run = run,
};

fn run(ctx: *ShellContext, args: [][]const u8) anyerror!void {
    _ = ctx;
    _ = args;
    term.print("Rebooting...\n", .{});
    x64.outb(0x64, 0xFE);
    x64.hang();
}
