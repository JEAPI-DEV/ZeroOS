//! Kernel's entry point.
//! This is where we get the ball rolling.

const limine = @import("limine");
const std = @import("std");

const gdt = @import("./cpu/gdt.zig");
const heap = @import("./memory/heap.zig");
const idt = @import("./interrupt/idt.zig");
const phys = @import("./memory/phys.zig");
const term = @import("./term/terminal.zig");
const virt = @import("./memory/virt.zig");
const x64 = @import("./cpu/x64.zig");

const driver = @import("./driver/driver.zig");
const ps2 = @import("./driver/ps2.zig");
const shell = @import("./term/shell.zig");

const MEGABYTE = phys.MEGABYTE;

/// Current version of the Zero kernel.
const Zero_VERSION = "0.0.2";

/// Base revision of the Limine protocol that the kernel supports.
pub export var base_revision: limine.BaseRevision linksection(".limine_requests") = .{
    .revision = 3,
};

/// Kernel's global panic handler.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // TODO(2): Support stack traces.
    term.panic("{s}", .{msg});
}

/// Kernel's entry point.
export fn _start() callconv(.c) noreturn {
    // Do not proceed if the kernel's base revision is not supported by the bootloader.
    if (!base_revision.is_supported()) {
        x64.hang();
    }

    // Initialize the terminal.
    term.initialize();
    term.print("Welcome to ", .{});
    term.colorPrint(.blue, "Zero v{s}.\n\n", .{Zero_VERSION});

    // Initialize the rest of the system.
    gdt.initialize();
    idt.initialize();
    phys.initialize();
    virt.initialize();
    heap.initialize(4 * MEGABYTE);

    // Initialize drivers.
    const pic = @import("./driver/pic.zig");
    // Remap PIC to 0x20-0x27 and 0x28-0x2F.
    term.print("Remapping PIC...\n", .{});
    pic.remap(0x20, 0x28);
    // Unmask Keyboard IRQ (IRQ 1).
    term.print("Unmasking IRQ 1...\n", .{});
    pic.unmask(1);
    // Unmask Mouse IRQ (IRQ 12).
    term.print("Unmasking IRQ 12...\n", .{});
    pic.unmask(12);

    driver.DriverManager.register(ps2.ps2_driver);
    driver.DriverManager.initialize();

    // Initialize Mouse.
    ps2.initMouse();

    // Enable interrupts.
    term.print("Enabling Interrupts...\n", .{});
    x64.sti();

    // Initialize and run the shell.
    var shell_instance = shell.Shell.init();
    shell_instance.run();

    // Loop forever (unreachable).
    x64.hang();
}
