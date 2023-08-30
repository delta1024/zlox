const std = @import("std");
const mem = std.mem;
const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;

pub const Lexer = @This();

source: []const u8,
start: usize = 0,
current: usize = 0,
line: u32 = 1,

pub const Error = error{ UnterminatedString, EndOfFile, UnexpectedChar };

pub fn init(source: []const u8) Lexer {
    return .{
        .source = source,
    };
}

pub fn next(self: *Lexer) ?Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isAtEnd()) return null;

    const c = self.advance();

    return switch (c) {
        '(' => self.makeToken(.LeftParen),
        ')' => self.makeToken(.RightParen),
        '{' => self.makeToken(.LeftBrace),
        '}' => self.makeToken(.RightBrace),
        ';' => self.makeToken(.Semicolon),
        ',' => self.makeToken(.Comma),
        '.' => self.makeToken(.Dot),
        '-' => self.makeToken(.Minus),
        '+' => self.makeToken(.Plus),
        '/' => self.makeToken(.Slash),
        '*' => self.makeToken(.Star),
        '!' => self.makeToken(if (self.match('=')) .BangEqual else .Bang),
        '=' => self.makeToken(if (self.match('=')) .EqualEqual else .Equal),
        '<' => self.makeToken(if (self.match('=')) .LessEqual else .Less),
        '>' => self.makeToken(if (self.match('=')) .GreaterEqual else .Greater),
        '0'...'9' => self.number(),
        'a'...'z', 'A'...'Z', '_' => self.identifier(),
        else => self.errorToken("Unexpected character."),
    };
}
fn isAlpha(char: u8) bool {
    return switch (char) {
        'a'...'z', 'A'...'Z', '_' => true,
        else => false,
    };
}
fn isDigit(char: u8) bool {
    return switch (char) {
        '0'...'9' => true,
        else => false,
    };
}
fn identifierType(self: *const Lexer) TokenType {
    return switch (self.source[self.start]) {
        'a' => self.checkKeyword(1, 2, "nd", .And),
        'c' => self.checkKeyword(1, 4, "lass", .Class),
        'e' => self.checkKeyword(1, 3, "lse", .Else),
        'f' => if ((self.current - self.start) > 1)
            switch (self.source[self.start + 1]) {
                'a' => self.checkKeyword(2, 3, "lse", .False),
                'o' => self.checkKeyword(2, 1, "r", .For),
                'u' => self.checkKeyword(2, 1, "n", .Fun),
                else => .Identifier,
            }
        else
            .Identifier,
        'i' => self.checkKeyword(1, 2, "f", .If),
        'n' => self.checkKeyword(1, 3, "il", .Nil),
        'o' => self.checkKeyword(1, 2, "r", .Or),
        'p' => self.checkKeyword(1, 4, "rint", .Print),
        'r' => self.checkKeyword(1, 5, "eturn", .Return),
        's' => self.checkKeyword(1, 4, "uper", .Super),
        't' => if ((self.current - self.start > 1))
            switch (self.source[self.start + 1]) {
                'h' => self.checkKeyword(2, 2, "is", .This),
                'r' => self.checkKeyword(2, 2, "ue", .True),
                else => .Identifier,
            }
        else
            .Identifier,
        'v' => self.checkKeyword(1, 2, "ar", .Var),
        'w' => self.checkKeyword(1, 4, "hile", .While),
        else => .Identifier,
    };
}
fn checkKeyword(self: *const Lexer, start: usize, length: usize, comptime rest: []const u8, id: TokenType) TokenType {
    // zig fmt: off
    return if (self.current - self.start == start + length and
                   mem.eql(u8, self.source[self.start + start .. self.current], rest)) id
           else .Identifier;
    // zig fmt: on
}
fn identifier(self: *Lexer) Token {
    while (!self.isAtEnd() and
        (isAlpha(self.peek()) or isDigit(self.peek()))) : (_ = self.advance())
    {}

    return self.makeToken(self.identifierType());
}
fn number(self: *Lexer) Token {
    while (!self.isAtEnd() and isDigit(self.peek())) : (_ = self.advance()) {}

    if (!self.isAtEnd() and (self.peek() == '.' and isDigit(self.peekNext()))) {
        // Consume the '.'.
        _ = self.advance();

        while (switch (self.peek()) {
            '0'...'9' => true,
            else => false,
        }) : (_ = self.advance()) {}
    }

    return self.makeToken(.Number);
}
fn string(self: *Lexer) Token {
    while (!self.isAtEnd() and self.peek() != '"') : (_ = self.advance()) {
        if (self.peek() == '\n') self.line += 1;
    }
    if (self.isAtEnd()) return self.errorToken("Unterminated string");

    // The closing quote.
    _ = self.advance();
    return self.makeToken(.String);
}
fn peek(self: *const Lexer) u8 {
    return if (self.isAtEnd()) '0' else self.source[self.current];
}

fn peekNext(self: *const Lexer) u8 {
    if (self.isAtEnd()) return '0';
    return self.source[self.current + 1];
}
fn skipWhitespace(self: *Lexer) void {
    while (!self.isAtEnd()) : (_ = self.advance()) {
        var c = self.peek();
        switch (c) {
            ' ', '\r', '\t' => continue,
            '\n' => {
                self.line += 1;
                continue;
            },
            '/' => if (self.peekNext() == '/')
                while (self.peek() != '\n' and !self.isAtEnd()) : (_ = self.advance()) {} else return,
            else => return,
        }
    }
}
fn match(self: *Lexer, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (self.source[self.current] != expected) return false;
    self.current += 1;
    return true;
}
fn advance(self: *Lexer) u8 {
    self.current += 1;
    return self.source[self.current - 1];
}
fn isAtEnd(self: *const Lexer) bool {
    return self.current == self.source.len;
}

fn makeToken(self: *Lexer, id: TokenType) Token {
    return Token.init(id, self.source[self.start..self.current], self.line);
}
fn errorToken(self: *Lexer, message: []const u8) Token {
    return .{
        .id = .Error,
        .lexum = message,
        .line = self.line,
    };
}
