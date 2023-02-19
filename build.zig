const std = @import("std");
const mem = std.mem;

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zlox", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addBuildOption(usize, "stack_max", 255);
    exe.addBuildOption(bool, "debug_trace_execution", true);
    exe.addBuildOption(bool, "debug_print_code", true);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const out_dir = b.addRemoveDirTree("./zig-out/");
    const cache_dir = b.addRemoveDirTree("./zig-cache/");
    const clean_step = b.step("clean", "Clean up build directories");
    clean_step.dependOn(&out_dir.step);
    clean_step.dependOn(&cache_dir.step);
}
