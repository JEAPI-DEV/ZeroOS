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
    pub const cd = @import("shell_apps/cd.zig").cd_app;
    pub const help = @import("shell_apps/help.zig").help_app;
    pub const mkdir = @import("shell_apps/mkdir.zig").mkdir_app;
    pub const touch = @import("shell_apps/touch.zig").touch_app;
    pub const cat = @import("shell_apps/cat.zig").cat_app;
    pub const write = @import("shell_apps/write.zig").write_app;
    pub const rm = @import("shell_apps/rm.zig").rm_app;
    pub const cp = @import("shell_apps/cp.zig").cp_app;
    pub const mv = @import("shell_apps/mv.zig").mv_app;
    pub const pwd = @import("shell_apps/pwd.zig").pwd_app;
    pub const reboot = @import("shell_apps/reboot.zig").reboot_app;
    pub const shutdown = @import("shell_apps/shutdown.zig").shutdown_app;
    pub const sync = @import("shell_apps/sync.zig").sync_app;
    pub const start_ui = @import("shell_apps/start_ui.zig").start_ui_app;
};

const shell_app_mod = @import("shell_apps/shell_app.zig");
const ShellApp = shell_app_mod.ShellApp;
const ShellContext = shell_app_mod.ShellContext;
const ramfs = @import("../fs/ramfs.zig");

/// Maximum command length.
const MAX_COMMAND_LEN = 256;

const all_apps = [_]ShellApp{
    shell_apps.clear,
    shell_apps.echo,
    shell_apps.ls,
    shell_apps.cd,
    shell_apps.help,
    shell_apps.pwd,
    shell_apps.mkdir,
    shell_apps.touch,
    shell_apps.cat,
    shell_apps.write,
    shell_apps.rm,
    shell_apps.cp,
    shell_apps.mv,
    shell_apps.reboot,
    shell_apps.shutdown,
    shell_apps.sync,
    shell_apps.start_ui,
};

/// The shell structure.
pub const Shell = struct {
    /// Command buffer.
    buffer: [MAX_COMMAND_LEN]u8 = undefined,
    /// Current buffer length.
    len: usize = 0,
    /// Shell context.
    ctx: ShellContext,

    /// List of registered apps.
    apps: []const ShellApp = &all_apps,

    /// Initializes the shell.
    pub fn init() Shell {
        // Try to load persistence
        serial.print("[SHELL] Loading filesystem... (DISABLED)\n", .{});
        // ramfs.loadFromDisk() catch |err| {
        //     serial.print("[SHELL] Failed to load filesystem (or empty): {s}\n", .{@errorName(err)});
        // };

        return Shell{
            .ctx = .{
                .current_dir = vfs.getRoot(),
                .apps = &all_apps,
            },
        };
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
        term.colorPrint(.green, "Zero:", .{});
        term.colorPrint(.blue, "{s}", .{self.ctx.current_dir.name});
        term.colorPrint(.green, "> ", .{});
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
                app.run(&self.ctx, args) catch |err| {
                    term.print("Error running '{s}': {s}\n", .{ app.name, @errorName(err) });
                };
                return;
            }
        }

        term.print("Unknown command: {s}\n", .{cmd_name});
    }
};
