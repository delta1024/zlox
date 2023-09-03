const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Parser = @import("compiler/Parser.zig");
const luf = @import("compiler/lookup_functions.zig");
pub fn compile(source: []const u8, chunk: *Chunk) bool {
    var parser = Parser.init(source, chunk);

    parser.advance() catch return false;

    luf.expression(&parser, false) catch return false;

    parser.consume(.Eof, "Expect end of expression") catch return false;
    parser.endCompiler() catch return false;
    return !parser.had_error;
}
