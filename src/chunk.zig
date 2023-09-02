const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;
const Value = @import("value.zig").Value;

pub const OpCode = enum(u8) {
    Constant,
    Add,
    Subtract,
    Multiply,
    Divide,
    Negate,
    Return,
    pub fn format(self: OpCode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        const varient = @tagName(self);
        var buffer: [256]u8 = undefined;
        var n: usize = 0;
        for ("OP_") |v| {
            buffer[n] = v;
            n += 1;
        }
        for (varient) |v, i| {
            if (ascii.isUpper(v) and i > 2) {
                buffer[n] = '_';
                n += 1;
                buffer[n] = v;
                n += 1;
            } else {
                buffer[n] = ascii.toUpper(v);
                n += 1;
            }
        }
        buffer[n] = '0';
        try writer.print("{s}", .{buffer[0..n]});
    }
};

pub const Chunk = struct {
    code: ArrayList(u8),
    values: ArrayList(Value),
    lines: ArrayList(u8),
    pub const Error = error{OutOfMemory} || Allocator.Error;
    pub fn init(allocator: Allocator) Chunk {
        return .{
            .code = ArrayList(u8).init(allocator),
            .values = ArrayList(Value).init(allocator),
            .lines = ArrayList(u8).init(allocator),
        };
    }
    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.values.deinit();
        self.lines.deinit();
    }
    pub fn pushByte(self: *Chunk, comptime T: type, byte: T, line: u8) Error!void {
        const b = if (T == OpCode) @enumToInt(byte) else @as(u8, byte);
        try self.code.append(b);
        try self.lines.append(line);
    }
    pub fn pushBytes(self: *Chunk, byte1: anytype, byte2: anytype, line: u8) Error!void {
        try self.pushByte(@TypeOf(byte1), byte1, line);
        try self.pushByte(@TypeOf(byte2), byte2, line);
    }
    pub fn addConstant(self: *Chunk, value: Value) Error!usize {
        try self.values.append(value);
        return self.values.items.len - 1;
    }

    // Formating Functions -------------------------------------------------
    // ---------------------------------------------------------------------
    pub fn dissasembleChunk(self: *const Chunk, name: []const u8, writer: anytype) @TypeOf(writer).Error!void {
        try writer.print("== {s} ==\n", .{name});
        var offset: usize = 0;
        while (offset < self.code.items.len) : (offset = try self.dissasembleInstruction(offset, writer)) {}
    }
    fn simpleInstruction(name: OpCode, offset: usize, writer: anytype) @TypeOf(writer).Error!usize {
        try writer.print("{}", .{name});
        return offset + 1;
    }
    fn constantInstruction(self: *const Chunk, name: []const u8, offset: usize, writer: anytype) @TypeOf(writer).Error!usize {
        const constant = self.code.items[offset + 1];
        try writer.print("{s: <16} {d: >4} '{d}'", .{ name, constant, self.values.items[constant] });
        return offset + 2;
    }
    pub fn dissasembleInstruction(self: *const Chunk, offset: usize, writer: anytype) @TypeOf(writer).Error!usize {
        // So we know where done
        if (offset >= self.code.items.len) return 0;
        try writer.print("{X:0>4} ", .{@truncate(u32, offset)});

        if (offset > 0 and (self.lines.items[offset] == self.lines.items[offset - 1]))
            try writer.print("   | ", .{})
        else
            try writer.print("{d: >4} ", .{self.lines.items[offset]});

        const instruction: OpCode = @intToEnum(OpCode, self.code.items[offset]);
        const n = switch (instruction) {
            .Constant => try self.constantInstruction("OP_CONSTANT", offset, writer),
            else => try simpleInstruction(instruction, offset, writer),
            // else => b: {
            //     try writer.print("Unknown opcode {}\n", .{instruction});
            //     break :b offset + 1;
            // },
        };
        try writer.print("\n", .{});
        return n;
    }
    pub fn format(self: Chunk, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try self.dissasembleChunk(fmt, writer);
    }
    // ---------------------------------------------------------------------
    // ---------------------------------------------------------------------
};
