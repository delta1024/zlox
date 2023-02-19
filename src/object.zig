const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Chunk = @import("./Chunk.zig");
pub const ObjType = enum {
    String,
    Function,
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
                        try writer.print("<fn {s}", .{name});
                    } else {
                            try writer.writeAll("<fn script>");
                        }
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
