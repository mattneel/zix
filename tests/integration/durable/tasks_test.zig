//! The CreateTask slice's acceptance suite: the seven scenarios that define the milestone, run against a
//! real PostgreSQL.
//!
//! What:
//! - Invalid or unauthorized submission, transaction failure, duplicate submission, worker crash, crash
//!   after commit before publication, duplicate event delivery, and view reconstruction after a restart.
//!
//! Note:
//! - This suite needs a live database, which is why it is `zig build test-durable` and not part of
//!   `test-all`: the point of these scenarios is the SQL the slice runs, and a fake server that speaks the
//!   wire protocol without executing SQL cannot fail them the way Postgres can (a unique index, a
//!   `SKIP LOCKED` lease, a rollback).
//! - The DSN comes from `ZIX_TASKS_DSN` (or `DATABASE_URL`), defaulting to the local development database
//!   `postgres://zix:zix@127.0.0.1:5432/zix_dev`. Each scenario uses its own tenant and principal, so the
//!   scenarios do not see each other's rows and a rerun starts from its own clean slate.

const std = @import("std");
const testing = std.testing;

const zix = @import("zix");
const tasks = @import("durable_tasks");
const options = @import("durable_options");

const postgrez = zix.Driver.postgrez;

// --------------------------------------------------------- //

const CountRow = struct { n: i64 };

/// The DSN the suite runs against, and the io every store in it uses.
const Harness = struct {
    threaded: std.Io.Threaded,
    dsn: []const u8,
    allocator: std.mem.Allocator,

    fn init() Harness {
        return .{
            .threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{}),
            .dsn = options.dsn,
            .allocator = std.heap.smp_allocator,
        };
    }

    fn deinit(self: *Harness) void {
        self.threaded.deinit();
    }

    fn io(self: *Harness) std.Io {
        return self.threaded.io();
    }

    /// A store for this thread (postgrez pools are shared-nothing), with the schema applied.
    fn openStore(self: *Harness) !tasks.Store {
        var opened: tasks.Store = undefined;
        try opened.init(self.allocator, self.io(), self.dsn, 3);

        return opened;
    }

    /// Seed `principal` as a member of `tenant`.
    fn principal(self: *Harness, opened: *tasks.Store, for_tenant: []const u8, name: []const u8) !void {
        _ = self;
        try opened.addPrincipal(name, for_tenant);
    }

    /// A second, read-only connection so a scenario can count rows behind the store's back.
    fn conn(self: *Harness) !*postgrez.Conn {
        return postgrez.Conn.connect(self.allocator, self.io(), try postgrez.parseUrl(self.dsn));
    }

    /// A tenant of this scenario's own: the name carries the backend pid of the connection doing the
    /// asking, so a rerun of the suite starts clean without truncating anyone else's rows.
    fn tenant(self: *Harness, out: []u8, name: []const u8) ![]const u8 {
        const probe = try self.conn();
        defer probe.deinit();

        return try std.fmt.bufPrint(out, "{s}-{d}", .{ name, probe.backend_pid });
    }
};

fn countOf(conn: *postgrez.Conn, sql: []const u8, tenant: []const u8) !i64 {
    return (try conn.queryRow(CountRow, sql, .{tenant})).?.n;
}

const tasks_in = "SELECT count(*)::int8 AS n FROM tasks WHERE tenant_id = $1";
const jobs_in = "SELECT count(*)::int8 AS n FROM jobs j JOIN tasks t ON t.id = j.task_id WHERE t.tenant_id = $1";
const outbox_in = "SELECT count(*)::int8 AS n FROM outbox WHERE tenant_id = $1";
const unpublished_in = "SELECT count(*)::int8 AS n FROM outbox WHERE tenant_id = $1 AND NOT published";

// --------------------------------------------------------- //

test "durable tasks: an invalid or unauthorized submission persists nothing" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf: [32]u8 = undefined;
    const t1 = try harness.tenant(&tenant_buf, "t1");

    var store = try harness.openStore();
    defer store.deinit();

    // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
    // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
    try store.truncate();

    try harness.principal(&store, t1, "alice");

    // Unauthorized: this principal is a member of another tenant.
    const unauthorized = try store.create(.{ .principal = "alice", .tenant = "someone-else", .idempotency_key = "k1", .title = "nope" });
    try testing.expectEqualStrings("principal is not a member of this tenant", unauthorized.rejected);

    // Invalid: an empty title, and an oversized key.
    const empty = try store.create(.{ .principal = "alice", .tenant = t1, .idempotency_key = "k2", .title = "" });
    try testing.expectEqualStrings("title must be 1..120 bytes", empty.rejected);

    var long_key: [tasks.max_key + 1]u8 = @splat('k');
    const oversized = try store.create(.{ .principal = "alice", .tenant = t1, .idempotency_key = &long_key, .title = "key too long" });
    try testing.expectEqualStrings("idempotency key must be 1..64 bytes", oversized.rejected);

    // Nothing at all was written: no task, no job, and no outbox row either, because the rejection happens
    // before the transaction's first insert.
    const conn = try harness.conn();
    defer conn.deinit();

    try testing.expectEqual(@as(i64, 0), try countOf(conn, tasks_in, t1));
    try testing.expectEqual(@as(i64, 0), try countOf(conn, jobs_in, t1));
    try testing.expectEqual(@as(i64, 0), try countOf(conn, outbox_in, t1));
}

test "durable tasks: a transaction that never commits persists neither the task nor the job" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf2: [32]u8 = undefined;
    const t2 = try harness.tenant(&tenant_buf2, "t2");

    var store = try harness.openStore();
    defer store.deinit();

    // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
    // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
    try store.truncate();

    try harness.principal(&store, t2, "alice");

    const conn = try harness.conn();
    defer conn.deinit();

    // The inserts all succeed inside the transaction, and then the transaction dies the way a crash mid-tx
    // dies: it never commits. Both inserts and the outbox row have to disappear together.
    {
        const pool_conn = try store.pool.acquire();
        defer store.pool.release(pool_conn);

        var tx = try pool_conn.begin();
        defer tx.rollback();

        const outcome = try tasks.Store.createIn(&tx, .{ .principal = "alice", .tenant = t2, .idempotency_key = "k1", .title = "rolled back" });
        try testing.expect(!outcome.accepted.duplicate);
        try testing.expect(outcome.accepted.task_id > 0);
    }

    try testing.expectEqual(@as(i64, 0), try countOf(conn, tasks_in, t2));
    try testing.expectEqual(@as(i64, 0), try countOf(conn, jobs_in, t2));
    try testing.expectEqual(@as(i64, 0), try countOf(conn, outbox_in, t2));
}

test "durable tasks: a duplicate submission yields one logical task and one job" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf3: [32]u8 = undefined;
    const t3 = try harness.tenant(&tenant_buf3, "t3");

    var store = try harness.openStore();
    defer store.deinit();

    // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
    // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
    try store.truncate();

    try harness.principal(&store, t3, "alice");

    const first = (try store.create(.{ .principal = "alice", .tenant = t3, .idempotency_key = "same-key", .title = "first" })).accepted;
    try testing.expect(!first.duplicate);

    // The retry, and a retry whose body differs: both are the same logical submission, so the idempotency
    // key wins over the payload and nothing new is inserted.
    const second = (try store.create(.{ .principal = "alice", .tenant = t3, .idempotency_key = "same-key", .title = "first" })).accepted;
    const third = (try store.create(.{ .principal = "alice", .tenant = t3, .idempotency_key = "same-key", .title = "a different title" })).accepted;

    try testing.expect(second.duplicate and third.duplicate);
    try testing.expectEqual(first.task_id, second.task_id);
    try testing.expectEqual(first.task_id, third.task_id);
    try testing.expectEqual(first.rev, second.rev);

    const conn = try harness.conn();
    defer conn.deinit();

    try testing.expectEqual(@as(i64, 1), try countOf(conn, tasks_in, t3));
    try testing.expectEqual(@as(i64, 1), try countOf(conn, jobs_in, t3));
    try testing.expectEqual(@as(i64, 1), try countOf(conn, outbox_in, t3));

    const snapshot = try store.snapshot(t3);
    try testing.expectEqual(@as(usize, 1), snapshot.tasks.len);
    try testing.expectEqualStrings("first", snapshot.tasks[0].title);
}

test "durable tasks: a crashed worker's job is recovered after its lease expires" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf4: [32]u8 = undefined;
    const t4 = try harness.tenant(&tenant_buf4, "t4");

    var store = try harness.openStore();
    defer store.deinit();

    // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
    // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
    try store.truncate();

    try harness.principal(&store, t4, "alice");
    _ = try store.create(.{ .principal = "alice", .tenant = t4, .idempotency_key = "k1", .title = "long job" });

    // Worker A leases the job with a short lease and then dies: no completion, no release.
    const crashed = (try store.lease(200)).?;
    try testing.expectEqual(@as(i64, 1), crashed.attempts);

    const running = try store.snapshot(t4);
    try testing.expectEqualStrings("running", running.tasks[0].state);
    try testing.expectEqual(@as(i64, 1), running.tasks[0].attempts);

    // While the lease is held, nobody else can take the job.
    try testing.expect((try store.lease(200)) == null);

    // The lease expires and the job comes back, with the attempt counted. The expiry is judged by the
    // database's clock, so this polls for it rather than assuming a sleep on this side outlasts it.
    var recovered: ?tasks.Lease = null;
    var waited_ms: usize = 0;
    while (recovered == null and waited_ms < 5_000) : (waited_ms += 100) {
        harness.io().sleep(.fromMilliseconds(100), .awake) catch {};
        recovered = try store.lease(5_000);
    }

    try testing.expect(recovered != null);
    try testing.expectEqual(crashed.job_id, recovered.?.job_id);
    try testing.expectEqual(crashed.task_id, recovered.?.task_id);
    try testing.expectEqual(@as(i64, 2), recovered.?.attempts);

    // Worker B finishes it. The lease's own slices stay valid until the call that uses them, which is why
    // nothing resets the store's arena in between.
    const done = switch (try store.complete(recovered.?, "recovered")) {
        .committed => |rev| rev,
        .not_owner => return error.JobWasTakenOver,
    };

    const finished = try store.snapshot(t4);
    try testing.expectEqualStrings("completed", finished.tasks[0].state);
    try testing.expectEqualStrings("recovered", finished.tasks[0].result.?);
    try testing.expectEqual(@as(i64, 2), finished.tasks[0].attempts);
    try testing.expectEqual(done, finished.rev);
}

test "durable tasks: a worker whose lease expired cannot complete the job another worker holds" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf: [32]u8 = undefined;
    const t = try harness.tenant(&tenant_buf, "t-ownership");

    var store = try harness.openStore();
    defer store.deinit();

    try store.truncate();
    try harness.principal(&store, t, "alice");
    _ = try store.create(.{ .principal = "alice", .tenant = t, .idempotency_key = "k1", .title = "one job, two workers" });

    // Worker A takes the job with a lease short enough to expire while it works.
    const stale = (try store.lease(200)).?;
    try testing.expectEqual(@as(i64, 1), stale.attempts);

    // The lease expires and worker B takes over: the job now belongs to attempt 2.
    var taken_over: ?tasks.Lease = null;
    var waited_ms: usize = 0;
    while (taken_over == null and waited_ms < 5_000) : (waited_ms += 100) {
        harness.io().sleep(.fromMilliseconds(100), .awake) catch {};
        taken_over = try store.lease(5_000);
    }
    try testing.expect(taken_over != null);
    try testing.expectEqual(@as(i64, 2), taken_over.?.attempts);

    const conn = try harness.conn();
    defer conn.deinit();

    // Worker A finishes late. Its completion must be refused — inside its own transaction — rather than
    // overwriting the attempt that owns the job now, and it must leave no event behind.
    // Create and both leases have each published one event; a refused completion adds none.
    try testing.expect((try store.complete(stale, "the slower worker's answer")) == .not_owner);
    try testing.expectEqual(@as(i64, 3), try countOf(conn, outbox_in, t));

    const during = try store.snapshot(t);
    try testing.expectEqualStrings("running", during.tasks[0].state);
    try testing.expectEqual(@as(i64, 2), during.tasks[0].attempts);
    try testing.expect(during.tasks[0].result == null);

    // Worker B, the current owner, completes normally.
    const committed = switch (try store.complete(taken_over.?, "the worker that owns it")) {
        .committed => |rev| rev,
        .not_owner => return error.OwnerRefusedCompletion,
    };

    const after = try store.snapshot(t);
    try testing.expectEqualStrings("completed", after.tasks[0].state);
    try testing.expectEqualStrings("the worker that owns it", after.tasks[0].result.?);
    try testing.expectEqual(committed, after.rev);

    // A double completion by the same worker is refused too: the job is done, not running.
    try testing.expect((try store.complete(taken_over.?, "again")) == .not_owner);
    try testing.expectEqual(@as(i64, 4), try countOf(conn, outbox_in, t));
}

test "durable tasks: a takeover racing a completion leaves exactly one completion" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf: [32]u8 = undefined;
    const t = try harness.tenant(&tenant_buf, "t-race");

    var store = try harness.openStore();
    defer store.deinit();

    try store.truncate();
    try harness.principal(&store, t, "alice");

    const conn = try harness.conn();
    defer conn.deinit();

    // One race per round: a worker that stalled past its lease completes while another worker takes the job
    // over. The guard must serialize them, because both sides are writes against the same row: the
    // completion is a conditional UPDATE (attempts must still be this attempt's, state still running), and a
    // takeover leases only rows that are queued or whose lease expired. Exactly one of them may win, and the
    // task must never end up completed twice or completed by the attempt that lost.
    var round: usize = 0;
    while (round < 10) : (round += 1) {
        var key_buf: [32]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "race-{d}", .{round});
        const created = (try store.create(.{ .principal = "alice", .tenant = t, .idempotency_key = key, .title = "race" })).accepted;
        store.reset();

        const stale = (try store.lease(80)).?;
        try testing.expectEqual(created.task_id, stale.task_id);
        harness.io().sleep(.fromMilliseconds(120), .awake) catch {};

        var takeover_store = try harness.openStore();
        defer takeover_store.deinit();

        var racer = Racer{ .store = &takeover_store, .result = null };
        var thread = try std.Thread.spawn(.{}, Racer.run, .{&racer});

        // The stale attempt completes at the same moment the takeover runs.
        const stale_result = try store.complete(stale, "the stale attempt");
        thread.join();
        store.reset();

        const leaser_won = racer.result != null;
        const completer_won = stale_result == .committed;

        // Exactly one of the two writes won the row.
        try testing.expect(leaser_won != completer_won);

        // And exactly one completion exists, whichever it was.
        const completed = try store.snapshot(t);
        const row = for (completed.tasks) |task| {
            if (task.id == created.task_id) break task;
        } else unreachable;

        try testing.expectEqualStrings("completed", row.state);
        const completions = try conn.queryRow(
            CountRow,
            "SELECT count(*)::int8 AS n FROM outbox WHERE tenant_id = $1 AND kind = 'task_completed' AND payload->'task'->>'id' = $2",
            .{ t, try std.fmt.allocPrint(harness.allocator, "{d}", .{created.task_id}) },
        );
        try testing.expectEqual(@as(i64, 1), completions.?.n);
    }
}

/// The other half of the race: a worker taking over a job while its previous attempt completes.
const Racer = struct {
    store: *tasks.Store,
    result: ?tasks.Lease,

    fn run(self: *Racer) void {
        self.result = self.store.lease(5_000) catch null;
    }
};

test "durable tasks: a crash after the commit, before publication, still delivers" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf5: [32]u8 = undefined;
    const t5 = try harness.tenant(&tenant_buf5, "t5");

    var store = try harness.openStore();
    defer store.deinit();

    // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
    // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
    try store.truncate();

    try harness.principal(&store, t5, "alice");
    _ = try store.create(.{ .principal = "alice", .tenant = t5, .idempotency_key = "k1", .title = "committed then crash" });

    var feed = tasks.Feed.init(harness.io());
    var dispatcher = tasks.Dispatcher{ .store = &store, .feed = &feed };

    // The process "crashes" here: the commit happened, the dispatcher never ran. The work is still there.
    const conn = try harness.conn();
    defer conn.deinit();
    try testing.expectEqual(@as(i64, 1), try countOf(conn, unpublished_in, t5));

    // A later dispatcher run delivers it, in order, and marks it published.
    var cursor: u64 = 0;
    var buf: [8]tasks.Feed.Published = undefined;
    const delivered = feed.drain(t5, cursor, &buf);
    try testing.expectEqual(@as(usize, 0), delivered.events.len);

    try testing.expectEqual(@as(usize, 1), try dispatcher.runOnce());
    const after = feed.drain(t5, cursor, &buf);
    try testing.expectEqual(@as(usize, 1), after.events.len);
    try testing.expectEqualStrings("task_created", after.events[0].kind);
    try testing.expectEqual(@as(i64, 0), try countOf(conn, unpublished_in, t5));

    cursor = after.events[0].seq;

    // The lease and the completion also land in the outbox, and both reach the view.
    const lease = (try store.lease(5_000)).?;
    try testing.expect((try store.complete(lease, "ok")) == .committed);
    try testing.expectEqual(@as(usize, 2), try dispatcher.runOnce());

    const rest = feed.drain(t5, cursor, &buf);
    try testing.expectEqual(@as(usize, 2), rest.events.len);
    try testing.expectEqualStrings("task_running", rest.events[0].kind);
    try testing.expectEqualStrings("task_completed", rest.events[1].kind);
}

test "durable tasks: a replayed event delivery does not move the view twice" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf6: [32]u8 = undefined;
    const t6 = try harness.tenant(&tenant_buf6, "t6");

    var store = try harness.openStore();
    defer store.deinit();

    // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
    // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
    try store.truncate();

    try harness.principal(&store, t6, "alice");
    _ = try store.create(.{ .principal = "alice", .tenant = t6, .idempotency_key = "k1", .title = "replayed" });

    var feed = tasks.Feed.init(harness.io());
    var dispatcher = tasks.Dispatcher{ .store = &store, .feed = &feed };
    try testing.expectEqual(@as(usize, 1), try dispatcher.runOnce());

    const conn = try harness.conn();
    defer conn.deinit();

    // At-least-once in the narrowest sense: the row was published, and then the marking was lost (the
    // dispatcher crashed between the two). It is published again on the next run.
    _ = try conn.exec("UPDATE outbox SET published = false WHERE tenant_id = $1", .{t6});
    try testing.expectEqual(@as(usize, 1), try dispatcher.runOnce());

    // The view sees one event, applies one revision, and the replay is dropped by both layers.
    var cursor: u64 = 0;
    var buf: [8]tasks.Feed.Published = undefined;
    const drained = feed.drain(t6, cursor, &buf);
    try testing.expectEqual(@as(usize, 1), drained.events.len);

    var applied: i64 = 0;
    var applied_count: usize = 0;
    for (drained.events) |event| {
        if (tasks.applyRevision(&applied, event.rev)) applied_count += 1;
        cursor = event.seq;
    }

    // The feed's own duplicate check dropped the second copy; the revision check would drop it too.
    const replay = feed.drain(t6, cursor, &buf);
    try testing.expectEqual(@as(usize, 0), replay.events.len);
    try testing.expectEqual(@as(usize, 1), applied_count);
    try testing.expect(!tasks.applyRevision(&applied, drained.events[0].rev));

    const snapshot = try store.snapshot(t6);
    try testing.expectEqual(@as(usize, 1), snapshot.tasks.len);
    try testing.expectEqual(applied, snapshot.rev);
}

test "durable tasks: a restarted view reconstructs the state from the database" {
    var harness = Harness.init();
    defer harness.deinit();

    var tenant_buf7: [32]u8 = undefined;
    const t7 = try harness.tenant(&tenant_buf7, "t7");

    const unique = t7;

    var revision: i64 = 0;
    {
        // The first process: it creates the task, runs it through the worker, and then goes away whole —
        // the store's pool, its arena, and every slice it handed out are gone before the second store opens.
        var before = try harness.openStore();
        defer before.deinit();

        // The suite truncates what the slice owns, because the worker leases the oldest ready job of any
        // tenant: a scenario asserting on its own job cannot have a previous run's rows queued.
        try before.truncate();

        try harness.principal(&before, unique, "alice");
        _ = try before.create(.{ .principal = "alice", .tenant = unique, .idempotency_key = "k1", .title = "survives a restart" });

        var worker = tasks.Worker{ .store = &before, .id = "w1", .work_ms = 0 };
        try testing.expect(try worker.runOnce());

        const committed = try before.snapshot(unique);
        try testing.expectEqualStrings("completed", committed.tasks[0].state);
        try testing.expectEqual(@as(i64, 1), committed.tasks[0].attempts);
        revision = committed.rev;
    }

    // Server restart: a fresh store, a fresh pool, no process-local state carried over.
    var after = try harness.openStore();
    defer after.deinit();

    const rebuilt = try after.snapshot(unique);
    try testing.expectEqual(revision, rebuilt.rev);
    try testing.expectEqual(@as(usize, 1), rebuilt.tasks.len);
    try testing.expectEqualStrings("survives a restart", rebuilt.tasks[0].title);
    try testing.expectEqualStrings("completed", rebuilt.tasks[0].state);
    try testing.expectEqualStrings("done by w1", rebuilt.tasks[0].result.?);
    try testing.expectEqual(@as(i64, 1), rebuilt.tasks[0].attempts);

    // A fresh feed (a restarted process) has no events, and the view needs none: the snapshot is the
    // state, and the revision tells it which patches it can still accept.
    var feed = tasks.Feed.init(harness.io());
    var buf: [4]tasks.Feed.Published = undefined;
    const drained = feed.drain(unique, 0, &buf);
    try testing.expectEqual(@as(usize, 0), drained.events.len);
    try testing.expect(!drained.gap);
}
