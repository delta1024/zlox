const Self = @This();
const Chunk = @import("../chunk.zig").Chunk;
const Value = @import("../value.zig").Value;
const Stack = @import("stack.zig").Stack;
stack: Stack(Value) = Stack(Value){},
chunk: ?*const Chunk = null,
ip: usize = 0,
pub fn init() Self {
    return .{};
}
pub fn readByte(self: *Self) ?u8 {
    if (self.chunk) |chunk| {
        self.ip += 1;
        return chunk.code.items[self.ip - 1];
    }
    return null;
}

pub fn readConstant(self: *Self) ?Value {
    if (self.readByte()) |idx| {
        if (self.chunk) |chunk| {
            return chunk.values.items[idx];
        }
    }
    return null;
}
pub fn deinit(self: *Self) void {
    _ = self;
}
