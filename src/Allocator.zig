const std = @import("std");
const mem = std.mem;
const heap = std.heap;
usingnamespace @import("./object.zig");
const Chunk = @import("./Chunk.zig");
const Allocator = mem.Allocator;
const Table = std.StringHashMapUnmanaged;
const VmAllocator = @This();
const VM = @import("./VM.zig");
pub const Error = error{OutOfMemory} || Allocator.Error;
bytes_writen: usize = 0,
bytes_freed: usize = 0,
backing_allocator: *Allocator = heap.page_allocator,
strings: Table(*ObjString) = Table(*ObjString){},
objects: ?*Obj = null,
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
pub fn newFunction(self: *VmAllocator) Error!*ObjFunction {
    var function = @fieldParentPtr(ObjFunction, "obj", try self.allocateObj(ObjFunction, .Function));
    function.* = .{
        .chunk = Chunk.init(&self.allocator),
    };
    return function;
}
pub fn newNative(self: *VmAllocator, function: NativeFn) Error!*ObjNative {
    var native = @fieldParentPtr(ObjNative, "obj", try self.allocateObj(ObjNative, .Native));
    native.function = function;
    return native;
}
pub fn allocateObj(self: *VmAllocator, comptime T: type, id: ObjType) Error!*Obj {
    var obj = try self.allocator.create(T);
    obj.* = T.init(&self.allocator);
    obj.obj.next = self.objects;
    self.objects = &obj.obj;
    return &obj.obj;
}
fn allocateString(self: *VmAllocator, chars: [*:0]u8) Error!*ObjString {
    var string = @fieldParentPtr(ObjString, "obj", try self.allocateObj(ObjString, .String));
    string.chars = chars;
    try self.strings.put(&self.allocator, string.chars[0..mem.len(string.chars)], string);
    return string;
}
pub fn takeString(self: *VmAllocator, chars: [*:0]u8) Error!*ObjString {
    const interned = self.strings.get(chars[0..mem.len(chars)]);
    if (interned) |ptr| {
        self.allocator.free(chars[0..mem.len(chars)]);
        return ptr;
    }
    return try self.allocateString(chars);
}
pub fn copyString(self: *VmAllocator, chars: []const u8) Error!*ObjString {
    const interned = self.strings.get(chars);
    if (interned) |ptr| return ptr;
    var heap_chars = try self.allocator.allocSentinel(u8, chars.len, 0);
    mem.copy(u8, heap_chars[0..mem.len(heap_chars)], chars);
    return try self.allocateString(heap_chars);
}
pub fn deinit(self: *VmAllocator) void {
    self.freeObjects();
    self.strings.deinit(&self.allocator);
}
pub fn freeObjects(self: *VmAllocator) void {
    var object = self.objects;
    while (object) |obj| {
        const next = obj.next;
        obj.deinit(&self.allocator);
        object = next;
    }
}
