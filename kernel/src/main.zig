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
const symbol = @import("./debug/symbol.zig");

const driver = @import("./driver/driver.zig");
const ps2 = @import("./driver/ps2.zig");
const shell = @import("./term/shell.zig");
const serial = @import("./driver/serial.zig");
const proc = @import("./proc/process.zig");
const scheduler = @import("./proc/scheduler.zig");
const pit = @import("./driver/pit.zig");
const isr = @import("./interrupt/isr.zig");
const vfs = @import("./fs/vfs.zig");
const ramfs = @import("./fs/ramfs.zig");
const pci = @import("./driver/pci.zig");
const libc = @import("./libc/libc.zig");
const mutex = @import("./sync/mutex.zig");
const condition = @import("./sync/condition.zig");

comptime {
    _ = libc;
    _ = mutex;
    _ = condition;
}

const MEGABYTE = phys.MEGABYTE;

/// Current version of the Zero kernel.
const Zero_VERSION = "0.0.2";

/// Base revision of the Limine protocol that the kernel supports.
pub export var base_revision: limine.BaseRevision linksection(".limine_requests") = .{
    .revision = 3,
};

pub export var module_request: limine.ModuleRequest linksection(".limine_requests") = .{};

/// Kernel's global panic handler.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    serial.print("\n!!! KERNEL PANIC !!!\n{s}\n", .{msg});
    if (ret_addr) |addr| {
        serial.print("Return Address: 0x{x}", .{addr});
        if (symbol.lookup(addr)) |name| {
            serial.print(" ({s})", .{name});
        }
        serial.print("\n", .{});
    }

    serial.print("Stack Trace:\n", .{});
    var rbp = x64.readRbp();
    // Safely walk RBP
    var i: usize = 0;
    while (rbp != 0 and i < 16) : (i += 1) {
        // We need to be careful about accessing memory here, but we are in panic mode.
        // Assuming RBP points to valid stack.
        // Return address is at RBP + 8
        const ret_ptr = @as(*usize, @ptrFromInt(rbp + 8));
        const next_rbp_ptr = @as(*usize, @ptrFromInt(rbp));

        // Basic sanity check to avoid page faulting in panic handler
        if (rbp < 0xFFFF_8000_0000_0000) { // Kernel stack usually high
            // Actually stack might be anywhere depending on thread.
            // Just try.
        }

        serial.print("  [{d}] 0x{x}", .{ i, ret_ptr.* });
        if (symbol.lookup(ret_ptr.*)) |name| {
            serial.print(" ({s})", .{name});
        }
        serial.print("\n", .{});
        rbp = next_rbp_ptr.*;
    }

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
    heap.initialize(32 * MEGABYTE);

    // Initialize symbol table
    if (module_request.response) |response| {
        symbol.init(response);
    }

    // Initialize VFS and mount RAMFS.
    const root_fs = ramfs.createFileSystem(heap.allocator, "root") catch unreachable;
    vfs.mount(root_fs);

    // Initialize drivers.
    @import("./driver/storage.zig").init(heap.allocator);
    const pic = @import("./driver/pic.zig");
    pic.remap(0x20, 0x28);
    pic.unmask(1);
    pic.unmask(12);
    pic.unmask(2);

    driver.DriverManager.register(ps2.ps2_driver);
    driver.DriverManager.register(pci.pci_driver);
    driver.DriverManager.initialize();
    ps2.initMouse();

    // Initialize PIT (100Hz).
    pit.init(100);
    isr.registerHandler(32, pit.handleInterrupt);
    pic.unmask(0);

    // Initialize the scheduler.
    const sched = scheduler.Scheduler.init();

    // Create a kernel process.
    kernel_proc = proc.Process.init(0, "kernel", heap.allocator);

    // Create a shell thread.
    serial.print("Creating shell thread...\n", .{});
    const shell_thread = kernel_proc.createThread(shellThread, null, 32768, heap.allocator) catch unreachable;
    sched.enqueue(shell_thread);

    // // Create a test thread.
    // serial.print("Creating test thread...\n", .{});
    // const test_thread = kernel_proc.createThread(testThread, 16384, heap.allocator) catch unreachable;
    // scheduler.global_scheduler.enqueue(test_thread);

    // Register the current execution as the first thread.
    const main_thread = heap.allocator.create(proc.Thread) catch unreachable;
    main_thread.* = .{
        .id = 999,
        .state = .RUNNING,
        .stack_pointer = 0,
        .process = &kernel_proc,
    };
    sched.current_thread = main_thread;

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

fn shellThread(_: ?*anyopaque) void {
    x64.sti();
    var s = shell.Shell.init();
    s.run();
}
