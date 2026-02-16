const std = @import("std");
const limine = @import("limine");

var symbol_data: ?[]const u8 = null;

pub fn init(response: *limine.ModuleResponse) void {
    if (response.module_count > 0) {
        const file = response.modules()[0];
        symbol_data = @as([*]const u8, @ptrCast(file.address))[0..file.size];
    }
}

pub fn lookup(addr: usize) ?[]const u8 {
    const data = symbol_data orelse return null;

    var best_addr: usize = 0;
    var best_name: ?[]const u8 = null;

    var lines = std.mem.tokenizeScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const addr_str = parts.next() orelse continue;
        const name = parts.rest(); // The rest is the name (might handle spaces if function name has spaces? no, nm doesn't usually)
        // Wait, awk printed $1 " " $3. if $3 is name.
        // Actually name should be parts.next().

        const sym_addr = std.fmt.parseInt(usize, addr_str, 16) catch continue;

        if (sym_addr <= addr) {
            if (sym_addr >= best_addr) {
                best_addr = sym_addr;
                best_name = name;
            }
        } else {
            // Sorted input, so we can stop?
            // "nm -n" sorts.
            // If sym_addr > addr, then this symbol is AFTER our address.
            // Since we want the closest symbol BEFORE or AT addr, and we are iterating in increasing order,
            // we keep updating best_addr as long as sym_addr <= addr.
            // Once we hit > addr, we break.
            break;
        }
    }

    return best_name;
}
