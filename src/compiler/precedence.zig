const Parser = @import("Parser.zig");
const TokenType = @import("../lexer.zig").TokenType;

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
const LuF = @import("lookup_functions.zig");
pub fn getRule(token: TokenType) ParseRule {
    return switch (token) {
        .LeftParen => ParseRule.init(.None, .{ .p = LuF.grouping }),
        .Minus => ParseRule.init(.Term, .{ .p = LuF.unary, .i = LuF.binary }),
        .Plus => ParseRule.init(.Term, .{ .i = LuF.binary }),
        .Slash, .Star => ParseRule.init(.Factor, .{ .i = LuF.binary }),
        .Number => ParseRule.init(.None, .{ .p = LuF.number }),
        .False, .True, .Nil => ParseRule.init(.None, .{ .p = LuF.literal }),
        .Bang => ParseRule.init(.None, .{ .p = LuF.unary }),
        .BangEqual, .EqualEqual => ParseRule.init(.Equality, .{ .i = LuF.binary }),
        .Greater, .GreaterEqual, .Less, .LessEqual => ParseRule.init(.Comparison, .{ .i = LuF.binary }),
        else => ParseRule.init(.None, .{}),
    };
}
pub const ParseFn = *const fn (parser: *Parser, bool) Parser.Error!void;

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
