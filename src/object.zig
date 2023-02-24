const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Chunk = @import("./Chunk.zig");
const Value = @import("./value.zig").Value;
pub const ObjType = enum {
    String,
    Function,
    Native,
};
pub const Obj = struct {
    type: ObjType,
    next: ?*Obj = null,
    pub fn format(self: *const Obj, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.type) {
            .String => {
                const string = @fieldParentPtr(ObjString, "obj", self);
                try string.format(fmt, options, writer);
            },
            .Function => {
                const func = @fieldParentPtr(ObjFunction, "obj", self);
                if (func.name) |name| {
                    try writer.print("<fn {s}>", .{name});
                } else {
                    try writer.writeAll("<fn script>");
                }
            },
            .Native => {
                try writer.writeAll("<native fn>");
            },
        }
    }
    pub fn deinit(self: *Obj, allocator: *Allocator) void {
        switch (self.type) {
            .String => {
                const string = @fieldParentPtr(ObjString, "obj", self);
                allocator.free(string.chars[0..mem.len(string.chars)]);
                allocator.destroy(string);
            },
            .Function => {
                const func = @fieldParentPtr(ObjFunction, "obj", self);
                func.chunk.deinit();
                allocator.destroy(func);
            },
            .Native => {
                const func = @fieldParentPtr(ObjNative, "obj", self);
                allocator.destroy(func);
            },
        }
    }
};

pub const ObjFunction = struct {
    obj: Obj = .{ .type = .Function },
    arity: usize = 0,
    chunk: Chunk,
    name: ?*ObjString = null,
    pub fn init(allocator: *Allocator) ObjFunction {
        return .{
            .chunk = Chunk.init(allocator),
        };
    }
};
pub const ObjString = struct {
    obj: Obj = .{ .type = .String },
    chars: [*:0]u8 = undefined,
    pub fn init(_: *Allocator) ObjString {
        return .{};
    }
    pub fn format(self: *const ObjString, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{self.chars});
    }
};

pub const NativeFn = fn (usize, []Value) Value;
pub const ObjNative = struct {
    obj: Obj,
    function: NativeFn = undefined,
    pub fn init(_: *Allocator) ObjNative {
        return .{
            .obj = .{ .type = .Native },
        };
    }
};
