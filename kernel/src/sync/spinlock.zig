//! Basic spinlock implementation for kernel synchronization.

const std = @import("std");
const atomic = std.atomic;

pub const Spinlock = struct {
    locked: atomic.Value(bool) = atomic.Value(bool).init(false),

    pub fn lock(self: *Spinlock) void {
        while (self.locked.swap(true, .acquire)) {
            // Spin until the lock is released.
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Spinlock) void {
        self.locked.store(false, .release);
    }

    pub fn isLocked(self: *Spinlock) bool {
        return self.locked.load(.acquire);
    }
};
