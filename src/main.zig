const std = @import("std");
const page_allcator = std.heap.page_allocator;
const Arena = std.heap.ArenaAllocator;
const vm_mod = @import("vm.zig");
const Vm = vm_mod.Vm;
fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    return (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse null;
}
fn repl() !void {
    var buf: [256]u8 = undefined;
    var vm = Vm.init();
    defer vm.deinit();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    while (true) {
        try stdout.writeAll("> ");

        const src = (try nextLine(stdin.reader(), &buf)) orelse break;

        vm_mod.interpret(&vm, src) catch continue;
    }

    // we are at parse precedence
}
fn runFile(in_file: []const u8) !void {
    const file = try std.fs.cwd().openFile(in_file, .{});
    defer file.close();
    var allocator = page_allcator;

    var buffer = buf: {
        const len = try file.getEndPos();
        var buff = try allocator.alloc(u8, len);
        _ = try file.seekTo(0);
        _ = try file.readAll(buff);
        break :buf buff;
    };
    defer allocator.free(buffer);

    var vm = Vm.init();
    defer vm.deinit();

    vm_mod.interpret(&vm, buffer) catch |err| switch (err) {
        vm_mod.InterpretError.InterpretRuntimeError => std.process.exit(70),
        vm_mod.InterpretError.InterpretCompileError => std.process.exit(65),
        else => std.process.exit(1),
    };
}
pub fn main() !void {
    var arena = Arena.init(page_allcator);
    defer arena.deinit();
    var args = try std.process.argsAlloc(arena.allocator());
    if (args.len == 1) {
        try repl();
    } else if (args.len == 2) {
        try runFile(args.ptr[1]);
    } else {
        std.io.getStdErr().writer().print("Usage: zlox [path]\n", .{}) catch unreachable;
        std.process.exit(1);
    }
}
