const std = @import("std");
const ValueId = enum { number, nil };
pub const Value = union(ValueId) {
    number: f64,
    nil,

    pub fn isType(self: *Value, comptime T: type) bool {
        return switch (self.*) {
            .number => T == f64,
            .nil => T == void,
        };
    }
    pub fn asType(self: Value, comptime T: type) T {
        switch (T) {
            f64 => {
                switch (self) {
                    .number => |n| return n,
                    else => unreachable,
                }
            },
            else => unreachable,
        }
    }
    pub fn format(self: *const Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.*) {
            .number => |*n| {
                try writer.print("{d:.2}", .{n.*});
            },
            else => {
                try writer.print("nil", .{});
            },
        }
    }
};
