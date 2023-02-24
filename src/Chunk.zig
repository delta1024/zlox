const std = @import("std");
const memory = @import("./memory.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Array = std.ArrayListUnmanaged;
const Value = @import("./value.zig").Value;
pub const Error = error{WriteError} || std.os.WriteError;
const Chunk = @This();
allocator: *Allocator,
code: Array(u8),
lines: Array(u8),
constants: Array(Value),
pub fn init(allocator: *Allocator) Chunk {
    return .{
        .allocator = allocator,
        .code = Array(u8){},
        .lines = Array(u8){},
        .constants = Array(Value){},
    };
}
pub fn deinit(self: *Chunk) void {
    self.code.deinit(self.allocator);
    self.lines.deinit(self.allocator);
    self.constants.deinit(self.allocator);
}
pub fn push_code(self: *Chunk, code: u8, line: u8) !void {
    try self.code.append(self.allocator, code);
    try self.lines.append(self.allocator, line);
}
pub fn push_value(self: *Chunk, value: Value) !u8 {
    try self.constants.append(self.allocator, value);
    return @truncate(u8, self.constants.items.len - 1);
}

pub fn format(self: *const Chunk, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    var i: usize = 0;
    while (i < self.code.items.len) {
        i = try disassembleInstruction(self, i, writer);
    }
}

fn simpleInstruction(instruction: OpCode, offset: usize, writer: anytype) !usize {
    try writer.print("{}\n", .{instruction});
    return offset + 1;
}
fn byteInstruction(chunk: *const Chunk, instruction: OpCode, offset: usize, writer: anytype) !usize {
    const slot = chunk.code.items[offset + 1];
    try writer.print("{: >16} {d:4}\n", .{ instruction, slot });
    return offset + 2;
}
fn jumpInstruction(chunk: *const Chunk, instruction: OpCode, sign: isize, offset: usize, writer: anytype) !usize {
    var jump = std.math.shl(u16, @intCast(u16, chunk.code.items[offset + 1]), 8);
    jump |= chunk.code.items[offset + 2];
    try writer.print("{: >16} {d:4} -> {d}\n", .{ instruction, offset, @bitCast(isize, offset) + 3 + sign * @bitCast(i16, jump) });
    return offset + 3;
}
fn constantInstruction(chunk: *const Chunk, instruction: OpCode, offset: usize, writer: anytype) !usize {
    const pos = chunk.code.items[offset + 1];

    try writer.print("{: >16} {d:4} '{}'\n", .{ instruction, pos, chunk.constants.items[pos] });
    return offset + 2;
}
pub fn disassembleInstruction(chunk: *const Chunk, offset: usize, writer: anytype) !usize {
    try writer.print("{d:0>4} ", .{offset});
    if ((offset > 0) and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        try writer.print("   | ", .{});
    } else {
        try writer.print("{d:0>4} ", .{chunk.lines.items[offset]});
    }
    const instruction = @intToEnum(OpCode, chunk.code.items[offset]);
    switch (instruction) {
        .Loop => return try jumpInstruction(chunk, instruction, -1, offset, writer),
        .Jump, .JumpIfFalse => return try jumpInstruction(chunk, instruction, 1, offset, writer),
        .Constant, .DefineGlobal, .GetGlobal, .SetGlobal => return try constantInstruction(chunk, instruction, offset, writer),
        .GetLocal, .SetLocal, .Call => return try byteInstruction(chunk, instruction, offset, writer),
        else => return try simpleInstruction(instruction, offset, writer),
    }
}
pub fn disassembleChunk(chunk: *const Chunk, name: []const u8) !void {
    var writer = std.io.getStdOut().writer();
    try writer.print("== {s} ==\n{}", .{ name, chunk });
}
pub const OpCode = enum(u8) {
    Constant,
    Nil,
    True,
    False,
    DefineGlobal,
    GetGlobal,
    SetGlobal,
    GetLocal,
    SetLocal,
    Equal,
    Greater,
    Less,
    Add,
    Subtract,
    Multiply,
    Divide,
    Not,
    Negate,
    Print,
    JumpIfFalse,
    Jump,
    Pop,
    Loop,
    Call,
    Return,
    pub fn format(self: OpCode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        const width = options.width orelse 0;
        var i: usize = 0;
        if (options.alignment == .Left or options.alignment == .Center) {
            while (i < width) : (i += 1) {
                try writer.print("{c}", .{options.fill});
            }
        }
        const isUpper = std.ascii.isUpper;
        const toUpper = std.ascii.toUpper;
        _ = try writer.write("OP");
        i += 2;
        for (@tagName(self)) |c| {
            if (isUpper(c)) {
                _ = try writer.write("_");
                i += 1;
                try writer.print("{c}", .{c});
                i += 1;
                continue;
            }

            try writer.print("{c}", .{toUpper(c)});
            i += 1;
        }
        if (options.alignment == .Right or options.alignment == .Center) {
            while (i < width) : (i += 1) {
                try writer.print("{c}", .{options.fill});
            }
        }
    }
};
