# Concurrency Models: zix

Three dispatch models for HTTP and raw TCP. Select via `config.dispatch_model` (`DispatchModel` enum) in `HttpServerConfig` or `TcpServerConfig`. Required: set it explicitly (no default).

---

## DispatchModel

```zig
pub const DispatchModel = enum(u8) {
    ASYNC = 0, // single accept, io.async() dispatch, the only portable model
    EPOLL = 1, // shared-nothing epoll workers, Linux-only
    URING = 2, // shared-nothing io_uring workers, Linux-only
};
```

Defined once in `src/tcp/config.zig`. Re-exported by `src/tcp/http/config.zig` (for `zix.Http`) and imported by `src/tcp/http2/grpc/config.zig` (for `zix.Grpc`). All three values are present in every config.

`.EPOLL = 1` is Linux-only. `zix.Http` (HTTP/1), `zix.Http1`, `zix.Http2`, `zix.Grpc`, `zix.Fix`, and `zix.Tcp` implement it natively on Linux. `.URING = 2` is also Linux-only and native in `zix.Http1`, `zix.Http`, `zix.Http2`, `zix.Grpc`, and `zix.Fix`. The `zix.Tcp` per-connection handler folds to `.EPOLL` (the `zix.Tcp` framed callback runs the ring natively). See the Dispatch Model Comparison table below.

Off Linux there is no silent downgrade: `run()` returns `error.ZixDispatchModelUnsupported` when the model is `.EPOLL` or `.URING`, so a caller never believes it got a model it did not (ADR-065). A portable caller picks the model per target at comptime:

```zig
const builtin = @import("builtin");

const DISPATCH_MODEL: zix.Http1.DispatchModel = if (builtin.os.tag == .linux) .URING else .ASYNC;
```

The gate is one shared predicate, `zix.utils.dispatch_support.isSupported`, that every engine's `run()` consults before it binds a listener or spawns a TLS thread. A rejected config therefore leaves nothing behind.

---

## .ASYNC: Single Accept, io.async() Dispatch

One accept thread dispatches each accepted connection as a concurrent task via `io.async()`
(non-blocking). The caller owns the `std.Io` backend. Best for low-latency workloads and
long-lived connections (SSE, WebSocket), and the only model available on every platform.

```
Main thread:
  bind -> listen
  loop:
    stream = accept(io)
    io.async(handleConnection, stream)   <- suspends, OS event loop schedules task

Handler tasks (one per active connection):
  handleConnection(stream)  // keep-alive loop until client closes
  task exits when connection closes
```

**When to use:**
- Any non-Linux target: `.EPOLL` and `.URING` are rejected there, so this is the model to pick.
- SSE and WebSocket: an open stream costs one task, not an event-loop worker slot.
- You need an explicit `concurrent_limit` (resource-constrained deployments).
- `dispatch_model = .ASYNC` in `HttpServerConfig`.
- `workers` is ignored (there is always exactly one accept thread).

**Example** (`examples/http_sse.zig`, `examples/http_websocket.zig`):
```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/events", .handler = eventsHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .ASYNC,
});
```

**Manual concurrency limit** (`examples/http_manual_concurrent.zig`):
```zig
var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{
    .concurrent_limit = std.Io.Limit.limited(4),
});
defer threaded.deinit();

var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = threaded.io(),
    .dispatch_model = .ASYNC,
});
```

---

## .EPOLL: Shared-Nothing epoll Event Loop (Linux-only)

Each worker owns a private `SO_REUSEPORT` listener and its own `epoll` instance. The kernel
distributes new connections across per-worker listeners. No shared queue, no cross-thread fd
handoff. Each worker accepts, registers, reads, and responds on its own connections without
touching any other worker's state.

**Why it exists:** `.ASYNC` pays a cross-thread wakeup cost on every accepted connection (via the
`io.async()` fiber scheduler), and only one thread accepts. Under very high connection counts
where connections are fast but many overlap, that single accept path and the scheduler hand-off
both become the bottleneck. With shared-nothing, every worker accepts directly on its own
listener and handles all I/O inline: no mutex, no condvar, no fd handoff.

```
Workers (workers, default cpu_count):
  resolve + listen on same port with SO_REUSEPORT
  epoll_create1
  epoll_ctl(ADD, listener_fd, EPOLLIN)        <- accept loop trigger

  event loop:
    epoll_wait(events, EPOLL_MAX_EVENTS)        <- Http: 1024, Http1: 4096
    for each event:
      if listener_fd:
        loop: fd = accept4(SOCK_CLOEXEC)
              setNoDelay(fd)
              epoll_ctl(ADD, fd, EPOLLIN | EPOLLRDHUP)
      else:   // connection fd
        if HUP or ERR or RDHUP:
          epoll_ctl(DEL, fd)
          close(fd)
        else:
          read, then serve every complete buffered request   <- on the worker, no fiber
          (Http: read to EAGAIN + processRequest, Http1: serveEpollConn)
          if keep-alive: stay registered (level-triggered, re-fires on next data)
          if close: epoll_ctl(DEL, fd) + close(fd)
```

Connections stay registered after each request. No explicit re-arm is needed: level-triggered
`EPOLLIN` re-fires whenever new data arrives. Idle keep-alive connections hold no thread and
occupy only one entry in the per-worker epoll set.

**When to use:**
- Linux production deployments of `zix.Http` or `zix.Http1` under high connection counts.
- Short-lived requests (REST, API) where a request pass finishes quickly and returns the
  worker to `epoll_wait`.
- You want to avoid `io.async()` fiber scheduler overhead entirely.
- `dispatch_model = .EPOLL` in `HttpServerConfig` or `Http1ServerConfig`.
- `workers` controls worker count (0 = cpu_count) on every engine.

**Example (`zix.Http`):**
```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .EPOLL,
    .workers        = 0, // 0 = cpu_count workers (default)
});
try server.run();
```

**Example (`zix.Grpc`):**
```zig
var server = zix.Grpc.Server.init(
    &[_]zix.Grpc.Route{
        .{ .path = "/helloworld.Greeter/SayHello", .handler = sayHello },
    },
    .{
        .io             = process.io,
        .dispatch_model = .EPOLL,
    },
);
try server.run();
```

**Cost and considerations:**

| Item | Detail |
| :- | :- |
| Platform | Linux only (`epoll_create1`, `epoll_wait`, `epoll_ctl`). Off Linux, `run()` returns `error.ZixDispatchModelUnsupported` after logging which model was rejected |
| Availability | `zix.Http` (HTTP/1), `zix.Http1`, `zix.Http2`, `zix.Grpc`, `zix.Fix`, and `zix.Tcp` implement natively on Linux |
| Accept model (`zix.Http`) | Each worker binds its own `SO_REUSEPORT` listener. The kernel distributes connections across workers: no shared accept queue |
| gRPC difference | `zix.Grpc` uses a multiplexed shared-nothing model: one worker drives many non-blocking h2 connections via a resumable state machine. See ADR-031 |
| `workers` field | Controls the worker count on every engine (0 = cpu_count) |
| Keep-alive idle cost | Near-zero: idle sockets sit in the epoll set without holding any thread |
| Debugging | `strace` or `perf` will show `epoll_wait` dominating idle time, this is expected and correct |

**When NOT to use:**
- SSE or WebSocket via `zix.Http`: connections stay active and data flows continuously, blocking reads will park the worker. Prefer `.ASYNC`.
- Non-Linux targets: `run()` rejects the model, so pick `.ASYNC` explicitly.
- When connection count is low (< a few hundred): the simpler `.ASYNC` model will perform the same or better with less complexity.

---

## .URING: Shared-Nothing io_uring Event Loop (Linux-only)

`.URING` is the completion-based sibling of `.EPOLL`: the same shared-nothing, thread-per-core topology (one `SO_REUSEPORT` listener and one ring per worker, no shared queue, no cross-thread fd handoff), but accepts, reads, and writes are submitted as io_uring SQEs and reaped as CQEs instead of waiting on `epoll_wait` readiness. Most syscall transitions are batched into the ring (ADR-037 Phase 4).

- Native engines: `zix.Http1`, `zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Fix`. The `zix.Tcp` per-connection handler has no native ring and folds to `.EPOLL` (the `zix.Tcp` framed callback does run the ring). Off Linux, `run()` returns `error.ZixDispatchModelUnsupported`.
- `workers` sizes the worker count on every engine, exactly as `.EPOLL`.
- On loopback `.URING` matches `.EPOLL` on throughput and total CPU, winning mainly on per-request cache locality. On a many-core box the ring close (`prep_close`, ADR-041) keeps the worker reaping completions through connection churn instead of blocking in a synchronous `close`, so `.URING` reaches parity or better than `.EPOLL` on every measured workload at a fraction of the memory.
- When io_uring itself is unavailable on the host (an old kernel, a low `RLIMIT_MEMLOCK`, a sandbox), the engine folds to the `.EPOLL` loop with a logged notice. That is a runtime capability gap on a supported platform, not the platform rejection above.
- Same "when NOT to use" as `.EPOLL`: SSE / WebSocket on `zix.Http`, low connection counts, non-Linux targets.

---

## Why Dispatch Loops Are Per-Engine

Each engine keeps its own dispatch loop (`.ASYNC` / `.EPOLL` / `.URING`) in its own `server.zig` rather than behind one generic multiplexer. The split is deliberate and is itself the optimization: per-engine ownership lets each engine tune its hot path for its own connection shape.

The clearest example is the `.EPOLL` connection table, which looks like the most duplicated piece but is in fact specialized per engine:

| Engine | Connection table | Allocation | Why |
| :- | :- | :- | :- |
| `zix.Http1` | contiguous demand-paged slab | no per-accept heap call | buffers carved from one `MAX_FD * buf_size` slab, empty slot is `buf.len == 0` |
| `zix.Grpc` | per-connection heap pointer | one heap object per accept | the connection carries resumable h2 + HPACK state, too large and variable for one fixed slab cell |
| `zix.Fix` | per-connection heap pointer | one heap object per accept | the connection carries FIX session state (sequence numbers, heartbeat timing) |

A single generic loop would force one connection-table shape on every engine (erasing the `zix.Http1` slab win) and add a callback-per-event indirection on the accept / recv / send path, which is the hottest path in the library.

Only byte-identical primitives are shared, in `src/multiplexers/`. Today that is the `.URING` `user_data` codec (`ring.zig`): every io_uring engine must pack the same bits (an fd-keyed slot guarded by a generation in one layout), so the codec is hoisted out while the ring loop and slot table stay per-engine. The rule: share primitives that must match, keep dispatch loops per-engine. See ADR-042.

---

## Thread Count Reference

| Field | Default | Meaning |
| :- | :- | :- |
| `dispatch_model = .ASYNC` | single accept, io.async() | 1 accept thread, io.async() per connection |
| `dispatch_model = .EPOLL` | shared-nothing epoll workers | one worker per core, each with its own listener and epoll instance |
| `dispatch_model = .URING` | shared-nothing io_uring workers | one worker per core, each with its own listener and ring |
| `workers = 0` | cpu_count threads | worker count for `.EPOLL` and `.URING` on every engine, ignored by `.ASYNC` |
| `workers = N` | N threads | explicit worker count for `.EPOLL` and `.URING`, ignored by `.ASYNC` |

---

## Dispatch Model Comparison

| | `.ASYNC` | `.EPOLL` | `.URING` |
| :- | :- | :- | :- |
| Accept threads | 1 | cpu_count (or N) | cpu_count (or N) |
| Connection dispatch | `io.async()` task | per-worker epoll, level-triggered | per-worker io_uring, completion-based |
| Scheduler overhead | yes (condvar wakeup) | no (epoll, Linux only) | no (ring, Linux only) |
| `SO_REUSEPORT` | no | yes (per-worker listener) | yes (per-worker listener) |
| `workers` field used | no (ignored) | yes | yes |
| Platform | all | Linux only | Linux only |
| Best for | SSE, WebSocket, low latency, non-Linux | high-throughput HTTP/1 or gRPC on Linux | same as `.EPOLL`, lower memory under churn |
| Available in | Http, Http1, Http2, Grpc, Tcp, Fix | Http, Http1, Http2, Grpc, Fix, Tcp | Http, Http1, Http2, Grpc, Fix (Tcp folds to `.EPOLL`) |

---

## Protocol Applicability

| Protocol | `.ASYNC` | `.EPOLL` | `.URING` |
| :- | :- | :- | :- |
| HTTP | yes | yes, Linux-only | yes, Linux-only |
| SSE | yes, preferred | n/a | n/a |
| WebSocket | yes, preferred | n/a | n/a |
| HTTP/2 (h2c) | yes | yes, Linux-only | yes, Linux-only |
| HTTP/3 (QUIC) | yes (single worker) | yes, Linux-only | yes, Linux-only |
| gRPC (h2c) | yes | yes, Linux-only | yes, Linux-only |
| TCP (raw stream) | yes | yes, Linux-only | framed callback only, per-connection handler folds to `.EPOLL` |
| FIX 4.x | yes | yes, Linux-only | yes, Linux-only |
| UDP (raw) | yes (single worker) | yes, Linux-only | yes, Linux-only |
| WebRTC | yes (single worker) | yes, Linux-only | yes, Linux-only |
| UDS (stream) | yes (io.concurrent() per connection) | n/a | n/a |

Http3 under `.EPOLL` / `.URING` runs real per-core workers (cross-core CID steering for mid-connection migration is v2, ADR-049 phase 3).

WebRTC under `.EPOLL` / `.URING` also runs real per-core workers, but with no CPU steering knob at all: a peer is its 4-tuple, so steering by receiving CPU could split one session across two workers mid-handshake (ADR-067).

---

## Cross-Platform Backends (planned)

Each model names two things at once: a concurrency shape (single or multi-core) and, for the per-core models, an I/O backend. The backend is OS-specific. The contract: the OS swaps the backend, never the single-or-multi nature of the model.

| Model | Core behavior | OS | Status |
| :- | :- | :- | :- |
| `.ASYNC` | single | all | now |
| `.EPOLL` | multi (per-core) | Linux | now |
| `.URING` | multi (per-core) | Linux | now |
| `.KQUEUE` | multi (per-core) | macOS / BSD | planned |
| `.IOCP` | multi (per-core) | Windows | planned |

`.EPOLL`, `.KQUEUE`, and `.IOCP` are the same multi-core per-core idea, one per operating system. Each lives in its own `dispatch/<model>.zig` file, so the folder is self-documenting: open it, see every model, each header line states its core behavior and OS.

Like `.EPOLL` and `.URING` today, these backends are family-wide: every engine that selects a `DispatchModel` (`zix.Http`, `zix.Http1`, `zix.Http2`, `zix.Http3`, `zix.Webrtc`, `zix.Grpc`, `zix.Tcp`, `zix.Fix`, `zix.Udp`) gets its platform's backend through the same enum.

There is no auto-select keyword. Portable code either picks `.ASYNC` outright or names the exact backend with a one-line comptime switch on `builtin.os.tag`. Two mismatches are handled differently:

- A backend that cannot run on the target OS (for example `.EPOLL` off Linux) is rejected by `run()` with `error.ZixDispatchModelUnsupported`. This is a config error, reported rather than worked around (ADR-065).
- A backend that exists but the machine cannot use at runtime (for example `.URING` on an old kernel) folds to a working model with a logged notice. This is a capability gap on a platform that does support the model.

Until the macOS and Windows backends land, `.ASYNC` is the model for every non-Linux target. `.KQUEUE` and `.IOCP` are reserved names only, not yet implemented and not present as source files. They also need a maintainer before they can land: the models zix keeps are the models it can maintain, which is why `.POOL` and `.MIXED` were dropped in ADR-065. See ADR-050 and ADR-065.

---

## Channel

`zix.Channel` is **not** a concurrency model. It is an in-process message-passing primitive
that works alongside all three dispatch models. A Channel connects producer and consumer tasks
(OS threads or `io.async()` fibers) within the same process. It does not cross a network or
process boundary.

```
Producer task --> [ Channel(T) ring buffer ] --> Consumer task
```

All three dispatch models can spawn `io.async()` tasks or OS threads that communicate through
a Channel. The Channel itself is independent of which dispatch model is in use.

| Property | Channel |
| :- | :- |
| Crossing process/network boundary | no (in-process only) |
| Works with `io.async()` tasks | yes, uses `std.Io.Mutex` + `std.Io.Condition` (fiber-aware) |
| Works with OS threads | yes: each thread needs its own `std.Io` from `std.Io.Threaded` |
| Replaces dispatch model | no (orthogonal) |

Status: Implemented. See ADR-017 and [`docs/hld-channel-en.md`](hld-channel-en.md).

---

###### end of concurrency
