# LLD: zix.Logger (internal)

Internal data structures and algorithms for the logger implementation.

---

## Data Structures

```zig
pub const Logger = struct {
    config: Config,
    allocator: std.mem.Allocator,
    locked: std.atomic.Value(bool),   // spinlock

    file_fd: std.posix.fd_t,          // -1 when no file is open
    current_date: [10]u8,             // "YYYY-MM-DD" of currently open file
    file_seq: u32,                    // sequence counter for file rotation
    line_count: u64,                  // lines written to current file
    file_suspended: bool,             // true after unrecoverable file I/O error

    file_sink: Sink,                  // two 64 KB buffers for the log file (empty if save_path == "")
    console_sink: Sink,               // two 64 KB buffers for the console (empty if console == .OFF)
    flusher: Flusher,                 // the background thread that owns every write
    flusher_unavailable: bool,        // true when the thread could not spawn, so drains run inline
};

pub const Sink = struct {
    bufs: [2][]u8,                    // producers fill one, the flush thread writes the other
    active: u1,                       // which buffer producers append into
    fill: usize,                      // bytes in bufs[active]
    pending: usize,                   // bytes in bufs[active ^ 1] awaiting a write, 0 = none in flight
    stalls: u64,                      // times a producer waited because both buffers were spoken for
    lines: u64,                       // records appended
    writes: u64,                      // batches written out
};
```

---

## Write Path

All log methods follow the same pattern:

1. Derive level (caller-supplied for `system()`, computed for all others).
2. Check `consoleActive(level)` and `fileActive(level)`: early exit if both inactive.
3. Format `line` into a 4096-byte stack buffer via `std.fmt.bufPrint`.
4. `spinLock()`.
5. If console active: `rawWrite(STDERR_FILENO, line + "\n")`.
6. If file active: `ensureFileLocked(&ts.date)` then `writeLineLocked(line)`.
7. `spinUnlock()`.

All formatting happens before the lock is acquired. Lock hold time is proportional to `memcpy` into the write buffer, typically a few hundred nanoseconds.

---

## rawWrite

Direct POSIX `write` syscall in a retry loop until all bytes are sent or an error is returned:

```zig
fn rawWrite(fd: std.posix.fd_t, data: []const u8) ?std.posix.E {
    var rem = data;
    while (rem.len > 0) {
        const rc = std.posix.system.write(fd, rem.ptr, rem.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => { rem = rem[@intCast(rc)..]; },
            else => return,
        }
    }
}
```

No `std.Io`: safe from any OS thread including threads spawned via `std.Thread.spawn`. This is intentional: `std.debug.print` routes through `std.Options.debug_io` (a global singleton) and races with the test runner IPC on background threads. `rawWrite` to STDERR_FILENO has no such global state.

---

## Spinlock

CAS loop on `locked: std.atomic.Value(bool)`:
- Lock: `cmpxchgWeak(false, true, .acquire, .monotonic)`, retries with `spinLoopHint()` on failure.
- Unlock: `store(false, .release)`.
- `spinLoopHint()` maps to `pause`/`yield` on x86/ARM.

The spinlock is correct under high concurrency because the lock is held for a `memcpy` into the active buffer and nothing else. It is never held across a syscall: the flush thread releases it before writing and takes it back afterwards, so a slow disk cannot stall a producer.

---

## Write Buffer

Allocated by `init()` per enabled destination, two buffers each (`write_buf_size`, 64 KB by default, raised to fit one whole record if configured smaller).

`appendLocked(sink, kind, line)`:
1. `sink.tryAppend(line)`: `@memcpy` the record and a trailing `'\n'` into `bufs[active]` when there is room, and return.
2. No room and `pending != 0`: the flush thread still owns the other buffer. Count a stall and wait for it, releasing the lock while waiting.
3. `sink.swap()`: hand `bufs[active]` over as `pending` and start filling the other one.
4. Retry the append, which now fits.

The producer never issues a syscall. Writes happen in two places:

- `pumpSinkLocked` on the flush thread, which releases the lock across the write. This is the normal path.
- `drainSinkLocked` on the calling thread, holding the lock throughout. This is the synchronous path.

The synchronous path runs on:
- An `ERROR` record, so a crash cannot swallow the record that explains it.
- Date rollover or sequence rotation (inside `ensureFileLocked`), which needs the descriptor to itself.
- Explicit `logger.flush()`.
- `logger.deinit()`, after the flush thread has been stopped and joined.

The flush thread naps 20 us between passes while a burst may still be running, stretching to 2 ms once it has been quiet for 64 passes. A trickle of records is written at least every 2 ms, which is what bounds the syscall rate for a logger that never fills a buffer.

---

## File Rotation

`ensureFileLocked(date: *const [10]u8)` is called before every file write:

```
if file_suspended: return

if file_fd < 0:
    open initial file for *date*
    return

if date changed:
    flush + close
    reset seq=0, line_count=0
    open new file in new date directory
    return

if line_count >= max_lines:
    if seq >= 999_999:
        flush + close
        file_suspended = true
        rawWrite(STDERR, warning)
        return
    flush + close
    seq += 1, line_count = 0
    open new file (same date directory)
```

File path: `<save_path>/<YYYY-MM-DD>/<save_file>-<NNNNNN>.log` (6-digit zero-padded sequence).

The date directory is created with `mkdirat` at each open. `mkdirat` is idempotent: "already exists" is not an error at the system call level.

---

## Timestamp

`getTimestamp()` calls `clock_gettime(.REALTIME)` via `std.os.linux.clock_gettime` (direct syscall). Calendar fields are computed using `std.time.epoch`. Output:
- `date`: `"YYYY-MM-DD"` (10 bytes, stack)
- `time`: `"HH:MM:SS.mmm"` (12 bytes, stack)

Milliseconds come from `nsec / 1_000_000`. No allocation, no `std.Io`.

---

## consoleActive / fileActive

```zig
fn consoleActive(self, level) bool:
    .OFF           -> false
    .DEBUG_ONLY    -> comptime mode == .Debug and level >= console_min_level
    .ALWAYS        -> level >= console_min_level

fn fileActive(self, level) bool:
    save_path.len > 0
    and not file_suspended
    and level >= save_min_level
```

Both are checked before any formatting to short-circuit no-op calls at zero cost.

---

###### end of lld-logger
