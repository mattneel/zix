//! The room host: gkz's authoritative room, served to browsers over HTTP/3 and WebTransport.
//!
//! This is its own Zig project, the way gkz's roguelike is: the room is a dependency's source, compiled twice
//! from one file — natively for this host, and to wasm for the browser tab.
//!
//!   zig build          — build the host and the module it serves
//!   zig build run      — run it (ZIX_CERT / ZIX_KEY for the listener, defaults to the example certs)
//!   zig build session  — drive a native session and export its run log, to replay with gkz's `replay`
//!   zig build wasm     — just the browser module

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zix = b.dependency("zix", .{ .target = target, .optimize = optimize }).module("zix");
    const gkz_dep = b.dependency("gkz", .{ .target = target, .optimize = optimize });
    const gkz = gkz_dep.module("gkz");

    // The room, compiled natively: the authoritative half this host drives. Its source comes from the gkz
    // checkout, so the Durable Object's wasm instance, the browser tab and this process all build one file.
    const room_obj = b.addObject(.{
        .name = "gkz_room",
        .root_module = b.createModule(.{
            .root_source_file = gkz_dep.path("examples/roguelike/src/room.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "gkz", .module = gkz }},
        }),
    });
    room_obj.entry = .disabled;
    room_obj.rdynamic = true;

    const server = b.addExecutable(.{
        .name = "room-host",
        .root_module = b.createModule(.{
            .root_source_file = b.path("server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zix", .module = zix }},
        }),
    });
    server.root_module.addObject(room_obj);
    b.installArtifact(server);

    // The same room for the browser tab: wasm32-freestanding, a reactor module (no entry point) whose exports
    // and linear memory are reachable, exactly as gkz's own wasm step builds it.
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const gkz_wasm = b.dependency("gkz", .{ .target = wasm_target, .optimize = .ReleaseSmall });
    const room_wasm = b.addExecutable(.{
        .name = "room",
        .root_module = b.createModule(.{
            .root_source_file = gkz_wasm.path("examples/roguelike/src/room.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{.{ .name = "gkz", .module = gkz_wasm.module("gkz") }},
        }),
    });
    room_wasm.entry = .disabled;
    room_wasm.rdynamic = true;

    const install_wasm = b.addInstallArtifact(room_wasm, .{
        .dest_dir = .{ .override = .{ .custom = "web/room" } },
    });
    const wasm_step = b.step("wasm", "Build the room module the browser tab loads");
    wasm_step.dependOn(&install_wasm.step);

    // The server reads its module from disk at startup, so the default step installs both.
    const install_page = b.addInstallFileWithDir(b.path("page.html"), .{ .custom = "web/room" }, "page.html");
    b.getInstallStep().dependOn(&install_page.step);
    b.getInstallStep().dependOn(&install_wasm.step);

    const run = b.addRunArtifact(server);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the room host").dependOn(&run.step);

    // The native acceptance harness: drive a session, export its run log, and hand the file to gkz's `replay`.
    const session = b.addExecutable(.{
        .name = "room-session",
        .root_module = b.createModule(.{
            .root_source_file = b.path("native_session.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });
    session.root_module.addObject(room_obj);
    const run_session = b.addRunArtifact(session);
    if (b.args) |args| run_session.addArgs(args);
    b.step("session", "Drive a native session and export its run log").dependOn(&run_session.step);
}
