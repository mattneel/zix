// Test runner for zix.Webtransport (WebTransport over HTTP/3, http3_webtransport on UDP port 9089).
// Spawns the WebTransport echo server, drives one session end to end with the hand-rolled http3_client
// (extended CONNECT on /echo, a bidirectional data-stream echo, a datagram echo, and the banner the
// server writes on the unidirectional stream it opens per session), then kills the server.
//
// Invoked by `zig build test-runner-webtransport`.
// argv[1]: server binary path, argv[2]: label, argv[3]: port.
//
// Note:
// - The client is hand-rolled from zix.Http3 primitives, the same way the plain HTTP/3 runner hand-rolls
//   one from the frame and QPACK primitives. QUIC binds a UDP socket with no TCP accept to poll, so the
//   server is given a short fixed moment to bind before the client connects.

const std = @import("std");
const common = @import("common.zig");
const http3_client = @import("http3_client.zig");

const SERVER_IP: []const u8 = "127.0.0.1";
const WAIT_MS: i64 = 1200;

/// The path the example accepts sessions on. Every other one is answered 404.
const SESSION_PATH: []const u8 = "/echo";

/// What the example writes on the unidirectional stream it opens for each session.
const BANNER: []const u8 = "zix webtransport echo: write to a stream, or send a datagram\n";

/// The bytes the runner sends on a data stream and inside a datagram, so a short, padded, or reordered
/// echo is a mismatch rather than a pass.
const STREAM_PAYLOAD: []const u8 = "zix webtransport runner stream";
const DATAGRAM_PAYLOAD: []const u8 = "zix webtransport runner datagram";

// --------------------------------------------------------- //

fn run(io: std.Io, server_path: []const u8, port: u16) !void {
    var server_child = try common.spawnServer(io, server_path);
    defer server_child.kill(io);

    try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(WAIT_MS), .awake);

    // One session: the extended CONNECT has to be answered with 2xx before anything else can flow.
    var session = try http3_client.webtransportConnect(io, SERVER_IP, port, SESSION_PATH);
    defer session.close();

    // The server opens one unidirectional stream per session, writes a banner, and finishes the stream.
    var banner_buf: [128]u8 = undefined;
    const banner = try http3_client.webtransportBanner(&session, &banner_buf);

    if (!std.mem.eql(u8, banner, BANNER)) return error.UnexpectedBanner;

    // A client bidirectional stream: the signal value, the session id, then the payload. The server
    // echoes the payload back on the same stream and finishes it.
    var stream_buf: [128]u8 = undefined;
    const echoed = try http3_client.webtransportStream(&session, STREAM_PAYLOAD, &stream_buf);

    if (!std.mem.eql(u8, echoed, STREAM_PAYLOAD)) return error.UnexpectedStreamEcho;

    // A datagram: the QUIC DATAGRAM frame carries the HTTP/3 datagram framing, and the server echoes
    // the payload back in a datagram of its own.
    var datagram_buf: [128]u8 = undefined;
    const datagram = try http3_client.webtransportDatagram(&session, DATAGRAM_PAYLOAD, &datagram_buf);

    if (!std.mem.eql(u8, datagram, DATAGRAM_PAYLOAD)) return error.UnexpectedDatagramEcho;
}

// --------------------------------------------------------- //

pub fn main(process: std.process.Init) void {
    var arg_iter = common.argsIterator(process.minimal.args);
    _ = arg_iter.skip();
    const server_path = arg_iter.next() orelse {
        std.debug.print("FAIL webtransport: missing server path\n", .{});
        std.process.exit(1);
    };
    const label = arg_iter.next() orelse {
        std.debug.print("FAIL webtransport: missing label\n", .{});
        std.process.exit(1);
    };

    if (common.skipDispatchOffPlatform(label)) return;

    const port_str = arg_iter.next() orelse {
        std.debug.print("FAIL {s}: missing port\n", .{label});
        std.process.exit(1);
    };
    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        std.debug.print("FAIL {s}: invalid port\n", .{label});
        std.process.exit(1);
    };

    run(process.io, server_path, port) catch |err| {
        std.debug.print("FAIL {s}: {}\n", .{ label, err });
        std.process.exit(1);
    };

    common.printPass(label);
}
