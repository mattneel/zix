// WebTransport live view: one process, one port number, two protocols. The browser loads the page over
// HTTPS/1.1 on TCP, and that page opens a WebTransport session over HTTP/3 on the same host and port
// over UDP, so the page and the session share one origin and no cross-origin question arises.
//
// What the demo shows, through the application surface only (zix.Webtransport: a handler of callbacks
// plus the Session and Stream handles; nothing here names a stream id, a frame, or a capsule):
//
// - The server owns the state: a revision, a tick counter, uploaded bytes, and a note count. Every
//   change bumps the revision and is pushed to the subscribing client as one typed event line.
// - A bidirectional data stream is the subscription. The client subscribes, ticks, and reads increment
//   events off the same stream, which it renders into the DOM.
// - A datagram carries a note and returns its patch. Datagrams are unreliable by construction, so a
//   lost patch is not repaired by a retransmit: the client converges on the next snapshot, and every
//   subscription starts with one. That is the shape a live view takes when it mixes both channels.
// - A second bidirectional stream uploads while the first keeps ticking, so progress events and
//   increment events interleave: concurrent streams on one session, each with its own flow control.
// - Reconnecting opens a new session against the same server state, and the subscription answers with
//   a current snapshot: the client resynchronizes to a revision whose events it never saw.
//
// Two things shape the application code. A stream handle is only valid for the callback that delivered
// it, so the application keeps counters, not stream pointers, and pushes an event when traffic arrives
// rather than from a timer. And a server configured with one worker runs every WebTransport callback
// on one thread, which is why this state needs no lock: a multi-worker server would add one.

const std = @import("std");
const builtin = @import("builtin");
const zix = @import("zix");

// --------------------------------------------------------- //

const IP: []const u8 = "127.0.0.1";
/// The port the demo binds twice: TCP for the page (HTTPS/1.1) and UDP for the session (HTTP/3).
const PORT: u16 = 9443;
// Demo fixtures. For a real domain, point CERT / KEY at your certbot files.
const CERT: []const u8 = "examples/certs/ecdsa_p256_cert.pem";
const KEY: []const u8 = "examples/certs/ecdsa_p256_key.pem";

/// The path a WebTransport session is accepted on. Every other path is refused with 404.
const SESSION_PATH: []const u8 = "/live";

/// The page, embedded so the binary runs from any working directory.
const PAGE: []const u8 = @embedFile("webtransport_live.html");

/// Longest note text the demo keeps from a datagram, the longest application line it answers with, and
/// the longest command line it will assemble from a stream that splits one.
const MAX_NOTE: usize = 48;
const EVENT_BYTES: usize = 256;
const COMMAND_BYTES: usize = 64;

// --------------------------------------------------------- //

/// The state the server owns. Every change is a revision, and a subscription gets the whole struct:
/// that is what makes a reconnect a resynchronization rather than a fresh start.
const State = struct {
    revision: u64 = 0,
    count: u64 = 0,
    uploaded: u64 = 0,
    uploads: u64 = 0,
    notes: u64 = 0,
    slots: [slot_cap]Slot = @splat(.{}),

    /// One data stream this application tracks. A slot holds counters, never a stream handle, because a
    /// handle is only valid inside the callback that delivered it.
    const Slot = struct {
        session: ?*zix.Webtransport.Session = null,
        stream_id: u64 = 0,
        role: Role = .unknown,
        received: u64 = 0,
        total: u64 = 0,
        /// Command bytes that arrived without their line ending yet.
        partial: [COMMAND_BYTES]u8 = undefined,
        partial_len: usize = 0,

        const Role = enum { unknown, feed, upload };
    };

    const slot_cap: usize = 32;

    /// The slot for this session's stream, taken on first sight.
    fn slot(self: *State, session: *zix.Webtransport.Session, stream_id: u64) ?*Slot {
        for (&self.slots) |*entry| {
            if (entry.session == session and entry.stream_id == stream_id) return entry;
        }

        for (&self.slots) |*entry| {
            if (entry.session == null) {
                entry.* = .{ .session = session, .stream_id = stream_id };

                return entry;
            }
        }

        return null;
    }

    /// Drop a slot once its stream is done, so a later stream reuses it.
    fn release(self: *State, session: *zix.Webtransport.Session, stream_id: u64) void {
        for (&self.slots) |*entry| {
            if (entry.session == session and entry.stream_id == stream_id) entry.* = .{};
        }
    }

    /// Drop every slot of a session that just closed.
    fn releaseSession(self: *State, session: *zix.Webtransport.Session) void {
        for (&self.slots) |*entry| {
            if (entry.session == session) entry.* = .{};
        }
    }

    /// The snapshot a subscription starts with.
    fn snapshotEvent(self: *State, out: []u8) []const u8 {
        return std.fmt.bufPrint(out, "{{\"kind\":\"snapshot\",\"rev\":{d},\"count\":{d},\"uploaded\":{d},\"uploads\":{d},\"notes\":{d}}}\n", .{
            self.revision, self.count, self.uploaded, self.uploads, self.notes,
        }) catch out[0..0];
    }

    /// One tick: the counter and the revision move together, and the event names both.
    fn tick(self: *State, out: []u8) []const u8 {
        self.count += 1;
        self.revision += 1;

        return std.fmt.bufPrint(out, "{{\"kind\":\"increment\",\"rev\":{d},\"count\":{d}}}\n", .{ self.revision, self.count }) catch out[0..0];
    }

    /// Upload progress: the bytes counted so far against the total the stream announced.
    fn progress(self: *State, received: u64, total: u64, done: bool, out: []u8) []const u8 {
        if (done) {
            self.uploads += 1;
            self.uploaded += received;
            self.revision += 1;
        }

        return std.fmt.bufPrint(out, "{{\"kind\":\"{s}\",\"rev\":{d},\"received\":{d},\"total\":{d},\"uploads\":{d}}}\n", .{
            if (done) "upload_done" else "upload", self.revision, received, total, self.uploads,
        }) catch out[0..0];
    }

    /// A note that arrived in a datagram: the count moves, and the revision with it.
    fn note(self: *State, out: []u8) []const u8 {
        self.notes += 1;
        self.revision += 1;

        return std.fmt.bufPrint(out, "{{\"kind\":\"note\",\"rev\":{d},\"notes\":{d}}}\n", .{ self.revision, self.notes }) catch out[0..0];
    }

    /// The banner the server pushes on a unidirectional stream, so the page can show a server-opened
    /// stream next to the ones it opened itself.
    fn banner(self: *State, out: []u8) []const u8 {
        return std.fmt.bufPrint(out, "zix webtransport live: rev {d}, {d} ticks, {d} uploads, {d} notes\n", .{
            self.revision, self.count, self.uploads, self.notes,
        }) catch out[0..0];
    }
};

var state: State = .{};

// --------------------------------------------------------- //

/// The page. One origin, no store: the demo is meant to be reloaded.
fn page(_: *zix.Http1.Request, res: *zix.Http1.Response, _: *zix.Http1.Context) !void {
    var head_buf: [192]u8 = undefined;
    var head = std.Io.Writer.fixed(&head_buf);
    head.print("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nCache-Control: no-store\r\n\r\n", .{PAGE.len}) catch return;

    try res.sendRaw(head.buffered());
    try res.sendRaw(PAGE);
}

// --------------------------------------------------------- //

/// Accept a session on SESSION_PATH, refuse anything else, and push the banner on the unidirectional
/// stream the server opens for it.
fn onSession(session: *zix.Webtransport.Session) ?u16 {
    const request = session.sessionRequest();
    std.debug.print("[live] session {d} requested ({s} {s}, dialect {s})\n", .{
        session.id(),
        request.protocol,
        request.path,
        @tagName(request.dialect),
    });

    if (!std.mem.eql(u8, request.path, SESSION_PATH)) return 404;

    if (session.openUni()) |stream| {
        var buf: [EVENT_BYTES]u8 = undefined;
        writeLine(&stream, state.banner(&buf));
        stream.finish();
    }

    return null;
}

/// One chunk of application bytes on a data stream: command lines on the subscription, upload bytes on
/// the stream that announced a size, and a progress event back on the stream that produced them.
fn onStream(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    const chunk = stream.read();
    const entry = state.slot(session, stream.id()) orelse {
        std.debug.print("[live] session {d} stream {d}: no slot free, {d} bytes dropped\n", .{ session.id(), stream.id(), chunk.len });

        return;
    };

    if (entry.role == .upload) {
        entry.received += chunk.len;

        var buf: [EVENT_BYTES]u8 = undefined;
        const done = stream.finished();
        writeLine(stream, state.progress(entry.received, entry.total, done, &buf));

        if (done) {
            std.debug.print("[live] session {d} stream {d}: upload of {d} bytes complete\n", .{ session.id(), stream.id(), entry.received });
            state.release(session, stream.id());
        }

        return;
    }

    consumeCommands(session, stream, entry, chunk);
}

/// Assemble command lines from a byte chunk: whatever a previous chunk left half-said, then this chunk,
/// one line at a time. Bytes past the last line ending wait for the next chunk, which is what makes a
/// split line harmless.
fn consumeCommands(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream, entry: *State.Slot, chunk: []const u8) void {
    var joined: [COMMAND_BYTES * 2]u8 = undefined;

    const carried = entry.partial_len;
    const copy = @min(chunk.len, joined.len - carried);
    @memcpy(joined[0..carried], entry.partial[0..carried]);
    @memcpy(joined[carried..][0..copy], chunk[0..copy]);

    var rest = joined[0 .. carried + copy];
    while (std.mem.indexOfScalar(u8, rest, '\n')) |end| {
        handleLine(session, stream, entry, rest[0..end]);
        rest = rest[end + 1 ..];
    }

    if (rest.len > entry.partial.len) {
        // A line longer than any command this application defines: drop it rather than grow without
        // bound on a stream that never sends a line ending.
        std.debug.print("[live] session {d} stream {d}: command line too long, dropped\n", .{ session.id(), stream.id() });
        entry.partial_len = 0;

        return;
    }

    @memcpy(entry.partial[0..rest.len], rest);
    entry.partial_len = rest.len;
}

/// One command line from the subscription stream.
fn handleLine(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream, entry: *State.Slot, line: []const u8) void {
    var buf: [EVENT_BYTES]u8 = undefined;

    if (std.mem.eql(u8, line, "sub")) {
        entry.role = .feed;
        writeLine(stream, state.snapshotEvent(&buf));
        std.debug.print("[live] session {d} stream {d}: subscribed\n", .{ session.id(), stream.id() });

        return;
    }

    if (std.mem.eql(u8, line, "tick")) {
        entry.role = .feed;
        writeLine(stream, state.tick(&buf));

        return;
    }

    if (std.mem.startsWith(u8, line, "upload:")) {
        const total = std.fmt.parseInt(u64, line["upload:".len..], 10) catch 0;
        entry.role = .upload;
        entry.total = total;
        entry.received = 0;
        std.debug.print("[live] session {d} stream {d}: upload of {d} bytes announced\n", .{ session.id(), stream.id(), total });

        return;
    }

    std.debug.print("[live] session {d} stream {d}: unknown command \"{s}\"\n", .{ session.id(), stream.id(), line });
}

/// The application's own back-pressure policy: an event line is small, so one write takes it. A short
/// write is reported rather than retried here, because a retry belongs in the next callback, where the
/// peer's window has moved and the handle is valid again.
fn writeLine(stream: *const zix.Webtransport.Stream, line: []const u8) void {
    if (line.len == 0) return;

    const queued = stream.write(line);
    if (queued != line.len) std.debug.print("[live] stream {d}: {d} of {d} event bytes queued (window full)\n", .{ stream.id(), queued, line.len });
}

/// A datagram: the note the page typed, answered with a datagram carrying the patch. Nothing here is
/// retransmitted, which is the point of the channel.
fn onDatagram(session: *zix.Webtransport.Session, datagram: []const u8) void {
    const note = if (std.mem.startsWith(u8, datagram, "note:")) safeNote(datagram["note:".len..]) else "";

    var buf: [EVENT_BYTES]u8 = undefined;
    if (!session.sendDatagram(state.note(&buf))) {
        std.debug.print("[live] datagram patch dropped (window or size)\n", .{});
    }

    std.debug.print("[live] session {d}: note \"{s}\" ({d} bytes in, patch out)\n", .{ session.id(), note, datagram.len });
}

/// Keep what the page typed to characters a log line and a JSON string can carry unchanged.
fn safeNote(text: []const u8) []const u8 {
    const kept = @min(text.len, MAX_NOTE);

    return text[0..kept];
}

/// A session ends when its CONNECT stream closes, when either side sends a close capsule, or with the
/// connection.
fn onClose(session: *zix.Webtransport.Session) void {
    const info = session.closeInfo();
    state.releaseSession(session);

    std.debug.print("[live] session {d} closed: {s} code={d} message=\"{s}\"\n", .{
        session.id(),
        @tagName(info.reason),
        info.code,
        info.message,
    });
}

/// The same page over HTTP/3, so a browser can load it either way: it is the page a session is opened
/// from, and serving it on both transports keeps the demo one origin whichever protocol the browser
/// picks for the navigation.
fn root(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.content_type = "text/html; charset=utf-8";
    res.send(PAGE);
}

// --------------------------------------------------------- //

pub fn main(process: std.process.Init) !void {
    var page_tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = CERT,
        .key_path = KEY,
        .alpn = &.{.HTTP_1_1},
    });
    defer page_tls.deinit();

    var session_tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = CERT,
        .key_path = KEY,
    });
    defer session_tls.deinit();

    var page_server = zix.Http1.Server.init(page, .{
        .io = process.io,
        .ip = IP,
        .port = PORT,
        .tls = &page_tls,
        .dispatch_model = if (builtin.os.tag == .linux) .URING else .ASYNC,
        .workers = 1,
    });
    defer page_server.deinit();

    const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
        .{ .path = "/", .handler = root },
    });

    var live_server = zix.Http3.Server.init(Routes.dispatch, .{
        .io = process.io,
        .allocator = std.heap.smp_allocator,
        .ip = IP,
        .port = PORT,
        .dispatch_model = .ASYNC,
        // One worker: every WebTransport callback of this server runs on one thread, which is what lets
        // the state above stay lock-free.
        .workers = 1,
        .tls = &session_tls,
        .webtransport = .{
            .enabled = true,
            .max_sessions_per_connection = 4,
            .max_streams_bidi = 16,
            .max_streams_uni = 16,
            .max_session_data = 1 << 20,
            .handler = .{
                .on_session = onSession,
                .on_stream = onStream,
                .on_datagram = onDatagram,
                .on_close = onClose,
            },
        },
    });
    defer live_server.deinit();

    // The two servers differ in transport, not in port number: the page's origin and the session's URL
    // are the same authority.
    const PageServer = @TypeOf(page_server);
    var page_thread = try std.Thread.spawn(.{}, struct {
        fn serve(server: *PageServer) void {
            server.run() catch |err| std.debug.print("[live] page server stopped: {s}\n", .{@errorName(err)});
        }
    }.serve, .{&page_server});
    page_thread.detach();

    std.debug.print("[live] page https://{s}:{d}/ · session https://{s}:{d}{s}\n", .{ IP, PORT, IP, PORT, SESSION_PATH });

    try live_server.run();
}
