//! Virtual File System (VFS) interface for Zen OS.

const std = @import("std");

pub const NodeType = enum {
    file,
    directory,
    char_device,
    block_device,
};

pub const VfsNode = struct {
    name: []const u8,
    fs: *FileSystem,
    vtable: *const VTable,
    data: ?*anyopaque = null,
    node_type: NodeType,
    parent: ?*VfsNode = null,

    pub const VTable = struct {
        open: *const fn (node: *VfsNode, flags: u32) anyerror!*FileHandle,
        read: *const fn (node: *VfsNode, offset: u64, buffer: []u8) anyerror!usize,
        write: *const fn (node: *VfsNode, offset: u64, buffer: []const u8) anyerror!usize,
        readdir: *const fn (node: *VfsNode, index: usize) anyerror!?*VfsNode,
        mkdir: *const fn (node: *VfsNode, name: []const u8) anyerror!*VfsNode,
        create: *const fn (node: *VfsNode, name: []const u8) anyerror!*VfsNode,
        remove: *const fn (node: *VfsNode, name: []const u8) anyerror!void,
        rename: *const fn (node: *VfsNode, old_name: []const u8, new_name: []const u8) anyerror!void,
    };

    pub fn open(self: *VfsNode, flags: u32) anyerror!*FileHandle {
        return self.vtable.open(self, flags);
    }

    pub fn read(self: *VfsNode, offset: u64, buffer: []u8) anyerror!usize {
        return self.vtable.read(self, offset, buffer);
    }

    pub fn write(self: *VfsNode, offset: u64, buffer: []const u8) anyerror!usize {
        return self.vtable.write(self, offset, buffer);
    }

    pub fn readdir(self: *VfsNode, index: usize) anyerror!?*VfsNode {
        return self.vtable.readdir(self, index);
    }

    pub fn mkdir(self: *VfsNode, name: []const u8) anyerror!*VfsNode {
        return self.vtable.mkdir(self, name);
    }

    pub fn create(self: *VfsNode, name: []const u8) anyerror!*VfsNode {
        return self.vtable.create(self, name);
    }

    pub fn remove(self: *VfsNode, name: []const u8) anyerror!void {
        return self.vtable.remove(self, name);
    }

    pub fn rename(self: *VfsNode, old_name: []const u8, new_name: []const u8) anyerror!void {
        return self.vtable.rename(self, old_name, new_name);
    }
};

pub const FileHandle = struct {
    node: *VfsNode,
    offset: u64 = 0,
    flags: u32,

    pub fn read(self: *FileHandle, buffer: []u8) anyerror!usize {
        const bytes_read = try self.node.read(self.offset, buffer);
        self.offset += bytes_read;
        return bytes_read;
    }

    pub fn write(self: *FileHandle, buffer: []const u8) anyerror!usize {
        const bytes_written = try self.node.write(self.offset, buffer);
        self.offset += bytes_written;
        return bytes_written;
    }
};

pub const FileSystem = struct {
    name: []const u8,
    root: *VfsNode,
};

var root_fs: ?*FileSystem = null;

pub fn mount(fs: *FileSystem) void {
    root_fs = fs;
}

pub fn getRoot() *VfsNode {
    return root_fs.?.root;
}

/// Simple path resolution
pub fn lookup(path: []const u8, base_node: ?*VfsNode) anyerror!*VfsNode {
    if (path.len == 0) return error.InvalidPath;

    var current = if (path[0] == '/') getRoot() else (base_node orelse getRoot());
    const start_index: usize = if (path[0] == '/') 1 else 0;
    var it = std.mem.tokenizeScalar(u8, path[start_index..], '/');

    while (it.next()) |component| {
        if (std.mem.eql(u8, component, ".")) continue;
        if (std.mem.eql(u8, component, "..")) {
            if (current.parent) |p| {
                current = p;
            }
            continue;
        }

        if (current.node_type != .directory) return error.NotADirectory;

        var i: usize = 0;
        var found = false;
        while (try current.readdir(i)) |node| : (i += 1) {
            if (std.mem.eql(u8, node.name, component)) {
                current = node;
                found = true;
                break;
            }
        }

        if (!found) return error.NotFound;
    }

    return current;
}
