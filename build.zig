const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const pag = std.build.Pkg{
        .name = "pag",
        .path = std.build.FileSource.relative("pag.zig"),
    };

    const exe = b.addExecutable("pag", "compiler/main.zig");
    exe.addPackage(pag);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const compiler_tests = b.addTest("compiler/main.zig");
    compiler_tests.addPackage(pag);
    const test_step = b.step("test", "Run compiler tests");
    test_step.dependOn(&compiler_tests.step);
}
