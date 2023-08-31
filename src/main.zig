const std = @import("std");
const page_allcator = std.heap.page_allocator;
const chunk_mod = @import("chunk.zig");
const vm_mod = @import("vm.zig");
const Vm = vm_mod.Vm;
const Chunk = chunk_mod.Chunk;

pub fn main() !void {
    var chunk = Chunk.init(page_allcator);
    defer chunk.deinit();

    var vm = Vm.init();
    defer vm.deinit();

    var pos = try chunk.addConstant(23.0);
    try chunk.pushBytes(chunk_mod.OpCode.Constant, pos, 1);
    pos = try chunk.addConstant(24.0);
    try chunk.pushBytes(chunk_mod.OpCode.Constant, pos, 1);
    try chunk.pushByte(chunk_mod.OpCode, .Add, 1);

    try chunk.pushByte(chunk_mod.OpCode, .Negate, 1);
    try chunk.pushByte(chunk_mod.OpCode, .Return, 2);
    std.debug.print("{test chunk}", .{chunk});
    vm_mod.interpret(&vm, &chunk) catch |err|
        switch (err) {
        error.InterpretRuntimeError, error.InterpretCompileError, error.StackOverFlow => std.process.exit(1),
    };
}
