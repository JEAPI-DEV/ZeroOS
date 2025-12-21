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
const serial = @import("./driver/serial.zig");
const proc = @import("./proc/process.zig");
const scheduler = @import("./proc/scheduler.zig");
const pit = @import("./driver/pit.zig");
const isr = @import("./interrupt/isr.zig");

const MEGABYTE = phys.MEGABYTE;

/// Current version of the Zero kernel.
const Zero_VERSION = "0.0.2";

/// Base revision of the Limine protocol that the kernel supports.
pub export var base_revision: limine.BaseRevision linksection(".limine_requests") = .{
    .revision = 3,
};

/// Kernel's global panic handler.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    serial.print("\n!!! KERNEL PANIC !!!\n{s}\n", .{msg});
    term.panic("{s}", .{msg});
}

var kernel_proc: proc.Process = undefined;

/// Kernel's entry point.
export fn _start() callconv(.c) noreturn {
    // Do not proceed if the kernel's base revision is not supported by the bootloader.
    if (!base_revision.is_supported()) {
        x64.hang();
    }

    // Initialize the terminal.
    term.initialize();

    // Initialize serial.
    serial.init();
    serial.print("Zero OS Serial Debug Console\n", .{});

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
    pic.remap(0x20, 0x28);
    pic.unmask(1);
    pic.unmask(12);
    pic.unmask(2);

    driver.DriverManager.register(ps2.ps2_driver);
    driver.DriverManager.initialize();
    ps2.initMouse();

    // Initialize PIT (100Hz).
    pit.init(100);
    isr.registerHandler(32, pit.handleInterrupt);
    pic.unmask(0);

    // Initialize scheduler.
    scheduler.global_scheduler = scheduler.Scheduler.init();

    // Create a kernel process.
    kernel_proc = proc.Process.init(0, "kernel", heap.allocator);

    // Create a shell thread.
    serial.print("Creating shell thread...\n", .{});
    const shell_thread = kernel_proc.createThread(shellThread, 32768, heap.allocator) catch unreachable;
    scheduler.global_scheduler.enqueue(shell_thread);

    // Create a test thread.
    serial.print("Creating test thread...\n", .{});
    const test_thread = kernel_proc.createThread(testThread, 16384, heap.allocator) catch unreachable;
    scheduler.global_scheduler.enqueue(test_thread);

    // Register the current execution as the first thread.
    const main_thread = heap.allocator.create(proc.Thread) catch unreachable;
    main_thread.* = .{
        .id = 1,
        .state = .RUNNING,
        .stack_pointer = 0,
        .process = &kernel_proc,
    };
    scheduler.global_scheduler.current_thread = main_thread;

    // Enable interrupts.
    serial.print("Enabling interrupts...\n", .{});
    x64.sti();

    // Start the scheduler.
    serial.print("Starting scheduler...\n", .{});
    while (true) {
        // The main thread just hangs out now, preemption will handle the rest.
        x64.ioWait();
        asm volatile ("hlt");
    }
}

fn shellThread() void {
    x64.sti();
    var s = shell.Shell.init();
    s.run();
}

fn testThread() void {
    x64.sti();
    while (true) {
        serial.print("[TEST] Heartbeat...\n", .{});
        // Large delay
        var i: usize = 0;
        while (i < 100000000) : (i += 1) {
            asm volatile ("nop");
        }
    }
}
