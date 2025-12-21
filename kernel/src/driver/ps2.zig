//! PS/2 Controller and Keyboard driver.

const driver = @import("driver.zig");
const isr = @import("../interrupt/isr.zig");
const pic = @import("pic.zig");
const term = @import("../term/terminal.zig");
const x64 = @import("../cpu/x64.zig");

/// The PS/2 driver instance.
pub const ps2_driver = driver.Driver{
    .name = "PS/2 Controller",
    .init = init,
};

/// Data port.
const DATA_PORT = 0x60;
/// Status port.
const STATUS_PORT = 0x64;
/// Command port.
const COMMAND_PORT = 0x64;

/// Keyboard interrupt vector.
const KEYBOARD_IRQ = 1;
const KEYBOARD_VECTOR = 0x21; // Remapped IRQ 1

/// Scancode set 1 mapping.
const scancode_set1 = [_]u8{
    0,    27,  '1', '2', '3', '4', '5', '6', '7', '8', '9',  '0', '-', '=',  '\x08',
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p',  '[', ']', '\n', 0,
    'a',  's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,   '\\', 'z',
    'x',  'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,   '*',  0,   ' ',
};

/// Keyboard buffer size.
const BUFFER_SIZE = 128;

/// Circular buffer for keyboard input.
var buffer: [BUFFER_SIZE]u8 = undefined;
var write_index: usize = 0;
var read_index: usize = 0;
var count: usize = 0;

/// Initializes the PS/2 controller and keyboard.
fn init() void {
    // Register the keyboard interrupt handler.
    isr.registerHandler(KEYBOARD_VECTOR, keyboardHandler);

    // Enable the keyboard port.
    // We assume the PS/2 controller is already in a somewhat sane state from BIOS/UEFI.
    // A full initialization sequence would be more robust but complex.

    // Flush the output buffer.
    while ((x64.inb(STATUS_PORT) & 1) != 0) {
        _ = x64.inb(DATA_PORT);
    }
}

/// Returns the next character from the keyboard buffer.
/// This function blocks until a character is available.
pub fn getKey() u8 {
    // Wait for data.
    while (count == 0) {
        x64.ioWait();
        asm volatile ("hlt");
    }

    // Disable interrupts to ensure atomicity.
    asm volatile ("cli");

    const char = buffer[read_index];
    read_index = (read_index + 1) % BUFFER_SIZE;
    count -= 1;

    // Re-enable interrupts.
    asm volatile ("sti");

    return char;
}

/// Handles a byte from the keyboard.
fn handleKeyboardByte(byte: u8) void {
    // If the top bit is set, it's a key release.
    if ((byte & 0x80) != 0) {
        return;
    }

    // Convert to ASCII.
    if (byte < scancode_set1.len) {
        const char = scancode_set1[byte];
        if (char != 0) {
            // Push to buffer if not full.
            if (count < BUFFER_SIZE) {
                buffer[write_index] = char;
                write_index = (write_index + 1) % BUFFER_SIZE;
                count += 1;
            }
        }
    }
}

/// Handles a byte from the mouse.
fn handleMouseByte(byte: u8) void {
    mouse_byte[mouse_cycle] = byte;
    mouse_cycle += 1;

    if (mouse_cycle == 3) {
        mouse_cycle = 0;

        const flags = mouse_byte[0];
        const x_mov = @as(i8, @bitCast(mouse_byte[1]));
        const y_mov = @as(i8, @bitCast(mouse_byte[2]));
        _ = x_mov;
        _ = y_mov;

        // Let's print only on click to avoid spamming.
        if ((flags & 1) != 0) {
            term.print("Left Click\n", .{});
        }
        if ((flags & 2) != 0) {
            term.print("Right Click\n", .{});
        }
    }
}

/// Keyboard interrupt handler.
fn keyboardHandler(ctx: *isr.InterruptStack) callconv(.c) void {
    _ = ctx;

    // Send End of Interrupt (EOI) to the PIC.
    defer pic.sendEOI(KEYBOARD_IRQ);

    // ALWAYS read the data port to drain the 8042 buffer
    // This is critical - if we don't read it, the controller locks up
    const data = x64.inb(DATA_PORT);

    // Now check status to see what kind of data it was
    const status = x64.inb(STATUS_PORT);

    // Dispatch based on whether it was mouse data (bit 5)
    if ((status & 0x20) != 0) {
        handleMouseByte(data);
    } else {
        handleKeyboardByte(data);
    }
}

/// Mouse interrupt vector.
const MOUSE_IRQ = 12;
const MOUSE_VECTOR = 0x2C; // Remapped IRQ 12

/// Mouse packet state.
var mouse_cycle: u8 = 0;
var mouse_byte: [3]u8 = undefined;

/// Initializes the mouse.
pub fn initMouse() void {
    term.print("Initializing Mouse...\n", .{});
    // Register the mouse interrupt handler.
    isr.registerHandler(MOUSE_VECTOR, mouseHandler);

    // Enable the auxiliary device (mouse).
    mouseWait(1);
    x64.outb(COMMAND_PORT, 0xA8);

    // Enable the interrupts.
    mouseWait(1);
    x64.outb(COMMAND_PORT, 0x20); // Get Compaq Status Byte
    mouseWait(0);
    var status = x64.inb(DATA_PORT);
    status |= 1; // Enable IRQ 1 (Keyboard)
    status |= 2; // Enable IRQ 12 (Mouse)
    status &= ~@as(u8, 0x20); // Disable Mouse Clock
    mouseWait(1);
    x64.outb(COMMAND_PORT, 0x60); // Set Compaq Status Byte
    mouseWait(1);
    x64.outb(DATA_PORT, status);

    // Use default settings.
    mouseWrite(0xF6);
    _ = mouseRead(); // Acknowledge

    // Enable streaming.
    mouseWrite(0xF4);
    _ = mouseRead(); // Acknowledge
    term.print("Mouse Initialized.\n", .{});
}

/// Waits for the PS/2 controller to be ready.
/// type: 0 for data, 1 for signal.
fn mouseWait(wait_type: u8) void {
    var time_out: u32 = 100000;
    if (wait_type == 0) {
        while (time_out > 0) : (time_out -= 1) {
            if ((x64.inb(STATUS_PORT) & 1) == 1) {
                return;
            }
        }
    } else {
        while (time_out > 0) : (time_out -= 1) {
            if ((x64.inb(STATUS_PORT) & 2) == 0) {
                return;
            }
        }
    }
}

/// Writes a byte to the mouse.
fn mouseWrite(value: u8) void {
    mouseWait(1);
    x64.outb(COMMAND_PORT, 0xD4); // Tell the controller we want to send data to the mouse
    mouseWait(1);
    x64.outb(DATA_PORT, value);
}

/// Reads a byte from the mouse.
fn mouseRead() u8 {
    mouseWait(0);
    return x64.inb(DATA_PORT);
}

/// Mouse interrupt handler.
fn mouseHandler(ctx: *isr.InterruptStack) callconv(.c) void {
    _ = ctx;

    // Send EOI.
    defer pic.sendEOI(MOUSE_IRQ);

    // ALWAYS read the data port to drain the 8042 buffer
    // This is critical - if we don't read it, the controller locks up
    const data = x64.inb(DATA_PORT);

    // Now check status to see what kind of data it was
    const status = x64.inb(STATUS_PORT);

    // Dispatch based on whether it was mouse data (bit 5)
    if ((status & 0x20) != 0) {
        handleMouseByte(data);
    } else {
        handleKeyboardByte(data);
    }
}
