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

    /// Creates a new thread within the process.
    pub fn createThread(self: *Process, entry: *const fn () void, stack_size: usize, allocator: std.mem.Allocator) !*Thread {
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

        // Push a dummy return address (threadExit)
        sp -= 1;
        sp[0] = @intFromPtr(&threadExit);

        // Push RIP (entry point)
        sp -= 1;
        sp[0] = @intFromPtr(entry);

        // Push dummy values for callee-saved registers (r15, r14, r13, r12, rbx, rbp)
        var j: usize = 0;
        while (j < 6) : (j += 1) {
            sp -= 1;
            sp[0] = 0;
        }

        thread.context.rsp = @intFromPtr(sp);

        self.threads[self.thread_count] = thread;
        self.thread_count += 1;
        return thread;
    }
};

/// Function that threads "return" to if they exit.
fn threadExit() noreturn {
    const x64 = @import("../cpu/x64.zig");
    x64.hang();
}
