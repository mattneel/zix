//! A native session against the room, with the transport not yet in the picture.
//!
//! Seat a room, drive scripted actions the way gkz's gate does, and export the run log. gkz's own `replay`
//! command then has to reproduce the same tick and digest from that log alone — the acceptance property of a
//! host, checked by the code that owns the format rather than by anything here.
//!
//! ```
//! zig build-exe examples/room/native_session.zig -M room=... -M gkz=... -M fpz=...
//! ./native_session lobby 8 /tmp/room.log
//! (cd ~/src/gkz/examples/roguelike && zig build run -- replay /tmp/room.log)
//! ```

const std = @import("std");
const host = @import("host.zig");

/// The gate's scripted pattern: a pure function of the tick index, so a driven room is as reproducible as any
/// other.
const moves = [_][2]i32{ .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 }, .{ 0, -1 } };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var sbuf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &sbuf);
    const out = &fw.interface;
    defer out.flush() catch {};

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const code = if (args.len > 1) args[1] else "lobby";
    const ticks: usize = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 8;
    const log_path = if (args.len > 3) args[3] else "/tmp/room.log";

    var h = host.Host.init(gpa, code);
    defer h.deinit();

    try h.ready();
    try out.print("room {s}: seed {d} tick {d} digest {d} log {d}B\n", .{ code, h.seed, h.tick(), h.digest(), h.log.items.len });

    // Two participants, seated the way the host seats them: JOIN enters the log as an input, so replaying the
    // log reconstructs the roster without any out-of-band state.
    _ = h.join(1);
    _ = h.join(2);
    try out.print("seated: members {d} owed(1) {d}\n", .{ h.members(), h.owed(1) });

    var i: usize = 0;
    while (i < ticks) : (i += 1) {
        const m = moves[i % moves.len];
        _ = h.action(1, m[0], m[1]);
        const wire = try h.flush();
        try out.print("tick {d} digest {d} wire {d}B log {d}B\n", .{ h.tick(), h.digest(), wire.len, h.log.items.len });
    }

    // What a participant is handed on join: INPUT records only, never a snapshot.
    const backlog = try host.inputRecordsOnly(gpa, h.log.items);
    defer gpa.free(backlog);
    try out.print("backlog for a late join: {d}B of {d}B (inputs only)\n", .{ backlog.len, h.log.items.len });

    var fbuf: [4096]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(init.io, log_path, .{});
    defer file.close(init.io);
    var filew = file.writer(init.io, &fbuf);
    try filew.interface.writeAll(h.log.items);
    try filew.interface.flush();

    try out.print("exported {d}B to {s}: final tick {d} digest {d}\n", .{ h.log.items.len, log_path, h.tick(), h.digest() });
}
