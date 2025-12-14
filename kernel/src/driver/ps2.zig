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

/// Keyboard interrupt handler.
fn keyboardHandler(ctx: *isr.InterruptStack) callconv(.c) void {
    _ = ctx;

    // Read the scancode.
    const scancode = x64.inb(DATA_PORT);

    // Send End of Interrupt (EOI) to the PIC.
    // We must send this regardless of whether we process the key or not.
    defer pic.sendEOI(KEYBOARD_IRQ);

    // If the top bit is set, it's a key release.
    if ((scancode & 0x80) != 0) {
        return;
    }

    // Convert to ASCII.
    if (scancode < scancode_set1.len) {
        const char = scancode_set1[scancode];
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
