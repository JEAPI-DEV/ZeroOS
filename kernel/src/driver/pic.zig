//! Programmable Interrupt Controller (PIC) driver.

const x64 = @import("../cpu/x64.zig");

/// Master PIC command port.
const PIC1_COMMAND = 0x20;
/// Master PIC data port.
const PIC1_DATA = 0x21;
/// Slave PIC command port.
const PIC2_COMMAND = 0xA0;
/// Slave PIC data port.
const PIC2_DATA = 0xA1;

/// Initialization Command Word 1.
const ICW1_INIT = 0x10;
const ICW1_ICW4 = 0x01;

/// Initialization Command Word 4.
const ICW4_8086 = 0x01;

/// Remaps the PIC interrupts.
///
/// Parameters:
///   offset1: Vector offset for the master PIC (IRQs 0-7).
///   offset2: Vector offset for the slave PIC (IRQs 8-15).
pub fn remap(offset1: u8, offset2: u8) void {
    // Save masks.
    const a1 = x64.inb(PIC1_DATA);
    const a2 = x64.inb(PIC2_DATA);

    // Start initialization sequence (in cascade mode).
    x64.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    x64.ioWait();
    x64.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    x64.ioWait();

    // Set vector offsets.
    x64.outb(PIC1_DATA, offset1);
    x64.ioWait();
    x64.outb(PIC2_DATA, offset2);
    x64.ioWait();

    // Tell Master PIC that there is a slave PIC at IRQ2 (0000 0100).
    x64.outb(PIC1_DATA, 4);
    x64.ioWait();
    // Tell Slave PIC its cascade identity (0000 0010).
    x64.outb(PIC2_DATA, 2);
    x64.ioWait();

    // Set mode (8086/88 mode).
    x64.outb(PIC1_DATA, ICW4_8086);
    x64.ioWait();
    x64.outb(PIC2_DATA, ICW4_8086);
    x64.ioWait();

    // Restore masks.
    x64.outb(PIC1_DATA, a1);
    x64.outb(PIC2_DATA, a2);
}

/// Disables the PIC.
pub fn disable() void {
    x64.outb(PIC1_DATA, 0xFF);
    x64.outb(PIC2_DATA, 0xFF);
}

/// Sends an End of Interrupt (EOI) signal to the PIC.
///
/// Parameters:
///   irq: The IRQ number.
pub fn sendEOI(irq: u8) void {
    if (irq >= 8) {
        x64.outb(PIC2_COMMAND, 0x20);
    }
    x64.outb(PIC1_COMMAND, 0x20);
}

/// Masks a specific IRQ.
pub fn mask(irq: u8) void {
    var port: u16 = undefined;
    var value: u8 = undefined;

    if (irq < 8) {
        port = PIC1_DATA;
        value = @intCast(irq);
    } else {
        port = PIC2_DATA;
        value = @intCast(irq - 8);
    }

    const mask_value = x64.inb(port) | (@as(u8, 1) << @intCast(value));
    x64.outb(port, mask_value);
}

/// Unmasks a specific IRQ.
pub fn unmask(irq: u8) void {
    var port: u16 = undefined;
    var value: u8 = undefined;

    if (irq < 8) {
        port = PIC1_DATA;
        value = @intCast(irq);
    } else {
        port = PIC2_DATA;
        value = @intCast(irq - 8);
    }

    const mask_value = x64.inb(port) & ~(@as(u8, 1) << @intCast(value));
    x64.outb(port, mask_value);
}
