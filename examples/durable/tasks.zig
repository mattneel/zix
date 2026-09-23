//! Durable, authorized CreateTask: the whole slice, in one place.
//!
//! What:
//! - A typed submission is validated and authorized, then one database transaction inserts the task and
//!   its job. A worker leases the job and executes it. One completion transaction updates the task,
//!   completes the job, and inserts an outbox row. A dispatcher publishes that row into the in-process
//!   feed. The live view drains the feed and patches itself, and rebuilds from the database whenever it
//!   (re)connects.
//!
//! Note:
//! - **At least once, made harmless by revisions.** Every state change allocates the tenant's next
//!   revision inside the same transaction that changes the state, and the outbox row carries it. The
//!   dispatcher marks a row published only after the feed took it, so a crash in between replays the
//!   event; a view that already applied revision N drops anything <= N, and a view that missed events
//!   rebuilds from the snapshot.
//! - **Idempotency is the database's, not the caller's.** `(tenant_id, idempotency_key)` is unique, so a
//!   retried submission returns the task it already created and inserts no second job.
//! - **One transaction per step.** Create commits `{task, job, outbox}` together; complete commits
//!   `{task, job, outbox}` together. There is no window where a task exists without its job, or a
//!   completed task without its event.
//! - **Leases, not locks.** A worker holds a job by writing `lease_until`; a worker that dies mid-job
//!   leaves a `running` row whose lease expires, and the next poll takes it again with `attempts` bumped.
//! - **Postgres pools are shared-nothing** (one pool belongs to one thread), so a `Store` is per thread:
//!   the HTTP worker, the job worker, and the dispatcher each build their own. Results are owned by the
//!   store's arena, so call `reset()` between operations once the returned slices are done with.

const std = @import("std");
const zix = @import("zix");

const postgrez = zix.Driver.postgrez;

// --------------------------------------------------------- //
// Schema

/// The slice's schema, applied by `Store.init`. Every statement is idempotent, so startup is the only
/// migration step this slice needs and running it twice is a no-op.
pub const schema = [_][]const u8{
    \\CREATE TABLE IF NOT EXISTS principals (
    \\  id text PRIMARY KEY,
    \\  tenant_id text NOT NULL
    \\)
    ,
    \\CREATE TABLE IF NOT EXISTS tasks (
    \\  id bigserial PRIMARY KEY,
    \\  tenant_id text NOT NULL,
    \\  idempotency_key text NOT NULL,
    \\  title text NOT NULL,
    \\  state text NOT NULL DEFAULT 'queued',
    \\  result text,
    \\  attempts integer NOT NULL DEFAULT 0,
    \\  created_rev bigint NOT NULL DEFAULT 0,
    \\  updated_rev bigint NOT NULL DEFAULT 0,
    \\  UNIQUE (tenant_id, idempotency_key)
    \\)
    ,
    \\CREATE TABLE IF NOT EXISTS jobs (
    \\  id bigserial PRIMARY KEY,
    \\  task_id bigint NOT NULL REFERENCES tasks (id),
    \\  state text NOT NULL DEFAULT 'queued',
    \\  attempts integer NOT NULL DEFAULT 0,
    \\  available_at timestamptz NOT NULL DEFAULT now(),
    \\  lease_until timestamptz,
    \\  UNIQUE (task_id)
    \\)
    ,
    \\CREATE TABLE IF NOT EXISTS tenant_revision (
    \\  tenant_id text PRIMARY KEY,
    \\  rev bigint NOT NULL DEFAULT 0
    \\)
    ,
    \\CREATE TABLE IF NOT EXISTS outbox (
    \\  id bigserial PRIMARY KEY,
    \\  tenant_id text NOT NULL,
    \\  rev bigint NOT NULL,
    \\  kind text NOT NULL,
    \\  payload jsonb NOT NULL,
    \\  published boolean NOT NULL DEFAULT false,
    \\  created_at timestamptz NOT NULL DEFAULT now()
    \\)
    ,
    // Partial indexes: the dispatcher only ever scans unpublished rows, and the worker only ever scans
    // rows that are ready or whose lease has expired.
    \\CREATE INDEX IF NOT EXISTS outbox_unpublished ON outbox (id) WHERE NOT published
    ,
    \\CREATE INDEX IF NOT EXISTS jobs_leasable ON jobs (id) WHERE state <> 'done'
    ,
};

// --------------------------------------------------------- //

/// Longest title this slice accepts, and longest idempotency key.
pub const max_title = 120;
pub const max_key = 64;

/// How many published events the in-process feed keeps per tenant before it drops the oldest, and how
/// many tenants one process serves. A view whose cursor has fallen further behind than the ring is told
/// to re-snapshot instead, which is the same repair a reconnect performs.
pub const feed_ring = 128;
pub const feed_tenants = 8;

pub const Task = struct {
    id: i64,
    title: []const u8,
    state: []const u8,
    attempts: i64,
    result: ?[]const u8,
};

pub const CreateRequest = struct {
    principal: []const u8,
    tenant: []const u8,
    idempotency_key: []const u8,
    title: []const u8,
};

pub const Accepted = struct {
    task_id: i64,
    rev: i64,
    /// True when this submission was a retry: the task existed under the key and nothing was inserted.
    duplicate: bool,
};

pub const Outcome = union(enum) {
    accepted: Accepted,
    /// The submission was refused, with the reason a view is meant to show the user.
    rejected: []const u8,
};

pub const Completion = union(enum) {
    /// The job was still this attempt's to finish: the task, the job and the outbox row committed together.
    committed: i64,
    /// Another attempt owns the job now, so nothing was written. This is what a worker whose lease expired
    /// and was taken over gets: its result must not overwrite the newer attempt's, and its event must not
    /// reach a view.
    not_owner,
};

pub const Snapshot = struct {
    rev: i64,
    tasks: []const Task,
};

pub const Lease = struct {
    job_id: i64,
    task_id: i64,
    tenant_id: []const u8,
    title: []const u8,
    attempts: i64,
};

pub const Event = struct {
    id: i64,
    tenant_id: []const u8,
    rev: i64,
    kind: []const u8,
    /// The event as the view receives it: `{"rev":N,"task":{...}}`.
    payload: []const u8,
};

/// Whether a revisioned patch may move the view forward. Delivery is at least once, so a view sees a
/// revision twice whenever a dispatcher crashed between publishing and marking; applying the same
/// revision twice must not move the state or double-count.
pub fn applyRevision(applied: *i64, rev: i64) bool {
    if (rev <= applied.*) return false;

    applied.* = rev;

    return true;
}

// --------------------------------------------------------- //

const RevRow = struct { rev: i64 };
const IdRow = struct { id: i64 };
const AuthRow = struct { ok: i32 };
const ExistingRow = struct { id: i64, rev: i64 };
const LeaseRow = struct {
    job_id: i64,
    task_id: i64,
    tenant_id: []const u8,
    title: []const u8,
    attempts: i64,
};
const OutboxRow = struct {
    id: i64,
    tenant_id: []const u8,
    rev: i64,
    kind: []const u8,
    payload: []const u8,
};

/// One thread's view of the durable store: its own connection pool and its own result arena.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    pool: postgrez.Pool,
    arena: std.heap.ArenaAllocator,

    /// Connect and apply the schema. `dsn` is a `postgres://user:password@host:port/database` URL, the
    /// form `postgrez.parseUrl` accepts.
    pub fn init(self: *Store, allocator: std.mem.Allocator, io: std.Io, dsn: []const u8, pool_size: usize) !void {
        const parsed = try postgrez.parseUrl(dsn);

        self.allocator = allocator;
        self.io = io;
        self.arena = std.heap.ArenaAllocator.init(allocator);
        // Every field the parsed DSN carries, including its TLS mode. Dropping `tls` here is silent and the
        // DSN's `sslmode=require` then does nothing: the connection goes out in cleartext, which a hosted
        // database refuses - so a URL that asks for TLS has to be the URL that gets it.
        self.pool = try postgrez.Pool.init(allocator, io, .{
            .ip = parsed.ip,
            .port = parsed.port,
            .user = parsed.user,
            .password = parsed.password,
            .database = parsed.database,
            .tls = parsed.tls,
            .pool_size = pool_size,
        });

        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        for (schema) |statement| _ = try conn.exec(statement, .{});
    }

    pub fn deinit(self: *Store) void {
        self.pool.deinit();
        self.arena.deinit();
    }

    /// Free everything a completed operation allocated. Slices this store returned stay valid only until
    /// the next `reset`.
    pub fn reset(self: *Store) void {
        _ = self.arena.reset(.retain_capacity);
    }

    /// Seed a principal that is a member of `tenant`. The authorization step is a lookup against exactly
    /// this table, so the slice can be wired to whatever identity mapping a deployment already has.
    pub fn addPrincipal(self: *Store, principal: []const u8, tenant: []const u8) !void {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        _ = try conn.exec(
            "INSERT INTO principals (id, tenant_id) VALUES ($1, $2) ON CONFLICT (id) DO UPDATE SET tenant_id = excluded.tenant_id",
            .{ principal, tenant },
        );
    }

    /// Delete every row this slice owns, so a test or a demo run starts from a known state.
    pub fn truncate(self: *Store) !void {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        _ = try conn.exec("TRUNCATE outbox, jobs, tasks, tenant_revision", .{});
    }

    /// Validate, authorize, and create. The task, its job, and the outbox row commit together, so a task
    /// never exists without the job that will complete it.
    pub fn create(self: *Store, request: CreateRequest) !Outcome {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        var tx = try conn.begin();
        defer tx.rollback();

        const outcome = try Store.createIn(&tx, request);
        switch (outcome) {
            .rejected => return outcome,
            .accepted => try tx.commit(),
        }

        return outcome;
    }

    /// The transaction body of `create`, callable with a caller-owned transaction so the failure case can
    /// be tested where it matters: after both inserts, before the commit. Nothing here writes outside `tx`,
    /// which is why it takes no `Store`: a caller that rolls back has to be able to run exactly this body.
    pub fn createIn(tx: *postgrez.Transaction, request: CreateRequest) !Outcome {
        if (request.title.len == 0 or request.title.len > max_title) return .{ .rejected = "title must be 1..120 bytes" };
        if (request.idempotency_key.len == 0 or request.idempotency_key.len > max_key) return .{ .rejected = "idempotency key must be 1..64 bytes" };
        if (request.principal.len == 0 or request.tenant.len == 0) return .{ .rejected = "principal and tenant are required" };

        const member = try tx.queryRow(AuthRow, "SELECT 1::int8 AS ok FROM principals WHERE id = $1 AND tenant_id = $2", .{ request.principal, request.tenant });
        if (member == null) return .{ .rejected = "principal is not a member of this tenant" };

        // The unique key is what makes a retry idempotent: the second submission conflicts, reads the task
        // it already created, and inserts no second job and no second event.
        const inserted = try tx.queryRow(IdRow,
            \\INSERT INTO tasks (tenant_id, idempotency_key, title)
            \\VALUES ($1, $2, $3)
            \\ON CONFLICT (tenant_id, idempotency_key) DO NOTHING
            \\RETURNING id::int8 AS id
        , .{ request.tenant, request.idempotency_key, request.title });

        if (inserted == null) {
            const existing = (try tx.queryRow(
                ExistingRow,
                "SELECT id::int8 AS id, updated_rev::int8 AS rev FROM tasks WHERE tenant_id = $1 AND idempotency_key = $2",
                .{ request.tenant, request.idempotency_key },
            )).?;

            return .{ .accepted = .{ .task_id = existing.id, .rev = existing.rev, .duplicate = true } };
        }

        const task_id = inserted.?.id;
        const rev = try nextRevision(tx, request.tenant);

        _ = try tx.exec("UPDATE tasks SET created_rev = $2, updated_rev = $2 WHERE id = $1", .{ task_id, rev });
        _ = try tx.exec("INSERT INTO jobs (task_id) VALUES ($1)", .{task_id});

        var payload_buf: [512]u8 = undefined;
        const payload = try renderTaskEvent(&payload_buf, rev, "task_created", task_id, request.title, "queued", 0, null);
        try insertOutbox(tx, request.tenant, rev, "task_created", payload);

        return .{ .accepted = .{ .task_id = task_id, .rev = rev, .duplicate = false } };
    }

    /// The committed state of one tenant with the revision it is at. This is what a view rebuilds from, so
    /// it reads the tables directly rather than any process-local cache.
    pub fn snapshot(self: *Store, tenant: []const u8) !Snapshot {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        const rev = (try conn.queryRow(RevRow, "SELECT COALESCE((SELECT rev FROM tenant_revision WHERE tenant_id = $1), 0)::int8 AS rev", .{tenant})).?.rev;

        var tasks: std.ArrayList(Task) = .empty;
        var result = try conn.rows(
            \\SELECT id::int8 AS id, title, state, attempts::int8 AS attempts, result
            \\FROM tasks WHERE tenant_id = $1 ORDER BY id
        , .{tenant});
        defer result.deinit();

        const arena = self.arena.allocator();
        while (try result.next()) |row| {
            try tasks.append(arena, .{
                .id = try row.get(i64, 0),
                .title = try arena.dupe(u8, try row.get([]const u8, 1)),
                .state = try arena.dupe(u8, try row.get([]const u8, 2)),
                .attempts = try row.get(i64, 3),
                .result = if (try row.get(?[]const u8, 4)) |text| try arena.dupe(u8, text) else null,
            });
        }

        return .{ .rev = rev, .tasks = try tasks.toOwnedSlice(arena) };
    }

    /// Lease the oldest ready job, or the oldest job whose lease expired, and bump the task to `running`
    /// in the same transaction. `FOR UPDATE SKIP LOCKED` is what lets several workers poll one table.
    ///
    /// Note:
    /// - The lease is a timestamp, not a lock: a worker that dies holding one leaves a `running` row whose
    ///   lease expires, and the next poll takes it again with `attempts` bumped, so a crash loop shows up
    ///   in the view instead of hiding.
    pub fn lease(self: *Store, lease_ms: i64) !?Lease {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        var tx = try conn.begin();
        defer tx.rollback();

        const leased = try tx.queryRow(LeaseRow,
            \\WITH candidate AS (
            \\  SELECT j.id FROM jobs j
            \\  WHERE (j.state = 'queued' AND j.available_at <= now())
            \\     OR (j.state = 'running' AND j.lease_until IS NOT NULL AND j.lease_until < now())
            \\  ORDER BY j.id
            \\  FOR UPDATE SKIP LOCKED
            \\  LIMIT 1
            \\), leased AS (
            \\  UPDATE jobs SET state = 'running',
            \\                  attempts = jobs.attempts + 1,
            \\                  lease_until = now() + make_interval(secs => $1::float8)
            \\  FROM candidate WHERE jobs.id = candidate.id
            \\  RETURNING jobs.id, jobs.task_id, jobs.attempts
            \\)
            \\SELECT leased.id::int8 AS job_id, leased.task_id::int8 AS task_id,
            \\       leased.attempts::int8 AS attempts, t.tenant_id AS tenant_id, t.title AS title
            \\FROM leased JOIN tasks t ON t.id = leased.task_id
        , .{@as(f64, @floatFromInt(lease_ms)) / 1000.0});

        if (leased == null) return null;

        const found = leased.?;
        const rev = try nextRevision(&tx, found.tenant_id);
        _ = try tx.exec("UPDATE tasks SET state = 'running', attempts = $2, updated_rev = $3 WHERE id = $1", .{ found.task_id, found.attempts, rev });

        var payload_buf: [512]u8 = undefined;
        const payload = try renderTaskEvent(&payload_buf, rev, "task_running", found.task_id, found.title, "running", found.attempts, null);
        try insertOutbox(&tx, found.tenant_id, rev, "task_running", payload);

        try tx.commit();

        return .{
            .job_id = found.job_id,
            .task_id = found.task_id,
            .tenant_id = try self.arena.allocator().dupe(u8, found.tenant_id),
            .title = try self.arena.allocator().dupe(u8, found.title),
            .attempts = found.attempts,
        };
    }

    /// Complete a leased job: the task update, the job completion, and the outbox row commit together, and
    /// only if this attempt still owns the job.
    ///
    /// Note:
    /// - Ownership is checked inside the same transaction as the writes it guards, against `attempts`: the
    ///   token every lease bumps. A worker whose lease expired and was taken over therefore cannot complete
    ///   a job another attempt holds: it gets `.not_owner`, writes nothing, and produces no event. Without
    ///   that check, lease expiry would be a duplicate execution rather than a recovery, and the slower of
    ///   two workers would decide the result.
    pub fn complete(self: *Store, held: Lease, result: []const u8) !Completion {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        var tx = try conn.begin();
        defer tx.rollback();

        const owned = try tx.queryRow(IdRow,
            \\UPDATE jobs SET state = 'done', lease_until = NULL
            \\WHERE id = $1 AND attempts = $2 AND state = 'running'
            \\RETURNING id::int8 AS id
        , .{ held.job_id, held.attempts });

        if (owned == null) return .not_owner;

        const rev = try nextRevision(&tx, held.tenant_id);

        _ = try tx.exec("UPDATE tasks SET state = 'completed', result = $2, updated_rev = $3 WHERE id = $1", .{ held.task_id, result, rev });

        var payload_buf: [512]u8 = undefined;
        const payload = try renderTaskEvent(&payload_buf, rev, "task_completed", held.task_id, held.title, "completed", held.attempts, result);
        try insertOutbox(&tx, held.tenant_id, rev, "task_completed", payload);

        try tx.commit();

        return .{ .committed = rev };
    }

    /// The unpublished outbox rows, oldest first. Nothing is marked here: the dispatcher marks a row
    /// published only after the feed took it, which is what makes a crash between the two a replay rather
    /// than a lost update.
    pub fn pendingOutbox(self: *Store, limit: usize) ![]Event {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        var events: std.ArrayList(Event) = .empty;
        var result = try conn.rows(
            \\SELECT id::int8 AS id, tenant_id, rev::int8 AS rev, kind, payload::text AS payload
            \\FROM outbox WHERE NOT published ORDER BY id LIMIT $1
        , .{@as(i64, @intCast(@min(limit, 1024)))});
        defer result.deinit();

        const arena = self.arena.allocator();
        while (try result.next()) |row| {
            try events.append(arena, .{
                .id = try row.get(i64, 0),
                .tenant_id = try arena.dupe(u8, try row.get([]const u8, 1)),
                .rev = try row.get(i64, 2),
                .kind = try arena.dupe(u8, try row.get([]const u8, 3)),
                .payload = try arena.dupe(u8, try row.get([]const u8, 4)),
            });
        }

        return events.toOwnedSlice(arena);
    }

    /// Mark one outbox row published. The dispatcher calls this only after the feed accepted the event.
    pub fn markPublished(self: *Store, event_id: i64) !void {
        const conn = try self.pool.acquire();
        defer self.pool.release(conn);

        _ = try conn.exec("UPDATE outbox SET published = true WHERE id = $1", .{event_id});
    }
};

/// Allocate this tenant's next revision inside `tx`, so the revision and the state change it labels commit
/// together or not at all.
fn nextRevision(tx: *postgrez.Transaction, tenant: []const u8) !i64 {
    return (try tx.queryRow(RevRow,
        \\INSERT INTO tenant_revision (tenant_id, rev) VALUES ($1, 1)
        \\ON CONFLICT (tenant_id) DO UPDATE SET rev = tenant_revision.rev + 1
        \\RETURNING rev::int8 AS rev
    , .{tenant})).?.rev;
}

fn insertOutbox(tx: *postgrez.Transaction, tenant: []const u8, rev: i64, kind: []const u8, payload: []const u8) !void {
    _ = try tx.exec("INSERT INTO outbox (tenant_id, rev, kind, payload) VALUES ($1, $2, $3, $4::jsonb)", .{ tenant, rev, kind, payload });
}

/// Render one event payload. The outbox column is `jsonb`, so Postgres rejects a malformed payload at the
/// insert: a bug in this renderer fails the transaction rather than reaching a view.
fn renderTaskEvent(out: []u8, rev: i64, kind: []const u8, task_id: i64, title: []const u8, state: []const u8, attempts: i64, result: ?[]const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(out);
    try writer.print("{{\"kind\":\"{s}\",\"rev\":{d},\"task\":{{\"id\":{d},\"title\":", .{ kind, rev, task_id });
    try writeJsonString(&writer, title);
    try writer.print(",\"state\":\"{s}\",\"attempts\":{d},\"result\":", .{ state, attempts });
    if (result) |text| try writeJsonString(&writer, text) else try writer.writeAll("null");
    try writer.writeAll("}}");

    return writer.buffered();
}

/// Escape one string into a JSON string literal. Titles come from the wire, so a quote in one must not be
/// able to close the payload's string and change the event's meaning.
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

// --------------------------------------------------------- //
// The publish step, in process

/// The tenant feed: what the dispatcher publishes into and what every subscribed view drains. It is the
/// "pub" in pub/sub for this slice, one bounded ring per tenant and one cursor per view held by the caller.
///
/// Note:
/// - Bounded on purpose. A view that has fallen further behind than the ring is told to re-snapshot
///   (`drain` reports `gap`), which is the same repair a reconnect performs, so a slow consumer costs a
///   snapshot instead of unbounded memory. `publish` is idempotent per revision, so a dispatcher replay
///   after a crash adds nothing.
pub const Feed = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    tenants: [feed_tenants]Tenant = @splat(.{}),

    const Tenant = struct {
        id: [64]u8 = @splat(0),
        id_len: usize = 0,
        /// Sequence of the newest entry, 0 while the ring is empty.
        newest: u64 = 0,
        /// Sequence of the oldest entry still in the ring.
        oldest: u64 = 1,
        entries: [feed_ring]Entry = @splat(.{}),
    };

    const Entry = struct {
        seq: u64 = 0,
        rev: i64 = 0,
        kind: [32]u8 = @splat(0),
        kind_len: usize = 0,
        payload: [512]u8 = @splat(0),
        payload_len: usize = 0,
    };

    pub const Published = struct {
        seq: u64,
        rev: i64,
        kind: []const u8,
        payload: []const u8,
    };

    pub const Drained = struct {
        events: []Published,
        /// The view's cursor is older than the ring: it must rebuild from the snapshot instead of patching.
        gap: bool,
    };

    pub fn init(io: std.Io) Feed {
        return .{ .io = io };
    }

    /// Publish one event for `tenant`.
    pub fn publish(self: *Feed, tenant: []const u8, rev: i64, kind: []const u8, payload: []const u8) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const target = self.findTenant(tenant) orelse return error.TooManyTenants;
        for (target.entries) |entry| {
            if (entry.seq != 0 and entry.rev == rev) return;
        }

        target.newest += 1;
        const slot = &target.entries[@intCast((target.newest - 1) % feed_ring)];
        slot.* = .{
            .seq = target.newest,
            .rev = rev,
            .kind_len = @min(kind.len, 32),
            .payload_len = @min(payload.len, 512),
        };
        @memcpy(slot.kind[0..slot.kind_len], kind[0..slot.kind_len]);
        @memcpy(slot.payload[0..slot.payload_len], payload[0..slot.payload_len]);

        if (target.newest - target.oldest >= feed_ring) target.oldest = target.newest - feed_ring + 1;
    }

    /// The newest sequence this feed has published for `tenant`, 0 when it has published nothing. A view
    /// that just read the committed state sets its cursor here: it needs no patch for a revision it was
    /// handed, and the feed stays a queue of what happened after the snapshot.
    pub fn latest(self: *Feed, tenant: []const u8) u64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const target = self.findTenant(tenant) orelse return 0;

        return target.newest;
    }

    /// The events after `cursor`, oldest first, without advancing it. The caller writes them and then calls
    /// `advance` with the last sequence it managed to write, so a short write is replayed rather than lost.
    pub fn drain(self: *Feed, tenant: []const u8, cursor: u64, out: []Published) Drained {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const target = self.findTenant(tenant) orelse return .{ .events = out[0..0], .gap = false };
        if (target.newest == 0) return .{ .events = out[0..0], .gap = false };
        if (cursor + 1 < target.oldest) return .{ .events = out[0..0], .gap = true };

        var count: usize = 0;
        var seq = cursor + 1;
        while (seq <= target.newest and count < out.len) : (seq += 1) {
            const entry = &target.entries[@intCast((seq - 1) % feed_ring)];
            if (entry.seq != seq) continue;

            out[count] = .{
                .seq = seq,
                .rev = entry.rev,
                .kind = entry.kind[0..entry.kind_len],
                .payload = entry.payload[0..entry.payload_len],
            };
            count += 1;
        }

        return .{ .events = out[0..count], .gap = false };
    }

    fn findTenant(self: *Feed, id: []const u8) ?*Tenant {
        for (&self.tenants) |*slot| {
            if (slot.id_len != 0 and std.mem.eql(u8, slot.id[0..slot.id_len], id)) return slot;
        }

        const clipped = @min(id.len, 64);
        for (&self.tenants) |*slot| {
            if (slot.id_len == 0) {
                @memcpy(slot.id[0..clipped], id[0..clipped]);
                slot.id_len = clipped;

                return slot;
            }
        }

        return null;
    }
};

// --------------------------------------------------------- //
// The worker and the dispatcher

/// Leases one job at a time and runs it. `runOnce` is the whole step, so a test drives it exactly as many
/// times as a scenario needs; `loop` is the thread the demo runs.
pub const Worker = struct {
    store: *Store,
    id: []const u8,
    lease_ms: i64 = 4_000,
    /// How long a job pretends to take. The slice's subject is the durable path, not the payload.
    work_ms: u64 = 20,
    done: u64 = 0,

    /// Completions this worker dropped because another attempt owned the job by then.
    lost: u64 = 0,

    pub fn runOnce(self: *Worker) !bool {
        const lease = (try self.store.lease(self.lease_ms)) orelse return false;

        // The work happens outside any transaction: a transaction held open across it would make the lease
        // the database's rather than this worker's, and a crash would block the rows it touched.
        self.store.io.sleep(.fromMilliseconds(@intCast(self.work_ms)), .awake) catch {};

        var result_buf: [64]u8 = undefined;
        const result = try std.fmt.bufPrint(&result_buf, "done by {s}", .{self.id});

        switch (try self.store.complete(lease, result)) {
            .committed => self.done += 1,
            .not_owner => {
                // The lease expired while this worker was working and someone else took the job. The result is
                // dropped: the attempt that owns it now decides what the task becomes.
                self.lost += 1;
            },
        }

        return true;
    }

    pub fn loop(self: *Worker, stop: *std.atomic.Value(bool), poll_ms: u64) void {
        while (!stop.load(.acquire)) {
            const worked = self.runOnce() catch |err| {
                std.debug.print("[tasks] worker {s}: {s}\n", .{ self.id, @errorName(err) });
                self.store.io.sleep(.fromMilliseconds(@intCast(poll_ms)), .awake) catch {};

                continue;
            };

            if (!worked) self.store.io.sleep(.fromMilliseconds(@intCast(poll_ms)), .awake) catch {};
            self.store.reset();
        }
    }
};

/// Publishes outbox rows into the feed, marking each published only after the feed took it.
pub const Dispatcher = struct {
    store: *Store,
    feed: *Feed,
    batch: usize = 32,
    published: u64 = 0,

    /// Returns how many rows were published this time.
    pub fn runOnce(self: *Dispatcher) !usize {
        const events = try self.store.pendingOutbox(self.batch);
        defer self.store.reset();

        for (events) |event| {
            try self.feed.publish(event.tenant_id, event.rev, event.kind, event.payload);
            try self.store.markPublished(event.id);
            self.published += 1;
        }

        return events.len;
    }

    pub fn loop(self: *Dispatcher, stop: *std.atomic.Value(bool), poll_ms: u64) void {
        while (!stop.load(.acquire)) {
            const count = self.runOnce() catch |err| {
                std.debug.print("[tasks] dispatcher: {s}\n", .{@errorName(err)});
                self.store.io.sleep(.fromMilliseconds(@intCast(poll_ms)), .awake) catch {};

                continue;
            };

            if (count == 0) self.store.io.sleep(.fromMilliseconds(@intCast(poll_ms)), .awake) catch {};
        }
    }
};

// --------------------------------------------------------- //
// Tests over the parts that need no database

test "zix durable tasks: a view applies a revision once and ignores a replay" {
    var applied: i64 = 0;

    try std.testing.expect(applyRevision(&applied, 1));
    try std.testing.expect(applyRevision(&applied, 2));
    try std.testing.expectEqual(@as(i64, 2), applied);

    // The same revision again (a dispatcher crash between publish and mark) and an older one (a replayed
    // outbox row) both leave the view exactly where it was.
    try std.testing.expect(!applyRevision(&applied, 2));
    try std.testing.expect(!applyRevision(&applied, 1));
    try std.testing.expectEqual(@as(i64, 2), applied);
}

test "zix durable tasks: the feed drops a duplicate revision, drains in order, and reports a gap" {
    var feed = Feed.init(std.testing.io);
    try feed.publish("acme", 1, "task_created", "{\"rev\":1}");
    try feed.publish("acme", 2, "task_running", "{\"rev\":2}");
    try feed.publish("acme", 2, "task_running", "{\"rev\":2}"); // a dispatcher replay
    try feed.publish("globex", 1, "task_created", "{\"rev\":1}");

    var buf: [8]Feed.Published = undefined;
    const first = feed.drain("acme", 0, &buf);
    try std.testing.expectEqual(@as(usize, 2), first.events.len);
    try std.testing.expectEqual(@as(i64, 1), first.events[0].rev);
    try std.testing.expectEqual(@as(i64, 2), first.events[1].rev);
    try std.testing.expectEqualStrings("task_running", first.events[1].kind);

    // Another tenant's ring is its own.
    const other = feed.drain("globex", 0, &buf);
    try std.testing.expectEqual(@as(usize, 1), other.events.len);

    // A cursor that is already current sees nothing.
    const none = feed.drain("acme", first.events[1].seq, &buf);
    try std.testing.expectEqual(@as(usize, 0), none.events.len);

    // Past the ring bound the view is told to re-snapshot instead of being handed a hole.
    var i: usize = 0;
    while (i < feed_ring + 4) : (i += 1) try feed.publish("acme", @intCast(100 + i), "task_completed", "{}");
    const gap = feed.drain("acme", 2, &buf);
    try std.testing.expect(gap.gap);
    try std.testing.expectEqual(@as(usize, 0), gap.events.len);
}

test "zix durable tasks: an event payload escapes what the caller typed" {
    var buf: [512]u8 = undefined;
    const payload = try renderTaskEvent(&buf, 7, "task_created", 3, "quote \" and \\ and \n", "queued", 0, null);

    try std.testing.expectEqualStrings(
        "{\"kind\":\"task_created\",\"rev\":7,\"task\":{\"id\":3,\"title\":\"quote \\\" and \\\\ and \\\\n\",\"state\":\"queued\",\"attempts\":0,\"result\":null}}",
        payload,
    );
}
