const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const math = std.math;
const Table = std.StringHashMapUnmanaged;
const Chunk = @import("./Chunk.zig");
const OpCode = Chunk.OpCode;
const Compiler = @import("./Compiler.zig");
const mem = std.mem;
const Allocator = @import("./Allocator.zig");
const VM = @This();
usingnamespace @import("./value.zig");
usingnamespace @import("./object.zig");
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
    DiskQuota } || Allocator.Error || Compiler.Error;
// zig fmt: on

const FRAMES_MAX = 64;
const STACK_MAX = FRAMES_MAX * math.maxInt(u8);
memory: Allocator = Allocator{},
globals: Table(Value) = Table(Value){},
frame_count: usize = 0,
frames: [FRAMES_MAX]Frame = undefined,
stack_top: usize = 0,
stack: [STACK_MAX]Value = undefined,

fn clockNative(arg_count: usize, args: []Value) Value {
    return numberVal(@intToFloat(f64, std.time.timestamp()));
}
fn resetStack(self: *VM) void {
    self.stack_top = 0;
    self.frame_count = 0;
}
fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) Error {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(format, args);
    _ = try stderr.write("\n");
    var i: usize = self.frame_count - 1;
    while (i >= 0) : (i -= 1) {
        const frame = &self.frames[i];
        const function =
            frame.function;
        const instruction = frame.ip.pos - 1;
        try stderr.print("[line {d}] in ", .{function.chunk.lines.items[instruction]});

        if (function.name) |n| {
            try stderr.print("{s}()\n", .{n});
        } else {
            try stderr.print("script\n", .{});
        }
    }
    self.resetStack();
    return error.Runtime;
}
fn defineNative(self: *VM, name: []const u8, func: NativeFn) Error!void {
    self.push(objVal(&(try self.memory.copyString(name)).obj));
    self.push(objVal(&(try self.memory.newNative(func)).obj));
    const string = @fieldParentPtr(ObjString, "obj", self.stack[0].as(*Obj));
    try self.globals.put(&self.memory.allocator, string.chars[0..mem.len(string.chars)], self.stack[1]);
    _ = self.pop();
    _ = self.pop();
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
fn call(self: *VM, function: *ObjFunction, arg_count: u8) Error!void {
    if (arg_count != function.arity) {
        return self.runtimeError("Expected {d} arguments got {d}", .{ function.arity, arg_count });
    }
    if (self.frame_count == FRAMES_MAX) {
        return self.runtimeError("Stack overflow.", .{});
    }
    var frame = &self.frames[self.frame_count];
    self.frame_count += 1;
    const stack_start = self.stack_top - arg_count - 1;
    frame.* = Frame.init(function, self.stack[stack_start..], stack_start);
}
fn callValue(self: *VM, callee: Value, arg_count: u8) Error!void {
    if (callee.isObjType(ObjFunction)) {
        try self.call(@fieldParentPtr(ObjFunction, "obj", callee.as(*Obj)), arg_count);
        return;
    } else if (callee.isObjType(ObjNative)) {
        const native = @fieldParentPtr(ObjNative, "obj", callee.as(*Obj)).function;
        const result = native(arg_count, self.stack[self.stack_top - arg_count ..]);
        self.stack_top -= arg_count + 1;
        self.push(result);
        return;
    }
    return self.runtimeError("Can only call functions and classes.", .{});
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
    function: *ObjFunction,
    ip: Ip,
    slots: []Value,
    start: usize,
    fn init(function: *ObjFunction, slots: []Value, start: usize) Frame {
        return .{
            .function = function,
            .ip = Ip.init(&function.chunk),
            .slots = slots,
            .start = start,
        };
    }
    inline fn readByte(self: *Frame) u8 {
        return self.ip.next() orelse 0;
    }
    inline fn readConstant(self: *Frame) Value {
        const index = self.readByte();
        return self.function.chunk.constants.items[index];
    }
    inline fn readString(self: *Frame) *ObjString {
        const str = self.readConstant();
        return @fieldParentPtr(ObjString, "obj", str.as(*Obj));
    }
    inline fn readShort(self: *Frame) u16 {
        self.ip.pos += 2;
        return math.shl(u16, @intCast(u16, self.ip.code[self.ip.pos - 2]), 8) | self.ip.code[self.ip.pos - 1];
    }
};

pub fn init() VM {
    var vm = VM{};
    vm.resetStack();
    vm.defineNative("clock", clockNative) catch {
        @panic("Could not initialize vm.");
    };
    return vm;
}
pub fn free(self: *VM) void {
    self.memory.deinit();
    self.globals.deinit(&self.memory.allocator);
}
pub fn interpret(self: *VM, source: []const u8) Error!void {
    var parser = Compiler.init(source, &self.memory);
    var function = try parser.compile();

    self.push(objVal(&function.obj));
    var frame = &self.frames[self.frame_count];
    self.frame_count += 1;
    frame.* = Frame.init(function, self.stack[0..], self.stack_top);
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
    var frame: *Frame = &self.frames[self.frame_count - 1];
    while (true) {
        if (options.debug_trace_execution) {
            var writer = std.io.getStdOut().writer();
            _ = try writer.write("        ");
            var i: usize = 0;
            while (i < self.stack_top) : (i += 1) {
                try writer.print("[ {d:.2} ]", .{self.stack[i]});
            }
            try writer.writeAll("\n");
            _ = try Chunk.disassembleInstruction(&frame.function.chunk, frame.ip.pos, writer);
        }
        const instruction = frame.readByte();
        try switch (@intToEnum(OpCode, instruction)) {
            .Return => {
                const result = self.pop();
                self.frame_count -= 1;
                if (self.frame_count == 0) {
                    _ = self.pop();
                    return;
                }
                self.stack_top = frame.start;
                self.push(result);
                frame = &self.frames[self.frame_count - 1];
            },
            .Call => {
                const arg_count = frame.readByte();
                try self.callValue(self.peek(arg_count), arg_count);
                frame = &self.frames[self.frame_count - 1];
            },
            .Loop => {
                const offset = frame.readShort();
                frame.ip.pos -= offset;
            },
            .JumpIfFalse => {
                const offset = frame.readShort();
                if (self.peek(0).isFalsey()) frame.ip.pos += offset;
            },
            .Jump => {
                const offset = frame.readShort();
                frame.ip.pos += offset;
            },
            .Pop => _ = self.pop(),
            .DefineGlobal => {
                const name = frame.readString();
                try self.globals.put(&self.memory.allocator, name.chars[0..mem.len(name.chars)], self.peek(0));
                _ = self.pop();
            },
            .GetLocal => {
                const slot = frame.readByte();
                self.push(frame.slots[slot]);
            },
            .SetLocal => {
                const slot = frame.readByte();
                frame.slots[slot] = self.peek(0);
            },
            .GetGlobal => {
                const name = frame.readString();
                const value = self.globals.get(name.chars[0..mem.len(name.chars)]) orelse {
                    return self.runtimeError("Undefined variable '{s}'", .{name.chars});
                };
                self.push(value);
            },
            .SetGlobal => {
                const name = frame.readString();
                if (!self.globals.contains(name.chars[0..mem.len(name.chars)])) {
                    return self.runtimeError("Undefined variabl '{s}'", .{name.chars});
                } else {
                    try self.globals.put(&self.memory.allocator, name.chars[0..mem.len(name.chars)], self.peek(0));
                }
            },
            .Print => {
                const value = self.pop();
                const writer = std.io.getStdOut().writer();
                try writer.print("{d:.2}\n", .{value});
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
