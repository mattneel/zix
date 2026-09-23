//! Acceptance for the durable action slice, against a real PostgreSQL.
//!
//! These are the claims the slice makes, each one observed from outside it: what a caller sees, what a
//! worker sees, and what the database holds afterwards. The three tests inside `tasks.zig` cover the parts
//! that need no database (the revision gate, the feed ring, the event payload); these cover the invariants
//! that only exist because there is a database under them.
//!
//! One database is shared by every scenario here, so each one starts by truncating the slice's tables and
//! seeds what it needs. That is the same thing the demo does on startup, and it means a run is
//! reproducible rather than dependent on what the last run left behind.

const std = @import("std");
const zix = @import("zix");
const tasks = @import("tasks.zig");
const build_options = @import("build_options");

const postgrez = zix.Driver.postgrez;

/// Point this at a database you are willing to empty — every scenario truncates:
/// `zig build test-durable -Ddsn=postgres://user:password@host:5432/database`.
const dsn = build_options.dsn;

/// Every scenario shares one database, so they run one at a time. Tests are otherwise concurrent, and two
/// of these truncating each other's rows would fail in a way that looks like a slice bug.
var db_lock: std.Io.Mutex = .init;

fn open(store: *tasks.Store) !void {
    try store.init(std.testing.allocator, std.testing.io, dsn, 4);
    errdefer store.deinit();

    try store.truncate();
    try store.addPrincipal("alice", "acme");
}

const CountRow = struct { n: i64 };

/// A second connection to the same database, used to ask what is actually stored rather than what the
/// slice says it stored: "no second job" is a claim about rows, so it is checked as rows.
const Raw = struct {
    pool: postgrez.Pool,
    allocator: std.mem.Allocator,

    fn open_(allocator: std.mem.Allocator) !Raw {
        const parsed = try postgrez.parseUrl(dsn);

        return .{
            .allocator = allocator,
            .pool = try postgrez.Pool.init(allocator, std.testing.io, .{
                .ip = parsed.ip,
                .port = parsed.port,
                .user = parsed.user,
                .password = parsed.password,
                .database = parsed.database,
                .tls = parsed.tls,
                .pool_size = 2,
            }),
        };
    }

    fn deinit(self: *Raw) void {
        self.pool.deinit();
    }

    fn count(self: *Raw, sql: []const u8) !i64 {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        const row = (try conn.queryRow(CountRow, sql, .{})) orelse return error.NoRow;

        return row.n;
    }
};

test "zix durable tasks: a retried submission returns its task, inserts no second job" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    var raw = try Raw.open_(std.testing.allocator);
    defer raw.deinit();

    const request = tasks.CreateRequest{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "render the tiles",
    };

    const first = try store.create(request);
    try std.testing.expectEqual(false, (try expectAccepted(first)).duplicate);
    const first_id = (try expectAccepted(first)).task_id;
    const first_rev = (try expectAccepted(first)).rev;
    store.reset();

    // The same key again: the database's unique constraint decides, so the caller gets its own task back
    // and no work is queued twice.
    const retry = try store.create(request);
    try std.testing.expectEqual(true, (try expectAccepted(retry)).duplicate);
    try std.testing.expectEqual(first_id, (try expectAccepted(retry)).task_id);
    // A retry that changed the revision would mean read-your-writes broke: the state did not move, so the
    // revision must not either.
    try std.testing.expectEqual(first_rev, (try expectAccepted(retry)).rev);
    store.reset();

    try std.testing.expectEqual(@as(i64, 1), try raw.count("SELECT count(*)::int8 AS n FROM tasks"));
    try std.testing.expectEqual(@as(i64, 1), try raw.count("SELECT count(*)::int8 AS n FROM jobs"));

    // A different key is a different submission: the unique key is the pair, not the tenant.
    const other = try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-2",
        .title = "render the tiles",
    });
    try std.testing.expectEqual(false, (try expectAccepted(other)).duplicate);
    store.reset();

    try std.testing.expectEqual(@as(i64, 2), try raw.count("SELECT count(*)::int8 AS n FROM tasks"));
    try std.testing.expectEqual(@as(i64, 2), try raw.count("SELECT count(*)::int8 AS n FROM jobs"));
}

test "zix durable tasks: a task never exists without its job, nor completes without its event" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    var raw = try Raw.open_(std.testing.allocator);
    defer raw.deinit();

    _ = try expectAccepted(try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "first",
    }));
    _ = try expectAccepted(try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-2",
        .title = "second",
    }));
    store.reset();

    // The create transaction wrote the task, its job and its event together: there is no row in any of
    // these shapes, at any point after the commit.
    try std.testing.expectEqual(@as(i64, 0), try raw.count(
        "SELECT count(*)::int8 AS n FROM tasks t WHERE NOT EXISTS (SELECT 1 FROM jobs j WHERE j.task_id = t.id)",
    ));
    try std.testing.expectEqual(@as(i64, 2), try raw.count(
        "SELECT count(*)::int8 AS n FROM outbox WHERE kind = 'task_created'",
    ));

    // Run the job worker and the dispatcher the way the demo does, once each.
    var worker = tasks.Worker{ .store = &store, .id = "worker-a", .work_ms = 0 };
    try std.testing.expect(try worker.runOnce());
    store.reset();

    var feed = tasks.Feed.init(std.testing.io);
    var dispatcher = tasks.Dispatcher{ .store = &store, .feed = &feed };
    try std.testing.expect(try dispatcher.runOnce() > 0);
    store.reset();

    // The completion committed its three writes together too: the task is completed, the job is completed,
    // and exactly one event exists for the completion of that one task.
    const snapshot = try store.snapshot("acme");
    try std.testing.expectEqual(@as(usize, 2), snapshot.tasks.len);

    var completed: usize = 0;
    for (snapshot.tasks) |task| {
        if (std.mem.eql(u8, task.state, "completed")) completed += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), completed);
    store.reset();

    try std.testing.expectEqual(@as(i64, 1), try raw.count(
        "SELECT count(*)::int8 AS n FROM jobs WHERE state = 'done'",
    ));
    try std.testing.expectEqual(@as(i64, 1), try raw.count(
        "SELECT count(*)::int8 AS n FROM jobs WHERE state = 'queued'",
    ));
    try std.testing.expectEqual(@as(i64, 1), try raw.count(
        "SELECT count(*)::int8 AS n FROM outbox WHERE kind = 'task_completed'",
    ));
    // Nothing was written without its event: the tenant's revision is the highest revision any outbox row
    // carries, so a view that replays the events lands exactly on the stored revision.
    try std.testing.expectEqual(
        try raw.count("SELECT COALESCE(max(rev), 0)::int8 AS n FROM outbox WHERE tenant_id = 'acme'"),
        try raw.count("SELECT COALESCE((SELECT rev FROM tenant_revision WHERE tenant_id = 'acme'), 0)::int8 AS n"),
    );
}

test "zix durable tasks: a lease is held, the owner's completion commits, and it is not leased twice" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    _ = try expectAccepted(try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "first",
    }));
    store.reset();

    // The lease borrows the store's arena, so it is used before anything is released: the check that a
    // held job is not offered twice happens between the lease and the completion, not across a reset.
    const held = (try store.lease(5_000)) orelse return error.ExpectedALease;
    defer store.reset();
    try std.testing.expectEqual(@as(i64, 1), held.attempts);

    // Held, so the next poll finds nothing: a lease takes the job out of circulation without locking a row
    // for the length of the work.
    try std.testing.expect((try store.lease(5_000)) == null);

    const rev = switch (try store.complete(held, "done by worker-a")) {
        .committed => |value| value,
        .not_owner => return error.ExpectedTheOwnerToCommit,
    };

    const snapshot = try store.snapshot("acme");
    try std.testing.expectEqual(rev, snapshot.rev);
    try std.testing.expectEqualStrings("completed", snapshot.tasks[0].state);
    try std.testing.expectEqualStrings("done by worker-a", snapshot.tasks[0].result.?);
    store.reset();

    // Completed, so it is not offered again.
    try std.testing.expect((try store.lease(5_000)) == null);
}

test "zix durable tasks: an expired lease is taken again, and the older attempt's result is dropped" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    var raw = try Raw.open_(std.testing.allocator);
    defer raw.deinit();

    _ = try expectAccepted(try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "first",
    }));
    store.reset();

    // An attempt that takes the job and then dies: its lease expires while it is "working". Both leases
    // borrow the arena, so neither is used across a reset.
    const dead = (try store.lease(1)) orelse return error.ExpectedALease;
    defer store.reset();
    store.io.sleep(.fromMilliseconds(30), .awake) catch {};

    // The next poll takes the same job, with the attempt count showing there was a previous one: a crash
    // loop is visible as a number rather than as silence.
    const next = (try store.lease(5_000)) orelse return error.ExpectedTheJobToComeBack;
    try std.testing.expectEqual(dead.job_id, next.job_id);
    try std.testing.expectEqual(@as(i64, 2), next.attempts);

    // The dead attempt wakes up and finishes. Its result must not overwrite the attempt that owns the job
    // now, and its event must not reach a view.
    try std.testing.expectEqual(tasks.Completion.not_owner, try store.complete(dead, "done by the dead one"));

    switch (try store.complete(next, "done by the live one")) {
        .committed => {},
        .not_owner => return error.ExpectedTheLiveAttemptToCommit,
    }

    const snapshot = try store.snapshot("acme");
    try std.testing.expectEqualStrings("completed", snapshot.tasks[0].state);
    try std.testing.expectEqualStrings("done by the live one", snapshot.tasks[0].result.?);
    store.reset();

    // The dropped attempt wrote nothing at all: one completion event for one task, and one owner.
    try std.testing.expectEqual(@as(i64, 1), try raw.count(
        "SELECT count(*)::int8 AS n FROM outbox WHERE kind = 'task_completed'",
    ));
    try std.testing.expectEqual(@as(i64, 2), try raw.count(
        "SELECT attempts::int8 AS n FROM jobs",
    ));
}

test "zix durable tasks: a dispatcher replay is delivered once and dropped by the view" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    _ = try expectAccepted(try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "first",
    }));
    store.reset();

    var feed = tasks.Feed.init(std.testing.io);

    // The dispatcher publishes the row and then "crashes" before marking it: the row is still pending, so
    // the next poll hands it out again. Delivery is at least once, and this is what that looks like.
    const first = try store.pendingOutbox(32);
    try std.testing.expectEqual(@as(usize, 1), first.len);
    try feed.publish(first[0].tenant_id, first[0].rev, first[0].kind, first[0].payload);
    store.reset();

    const replayed = try store.pendingOutbox(32);
    try std.testing.expectEqual(@as(usize, 1), replayed.len);
    try std.testing.expectEqual(first[0].id, replayed[0].id);
    try std.testing.expectEqual(first[0].rev, replayed[0].rev);
    store.reset();

    // The view is what makes the replay harmless: the revision moves it once, and the replay is dropped.
    var applied: i64 = 0;
    try std.testing.expect(tasks.applyRevision(&applied, replayed[0].rev));
    try std.testing.expect(!tasks.applyRevision(&applied, replayed[0].rev));
    try std.testing.expectEqual(replayed[0].rev, applied);

    // Marked only after the feed took it, so the row drains and stays drained.
    try store.markPublished(replayed[0].id);
    store.reset();
    try std.testing.expectEqual(@as(usize, 0), (try store.pendingOutbox(32)).len);
}

test "zix durable tasks: a subscription rebuilds from committed state" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    var raw = try Raw.open_(std.testing.allocator);
    defer raw.deinit();

    _ = try expectAccepted(try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "first",
    }));
    store.reset();

    var worker = tasks.Worker{ .store = &store, .id = "worker-a", .work_ms = 0 };
    try std.testing.expect(try worker.runOnce());
    store.reset();

    var feed = tasks.Feed.init(std.testing.io);
    var dispatcher = tasks.Dispatcher{ .store = &store, .feed = &feed };
    try std.testing.expect(try dispatcher.runOnce() > 0);
    store.reset();

    // What a reconnect, a reload or a restarted server does: ask for the snapshot instead of the events.
    // It has to land on the same revision the events would have built, or a view that reconnects would
    // disagree with one that stayed.
    const snapshot = try store.snapshot("acme");
    try std.testing.expectEqual(
        try raw.count("SELECT COALESCE(max(rev), 0)::int8 AS n FROM outbox WHERE tenant_id = 'acme'"),
        snapshot.rev,
    );

    // And the work it describes is the work that happened.
    try std.testing.expectEqual(@as(usize, 1), snapshot.tasks.len);
    try std.testing.expectEqualStrings("completed", snapshot.tasks[0].state);
    try std.testing.expectEqualStrings("done by worker-a", snapshot.tasks[0].result.?);

    // Another tenant's view sees none of it.
    store.reset();
    const other = try store.snapshot("globex");
    try std.testing.expectEqual(@as(i64, 0), other.rev);
    try std.testing.expectEqual(@as(usize, 0), other.tasks.len);
}

test "zix durable tasks: a refused submission writes nothing" {
    db_lock.lockUncancelable(std.testing.io);
    defer db_lock.unlock(std.testing.io);

    var store: tasks.Store = undefined;
    try open(&store);
    defer store.deinit();

    var raw = try Raw.open_(std.testing.allocator);
    defer raw.deinit();

    // Not a member of the tenant: authorization is a lookup, and a refusal is a value the view can show
    // rather than an error the transport has to interpret.
    const stranger = try store.create(.{
        .principal = "mallory",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "first",
    });
    try std.testing.expectEqualStrings("principal is not a member of this tenant", try expectRejected(stranger));
    store.reset();

    const empty = try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "submit-1",
        .title = "",
    });
    try std.testing.expect(empty == .rejected);
    store.reset();

    const long_key = try store.create(.{
        .principal = "alice",
        .tenant = "acme",
        .idempotency_key = "k" ** (tasks.max_key + 1),
        .title = "first",
    });
    try std.testing.expect(long_key == .rejected);
    store.reset();

    try std.testing.expectEqual(@as(i64, 0), try raw.count("SELECT count(*)::int8 AS n FROM tasks"));
    try std.testing.expectEqual(@as(i64, 0), try raw.count("SELECT count(*)::int8 AS n FROM jobs"));
    try std.testing.expectEqual(@as(i64, 0), try raw.count("SELECT count(*)::int8 AS n FROM outbox"));
}

// --------------------------------------------------------- //

fn expectAccepted(outcome: tasks.Outcome) !tasks.Accepted {
    return switch (outcome) {
        .accepted => |accepted| accepted,
        .rejected => |reason| {
            std.debug.print("expected an accepted submission, got: {s}\n", .{reason});

            return error.ExpectedAcceptance;
        },
    };
}

/// `Outcome` is a union: a test that asserts on one half has to say what happens if it is the other.
fn expectRejected(outcome: tasks.Outcome) ![]const u8 {
    return switch (outcome) {
        .accepted => |accepted| {
            std.debug.print("expected a refused submission, got task {d}\n", .{accepted.task_id});

            return error.ExpectedRefusal;
        },
        .rejected => |reason| reason,
    };
}
