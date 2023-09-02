const Parser = @import("Parser.zig");
const TokenType = @import("../lexer.zig").TokenType;
const lUF = @import("lookup_functions.zig");
pub const Precedence = enum(usize) {
    None = 0,
    /// =
    Assignment,
    /// or
    Or,
    /// and
    And,
    /// == !=
    Equality,
    /// < > <= >=
    Comparison,
    /// + -
    Term,
    /// * /
    Factor,
    /// ! -
    Unary,
    /// . ()
    Call,
    Primary,
};
pub fn getRule(token: TokenType) ParseRule {
    return switch (token) {
        .LeftParen => ParseRule.init(.None, .{ .p = lUF.grouping }),
        .Minus => ParseRule.init(.Term, .{ .p = lUF.unary, .i = lUF.binary }),
        .Plus => ParseRule.init(.Term, .{ .i = lUF.binary }),
        .Slash, .Star => ParseRule.init(.Factor, .{ .i = lUF.binary }),
        .Number => ParseRule.init(.None, .{ .p = lUF.number }),
        else => ParseRule.init(.None, .{}),
    };
}
pub const ParseFn = *const fn (parser: *Parser) Parser.Error!void;

pub const ParseRule = struct {
    const ProtoRule = struct {
        p: ?ParseFn = null,
        i: ?ParseFn = null,
    };

    prefix: ?ParseFn = null,
    infix: ?ParseFn = null,
    precedence: Precedence,

    pub fn init(prec: Precedence, proto: ProtoRule) ParseRule {
        return .{
            .prefix = proto.p,
            .infix = proto.i,
            .precedence = prec,
        };
    }
};
