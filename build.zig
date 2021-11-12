const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary("stga", "src/main.zig");
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();

    const testCmd = b.addTest("src/main.zig");
    testCmd.setBuildMode(mode);

    const testStep = b.step("test", "Run tests");
    testStep.dependOn(&testCmd.step);
}
