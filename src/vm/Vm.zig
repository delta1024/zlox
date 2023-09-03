const std = @import("std");
const Self = @This();
const Chunk = @import("../chunk.zig").Chunk;
const Value = @import("../value.zig").Value;
const Stack = @import("stack.zig").Stack;
pub const Error = error{};
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
pub fn runtimeError(self: *Self, comptime fmt: []const u8, args: anytype) void {
    const std_err = std.io.getStdErr();
    std_err.writer().print(fmt, args) catch unreachable;
    std_err.writer().print("\n", .{}) catch unreachable;

    const instruction = self.ip - 1;
    const line = self.chunk.?.lines.items[instruction];
    std_err.writer().print("[line {d}] in script\n", .{line}) catch unreachable;
    self.stack.reset();
}
pub fn deinit(self: *Self) void {
    _ = self;
}
