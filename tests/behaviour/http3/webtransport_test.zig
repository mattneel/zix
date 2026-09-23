//! Behaviour tests: the zix.Webtransport surface an application and a peer depend on, through the
//! handles a caller actually holds. The engine hooks here are the dispatch layer's contract (open a
//! stream, send a datagram, close a session) implemented over a worker pool, so a session and a
//! stream are driven the way a connection drives them, minus the socket.

const std = @import("std");
const zix = @import("zix");

const Webtransport = zix.Webtransport;
const wt_datagram = Webtransport.datagram;
const wt_draft = Webtransport.draft;
const wt_pool = Webtransport.pool;
const wt_session = Webtransport.session;
const wt_stream_header = Webtransport.stream_header;

// --------------------------------------------------------- //

/// The engine hooks an application-facing call lands on.
///
/// Note:
/// - The real implementation lives in the dispatch layer over a live connection. This one takes the
///   same calls over a worker pool, so what the tests below assert is what a caller sees through
///   `Session` and `Stream` rather than what a private shortcut arranged.
const Engine = struct {
    /// The worker pool the engine's stream slots come from.
    pool: *wt_pool.Pool,
    /// The per-stream send limit the handshake gave a stream this endpoint opens, as the peer
    /// advertised it (QUIC's initial_max_stream_data).
    stream_limit: u64 = std.math.maxInt(u64),
    /// The peer's largest DATAGRAM frame, null when it advertised none.
    datagram_frame_size: ?u64 = null,
    /// The next server-owned stream id.
    next_stream_id: u64 = 1,
    /// The hooks themselves, so a session or stream view carries a stable pointer to them.
    hooks: wt_session.Driver = undefined,
    /// What the engine was asked to do, so a test can tell the call arrived.
    streams_opened: usize = 0,
    datagrams_sent: usize = 0,
    datagrams_refused: usize = 0,
    sessions_closed: usize = 0,
    drains: usize = 0,
    resets: usize = 0,
    stops: usize = 0,

    fn install(self: *Engine) void {
        self.hooks = .{
            .context = self,
            .open_stream = Engine.openStream,
            .send_datagram = Engine.sendDatagram,
            .close_session = Engine.closeSession,
            .drain_session = Engine.drainSession,
            .stop_receiving = Engine.stopReceiving,
            .reset_stream = Engine.resetStream,
        };
    }

    fn engineOf(context: *anyopaque) *Engine {
        return @ptrCast(@alignCast(context));
    }

    /// Open a stream the way the dispatch layer does: take a pool slot, queue the header that tells the
    /// peer which session the stream belongs to, and count it against the session's own limit.
    fn openStream(context: *anyopaque, session: *wt_session.Session, kind: wt_stream_header.Kind) ?*wt_session.Stream {
        const engine = engineOf(context);
        const live = engine.pool.acquireStream() orelse return null;

        var header_buf: [16]u8 = undefined;
        const header_len = wt_stream_header.write(kind, &header_buf, session.id) orelse {
            engine.pool.releaseStream(live);

            return null;
        };

        live.* = .{
            .id = engine.next_stream_id,
            .session_id = session.id,
            .kind = kind,
            .initiator = .server,
            .buf = live.buf,
            .driver = &engine.hooks,
            .send = .{ .open = true, .limit = engine.stream_limit },
            .recv = .{ .limit = 1 << 20 },
        };
        live.openWithHeader(header_buf[0..header_len]);
        engine.next_stream_id += 4;

        session.attachStream(live);
        session.flow.onOpenedStream(kind);
        engine.streams_opened += 1;

        return live;
    }

    /// Queue one datagram, refusing what the peer's advertised frame limit cannot hold. A datagram is
    /// never queued for later, so a refusal is a drop.
    fn sendDatagram(context: *anyopaque, session: *wt_session.Session, payload: []const u8) bool {
        const engine = engineOf(context);
        if (!wt_datagram.payloadFits(engine.datagram_frame_size, session.id, payload.len)) {
            engine.datagrams_refused += 1;

            return false;
        }

        engine.datagrams_sent += 1;

        return true;
    }

    /// End the session for the peer: the close capsule and the CONNECT stream's FIN.
    fn closeSession(context: *anyopaque, session: *wt_session.Session) void {
        _ = session;
        engineOf(context).sessions_closed += 1;
    }

    /// Queue the drain capsule, which is advice and not an end.
    fn drainSession(context: *anyopaque, session: *wt_session.Session) void {
        _ = session;
        engineOf(context).drains += 1;
    }

    fn stopReceiving(context: *anyopaque, stream: *wt_session.Stream, code: u32) void {
        _ = .{ stream, code };
        engineOf(context).stops += 1;
    }

    /// Queue the reset of a stream's send half: RESET_STREAM_AT on a draft-16 session, plain
    /// RESET_STREAM on a draft-07 one.
    fn resetStream(context: *anyopaque, stream: *wt_session.Stream) void {
        _ = stream;
        engineOf(context).resets += 1;
    }
};

// --------------------------------------------------------- //

test "zix webtransport: the HTTP/3 server config carries the feature off and costs nothing while it is" {
    // A server that never mentions WebTransport must keep the values it had before the feature
    // existed: the config field defaults to off, so nothing is advertised and no pool is sized.
    const cfg = zix.Http3.ServerConfig{
        .io = undefined,
        .allocator = std.testing.allocator,
        .ip = "127.0.0.1",
        .port = 9064,
        .dispatch_model = .ASYNC,
    };

    try std.testing.expect(!cfg.webtransport.enabled);
    try std.testing.expect(Webtransport.capacityError(cfg.webtransport) == null);

    // The pool sizing the default asks for, which is what a worker allocates the moment the feature is
    // turned on with no tuning: the stream buffers are the whole per-worker cost.
    const sizing = Webtransport.poolConfig(cfg.webtransport);
    try std.testing.expectEqual(@as(usize, 16), sizing.sessions);
    try std.testing.expectEqual(@as(usize, 64), sizing.streams);
    try std.testing.expectEqual(@as(usize, 16 * 1024), sizing.stream_buffer_bytes);
    try std.testing.expectEqual(@as(usize, 8), sizing.orphans);
    try std.testing.expectEqual(@as(usize, 1024), sizing.orphan_bytes);
}

test "zix webtransport: a config past the connection ceilings is refused by the field that crossed them" {
    // Each ceiling is a compile-time limit the connection-side tables are sized from, so a config above
    // one has to be refused before the server starts, naming the field to lower.
    try std.testing.expectEqualStrings("max_sessions_per_connection", Webtransport.capacityError(.{
        .max_sessions_per_connection = Webtransport.connection_session_cap + 1,
    }).?);
    try std.testing.expectEqualStrings("pool_sessions", Webtransport.capacityError(.{
        .pool_sessions = wt_pool.maxima.sessions + 1,
    }).?);
    try std.testing.expectEqualStrings("pool_streams", Webtransport.capacityError(.{
        .pool_streams = wt_pool.maxima.streams + 1,
    }).?);
    try std.testing.expectEqualStrings("pool_orphan_streams", Webtransport.capacityError(.{
        .pool_orphan_streams = wt_pool.maxima.orphans + 1,
    }).?);

    // The pool the config asks for really holds every slot, or the limit would be a promise the pool
    // cannot keep. The pool is sized from pool_sessions, while max_sessions_per_connection caps one
    // connection, so the two ceilings are separate numbers.
    const at_ceiling = Webtransport.Config{
        .max_sessions_per_connection = Webtransport.connection_session_cap,
        .pool_sessions = wt_pool.maxima.sessions,
        .pool_streams = wt_pool.maxima.streams,
        .pool_orphan_streams = wt_pool.maxima.orphans,
        .stream_send_bytes = wt_pool.min_stream_buffer_bytes,
        .pool_orphan_bytes = wt_pool.min_orphan_buffer_bytes,
    };
    try std.testing.expect(Webtransport.capacityError(at_ceiling) == null);

    var pool = try wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(at_ceiling));
    defer pool.deinit(std.testing.allocator);

    var sessions: usize = 0;
    while (pool.acquireSession()) |_| sessions += 1;
    try std.testing.expectEqual(at_ceiling.pool_sessions, sessions);

    var streams: usize = 0;
    while (pool.acquireStream()) |_| streams += 1;
    try std.testing.expectEqual(at_ceiling.pool_streams, streams);
}

test "zix webtransport: the pool sizing a config asks for is the window a stream has to write into" {
    const config = Webtransport.Config{
        .enabled = true,
        .max_session_data = 4096,
        .max_streams_bidi = 2,
        .max_streams_uni = 2,
        .stream_send_bytes = 4096,
        .pool_sessions = 1,
        .pool_streams = 2,
        .pool_orphan_streams = 1,
        .pool_orphan_bytes = 128,
    };
    try std.testing.expect(Webtransport.capacityError(config) == null);

    var pool = try wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(config));
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    const stream = view.openBidi().?;

    // stream_send_bytes is the whole send buffer of a stream slot, and the header the engine queued is
    // already charged to it, so the application sees the buffer less that header.
    try std.testing.expectEqual(config.stream_send_bytes, stream.inner.buf.len);

    const header = wt_stream_header.headerLen(stream.kind(), view.id());
    try std.testing.expectEqual(@as(usize, 3), header);
    try std.testing.expectEqual(config.stream_send_bytes - header, stream.writable());

    // A write larger than the room is partially accepted, which is the back-pressure contract rather
    // than a dropped write.
    var block: [4096]u8 = @splat(0xaa);
    try std.testing.expectEqual(config.stream_send_bytes - header, stream.write(&block));
    try std.testing.expectEqual(@as(usize, 0), stream.writable());
    try std.testing.expectEqual(@as(usize, 0), stream.write(&block));
    try std.testing.expectEqual(@as(usize, 1), engine.streams_opened);
}

test "zix webtransport: the token a client sends is the dialect its session speaks" {
    // The two tokens this build speaks pick their revision; a token it does not know picks nothing, so
    // a client that sends one is answered rather than handed a session speaking the wrong draft.
    try std.testing.expectEqual(Webtransport.Dialect.draft16, wt_draft.dialectForToken("webtransport-h3").?);
    try std.testing.expectEqual(Webtransport.Dialect.draft07, wt_draft.dialectForToken("webtransport").?);
    try std.testing.expect(wt_draft.dialectForToken("websocket") == null);
    try std.testing.expect(wt_draft.dialectForToken("webtransport-h3,webtransport") == null);

    var pool = try wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(.{ .stream_send_bytes = 256 }));
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    // A draft-16 session is the one with session flow control, and what an application may open is the
    // allowance the peer's SETTINGS and capsules granted (5.3).
    const draft16 = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    draft16.inner.dialect = wt_draft.dialectForToken("webtransport-h3").?;
    draft16.inner.flow.declareLocal(1 << 20, 4, 4);
    draft16.inner.flow.declarePeer(1 << 20, 2, 2);

    try std.testing.expectEqual(Webtransport.Dialect.draft16, draft16.dialect());
    try std.testing.expectEqualStrings("webtransport-h3", wt_draft.tokenFor(draft16.dialect()));
    try std.testing.expectEqual(@as(u64, 2), draft16.streamsAvailable(.bidi));
    try std.testing.expectEqual(@as(u64, 2), draft16.streamsAvailable(.uni));

    // The deployed dialect declares no limits of its own, so a session that speaks it reports no
    // session-level allowance at all: its streams are bounded by QUIC alone.
    const draft07 = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    draft07.inner.dialect = wt_draft.dialectForToken("webtransport").?;
    draft07.inner.flow.declareLocal(1 << 20, 4, 4);

    try std.testing.expectEqual(Webtransport.Dialect.draft07, draft07.dialect());
    try std.testing.expectEqualStrings("webtransport", wt_draft.tokenFor(draft07.dialect()));
    try std.testing.expectEqual(std.math.maxInt(u64), draft07.streamsAvailable(.bidi));
}

test "zix webtransport: a stream is a write window, a FIN closes it, and only an acknowledgement finishes it" {
    // A stream slot's smallest send buffer: a smaller configuration is raised to this floor.
    const buffer_bytes: usize = wt_pool.min_stream_buffer_bytes;
    const config = Webtransport.Config{ .stream_send_bytes = buffer_bytes, .pool_sessions = 1, .pool_streams = 1 };

    var pool = try wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(config));
    defer pool.deinit(std.testing.allocator);

    // The handshake's allowance for a stream this endpoint opens, raised later with MAX_STREAM_DATA.
    var engine = Engine{ .pool = &pool, .stream_limit = 40 };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    const stream = view.openBidi().?;

    // The header is the first bytes of the buffer, so the window the application may fill is the
    // whole send buffer less that header.
    const header: usize = 3;
    const window_bytes = buffer_bytes - header;
    const peer_limit: usize = 40;

    var block: [buffer_bytes]u8 = @splat(0xaa);
    try std.testing.expectEqual(window_bytes, stream.write(&block));
    try std.testing.expectEqual(@as(usize, 0), stream.writable());

    // What the pump may send is bounded by the peer's per-stream limit, not by what the application
    // queued: the difference waits for the peer to raise the limit.
    try std.testing.expectEqual(peer_limit, stream.inner.sendable());
    stream.inner.onSent(peer_limit);

    // An acknowledgement frees exactly the prefix the peer confirmed, which is what lets a long stream
    // reuse one buffer instead of growing one.
    stream.inner.onAcked(0, peer_limit);
    try std.testing.expectEqual(peer_limit, stream.writable());

    // MAX_STREAM_DATA raises the limit, and the bytes it held back become sendable.
    stream.inner.onStreamLimit(1 << 20);
    try std.testing.expectEqual(buffer_bytes - peer_limit, stream.inner.sendable());

    // A FIN stops taking writes even with room left in the window: a byte queued after the FIN could
    // never be sent, so the write is refused instead of silently lost.
    try std.testing.expectEqual(@as(usize, 10), stream.write("0123456789"));
    try std.testing.expectEqual(peer_limit - 10, stream.writable());
    stream.finish();
    try std.testing.expectEqual(@as(usize, 0), stream.writable());
    try std.testing.expectEqual(@as(usize, 0), stream.write("late"));

    // The stream is not finished until the peer confirms the bytes it queued: that is what keeps a lost
    // packet from taking bytes with it, and what the pool waits for before recycling the slot.
    const queued_total = buffer_bytes + 10;
    try std.testing.expect(!stream.inner.sendFinished());
    stream.inner.onSent(stream.inner.sendable());
    try std.testing.expect(stream.inner.finPending());
    try std.testing.expect(!stream.inner.sendFinished());
    stream.inner.onAcked(peer_limit, queued_total - peer_limit);
    try std.testing.expect(stream.inner.sendFinished());
}

test "zix webtransport: a session enforces the data limit it advertised and raises it as the peer consumes it" {
    var pool = try wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(.{ .stream_send_bytes = 256 }));
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    const inner = view.inner;

    // Both endpoints declared a limit, which is what turns session flow control on (5.1).
    inner.flow.declareLocal(1000, 2, 2);
    inner.flow.declarePeer(1000, 2, 2);
    try std.testing.expect(inner.flow.enabled);

    // Stream Body bytes are charged as they arrive (5.4), up to the limit this endpoint advertised.
    try inner.onStreamData(600);
    try inner.onStreamData(400);

    // One byte past it is a session flow control error, which the engine turns into
    // WT_FLOW_CONTROL_ERROR (5.6.4).
    try std.testing.expectError(error.ZixFlowControlError, inner.onStreamData(1));

    // Once the window is consumed the endpoint owes the peer credit: the value due is the new limit,
    // and the peer may send up to it.
    try std.testing.expectEqual(@as(u64, 2000), inner.flow.dueMaxData(1000).?);
    try inner.onStreamData(1000);
    try std.testing.expectError(error.ZixFlowControlError, inner.onStreamData(1));

    // A WT_MAX_DATA capsule that does not raise the limit already applied is a flow control error too
    // (5.6.4): a peer cannot shrink what it granted.
    inner.flow.onMaxData(2000) catch unreachable;
    try std.testing.expectError(error.ZixFlowControlError, inner.flow.onMaxData(2000));
    try std.testing.expectError(error.ZixFlowControlError, inner.flow.onMaxData(1999));

    // A raise is what lets this endpoint send on the session at all, so the limit is the send budget.
    inner.flow.onMaxData(4000) catch unreachable;
    try std.testing.expect(inner.flow.canSendData(4000));
    try std.testing.expect(!inner.flow.canSendData(4001));
}

test "zix webtransport: a datagram is framed with its session's quarter stream id and bounded by the peer's limit" {
    // The peer advertised a 1200-byte DATAGRAM frame (RFC 9221 3). The payload that fits is what the
    // application may send, and one byte more is refused rather than split: a DATAGRAM frame cannot be
    // fragmented.
    const peer_frame_size: u64 = 1200;
    const session_id: u64 = 12; // quarter stream id 3 (RFC 9297 2.1)

    const fits = wt_datagram.maxPayloadBytes(peer_frame_size, session_id);
    try std.testing.expect(fits != 0);
    try std.testing.expect(wt_datagram.payloadFits(peer_frame_size, session_id, fits));
    try std.testing.expect(!wt_datagram.payloadFits(peer_frame_size, session_id, fits + 1));

    // A peer that advertised no frame size accepts no DATAGRAM frame at all, which is a client that
    // did not negotiate datagrams: nothing can be framed for it, whatever its length.
    try std.testing.expect(wt_datagram.maxPayloadBytes(null, session_id) == 0);
    try std.testing.expect(!wt_datagram.sendable(null, 0));

    // The bytes on the wire open with the quarter stream id, then the application payload unmodified.
    var buf: [2048]u8 = undefined;
    var payload: [2048]u8 = undefined;
    @memset(payload[0..fits], 0x5a);

    const len = wt_datagram.writeHttp3(&buf, session_id, payload[0..fits]).?;

    try std.testing.expectEqual(@as(u8, 3), buf[0]);
    try std.testing.expectEqual(@as(usize, 1 + fits), len);

    const parsed = try wt_datagram.parseHttp3(buf[0..len]);
    try std.testing.expectEqual(session_id, parsed.session_id);
    try std.testing.expectEqualSlices(u8, payload[0..fits], parsed.payload);

    // Framed as a QUIC DATAGRAM it still fits the limit the peer advertised, which is the arithmetic
    // the sender has to do before it queues anything.
    try std.testing.expect(wt_datagram.sendable(peer_frame_size, len));

    // Through the session handle: what the peer's limit allows goes out, and what it does not is
    // refused rather than queued for later.
    var pool = try wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(.{ .stream_send_bytes = 256 }));
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool, .datagram_frame_size = peer_frame_size };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    view.inner.id = session_id;

    try std.testing.expect(view.sendDatagram(payload[0..fits]));
    try std.testing.expect(!view.sendDatagram(payload[0 .. fits + 1]));
    try std.testing.expectEqual(@as(usize, 1), engine.datagrams_sent);
    try std.testing.expectEqual(@as(usize, 1), engine.datagrams_refused);
}
