//! Basic Round Robin scheduler for Zen OS.

const std = @import("std");
const process = @import("process.zig");
const spinlock = @import("../sync/spinlock.zig");
const x64 = @import("../cpu/x64.zig");

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

    // Static pool of nodes to avoid heap allocations during scheduling.
    nodes: [64]ThreadQueue.Node = undefined,

    pub fn init() Scheduler {
        var self = Scheduler{};
        for (&self.nodes) |*node| {
            node.* = .{
                .data = undefined,
                .in_use = false,
            };
        }
        return self;
    }

    fn allocNode(self: *Scheduler) *ThreadQueue.Node {
        for (&self.nodes) |*node| {
            if (!node.in_use) {
                node.in_use = true;
                return node;
            }
        }
        @panic("Scheduler out of nodes");
    }

    fn freeNode(self: *Scheduler, node: *ThreadQueue.Node) void {
        _ = self;
        node.in_use = false;
    }

    /// Adds a thread to the ready queue.
    pub fn enqueue(self: *Scheduler, thread: *process.Thread) void {
        self.lock.lock();
        defer self.lock.unlock();

        thread.state = .READY;
        const node = self.allocNode();
        node.data = thread;
        self.ready_queue.append(node);
    }

    /// Picks the next thread to run and switches to it.
    pub fn schedule(self: *Scheduler) void {
        const serial = @import("../driver/serial.zig");

        // Disable interrupts during scheduling
        asm volatile ("cli");

        self.lock.lock();

        const next_node = self.ready_queue.popFirst();
        if (next_node) |node| {
            const next_thread = node.data;
            self.freeNode(node);

            const old_thread = self.current_thread;
            self.current_thread = next_thread;
            next_thread.state = .RUNNING;

            if (old_thread) |old| {
                if (old.state == .RUNNING) {
                    old.state = .READY;
                    // Re-enqueue the old thread
                    const old_node = self.allocNode();
                    old_node.data = old;
                    self.ready_queue.append(old_node);
                }

                serial.print("[SCHED] {} -> {}\n", .{ old.id, next_thread.id });
                self.lock.unlock();
                switchContext(&old.context, &next_thread.context);
                // Re-enable interrupts after switching back
                asm volatile ("sti");
            } else {
                // First thread ever
                serial.print("[SCHED] Start {}\n", .{next_thread.id});
                self.lock.unlock();
                asm volatile ("sti");
            }
        } else {
            self.lock.unlock();
            asm volatile ("sti");
        }
    }

    /// Yields the CPU to the next thread.
    pub fn yield(self: *Scheduler) void {
        self.schedule();
    }
};

pub var global_scheduler: Scheduler = undefined;
