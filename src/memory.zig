const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const Allocator = mem.Allocator;
pub const VmAllocator = @This();
pub const Error = error{OutOfMemory} || mem.Allocator.Error;
bytes_writen: usize = 0,
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
    }
    return try self.backing_allocator.resizeFn(self.backing_allocator, buf, buf_align, new_len, len_align, ret_addr);
}
