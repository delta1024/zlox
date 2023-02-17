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
fn constantInstruction(chunk: *const Chunk, instruction: OpCode, offset: usize, writer: anytype) !usize {
    const pos = chunk.code.items[offset + 1];

    try writer.print("{: >16} {d} '{d:.2}'\n", .{ instruction, pos, chunk.constants.items[pos] });
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
        .Constant => return try constantInstruction(chunk, instruction, offset, writer),
        else => return try simpleInstruction(instruction, offset, writer),
    }
}
pub fn disassembleChunk(chunk: *const Chunk, name: []const u8) !void {
    var writer = std.io.getStdOut().writer();
    try writer.print("== {s} ==\n{}", .{ name, chunk });
}
pub const OpCode = enum(u8) {
    Constant,
    Add,
    Subtract,
    Divide,
    Multiply,
    Negate,
    Return,
    pub fn format(self: OpCode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        var tag_name: [255]u8 = undefined;
        var i: usize = if (options.alignment == .Left or options.alignment == .Center) bk: {
            var j: usize = 0;
            const max = options.width orelse 0;
            while (j < max) : (j += 1) {
                tag_name[j] = options.fill;
            }
            break :bk j;
        } else bk: {
            break :bk 0;
        };
        for ("OP") |c| {
            tag_name[i] = c;
            i += 1;
        }
        for (@tagName(self)) |c| {
            if (std.ascii.isUpper(c)) {
                tag_name[i] = '_';
                i += 1;
            }
            tag_name[i] = std.ascii.toUpper(c);
            i += 1;
        }
        if (options.alignment == .Right or options.alignment == .Center) {
            while (i < options.width orelse 0) : (i += 1) {
                tag_name[i] = options.fill;
            }
        }
        tag_name[i] = 0;
        try writer.print("{s}", .{tag_name});
    }
};
