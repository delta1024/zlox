const std = @import("std");
const mem = std.mem;
const math = std.math;
const options = @import("build_options");
usingnamespace @import("./value.zig");
const Parser = @This();
const Scanner = @import("./Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = @import("./Chunk.zig");
const OpCode = Chunk.OpCode;
const Allocator = @import("./Allocator.zig");

pub const Error = error{ UnterminatedString, UnexpectedCharacter, Compiler, OutOfMemory, ParseIntError } || Scanner.Error || Chunk.Error || std.fmt.ParseIntError;

compiling_chunk: *Chunk = undefined,
current: Token = undefined,
previous: Token = undefined,
compiler: *Compiler = undefined,
scanner: Scanner,
allocator: *Allocator,
had_error: bool = false,
panic_mode: bool = false,

pub const UINT8_COUNT = std.math.maxInt(u8) + 1;
const Compiler = struct {
    const Local = struct {
        name: Token = undefined,
        depth: isize = -1,
    };
    locals: [UINT8_COUNT]Local = undefined,
    local_count: usize = 0,
    scope_depth: usize = 0,
    fn markInitialized(self: *Compiler) void {
        self.locals[self.local_count - 1].depth = @intCast(isize, self.scope_depth);
    }
};
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
    const ParseFn = fn (*Parser, bool) Error!void;
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
                @panic("unexpected error");
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
fn check(self: *Parser, id: TokenType) bool {
    return self.current.type == id;
}
fn match(self: *Parser, id: TokenType) Error!bool {
    if (!self.check(id)) return false;
    try self.advance();
    return true;
}
fn emitByte(self: *Parser, byte: u8) Error!void {
    try self.currentChunk().push_code(byte, @truncate(u8, self.previous.line));
}
fn emitBytes(self: *Parser, byte1: u8, byte2: u8) Error!void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}
fn emitJump(self: *Parser, instruction: OpCode) Error!usize {
    try self.emitByte(@enumToInt(instruction));
    try self.emitByte(0xff);
    try self.emitByte(0xff);
    return self.currentChunk().code.items.len - 2;
}
fn patchJump(self: *Parser, offset: usize) Error!void {
    // -2 to adjust for the jump offset itself.
    const jump = self.currentChunk().code.items.len - offset - 2;

    if (jump > math.maxInt(u16)) {
        return self.error_("Too much code to jump over");
    }
    self.currentChunk().code.items[offset] = @truncate(u8, math.shr(u16, @truncate(u16, jump), 8)) & 0xff;
    self.currentChunk().code.items[offset + 1] = @truncate(u8, jump) & 0xff;
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
fn beginScope(self: *Parser) void {
    self.compiler.scope_depth += 1;
}
fn endScope(self: *Parser) Error!void {
    self.compiler.scope_depth -= 1;

    // zig fmt: off
    while (self.compiler.local_count > 0 and 
        self.compiler.locals[self.compiler.local_count - 1].depth > 
        self.compiler.scope_depth) : (self.compiler.local_count -= 1) {
        try self.emitByte(@enumToInt(OpCode.Pop));
    }
    // zig fmt: on
}
fn binary(self: *Parser, _: bool) Error!void {
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
fn literal(self: *Parser, _: bool) Error!void {
    switch (self.previous.type) {
        .False => try self.emitByte(@enumToInt(OpCode.False)),
        .Nil => try self.emitByte(@enumToInt(OpCode.Nil)),
        .True => try self.emitByte(@enumToInt(OpCode.True)),
        else => unreachable,
    }
}
fn grouping(self: *Parser, _: bool) Error!void {
    try self.expression();
    try self.consume(.RightParen, "Expect ')' after expression.");
}
fn number(self: *Parser, _: bool) Error!void {
    const value = try std.fmt.parseFloat(f64, self.previous.start);
    try self.emitConstant(numberVal(value));
}
fn string(self: *Parser, _: bool) Error!void {
    try self.emitConstant(objVal(&(try self.allocator.copyString(self.previous.start[1 .. self.previous.start.len - 1])).obj));
}
fn namedVariable(self: *Parser, name: Token, can_assign: bool) Error!void {
    var get_op: u8 = undefined;
    var set_op: u8 = undefined;
    var arg = try self.resolveLocal(&name);
    if (arg) |_| {
        get_op = @enumToInt(OpCode.GetLocal);
        set_op = @enumToInt(OpCode.SetLocal);
    } else {
        arg = try self.identifierConstant(&name);
        get_op = @enumToInt(OpCode.GetGlobal);
        set_op = @enumToInt(OpCode.SetGlobal);
    }

    if (can_assign and try self.match(.Equal)) {
        try self.expression();
        try self.emitBytes(set_op, arg.?);
    } else {
        try self.emitBytes(get_op, arg.?);
    }
}
fn variable(self: *Parser, can_assign: bool) Error!void {
    try self.namedVariable(self.previous, can_assign);
}
fn unary(self: *Parser, _: bool) Error!void {
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
    .{ .prefix = variable },
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

    const can_assign = @enumToInt(precedence) <= @enumToInt(Precedence.Assignment);
    try prefixRule(self, can_assign);

    while (@enumToInt(precedence) <= @enumToInt(getRule(self.current.type).precedence)) {
        try self.advance();
        const infixRule = getRule(self.previous.type).infix.?;
        try infixRule(self, can_assign);
    }

    if (can_assign and try self.match(.Equal)) {
        return self.error_("Invalid assignment target");
    }
}
fn identifierConstant(self: *Parser, name: *const Token) Error!u8 {
    return try self.makeConstant(objVal(&(try self.allocator.copyString(name.start)).obj));
}
fn addLocal(self: *Parser, name: Token) Error!void {
    if (self.compiler.local_count == UINT8_COUNT) {
        return self.error_("Too many variables in function.");
    }
    var local = &self.compiler.locals[self.compiler.local_count];
    self.compiler.local_count += 1;
    local.name = name;
    local.depth = -1;
}
fn resolveLocal(self: *Parser, name: *const Token) Error!?u8 {
    var i: usize = self.compiler.local_count - 1;
    while (i >= 0) : (i -= 1) {
        const local = &self.compiler.locals[i];
        if (mem.eql(u8, name.start, local.name.start)) {
            if (local.depth == -1) {
                return self.error_("Can't read local variable in it's own initializer.");
            }
            return @truncate(u8, i);
        }
    }
    return null;
}
fn declareVariable(self: *Parser) Error!void {
    if (self.compiler.scope_depth == 0) return;

    const name = &self.previous;
    var i: usize = self.compiler.local_count;
    while (i >= 0) : (i -= 1) {
        const local = &self.compiler.locals[i];
        if (local.depth != -1 and local.depth < self.compiler.scope_depth) {
            break;
        }
        if (mem.eql(u8, name.start, local.name.start)) {
            return self.error_("Already a variable with this name in this scope.");
        }
    }
    try self.addLocal(name.*);
}
fn parseVariable(self: *Parser, comptime error_message: []const u8) Error!u8 {
    try self.consume(.Identifier, error_message);
    try self.declareVariable();
    if (self.compiler.scope_depth > 0) return 0;

    return try self.identifierConstant(&self.previous);
}
fn defineVariable(self: *Parser, global: u8) Error!void {
    if (self.compiler.scope_depth > 0) {
        self.compiler.markInitialized();
        return;
    }
    try self.emitBytes(@enumToInt(OpCode.DefineGlobal), global);
}
fn getRule(id: TokenType) *const ParseRule {
    return &rules[@enumToInt(id)];
}
fn expression(self: *Parser) Error!void {
    try self.parsePrecedence(.Assignment);
}
fn block(self: *Parser) Error!void {
    while (!self.check(.RightBrace) and !self.check(.Eof)) {
        self.declaration();
    }

    try self.consume(.RightBrace, "Expect '}' after block.");
}
fn varDeclaration(self: *Parser) Error!void {
    const global = try self.parseVariable("Expect variable name");

    if (try self.match(.Equal)) {
        try self.expression();
    } else {
        try self.emitByte(@enumToInt(OpCode.Nil));
    }

    try self.consume(.Semicolon, "Expect ';' after variable declaration.");
    try self.defineVariable(global);
}
fn expressionStatement(self: *Parser) Error!void {
    try self.expression();
    try self.consume(.Semicolon, "Expect ';' after expression.");
    try self.emitByte(@enumToInt(OpCode.Pop));
}
fn ifStatement(self: *Parser) Error!void {
    try self.consume(.LeftParen, "Expect '(' after 'if'");
    try self.expression();
    try self.consume(.RightParen, "Expect ')' after condition.");

    const then_jump = try self.emitJump(.JumpIfFalse);
    try self.emitByte(@enumToInt(OpCode.Pop));
    try self.statement();
    const else_jump = try self.emitJump(.Jump);

    try self.patchJump(then_jump);
    try self.emitByte(@enumToInt(OpCode.Pop));

    if (try self.match(.Else)) try self.statement();
    try self.patchJump(else_jump);
}
fn printStatement(self: *Parser) Error!void {
    try self.expression();
    try self.consume(.Semicolon, "Expect ';' after value.");
    try self.emitByte(@enumToInt(OpCode.Print));
}
fn synchronize(self: *Parser) void {
    self.panic_mode = false;

    while (self.current.type != .Eof) {
        if (self.previous.type == .Semicolon) return;
        switch (self.current.type) {
            .Class, .Fun, .Var, .For, .If, .While, .Print, .Return => return,
            else => self.advance() catch self.synchronize(),
        }
    }
}
fn declaration(self: *Parser) void {
    if (self.match(.Var) catch {
        self.synchronize();
        return;
    }) {
        self.varDeclaration() catch self.synchronize();
    } else {
        self.statement() catch self.synchronize();
    }
}
fn statement(self: *Parser) Error!void {
    if (try self.match(.Print)) {
        try self.printStatement();
    } else if (try self.match(.If)) {
        try self.ifStatement();
    } else if (try self.match(.LeftBrace)) {
        self.beginScope();
        try self.block();
        try self.endScope();
    } else {
        try self.expressionStatement();
    }
}
pub fn compile(self: *Parser, chunk: *Chunk) Error!void {
    var compiler = Compiler{};
    self.compiler = &compiler;
    self.compiling_chunk = chunk;
    try self.advance();
    while (!try self.match(.Eof)) {
        self.declaration();
    }
    try self.endCompiler();
    if (self.had_error) return error.Compiler;
}
