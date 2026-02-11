//! Thread and Process structures for Zen OS.

const std = @import("std");
const spinlock = @import("../sync/spinlock.zig");
const phys = @import("../memory/phys.zig");
const virt = @import("../memory/virt.zig");

/// Possible states for a thread.
pub const ThreadState = enum {
    READY,
    RUNNING,
    BLOCKED,
    TERMINATED,
};

/// Represents a single unit of execution.
pub const Thread = struct {
    id: usize,
    state: ThreadState,
    stack_pointer: usize,
    process: *Process,

    // Context saved during context switch
    context: Context = .{},

    /// Next thread in a wait queue (Mutex/Condition).
    next_waiter: ?*Thread = null,

    /// Saved register state for context switching.
    pub const Context = struct {
        rsp: u64 = 0,
    };
};

/// Represents a container for resources.
pub const Process = struct {
    id: usize,
    name: []const u8,
    threads: [16]*Thread = undefined,
    thread_count: usize = 0,
    lock: spinlock.Spinlock = .{},

    pub fn init(id: usize, name: []const u8, allocator: std.mem.Allocator) Process {
        _ = allocator;
        return .{
            .id = id,
            .name = name,
        };
    }

    pub fn deinit(self: *Process) void {
        _ = self;
    }

    extern fn thread_entry_stub() void;

    /// Creates a new thread within the process.
    pub fn createThread(self: *Process, entry: *const fn (?*anyopaque) void, arg: ?*anyopaque, stack_size: usize, allocator: std.mem.Allocator) !*Thread {
        if (self.thread_count >= self.threads.len) return error.TooManyThreads;

        const thread = try allocator.create(Thread);

        // Allocate stack from physical memory directly to avoid heap issues.
        // We assume stack_size is a multiple of PAGE_SIZE.
        const num_pages = (stack_size + phys.PAGE_SIZE - 1) / phys.PAGE_SIZE;
        const stack_base = virt.higherHalf(512 * phys.GIGABYTE + 0x1000000 + self.thread_count * 0x100000); // Arbitrary high address

        var i: usize = 0;
        while (i < num_pages) : (i += 1) {
            virt.mapAllocatePage(stack_base + i * phys.PAGE_SIZE, virt.WRITABLE);
        }

        thread.* = .{
            .id = self.thread_count,
            .state = .READY,
            .stack_pointer = stack_base + num_pages * phys.PAGE_SIZE,
            .process = self,
        };

        // Set up the initial stack to look like a saved context.
        var sp = @as([*]u64, @ptrFromInt(thread.stack_pointer));

        // Push RIP (entry point stub)
        sp -= 1;
        sp[0] = @intFromPtr(&thread_entry_stub);

        // Push RBP
        sp -= 1;
        sp[0] = 0;

        // Push RBX (Thread Function)
        sp -= 1;
        sp[0] = @intFromPtr(entry);

        // Push R12 (Argument)
        sp -= 1;
        sp[0] = if (arg) |a| @intFromPtr(a) else 0;

        // Push R13 (Exit Function)
        sp -= 1;
        sp[0] = @intFromPtr(&threadExit);

        // Push R14
        sp -= 1;
        sp[0] = 0;

        // Push R15
        sp -= 1;
        sp[0] = 0;

        thread.context.rsp = @intFromPtr(sp);

        self.threads[self.thread_count] = thread;
        self.thread_count += 1;
        return thread;
    }
};

/// Function that threads "return" to if they exit.
fn threadExit() noreturn {
    const scheduler = @import("scheduler.zig");
    const x64 = @import("../cpu/x64.zig");
    x64.sti(); // Ensure interrupts enabled
    while (true) {
        scheduler.instance.yield();
        x64.hlt();
    }
}
