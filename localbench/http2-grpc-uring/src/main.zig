//! localbench: zix-grpc
//!
//! zix.Grpc (.URING) over h2c, one handler module per RPC (src/handlers/).
//! Shared-nothing: each worker owns its SO_REUSEPORT listener, its io_uring
//! completion ring, and its connections, multiplexing h2 streams per
//! connection. Nothing is cached.

const std = @import("std");
const zix = @import("zix");

const getsum = @import("handlers/getsum.zig");
const streamsum = @import("handlers/streamsum.zig");

// --------------------------------------------------------- //

// The engine reads is_server_streaming off the route table before any handler
// runs, to pick sync-inline against task-spawn dispatch, so init takes the
// router TYPE rather than a handler pointer.
const Routes = zix.Grpc.Router(&[_]zix.Grpc.Route{
    .{ .path = getsum.PATH, .handler = getsum.RESPONSE },
    .{ .path = streamsum.PATH, .handler = streamsum.RESPONSE, .is_server_streaming = true },
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

    var server = zix.Grpc.Server.init(Routes, .{
        .io = io,
        .ip = "::",
        .port = 8080,
        .workers = 0,
        .dispatch_model = .URING,
        //
        .kernel_backlog = 16 * 1024,
        //
        // Wide enough that a client opening many parallel streams is never
        // refused: h2load drives 100 at a time. Per-stream buffers are small,
        // so a wide table stays cheap.
        .max_streams = 128,
        .max_body = 4 * 1024,
    });
    defer server.deinit();

    try server.run();
}
