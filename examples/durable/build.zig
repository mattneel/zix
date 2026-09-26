//! The durable action slice: a CreateTask that survives a crash, end to end.
//!
//! Two runs, because they answer different questions:
//!
//!   zig build test-unit     — the slice's own tests: the revision gate, the feed ring, the event payload.
//!                             No database, no server, nothing to set up.
//!   zig build test-durable  — the acceptance run: seven scenarios against a real PostgreSQL, covering the
//!                             invariants the slice exists to keep — idempotency by unique key, one
//!                             transaction per step, a lease that expires rather than a lock that blocks,
//!                             at-least-once delivery made harmless by revisions, and a view that rebuilds
//!                             from committed state.
//!
//! The acceptance run truncates the slice's tables (the same thing the demo does on startup), so point it
//! at a database you are willing to empty. It defaults to a local one, and `-Ddsn=` overrides it:
//!
//!   zig build test-durable -Ddsn=postgres://user:password@host:5432/database

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zix = b.dependency("zix", .{ .target = target, .optimize = optimize }).module("zix");

    // The database the acceptance run is allowed to truncate.
    const dsn = b.option(
        []const u8,
        "dsn",
        "PostgreSQL DSN for the acceptance run (its tables are truncated)",
    ) orelse "postgres://zix:zix@127.0.0.1:5432/zix_durable_test";
    const options = b.addOptions();
    options.addOption([]const u8, "dsn", dsn);

    // The slice as a module, so both runs compile the same source the example ships.
    const slice = b.createModule(.{
        .root_source_file = b.path("tasks.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zix", .module = zix }},
    });

    const unit = b.addTest(.{ .root_module = slice });
    const run_unit = b.addRunArtifact(unit);
    const unit_step = b.step("test-unit", "Run the slice's tests that need no database");
    unit_step.dependOn(&run_unit.step);

    const acceptance_module = b.createModule(.{
        .root_source_file = b.path("acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zix", .module = zix }},
    });
    acceptance_module.addOptions("build_options", options);

    const acceptance = b.addTest(.{ .root_module = acceptance_module });
    const run_acceptance = b.addRunArtifact(acceptance);
    // `zig build test-durable -- --test-filter "an expired lease"` runs one scenario.
    // Zig 0.16 hands the arguments after `--` to the build script as `b.args`;
    // later versions forward them through the run step itself.
    if (@hasField(std.Build, "args")) {
        if (b.args) |args| run_acceptance.addArgs(args);
    } else run_acceptance.addPassthruArgs();
    const durable_step = b.step("test-durable", "Run the acceptance scenarios against a real PostgreSQL");
    durable_step.dependOn(&run_acceptance.step);

    // `zig build` on its own runs the tests that need nothing set up.
    b.getInstallStep().dependOn(&run_unit.step);
}
