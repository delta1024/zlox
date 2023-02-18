const std = @import("std");
const mem = std.mem;
const obj_mod = @import("./object.zig");
const Obj = obj_mod.Obj;
pub const ValueType = enum { boolean, nil, number, obj };
const ObjString = obj_mod.ObjString;
pub inline fn numberVal(val: f64) Value {
    return Value{ .number = val };
}
pub inline fn boolVal(val: bool) Value {
    return Value{ .boolean = val };
}
pub inline fn nilVal() Value {
    return .{ .nil = .{} };
}
pub inline fn objValue(val: *Obj) Value {
    return .{
        .obj = val,
    };
}
pub const Value = union(ValueType) {
    boolean: bool,
    number: f64,
    obj: *Obj,
    nil,
    pub fn id(self: *const Value) ValueType {
        return switch (self.*) {
            .boolean => .boolean,
            .number => .number,
            .nil => .nil,
            .obj => .obj,
        };
    }
    pub fn is(self: *const Value, comptime T: type) bool {
        return switch (self.*) {
            .nil => T == void,
            .number => T == f64,
            .boolean => T == bool,
            .obj => T == Obj,
        };
    }
    pub fn isObjType(self: *const Value, comptime T: type) bool {
        return switch (self.*) {
            .obj => |obj| switch (T) {
                ObjString => T == ObjString,
                else => false,
            },
            else => false,
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
            *Obj => switch (self) {
                .obj => |p| return p,
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
            .obj => |obj| {
                const a_string = @fieldParentPtr(ObjString, "obj", obj);
                const b_string = @fieldParentPtr(ObjString, "obj", other.as(*Obj));
                return mem.eql(u8, a_string.chars[0..mem.len(a_string.chars)], b_string.chars[0..mem.len(b_string.chars)]);
            },
        }
    }
    pub fn format(self: *const Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.*) {
            .boolean => |b| if (b) {
                try writer.print("true", .{});
            } else try writer.print("false", .{}),
            .number => |n| try writer.print("{d:.2}", .{n}),
            .nil => try writer.print("nil", .{}),
            .obj => |o| try o.format(fmt, options, writer),
        }
    }
};
