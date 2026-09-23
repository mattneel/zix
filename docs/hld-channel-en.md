# HLD: zix.Channel

In-process typed message-passing channels.

---

## Status

Implemented. See ADR-017 for design rationale.

---

## Goals

- Typed in-process communication between concurrent tasks (`io.concurrent`) or OS threads.
- Blocking `send`/`recv` only. Non-blocking variants are deferred (see below).
- Buffered (capacity > 0) mode. Unbuffered (rendezvous) is not yet supported.
- Comptime-generic over the message type (no runtime type erasure).
- No cross-process or cross-network boundary (in-process only).
- Explicit over implicit: caller provides the allocator.

---

## Model

```
Sender task  -->  [ Channel(T) ring buffer ]  -->  Receiver task
               capacity N: blocks when full/empty
```

| Operation | Blocks when |
| :- | :- |
| `send(io, value)` | buffer is full |
| `recv(io)` | buffer is empty |

After `close(io)` no new sends are accepted. `recv()` drains any remaining items then returns `error.ZixClosed`.

---

## API

```zig
const MyChan = zix.Channel(u32);

// buffered, capacity 8
var ch = try MyChan.init(allocator, 8);
defer ch.deinit();

// send blocks when full, returns error.ZixClosed if ch.close() was called
try ch.send(io, 42);

// recv blocks when empty, drains remaining items after close(), then returns error.ZixClosed
const v = try ch.recv(io);  // v == 42

// close: no more sends, blocked receivers are unblocked and drain remaining items
ch.close(io);
```

Capacity must be > 0. `init()` asserts this at runtime. Unbuffered (rendezvous) is not yet supported.

---

## Source Layout

```
src/channel/
    channel.zig   // Channel(comptime T: type) generic implementation
    Channel.zig   // namespace aggregator (pub const Channel = channel.zig.Channel)
```

Export from `src/lib.zig`:
```zig
pub const Channel = @import("channel/Channel.zig").Channel;
```

---

## Concurrency Requirement

`Channel.send()` and `Channel.recv()` call `std.Io.Mutex.lockUncancelable(io)`. This requires an `io` that is valid on the calling thread. Each thread must have its own `std.Io` (e.g. from `std.Io.Threaded`).

```zig
var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{});
defer threaded.deinit();
const io = threaded.io();

var ch = try MyChan.init(std.heap.smp_allocator, 8);
defer ch.deinit();

const t = try std.Thread.spawn(.{}, workerFn, .{ &ch, io });
```

---

## Relation to Server Concurrency Models

Channel is orthogonal to the HTTP dispatch model (`.ASYNC`, `.EPOLL`, `.URING`). It does not replace or extend any model. It is an in-process coordination primitive that can be used alongside any of them.

```
.ASYNC / .EPOLL / .URING server
  handler task A  -->  Channel(Event)  -->  background task B
```

Integration example: `uds_http.zig` wires a UDS fetcher task into SSE handlers via a `Channel(u64)`:

```
[uds_server] /tmp/zix.sock [fetcher task] Channel(u64) [SSE handler]
                                                      \ [/data handler]
```

See [`docs/concurrency-en.md`](concurrency-en.md) for the Channel entry in the Protocol Applicability table.

---

## Examples

| File | Pattern |
| :- | :- |
| `examples/channel_basic.zig` | Producer/consumer: Channel(u32) with two OS threads |
| `examples/channel_worker_pool.zig` | Fan-out worker pool: one producer many consumers |
| `examples/channel_pipeline.zig` | Multi-stage pipeline: each stage runs at its own pace |
| `examples/channel_ipc_a.zig` | IPC process side A (writer), pair with ipc_b |
| `examples/channel_ipc_b.zig` | IPC process side B (reader), pair with ipc_a |
| `examples/uds_http.zig` | HTTP + UDS + Channel integration: full real-world pattern |

---

## Logger Integration

`Channel` has no server config struct, so there is no `logger` field. `Channel.init` prints a one-line init notice (`zix channel: init <T> cap=<N>`) to stderr in Debug builds only, suppressed in release and under the test runner (`builtin.is_test`, a print there would poison the test IPC). For real lifecycle logging use `logger.system()` manually:

```zig
// Uncomment to add logger (console only):
// var logger = try zix.Logger.init(std.heap.smp_allocator, .{
//     .console           = .ALWAYS,
//     .console_min_level = .INFO,
// });
// defer logger.deinit();

// Use logger.system(.INFO, "channel", "started", .{}) for manual lifecycle logging.
```

All Channel examples include this commented block ready to enable.

---

## Not Yet Implemented

| Feature | Note |
| :- | :- |
| Non-blocking `trySend`/`tryRecv` | Deferred. Blocking variants cover all current examples. |
| Unbuffered (rendezvous, capacity = 0) | `init()` asserts capacity > 0. Two-sided sync adds complexity. |
| `select` / multiplex over N channels | Deferred. Internal ring design does not preclude it. |
| `send` / `recv` with timeout | Not implementable: `std.Io.Condition` has no `timedWait` method. Blocked until stdlib adds it. |

---

###### end of hld-channel
