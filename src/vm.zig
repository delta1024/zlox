const std = @import("std");
const build_options = @import("build_options");
const Value = @import("value.zig").Value;
const ValueType = @import("value.zig").ValueType;
const valuesEqual = @import("value.zig").valuesEqual;
const OpCode = @import("chunk.zig").OpCode;
const Chunk = @import("chunk.zig").Chunk;
const compile = @import("compiler.zig").compile;
pub const InterpretError = error{ InterpretCompileError, InterpretRuntimeError, StackOverFlow } || @import("vm/stack.zig").Stack(Value).Error;

pub const Vm = @import("vm/Vm.zig");
fn BinaryOp(vm: *Vm, comptime op: u8) InterpretError!void {
    if (vm.stack.peek(0)) |b| if (vm.stack.peek(1)) |a| {
        if (!b.is(f64) or !a.is(f64)) {
            vm.runtimeError("Operands must be numbers.", .{});
            return error.InterpretRuntimeError;
        }
        _ = vm.stack.pop();
        _ = vm.stack.pop();

        switch (op) {
            '+' => try vm.stack.push(.{ .number = a.as(f64) + b.as(f64) }),
            '-' => try vm.stack.push(.{ .number = a.as(f64) - b.as(f64) }),
            '*' => try vm.stack.push(.{ .number = a.as(f64) * b.as(f64) }),
            '/' => try vm.stack.push(.{ .number = a.as(f64) / b.as(f64) }),
            '>' => try vm.stack.push(.{ .boolean = a.as(f64) > b.as(f64) }),
            '<' => try vm.stack.push(.{ .boolean = a.as(f64) < b.as(f64) }),
            else => unreachable,
        }
    };
}
fn run(vm: *Vm) InterpretError!void {
    while (true) {
        // debug_trace_execution
        if (build_options.debug_trace_execution) {
            if (vm.chunk) |chunk| {
                var writer = std.io.getStdErr().writer();
                writer.print("\t", .{}) catch unreachable;
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
                        std.debug.print("{d}\n", .{val});
                    return;
                },
                .Add => try BinaryOp(vm, '+'),
                .Subtract => try BinaryOp(vm, '-'),
                .Multiply => try BinaryOp(vm, '*'),
                .Divide => try BinaryOp(vm, '/'),
                .Greater => try BinaryOp(vm, '>'),
                .Less => try BinaryOp(vm, '<'),
                .Nil => try vm.stack.push(.{ .nil = {} }),
                .True => try vm.stack.push(.{ .boolean = true }),
                .False => try vm.stack.push(.{ .boolean = false }),
                .Not => try vm.stack.push(.{ .boolean = vm.stack.pop().?.isFalsey() }),
                .Equal => {
                    const b = vm.stack.pop().?;
                    const a = vm.stack.pop().?;
                    try vm.stack.push(.{ .boolean = valuesEqual(a, b) });
                },
                .Negate => {
                    if (vm.stack.peek(0)) |v| {
                        if (!v.is(f64)) {
                            vm.runtimeError("Operand must be a numder.", .{});
                            return error.InterpretRuntimeError;
                        }
                        _ = vm.stack.pop();
                        try vm.stack.push(.{ .number = -(v.as(f64)) });
                    }
                },

                .Constant => {
                    if (vm.readConstant()) |constant|
                        try vm.stack.push(constant);
                },
            }
        else
            return error.InterpretRuntimeError;
    }
}
pub fn interpret(vm: *Vm, source: []const u8) InterpretError!void {
    const allocator = std.heap.page_allocator;
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    if (!compile(source, &chunk)) return error.InterpretCompileError;

    vm.stack.reset();
    vm.chunk = &chunk;
    try run(vm);
}
