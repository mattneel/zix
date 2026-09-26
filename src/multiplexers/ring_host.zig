//! Where a .URING worker loop gets its ring, and how it waits on it.
//!
//! By default each worker loop runs on an OS thread of its own and owns its ring. When the
//! server's `io` is Zig++'s `std.Io.Threadz` on Linux, each loop runs instead as a task pinned
//! to one Threadz worker, on that worker's ring: the loop parks when it has nothing to do, and
//! the worker runs its other tasks meanwhile. Zig 0.16 and upstream Zig have no Threadz, and
//! there the loops always own their rings.
//!
//! A loop on a lent ring shares it with the worker, so every SQE it queues carries
//! `ring.zig`'s owner bit in user_data (packUserData sets it), which is how the worker tells
//! the loop's completions from its own.

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const IoUring = linux.IoUring;

/// Zig++'s std.Io.Threadz where it lends worker rings, `void` everywhere else.
pub const Threadz = blk: {
    if (builtin.os.tag != .linux) break :blk void;
    if (!@hasDecl(std.Io, "Threadz")) break :blk void;
    const T = std.Io.Threadz;
    if (T == void) break :blk void;
    if (!@hasDecl(T, "acquireRing")) break :blk void;
    break :blk T;
};

/// The user_data bit that marks a completion as the loop's on a lent ring.
pub const owner_bit: u64 = 1 << 63;

comptime {
    if (Threadz != void) std.debug.assert(Threadz.ring_owner_bit == owner_bit);
}

/// The Threadz instance behind `io`, or null when `io` is any other implementation.
pub fn threadzOf(io: std.Io) ?*Threadz {
    if (Threadz == void) return null;
    return Threadz.fromIo(io);
}

/// A worker loop's ring: one of its own, or the one its Threadz worker lends it.
pub const LoopRing = struct {
    ring: *IoUring,
    lent: Lent,

    const Lent = if (Threadz == void) void else ?Threadz.Ring;

    /// Borrows the calling task's worker ring when `io` is a Threadz. Otherwise sets `own` up
    /// with `initOwn`; `own` must then outlive the loop.
    pub fn init(io: std.Io, own: *IoUring, comptime initOwn: anytype) !LoopRing {
        if (Threadz != void) {
            if (threadzOf(io)) |tz| {
                const lent = try tz.acquireRing();
                return .{ .ring = lent.uring(), .lent = lent };
            }
        }
        own.* = try initOwn();
        return .{ .ring = own, .lent = if (Threadz == void) {} else null };
    }

    /// Gives a lent ring back, or tears an own ring down.
    pub fn deinit(lr: LoopRing) void {
        if (Threadz != void) {
            if (lr.lent) |lent| return lent.release();
        }
        lr.ring.deinit();
    }

    /// Whether the ring is the worker's. The loop then parks in `wait` rather than blocking
    /// in the kernel, and a bounded wait for a batch is not available.
    pub fn isLent(lr: LoopRing) bool {
        if (Threadz == void) return false;
        return lr.lent != null;
    }

    /// Submits the queued SQEs, waits for at least one of the loop's completions, and copies
    /// up to `cqes.len` of them.
    pub fn wait(lr: LoopRing, cqes: []linux.io_uring_cqe) !u32 {
        if (Threadz != void) {
            if (lr.lent) |lent| return @intCast(lent.waitCqes(cqes));
        }
        _ = try lr.ring.submit_and_wait(1);
        return lr.ring.copy_cqes(cqes, 0);
    }

    /// Copies the loop's completions that have arrived, up to `cqes.len`, without waiting.
    pub fn copy(lr: LoopRing, cqes: []linux.io_uring_cqe) !u32 {
        if (Threadz != void) {
            if (lr.lent) |lent| return @intCast(lent.copyCqes(cqes));
        }
        return lr.ring.copy_cqes(cqes, 0);
    }
};

/// The worker loops of one server: an OS thread each, or a task pinned to each Threadz worker
/// when the server's `io` is a Threadz.
pub const Workers = struct {
    io: std.Io,
    threadz: ?*Threadz,
    threads: []std.Thread,
    group: Group,
    spawned: usize,

    const Group = if (Threadz == void) void else std.Io.Group;

    /// How many loops a server on `io` runs when it wants `wanted`: no more than a Threadz has
    /// workers, since each loop is pinned to one.
    pub fn count(io: std.Io, wanted: usize) usize {
        if (Threadz == void) return wanted;
        const tz = threadzOf(io) orelse return wanted;
        return @min(wanted, tz.workerLimit());
    }

    pub fn init(io: std.Io, loops: usize) !Workers {
        return .{
            .io = io,
            .threadz = threadzOf(io),
            .threads = try std.heap.smp_allocator.alloc(std.Thread, loops),
            .group = if (Threadz == void) {} else .init,
            .spawned = 0,
        };
    }

    pub fn deinit(ws: *Workers) void {
        std.heap.smp_allocator.free(ws.threads);
    }

    /// Starts the next loop: loop `ws.spawned`, pinned to the Threadz worker of that index.
    pub fn spawn(
        ws: *Workers,
        stack_size: usize,
        comptime function: anytype,
        args: std.meta.ArgsTuple(@TypeOf(function)),
    ) !void {
        const index = ws.spawned;
        if (Threadz != void) {
            if (ws.threadz) |tz| {
                try tz.groupConcurrentWith(&ws.group, .{
                    .stack_size = stack_size,
                    .affinity = .{ .pinned = @intCast(index) },
                }, function, args);
                ws.spawned += 1;
                return;
            }
        }
        ws.threads[index] = try std.Thread.spawn(.{ .stack_size = stack_size }, function, args);
        ws.spawned += 1;
    }

    /// Returns once every loop started has returned.
    pub fn join(ws: *Workers) void {
        if (Threadz != void) {
            if (ws.threadz != null) {
                ws.group.await(ws.io) catch {};
                return;
            }
        }
        for (ws.threads[0..ws.spawned]) |thread| thread.join();
    }
};
