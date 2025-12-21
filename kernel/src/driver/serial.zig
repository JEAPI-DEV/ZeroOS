//! Basic serial driver for Zen OS.

const x64 = @import("../cpu/x64.zig");

const COM1 = 0x3F8;

pub fn init() void {
    x64.outb(COM1 + 1, 0x00); // Disable all interrupts
    x64.outb(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
    x64.outb(COM1 + 0, 0x03); // Set divisor to 3 (38400 baud)
    x64.outb(COM1 + 1, 0x00);
    x64.outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
    x64.outb(COM1 + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
    x64.outb(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

fn isTransmitEmpty() bool {
    return (x64.inb(COM1 + 5) & 0x20) != 0;
}

pub fn writeByte(byte: u8) void {
    while (!isTransmitEmpty()) {}
    x64.outb(COM1, byte);
}

pub fn writeString(string: []const u8) void {
    for (string) |byte| {
        writeByte(byte);
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const slice = @import("std").fmt.bufPrint(&buf, fmt, args) catch return;
    writeString(slice);
}
