//! Basic interactive shell.

const std = @import("std");
const ps2 = @import("../driver/ps2.zig");
const term = @import("terminal.zig");
const x64 = @import("../cpu/x64.zig");

/// Maximum command length.
const MAX_COMMAND_LEN = 256;

/// The shell structure.
pub const Shell = struct {
    /// Command buffer.
    buffer: [MAX_COMMAND_LEN]u8 = undefined,
    /// Current buffer length.
    len: usize = 0,

    /// Initializes the shell.
    pub fn init() Shell {
        return Shell{};
    }

    /// Runs the shell loop.
    pub fn run(self: *Shell) void {
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
            const char = ps2.getKey();

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
        const cmd = iter.next() orelse return;

        if (std.mem.eql(u8, cmd, "help")) {
            term.print("Available commands:\n", .{});
            term.print("  help      - Show this help message\n", .{});
            term.print("  clear     - Clear the screen\n", .{});
            term.print("  echo      - Print arguments\n", .{});
            term.print("  reboot    - Reboot the system\n", .{});
            term.print("  shutdown  - Shutdown the system\n", .{});
        } else if (std.mem.eql(u8, cmd, "clear")) {
            term.clear();
        } else if (std.mem.eql(u8, cmd, "echo")) {
            const rest = iter.rest();
            term.print("{s}\n", .{rest});
        } else if (std.mem.eql(u8, cmd, "reboot")) {
            term.print("Rebooting...\n", .{});
            // 8042 keyboard controller pulse reset line.
            x64.outb(0x64, 0xFE);
            x64.hang();
        } else if (std.mem.eql(u8, cmd, "shutdown")) {
            term.print("Shutting down...\n", .{});
            // QEMU shutdown hack (for newer QEMU).
            x64.outw(0x604, 0x2000);
            // Bochs/older QEMU shutdown hack.
            x64.outw(0xB004, 0x2000);
            x64.hang();
        } else {
            term.print("Unknown command: {s}\n", .{cmd});
        }
    }
};
