const std = @import("std");
pub fn Stack(comptime T: type) type {
    return struct {
        pub const Error = error{StackOverFlow};
        pub const STACK_MAX = 256;
        const Self = @This();
        stack_top: usize = 0,
        data: [STACK_MAX]T = undefined,
        pub fn push(self: *Self, val: T) Error!void {
            if (self.stack_top > STACK_MAX) return error.StackOverFlow;
            self.data[self.stack_top] = val;
            self.stack_top += 1;
        }
        pub fn pop(self: *Self) ?T {
            if (self.stack_top == 0) return null;
            self.stack_top -= 1;
            return self.data[self.stack_top];
        }
        pub fn reset(self: *Self) void {
            self.stack_top = 0;
        }
        pub fn peek(self: *Self, distance: usize) ?T {
            if (self.stack_top == 0) return null;
            return self.data[(self.stack_top - distance) - 1];
        }
    };
}
