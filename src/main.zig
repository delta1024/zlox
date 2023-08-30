const std = @import("std");
const lexer = @import("lexer.zig");
const Lexer = lexer.Lexer;

pub fn main() !void {
    var lex = Lexer.init("and fun for hello <= == = < (){}./,");
    while (lex.next()) |token| {
        std.debug.print("{}", .{token});
    }
}
