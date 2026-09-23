//! Durable tasks over WebTransport: the browser submits a typed form event with an idempotency key over a
//! reliable stream, and the page is patched from committed state as the durable path advances.
//!
//! What:
//! - The page is served over HTTPS/1.1 on TCP and over HTTP/3, and the session goes to the same host and
//!   port over UDP: one origin, one port number, two transports.
//! - The view subscribes on a reliable bidirectional stream with the identity it claims. The server
//!   authorizes that principal for that tenant, answers with a revisioned snapshot read from the database,
//!   and from then on answers each `poll` with the revisioned patches the outbox has produced.
//! - The action itself is `examples/durable/tasks.zig`: validate + authorize, one transaction for the task
//!   and its job, a worker lease, one completion transaction, an outbox row, a dispatcher. Nothing in this
//!   file re-implements any of it; this file is the transport and the page.
//!
//! Note:
//! - **Reliable streams carry durable mutations, datagrams carry what may be lost.** The form event, the
//!   subscription, the polling and every patch ride the bidirectional stream; the datagram channel is used
//!   only for the "typing" hint the page sends, which is replaceable by construction and not worth a
//!   retransmit.
//! - **Patching is client-polled, on purpose.** A stream handle is only writable from the callback that
//!   delivered it, so a dispatcher thread cannot push into a session: it publishes into the feed, and the
//!   session drains the feed from its own callback. The page polls on a short interval, which also makes
//!   the durable path's latency observable instead of hidden.
//! - **Each thread owns a postgrez pool** (they are shared-nothing), so the handler builds its store on the
//!   thread it runs on, and the worker and dispatcher threads each build their own.

const std = @import("std");
const builtin = @import("builtin");
const zix = @import("zix");

const tasks = @import("durable_tasks");

// --------------------------------------------------------- //

/// The bind address, ports, certificate paths and database URL. Defaults keep the development loop exactly
/// as it is; each has an environment override because a deployment gives the process its interface and its
/// certificate from outside. Fly.io, for one, requires a UDP listener to bind the `fly-global-services`
/// address rather than loopback, and needs a certificate a browser already trusts.
var IP: []const u8 = "127.0.0.1";
var PAGE_IP: []const u8 = "127.0.0.1";
/// The session's port: HTTP/3 over QUIC, where the WebTransport binding lives.
var PORT: u16 = 9444;
/// The page's port: HTTPS/1.1 over TCP. It defaults to the session's port, because a session shares its
/// page's origin; a deployment that terminates both behind one external port overrides both.
var PAGE_PORT: u16 = 9444;
/// The page's port: HTTPS/1.1 over TCP. It is deliberately *not* the QUIC port. A browser that is told to
/// force QUIC for an origin sends every request to that origin over QUIC, so a page served there cannot
/// reload while the server is being rebuilt — and the development loop is exactly a rebuild followed by a
/// reload. Serving the page on TCP keeps reload (and the version poll that triggers it) independent of the
/// QUIC server's lifecycle, while the session still goes to the QUIC port.

/// Where the durable store lives. Every example in this repository points at a fixed local database; this
/// is the one it points at.
var DSN: []const u8 = "postgres://zix:zix@127.0.0.1:5432/zix_dev";
// Demo fixtures. For a real domain, point CERT / KEY at your certbot files.
var CERT: []const u8 = "examples/certs/ecdsa_p256_cert.pem";
var KEY: []const u8 = "examples/certs/ecdsa_p256_key.pem";

/// The path a session is accepted on.
const SESSION_PATH: []const u8 = "/tasks";

/// The page, embedded so the binary runs from any working directory.
const PAGE: []const u8 = @embedFile("webtransport_tasks.html");

/// The build marker a source edit bumps, and the placeholder it replaces in the page. The page renders it
/// and reports it back, so a change that never reached the browser fails the development loop's check
/// instead of being assumed to have arrived.
const dev_token: []const u8 = "d0";
const dev_placeholder = "__DEV_TOKEN__";

/// The page as this process serves it, and a version for it: an edit anywhere in the page, the token, or the
/// code that renders them changes the version, and the browser reloads when the version it polls changes.
var served_page: [PAGE.len + 64]u8 = undefined;
var served_page_len: usize = 0;
var served_version: u64 = 0;

/// Event bytes one poll may hand to a session at once, the longest line one event can be, and how much
/// undelivered patch text one view may hold before it is re-snapshotted instead.
const patches_per_poll = 32;
const line_bytes = 768;
const patch_bytes = 16 * 1024;

// --------------------------------------------------------- //

/// One subscribed view. Sessions are only writable from their own callbacks, so a slot holds no stream
/// handle: it holds the identity to authorize, and the feed cursor to resume from.
const View = struct {
    session: ?*zix.Webtransport.Session = null,
    tenant: [64]u8 = @splat(0),
    tenant_len: usize = 0,
    principal: [64]u8 = @splat(0),
    principal_len: usize = 0,
    cursor: u64 = 0,
    authorized: bool = false,
    /// Patches written for this view, for the log line that shows the consumer keeping up.
    sent: u64 = 0,
    /// Lines accepted by the engine's window so far but not yet fully handed to it. A stream write may be
    /// short (the congestion window, the peer's credit), and the remainder is the application's to keep:
    /// dropping it would lose a patch the outbox has already marked published.
    pending: [patch_bytes]u8 = @splat(0),
    pending_len: usize = 0,
    /// Set when the view fell too far behind for its buffer: the next drain re-reads the snapshot.
    needs_resync: bool = false,

    fn tenantSlice(self: *const View) []const u8 {
        return self.tenant[0..self.tenant_len];
    }
};

var views: [32]View = @splat(.{});
var feed: tasks.Feed = undefined;
var stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Log one line per state change the demo makes, so the terminal shows the same progression the page does.
fn log(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[tasks] " ++ fmt ++ "\n", args);
}

// --------------------------------------------------------- //
// Per-thread stores

const thread_store_allocator = std.heap.smp_allocator;
threadlocal var thread_store: ?*tasks.Store = null;
threadlocal var thread_store_arena: ?*std.heap.ArenaAllocator = null;

/// The calling thread's store. postgrez pools are shared-nothing, so a thread that runs callbacks (or the
/// worker, or the dispatcher) needs one of its own; the first call on a thread builds it.
fn store() *tasks.Store {
    if (thread_store) |existing| return existing;

    const arena = thread_store_allocator.create(std.heap.ArenaAllocator) catch @panic("store arena");
    arena.* = std.heap.ArenaAllocator.init(thread_store_allocator);

    const built = thread_store_allocator.create(tasks.Store) catch @panic("store");
    built.init(thread_store_allocator, current_io, DSN, 4) catch |err| {
        std.debug.print("[tasks] store init failed: {s}\n", .{@errorName(err)});
        @panic("durable store unavailable");
    };

    thread_store_arena = arena;
    thread_store = built;

    return built;
}

/// The io every thread shares: the process's own.
var current_io: std.Io = undefined;

// --------------------------------------------------------- //

fn page(req: *zix.Http1.Request, res: *zix.Http1.Response, ctx: *zix.Http1.Context) !void {
    if (std.mem.eql(u8, req.path(), "/favicon.ico")) {
        _ = ctx;

        return sendText(res, "");
    }

    const path = req.path();

    // The version the development loop polls: it changes exactly when the bytes this server serves change.
    if (std.mem.eql(u8, path, "/devloop/version")) {
        var body_buf: [24]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buf, "{x}\n", .{served_version}) catch return;

        return sendText(res, body);
    }

    // The browser's own report that it rendered the changed behaviour and finished a durable action.
    if (std.mem.startsWith(u8, path, "/verified/")) {
        std.debug.print("[devloop] verified {s}\n", .{path["/verified/".len..]});

        return sendText(res, "ok\n");
    }

    var head_buf: [192]u8 = undefined;
    var head = std.Io.Writer.fixed(&head_buf);
    // Alt-Svc is how a browser finds out that this session's origin speaks HTTP/3. The page is served over
    // TCP, and the session port is QUIC-only, so without this header a normal browser has no way to learn
    // that https://host:9444 is reachable over QUIC: it tries TCP, finds nothing, and the WebTransport
    // dial fails. Only a browser launched with --origin-to-force-quic-on could connect, which is not a demo
    // anybody can run.
    head.print("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nAlt-Svc: h3=\":{d}\"; ma=86400\r\n\r\n", .{ served_page_len, PORT }) catch return;

    try res.sendRaw(head.buffered());
    try res.sendRaw(served_page[0..served_page_len]);
}

fn sendText(res: *zix.Http1.Response, body: []const u8) !void {
    var head_buf: [128]u8 = undefined;
    var head = std.Io.Writer.fixed(&head_buf);
    head.print("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nAlt-Svc: h3=\":{d}\"; ma=86400\r\n\r\n", .{ body.len, PORT }) catch return;

    try res.sendRaw(head.buffered());
    try res.sendRaw(body);
}

/// Compose the page this process serves: the embedded file with the build token substituted in.
fn preparePage() void {
    const marker = std.mem.indexOf(u8, PAGE, dev_placeholder) orelse {
        @memcpy(served_page[0..PAGE.len], PAGE);
        served_page_len = PAGE.len;

        return;
    };

    @memcpy(served_page[0..marker], PAGE[0..marker]);
    @memcpy(served_page[marker..][0..dev_token.len], dev_token);
    const rest = PAGE[marker + dev_placeholder.len ..];
    @memcpy(served_page[marker + dev_token.len ..][0..rest.len], rest);

    served_page_len = PAGE.len - dev_placeholder.len + dev_token.len;
}

fn root(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.content_type = "text/html; charset=utf-8";
    res.send(served_page[0..served_page_len]);
}

/// A browser asks for the favicon on the page's own origin, which is this HTTP/3 listener: answering it
/// with no content keeps the console clean and, on a demo, is the whole requirement.
fn favicon(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.status = 204;
    res.send("");
}

/// The version the development loop polls, on the HTTP/3 listener: it changes exactly when the bytes this
/// server serves change.
fn devloopVersion(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    var body_buf: [24]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{x}\n", .{served_version}) catch return;

    res.content_type = "text/plain";
    res.send(body);
}

/// The browser's own report, on the HTTP/3 listener: it says it rendered the changed behaviour and
/// finished a durable action. A prefix route, so the mark the harness waits for travels in the path.
fn devloopVerified(req: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    const path = req.path;

    if (std.mem.startsWith(u8, path, "/verified/")) {
        std.debug.print("[devloop] verified {s}\n", .{path["/verified/".len..]});
    }

    res.content_type = "text/plain";
    res.send("ok\n");
}

// --------------------------------------------------------- //
// The session

fn onSession(session: *zix.Webtransport.Session) ?u16 {
    const request = session.sessionRequest();
    log("session {d} requested ({s} {s}, dialect {s})", .{ session.id(), request.protocol, request.path, @tagName(request.dialect) });

    if (!std.mem.eql(u8, request.path, SESSION_PATH)) return 404;

    // A session handle's address is what this file can key a view by, and the engine reuses that address
    // once a session closes: clear every slot that still names this session, so a new session can never
    // inherit the identity a previous one subscribed with.
    releaseViews(session);

    if (viewFor(session) == null) log("session {d}: no view slot free", .{session.id()});

    if (session.openUni()) |stream| {
        _ = stream.write("zix durable tasks: subscribe with an identity, then create tasks\n");
        stream.finish();
    }

    return null;
}

/// One chunk of application bytes on the view stream: a JSON command per line. Durable mutations arrive
/// here (reliable), and so do the polls that pull committed patches back.
fn onStream(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    const chunk = stream.read();
    if (chunk.len == 0) return;

    var rest = chunk;
    while (std.mem.indexOfScalar(u8, rest, '\n')) |end| {
        const line = std.mem.trim(u8, rest[0..end], " \r");
        rest = rest[end + 1 ..];
        if (line.len != 0) handleCommand(session, stream, line);
    }
}

fn handleCommand(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream, line: []const u8) void {
    var parsed = std.json.parseFromSlice(std.json.Value, thread_store_allocator, line, .{}) catch {
        writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"malformed command\"}");

        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return;

    const object = parsed.value.object;
    const kind = if (object.get("kind")) |value| value.string else "";

    if (std.mem.eql(u8, kind, "subscribe")) {
        subscribe(session, stream, object);

        return;
    }

    if (std.mem.eql(u8, kind, "create_task")) {
        createTask(session, stream, object);

        return;
    }

    if (std.mem.eql(u8, kind, "poll")) {
        drain(session, stream);

        return;
    }

    writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"unknown command\"}");
}

/// The subscription: authorize the identity for the tenant, then answer with the committed state. This is
/// also the resync path — a reconnect, a reload or a restarted server all land here and get the database.
fn subscribe(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream, object: std.json.ObjectMap) void {
    const principal = stringField(object, "principal");
    const tenant = stringField(object, "tenant");

    const view = viewFor(session) orelse {
        writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"too many views\"}");

        return;
    };

    const authorized = authorize(principal, tenant) catch false;
    view.principal_len = @min(principal.len, view.principal.len);
    @memcpy(view.principal[0..view.principal_len], principal[0..view.principal_len]);
    view.tenant_len = @min(tenant.len, view.tenant.len);
    @memcpy(view.tenant[0..view.tenant_len], tenant[0..view.tenant_len]);
    view.authorized = authorized;

    if (!authorized) {
        log("session {d}: {s} is not a member of {s}", .{ session.id(), principal, tenant });
        writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"principal is not a member of this tenant\"}");

        return;
    }

    sendSnapshot(session, stream, view, tenant);

    log("session {d}: {s} subscribed to {s}", .{ session.id(), principal, tenant });
}

/// Write the committed state as one revisioned snapshot line, and set the view's cursor to the feed's
/// newest: the snapshot is the state, so the view needs no patch for a revision it was just handed, and a
/// reconnect, a reload, a restarted server and a cursor that fell behind the feed all land here.
fn sendSnapshot(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream, view: *View, tenant: []const u8) void {
    const store_ = store();
    const snapshot = store_.snapshot(tenant) catch |err| {
        log("session {d}: snapshot failed ({s})", .{ session.id(), @errorName(err) });
        writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"snapshot unavailable\"}");

        return;
    };

    view.cursor = feed.latest(tenant);

    var buf: [line_bytes]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    writer.print("{{\"kind\":\"snapshot\",\"rev\":{d},\"worker\":\"{s}\",\"tasks\":[", .{ snapshot.rev, if (stop.load(.acquire)) "paused" else "running" }) catch return;

    for (snapshot.tasks, 0..) |task, index| {
        if (index != 0) writer.writeByte(',') catch return;
        taskJson(&writer, task) catch return;
    }

    _ = writer.writeAll("]}\n") catch return;
    _ = queueLine(view, stream, writer.buffered());
    log("session {d}: snapshot at rev {d} with {d} task(s)", .{ session.id(), snapshot.rev, snapshot.tasks.len });
}

/// The action. Everything durable happens in the store's transaction; this only turns the outcome into a
/// line for the page. The patch for the new task arrives through the outbox like every other patch.
fn createTask(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream, object: std.json.ObjectMap) void {
    const view = viewFor(session) orelse return;
    const principal = stringField(object, "principal");
    const tenant = stringField(object, "tenant");

    // A view may only act as the identity it subscribed with: the subscription is the authorization, and
    // an action that names another principal is refused here rather than at the database.
    if (!view.authorized or !std.mem.eql(u8, view.tenantSlice(), tenant) or !std.mem.eql(u8, view.principal[0..view.principal_len], principal)) {
        // Never silent: a refusal the operator cannot see is a refusal nobody can debug.
        log("session {d}: create refused, the view is subscribed as \"{s}\" for \"{s}\"", .{
            session.id(), view.principal[0..view.principal_len], view.tenantSlice(),
        });
        writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"subscribed identity only\"}");

        return;
    }

    const outcome = store().create(.{
        .principal = principal,
        .tenant = tenant,
        .idempotency_key = stringField(object, "idempotency_key"),
        .title = stringField(object, "title"),
    }) catch |err| {
        log("session {d}: create failed ({s})", .{ session.id(), @errorName(err) });
        writeLine(stream, "{\"kind\":\"rejected\",\"reason\":\"store unavailable\"}");

        return;
    };

    var buf: [256]u8 = undefined;
    const line = switch (outcome) {
        .rejected => |reason| std.fmt.bufPrint(&buf, "{{\"kind\":\"rejected\",\"reason\":\"{s}\"}}\n", .{reason}) catch return,
        .accepted => |accepted| std.fmt.bufPrint(&buf, "{{\"kind\":\"accepted\",\"task_id\":{d},\"rev\":{d},\"duplicate\":{}}}\n", .{
            accepted.task_id, accepted.rev, accepted.duplicate,
        }) catch return,
    };

    writeLine(stream, line);
    log("session {d}: create {s} under {s}", .{ session.id(), switch (outcome) {
        .rejected => "refused",
        .accepted => |accepted| if (accepted.duplicate) "was a replay" else "committed",
    }, stringField(object, "idempotency_key") });
}

/// The patch pump: everything the outbox has published for this view's tenant since its cursor, written as
/// one line per event. A cursor that fell further behind than the feed's ring is repaired with a fresh
/// snapshot instead of a hole.
fn drain(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    const view = viewFor(session) orelse return;
    if (!view.authorized) return;

    var buf: [patches_per_poll]tasks.Feed.Published = undefined;
    const drained = feed.drain(view.tenantSlice(), view.cursor, &buf);

    if (drained.gap) {
        log("session {d}: cursor fell behind the feed, re-snapshotting", .{session.id()});
        sendSnapshot(session, stream, view, view.tenantSlice());

        return;
    }

    for (drained.events) |event| {
        // The cursor advances only for a line the engine took whole: anything still buffered is resumed by
        // the next poll, and the event it belongs to stays unacknowledged until then.
        const queued = queueLine(view, stream, event.payload);
        if (!queued) break;

        view.cursor = event.seq;
        view.sent += 1;
    }

    if (view.needs_resync) {
        view.needs_resync = false;
        log("session {d}: view fell behind its buffer, re-snapshotting", .{session.id()});
        sendSnapshot(session, stream, view, view.tenantSlice());
    } else {
        flushView(view, stream);
    }
}

/// A datagram is used only for transient state. The page sends a typing hint; it is replaceable, so a lost
/// one costs nothing and nothing here retransmits.
fn onDatagram(session: *zix.Webtransport.Session, datagram: []const u8) void {
    _ = session;

    if (std.mem.startsWith(u8, datagram, "typing")) log("transient: {s}", .{datagram});
}

fn onStreamReset(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    log("session {d} stream {d} reset by the peer", .{ session.id(), stream.id() });
}

/// Release every slot this session owns. Both the close callback and the next session that reuses a
/// handle address reach this, which is what keeps a view from outliving its session.
fn releaseViews(session: *zix.Webtransport.Session) void {
    for (&views) |*view| {
        if (view.session == session) view.* = .{};
    }
}

fn onClose(session: *zix.Webtransport.Session) void {
    const info = session.closeInfo();

    releaseViews(session);

    log("session {d} closed: {s}", .{ session.id(), @tagName(info.reason) });
}

// --------------------------------------------------------- //
// Helpers

/// The view slot for this session, taken on first sight.
fn viewFor(session: *zix.Webtransport.Session) ?*View {
    for (&views) |*view| {
        if (view.session == session) return view;
    }

    for (&views) |*view| {
        if (view.session == null) {
            view.* = .{ .session = session };

            return view;
        }
    }

    return null;
}

fn authorize(principal: []const u8, tenant: []const u8) !bool {
    const conn = try store().pool.acquire();
    defer store().pool.release(conn);

    const Member = struct { ok: i64 };
    const found = try conn.queryRow(Member, "SELECT 1::int8 AS ok FROM principals WHERE id = $1 AND tenant_id = $2", .{ principal, tenant });

    return found != null;
}

fn stringField(object: std.json.ObjectMap, key: []const u8) []const u8 {
    const value = object.get(key) orelse return "";

    return switch (value) {
        .string => |text| text,
        else => "",
    };
}

fn taskJson(writer: *std.Io.Writer, task: tasks.Task) !void {
    try writer.print("{{\"id\":{d},\"title\":", .{task.id});
    try writeJsonString(writer, task.title);
    try writer.print(",\"state\":\"{s}\",\"attempts\":{d},\"result\":", .{ task.state, task.attempts });
    if (task.result) |text| try writeJsonString(writer, text) else try writer.writeAll("null");
    try writer.writeByte('}');
}

/// Escape one string into a JSON string literal: a title comes from the wire, so a quote in one must not be
/// able to close the payload's string on its way to the page.
fn writeJsonString(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f => try writer.print("\\u{x:0>4}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

/// Queue one terminated line for a view and hand the engine as much of it as it will take. Returns
/// whether the whole line reached the engine's buffer.
///
/// Note:
/// - A stream write is short when the congestion window or the peer's credit has no room, and only the
///   head of the line is taken: the rest stays here and the next poll resumes it, so a patch the outbox
///   marked published is never dropped. That is why the view, not the line, owns the buffer.
fn queueLine(view: *View, stream: *const zix.Webtransport.Stream, line: []const u8) bool {
    if (line.len == 0) return true;

    const needed = line.len + @intFromBool(!std.mem.endsWith(u8, line, "\n"));
    if (view.pending_len + needed > view.pending.len) {
        // The view is further behind than its buffer: mark it for a re-snapshot rather than dropping a
        // patch silently. The snapshot is the state, so nothing is lost either way.
        view.needs_resync = true;
        view.pending_len = 0;

        return false;
    }

    @memcpy(view.pending[view.pending_len..][0..line.len], line);
    view.pending_len += line.len;
    if (needed != line.len) {
        view.pending[view.pending_len] = '\n';
        view.pending_len += 1;
    }

    flushView(view, stream);

    return view.pending_len == 0;
}

/// Hand the buffered bytes to the engine, keeping whatever it did not take.
fn flushView(view: *View, stream: *const zix.Webtransport.Stream) void {
    if (view.pending_len == 0) return;

    const queued = stream.write(view.pending[0..view.pending_len]);
    if (queued == 0) return;

    const rest = view.pending_len - queued;
    std.mem.copyForwards(u8, view.pending[0..rest], view.pending[queued..view.pending_len]);
    view.pending_len = rest;
}

/// A line with no view behind it: a refusal before a subscription accepted, which is small enough to hand
/// over in one write and is not part of any view's patch stream.
fn writeLine(stream: *const zix.Webtransport.Stream, line: []const u8) void {
    if (line.len == 0) return;

    var framed: [line_bytes + 1]u8 = undefined;
    const body = @min(line.len, line_bytes);
    @memcpy(framed[0..body], line[0..body]);
    const terminated = !std.mem.endsWith(u8, line, "\n");
    if (terminated) framed[body] = '\n';

    const write = framed[0 .. body + @intFromBool(terminated)];
    const queued = stream.write(write);
    if (queued != write.len) log("stream {d}: {d} of {d} bytes queued (window full)", .{ stream.id(), queued, write.len });
}

// --------------------------------------------------------- //

pub fn main(process: std.process.Init) !void {
    current_io = process.io;

    // Environment overrides, read before anything uses these. `fly-global-services` is Fly.io's name for
    // the address a UDP listener must bind; ZIX_PAGE_IP stays separate because the TCP page listener binds
    // wherever the platform routes its TCP, which is not that address.
    if (process.environ_map.get("ZIX_SESSION_IP")) |value| IP = value;
    if (process.environ_map.get("ZIX_PAGE_IP")) |value| PAGE_IP = value;
    if (process.environ_map.get("ZIX_SESSION_PORT")) |value| PORT = std.fmt.parseInt(u16, value, 10) catch PORT;
    if (process.environ_map.get("ZIX_PAGE_PORT")) |value| PAGE_PORT = std.fmt.parseInt(u16, value, 10) catch PAGE_PORT;
    if (process.environ_map.get("ZIX_CERT")) |value| CERT = value;
    if (process.environ_map.get("ZIX_KEY")) |value| KEY = value;
    if (process.environ_map.get("DATABASE_URL")) |value| DSN = value;

    preparePage();
    served_version = std.hash.Fnv1a_64.hash(served_page[0..served_page_len]);

    // The demo owns its database rows: start from a clean slice so the page and the log agree on what is
    // there. A deployment would migrate instead, and never truncate.
    {
        const store_ = store();
        try store_.truncate();
        try store_.addPrincipal("alice@acme", "acme");
        try store_.addPrincipal("bob@globex", "globex");
        log("seeded principals alice@acme (acme) and bob@globex (globex)", .{});
    }

    feed = tasks.Feed.init(process.io);

    // Worker and dispatcher threads, each with its own store because a postgrez pool belongs to one thread.
    var worker_a = try std.Thread.spawn(.{}, runWorker, .{"w1"});
    worker_a.detach();
    var worker_b = try std.Thread.spawn(.{}, runWorker, .{"w2"});
    worker_b.detach();
    var dispatcher_thread = try std.Thread.spawn(.{}, runDispatcher, .{});
    dispatcher_thread.detach();

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
        .ip = PAGE_IP,
        .port = PAGE_PORT,
        .tls = &page_tls,
        .dispatch_model = if (builtin.os.tag == .linux) .URING else .ASYNC,
        .workers = 1,
    });
    defer page_server.deinit();

    // Every route the page uses must exist on both listeners. Once a browser learns this origin speaks
    // HTTP/3 it fetches the page - and everything the page fetches - over QUIC, so an endpoint that lives
    // only on the TCP side answers 404 and the development loop never reports. That is exactly what
    // happened when the page started being served over HTTP/3.
    const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
        .{ .path = "/", .handler = root },
        .{ .path = "/favicon.ico", .handler = favicon },
        .{ .path = "/devloop/version", .handler = devloopVersion },
        .{ .path = "/verified", .handler = devloopVerified, .kind = .PREFIX },
    });

    var tasks_server = zix.Http3.Server.init(Routes.dispatch, .{
        .io = process.io,
        .allocator = std.heap.smp_allocator,
        .ip = IP,
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
    defer tasks_server.deinit();

    const PageServer = @TypeOf(page_server);
    var page_thread = try std.Thread.spawn(.{}, struct {
        fn serve(server: *PageServer) void {
            server.run() catch |err| log("page server stopped: {s}", .{@errorName(err)});
        }
    }.serve, .{&page_server});
    page_thread.detach();

    log("page https://{s}:{d}/ · session https://{s}:{d}{s} (same origin: TCP serves the page, UDP serves HTTP/3)", .{ IP, PORT, IP, PORT, SESSION_PATH });

    try tasks_server.run();
}

fn runWorker(id: []const u8) void {
    var worker = tasks.Worker{ .store = store(), .id = id, .work_ms = 40 };
    worker.loop(&stop, 20);
}

fn runDispatcher() void {
    var dispatcher = tasks.Dispatcher{ .store = store(), .feed = &feed };
    dispatcher.loop(&stop, 20);
}
