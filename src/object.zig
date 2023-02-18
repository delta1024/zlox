const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
pub const ObjType = enum {
    String,
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
        }
    }
    pub fn deinit(self: *Obj, allocator: *Allocator) void {
        switch (self.type) {
            .String => {
                const string = @fieldParentPtr(ObjString, "obj", self);
                allocator.free(string.chars[0..mem.len(string.chars)]);
                allocator.destroy(string);
            },
        }
    }
};

pub const ObjString = struct {
    obj: Obj,
    chars: [*:0]u8 = undefined,
    pub fn format(self: *const ObjString, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{self.chars});
    }
};
