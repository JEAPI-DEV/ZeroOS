//! Basic Round Robin scheduler for Zen OS.

const std = @import("std");
const process = @import("process.zig");
const spinlock = @import("../sync/spinlock.zig");
const x64 = @import("../cpu/x64.zig");
const serial = @import("../driver/serial.zig");
const heap = @import("../memory/heap.zig");

extern fn switchContext(old: *process.Thread.Context, new: *process.Thread.Context) void;

pub const ThreadQueue = struct {
    pub const Node = struct {
        data: *process.Thread,
        next: ?*Node = null,
        prev: ?*Node = null,
        in_use: bool = false,
    };

    head: ?*Node = null,
    tail: ?*Node = null,

    pub fn append(self: *ThreadQueue, node: *Node) void {
        node.next = null;
        node.prev = self.tail;
        if (self.tail) |t| {
            t.next = node;
        } else {
            self.head = node;
        }
        self.tail = node;
    }

    pub fn popFirst(self: *ThreadQueue) ?*Node {
        const node = self.head orelse return null;
        self.head = node.next;
        if (self.head) |h| {
            h.prev = null;
        } else {
            self.tail = null;
        }
        return node;
    }
};

pub const Scheduler = struct {
    current_thread: ?*process.Thread = null,
    ready_queue: ThreadQueue = .{},
    lock: spinlock.Spinlock = .{},
    thread_count: usize = 0,

    pub fn init() *Scheduler {
        instance = Scheduler{};
        return &instance;
    }

    fn allocNode(self: *Scheduler) *ThreadQueue.Node {
        _ = self;
        return heap.allocator.create(ThreadQueue.Node) catch @panic("Scheduler out of memory");
    }

    fn freeNode(self: *Scheduler, node: *ThreadQueue.Node) void {
        _ = self;
        heap.allocator.destroy(node);
    }

    /// Adds a thread to the ready queue.
    pub fn enqueue(self: *Scheduler, thread: *process.Thread) void {
        self.lock.lock();
        defer self.lock.unlock();

        self.thread_count += 1;
        serial.print("[SCHED] Enqueue thread {} (Total: {})\n", .{ thread.id, self.thread_count });

        thread.state = .READY;
        const node = self.allocNode();
        node.data = thread;
        self.ready_queue.append(node);
    }

    /// Picks the next thread to run and switches to it.
    pub fn schedule(self: *Scheduler) void {
        // Disable interrupts during scheduling to ensure atomicity
        const flags = x64.saveAndDisableInterrupts();
        defer x64.restoreInterrupts(flags);

        self.lock.lock();

        const next_node = self.ready_queue.popFirst();
        if (next_node) |node| {
            const next_thread = node.data;
            self.freeNode(node);

            // serial.print("[SCHED] Switch {} -> {}\n", .{ if (self.current_thread) |t| t.id else 999, next_thread.id });

            const old_thread = self.current_thread;
            self.current_thread = next_thread;
            next_thread.state = .RUNNING;

            if (old_thread) |old| {
                if (old.state == .RUNNING or old.state == .READY) {
                    old.state = .READY;
                    // Re-enqueue the old thread
                    const old_node = self.allocNode();
                    old_node.data = old;
                    self.ready_queue.append(old_node);
                }

                self.lock.unlock();
                switchContext(&old.context, &next_thread.context);
            } else {
                // First thread ever
                self.lock.unlock();
            }
        } else {
            // serial.print("[SCHED] Idle\n", .{});
            self.lock.unlock();
        }
    }

    /// Called by the timer interrupt.
    pub fn tick(self: *Scheduler) void {
        // For now, just yield on every tick to verify preemption.
        // In a real OS, we would check a time slice.
        self.schedule();
    }

    /// Yields the CPU to the next thread.
    pub fn yield(self: *Scheduler) void {
        self.schedule();
    }

    /// Blocks the current thread and switches to the next one.
    /// The thread must be woken up by another thread calling `wake()`.
    pub fn block(self: *Scheduler) void {
        const flags = x64.saveAndDisableInterrupts();
        defer x64.restoreInterrupts(flags);

        if (self.current_thread) |thread| {
            thread.state = .BLOCKED;
        }
        self.schedule();
    }

    /// Wakes up a thread, adding it to the ready queue.
    pub fn wake(self: *Scheduler, thread: *process.Thread) void {
        const flags = x64.saveAndDisableInterrupts();
        defer x64.restoreInterrupts(flags);

        self.lock.lock();
        defer self.lock.unlock();

        if (thread.state == .BLOCKED) {
            thread.state = .READY;
            const node = self.allocNode();
            node.data = thread;
            self.ready_queue.append(node);
        }
    }
};

pub var instance: Scheduler = undefined;
