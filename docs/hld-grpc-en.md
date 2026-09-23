# gRPC h2c High-Level Design: zix.Grpc

## Goals

- gRPC h2c (HTTP/2 cleartext) server and client implemented without C FFI.
- All 4 RPC types: unary, server streaming, client streaming, bidirectional streaming.
- All 3 dispatch models: ASYNC (portable), EPOLL (Linux-only), URING (Linux-only). Required, no default.
- Minimal protobuf codec (varint + LEN wire types) for payload encoding without codegen.
- grpc-timeout header parsing, grpc-status trailer serialization.
- Native TLS (TLS 1.3 / 1.2, ALPN h2) via a `Tls.Context`, additive over the h2c default. A reverse proxy (nginx, haproxy) stays an option for offloading.

## Architecture

```mermaid
graph LR
    Z[zix.Grpc] --> H[zix.Http2]
    H --> T[std.Io / std.posix]
    Z --> P[proto.zig codec]
    Z --> S[status.zig]
    Z --> TO[timeout.zig]
```

`zix.Grpc` builds on top of `zix.Http2`. The gRPC frame loop (`serveGrpcConn`) replicates the h2c stream loop from `zix.Http2.serveConn`, both dispatch the same `req`/`res`/`ctx` trio shape (ADR-063), but gRPC's engine additionally reads `Route.is_server_streaming` before invoking the handler to support streaming without inter-thread queues (see Handler Pattern).

## Source Layout

| File | Role |
| :- | :- |
| `src/tcp/http2/grpc/Grpc.zig` | namespace: all public re-exports |
| `src/tcp/http2/grpc/core.zig` | `GrpcContext`, `GrpcRequest`, `GrpcResponse`, `HandlerFn`, `Router`, `serveGrpcConn` (blocking models), `GrpcMuxConn` + `grpcMuxOnReadable` (multiplexed `.EPOLL`), `parsePath`, `detectContentType`, `wallClockNs`, `computeDeadline`, `peerStr` |
| `src/tcp/http2/grpc/config.zig` | `GrpcServerConfig`, `GrpcClientConfig` |
| `src/tcp/http2/grpc/server.zig` | `GrpcServer`: thin `run()` switch that dispatches to the per-model files under `dispatch/` (and to the TLS serve paths when `cfg.tls != null`) |
| `src/tcp/http2/grpc/dispatch/` | per-model dispatch files: `async.zig`, `epoll.zig` (multiplexed `epollMuxWorkerFn` + `GrpcConnTable`), `uring.zig` (`.URING`), `common.zig` (shared helpers) |
| `src/tcp/http2/grpc/tls_serve.zig` | `runTls`: blocking TLS handler path (per-connection) |
| `src/tcp/http2/grpc/tls_mux.zig` | `runTlsMux`: multiplexed TLS dispatch path |
| `src/tcp/http2/grpc/client.zig` | `GrpcClient`: openStream, sendMessage, endStream, recvResponse, unary |
| `src/tcp/http2/grpc/frame.zig` | `GrpcPrefix` struct, `readGrpcPrefix`, `writeGrpcPrefix`, `send*`/`build*` frame helpers (`buildGrpcHeaders`/`buildGrpcDataHeader`/`buildGrpcTrailer`/`buildGrpcError`), comptime cached reply blocks |
| `src/tcp/http2/grpc/proto.zig` | `WT_*` wire type constants, `encodeVarint`, `decodeVarint`, `encodeString`, `encodeInt32`, `encodeDouble`, `decodeDouble`, `MessageReader` |
| `src/tcp/http2/grpc/status.zig` | `GrpcStatus` enum (u8), OK=0 to UNAUTHENTICATED=16 |
| `src/tcp/http2/grpc/timeout.zig` | `parseTimeout`: grpc-timeout header parser |

## Public API

| Symbol | Notes |
| :- | :- |
| `zix.Grpc.Server` | `init(Router(&routes), config)`, `deinit()`, `run()!void` (ADR-063: the one exception to the family's `init(handler, config)`, see Handler Pattern below) |
| `zix.Grpc.Client` | `connect(config, io)!Self`, `deinit()`, `openStream`, `sendMessage`, `endStream`, `recvResponse`, `unary` |
| `zix.Grpc.Request` | `{ path, headers }` view, `header(name)`, `recvMessage()`. Thin delegating wrapper over `Context`, zero internal logic moved |
| `zix.Grpc.Response` | `sendHeaders()`, `sendMessage()`, `finish()`, `serveCached()`, `sendCached()`. Thin delegating wrapper over `Context`, byte-identical wire |
| `zix.Grpc.Context` | `withTimeout()` / `setTimeout()` / `withDeadline()` / `isExpired()` / `timedOut()`, `io`, and a stack-arena `allocator` (`FixedBufferAllocator`, no heap call) |
| `zix.Grpc.HandlerFn` | `*const fn (req: *Request, res: *Response, ctx: *Context) anyerror!void` (ADR-063 trio). A returned error closes a still-open call with `grpc-status 13` |
| `zix.Grpc.Route` | `struct { path: []const u8, handler: HandlerFn, timeout_ms: u32 = 0, is_server_streaming: bool = false }` |
| `zix.Grpc.Router(routes)` | comptime type: `pub const route_slice`, `dispatch(req, res, ctx) anyerror!void` (sends UNIMPLEMENTED if no route matches). `Server.init` takes the Router TYPE itself, not `.dispatch`, because the engine reads `Route.is_server_streaming` off `route_slice` before dispatch |
| `zix.Grpc.ServerConfig` | see config fields below |
| `zix.Grpc.ClientConfig` | `ip`, `port` |
| `zix.Grpc.DispatchModel` | ASYNC=0 (portable), EPOLL=1 (Linux-only), URING=2 (Linux-only), required with no default |
| `zix.Grpc.Status` | enum(u8): OK=0 ... UNAUTHENTICATED=16 |
| `zix.Grpc.ContentType` | PROTO, JSON, UNKNOWN |
| `zix.Grpc.ServeOpts` | `GrpcServeOpts`: per-connection options passed to `serveConn` |
| `zix.Grpc.Path` | `package_service: []const u8`, `method: []const u8` |
| `zix.Grpc.Prefix` | `compress: bool`, `msg_len: u32` |
| `zix.Grpc.readPrefix` | `fn(body: []const u8) error{TooShort}!Prefix` |
| `zix.Grpc.writePrefix` | `fn(buf: *[5]u8, compress: bool, msg_len: u32) void` |
| `zix.Grpc.sendHeadersFD` | `fn(fd, sid, content_type) !void`: send initial HEADERS (no END_STREAM) |
| `zix.Grpc.sendDataFD` | `fn(fd, sid, msg) !void`: send DATA with 5-byte gRPC prefix |
| `zix.Grpc.sendTrailerFD` | `fn(fd, sid, grpc_status, grpc_message) !void`: send trailer HEADERS (END_STREAM) |
| `zix.Grpc.sendErrorFD` | `fn(fd, sid, grpc_status, grpc_message) !void`: trailers-only error, no DATA frame |
| `zix.Grpc.parsePath` | `fn(path: []const u8) ?Path` |
| `zix.Grpc.detectContentType` | `fn(headers: []const Header) ContentType` |
| `zix.Grpc.parseTimeout` | `fn(value: []const u8) ?u64` (nanoseconds) |
| `zix.Grpc.serveConn` | `fn(comptime RouterType, fd, opts, io) void`: direct connection entry point |
| `zix.Grpc.ClientResponse` | `union(enum) { data: []const u8, status: GrpcStatus }` |
| `zix.Grpc.wallClockNs` | `fn() u64`: current wall-clock time in nanoseconds (CLOCK_REALTIME). Used to override `ctx.deadline_ns` at runtime. |

## GrpcServerConfig Fields

| Field | Default | Description |
| :- | :- | :- |
| `io` | required | caller-provided `std.Io` backend |
| `ip` | required | bind address |
| `port` | required | listen port, 0 -> `error.ZixPortNotConfigured` |
| `dispatch_model` | required, no default | `.ASYNC`, `.EPOLL`, or `.URING` (the last two Linux-only, native, rejected off Linux with error.ZixDispatchModelUnsupported) |
| `kernel_backlog` | 1024 | `listen()` backlog |
| `workers` | 0 | 0 -> cpu_count multiplexing workers for EPOLL and URING. Ignored by ASYNC |
| `max_streams` | 128 | max concurrent HTTP/2 streams per connection (advertised SETTINGS_MAX_CONCURRENT_STREAMS) |
| `max_frame_size` | 16384 | advertised max HTTP/2 frame size |
| `max_header_scratch` | 4096 | HPACK decode scratch buffer per stream (pooled per worker) |
| `max_body` | 16384 | max total gRPC body buffered per stream (all DATA frames), a body past this sheds the stream with RESOURCE_EXHAUSTED |
| `logger` | `null` | optional `*zix.Logger`, when set, logs each stream close via `rpc()` and startup/shutdown via `system()` |
| `handler_timeout_ms` | 0 | global handler timeout cap (ms), 0 = disabled. Combined with `Route.timeout_ms` and `grpc-timeout` header at dispatch |
| `compress` | `false` | gzip-compress DATA frames for clients advertising `grpc-accept-encoding: gzip` |
| `response_cache` | `false` | per-worker unary response cache (ADR-036), opt-in via `res.serveCached` / `res.sendCached` (`.EPOLL` / `.URING`) |
| `cache_max_entries` | 256 | response cache slot count, rounded down to a power of two |
| `cache_max_value_bytes` | 16384 | per-slot response-message cap, a larger message bypasses the cache |
| `cache_ttl_ms` | 1000 | default cache freshness, handlers may pass their own TTL per store |
| `cache_max_total_bytes` | 0 | optional per-worker cache memory ceiling, 0 disables it |
| `tls` | `null` | non-null serves gRPC over TLS (ALPN h2) instead of h2c, see [TLS](#tls) |
| `tls_port` | 0 | dual-listener companion port (requires `tls`), 0 = single-listener |

More tuning fields (`worker_stack_size_bytes`, `busy_poll_us`, `reuseport_cbpf`, `max_recv_buf`, `tls_write_buf_initial_bytes`) are covered in [`docs/zix-config-en.md`](zix-config-en.md).

## Handler Pattern

Routes are registered at compile time and wrapped in `Router(&routes)`. The handler receives the `req`/`res`/`ctx` trio (ADR-063), the path is already resolved by the route table.

```zig
fn echoHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    while (req.recvMessage()) |msg| {
        res.sendMessage("application/grpc+proto", msg);
    }
    res.finish(zix.Grpc.Status.OK, "");
}

var server = zix.Grpc.Server.init(
    zix.Grpc.Router(&[_]zix.Grpc.Route{
        .{ .path = "/pkg.Svc/Echo", .handler = echoHandler, .is_server_streaming = true },
    }),
    .{ .io = io, .ip = "127.0.0.1", .port = 8083 },
);
defer server.deinit();
try server.run();
```

`Server.init` is gRPC's one deliberate exception to the family's `Server.init(handler, config)` shape (ADR-063): it takes `Router(&routes)` itself, not `.dispatch`, because the engine reads `Route.is_server_streaming` off the router's `route_slice` before invoking the handler, to pick sync-inline dispatch (unary, cheap) vs task-spawn dispatch (streaming). Measured: sync-inline is roughly two orders of magnitude more RPS per core than task-spawn for a trivial unary handler, so a bare `HandlerFn` pointer losing that metadata was not an acceptable simplification.

Key rules:
- `res.finish()` must always be called before returning. It sends the grpc-status trailer.
- `res.sendMessage()` sends initial response HEADERS on the first call. Do not call `res.sendHeaders()` manually if using `sendMessage`.
- `req.recvMessage()` returns `null` when all client messages are consumed (client sent END_STREAM).
- A handler error closes the call. When the handler returned an error without calling `res.finish`, the engine closes the stream with `grpc-status 13` (INTERNAL) and grpc-message `handler error`, so the caller is never left waiting on a stream that will never carry a status. A call the handler already closed keeps the status the handler chose. An error the handler catches itself never reaches the engine, so that handler owns what the caller gets: `try res.sendMessage(...)` takes the default, `res.sendMessage(...) catch { ... }` answers on its own terms.
- Unary routes (`is_server_streaming = false`, the default) dispatch synchronously on the connection thread. Server-streaming routes (`is_server_streaming = true`) each run on a dedicated thread sharing a connection-level write mutex.
- The server buffers all client DATA before dispatching the handler.
- `parsePath` and path-based dispatch inside the handler are not needed: the route table handles that.
- A unary handler may opt into the per-worker response cache: `if (res.serveCached(content_type)) return;` before the expensive work, `res.sendCached(content_type, reply, ttl_ms)` instead of `sendMessage` to store it. Requires `response_cache = true`, degrades to a plain `sendMessage` otherwise.

## Context Timeout

Three inputs determine `ctx.deadline_ns` at dispatch time:

| Input | Where | Notes |
| :- | :- | :- |
| `GrpcServerConfig.handler_timeout_ms` | config | global cap (0 = disabled) |
| `Route.timeout_ms` | comptime route table | per-route default (0 = use global cap) |
| `grpc-timeout` header | client request | parsed by `parseTimeout` (takes effect if tighter) |

`ctx.deadline_ns: ?u64` is the tightest of all three (CLOCK_REALTIME nanoseconds). `null` means no deadline. `Router.dispatch` applies `Route.timeout_ms` after the global deadline is set, so per-route timeout only tightens, never loosens.

Handlers check the deadline explicitly:

```zig
fn slowHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    if (ctx.isExpired()) {
        res.finish(zix.Grpc.Status.DEADLINE_EXCEEDED, "");
        return;
    }
    const msg = req.recvMessage() orelse {
        res.finish(zix.Grpc.Status.INVALID_ARGUMENT, "no message");
        return;
    };
    res.sendMessage("application/grpc+proto", msg);
    res.finish(zix.Grpc.Status.OK, "");
}
```

Handler deadline override pattern (canonical):

```zig
ctx.deadline_ns = wallClockNs() + 60 * std.time.ns_per_s; // extend to 60 s from now
ctx.deadline_ns = null; // disable for this call
// or via the helpers: ctx.setTimeout(60_000); ctx.withDeadline(deadline_ns);
```

Risks on override:
- Extending past the client `grpc-timeout` wastes work on a dead connection.
- `null` disables all enforcement.
- Extending without first calling `ctx.isExpired()` silently continues past an already-expired deadline.

Per-route timeout example:

```zig
var server = zix.Grpc.Server.init(
    zix.Grpc.Router(&[_]zix.Grpc.Route{
        .{ .path = "/svc.Svc/FastOp", .handler = fastHandler, .timeout_ms = 500    },
        .{ .path = "/svc.Svc/SlowOp", .handler = slowHandler, .timeout_ms = 30_000 },
    }),
    .{ .io = process.io, .ip = "127.0.0.1", .port = 8083, .handler_timeout_ms = 5000 },
);
```

## All 4 RPC Types

Unary and client-streaming handlers use `is_server_streaming = false` (the default). Server-streaming and bidirectional handlers must set `is_server_streaming = true` on their `Route` entry to prevent deadlock under flow-control backpressure.

### Unary (1 request, 1 response)

```zig
fn unaryHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    const msg = req.recvMessage() orelse {
        res.finish(zix.Grpc.Status.INVALID_ARGUMENT, "no message");
        return;
    };
    res.sendMessage("application/grpc+proto", msg);
    res.finish(zix.Grpc.Status.OK, "");
}
```

### Server Streaming (1 request, N responses)

```zig
fn serverStreamHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    _ = req.recvMessage();
    res.sendMessage("application/grpc+proto", "result-1");
    res.sendMessage("application/grpc+proto", "result-2");
    res.sendMessage("application/grpc+proto", "result-3");
    res.finish(zix.Grpc.Status.OK, "");
}
```

### Client Streaming (N requests, 1 response)

```zig
fn clientStreamHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    var count: usize = 0;
    while (req.recvMessage()) |_| count += 1;
    var buf: [32]u8 = undefined;
    const reply = std.fmt.bufPrint(&buf, "got {d}", .{count}) catch "got ?";
    res.sendMessage("application/grpc+proto", reply);
    res.finish(zix.Grpc.Status.OK, "");
}
```

### Bidirectional Streaming (N requests, M responses)

```zig
fn bidiHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    while (req.recvMessage()) |msg| {
        res.sendMessage("application/grpc+proto", msg);
    }
    res.finish(zix.Grpc.Status.OK, "");
}
```

Note: all client messages are buffered before the handler is called. True interleaved bidirectional streaming (server sends before client finishes) would require a different architecture. The buffered design covers all 4 patterns for bounded message sizes.

## GrpcClient Usage

```zig
var client = try zix.Grpc.Client.connect(.{
    .ip   = "127.0.0.1",
    .port = 8083,
}, process.io);
defer client.deinit();

// Unary convenience
var buf: [4096]u8 = undefined;
const resp = try client.unary(
    "/helloworld.Greeter/SayHello",
    "application/grpc+proto",
    request_bytes,
    &buf,
);

// Manual streaming
const sid = try client.openStream("/svc.Svc/Echo", "application/grpc+proto");
try client.sendMessage(sid, "msg1");
try client.sendMessage(sid, "msg2");
try client.endStream(sid);

var rbuf: [4096]u8 = undefined;
while (true) {
    const r = try client.recvResponse(sid, &rbuf);
    switch (r) {
        .data   => |d| { _ = d; },
        .status => |s| { _ = s; break; },
    }
}
```

## Wire Protocol

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server

    C->>S: HEADERS (POST :path, content-type, END_HEADERS)
    C->>S: DATA (5-byte prefix + message, END_STREAM)
    S->>C: HEADERS (:status 200, content-type, END_HEADERS)
    S->>C: DATA (5-byte prefix + message, END_STREAM=false)
    S->>C: HEADERS (grpc-status 0, END_HEADERS, END_STREAM)
```

### gRPC 5-byte message prefix

```
+----------+-------------------------------+
| Compress | Message Length (4 bytes, BE)  |
|  Flag(1) |                               |
+----------+-------------------------------+
| Message payload                          |
+------------------------------------------+
```

The compress flag is 1 when the message payload is gzip-compressed, otherwise 0. Compression is opt-in through the server `compress` config and applies only when the client advertises `grpc-accept-encoding: gzip`, in which case the server also emits `grpc-encoding: gzip` in the initial HEADERS frame.

### Error path (trailers-only)

When the handler calls `res.finish(status, msg)` without sending any data, the server sends a single HEADERS frame with `:status 200`, `content-type`, `grpc-status`, and `grpc-message` with `FLAG_END_STREAM`. HTTP `:status` is always 200 per the gRPC wire protocol, the actual gRPC error is in the `grpc-status` trailer. `content-type` is always included per the gRPC spec to ensure client compatibility.

## Dispatch Models

| Model | Accept threads | Connection dispatch | Notes |
| :- | :- | :- | :- |
| `.ASYNC` | 1 | `io.async()` per connection | preferred for unbounded or long-lived streams |
| `.EPOLL` | per worker | multiplexed event loop (Linux only) | highest throughput, see below |
| `.URING` | per worker | multiplexed io_uring loop (Linux only) | same shape as `.EPOLL`, completion-based |

`.EPOLL` is Linux-specific. Off Linux, `run()` returns `error.ZixDispatchModelUnsupported` after logging which model was rejected, so pick `.ASYNC` there. `.URING` is the same shared-nothing multiplexed design on the io_uring ring (`runUring`, ADR-037 Phase 4): completion-based instead of readiness-based, `workers` workers (0 = cpu_count), Linux-only, and rejected off Linux the same way. When io_uring itself is unavailable on a Linux host, `.URING` folds to the `.EPOLL` loop with a logged notice.

### `.EPOLL` is multiplexed and shared-nothing

`.EPOLL` does not park one thread per connection. It runs `workers` worker threads (0 = cpu count), each owning a private `SO_REUSEPORT` listener, its own epoll instance, and a private fd-indexed connection table. The kernel load-balances new connections across the per-worker listeners, so there is no accept thread, no shared queue, and no cross-thread fd handoff. One worker drives many non-blocking connections through a resumable HTTP/2 state machine (`GrpcMuxConn`), so concurrency is bounded by connection count, not by thread count. Each worker's `epoll_wait` drains up to `EPOLL_MAX_EVENTS` (512) ready events per call (ADR-032). The low-level design is in `lld-grpc-en.md`.

Two consequences differ from `.ASYNC`:

- `workers` is the multiplexing worker count for `.EPOLL` (the optimal value is around cpu count). Oversubscribing it only adds scheduler churn.
- Every route, including server-streaming, is dispatched inline on the worker (no per-stream thread). A streaming handler runs on the event loop, so it must be bounded - a long-running or unbounded stream blocks the other connections on that worker. Use `.ASYNC` for unbounded streaming, where the per-stream thread spawn still applies to server-streaming routes.
- Server-streaming replies coalesce many gRPC messages into each HTTP/2 DATA frame (up to the 16 KiB default max frame size) instead of one frame per message, so a chatty stream costs far fewer frames on the wire and far less per-frame parsing on the client. See the LLD for the mechanism.

The advertised `max_streams` must be at least the client's concurrent-stream count. A client (for example a benchmark with 100 parallel streams per connection) opens streams optimistically before it sees the server SETTINGS, and any beyond `max_streams` are answered with `REFUSED_STREAM`.

## Lifecycle

```mermaid
flowchart TD
    A[GrpcServer.run] --> B{dispatch_model}
    B -->|ASYNC| C[single accept thread\nio.async per conn]
    B -->|EPOLL| EP[N workers\nSO_REUSEPORT listener\n+ epoll each]
    C --> F[serveGrpcConn blocking]
    D --> F
    E --> F
    EP --> MX[grpcMuxOnReadable\nresumable per-conn state]
    F --> G{h2c preface?}
    G -->|PRI| H[h2c direct]
    G -->|GET/POST| I[h2c upgrade]
    H --> J[blocking frame loop]
    I --> J
    J -->|HEADERS stream| K[buffer DATA]
    K -->|END_STREAM| L[dispatchStream]
    L -->|is_server_streaming=false| LI[inline on conn thread]
    L -->|is_server_streaming=true| LS[spawn thread]
    LI --> M[HandlerFn: req/res/ctx trio]
    LS --> M
    MX -->|every complete frame| MI[muxDispatch inline\nreply staged to cork]
    MI --> M
    M --> N[res.finish sends trailers]
```

## Minimal Protobuf Codec

`proto.zig` provides wire-type constants and encode/decode primitives for proto3. No `.proto` file compiler or generated code is required for simple schemas.

| Function | Notes |
| :- | :- |
| `encodeVarint(buf, value)` | encodes u64 as 1-10 bytes, returns bytes written |
| `decodeVarint(buf)` | returns `{value: u64, consumed: usize}` or error |
| `encodeString(field_number, s, buf)` | LEN wire type (2), returns bytes written |
| `encodeInt32(field_number, val, buf)` | VARINT wire type (0), returns bytes written |
| `encodeDouble(field_number, val, buf)` | I64 wire type (1), 8-byte little-endian IEEE 754, returns bytes written |
| `decodeDouble(payload)` | reads `*const [8]u8`, returns `f64` |
| `MessageReader.init(buf)` | wraps a serialized message buffer |
| `MessageReader.next()` | returns `?ProtoField` with `field_number`, `wire_type`, `payload` |

Example encoding a `HelloRequest { string name = 1; }`:

```zig
var out: [256]u8 = undefined;
const n = zix.Grpc.encodeString(1, "world", &out);
// send out[0..n] as the gRPC message payload
```

## TLS

`zix.Grpc` serves h2c (cleartext) by default. Setting `tls: ?*Tls.Context` on the config opts into gRPC over TLS (TLS 1.3, with a 1.2 fallback, ALPN h2), with two serve paths selected by `dispatch_model` (ADR-052). Under `.EPOLL` / `.URING`, one `SO_REUSEPORT` epoll worker per core terminates TLS in place via a resumable session (`tcp/tls/tls_session.zig`) and multiplexes many connections per worker (`grpc/tls_mux.zig`), with no socketpair and no thread per connection. Under `.ASYNC`, a thread-per-connection terminator (`grpc/tls_serve.zig`) runs the shared `tcp/tls/h2_terminator.zig` with an inline-mux driver that drives the resumable gRPC mux directly over the decrypted records and seals frames back into TLS records via a thread-local write hook (also used by Http2). The cert / key / policy live in the `Tls.Context` (ADR-047), reused across engines. With `tls_port` set next to `tls`, ONE server serves h2c on `port` and gRPC over TLS on `tls_port` from the same worker fleet (ADR-060).

```mermaid
graph LR
    C[gRPC client\nTLS/port 8443] -->|grpc over tls| Z[zix.Grpc server\nTLS terminator + h2c engine]
```

A reverse proxy stays an alternative when TLS offload, routing, or sharing a port with other services is wanted. See [`docs/hld-proxy-en.md`](hld-proxy-en.md) for nginx and haproxy configuration examples.

## Examples

| File | Pattern |
| :- | :- |
| `examples/grpc_server.zig` | dispatch model picked per target (URING on Linux, ASYNC elsewhere): SayHello, Echo, and StreamSum handlers, port 9032 |
| `examples/grpc_client.zig` | unary call and manual streaming demo, port 8083 |
| `examples/grpc_timeout.zig` | context timeout demo: handler_timeout_ms, Route.timeout_ms, ctx.isExpired(), ctx.deadline_ns override, port 8084 |
| `examples/grpc_location_server.zig` | location.Location/SendLocationAndSave, dispatch model picked per target, port 9038 |
| `examples/grpc_location_client.zig` | location service client: encodes double fields, decodes bool response |
| `examples/grpc_multi_server.zig` | ASYNC, helloworld.Greeter + location.Location on one port (10102), logger wired |
| `examples/grpc_multi_client.zig` | calls both services on one connection, port 10102 |
| `examples/protobuf/helloworld.proto` | proto3 schema for helloworld.Greeter/SayHello |
| `examples/protobuf/location.proto` | proto3 schema for location.Location/SendLocationAndSave |

## Tests

| Tier | File | Count |
| :- | :- | :- |
| unit | inline in `src/tcp/http2/grpc/*.zig` via `refAllDecls` | ~40 |
| integration | `tests/integration/grpc/server_test.zig` | 9 |
| behaviour | `tests/behaviour/grpc/config_test.zig` | 7 |
| edge | `tests/edge/grpc/server_test.zig` | 13 |

Ports: integration 18200-18206, edge 18220-18221.

---

###### end of hld-grpc
