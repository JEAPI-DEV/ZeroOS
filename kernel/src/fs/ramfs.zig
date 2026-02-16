//! RAMFS implementation for Zen OS.

const std = @import("std");
const vfs = @import("vfs.zig");

pub const RamfsNode = struct {
    vfs_node: vfs.VfsNode,
    allocator: std.mem.Allocator,

    // For files
    data: std.ArrayListUnmanaged(u8),

    // For directories
    children: std.ArrayListUnmanaged(*RamfsNode),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, node_type: vfs.NodeType, fs: *vfs.FileSystem) !*RamfsNode {
        const self = try allocator.create(RamfsNode);
        const name_copy = try allocator.dupe(u8, name);

        self.* = .{
            .vfs_node = .{
                .name = name_copy,
                .fs = fs,
                .vtable = &ramfs_vtable,
                .data = self,
                .node_type = node_type,
            },
            .allocator = allocator,
            .data = .{},
            .children = .{},
        };

        return self;
    }
};

const ramfs_vtable = vfs.VfsNode.VTable{
    .open = ramfs_open,
    .read = ramfs_read,
    .write = ramfs_write,
    .readdir = ramfs_readdir,
    .mkdir = ramfs_mkdir,
    .create = ramfs_create,
    .remove = ramfs_remove,
    .rename = ramfs_rename,
};

fn ramfs_open(node: *vfs.VfsNode, flags: u32) anyerror!*vfs.FileHandle {
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));
    const handle = try ram_node.allocator.create(vfs.FileHandle);
    handle.* = .{
        .node = node,
        .flags = flags,
        .offset = 0,
    };
    return handle;
}

fn ramfs_read(node: *vfs.VfsNode, offset: u64, buffer: []u8) anyerror!usize {
    if (node.node_type != .file) return error.NotAFile;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    if (offset >= ram_node.data.items.len) return 0;

    const remaining = ram_node.data.items.len - offset;
    const to_read = @min(remaining, buffer.len);

    @memcpy(buffer[0..to_read], ram_node.data.items[@intCast(offset)..@intCast(offset + to_read)]);
    return to_read;
}

fn ramfs_write(node: *vfs.VfsNode, offset: u64, buffer: []const u8) anyerror!usize {
    if (node.node_type != .file) return error.NotAFile;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    const end = offset + buffer.len;
    if (end > ram_node.data.items.len) {
        try ram_node.data.resize(ram_node.allocator, @intCast(end));
    }

    @memcpy(ram_node.data.items[@intCast(offset)..@intCast(offset + buffer.len)], buffer);
    return buffer.len;
}

fn ramfs_readdir(node: *vfs.VfsNode, index: usize) anyerror!?*vfs.VfsNode {
    if (node.node_type != .directory) return error.NotADirectory;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    if (index >= ram_node.children.items.len) return null;
    return &ram_node.children.items[index].vfs_node;
}

fn ramfs_mkdir(node: *vfs.VfsNode, name: []const u8) anyerror!*vfs.VfsNode {
    if (node.node_type != .directory) return error.NotADirectory;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    const new_node = try RamfsNode.init(ram_node.allocator, name, .directory, node.fs);
    new_node.vfs_node.parent = node;
    try ram_node.children.append(ram_node.allocator, new_node);
    return &new_node.vfs_node;
}

fn ramfs_create(node: *vfs.VfsNode, name: []const u8) anyerror!*vfs.VfsNode {
    if (node.node_type != .directory) return error.NotADirectory;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    const new_node = try RamfsNode.init(ram_node.allocator, name, .file, node.fs);
    new_node.vfs_node.parent = node;
    try ram_node.children.append(ram_node.allocator, new_node);
    return &new_node.vfs_node;
}

fn ramfs_remove(node: *vfs.VfsNode, name: []const u8) anyerror!void {
    if (node.node_type != .directory) return error.NotADirectory;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    for (ram_node.children.items, 0..) |child, i| {
        if (std.mem.eql(u8, child.vfs_node.name, name)) {
            // Found it.
            // TODO: Recursive cleanup if directory
            _ = ram_node.children.orderedRemove(i);
            // We're leaking the node memory for now, but that's okay for RAMFS in this kernel
            return;
        }
    }
    return error.NotFound;
}

fn ramfs_rename(old_parent: *vfs.VfsNode, old_name: []const u8, new_parent: *vfs.VfsNode, new_name: []const u8) anyerror!void {
    if (old_parent.node_type != .directory or new_parent.node_type != .directory) return error.NotADirectory;

    const old_ram_node = @as(*RamfsNode, @ptrCast(@alignCast(old_parent.data.?)));
    const new_ram_node = @as(*RamfsNode, @ptrCast(@alignCast(new_parent.data.?)));

    // 1. Find the child in old_parent
    var child_idx: ?usize = null;
    for (old_ram_node.children.items, 0..) |child, i| {
        if (std.mem.eql(u8, child.vfs_node.name, old_name)) {
            child_idx = i;
            break;
        }
    }

    if (child_idx) |idx| {
        // 2. Remove from old_parent
        const child = old_ram_node.children.orderedRemove(idx); // Use orderedRemove to swap-remove is not safe if we rely on order? Ordered is safer for stability.

        // 3. Rename child
        const new_name_copy = try child.allocator.dupe(u8, new_name);
        child.allocator.free(child.vfs_node.name);
        child.vfs_node.name = new_name_copy;

        // 4. Reparent
        child.vfs_node.parent = new_parent;

        // 5. Add to new_parent
        try new_ram_node.children.append(new_ram_node.allocator, child);
        return;
    }
    return error.NotFound;
}

pub fn createFileSystem(allocator: std.mem.Allocator, name: []const u8) !*vfs.FileSystem {
    const fs = try allocator.create(vfs.FileSystem);
    fs.name = try allocator.dupe(u8, name);

    const root = try RamfsNode.init(allocator, "", .directory, fs);
    fs.root = &root.vfs_node;

    return fs;
}

// --- Persistence ---

const storage = @import("../driver/storage.zig");
const MAGIC = 0x53464E455A; // "ZENFS" in little endian + nulls... actually just "ZENFS" is 5 bytes. 0x... is integer.
// Let's use string check.
const MAGIC_STR = "ZENFSv1\x00"; // 8 bytes

const serial = @import("../driver/serial.zig");

pub fn saveToDisk() !void {
    serial.print("[RAMFS] Saving to disk...\n", .{});
    if (vfs.root_fs == null) return;

    // Get Block Device
    const device = storage.getPrimary() orelse {
        serial.print("[RAMFS] No block device found for saving.\n", .{});
        return;
    };

    const root = vfs.getRoot();
    if (root.data) |ptr| {
        const ram_root = @as(*RamfsNode, @ptrCast(@alignCast(ptr)));
        var writer = SectorWriter.init(device);

        // Write Magic
        try writer.writeBytes(MAGIC_STR);

        // Recursive write
        try serializeNode(ram_root, "", &writer);

        // Flush remaining
        try writer.flush();
        serial.print("[RAMFS] Save complete.\n", .{});
    }
}

fn serializeNode(node: *RamfsNode, path_prefix: []const u8, writer: *SectorWriter) !void {
    // Construct full path
    if (node.vfs_node.node_type == .directory) {
        for (node.children.items) |child| {
            // Build path: prefix + "/" + name
            var path_buf: [256]u8 = undefined;
            const len = path_prefix.len + 1 + child.vfs_node.name.len;
            if (len > 255) continue; // Skip too long paths

            @memcpy(path_buf[0..path_prefix.len], path_prefix);
            path_buf[path_prefix.len] = '/';
            @memcpy(path_buf[path_prefix.len + 1 ..][0..child.vfs_node.name.len], child.vfs_node.name);
            const full_path = path_buf[0..len];

            try writeEntry(child, full_path, writer);
            try serializeNode(child, full_path, writer);
        }
    }
}

fn writeEntry(node: *RamfsNode, path: []const u8, writer: *SectorWriter) !void {
    try writer.writeU16(@intCast(path.len));
    try writer.writeBytes(path);

    const type_byte: u8 = if (node.vfs_node.node_type == .directory) 1 else 0;
    try writer.writeU8(type_byte);

    if (node.vfs_node.node_type == .file) {
        const size: u64 = node.data.items.len;
        try writer.writeU64(size);
        try writer.writeBytes(node.data.items);
    } else {
        try writer.writeU64(0);
    }
}

pub fn loadFromDisk() !void {
    serial.print("[RAMFS] Loading from disk...\n", .{});

    const device = storage.getPrimary() orelse {
        serial.print("[RAMFS] No block device found for loading.\n", .{});
        return;
    };

    var reader = SectorReader.init(device);

    var magic_buf: [8]u8 = undefined;
    if (reader.readBytes(&magic_buf)) |read| {
        if (read != 8 or !std.mem.eql(u8, &magic_buf, MAGIC_STR)) {
            // Invalid magic, assume empty/fresh disk
            serial.print("[RAMFS] Invalid magic or empty disk.\n", .{});
            return;
        }
    } else |_| {
        serial.print("[RAMFS] Failed to read magic.\n", .{});
        return;
    }

    const root = vfs.getRoot(); // Assuming root fs is initialized

    while (true) {
        // Read Entry
        // PathLen
        var path_len_bytes: [2]u8 = undefined;
        _ = reader.readBytes(&path_len_bytes) catch break; // End of stream or error
        const path_len = std.mem.readInt(u16, &path_len_bytes, .little);
        if (path_len == 0) break; // Should not happen ideally, but 0 len path is invalid for us here (root is skipped)

        var path_buf: [256]u8 = undefined;
        if (path_len > 256) return error.PathTooLong;
        _ = try reader.readBytes(path_buf[0..path_len]);
        const path = path_buf[0..path_len];

        var type_byte: [1]u8 = undefined;
        _ = try reader.readBytes(&type_byte);

        var size_bytes: [8]u8 = undefined;
        _ = try reader.readBytes(&size_bytes);
        const size = std.mem.readInt(u64, &size_bytes, .little);

        // Create the node
        if (type_byte[0] == 1) {
            _ = ensurePath(root, path, .directory) catch {};
        } else {
            // File
            const node = ensurePath(root, path, .file) catch null;
            if (node) |n| {
                // Read Data
                // Use a loop to read chunks and write to file
                var remaining = size;
                var buf: [512]u8 = undefined;
                while (remaining > 0) {
                    const to_read = @min(remaining, 512);
                    _ = try reader.readBytes(buf[0..to_read]); // This might return less or error
                    // Actually SectorReader buffers 512 bytes.
                    _ = try vfs.VfsNode.write(n, size - remaining, buf[0..to_read]); // offset calc needed?
                    // Wait, VfsNode.write appends/overwrites. We are writing sequentially.
                    // offset = size - remaining.
                    remaining -= to_read;
                }
            } else {
                // Skip data if failed to create
                _ = reader.skip(size) catch {};
            }
        }
    }
    serial.print("[RAMFS] Load complete.\n", .{});
}

fn ensurePath(root: *vfs.VfsNode, path: []const u8, node_type: vfs.NodeType) !*vfs.VfsNode {
    // We trust path is absolute relative to root (starts with /)
    // Actually our serialized paths start with /name.
    // We can use `vfs.lookup` or manual creation.
    // If we use vfs.lookup for parent.

    // Split into dir and name
    const last_slash = std.mem.lastIndexOfScalar(u8, path, '/');
    var parent = root;
    var name = path;

    if (last_slash) |idx| {
        if (idx > 0) {
            const parent_path = path[0..idx];
            parent = try vfs.lookup(parent_path, root); // Should exist due to order
        }
        name = path[idx + 1 ..];
    }

    if (node_type == .directory) {
        return vfs.VfsNode.mkdir(parent, name);
    } else {
        return vfs.VfsNode.create(parent, name);
    }
}

const SectorWriter = struct {
    buf: [512]u8 = undefined,
    idx: usize = 0,
    sector: u64 = 0,
    device: storage.BlockDevice,

    pub fn init(device: storage.BlockDevice) SectorWriter {
        return SectorWriter{ .device = device };
    }

    pub fn writeU8(self: *SectorWriter, val: u8) !void {
        try self.writeBytes(&[_]u8{val});
    }

    pub fn writeU16(self: *SectorWriter, val: u16) !void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, val, .little);
        try self.writeBytes(&bytes);
    }

    pub fn writeU64(self: *SectorWriter, val: u64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, val, .little);
        try self.writeBytes(&bytes);
    }

    pub fn writeBytes(self: *SectorWriter, bytes: []const u8) !void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const space = 512 - self.idx;
            const chunk = @min(space, bytes.len - offset);
            @memcpy(self.buf[self.idx..][0..chunk], bytes[offset..][0..chunk]);
            self.idx += chunk;
            offset += chunk;

            if (self.idx == 512) {
                try self.flush();
            }
        }
    }

    pub fn flush(self: *SectorWriter) !void {
        if (self.idx > 0) {
            // Zero out rest? Not strictly needed but clean.
            @memset(self.buf[self.idx..], 0);
            self.device.writeSector(self.device.context, self.sector, &self.buf) catch return error.DiskIOError;
            self.sector += 1;
            self.idx = 0;
        }
    }
};

const SectorReader = struct {
    buf: [512]u8 = undefined,
    idx: usize = 0,
    sector: u64 = 0,
    loaded: bool = false,
    device: storage.BlockDevice,

    pub fn init(device: storage.BlockDevice) SectorReader {
        return SectorReader{ .device = device };
    }

    fn ensureLoaded(self: *SectorReader) !void {
        if (!self.loaded or self.idx == 512) {
            self.device.readSector(self.device.context, self.sector, &self.buf) catch return error.DiskIOError;
            self.sector += 1;
            self.idx = 0;
            self.loaded = true;
        }
    }

    pub fn readBytes(self: *SectorReader, out: []u8) !usize {
        var offset: usize = 0;
        while (offset < out.len) {
            try self.ensureLoaded();
            const available = 512 - self.idx;
            const chunk = @min(available, out.len - offset);

            @memcpy(out[offset..][0..chunk], self.buf[self.idx..][0..chunk]);
            self.idx += chunk;
            offset += chunk;
        }
        return offset; // Should be out.len unless error
    }

    pub fn skip(self: *SectorReader, amount: u64) !void {
        var left = amount;
        while (left > 0) {
            try self.ensureLoaded();
            const available = 512 - self.idx;
            const chunk = @min(available, left);
            self.idx += chunk;
            left -= chunk;
        }
    }
};
