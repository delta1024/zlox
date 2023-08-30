const std = @import("std");
const page_allcator = std.heap.page_allocator;
const chunk = @import("chunk.zig");
const Chunk = chunk.Chunk;

pub fn main() !void {
    var ch = Chunk.init(page_allcator);
    defer ch.deinit();
    const pos = try ch.addConstant(23.0);
    try ch.pushBytes(chunk.OpCode.Constant, pos, 1);
    try ch.pushByte(chunk.OpCode, .Return, 1);
    std.debug.print("{test chunk}", .{ch});
}
