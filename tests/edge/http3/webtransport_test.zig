//! Edge tests: the boundaries of zix.Webtransport at its public surface, and the hostile input a peer
//! is free to send. What is pinned here is what a caller can see going wrong: a capsule stream that
//! declares more than the reader holds, an application error at the ends of its range, a send window
//! whose bookkeeping is full, a pool at its last slot, and a session that has already ended.

const std = @import("std");
const zix = @import("zix");

const Webtransport = zix.Webtransport;
const wt_capsule = Webtransport.capsule;
const wt_draft = Webtransport.draft;
const wt_pool = Webtransport.pool;
const wt_session = Webtransport.session;
const wt_stream_header = Webtransport.stream_header;
const varint = zix.Http3.varint;

// --------------------------------------------------------- //

/// What a reader delivered, in arrival order.
///
/// Note:
/// - A delivered value borrows the reader's own accumulation buffer, so these tests read it in the
///   step that delivered it, before the next capsule can overwrite it.
const Collector = struct {
    types: [4]u64 = @splat(0),
    lengths: [4]usize = @splat(0),
    values: [4][]const u8 = @splat(""),
    count: usize = 0,

    fn visit(self: *Collector, capsule: wt_capsule.Capsule) bool {
        if (self.count < self.types.len) {
            self.types[self.count] = capsule.type;
            self.lengths[self.count] = capsule.value.len;
            self.values[self.count] = capsule.value;
            self.count += 1;
        }

        return true;
    }
};

/// The engine hooks an application-facing call lands on: the dispatch layer's contract, over a worker
/// pool instead of a connection.
const Engine = struct {
    pool: *wt_pool.Pool,
    /// The per-stream send limit the handshake gave a stream this endpoint opens.
    stream_limit: u64 = std.math.maxInt(u64),
    /// The next server-owned stream id.
    next_stream_id: u64 = 1,
    /// The hooks themselves, so a session or stream view carries a stable pointer to them.
    hooks: wt_session.Driver = undefined,
    /// What the engine was asked to do, so a test can tell the call arrived, and how often.
    streams_opened: usize = 0,
    datagrams_sent: usize = 0,
    sessions_closed: usize = 0,
    resets: usize = 0,

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

    fn sendDatagram(context: *anyopaque, session: *wt_session.Session, payload: []const u8) bool {
        _ = session;
        _ = payload;
        engineOf(context).datagrams_sent += 1;

        return true;
    }

    fn closeSession(context: *anyopaque, session: *wt_session.Session) void {
        _ = session;
        engineOf(context).sessions_closed += 1;
    }

    fn drainSession(context: *anyopaque, session: *wt_session.Session) void {
        _ = .{ context, session };
    }

    fn stopReceiving(context: *anyopaque, stream: *wt_session.Stream, code: u32) void {
        _ = .{ context, stream, code };
    }

    fn resetStream(context: *anyopaque, stream: *wt_session.Stream) void {
        _ = stream;
        engineOf(context).resets += 1;
    }
};

/// A pool sized the way a worker is when the feature is on with a small tuning.
fn testPool() !wt_pool.Pool {
    return wt_pool.Pool.init(std.testing.allocator, Webtransport.poolConfig(.{
        .stream_send_bytes = wt_pool.min_stream_buffer_bytes,
        .pool_streams = 8,
    }));
}

// --------------------------------------------------------- //

test "zix webtransport: the capsule reader holds a value up to its limit and skips one past it" {
    // The reader accumulates a known capsule in its own fixed buffer, so a peer can make it hold only
    // so much. The largest capsule this binding defines is WT_CLOSE_SESSION at 4 + 1024, which is
    // exactly the limit: one byte more has to be skipped in place, and the capsule behind it still has
    // to arrive or a peer could stall the CONNECT stream by announcing a length it never sends.
    const limit = wt_capsule.max_known_value;

    var held: [limit + 16]u8 = undefined;
    var hp: usize = 0;
    hp += varint.write(held[hp..], wt_draft.capsule.close_session);
    hp += varint.write(held[hp..], limit);
    std.mem.writeInt(u32, held[hp..][0..4], 7, .big);
    @memset(held[hp + 4 ..][0 .. limit - 4], 'm');
    hp += limit;

    var reader = wt_capsule.Reader{};
    var collector = Collector{};
    const outcome = reader.feed(held[0..hp], Collector.visit, &collector);

    try std.testing.expectEqual(@as(u32, 1), outcome.delivered);
    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(wt_draft.capsule.close_session, collector.types[0]);
    try std.testing.expectEqual(limit, collector.lengths[0]);
    try std.testing.expectEqual(@as(u32, 7), (try wt_capsule.parseCloseSession(collector.values[0])).code);

    // One byte past the limit, with its whole declared value on the wire and a drain capsule behind it.
    var over: [limit + 32]u8 = undefined;
    var op: usize = 0;
    op += varint.write(over[op..], wt_draft.capsule.close_session);
    op += varint.write(over[op..], limit + 1);
    @memset(over[op..][0 .. limit + 1], 0x7a);
    op += limit + 1;
    op += wt_capsule.writeDrainSession(over[op..]).?;

    var after = Collector{};
    const skipped = reader.feed(over[0..op], Collector.visit, &after);

    try std.testing.expectEqual(@as(u32, 1), skipped.skipped);
    try std.testing.expectEqual(@as(u32, 1), skipped.delivered);
    try std.testing.expectEqual(@as(usize, 1), after.count);
    try std.testing.expectEqual(wt_draft.capsule.drain_session, after.types[0]);

    // Nothing of the oversized value was held, and the skip ended exactly at the capsule boundary.
    try std.testing.expectEqual(@as(usize, 0), reader.value_len);
    try std.testing.expectEqual(@as(usize, 0), reader.value_need);
    try std.testing.expectEqual(@as(u64, 0), reader.discard);
}

test "zix webtransport: a capsule value one byte short of its own length is not delivered" {
    // The declared length is what the reader trusts, so a capsule that is one byte short is still
    // arriving. Delivering it early would hand the application a truncated message as if the peer had
    // sent exactly that.
    var buf: [64]u8 = undefined;
    const len = wt_capsule.writeCloseSession(&buf, 9, "gone").?;

    var reader = wt_capsule.Reader{};
    var collector = Collector{};

    const partial = reader.feed(buf[0 .. len - 1], Collector.visit, &collector);
    try std.testing.expectEqual(@as(u32, 0), partial.delivered);
    try std.testing.expectEqual(@as(usize, 0), collector.count);
    try std.testing.expectEqual(@as(usize, 1), reader.value_need);

    const rest = reader.feed(buf[len - 1 .. len], Collector.visit, &collector);
    try std.testing.expectEqual(@as(u32, 1), rest.delivered);
    try std.testing.expectEqual(@as(usize, 1), collector.count);

    const close = try wt_capsule.parseCloseSession(collector.values[0]);
    try std.testing.expectEqual(@as(u32, 9), close.code);
    try std.testing.expectEqualStrings("gone", close.message);
}

test "zix webtransport: the application error mapping spans the 32-bit ends without landing on a grease code" {
    // 4.4: the application error space is the whole unsigned 32-bit range, carried inside
    // WT_APPLICATION_ERROR. The ends are what pin the range, and an encoded code a receiver has to read
    // as H3_NO_ERROR would lose the peer's error entirely.
    try std.testing.expectEqual(wt_draft.app_error_first, wt_draft.encodeAppError(0));
    try std.testing.expectEqual(wt_draft.app_error_last, wt_draft.encodeAppError(0xffffffff));
    try std.testing.expectEqual(@as(u32, 0), wt_draft.decodeAppError(wt_draft.app_error_first).?);
    try std.testing.expectEqual(@as(u32, 0xffffffff), wt_draft.decodeAppError(wt_draft.app_error_last).?);

    // The ends and the first few codes either side of the gap the mapping skips: every encoded code is
    // outside the reserved range, and every one decodes back to the code it came from.
    const probes = [_]u32{ 0, 1, 2, 29, 30, 31, 0x7fffffff, 0xfffffffe, 0xffffffff };
    for (probes) |code| {
        const encoded = wt_draft.encodeAppError(code);
        try std.testing.expect(!wt_draft.isReservedErrorCode(encoded));
        try std.testing.expectEqual(code, wt_draft.decodeAppError(encoded).?);
    }

    // Outside the range there is no application error to report, however the code got there.
    try std.testing.expect(wt_draft.decodeAppError(0) == null);
    try std.testing.expect(wt_draft.decodeAppError(wt_draft.app_error_first - 1) == null);
    try std.testing.expect(wt_draft.decodeAppError(wt_draft.app_error_last + 1) == null);
    try std.testing.expect(wt_draft.decodeAppError(std.math.maxInt(u64)) == null);

    // Including the HTTP/3 codes themselves, which are what a connection-level failure arrives as.
    try std.testing.expect(wt_draft.decodeAppError(0x0100) == null);
    try std.testing.expect(wt_draft.decodeAppError(wt_draft.error_code.wt_session_gone) == null);
}

test "zix webtransport: a peer reset reports an application code only when it carried one" {
    var pool = try testPool();
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    const stream = view.openBidi().?;

    // A reset carrying an application error: the application reads the code the peer chose.
    stream.inner.onResetReceived(wt_draft.encodeAppError(42), 0);
    try std.testing.expectEqual(@as(u32, 42), stream.resetCode().?);

    // A code outside the range is still a reset, it just carries no application code: a flow control
    // code, a grease codepoint, and a code below the range all read as null.
    stream.inner.onResetReceived(wt_draft.error_code.wt_flow_control_error, 0);
    try std.testing.expect(stream.resetCode() == null);

    var reserved: u64 = wt_draft.app_error_first;
    while (!wt_draft.isReservedErrorCode(reserved)) : (reserved += 1) {}
    stream.inner.onResetReceived(reserved, 0);
    try std.testing.expect(stream.resetCode() == null);

    stream.inner.onResetReceived(wt_draft.app_error_first - 1, 0);
    try std.testing.expect(stream.resetCode() == null);

    // Either way the peer ended the stream, so nothing more arrives on it: a reset without a code is
    // still a reset.
    try std.testing.expect(stream.finished());
}

test "zix webtransport: a stream whose sent-range list is full is offered no more bytes" {
    // Every range the pump hands the wire stays on the stream's list until an acknowledgement covers
    // it, so the stream can prove what the peer has. The list is bounded, and a full list stops the
    // pump rather than letting it send a byte it could no longer account for.
    var pool = try testPool();
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
    const stream = view.openBidi().?;

    var payload: [200]u8 = @splat('z');
    try std.testing.expectEqual(payload.len, stream.write(&payload));
    try std.testing.expectEqual(@as(u64, 3 + payload.len), stream.inner.send.queued);

    // The peer keeps reporting the same range lost and the engine keeps resending it: each resend is
    // another range until an acknowledgement covers it.
    const chunk: u64 = 16;
    var round: usize = 0;
    while (round < wt_session.max_outstanding_ranges) : (round += 1) {
        stream.inner.onLost(0);
        stream.inner.onSent(chunk);
    }

    try std.testing.expectEqual(@as(u8, wt_session.max_outstanding_ranges), stream.inner.send.outstanding_len);
    try std.testing.expectEqual(@as(usize, 0), stream.inner.sendable());
    // The bytes are still queued and unsent, which is what makes the stop a stop and not an empty
    // window: nothing was dropped, the stream just will not hand over a range it cannot track.
    try std.testing.expect(stream.inner.send.sent < stream.inner.send.acked + stream.inner.send.queued);

    // An acknowledgement that covers the range drains the list and the stream is offered its bytes
    // again, so a stream stalled by its own bookkeeping resumes.
    stream.inner.onAcked(0, chunk);
    try std.testing.expectEqual(@as(usize, 0), stream.inner.send.outstanding_len);
    try std.testing.expect(stream.inner.sendable() != 0);
}

test "zix webtransport: a reset covers at least the header of the kind it resets" {
    // 4.4: a reliable reset delivers the first bytes of the stream and discards the rest, so it has to
    // cover the header. With the header gone the peer could not tell which session the stream belonged
    // to, and the session id is widest at the largest legal one.
    var pool = try testPool();
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    const session_ids = [_]u64{ 0, 4, 16384, wt_stream_header.max_session_id };
    const kinds = [_]wt_stream_header.Kind{ .bidi, .uni };

    for (session_ids) |session_id| {
        const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };
        view.inner.id = session_id;

        for (kinds) |kind| {
            const stream = switch (kind) {
                .bidi => view.openBidi().?,
                .uni => view.openUni().?,
            };

            // The application queued bytes and then gave up on the stream.
            _ = stream.write("payload");
            stream.reset(7);

            const reset = stream.inner.send.reset.?;
            try std.testing.expectEqual(@as(u32, 7), reset.code);
            try std.testing.expect(reset.reliable_size >= wt_stream_header.headerLen(kind, session_id));
            try std.testing.expect(stream.inner.totalBytes() >= reset.reliable_size);
            try std.testing.expectEqual(@as(usize, 1), engine.resets);

            _ = view.inner.detachStream(stream.inner);
            pool.releaseStream(stream.inner);
            engine.resets = 0;
        }

        pool.releaseSession(view.inner);
    }
}

test "zix webtransport: the pool refuses past its last slot and the pre-session table holds nothing it refuses" {
    // A one-slot pool is the smallest a deployment can configure without turning the feature off: the
    // second session is refused rather than served out of the first one's slot.
    var pool = try wt_pool.Pool.init(std.testing.allocator, .{
        .sessions = 1,
        .streams = 1,
        .orphans = 1,
        .orphan_bytes = wt_pool.min_orphan_buffer_bytes,
    });
    defer pool.deinit(std.testing.allocator);

    const session = pool.acquireSession().?;
    try std.testing.expect(pool.acquireSession() == null);
    const stream = pool.acquireStream().?;
    try std.testing.expect(pool.acquireStream() == null);

    // Recycling hands the same slot back cleared, so a later session cannot read the old one's state.
    session.id = 12;
    session.state = .draining;
    pool.releaseSession(session);

    const reused = pool.acquireSession().?;
    try std.testing.expect(reused == session);
    try std.testing.expectEqual(@as(u64, 0), reused.id);
    try std.testing.expectEqual(wt_session.State.open, reused.state);

    pool.releaseStream(stream);
    try std.testing.expect(pool.acquireStream() == stream);

    // The pre-session table takes a stream that fits its buffer and refuses one that does not, holding
    // nothing of it: half a stream would be worse than none, because the peer would see its bytes
    // accepted and then find them missing when the session is established.
    var too_big: [wt_pool.min_orphan_buffer_bytes + 1]u8 = @splat(0x5a);
    try std.testing.expect(pool.bufferOrphan(0, 4, .bidi, &too_big, false) == null);
    try std.testing.expect(pool.orphanFor(4) == null);
    try std.testing.expectEqual(@as(usize, 0), pool.dropOrphans(0));

    var fits: [wt_pool.min_orphan_buffer_bytes]u8 = @splat(0x5a);
    const held = pool.bufferOrphan(0, 4, .bidi, &fits, false).?;
    try std.testing.expectEqual(wt_pool.min_orphan_buffer_bytes, held.len);

    // A later write that does not fit the rest of the slot is refused whole: what was buffered stays
    // exactly as it was, so the replay after the session is established is never a torn one.
    try std.testing.expect(pool.bufferOrphan(0, 4, .bidi, "x", false) == null);
    try std.testing.expectEqual(wt_pool.min_orphan_buffer_bytes, held.len);
    try std.testing.expectEqual(@as(usize, 1), pool.dropOrphans(0));
}

test "zix webtransport: a closed session refuses streams and datagrams and clips its close message" {
    var pool = try testPool();
    defer pool.deinit(std.testing.allocator);

    var engine = Engine{ .pool = &pool };
    engine.install();

    const view = Webtransport.Session{ .inner = pool.acquireSession().?, .driver = &engine.hooks };

    // A message longer than a WT_CLOSE_SESSION can carry is what an application may pass: the session
    // keeps what the capsule holds and drops the rest, so the peer reads a message the capsule's own
    // limit allows.
    var message: [wt_draft.max_close_message + 512]u8 = @splat('x');
    view.close(7, &message);

    try std.testing.expectEqual(Webtransport.State.closed, view.state());
    try std.testing.expect(!view.isOpen());
    try std.testing.expectEqual(@as(usize, 1), engine.sessions_closed);

    const info = view.closeInfo();
    try std.testing.expectEqual(@as(u32, 7), info.code);
    try std.testing.expectEqual(wt_draft.max_close_message, info.message.len);
    try std.testing.expectEqual(Webtransport.CloseReason.local_close, info.reason);

    // Nothing new is routed to it: a closed session takes no streams and drops datagrams instead of
    // handing either to the engine, which is what keeps a session's slot from outliving its session.
    try std.testing.expect(view.openBidi() == null);
    try std.testing.expect(view.openUni() == null);
    try std.testing.expect(!view.sendDatagram("dropped"));
    try std.testing.expectEqual(@as(usize, 0), engine.streams_opened);
    try std.testing.expectEqual(@as(usize, 0), engine.datagrams_sent);

    // A second close is a no-op rather than a second capsule on the wire.
    view.close(8, "again");
    try std.testing.expectEqual(@as(usize, 1), engine.sessions_closed);
    try std.testing.expectEqual(@as(u32, 7), view.closeInfo().code);
    try std.testing.expectEqual(wt_draft.max_close_message, view.closeInfo().message.len);
}
