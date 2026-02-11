//! Basic interactive shell.

const std = @import("std");
const ps2 = @import("../driver/ps2.zig");
const term = @import("terminal.zig");
const x64 = @import("../cpu/x64.zig");
const serial = @import("../driver/serial.zig");
const vfs = @import("../fs/vfs.zig");
const desktop = @import("../gui/desktop.zig");
const heap = @import("../memory/heap.zig");
const proc = @import("../proc/process.zig");
const scheduler = @import("../proc/scheduler.zig");
const input = @import("../driver/input.zig");

// Shell Apps
const shell_apps = struct {
    pub const clear = @import("shell_apps/clear.zig").clear_app;
    pub const echo = @import("shell_apps/echo.zig").echo_app;
    pub const ls = @import("shell_apps/ls.zig").ls_app;
    pub const power = @import("shell_apps/power.zig");
    pub const start_ui = @import("shell_apps/start_ui.zig").start_ui_app;
    pub const vfs = @import("shell_apps/vfs.zig");
};

const ShellApp = @import("shell_apps/shell_app.zig").ShellApp;

/// Maximum command length.
const MAX_COMMAND_LEN = 256;

/// The shell structure.
pub const Shell = struct {
    /// Command buffer.
    buffer: [MAX_COMMAND_LEN]u8 = undefined,
    /// Current buffer length.
    len: usize = 0,

    /// List of registered apps.
    apps: []const ShellApp = &.{
        shell_apps.clear,
        shell_apps.echo,
        shell_apps.ls,
        shell_apps.power.reboot_app,
        shell_apps.power.shutdown_app,
        shell_apps.start_ui,
        shell_apps.vfs.mkdir_app,
        shell_apps.vfs.touch_app,
        shell_apps.vfs.cat_app,
        shell_apps.vfs.write_app,
    },

    /// Initializes the shell.
    pub fn init() Shell {
        return Shell{};
    }

    /// Runs the shell loop.
    pub fn run(self: *Shell) void {
        serial.print("[SHELL] Starting...\n", .{});
        term.print("\nWelcome to Zero Shell!\n", .{});
        term.print("Type 'help' for a list of commands.\n\n", .{});

        while (true) {
            self.prompt();
            self.readLine();
            self.execute();
        }
    }

    /// Prints the shell prompt.
    fn prompt(self: *Shell) void {
        _ = self;
        term.colorPrint(.green, "Zero> ", .{});
    }

    /// Reads a line of input from the keyboard.
    fn readLine(self: *Shell) void {
        self.len = 0;

        while (true) {
            const char = input.getKey();
            if (char == 0) {
                scheduler.instance.yield();
                continue;
            }

            if (char == '\n') {
                term.print("\n", .{});
                break;
            } else if (char == '\x08') { // Backspace
                if (self.len > 0) {
                    self.len -= 1;
                    term.print("\x08", .{});
                }
            } else {
                if (self.len < MAX_COMMAND_LEN) {
                    self.buffer[self.len] = char;
                    self.len += 1;
                    term.print("{c}", .{char});
                }
            }
        }
    }

    /// Executes the command in the buffer.
    fn execute(self: *Shell) void {
        if (self.len == 0) return;

        const cmd_line = self.buffer[0..self.len];
        var iter = std.mem.tokenizeScalar(u8, cmd_line, ' ');
        const cmd_name = iter.next() orelse return;

        if (std.mem.eql(u8, cmd_name, "help")) {
            term.print("Available commands:\n", .{});
            term.print("  help      - Show this help message\n", .{});
            for (self.apps) |app| {
                term.print("  {s: <9} - {s}\n", .{ app.name, app.description });
            }
            return;
        }

        // Collect arguments
        var args_buf: [16][]const u8 = undefined;
        var args_len: usize = 0;
        while (iter.next()) |arg| {
            if (args_len < args_buf.len) {
                args_buf[args_len] = arg;
                args_len += 1;
            }
        }
        const args = args_buf[0..args_len];

        for (self.apps) |app| {
            if (std.mem.eql(u8, app.name, cmd_name)) {
                app.run(args) catch |err| {
                    term.print("Error running '{s}': {s}\n", .{ app.name, @errorName(err) });
                };
                return;
            }
        }

        term.print("Unknown command: {s}\n", .{cmd_name});
    }
};
