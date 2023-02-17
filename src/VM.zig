const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const Chunk = @import("./Chunk.zig");
const OpCode = Chunk.OpCode;
const Compiler = @import("./Compiler.zig");
const mem = std.mem;
const VmAllocator = @import("./memory.zig");
const VM = @This();
const Value = @import("./value.zig").Value;
const os = std.os;
// zig fmt: off
pub const Error = error{ 
    Interpret, Compile, 
    UnterminatedString, 
    OutOfMemroy, Unexpected, 
    WouldBlock,
    NotOpenForWriting,
    OperationAborted, 
    SystemResources, 
    ConnectionResetByPeer, 
    BrokenPipe, 
    AccessDenied, 
    NoSpaceLeft, 
    InputOutput, 
    FileTooBig, 
    DiskQuota } || VmAllocator.Error || Compiler.Error;
// zig fmt: on

frame: Frame = undefined,
memory: VmAllocator = VmAllocator{},
stack_top: usize = 0,
stack: [options.stack_max]Value = undefined,

fn resetStack(self: *VM) void {
    self.stack_top = 0;
}
fn push(self: *VM, value: Value) void {
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}
fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}
const Frame = struct {
    const Ip = struct {
        code: []u8,
        pos: usize = 0,
        fn init(chunk: *Chunk) Ip {
            return .{ .code = chunk.code.items };
        }
        fn next(self: *Ip) ?u8 {
            if (self.code.len == self.pos)
                return null;
            self.pos += 1;
            return self.code[self.pos - 1];
        }
    };
    chunk: *Chunk,
    ip: Ip,
    fn init(chunk: *Chunk) Frame {
        return .{
            .chunk = chunk,
            .ip = Ip.init(chunk),
        };
    }
    fn readByte(self: *Frame) u8 {
        return self.ip.next() orelse 0;
    }
    fn readConstant(self: *Frame) Value {
        const index = self.readByte();
        return self.chunk.constants.items[index];
    }
};

pub fn init() VM {
    var vm = VM{};
    vm.resetStack();
    return vm;
}
pub fn free(self: *VM) void {}
pub fn interpret(self: *VM, source: []const u8) Error!void {
    var chunk = Chunk.init(&self.memory.allocator);
    defer chunk.deinit();
    var parser = Compiler.init(source);
    try parser.compile(&chunk);
    self.frame = Frame.init(&chunk);

    try self.run();
}

fn binaryOp(self: *VM, op: OpCode) Error!void {
    const b = self.pop();
    const a = self.pop();

    self.push(switch (op) {
        .Subtract => a - b,
        .Add => a + b,
        .Multiply => a * b,
        .Divide => a / b,
        else => unreachable,
    });
}
fn run(self: *VM) Error!void {
    var frame: *Frame = &self.frame;
    while (true) {
        if (options.debug_trace_execution) {
            var writer = std.io.getStdOut().writer();
            _ = try writer.write("        ");
            var i: usize = 0;
            while (i < self.stack_top) : (i += 1) {
                try writer.print("[ {d:.2} ]", .{self.stack[i]});
            }
            try writer.writeAll("\n");
            _ = try Chunk.disassembleInstruction(frame.chunk, frame.ip.pos, writer);
        }
        const instruction = frame.readByte();
        try switch (@intToEnum(OpCode, instruction)) {
            .Return => {
                const value = self.pop();
                const writer = std.io.getStdOut().writer();
                try writer.print("{d:.2}\n", .{value});
                return;
            },
            .Constant => {
                const v = frame.readConstant();
                self.push(v);
            },
            .Add, .Subtract, .Multiply, .Divide => self.binaryOp(@intToEnum(OpCode, instruction)),
            .Negate => {
                self.push(-self.pop());
            },
        };
    }
}
