const std = @import("std");
const term = @import("../terminal.zig");
const x64 = @import("../../cpu/x64.zig");
const ShellApp = @import("shell_app.zig").ShellApp;

pub const reboot_app = ShellApp{
    .name = "reboot",
    .description = "Reboot the system",
    .run = runReboot,
};

pub const shutdown_app = ShellApp{
    .name = "shutdown",
    .description = "Shutdown the system",
    .run = runShutdown,
};

fn runReboot(args: [][]const u8) anyerror!void {
    _ = args;
    term.print("Rebooting...\n", .{});
    x64.outb(0x64, 0xFE);
    x64.hang();
}

fn runShutdown(args: [][]const u8) anyerror!void {
    _ = args;
    term.print("Shutting down...\n", .{});
    x64.outw(0x604, 0x2000);
    x64.outw(0xB004, 0x2000);
    x64.hang();
}
