//! PCI Bus Driver.
//! Handles enumeration of the PCI bus and device discovery.

const std = @import("std");
const x64 = @import("../cpu/x64.zig");
const serial = @import("serial.zig");
const driver = @import("driver.zig");

const CONFIG_ADDRESS = 0xCF8;
const CONFIG_DATA = 0xCFC;

/// Reads a 32-bit value from the PCI configuration space.
fn pciConfigReadWord(bus: u8, slot: u8, func: u8, offset: u8) u32 {
    const address = (@as(u32, bus) << 16) | (@as(u32, slot) << 11) |
        (@as(u32, func) << 8) | (@as(u32, offset) & 0xFC) | 0x80000000;

    x64.outl(CONFIG_ADDRESS, address);
    return x64.inl(CONFIG_DATA);
}

/// Checks a specific device code (Vendor ID and Device ID).
fn checkDevice(bus: u8, device: u8) void {
    const func: u8 = 0;

    // Read Vendor ID (lower 16 bits of offset 0)
    const val = pciConfigReadWord(bus, device, func, 0);
    const vendor_id = @as(u16, @truncate(val));

    // If Vendor ID is 0xFFFF, the device doesn't exist.
    if (vendor_id == 0xFFFF) return;

    const device_id = @as(u16, @truncate(val >> 16));

    // Read Class Code and Subclass (Offset 0x08)
    const class_reg = pciConfigReadWord(bus, device, func, 0x08);
    const class_code = @as(u8, @truncate(class_reg >> 24));
    const subclass = @as(u8, @truncate(class_reg >> 16));

    serial.print("[PCI] Found device at {}:{}:{} - Vendor=0x{x}, Device=0x{x}, Class=0x{x}, Subclass=0x{x}\n", .{ bus, device, func, vendor_id, device_id, class_code, subclass });

    // Basic interpretation of detect devices for the user
    if (class_code == 0x01 and subclass == 0x01) {
        serial.print("      -> IDE Controller\n", .{});
    } else if (class_code == 0x03 and subclass == 0x00) {
        serial.print("      -> VGA Compatible Controller\n", .{});
    } else if (class_code == 0x02 and subclass == 0x00) {
        serial.print("      -> Ethernet Controller\n", .{});
    } else if (class_code == 0x06 and subclass == 0x00) {
        serial.print("      -> Host Bridge\n", .{});
    } else if (class_code == 0x06 and subclass == 0x01) {
        serial.print("      -> ISA Bridge\n", .{});
    }
}

/// Scans the PCI bus for devices.
pub fn scanBus() void {
    serial.print("[PCI] Scanning bus 0...\n", .{});
    var device: u8 = 0;
    while (device < 32) : (device += 1) {
        checkDevice(0, device);
    }
    serial.print("[PCI] Scan complete.\n", .{});
}

/// Initialization function for the global driver manager.
pub fn init() void {
    scanBus();
}

/// The global PCI driver instance.
pub const pci_driver = driver.Driver{
    .name = "PCI Bus",
    .init = init,
};
