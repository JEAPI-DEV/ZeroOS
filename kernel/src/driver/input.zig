const ps2 = @import("./ps2.zig");
const scheduler = @import("../proc/scheduler.zig");

pub const InputMode = enum {
    CONSOLE,
    GUI,
};

pub var mode: InputMode = .CONSOLE;

/// Keyboard buffer size.
const BUFFER_SIZE = 128;

/// Circular buffer for keyboard input.
var key_buffer: [BUFFER_SIZE]u8 = undefined;
var write_index: usize = 0;
var read_index: usize = 0;
var key_count: usize = 0;

/// Mouse state.
var mouse_dx: i32 = 0;
var mouse_dy: i32 = 0;
var mouse_buttons: u8 = 0;

pub fn setMode(new_mode: InputMode) void {
    mode = new_mode;
}

pub fn pushKey(char: u8) void {
    if (key_count < BUFFER_SIZE) {
        key_buffer[write_index] = char;
        write_index = (write_index + 1) % BUFFER_SIZE;
        key_count += 1;
    }
}

pub fn getKey() u8 {
    if (mode == .GUI) return 0;

    // Wait for data.
    if (key_count == 0) return 0;

    // Disable interrupts to ensure atomicity.
    asm volatile ("cli");

    const char = key_buffer[read_index];
    read_index = (read_index + 1) % BUFFER_SIZE;
    key_count -= 1;

    // Re-enable interrupts.
    asm volatile ("sti");

    return char;
}

pub fn getGuiKey() u8 {
    if (mode == .CONSOLE) return 0;

    if (key_count == 0) return 0;

    asm volatile ("cli");
    const char = key_buffer[read_index];
    read_index = (read_index + 1) % BUFFER_SIZE;
    key_count -= 1;
    asm volatile ("sti");

    return char;
}

pub fn updateMouse(dx: i32, dy: i32, buttons: u8) void {
    mouse_dx += dx;
    mouse_dy += dy;
    mouse_buttons = buttons;
}

pub fn getMouseDelta(dx: *i32, dy: *i32, buttons: *u8) void {
    asm volatile ("cli");
    dx.* = mouse_dx;
    dy.* = mouse_dy;
    buttons.* = mouse_buttons;
    mouse_dx = 0;
    mouse_dy = 0;
    asm volatile ("sti");
}
