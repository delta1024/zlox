const std = @import("std");
const Parser = @import("Parser.zig");
const OpCode = @import("../chunk.zig").OpCode;
const Precedence = @import("precedence.zig").Precedence;
const getRule = @import("precedence.zig").getRule;
pub fn parsePrecedence(parser: *Parser, prec: Precedence) Parser.Error!void {
    try parser.advance();
    const prefixRule = getRule(parser.previous.?.id).prefix orelse return parser.errorAtPrev("Expect expression");

    try prefixRule(parser);

    while (@enumToInt(prec) <= @enumToInt(getRule(parser.current.?.id).precedence)) {
        try parser.advance();
        const infixRule = getRule(parser.previous.?.id).infix.?;
        try infixRule(parser);
    }
}
pub fn expression(parser: *Parser) Parser.Error!void {
    try parsePrecedence(parser, .Assignment);
}
pub fn number(parser: *Parser) Parser.Error!void {
    const value = try std.fmt.parseFloat(f64, parser.previous.?.lexum);
    try parser.emitConstant(value);
}
pub fn grouping(parser: *Parser) Parser.Error!void {
    try expression(parser);
    try parser.consume(.RightParen, "Expect ')' after expression");
}

pub fn unary(parser: *Parser) Parser.Error!void {
    const op = parser.previous.?.id;
    try parsePrecedence(parser, .Unary);

    switch (op) {
        .Minus => try parser.emitByte(OpCode.Negate),
        else => unreachable,
    }
}
pub fn binary(parser: *Parser) Parser.Error!void {
    const operator_type = parser.previous.?.id;
    const rule = getRule(operator_type);

    try parsePrecedence(parser, @intToEnum(Precedence, @enumToInt(rule.precedence) + 1));

    try parser.emitByte(switch (operator_type) {
        .Plus => OpCode.Add,
        .Minus => OpCode.Subtract,
        .Star => OpCode.Multiply,
        .Slash => OpCode.Divide,
        else => unreachable,
    });
}
