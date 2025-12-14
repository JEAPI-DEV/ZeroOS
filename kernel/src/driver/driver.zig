//! Driver management subsystem.

const std = @import("std");
const term = @import("../term/terminal.zig");

/// Interface that all drivers must implement.
pub const Driver = struct {
    /// The name of the driver.
    name: []const u8,
    /// The initialization function.
    init: *const fn () void,
};

/// The global driver manager.
pub const DriverManager = struct {
    /// The maximum number of drivers that can be registered.
    const MAX_DRIVERS = 32;

    /// The list of registered drivers.
    var drivers: [MAX_DRIVERS]Driver = undefined;
    /// The number of registered drivers.
    var num_drivers: usize = 0;

    /// Registers a new driver.
    ///
    /// Parameters:
    ///   driver: The driver to register.
    pub fn register(driver: Driver) void {
        if (num_drivers >= MAX_DRIVERS) {
            term.panic("Too many drivers registered.", .{});
        }

        drivers[num_drivers] = driver;
        num_drivers += 1;
    }

    /// Initializes all registered drivers.
    pub fn initialize() void {
        term.step("Initializing drivers", .{});

        for (drivers[0..num_drivers]) |driver| {
            term.print("  -> Initializing {s}...\n", .{driver.name});
            driver.init();
        }

        term.stepOk("", .{});
    }
};
