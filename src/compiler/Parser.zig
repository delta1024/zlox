const std = @import("std");
const build_options = @import("build_options");
const Chunk = @import("../chunk.zig").Chunk;
const Value = @import("../value.zig").Value;
const OpCode = @import("../chunk.zig").OpCode;
const TokenType = @import("../lexer.zig").TokenType;
const Token = @import("../lexer.zig").Token;
const Lexer = @import("../lexer.zig").Lexer;
const Self = @This();

pub const Error = error{ ConsumeError, OutOfMemory, InvalidCharacter } || @import("../chunk.zig").Chunk.Error || std.fmt.ParseFloatError;

current: ?Token = null,
previous: ?Token = null,
tokens: Lexer,
chunk: *Chunk,
had_error: bool = false,

pub fn init(source: []const u8, chunk: *Chunk) Self {
    return .{ .tokens = Lexer.init(source), .chunk = chunk };
}
pub fn makeConstant(self: *Self, value: Value) Error!u8 {
    const constant = try self.currentChunk().addConstant(value);
    if (constant > std.math.maxInt(u8))
        return self.errorAtPrev("Too many constants in one chunk");
    return @truncate(u8, constant);
}
pub fn emitConstant(self: *Self, value: Value) Error!void {
    try self.emitBytes(OpCode.Constant, try self.makeConstant(value));
}
pub fn currentChunk(self: *Self) *Chunk {
    return self.chunk;
}
pub fn emitByte(self: *Self, byte: anytype) Error!void {
    try self.currentChunk().pushByte(@TypeOf(byte), byte, @truncate(u8, self.previous.?.line));
}
pub fn emitBytes(self: *Self, byte1: anytype, byte2: anytype) Error!void {
    try self.currentChunk().pushBytes(byte1, byte2, @truncate(u8, self.previous.?.line));
}
pub fn endCompiler(self: *Self) Error!void {
    try self.emitReturn();
    if (build_options.debug_print_code) {
        self.currentChunk().dissasembleChunk("code", std.io.getStdErr().writer()) catch unreachable;
    }
}
pub fn emitReturn(self: *Self) Error!void {
    try self.emitByte(OpCode.Return);
}
pub fn advance(self: *Self) Error!void {
    self.previous = self.current;

    self.current = self.tokens.next();

    if (self.current) |cur| {
        if (cur.id != .Error) return else {
            return self.errorAtCurrent(if (self.current) |t| t.lexum else "");
        }
    }
}
pub fn consume(self: *Self, id: TokenType, message: []const u8) Error!void {
    if (self.current.?.id == id) {
        try self.advance();
        return;
    }
    return self.errorAtCurrent(message);
}
pub fn errorAtCurrent(
    self: *Self,
    message: []const u8,
) Error {
    return self.errorAt(self.current.?, message);
}
pub fn errorAtPrev(self: *Self, message: []const u8) Error {
    return self.errorAt(self.previous.?, message);
}
pub fn errorAt(self: *Self, token: Token, message: []const u8) Error {
    const writer = std.io.getStdErr().writer();
    writer.print("[line {d}] Error", .{token.line}) catch unreachable;

    if (token.id == .Eof) {
        writer.print(" at end", .{}) catch unreachable;
    } else if (token.id == .Error) {
        // Nothing.
    } else {
        writer.print(" at '{s}'", .{token.lexum}) catch unreachable;
    }

    writer.print(": {s}", .{message}) catch unreachable;
    self.had_error = true;
    return error.ConsumeError;
}
