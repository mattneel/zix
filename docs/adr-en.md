# Architecture Decision Records: zix

Each ADR records a significant design decision: the context that made it necessary, the decision taken, and its consequences. Accepted ADRs are binding. Proposed ones are under discussion.

---

## ADR-001: `std.Io` as the I/O abstraction

**Status:** Accepted

**Context:** The server must handle many concurrent connections without blocking on I/O. Zig 0.16 provides `std.Io` as an opaque event loop abstraction over OS facilities (epoll, kqueue, io_uring, etc.). The alternative was raw OS threads with explicit synchronization.

**Decision:** Accept `std.Io` as a parameter in `zix.Http.Server` and `zix.Udp.Server`. The caller owns and provides the backend (`process.io` for runtime-managed or `std.Io.Threaded` for an explicit cap). The server uses `io.concurrent()` in model 1. In model 2 the pool threads call `handleConnection` directly with a `std.Io` derived from `std.Io.Threaded`.

**Consequences:**
- Caller controls the concurrency model. zix does not own or deinit the backend.
- `zix.Http.Server.run()` and `zix.Udp.Server.run()` block until error.
- `io.concurrent()` is used in model 1 (single accept, task-per-connection). Model 2 bypasses `io.concurrent()` entirely: pool threads handle connections with blocking synchronous I/O.
- Code that needs true parallelism (e.g. UDP broadcast) can call `io.concurrent()` from within a task.

---

## ADR-002: Namespace API (zix.Http.*, zix.Udp.*)

**Status:** Accepted

**Context:** The initial API exposed flat exports from the zix root (`zix.HttpServer`, `zix.Request`, etc.). When UDP was added the surface became inconsistent: HTTP types were flat while UDP types were already under `zix.Udp.*`. The flat HTTP names also carried redundant prefixes (`HttpServer`, `HttpHeader`) that became obvious once nested.

**Decision:** Introduce `zix.Http` and `zix.Udp` as namespace aggregators backed by `Http.zig` and `Udp.zig`. Remove all flat HTTP exports. Canonical paths:
- `zix.Http.Server`, `zix.Http.Request`, `zix.Http.WebSocket`, ...
- `zix.Udp.Server(Packet)`, `zix.Udp.Client(Packet)`, `zix.Udp.ServerConfig`, ...

`zix.Tcp.Http.*` remains accessible (Tcp.zig re-exports Http.zig) but is not the canonical path.
`zix.utils` stays flat (it is not protocol-specific).

**Consequences:**
- Breaking change: all code referencing flat exports must update.
- Namespace makes protocol affiliation self-evident at the call site.
- Adding future protocols (UDS, QUIC) follows the same pattern with zero impact on existing namespaces.

---

## ADR-003: Per-connection arena allocator, reset per request

**Status:** Accepted

**Context:** Handler code needs temporary allocations (body parsing, path segments, JSON, etc.) that are only valid for the duration of one request. A general-purpose allocator would require explicit `free` calls in every handler and every error path.

**Decision:** Allocate one `ArenaAllocator` per connection (backed by `smp_allocator`). Reset it between requests with `.retain_capacity`. Expose the arena's allocator as `ctx.allocator`. Deinit the arena when the connection closes.

**Consequences:**
- Handlers never call `free`. All per-request memory is reclaimed automatically at request end.
- `ctx.allocator` allocations must not escape the request (e.g. stored in a global). The name `ctx.allocator` is intentionally brief, the arena lifetime constraint is documented rather than encoded in the name. (A rename to `ctx.request_arena` was considered and declined: the lifetime constraint is enforced by documentation and convention.)
- Retain-capacity reset amortizes arena backing block growth over the connection lifetime.

---

## ADR-004: 3-pass router dispatch (exact > param > prefix)

**Status:** Accepted

**Context:** A router needs a consistent priority rule when multiple patterns could match the same request. Options were: first-match-wins (registration order), longest-match, or explicit priority tiers.

**Decision:** Three passes in fixed priority order: exact routes first, then param routes (first-registered wins within pass 2), then prefix routes (longest wins within pass 3). Registration order is irrelevant for passes 1 and 3.

**Consequences:**
- Exact and prefix routes are deterministic regardless of order. This covers the common case (most routes are exact or prefix).
- Param routes require care: more-literal patterns must be registered before all-param patterns of the same depth. This is documented and demonstrated in examples.
- The 3-pass design was considered for replacement with first-match-wins. Deferred: the change would be breaking and the benefit is marginal for typical route counts.

---

## ADR-005: Comptime-generic UDP packet type

**Status:** Accepted

**Context:** UDP carries application-defined binary structs. A fixed built-in packet type would limit interoperability. A runtime `[]u8` slice would lose type safety and require the user to handle serialization manually.

**Decision:** `UdpServer` and `UdpClient` are generic over a comptime `Packet: type`. The user defines their own `extern struct` and passes it at the instantiation site (`zix.Udp.Server(MyPacket)`). zix handles endianness, size validation, and framing. The application owns the packet definition and identity logic.

**Consequences:**
- The server does not stamp or modify any packet field. The `id` field (if present) is the sender's responsibility.
- Endianness helpers (`toEndian`, `fromEndian`) are fully generic: they work on any `extern struct`.
- `@sizeOf(Packet)` is comptime-known, enabling the RFC 768 size assert and the fixed receive buffer `[@sizeOf(Packet)]u8`.

---

## ADR-006: LITTLE endianness as default for UDP

**Status:** Accepted

**Context:** UDP packets transmitted across machines or languages must agree on byte order. The two common choices are LITTLE (x86/ARM native, most modern hardware) and BIG (network byte order, RFC 791 convention).

**Decision:** `Endianness.LITTLE` is the default in both `UdpServerConfig` and `UdpClientConfig`. BIG is available for interop with legacy or internet protocols.

**Consequences:**
- On x86 and ARM (the majority of deployment targets), LITTLE is a no-op (no swapping performed).
- Cross-language clients (Go, C++, Rust) on the same hardware family also default to little-endian, so no conversion is needed in the common case.
- Users targeting network byte order (BIG) must explicitly set `endianness: .BIG` on both sides.

---

## ADR-007: Timeout-based disconnect detection for UDP

**Status:** Accepted

**Context:** UDP has no connection state. There is no OS-level equivalent of TCP FIN. The only reliable way to detect that a client has stopped sending is the absence of traffic for a configurable period.

**Decision:** Track clients by remote address in a `Managed(ClientRecord)` list. Update `last_seen` on each packet. On `receiveTimeout` expiry (poll interval) and after each burst of packets (rate-limited check), scan for clients whose `last_seen` is older than `conn_timeout_ms` and remove them.

**Consequences:**
- Worst-case detection delay is `conn_timeout_ms + poll_timeout_ms`. This is documented and configurable.
- A client that crashes and restarts from a new port is treated as a new client.
- A client that restarts from the same port is re-registered on the next packet.
- False positives (briefly silent clients) are bounded by `conn_timeout_ms`.

---

## ADR-008: Heap-allocated peer snapshot for UDP broadcast

**Status:** Accepted

**Context:** Broadcast requires sending the received packet to all currently connected clients. The client list is mutable (new clients may join between packets). Passing a pointer to the mutable list into the concurrent task would create a data race.

**Decision:** Before `io.concurrent(processPacket)`, snapshot the current client addresses into a heap-allocated `[]IpAddress` (`smp_allocator.alloc`). The task receives the snapshot by value in its `Task` struct. The task frees the snapshot via `defer` after all sends complete.

**Consequences:**
- No shared mutable state between the receive loop and concurrent tasks.
- Allocation only occurs when `broadcast = true` and the clients list is non-empty.
- A client that disconnects between the snapshot and the broadcast send will receive a send error that is silently ignored (correct behavior).

---

## ADR-009: extra_buf as arena-allocated []HttpHeader

**Status:** Accepted

**Context:** The original design stored custom response headers in a fixed `[32]HttpHeader` buffer. This caused an out-of-bounds write when `max_response_headers = .LARGE` (64 slots) and more than 32 headers were added. A compile-time cap was insufficient because the cap is runtime-configurable per server instance.

**Decision:** Store custom response headers in `extra_buf: ?[]HttpHeader`, allocated from the per-request arena and sized to `max_headers` (from `ServerConfig.max_response_headers.value()`). Allocation is lazy: `Response.init()` leaves `extra_buf = null` and the buffer is allocated on the first `addHeader()` call, so `Response` keeps a `max_headers` field as the cap.

**Consequences:**
- The cap is exact: no `@min(..., 128)` clamp, no wasted slots.
- `Response.init()` stays non-fallible: the allocation moved to the first `addHeader()`, which returns `error.TooManyHeaders` on allocation failure or past the cap. A response that adds no custom header never allocates the buffer.
- The arena lifetime guarantees the buffer is valid for the request and reclaimed automatically.

---

## ADR-010: UDS (Unix Domain Socket)

**Status:** Accepted, Implemented (2026-05-13)

**Context:** Unix Domain Sockets are the standard IPC mechanism on Linux and macOS for same-host communication. A `zix.Uds` namespace following the same pattern as `zix.Udp` would complete the trilogy of transport protocols.

**Decision:** Implemented in `src/uds/`. Namespace aggregator at `src/uds/Uds.zig`, exported as `pub const Uds = @import("uds/Uds.zig")` in `lib.zig`. Stream mode only (datagram requires raw `std.posix`, not exposed via `std.Io.net.UnixAddress`, and is deferred). Frame format: 4-byte `u32` length header (big-endian, network byte order) followed by payload bytes. `UdsClient.sendMsg`/`recvMsg` and `echoHandler` all use this frame contract.

**`std.Io.net` API used:** `std.Io.net.UnixAddress.init(path)`, `.listen(io, opts) !Server`, `.connect(io) !Stream`. `has_unix_sockets = false` on WASI: both `Server.init()` and `Client.connect()` emit `@compileError` on unsupported platforms.

**Consequences:**
- `zix.Uds.Server`, `zix.Uds.Client`, `zix.Uds.ServerConfig`, `zix.Uds.ClientConfig`, `zix.Uds.HandlerFn`, and `zix.Uds.echoHandler` are all public.
- Server uses Model 1 (`io.concurrent()`): one accept thread, task per connection.
- Socket path is unlinked before bind (clean restart) and again on `runWith()` return.
- `error.PathEmpty` is returned by `Server.init()` when `config.path` is empty.
- `allocator` field in `UdsServerConfig` is reserved for future extensions. Current implementation is allocation-free (stack buffers only).

---

## ADR-011: Comptime middleware wrapper pattern

**Status:** Accepted

**Context:** HTTP handlers need cross-cutting concerns (auth, rate limiting, CORS, logging) that apply to subsets of routes. Options were: runtime chain runner (heap-allocated list of middleware functions called in order), decorator pattern (wrapper functions), or manual handler composition.

**Decision:** Comptime wrapper functions that return `HandlerFn`. Each wrapper takes `comptime next: HandlerFn` and returns a new `HandlerFn`. The `next` call is a direct function call (no runtime dispatch, no allocation). Composing left-to-right: outermost wrapper runs first.

```zig
fn withAuth(comptime next: zix.Http.HandlerFn) zix.Http.HandlerFn {
    return struct {
        fn handle(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
            // guard ...
            return next(req, res, ctx);
        }
    }.handle;
}

var server = zix.Http.Server.init(&[_]zix.Http.Route{
    .{ .path = "/private", .handler = withAuth(withLogging(privateHandler)) },
}, .{ .io = process.io, .ip = "127.0.0.1", .port = 9000 });
```

**Consequences:**
- Zero runtime overhead. Each unique `next` value generates a distinct function at comptime.
- No heap allocation. No middleware chain runner to deinit.
- Composition is explicit at the registration call site: readers see the full chain without looking inside any function.
- Each unique composition generates a new comptime function, excessive combinations increase binary size.

---

## ADR-012: Explicit HTTP server behavior config fields

**Status:** Proposed

**Context:** Several HTTP server behaviors are embedded in `server.zig` internals and not visible in `HttpServerConfig`: the 404 auto-response when no route matches, the keep-alive loop, and the static file fallback behavior. Users cannot override these without modifying source.

**Decision:** Add named fields to `HttpServerConfig` for every configurable behavior. `null` disables a behavior, a function value enables the user's override. Proposed additions:

```zig
pub const HttpServerConfig = struct {
    // existing fields ...
    not_found:  ?HandlerFn = null,    // null = built-in 404 plain text
    keep_alive: bool       = true,    // false = close after each response
};
```

The `public_dir` field already exists but its role as an opt-in feature (not a magic fallback) should be made explicit in documentation.

**Consequences:**
- Config struct is the complete contract: if it is not in the struct, it does not happen.
- Breaking change for any code that relies on the current implicit 404 behavior (minimal impact in practice).
- `not_found = null` preserves the current default behavior, no migration required unless the user wants a custom 404.
- Static fallback magic is removed: `public_dir = ""` (already the default) disables it, as it does now.

---

## ADR-013: Explicit allocator in UdpServerConfig

**Status:** Accepted

**Context:** `UdpServer` uses the heap for two purposes: the `Managed(ClientRecord)` client list (process lifetime) and the per-packet `[]IpAddress` broadcast snapshot (freed inside `processPacket`). Both previously used `std.heap.smp_allocator` internally, invisible to the caller. The project's "explicit over implicit" principle applies equally to memory ownership: hiding the allocator makes it impossible to substitute a leak-detecting allocator in tests.

**Decision:** Add `allocator: std.mem.Allocator` as a required field (no default) to `UdpServerConfig`. The server uses this allocator for the client list and broadcast peer snapshots. `UdpClientConfig` receives no allocator field because `UdpClient` makes no heap allocations: all buffers are stack-allocated (`[@sizeOf(Packet)]u8`).

**Why `ArenaAllocator` is explicitly rejected for UDP:** Unlike HTTP (where the router allocator is append-only), the UDP server allocates and frees a peer snapshot on every packet when `broadcast = true`. `ArenaAllocator.free()` is a no-op: memory is not reclaimed until `arena.deinit()`. On a busy broadcast server this causes unbounded growth:

```
// PoC: what goes wrong with ArenaAllocator
var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
var server = try MyServer.init(.{
    .allocator = arena.allocator(), // WRONG for UDP
    .broadcast = true,
    ...
});
// Each received packet when broadcast = true:
//   alloc(IpAddress, N)  ->  real allocation, grows arena
//   free(peers)          ->  NO-OP, memory not reclaimed
// After M packets with N clients: M * N * @sizeOf(IpAddress) bytes permanently held
// arena.deinit() is never called while the server runs -> unbounded memory growth
```

`ArenaAllocator` is correct for `HttpServerConfig.allocator` because the router is append-only: routes are registered once at startup and freed together via `arena.deinit()` when the server shuts down.

**Consequences:**
- Breaking change: all existing `UdpServerConfig` initialisers must add `.allocator = ...`
- Test code can now pass `std.testing.allocator` for leak detection, prod code passes `std.heap.smp_allocator`.
- `UdpServerConfig` and `HttpServerConfig` are now consistent: both expose an explicit, required allocator field.
- `UdpClient` remains simpler by design: no heap allocation, no allocator field required.

---

## ADR-014: `Server.init(comptime routes, config)`, internal stack buffer cap

**Status:** Accepted

**Context:** The original API used a comptime generic function as the entry point: `zix.Http.Server(4096).init(config)`. This forced callers to treat `HttpServer` as a factory function rather than a struct, which was unintuitive and inconsistent with the rest of the API. A comptime `stack_threshold` parameter on the constructor is also dead flexibility: every call site passes the same 4096, the runtime knob deciding the buffer size is already `max_recv_buf`, and the write-side field it once paired with (`max_client_response`) has no consumer.

**Decision:** Expose a `pub const Server` struct with a single `pub fn init(comptime routes: []const Route, config: Config) HttpServerImpl(routes)`. The stack cutoff is the internal constant `stack_read_buf_max = 4096` (dispatch/common.zig): a connection whose `max_recv_buf` fits within it reads on the connection thread stack, a larger `max_recv_buf` heap-allocates from `smp_allocator`. The `HttpServerImpl` generic remains private. Call sites become `zix.Http.Server.init(&[_]zix.Http.Route{...}, .{...})`: `Server` reads as a type, `init` reads as a constructor.

**Consequences:**
- Call sites match the rest of the engine family: `Server.init(routes, config)`, like `zix.Http1` / `zix.Http2` / `zix.Grpc` / `zix.Http3` (`Server.init(routes-or-handler, config)`).
- `routes` must remain `comptime`: the route table is baked into the server type. The stack array is sized by the internal comptime constant, so no comptime size parameter is needed at the call site.
- `max_recv_buf` (config) is the single tuning knob: it sets the read buffer size and thereby its stack vs heap placement.
- `init` stores the config and cannot fail, validation happens in `run()`.
- Breaking change: all existing call sites updated (the leading size parameter removed).

---

## ADR-015: Model 2 work-queue architecture (ConnQueue)

**Status:** Accepted

**Context:** The original Model 2 used `io.concurrent()` to dispatch connections from each worker thread. This added scheduler overhead (condvar wakeup per connection) that caused ~4x higher latency than a comparable blocking-thread HTTP server (334 us vs ~88 us) despite matching throughput (~145K req/s). A blocking-thread architecture (dedicated accept thread + OS thread pool + synchronous I/O) eliminates the fiber scheduler from the hot path entirely.

**Decision:** Replace per-worker `io.concurrent()` dispatch with a shared `ConnQueue` (mutex + condvar, backed by a heap ring buffer with O(1) push and pop). Accept threads (`workers`, `0` = cpu_count) only call `accept()` and `queue.push()` (they never handle I/O). Pool threads (`pool_size`, default `max(10, cpu_count * 2)`) call `queue.pop()` and then handle each connection synchronously with blocking I/O. `std.Io.Mutex` and `std.Io.Condition` are used (Zig 0.14 sync primitives. `std.Thread.Mutex` does not exist in this version).

**Consequences:**
- Pool threads handle connections with pure blocking I/O: no condvar dispatch overhead per request, no fiber wakeup latency.
- Throughput ~143-144K req/s, latency ~92 us avg. A ~3-5K req/s gap and ~4 us latency gap vs comparable blocking-thread servers remains, attributed to `std.http.Server` parsing overhead and the per-connection arena vs direct POSIX allocators.
- `pool_size` is now a configurable field in `HttpServerConfig` (`0` = auto `max(10, cpu_count * 2)`).
- Accept threads are lightweight, so `workers = 0` (cpu_count) saturates the kernel accept queue, `workers = N` allows explicit override.
- `io.concurrent()` is still used by the `.ASYNC` model (unaffected).

---

## ADR-017: Channel, In-Process Typed Message Passing

**Status:** Accepted, Implemented (2026-05-13)

**Context:** The server models (Model 1 / Model 2) handle request concurrency. There is no primitive for typed message passing between concurrent tasks within a single process. Go channels and POSIX pipes address this pattern, zix needs its own Zig-native equivalent that works alongside `io.concurrent()` tasks.

**Decision:** Implemented as `zix.Channel(comptime T: type)`. Buffered only (capacity > 0, unbuffered rendezvous deferred). Blocking `send(io, value)` and `recv(io)`. Exported as `pub const Channel = @import("channel/Channel.zig").Channel` in `lib.zig`. Open questions resolved:

- **Locking:** `std.Io.Mutex` + `std.Io.Condition` (fiber-aware, works in both `io.concurrent()` handler tasks and OS threads). `std.Thread.Mutex` was rejected because it blocks the OS thread.
- **Storage:** heap-allocated ring buffer (`allocator.alloc(T, capacity)`), runtime capacity, allocator required in `init()`.
- **Naming:** `Channel` (not `Chan`), locked at first example.
- **Unbuffered:** not yet implemented. `init()` asserts `capacity > 0`.
- **`select`/multiplex:** deferred. Ring design does not preclude it.

**Consequences:**
- `zix.Channel(T)` is a generic returning a struct. Usage: `const MyChan = zix.Channel(u32)`.
- `init(allocator, capacity)` allocates the ring buffer. `deinit()` frees it.
- `close(io)` unblocks all waiting `recv()` calls: receivers drain remaining items then get `error.Closed`.
- `send()` and `recv()` require an `io` valid on the calling thread: each OS thread needs its own `std.Io` (e.g. from `std.Io.Threaded`).
- Non-blocking `trySend`/`tryRecv` are deferred. All current examples use blocking variants.

---

## ADR-016: SSE via `res.stream()` + `SseWriter`, `.ASYNC` preferred

**Status:** Accepted (dispatch model updated by ADR-021)

**Context:** SSE (Server-Sent Events) requires a streaming HTTP response: headers are sent once with no `Content-Length`, and the connection stays open while the handler pushes events. The existing `Response.send()` assumes a complete body and always emits `Content-Length`. A new code path is needed without breaking the existing response API.

SSE connections are long-lived (seconds to minutes per stream). `.POOL`'s blocking thread pool assigns one OS thread per open connection for the full stream duration. With the default `max(10, cpu_count * 2)` pool, a handful of SSE clients would exhaust all pool threads and starve regular HTTP requests. `.ASYNC` (`dispatch_model = .ASYNC`) dispatches each connection as a concurrent fiber via `io.async()`, allowing thousands of open SSE streams without thread exhaustion.

**Decision:**

1. Add `res.stream() !SseWriter` to `Response`. It sends `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`, and `Date` (no `Content-Length`), then sets `res.streaming = true` and returns an `SseWriter`.

2. `SseWriter` holds `*std.Io.Writer` (the connection's buffered writer). Each method writes the SSE wire format and flushes immediately:
   - `writeEvent(data)` -> `data: <data>\n\n`
   - `writeNamedEvent(event, data)` -> `event: <event>\ndata: <data>\n\n`
   - `comment(text)` -> `: <text>\n`

3. `handleConnection` checks `if (res.streaming) break` after each dispatch. When the handler returns the keep-alive loop exits and the TCP connection closes. The browser's `EventSource` auto-reconnects after the default 3-second retry.

4. SSE examples must use `dispatch_model = .ASYNC` (see ADR-021). This is documented in the example, the README, and HLD.

**Consequences:**
- No change to `Response.send()`: existing handlers are unaffected.
- `res.streaming` defaults to `false`. Only SSE handlers set it to `true`.
- The `.ASYNC` preference is a usage constraint, not enforced at compile time. Handlers that call `res.stream()` in a `.POOL` server will work but will block pool threads for the stream duration.
- `SseWriter` is exported from `zix.Http.SseWriter` for handler authors who want to type-annotate the writer.

---

## ADR-018: Timeout strategy, B+D (ctx.timedOut + ConnRegistry eviction)

**Status:** Accepted

**Context:** The original `HttpServerConfig.response_timeout_ms` field was never wired into `server.zig`. It existed as a placeholder. Two classes of timeout are needed: a network-level guard for clients that stall before or during header send (holding a pool thread indefinitely), and a handler-level budget for slow application logic.

`SO_RCVTIMEO` was investigated and rejected: on Linux, `SO_RCVTIMEO` fires `EAGAIN`, which `std.Io.Threaded.netReadPosix` maps to `errnoBug` (a panic in debug mode and `error.Unexpected` in release). It cannot be used on blocking sockets in this stack. `stream.shutdown(.both)` is the correct interruption mechanism: on Linux it causes a blocked `readv()` to return 0 (EOF), which propagates as `error.HttpConnectionClosing` or `error.ReadFailed` through `std.http.Server.receiveHead()`.

Four options were prototyped and tested.

**Option A: Connection max-age (rejected):**
A deadline is set once at accept time and checked at the top of each keep-alive loop iteration. This is a connection lifetime cap, not a per-idle-gap timeout. The check fires only when `receiveHead()` returns, so it cannot interrupt a client that goes permanently idle. A thread is held indefinitely inside `receiveHead()` once the client stops sending. Option A is not wired into the server.

**Option C: Watchdog thread per connection (rejected):**
Spawning one OS thread per accepted connection eliminates the permanent-idle problem. Each watchdog sleeps for `timeout_ms` and calls `stream.shutdown(.both)` if the connection has not finished. Tested and working: fires at exactly 5.006s. Rejected because it adds one OS thread per active connection (with a 64KB virtual stack each), which multiplies memory pressure under load. Option D achieves the same coverage at zero extra threads.

**Decision:** Adopt B + D as two independent, orthogonal layers. Remove `response_timeout_ms` and replace it with two config fields:

- `conn_timeout_ms: u32 = 0` (**Layer D**): `ConnRegistry` embedded in `HttpServerImpl`. On each 500ms timer tick, `registry.evict()` scans active connections and calls `stream.shutdown(.both)` on any whose deadline has passed. `handleConnection` registers a `ConnEntry` on accept and deregisters (via `defer`) on close. Effective in model 2 only (the timer thread already exists). Eviction precision: `[deadline, deadline + 500ms]`.

- `handler_timeout_ms: u32 = 0` (**Layer B**): `ctx.deadline` is set from config before each handler dispatch. Handlers opt in by calling `ctx.timedOut()` between expensive steps and responding with 408 early. Zero overhead when disabled (null check on deadline). Works in both model 1 and model 2.

The two layers are orthogonal: D fires if the client stalls before the handler ever starts, B fires if the handler takes too long after it starts. Both default to 0 (disabled) so existing code is unaffected.

**Consequences:**
- `response_timeout_ms` removed: callers that set it must migrate to `conn_timeout_ms` and/or `handler_timeout_ms`.
- Layer D fires `shutdown(.both)` which causes `receiveHead()` to return `error.ReadFailed`. This error case is now handled in `handleConnection`.
- Layer B is cooperative: a handler that does not call `ctx.timedOut()` is never interrupted. This is intentional (forced cancellation across arbitrary Zig code is not safe).
- `conn_timeout_ms` should be >= `handler_timeout_ms`. If D fires while the handler is mid-response, the connection closes abruptly instead of sending a clean 408.
- Option C is the correct choice for deployments where per-connection jitter must be bounded to exact milliseconds rather than `[deadline, deadline + 500ms]`.

---

## ADR-019: Router routes, MultiArrayList (SoA) layout

**Status:** Accepted

**Context:** `Router.routes` was `ArrayList(Route)` where `Route = {path, handler, kind}`. Dispatch Pass 2 (PARAM) and Pass 3 (PREFIX) iterate the list filtering by `kind` before accessing `path` or `handler`. AoS interleaves all three fields in memory, so iterating `kind` pulls `path` and `handler` into cache even when they are not yet needed.

**Decision:** Replace `ArrayList(Route)` with `MultiArrayList(Route)`. Each field (`kind`, `path`, `handler`) is stored in its own contiguous array. Pass 2 iterates only `items(.kind)` with an index, touching `items(.path)[i]` and `items(.handler)[i]` only on a PARAM match. Pass 3 zips `items(.kind)` and `items(.path)` without loading `items(.handler)` until a prefix candidate is confirmed.

**Consequences:**
- `routes.items.len` becomes `routes.len`. Field access becomes `routes.items(.field)[i]`
- `init()` simplified: `routes` default-initializes to `.{}`, no explicit `.empty` needed
- `append()` and `deinit()` signatures are unchanged
- Unit tests in `router.zig` updated, integration tests and examples unchanged (public API unaffected)
- Practical gain is proportional to PARAM and PREFIX route count, most production deployments favour exact routes (O(1) via `exact_map`) so the improvement is cache-coherence rather than algorithmic

---

## ADR-020: Http.Client, wrapping std.http.Client with typed response and named errors

**Status:** Accepted

**Context:** zix had a server but no client. Callers writing integration test harnesses, service-to-service calls, or webhook senders needed to reach out to HTTP endpoints. The stdlib provides `std.http.Client` but its API is low-level: callers manage redirect buffers, body readers, head invalidation, and connection pooling themselves. There was no concept of a size-capped response, a typed response object the caller owns, or a named error set.

**Decision:** Implement `zix.Http.Client` as a thin wrapper over `std.http.Client` that adds:

1. **Typed config (`HttpClientConfig`)**: allocator, io, connect/response/read timeouts, body cap, redirect policy, user-agent. All required fields are named. All optional fields have defaults.

2. **Connect timeout**: passed to `std.http.Client.connectTcpOptions(.{ .timeout = Io.Timeout })`. This is the only timeout enforced in v1 because `connectTcpOptions` exposes a timeout parameter. Response and read timeouts require IO-level wiring and are deferred.

3. **Body size cap**: `body_reader.allocRemaining(gpa, .limited(max_response_body))` returns `error.StreamTooLong`, which is remapped to `error.BodyTooLarge`. This prevents silent OOM on large or malicious responses.

4. **Head bytes copy**: `std.http.Client.Response.head.bytes` points into the connection's read buffer. It is invalidated by `response.reader()` and becomes dangling after `req.deinit()`. The client copies `head.bytes` via `gpa.dupe` before calling `response.reader()`. This makes `ClientResponse.header()` and `iterateHeaders()` safe after the request completes.

5. **Caller-owned `ClientResponse`**: holds `status_code: u16`, `head_bytes: []u8`, `body_data: []u8`, all owned by `config.allocator`. Caller calls `deinit()` to free. No hidden lifetime coupling to the `HttpClient` instance.

6. **Named errors**: `error.InvalidUrl` (parse failure, unsupported scheme, missing host) and `error.BodyTooLarge` surface before the caller needs to inspect stdlib error sets. `error.Timeout` from `std.Io` propagates unchanged for connect timeouts.

**Alternatives considered:**

- *Build on raw TCP streams (like UDS client)*: would require reimplementing HTTP/1.1 framing, chunked transfer, header parsing, redirect following, and connection pooling. Too much scope for v1. `std.http.Client` provides all of this correctly.

- *Return `std.http.Client.Response` directly*: the caller would inherit all the head invalidation and buffer lifetime constraints, plus would need to manage the connection pool state. Defeats the "explicit over implicit" goal.

- *Single `fetch()` call path*: `std.http.Client.fetch()` hides connection-level details. It does not expose a way to inject a per-call connect timeout, making `connect_timeout_ms` unimplementable. The lower-level `connectTcpOptions` + `request()` + `receiveHead()` path was chosen instead.

**Consequences:**
- One extra heap allocation per request (head bytes copy via `gpa.dupe`). Size is the raw head (status line + headers), typically a few hundred bytes.
- `ClientResponse` is not safe to use after `deinit()`.
- TLS (HTTPS) is out of scope for `zix.Http.Client`. The library is a network backend: for the client wrapper, TLS termination is delegated to an upstream reverse proxy. `std.http.Client` supports TLS internally, but the wrapper does not expose, configure, or test it. Plain HTTP on the internal network is the intended usage. (A native zix TLS server landed later: ADR-045 to ADR-048.)
- `response_timeout_ms` and `read_timeout_ms` are stored in config and documented as "v1: not yet enforced" so callers can set them now and get enforcement in a future release without an API change.

---

## ADR-021: DispatchModel enum (POOL / ASYNC / MIXED)

**Status:** Accepted

**Context:** The original `HttpServerConfig` used `workers: usize` to select between two concurrency modes: `workers = 1` for single-accept `io.async()` dispatch and `workers = 0` / `workers = N` for the work-queue thread pool. A third mode (N accept threads each dispatching via `io.async()` without a ConnQueue) existed as a natural middle ground. The `workers` field was overloaded: a value of `1` changed the dispatch strategy entirely rather than setting an accept thread count. This was non-obvious and not self-documenting at call sites.

**Decision:** Introduce `DispatchModel = enum(u8) { ASYNC = 0, POOL = 1, MIXED = 2 }` as a named field `dispatch_model: DispatchModel` in `HttpServerConfig`. The three models are:

- `.POOL`: N accept threads push to a shared `ConnQueue`. M pool threads pop and handle connections with synchronous blocking I/O. Best throughput under high connection counts. `workers` controls accept thread count. `pool_size` controls pool thread count.
- `.ASYNC`: Single accept thread dispatches each connection via `io.async()`. Preferred for SSE and WebSocket: long-lived connections do not hold pool threads. `workers` and `pool_size` are ignored.
- `.MIXED`: N accept threads each dispatch via `io.async()` directly, no `ConnQueue`. Balanced throughput and latency. `pool_size` is ignored.

The old `workers = 1` shorthand for single-accept dispatch is removed. Callers wanting that behavior set `dispatch_model = .ASYNC`.

`workers = 0` now means cpu_count accept threads for `.POOL` and `.MIXED`. The former default of 2 was an undercount on machines with many cores.

**Consequences:**
- Breaking change: callers using `workers = 1` must migrate to `dispatch_model = .ASYNC`.
- `dispatch_model` is self-documenting at the call site. The three strategies are explicit enum variants, not magic `usize` values.
- `pool_size` is silently ignored for `.ASYNC` and `.MIXED` (no error, documented in `HttpServerConfig`).
- Enum backing type `u8` follows the project convention for all named enums.
- Later evolution: `.EPOLL` (ADR-034) and `.URING` (ADR-037) joined the enum as `EPOLL = 3` / `URING = 4`, and `dispatch_model` became a required field with no default (`.ASYNC = 0` is the zero-init value), so a config names its model explicitly. See ADR-050 for the whole-family taxonomy.

---

## ADR-022: zix.Tcp raw stream server and client

**Status:** Accepted

**Context:** After the HTTP engine was complete, the next protocol layer was a generic raw TCP stream server: no HTTP framing, no router, user-defined handler owns the stream. The HTTP PoC in `rnd/` proved all three dispatch models (POOL, ASYNC, MIXED) work for TCP. The question was how to expose this as a library API without duplicating HTTP internals.

**Decision:**

- `zix.Tcp.Server` and `zix.Tcp.Client` are standalone types in `src/tcp/server.zig` and `src/tcp/client.zig`. No shared base with `zix.Http.Server`, same standalone-per-protocol principle as `zix.Uds.Server`.
- `HandlerFn = *const fn(stream: std.Io.net.Stream, io: std.Io) void`: identical signature to `zix.Uds.HandlerFn`. The handler owns the stream and must close it before returning.
- `TcpServer.run(io)` / `runWith(io, handler)`: io is passed as a parameter (not stored in config). The caller controls the `std.Io` backend lifetime.
- All three dispatch models (POOL, ASYNC, MIXED) apply with the same `ConnQueue` + thread spawn pattern from `zix.Http.Server`. `DispatchModel` is defined once in `src/tcp/config.zig` and imported by `src/tcp/http/config.zig` (single source of truth for all TCP-based protocols).
- Frame format: `[u32 big-endian payload_len][payload bytes]`. Big-endian (network byte order) is chosen for TCP because it is the network convention and matches what other protocol libraries expect. `zix.Uds` uses the same big-endian frame format (ADR-010), despite having no interop requirement.
- `initArgs()` on the server and `connectArgs()` on the client parse `--ip` and `--port` from CLI args, following the same CLI-arg override pattern used across the engines.

**Consequences:**
- `zix.Tcp.Http.*` and `zix.Tcp.Server`/`Client` coexist under the same `zix.Tcp` namespace: HTTP is the high-level protocol, raw TCP is the low-level stream layer.
- `zix.Tcp.Server` does not allocate from a user-provided allocator. The `ConnQueue` uses `smp_allocator` directly, same approach as the HTTP server.
- The built-in `echoHandler` uses `takeVarInt(u32, .big, 4)` and `readSliceAll` (vs. the `readSliceShort` loop in `zix.Uds.echoHandler`), consistent with the PoC pattern confirmed during the TCP RnD phase.
- Future Fix protocol (`zix.Tcp.Fix.*`) follows the same standalone-per-protocol pattern and will not be built on top of `zix.Tcp.Server`.

---

## ADR-023: zix.Logger, structured thread-safe event logger

**Status:** Accepted, Implemented (2026-05-23)

**Context:** Every server implementation (HTTP, TCP, UDP, UDS, FIX, gRPC) needs a logging layer. `std.debug.print` is unsafe on background OS threads because it routes through `std.Options.debug_io`, a global `Io.Threaded` singleton: calling it from any spawned thread races with the test runner's IPC channel and causes a panic. A logging primitive that is safe on background OS threads without a `std.Io` dependency is required.

**Decision:** Implement `zix.Logger` as a struct with a per-instance spinlock (atomic CAS) protecting a 64 KB write buffer and file descriptor. All I/O uses raw `std.posix.write` (no `std.Io`, no `std.debug.print`). Protocol-specific log methods provide machine-parseable lines without post-processing: `system()`, `access()` (HTTP), `conn()` (TCP), `packet()` (UDP), `frame()` (UDS), `session()` (FIX), `rpc()` (gRPC). Each server config accepts `logger: ?*Logger = null`. The logger is optional and the server is silent when null.

**Consequences:**
- All log methods are safe to call simultaneously from any OS thread including thread-pool workers, accept threads, and connection handlers.
- No `std.Io` allocation per log call. The write buffer is flushed on date rollover, sequence rotation, explicit `logger.flush()`, or `logger.deinit()`.
- File rotation is daily (`YYYY-MM-DD/` subdirectory) with per-file sequence numbering. `save_path` must exist before `Logger.init`: the logger does not create it.
- Console output is controlled by `ConsoleMode` (`.OFF`, `.DEBUG_ONLY`, `.ALWAYS`). Both file and console paths are guarded by `save_min_level` / `console_min_level`.
- `access()` derives log level from HTTP status: 2xx/3xx=INFO, 4xx=WARN, 5xx=ERROR. `rpc()` derives from grpc-status code.

---

## ADR-024: zix.Fix, FIX 4.x session layer as standalone server

**Status:** Accepted, Implemented (2026-05-23)

**Context:** FIX (Financial Information eXchange) protocol is the dominant messaging standard for financial trading systems. It uses SOH (0x01) as a field delimiter (not a length prefix), which makes it incompatible with the `readSliceShort` recv pattern used by HTTP. A standalone server following the same config and dispatch-model pattern as `zix.Tcp` is required, with the session layer (Logon/Logout/Heartbeat handling) built in so callers do not implement it themselves.

**Decision:** Implement `zix.Fix` in `src/tcp/fix/`. `serveConn` is the core loop: it accumulates bytes via `takeByte` until `findMessageEnd` detects a complete message, then dispatches internally by MsgType (tag 35). Logon/Logout/Heartbeat/TestRequest are handled automatically, all other messages are echoed. No handler callback needed. Session state (comp_id, seq_num) is stack-local to `serveConn`, no heap allocation in the message loop. All 4 dispatch models apply. `.ASYNC` suits FIX sessions because they are long-lived. `.EPOLL` runs natively on Linux (single epoll accept loop, `FdQueue` ring buffer, pool workers hold each connection for its full lifetime, same pattern as `zix.Grpc`). Non-Linux falls back to `.POOL`.

**Consequences:**
- `takeByte` in a loop avoids the `readSliceShort` deadlock: the reader's internal buffer absorbs the full TCP segment, subsequent `takeByte` calls drain it with no extra syscalls.
- `serveConn` uses only stack buffers (`recv_buf[MAX_MSG_SIZE * 2]`, `fields[MAX_FIELDS]`). No per-request allocation.
- `buildMessage` computes and embeds the checksum. `verifyChecksum` validates incoming messages. Bad checksum closes the connection without a reply.
- `std.debug.print` is absent from all thread entry functions, learned from the `std.Options.debug_io` test runner IPC panic.
- `FixClient` provides a typed client (`logon`, `logout`, `sendMessage`, `recvMessage`) for tests and examples.

---

## ADR-025: `reuse_address = true` on all dispatch models (SO_REUSEADDR + SO_REUSEPORT)

**Status:** Accepted

**Context:** Every server in zix (Http, Http2, Grpc, Tcp, Fix) calls `addr.listen(io, .{ .reuse_address = true })`. In Zig's `std.Io.Threaded`, `reuse_address = true` sets both `SO_REUSEADDR` and `SO_REUSEPORT` on POSIX. `SO_REUSEPORT` is strictly required by the POOL dispatch model: each accept thread calls `addr.listen()` on the same port independently, without it the second bind fails with `EADDRINUSE`. The choice was whether to set it conditionally (POOL only) or unconditionally (all models).

**Decision:** Apply `reuse_address = true` unconditionally on every `addr.listen()` call regardless of dispatch model. All models share the same socket setup path: no branching on `dispatch_model` at the socket level. This is socket-level behavior, it is documented here and inline in source, not exposed as a config field.

**Consequences:**
- POOL works correctly: all accept threads bind to the same port and the kernel load-balances incoming connections across them.
- ASYNC, MIXED, and EPOLL also receive `SO_REUSEPORT` as a side effect. Multiple server instances on the same port do not crash: the kernel silently distributes connections between them.
- This is intentional. Port-sharing between processes is a valid deployment pattern (rolling restart, staged rollout). Examples that share a port number coexist without error when run simultaneously for the same reason.
- No `ServerConfig` field is added to expose or toggle this behavior.

---

## ADR-026: zix.Http1 writeSimple, combined buffer beats writev for small bodies

**Status:** Accepted

**Context:** `zix.Http1.writeSimple` (the EPOLL hot path) sends a status line, headers, and a body. Two strategies were profiled in ReleaseFast. Strategy A (`writev` with two `iovec` entries) is zero-copy: the header buffer and the body slice are passed as separate segments, no concatenation. Strategy B copies the header and body into one contiguous stack buffer, then issues a single `write()`. The theory favored A (no copy), the measurement did not.

**Decision:** Use a contiguous buffer plus a single `write()` for bodies up to 3840 bytes (header buffer is a 256-byte stack array, total fits a 4096-byte stack buffer). For bodies above 3840 bytes, fall back to inline `writev` to avoid copying a large payload. The Date header is filled by `cachedDate()`, which calls `clock_gettime` only every 256 requests via a thread-local tick counter. The response header itself is built by `buildSimpleHeader`, a direct byte encoder (`appendStatusCode` / `appendDec` / `appendBytes`) replacing `std.fmt.bufPrint`.

**Consequences:**
- Small-body throughput rose from ~450k to ~612k req/s at c128 on the reference machine. A single contiguous `write()` outperforms `writev` with two small segments because the per-syscall `iovec` setup and kernel gather cost exceeds the cost of copying ~100 bytes on the stack.
- Large bodies (over 3840 bytes) keep zero-copy semantics through the `writev` fallback, so big responses pay no 4KB stack-copy penalty.
- Benchmark caveat: loopback `wrk` at high concurrency is roughly 85 percent kernel-bound and highly variance-prone. Comparisons must be run back-to-back in one script under identical conditions, never from separate captures. See docs commentary and the project memory note.

---

## ADR-027: Response header default lowered to `.MINIMAL` (16)

**Status:** Accepted

**Context:** `HttpServerConfig.max_response_headers` controls the per-request arena slot count for custom response headers (ADR-009). The default was `.COMMON` (32). Most handlers in practice emit far fewer than 16 custom headers (a bare service adds 2 to 6), so the 32-slot default over-provisioned the per-request arena for the common case. The `zix.Http1` engine made the same move at the compile-time level (`MAX_HEADERS` 32 to 16, plus a runtime `Http1ServerConfig.max_headers: u8 = 16`).

**Decision:** Lower the default to `.MINIMAL` (16) for both `zix.Http` (`max_response_headers`) and `zix.Http1` (`max_headers` and the `MAX_HEADERS` cap). Callers who need more raise the tier explicitly (`.COMMON`, `.LARGE`, `.EXTRA_LARGE`, or `.{ .CUSTOM = N }`).

**Consequences:**
- Worst-case per-response header arena footprint drops from ~1 KB (32 slots) to ~512 bytes (16 slots), tightening the DoS bound for a handler that loops on `addHeader()`.
- Behavioral change for any deployment that relied on the implicit 32-slot cap and added 17 to 32 custom headers. Such handlers now hit `error.TooManyHeaders` until the tier is raised. Documented in `docs/headers-en.md` and `docs/headers-id.md`.
- The dynamic-growth allocation strategy (ADR-009) is unchanged. Only the default cap value moved.

---

## ADR-028: Version selector on the shared `zix.Http.Client`

**Status:** Accepted

**Context:** The `zix.Http1` engine needed a client example (`examples/http1_client.zig`). A separate raw `zix.Http1.Client` would have duplicated URL parsing, TLS, redirect handling, and connection pooling that `zix.Http.Client` already provides by wrapping `std.http.Client`. The Zig std roadmap adds HTTP/2 to that same `std.http.Client`, so a single client is the natural path to multi-version support. The open question was how to express the protocol version without a separate client per version.

**Decision:** Add a `version` field to `HttpClientConfig`, typed `Version` (`HTTP_1`, `HTTP_2`, `HTTP_3`, CAPITAL variants, no `auto`, default `.HTTP_1`), exported as `zix.Http.ClientVersion`. `request()` guards on it: `HTTP_1` proceeds (HTTP/1.1 over `std.http.Client`), `HTTP_2` and `HTTP_3` return `error.UnsupportedVersion`. Do not build a separate `zix.Http1.Client`.

**Consequences:**
- One client surface speaks HTTP/1.1 today and works against any HTTP/1.1 server, including the raw `zix.Http1` server. The `http1_client` example uses it with `.version = .HTTP_1`.
- The API is forward-shaped: when an h2 (or h3) backend lands, it slots in behind the existing enum value with no caller-facing signature change.
- A caller selecting `HTTP_2` or `HTTP_3` fails fast and explicitly rather than silently downgrading.

---

## ADR-029: `zix.Http1` per-handler deadline via thread-local, not a ctx object

**Status:** Accepted

**Context:** `zix.Http` enforces a per-handler budget through `ctx.isExpired()`, where the server sets `ctx.deadline` before dispatch (ADR-018). The `zix.Http1` handler signature is `fn(head, body, fd) void` with no context parameter, kept deliberately lean for the zero-alloc hot path. Adding a `ctx` parameter would have rippled through `Router`, every example, and the dispatch loop, and would have widened the hot-path call.

**Decision:** Add `Http1ServerConfig.handler_timeout_ms`. Store the deadline in a `threadlocal` in `core.zig`, armed by the server (`setTimeout(config.handler_timeout_ms)`) before every dispatch across all four models (`serveConn` via `ServeOpts`, `serveEpollConn` via a parameter). Expose `zix.Http1.isExpired()` and `zix.Http1.setTimeout()` as free functions so handlers query and override their budget without a ctx object. Add `408 Request Timeout` to `statusPhrase`.

**Consequences:**
- The handler signature stays `fn(head, body, fd) void`. No breaking change to `Router` or existing examples.
- The deadline is per-worker-thread, which matches the shared-nothing dispatch model (each connection is served by one thread for the call's duration).
- `handler_timeout_ms == 0` leaves the thread-local at 0, so `isExpired()` is a cheap always-false check with no clock syscall on the disabled path.
- All current dispatch entry points arm the deadline (`serveConn` via `ServeOpts`, `serveEpollConn` via a parameter). A handler that overrides its own budget calls `setTimeout()` directly.

---

## ADR-030: `zix.Http1` engine-owned WebSocket frame loop with per-event write coalescing

**Status:** Accepted

**Context:** The first `zix.Http1` WebSocket example did the handshake in the handler and then ran its own `while (true)` blocking `std.posix.read` loop to echo frames. Under `.EPOLL` the engine accepts with `accept4(SOCK.NONBLOCK)`, so that read returned `EAGAIN` on the first empty poll and the handler returned at once: the handshake succeeded but no frame was ever echoed (0 frames). Even where the loop did work (the blocking `.ASYNC` sockets), it parked one worker thread on a single connection for that connection's whole lifetime, which caps concurrency at the worker count. A reference io_uring echo server keeps every connection in a completion loop instead, so all connections progress at once.

**Decision:** Make the WebSocket frame loop engine-owned under `.EPOLL`. A handler calls `WebSocket.serve(fd, key, on_frame)`, which performs the handshake and records a thread-local handoff (`core.requestWebSocket`). Right after the handler returns, the epoll loop reads the handoff (`core.takeWebSocket`), flips the connection to WebSocket mode (`Conn.ws`), and from then on routes that fd to `serveEpollWs`. Each readable event reads once (the loop is level-triggered, so more bytes re-fire) and `WebSocket.pump` parses every complete frame, invoking `on_frame` for text and binary, auto-ponging ping, and auto-echoing close. The callback is `fn(fd, opcode: u8, payload) void`: `opcode` is the raw RFC 6455 value to keep the type in `core.zig` and avoid a `core` to `websocket` import cycle. All frames produced during one readable event are staged in a per-event `SendSink` and flushed in a single `write()`, so a pipelined burst costs one syscall instead of one per frame. `buildHeader` was split out of `buildFrame` for the staged path. On `.ASYNC` and `.POOL` the handoff is cleared and the connection ends after the handler returns: engine-owned WebSocket is `.EPOLL` only.

**Consequences:**
- The handler signature stays `fn(head, body, fd) void`. WebSocket support adds no ctx and no router change, the handler just calls `WebSocket.serve` instead of looping.
- No worker is parked per connection. One epoll worker drives many WebSocket connections, echoing each on readiness.
- Write coalescing is the dominant pipelined win. Without it a 16-deep pipelined burst issued 16 writes per event.
- A frame larger than the connection read buffer can never complete: `serveEpollWs` closes such a connection rather than spin. For the echo workload (small frames) this never triggers.
- A manual blocking-loop WebSocket is still possible under `.ASYNC` or `.POOL` (those sockets are blocking), but it carries the old one-worker-per-connection cap and does not use the handoff.

---

## ADR-031: `zix.Grpc` `.EPOLL` multiplexed event loop, inline dispatch, and hot-path coalescing

**Status:** Accepted

**Context:** The first `zix.Grpc` `.EPOLL` model was not event-multiplexed. A single accept loop fed a `FdQueue`, and a pool of `max(10, cpu*2)` worker threads each popped one connection and ran the full h2c connection lifetime with blocking reads. Concurrency was therefore capped at the worker count: under a load of 256 or 1024 connections only ~24 were ever served at once. The per-request cost was also high: a unary reply issued seven `write()` calls (HEADERS, DATA, trailer, each a separate frame-header write plus a payload write), plus two `WINDOW_UPDATE` writes per inbound DATA frame, plus a 9-byte frame-header read then a payload read per frame, with `TCP_NODELAY` on. Each connection also allocated a 16-slot stream table with a 64 KB inline body per slot (~1.1 MB per connection). Server-streaming routes spawned one thread per stream. Under benchmark load, unary throughput plateaued at ~110k req/s regardless of connection count and streaming sat at ~2.6k calls/s.

**Decision:** Re-architect the `.EPOLL` model into a shared-nothing multiplexed event loop and cut the per-request work to a near-minimum syscall count.

- Multiplexing: each worker owns a private `SO_REUSEPORT` listener, its own epoll instance, and a private fd-indexed `GrpcConnTable`. The kernel load-balances new connections across the per-worker listeners. `worker_count = pool_size` (0 selects cpu count). The h2 connection loop became a resumable state machine (`GrpcMuxConn`): a per-connection read accumulator persists across readable events and holds any partial frame, a handshake phase machine (`await_preface` / `await_upgrade` / `await_preface2` / `h2`) replaces the blocking preface read, and `muxFrameLoop` processes every complete buffered frame and returns to epoll on `EAGAIN`.
- Inline dispatch: in the `.EPOLL` model every route, including server-streaming, is dispatched inline on the worker (no per-stream thread, no connection write mutex), because the worker owns the connection. A streaming handler runs on the event loop and must stay bounded.
- Per-event write coalescing: all response frames produced while handling one readable event (initial HEADERS, every DATA, the trailer, and any control frame) are staged in a per-connection `ReplyStage` cork and flushed in a single `write()`. A unary reply is one write instead of seven.
- Flow control: `SETTINGS_INITIAL_WINDOW_SIZE` is raised to 16 MB and the connection receive window is bumped once after the handshake, so small request bodies never trigger a per-DATA `WINDOW_UPDATE`. The connection window is replenished in bulk only past a threshold.
- Buffered reads: frame headers and payloads are served from the connection read buffer, so a HEADERS plus DATA pair costs one `read()` rather than four.
- Right-sized buffers: per-stream `body` and `header_scratch` are slices into per-connection backing buffers sized to `max_body` / `max_header_scratch`, not fixed inline arrays.
- Cached reply blocks: the constant reply headers for the common case are HPACK-encoded once at comptime - `:status 200` plus `content-type: application/grpc+proto` for the initial HEADERS, and `grpc-status: 0` for the OK trailer. `buildGrpcHeaders` and `buildGrpcTrailer` memcpy the cached block and stamp the 9-byte frame header instead of re-running the HPACK encoder (two 61-entry linear scans plus Huffman per header). The dynamic encoder is the fallback for other content-types or statuses.

The blocking `serveGrpcConn` and `serveGrpcLoop` are retained unchanged for `.ASYNC`, `.POOL`, and `.MIXED`.

**Consequences:**
- Unary throughput rose from ~110k to ~420k req/s at 256 connections. Streaming rose from ~2.6k to ~28k calls/s. On isolated (separate-cpuset) cores the server is CPU-saturated and scales near-linearly at ~38-39k req/s per core. The earlier lower result at 1024 connections was a shared-core measurement artifact where the load generator and the server contended for the same cores.
- `pool_size` changed meaning for `.EPOLL`: it is now the multiplexing worker count (0 = cpu), not a blocking pool size. A large value no longer helps and oversubscribes the scheduler.
- The advertised `max_streams` must be at least the client's concurrent-stream count, or the client's optimistically opened streams get `REFUSED_STREAM` at connection start. The HttpArena entry sets `max_streams = 128` (h2load uses `-m 100`).
- `.EPOLL` streaming handlers must be bounded: a long-running stream blocks the other connections on that worker. Unbounded streaming should use `.ASYNC`.
- Non-blocking writes use the staged flush. `EAGAIN` is treated as a broken pipe and drops the connection. This never triggers for the small replies of the benchmark, but a slow client with a large reply could be dropped: a future `EPOLLOUT` backpressure queue would remove that edge.
- The h2c upgrade path in the multiplexed loop is minimal: it returns `400` without an `Upgrade: h2c` header (the validate probe path) and `101` then the connection preface with one, but it does not serve an initial request carried on stream 1 of the upgrade. Prior-knowledge clients are unaffected.
- A one-line change in `HpackEncoder.writeString` (annotating the Huffman result as `?usize`) lets the encoder run at comptime so the cached blocks can be built there.

---

## ADR-032: `EPOLL_MAX_EVENTS = 512`, one named epoll batch constant across all servers

**Status:** Accepted

**Context:** Every native epoll worker (`zix.Tcp`, `zix.Http`, `zix.Fix`, `zix.Grpc`, `zix.Http1`) calls `epoll_wait` with a fixed-size `epoll_event` array. That size is the maximum number of ready events the worker drains in one syscall. The value was `256` everywhere, expressed three different ways: a named file-level `epoll_max_events` in `tcp` and `http`, and an inline `const max_events` literal in `fix`, `grpc`, and `http1`. With one `SO_REUSEPORT` listener and one epoll instance per worker, a worker on a 12-core box at 4096 connections holds roughly 341 fds, so more than 256 can be readable in a single tick. A 256 cap then forces a second `epoll_wait` to drain the remainder, an extra syscall per loop that appears only once the ready set exceeds the cap.

**Decision:** Raise the batch to `512` and express it as one named, documented file-level constant `EPOLL_MAX_EVENTS: usize = 512` in each of the five server files, used for both the `[N]epoll_event` array size and the `epoll_wait` count argument. The inline `256` literals and the lowercase `epoll_max_events` consts are removed, and the type is unified to `usize`. 512 covers a worker's ready-fd set in one syscall at the high connection counts where the old cap was binding.

**Consequences:**
- A/B perf (`EPOLL_MAX_EVENTS` 256 vs 512 on the same release build, fixed-response handler, profiled with `perf stat` on userspace counters) showed the change is neutral at c128 and c1024, where the ready set per worker is well under 256 so the cap never bound, and a small gain at c4096, where throughput rose ~8% and userspace cycles per request fell. That matches the predicted mechanism: fewer `epoll_wait` syscalls only where the ready set exceeded 256.
- Cost is one `epoll_event` array per worker growing from ~6 KB to ~12 KB of stack. Negligible against the 512 KB worker stacks.
- No public API change. The constant is private and not configurable. The value is a tuned default, not a knob.
- The c2048+ throughput collapse seen on a shared-core loopback box is environmental (load generator and server contend for the same cores). It is neither caused nor addressed by this constant.
- Later evolution: the constant is now named `n` per dispatch file, and the shared value diverged as engines were tuned individually. `zix.Tcp` / `zix.Fix` / `zix.Http2` / `zix.Grpc` stay at 512, `zix.Http` uses 1024, and `zix.Http1` uses 4096 (the TLS mux paths also use 4096). The unify decision held, per-engine tuning later raised two of the five.

---

## ADR-033: `zix.Http1` router gains `.PREFIX` and `.PARAM`, params via thread-local

**Status:** Accepted

**Context:** The `zix.Http1` comptime router was exact-match only (`std.mem.eql` over the route table), while the higher-level `zix.Http` router has supported `.EXACT` / `.PREFIX` / `.PARAM` since ADR-004. Any prefix or path-param routing in an Http1 server had to be hand-written in the dispatch function with `startsWith` and `splitScalar` (as `examples/http1_paths.zig` did). The capture problem is the reason the gap persisted: the `zix.Http` matcher writes captured params to `req.path_params`, but the Http1 handler is `fn(head: *const ParsedHead, body, fd) void` with no `Request` and no per-call mutable state to write into (the same lean zero-alloc signature defended in ADR-029).

**Decision:** Bring the Http1 router to parity with the Http router. Add `RouteKind { EXACT, PREFIX, PARAM }` and a `kind` field (default `.EXACT`) to `zix.Http1.Route`, and partition the route table at comptime into a `StaticStringMap` (exact), a PARAM array, and a PREFIX array. Dispatch keeps the ADR-004 priority: exact (O(1) hash) > param (first-registered wins) > prefix (longest wins). Param capture reuses the ADR-029 model: matched `:name` segments are written to a per-handler `threadlocal` store in `router.zig`, read back through a new free function `zix.Http1.pathParam(name)` instead of a ctx or `Request`. The store is a fixed array capped at `MAX_PATH_PARAMS = 8`, so capture is zero-alloc. The prefix pass guards the boundary index behind `startsWith` (`p[route.path.len]` is only read once `p.len >= route.path.len`), and the same guard was applied back to the `zix.Http` router, which had the index ordered before the `startsWith` check.

**Consequences:**
- The handler signature is unchanged and `.kind` defaults to `.EXACT`, so every existing exact-only Http1 route table compiles and behaves identically. No breaking change.
- Param values are thread-local and valid only for the dispatch call (they borrow the request path), which matches the shared-nothing model where one worker serves one connection at a time. A handler that needs a param past its own return must copy it.
- Capture is capped at 8 params per match. A pattern with more `:segments` than that fails to match rather than overflowing.
- The `zix.Http` prefix pass no longer reads one byte past a short request path. In ReleaseFast this was a harmless out-of-bounds read masked by the `and`, in Debug or ReleaseSafe it was a panic on any request path shorter than a registered prefix.
- `examples/http1_paths.zig` still demonstrates manual `startsWith` / `splitScalar` routing on purpose (custom matching beyond the three kinds). Its prior comment claiming the router is exact-only was corrected.

---

## ADR-034: `zix.Http` `.EPOLL` shared-nothing architecture

**Status:** Accepted

**Context:** The original `zix.Http` `.EPOLL` model used a centralized design: one accept thread pushed accepted connection streams to a shared `ConnQueue` (mutex + condvar + ring buffer), and a pool of `max(10, cpu_count * 2)` worker threads popped from the queue and called `handleOneRequest`. Under benchmark load at c1000, the `ConnQueue` mutex became the bottleneck. Throughput was 428k req/s vs 480k for `zix.Http1` (same shared-nothing architecture, 11% gap). `pool_size` was the relevant config field.

**Decision:** Replace the centralized model with a shared-nothing architecture matching `zix.Http1`. Each worker binds its own `SO_REUSEPORT` listener, creates its own `epoll` instance, and runs its own level-triggered event loop. The kernel distributes new connections across per-worker listeners. No `ConnQueue`, no mutex, no condvar, no fd handoff between threads.

- `workers` (not `pool_size`) is now the EPOLL worker count for `zix.Http`. `0` selects cpu_count.
- `pool_size` is ignored for `zix.Http` `.EPOLL` (it still applies to `.POOL`).
- Level-triggered `EPOLLIN` replaces `EPOLLONESHOT`: connections stay registered after each request and re-fire when new data arrives. No explicit re-arm.
- Accepted fds are blocking: `handleOneRequest` does a synchronous recv/parse/dispatch/send, then the worker returns to `epoll_wait`.
- `handleOneRequest` is unchanged: no new non-blocking logic, no per-connection state table.

**Consequences:**
- Throughput: 428k to 451k req/s at c1000 (`wrk -c1000 -t4 -d10s`), closing the gap vs `zix.Http1` from 11% to 6.8%.
- Remaining 6.8% gap is structural: `zix.Http` allocates an `ArenaAllocator` per connection and builds a `Request` / `Response` / `ParsedHead` (64-entry header array) per request. `zix.Http1` uses zero-alloc stack-local parsing. This gap is not closeable by architecture alone.
- The `pool_size` field is silently ignored for `.EPOLL` (same behavior as `.ASYNC` and `.MIXED` already ignored it). Existing callers that set `.pool_size = N` with `.EPOLL` must migrate to `.workers = N`.
- SSE and WebSocket are still not suitable for `.EPOLL`: blocking reads park the worker for the connection's lifetime. Use `.ASYNC`.

---

## ADR-035: gRPC mux per-connection staging, cached SETTINGS, and TCP_CORK

**Status:** Accepted

**Context:** The multiplexed gRPC EPOLL event loop (ADR-031) stages a reply (HEADERS + DATA + trailer) into a `ReplyStage` buffer and flushes it in one `write()`. The buffer was an inline `[4096]u8` on `GrpcMuxConn`. A streaming handler that emits thousands of messages overflowed 4096 bytes repeatedly, forcing one `write()` per overflow (~85 KB streamed in ~21 flushes). The server SETTINGS frame was re-encoded from a parameter loop on every new connection. Streaming handlers produced many small intermediate flushes, each becoming its own TCP segment.

**Decision:** Make the reply stage backing caller-owned and give the mux connection a larger buffer plus a precomputed handshake, and cork streaming output.

- `ReplyStage.buf` is now a `[]u8` slice supplied by the caller. The blocking inline path (`dispatchGrpcInline`) passes a 4096-byte stack array (unary replies are small). The mux path passes the connection's own buffer.
- `GrpcMuxConn` owns a 64 KB `stage_buf`. A ~5000-message streaming call (~85 KB peak) flushes in two writes, and ~100 concurrent unary replies (~6 KB) coalesce into a single write.
- `GrpcMuxConn.init` calls `buildSettingsFrame` once to fill a 33-byte `settings_frame` (9-byte header + 4 params). The handshake appends that blob as-is instead of re-running the encode loop per connection.
- `muxDispatch` detects a streaming route (`routeIsStreaming`) and wraps the handler in `setTcpCork(fd, true)` / `setTcpCork(fd, false)`: the kernel holds output until the MSS is full or cork clears, coalescing the intermediate stage flushes into fewer segments. Unary routes are not corked (already single-write). No-op on non-Linux.

**Consequences:**
- Fewer syscalls per streaming call (writes drop from ~21 to ~2 for a 5000-message reply) and fewer TCP segments on the wire under cork.
- `GrpcMuxConn` grows by ~64 KB per connection. This is a deliberate per-connection memory cost traded for syscall and segment reduction. The mux model holds one `GrpcMuxConn` per live h2 connection, not per stream.
- Related stream-write fix: `fdWriteAll` now polls and retries on `EAGAIN` rather than reporting `BrokenPipe`, so a full send buffer on a non-blocking EPOLL socket no longer truncates a staged reply. See the 0.4.0 changelog.

---

## ADR-036: Opt-in per-worker ResponseCache (shared `utils`) across `zix.Http1`, `zix.Http`, and `zix.Grpc`, plus WebSocket build-once broadcast

**Status:** Accepted

**Context:** A handler re-runs and re-serializes its response on every request. For repeated idempotent calls whose response is expensive to build, that work dominates the userspace cost, while the kernel path is shared by every approach. The engine already proves a precompute-then-write pattern elsewhere (comptime gRPC reply blocks, the cached SETTINGS frame, the thread-local cached Date). A PoC measured whether extending that to user handlers, as a per-key precomputed response cache, pays off. Loopback, AMD Ryzen 5 5600H (12 logical cores), zig 0.16.0, wrk 4.2.0, threads 6, duration 5s, c512 and c4096, twice each, avg Requests/sec:

| Response | c512 nocache -> cache | c4096 nocache -> cache |
| :- | :- | :- |
| trivial (13 B) | 614,551 -> 611,758 (-0.5%) | 453,328 -> 449,565 (-0.8%) |
| built (~32 KiB JSON) | 171,821 -> 230,844 (+34.4%) | 137,516 -> 163,116 (+18.6%) |
| file-backed (~32 KiB) | 209,590 -> 225,058 (+7.4%) | 158,803 -> 163,997 (+3.3%) |

A body-size sweep (c512) puts the crossover near 4 KiB: the delta stays inside run-to-run noise below ~2 KiB (256 B +0.2%, 1 KiB +1.9%, 2 KiB +3.7%), then jumps at 4 KiB (+12.6%) and climbs to +37% at 64 KiB. The file-backed case wins only modestly because the OS page cache already serves the file cheaply.

**Decision:** Add an opt-in, per-worker ResponseCache as a shared module, off by default and scoped to compute-heavy responses, and wire it into `zix.Http1`, `zix.Http`, and `zix.Grpc`. Adopt the same build-once principle for WebSocket broadcast.

- Shared structure in `src/utils/response_cache.zig`: a structure-of-arrays slab (`keys: []u64` open addressing with 0 as the empty sentinel, `meta: []Meta` of `insert_tick_ms` / `len` / `ttl_ms`, and one flat payload slab). Slot count is a power of two indexed by mask. An arena allocates the slab once at init and frees it whole at deinit. A churning cache reuses fixed slots in place, so the arena never grows. Lazy on-access TTL: an entry expires exactly at `insert_tick_ms + ttl_ms`, so `ttl_ms = 0` is never fresh. Expired slots are reused in place by the next store, never zeroed, since zeroing would truncate an open-addressing probe chain. No timer thread is introduced.
- One cache per worker, never shared, never locked (lock-free by ownership). The invariant holds only when one zix-owned thread installs the cache (allocate, set, free on exit) and is the sole thread that touches it. Under `.EPOLL` shared-nothing each worker is exactly that, so the cache is installed there. The `.URING` rings are the same (one thread per ring), so the cache is installed there too. `.POOL` is also zix-owned and could be wired safely, but each pool thread would hold an independent cache (lower hit rate, N times the memory), so it is deferred. `.ASYNC` and `.MIXED` run handlers on the `std.Io` executor pool that zix does not own, where a task is not pinned to one thread, so a shared cache would need locks and break the lock-free design. In this release the cache is installed under `.EPOLL` and `.URING`, the other models leave it uninstalled and the API degrades to a plain send.
- HTTP (`zix.Http1`, `zix.Http`): the key is method, path, and query, and the cached value is the full serialized HTTP response, written verbatim on a hit. `zix.Http1` exposes the explicit pair `cacheLookup` / `cacheStore` plus the fused `writeWithCache`. `zix.Http` exposes `res.serveCached` (lookup then write verbatim) and `res.sendCached` (serialize, write, store), producing bytes identical to a plain `send`.
- gRPC (`zix.Grpc`, unary): the key is the path plus the request body, and the cached value is the response message, not the framed reply, because HEADERS are HPACK and stream-id stateful. On a hit the message is re-framed for the current stream so HPACK and stream id stay correct. `ctx.serveCached` replays the stored message and finishes with OK, `ctx.sendCached` sends and stores.
- WebSocket broadcast adopts the same build-once principle rather than a TTL cache: `zix.Http1.WebSocket.broadcast(conns, opcode, payload)` serializes the frame once and fans the same bytes out to every fd in a caller-maintained room, skipping a failed write to a dead peer. This is the WS-shaped form of the follow-up, not a keyed cache.
- Config is flat and the field names are identical across `Http1ServerConfig`, `HttpServerConfig`, and `GrpcServerConfig`: `response_cache: bool = false`, `cache_max_entries: u32` (rounded down to a power of two), `cache_max_value_bytes: u32` (responses past it bypass, lean default around 16 KiB), `cache_ttl_ms: u32`, and `cache_max_total_bytes: usize = 0` (optional ceiling validated against `entries * value_bytes`).

**Consequences:**
- Clear win for expensive serialization past the ~4 KiB crossover (+12.6% at 4 KiB, rising to +37% at 64 KiB, c512) and zero regression below it, which is why opt-in is mandatory rather than a default.
- Per-worker memory is `cache_max_entries * cache_max_value_bytes`, multiplied by the worker count. Bounded and predictable, the deliberate trade for lock-free per-worker ownership.
- Deliberately not aimed at file-backed or static responses: the OS page cache already serves those cheaply, so `sendfile` / `splice` is the better lever there.
- Correctness rests on opt-in: the engine never auto-caches a handler's output. The handler decides cacheability and TTL. A dynamic or database-backed response sets a short `cache_ttl_ms` (accepting that much staleness) or does not cache and writes directly. The HTTP key covers method, path, and query only, so a response that varies on a header or cookie must not be cached.
- The cache structure is engine-agnostic in `src/utils`, so the per-engine glue (a thread-local cache plus key derivation) is the only protocol-specific part.

---

## ADR-037: `.URING` dispatch model on the raw linux io_uring surface, thread-per-core shared-nothing rings

**Status:** Accepted

**Context:** zix offers four readiness-model dispatch options (`.POOL`, `.ASYNC`, `.MIXED`, `.EPOLL`), all level-triggered or thread-per-task models built on the `epoll` readiness interface. The `.EPOLL` path is shared-nothing and competitive on raw loopback throughput, but under pipelined load it spends a large share of userspace cycles on syscall transitions (one `recv`, one `send`, and the `epoll_wait` bookkeeping per ready event). A completion-based io_uring dispatch batches submissions and reaps completions, removing most of those transitions. A PoC measured the effect (loopback, ReleaseFast, two zix builds only, the `.EPOLL` engine versus a hand-rolled io_uring hello server):

| Metric | zix-epoll | zix-uring (PoC) |
| :- | :- | :- |
| p1 cycles/req (userspace) | 1627 | 818 |
| p1 L1-miss/req | 73.5 | 22.9 |
| p16 cycles/req (userspace) | 710 | 240 |
| p16 server CPU (t4 c128, 10s) | ~45.1s | ~37.25s |

io_uring roughly halves userspace cycles per request at pipeline depth 1 and cuts server CPU about 21 percent at equal throughput under depth 16. Peak loopback throughput is parity at depth 1 (kernel and client bound), so the gain is efficiency headroom, not peak req/s. The userspace cyc/req and L1-miss/req drop reproduces the established exception-less, batched-submission syscall mechanism (FlexSC, OSDI 2010), so it is a verification of a known effect, not a local assumption. The PoC proves the gain. The open question this ADR settles, before any `src/` work begins, is which io_uring foundation to build `.URING` on, since that choice drives the whole port. Two independent engine pre-wins that benefit `.EPOLL` regardless have already landed in `zix.Http1` (lazy `parseHead` and the `EPOLLOUT` re-arm), verified by `zig build test-all`. They are still pending for `zix.Http`.

**Decision:** Build the `.URING` dispatch model on the raw linux io_uring surface (`std.os.linux.IoUring`, the stable low-level ring), not the fiber-based `std.Io.Uring`. The two foundations were weighed as:

| Aspect | A. std posix io_uring (`std.Io.Uring`) | B. raw linux io_uring (`std.os.linux.IoUring`) |
| :- | :- | :- |
| Source | std-provided fiber-based `Evented` backend, drop-in `std.Io` | hand-rolled per-worker rings on the stable low-level ring API |
| Coupling | rides the existing `io: std.Io` config field, one code path for all backends | new `.URING`-only runtime, separate from the `std.Io` abstraction |
| Control | submission and reaping owned by std, opaque to zix | full control: ring flags, buffer rings, multishot ops, batching policy |
| Features used | whatever std exposes through `std.Io` | multishot accept and recv, provided buffer ring, one coalesced send per readable completion, gen-tagged `user_data`, deferred close while a send is in flight |
| Shared-nothing | depends on std executor topology | native: one ring per worker, no cross-thread handoff, matches the `.EPOLL` design |
| Stability risk | tracks std internals (the io_uring surface moved across 0.16.x) | depends only on the stable kernel io_uring ABI, not on std internals |
| Maintenance | low (std maintains the engine) | higher (zix owns the ring lifecycle and edge cases) |

Reasoning for B: the measured win comes from features std does not currently expose through `std.Io` (multishot accept and recv, provided buffer rings), so approach A cannot reach the PoC numbers. The shared-nothing per-worker ring model (one ring, one `SO_REUSEPORT` listener, no shared accept queue) is already the topology the `.EPOLL` path uses, so approach B keeps it intact, while approach A reintroduces a std-owned executor topology zix does not control (the same ownership problem that confines the response cache to the shared-nothing per-worker models, ADR-036). Approach B depends only on the stable kernel ABI, so the moving std io_uring surface does not gate it and the work starts on current Zig (0.16.x).

Scope of the decision:
- Topology preserved from `.EPOLL`: thread-per-core, one ring per worker, one `SO_REUSEPORT` listener per worker, no shared accept queue, no cross-thread fd handoff. Process-per-core (fork-per-core) is rejected because it would split the per-worker route tables and response cache out of one address space.
- Minimal correct core first: multishot accept re-armed on `!IORING_CQE_F_MORE`, an fd-indexed slot table (direct index, no hashmap) guarded against the close-versus-recv completion race with a generation tag in `user_data` against fd reuse, a fixed per-connection recv buffer with a plain `recv` SQE, and a batched CQE drain into a stack array. The listener setup uses raw `linux.*` (or `std.Io.net`) because `std.posix.socket` / `bind` / `listen` / `close` were removed in 0.16.x.
- Ring flags are optimizations, not prerequisites: a ring initialized with no flags is correct. `SINGLE_ISSUER`, `COOP_TASKRUN`, and `DEFER_TASKRUN` (the last needs kernel 6.1 or newer) are added and measured one at a time.
- Buffer strategy is staged: start with the fixed per-connection recv buffer plus a plain `recv` SQE (already enough to compete), and move to a registered provided buffer ring with multishot recv only if the measured syscall savings justify the harder buffer lifecycle.
- Other staged levers (each behind its own A/B, settled by perf counters): registered or direct files (`IOSQE_FIXED_FILE`, `accept_direct`), a registered send buffer holding a response-cache payload (`send_fixed` on a hit), reading the clock once per CQE batch for the cache TTL, and `SEND_ZC` for responses past a size gate.
- Implementation order: `zix.Http1` first (proves the ring core), then WebSocket (reuses the upgrade path, the readable-burst coalescing maps to one batched send), then `zix.Grpc` (h2 framing, HPACK, and stream multiplexing are stateful), then `zix.Http` (reuses the Http1 ring core, cheapest last).
- `DispatchModel.URING` is added to every server `config.zig`, with a non-Linux compile-time or run-time fallback to `.EPOLL` (mirrors the existing non-Linux `.EPOLL` to `.POOL` fallback).

**Consequences:**
- The deliverable is CPU per request and connections per core, not a bigger loopback req/s number. Peak loopback throughput stays parity at depth 1 because that workload is kernel and client bound. Acceptance is measured with `cycles:u` and `L1-miss/req` under pipelined load, back to back against `.EPOLL` on the same machine, fresh server per run (the ring pins memlock pages, so reusing a server instance across runs exhausts the per-user memlock budget).
- zix owns the ring lifecycle and its edge cases: the close-versus-recv completion race, fd reuse (handled by the generation tag), and the per-user memlock budget the rings consume. This is the maintenance cost traded for the control that the measured win requires.
- Approach A stays the fallback if the raw-syscall surface proves too costly to maintain, or if a future `std.Io` exposes multishot and provided buffers as first-class operations.
- The two engine pre-wins (lazy `parseHead`, `EPOLLOUT` re-arm) are in `zix.Http1` and benefit `.EPOLL` independently of this decision. Both are now ported to `zix.Http` as well: its `ParsedHead` drops the per-request 64-entry header array and records the raw header block as offsets for `getHeader` to rescan on demand, and its `.EPOLL` worker stages the unwritten response tail on a partial write and arms `EPOLLOUT` to drain it on the next writable event instead of dropping the connection. The coalescing sink is bypassed for SSE, whose draining stays handler-side (a blocking write parks the handler, not a library event loop).
- The io_uring-specific levers above rest on documented kernel mechanisms but have no workload-specific proof yet, so each is settled locally by an A/B with a named perf-counter signal rather than assumed. Peer-reviewed io_uring evidence is mostly storage, so for networking the backing is the FlexSC mechanism plus the kernel maintainer design notes.

**Extension to `zix.Tcp` and `zix.Fix` (callback rings):**
- These two engines could not take a direct ring port: their handler is a blocking `fn(stream, io)` that owns the connection and loops on synchronous reads and writes, which a single-threaded completion loop cannot run. So each gains a new engine-driven callback API alongside the existing blocking one. `zix.Tcp` adds `runFramed` with a per-frame `FrameFn` over a 4-byte length prefix, and `zix.Fix` adds a `.URING` path that runs a resumable session processor (`core.processFixRing`) per readable batch. The blocking `runWith` and `serveConn` paths are unchanged, and their `.URING` still folds to `.EPOLL`.
- FIX heartbeats on the ring use a per-worker periodic timer, not a per-connection one. A single `prep_timeout` SQE per worker (re-armed on each fire, tagged with a new `.timeout` `OpKind` that the other engines treat as a no-op) ticks every `heartbeat_timeout_ms`. On each fire the worker scans its slot table and, for every logged-in session idle past the interval, sends a TestRequest on the first tick then a Logout on the next, written straight to the fd. One SQE per worker plus an O(n) scan per tick beats a per-connection timeout that would cancel and re-arm on every inbound message. Reaping an idle session is close-safe: its only in-flight op is an idle recv with no buffered data, so closing it leaves the stale recv completion to be dropped by the generation tag. This completes the session: `processFixRing` answers peer Heartbeat/TestRequest reactively, and the timer adds the server-initiated half.

## ADR-038: `zix.Tcp` server bakes the handler at comptime, single `run`, mirroring the engine server shape

**Status:** Accepted

**Context:** Every zix server engine except `zix.Tcp` bakes its handler (or route table) into the server type at `init`, so the handler is comptime-known and `run` takes no handler argument (`zix.Http1`, `zix.Http2`, `zix.Grpc`). `zix.Tcp` was the exception: it took the handler as a runtime function pointer through `runWith(io, handler)`, with `run(io)` as a separate entry that used the built-in echo handler, plus `runFramed(io, frame_fn)` for the per-frame callback. The `run` versus `runWith` split and the runtime pointer were inconsistent with the other engines and with the project's explicit-over-implicit and comptime-where-structural principles. Note the asymmetry was already half-resolved: the per-frame `FrameFn` (`runFramed`) was comptime, only the per-connection `HandlerFn` was runtime. This change is justified on consistency and clarity, not measurement. The per-connection blocking handler runs once per accepted connection (a cold dispatch point), so devirtualizing it is negligible, unlike `zix.Http1`'s per-request handler or the per-frame `FrameFn`, which is why those are already comptime.

**Decision:** Mirror the `zix.Http1` / `zix.Grpc` server shape. Bake the handler (or per-frame callback) into the server type at `init` so `run` takes only `io`. `zix.Tcp.Server` becomes a fieldless namespace with comptime constructors over two private factory types:

| Constructor | Returns | Contract |
| :- | :- | :- |
| `Server.init(comptime handler, config)` / `initArgs(..., args)` | `TcpServerImpl(handler)` | per-connection `HandlerFn` (owns the stream) |
| `Server.initFramed(comptime frame_fn, config)` / `initFramedArgs(..., args)` | `TcpFramedServerImpl(frame_fn)` | per-frame `FrameFn` (engine owns the connection) |

Both factory types hold only `config` and expose `init`, `deinit`, and `run(io)`. The built-in echo handler stops being a hidden default behind `run`: it is the public `zix.Tcp.echoHandler`, passed explicitly (`Server.init(zix.Tcp.echoHandler, config)`), per explicit-over-implicit. The `runWith` and `runFramed` methods are removed.

The two factory types (rather than one type with an optional second comptime parameter, the shape `zix.Http1` used for `(handler, raw_fn)` before ADR-062 removed the unused `raw_fn` hook) follow a compose-versus-alternative rule. In `zix.Http1` the raw interceptor composes with the handler (same connection, a pre-parse hook), so one impl carries both. In `zix.Tcp`, `HandlerFn` (owns the connection, blocks) and `FrameFn` (engine-owned, never blocks, runs on the `.URING` ring) are mutually exclusive contracts: a connection cannot be both hand-owned and engine-deframed. Two factory types keep that impossible state unrepresentable. The `FrameFn` contract from ADR-037 is unchanged, only its entry point moves.

`io` stays a `run(io)` argument rather than a config field (unlike `zix.Http1` / `zix.Grpc`, whose `io` lives in config). Moving `io` into `TcpServerConfig` for full shape parity (which would also resolve the io-placement inconsistency across the server configs) is a separate, larger change spanning the config struct and every call site, deferred to its own decision.

**Consequences:**
- Breaking API change: `runWith` and `runFramed` are gone, `run(io)` is the only run path, and the constructor carries the handler. The internal worker functions (`serveDispatch`, `runEpoll`, and the pool / async / epoll entries) keep the handler as a runtime value, exactly as `zix.Http1`'s `runAsync` / `runPool` / `runMixed` do. The comptime binding is at the type boundary (no runtime registration), not a hot-loop devirtualization.
- The handler must be comptime-known. A runtime-selected handler (`const h = pick(cfg)`) now branches at the call site (`if (...) Server.init(handlerA, ...) else ...`). This is the one expressiveness cost, accepted on principle for the raw-TCP engine.
- Supersedes the extension API names in ADR-037: the blocking path is `Server.init(handler, config)` then `run(io)` (was `runWith`), the framed ring path is `Server.initFramed(frame_fn, config)` then `run(io)` (was `runFramed`). `.URING` still folds to `.EPOLL` for the per-connection handler and runs natively for the framed callback.
- Verified: the library compiles, all five `tcp_server_*` examples compile, the unit / integration / edge / behaviour suites pass, and all five end-to-end runners (async, pool, mixed, epoll, uring) pass.

---

## ADR-039: `zix.Tcp` / `zix.Udp` / `zix.Uds` move `io` into the server config and `zix.Uds` bakes the handler at comptime, unifying the server shape on `run()`

**Status:** Accepted

**Context:** Five server engines (`zix.Http`, `zix.Http1`, `zix.Http2`, `zix.Grpc`, `zix.Fix`) carry `io: std.Io` in their config, so `run()` takes no argument. The three remaining servers diverged: `zix.Tcp` and `zix.Udp` took `io` as a `run(io)` parameter, and `zix.Uds` took both `io` and the handler at run (`run(io, handler)`). This was the last server-shape inconsistency in the library: moving a server between protocols meant remembering which ones thread `io` through `run`. ADR-038 already baked the `zix.Tcp` handler into the type at `init`, but deliberately deferred the `io` placement as a separate, larger change. Nothing prevents the move: the engine servers prove the pattern, and the internal worker functions already take `io` as a plain value.

**Decision:** Move `io` into the config and bake the `zix.Uds` handler at `init`, so every server is constructed the same way and `run()` takes no argument.

- Add `io: std.Io` as the first, required field of `TcpServerConfig`, `UdpServerConfig`, and `UdsServerConfig`.
- `run()` takes no argument on all three. It reads `self.config.io` and passes that value to the existing internal workers (`serveDispatch`, `runEpoll`, the Udp receive loop, the Uds accept loop), so there is no hot-path or ownership change.
- `zix.Uds` adopts the ADR-038 factory shape: `Server.init(comptime handler, config)` returns a specialized type whose `run()` takes nothing. The built-in echo default is the public `zix.Uds.echoHandler`, passed explicitly. The old `run(io, handler)` / `runWith` path is removed.

The server constructor map is now uniform:

| Server | Construct | Run |
| :- | :- | :- |
| `zix.Http` / `zix.Http1` / `zix.Http2` / `zix.Grpc` / `zix.Fix` | `Server.init(routes_or_handler, config)` | `run()` |
| `zix.Tcp` | `Server.init(handler, config)` / `initFramed(frame_fn, config)` | `run()` |
| `zix.Udp` | `Server(Packet).init(config)` | `run()` |
| `zix.Uds` | `Server.init(handler, config)` | `run()` |

Clients (`zix.Tcp.Client`, `zix.Udp.Client`, `zix.Uds.Client`) keep `io` as a `connect()` / `init()` parameter. Client `io` placement is a separate axis (`zix.Grpc.Client` also takes `io` as a parameter while `zix.Http.Client` carries it in config), deferred to its own decision.

**Consequences:**
- Breaking API change: every `zix.Tcp` / `zix.Udp` / `zix.Uds` server call site adds `.io = process.io` to the config literal and drops the `run` argument. `zix.Uds` callers also pass the handler to `init` (the `runWith` path is gone).
- `io` must outlive the server, the same contract the engine configs already document.
- Supersedes the `io` placement recorded in ADR-038: the `zix.Tcp` run path is now `run()` (was `run(io)`). The handler-at-`init` decision from ADR-038 is unchanged and is extended to `zix.Uds`.
- Full server-shape parity: all eight servers are constructed with a config that carries `io` and served with a no-argument `run()`. Moving a server between protocols is mechanical.
- Verified: the library compiles, every `tcp_server_*` / `udp_server` / `uds_server` example compiles, the unit / integration / edge / behaviour suites pass, and the `tcp` (all five models), `udp`, and `uds` end-to-end runners pass.

---

## ADR-040: user-space hot-path optimizations across the engine family (integer-compare, baked response prefix, lazy parse, writer bypass, copy reduction)

**Status:** Accepted

**Context:** The 0.4.x kernel-cycle pass showed loopback is ~94% kernel TCP, identical for `.EPOLL` and `.URING`. The io_uring syscall levers (direct descriptors, fixed buffers, send_zc, SQPOLL) are sub-noise on this box, and a probe of the top io_uring HTTP engines (ringzero, zeemo) found they use none of them, so those are deprioritized. The remaining wins that clear the 1% bar are in the shared user-space hot path: they are measurable on loopback and help every dispatch model (`.EPOLL`, `.URING`, `.POOL`, `.ASYNC`, `.MIXED`) at once, because the code lives in the shared parse and response paths, not a dispatch loop. The server-process perf profiles name the hot user-space leaves:

| Symbol | http1 EPOLL | http1 URING | http EPOLL | http URING | Pattern |
| :- | :- | :- | :- | :- | :- |
| `mem.eql` (fixed-string compares) | present | 14.99% | present | present | P1 |
| `buildSimpleHeaderInto` / response build | 4.63% | 9.92% | 5.39% | 7.02% | P2 |
| `mem.findScalarPos` (eager header scan) | low | low | present | 10.98% | P3 |
| `Io.Writer.alignBufferOptions` (std writer) | n/a | n/a | 1.91% | 1.97% | P4 |
| `memcpy.memcpyFast` (build-then-copy) | 1.40% | 1.99% | 4.95% | 9.03% | P5 |

**Decision:** Apply five optimization patterns, each as one increment, applied to every engine whose hot path contains it, gated by `zig build test-all`, `zig build examples`, and `zig build test-runner-all` before the next.

| Id | Pattern | What | Targets |
| :- | :- | :- | :- |
| P1 | integer-compare | Replace a hot `mem.eql` against a fixed-length string literal with one integer (u32/u64) load-and-compare. | HTTP/1 version + method, HTTP/2 `:method` / `:path`, gRPC `:path` |
| P2 | baked response prefix | Replace per-request response-header assembly (many small appends or `bufPrint`) with one `@memcpy` of a comptime-baked prefix, plus the variable Content-Length digits and optional cached Date. | Http1, Http |
| P3 | lazy header parse | Parse only the framing headers up front, defer the rest to on-demand lookup. | Http (already lazy) |
| P4 | writer bypass | Write the response straight into the engine sink/fd instead of through `std.Io.Writer`. | Http |
| P5 | copy reduction | Build the response header directly into the send/sink buffer (write-in-place), removing one copy generation. | any build-then-copy path |

Per-engine application (a pattern applies only where the hot path has it):

| Engine | Change |
| :- | :- |
| zix.Http1 | P1 `parseGetFastPath` version/method `readInt` compares. P2 comptime-baked `statusLine` (one `memcpy`) |
| zix.Http | P1 parser framing-header length-switch. P2 + P4 `buildResponse` + `send` Content-Type / Date `@memcpy` (drops `std.Io.Writer`) |
| zix.Http2 / zix.Grpc | P1 `:method` / `:path` length-gated compares |
| WebSocket (Http1 + Http) | already a 16-wide `@Vector(16, u8)` unmask, no change |
| zix.Fix / zix.Tcp / zix.Udp | byte-level or length-prefixed framing, no hot fixed-string compare, no change |

**Config:** internal optimizations, no new server-config field. Should a toggle ever prove necessary it is added to every server config (`Http`, `Http1`, `Http2`, `Grpc`, `Tcp`, `Udp`, `Uds`, `Fix`) with the same name, type, and default, per the flat-config consistency rule.

**Consequences:**
- Faster on every dispatch model, and measurable on loopback (unlike the io_uring levers). Each pattern targets a symbol that is at least ~1% of a server profile.
- No API or behaviour change. Each increment carries an equivalence test (byte-exact output or behaviour), so the wire bytes are unchanged. The unit / integration / behaviour / edge suites plus the end-to-end runners are the regression gate, run green after every increment (56/56 runner protocols each).
- Verified already-optimal (no change): zix.Http `parse` is already lazy and vectorized (P3 pre-done), zix.Http `buildResponse` already bakes the status line and uses `@memcpy` + `writeDecimal` for Content-Length, WebSocket unmask is already SIMD, and zix.Grpc replies already use comptime-cached HPACK blocks.
- Result (httparena-lite, attempt 3, post-sweep, AMD Ryzen 5 5600H, 6/12 threads, loopback, recorded in the README Benchmark tables): representative EPOLL HTTP/1.1 throughput rose versus the prior recorded attempt, baseline 512c 585,239 -> 614,416 req/s (+5.0%) and pipelined 512c 7,156,160 -> 7,682,896 req/s (+7.4%), with the remaining scenarios within loopback variance and `.URING` at parity with `.EPOLL` (expected on a 94%-kernel loopback path). These are full-suite numbers (a fresh server per scenario), so they confirm the direction rather than isolate a per-increment delta.

---

## ADR-041: `.URING` connection-churn scaling (ring `prep_close` teardown + on-ring `RespSink` growth) after the write-path pivot

**Status:** Accepted

**Context:** On the 64-core HttpArena box, `.URING` split from `.EPOLL` by reqs-per-connection. It won the long-lived cells (baseline +14 to +20%, pipelined +9 to +13%) and tied static, but collapsed on the connection-churn cells (json -73%, limited-conn -87%). Per-core throughput was equal or better for `.URING`, so the problem was core occupancy, not work done per request. Under churn the worker engaged only about 7 of 64 cores because each teardown blocked it in a synchronous `linux.close` between connections, making the accept-recv-send-close cycle close-bound. The earlier read had blamed the write path (a response over the 16 KiB send buffer falling back to a blocking off-ring `fdWriteAllDirect`), but the write-path cell (static) already tied, so the real lever was connection setup and teardown.

**Decision:** Two changes, both `.URING` only, with `.EPOLL` byte-for-byte unchanged:

| Change | What |
| :- | :- |
| ring close | `finishClose` submits a `prep_close` SQE (tagged with a new shared `OpKind.close`) and recycles the connection slot first, instead of a synchronous `linux.close`, so the worker keeps reaping completions across teardowns. It falls back to a synchronous close only when the SQ is momentarily full. The half-duplex per-connection state guarantees no in-flight op targets the closing fd. |
| on-ring growth | `RespSink` grows the per-connection `send_buf` (power-of-two `realloc` up to `URING_SEND_BUF_MAX` = 1 MiB, never shrinks, reused through the idle-conn free list) to stage an oversized response on the ring, removing the blocking `fdWriteAllDirect` fallback. |

The shared `OpKind` lives in `src/multiplexers/ring.zig` (relocated from `src/tcp/io_uring`) and gained `close`, so every io_uring engine carries a `.close => {}` arm. Only `zix.Http1` arms it for now.

Rejected on the way, kept for the record. Ring `sendFile` for static was deprioritized because static already ties, so it is quality, not a composite mover. A comptime `Route.profile` write-strategy API is scaffolding rather than a perf lever, because parsing happens before routing and writes live in the handler, so a route-level write profile has nothing real to select until other behaviors exist. A buffer-select parse-in-place recv was implemented and reverted, because the plain recv-into-`conn.buf` path already parses in place with no copy, so the buffer ring only added per-recv bookkeeping and regressed pipelined 13 to 16%. A per-machine `lean` / `throughput` recv-buffer profile (comptime, app-level, no engine change) is kept as a deployment knob.

**Config:** no new server-config field. The per-machine recv buffer is selected by the deployment through the existing `max_recv_buf`. The send-buffer grow cap is an internal constant.

**Consequences:**
- The churn cells recovered to parity on the 64-core box: json -73% to -2.4%, limited-conn 512 -87% to +5.5%, limited-conn 4096 -87% to -1.5%, an absolute jump of roughly 8x on limited-conn and 3.7x on json. Mechanism confirmed: limited-conn 512 server CPU rose from about 722% (around 7 of 64 cores) to about 5443% (around 54 cores), so the cores now fill across teardowns.
- `.URING` now reaches parity or better on every subscribed cell at 50 to 85% less memory than `.EPOLL` (json 289 MiB versus 1.3 GiB, limited-conn 4096 231 MiB versus 1.5 GiB), so the HttpArena entry ships on `.URING`. `.EPOLL` is unchanged this release.
- No API or behaviour change. The `prep_close` teardown is exercised end-to-end by the io_uring integration runners (HTTP, WebSocket upgrade, large-body drain). The grow path is capped and pooled, a correctness and tail-latency guard rather than a hot path, because no benchmark cell emits a response over 16 KiB inline.

---

## ADR-042: dispatch loops stay per-engine, only byte-identical primitives are shared

**Status:** Accepted

**Context:** When `.URING` (ADR-037) landed across engines, the first piece hoisted into a shared module was `src/multiplexers/ring.zig`: the `OpKind` tag and the `user_data` codec (about 40 lines). Every io_uring engine reuses it because the bits must match exactly (an fd-keyed slot guarded by a generation in one `user_data` layout). A second primitive later joined it, `src/multiplexers/slab.zig`: the Linux demand-paging helpers (`mapZeroedSlots`, `unmapSlots`, `releaseSlabPages`) that every per-worker EPOLL / URING connection table uses to mmap zero-filled slots and hand a closed connection's pages back to the OS. Everything else stayed per-engine: each engine keeps its own `.EPOLL` and `.URING` connection table, `acceptAll`, and per-event dispatch. A reader can ask whether those loops should be unified the way the codec and the slab helpers were.

**Decision:** Keep each engine's dispatch loop (`.ASYNC` / `.POOL` / `.MIXED` / `.EPOLL` / `.URING`) and its connection table in its own `server.zig` (or `dispatch/` folder, ADR-043). Do not build a generic multiplexer interface. Share only byte-identical primitives in `src/multiplexers/`: today the `.URING` `user_data` codec (`ring.zig`) and the demand-paging helpers (`slab.zig`). The rule: share primitives that must match, keep dispatch loops and tables per-engine.

**Rationale:** The split is the optimization. Per-engine ownership lets each engine tune its hot path for its own connection shape: `zix.Http1` carves connection buffers from a contiguous demand-paged slab (no per-accept heap call), while `zix.Grpc` and `zix.Fix` hold per-connection heap pointers because their connection objects carry h2 or FIX session state too large or variable for one fixed slab cell. A single generic loop would force one table shape on every engine (erasing the slab win) and add a callback-per-event indirection on the accept / recv / send path, the hottest path in the library. The two shared primitives pass the bar precisely because they are mechanics, not policy: `ring.zig` is a pure bit codec, and `slab.zig` is pure mmap / madvise that works for an inline-struct slot (zero means empty) or a pointer slot (zero means null) without knowing the table shape. Each engine still owns the table that calls them.

**Config:** none. No API change. This records existing intent.

**Consequences:**
- `src/multiplexers/` holds shared primitives only, today `ring.zig` (the `user_data` codec) and `slab.zig` (the demand-paging helpers). The bar for adding to it is byte-identical-by-requirement, not merely similar shape.
- A small amount of boilerplate stays duplicated per engine (the epoll bootstrap and the fd-indexed slot table shape), accepted in exchange for per-engine tunability. A bounds or generation fix in that pattern is applied per engine.
- The connection tables are intentionally not identical: `zix.Http1` inline-struct slab versus `zix.Grpc` / `zix.Fix` per-connection heap pointers, each chosen for that engine's connection shape, but both reach the shared `slab.zig` helpers for the mmap and page-release mechanics.

---

## ADR-043: split each engine's dispatch models into a per-engine dispatch/ folder

**Status:** Accepted

**Context:** Each engine keeps all of its dispatch models in one `server.zig` (ADR-042). For `zix.Http1` that file was about 2,600 lines, with `.EPOLL` and `.URING` about 900 lines each and barely overlapping, so a change to one model meant scrolling past the other four. The A2 idle-pool variants, which differ only in the `.URING` pool code, were forced to be full-file copies.

**Decision:** Split the models into a per-engine `dispatch/` folder, one file per model named for the `DispatchModel` enum value (`async.zig`, `pool.zig`, `mixed.zig`, `epoll.zig`, `uring.zig`), with shared dispatch helpers in `dispatch/common.zig`. `server.zig` keeps the public `Server` type and the runtime model switch. `core.zig` (shared request processing) is untouched. Rolled out on `zix.Http1` first, then replicated to the other connection-oriented engines (`zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Tcp`, `zix.Fix`). `zix.Udp` is excluded by design (see Consequences): it is connectionless, has a single serve strategy, and has no `dispatch_model` to switch on.

**Rationale:** This is file organization, not a behavior or perf change, and it does not introduce a shared or generic dispatch loop, so it complies with ADR-042: no per-event indirection, and each engine still owns its dispatch. Isolating a model makes per-model work and per-model variant comparison (the A2 record) tractable. Moved bodies stay byte-identical because each model file reaches the shared helpers through `const X = common.X;` aliases, so only the `run()` switch is rewritten.

**Config:** none. No code-behavior or API change. `Server.init` and the config are unchanged (`initRaw` was still present at this point, later removed by ADR-062).

**Consequences:**
- Each new file needs its own `std.testing.refAllDecls` line in `src/lib.zig` (refAllDecls is not recursive), else its tests silently never run. Tests move into the file of the model they cover.
- The `zix.Http1` pilot landed green: `server.zig` shrank from 2,624 lines to 154, the five models live under `dispatch/` (with `common.zig` for the shared helpers), and `zig build`, `test-all`, and `test-runner-all` (all 56 protocols) pass with the 25 http1 tests preserved.
- The four A2 idle-pool variants are preserved as full-server snapshots in `rnd/0.5.x/a2-variants/` (they differ only in the `.URING` pool code) with a cross-reference manifest.
- The connection-oriented engines (`zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Tcp`, `zix.Fix`) landed the same split, each an independent equivalent move, all green on Zig 0.16.x and 0.17.x (`test-all`, `examples`, `test-runner-all`). `zix.Http2` and `zix.Grpc` thread routes through a `common.Dispatch(...)` generic, and `zix.Http` bakes them into a `HttpServerImpl(routes)` factory (its dispatch functions take `server: anytype`), so the moved bodies stay byte-identical, the runtime-route engines (`zix.Tcp`, `zix.Fix`) pass the handler at runtime.
- `zix.Udp` is excluded by design. The dispatch models abstract connection lifecycle (accept, then per-fd multiplex, then close). UDP is connectionless: one bound datagram socket, no per-connection fds, clients tracked as application-level address records, and concurrency is per-datagram (`io.concurrent`) not per-connection. There are no models to partition. A `dispatch/` split would be revisited only if a second datagram serve strategy is added (reuseport plus `recvmmsg` / `sendmmsg` / io_uring multishot).

---

## ADR-044: support Zig 0.16.x and 0.17.x from one tree via comptime ZIG_SEMVER gating

**Status:** Accepted

**Context:** zix is developed on Zig 0.16.0 while the rolling `zig` toolchain has moved to 0.17.0-dev, and the two differ in std and build APIs in ways that break compilation outright. The roadmap framed a version bump as blocking the 0.5.x campaign because it was assumed to force a re-baseline and an io_uring rewrite. Two findings removed that: the feared io_uring rewrite is a non-issue (the raw `std.os.linux.IoUring` is unchanged in 0.17, so the ring engines compile as-is), and every other difference is either a single parse-level operator change or a semantic API change that a comptime branch can carry on both versions at once. The full difference inventory was catalogued during the port.

**Decision:** Build on BOTH 0.16.x and 0.17.x from one source tree, gated by `ZIG_SEMVER`, a named comptime constant (`MAJOR` / `MINOR` / `PATCH`) over `builtin.zig_version`. It exists in exactly two places, because `build.zig` and the zix module are separate compilation contexts and `build.zig` cannot import the module: a build-only copy in `build.zig` (for the `ensureSupportedZig` guard and the `dirExists` build-root branch) and the public `zix.ZIG_SEMVER` in `src/lib.zig` (for source-code gates and external consumers). Semantic differences are gated `if (comptime ZIG_SEMVER.MINOR == 16) { 0.16 code } else { 0.17 form }`, where the comptime-dead branch is never analyzed so neither version sees the other's API. `ensureSupportedZig` fails fast with a readable message outside the 0.16.x / 0.17.x range.

**Rationale:** Pinning one version would either strand 0.16 users or block adoption of the current toolchain for no benefit, since dual support is mechanical once the io_uring fear is gone. The gate preserves the validated 0.16 code verbatim on its branch and adds the 0.17 form in the `else`, rather than rewriting working code. `ZIG_SEMVER` centralizes the check, so the next port (0.18) is a search for `ZIG_SEMVER.MINOR` plus the parse-level sweep. The one exception is the `**` repeat operator: its 0.17 rejection is a parse (AstGen) error that fires over the whole file before any comptime branch is eliminated, so it cannot be gated and is replaced unconditionally with `@splat`, which is byte-identical on 0.16.

**Config:** none. `ZIG_SEMVER` is a comptime constant, not a runtime field. No engine config or API change.

**Consequences:**
- One tree serves both the stable 0.16 line and the current 0.17 toolchain, with no fork or per-version branch, and the roadmap's Phase-1-blocking version decision is removed.
- The seven differences resolved: `b.build_root` -> `b.root.root_dir` (build.zig), `X ** N` -> `@splat` (6 sites, unconditional), `bufPrintZ` -> `bufPrintSentinel(buf, fmt, args, 0)`, `indexOfIgnoreCase` -> `findIgnoreCase` (a rename), `@typeInfo` `.fields` -> `field_names` + `field_types`, `std.meta.Int` -> `@Int`, and io_uring unchanged.
- Verified green on both 0.16.0 and 0.17.0-dev.902 across `test-all`, `examples`, and the live `test-runner-all` (56 protocols).
- Two `ZIG_SEMVER` copies (build-only and public) must stay in sync, three trivial lines each over the same `builtin.zig_version`, and the doc comment in each forbids a third copy. A future compiler can add differences not covered here, bounded by `ensureSupportedZig`.

---

## ADR-045: pure-Zig TLS, TLS 1.2 the minimum version

**Status:** Accepted

**Context:** zix needs TLS for https and h2, and as the hard prerequisite for Http3. std ships a TLS client only, so a server needs its own certificate-based handshake. Two decisions had to be fixed: build the handshake in Zig or bind a C library, and which protocol versions to put on the wire.

**Decision:** Build the TLS 1.3 server handshake in pure Zig on `std.crypto` primitives, no OpenSSL or BoringSSL. Version policy: offer TLS 1.2 and TLS 1.3, prefer 1.3, never negotiate below 1.2. 1.2 is the floor and required scope, 1.0 / 1.1 / SSL are never offered (RFC 8996). Mandatory-to-implement crypto: `TLS_AES_128_GCM_SHA256`, secp256r1 plus X25519 ECDHE, an ECDSA P-256 or Ed25519 certificate. https is opt-in, cleartext stays the default and is left untouched, and https lives on its own perf band.

**Rationale:** std already provides every primitive (AES-GCM, HKDF, X25519, P-256, ECDSA, Ed25519), so a C dependency would add build complexity and an FFI boundary for no functional gain and would break the pure-Zig posture. TLS 1.2 is the minimum because RFC 5246 is not deprecated and is still widely deployed (older Android, legacy OpenSSL, embedded and enterprise stacks), whereas 1.0 / 1.1 are deprecated (RFC 8996) and so are never offered. The 1.2 suites are restricted to ECDHE-AEAD for forward secrecy and authenticated encryption on both versions, and an ECDSA or Ed25519 certificate covers authentication on the std signing path. RSA signing was initially left optional here, then implemented later for RSA-certificate interop (ADR-048).

**Config:** flat `tls_*` fields on the server configs (`tls_cert_path`, `tls_key_path`, `tls_alpn`, plus `hsts_max_age_s` on Http1) and `tls_ca_path` on the client config. No nested sub-config, per the existing flat-config rule. The server-side flat fields are superseded by the `Tls.Context` object (ADR-047).

**Consequences:**
- The TLS 1.3 server is implemented and verified byte-exact against the RFC 8448 trace, green on Zig 0.16 and 0.17.
- TLS 1.2 is an OPEN required milestone (the shipped code is 1.3-only). It is a separate track: a SHA-256 / SHA-384 PRF key schedule, the 1.2 record layer, the 1.2 handshake, and cross-version suite negotiation restricted to ECDHE-AEAD.
- The downgrade-protection sentinel (RFC 8446 4.1.3) becomes required once both versions are offered. It is not yet implemented.
- The cleartext EPOLL / URING path is untouched, and https is held to its own perf band, not the 1 percent gate.
- A native verifying TLS client (ALPN offer plus X.509 / RFC 6125) is a separate milestone.

---

## ADR-046: wire TLS as a layer, gated serve paths over the unchanged engines

**Status:** Accepted

**Context:** TLS sits under Http1 and Http2 (https, h2). https had to be added without disturbing the tuned cleartext dispatch models (`.ASYNC` / `.POOL` / `.MIXED` / `.EPOLL` / `.URING`) or their hot path.

**Decision:** Add TLS as a gated blocking serve path per engine, selected when `config.tls` is set (the `Tls.Context`, ADR-047), leaving every cleartext model untouched. Http1: `serveConnTls` runs the handshake through `zix.Tls`, then per request decrypts the record, reuses `core.parseHead`, runs the existing fd-handler over a pipe, and encrypts the response. Http2: a terminator runs the UNCHANGED h2c engine (`core.serveConn`) behind a socketpair, with a `poll` loop that decrypts inbound client records to plaintext and encrypts the engine's frames back, and ALPN selects h2. `zix.Tls` is sans-I/O: `serverHandshake` returns the bytes to send plus a `Connection`, so the engine owns the socket loop.

**Rationale:** Terminating TLS in front of the unchanged engines reuses the whole cleartext frame and request machinery, so https cannot regress the cleartext hot path (it is additive) and the h2c state machine is not forked. The blocking path with a per-connection pipe or socketpair is acceptable because https is opt-in on its own perf band, not the 1 percent gate. Sans-I/O keeps `zix.Tls` usable from blocking and non-blocking dispatch alike. Teardown uses `shutdown(SHUT_WR)` so the engine sees EOF without a write racing a closed peer, avoiding SIGPIPE.

**Config:** `config.tls` (a `*Tls.Context`, ADR-047) gates the path. No new dispatch model and no change to the cleartext API.

**Consequences:**
- Http1 https/1.1 and Http2 h2 both serve over TLS 1.3, examples on ports 9060 and 9061, green on Zig 0.16 and 0.17.
- The h2 path reuses `core.serveConn` unchanged. Only ALPN selection and the terminator are new code.
- One request per Http1 https connection for now (keep-alive is a later refinement), and the terminator is one thread plus a socketpair per connection, accepted on the https band.
- No native h2 runner yet: it needs an ALPN-offering client, which is the `zix.Tls` client milestone.
- Superseded for the h2 / gRPC terminator by ADR-052: the socketpair plus thread-per-connection design moved to a multiplexed per-core dispatch under `.EPOLL` / `.URING` and to an inline-mux driver under `.ASYNC` / `.POOL` / `.MIXED`. The socketpair described above is gone. Http1 https is unchanged by that ADR.

---

## ADR-047: TLS bind options as a Tls.Context object

**Status:** Accepted

**Context:** TLS shipped with flat `tls_*` fields (cert, key, alpn, HSTS) on each HTTP server config (ADR-045 / 046), the minimal subset. Exposing the full bind surface (version floor / ceiling, ECDHE curves, cipher suites, server-cipher preference) as more flat fields would bloat every HTTP config, and a runtime config-file parser (the planned `zixer` executable) cannot produce compile-time enum literals: it needs a value it builds at runtime.

**Decision:** Expose server TLS as a user-owned object, `zix.Tls.Context`, modeled on the logger (`logger: ?*Logger`). `Tls.Context.Config` is the plain settings struct (`cert_path`, `key_path`, `alpn`, `min_version`, `max_version`, `curves`, `ciphers`, `prefer_server_ciphers`, `hsts_max_age_s`). `Tls.Context.init(allocator, io, config)` loads the PEM, detects the key type, and validates the policy once on the cold path. The HTTP configs carry `tls: ?*Tls.Context = null`, and a non-null pointer is the https opt-in gate (replacing the `tls_cert_path != null` gate). Curves and ciphers are typed enum slices validated to the implemented set: an unsupported value is a startup error, never a silent no-op. zix is ECDHE-only, so there is no dhparam knob. Session resumption is deferred: it touches the data path and is gated on the perf bench.

**Rationale:** The logger already established that a user-constructed object passed by pointer is the right shape for cross-cutting state, and it keeps `HttpServerConfig` flat (the many TLS knobs live inside `Tls.Context.Config`, not on the HTTP config). `Context` is the honest name: `zix.Tls` is sans-I/O with no listener (the accept loop is the HTTP engine's), so the object is the loaded-state context (the `SSL_CTX` analog), not a server. One config type serves two front-ends: the typed library path and the future `zixer` text-config parser both produce a `Tls.Context.Config`. Validate-or-reject keeps every exposed field honored or refused, never silently ignored, and loading / validating once keeps the per-connection serve path free of PEM work. Forward secrecy (ECDHE) and AEAD hold on both 1.2 and 1.3 by construction.

**Config:** `tls: ?*Tls.Context` on the Http1 and Http2 server configs. `Tls.Context.Config` holds the bind options. The flat `tls_*` server fields of ADR-045 / 046 are removed.

**Consequences:**
- The four flat fields (`tls_cert_path`, `tls_key_path`, `tls_alpn`, Http1 `hsts_max_age_s`) collapse to one `tls` pointer. HSTS becomes available to Http2 too, since it lives in the shared context.
- Configured curves are threaded into TLS 1.3 negotiation (reorder / subset is honored), and the version floor / ceiling gates the serve path: a ceiling of TLS 1.2 forces the 1.2 path, a floor of TLS 1.3 refuses 1.2 clients with a protocol_version alert.
- The implemented set (X25519, secp256r1, AES-128-GCM for 1.3, ECDHE-ECDSA-AES128-GCM for 1.2) widens with no API change as crypto lands. Unsupported values are rejected at init.
- The `Tls.Context` is the foundation the planned `zixer` executable parses its text config into.
- Green on Zig 0.16 and 0.17 (unit-test plus the 59-protocol test-runner-all).

---

## ADR-048: RSA server certificate signing

**Status:** Accepted

**Context:** ADR-045 left RSA signing optional: an ECDSA P-256 or Ed25519 certificate covers authentication on the std signing path, and std verifies RSA but cannot sign with an RSA private key. A deployment that must serve a pre-issued RSA-2048 certificate (a common shape, for example a shared certificate mounted by an external harness) could not be served, since zix had no RSA signing.

**Decision:** Implement RSA signing in pure Zig on `std.crypto`, server-side only, for RSA server certificates. The primitive is a constant-time modular exponentiation: a dedicated Montgomery modexp in `montgomery.zig` (portable CIOS plus a fused ADCX / ADOX asm path on x86_64+ADX), with `std.crypto.ff.Modulus` as the fallback for prime widths it does not cover. zix authors the padding: EMSA-PKCS1-v1_5 (RFC 8017 9.2) and EMSA-PSS plus MGF1 (RFC 8017 9.1), plus the PKCS#1 / PKCS#8 private-key DER parse. `Tls.Context.init` detects an `rsaEncryption` certificate, parses the key, and rejects below RSA-2048. RSA authenticates the TLS 1.3 CertificateVerify with `rsa_pss_rsae_sha256`, so an RSA certificate requires TLS 1.3: the 1.2 ServerKeyExchange path stays ECDSA-only, and an RSA context that meets a 1.2-only client returns an error. The default certificate type is unchanged (ECDSA P-256), RSA engages only when an RSA certificate is loaded.

**Rationale:** The bignum was never the gap (`std.crypto.ff` already provides constant-time modexp), only the PKCS#1 padding and the key DER parse were missing, so the work is pure-Zig with no new dependency, holding the ADR-045 posture. The modexp later moved to a dedicated constant-time Montgomery routine (`montgomery.zig`) to lift the sign rate under a TLS handshake storm (ff stays the fallback), still pure-Zig. PSS (not v1.5) on the 1.3 path because RFC 8446 permits only `rsa_pss_rsae_sha256` for an RSA CertificateVerify. The 2048-bit floor is the modern minimum. Server-side only, with no RSA on the client (`zix.Tls.Client` still offers and verifies ECDSA plus Ed25519), because the driver is serving an RSA certificate, not consuming one. ECDSA stays the default for its smaller, faster signatures.

**Config:** none new. An RSA certificate is selected by pointing `Tls.Context.Config.cert_path` / `key_path` at an RSA certificate and key, `Tls.Context.init` detects the type. Floor the context at TLS 1.3 for an RSA certificate (`min_version = .TLS_1_3`).

**Consequences:**
- `src/tls/rsa.zig` is the signer (key parse, EMSA-PKCS1-v1_5, EMSA-PSS, salt injected by the caller). `certificate.SigningKey` gains an `rsa` variant with `scheme()` returning `rsa_pss_rsae_sha256`. `handshake.SignatureScheme` gains `rsa_pkcs1_sha256` (0x0401) and `rsa_pss_rsae_sha256` (0x0804).
- `src/tls/montgomery.zig` is the modexp: a constant-time Montgomery routine (portable CIOS, plus a fused ADCX / ADOX asm path on x86_64+ADX selected by a `+adx` build), used for the two CRT half-exponentiations of the sign. `std.crypto.ff` remains the fallback. The sign is constant-time on either path.
- The PSS salt is threaded per connection like the other randoms: serve-path getrandom into `Tls.Context.handshakeOptions`, then `HandshakeOptions.pss_salt`, then `buildCertificateVerify`.
- Verified: byte-exact against `openssl dgst -sign` for v1.5, std RSA verify for PSS, and an integration test loads an RSA certificate, signs a std-verified PSS signature, and rejects a 1024-bit key. Green on Zig 0.16 and 0.17.
- RSA over TLS 1.2 is out of scope: the 1.2 path is ECDSA-only, so an RSA context serves 1.3 only.

---

## ADR-049: raw-bytes UDP datagram mode

**Status:** Accepted

**Context:** `zix.Udp` shipped as a typed messaging engine: `Server(comptime Packet)`, where every datagram is exactly one `extern struct`, received and sent one syscall at a time, with no dispatch model. That fits fixed-shape messaging but is not a datagram transport: it cannot carry variable-length payloads, batch syscalls, or run per-core. A throughput-oriented UDP workload (and a future QUIC / HTTP3 engine) needs a variable-length, batched, per-core datagram substrate, and that substrate is independently useful for echo, DNS-style, and telemetry servers.

**Decision:** Add a raw-bytes mode, `zix.Udp.Raw(handler)`, alongside the unchanged typed `Server(Packet)`. The handler receives the datagram bytes (variable length up to `max_recv_buf`), the peer address, and a `Sink` to reply through. On Linux it receives in `recvmmsg` batches and sends in `sendmmsg` batches, replies coalescing into one send per received batch. `dispatch_model` (the same enum as the TCP engines) selects the worker shape: `.EPOLL` / `.URING` run one `SO_REUSEPORT` worker per CPU (per-core shared-nothing, the kernel load-balances datagrams), and `.ASYNC` / `.POOL` / `.MIXED` run a single worker. Dispatch is partitioned per ADR-043: a `src/udp/dispatch/` folder with one file per model plus `common.zig` and a thin `run()` switch, the same layout as `zix.Http1`. The typed path is unchanged and keeps its single async receive loop, and a non-ASYNC `dispatch_model` on the typed path folds with a logged notice rather than a silent no-op. QUIC-specific machinery (connection-ID demux, packet protection, transport state) stays out of `zix.Udp` and is reserved for a later `src/udp/http3/`.

**Rationale:** Batched syscalls (`recvmmsg` / `sendmmsg`) and per-core `SO_REUSEPORT` workers are the real datagram-throughput levers, so building them as a first-class `zix.Udp` capability earns its keep beyond QUIC and keeps a future QUIC layer focused on transport semantics rather than reaching around a fixed-struct messaging engine. The handler-plus-`Sink` shape keeps batching invisible: a reply queues into the send batch and the whole batch leaves as one `sendmmsg`, and a reply to the sender reuses the kernel-filled address with no conversion. Reusing the TCP `DispatchModel` enum and the ADR-043 dispatch folder keeps the engine family consistent. GSO (`UDP_SEGMENT`), GRO (`UDP_GRO`), ECN, and a dedicated io_uring submission path behind `.URING` are deferred: the offloads need per-message control-data paths whose correctness depends on hardware (GRO coalesces several datagrams into one buffer, so enabling it without a splitter would hand the handler a wrong super-datagram), so `.URING` folds to the `recvmmsg` per-core loop for now.

**Config:** new `UdpServerConfig` fields, all additive with safe defaults, used by the raw path: `dispatch_model` (required, no default), `workers` (0 = one per CPU), `reuse_address` (SO_REUSEADDR + SO_REUSEPORT), `recv_batch` / `send_batch` (the mmsg batch sizes), and `max_recv_buf` (the per-datagram buffer, the typed path keeps `@sizeOf(Packet)`). There is no `kernel_backlog`: UDP has no `listen` backlog.

**Consequences:**
- New `src/udp/datagram.zig` (raw-fd socket, `recvmmsg` with `MSG_WAITFORONE`, `sendmmsg`, `SO_REUSEPORT`, address conversion), `src/udp/core.zig` (`HandlerFn`, `Sink`), `src/udp/dispatch/` (`common.zig` plus one file per model), and `src/udp/raw.zig` (the `Raw` facade and `run()` switch). Sockets are raw `std.os.linux` syscalls, since `std.posix` no longer wraps `socket` / `bind` / `close`.
- `zix.Udp` exports `Raw`, `Sink`, `HandlerFn`, and `DispatchModel`. The typed `Server(Packet)` is unchanged except for the fold notice.
- New example `examples/udp_server_raw.zig` (port 9064) and runner `tests/runner/udp_raw_runner.zig`, plus a `udp-raw` case folded into `test-runner-all`.
- Non-Linux targets fall back to a single `std.Io.net` receive loop (no `recvmmsg` / `sendmmsg`).
- Phase two: a dedicated io_uring submission path behind `.URING` and GSO landed in ADR-056 (`src/udp/dispatch/uring.zig` real recv ring, `datagram.zig` `UDP_SEGMENT`). GRO / ECN stay deferred. ADR-056 also makes `.POOL` / `.MIXED` genuinely multi-core, correcting the "run a single worker" wording above.
- Phase three: optional connection-affinity steering. The `.EPOLL` / `.URING` per-core mapping is stateless fan-out (the kernel hashes datagrams by 4-tuple), correct for echo / DNS / telemetry but not for a connection-oriented protocol that needs datagram-to-owner affinity, since a QUIC connection migration changes the 4-tuple and can reach a worker without the connection state. Such a protocol runs the single-worker shape and demuxes internally, or sets an optional `steering` knob that routes by a protocol-supplied byte-range key (an `SO_REUSEPORT` eBPF program parameterized by offset and length), `zix.Udp` staying protocol-agnostic. Where steering is unavailable the per-core models fall back to the single-demux path.
- Green on Zig 0.16 and 0.17 (unit-test plus the 60-protocol test-runner-all).

---

## ADR-050: dispatch-model taxonomy and cross-platform backend matrix

**Status:** Accepted (`.KQUEUE` / `.IOCP` reserved, not yet implemented)

**Context:** The `DispatchModel` enum is shared across the engine family, but its values mix two axes: a concurrency shape (single or multi-core) and, for the per-core models, an OS-specific I/O backend (`.EPOLL` and `.URING` are Linux-only). Today some values alias (in `zix.Udp` raw mode `.POOL` and `.MIXED` both run a single worker), and an off-platform selection silently falls back to `.POOL`. As macOS (`kqueue`) and Windows (IOCP) support approaches, the family needs one predictable rule for what each model means and which OS runs it, so a developer never has to guess the core behavior or hunt for the backend.

**Decision:** Fix the meaning of each model: the OS swaps the backend, never the single-or-multi nature. `.ASYNC` is single-core everywhere. `.POOL` (thread pool) and `.MIXED` (hybrid) are multi-core everywhere. `.EPOLL`, `.KQUEUE`, and `.IOCP` are the same multi-core per-core idea, one per operating system (`.EPOLL` Linux, `.KQUEUE` macOS / BSD, `.IOCP` Windows), and `.URING` is the Linux completion ring. Every engine's `dispatch/` folder carries one file per model, so the folder is self-documenting and each model is independently tunable. Two mismatches are distinguished: a category error (a backend that cannot exist on the target OS, for example `.IOCP` on Linux) is a compile-time reject via `builtin.os.tag`, and a capability gap (a backend that exists but the machine cannot use, for example `.URING` on an old kernel) folds to a working model with a logged notice. There is no auto-select keyword: portable code picks a portable shape (`.POOL` / `.MIXED`) or a one-line comptime switch.

**Rationale:** A fixed contract removes the guess-work the aliasing and the silent fallback introduced. Keeping the OS backends as named, file-per-model entries (rather than hiding them behind one abstract per-core value) lets a developer see and tune the exact path for their platform, and matches the per-engine dispatch folder of ADR-043. The compile-time category error catches a wrong-OS pick at build, the earliest place, while the runtime capability fold keeps a correct-but-unavailable pick running. Rejecting an auto-select keyword keeps selection explicit: a value names exactly one behavior, never a per-machine surprise.

**Consequences:**
- `.KQUEUE` and `.IOCP` are reserved names, documented but not yet implemented. They are not created as empty source files: the reservation lives in this ADR and the concurrency reference.
- `zix.Udp` raw mode's `.POOL` / `.MIXED` aliasing to a single worker was the gap to close: both must be multi-core under the contract. Closed in ADR-056 (both run multi-core via `common.runMulti`), which makes this contract real and moves this ADR to Accepted.
- The existing non-Linux silent fallback of `.EPOLL` to `.POOL` is replaced, once the OS backends land, by the OS-native backend plus the category-error rule.
- The taxonomy is whole-family. `zix.Udp` and the HTTP/3 work (ADR-049 and `src/udp/http3/`) are one consumer.

---

## ADR-051: HTTP/3 over QUIC engine

**Status:** Accepted

**Context:** zix served HTTP/1.1, HTTP/2 (h2c and h2-over-TLS), and gRPC over TCP, but not HTTP/3, which runs over QUIC on UDP. QUIC is a large surface: packet protection, a transport state machine, loss recovery, QPACK header compression, the HTTP/3 framing layer, and a TLS 1.3 handshake that QUIC mandates and carries inside CRYPTO frames rather than TLS records. `std` provides the cryptographic primitives but none of the QUIC / HTTP-3 wiring, and the substrate (variable-length batched datagrams) only arrived with `zix.Udp` raw mode (ADR-049). The standing constraint also applies: a new engine must not need a C library, and must not regress the perf / memory gate.

**Decision:** Author HTTP/3 pure-Zig from the RFCs (9000 transport, 9001 QUIC-TLS, 9002 recovery, 9114 HTTP/3, 9204 QPACK) as `zix.Http3`, on the `zix.Udp` datagram substrate. The TLS 1.3 handshake reuses `src/tls` (key schedule, handshake messages, certificate), carried over QUIC CRYPTO frames in place of the TLS record layer, so there is one handshake implementation across TCP and QUIC. The deterministic layers are built and proven bottom-up against the RFCs' own worked-example vectors before assembly. The engine ships as v1: one single-worker recv loop with internal connection-id demux (keyed by the client's Destination Connection ID, with a Source-CID fallback for post-handshake packets), which is migration-safe by construction. `.EPOLL` / `.URING` fold to the v1 worker until per-core `SO_REUSEPORT` CID steering lands (v2, ADR-049 phase 3). Routing is a comptime `Router`, the same shape as `zix.Http1` / `zix.Http2`. The live path uses the QPACK static table and the RFC 7541 Huffman decoder for request paths. TLS 1.3 is mandatory, configured by the same user-owned `Tls.Context` as the TCP engines (ADR-047).

**Rationale:** Pure-Zig keeps the no-C-library rule and the single-handshake reuse, since QUIC-TLS differs from TLS-over-TCP only in record framing. Building and vector-proving each deterministic layer (crypto, transport, QPACK, HTTP/3, recovery) before assembly de-risks the largest protocol surface in the project and localizes any failure to the layer under test. The v1 single-worker shape is correct under connection migration without an eBPF steering asset, so it ships first and per-core scaling is a later, isolated change (the same fold pattern `zix.Http2` and `zix.Udp` raw mode already use). Mirroring the `zix.Http2` precedent, `zix.Http3` exports its low-level primitives (`crypto`, `protection`, `keyschedule`, `qpack`, `huffman`, `packet`, `varint`, `frame`, plus `tls_key_schedule`) so a peer can build the other side of the wire, which is what lets the test runner drive a hermetic native QUIC client with no external tool.

**Consequences:**
- New `src/udp/http3/`: the deterministic layers as tested library modules (crypto, protection, keyschedule, qpack, huffman, packet, varint, frame, recovery, h3), plus the engine layer (config, core, demux, connection, server, `dispatch/` per model) and the live-handshake driver (serverhello, flight, response, request, router). RFC vectors live in `test {}` blocks.
- `zix.Http3` exports the server type, the comptime `Router` / `Route`, and the low-level QUIC / TLS / QPACK primitives.
- New example `examples/tls/http3_basic.zig` (port 9063, ECDSA P-256). The round trip is validated by `curl --http3` (HTTP/3 200, clean exit) during development and, hermetically, by a native QUIC client hand-rolled from the exported primitives in `tests/runner/http3_client.zig`, wired as `test-runner-http3` and folded into `test-runner-all`.
- Green on Zig 0.16 and 0.17 (unit-test plus the 66-protocol test-runner-all).
- Deferred: cross-core CID steering for mid-connection migration (v2, ADR-049 phase 3), dynamic-table QPACK / key update / connection migration beyond the v1 demux, the QUIC Interop Runner and qlog traces, and the multi-core HttpArena throughput / memory gate.
- Superseded in part by ADR-056: `.EPOLL` / `.URING` now run as real per-core `SO_REUSEPORT` workers (not folded to the v1 worker), and RFC 9002 loss recovery plus NewReno congestion control now run on the serve hot path. Cross-core CID steering for mid-connection migration is the remaining v2 item.

---

## ADR-052: multiplexed TLS dispatch for Http2 and gRPC

**Status:** Accepted

**Context:** TLS for Http2 and gRPC was served by the ADR-046 terminator: run the handshake, then run the h2 engine behind a socketpair with a second worker thread, one thread per connection. That shape thrashes at high concurrency. At 512 or 1024 connections on a core count far below that, the scheduler churns one thread per connection and throughput collapses (the cleartext EPOLL and URING engines already multiplex many connections per core, but the TLS path did not). The socketpair plus the second thread were the cost, not the crypto.

**Decision:** For the `.EPOLL` and `.URING` dispatch models, terminate TLS in place on a multiplexed event loop. One `SO_REUSEPORT` listener plus one epoll instance per worker (worker count is the core count), each worker holding many TLS connections through a resumable TLS 1.3 session (`src/tcp/tls/tls_session.zig`): it accumulates ciphertext, processes each complete record, drives the resumable h2 / gRPC mux over the decrypted plaintext, and seals the engine's frames back into TLS records through a thread-local write hook. The new files are `src/tcp/http2/tls_mux.zig` and `src/tcp/http2/grpc/tls_mux.zig`. The socketpair and the per-connection second thread are removed everywhere: the `.ASYNC` / `.POOL` / `.MIXED` path keeps a thread-per-connection accept loop but runs the same inline-mux driver in `tcp/tls/h2_terminator.zig` (also no socketpair), and that path also serves the TLS 1.2 fallback. `server.run` routes `.EPOLL` / `.URING` with `config.tls` to `runTlsMux`, every other case to `runTls`.

**Rationale:** The thread-per-connection terminator was correct but did not scale, so https was latency-by-construction at high concurrency. Multiplexing TLS the same way the cleartext engines already multiplex matches the proven shape, so one worker per core holds thousands of half-open handshakes and established connections with no thread each. The resumable sans-I/O session is the linchpin that makes that possible. Keeping the low-concurrency and 1.2 cases on the inline-mux driver avoids forking the mux state machine. Proven locally on 6 cores (the worst case against the 64-core box): Http2 RSA at 512 connections and gRPC at 512 and 1024 connections serve with one worker thread per core, not per connection, and no hang, where the old path thrashed (load average in the hundreds, minutes to finish).

**Consequences:**
- ADR-046's socketpair plus thread-per-connection h2 / gRPC terminator is superseded: by this multiplexed dispatch for `.EPOLL` / `.URING`, and by the inline-mux driver for `.ASYNC` / `.POOL` / `.MIXED`. The socketpair is gone.
- The multiplexed path is TLS 1.3 only. A 1.2-only ClientHello on an `.EPOLL` / `.URING` https port is refused with a fatal alert. The 1.2 fallback lives on the thread-per-connection path.
- `.URING` with `config.tls` currently routes to the same epoll-multiplexed loop. A native io_uring TLS loop is a later optimization.
- Http1 TLS is still thread-per-connection (`tcp/http1/tls_serve.zig`), which json-tls rides. Porting the same dispatch to Http1 is the remaining step.
- New example `examples/tls/tls_grpc_basic.zig` (port 9070, ECDSA P-256) and runner `tests/runner/tls_grpc_basic_runner.zig` (a real unary gRPC call over TLS), green on Zig 0.16 and 0.17.
- The multiplexed Http2 and gRPC TLS workers now pin to their CPU slot (cgroup-mask aware) and size the worker count by the available cpuset, matching Http1's `tls_mux`. Without it the workers spawned host-many threads with no pin, so a cgroup-pinned cpuset oversubscribed one core under a handshake storm (the same collapse Http1 was fixed for).

---

## ADR-053: https serve path for zix.Http

**Status:** Accepted

**Context:** `zix.Http` (the arena engine) served cleartext only. Http1, Http2, and gRPC gained TLS (ADR-046, ADR-052), but the arena engine had no https path, so a deployment standardizing on `zix.Http` could not opt into TLS without an upstream proxy.

**Decision:** Add a gated TLS serve path to `zix.Http`, opt-in via `config.tls` (a `*Tls.Context`), mirroring Http1. The router response is captured into a buffer and encrypted: rather than author a new sink, the path reuses the arena engine's existing `RespSink` / `tl_resp_sink` response-coalescing hook (built for the URING path, ADR-037) by installing a sentinel-fd (-1) sink over the output buffer and running the normal `processRequest` with fd -1, so every Response write (the send fast path, `fdWriteAll`, static files, 404) serializes into the buffer instead of a socket, with no plaintext escape and no new cleartext hot-path branch. The cert / key / policy load once in `Tls.Context.init`. Two execution paths share the capture, picked by `dispatch_model`:
- `.ASYNC` / `.POOL` / `.MIXED`: thread-per-connection (`src/tcp/http/tls_serve.zig`). Each connection gets its own worker thread for the handshake (TLS 1.3, with a 1.2 ECDSA fallback) and the keep-alive loop.
- `.EPOLL` / `.URING`: event-driven multiplexed (`src/tcp/http/tls_mux.zig`). One SO_REUSEPORT epoll worker per core, many connections each, a resumable handshake / record state machine per connection (`src/tcp/tls/tls_session.zig`). The worker count is cpuset-aware (`getAvailableCpuCount`) and each worker pins to its core (`pinToCpu`), the same collapse-fix as Http1 / Http2 / gRPC (ADR-052).

`server.run` routes `config.tls` to the multiplexed worker for `.EPOLL` / `.URING` and to the thread-per-connection path otherwise.

**Rationale:** Reusing the existing sink keeps the cleartext path untouched (the `tl_resp_sink` null-check is already paid for the URING coalescing), so https adds zero overhead off the TLS path. The sentinel fd -1 makes a stray socket write fail safely instead of leaking plaintext past TLS. The multiplexed worker is the throughput path (parity with Http1), the thread-per-connection path is the simpler model and the home for handler-blocking work (SSE / streaming, WebSocket).

**Consequences:**
- Request / response is served on both paths. At this cut SSE / streaming and WebSocket were buffered-capture-incompatible (the handler writes incrementally and never returns, the buffer only flushes after the handler exits), so they detached the sink (`res.stream` nulls `tl_resp_sink`), surfaced as `StreamingNotSupported`, and closed cleanly. ADR-054 lands SSE / streaming over TLS (the streaming write hook below), so this no longer holds for SSE on the thread-per-connection path. WebSocket over TLS is ADR-055.
- The solution path for SSE / streaming over TLS (realized in ADR-054): a streaming TLS write hook on the thread-per-connection path. Instead of the buffered sink, install a thread-local writer that holds the live TLS session and the fd, so each `fdWriteAll` encrypts that chunk into TLS records and writes the ciphertext immediately (vs the buffered capture that accumulates plaintext and encrypts once). `res.stream` installs this writer instead of nulling the sink, so the existing SSE write loop flows unchanged, each event encrypted as it is produced. WebSocket (ADR-055) sends its upgrade response through the same stream sink, then runs the frame loop reading / writing through the same session. This belongs on the thread-per-connection path because, like cleartext SSE, it requires a blocking handler, which the multiplexed worker (one core, many connections) cannot host. The multiplexed `tls_mux` stays request / response only, matching cleartext `.EPOLL` / `.URING` which also do not serve handler-blocking SSE.
- `HttpServerConfig` gains `tls: ?*Tls.Context = null`. The cert is ECDSA P-256, Ed25519, or RSA (detected from the cert), Ed25519 and RSA require TLS 1.3.
- New example `examples/tls/tls_http_basic.zig` (port 9071). Verified end-to-end (curl + openssl: TLS 1.3, ALPN http/1.1, ECDSA P-256), both the multiplexed `.EPOLL` worker (keep-alive and concurrent connections multiplexed on one worker) and the thread-per-connection path, green on Zig 0.16 and 0.17.

---

## ADR-054: SSE / streaming over TLS for zix.Http and zix.Http1

**Status:** Accepted

**Context:** The https serve paths (ADR-053 for `zix.Http`, the approach-A path for `zix.Http1`) capture the handler's plaintext response into a buffer behind a `-1` sentinel fd, encrypt it once, and send it. That fits request / response but not a streaming handler (SSE): it loops emitting events and never returns, so a buffered capture deadlocks or overflows. ADR-053 left SSE / streaming over TLS out of scope for this reason.

**Decision:** On the thread-per-connection https path, add a per-connection streaming sink that encrypts one TLS record per write and sends it immediately, replacing the buffered capture only when a handler opts into streaming.
- A thread-local `TlsStreamSink` (type-erased over the live connection, so the TLS 1.3 and 1.2 paths share it) holds the connection and fd. Its write encrypts one record and sends it. It lives in `src/tcp/http/response.zig` (`zix.Http`) and `src/tcp/http1/core.zig` (`zix.Http1`).
- `fdWriteAll` precedence: the buffered capture sink first, then the stream sink, then the raw fd. During buffered capture both are armed and the capture wins. The opt-in switch detaches the capture, so writes fall through to the stream sink.
- Opt-in switch: `zix.Http` reuses `res.stream()` (it already detaches the sink, now it keeps the stream sink active over TLS, so no new public symbol). `zix.Http1` gains one call, `beginStream()`, a no-op in cleartext, so the same fd-handler serves cleartext and TLS.
- `serveRequests` installs the stream sink per connection and detects the streamed outcome (the capture sink was detached) to close after the stream ends.

**Rationale:** Reusing `fdWriteAll` as the one chokepoint keeps the buffered fast path for normal responses untouched (the capture sink still wins until a handler streams), so SSE adds nothing off the streaming path. A streaming handler parks its own per-connection thread, which is exactly the thread-per-connection model the https path already uses, so no new execution model is needed.

**Consequences:**
- SSE / streaming is served over TLS on the thread-per-connection path (`.ASYNC` / `.POOL` / `.MIXED`) for both engines. The multiplexed `tls_mux` path (`.EPOLL` / `.URING`) stays request / response only: hosting a long-lived stream there needs event-loop state-machine work, out of scope. SSE on `zix.Http` already requires the thread-per-connection model in cleartext, so TLS adds no new limit.
- Per-event size is bounded by one TLS record (~16 KiB plaintext), ample for an SSE event.
- New examples `examples/tls/tls_http_sse.zig` (port 9072) and `examples/tls/tls_http1_sse.zig` (port 9073). `examples/http1_sse.zig` now calls `beginStream()` so one handler serves cleartext and TLS. Verified end-to-end with the native `zix.Tls` client (handshake, GET /events, decrypt, `Content-Type: text/event-stream` plus the first event), green on Zig 0.16 and 0.17.
- WebSocket over TLS (bidirectional, the read path) builds on this stream sink and is ADR-055.

---

## ADR-055: WebSocket over TLS for zix.Http and zix.Http1

**Status:** Accepted

**Context:** SSE over TLS (ADR-054) added a streaming write hook on the thread-per-connection https path. WebSocket is the bidirectional sibling: after the `101` upgrade it needs both the write half (encrypt outbound frames) and a read half (decrypt inbound records, parse frames). The cleartext WS paths cannot serve TLS: `zix.Http1`'s `WebSocket.serve` hands the raw fd to the `.EPOLL` engine (there is no engine loop on the thread-per-connection path), and `zix.Http`'s `WebSocket.upgrade` writes onto a `std.Io` stream and the handler reads the raw stream. Over TLS the fd is the `-1` sentinel and the stream is fake, so neither runs.

**Decision:** Add an engine-driven WebSocket-over-TLS path on the thread-per-connection https loop, built on the ADR-054 stream sink for the write half and an inline frame loop for the read half. A handler served over TLS calls `WebSocket.serveTls(fd, key, on_frame)` instead of the cleartext `serve` / `upgrade`:
- `serveTls` detaches the buffered capture (the ADR-054 stream sink takes over), writes the `101` through it (encrypted), and registers the handoff (`requestWebSocket`).
- After the handler returns, `serveRequests` calls `takeWebSocket` and runs an inline frame loop (`serveWsTls`): read one ciphertext record, decrypt it (`conn.readAppData`), accumulate, and pump every complete frame. A text / binary frame invokes `on_frame`, ping is auto-ponged, close is auto-echoed. Outbound frames flow through the stream sink (`fdWriteAll` -> `conn.writeAppData`), so each pump pass encrypts its coalesced frames as one record.
- `zix.Http1` reuses its existing frame codec (`parseFrame` / `pump` / `send`) and the `requestWebSocket` / `takeWebSocket` handoff. `zix.Http` gains the engine-driven pieces (`WsFrameFn`, `send`, `pump`, the handoff, `upgradeFd`) so the same `on_frame(fd, opcode, payload)` shape and `serveTls` entry work on both engines.

**Rationale:** The frame codec is unchanged, only the transport moves from a raw fd / stream to the TLS session. Running the loop inline in the connection thread fits the thread-per-connection model the https path already uses (a WS connection is long-lived and owns its thread), and reusing the ADR-054 stream sink means the same `fdWriteAll` chokepoint encrypts both SSE events and WS frames.

**Consequences:**
- WebSocket is served over TLS on the thread-per-connection path (`.ASYNC` / `.POOL` / `.MIXED`) for both engines. The multiplexed `tls_mux` path (`.EPOLL` / `.URING`) stays request / response only and drops any erroneous handoff.
- Rooms / broadcast are not served over TLS: each connection has its own TLS session, so a frame must be encrypted per connection. WS over TLS is per-connection (echo / point-to-point), the cleartext arena example keeps the room model.
- New examples `examples/tls/tls_http1_ws.zig` (port 9074) and `examples/tls/tls_http_ws.zig` (port 9075). Verified end-to-end with the native `zix.Tls` client (handshake, WS upgrade, encrypted `101`, masked frame, decrypted echo), green on Zig 0.16 and 0.17.

---

## ADR-056: HTTP/3 hot-path loss recovery, congestion control, and real per-core .EPOLL / .URING

**Status:** Accepted

**Context:** ADR-051 shipped HTTP/3 v1 as one single-worker recv loop with internal connection-id demux, and it deferred two things: loss recovery / congestion control on the serving hot path, and per-core scaling (`.EPOLL` / `.URING` folded to the single v1 worker). Two problems followed under sustained multi-connection large-body load. One worker is the throughput ceiling because a single core drains every datagram. And without loss recovery a dropped tail packet stalls a whole response: no later packet acknowledges it, so nothing re-pumps the lost bytes and the stream hangs until the idle timeout. The deterministic `recovery.zig` layer already carried an RTT estimator, a Probe Timeout, and a NewReno controller (proven against RFC 9002 vectors), but the serve path did not drive them.

**Decision:** Bring RFC 9002 loss recovery and NewReno congestion control onto the `zix.Http3` serve path, and run `.EPOLL` / `.URING` as real per-core `SO_REUSEPORT` workers instead of folding to the v1 worker.
- Loss recovery and NewReno run on the serve path: `recovery.zig` (RTT estimator, PTO with backoff up to `connection.max_pto_backoff` = 6, `CongestionController` congestion-event handling, persistent congestion), driven by `connection.onAckFrame`. Only ack-detected loss cuts the congestion window.
- A timer-driven maintenance sweep (`dispatch/common.sweepMaintenance`) runs every `maintenance_interval_us` (5 ms), armed by a bounded `epoll_wait` timeout on `.EPOLL` and a timeout SQE on `.URING`. It declares a timed-out in-flight range lost and re-pumps it (`resumeStreams`).
- A Probe Timeout is not a congestion signal: `connection.onMaintenance` retransmits and bumps `pto_backoff` only. It does NOT reduce cwnd (RFC 9002 6.2). A prior attempt that halved cwnd on every PTO collapsed the window and pinned connections congestion-window-blocked, and was reverted.
- Eviction policy: `onMaintenance` frees a connection (via `demux.remove`) only when the close state is draining or closed (CONNECTION_CLOSE, frames `0x1c` / `0x1d`) or the peer has been idle past `max_idle_ms` (tracked by `last_activity_us`). Loss never evicts a live-but-lossy peer.
- Table slot reuse: `demux` gained `remove` / `freeSlot` / `at` / an `occupied` map with a tombstone sentinel (`maxInt(u32)`) that probe chains skip past, so a reclaimed slot is reused without growing the index.
- Per-core `.EPOLL` / `.URING`: `server.run` routes `.POOL` / `.MIXED` to `common.runMulti`, `.EPOLL` to `dispatch/epoll.runEpoll`, `.URING` to `dispatch/uring.runUring`, and only `.ASYNC` stays single-core. Each worker owns its own CID table (shared-nothing, the kernel load-balancing by 4-tuple). `.URING` is a real io_uring ring (recvmsg SQEs, replies through the sendmmsg batch), falling back to the `.EPOLL` loop when io_uring is unavailable.
- `zix.Udp` raw gains ADR-049 phase two on the same cut: `src/udp/dispatch/uring.zig` is a real recvmsg io_uring ring, and `datagram.zig` adds UDP GSO (`UDP_SEGMENT`) via `probeGso` / `flushGso` / `submitUring`.

**Rationale:** The recovery machinery already existed and was vector-proven, so wiring it onto the serve path (rather than authoring it fresh) is low-risk and localizes the change to `connection` and the dispatch sweep. Retransmitting on PTO without cutting cwnd is the RFC 9002 6.2 rule and the reverted halve-on-PTO experiment is the evidence for why: a probe is a suspicion of loss, not a confirmation, so treating it as a congestion signal starves the window. Reclaiming a slot only on close or idle (never on loss) keeps a lossy-but-live peer connected, which is the whole point of recovery. Per-core `SO_REUSEPORT` workers match the shape the cleartext TCP engines and `zix.Udp` raw already use, so scaling HTTP/3 needs no new execution model, and per-core CID tables are correct as long as a connection's 4-tuple is stable (cross-core migration is the one case left to v2).

**Consequences:**
- Superseding ADR-051: the ".EPOLL / .URING fold to the v1 worker" shape (now real per-core) and the "loss-and-congestion in the hot path" deferral (now shipped) are both superseded. Cross-core CID steering for mid-connection migration remains the only v2 item from ADR-051.
- Superseding ADR-049: this lands phase two (a dedicated io_uring submission path behind `.URING` plus GSO) for `zix.Udp` raw, and corrects the ".POOL / .MIXED run a single worker" wording (both are multi-core via `runMulti`). GRO and ECN stay deferred.
- ADR-050: closes the "zix.Udp raw .POOL / .MIXED aliasing to a single worker" gap. This ADR is the second consumer that makes ADR-050's contract real.
- Correctness gate: full-body byte-exact under heavy fragmentation (~218 packets per response) plus recovery after an overload burst, green on Zig 0.16 and 0.17.
- Deferred: send pacing to spread a congestion window over the RTT instead of one burst (the residual `.EPOLL` throughput gap under sustained large-body load, `.URING` paces implicitly through completions), cross-core CID steering (eBPF) for mid-connection migration, GRO / ECN, and key update.

---

## ADR-057: gRPC server-streaming DATA-frame coalescing

**Status:** Accepted

**Context:** gRPC server-streaming emitted one HTTP/2 DATA frame per message. Each `sendMessage` wrote a 9-byte frame header plus a 5-byte gRPC prefix wrapping the payload, so a `count = 5000` reply was 5000 tiny DATA frames, about 45 KiB of frame headers, and 5000 frame parses on the client. On the HttpArena gRPC benchmark the server-streaming cells (`stream-grpc` / `stream-grpc-tls`) left the server at 5 to 10 percent CPU, idle, with throughput well below what that headroom allowed. The wall was the load client parsing frames, not zix. A first attempt to grow the reply cork (to avoid a mid-handler blocking flush) did not move throughput and was reverted, because the worker was never parked on that flush.

**Decision:** Coalesce consecutive gRPC messages into fewer, larger DATA frames on the mux cork path. `GrpcContext` gains an optional coalesce buffer (`_coal`). `muxDispatch` installs one for a server-streaming route. `sendMessage` packs each gRPC-framed message into the buffer and emits one DATA frame per `grpc_stream_coalesce_cap` (16 KiB, the HTTP/2 default `SETTINGS_MAX_FRAME_SIZE`), flushing the remainder at `finish()`. The frame length is known before the frame is written (pack, then emit), so there is no back-patch and the cork may flush freely between frames. Unary and the thread path (`.ASYNC` / `.POOL` / `.MIXED`) keep one frame per message (`_coal` null), so unary is byte-for-byte unchanged.

**Rationale:** The lever is the peer's per-frame cost, not the server's send. With the server idle and every send path already cheap, throughput was capped by the load client parsing HTTP/2 frames. Packing about 5000 messages into about 3 DATA frames cuts the frame-header bytes on the wire roughly in half and the client's frame-parse count by about 1600x. The 16 KiB cap keeps every emitted frame within a client's default max frame size, so no client reconfiguration is needed, and the message stream inside the DATA payload is unchanged (a conformant gRPC client reassembles length-prefixed messages regardless of frame boundaries). The fix lives in the shared `muxDispatch`, so `.URING`, `.EPOLL`, and both TLS mux paths inherit it in the one change.

**Consequences:**
- `stream-grpc` and `stream-grpc-tls` throughput rose about 44 to 50 percent (roughly 2.3M to 3.4M messages per second), with the server still at roughly 6 to 9 percent CPU.
- Unary is unchanged: one message, one frame.
- Deferred: the thread path (`.ASYNC` / `.POOL` / `.MIXED`) still emits one frame per message. It has no cork to pack into and needs its own per-context accumulator, deferred until the URING and EPOLL sweep across the other engines lands.

---

## ADR-058: per-worker stream-slot pool for the multiplexed engines

**Status:** Accepted

**Context:** The multiplexed (`.EPOLL` / `.URING`) HTTP/2 and gRPC engines reserved a full stream table per connection at accept. `MuxConn` / `GrpcMuxConn` allocated `max_streams` stream slots, each carrying an inline header table plus body and scratch buffers, whether the connection was busy or idle. Resident memory therefore tracked connection count, not in-flight work. On the HttpArena benchmark `zix.Http2` held about 6x more memory than the work needed at 4096 connections (baseline-h2c), and `zix.Grpc` about 12x more at 1024 connections (unary-grpc, roughly 916 MiB). Buffer-size shrinks did not close it: the bulk was the table itself, provisioned at peak per connection.

**Decision:** Borrow each stream's slot from a per-worker pool. A thread-local free-list of stream slots is shared across every connection on the worker (shared-nothing per worker, no atomics). A connection borrows a slot on stream open (`acquireStream` in `mux.zig`, `acquireGrpcStream` in `grpc/core.zig`) and returns it on close (`releaseStream` / `releaseGrpcStream`), reusing the slot's buffers, so the steady state does no per-stream allocation. `MuxConn.streams` / `GrpcMuxConn.streams` becomes a `max_streams`-wide pointer array (`[]*Stream`, about 1 KiB per connection) in place of the inline table, and the eager per-connection body / scratch backing is removed. Scoped to the multiplexed engines only: the blocking `.ASYNC` / `.POOL` / `.MIXED` paths keep their own per-connection arrays, since each connection is its own thread and a per-worker pool of one buys nothing.

**Rationale:** One worker drives many connections, so the worker, not the connection, is the natural owner of stream state. Sizing that state to the concurrent streams on the worker instead of `connections * max_streams` makes memory track work. The change also lifted throughput 8 to 20 percent on the small-body cells, because the pooled hot slots (LIFO reuse) have a tight cache working set where the old sparse per-connection table was cache-thrashing, a both-axes result. Decoupling memory from `max_streams` lets the advertised stream concurrency default rise with no per-connection memory cost.

**Consequences:**
- `zix.Http2` 4096c baseline-h2c memory fell about 6x with throughput up 8 to 20 percent. `zix.Grpc` 1024c unary memory fell about 12x (roughly 916 to 77 MiB) with throughput up 8 to 11 percent. URING and EPOLL stay tied.
- Config defaults folded as a direct consequence: `max_streams` 16 to 128 and `max_body` 64 KiB to 16 KiB on both `Http2ServerConfig` / `ServeOpts` and `GrpcServerConfig` / `GrpcServeOpts`. `max_header_scratch` stays 4 KiB.
- The blocking `.ASYNC` / `.POOL` / `.MIXED` paths are unchanged. `zix.Http1` WebSocket, which reuses the Http1 slab (a different memory model), is a future candidate.
- Post-pool read-buffer and body-buffer shrinks were demand-paged no-ops (the high-connection residual is kernel socket buffers, not app buffers), so the pool is the memory lever.

---

## ADR-059: response-API send / write / FD naming taxonomy

**Status:** Accepted

**Context:** The response-writing surface grew per engine with no single rule. The same idea appeared as `write*` on one engine and `send*` on another, and raw fd plumbing (`fdWrite*`) leaked into response paths. Reading a call site did not tell you whether it shaped a response or just moved bytes, nor whether it touched a raw fd. That ambiguity resurfaced every time compression or a new engine was discussed.

**Decision:** Name every response-path function by two independent axes. Verb axis: a function that sends a response, or any outbound communication, is `send*`, a pure write with no send is `write*`. Suffix axis: a signature that takes a raw `fd` parameter ends in `FD`, an fd held inside a struct (reached through `self`) does not count, so object methods stay clean.

| bucket | example |
| :- | :- |
| send + fd | `sendGzipFD(fd, ...)` |
| send + no fd | `Response.sendJson(...)` |
| write + fd | `writeAllFD(fd, bytes)` |
| write + no fd | `wire.writeU16(...)` |

Compression-capable engines expose the same six: `sendGzipFD`, `sendGzipCachedFD`, `sendBrotliFD`, `sendBrotliCachedFD`, `sendNegotiateFD`, `sendNegotiateCachedFD`. Negotiate routes internally through the same gzip / brotli path, so the compression policy lives in one place. The precompressed / caller-encoded primitive (`sendResponseEncodedFD` shape) stays as the layer those six build on.

**Rationale:** Two orthogonal axes make a name self-describing: the verb says whether bytes leave as a response, the suffix says whether a raw fd is in the signature. A reader classifies any call at a glance without opening the body, and the rule scales to every engine and to future codings, so the same idea can no longer surface under two names.

**Consequences:**
- Wide but mechanical rename. Function bodies and parameters are unchanged, only names and the doc / comment text that references them.
- The correction lands before new code. The two brotli twins and the uncached `sendNegotiateFD` are added afterward.
- HttpArena entries change call sites only, never behavior.
- Rolled out engine by engine (Http1, WebSocket, Http2, Grpc, Http3, then the full server plus shared tls / dispatch), each step gated by the full test suite.

---

## ADR-060: TLS dual listener (tls_port) and the shared tls_conn transport

**Status:** Accepted

**Context:** TLS was all-or-nothing per server: a non-null `config.tls` flipped the whole server to a TLS-only path, so serving cleartext and https from one process required a second `Server` launch. The second launch duplicated a full runtime: worker fleet, MAX_FD fd tables, epoll instances, response / static caches. The four `tls_mux.zig` files each carried a near-identical copy of the per-connection TLS transport (about 2k lines total), under `.URING` the TLS side still ran a parallel epoll fleet, and WebSocket / SSE over TLS were confined to the thread-per-connection path (ADR-054 / ADR-055).

**Decision:** TLS becomes a connection property behind one flat config field, `tls_port: u16 = 0`, on `Http1ServerConfig`, `HttpServerConfig`, `Http2ServerConfig`, and `GrpcServerConfig`:

| tls | tls_port | behavior |
| :- | :- | :- |
| null | any | cleartext only on port (unchanged, tls_port ignored) |
| set | 0 | TLS-only on port (unchanged) |
| set | non-zero | ONE server: cleartext on port + TLS on tls_port, same workers |

`tls_port == port` is rejected at run() (`error.TlsPortConflict`). Supporting decisions:

- Shared transport module `src/multiplexers/tls_conn.zig`: the per-connection TLS byte transport (resumable session, outbound-ciphertext backpressure buffer, fd -> connection slot table) lifted out of the four tls_mux copies. Engine loops stay per-engine (ADR-050) and feed the module.
- `.EPOLL`: the TLS listen fd joins the same epoll instance. TLS events carry a tag bit in the epoll data word (`tls_event_tag | fd`), and TLS connections live in a pointer table mapped only when tls_port is active, so a cleartext-only worker sees zero layout change.
- `.URING`: TLS rides the ring for the first time (`tls_accept` / `tls_recv` / `tls_send` ops in the shared user_data codec), no hidden epoll fleet. Flushes are half-duplex: staged ciphertext is sent on-ring before the next recv is armed, so the staging buffer never moves while the kernel reads it.
- Thread models (`.ASYNC` / `.POOL` / `.MIXED`): one extra accept thread (`serveTlsThread`) serves the TLS side through the existing tls_serve path (WebSocket + SSE included).
- The `zix.Http1` mux loop now hosts WebSocket (the `WebSocket.serve` handoff plus the frame pump) and SSE (`beginStream`) over TLS, encrypt-on-write through a per-connection stream sink, dissolving the ADR-054 / ADR-055 thread-path restriction there. `zix.Http` hosts `res.stream()` the same way. Its WebSocket stays on the thread path (parity with its cleartext mux loop, which does not host WS either).
- ALPN scoping for a shared Context stays engine-side: the h2 engines reject a session that did not negotiate h2 (`alpnIsH2`), `Http1` / `zix.Http` accept the rest. One Context listing every served protocol can back all engines in a process, no per-engine ALPN override field.
- `zix.Http3` is exempt: QUIC is always encrypted (one UDP listener, `tls` required), it participates by sharing the one `Tls.Context`.

**Rationale:** The second launch was pure duplication. The only TLS-specific per-connection cost is the session state (keys, staging buffers), which cannot be shared anyway, so folding the TLS listener into the one loop keeps exactly that cost and deletes everything else: one fleet, one fd-slot layout, one cache set serving both transports.

**Consequences:**
- Dual serving drops from 2 worker fleets / 2 fd tables / 2 cache sets to 1, plus a demand-paged TLS pointer slab mapped only when tls_port is active.
- Cleartext hot path unchanged: connection registration switched to the u64 epoll-data form (same bytes for an fd) and TLS routing adds one predictable branch per event. Gate: isolate bench, more than 1% RPS drop reverts.
- Shared unit tests (tls_conn), per-engine dual-listener integration tests (.EPOLL / .URING / .POOL, plus SSE over the mux), example `examples/tls/tls_http1_dual.zig` (9076 cleartext / 9077 TLS) with the `tls-http1-dual` runner check.

---

## ADR-061: REUSEPORT CPU steering (reuseport_cbpf), worker pin completion, and per-worker load counters

**Status:** Accepted

**Context:** The multiplexed engines pin one SO_REUSEPORT worker per core, but the kernel places connections by 4-tuple hash, blind to which CPU received the packets: a connection can land on worker A while its packets soft-irq on CPU B, costing cross-CPU wakeups and cold caches on every request. `zix.Tcp` and `zix.Fix` also predated the pinning convention (their workers ran unpinned), pin order followed the raw affinity mask (SMT siblings interleaved with physical cores), and load balance across workers was unobservable (no per-worker counters).

**Decision:** Three placement moves behind one new flat config field:

- `reuseport_cbpf: bool = false` on every server config except `zix.Uds`: attach SO_ATTACH_REUSEPORT_CBPF to the per-worker REUSEPORT group (`src/multiplexers/reuseport.zig`), placing a new connection (TCP) or each datagram (UDP) at listener index = receiving CPU mod workers instead of the 4-tuple hash. Listeners bind inside racing worker threads, so a startup-only bind-order gate (`BindOrderGate` / `BindTurn`) serializes the joins: group index i = worker i = pin slot i. The turn release is idempotent and defer-backed, so a failed bind never wedges the sibling workers. TLS dual listeners form a second REUSEPORT group with their own attach.
- Pinning completes the family: `zix.Tcp` and `zix.Fix` `.EPOLL` / `.URING` workers now pin per-core with a cpuset-aware worker count, and every engine's pin order fills physical cores first, SMT siblings after (sysfs package/core keys, stable two-pass, mask order kept when sysfs is absent).
- Per-worker load counters report at worker exit through the system logger (requests, frames, accepted connections, or messages, per engine), so REUSEPORT skew across workers is observable. The two h2-mux engines (`zix.Http2`, `zix.Grpc`) carry no counter: a threadlocal increment in their mux dispatch measured about 1 percent of throughput at multi-million req/s and was removed.
- QUIC: `reuseport_cbpf` stays available on `zix.Http3` but is warned against in the field doc comment and the config reference, not rejected. Per-packet CPU steering breaks QUIC flow affinity (a flow's packets land on workers without its connection state), measured as a heavy throughput drop with zero failed requests. Nothing hard-fails, so the guard is documentation, keeping the opt-in contract identical on every engine.

**Rationale:** Default false keeps the kernel hash, which already balances on a loopback box (measured throughput-neutral across the TCP engines). The value case is a multi-CPU host where NIC RSS spreads soft-irqs: steering makes connection placement follow the receiving core, which the per-core pin then serves without a cross-CPU handoff. An opt-in field with a documented QUIC warning preserves the one flat config vocabulary across engines instead of a per-engine exception or a hard error on a field that is valid everywhere else.

**Consequences:**
- Zero hot-path cost: the CBPF program runs in the kernel at placement time (per SYN on TCP, per packet on UDP), and the bind-order gate exists only during the startup binds.
- The counters cost one per-worker-local increment per unit served on six engines, and nothing on the mux engines (cost measured there, so removed there).
- Isolate A/B (before / steering off / steering on, five subjects, three full runs each): steering off is throughput-neutral with lower CPU-at-best on several cells, steering on is neutral on the TCP subjects over loopback and collapses `zix.Http3`, which is recorded as the warning in the field comment and `docs/zix-config-en.md` / `-id.md`.
- Silent no-op on a kernel before 4.5 (no SO_ATTACH_REUSEPORT_CBPF), matching the busy-poll posture.

---

## ADR-062: zix.Http1 hot path engine ergonomic handler (Request, Response, Context trio)

**Status:** Accepted

**Context:** The zix.Http1 raw engine runs hand-rolled multiplexed loops (`.URING` on io_uring, `.EPOLL` on epoll) plus the blocking `.ASYNC` / `.POOL` / `.MIXED` paths, all pinned per core. The handler contract was `fn(head: *const ParsedHead, body: []const u8, fd: fd_t) void`: a route wrote its response by calling raw fd writers (`sendSimpleFD`, `sendJsonFD`, `writeAllFD`) against the socket. That is the fastest possible shape, but it is not the shape the full engine zix.Http offers, where a route takes a Request view, a Response builder, and a Context (io, a per-request allocator, a deadline). Two handler vocabularies across the two HTTP engines is a learning and maintenance cost, and the raw shape gives a route no typed request view, no error channel, and no per-request allocator.

**Decision:** Replace the engine handler signature with the trio. One shape, no wrapper, no additive second path:

- `HandlerFn = *const fn(req: *Request, res: *Response, ctx: *Context) anyerror!void` in `src/tcp/http1/core.zig`, where `Request`, `Response`, and `Context` are re-exported. `Request` is a zero-copy view over the parsed head, the body, and the fd. `Response` (`src/tcp/http1/response.zig`) is a thin builder over the existing `core` writers, so its send methods emit byte-identical wire to `sendSimpleFD` / `sendJsonFD` / `writeAllFD`. `Context` carries io, a per-request arena allocator, the fd, and the deadline hooks.
- `core.invokeHandler(handler, head, body, fd, io, allocator)` builds the trio in one place and, on a handler error, writes a single 500 only when the response was not already sent (`Response.sent`). Every dispatch model calls through it, so the error-to-500 policy is identical everywhere.
- io and a per-request arena (reset with `.retain_capacity`) thread to every call site: the blocking `serveConn` gained an io parameter plus its own per-connection arena (async, pool, and mixed pass `config.io`), the epoll and uring workers hold a `req_arena` and io, and the TLS buffer path (`tls_serve.runHandlerToBuffer`) sources io from `core.tl_static_io`.
- `Router.dispatch` becomes `fn(*Request, *Response, *Context) anyerror!void`, matches on `req.head`, and falls through to a 404. The house handler idiom is `try res.foo(...)`, never `return res.foo(...)`: a guard writes then returns, a final statement is a bare `try`, a stream writes the header then `catch return` per event.

**Rationale:** One handler vocabulary across zix.Http1 and zix.Http removes the second shape a route author has to learn, and gives every zix.Http1 route a typed request view, an error channel (`anyerror!void`), and a per-request arena, without a wrapper layer. Building the trio inside `invokeHandler` keeps the raw dispatch loops untouched: the URING and EPOLL loops still own their own send sink and buffers, the trio is constructed per request from stack-cheap views, and `Response` delegates to the same byte-for-byte writers, so the wire output does not change. Replacing the signature rather than adding a parallel `!void` path avoids carrying two handler types and the drift between them.

**Extension (trio parity and canonical send* naming):** The signature landed identical, but the trio types behind it were not: zix.Http1 exposed a raw u16 status and string content type against zix.Http's typed enums, the same concepts carried different names across the engines (json vs sendJson, param vs pathParam, noContent, serveCached, stream), and the helper modules (method, status, content, parser) existed only on the zix.Http side. The extension makes the trio caller-identical:

- Module copies, not sharing: src/tcp/http1/ gains its own method.zig, status.zig, content.zig (identical copies of the http versions) plus parser.zig (the head-parse family extracted from core.zig, re-exported under the same core.* names so every dispatch loop compiles unchanged). Cross-engine utilities stay in src/utils/ as before.
- Canonical send* on both engines: every body-sending Response method is send*. zix.Http1 renames json -> sendJson, text -> sendText, raw -> sendRaw and gains setKeepAlive, addHeader, sendNoContent, sendFromCache, sendCached, sendNegotiated, sendStream. zix.Http renames noContent -> sendNoContent, serveCached -> sendFromCache, stream -> sendStream and gains sendText, sendRaw. Request: param -> pathParam on http1, plus queryParams, pathSegments, body(), fromRaw, and keepAlive on both. Context gains withDeadline on http1. Typed trio surface: setStatus(Status.Code), setContentType(Content.Type), req.method() returns Method.Code.
- Response.sent is the sent flag on both engines. zix.Http's dead Context.response_sent is deleted, and its handler-error path now writes one 500 only when the handler wrote nothing (previously an erroring handler fell through to the 404 branch), the same policy as http1's invokeHandler.
- Caller-identical, engine-owned internals: http1's body() returns the engine-delivered slice (the engine drains and dechunks before invoke, no socket read in a handler), zix.Http's body() stays the lazy socket read. The Context escape hatch stays engine-native (stream on http, fd on http1). New http1 Response methods delegate to the existing core writers, and the no-extras send path is byte-identical to before (asserted in tests).
- Config alignment: http1 gains max_response_headers (HeaderSize, the addHeader capacity, installed per worker on every model including the TLS paths) and conn_timeout_ms (a ConnRegistry port of http's Layer D, active on .ASYNC, .POOL, .MIXED, documented no-op on .EPOLL and .URING whose event loops own connection lifetime). http1's max_headers is deleted: it was a documented no-op (the on-demand parser has no header array to bound), so the intent cannot apply. http gains send_date_header and uring_idle_pool_ceiling (its URING idle pool cap now clamps between floor and ceiling like http1), and its shared-name defaults follow http1 (kernel_backlog 1024, max_recv_buf 6 * 1024, uring_idle_pool_floor 8).
- One init: http1's initRaw and the RawFn hook are removed (zero consumers existed outside the engine plumbing, the comptime raw_fn was null everywhere in practice, so codegen is identical). Server.init(handler, config) is the single entry.
- middleware.zig is deleted from zix.Http: nothing imported it. Comptime wrapper composition (examples/http_middleware.zig, examples/http1_middleware.zig) is the middleware idiom for both engines.
- Namespace parity: both Http.zig and Http1.zig export Method, Status, Content, ContentType (previously neither exported them, enum literals hid it), and Http1.zig additionally re-exports setCache, SseWriter, Header, HeaderSize, Multipart, MultipartField. A compile-time test in src/lib.zig asserts the full canonical trio surface resolves on both namespaces, so drift now fails the build.

**Consequences:**
- Hot path neutral on all raw profiles except one. Between the pre-trio engine and the trio engine the raw isolate profiles sit inside the bench run-to-run noise (about 2 to 3 percent): baseline 512c 868,986 to 936,038, pipelined 512c 9,668,886 to 9,719,625, limited-conn, json, json-comp, and upload flat. The per-request `Request` / `Response` / `Context` are stack views plus an arena reset (`.retain_capacity`), so steady state does no per-request heap allocation.
- static 1024c, settled: static sat about 5 percent under the pre-trio baseline (323,300 to 305,071) across the trio-era runs, consistent rather than a one-run blip. Later engine work (independent of this ADR) recovered most of it: subsequent boots read 308,402 to 313,570, about 3 to 4 percent under the pre-trio figure, inside that cell's cross-day drift band (the same sessions showed swings of that size on baseline 512c). Accepted as the closing state of this record.
- One 500 policy: a handler that returns an error without having sent gets exactly one 500 from `invokeHandler`, on every model including the TLS buffer path.
- The per-request arena is available to a route for scratch (multipart parse, JSON build) and resets between requests, so a route no longer needs its own threadlocal scratch for that.
- TLS unit tests that drive the serve path directly source io as `core.tl_static_io orelse undefined` (the static io is set only when the TLS listener starts), so a direct-path test never dereferences a null io.
- Migration surface: all in-src mock and test handlers, every `examples/http1_*.zig` and `examples/tls/tls_http1_*.zig`, and the http1 integration tests moved to the trio. Source unit 813 of 813, test-all, the nine test-runners, and every example are green, and `zig fmt` is clean.
- Extension migration surface: the typed enums and canonical names are a breaking sweep over every handler body (setStatus(.OK), req.method() == .GET, sendJson, pathParam, try req.body()), applied to src, every http and http1 example (both SSE examples now use res.sendStream() and the event writer), the test suites, and the consumer entries. After the extension: unit 836 of 836, test-all 1196 of 1196, every example builds, 16 live test-runners pass, `zig fmt` clean. The isolate bench gate ran 2026-07-16 against the pre-extension reference: DB profiles hold (crud, async-db, api-4 flat, api-16 +3.2 percent), the raw mean is flat (-0.1 percent across the 16 raw profiles), and the 3 cells below the 2 percent band (pipelined 512c -2.3, limited-conn 4096c -2.2, json 4096c -3.2) are mirrored by 3 cells above it (+2.4 to +3.3), the symmetric scatter of the documented 2 to 3 percent run-to-run band rather than a hot path shift. Whole-matrix memory holds (steady median 86.8 MiB, peak 415.7 MiB, both within the pre-extension envelope). Later boots hold the same trio surface with the same profile signature, and the record is accepted 2026-07-17.

---

## ADR-063: engine handler trio parity (Request, Response, Context) and explicit Router across engines

**Status:** Accepted

**Context:** Not every engine gave its handler the same three roles. `zix.Http` and `zix.Http1` had the full trio since ADR-062. The others did not:

| Engine | Request-like view | Response-like builder | Context-like env |
| :- | :- | :- | :- |
| Http / Http1 | yes, typed `Request` | yes, typed `Response` | yes, `Context` |
| Http3 | yes, `Request` | yes, `Response` | missing, no ctx param, no error return |
| Http2 | missing, raw `method` / `path` / `headers` / `body` args | missing, writes via free `sendResponseFD` on a raw `fd` / `sid` | missing |
| Grpc | missing, raw `headers` slice | missing, writes via free `sendHeadersFD` / `sendDataFD` on `ctx`'s fd | yes, `GrpcContext` |
| Fix | missing, raw `fields` slice | missing, writes via `buildMessage` on `ctx`'s fd | yes, `FixContext` |

Router had a matching split. `Http`, `Http2`, `Grpc`, `Fix` took a route array straight into `Server.init(routes, config)`, the router built internally, the user never calling `Router(...)`. `Http1` and `Http3` required the user to call `zix.ENGINE.Router(&[_]zix.ENGINE.Route{...})` and hand `.dispatch` to `Server.init(handler, config)`. That split is why examples read differently per engine, and why an application moving a route from one engine to another had to relearn the handler shape.

**Decision:** Every engine gets the trio, protocol-shaped, and the Http1 router idiom everywhere, in one combined pass across all five engines (Fix, Http, Http2, Grpc, Http3, in that order):

- Trio on all engines: `Request`, `Response`, `Context`, with `HandlerFn = *const fn(*Request, *Response, *Context) anyerror!void`. Not forced into identical structs, each engine keeps its own shapes for what its protocol actually carries, but the three roles exist everywhere and the idiom matches Http1's (`try res.foo(...)`, a `Response.sent` guard, `Context` holding io, a per-request arena, a deadline, and the fd / session escape hatch).
- Router: `Server.init(handler, config)` everywhere, the user building the handler via `zix.ENGINE.Router(&[_]zix.ENGINE.Route{...}).dispatch`. Breaking change for `Http`, `Http2`, `Grpc`, `Fix`, mirroring ADR-062's approach on Http1. Every example and the affected test suites moved to the same call-site idiom.
- Names stay bare per namespace (`zix.Http2.Request`), not engine-prefixed.
- Handler-error wire policy: `Http1`, `Http2`, `Http3` auto-send one 500 when the handler errors and nothing was sent (the ADR-062 rule, extended). `Grpc` and `Fix` pass errors through silently, current wire behavior kept, invoke site is `handler(&req, &res, &ctx) catch {}`. **Superseded in part by ADR-068**, which gives `Grpc` and `Fix` a wire answer of their own and makes "nothing was sent" count an fd answer as well.
- Raw expose: the raw `send*FD` surfaces stay public on `Http1`, `Http2`, `Grpc`, `Http3`. `Http` and `Fix` get no raw expose.
- Fix timeout fold: `server_timeout_ms` stopped being a bare third `dispatch` argument. The effective-timeout calculation moved to where `Context` is built, and `deadline_ns` carries the result. No raw timeout field was added.

**Rationale:** One handler vocabulary across all engines: when moving between engines the memory carries over, less learning curve. Building the trio at the invoke site keeps the tuned dispatch loops untouched, the same pattern ADR-062 proved on Http1 (stack-cheap views, byte-identical writers underneath).

**Parity matrix:** same name, same behavior, only where the protocol has the concept. A "no" means the concept does not exist in that protocol, so the method is absent, never a stub that lies.

| Member | Http / Http1 | Http2 | Http3 | Grpc | Fix |
| :- | :- | :- | :- | :- | :- |
| `Request.method` | yes | yes | yes | no (always POST) | no |
| `Request.path` | yes | yes | yes | yes | no |
| `Request.query` / `queryParam` / `queryParams` | yes | yes | no (handler parses `req.path` manually, no query API this pass) | no | no |
| `Request.pathParam` / `pathSegments` | yes | pathSegments only, no PARAM route kind this pass | PARAM route kind exists, but `pathParam` is a package free function (`zix.Http3.pathParam`) off a threadlocal, not a `Request` method | no | no |
| `Request.header` | yes | yes | no (no generic accessor, specific headers are pre-parsed into named `Request` fields: `authority`, `accept_encoding`) | yes | no |
| `Request.body` / `bodyReceived` | yes | yes | yes (plain field, no `bodyReceived` distinction) | yes (proto bytes) | no |
| `Request.getField` (typed field view) | no | no | no | no | yes |
| `Request.keepAlive` | yes | no (persistent by protocol) | no (same) | no | no |
| `Response.setStatus` / `setContentType` / `addHeader` | yes | yes | `setStatus` only, `content_type` is a plain field not wired to the wire yet, no `addHeader` (the v1 HTTP/3 response path emits only `:status` and `content-encoding`) | no | no |
| `Response.send` / `sendJson` / `sendText` / `sendNoContent` | yes | yes | `send` only, no `sendJson` / `sendText` / `sendNoContent` this pass | no | no |
| `Response.sendRaw` (pre-built wire bytes verbatim) | yes | no (h2 has no flat pre-buildable wire form, everything is HPACK plus framed) | no (no raw pre-built-bytes surface exposed this pass) | no | no |
| `Response.sendNegotiated` | yes | no (no compression negotiation exists for Http2, ADR-059's own track, out of scope this pass) | no (handler negotiates manually via `accept_encoding` plus `setContentEncoding`, no `sendNegotiated` helper this pass) | no | no |
| `Response.setKeepAlive` | yes | no | no | no | no |
| `Response.sendStream` (SSE) / `sendFromCache` / `sendCached` | yes | out of scope this pass | out of scope this pass | `serveCached` / `sendCached` only, no SSE (a pre-existing response-cache feature, not new here) | no |
| `Response.sendMessage` / `finish(status)` | no | no | no | yes | no |
| `Response.sendMessage(msg_type, fields)` | no | no | no | no | yes |
| `Context.withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut` | yes | yes | yes | yes | yes |
| `Context` io plus per-request arena | yes | yes | yes | yes | yes |

**Consequences:**
- Fix: `Request` is a typed view over `fields` reusing `getField`, `Response` is a builder over `buildMessage` plus the SOH-framed write with `sendMessage(msg_type, fields)`. `Context` folds the effective-timeout calculation in at build (`deadline_ns` carries it, no raw field) and gains `io` plus a per-request arena (a stack `FixedBufferAllocator`, no heap call, keeping the FIX core zero-heap-allocation). `Server.init(handler, config)` takes `handler: ?HandlerFn`, null keeps the existing echo-only mode. Examples migrated, tests added.
- Http: bigger than the one-liner implied. `zix.Http.Server` was a comptime-generic-over-routes type (`HttpServerImpl(routes)`), it became one concrete struct holding a runtime `handler: HandlerFn`. `Router(routes).dispatch` changed from a `self`-taking method returning `!bool` to a plain `fn(req, res, ctx) anyerror!void` matching `HandlerFn` exactly, absorbing the static-file-fallback and 404 that `dispatch/common.zig` used to own externally (mirrors Http1's router). `Context` gained a `public_dir: []const u8` field so the router can reach it without a threadlocal (Http1 keeps its own `tl_static_dir`, unchanged). 17 examples plus `uds_http` migrated, 4 router / tls_dual test files migrated. Static-file-serving and 404 fallback verified end to end by hand (curl against a running `example-http_static`), not just compiled.
- Http2: the biggest of the five. Routing was comptime-threaded through roughly 20 function signatures across `core.zig`, `mux.zig`, all 5 `dispatch/*.zig` files, and both TLS paths (`tls_serve.zig`, `tls_mux.zig`), not baked into the server type once like Http. Every `comptime routes: []const Route` parameter became a plain runtime `handler: HandlerFn`, and 3 comptime-generic worker-function factories (`epollMuxWorkerFn`, `uringMuxWorkerFn`, `workerFn` in `tls_mux.zig`) flattened into plain functions carrying `handler` as a struct field instead. `Request`, `Response`, `Context`, `Router` built from scratch (Http2 had none of the trio before), matching the parity matrix above (no PARAM route kind, no `sendNegotiated`, no `sendRaw`, no `keepAlive`). `handler_timeout_ms` added to `Http2ServerConfig` (Http2 had no timeout concept at all before this). Wire byte-identity against `sendResponseFD` asserted in tests. 5 `http2_basic_*` examples plus 4 test files migrated. Verified end to end by hand: curled a running `example-http2_basic_1_async` over h2c prior-knowledge.
- Grpc: `Server.init` is the one deliberate exception to the otherwise-uniform `Server.init(handler, config)` shape. It takes `Server.init(Router(&routes), config)`, the comptime Router TYPE, not `.dispatch`, because `Route.is_server_streaming` is metadata the engine reads before invoking the handler, to pick sync-inline dispatch (unary, cheap) versus task-spawn dispatch (streaming, needed so a long-running stream does not block other h2 streams on the same connection), and a bare opaque `handler: HandlerFn` cannot carry that metadata. Settled empirically: an isolated-process scratchpad PoC measured direct-call dispatch at 44.8M RPS on 1 core, `io.async` task-spawn (64 concurrent) at 1.14M RPS needing about 4.7 cores (roughly 185x worse per core), and raw `std.Thread.spawn` at 5,954 RPS total (roughly 7,500x worse). Unifying onto always-task-spawn was not an acceptable simplification. `Router(routes)` gained `pub const route_slice: []const Route = routes`, and every dispatch model keeps `comptime RouterType: type` instead of dropping to a runtime handler value. `GrpcRequest` / `GrpcResponse` are thin delegating wrappers holding a `*GrpcContext` pointer, forwarding to the pre-existing, already-tuned `GrpcContext` methods, zero internal logic moved or duplicated. 12 examples plus 4 test files migrated. Verified end to end by hand: the gRPC example client against a running async server (unary and streaming), and `grpcurl` (real protobuf wire encoding) against a two-service, one-port example.
- Http3: much thinner than Http2 and Grpc. Only one real handler invoke site existed in the whole engine (`dispatch/common.zig`'s per-packet request loop), so there was no comptime-routes threading to unwind, `comptime handler: core.HandlerFn` stayed exactly as it was at every `dispatch/*.zig` factory function, only the `HandlerFn` typedef's shape changed. `Context` added `stream_id` as the raw escape hatch (QUIC has no per-request fd), the timeout helper set, `io`, and a stack-arena allocator. `Response` gained a `sent: bool` flag. `core.invokeHandler` builds the Context and auto-500s only when the handler errored and nothing was sent. `Server.init(handler, config)` was already in place and needed no change. One example migrated (4 handlers). Verified end to end by hand with `curl --http3-only` against a running server: a plain body, a query-sum, a 256 KiB multi-packet body, and brotli content negotiation all round-tripped correctly.
- Supersedes ADR-014's `Server.init(comptime routes: []const Route, config) HttpServerImpl(routes)` for `zix.Http`: `Server` is now one concrete struct, not a comptime generic, and `routes` is no longer a direct `Server.init` argument.
- Guardrails held across all five: no change to hot-path wire mechanics (`send*FD` writers stay byte-identical, the tuned `.EPOLL` / `.URING` dispatch loops are untouched internally, only what wraps their handler call changed), and both `zig-0.16` and `zig-0.17` build clean throughout.
- Migration surface: `test-all` 1249 of 1249 tests, 131 of 131 steps, `examples` 205 of 205 steps, both compilers, `zig fmt` clean.

---

## ADR-064: public_dir static cache across all four HTTP engines

**Status:** Accepted

**Context:** Static file serving was half-built, and slow where it existed.

| Engine | `public_dir` field | static file | how the body went out |
| :- | :- | :- | :- |
| zix.Http | yes | `src/tcp/http/static.zig` | per-request `openFile` plus `stat` plus an 8 KiB read/write copy loop |
| zix.Http1 | yes | `src/tcp/http1/static.zig` | the same loop, writing through `core.writeAllFD` |
| zix.Http2 | no | none | not built |
| zix.Http3 | no | none | not built |

Every request for the same file paid 2 syscalls to locate it, then `ceil(size / 8 KiB)` reads and as many writes, plus a full userspace copy of every byte. Nothing was remembered between requests, and the two implementations were near duplicates of each other.

The shipped `cache_ttl_ms` and `cache_max_entries` pair could not be reused. Those drive `src/utils/response_cache.zig` (ADR-036), a per-worker keyed response slab whose key is `hashKeyEncoded(method, path, query, encoding)`, deliberately coupled to compression and to handler-produced responses. A static file has a different owner, a different lifetime, and a different body source (a descriptor, not a byte slice), so it needs its own knobs.

**Decision:** One shared cache module plus one thin per-engine static file, behind two new flat config fields present on all four engines.

- New `src/utils/static_cache.zig`, owning the name index, TTL stamps, the open file, its size, the prerendered response header bytes, pin counts, and reclaim. It knows nothing about HTTP versions.
- New `src/utils/static_send.zig`, owning one thing: moving a byte range of an open file to a socket, with `sendfile` or by copying through the engine's own write function.
- New `src/utils/http_range.zig`, a shared RFC 7233 parser that splits reading the header from clamping it against a known length, so a malformed header can be ignored (200) while a well-formed unsatisfiable one is answered 416.
- Each engine's `static.zig` owns encoding negotiation, framing for its own wire format, and the send. Only the framing differs, so only the framing is duplicated.
- Two new flat fields mirroring the shipped `cache_*` naming: `public_dir_cache_ttl_ms: u32 = 0` and `public_dir_cache_max_entries: u32 = 256`. `zix.Http2` and `zix.Http3` also gain `public_dir` itself.
- `public_dir_cache_ttl_ms = 0` means never cached, and it is the default. That leg runs the prior code path byte for byte, so an existing deployment cannot regress by upgrading.
- The cache is process-wide, not per-worker: one descriptor per cached variant instead of one per worker, lock-free acquire-ordered reads, and a spinlock only on the rare insert. A deliberate exception to the shared-nothing idiom used elsewhere, taken because the cached value is a kernel object rather than per-worker state.
- One atomic word per slot carries both the live flag and the pin count. A reader pins with a compare-and-swap that only succeeds while the slot is live, and reclaim clears the live flag with a compare-and-swap that only succeeds at zero pins. Two separate words would race: a reclaim could pass its pin check between a reader's key match and its pin.
- The key is the resolved identity path, and one slot holds all three variants of that file. A client accepting brotli for a file with no `.br` sibling shares the identity entry instead of consuming a second slot.
- Precompressed siblings are picked up from disk only. `foo.js.br` and `foo.js.gz` are opened once at insert, and `compression.negotiate` picks per request among the variants that exist. No on-the-fly compression. Every variant header carries `Vary: Accept-Encoding`, identity included, so an intermediary cannot hand a brotli body to a client that did not ask for one.
- A miss is never cached, so a flood of unknown paths costs one failed open each and leaves the table untouched. Fill is lazy, with no startup walk.
- Overflow never fails a request. Three tiers: reclaim first (a full insert sweeps a bounded 8 slots, freeing any expired and unpinned), then serve uncached through the existing path, and never allocate on the hot path. A full table is a slower response, not an error.
- Clean-up has no timer thread. A lookup landing on an expired entry reclaims it in place and reports a miss, and a full insert sweeps as above. Bounded means no lookup pays for a full-table scan, which is what keeps the tail latency flat.
- Expiry doubles as the staleness window: an expired hit becomes a miss, the miss re-opens and re-stats, so a file changed on disk is picked up within one TTL with no inotify machinery.
- An entry whose bytes back an in-flight send is pinned, and reclaim skips it. A `sendfile` of a large file over a slow socket can outlive the TTL, and closing the descriptor underneath it would truncate a live response.
- `public_dir_cache_max_entries` is clamped at init against `RLIMIT_NOFILE`, since one entry holds up to three open files. The result is reported through an `InstallResult` return rather than logged, so the module never writes to stderr on a caller's behalf.
- `zix.Http3` takes its body from a SNAPSHOT the cache holds, not from the descriptor and not from a mapping. Bounded by `SNAPSHOT_MAX_BYTES` (8 MiB), taken on the first request that needs it, with the pin held for the whole response. Because the body can only come from the cache, `public_dir_cache_ttl_ms = 0` disables static serving on that engine entirely rather than merely turning the cache off.

**Body path per engine:** the entry keeps the file open always, and the paths that need bytes read them positionally (`readPositionalAll`, a `pread`) rather than mapping. A positional read needs no lifetime management, works on every target, and is safe on a descriptor shared by every worker, since it never moves the file offset.

| Engine | header | body | why |
| :- | :- | :- | :- |
| zix.Http cleartext | prerendered bytes | `sendfile` | thread per connection, blocking descriptor, the simplest case |
| zix.Http1 cleartext | prerendered bytes | `sendfile` | descriptor to socket, no userspace copy |
| zix.Http / Http1 with TLS | staged into the record path | resident snapshot, then encrypt | records are built in userspace, `sendfile` cannot apply |
| zix.Http2 | HPACK HEADERS frame | resident snapshot cut into DATA frames | the mux coalescing hook is installed on every batch, cleartext included, so a direct write would put the body ahead of frames already staged |
| zix.Http3 | QPACK HEADERS | snapshot held by the cache, pinned for the whole response | QUIC encrypts every packet, and the body is re-read for every packet and every retransmission |

`sendfile` here is the Linux shape. The existing read/write loop stays as the portable fallback under the same comptime split the tree already uses for its other fast paths, so no platform loses static serving.

**Rationale:** The four properties that make a fast static path fast are cache properties, not protocol properties, which is why they belong in one shared module. A resolved name to open descriptor is remembered, so `open` and `stat` happen once per file instead of once per request. The response header is rendered once at insert and replayed as bytes. The body goes out with `sendfile` where it can, kernel to kernel, with no userspace copy and no RSS growth. Sibling selection is resolved at insert rather than probed per request. Steady state per request becomes one hash lookup, one header send, and one body send.

Sizing is runtime rather than comptime because the library cannot know how many files sit under someone's `public_dir`, so a baked-in `[N]Entry` would be wrong for nearly every user. The no-crash property comes from the overflow policy, not from where the array lives. `ResponseCache` already proves the runtime pattern in this tree (`slab_mem.mapZeroedSlots`, kernel-zeroed, demand-paged, one mapping at init), so reusing it keeps one idiom instead of two.

A slot is a 256 B path buffer plus three variants of roughly 290 B each, near 1.1 KiB, so the default table is about 290 KiB of address space for the whole process. That is virtual, not resident: an untouched slot costs no physical memory. Open descriptors are the real per-entry cost, which is why the init clamp exists.

Precompressed siblings landed in the same pass for a structural reason and a value reason. Structurally, the key has to carry the encoding either way, so adding the pickup later would mean rewriting the index instead of extending it. By value, once caching removes the syscalls, the only lever left is sending fewer bytes.

**A file mapping was measured and rejected for the Http3 snapshot.** A body too large for one packet is parked in a send-stream slot and re-read for every packet and every retransmission, so it has to be stable, randomly readable memory that outlives the handler. Five sources were measured at the engine's own constants (1040 B chunk, 256 KiB body, ReleaseFast):

| strategy | ns per packet | vs baseline |
| :- | :- | :- |
| resident bytes, memcpy | 15.7 | 1.00x |
| mmap the file, memcpy | 16.1 | 1.02x |
| 64 KiB block read, memcpy | 120 | 7.2x |
| raw pread per packet | 567 | 34x |
| `std.Io` `readPositionalAll` per packet | 668 | 40x |

Per-packet reads are out: the syscall floor on the development box is 324 ns, so they add a syscall to a path that already pays one `sendmsg` per packet. Per-stream buffers are out on arithmetic alone: 256 connections per worker times 64 send streams is 16,384 concurrent large bodies, so even 64 KiB each is 1 GiB per worker.

That left mmap, which measured essentially free, and it was implemented before a test rejected it. A file rewritten IN PLACE, which is what copying a new build over a served file does, changes under a mapping a response is still reading: verified directly, an in-place rewrite showed the new bytes through an existing mapping while an atomic rename left the mapping on the old inode untouched. So an in-flight response would serve the new file's bytes, and a file that shrank would fault past its own end and take the process with it. Being able to crash a server by copying a file into its own `public_dir` is not an acceptable trade for 0.4 ns per packet. The landed snapshot cannot be changed underneath a response, and measured marginally faster than mmap because there is no page-fault path.

**Consequences:**

- Default behavior is unchanged. With `public_dir_cache_ttl_ms = 0` the cache is never consulted, so both the fast path and its fallback are inert for anyone who does not opt in.
- One process-wide mutable structure now exists in a tree that is otherwise shared-nothing. Reads are lock-free with acquire ordering and the spinlock is held only across an insert, but the exception is real and is documented here so it is not copied by default into unrelated work.
- Files served from cache reflect disk state up to one TTL late. A deployment that swaps assets in place should keep the TTL short or leave caching off during the swap.
- Range is served on `zix.Http`, `zix.Http1`, and `zix.Http2`. A multi-range header answers the first range only. `zix.Http3` serves whole files only, a deliberate gap in this pass.
- `public_dir_upload` is not added to `zix.Http2` or `zix.Http3`. Neither has an upload handler convention, and adding one alongside net-new static serving would mix two concerns in one pass.
- The cached path emits `Vary: Accept-Encoding` and the uncached path does not. Only the cached path negotiates, so only it has something to vary on.
- `zix.Http2` gained an explicit `peer_max_frame_size` parameter on `core.invokeHandler`. `ServeOpts.max_frame_size` is this server's receive-side advertisement and had been reused as the outbound cap, which a peer may answer with FRAME_SIZE_ERROR. Three producers now feed the correct value: the mux (which already tracked it), the h2c loop (updated from SETTINGS mid-connection), and the h2c upgrade path (read from the base64 `HTTP2-Settings` header).
- `Cache-Control`, `ETag`, and `Last-Modified` stay out of scope. Those are the user's concern, not the engine's, in this pass.

**Guardrails held:** no allocation on the request path, every array sized once at init. `zig fmt` clean, `test-all` green on `zig-0.16` and `zig-0.17`, `examples` green, and all 7 targets of the cross-build matrix compiling clean. The `public_dir_cache_ttl_ms = 0` leg stays byte for byte identical to the prior path, which is what keeps `zix.Http1` off the perf gate.

## ADR-065: drop the POOL and MIXED dispatch models

**Status:** Accepted

**Context:** `DispatchModel` carried five values: `.ASYNC`, `.POOL`, `.MIXED`, `.EPOLL`, `.URING`. Five models across eight engines meant 40 dispatch loops to keep correct, and only three of them were actually maintained. `.EPOLL` and `.URING` are Linux-only, so `.POOL` also served a second job nobody chose it for: it was the silent fallback target off Linux.

That fallback was the real problem. Every engine's `run()` contained a branch like this:

```zig
.EPOLL => if (comptime builtin.target.os.tag == .linux)
    epoll_model.runEpoll(cfg, handler)
else blk: {
    common.logSystem(cfg, "EPOLL is Linux-only. Falling back to POOL.", .{});

    break :blk pool_model.runPool(cfg, handler);
},
```

A caller who configured a shared-nothing per-core loop and deployed to Windows got a thread pool instead. The log line was the only signal, and a server with no logger configured emitted nothing in release. The caller's throughput, memory, and latency profile all changed, silently.

`.POOL` and `.MIXED` were also not free to keep. `.POOL` needed a `ConnQueue` (mutex, condvar, growable ring) and two thread roles per engine, `.MIXED` needed a third accept-thread shape with its own stack-size workaround for the `io.async` inline fallback. Both existed in every engine's `dispatch/` directory and in every engine's `common.zig`.

**Decision:** Keep the three maintained models. Reject an unsupported one instead of downgrading it.

- `DispatchModel` becomes `ASYNC = 0`, `EPOLL = 1`, `URING = 2`. Gapless, because nothing serializes the value: it is source-level config only.
- Off Linux, an engine's `run()` returns `error.DispatchModelUnsupported` for `.EPOLL` and `.URING`. It logs which model was rejected first, so an operator sees the cause and not just an error name.
- The check is one shared predicate, `src/utils/dispatch_support.zig`, consulted at the top of every `run()` before it opens a listener, spawns a timer thread, or detaches a TLS accept thread. A rejected config therefore leaves nothing behind.
- The 16 `dispatch/pool.zig` and `dispatch/mixed.zig` files are deleted, along with the `ConnQueue`, `WorkerCtx`, `PoolCtx`, and `AsyncWorkerCtx` helpers that only they used.
- `pool_size` is removed from all 8 configs, and `pool_stack_size_bytes` from `zix.Fix`. In `zix.Http2` and `zix.Grpc` `pool_size` was the `.EPOLL` / `.URING` worker count while `workers` was POOL and MIXED only, so those two engines are repointed onto `workers`. All 8 engines now read the same field for the same purpose. Both defaulted to 0, so default behaviour is unchanged.
- The numbered per-model examples collapse to one unified example per engine (`examples/http1_basic.zig`, `examples/tcp_server.zig`, and so on), each picking its model per target at comptime:

```zig
const DISPATCH_MODEL: zix.Http1.DispatchModel = if (builtin.os.tag == .linux) .URING else .ASYNC;
```

Four examples kept a Linux-only pin at the time this decision was taken, because compression, the WebSocket pump, and the io_uring WebSocket demo were installed by the multiplexed workers only. ADR-066 removed that limitation, so no example pins a dispatch model any more.

**Consequences:**

- A caller outside this tree that set `.POOL`, `.MIXED`, `pool_size`, or `pool_stack_size_bytes` no longer compiles. That is the intent: a compile error names the problem, where the old fallback did not.
- `.ASYNC` is now the only portable model, and the six non-Linux targets in the cross-build matrix all use it. It is also the model to reach for on Linux when connections are long-lived (SSE, WebSocket).
- The `.URING` runtime fold to `.EPOLL` stays. That is a different thing: a capability gap on a platform that does support the model (an old kernel, a low `RLIMIT_MEMLOCK`, a sandbox), not a platform mismatch. It keeps its logged notice.
- The per-model test-runner matrix collapses to one runner row per engine. Two legs are lost and named here rather than left to be discovered: the `http1-drain` runner keeps only its URING leg, and `grpc-stream` now shares port 9032 with `grpc`.
- `tests/runner/common.zig:skipDispatchOffPlatform` previously substring-matched the label for `"epoll"` and `"uring"`. Collapsing the runner rows removed those words from every label, so the guard silently stopped matching anything. It became an exact-match list of the Linux-only scenario labels, which cannot rot the same way unnoticed.
- `tests/behaviour/dispatch/platform_gate_test.zig` covers the predicate and the enum shape, and skips nothing. Three earlier tests that called each engine's `run()` to observe the rejection were removed: they could only ever execute off Linux, so they were a permanent skip on the platform they were developed on. What is lost is a runtime check that `run()` consults the predicate, which the compile still proves the call site of.
- This supersedes the `.POOL` and `.MIXED` parts of ADR-043 (per-engine `dispatch/` rollout) and ADR-058 (per-worker pool). The rest of both stands.
- `.KQUEUE` and `.IOCP` remain reserved names in ADR-050, and the same rule now applies to them: a model ships when it has a maintainer. Until then non-Linux targets use `.ASYNC`.

**Guardrails held:** `zig fmt` clean, `test-all` green on `zig-0.16` and `zig-0.17` with zero skips, `examples` green, `test-runner-all` green across all 52 protocols, and `scripts/build-all-targets.sh` reporting `all targets passed` for the full 7-target matrix. Dispatch loops themselves are untouched, so the only path this decision moved is the `pool_size` to `workers` repoint on the `zix.Http2` and `zix.Grpc` worker-count read.

---

## ADR-066: every feature works under .ASYNC, on every platform

**Status:** Accepted

**Context:** ADR-065 left `.ASYNC` as the only model available off Linux. That is only useful if `.ASYNC` can actually serve what the engine advertises. It could not.

Three separate gaps, found by auditing rather than by a failing test, because none of them fail on a Linux development machine:

1. **Features the multiplexed workers installed and `.ASYNC` did not.** Response compression and the response cache are per-worker threadlocal switches, installed once per worker by `dispatch/epoll.zig` and `dispatch/uring.zig`. `.ASYNC` has no worker: `io.async` hands each connection to whichever pool thread is free, so nothing ever installed them. A server with `compress = true` on `.ASYNC` returned uncompressed bodies with no error. The engine-owned WebSocket promotion was worse: `core.zig` took the handoff and dropped it, ending the connection.

2. **A two-way platform split that silently targeted the wrong kernel.** Six files branched `if (windows) ... else <Linux syscall>`, so macOS, FreeBSD, NetBSD and OpenBSD fell into the Linux branch and issued Linux syscall numbers. `tls_serve.zig` is the `.ASYNC` TLS path, so TLS over `.ASYNC` was broken on four of the seven supported platforms. It compiled, which is why the cross-build sweep never caught it, and those four legs had never been run.

3. **Protocols with no portable path.** HTTP/3's `runSingle` logged a line and returned void off Linux, so `run()` reported success and never bound a socket. Unix-domain sockets bound a relative path, which the Windows AF_UNIX bind rejects outright, and the channel IPC pair used `/tmp/...`, a location Windows does not have.

**Decision:** `.ASYNC` is not a reduced model. Anything the engine offers works under it, on every supported platform. A feature may be faster on a multiplexed model, never absent from `.ASYNC`.

- **Use `std.Io` wherever it reaches.** A raw accepted descriptor becomes a `std.Io.net.Stream` and is driven through the stream reader and writer, with no OS branch at all. Handshake secrets come from `io.randomSecure`, which is safe from a plain `std.Thread` and carries the platform's CSPRNG. This is the 0.16 answer to portability, and it replaces hand-rolled syscall shims.
- **Where `std.Io` does not reach, split three ways and guard the Linux branch.** `sendfile`, `recvmmsg` and `sendmmsg`, `epoll`, `io_uring` and `socketpair` have no `std.Io` equivalent. Those get a comptime `windows` / `linux` / `posix` split, where posix covers macOS and the three BSDs. A two-way split is the defect in context item 2 and must not reappear.
- **New shared substrate**, one responsibility each:

| Module | Owns |
| :- | :- |
| `utils/fd_io.zig` | blocking read / write / close / readiness on a raw descriptor |
| `utils/socket_pair.zig` | a connected descriptor pair, socketpair on POSIX, loopback on Windows |
| `utils/socket_path.zig` | where a local socket lives, absolute and identical for both ends |
| `utils/async_cache.zig` | the response cache for `.ASYNC`, one per io pool thread, plus reclaim |

- **The `.ASYNC` cache is threadlocal, not shared and not per connection.** Per connection it would die before it ever hit. Shared it would need a lock on the response path. Threadlocal matches the shared-nothing design the multiplexed workers already use. A threadlocal has no destructor and a `ResponseCache` owns an arena plus an mmap slab, so every cache is recorded in a registry and the accept loop reclaims them all on exit.
- **HTTP/3 gains a portable fallback**, mirroring the one `udp` already had: one datagram per receive over `std.Io` instead of a `recvmmsg` batch, reusing the QUIC state machine unchanged. The send helpers only queue into the batch, so a `flushPortable` on `SendBatch` was the only new primitive needed.
- **Local socket paths are resolved, not written literally.** Both ends derive the same absolute path from the same working directory, so there is no shared state and no platform-specific literal.

**Consequences:**

- The four examples ADR-065 pinned to a multiplexed model all take the per-target idiom, so no example pins a dispatch model any more and every one of them starts on every platform.
- `examples/http1_websocket_uring.zig` is deleted. Under the idiom `http1_websocket.zig` already runs `.URING` on Linux and so already exercises `websocket.pumpRing`, which made the separate example redundant. Its `/ws` echo route moved across, next to the existing `/ws/:room-id` rooms demo, and its runner became `test-runner-http1-websocket-echo` on the surviving port. Port 9029 is retired, not reused.
- `tests/runner/common.zig:linux_only_labels` is now empty. Every one of the 52 runner scenarios is expected to pass on every platform.
- 85 unit, integration and edge tests dropped their `!= .linux` skip guard, because what made them Linux-only was the test harness (`socketpair`, `pipe2`, `memfd_create`) and not the behaviour under test. Eight logger tests traded their `!= .linux` guard for a narrower `== .windows` one: they read a log file back through `openat(AT.FDCWD)`, which Windows has no equivalent for, so they now run on macOS and the three BSDs where they never did before.
- `.ASYNC` remains slower than a multiplexed model under load. Nothing here changes that, and nothing here touches the `.EPOLL` / `.URING` install path: their per-worker cache and compression setup is byte for byte what it was.
- A caller on macOS or a BSD who was somehow relying on the old TLS behaviour was relying on undefined behaviour. There is no compatibility story to preserve.

**How the defect in context item 2 is found again:** for each file, count production `linux.*` calls before the first `test "`, then count `os.tag == .windows` guards against `os.tag == .linux` guards. A file with Windows guards and zero Linux guards is the two-way split, and it will compile cleanly on every target while running on none of them but Linux.

**Guardrails held:** `zig fmt` clean, `test-all` 1422/1422 on both `zig-0.16` and `zig-0.17`, `test-runner-all` green across all 52 protocols, and `scripts/build-all-targets.sh` reporting `all targets passed` with `test-all`, `examples` and `test-runner-all` compiling for every triple. Each new behaviour was proven by forcing `.ASYNC` on Linux and running the real runner rather than by inspection: compression through `http1-compression` and `http-compression`, the response cache through `http1-cache`, WebSocket through `http1-websocket`, the HTTP/3 portable fallback through the `http3` runner forced onto `runFallback` (handshake plus two multiplexed requests), and the local socket paths through `uds`, `uds-http` and `channel-ipc`.

---

## ADR-067: zix.Webrtc, a WebRTC peer as its own engine

**Status:** Accepted

**Context:** A browser cannot open a raw socket. The only transports it offers a server are HTTP, WebSocket and WebRTC, and only WebRTC gives unreliable delivery, a per-channel choice about ordering, and audio and video. zix had the first two and not the third.

WebRTC is not one protocol. Reaching a browser at all means answering ICE connectivity checks carried over STUN, completing a DTLS 1.2 handshake, running SCTP inside it for data channels, and negotiating all of that through SDP. Carrying media means SRTP on top of that. Every one of those is a separate wire format with its own RFC.

Three constraints shaped the design before any code was written:

1. **It is timer-driven.** DTLS retransmits on a 1 second doubling timer, SCTP has its own retransmission timeout, ICE has consent freshness, and an idle peer has to be dropped. Nothing else in zix's UDP family needs a clock: `zix.Udp` in raw mode hands a handler `fn (datagram, peer, sink) void` and its dispatch path has no tick, no deadline and no clock anywhere. Adding one to `zix.Udp` would have made every raw UDP server pay for a facility only WebRTC uses.

2. **A peer is its 4-tuple.** Every datagram of one session, whatever protocol it carries inside, arrives from the same address and port and has to reach the same state machine. That rules out the receive-CPU steering (`reuseport_cbpf`) the raw UDP and HTTP/3 engines use, because steering picks a worker by receiving CPU and could split one session across two workers in the middle of a handshake.

3. **Self-testing proves nothing here.** Eight layers tested against themselves agree with their own mistakes. This is an interop protocol, so the exit criterion for every phase had to be an independent implementation, first OpenSSL and then a real browser.

**Decision:** WebRTC is its own engine at `src/udp/webrtc/`, owning its socket and its own `dispatch/`, not a mode of `zix.Udp`.

- **DTLS lives in `src/tls/` with a flat `dtls_` prefix**, beside the TLS 1.2 and 1.3 code it shares primitives with, not under the WebRTC tree. It keeps no separate public surface. `dtls_connection.zig` composes its own flights and reuses only leaf primitives (`tls12_prf`, certificate plus ECDSA signing, P-256 ECDHE). It cannot reuse `tls12_connection.zig`, because that one hashes TLS-framed bytes while RFC 6347 section 4.2.6 needs the transcript taken over DTLS 12-byte headers as-if-unfragmented, excluding the first ClientHello and the HelloVerifyRequest. That mismatch is invisible until a real peer rejects the Finished message.
- **ICE-lite, not a full ICE agent.** A server is not behind a NAT it has to discover its way out of. It has one candidate, it never gathers, it never nominates, and it answers 487 for every role tiebreaker value because it has no role to switch to (RFC 8445 section 6.1.1). That removes candidate gathering, pair state, and trickle as a mechanism from the engine entirely.
- **zix is always the DTLS server.** The answer is always `a=setup:passive`. That single value fixes the SRTP key direction (`client_write_*` opens what arrives, `server_write_*` seals what leaves) and fixes data channels to odd stream identifiers (RFC 8832 section 6).
- **Three dispatch models, matching every other engine.** `.ASYNC` runs one worker on every platform, `.EPOLL` and `.URING` run one SO_REUSEPORT worker per core and are rejected off Linux with `error.DispatchModelUnsupported`. The loop body is shared by all three in `dispatch/worker.zig`, because the order a peer's outbound datagrams drain in is a correctness property and not a per-model detail. Copying that order per model would have reopened a defect the engine already shipped once. Outbound goes through `datagram.SendBatch`, which is `sendmmsg` on Linux and a portable `std.Io` sink elsewhere.
- **The wait is deadline-derived, not a fixed maintenance interval.** `Worker.waitMs` is the soonest peer deadline capped by `tick_interval_ms`, so the loop never parks past a retransmit and never spins when nothing is due. That is the whole reason this engine has its own loop instead of borrowing one.
- **Media is forwarded, never decoded.** With `carry_media` on, the engine opens a peer's SRTP packet, rewrites the RTP header, and seals it again under each receiver's key. It does not parse a codec, does not hold a frame, and has no opinion about what the payload is. Re-protection is unavoidable rather than chosen: no two peers share an SRTP key, so a packet cannot be passed along as it arrived.
- **RTCP is answered, never forwarded.** A report names streams by their pre-rewrite identifiers, so relaying one describes a stream the far side never saw. A receiver's picture-loss indication is read, mapped back through its routes to the source, and rebuilt for the sender.

Layer map, one concern per file, 84 files under `src/udp/webrtc/` plus 9 `dtls_*` files in `src/tls/`:

| Directory | Owns |
| :- | :- |
| `stun/` | the RFC 8489 message container and the section 6.3.1 binding rules |
| `ice/` | candidate, credentials, the four ICE attributes, the ice-lite responder |
| `sctp/` | 20 files: wire, control, data, reliability, reconfig, then the association driver |
| `datachannel/` | payload types, DCEP, stream identifier parity, the channel registry, stream reset |
| `sdp/` | 18 files: the line and attribute codecs up to reading an offer and writing an answer |
| `media/` | RTP, RTCP, SRTP, SRTCP, and the forwarding path (routes, stream sets, per-peer state) |
| `dispatch/` | `worker.zig` holds the loop, one file per model, `common.zig` is substrate only |

**Consequences:**

- `zix.Webrtc.Server` answers a real browser under every dispatch model. Eight examples occupy ports 9081 to 9088, four of which need a browser to drive.
- `max_peers` is counted per worker, so a server with N workers holds up to N times `max_peers`. The config doc says so.
- One SRTP session per stream identifier, not per peer. The rollover counter and the replay list are per-SSRC, so audio and video sharing one session read each other's sequence numbers as gaps or wraps and reject real packets.
- A fan-out opens a packet once and seals it once per receiver. Opening it twice is a replay of an index the source stream already accepted, so the relay had to split into `open` plus `reseal`.
- The engine asks a source for a keyframe when a new route is admitted on any receiver. Nothing in a browser asks on a watcher's behalf, so without it a watcher joining mid-stream stays grey indefinitely.
- `accept_any_peer_ice_ufrag` exists because a browser draws a fresh ICE ufrag for every peer connection. With one server-wide credential set, comparing the ufrag proved nothing the password did not, so the flag makes the password the only gate. It is off by default: a server that names one peer should keep refusing everybody else.
- The reach of `ctx.broadcast` is one worker. That is the whole room under `.ASYNC` and this core's share under `.EPOLL` or `.URING`, so the room examples pin `.ASYNC` and say why in their own header.
- `zix.Udp` is untouched. Nothing here was folded into it, and no raw UDP server pays for the timer wheel.
- Browser runs are not a CI check and must not become one. The CI exit gate is `tests/integration/webrtc/exchange_test.zig`, a whole session driven in memory in 435ms with no port and no sleep.

**Not built, and each for a stated reason:** TURN relaying and a full ICE agent (everything so far was one machine on one LAN with no NAT, which says nothing about what they would need), DTLS 1.3 (Firefox 153 and OpenSSL 3.6 both complete on 1.2), periodic sender and receiver reports on a timer, NACK answering (advertised in SDP, no packet history is kept), payload type remapping, simulcast and layer switching, `a=msid`, `a=extmap`, `a=ssrc`, RFC 8260 message interleaving, and a room that spans cores.

**Evidence, and why self-tests were not enough:** five defects reached a browser and nothing self-tested could have caught any of them, because in each case zix's own client agreed with zix's own server.

| Defect | Why every self-test passed |
| :- | :- |
| HelloVerifyRequest and ServerHello both sent as epoch 0 record sequence 0 | zix's DTLS client only runs a replay window on established epoch 1 records |
| a fragmented ClientHello never reassembled | OpenSSL's hello is 206 bytes and fits one record, a browser's is about 1500 and never does |
| a full-range u64 SDP session id | RFC 8829 section 5.2.1 wants one that fits a signed 64-bit integer, and zix's own reader did not care |
| a candidate published as 127.0.0.1 | Firefox gathers no loopback candidate and never pairs with one |
| no `a=candidate` line in a carried media section | the answer parses and reads back cleanly through zix's own offer reader |

The last one is the sharpest. A browser reads remote candidates off the BUNDLE-tagged section, which is whichever section the offer put first, and with media offered that is audio or video, not the data channel section that did carry a candidate. The peer had credentials to sign checks with and no address to send them to, so ICE failed with zero datagrams ever leaving the browser.

**How a browser was driven without a display:** the page reassigns its own `log` to also `fetch('http://' + location.hostname + ':9099/' + encodeURIComponent(line), {mode: 'no-cors'})` against a small threaded `http.server`, then Firefox runs headless with `media.navigator.streams.fake=true` and `media.navigator.permission.disabled=true`. That is what makes a headless browser report back. For DTLS alone, `openssl s_client -dtls1_2 -connect <ip>:<port> -state` reaches the DTLS server directly, because the demux routes DTLS with no ICE gate in front of it.

**Guardrails held:** `zig fmt` clean, `test-all` 2913 tests over 167 steps on both `zig-0.16` and `zig-0.17` with a fresh cache directory, `test-runner-all` green across all 55 protocols, and all 7 CI legs green on the branch. Every ladder phase exit was met by an independent implementation rather than by inspection: OpenSSL for the DTLS handshake, a hand-built STUN binding request for ICE, and real browsers for the data channel, file transfer, mesh call and forwarding examples. The forwarding exit was one sending Firefox and two watching Firefox, both watchers decoding 640x480 with nothing sent back to the sender.

---

## ADR-068: one answer per failed handler, on every engine

**Status:** Accepted

**Context:** ADR-063 set the handler-error wire policy for the whole family, and two parts of it turned out to be wrong once they were read against the wire rather than against the source.

The first is that "the handler wrote nothing" was decided by `Response.sent`, and only the `Response` builder sets that flag. Every engine that also exposes fd writers (`Http1`, `Http2`) therefore read a handler that answered with `sendSimpleFD` or `sendResponseFD` as never having answered at all. A handler that answered and then returned an error got its answer followed by a second one. On the wire that is `HTTP/1.1 200 OK ... okHTTP/1.1 500 Internal Server Error`, one connection, one request, two responses. On HTTP/2 it is a second HEADERS frame on a stream the peer already saw closed.

The second is that `Grpc` and `Fix` were left answering nothing at all, recorded as "current wire behavior kept". For a request-response protocol that is not a neutral default: a gRPC caller waits on a stream that will never carry a status, and a FIX counterparty waits on a message that will never arrive. Both engines also swallowed their own send failures, so a handler had nothing to `try` and nothing to `catch`, and could not tell a delivered message from one that never left.

**Decision:** One rule, all six engines. A handler that RETURNS an error is answered exactly once.

- Answered nothing: the engine sends the protocol default. `500 Internal Server Error` on `Http`, `Http1`, `Http2` and `Http3`, `grpc-status 13` (INTERNAL) on `Grpc`, Reject (`35=3`) carrying the failed message's RefSeqNum on `Fix`.
- Already answered: the engine sends nothing more, and a status the handler chose itself is never overwritten.
- "Answered" counts both answer styles. `Http1` and `Http2` mark it in their fd writers as well as their `Response` builder, so the check is one truthful answer rather than two half-answers.
- An error the handler catches itself never reaches the engine. `catch {}` is a decision, not an oversight, and the handler owns what the caller gets.
- `Grpc` and `Fix` sends return an error union rather than `void`, which is what makes that choice available to a handler at all. Breaking change for both.

**Rationale:** A protocol answer is not optional. Every one of these protocols has a caller waiting on exactly one reply, so an engine that answers zero times and an engine that answers twice are the same class of defect, and both were present. Deciding it in one place per engine, off one flag that both answer styles set, is what keeps the two failure modes from trading places later.

The alternative considered for the fd half was leaving fd handlers to fend for themselves and documenting the double answer. Rejected: the fd writers are the documented escape hatch on those engines (ADR-063 keeps them public on purpose), so a defect that only appears when the escape hatch is used is a defect in the escape hatch.

The alternative considered for `Grpc` and `Fix` was keeping them silent and letting handlers answer, which is what ADR-063 chose. Rejected on the same ground: a handler that fails before it can answer is exactly the case where the engine has to.

**Guardrails held:** `zig fmt` clean, `test-all` green on both `zig-0.16` and `zig-0.17`, examples building on both. Every engine has a test for the default on `try`, for the already-answered case, and for the error a handler swallows itself. Every guard was mutation-tested: removing the fd check reproduces `expected 1, found 2` status lines on `Http1` and the same count of HEADERS frames on `Http2`, removing the already-answered guards reproduces the Reject glued onto an answer and the twice-closed gRPC call, and removing the `Fix` fallback entirely reproduces the silent failure.

## ADR-069: WebTransport over HTTP/3 as a feature of zix.Http3

**Status:** Accepted

**Context:** A browser cannot open a raw QUIC connection, and WebTransport is the only transport it offers that gives an application reliable per-stream delivery and an unreliable datagram on the same connection at the same time. zix already terminates QUIC, TLS 1.3, HTTP/3, and QPACK in `zix.Http3`, so the binding belongs on top of an engine that exists rather than in a second server that duplicates it. Two revisions are live on the wire: draft-ietf-webtrans-http3-16 renamed the upgrade token and the support setting, and every shipping browser and aioquic still send the draft-07 spellings, so an engine that speaks one revision serves half the clients that exist.

Three facts about the protocol decided the shape of the implementation:

1. **A WebTransport data stream is a QUIC stream whose first bytes are not HTTP/3 frames**, and a session is identified by its CONNECT stream id. So the binding runs its own pass over a decrypted payload before the HTTP request pass, and the streams it recognizes are claimed so they are never answered as requests.
2. **The receive path runs on the worker that owns the connection, one datagram at a time.** Sessions and streams are per-connection state on a single thread, so an application callback never needs a lock.
3. **Nothing on the path may allocate per packet.** A peer decides how many streams and datagrams to send, so the resources those need have to exist before the peer asks for them.

**Decision:** WebTransport over HTTP/3 is a feature of `zix.Http3`, configured on the HTTP/3 server, speaking both the draft-16 and the deployed draft-07 dialects, implemented over a worker-owned fixed-capacity pool. The capsule-based WebTransport over HTTP/2 variant is deliberately out of scope for this pass.

- **Configured, not a second server.** `Http3ServerConfig.webtransport` carries `zix.Webtransport.Config`. Turning it on advertises the settings and transport parameters a client needs, accepts extended CONNECT requests, and opens the pool. Leaving it off advertises exactly the empty SETTINGS and the transport parameters the engine sent before the feature existed, and allocates nothing.
- **Both dialects, one SETTINGS frame.** The server writes `SETTINGS_WT_ENABLED` (0x2c7cf000), the three draft-16 initial session limits (0x2b64 / 0x2b65 / 0x2b61), `SETTINGS_ENABLE_WEBTRANSPORT` (0x2b603742), and `SETTINGS_WEBTRANSPORT_MAX_SESSIONS` (0xc671706a) together. A peer ignores the settings it does not know (RFC 9114 7.2.4.1), and the CONNECT `:protocol` token picks the dialect the session speaks. `legacy_dialect = false` narrows the accepted tokens for a deployment whose clients are all known.
- **A worker-owned fixed-capacity pool.** Sessions, data streams with their send buffers, and the buffers for streams that arrive before their session are allocated once per worker and recycled. Acquisition returns null instead of growing, and the caller decides what a full pool means (a refused stream, a dropped datagram, a refused session). The receive path allocates nothing, and a worker's WebTransport memory cost is `streams * stream_send_bytes` plus the orphan buffers, independent of the connection count. `capacityError` reports the config field that outgrows a compile-time ceiling rather than truncating the feature silently.
- **The engine owns the framing, the application owns the policy.** The library answers what the drafts make it answer (a CONNECT that arrives before the client's SETTINGS, a session without datagrams negotiated, a stream for a session that does not exist, a session flow control violation, the session ceiling, a full pool) and hands the rest (path, authority, token, and the Origin field) to `on_session`, which accepts with null or refuses with an HTTP status. The engine deliberately does not invent an origin policy, because only the application knows which origins it serves.
- **Out of scope for this pass:** the capsule-based WebTransport over HTTP/2 variant, 0-RTT sessions, keying-material exporters, priority signalling, and a GOAWAY-initiated session drain. Each is recorded with its reason in the HLD's Not Yet Wired table.

**Rationale:** The binding is a wire protocol over an engine that already exists, so the only defensible home for it is that engine. A separate `zix.Webtransport` server would have to duplicate the QUIC handshake, the TLS context, the settings exchange, and the dispatch loop, and would lose the property that makes the binding worth having in the first place: a session and an ordinary request sharing one connection, one certificate, and one congestion controller. Everything a browser needs to reach it (ALPN `h3`, the extended CONNECT, the datagram framing) is already in `zix.Http3` or is one frame away from it.

The pool is the second half of the decision. WebTransport turns "how much state does one connection cost" from something the engine chooses into something the peer chooses, since a client decides how many sessions, streams, and datagrams to send. A pool that refuses is the only shape that keeps that choice from becoming an allocation: it makes the ceiling a number the server picked before the peer connected, and it makes the refusal a protocol answer (`WT_BUFFERED_STREAM_REJECTED`, a dropped datagram, 429 or 503 on the CONNECT) rather than a failure the engine has to survive.

Alternatives considered:

- **A separate WebTransport server with its own socket.** Rejected: the binding is defined as a use of HTTP/3, so a second server would duplicate the handshake, the settings exchange, and the request path, and a session could not share a connection with ordinary requests.
- **Session limits modelled per connection instead of per session.** Rejected: the drafts put the flow control limits on the session, and a connection-wide limit would cap N sessions at one session's allowance, which is a different protocol.
- **Buffering pre-session streams without a bound.** Rejected: a peer could park streams on a connection whose session will never be established. `WT_BUFFERED_STREAM_REJECTED` exists for exactly that peer.
- **Speaking only the current revision.** Rejected: every shipping browser and aioquic send the deployed token, so a draft-16-only server reaches no real client today. The two dialects differ in the token, the support setting, the flow control capsules, and the reset frame, and the engine gates each of those on the session's dialect.

**Consequences:**

- `Http3ServerConfig` gains one field and every existing config keeps working unchanged: the default is off, and off costs no allocation, no settings entry, and no parse.
- Every connection carries a fixed inline `wt` state (a table of 8 session pointers, a table of 32 stream pointers, the client's decoded SETTINGS, the two transport-parameter values, an 8-entry table classifying client unidirectional streams, and a 256-byte control-stream buffer). Raising `connection_session_cap` costs that many pointers in every eagerly allocated connection.
- The HTTP/3 serve path gained a receive pass that runs before the request pass and a pump that runs after the response pump. A stream either one claims is never answered as an HTTP request, which is what lets a data stream and a request coexist on one connection.
- Two dialects mean two wire behaviours to keep honest: a draft-07 session has no session-level flow control and resets with a plain `RESET_STREAM`, so every rule that exists only in draft-16 is gated on the session's dialect rather than assumed.
- The API is a set of views over engine state: a `Session`, a `Stream`, and the request fields are valid for the callback that produced them, so an application that keeps bytes or a path copies them.
- The interop surface is the example plus the runner: `examples/tls/http3_webtransport.zig` on port 9089 shows the whole surface with no wire vocabulary in it, and `zig build test-runner-webtransport` asserts the four observable results of one session end to end.

**Guardrails held:** the binding carries its proofs in-file rather than in a claim. 52 unit tests across the seven modules under `src/udp/http3/webtransport/`, every one named `zix webtransport: <claim>`, reachable through `std.testing.refAllDecls` from `src/lib.zig` under `zig build unit-test`. Three registered test tiers cover the surface above them, all named `zix webtransport: <claim>`: 5 integration tests in `tests/integration/http3/webtransport_test.zig` (the request decode that recognizes a session request, the SETTINGS codec a client reads before it sends one, and the transport parameters the feature is built on, with the bytes built by hand from the public primitives a peer uses), 7 behaviour tests in `tests/behaviour/http3/webtransport_test.zig` (the config surface, the pool sizing, the dialect a token selects, the stream write window and FIN rule, the session data limit, and the datagram framing and bound), and 8 edge tests in `tests/edge/http3/webtransport_test.zig` (the capsule reader at and past its limit, an application error at the ends of its range, a full sent-range list, a one-slot pool, and a session that has already ended). All three files are registered in `zix-build-tests.zig`, so `zig build integration-test`, `behaviour-test`, and `edge-test` reach them. The end-to-end proof is `zig build test-runner-webtransport`, which spawns the example on port 9089 and drives one session with the hand-rolled HTTP/3 client: the extended CONNECT answered 2xx, the banner on the unidirectional stream the server opens, a bidirectional data-stream echo, and a datagram echo, each compared byte for byte rather than by length. The same server is in the `test-runner-all` server list. Every codepoint the code uses is pinned against its draft in-file, so a transcription error fails the suite rather than reaching a peer.

---

###### end of adr
