const std = @import("std");
const mem = std.mem;
const VM = @import("./VM.zig");
const Scanner = @import("./Scanner.zig");
const Token = Scanner.Token;
const Allocator = std.mem.Allocator;
fn runRepl(vm: *VM) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var buffer: [1024]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});
        if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |user_input| {
            vm.interpret(user_input) catch {};
        } else {
            std.process.exit(0);
        }
    }
}
fn readFile(allocator: *Allocator, file_path: []const u8) ![]u8 {
    var path_buff: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(file_path, &path_buff);
    const file = try std.fs.openFileAbsolute(path, .{ .read = true });
    defer file.close();
    const file_buffer = try file.readToEndAlloc(allocator, try file.getEndPos());
    return file_buffer;
}
fn runFile(vm: *VM, file_path: []const u8) !void {
    var file = try readFile(&vm.memory.allocator, file_path);
    defer vm.memory.allocator.free(file);
    vm.interpret(file) catch |err| switch (err) {
        VM.Error.Compile => std.process.exit(60),
        VM.Error.Runtime => std.process.exit(75),
        else => {
            try std.io.getStdErr().writer().print("{}", .{err});
            std.process.exit(1);
        },
    };
}
pub fn main() anyerror!void {
    var vm = VM.init();
    defer vm.free();
    var args = try std.process.argsAlloc(&vm.memory.allocator);
    defer std.process.argsFree(&vm.memory.allocator, args);
    if (mem.len(args) == 1) {
        try runRepl(&vm);
    } else if (mem.len(args) == 2) {
        try runFile(&vm, args[1]);
    } else {
        std.debug.print("Usage: {s} <file> \n", .{args[0]});
    }
}
