//! Programmable Interval Timer (PIT) driver for Zen OS.

const x64 = @import("../cpu/x64.zig");
const serial = @import("./serial.zig");

const PIT_COMMAND = 0x43;
const PIT_CHANNEL0 = 0x40;

/// Initializes the PIT to trigger at the given frequency.
///
/// Parameters:
///   frequency: Target frequency in Hz.
pub fn init(frequency: u32) void {
    const divisor = 1193182 / frequency;

    // Command byte: Channel 0, Access mode: lobyte/hibyte, Operating mode: Rate Generator, Binary mode.
    x64.outb(PIT_COMMAND, 0x34);

    // Set divisor.
    x64.outb(PIT_CHANNEL0, @as(u8, @truncate(divisor & 0xFF)));
    x64.outb(PIT_CHANNEL0, @as(u8, @truncate((divisor >> 8) & 0xFF)));
}

/// PIT interrupt handler.
pub fn handleInterrupt(stack: *@import("../interrupt/isr.zig").InterruptStack) callconv(.c) void {
    _ = stack;
    const pic = @import("./pic.zig");
    const scheduler = @import("../proc/scheduler.zig");

    pic.sendEOI(0);
    scheduler.global_scheduler.tick();
}
