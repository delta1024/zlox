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
        else => unreachable,
    }
}
pub fn binary(parser: *Parser, can_assign: bool) Parser.Error!void {
    _ = can_assign;
    const operator_type = parser.previous.?.id;
    const rule = getRule(operator_type);

    try parsePrecedence(parser, @intToEnum(Precedence, @enumToInt(rule.precedence) + 1), false);

    try parser.emitByte(switch (operator_type) {
        .Plus => OpCode.Add,
        .Minus => OpCode.Subtract,
        .Star => OpCode.Multiply,
        .Slash => OpCode.Divide,
        else => unreachable,
    });
}
