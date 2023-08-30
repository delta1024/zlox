const std = @import("std");
pub const TokenType = enum(u8) {
    // zig fmt: off
    // Single-character tokens.
    LeftParen, RightParen,
    LeftBrace, RightBrace,
    Comma, Dot, Minus, Plus,
    Semicolon, Slash, Star,
    // One or two character tokens.
    Bang, BangEqual,
    Equal, EqualEqual,
    Greater, GreaterEqual,
    Less, LessEqual,
    // Literals.
    Identifier, String, Number,
    // Keywords.
    And, Class, Else, False,
    For, Fun, If, Nil, Or,
    Print, Return, Super, This,
    True, Var, While,

    Error, Eof,
    // zig fmt: on

    pub fn format(self: TokenType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{@tagName(self)});
    }
};
pub const Token = struct {
    id: TokenType,
    lexum: []const u8,
    line: u32,
    pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Token {{\n\tid: {},\n\tlexum: \"{s}\",\n\tline: {d},\n}}", .{ self.id, self.lexum, self.line });
    }
    pub fn init(id: TokenType, lexum: []const u8, line: u32) Token {
        return Token{
            .id = id,
            .lexum = lexum,
            .line = line,
        };
    }
};
