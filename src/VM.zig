const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const Table = std.StringHashMapUnmanaged;
const Chunk = @import("./Chunk.zig");
const OpCode = Chunk.OpCode;
const Compiler = @import("./Compiler.zig");
const mem = std.mem;
const VmAllocator = @import("./memory.zig");
const VM = @This();
const val_mod = @import("./value.zig");
const Value = val_mod.Value;
const numberVal = val_mod.numberVal;
const boolVal = val_mod.boolVal;
const nilVal = val_mod.nilVal;
const objVal = val_mod.objValue;
const obj_mod = @import("./object.zig");
const Obj = obj_mod.Obj;
const ObjString = obj_mod.ObjString;
const os = std.os;
// zig fmt: off
pub const Error = error{ 
    Runtime, Compile, 
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
strings: Table(*ObjString) = Table(*ObjString){},
objects: ?*Obj = null,
stack_top: usize = 0,
stack: [options.stack_max]Value = undefined,

fn resetStack(self: *VM) void {
    self.stack_top = 0;
}
fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) Error {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(format, args);
    _ = try stderr.write("\n");

    const instruction = self.frame.ip.pos - 1;
    const line = self.frame.chunk.lines.items[instruction];
    try stderr.print("[line {d}] in script\n", .{line});
    return error.Runtime;
}
fn push(self: *VM, value: Value) void {
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}
fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}
fn peek(self: *VM, distance: usize) Value {
    return self.stack[self.stack_top - distance - 1];
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
pub fn free(self: *VM) void {
    self.memory.freeObjects();
    self.strings.deinit(&self.memory.allocator);
}
pub fn interpret(self: *VM, source: []const u8) Error!void {
    var chunk = Chunk.init(&self.memory.allocator);
    defer chunk.deinit();
    var parser = Compiler.init(source, &self.memory);
    try parser.compile(&chunk);
    self.frame = Frame.init(&chunk);

    try self.run();
}

fn binaryOp(self: *VM, op: OpCode) Error!void {
    if (!self.peek(0).is(f64) or !self.peek(1).is(f64)) {
        return self.runtimeError("Operands must be numbers.", .{});
    }
    const b = self.pop().as(f64);
    const a = self.pop().as(f64);

    self.push(switch (op) {
        .Subtract, .Add, .Multiply, .Divide => numberVal(switch (op) {
            .Subtract => a - b,
            .Add => a + b,
            .Multiply => a * b,
            .Divide => a / b,
            else => unreachable,
        }),
        .Greater, .Less => boolVal(switch (op) {
            .Greater => a > b,
            .Less => a < b,
            else => unreachable,
        }),
        else => unreachable,
    });
}
fn concatenate(self: *VM) Error!void {
    const b = @fieldParentPtr(ObjString, "obj", self.pop().as(*Obj));
    const a = @fieldParentPtr(ObjString, "obj", self.pop().as(*Obj));

    const length = mem.len(a.chars) + mem.len(b.chars) + 1;
    var chars = try self.memory.allocator.allocSentinel(u8, length + 1, 0);
    mem.copy(u8, chars[0..mem.len(a.chars)], a.chars[0..mem.len(a.chars)]);
    mem.copy(u8, chars[mem.len(a.chars)..length], b.chars[0..mem.len(b.chars)]);
    const result = try self.memory.takeString(chars);
    self.push(objVal(&result.obj));
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
            .Nil => self.push(nilVal()),
            .True => self.push(boolVal(true)),
            .False => self.push(boolVal(false)),
            .Equal => {
                const b = self.pop();
                const a = self.pop();
                self.push(boolVal(a.equals(b)));
            },
            .Greater, .Less => self.binaryOp(@intToEnum(OpCode, instruction)),
            .Add => {
                if (self.peek(0).isObjType(ObjString) and self.peek(1).isObjType(ObjString)) {
                    try self.concatenate();
                } else if (self.peek(0).is(f64) and self.peek(1).is(f64)) {
                    const b = self.pop().as(f64);
                    const a = self.pop().as(f64);
                    self.push(numberVal(a + b));
                } else {
                    return self.runtimeError("Operands must be two numbers or two strings.", .{});
                }
            },
            .Subtract, .Multiply, .Divide => self.binaryOp(@intToEnum(OpCode, instruction)),
            .Not => {
                self.push(boolVal(self.pop().isFalsey()));
            },
            .Negate => {
                if (!self.peek(0).is(f64)) {
                    return self.runtimeError("Operand must be a number.", .{});
                }
                self.push(numberVal(-self.pop().as(f64)));
            },
        };
    }
}
