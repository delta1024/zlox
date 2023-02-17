const std = @import("std");
const mem = std.mem;
const Scanner = @This();
pub const Error = error{ UnterminatedString, UnexpectedCharacter };

start: usize = 0,
current: usize = 0,
line: usize = 1,
source: []const u8,
fn isAlpha(c: u8) bool {
    // zig fmt: off
    return (c >= 'a' and c <= 'z') or
           (c >= 'A' and c <= 'Z') or
            c == '_';
    // zig fmt: on
}
fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
pub const TokenType = enum {
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

    // zig fmt: on
    pub fn format(self: *const TokenType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        const width = options.width orelse 0;
        var i: usize = 0;
        if (options.alignment == .Left or options.alignment == .Center) {
            while (i < width) : (i += 1) {
                try writer.print("{c}", .{options.fill});
            }
        }
        const isUpper = std.ascii.isUpper;
        const toUpper = std.ascii.toUpper;
        _ = try writer.write("TT");
        for (@tagName(self.*)) |c| {
            if (isUpper(c)) {
                _ = try writer.write("_");
                i += 1;
                try writer.print("{c}", .{c});
                i += 1;
                continue;
            }

            try writer.print("{c}", .{toUpper(c)});
            i += 1;
        }
        if (options.alignment == .Right or options.alignment == .Center) {
            while (i < width) : (i += 1) {
                try writer.print("{c}", .{options.fill});
            }
        }
    }
};

pub const Token = struct {
    type: TokenType,
    start: []const u8,
    line: usize,
    pub fn format(self: *const Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try self.type.format(fmt, options, writer);
        try writer.print(" '{s}'", .{self.start});
    }
};

fn isAtEnd(self: *Scanner) bool {
    return self.current == self.source.len;
}
fn advance(self: *Scanner) u8 {
    self.current += 1;
    return self.source[self.current - 1];
}
fn peek(self: *Scanner) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current];
}
fn peekNext(self: *Scanner) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current + 1];
}
fn match(self: *Scanner, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (self.source[self.current] != expected) return false;
    self.current += 1;
    return true;
}
fn makeToken(self: *Scanner, id: TokenType) Token {
    return .{
        .type = id,
        .start = self.source[self.start..self.current],
        .line = self.line,
    };
}
fn errorToken(self: *Scanner, comptime message: []const u8) Token {
    return .{
        .type = TokenType.Error,
        .start = message,
        .line = self.line,
    };
}
fn skipWhitespace(self: *Scanner) void {
    while (true) {
        const c = self.peek();
        switch (c) {
            ' ', '\r', '\t' => _ = self.advance(),
            '\n' => {
                self.line += 1;
                _ = self.advance();
            },

            '/' => {
                if (self.peekNext() == '/') {
                    while (self.peek() != '\n' and !self.isAtEnd()) _ = self.advance();
                }
            },

            else => return,
        }
    }
}
fn checkKeyword(self: *Scanner, start: usize, length: usize, rest: []const u8, comptime id: TokenType) TokenType {
    const cur_diff = self.current - self.start;
    const cur_start = self.start + start;
    if ((cur_diff == start + length) and mem.eql(u8, self.source[cur_start .. cur_start + rest.len], rest)) {
        return id;
    }
    return .Identifier;
}
fn identifierType(self: *Scanner) TokenType {
    return switch (self.source[self.start]) {
        'a' => self.checkKeyword(1, 2, "nd", .And),
        'c' => self.checkKeyword(1, 4, "lass", .Class),
        'e' => self.checkKeyword(1, 3, "lse", .Else),
        'f' => {
            if (self.current - self.start > 1) {
                return switch (self.source[self.start + 1]) {
                    'a' => self.checkKeyword(2, 3, "lse", .False),
                    'o' => self.checkKeyword(2, 1, "r", .For),
                    'u' => self.checkKeyword(2, 1, "n", .Fun),
                    else => .Identifier,
                };
            }
            return .Identifier;
        },
        'i' => self.checkKeyword(1, 1, "f", .If),
        'n' => self.checkKeyword(1, 2, "il", .Nil),
        'o' => self.checkKeyword(1, 1, "r", .Or),
        'p' => self.checkKeyword(1, 4, "rint", .Print),
        'r' => self.checkKeyword(1, 5, "eturn", .Return),
        's' => self.checkKeyword(1, 4, "uper", .Super),
        't' => {
            if (self.current - self.start > 1) {
                return switch (self.source[self.start + 1]) {
                    'h' => self.checkKeyword(2, 2, "is", .This),
                    'r' => self.checkKeyword(2, 2, "ue", .True),
                    else => .Identifier,
                };
            }
            return .Identifier;
        },
        'v' => self.checkKeyword(1, 2, "ar", .Var),
        'w' => self.checkKeyword(1, 4, "hile", .While),
        else => .Identifier,
    };
}
fn identifier(self: *Scanner) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) : (_ = self.advance()) {}
    return self.makeToken(self.identifierType());
}
fn number(self: *Scanner) Token {
    while (isDigit(self.peek())) : (_ = self.advance()) {}

    // Look for a fractional part.
    if (self.peek() == '.' and isDigit(self.peekNext())) {
        // Consume the ".".
        _ = self.advance();

        while (isDigit(self.peek())) : (_ = self.advance()) {}
    }

    return self.makeToken(.Number);
}
fn string(self: *Scanner) error{UnterminatedString}!Token {
    while (self.peek() != '"' and !self.isAtEnd()) : (_ = self.advance()) {
        if (self.peek() == '\n') self.line += 1;
    }

    if (self.isAtEnd()) return error.UnterminatedString;
    _ = self.advance();
    return self.makeToken(.String);
}
pub fn next(self: *Scanner) Error!?Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isAtEnd()) return null;
    const c = self.advance();
    if (isAlpha(c)) return self.identifier();
    if (isDigit(c)) return self.number();
    switch (c) {
        '(' => return self.makeToken(.LeftParen),
        ')' => return self.makeToken(.RightParen),
        '{' => return self.makeToken(.LeftBrace),
        '}' => return self.makeToken(.RightBrace),
        ';' => return self.makeToken(.Semicolon),
        ',' => return self.makeToken(.Comma),
        '.' => return self.makeToken(.Dot),
        '-' => return self.makeToken(.Minus),
        '+' => return self.makeToken(.Plus),
        '/' => return self.makeToken(.Slash),
        '*' => return self.makeToken(.Star),
        '!' => return self.makeToken(if (self.match('=')) .BangEqual else .Bang),
        '=' => return self.makeToken(if (self.match('=')) .EqualEqual else .Equal),
        '<' => return self.makeToken(if (self.match('=')) .LessEqual else .Less),
        '>' => return self.makeToken(if (self.match('=')) .GreaterEqual else .Greater),
        '"' => return self.string() catch return error.UnterminatedString,
        else => return error.UnexpectedCharacter,
    }
}
