//! Manages input routing between console and GUI.

const ps2 = @import("./ps2.zig");

pub const InputMode = enum {
    CONSOLE,
    GUI,
};

pub var mode: InputMode = .CONSOLE;

pub fn setMode(new_mode: InputMode) void {
    mode = new_mode;
}

pub fn getKey() u8 {
    if (mode == .GUI) {
        // In GUI mode, keyboard input should be handled by the window manager.
        // For now, we just block the shell from receiving keys.
        return 0;
    }
    return ps2.getKey();
}

pub fn getMouseDelta() struct { dx: i32, dy: i32, buttons: u8 } {
    if (mode == .CONSOLE) {
        return .{ .dx = 0, .dy = 0, .buttons = 0 };
    }
    return ps2.getMouseDelta();
}
