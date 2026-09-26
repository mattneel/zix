//! localbench: zix-ws
//!
//! zix.Http1 WebSocket (.URING), Router-only: one handler module per route
//! (src/handlers/). GET /ws upgrades, then the engine drives the echo loop:
//! frames are echoed on readiness and a pipelined burst is coalesced into one
//! write.

const std = @import("std");
const zix = @import("zix");

const ws = @import("handlers/ws.zig");

// --------------------------------------------------------- //

const Routes = zix.Http1.Router(&[_]zix.Http1.Route{
    .{ .path = ws.PATH, .handler = ws.RESPONSE },
});

/// Zig++'s std.Io.Threadz, `void` on a Zig without it.
const Threadz = blk: {
    if (!@hasDecl(std.Io, "Threadz")) break :blk void;
    break :blk std.Io.Threadz;
};

pub fn main(process: std.process.Init) !void {
    // ZIX_IO=threadz runs the server on std.Io.Threadz: each io_uring loop is a task pinned to
    // one worker, on that worker's ring, instead of a thread with a ring of its own.
    var threadz: Threadz = undefined;
    const on_threadz = Threadz != void and std.mem.eql(u8, process.environ_map.get("ZIX_IO") orelse "", "threadz");
    if (on_threadz) try threadz.init(std.heap.smp_allocator, .{ .log2_ring_entries = 12 });
    defer if (on_threadz) threadz.deinit();
    const io = if (on_threadz) threadz.io() else process.io;

    var server = zix.Http1.Server.init(Routes.dispatch, .{
        .io = io,
        .ip = "::",
        .port = 8080,
        .workers = 0,
        .dispatch_model = .URING,
        //
        .send_date_header = false,
        //
        .kernel_backlog = 16 * 1024,
        .max_recv_buf = 4 * 1024,
        .ws_recv_buf = 32 * 1024,
    });
    defer server.deinit();

    try server.run();
}
