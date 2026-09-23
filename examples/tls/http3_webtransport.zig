// WebTransport over HTTP/3: an echo server that accepts sessions on /echo, echoes every data stream and
// every datagram back, and opens one unidirectional stream per session to say hello. WebTransport is a
// feature of the HTTP/3 server (zix.Http3), configured per server: turning it on advertises the settings
// and transport parameters a client needs (SETTINGS_WT_ENABLED, SETTINGS_ENABLE_CONNECT_PROTOCOL,
// SETTINGS_H3_DATAGRAM, max_datagram_frame_size, reset_stream_at), accepts extended CONNECT requests,
// and allocates the worker pool sessions and data streams come from.
//
// The application surface is zix.Webtransport: a handler of callbacks and two handles, Session and
// Stream. Nothing in this file names a stream id, a frame, or a capsule.
//
// Clients: any WebTransport over HTTP/3 client, including the deployed draft that browsers and aioquic
// still send (the binding accepts both revisions). The session's dialect is available to the
// application, which only has to care when it wants the session-level flow control that draft-16 adds.

const std = @import("std");
const zix = @import("zix");

// --------------------------------------------------------- //

const IP: []const u8 = "127.0.0.1";
const PORT: u16 = 9089;
// Demo fixtures. For a real domain, point CERT / KEY at your certbot files.
const CERT: []const u8 = "examples/certs/ecdsa_p256_cert.pem";
const KEY: []const u8 = "examples/certs/ecdsa_p256_key.pem";

/// The path a session is accepted on. Every other path is refused with 404, which is how an application
/// serves WebTransport on one resource of a host and ordinary requests on the rest.
const SESSION_PATH: []const u8 = "/echo";

/// The banner written on the unidirectional stream opened for each new session.
const BANNER: []const u8 = "zix webtransport echo: write to a stream, or send a datagram\n";

// --------------------------------------------------------- //

// A plain HTTP/3 route, to show that WebTransport sessions and ordinary requests share one connection:
// a client may fetch / while its WebTransport session is open.
fn home(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.send("hello over http/3 (WebTransport sessions are accepted on /echo)\n");
}

// --------------------------------------------------------- //

/// Accept a session on SESSION_PATH, refuse anything else.
fn onSession(session: *zix.Webtransport.Session) ?u16 {
    const request = session.sessionRequest();
    std.debug.print("[wt] session {d} requested ({s} {s}, dialect {s})\n", .{
        session.id(),
        request.protocol,
        request.path,
        @tagName(request.dialect),
    });

    if (!std.mem.eql(u8, request.path, SESSION_PATH)) return 404;

    // One unidirectional stream per session, opened by the server: the client sees a stream it did not
    // open, which is the shape a server push of events takes over WebTransport.
    if (session.openUni()) |stream| {
        _ = stream.write(BANNER);
        stream.finish();
    }

    return null;
}

/// Echo whatever arrives on a data stream. The write can be short when the peer's window is full, which
/// is normal back pressure: a real application keeps the remainder and writes it from its next callback.
/// This example echoes what fits and says so.
fn onStream(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    _ = session;
    const chunk = stream.read();
    if (chunk.len == 0) {
        if (stream.finished()) std.debug.print("[wt] stream {d} finished by the peer\n", .{stream.id()});

        return;
    }

    var written: usize = 0;
    while (written < chunk.len) {
        const queued = stream.write(chunk[written..]);
        if (queued == 0) break;
        written += queued;
    }

    std.debug.print("[wt] stream {d} echoed {d}/{d} bytes\n", .{ stream.id(), written, chunk.len });
    if (written == chunk.len) stream.finish();
}

/// A reset stream carries the peer's application error code, when it was one (a reset with a code
/// outside the WebTransport application range reads as null).
fn onStreamReset(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    _ = session;
    std.debug.print("[wt] stream {d} reset by the peer (code {?d})\n", .{ stream.id(), stream.resetCode() });
}

/// Echo a datagram back. Datagrams are unreliable by construction: the send can be refused when the
/// congestion window has no room or the payload does not fit, and the engine drops those.
fn onDatagram(session: *zix.Webtransport.Session, datagram: []const u8) void {
    if (!session.sendDatagram(datagram)) {
        std.debug.print("[wt] datagram of {d} bytes dropped (window or size)\n", .{datagram.len});

        return;
    }

    std.debug.print("[wt] datagram of {d} bytes echoed\n", .{datagram.len});
}

/// A session ends when its CONNECT stream closes, when either side sends a close capsule, or with the
/// connection. `closeInfo` says which, and carries the peer's application code and message.
fn onClose(session: *zix.Webtransport.Session) void {
    const info = session.closeInfo();
    std.debug.print("[wt] session {d} closed: {s} code={d} message=\"{s}\"\n", .{
        session.id(),
        @tagName(info.reason),
        info.code,
        info.message,
    });
}

// --------------------------------------------------------- //

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = CERT,
        .key_path = KEY,
    });
    defer tls.deinit();

    const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
        .{ .path = "/", .handler = home },
    });

    var server = zix.Http3.Server.init(Routes.dispatch, .{
        .io = process.io,
        .allocator = std.heap.smp_allocator,
        .ip = IP,
        .port = PORT,
        .dispatch_model = .ASYNC,
        .tls = &tls,
        .webtransport = .{
            .enabled = true,
            .max_sessions_per_connection = 4,
            .max_streams_bidi = 16,
            .max_streams_uni = 16,
            .max_session_data = 1 << 20,
            .handler = .{
                .on_session = onSession,
                .on_stream = onStream,
                .on_stream_reset = onStreamReset,
                .on_datagram = onDatagram,
                .on_close = onClose,
            },
        },
    });
    defer server.deinit();

    try server.run();
}
