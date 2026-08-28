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
}
