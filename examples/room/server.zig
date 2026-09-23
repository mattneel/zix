//! The room, served over HTTP/3 and WebTransport: gkz's host seam, implemented on zix.
//!
//! gkz ships a host for this same room on Cloudflare — a Durable Object per room, WebSockets for transport,
//! SQLite for the run log. SPEC §14 deliberately leaves that layer outside the kernel ("sockets, framing over
//! the network, room routing and hibernation live above this, in the host"), so this is a second host, not a
//! second room: the same `room.zig`, compiled natively, driven through the same ABI, exporting the same run
//! log. gkz's `replay` command is the acceptance gate for both — a session driven through here must replay
//! natively to the same per-tick digests.
//!
//! What the transport carries, and why it is split this way:
//!
//! - **The control stream** (one per session, opened by the browser) carries what must not be lost: the room's
//!   own input vocabulary — `[dx+1, dy+1]` for "this move, now", `[dx+1, dy+1, u32 tick]` for "this move, for
//!   tick N" — exactly the frames gkz's Durable Object accepts, so both hosts speak one language. A single
//!   zero byte on the same stream means "send me what you have", and the server answers with a status line and
//!   the confirmed input records the client has not seen.
//! - **Datagrams** carry what may be lost: presence, and where a participant is looking (a preview, replaced
//!   by the next one). Each is also a pull, since it arrives on the connection it belongs to.
//! - **A second stream**, opened on demand, carries the run log — the replay, and the thing a natively
//!   replayable session is proven by.
//!
//! One property is structural rather than a rule: a SNAPSHOT record never reaches a socket. The participant-
//! facing stream is the run log filtered to `kind == input`, the same filter gkz's host applies, so world
//! bytes have no path to the wire.
//!
//! Note on pushes: a client is answered on its own traffic, never from another connection. That is not a
//! shortcut — a session handle is only valid inside a callback of its own connection (`WtCall.sendDatagram`
//! seals onto `call.conn`), so a cross-connection push is impossible by construction. The presence heartbeat is
//! what bounds the delay: a participant's view catches up within one heartbeat of somebody else's move.

const std = @import("std");
const zix = @import("zix");
const host = @import("host.zig");

const max_sources = host.max_sources;

/// The page, and the module it loads. The room's wasm build is the same `room.zig` this process links
/// natively, which is the point: server and browser run one kernel, and their digests agree by construction.
const PAGE: []const u8 = @embedFile("page.html");

/// Stream message framing. A WebTransport stream is a byte stream, unlike the message-oriented socket gkz's
/// Durable Object terminates, so the two kinds of server-to-client message are framed apart:
/// `[u8 tag][u32 len][payload]`.
const tag_json: u8 = 1;
const tag_records: u8 = 2;

/// The control stream's vocabulary. Inputs are 2 or 6 bytes, so a single byte is unambiguous.
const byte_pull: u8 = 0x00;

/// Presence datagrams: `[u8 kind][i32 viewed_tick][u8 flags]` from a client, answered with a table of the
/// others. Replaceable in both directions, which is why they are datagrams.
const presence_from_client: u8 = 0x01;
const presence_from_server: u8 = 0x02;

/// The largest record batch written in one stream message. Records are self-delimiting inside a frame, so a
/// long backlog is split across several frames without the client needing to know.
const max_record_frame = 4096;

const SESSION_PATH = "/room";

var SESSION_IP: []const u8 = "127.0.0.1";
var PAGE_IP: []const u8 = "127.0.0.1";
var PORT: u16 = 9444;
var PAGE_PORT: u16 = 9444;
var PUBLIC_PORT: u16 = 9443;
var CERT: []const u8 = "examples/certs/ecdsa_p256_cert.pem";
var KEY: []const u8 = "examples/certs/ecdsa_p256_key.pem";
var ROOM_CODE: []const u8 = "lobby";
var WASM_PATH: []const u8 = "zig-out/web/room/room.wasm";

var gpa: std.mem.Allocator = undefined;

/// The room. One per process: the room's state is module-level in `room.zig`, exactly as it is inside the wasm
/// instance a Durable Object owns, so a second timeline is a second process.
var room_host: host.Host = undefined;

/// The wasm module the page loads, read once at startup.
var room_wasm: []const u8 = &.{};

/// The log bytes already handed to a participant, filtered to INPUT records. Recomputed from the log on each
/// pull: the room's log is small by construction (53 bytes per confirmed tick) and this filter is what keeps
/// snapshots off the wire, so this is where that property lives.
var filtered: std.ArrayList(u8) = .empty;

/// One participant's host-side view. Sources are 1..max_sources and are what the room and the other players
/// see; the only per-participant state the host keeps is what it has already sent and where it is looking.
const Participant = struct {
    source: u32 = 0,
    /// Which connection holds this source.
    ///
    /// Not `Session.id()`: that is the CONNECT stream id (Webtransport.zig), which is unique within one
    /// connection and repeats across connections, so every client of a host seats itself as session 0. The
    /// session's own address is stable for as long as it lives and distinct per connection, and `onClose`
    /// clears the entry, so a recycled slot is never mistaken for the session that used it before.
    session_key: usize = 0,
    /// The id of the session's control stream; a later stream is a request for the run log.
    control_stream: u64 = 0,
    /// Bytes of the participant-facing (INPUT-only) stream already delivered.
    sent: usize = 0,
    /// Bytes of the run log already written to a replay stream.
    replay_sent: usize = 0,
    /// Where this participant says it is looking: a preview, replaced by the next report.
    viewed_tick: i32 = 0,
    flags: u8 = 0,
    joined: bool = false,
};

var participants: [max_sources + 1]Participant = @splat(.{});

fn log(comptime fmt: []const u8, args: anytype) void {
    std.log.info(fmt, args);
}

fn envOverride(env: anytype, name: []const u8) ?[]const u8 {
    const value = env.get(name) orelse return null;
    if (value.len == 0) return null;

    return value;
}

// --------------------------------------------------------- //
// The page

/// The HTTP/1.1 side exists for the first visit: a browser that has never seen this origin arrives over TCP,
/// learns the alt-svc, and moves to HTTP/3 for everything after. Both listeners serve the page, the module
/// and the favicon, because once the browser moves, an endpoint that lives only here answers 404.
fn servePage(req: *zix.Http1.Request, res: *zix.Http1.Response, ctx: *zix.Http1.Context) !void {
    _ = ctx;
    const path = req.path();
    const public_port: u16 = if (PUBLIC_PORT == 0) PORT else PUBLIC_PORT;

    if (std.mem.eql(u8, path, "/room.wasm")) return sendRaw(res, "application/wasm", room_wasm, public_port);
    if (std.mem.eql(u8, path, "/favicon.ico")) return sendRaw(res, "image/x-icon", "", public_port);
    if (!std.mem.eql(u8, path, "/")) {
        res.status = .NOT_FOUND;

        return sendRaw(res, "text/plain", "not found", public_port);
    }

    return sendRaw(res, "text/html; charset=utf-8", PAGE, public_port);
}

/// A response with the alt-svc that moves the browser to HTTP/3. Without it the page keeps arriving over
/// TCP and the session is the only thing on QUIC, which is a fine demo but not the deployed behaviour.
fn sendRaw(res: *zix.Http1.Response, content_type: []const u8, body: []const u8, public_port: u16) !void {
    var head_buf: [256]u8 = undefined;
    var head = std.Io.Writer.fixed(&head_buf);
    head.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nAlt-Svc: h3=\":{d}\"; ma=86400\r\n\r\n",
        .{ res.status, "OK", content_type, body.len, public_port },
    ) catch return;

    try res.sendRaw(head.buffered());
    try res.sendRaw(body);
}

fn root(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.content_type = "text/html; charset=utf-8";
    res.send(PAGE);
}

fn wasm(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    if (room_wasm.len == 0) {
        res.status = 404;
        res.content_type = "text/plain";
        res.send("room.wasm is not loaded");

        return;
    }
    res.content_type = "application/wasm";
    res.send(room_wasm);
}

fn favicon(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.status = 204;
    res.send("");
}

const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
    .{ .path = "/", .handler = root },
    .{ .path = "/favicon.ico", .handler = favicon },
    .{ .path = "/room.wasm", .handler = wasm },
});

// --------------------------------------------------------- //
// The session

fn onSession(session: *zix.Webtransport.Session) ?u16 {
    const request = session.sessionRequest();
    if (!std.mem.eql(u8, request.path, SESSION_PATH)) return 404;

    log("session {d} requested ({s} {s}, dialect {s})", .{ session.id(), request.protocol, request.path, @tagName(request.dialect) });

    return null;
}

/// A client chunk on a data stream: the control vocabulary, or a request for the run log.
fn onStream(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    const p = seat(session) orelse return;

    if (p.control_stream == 0) {
        p.control_stream = stream.id();
        sendHello(stream, p) catch {};
        sendPending(stream, p) catch {};

        return;
    }

    if (stream.id() != p.control_stream) return sendRunLog(stream, p);

    const chunk = stream.read();
    if (chunk.len == 0) return;

    var rest = chunk;
    while (rest.len > 0) {
        if (rest.len >= 6) {
            // A move for a chosen tick: the room's scheduled submission, and the primitive a branch is built
            // from — the same tick may be reopened with a different input.
            const dx: i32 = @as(i32, rest[0]) - 1;
            const dy: i32 = @as(i32, rest[1]) - 1;
            const at_tick = std.mem.readInt(u32, rest[2..6], .little);
            _ = room_host.submitAt(p.source, at_tick, dx, dy);
            rest = rest[6..];
        } else if (rest.len >= 2) {
            // A move now. Under the reactive policy one accepted action is one confirmed tick.
            const dx: i32 = @as(i32, rest[0]) - 1;
            const dy: i32 = @as(i32, rest[1]) - 1;
            _ = room_host.action(p.source, dx, dy);
            rest = rest[2..];
        } else if (rest[0] == byte_pull) {
            rest = rest[1..];
        } else break; // a fragment the next chunk completes
    }

    room_host.appendLog() catch {};
    sendPending(stream, p) catch {};
}

/// Presence: what a participant is looking at, and the pull that keeps its view current. The reply is the
/// table of everybody else, and it is a datagram because the next one replaces it.
fn onDatagram(session: *zix.Webtransport.Session, datagram: []const u8) void {
    const p = seat(session) orelse return;

    if (datagram.len >= 6 and datagram[0] == presence_from_client) {
        p.viewed_tick = std.mem.readInt(i32, datagram[1..5], .little);
        p.flags = datagram[5];
    }

    const table = presenceTable(p.source);
    _ = session.sendDatagram(&table);
}

fn onStreamReset(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    log("session {d} stream {d} reset by the peer", .{ session.id(), stream.id() });
}

fn onClose(session: *zix.Webtransport.Session) void {
    const p = find(sessionKey(session)) orelse return;
    if (p.joined) {
        _ = room_host.leave(p.source);
        // A reactive room folds the leave into the next tick straight away. A scheduled room must not: the
        // others are mid-answer for the open tick, and an empty fill would make their real submission arrive as
        // a refused duplicate.
        _ = room_host.idleTick();
        room_host.appendLog() catch {};
    }

    log("session {d} closed: source {d} left the room", .{ session.id(), p.source });
    p.* = .{};
}

/// The key a participant is held under: the live session's address, not its id. See `Participant`.
fn sessionKey(session: *zix.Webtransport.Session) usize {
    return @intFromPtr(session.inner);
}

fn find(key: usize) ?*Participant {
    for (participants[1..]) |*p| {
        if (p.joined and p.session_key == key) return p;
    }

    return null;
}

/// Seat a session the way gkz's host does: the lowest free source, a JOIN that enters the log as an input (so
/// replaying the log reconstructs the roster), and then the backlog a late join needs.
fn seat(session: *zix.Webtransport.Session) ?*Participant {
    const key = sessionKey(session);
    if (find(key)) |p| return p;

    var taken: [max_sources]u32 = undefined;
    var n: usize = 0;
    for (participants[1..]) |*p| {
        if (p.joined) {
            taken[n] = p.source;
            n += 1;
        }
    }

    const source = room_host.nextSource(taken[0..n]) orelse {
        log("connection 0x{x}: the room is full", .{sessionKey(session)});

        return null;
    };
    const p = &participants[source];
    p.* = .{ .source = source, .joined = true, .session_key = key };
    if (!room_host.isMember(source)) _ = room_host.join(source);
    room_host.appendLog() catch {};
    log("connection 0x{x}: seated as source {d}", .{ key, source });

    return p;
}

fn sendHello(stream: *const zix.Webtransport.Stream, p: *Participant) !void {
    var buf: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, "{{\"type\":\"hello\",\"room\":\"{s}\",\"seed\":{d},\"source\":{d},\"tick\":{d},\"policy\":\"reactive\"}}", .{
        room_host.code, room_host.seed, p.source, room_host.tick(),
    });

    return sendJson(stream, line);
}

/// Everything the participant has not seen: a status line, then the confirmed input records in batches. The
/// records come from the run log filtered to inputs, so a snapshot has no path here.
fn sendPending(stream: *const zix.Webtransport.Stream, p: *Participant) !void {
    var buf: [256]u8 = undefined;
    const status = try std.fmt.bufPrint(&buf, "{{\"type\":\"status\",\"tick\":{d},\"digest\":\"{d}\",\"members\":{d},\"horizon\":{d},\"logBytes\":{d}}}", .{
        room_host.tick(), room_host.digest(), room_host.members(), room_host.horizon(), room_host.log.items.len,
    });
    try sendJson(stream, status);

    filtered.clearRetainingCapacity();
    try host.filterInputs(gpa, room_host.log.items, &filtered);

    while (p.sent < filtered.items.len) {
        const room = stream.writable();
        if (room < 5) break; // the frame header alone will not fit: the next pull continues
        const take = @min(@min(room - 5, max_record_frame), filtered.items.len - p.sent);
        try sendRecords(stream, filtered.items[p.sent..][0..take]);
        p.sent += take;
    }
}

fn sendJson(stream: *const zix.Webtransport.Stream, line: []const u8) !void {
    var buf: [520]u8 = undefined;
    buf[0] = tag_json;
    std.mem.writeInt(u32, buf[1..5], @intCast(line.len), .little);
    @memcpy(buf[5..][0..line.len], line);

    _ = stream.write(buf[0 .. 5 + line.len]);
}

fn sendRecords(stream: *const zix.Webtransport.Stream, records: []const u8) !void {
    var header: [5]u8 = undefined;
    header[0] = tag_records;
    std.mem.writeInt(u32, header[1..5], @intCast(records.len), .little);
    _ = stream.write(&header);
    _ = stream.write(records);
}

/// The run log on its own stream: the replay, and what a natively replayable session is proven by. One byte
/// requests it and each further byte is credit to continue, because a stream is written as far as its window
/// allows and no further.
fn sendRunLog(stream: *const zix.Webtransport.Stream, p: *Participant) void {
    if (stream.read().len == 0) return;

    const run_log = room_host.runLog();
    if (p.replay_sent == 0) {
        var header: [4]u8 = undefined;
        std.mem.writeInt(u32, &header, @intCast(run_log.len), .little);
        _ = stream.write(&header);
    }

    while (p.replay_sent < run_log.len) {
        const take = @min(stream.writable(), run_log.len - p.replay_sent);
        if (take == 0) break;
        _ = stream.write(run_log[p.replay_sent..][0..take]);
        p.replay_sent += take;
    }

    if (p.replay_sent >= run_log.len) stream.finish();
}

/// The presence table: everyone else's scrub position. Replaceable, so it is a datagram and never a stream.
fn presenceTable(exclude: u32) [2 + max_sources * 6]u8 {
    var buf: [2 + max_sources * 6]u8 = @splat(0);
    var n: usize = 0;
    for (participants[1..]) |*p| {
        if (!p.joined or p.source == exclude) continue;
        const at = 2 + n * 6;
        buf[at] = @intCast(p.source);
        std.mem.writeInt(i32, buf[at + 1 ..][0..4], p.viewed_tick, .little);
        buf[at + 5] = p.flags;
        n += 1;
    }
    buf[0] = presence_from_server;
    buf[1] = @intCast(n);

    return buf;
}

// --------------------------------------------------------- //
// Startup

pub fn main(process: std.process.Init) !void {
    gpa = std.heap.smp_allocator;

    if (envOverride(process.environ_map, "ZIX_SESSION_IP")) |value| SESSION_IP = value;
    if (envOverride(process.environ_map, "ZIX_PAGE_IP")) |value| PAGE_IP = value;
    if (envOverride(process.environ_map, "ZIX_SESSION_PORT")) |value| PORT = std.fmt.parseInt(u16, value, 10) catch PORT;
    if (envOverride(process.environ_map, "ZIX_PAGE_PORT")) |value| PAGE_PORT = std.fmt.parseInt(u16, value, 10) catch PAGE_PORT;
    if (envOverride(process.environ_map, "ZIX_PUBLIC_PORT")) |value| PUBLIC_PORT = std.fmt.parseInt(u16, value, 10) catch PUBLIC_PORT;
    if (envOverride(process.environ_map, "ZIX_CERT")) |value| CERT = value;
    if (envOverride(process.environ_map, "ZIX_KEY")) |value| KEY = value;
    if (envOverride(process.environ_map, "ROOM_CODE")) |value| ROOM_CODE = value;
    if (envOverride(process.environ_map, "ZIX_ROOM_WASM")) |value| WASM_PATH = value;

    room_wasm = std.Io.Dir.cwd().readFileAlloc(process.io, WASM_PATH, gpa, .limited(1 << 22)) catch |err| blk: {
        log("room.wasm not loaded from {s} ({s}): the page will not run", .{ WASM_PATH, @errorName(err) });

        break :blk &.{};
    };

    room_host = host.Host.init(gpa, ROOM_CODE);
    try room_host.ready();
    log("room {s}: seed {d} tick {d} digest {d}", .{ ROOM_CODE, room_host.seed, room_host.tick(), room_host.digest() });

    var page_tls = try zix.Tls.Context.init(gpa, process.io, .{
        .cert_path = CERT,
        .key_path = KEY,
        .alpn = &.{.HTTP_1_1},
    });
    defer page_tls.deinit();

    var session_tls = try zix.Tls.Context.init(gpa, process.io, .{
        .cert_path = CERT,
        .key_path = KEY,
    });
    defer session_tls.deinit();

    var page_server = zix.Http1.Server.init(servePage, .{
        .io = process.io,
        .ip = PAGE_IP,
        .port = PAGE_PORT,
        .tls = &page_tls,
        .dispatch_model = .ASYNC,
        .workers = 1,
    });
    defer page_server.deinit();

    var room_server = zix.Http3.Server.init(Routes.dispatch, .{
        .io = process.io,
        .allocator = gpa,
        .ip = SESSION_IP,
        .port = PORT,
        .dispatch_model = .ASYNC,
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
                .on_stream_reset = onStreamReset,
                .on_datagram = onDatagram,
                .on_close = onClose,
            },
        },
    });
    defer room_server.deinit();

    const PageServer = @TypeOf(page_server);
    var page_thread = try std.Thread.spawn(.{}, struct {
        fn serve(server: *PageServer) void {
            server.run() catch |err| log("page server stopped: {s}", .{@errorName(err)});
        }
    }.serve, .{&page_server});
    page_thread.detach();

    log("room https://{s}:{d}/ · session https://{s}:{d}{s}", .{ PAGE_IP, PAGE_PORT, SESSION_IP, PORT, SESSION_PATH });

    try room_server.run();
}
