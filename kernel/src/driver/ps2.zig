//! PS/2 Controller and Keyboard driver.

const driver = @import("driver.zig");
const isr = @import("../interrupt/isr.zig");
const pic = @import("pic.zig");
const term = @import("../term/terminal.zig");
const x64 = @import("../cpu/x64.zig");
const serial = @import("serial.zig");

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

/// Global state to track if we have a second channel (mouse).
var has_dual_channel: bool = false;

/// Initializes the PS/2 controller and keyboard.
fn init() void {
    term.print("Initializing PS/2 Controller...\n", .{});

    // 1. Disable Devices
    sendCmd(0xAD); // Disable Port 1
    sendCmd(0xA7); // Disable Port 2

    // 2. Flush The Output Buffer
    flushBuffer();

    // 3. Set the Controller Configuration Byte
    sendCmd(0x20); // Read Config
    var config = readData();
    config &= ~@as(u8, 0x03); // Disable IRQs (bits 0 and 1)
    config |= @as(u8, 0x40); // Enable Translation (bit 6)
    sendCmdArg(0x60, config); // Write Config

    // 4. Perform Controller Self Test
    sendCmd(0xAA);
    if (readData() != 0x55) {
        term.print("PS/2 Controller Self Test Failed!\n", .{});
        return;
    }

    // 5. Determine If There Are 2 Channels
    sendCmd(0xA8); // Enable Port 2
    sendCmd(0x20); // Read Config
    config = readData();
    if ((config & 0x20) != 0) {
        has_dual_channel = false;
        term.print("PS/2 Controller is Single Channel.\n", .{});
    } else {
        has_dual_channel = true;
        term.print("PS/2 Controller is Dual Channel.\n", .{});
        // Disable Port 2 again
        sendCmd(0xA7);
    }

    // 6. Perform Interface Tests
    sendCmd(0xAB); // Test Port 1
    if (readData() != 0x00) {
        term.print("PS/2 Port 1 Test Failed!\n", .{});
    }

    if (has_dual_channel) {
        sendCmd(0xA9); // Test Port 2
        if (readData() != 0x00) {
            term.print("PS/2 Port 2 Test Failed!\n", .{});
        }
    }

    // 7. Enable Devices
    sendCmd(0xAE); // Enable Port 1
    if (has_dual_channel) {
        sendCmd(0xA8); // Enable Port 2
    }

    // 8. Enable IRQs
    sendCmd(0x20); // Read Config
    config = readData();
    config |= 0x01; // Enable IRQ 1
    if (has_dual_channel) {
        config |= 0x02; // Enable IRQ 12
    }
    sendCmdArg(0x60, config);

    // 9. Reset Keyboard
    resetDevice(false);

    // 10. Enable Keyboard Scanning
    sendDataToDevice(false, 0xF4);
    _ = readData(); // Acknowledge

    // Register Keyboard Handler
    isr.registerHandler(KEYBOARD_VECTOR, keyboardHandler);
}

/// Mouse interrupt vector.
const MOUSE_IRQ = 12;
const MOUSE_VECTOR = 0x2C; // Remapped IRQ 12

/// Mouse packet state.
var mouse_cycle: u8 = 0;
var mouse_byte: [3]u8 = undefined;

/// Initializes the mouse.
pub fn initMouse() void {
    if (!has_dual_channel) {
        term.print("No Mouse Port detected.\n", .{});
        return;
    }

    term.print("Initializing Mouse...\n", .{});

    // Register Mouse Handler
    isr.registerHandler(MOUSE_VECTOR, mouseHandler);

    // Reset Mouse
    resetDevice(true);

    // Set Defaults
    sendDataToDevice(true, 0xF6);
    _ = readData(); // Acknowledge

    // Reset cycle state
    mouse_cycle = 0;

    // Enable Mouse Scanning
    sendDataToDevice(true, 0xF4);
    _ = readData(); // Acknowledge

    term.print("Mouse Initialized.\n", .{});
}

/// Waits for the write buffer to be empty.
fn waitWrite() void {
    var time_out: u32 = 100000;
    while (time_out > 0) : (time_out -= 1) {
        if ((x64.inb(STATUS_PORT) & 2) == 0) {
            return;
        }
    }
}

/// Waits for the read buffer to be full.
fn waitRead() void {
    var time_out: u32 = 100000;
    while (time_out > 0) : (time_out -= 1) {
        if ((x64.inb(STATUS_PORT) & 1) == 1) {
            return;
        }
    }
}

/// Sends a command to the PS/2 controller.
fn sendCmd(cmd: u8) void {
    waitWrite();
    x64.outb(COMMAND_PORT, cmd);
}

/// Sends a command with an argument to the PS/2 controller.
fn sendCmdArg(cmd: u8, arg: u8) void {
    waitWrite();
    x64.outb(COMMAND_PORT, cmd);
    waitWrite();
    x64.outb(DATA_PORT, arg);
}

/// Reads a byte from the data port.
fn readData() u8 {
    waitRead();
    return x64.inb(DATA_PORT);
}

/// Flushes the output buffer.
fn flushBuffer() void {
    while ((x64.inb(STATUS_PORT) & 1) != 0) {
        _ = x64.inb(DATA_PORT);
    }
}

/// Sends data to a device (Keyboard or Mouse).
fn sendDataToDevice(is_mouse: bool, data: u8) void {
    if (is_mouse) {
        sendCmd(0xD4);
    }
    waitWrite();
    x64.outb(DATA_PORT, data);
}

/// Resets a device.
fn resetDevice(is_mouse: bool) void {
    sendDataToDevice(is_mouse, 0xFF);
    const ack = readData();
    if (ack != 0xFA) {
        term.print("Device Reset failed (No ACK: {x})!\n", .{ack});
        return;
    }
    const res = readData();
    if (res != 0xAA) {
        term.print("Device Reset failed (Self-test failed: {x})!\n", .{res});
        return;
    }
    // Read the ID byte (0x00 for standard mouse/keyboard)
    const id = readData();
    _ = id;
}

/// Returns the next character from the keyboard buffer.
/// This function blocks until a character is available.
pub fn getKey() u8 {
    const scheduler = @import("../proc/scheduler.zig");
    // Wait for data.
    while (count == 0) {
        scheduler.global_scheduler.yield();
    }

    // Disable interrupts to ensure atomicity.
    asm volatile ("cli");

    const char = buffer[read_index];
    read_index = (read_index + 1) % BUFFER_SIZE;
    count -= 1;

    serial.print("[PS2] getKey: {c}\n", .{char});

    // Re-enable interrupts.
    asm volatile ("sti");

    return char;
}

/// Handles a byte from the keyboard.
fn handleKeyboardByte(byte: u8) void {
    serial.print("[PS2] handleKeyboardByte: {x}\n", .{byte});
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
    // Byte 0: Flags (Bit 3 must be 1)
    if (mouse_cycle == 0) {
        if ((byte & 0x08) == 0) {
            // Not a valid first byte, likely out of sync.
            return;
        }
    }

    mouse_byte[mouse_cycle] = byte;
    mouse_cycle += 1;

    if (mouse_cycle == 3) {
        mouse_cycle = 0;

        const flags = @as(u16, mouse_byte[0]);
        const x_raw = @as(u16, mouse_byte[1]);
        const y_raw = @as(u16, mouse_byte[2]);

        // 9-bit signed extension logic
        const x_mov = @as(i16, @intCast(x_raw)) - @as(i16, @intCast((flags << 4) & 0x100));
        const y_mov = @as(i16, @intCast(y_raw)) - @as(i16, @intCast((flags << 3) & 0x100));

        _ = x_mov;
        _ = y_mov;

        // Let's print only on click to avoid spamming.
        if ((flags & 1) != 0) {
            term.print("Left Click [Raw: {x} {x} {x}]\n", .{ mouse_byte[0], mouse_byte[1], mouse_byte[2] });
        }
        if ((flags & 2) != 0) {
            term.print("Right Click [Raw: {x} {x} {x}]\n", .{ mouse_byte[0], mouse_byte[1], mouse_byte[2] });
        }
    }
}

/// Common logic to drain the PS/2 controller buffer.
fn drainBuffer() void {
    while (true) {
        const status = x64.inb(STATUS_PORT);
        if ((status & 0x01) == 0) break; // Output buffer empty

        const data = x64.inb(DATA_PORT);
        if ((status & 0x20) != 0) {
            handleMouseByte(data);
        } else {
            handleKeyboardByte(data);
        }
    }
}

/// Keyboard interrupt handler.
fn keyboardHandler(ctx: *isr.InterruptStack) callconv(.c) void {
    _ = ctx;
    serial.print("[PS2] Keyboard IRQ\n", .{});
    drainBuffer();
    pic.sendEOI(KEYBOARD_IRQ);
}

/// Mouse interrupt handler.
fn mouseHandler(ctx: *isr.InterruptStack) callconv(.c) void {
    _ = ctx;
    serial.print("[PS2] Mouse IRQ\n", .{});
    drainBuffer();
    pic.sendEOI(MOUSE_IRQ);
}
