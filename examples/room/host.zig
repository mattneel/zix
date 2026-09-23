//! The native half of gkz's host seam: the room, driven in-process.
//!
//! gkz runs this same room compiled to wasm inside a Cloudflare Durable Object (`gkz/host/src/index.js`) and
//! talks to it over WebSockets. SPEC §14 puts that shell outside the kernel — "sockets, framing over the
//! network, room routing and hibernation live above this, in the host" — so a second host is a second
//! implementation of the same job, not a second room. This is that job with the transport removed: create or
//! restore the room, seat participants, append the durable log, and hand out what the last confirmed tick
//! produced.
//!
//! The acceptance property is gkz's own and it is the only one that matters here: a session driven through
//! this host must export a run log that replays natively to the same per-tick digests. gkz's `replay` command
//! is that check — it rebuilds from the seed and the inputs alone and ignores every snapshot in the log, so a
//! host cannot certify itself by shipping its own claim about its state.
//!
//! One room per process. The room's state is module-level, exactly as it is in the wasm instance a Durable
//! Object owns, so a second timeline is a second process — which is gkz's own model (§13: a sim is one OS
//! process, and a crash is a repro).

const std = @import("std");

// --- the room's ABI ---------------------------------------------------------------------------------
//
// The room is a module with an exported interface — `export fn`, not `pub fn` — because its primary consumer
// is the wasm instance a Durable Object owns. A native host links the same symbols, so the seam is the same
// one it is over there: an ABI, not a Zig import. Everything below is the authoritative half; the client half
// (`cl_*`) belongs to the browser's instance of the same module.

extern fn srv_init(seed: u32) u32;
extern fn srv_set_cadence(interval: u32) void;
extern fn srv_join(source: u32) u32;
extern fn srv_leave(source: u32) u32;
extern fn srv_is_member(source: u32) u32;
extern fn srv_action(source: u32, dx: i32, dy: i32) u32;
extern fn srv_submit_at(source: u32, tick: u32, dx: i32, dy: i32) u32;
extern fn srv_pump() u32;
extern fn srv_idle_tick() u32;
extern fn srv_open_next() u32;
extern fn srv_open_tick() u32;
extern fn srv_tick() u32;
extern fn srv_digest() u64;
extern fn srv_members() u32;
extern fn srv_horizon() u32;
extern fn srv_owed(source: u32) u32;
extern fn srv_log_ptr() [*]u8;
extern fn srv_log_len() u32;
extern fn srv_log_clear() void;
extern fn srv_bcast_ptr() [*]u8;
extern fn srv_bcast_len() u32;
extern fn srv_bcast_clear() void;
extern fn srv_restore_from_log(len: u32) u32;
extern fn in_reserve(len: u32) ?[*]u8;

/// Concurrent participants one room admits; the room's sequencer is sized for 32 sources.
pub const max_sources: u32 = 32;

/// Snapshot cadence in ticks. gkz's Cloudflare host settled on 1024 on measured wake cost
/// (`gkz/docs/measured/host-shell.md`); it is the interval the log header carries, not a host preference.
pub const default_snapshot_interval: u32 = 1024;

/// Run-log framing (`gkz/src/net/runlog.zig`): a 39-byte header, then `u8 kind | u32 len | payload`.
pub const log_header_bytes: usize = 39;

/// Record kinds. `input` is the stream every participant receives; `snapshot` is world bytes and never
/// leaves the host.
pub const kind_input: u8 = 1;
pub const kind_snapshot: u8 = 2;

/// A room code becomes a seed: FNV-1a over the code, the same function gkz's host uses, so the same room
/// name is the same starting world on any host.
pub fn seedOf(code: []const u8) u32 {
    var h: u32 = 0x811c9dc5;
    for (code) |ch| {
        h ^= ch;
        h = h *% 0x01000193;
    }

    return h;
}

/// INPUT records only, appended to a caller-owned list: the backlog a joining participant is handed, and the
/// stream the host serves it from. Same walk as `inputRecordsOnly`, without the allocation, because a pull
/// happens far more often than a join.
pub fn filterInputs(gpa: std.mem.Allocator, run_log: []const u8, out: *std.ArrayList(u8)) !void {
    var p: usize = log_header_bytes;
    while (p + 5 <= run_log.len) {
        const kind = run_log[p];
        const len = std.mem.readInt(u32, run_log[p + 1 ..][0..4], .little);
        if (p + 5 + @as(usize, len) > run_log.len) break;
        if (kind == kind_input) try out.appendSlice(gpa, run_log[p .. p + 5 + @as(usize, len)]);
        p += 5 + @as(usize, len);
    }
}

/// INPUT records only: the backlog a joining participant is handed. A SNAPSHOT record never reaches a socket
/// — `cl_apply` refuses one anyway, and this is the layer that makes "world bytes were never on the wire" a
/// property of the code's shape rather than a rule someone has to remember.
///
/// Note:
/// - An unknown record kind is skipped rather than refused: the format is built to grow (`runlog.zig`'s
///   `scan` does the same), and a torn tail simply ends the walk at the last whole record.
pub fn inputRecordsOnly(gpa: std.mem.Allocator, log: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var p: usize = log_header_bytes;
    while (p + 5 <= log.len) {
        const kind = log[p];
        const len = std.mem.readInt(u32, log[p + 1 ..][0..4], .little);
        if (p + 5 + @as(usize, len) > log.len) break;
        if (kind == kind_input) try out.appendSlice(gpa, log[p .. p + 5 + @as(usize, len)]);
        p += 5 + @as(usize, len);
    }

    return out.toOwnedSlice(gpa);
}

/// One room, as its host sees it: the durable log it appends to, and the settings the log header carries.
pub const Host = struct {
    gpa: std.mem.Allocator,
    code: []const u8,
    seed: u32,
    cadence: u32 = default_snapshot_interval,
    /// The durable run log: what replay reads and what a restart restores from. Grown by `appendLog`.
    log: std.ArrayList(u8) = .empty,
    /// The last broadcast, copied out of the room so the caller can hold it past the next drain.
    bcast: std.ArrayList(u8) = .empty,

    pub fn init(gpa: std.mem.Allocator, code: []const u8) Host {
        return .{ .gpa = gpa, .code = code, .seed = seedOf(code) };
    }

    pub fn deinit(self: *Host) void {
        self.log.deinit(self.gpa);
        self.bcast.deinit(self.gpa);
    }

    /// Seat the room: create it, or bring it back from the durable log.
    ///
    /// Mirrors gkz's `#ready()`. The fresh header a create produces is discarded when a log already exists,
    /// because the durable one is the truth; a room that cannot restore its own log is an error rather than a
    /// silent reset, since a room that quietly started over would report a tick and a digest that no replay
    /// could reproduce.
    pub fn ready(self: *Host) !void {
        if (srv_init(self.seed) == 0) return error.RoomInitFailed;
        srv_set_cadence(self.cadence);

        if (self.log.items.len == 0) {
            try self.appendLog(); // the header and the origin snapshot
            _ = srv_log_clear();
            _ = srv_bcast_clear();

            return;
        }

        _ = srv_log_clear(); // discard the fresh header: the durable log already has one
        _ = srv_bcast_clear();

        const inbox = in_reserve(@intCast(self.log.items.len)) orelse return error.InboxTooSmall;
        @memcpy(inbox[0..self.log.items.len], self.log.items);
        if (srv_restore_from_log(@intCast(self.log.items.len)) == 0) return error.RestoreFailed;
    }

    /// Move what the last confirmed tick produced into the durable log. The room's buffer and the log are the
    /// same bytes, so this is the whole persistence path.
    pub fn appendLog(self: *Host) !void {
        const drained = srv_log_ptr()[0..srv_log_len()];
        if (drained.len > 0) try self.log.appendSlice(self.gpa, drained);
        srv_log_clear();
    }

    /// Copy the broadcast out and clear the room's copy. The result is the host's until the next call, and it
    /// holds INPUT records only: there is no path from the snapshot half of the log to a participant.
    pub fn takeBroadcast(self: *Host) ![]const u8 {
        self.bcast.clearRetainingCapacity();
        try self.bcast.appendSlice(self.gpa, srv_bcast_ptr()[0..srv_bcast_len()]);
        srv_bcast_clear();

        return self.bcast.items;
    }

    /// The last confirmed tick's records, appended, and the wire bytes for every participant.
    pub fn flush(self: *Host) ![]const u8 {
        try self.appendLog();

        return self.takeBroadcast();
    }

    // --- participants ---------------------------------------------------------------------------

    /// The lowest free source id, or null when the room is full. Source ids are the routing key a participant
    /// keeps for the session, so a free id is reused rather than a counter being advanced.
    pub fn nextSource(self: *Host, taken: []const u32) ?u32 {
        _ = self;
        var source: u32 = 1;
        while (source <= max_sources) : (source += 1) {
            var used = false;
            for (taken) |t| {
                if (t == source) used = true;
            }
            if (!used) return source;
        }

        return null;
    }

    pub fn join(self: *Host, source: u32) u32 {
        _ = self;
        return srv_join(source);
    }

    pub fn leave(self: *Host, source: u32) u32 {
        _ = self;
        return srv_leave(source);
    }

    pub fn isMember(self: *Host, source: u32) bool {
        _ = self;
        return srv_is_member(source) != 0;
    }

    /// One participant's move, now: the reactive tick policy advances exactly one tick per accepted action.
    pub fn action(self: *Host, source: u32, dx: i32, dy: i32) u32 {
        _ = self;
        return srv_action(source, dx, dy);
    }

    /// One participant's move, for a chosen tick — the scheduled policy's submission, and the primitive a
    /// branch is built from: the same tick may be re-opened with a different input.
    pub fn submitAt(self: *Host, source: u32, at_tick: u32, dx: i32, dy: i32) u32 {
        _ = self;
        return srv_submit_at(source, at_tick, dx, dy);
    }

    /// Step whatever the last tick confirmed. A reactive room steps inside `action`; a scheduled one steps
    /// when its clock fires.
    pub fn pump(self: *Host) u32 {
        _ = self;
        return srv_pump();
    }

    /// Fill in an empty submission for every member that has not answered yet. Only a reactive room may call
    /// this: in a scheduled room the others are still answering, and filling empty makes their real
    /// submission arrive as a refused duplicate.
    pub fn idleTick(self: *Host) u32 {
        _ = self;
        return srv_idle_tick();
    }

    /// Open the next tick for submission, without stepping.
    pub fn openNext(self: *Host) u32 {
        _ = self;
        return srv_open_next();
    }

    // --- observations ---------------------------------------------------------------------------

    pub fn tick(self: *Host) u32 {
        _ = self;
        return srv_tick();
    }

    pub fn digest(self: *Host) u64 {
        _ = self;
        return srv_digest();
    }

    pub fn members(self: *Host) u32 {
        _ = self;
        return srv_members();
    }

    pub fn horizon(self: *Host) u32 {
        _ = self;
        return srv_horizon();
    }

    pub fn openTick(self: *Host) u32 {
        _ = self;
        return srv_open_tick();
    }

    pub fn owed(self: *Host, source: u32) u32 {
        _ = self;
        return srv_owed(source);
    }

    /// The replay: the whole run log, which replays natively from the seed and the inputs alone.
    pub fn runLog(self: *Host) []const u8 {
        return self.log.items;
    }
};
