const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tack_mod = b.addModule("tack", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tack_lib = b.addLibrary(.{
        .name = "tack",
        .root_module = tack_mod,
    });

    b.installArtifact(tack_lib);

    const tests = b.addTest(.{
        .root_module = tack_mod,
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
