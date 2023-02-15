const std = @import("std");
const builtin = @import("builtin");
const memory = @import("./memory.zig");
const chunk_mod = @import("./chunk.zig");
const VM = @import("./VM.zig");
const VmAllocator = memory.VmAllocator;
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;
const Value = @import("./value.zig").Value;
pub fn main() anyerror!void {
    var vm = VM.init();
    var chunk = Chunk.init(&vm.memory.allocator);
    defer chunk.deinit();

    var v = try chunk.push_value(Value{ .number = 88 });
    try chunk.push_code(@enumToInt(OpCode.Constant), 123);
    try chunk.push_code(v, 123);
    v = try chunk.push_value(Value{ .number = 33 });
    try chunk.push_code(@enumToInt(OpCode.Constant), 123);
    try chunk.push_code(v, 123);

    try chunk.push_code(@enumToInt(OpCode.Add), 123);

    v = try chunk.push_value(Value{ .number = 17 });
    try chunk.push_code(@enumToInt(OpCode.Constant), 123);
    try chunk.push_code(v, 123);

    try chunk.push_code(@enumToInt(OpCode.Divide), 123);
    try chunk.push_code(@enumToInt(OpCode.Negate), 123);

    try chunk.push_code(@enumToInt(OpCode.Return), 123);

    if (builtin.mode == .Debug)
        try chunk_mod.disassembleChunk(&chunk, "test");

    try vm.interpret(&chunk);
}
