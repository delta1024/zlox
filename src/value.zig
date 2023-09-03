const std = @import("std");
pub const ValueType = enum {
    boolean,
    number,
    nil,
};

pub const Value = union(ValueType) {
    boolean: bool,
    number: f64,
    nil,
    pub fn is(self: Value, comptime pred: type) bool {
        return switch (self) {
            ValueType.boolean => |_| pred == bool,
            ValueType.number => |_| pred == f64,
            ValueType.nil => pred == Value,
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
    }
    pub fn isFalsey(self: Value) bool {
        return switch (self) {
            .nil => true,
            .boolean => |b| !b,
            else => false,
        };
    }

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .boolean => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
            .number => |n| try writer.print("{d}", .{n}),
            .nil => try writer.print("nil", .{}),
        }
    }
};

pub fn valuesEqual(a: Value, b: Value) bool {
    if (@as(ValueType, a) != @as(ValueType, b)) return false;
    return switch (a) {
        .boolean => |a_| a_ == b.as(bool),
        .nil => true,
        .number => |a_| a_ == b.as(f64),
    };
}
