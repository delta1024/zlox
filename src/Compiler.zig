const std = @import("std");
const options = @import("build_options");
const Parser = @This();
const Scanner = @import("./Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = @import("./Chunk.zig");
const OpCode = Chunk.OpCode;
const val_mod = @import("./value.zig");
const Value = val_mod.Value;
const Allocator = @import("./memory.zig");
const numberVal = val_mod.numberVal;
const boolVal = val_mod.boolVal;
const objVal = val_mod.objValue;

pub const Error = error{ UnterminatedString, UnexpectedCharacter, Compiler, OutOfMemory, ParseIntError } || Scanner.Error || Chunk.Error || std.fmt.ParseIntError;

compiling_chunk: *Chunk = undefined,
current: Token = undefined,
previous: Token = undefined,
scanner: Scanner,
allocator: *Allocator,
had_error: bool = false,
panic_mode: bool = false,

const Precedence = enum {
    // zig fmt: off
    None,
    Assignment,  // =
    Or,          // or
    And,         // and
    Equality,    // == !=
    Comparison,  // < > <= >=
    Term,        // + -
    Factor,      // * /
    Unary,       // ! -
    Call,        // . ()
    Primary,
    // zig fmt: on
};

const ParseRule = struct {
    const ParseFn = fn (*Parser) Error!void;
    prefix: ?ParseFn = null,
    infix: ?ParseFn = null,
    precedence: Precedence = .None,
};

pub fn init(source: []const u8, allocator: *Allocator) Parser {
    return .{
        .scanner = .{ .source = source },
        .allocator = allocator,
    };
}

fn currentChunk(self: *Parser) *Chunk {
    return self.compiling_chunk;
}
fn errorAt(self: *Parser, token: *Token, message: []const u8, err: Error) Error {
    if (self.panic_mode) return error.Compiler;
    self.panic_mode = true;
    var mess = message;
    const stderr = std.io.getStdErr().writer();

    try stderr.print("[line {d}] Error", .{token.line});

    if (token.type == .Eof) {
        _ = try stderr.write(" at end");
    } else if (err != error.Compiler) {
        mess = switch (err) {
            Scanner.Error.UnterminatedString => "unterminated string",
            Scanner.Error.UnexpectedCharacter => "unexpected character",
            else => {
                try stderr.print("Unexpected system err: {}", .{err});
                @panic("unexpected erro");
            },
        };
    } else {
        try stderr.print(" at '{s}'", .{token.start});
    }

    try stderr.print(": {s}\n", .{mess});
    self.had_error = true;
    return error.Compiler;
}
fn error_(self: *Parser, message: []const u8) Error {
    return self.errorAt(&self.previous, message, error.Compiler);
}
fn errorAtCurrent(self: *Parser, message: []const u8) Error {
    return self.errorAt(&self.current, message, error.Compiler);
}
fn advance(self: *Parser) Error!void {
    self.previous = self.current;

    self.current = self.scanner.next() catch |err| {
        return self.errorAt(&self.current, self.current.start, err);
    } orelse Token{ .type = .Eof, .start = "", .line = self.previous.line };
}
fn consume(self: *Parser, id: TokenType, comptime message: []const u8) Error!void {
    if (self.current.type == id) {
        try self.advance();
        return;
    }

    return self.errorAtCurrent(message);
}
fn emitByte(self: *Parser, byte: u8) Error!void {
    try self.currentChunk().push_code(byte, @truncate(u8, self.previous.line));
}
fn emitBytes(self: *Parser, byte1: u8, byte2: u8) Error!void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}
fn emitReturn(self: *Parser) Error!void {
    try self.emitByte(@enumToInt(OpCode.Return));
}
fn makeConstant(self: *Parser, value: Value) Error!u8 {
    const constant = try self.currentChunk().push_value(value);
    if (constant > std.math.maxInt(u8)) {
        return self.error_("Too many constants in one chunk.");
    }
    return constant;
}
fn emitConstant(self: *Parser, value: Value) Error!void {
    try self.emitBytes(@enumToInt(OpCode.Constant), try self.makeConstant(value));
}
fn endCompiler(self: *Parser) Error!void {
    try self.emitReturn();
    if (options.debug_print_code and !self.had_error)
        try Chunk.disassembleChunk(self.currentChunk(), "code");
}
fn binary(self: *Parser) Error!void {
    const operator_type = self.previous.type;
    const rule = getRule(operator_type);
    try self.parsePrecedence(@intToEnum(Precedence, @enumToInt(rule.precedence) + 1));

    switch (operator_type) {
        .BangEqual => try self.emitBytes(@enumToInt(OpCode.Equal), @enumToInt(OpCode.Not)),
        .EqualEqual => try self.emitByte(@enumToInt(OpCode.Equal)),
        .Greater => try self.emitByte(@enumToInt(OpCode.Greater)),
        .GreaterEqual => try self.emitBytes(@enumToInt(OpCode.Less), @enumToInt(OpCode.Not)),
        .Less => try self.emitByte(@enumToInt(OpCode.Less)),
        .LessEqual => try self.emitBytes(@enumToInt(OpCode.Greater), @enumToInt(OpCode.Not)),
        .Plus => try self.emitByte(@enumToInt(OpCode.Add)),
        .Minus => try self.emitByte(@enumToInt(OpCode.Subtract)),
        .Star => try self.emitByte(@enumToInt(OpCode.Multiply)),
        .Slash => try self.emitByte(@enumToInt(OpCode.Divide)),
        else => unreachable,
    }
}
fn literal(self: *Parser) Error!void {
    switch (self.previous.type) {
        .False => try self.emitByte(@enumToInt(OpCode.False)),
        .Nil => try self.emitByte(@enumToInt(OpCode.Nil)),
        .True => try self.emitByte(@enumToInt(OpCode.True)),
        else => unreachable,
    }
}
fn grouping(self: *Parser) Error!void {
    try self.expression();
    try self.consume(.RightParen, "Expect ')' after expression.");
}
fn number(self: *Parser) Error!void {
    const value = try std.fmt.parseFloat(f64, self.previous.start);
    try self.emitConstant(numberVal(value));
}
fn string(self: *Parser) Error!void {
    try self.emitConstant(objVal(&(try self.allocator.copyString(self.previous.start[1 .. self.previous.start.len - 1])).obj));
}
fn unary(self: *Parser) Error!void {
    const operator_type = self.previous.type;

    // Compile the operand
    try self.parsePrecedence(.Assignment);

    // Emit the operator instruction
    switch (operator_type) {
        .Bang => try self.emitByte(@enumToInt(OpCode.Not)),
        .Minus => try self.emitByte(@enumToInt(OpCode.Negate)),
        else => unreachable,
    }
}
const rules: [39]ParseRule = [39]ParseRule{
    // LeftParen
    .{ .prefix = grouping },
    // RightParen
    .{},
    // LeftBrace
    .{},
    // RightBrace
    .{},
    // Comma
    .{},
    // Dot
    .{},
    // Minus
    .{ .prefix = unary, .infix = binary, .precedence = .Term },
    // Plus
    .{ .infix = binary, .precedence = .Term },
    // Semicolon
    .{},
    // Slash
    .{ .infix = binary, .precedence = .Factor },
    // Star
    .{ .infix = binary, .precedence = .Factor },
    // Bang
    .{ .prefix = unary },
    // BangEqual
    .{},
    // Equal
    .{},
    // EqualEqual
    .{ .infix = binary, .precedence = .Equality },
    // Greater
    .{ .infix = binary, .precedence = .Comparison },
    // GreaterEqual
    .{ .infix = binary, .precedence = .Comparison },
    // Less
    .{ .infix = binary, .precedence = .Comparison },
    // LessEqual
    .{ .infix = binary, .precedence = .Comparison },
    // Identifier
    .{},
    // String
    .{ .prefix = string },
    // Number
    .{ .prefix = number },
    // And
    .{},
    // Class
    .{},
    // Else
    .{},
    // False
    .{ .prefix = literal },
    // For
    .{},
    // Fun
    .{},
    // If
    .{},
    // Nil
    .{ .prefix = literal },
    // Or
    .{},
    // Print
    .{},
    // Return
    .{},
    // Super
    .{},
    // This
    .{},
    // True
    .{ .prefix = literal },
    // Var
    .{},
    // While
    .{},
    // Eof
    .{},
};
fn parsePrecedence(self: *Parser, precedence: Precedence) Error!void {
    try self.advance();
    const prefixRule = getRule(self.previous.type).prefix orelse {
        return self.error_("Expect expression.");
    };

    try prefixRule(self);

    while (@enumToInt(precedence) <= @enumToInt(getRule(self.current.type).precedence)) {
        try self.advance();
        const infixRule = getRule(self.previous.type).infix.?;
        try infixRule(self);
    }
}
fn getRule(id: TokenType) *const ParseRule {
    return &rules[@enumToInt(id)];
}
fn expression(self: *Parser) Error!void {
    try self.parsePrecedence(.Assignment);
}
pub fn compile(self: *Parser, chunk: *Chunk) Error!void {
    self.compiling_chunk = chunk;
    try self.advance();
    try self.expression();
    try self.consume(.Eof, "Expect end of expression.");
    try self.endCompiler();
    if (self.had_error) return error.Compiler;
}
