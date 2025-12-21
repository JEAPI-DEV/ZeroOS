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
                scheduler.global_scheduler.yield();
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
        const cmd = iter.next() orelse return;

        if (std.mem.eql(u8, cmd, "help")) {
            term.print("Available commands:\n", .{});
            term.print("  help      - Show this help message\n", .{});
            term.print("  clear     - Clear the screen\n", .{});
            term.print("  echo      - Print arguments\n", .{});
            term.print("  ls        - List directory contents\n", .{});
            term.print("  mkdir     - Create a directory\n", .{});
            term.print("  touch     - Create an empty file\n", .{});
            term.print("  cat       - Read file contents\n", .{});
            term.print("  write     - Write text to a file\n", .{});
            term.print("  start-ui  - Start the graphical user interface\n", .{});
            term.print("  reboot    - Reboot the system\n", .{});
            term.print("  shutdown  - Shutdown the system\n", .{});
        } else if (std.mem.eql(u8, cmd, "clear")) {
            term.clear();
        } else if (std.mem.eql(u8, cmd, "echo")) {
            const rest = iter.rest();
            term.print("{s}\n", .{rest});
        } else if (std.mem.eql(u8, cmd, "ls")) {
            var path = iter.next() orelse "/";
            // Strip quotes
            if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
                path = path[1 .. path.len - 1];
            }
            const node = vfs.lookup(path) catch |err| {
                term.print("ls: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
            if (node.node_type != .directory) {
                term.print("{s}\n", .{node.name});
                return;
            }
            var i: usize = 0;
            while (vfs.VfsNode.readdir(node, i) catch null) |child| : (i += 1) {
                if (child.node_type == .directory) {
                    term.colorPrint(.blue, "{s}/  ", .{child.name});
                } else {
                    term.print("{s}  ", .{child.name});
                }
            }
            term.print("\n", .{});
        } else if (std.mem.eql(u8, cmd, "mkdir")) {
            var path = iter.next() orelse {
                term.print("Usage: mkdir <path>\n", .{});
                return;
            };
            // Strip quotes
            if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
                path = path[1 .. path.len - 1];
            }
            // For simplicity, we only support creating in current dir (root for now)
            const root = vfs.getRoot();
            _ = vfs.VfsNode.mkdir(root, path) catch |err| {
                term.print("mkdir: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
        } else if (std.mem.eql(u8, cmd, "touch")) {
            var path = iter.next() orelse {
                term.print("Usage: touch <path>\n", .{});
                return;
            };
            // Strip quotes
            if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
                path = path[1 .. path.len - 1];
            }
            const root = vfs.getRoot();
            _ = vfs.VfsNode.create(root, path) catch |err| {
                term.print("touch: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
        } else if (std.mem.eql(u8, cmd, "cat")) {
            var path = iter.next() orelse {
                term.print("Usage: cat <path>\n", .{});
                return;
            };
            // Strip quotes
            if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
                path = path[1 .. path.len - 1];
            }
            const node = vfs.lookup(path) catch |err| {
                term.print("cat: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
            if (node.node_type != .file) {
                term.print("cat: {s}: Not a file\n", .{path});
                return;
            }
            var buf: [1024]u8 = undefined;
            const bytes_read = vfs.VfsNode.read(node, 0, &buf) catch |err| {
                term.print("cat: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
            term.print("{s}\n", .{buf[0..bytes_read]});
        } else if (std.mem.eql(u8, cmd, "write")) {
            var path = iter.next() orelse {
                term.print("Usage: write <path> <text>\n", .{});
                return;
            };
            // Strip quotes
            if (path.len >= 2 and ((path[0] == '\'' and path[path.len - 1] == '\'') or (path[0] == '"' and path[path.len - 1] == '"'))) {
                path = path[1 .. path.len - 1];
            }
            const text = std.mem.trim(u8, iter.rest(), " ");
            const node = vfs.lookup(path) catch |err| {
                term.print("write: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
            if (node.node_type != .file) {
                term.print("write: {s}: Not a file\n", .{path});
                return;
            }
            _ = vfs.VfsNode.write(node, 0, text) catch |err| {
                term.print("write: {s}: {s}\n", .{ path, @errorName(err) });
                return;
            };
        } else if (std.mem.eql(u8, cmd, "start-ui")) {
            term.print("Starting GUI...\n", .{});
            serial.print("[SHELL] Creating GUI thread...\n", .{});
            const current_thread = scheduler.global_scheduler.current_thread.?;
            const gui_thread = current_thread.process.createThread(desktopThread, 16384, heap.allocator) catch |err| {
                term.print("Failed to create GUI thread: {s}\n", .{@errorName(err)});
                return;
            };
            serial.print("[SHELL] Enqueueing GUI thread (ID={})...\n", .{gui_thread.id});
            input.setMode(.GUI);
            term.suppressed = true;
            scheduler.global_scheduler.enqueue(gui_thread);
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

fn desktopThread() void {
    serial.print("[GUI] desktopThread entered\n", .{});
    x64.sti();
    desktop.start() catch |err| {
        serial.print("[GUI] Desktop failed: {s}\n", .{@errorName(err)});
    };
}
