const std = @import("std");
pub const ValueType = enum { boolean, nil, number };
pub inline fn numberVal(val: f64) Value {
    return Value{ .number = val };
}
pub inline fn boolVal(val: bool) Value {
    return Value{ .boolean = val };
}
pub inline fn nilVal() Value {
    return .{ .nil = .{} };
}
pub const Value = union(ValueType) {
    boolean: bool,
    number: f64,
    nil,
    pub fn id(self: *const Value) ValueType {
        return switch (self.*) {
            .boolean => .boolean,
            .number => .number,
            .nil => .nil,
        };
    }
    pub fn is(self: *const Value, comptime T: type) bool {
        return switch (self.*) {
            .nil => T == void,
            .number => T == f64,
            .boolean => T == bool,
        };
    }

    pub fn as(self: Value, comptime T: type) T {
        switch (T) {
            f64 => switch (self) {
                .number => |n| return n,
                else => unreachable,
            },
            bool => switch (self) {
                .boolean => |b| return b,
                else => unreachable,
            },
            else => unreachable,
        }
        return switch (self) {
            .boolean => |b| return b,
            .number => |n| return n,
            else => unreachable,
        };
    }
    pub fn isFalsey(self: *Value) bool {
        return self.is(void) or (self.is(bool) and !self.as(bool));
    }
    pub fn equals(self: Value, other: Value) bool {
        if (self.id() != other.id()) return false;

        switch (self) {
            .boolean => |b| return b == other.as(bool),
            .number => |n| return n == other.as(f64),
            .nil => return true,
        }
    }
    pub fn format(self: *const Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.*) {
            .boolean => |b| if (b) {
                try writer.print("true", .{});
            } else try writer.print("false", .{}),
            .number => |n| try writer.print("{d:.2}", .{n}),
            .nil => try writer.print("nil", .{}),
        }
    }
};
