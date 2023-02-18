const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const obj_mod = @import("./object.zig");
const Obj = obj_mod.Obj;
const ObjString = obj_mod.ObjString;
const ObjType = obj_mod.ObjType;
const Allocator = mem.Allocator;
const VmAllocator = @This();
const VM = @import("./VM.zig");
pub const Error = error{OutOfMemory} || Allocator.Error;
bytes_writen: usize = 0,
bytes_freed: usize = 0,
backing_allocator: *Allocator = heap.page_allocator,
allocator: Allocator =
    Allocator{
        .allocFn = alloc,
        .resizeFn = resize,
    },

fn alloc(allocator: *Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Error![]u8 {
    const self = @fieldParentPtr(VmAllocator, "allocator", allocator);
    self.bytes_writen += len;
    return try self.backing_allocator.allocFn(self.backing_allocator, len, ptr_align, len_align, ret_addr);
}
fn resize(allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) Error!usize {
    const old_len = mem.alignForward(buf.len, mem.page_size);
    const self = @fieldParentPtr(VmAllocator, "allocator", allocator);
    if (new_len > old_len) {
        self.bytes_writen += new_len;
    } else {
        self.bytes_freed += (old_len - new_len);
    }
    return try self.backing_allocator.resizeFn(self.backing_allocator, buf, buf_align, new_len, len_align, ret_addr);
}

pub inline fn allocateObj(self: *VmAllocator, comptime T: type, id: ObjType) Error!*Obj {
    var obj = try self.allocator.create(T);
    const vm = @fieldParentPtr(VM, "memory", self);
    obj.* = T{
        .obj = .{ .type = id, .next = vm.objects },
    };
    vm.objects = &obj.obj;
    return &obj.obj;
}
fn allocateString(self: *VmAllocator, chars: [*:0]u8) Error!*ObjString {
    var string = @fieldParentPtr(ObjString, "obj", try self.allocateObj(ObjString, .String));
    string.chars = chars;
    return string;
}
pub fn takeString(self: *VmAllocator, chars: [*:0]u8) Error!*ObjString {
    return try self.allocateString(chars);
}
pub fn copyString(self: *VmAllocator, chars: []const u8) Error!*ObjString {
    var heap_chars = try self.allocator.allocSentinel(u8, chars.len, 0);
    mem.copy(u8, heap_chars[0..mem.len(heap_chars)], chars);
    return try self.allocateString(heap_chars);
}
pub fn freeObjects(self: *VmAllocator) void {
    const vm = @fieldParentPtr(VM, "memory", self);
    var object = vm.objects;
    while (object) |obj| {
        const next = obj.next;
        obj.deinit(&self.allocator);
        object = next;
    }
}
