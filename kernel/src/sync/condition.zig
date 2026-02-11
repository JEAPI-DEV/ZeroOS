//! Condition Variable implementation.

const std = @import("std");
const process = @import("../proc/process.zig");
const scheduler = @import("../proc/scheduler.zig");
const spinlock = @import("spinlock.zig");
const mutex = @import("mutex.zig");

/// A condition variable for thread synchronization.
pub const Condition = struct {
    // Internal spinlock to protect the wait queue.
    internal_lock: spinlock.Spinlock = .{},
    // Queue of waiting threads.
    wait_head: ?*process.Thread = null,
    wait_tail: ?*process.Thread = null,

    /// Atomically releases the mutex and waits on this condition.
    /// Re-acquires the mutex before returning.
    pub fn wait(self: *Condition, m: *mutex.Mutex) void {
        const current_thread = scheduler.instance.current_thread orelse return;

        self.internal_lock.lock();

        // Add to wait queue.
        current_thread.next_waiter = null;
        if (self.wait_tail) |tail| {
            tail.next_waiter = current_thread;
        } else {
            self.wait_head = current_thread;
        }
        self.wait_tail = current_thread;

        // Mark as blocked.
        // We hold internal_lock, so notify() cannot run yet.
        current_thread.state = .BLOCKED;

        self.internal_lock.unlock();

        // Release the mutex.
        m.unlock();

        // Block and switch to next thread.
        scheduler.instance.schedule();

        // We have been woken up. Re-acquire the mutex.
        m.lock();
    }

    /// Wakes up one waiting thread.
    pub fn notify(self: *Condition) void {
        self.internal_lock.lock();
        defer self.internal_lock.unlock();

        if (self.wait_head) |thread| {
            // Remove from queue.
            self.wait_head = thread.next_waiter;
            if (self.wait_head == null) {
                self.wait_tail = null;
            }
            thread.next_waiter = null;

            // Wake up.
            scheduler.instance.wake(thread);
        }
    }

    /// Wakes up all waiting threads.
    pub fn notifyAll(self: *Condition) void {
        self.internal_lock.lock();
        defer self.internal_lock.unlock();

        var iter = self.wait_head;
        while (iter) |thread| {
            const next = thread.next_waiter;

            // Wake up.
            scheduler.instance.wake(thread);
            thread.next_waiter = null;

            iter = next;
        }

        self.wait_head = null;
        self.wait_tail = null;
    }
};
