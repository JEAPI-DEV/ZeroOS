//! Low-level x86_64-specific functions.

const gdt = @import("./gdt.zig");

/// Structure for the IDT and GDT registers.
pub const SystemTableRegister = packed struct {
    limit: u16,
    base: u64,
};

/// Completely stops the CPU.
pub inline fn hang() noreturn {
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}

/// Enables interrupts.
pub inline fn sti() void {
    asm volatile ("sti");
}

/// Loads a new Interrupt Descriptor Table.
///
/// Parameters:
///   idtr: Pointer to a IDT Register structure.
pub inline fn lidt(idtr: SystemTableRegister) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (&idtr),
    );
}

/// Loads a new Global Descriptor Table.
///
/// Parameters:
///   gdtr: Pointer to a GDT Register structure.
pub inline fn lgdt(gdtr: SystemTableRegister) void {
    asm volatile ("lgdt (%[gdtr])"
        :
        : [gdtr] "r" (&gdtr),
    );
}

/// Loads a new Task Register.
///
/// Parameters:
///   selector: The segment selector of the TSS.
pub inline fn ltr(selector: gdt.SegmentSelector) void {
    asm volatile ("ltr %[selector]"
        :
        : [selector] "r" (@intFromEnum(selector)),
    );
}

/// Reads from the RSP register.
///
/// Returns:
///   Value of the RSP register.
pub inline fn readRsp() u64 {
    var value: u64 = undefined;
    asm volatile ("mov %rsp, %[value]"
        : [value] "=r" (value),
    );
    return value;
}

/// Reads from the CR2 register.
///
/// Returns:
///   Value of the CR2 register.
pub inline fn readCr2() u64 {
    var value: u64 = undefined;
    asm volatile ("mov %cr2, %[value]"
        : [value] "=r" (value),
    );
    return value;
}

/// Reads from the CR3 register.
///
/// Returns:
///   Value of the CR3 register.
pub inline fn readCr3() u64 {
    var value: u64 = undefined;
    asm volatile ("mov %cr3, %[value]"
        : [value] "=r" (value),
    );
    return value;
}

/// Writes to the CR3 register.
///
/// Parameters:
///   value: Value to write to the CR3 register.
pub inline fn writeCr3(value: u64) void {
    asm volatile ("mov %[value], %cr3"
        :
        : [value] "r" (value),
    );
}

/// Invalidates the TLB entries associated with the given virtual address.
///
/// Parameters:
///   address: Virtual address to invalidate.
pub inline fn invlpg(address: usize) void {
    asm volatile ("invlpg (%[address])"
        :
        : [address] "r" (address),
        : .{ .memory = true });
}

/// Writes a byte to the specified port.
///
/// Parameters:
///   port:  The port to write to.
///   value: The value to write.
pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

/// Writes a word (16 bits) to the specified port.
///
/// Parameters:
///   port:  The port to write to.
///   value: The value to write.
pub inline fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "{dx}" (port),
    );
}

/// Reads a byte from the specified port.
///
/// Parameters:
///   port: The port to read from.
///
/// Returns:
///   The value read from the port.
pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[value]"
        : [value] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

/// Waits for a very small amount of time (1 to 4 microseconds).
/// Useful for I/O operations that require a small delay.
pub inline fn ioWait() void {
    outb(0x80, 0);
}
