const chunk_mod = @import("chunk.zig");
const std = @import("std");
const value_mod = @import("value.zig");
const build_options = @import("build_options");
const Value = value_mod.Value;
const OpCode = chunk_mod.OpCode;
const Chunk = chunk_mod.Chunk;
const InterpretError = error{ InterpretCompileError, InterpretRuntimeError, StackOverFlow } || @import("vm/stack.zig").Stack(Value).Error;

pub const Vm = @import("vm/Vm.zig");
fn BinaryOp(vm: *Vm, comptime op: u8) InterpretError!void {
    if (vm.stack.pop()) |b| if (vm.stack.pop()) |a| try vm.stack.push(switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a * b,
        else => unreachable,
    });
}
fn run(vm: *Vm) InterpretError!void {
    while (true) {
        if (build_options.debug_trace_execution) {
            if (vm.chunk) |chunk| {
                var writer = std.io.getStdErr().writer();
                for (vm.stack.data[0..vm.stack.stack_top]) |slot| {
                    writer.print("[ {d} ]", .{slot}) catch unreachable;
                }
                writer.print("\n", .{}) catch unreachable;
                _ = chunk.dissasembleInstruction(vm.ip, writer) catch unreachable;
            }
        } // debug_trace_execution

        if (vm.readByte()) |byte|
            switch (@intToEnum(OpCode, byte)) {
                .Return => {
                    if (vm.stack.pop()) |val|
                        std.debug.print("{d}", .{val});
                    return;
                },
                .Add => try BinaryOp(vm, '+'),
                .Subtract => try BinaryOp(vm, '-'),
                .Multiply => try BinaryOp(vm, '*'),
                .Divide => try BinaryOp(vm, '/'),
                .Negate => if (vm.stack.pop()) |v| try vm.stack.push(-v),
                .Constant => {
                    if (vm.readConstant()) |constant|
                        try vm.stack.push(constant);
                },
            }
        else
            return error.InterpretRuntimeError;
    }
}
pub fn interpret(vm: *Vm, chunk: *const Chunk) InterpretError!void {
    vm.stack.reset();
    vm.chunk = chunk;
    try run(vm);
}
