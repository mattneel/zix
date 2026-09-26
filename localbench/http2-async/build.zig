const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const zix_dep = b.dependency("zix", .{ .target = target, .optimize = optimize });
    const zix_mod = zix_dep.module("zix");

    const exe = b.addExecutable(.{
        .name = "zix-localbench-http2-async",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
        }),
    });
    exe.root_module.addImport("zix", zix_mod);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the server");
    const run_cmd = b.addRunArtifact(exe);
    // Zig 0.16 hands the arguments after `--` to the build script as `b.args`;
    // later versions forward them through the run step itself.
    if (@hasField(std.Build, "args")) {
        if (b.args) |args| run_cmd.addArgs(args);
    } else run_cmd.addPassthruArgs();
    run_step.dependOn(&run_cmd.step);
}
