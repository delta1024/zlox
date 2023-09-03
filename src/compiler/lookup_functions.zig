const std = @import("std");
const Parser = @import("Parser.zig");
const OpCode = @import("../chunk.zig").OpCode;
const Precedence = @import("precedence.zig").Precedence;
const getRule = @import("precedence.zig").getRule;
const Value = @import("../value.zig").Value;
pub fn parsePrecedence(parser: *Parser, prec: Precedence, can_assign: bool) Parser.Error!void {
    try parser.advance();
    const prefixRule = getRule(parser.previous.?.id).prefix orelse return parser.errorAtPrev("Expect expression");

    try prefixRule(parser, can_assign);

    while (@enumToInt(prec) <= @enumToInt(getRule(parser.current.?.id).precedence)) {
        try parser.advance();
        const infixRule = getRule(parser.previous.?.id).infix.?;
        try infixRule(parser, can_assign);
    }
}
pub fn expression(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    try parsePrecedence(parser, .Assignment, true);
}
pub fn number(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    const value = try std.fmt.parseFloat(f64, parser.previous.?.lexum);
    try parser.emitConstant(Value{ .number = value });
}
pub fn grouping(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    try expression(parser, false);
    try parser.consume(.RightParen, "Expect ')' after expression");
}

pub fn unary(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    const op = parser.previous.?.id;
    try parsePrecedence(parser, .Unary, false);

    switch (op) {
        .Minus => try parser.emitByte(OpCode.Negate),
        .Bang => try parser.emitByte(OpCode.Not),
        else => unreachable,
    }
}
pub fn binary(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    const operator_type = parser.previous.?.id;
    const rule = getRule(operator_type);

    try parsePrecedence(parser, @intToEnum(Precedence, @enumToInt(rule.precedence) + 1), false);

    switch (operator_type) {
        .BangEqual => try parser.emitBytes(OpCode.Equal, OpCode.Not),
        .EqualEqual => try parser.emitByte(OpCode.Equal),
        .Greater => try parser.emitByte(OpCode.Greater),
        .GreaterEqual => try parser.emitBytes(OpCode.Less, OpCode.Not),
        .Less => try parser.emitByte(OpCode.Less),
        .LessEqual => try parser.emitBytes(OpCode.Greater, OpCode.Not),
        .Plus => try parser.emitByte(OpCode.Add),
        .Minus => try parser.emitByte(OpCode.Subtract),
        .Star => try parser.emitByte(OpCode.Multiply),
        .Slash => try parser.emitByte(OpCode.Divide),
        else => unreachable,
    }
}

pub fn literal(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    std.debug.print("{?}", .{parser.previous.?.id});
    try parser.emitByte(switch (parser.previous.?.id) {
        .False => OpCode.False,
        .True => OpCode.True,
        .Nil => OpCode.Nil,
        else => unreachable,
    });
}
