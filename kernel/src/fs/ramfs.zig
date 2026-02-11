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

fn ramfs_rename(node: *vfs.VfsNode, old_name: []const u8, new_name: []const u8) anyerror!void {
    if (node.node_type != .directory) return error.NotADirectory;
    const ram_node = @as(*RamfsNode, @ptrCast(@alignCast(node.data.?)));

    for (ram_node.children.items) |child| {
        if (std.mem.eql(u8, child.vfs_node.name, old_name)) {
            const new_name_copy = try child.allocator.dupe(u8, new_name);
            child.allocator.free(child.vfs_node.name);
            child.vfs_node.name = new_name_copy;
            return;
        }
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
