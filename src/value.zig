const std = @import("std");
pub const ValueType = enum { boolean, nil, number };
pub inline fn numberVal(val: f64) Value {
    return Value{ .number = val };
}
pub inline fn boolVal(val: bool) Value {
    return Value{ .number = val };
}
pub const Value = union(ValueType) {
    boolean: bool,
    number: f64,
    nil,
    pub fn is(self: *const Value, comptime T: type) bool {
        return switch (self.*) {
            .nil => T == void,
            .number => T == f64,
            .boolean => T == bool,
        };
    }

    pub fn as(self: Value, comptime T: type) T {
        return switch (T) {
            bool => self.boolean,
            f64 => self.number,
            else => unreachable,
        };
    }
    pub fn format(self: *const Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.*) {
            .boolean => |b| if (b) {try writer.print("true", .{});} else try writer.print("false", .{}),
            .number => |n| try writer.print("{d:.2}", .{n}),
            .nil => try writer.print("nil", .{}),
        }
    }
};
