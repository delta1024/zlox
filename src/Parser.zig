const std = @import("std");
const Parser = @This();
const Scanner = @import("./Scanner.zig");

pub const Error = error{ UnterminatedString, UnexpectedCharacter } || Scanner.Error;

scanner: Scanner,

pub fn init(source: []const u8) Parser {
    return .{
        .scanner = .{ .source = source },
    };
}

pub fn compile(self: *Parser) Error!void {
    var line: usize = 0;
    while (self.scanner.next() catch |err| {
        switch (err) {
            Scanner.Error.UnterminatedString => std.debug.print("Unterminated String\n", .{}),
            Scanner.Error.UnexpectedCharacter => std.debug.print("Unexpected Character\n", .{}),
        }
        return;
    }) |token| {
        if (token.line != line) {
            std.debug.print("{d:4} ", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{:14} '{s}'\n", .{ token.type, token.start });
    }
}
