//! Blocking Mutex implementation.

const std = @import("std");
const process = @import("../proc/process.zig");
const scheduler = @import("../proc/scheduler.zig");
const spinlock = @import("spinlock.zig");

/// A mutual exclusion lock that blocks waiting threads.
pub const Mutex = struct {
    // Internal spinlock to protect the mutex state.
    internal_lock: spinlock.Spinlock = .{},
    // Whether the mutex is currently locked.
    is_locked: bool = false,
    // Queue of waiting threads.
    wait_head: ?*process.Thread = null,
    wait_tail: ?*process.Thread = null,
    // Owner thread (optional, for debugging/reentrancy checks).
    owner: ?*process.Thread = null,

    /// Acquires the lock. Blocks if the lock is already held.
    pub fn lock(self: *Mutex) void {
        const current_thread = scheduler.instance.current_thread orelse return; // Should not happen in kernel threads

        while (true) {
            self.internal_lock.lock();

            if (!self.is_locked) {
                // Lock is free, take it.
                self.is_locked = true;
                self.owner = current_thread;
                self.internal_lock.unlock();
                return;
            }

            // Lock is held, add to wait queue.
            current_thread.next_waiter = null;
            if (self.wait_tail) |tail| {
                tail.next_waiter = current_thread;
            } else {
                self.wait_head = current_thread;
            }
            self.wait_tail = current_thread;

            // Mark as blocked.
            // Race safety: We hold internal_lock, so unlock() cannot run yet.
            // So nobody can wake us yet.
            // Once we release internal_lock, unlock() might run and wake us (set READY).
            // That's fine, schedule() will see READY and re-enqueue us.
            current_thread.state = .BLOCKED;

            self.internal_lock.unlock();

            // Yield CPU.
            scheduler.instance.schedule();

            // After wakeup, loop again to retry acquiring lock.
        }
    }

    /// Releases the lock. Wakes up the next waiting thread.
    pub fn unlock(self: *Mutex) void {
        self.internal_lock.lock();
        defer self.internal_lock.unlock();

        if (!self.is_locked) {
            return;
        }

        // Pass ownership to next waiter, or release if none.
        if (self.wait_head) |next_thread| {
            // Wake up next thread.
            self.wait_head = next_thread.next_waiter;
            if (self.wait_head == null) {
                self.wait_tail = null;
            }

            // Release lock logically so standard Mesa semantics apply (woken thread retries).
            // This allows barging but is simpler.
            self.is_locked = false;
            self.owner = null;

            scheduler.instance.wake(next_thread);
        } else {
            self.is_locked = false;
            self.owner = null;
        }
    }
};
