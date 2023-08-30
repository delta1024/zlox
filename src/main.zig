const std = @import("std");
const page_allcator = std.heap.page_allocator;
const chunk = @import("chunk.zig");
const Chunk = chunk.Chunk;

pub fn main() !void {
    var ch = Chunk.init(page_allcator);
    defer ch.deinit();
    try ch.pushByte(.Return);
    std.debug.print("{test chunk}", .{ch});
}
