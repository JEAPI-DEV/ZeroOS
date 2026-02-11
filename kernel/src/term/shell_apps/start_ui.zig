const std = @import("std");
const term = @import("../terminal.zig");
const desktop = @import("../../gui/desktop.zig");
const scheduler = @import("../../proc/scheduler.zig");
const input = @import("../../driver/input.zig");
const heap = @import("../../memory/heap.zig");
const serial = @import("../../driver/serial.zig");
const x64 = @import("../../cpu/x64.zig");
const ShellApp = @import("shell_app.zig").ShellApp;

pub const start_ui_app = ShellApp{
    .name = "start-ui",
    .description = "Start the graphical user interface",
    .run = run,
};

fn run(args: [][]const u8) anyerror!void {
    _ = args;
    term.print("Starting GUI...\n", .{});
    serial.print("[SHELL] Creating GUI thread...\n", .{});

    const current_thread = scheduler.instance.current_thread.?;
    const gui_thread = try current_thread.process.createThread(desktopThread, null, 16384, heap.allocator);

    serial.print("[SHELL] Enqueueing GUI thread (ID={})...\n", .{gui_thread.id});
    input.setMode(.GUI);
    term.suppressed = true;
    scheduler.instance.enqueue(gui_thread);
}

fn desktopThread(_: ?*anyopaque) void {
    serial.print("[GUI] desktopThread entered\n", .{});
    x64.sti();
    desktop.start() catch |err| {
        serial.print("[GUI] Desktop failed: {s}\n", .{@errorName(err)});
    };
}
