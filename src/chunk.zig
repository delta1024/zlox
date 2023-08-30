const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

pub const OpCode = enum(u8) {
    Return,
};

pub const Chunk = struct {
    code: ArrayList(u8),
    const Error = error{OutOfMemory} || Allocator.Error;
    pub fn init(allocator: Allocator) Chunk {
        return .{
            .code = ArrayList(u8).init(allocator),
        };
    }
    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
    }
    pub fn pushByte(self: *Chunk, comptime T: type, byte: T) Error!void {
        const b = if (T == OpCode) @enumToInt(byte) else @as(u8, byte);
        try self.code.append(b);
    }

    // Formating Functions -------------------------------------------------
    // ---------------------------------------------------------------------
    pub fn dissasembleChunk(self: *const Chunk, name: []const u8, writer: anytype) @TypeOf(writer).Error!void {
        try writer.print("== {s} ==\n", .{name});
        var offset: usize = 0;
        while (offset < self.code.items.len) : (offset = try self.dissasembleInstruction(offset, writer)) {}
    }
    fn simpleInstruction(name: []const u8, offset: usize, writer: anytype) @TypeOf(writer).Error!usize {
        try writer.print("{s}\n", .{name});
        return offset + 1;
    }
    pub fn dissasembleInstruction(self: *const Chunk, offset: usize, writer: anytype) @TypeOf(writer).Error!usize {
        try writer.print("{X:0>4} ", .{@truncate(u32, offset)});

        const instruction = @intToEnum(OpCode, self.code.items[offset]);
        return switch (instruction) {
            .Return => try simpleInstruction("OP_RETURN", offset, writer),
            // else => b: {
            //     try writer.print("Unknown opcode {}\n", .{instruction});
            //     break :b offset + 1;
            // },
        };
    }
    pub fn format(self: Chunk, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try self.dissasembleChunk(fmt, writer);
    }
    // ---------------------------------------------------------------------
    // ---------------------------------------------------------------------
};
