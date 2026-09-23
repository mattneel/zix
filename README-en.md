# README

<h1 align="center">
    <b><i>ZIX</i></b>
</h1>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <b><i>Zero sIX; 06;</i></b>
</p>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>A high-performance network backend library & engine written in Zig.</i>
</p>

<div align="center">
    <img src="zix-logo.svg" alt="zix-logo" style="display: block; margin: auto;" align="center" width="512px">
</div>

<hr>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Where the wire meets the will.</i>
</p>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Every byte owned, every thread deliberate, every route explicit.</i>
</p>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>No hidden cost. Just clean-metal and honest code - predictable by principle</i>
</p>

<hr>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>You are the thinker. Tinker.. Assembler... The builder, Not just as user/coder....</i>
</p>

<br>

# Table of Contents

- [Documentation](./README-en.md#documentation)
- [Important Notes](./README-en.md#important-notes)
- [Important Contribution Notes](./README-en.md#important-contribution-notes)
- [Repositories](./README-en.md#repositories)
- [Reason & Motivation](./README-en.md#a-reason-a-motivation)
- [Key Features](./README-en.md#key-features)
- [Server Config Consistency](./README-en.md#server-config-consistency)
- [Memory Model](./README-en.md#memory-model)
- [Requirements](./README-en.md#requirements)
- [Getting Started](./README-en.md#getting-started)
- [Build](./README-en.md#build)
- [Testing](./README-en.md#testing)
- [Examples](./README-en.md#examples)
    - [HTTP/1](./README-en.md#http1)
    - [Minimal](./README-en.md#minimal-examples)
    - [Routing](./README-en.md#routing)
    - [Handler Errors](./README-en.md#handler-errors)
    - [Concurrency Model](./README-en.md#concurrency-model)
    - [Timeouts](./README-en.md#timeouts)
    - [Middleware](./README-en.md#middleware)
    - [WebSocket](./README-en.md#websocket)
    - [SSE](./README-en.md#sse-server-sent-events)
    - [HTTP Client](./README-en.md#http-client)
    - [Static Files & Upload](./README-en.md#static-files--upload)
    - [Response Header Capacity](./README-en.md#response-header-cap-headersize)
    - [Request Header Capacity](./README-en.md#request-header-cap-requestheadersize)
    - [Response Cache Awareness](./README-en.md#response-cache-awareness-response_cache)
        - [When it pays off](./README-en.md#when-it-pays-off)
        - [Rules and conditions](./README-en.md#rules-and-conditions)
    - [Process Queue Awareness](./README-en.md#process-queue-awareness-process_queue_len)
        - [When it engages](./README-en.md#when-it-engages)
        - [Rules and sizing](./README-en.md#rules-and-sizing)
    - [HTTP/2](./README-en.md#http2)
        - [gRPC h2c](./README-en.md#grpc-h2c)
    - [TLS (https / h2)](./README-en.md#tls-https--h2)
    - [Raw TCP](./README-en.md#raw-tcp)
    - [FIX 4.x](./README-en.md#fix-4x)
    - [UDS (Unix Domain Sockets)](./README-en.md#uds-unix-domain-sockets)
    - [Channel](./README-en.md#channel)
    - [UDP](./README-en.md#udp)
    - [HTTP/3](./README-en.md#http3)
    - [WebTransport](./README-en.md#webtransport)
    - [WebRTC](./README-en.md#webrtc)
    - [Logger](./README-en.md#logger)
    - [JSON (jzon)](./README-en.md#json-jzon)
- [Drivers](./README-en.md#drivers)
- [zixer](./README-en.md#zixer)
- [AI Policies](./README-en.md#ai-policies)

<br>

## Documentation

| Document | Description |
| :- | :- |
| [`docs/hld-http-en.md`](docs/hld-http-en.md) | HTTP: goals, runtime model, API, router, WebSocket, SSE, memory model |
| [`docs/hld-http1-en.md`](docs/hld-http1-en.md) | HTTP/1: lean engine goals, dispatch models, handler model, router, WebSocket, memory model |
| [`docs/hld-http2-en.md`](docs/hld-http2-en.md) | HTTP/2: goals, dispatch models, mux state machine, HPACK, flow control, TLS, memory model |
| [`docs/hld-tcp-en.md`](docs/hld-tcp-en.md) | TCP raw stream: goals, API, frame format, dispatch models |
| [`docs/hld-udp-en.md`](docs/hld-udp-en.md) | UDP: goals, runtime model, API, packet model, endianness, disconnect |
| [`docs/hld-uds-en.md`](docs/hld-uds-en.md) | UDS: goals, API, frame format, server/client lifecycle |
| [`docs/hld-channel-en.md`](docs/hld-channel-en.md) | Channel: goals, model, API, concurrency requirement, examples |
| [`docs/hld-fix-en.md`](docs/hld-fix-en.md) | FIX 4.x: goals, protocol overview, session layer, dispatch models, config |
| [`docs/hld-grpc-en.md`](docs/hld-grpc-en.md) | gRPC h2c: goals, architecture, API, all 4 RPC types, codec, dispatch models |
| [`docs/hld-proxy-en.md`](docs/hld-proxy-en.md) | Reverse proxy (nginx, haproxy) for zix.Http1, zix.Http, zix.Grpc |
| [`docs/hld-logger-en.md`](docs/hld-logger-en.md) | Logger: goals, API, log methods, formats, file rotation, protocol wiring |
| [`docs/hld-tls-en.md`](docs/hld-tls-en.md) | TLS: goals, version policy, Tls.Context, handshake flow, engine integration, client |
| [`docs/hld-http3-en.md`](docs/hld-http3-en.md) | HTTP/3 (QUIC): goals, runtime model, API, router, dispatch models, handshake, QPACK, memory model |
| [`docs/hld-webtransport-en.md`](docs/hld-webtransport-en.md) | WebTransport over HTTP/3: goals, the two dialects, session negotiation, API, dispatch, flow control, memory model, security notes |
| [`docs/hld-webrtc-en.md`](docs/hld-webrtc-en.md) | WebRTC: goals, runtime model, API, ICE-lite, data channels, media forwarding, dispatch models, memory model |
| [`docs/lld-http-en.md`](docs/lld-http-en.md) | HTTP: internal data structures and algorithms |
| [`docs/lld-http1-en.md`](docs/lld-http1-en.md) | HTTP/1: internal parsing, write helpers, router, EPOLL engine, WebSocket codec |
| [`docs/lld-http2-en.md`](docs/lld-http2-en.md) | HTTP/2: mux state machine, per-worker stream-slot pool, HPACK cache, frame loop, flow control, dispatch |
| [`docs/lld-grpc-en.md`](docs/lld-grpc-en.md) | gRPC: frame build/send helpers, mux dispatch, per-worker stream-slot pool, server-streaming coalescing, TLS serve paths |
| [`docs/lld-tcp-en.md`](docs/lld-tcp-en.md) | TCP: internal data structures and algorithms |
| [`docs/lld-udp-en.md`](docs/lld-udp-en.md) | UDP: internal data structures and algorithms |
| [`docs/lld-uds-en.md`](docs/lld-uds-en.md) | UDS: internal server/client structure and frame handling |
| [`docs/lld-fix-en.md`](docs/lld-fix-en.md) | FIX: internal data structures and serveConn algorithm |
| [`docs/lld-channel-en.md`](docs/lld-channel-en.md) | Channel: ring buffer internals, locking, send/recv algorithms |
| [`docs/lld-logger-en.md`](docs/lld-logger-en.md) | Logger: internal write buffer, spinlock, rotation algorithm |
| [`docs/lld-tls-en.md`](docs/lld-tls-en.md) | TLS: wire / handshake / key-schedule / record internals, Tls.Context validate, serve paths |
| [`docs/lld-http3-en.md`](docs/lld-http3-en.md) | HTTP/3 (QUIC): per-layer internals (crypto, packet, frame, flow, recovery, QPACK, connection, demux, dispatch) |
| [`docs/lld-webtransport-en.md`](docs/lld-webtransport-en.md) | WebTransport: per-file internals (draft codepoints, capsules, datagrams, stream headers, session and pool), the engine hooks, the limits |
| [`docs/lld-webrtc-en.md`](docs/lld-webrtc-en.md) | WebRTC: per-layer internals (demux, STUN, ICE, DTLS, SCTP, data channels, SDP, media, dispatch) |
| [`docs/zix-deploy-en.md`](docs/zix-deploy-en.md) | Deployment: build a Docker image (zig fetch or vendor) and configure the TLS context for Ed25519 / ECDSA P-256 / RSA |
| [`docs/zix-config-en.md`](docs/zix-config-en.md) | Config reference: every config field with its default, effect, and tuning trade-offs (server engines plus the TLS context) |
| [`docs/concurrency-en.md`](docs/concurrency-en.md) | Dispatch models: ASYNC, EPOLL, URING. Thread counts, protocol applicability. |
| [`docs/design-considerations-en.md`](docs/design-considerations-en.md) | Design considerations, design patterns, and naming conventions |
| [`docs/coding-guideline-en.md`](docs/coding-guideline-en.md) | Coding style: source layout, naming, file anatomy, doc comments, config, tests, prose rules |
| [`docs/systems-thinking-en.md`](docs/systems-thinking-en.md) | Systems thinking: explicit cost, bounded allocation, kernel involvement, measurement tooling, the two-sided gate |
| [`docs/adr-en.md`](docs/adr-en.md) | Architecture Decision Records |
| [`docs/headers-en.md`](docs/headers-en.md) | Response header cap: tiers, security, error handling |
| [`docs/tests-en.md`](docs/tests-en.md) | Test tiers (unit / integration / behaviour / edge) and how to run |
<!-- | [`rnd/rfc/README.md`](rnd/rfc/README.md) | RFC-based MUST / MUST NOT conformance checklists for raw HTTP/1.1, HTTP/2, HTTP/3, and TLS 1.3 | -->

Driver documentation (each README fans out to its own hld, lld, and config docs):

| Document | Description |
| :- | :- |
| [`docs/driver/postgrez/README-en.md`](docs/driver/postgrez/README-en.md) | PostgreSQL driver: quickstart, URL and config init, prepared statements, pool, executor |
| [`docs/driver/rediz/README-en.md`](docs/driver/rediz/README-en.md) | Redis driver: quickstart, URL and config init, pipelining, deferred write-behind, pool |
| [`docs/driver/prometheuz/README-en.md`](docs/driver/prometheuz/README-en.md) | Prometheus driver: scrape, remote write, PromQL query |

<br>

## Important Notes

Zix dispatch model for IOCP and KQUEUE not supported.

__*Platform Development Status:*__ <br>
<img src="https://img.shields.io/badge/x86__64-Linux-brightgreen">
<img src="https://img.shields.io/badge/aarch64-Linux-brightgreen">
<img src="https://img.shields.io/badge/x86__64-Windows-yellow">
<img src="https://img.shields.io/badge/aarch64-MacOS-yellow">
<img src="https://img.shields.io/badge/x86__64-FreeBSD-yellow">
<img src="https://img.shields.io/badge/x86__64-NetBSD-yellow">
<img src="https://img.shields.io/badge/x86__64-OpenBSD-yellow">

> green: validated on native hardware. <br>
> yellow: cross-build verified (module, examples, test suites, and runners compile, EPOLL / URING are rejected at run() with error.ZixDispatchModelUnsupported, so those targets use ASYNC).

__*Maintained Platforms:*__
- x86_64-linux:
    - Maintainers:
        - @prothegee
    ---
- aarch64-linux:
    - Maintainers:
        - @prothegee
    ---
- x86_64-windows:
    - Looking for contributor & maintaner.
    ---
- aarch64-macos:
    - Looking for contributor & maintaner.
    ---
- x86_64-freebsd:
    - Looking for contributor & maintaner.
    ---
- x86_64-netbsd:
    - Looking for contributor & maintaner.
    ---
- x86_64-openbsd:
    - Looking for contributor & maintaner.

<br>

## Important Contribution Notes

- Helping Zig, helping Zix.
- Zig should be the ecosystem.
- Single file, single responsibility.
- Always use and push Zig and their std.
- Any significant change/s required RnD/PoC.
- Cover for the un-cover test/s is good contribution.
- Narrowing down the system thinking then be explicit.
- A "nice to have" and "maybe we need this" is tertiary.
- Always fix from our side first rather than Zig feature/s side.
- What can be control/adjust to the caller/user, serve it to them when possible.
- If bias/ambigue, try to discuss it. At least involved with other 1-2 entities.
- Don't use abstraction on specific engine or specific intent, avoid it if you must.
- Linux x86_64/aarch64 raw-syscall fast path is guarded, any change there can harm the implementation.
- You and your people (Junior/Mid/Senior) use another language beside english, you can contribute that.

<br>

### Contribution Extra Notes

- [Milestones.](https://codeberg.org/prothegee/zix/milestones)

- [Open an issue.](https://codeberg.org/prothegee/zix/issues/new)

- [Coding Guideline.](docs/coding-guideline-en.md)

- [System Thinking Guideline.](docs/systems-thinking-en.md)

- [Announcment & Breaking Changes.](https://codeberg.org/prothegee/zix/issues/238)

<br>

## Repositories

- [Codeberg as Main](https://codeberg.org/prothegee/zix)
- [Github as Mirror #1](https://github.com/prothegee/zix)

<br>

## A Reason.. A Motivation...

<details close>
<summary>Frame of Mind:</summary>

```
The way we think, is how system start.
A time to read and think from existing lines,
made "us" re-think, arguing, and approaching for the flow of the program.

When "our" next generation doesn't want to learn the past and present. What will happen?
If they don't want to use/learn/be eager about the language and the build system, they'll ..?

To be modern with less hassle, "magic" should less or more?

Zig (also another programming language) could complement existing program
and able to create a good program, but when critical-performance our options is less/hard.

My work mostly 80% backend and 20% frontend.
So network/communication system is essential in my end.
From monolith, micro-service, and modular micro-service.

At early Zig (before 0.16.x), I enjoyed the language.
Zig is flexible, but "variant of colors" made me go back to Go & C++ again.
So in mid 2025 the plan is only idea and some architectural design.

So when Zig 0.16.x release, and in 2026 early March. I started the march.
Now I can regain transparency, more control, and more explicit in approach.
```

<!--
Why not rust:
- Too many "just use tokio/smol" made me think again.
- My code in rust as professional is still 70% sync, less async.
- Rust in my case to complement existing system, QR & Barcode reader/writer replacing C++.
-->

</details>

<br>

<details open>

<summary>Principles for the motivations:</summary>

__*1. Explicit Over Implicit.*__

__*2. Modular & Maintanable.*__

__*3. Performance-First Architecture.*__

__*4. Practical Features, Ready to Use.*__

__*5. Modern Efficient Concurrency Model.*__

__*6. Predictable, Transparent Memory Management.*__

> We valued clarity, control, and performance.

</details>

<br>

## Key Features

__*0. Zero dependencies:*__

Only the Zig standard library. No third-party packages (an empty `build.zig.zon` dependency
set), no C libraries, and no libc linking: TLS 1.3 / 1.2 runs pure-Zig on `std.crypto` (no
OpenSSL), gzip / deflate on `std.compress.flate` plus an in-tree fast gzip encoder for small
dynamic bodies, and brotli, QUIC, HPACK, and QPACK are authored in-tree from their RFCs.

> One `zig build` compiles the whole stack from source with nothing to vendor, pin, or keep
patched, so the supply chain is the Zig toolchain plus this repository.

<br>

__*1. Full protocol stack under one roof:*__

Tcp (raw), Udp, Uds (Unix domain sockets), Http (HTTP/1.1), Http1 (hot-path-optimized
variant), Http2 (h2c), Http3 (HTTP/3 over QUIC, plus WebTransport over HTTP/3), Webrtc (data channels
and media), Grpc (gRPC over h2c), Fix (FIX 4.x), plus Channel and Logger.

> One coherent memory/threading model across monolith, micro-service, and
modular-micro-service backends, instead of stitching together separate libraries with
different conventions.

<br>

__*2. Client libraries across the stack:*__

Every engine ships its matching client: `zix.Http.Client`, the gRPC client, and raw `zix.Tcp`, `zix.Udp`, `zix.Uds`, and `zix.Fix` clients, plus dedicated SSE (`sse_client`) and WebSocket (`ws_client`) clients.

> Call and test your own services with the same library that serves them, instead of vendoring a separate client per protocol.

<br>

__*3. Three selectable dispatch models:*__

- ASYNC (single accept thread, io.async() per conn): lowest latency at moderate load, and the only model available on every platform.
- EPOLL (shared-nothing: each worker owns a SO_REUSEPORT listener + epoll instance, level-triggered, no shared queue): Linux-only, best for high connection counts.
- URING (shared-nothing io_uring: same thread-per-core topology as EPOLL, but completion-based so most syscall transitions are batched away): Linux-only.

> Concurrency strategy is a deliberate config choice, not a implementation default. Http1, Http, Grpc, Fix, and Http2 implement all three natively on Linux. Off Linux, EPOLL and URING are rejected at run() rather than silently downgraded, so a caller never believes it got a model it did not.

<br>

__*4. Shared-nothing architecture:*__

Under `.EPOLL` and `.URING` each worker owns a private SO_REUSEPORT listener, its own event loop, connection slab, and response cache, with no shared queue, no cross-thread fd handoff, and no locking. State is partitioned by ownership, not guarded by mutexes.

> Scales by adding independent workers, one per core, so the hot path never contends and the response cache is lock-free by ownership.

<br>

__*5. Explicit, flat configuration:*__

No nested sub-configs: every field (e.g. dispatch_model, max_response_headers: .MINIMAL, workers) is top-level and explicit.

> Predictability by principle. You sees exactly what the server does without
chasing inherited defaults. Do not buried (1 or 3+ levels deep) config fields at the core public access, it's not a cemetery.

<br>

__*6. Hot-path-optimized HTTP/1 zix.Http1:*__

- Removed HeadParser, thread-local cached Date header, consolidated sendSimpleFD, serveConn(fd, handler, opts), configurable response-header capacity.

> Squeeze the common request path without sacrificing the explicit API.

<br>

__*7. Composable HTTP request handling:*__

A comptime router with path parameters (`matchParam`) shared by `zix.Http` and `zix.Http1`, comptime wrapper composition for middleware on both engines (a handler-in, handler-out function, see [Middleware](./README-en.md#middleware)), static file serving, multipart and file upload parsing (`multipart.Parser`), and HTTP range request parsing (`parseRange`) for partial content.

> Each piece is an explicit, opt-in part of the engine, with route matching resolved at compile time. You compose only what a request needs instead of inheriting a fixed pipeline.

<br>

__*8. WebSocket and SSE (both HTTP engines):*__

Engine-owned WebSocket on `zix.Http` and `zix.Http1` (RFC 6455, ping auto-ponged, close auto-echoed, broadcast fan-out, per-event write coalescing on the multiplexed models), available under every dispatch model, and Server-Sent Events with a matching SSE client.

> Long-lived, push-style connections are handled by the engine itself, not bolted on inside the handler.

<br>

__*9. Multiplexed gRPC (h2c):*__

Multiplexed async epoll with a resumable HTTP/2 state machine, comptime-cached HPACK reply blocks, big initial window, buffered reads, max_streams=128 to avoid REFUSED_STREAM bursts. Context timeouts (handler_timeout_ms, Route.timeout_ms, ctx.isExpired()).

> All four RPC types (unary, server streaming, client streaming, bidirectional)
multiplexed over one h2c connection without a thread per stream, with client
deadlines honored end-to-end. Internal services speak gRPC directly, no TLS
terminator or sidecar required.

<br>

__*10. FIX 4.x:*__

FixContext, a MsgType struct (47 constants), session-oriented routing, trading examples.

> Domain-specific financial messaging as a citizen of the engine, not bolted onto raw
TCP.

<br>

__*11. Channel (typed concurrency and IPC primitive):*__

A generic bounded `Channel(T)` with `send` / `recv` / `close` and drain-after-close semantics, usable for in-process fan-out, worker pools, and inter-process coordination.

> A small, typed building block for coordinating work, the same primitive whether the peers are threads or processes.

<br>

__*12. Protocol-aware logger:*__

Log types per protocol: conn (TCP), packet (UDP), frame (UDS), session (FIX), rpc (gRPC), access() is HTTP-only, Channel is system-only.

> The log vocabulary matches the actual unit of work on each protocol.

<br>

__*13. Response Cache Awareness:*__

Opt-in, per-worker response cache shared by `zix.Http1`, `zix.Http`, and `zix.Grpc`. A handler builds its response once, the engine stores it under a key derived from the request, and a later matching request replays the stored bytes with no rebuild and no re-serialization. Data oriented (a structure of arrays plus one flat payload slab), lock-free by ownership (one instance per owner thread, never shared), with a lazy on-access TTL. Active under every dispatch model: one cache per multiplexed worker, one per io pool thread under `.ASYNC`.

> A tool you reach for deliberately, not a hidden layer. It pays off above a ~4 KiB body (heavy ~32 KiB JSON measured +34% throughput) and is a zero-regression wash below that.

<br>

__*14. Process Queue Awareness:*__

Opt-in, per-worker submission-queue backpressure on `zix.Http1` and `zix.Http` under `.URING`. When a burst fills the io_uring submission queue, a recv or send re-arm that would otherwise drop the connection is parked on a per-worker FIFO ring (references only, fd plus generation, reject-newest) and retried on the next loop pass. `process_queue_len` sizes the ring, `0` (default) leaves it off. No effect under the other dispatch models.

> A reliability valve, not a throughput knob. Under an accept storm or connection churn it keeps overflow work in flight instead of dropping connections, and it is a measured no-op when the submission queue is not saturated.

<br>

__*15. Pure-Zig TLS (https, h2, wss):*__

TLS 1.3 with a TLS 1.2 floor, on `std.crypto`, no OpenSSL. Opt-in and additive: `zix.Http1` and `zix.Http` serve https/1.1, `zix.Http2` and `zix.Grpc` serve h2 over TLS (ALPN h2), and SSE and WebSocket run over TLS (wss) on the thread-per-connection path. Server certificates are ECDSA P-256, Ed25519, or RSA, configured by a user-owned `Tls.Context` (validated curves / ciphers, HSTS). A verifying native client (`zix.Tls.Client`) checks the chain and hostname.

> Encrypted transport is a config gate in front of the unchanged cleartext engines, not a separate server, so the same handler serves http and https.

<br>

__*16. HTTP/3 over QUIC, pure-Zig:*__

`zix.Http3` serves HTTP/3 (RFC 9114) over QUIC (RFC 9000 / 9001 / 9002), built from the RFCs on `std.crypto`: packet protection, the TLS 1.3 handshake over CRYPTO streams, loss recovery, QPACK, and per-core dispatch on the `zix.Udp` substrate. Same comptime `Router` and `Tls.Context` as the TCP engines. `zix.Webtransport` extends it with WebTransport over HTTP/3 (RFC 9220 / 9297 / 9221): sessions, reliable data streams, and unreliable datagrams multiplexed on the same connection, speaking draft-ietf-webtrans-http3-16 and the deployed draft-07 dialect browsers still send.

> The newest HTTP transport ships in-tree with no C QUIC library, sharing the router and TLS config already used for HTTP/1 and HTTP/2, and the browser-facing WebTransport binding rides the same connection, certificate, and congestion controller.

<br>

__*17. WebRTC peer, pure-Zig:*__

`zix.Webrtc` answers a browser over WebRTC: ICE-lite (RFC 8445) over STUN, DTLS 1.2 (RFC 6347), SCTP data channels (RFC 9260 / 8831 / 8832), SDP offer and answer, and optional SRTP media forwarding (RFC 3711 / 5764), all on one UDP port and all written from the RFCs on `std.crypto`. Media is forwarded, never decoded: there is no codec in the engine.

> The one transport a browser offers that gives unreliable delivery, per-channel ordering, and audio and video, with no C WebRTC library and the same config shape and dispatch models as every other engine.

<br>

__*18. Response compression (gzip / deflate / brotli):*__

`Accept-Encoding` negotiation on `zix.Http1` and `zix.Http`: gzip and deflate on `std.compress.flate` (a small dynamic body takes the in-tree fast gzip encoder instead), plus brotli from an in-tree encoder / decoder authored from RFC 7932 (`std` has no brotli). Opt-in per server, with a size floor, already-compressed media-type skip, and `Vary: Accept-Encoding`. HTTP/3 serves pre-compressed static bodies with `content-encoding`.

> Smaller responses over real networks with no compression dependency, off by default so the cleartext hot path is untouched until opted in.

<br>

__*19. Comptime routing, zero allocation:*__

One comptime `Router` shared by `zix.Http`, `zix.Http1`, `zix.Http2`, `zix.Grpc`, and `zix.Http3`: the route table is a comptime argument, so matching (`.EXACT` via a `StaticStringMap`, `.PARAM`, longest-prefix `.PREFIX`, query stripped first) does no runtime allocation.

> Routing cost is paid at compile time, so the request path adds no heap traffic and every engine matches paths the same way.

<br>

__*20. Bounded, work-proportional memory:*__

Explicit, capped allocation: an arena per connection or request, per-worker stream-slot pools on the multiplexed h2 / gRPC engines (resident stream memory tracks concurrent streams, not connections * max_streams, cutting 4096-connection footprint 6 to 12x), and a lock-free response cache. No hidden per-request heap growth.

> Memory tracks the work in flight, not the connection count, so footprint stays predictable from idle to saturation.

<br>

__*21. Hermetic conformance test harness:*__

Tests run with no external tools: a 69-protocol runner driving hand-rolled native clients (raw sockets, a native QUIC client, native TLS), plus RFC-vector unit tests for the wire codecs (TLS key schedule, HPACK / QPACK, QUIC packets), discovered through `std.testing.refAllDecls`.

> Correctness is checked against the RFCs in-tree with no curl / openssl / websocat in the loop, so the suite is reproducible anywhere the toolchain builds.

<br>

__*22. Static file serving with range support:*__

`public_dir` on all four HTTP engines serves unmatched routes as files before the 404 fallback, with a traversal-safe path check, and a multipart upload companion (`public_dir_upload`) on `zix.Http` and `zix.Http1`. Range requests (RFC 7233, 206 / 416) are served on `zix.Http`, `zix.Http1`, and `zix.Http2`, whole-file only on `zix.Http3`.

Set `public_dir_cache_ttl_ms` above 0 to keep a resolved file open with its response header prerendered, so a repeat request costs a hash lookup instead of an open plus a stat, and a precompressed `.br` or `.gz` sibling is picked up from disk once instead of probed per request. It is off by default, and on `zix.Http3` it is what enables static serving at all (see [Configuration](./docs/zix-config-en.md)).

> Static assets and uploads are served by the engine on the same port as the API, no separate file server.

<br>

__*23. Bilingual multi-documentation:*__

Every doc has it own variants.

> Support: en - English, id - Bahasa

<br>

## Server Config Consistency

Every server config shares one vocabulary: the same concept uses the same field name and type across `zix.Tcp`, `zix.Http1`, `zix.Http`, `zix.Grpc`, and `zix.Fix`. Moving a config between protocols is mechanical, not a relearn. These fields are common to all of them:

| Field | Type | Meaning |
| :- | :- | :- |
| `io` | `std.Io` | I/O backend, required, must outlive the server |
| `ip` | `[]const u8` | Bind address |
| `port` | `u16` | Bind port, must be non-zero |
| `dispatch_model` | `DispatchModel` | `.ASYNC`, `.EPOLL`, `.URING` (required, no default) |
| `kernel_backlog` | `u31` | TCP listen backlog |
| `workers` | `usize` | EPOLL / URING worker count, `0` selects cpu_count, ignored by `.ASYNC` |
| `logger` | `?*Logger` | Optional logger, caller-owned |

Buffer, socket, timeout, and cache fields keep the same names wherever a protocol has the feature:

| Field | Type | Present on |
| :- | :- | :- |
| `max_recv_buf` | `usize` | every server engine (per-frame cap, read buffer, or datagram slot per engine) |
| `large_body_rcvbuf` | `usize` | `zix.Http1`, `zix.Http` |
| `busy_poll_us` | `u32` | `zix.Http1`, `zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Udp` raw, `zix.Http3` |
| `reuseport_cbpf` | `bool` | every server engine except `zix.Uds` (`.EPOLL` / `.URING` listener or socket groups) |
| `conn_timeout_ms` | `u32` | `zix.Http`, `zix.Fix`, `zix.Udp` |
| `handler_timeout_ms` | `u32` | `zix.Http1`, `zix.Http`, `zix.Grpc`, `zix.Fix` |
| `response_cache` and the four `cache_*` fields | see [Response Cache Awareness](#response-cache-awareness-response_cache) | `zix.Http1`, `zix.Http`, `zix.Grpc` |
| `process_queue_len` | `usize` | `zix.Http1`, `zix.Http` (`.URING` submission-queue park ring, see [Process Queue Awareness](#process-queue-awareness-process_queue_len)) |
| `compress`, `compression_min_size`, `compression_max_out` | `bool` / `usize` / `usize` | `zix.Http1`, `zix.Http` |
| `webtransport` | `zix.Webtransport.Config` | `zix.Http3` (WebTransport over HTTP/3: sessions, streams, datagrams, see [WebTransport](#webtransport)) |

A few differences are by design, not drift:

- `zix.Http1` has no `conn_timeout_ms`: it runs no connection-registry timer thread (see the Timeouts note in the HTTP/1 LLD docs).
- `zix.Http2` and `zix.Grpc` use `max_recv_buf` as the per-connection read-buffer floor and size per-stream data with protocol fields (`max_body`, `max_frame_size`, `max_header_scratch`).
- Runtime response compression (`compress` plus the `compression_*` sizes, the engine compresses on the fly) lives on `zix.Http1` and `zix.Http`, which negotiate against Accept-Encoding and compress the body themselves. `zix.Http3` negotiates too but does not carry a runtime codec: a handler reads `req.accept_encoding` and sets `res.content_encoding` on an already-compressed body (serve a `.br` / `.gz` file), so there is no `compress` config on it. `zix.Grpc` uses its own per-message `grpc-encoding` compression instead, and the raw transports (`zix.Tcp`, `zix.Udp`, `zix.Uds`, `zix.Fix`) have no HTTP content negotiation.
- `zix.Udp` (datagram) carries `ip` / `port` / `logger` for the typed path, plus the raw-path knobs `dispatch_model` / `workers` / `reuse_address` / `recv_batch` / `send_batch` / `max_recv_buf` (used by `zix.Udp.Raw`). `zix.Uds` (local socket) carries `kernel_backlog` / `max_recv_buf` / `logger` plus its socket path. Each engine takes only the subset that applies.

For the full per-field reference (every config field with its default, what it affects, when to raise or lower it, and the trade-offs), see [`docs/zix-config-en.md`](./docs/zix-config-en.md).

<br>

## Memory Model

### HTTP

| Scope | Allocator | Lifetime |
| :- | :- | :- |
| Route table | zero heap cost | N/A |
| Read / write I/O buffers | `smp_allocator` | Connection |
| Per-request allocations (`ctx.allocator`) | Per-connection `ArenaAllocator`, reset each request | Request |

Handlers receive `ctx.allocator`, an arena reset between requests. Any allocation made inside a handler is automatically reclaimed at the end of the request without any `free` call.

Routes are comptime-baked into the server type on `zix.Http1`; on `zix.Http` the handler is a runtime `HandlerFn` field (ADR-063), built from a comptime `Router`. Either way, no allocator is needed for route storage.

### UDP

| Scope | Allocator | Lifetime |
| :- | :- | :- |
| Client record list | `config.allocator` (caller-owned) | Server process lifetime |
| Peer snapshot (broadcast) | `config.allocator` | Single packet dispatch |
| Receive buffer | Stack | Single receive loop iteration |

`config.allocator` must be a general-purpose allocator (e.g. `std.heap.smp_allocator`). `ArenaAllocator` is not suitable: the broadcast peer snapshot is allocated and freed per packet: `ArenaAllocator.free()` is a no-op, so snapshots accumulate unboundedly until the server stops. See [`docs/hld-udp-en.md`](docs/hld-udp-en.md) for the full explanation and PoC.

The raw path (`zix.Udp.Raw`,) allocates its recv / send batches and worker-thread array from `config.allocator` once at startup, not per packet, so the arena caveat does not bind there.

### HTTP/2 and gRPC

HTTP/2 and gRPC `.EPOLL` / `.URING` mux both pool stream slots per worker, so resident stream memory tracks concurrent streams rather than `max_streams` per connection. The thread-path model (`.ASYNC`) keeps a heap-allocated per-connection stream array (stack allocation of `max_streams` `Stream` structs would overflow the thread stack). Handlers receive the same `req`/`res`/`ctx` trio as every other engine (ADR-063): `ctx.allocator` is a per-request arena backed by a fixed stack buffer (no heap call), reset per request, not per connection.

### WebTransport over HTTP/3

`zix.Webtransport` is a feature of `zix.Http3`, so it adds one worker-owned pool and nothing per packet.

| Scope | Allocator | Lifetime |
| :- | :- | :- |
| Worker pool (session slots, stream slots, send buffers, pre-session buffers) | `config.allocator`, once at worker start | Worker lifetime, released at worker exit |
| Session slot | inside the pool | Session lifetime, recycled on close |
| Data stream slot and its send buffer | inside the pool, one contiguous allocation for every buffer | Stream lifetime, recycled when both halves of the stream are finished |
| Pre-session stream buffer | inside the pool | Until its session appears, or until the stream is refused |
| Per-connection WebTransport state (`Connection.wt`) | inline in the connection slot | Connection lifetime, fixed size (no per-packet heap) |

The receive path allocates nothing: sessions and streams come from the pool, and the pool returns null instead of growing, so a peer cannot make the server allocate. A worker's WebTransport memory cost is exactly `pool_streams * stream_send_bytes` plus `pool_orphan_streams * pool_orphan_bytes` (1 MiB of send buffers plus 8 KiB of orphan buffers at the defaults), paid once and independent of the connection count. `zix.Webtransport.capacityError` refuses a config that outgrows the compile-time ceilings rather than silently truncating the feature.

The full pool sizing and the per-connection cost are in [`docs/hld-webtransport-en.md`](docs/hld-webtransport-en.md).

For full memory details see [`docs/hld-http-en.md`](docs/hld-http-en.md) and [`docs/hld-udp-en.md`](docs/hld-udp-en.md). For threading models see [`docs/concurrency-en.md`](docs/concurrency-en.md).

<br>

## Requirements

- [Zig](https://ziglang.org/):
    - [x] 0.16.x:
        - 0.16.0
    - [x] 0.17.x (Experimental):
        - 0.17.0-dev.1933+e19a73c2d

<br>

## Getting Started

Fetch zix to your project:

Do zig fetch save https: <br>
`codeberg.org`
```sh
zig fetch --save "https://codeberg.org/prothegee/zix/archive/MAJOR.MINOR.x.tar.gz"
```
`github.com`
```sh
zig fetch --save "https://github.com/prothegee/zix/archive/refs/heads/MAJOR.MINOR.x.tar.gz"
```

<br>

Or,

use zig fetch save git+https: <br>
`codeberg.org`
```sh
zig fetch --save "git+https://codeberg.org/prothegee/zix#MAJOR.MINOR.x"
```
`github.com`
```sh
zig fetch --save "git+https://github.com/prothegee/zix#MAJOR.MINOR.x"
```

> Use `../zix#main` for upstream.

<br>

Add to your project (`build.zig` file):

```zig
// const exe = ...;

const zix = b.dependency("zix", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zix", zix.module("zix"));

// ...
```

<br>

## Build

zix is consumed as a Zig module (source), not shipped as a prebuilt library. The repository defines the `zix` module with `b.addModule`, so there is no `addStaticLibrary` or `addSharedLibrary` artifact. Running `zig build` on its own runs the default `install` step with nothing to install: no `.a`, no `.so`, nothing under `zig-out/lib`. It compiles the module graph and is useful only as a quick "does it still compile" check.

The real entry points are the named steps. List them any time with `zig build -l`:

| Step | What it does |
| :- | :- |
| `zig build` | Compile the module graph only. No artifact is emitted, because zix is a source module. |
| `zig build test-all` | Run unit, integration, behaviour, and edge tests. |
| `zig build unit-test` | Run unit tests only. Also `integration-test`, `behaviour-test`, `edge-test`. |
| `zig build examples` | Build every example into `zig-out/bin/`. Binaries are named `zix-example-<name>-<arch>-<os>-<optimize>`, so builds for several targets and several optimize modes coexist. Without `-Doptimize` the mode is `debug`. |
| `zig build example-<group>` | Build one group of examples, for example `example-http1` or `example-grpc`. |
| `zig build example-<name>` | Build one example into `zig-out/bin/`, for example `example-http1_websocket`. The installed binary carries the target triple and the optimize mode, run it from there. |
| `zig build test-runner-<name>` | Spawn a server plus client integration check, for example `test-runner-http1-websocket`. |
| `zig build test-runner-all` | Run every server-plus-client integration runner. |

Built example binaries land in `zig-out/bin/`. To build all examples, then run one in the background and stop it:

```sh
zig build examples                                             # build every example into zig-out/bin/
./zig-out/bin/zix-example-http1_websocket-x86_64-linux-debug & # run one in the background
kill %1                                                        # stop it
```

Every step accepts `-Dtarget=<arch>-<os>`, covering seven targets: x86_64-linux, x86_64-windows, aarch64-macos, aarch64-linux, x86_64-freebsd, x86_64-netbsd, x86_64-openbsd. On a foreign target the test and runner steps compile everything and skip execution with a warning. `scripts/build-all-targets.sh` sweeps every build option of zix and the drivers over all seven.

There is no `zig build install` library output and no `-Doptimize` is required for a plain compile check. To consume zix in another project, follow Getting Started above: it is added as a `build.zig.zon` dependency and imported with `exe.root_module.addImport("zix", zix.module("zix"))`, never linked as a system library.

<br>

## Testing

```sh
zig build unit-test        # unit tests (src/ inline tests)
zig build integration-test # integration tests (components wired together)
zig build behaviour-test   # behaviour tests (observable API contracts)
zig build edge-test        # edge tests (boundary conditions and error paths)
zig build test-all         # all of the above
```

`zig build` alone does not run tests. See [`docs/tests-en.md`](docs/tests-en.md) for full coverage details.

Cross-target: with a foreign `-Dtarget` every suite compiles for that target and execution is skipped with a warning. On a non-Linux host, tests that exercise the Linux-only EPOLL / URING paths print a warn and skip, so the suites stay green on every supported platform.

<br>

## Examples

For more examples see the `examples` directory.

Run `zig build examples` to build all examples (read `build.zig` for more detail).

### HTTP/1

Zix has two models API for HTTP/1, `zix.Http` and `zix.Http1`.

`zix.Http` relies on zig `std.http` and works as the convenient approach, while `zix.Http1` does not.

**When to use:** both engines share the same handler trio (`fn(*Request, *Response, *Context) anyerror!void`, caller-identical surface, ADR-062), the same comptime router, and the same dispatch models. Pick `zix.Http` when you want the full-featured layer (client stack, richer body handling). Pick `zix.Http1` when you want the lean hot-path engine with the lowest per-request overhead: its trio is stack views plus an arena reset, and the raw fd write helpers stay available as the escape hatch.

<br>

### Minimal Examples

Auto I/O (work-queue thread pool, default):
```zig
const std = @import("std");
const zix = @import("zix");

pub fn homeHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req; _ = ctx;
    try res.send("hello from zix");
}

pub fn main(process: std.process.Init) !void {
    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io   = process.io,
        .ip   = "127.0.0.1",
        .port = 9000,
    });
    defer server.deinit();
    try server.run();
}
```

Manual I/O (explicit concurrency limit via `concurrent_limit`, `.ASYNC` dispatch):
```zig
pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{
        .concurrent_limit = std.Io.Limit.limited(4), // pin to 4 concurrent tasks
        // .concurrent_limit = .unlimited             // let runtime decide
    });
    defer threaded.deinit();

    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io             = threaded.io(),
        .ip             = "127.0.0.1",
        .port           = 9000,
        .dispatch_model = .ASYNC, // .ASYNC uses the caller's io directly
    });
    defer server.deinit();
    try server.run();
}
```

**Examples:**
- [examples/http_basic.zig](examples/http_basic.zig) - dispatch model picked per target (`.URING` on Linux, `.ASYNC` elsewhere)
- [examples/http_manual_concurrent.zig](examples/http_manual_concurrent.zig) - explicit concurrency control via `Io.Threaded`
- [examples/http1_basic.zig](examples/http1_basic.zig) - raw `zix.Http1`, dispatch model picked per target
- [examples/http1_json.zig](examples/http1_json.zig)
- [examples/http1_jzon.zig](examples/http1_jzon.zig) - a JSON body in and a JSON body out through [jzon](./README-en.md#json-jzon)
- [examples/http1_params.zig](examples/http1_params.zig)
- [examples/http1_paths.zig](examples/http1_paths.zig)
- [examples/http1_query.zig](examples/http1_query.zig) - the QUERY method (RFC 10008)
- [examples/http1_middleware.zig](examples/http1_middleware.zig)
- [examples/http1_cache.zig](examples/http1_cache.zig)
- [examples/http1_manual_concurrent.zig](examples/http1_manual_concurrent.zig)

**When to use:** start here for any plain HTTP service. Auto I/O (default) is the simplest path and lets the runtime size its own thread pool. Switch to manual I/O with `concurrent_limit` only when you must cap concurrency explicitly: constrained memory, a fixed worker budget, or deterministic load tests.

<br>

### Routing

Routes are registered at compile time via `zix.Http.Router(&[_]zix.Http.Route{...})`, and `.dispatch` is passed to `Server.init`. Each `Route` entry has a `path`, a `handler`, and an optional `kind` (`.EXACT` by default):

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/about",           .handler = aboutHandler },
    // exact (default): matches only /about

    .{ .path = "/api",             .handler = apiHandler,    .kind = .PREFIX },
    // prefix: matches /api, /api/foo, /api/foo/bar, NOT /apiv2

    .{ .path = "/users/:id",       .handler = userHandler,   .kind = .PARAM },
    // param: matches /users/alice, captures id="alice"
    // read inside handler: req.pathParam("id")

    .{ .path = "/:tenant/:branch", .handler = branchHandler, .kind = .PARAM },
    // multi-param: req.pathParam("tenant"), req.pathParam("branch")
}).dispatch, .{ .ip = "127.0.0.1", .port = 9000 });
```

**Priority:**

```
exact  >  param  >  prefix (longer prefix beats shorter)
```

Exact and prefix priority is independent of registration order. **Param routes are the exception**: when two patterns have the same segment count and both match, the first entry in the route table wins. Register more-literal patterns before all-param patterns of the same depth:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    // Correct order: /path/user/:id wins for /path/user/alice
    .{ .path = "/path/user/:id",        .handler = userHandler,   .kind = .PARAM },
    .{ .path = "/path/:tenant/:branch", .handler = tenantHandler, .kind = .PARAM },
}).dispatch, .{ ... });
```

| Registered | Request | Winner | Reason |
| :- | :- | :- | :- |
| `/path/info` (exact) + `/path/:id` (param) | `/path/info` | `/path/info` | exact beats param |
| `/path/:id` (param) + `/path` (prefix) | `/path/alice` | `/path/:id` | param beats prefix |
| `/api/v2` + `/api` (both prefix) | `/api/v2/foo` | `/api/v2` | longer prefix wins |
| `/path/user/:id` (1st) + `/path/:a/:b` (2nd) | `/path/user/alice` | `/path/user/:id` | more literals registered first |

**Regex-like matching**: zix has no regex engine. A prefix route (`.kind = .PREFIX`) covers the registered path and any sub-path below it. Additional filtering is done inside the handler with plain string operations on `req.path()`:

```zig
// In the route table:
.{ .path = "/secret", .handler = secretHandler, .kind = .PREFIX },

// Inside secretHandler: extract sub-path and apply custom logic
const sub = req.path()["/secret/".len..];  // e.g. "file.txt"
// check extension, depth, query params, headers, etc.
```

**Examples:**
- [examples/http_params.zig](examples/http_params.zig) - query and form parameter handling
- [examples/http_paths.zig](examples/http_paths.zig) - path parameter routing patterns
- [examples/http_query.zig](examples/http_query.zig) - the QUERY method (RFC 10008)
- [examples/http_json.zig](examples/http_json.zig) - JSON response handling

**Raw `zix.Http1` engine**: the low-level engine ships the same comptime `Router` with identical `.EXACT` / `.PREFIX` / `.PARAM` kinds, the same `exact > param > prefix` priority, and the same trio handler, so param capture reads identically: `req.pathParam("id")` (the free function `zix.Http1.pathParam("id")` remains as the raw-layer equivalent):

```zig
const Router = zix.Http1.Router(&[_]zix.Http1.Route{
    .{ .path = "/",          .handler = homeHandler },
    .{ .path = "/secret",    .handler = secretHandler, .kind = .PREFIX },
    .{ .path = "/users/:id", .handler = userHandler,   .kind = .PARAM },
});

var server = zix.Http1.Server.init(Router.dispatch, .{ .ip = "0.0.0.0", .port = 9100 });

// inside userHandler:
const id = req.pathParam("id") orelse return;
```

Per-route param capture is capped at 8 params per match..

**Examples:**
- [examples/http1_static.zig](examples/http1_static.zig) - a prefix route in use

**When to use:** use the comptime route table whenever a service has more than one endpoint. Prefer `.EXACT` for fixed paths, `.PARAM` for resource ids, and `.PREFIX` for sub-trees or fallthrough to static serving. Register more-literal patterns before all-param patterns of the same depth so the intended route wins.

<br>

### Handler Errors

Every handler returns `anyerror!void`, and every engine follows one rule: **a handler that returns an error is answered exactly once**. It answered nothing, the engine sends the protocol default. It already answered, the engine stays quiet rather than gluing a second answer onto the first.

| engine | default when the handler answered nothing |
| :- | :- |
| `zix.Http` | `500`, `text/plain`, body `Internal Server Error` |
| `zix.Http1` | `500`, `text/plain`, body `Internal Server Error` |
| `zix.Http2` | `500`, `text/plain`, body `Internal Server Error` |
| `zix.Http3` | `500`, empty body |
| `zix.Grpc` | trailers carrying `grpc-status 13` (INTERNAL) |
| `zix.Fix` | Reject (`35=3`) carrying the RefSeqNum of the message that failed |

"Answered" counts both ways of answering: the `Response` builder and the fd writers (`zix.Http1.sendSimpleFD`, `zix.Http2.sendResponseFD`, `writeAllFD`). A handler that answers through either one is not answered again.

`try` is how the default is reached. An error the handler catches itself never reaches the engine, so the handler owns what the caller gets:

```zig
fn handler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
    // try: the engine completes a failure as the default above
    const row = try db.fetch(req.param("id").?);

    // catch: the answer is yours, the engine adds nothing to it
    res.sendJson(row.json) catch {
        res.setStatus(.SERVICE_UNAVAILABLE);
        try res.sendText("try again shortly");
    };
}
```

The same choice exists on every engine, in that engine's own vocabulary:

```zig
// zix.Grpc
try res.sendMessage(ct, reply);                 // failure closes the call with grpc-status 13
res.sendMessage(ct, reply) catch {              // yours to close
    try res.finish(zix.Grpc.Status.UNAVAILABLE, "backend down");
};

// zix.Fix
try res.sendMessage(zix.Fix.MsgType.ExecutionReport, fields);  // failure answers with a Reject
res.sendMessage(zix.Fix.MsgType.ExecutionReport, fields) catch {
    try res.sendMessage(zix.Fix.MsgType.OrderCancelReject, reason_fields);
};
```

One exception: `zix.Http3.Response.send` returns `void`, not an error union. It only stores the body, the engine sends it after the handler returns, so there is nothing to `try` at that line. A handler error still reaches the engine and still becomes a 500.

### Concurrency Model

Three dispatch models, selected via `config.dispatch_model` (`DispatchModel` enum). This field is required: the caller must set it explicitly (there is no default). `.EPOLL` and `.URING` are Linux-only, so a portable caller picks the model per target at comptime:

```zig
const DISPATCH_MODEL: zix.Http1.DispatchModel = if (builtin.os.tag == .linux) .URING else .ASYNC;
```

**`.ASYNC` (single accept, `io.async()` dispatch):**

One accept thread dispatches each connection via `io.async()`. `workers` is ignored. Preferred for SSE and WebSocket (a long-lived connection costs a task, not a worker slot). Also suitable for explicit `concurrent_limit`. This is the only model available on every platform.

```zig
pub fn main(process: std.process.Init) !void {
    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io = process.io,
        .dispatch_model = .ASYNC, // required: .ASYNC, .EPOLL, or .URING
        // workers = 0 -> cpu_count workers for .EPOLL / .URING, ignored by .ASYNC
    });
```

**`.EPOLL` (shared-nothing epoll workers, Linux-only):**

Each worker owns a private `SO_REUSEPORT` listener and one `epoll` instance. The kernel distributes new connections across workers. No shared queue, no mutex, no fd handoff between threads. Level-triggered `EPOLLIN` keeps connections registered after each request without explicit re-arm. Idle keep-alive connections hold no thread. Best for high-throughput short-lived requests on Linux. Off Linux, `run()` returns `error.ZixDispatchModelUnsupported`: pick `.ASYNC` there.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .EPOLL,
    .workers        = 0, // 0 = cpu_count workers (default)
});
```

**`.URING` (shared-nothing io_uring workers, Linux-only):**

Same thread-per-core, shared-nothing topology as `.EPOLL` (one `SO_REUSEPORT` listener and one ring per worker, no shared queue), but completion-based instead of readiness-based, so most syscall transitions are batched into the ring. Accept, recv, send, and close all run on the ring (`zix.Http1` rings the close via `prep_close`, so the worker keeps reaping completions across connection teardowns under churn). Implemented natively by `zix.Http1`, `zix.Http`, `zix.Grpc`, `zix.Fix`, and `zix.Http2`. The `zix.Tcp` per-connection handler has no native ring and folds to `.EPOLL` (its `initFramed` per-frame path does run on the ring). Off Linux, `run()` returns `error.ZixDispatchModelUnsupported`: pick `.ASYNC` there.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .URING,
    .workers        = 0, // 0 = cpu_count workers (default)
});
```

---

__*In the nutshell:*__
- Looking for high throughput? Use `.EPOLL` or `.URING`.
- Looking for consistent latency? Use `.ASYNC`.
- On a non-Linux platform? Use `.ASYNC`, the only model available there.

> In many cases for high throughput,
> zix EPOLL mostly wins for memory efficiency and zix URING got more throughput.
> However in some cases its performance can vary, see the historical benchmarks in the `docs/benchmark` directory for reference.
> Uring is not allowed in some environment for some reason (e.g. security stand point). But you got the options.

**When to use:** the dispatch model is the one knob that reshapes the whole server. Reach for `.ASYNC` when latency and long-lived connections (SSE, WebSocket) matter or when the target is not Linux, and `.EPOLL` / `.URING` on Linux for the highest connection counts at the lowest per-request cost. On a loopback dev box the two tie on throughput and `.URING` wins mainly on cache locality. On a many-core box the ring close lets `.URING` keep its cores busy through connection churn, where it reaches parity or better than `.EPOLL` on every measured workload at a fraction of the memory.

**Why per-engine:** each engine implements these models in its own `server.zig`, not behind one shared multiplexer. The split is deliberate and is itself the optimization: it lets every engine tune its own hot path. `zix.Http1` carves connection buffers from a contiguous demand-paged slab (no per-accept heap call), while `zix.Grpc` and `zix.Fix` hold per-connection heap pointers because their connections carry h2 or FIX session state. Only byte-identical primitives are shared (the `.URING` `user_data` codec in `src/multiplexers/ring.zig`): share primitives that must match, keep dispatch loops per-engine..

> Our workload is not same, what suits you may not suits to someone else.
> Test your workload when possible, maybe with a 1:4 ratio from a production environment.
> Zix will not dictate your approach.

See [`docs/concurrency-en.md`](docs/concurrency-en.md) for architecture details, thread counts, and when to prefer each model.

<br>

### Timeouts

Two independent timeout layers, both disabled by default (`0`):

**`conn_timeout_ms`**: network-level connection guard (Layer D). The timer thread shuts down connections that have been open longer than this without completing. Protects the accept path from clients that stall before or during header send. Effective in `.ASYNC` only (the `.EPOLL` / `.URING` event loops own connection lifetime themselves).

**`handler_timeout_ms`**: per-handler execution budget (Layer B). Sets `ctx.deadline` before each dispatch. Handlers opt in by calling `ctx.isExpired()` between expensive steps.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/slow", .handler = slowHandler },
}).dispatch, .{
    .io                 = process.io,
    .ip                 = "127.0.0.1",
    .port               = 9000,
    .conn_timeout_ms    = 30_000, // close stalled connections after 30s
    .handler_timeout_ms = 5_000,  // handler budget: 5s
});
```

Handler using the budget:

```zig
pub fn slowHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req;

    doStep1(ctx.io);
    if (ctx.isExpired()) {
        res.setStatus(.REQUEST_TIMEOUT);
        return res.sendJson("{\"error\":\"timeout\"}");
    }

    doStep2(ctx.io);
    if (ctx.isExpired()) {
        res.setStatus(.REQUEST_TIMEOUT);
        return res.sendJson("{\"error\":\"timeout\"}");
    }

    try res.sendJson("{\"result\":\"ok\"}");
}
```

To override the deadline inside a handler (shorter or longer window than the global budget):

```zig
ctx.setTimeout(2_000); // override to 2s from now regardless of global cap
```

`ctx.isExpired()` is a no-op (always returns `false`) when `handler_timeout_ms == 0`. `ctx.timedOut()` is an alias for `ctx.isExpired()`. `conn_timeout_ms` should be >= `handler_timeout_ms` to avoid the connection being cut before the handler can send a 408. See `docs/adr-en.md` for design rationale.

**Examples:**
- [examples/http_timeout_resp.zig](examples/http_timeout_resp.zig)
- [examples/http1_timeout_resp.zig](examples/http1_timeout_resp.zig) - raw `zix.Http1`, uses `zix.Http1.isExpired()` plus the trio's `ctx.setTimeout()` / `ctx.timedOut()`

**When to use:** set `handler_timeout_ms` whenever a handler can run long (external calls, heavy compute) and you want it to bail out cooperatively with a 408 instead of holding a thread. Add `conn_timeout_ms` under `.ASYNC` to evict clients that stall before completing a request. Leave both at 0 for trusted internal traffic with bounded work.

<br>

### Middleware

Middleware is composed at comptime using wrapper functions. Each wrapper takes a `comptime next: zix.Http.HandlerFn` and returns a new `HandlerFn` (no heap allocation, no runtime chain runner).

```zig
fn withOriginCheck(comptime next: zix.Http.HandlerFn) zix.Http.HandlerFn {
    return struct {
        fn handle(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
            const origin = req.header("origin") orelse "";
            if (!isAllowedOrigin(origin)) {
                res.setStatus(.FORBIDDEN);
                try res.sendJson("{\"error\":\"forbidden origin\"}");
                return;
            }
            return next(req, res, ctx);
        }
    }.handle;
}

fn withBasicAuth(comptime next: zix.Http.HandlerFn) zix.Http.HandlerFn {
    return struct {
        fn handle(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
            // validate Authorization: Basic <base64(user:pass)>
            // ...
            return next(req, res, ctx);
        }
    }.handle;
}
```

Compose left-to-right, the outermost wrapper runs first:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    // origin check only
    .{ .path = "/public",  .handler = withOriginCheck(publicHandler) },
    // origin check -> basic auth -> handler
    .{ .path = "/private", .handler = withOriginCheck(withBasicAuth(privateHandler)) },
}).dispatch, .{ .io = process.io, .ip = "127.0.0.1", .port = 9008 });
```

```
# curl examples
curl -H "Origin: http://localhost" "http://localhost:9008/public"                         # 200
curl "http://localhost:9008/public"                                                       # 403

curl -H "Origin: http://localhost" -u "admin:secret" "http://localhost:9008/private"      # 200
curl -H "Origin: http://localhost" "http://localhost:9008/private"                        # 401
curl "http://localhost:9008/private"                                                      # 403
```

**Examples:**
- [examples/http_middleware.zig](examples/http_middleware.zig)

**When to use:** compose middleware for cross-cutting concerns that wrap many routes: auth, origin/CORS checks, rate limits, request logging. Because the chain is built at comptime with no heap and no runtime runner, it costs nothing per request, so prefer it over per-handler boilerplate whenever the same guard repeats across routes.

<br>

### WebSocket

Room-based broadcast over RFC 6455. A param handler upgrades the connection and enters a per-task frame loop, no separate thread needed.

```zig
var ws_rooms: zix.Http.WebSocket.RoomMap = undefined;

pub fn wsHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    const room_id = req.pathParam("room-id") orelse return;

    // Read query params BEFORE upgrade() (unavailable after the 101 handshake).
    const display_name = req.queryParam("name") orelse "anonymous";

    // extract Sec-WebSocket-Key from headers, then handshake
    var accept_buf: [64]u8 = undefined;
    const accept = try zix.Http.WebSocket.acceptKey(ws_key, &accept_buf);
    try zix.Http.WebSocket.upgrade(ctx.stream, ctx.io, accept); // writes 101 directly

    // heap-allocate conn, join room, both are cleaned up via defer (LIFO)
    const conn = try std.heap.smp_allocator.create(zix.Http.WebSocket.Conn);
    conn.* = .{ .stream = ctx.stream, .io = ctx.io };
    defer std.heap.smp_allocator.destroy(conn);
    ws_rooms.join(room_id, conn, ctx.io);
    defer ws_rooms.leave(room_id, conn, ctx.io);  // runs before destroy

    // frame loop:
    //   text/binary -> broadcast "[display_name] payload" to room
    //   ping        -> pong
    //   close       -> echo close frame + break
    //   EOF / error -> best-effort close frame + break
    _ = display_name;
}

pub fn main(process: std.process.Init) !void {
    ws_rooms = zix.Http.WebSocket.RoomMap.init(std.heap.smp_allocator);
    defer ws_rooms.deinit();

    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/ws/:room-id", .handler = wsHandler, .kind = .PARAM },
    }).dispatch, .{ .io = process.io, .ip = "127.0.0.1", .port = 9008 });
    defer server.deinit();
    try server.run();
}
```

```
# Connect with wscat or websocat, ?name sets the broadcast display name
wscat    -c "ws://localhost:9008/ws/lobby?name=alice"
websocat    "ws://localhost:9008/ws/lobby?name=alice"

# ?name is optional, omit for "anonymous"
wscat    -c "ws://localhost:9008/ws/lobby"
```

**Priority:** exact > param > prefix. `/ws/:room-id` is a param route, so `/ws/lobby` captures `room-id = "lobby"`.

`ctx.stream` is the raw TCP stream exposed via `Context`. The server sets it for **every** connection before calling any handler: HTTP handlers ignore it, WebSocket handlers use it after the 101 upgrade.

**Combining HTTP, static, and WebSocket in one server**: register all handler types together, routing handles dispatch. Unmatched routes fall through to static serving:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/",          .handler = homeHandler },
    .{ .path = "/api",       .handler = apiHandler,  .kind = .PREFIX },
    .{ .path = "/ws/:room-id", .handler = wsHandler, .kind = .PARAM },
}).dispatch, .{
    .io         = process.io,
    .ip         = "127.0.0.1",
    .port       = 9008,
    .public_dir = "./public", // static files for unmatched routes
});
```

**Examples:**
- [examples/http_websocket.zig](examples/http_websocket.zig) - full working example
- [examples/http_ws_client.zig](examples/http_ws_client.zig) - matching client
- [examples/http1_websocket.zig](examples/http1_websocket.zig) - raw `zix.Http1.WebSocket`: `/ws` echo plus `/ws/:room-id` broadcast rooms

**Build-once broadcast fanout**: on the engine-owned `zix.Http1` path, `zix.Http1.WebSocket.broadcast(conns, opcode, payload)` serializes the frame a single time and writes the same bytes to every fd in a caller-maintained room, so a broadcast costs one serialization no matter how many members it reaches. A failed write to a dead peer is skipped (the EPOLL engine reaps that fd on its next event), and the large-payload path builds the header once and writes the payload without copying it into a staging buffer. The high-level `zix.Http.WebSocket.RoomMap.broadcast` follows the same build-once, fan-out shape with a server-managed room registry.

**When to use:** use WebSocket for bidirectional, low-latency push (chat, presence, live dashboards, game state). Pair it with `.ASYNC` so long-lived connections never pin a pool thread, and reach for the build-once `broadcast` when one message fans out to a room. If the data flow is one-way server-to-client, prefer SSE: it is simpler and reconnects natively in the browser.

<br>

### SSE (Server-Sent Events)

One-way server push over HTTP/1.1: no WebSocket handshake, browser-native `EventSource` reconnect.

```zig
// GET /events: streams "tick N" once per second
pub fn eventsHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req;
    const sse = try res.sendStream(); // sends SSE headers, returns SseWriter
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var buf: [32]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "tick {d}", .{i}) catch break;
        sse.writeEvent(msg) catch break;                                       // data: tick N\n\n
        std.Io.sleep(ctx.io, std.Io.Duration.fromMilliseconds(1000), .awake) catch break;
    }
    // handler returns -> connection closes -> EventSource auto-reconnects
}
```

| `SseWriter` method | Wire format |
| :- | :- |
| `writeEvent(data)` | `data: <data>\n\n` |
| `writeNamedEvent(event, data)` | `event: <event>\ndata: <data>\n\n` |
| `comment(text)` | `: <text>\n` (keepalive) |

**Dispatch model:** use `.ASYNC`. SSE connections are long-lived, and `.ASYNC` dispatches each one via `io.async()`, so an open stream costs a task rather than an event-loop worker slot.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/events", .handler = eventsHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .ASYNC, // preferred for SSE: long-lived connections do not hold pool threads
});
```

```sh
curl -N http://localhost:9010/events
```

**Examples:**
- [examples/http_sse.zig](examples/http_sse.zig) - full example with a browser-compatible HTML page
- [examples/http_sse_client.zig](examples/http_sse_client.zig) - matching client
- [examples/http1_sse.zig](examples/http1_sse.zig) - raw `zix.Http1` engine

**When to use:** choose SSE for one-way server push over plain HTTP (progress streams, notifications, log tailing, live metrics) when the client does not need to send frames back. It is lighter than WebSocket and `EventSource` reconnects automatically. Always run it under `.ASYNC`, which costs a task per open stream instead of pinning an event-loop worker.

<br>

### HTTP Client

`zix.Http.Client` makes outbound HTTP requests. Each call returns a `ClientResponse` the caller owns and must release with `deinit()`.

```zig
var client = zix.Http.Client.init(.{
    .allocator         = arena.allocator(),
    .io                = process.io,
    .connect_timeout_ms = 5000,       // error.Timeout if TCP connect takes > 5s
    .max_response_body  = 64 * 1024,  // error.ZixBodyTooLarge if body exceeds 64 KB
});
defer client.deinit();

// GET
var resp = try client.get("http://127.0.0.1:9000/", .{});
defer resp.deinit();
std.debug.print("{d}: {s}\n", .{ resp.status(), resp.body() });

// GET with header inspection
if (resp.header("content-type")) |ct| {
    std.debug.print("content-type: {s}\n", .{ct});
}

// POST with body and custom headers
const extra = [_]std.http.Header{
    .{ .name = "X-Trace-Id", .value = "abc-123" },
};
var post_resp = try client.post("http://127.0.0.1:9000/api/items", .{
    .headers = &extra,
    .body    = "{\"name\":\"widget\"}",
});
defer post_resp.deinit();

// Per-request connect timeout override
var fast = try client.get("http://127.0.0.1:9000/health", .{
    .connect_timeout_ms = 500,
});
defer fast.deinit();
```

| Method shorthand | Sends body? |
| :- | :- |
| `client.get(url, opts)` | no |
| `client.head(url, opts)` | no |
| `client.post(url, opts)` | yes (Content-Length: 0 if opts.body is null) |
| `client.put(url, opts)` | yes |
| `client.patch(url, opts)` | yes |
| `client.delete(url, opts)` | no |
| `client.request(method, url, opts)` | depends on method |

| Error | Condition |
| :- | :- |
| `error.ZixUrlMalformed` | the URL does not parse |
| `error.ZixUrlSchemeUnsupported` | the scheme is not one the transport speaks |
| `error.ZixUrlHostMissing` | the URL carries no host |
| `error.ZixUrlPortInvalid` | the port is not a number in range |
| `error.ZixUrlPathTooLong` | the path and query do not fit the request buffer |
| `error.ZixBodyTooLarge` | response body exceeded `max_response_body` |
| `error.Timeout` | TCP connect exceeded `connect_timeout_ms` |

Redirects are followed automatically up to `max_redirects` (default 3). Set `follow_redirects = false` to receive the 3xx response directly.

The same `zix.Http.Client` works against the raw `zix.Http1` server via `.version = .HTTP_1` (the version selector, with `HTTP_2` and `HTTP_3` reserved).

**Examples:**
- [examples/http_client.zig](examples/http_client.zig)
- [examples/http1_client.zig](examples/http1_client.zig) - sets `.version = .HTTP_1`

[`docs/hld-http-en.md`](docs/hld-http-en.md) for details.

**When to use:** use `zix.Http.Client` for outbound calls from a handler or a standalone tool: health checks, service-to-service requests, webhooks, or fetching a known endpoint. Set `connect_timeout_ms` and `max_response_body` to bound untrusted peers, and disable `follow_redirects` when you must inspect a 3xx yourself.

<br>

### Static Files & Upload

Set `public_dir` in `HttpServerConfig` to enable static file serving. `server.run()` returns `error.ZixPublicDirNotFound` if the directory does not exist. Use a `createInitDirs` helper to create all required directories before `Server.init`:

```zig
fn createInitDirs(io: std.Io) void {
    std.Io.Dir.cwd().createDirPath(io, "./public") catch {};
    std.Io.Dir.cwd().createDirPath(io, "./public/u") catch {};
}

pub fn main(process: std.process.Init) !void {
    createInitDirs(process.io); // idempotent, safe on every start

    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/upload", .handler = uploadHandler },
    }).dispatch, .{
        .io                = process.io,
        .ip                = "127.0.0.1",
        .port              = 9005,
        .public_dir        = "./public", // validated at run(); "" = disabled
        .public_dir_upload = "u",
    });
```

- Unmatched routes fall through to static serving from `public_dir`.
- Range requests (`Range: bytes=...`) -> `206 Partial Content` (RFC 7233).
- Directory traversal (`..`) is rejected.

**Upload**: parse the multipart body in a handler, optionally rename before saving:

```zig
var parser = zix.utils.multipart.Parser.init(ctx.allocator, boundary);
defer parser.deinit();
try parser.parse(try req.body());

if (parser.getField("file")) |f| {
    // you can rename file first before save by replacing the filename string, e.g.:
    //   const filename = "custom_name.txt"
    // or build it dynamically:
    //   const filename = try std.fmt.allocPrint(ctx.allocator, "{s}_{s}", .{ sessionid, f.filename orelse "upload" });
    const filename = f.filename orelse "upload";
    const path = try zix.utils.file.save(ctx.io, ctx.allocator, "./public/u", filename, f.data);
    _ = path; // arena-allocated, valid for this request
}
```

`zix.utils.file.save` creates the destination directory if needed and returns a caller-owned path copy.

```
# curl example: upload a file with JSON metadata
curl -X POST "http://localhost:9005/upload" \
  -F "file=@/path/to/file.txt" \
  -F 'data={"userid":0,"sessionid":"01944f5a-0000-7000-8000-000000000000"}'
```

**Examples:**
- [examples/http_static.zig](examples/http_static.zig) - full working example including static serving, range requests, and multipart upload
- [examples/http1_static_cached.zig](examples/http1_static_cached.zig) - the same fallback with `public_dir_cache_ttl_ms` set, showing the cached path and `.br` / `.gz` sibling pickup
- [examples/tls/http3_static.zig](examples/tls/http3_static.zig) - static serving over HTTP/3, where the cache is what makes it possible at all

**When to use:** enable `public_dir` to serve a built frontend, assets, or downloads from the same server, with range requests handled for you. Use the multipart path for user uploads when you control the storage target. With `public_dir_cache_ttl_ms` set, a cleartext response hands the file to the kernel with `sendfile`, so the bytes never enter user space. A CDN is still the right answer for bulk file distribution across regions: this is for convenience and co-located assets.

**Important:** consider tweak the `max_recv_buf` field depend on your upload chunk file size when you serving an upload functionality.

<br>

### Response Header Cap (`HeaderSize`)

`HttpServerConfig.max_response_headers` controls how many custom headers `res.addHeader()` will accept per response. Pick the tier that matches your deployment:

| Variant | Cap | Typical use |
| :- | :- | :- |
| `.MINIMAL` | 16 | **Default.** Simple internal APIs, controlled environments, bare handlers |
| `.COMMON` | 32 | Most web apps, single proxy |
| `.LARGE` | 64 | CDN + proxy, load balancers, CORS-heavy APIs |
| `.EXTRA_LARGE` | 128 | k8s, service mesh, heavy forwarding stacks |
| `.{ .CUSTOM = N }` | N | Explicit cap, arena-allocated to exactly N slots per request |

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .max_response_headers = .LARGE,                // 64 headers
    // .max_response_headers = .{ .CUSTOM = 48 },  // explicit
});
```

`addHeader()` returns `error.ZixTooManyHeaders` when the cap is reached and `error.ZixInvalidHeaderName` / `error.ZixInvalidHeaderValue` if the name or value contains CR or LF (header injection guard).

`.{ .CUSTOM = N }` allocates exactly N slots from the per-request arena (no ceiling, no clamping).

**Examples:**
- [examples/http_xtra_headers.zig](examples/http_xtra_headers.zig) - working demonstration
- [examples/http1_xtra_headers.zig](examples/http1_xtra_headers.zig) - raw `zix.Http1`, hand-builds headers with a CR/LF injection guard

[`docs/headers-en.md`](docs/headers-en.md) for security guidance and tier selection.

**When to use:** raise `max_response_headers` only as far as your deployment needs. Keep `.MINIMAL` for internal APIs, step up to `.LARGE` / `.EXTRA_LARGE` behind CDNs, proxies, or CORS-heavy stacks that add many forwarding headers. A tighter cap is a cheap guard against runaway header growth and is arena-sized to exactly the tier you pick.

<br>

### Request Header Cap (`RequestHeaderSize`)

`HttpServerConfig.max_request_headers` controls how many headers the server accepts per request. Requests exceeding the cap are rejected with `431 Request Header Fields Too Large`.

| Variant | Cap | Note |
| :- | :- | :- |
| `.MINIMAL` | 16 | Strict APIs, internal services |
| `.COMMON` | 32 | Most web applications |
| `.LARGE` | 64 | **Default.** Parser storage limit. CDN, proxy, CORS-heavy APIs |
| `.{ .CUSTOM = N }` | N (capped at 64) | Explicit cap values above 64 silently capped at the parser limit |

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .max_request_headers = .COMMON,                // 32 headers
    // .max_request_headers = .{ .CUSTOM = 24 },   // explicit
});
```

The parser storage limit is 64: `CUSTOM` values above 64 are silently capped. See `zix.Http.RequestHeaderSize`.

**When to use:** lower `max_request_headers` (`.MINIMAL` / `.COMMON`) on strict internal services to reject oversized header blocks early with a 431. Keep the `.LARGE` default for public endpoints behind proxies that legitimately add headers. The hard parser ceiling is 64, so `CUSTOM` above that is silently capped.

<br>

### Response Cache Awareness (`response_cache`)

`zix.Http1`, `zix.Http`, and `zix.Grpc` share an opt-in, per-worker response cache. A handler builds its response once, the engine stores it under a key derived from the request, and a later matching request replays the stored bytes with no rebuild. A hit skips both the handler's body build and the serialization. The cache is data oriented (a structure of arrays plus one flat payload slab), lock-free by ownership (one instance per worker, never shared), and freshness is a lazy on-access TTL.

What the key and the cached value are depends on the engine:

| Engine | Cache key | Cached value |
| :- | :- | :- |
| `zix.Http1`, `zix.Http` | method, path, query | the full serialized HTTP response, written verbatim |
| `zix.Grpc` (unary) | path, request message | the response message, re-framed per stream (HPACK and stream id stay correct) |

It is off by default. Enable it on the `.EPOLL` or `.URING` dispatch model:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/report", .handler = reportHandler },
}).dispatch, .{
    .ip = "0.0.0.0",
    .port = 8080,
    .dispatch_model = .EPOLL,
    .response_cache = true,                  // enable the per-worker cache
    .cache_max_entries = 256,                // slots, rounded down to a power of two
    .cache_max_value_bytes = 16 * 1024,      // per-slot response cap
    .cache_ttl_ms = 1000,                    // default freshness
    // .cache_max_total_bytes = 4 * 1024 * 1024, // optional per-worker memory ceiling
});
```

A miss builds and stores the response, a fresh hit is served verbatim:

```zig
fn reportHandler(req: *zix.Http.Request, res: *zix.Http.Response, _: *zix.Http.Context) !void {
    if (res.sendFromCache(req)) return;          // fresh hit: cached bytes already written

    const body = try buildExpensiveReport(req);  // runs only on a miss
    res.setContentType(.APPLICATION_JSON);
    try res.sendCached(req, body, 0);            // ttl 0 uses cache_ttl_ms
}
```

The raw `zix.Http1` engine exposes the same idea through `cacheLookup` and `sendWithCacheFD` (or the trio's `res.sendFromCache` / `res.sendCached`).

For gRPC unary handlers the opt-in lives on the response builder. `res.serveCached` replays a stored reply message (re-framed for the current stream and finished with OK), and `res.sendCached` sends and stores the reply. Enable it with the same field names on `GrpcServerConfig` (`response_cache`, `cache_max_entries`, and so on) under `.EPOLL` or `.URING`:

```zig
fn sayHello(req: *zix.Grpc.Request, res: *zix.Grpc.Response, _: *zix.Grpc.Context) !void {
    if (res.serveCached("application/grpc")) return; // fresh hit: reply sent, stream finished

    const reply = buildExpensiveReply(req.recvMessage()); // runs only on a miss
    res.sendCached("application/grpc", reply, 0);          // ttl 0 uses cache_ttl_ms
    res.finish(.OK, "");
}
```

#### When it pays off

The measured crossover on loopback is around 4 KiB of response body. Below that the cost is dominated by the kernel and the cache is a wash. Above it the saved work grows with body size.

| Response shape | Cache effect |
| :- | :- |
| Compute-heavy serialization (large JSON, rendered output) above ~4 KiB | Best case, large gain (heavy ~32 KiB JSON measured +34% throughput) |
| Small responses below ~2 KiB | Wash, kernel-bound, zero regression |
| Static files read from disk | Marginal: the OS page cache already serves the file cheaply, prefer sendfile or splice |
| Per-request unique bodies (no key repetition) | No benefit, every request misses |

#### Rules and conditions

- Opt-in only. Off by default, and the handler must call `res.sendFromCache` then `res.sendCached` (HTTP engines), `res.serveCached` then `res.sendCached` (gRPC), or the raw `zix.Http1` `cacheLookup` / `sendWithCacheFD`.
- `.EPOLL` and `.URING` only in this release. The other dispatch models leave the cache uninstalled and the API degrades to a plain send.
- For HTTP the key is method, path, and query: two requests differing only in their query string are distinct entries, and you must not cache responses that vary on a header or cookie. When a response is compressed (`sendNegotiateFD` / `sendGzipCachedFD`), the content-encoding is also folded into the key (`hashKeyEncoded`), so the gzip and brotli variants occupy distinct entries. For gRPC the key is the path plus the request message, so only an identical request hits.
- A QUERY response is never stored. The HTTP key carries no request content, so two QUERY requests to one path with different bodies would share an answer. RFC 10008 section 2.7 makes caching a QUERY response a MAY, so both HTTP engines refuse the store outright. Nothing changes for any other method.
- Cache only what is safe to replay for the TTL window. For HTTP the same bytes (including the captured `Date`) are served until the entry expires, so keep `cache_ttl_ms` short for time-sensitive content.
- Responses larger than `cache_max_value_bytes` bypass the cache and fall back to a plain send. For gRPC this cap applies to the response message. Keep it lean so only past-crossover responses occupy a slot.
- Per-worker memory is `cache_max_entries * cache_max_value_bytes`, times the worker count, optionally bounded by `cache_max_total_bytes`.

**Why `.EPOLL` / `.URING` only:** the cache is a thread-local instance, never shared and never locked (lock-free by ownership). That invariant holds only when one zix-owned thread installs the cache (allocate, set, free on exit) and is the sole thread that touches it. The shared-nothing `.EPOLL` workers and the one-thread-per-ring `.URING` workers both satisfy it.

| Model | Runs the handler on | Cache state |
| :- | :- | :- |
| `.EPOLL` | a zix-owned shared-nothing worker thread, one per core | installed: clean lifecycle, one owner thread, the benchmarked path |
| `.URING` | a zix-owned shared-nothing ring worker, one per core | installed: same one-owner-thread lifecycle as `.EPOLL` |
| `.ASYNC` | `io.async()` tasks on the `std.Io` executor pool, not owned by zix | not installed: no per-thread install hook, and a task is not pinned to one thread, so a shared cache would need locks and break the lock-free design |

Under any model the behavior is safe, just inert: with the cache uninstalled, `response_cache = true` and the `sendFromCache` / `sendCached` calls degrade to a plain send (no error, no caching).

```mermaid
flowchart TD
    A[Incoming request] --> B{response_cache and EPOLL/URING?}
    B -- no --> P[Plain send]
    B -- yes --> C{sendFromCache hit and fresh?}
    C -- yes --> W[Write cached bytes, no rebuild]
    C -- no --> D[Build response]
    D --> E{body larger than cache_max_value_bytes?}
    E -- yes --> P
    E -- no --> S[sendCached: write then store under key]
```

**When to use:** turn the cache on for hot, repeatable, compute-heavy responses above ~4 KiB (rendered reports, large JSON aggregates) served under `.EPOLL` or `.URING`. Leave it off for small kernel-bound responses, per-request unique bodies, or anything that varies on a header or cookie, where it adds no benefit. Read the rules above before caching anything time-sensitive.

See `docs/adr-en.md` for the design rationale and measured numbers.

<br>

### Process Queue Awareness (`process_queue_len`)

`zix.Http1` and `zix.Http` share an opt-in, per-worker submission-queue backpressure ring under the `.URING` dispatch model. When a connection burst fills the io_uring submission queue, a recv or send re-arm that would otherwise close the connection is parked on a per-worker FIFO ring, holding only a reference (the fd plus a generation tag, never the request bytes), and retried on the next loop pass. Without it, a re-arm dropped on a full submission queue closes the connection, and a lost multishot-accept re-arm stops the worker from accepting at all while the kernel backlog fills.

It is `.URING` only, on `zix.Http1` and `zix.Http`. The submission-queue pressure it guards against does not exist on the thread models or `.EPOLL`, so the field is inert there.

Enable it by setting a ring length (`0`, off, by default):

```zig
var server = zix.Http1.Server.init(handler, .{
    .ip = "0.0.0.0",
    .port = 8080,
    .dispatch_model = .URING,
    .process_queue_len = 4096,   // per-worker park-ring capacity, 0 = off
});
```

Size the ring to about the peak concurrent connections a single worker handles: one connection parks at most one entry at a time, so the ring never needs more slots than that worker's live connections. A value far above that only reserves a slab that faults resident over time for no gain.

#### When it engages

The ring is a no-op under normal load and does work only when the submission queue is actually saturated.

| Workload | Effect |
| :- | :- |
| Steady low-connection keep-alive | No-op, the submission queue never fills |
| Connection burst above the submission-queue depth (accept storm, churn) | Overflow re-arms parked and retried next pass instead of the connection being dropped |
| Sustained overload past the ring capacity | Reject-newest: the newest entry falls back to the close path while the oldest parked work still drains in arrival order |

#### Rules and sizing

- Opt-in only. `process_queue_len = 0` (default) leaves the ring unallocated and the close-on-full behavior unchanged.
- `.URING` only, and only on `zix.Http1` and `zix.Http`. The other dispatch models and `.EPOLL` never fill a submission queue, so the field is inert.
- Streams never enter the ring. WebSocket, SSE, and gRPC streaming are governed by protocol flow control (HTTP/2 window and `max_streams`, QUIC MAX_DATA and MAX_STREAMS) and shed with the protocol's own signal, not parked.
- Reject-newest. When the ring is full the newest re-arm is refused (the connection closes), so parked work always drains oldest-first and a flood cannot starve earlier connections.
- Per-worker memory is `process_queue_len` times a few bytes per entry (a reference, not a request buffer), times the worker count.
- Sizing: about the peak concurrent connections per worker. Above that the extra slots are unreachable, below it a burst can hit reject-newest sooner.

A related but separate guard covers an oversize request body: on `zix.Http2` a DATA body past the stream buffer is shed with a `413` and END_STREAM (crediting only the connection window), and on `zix.Grpc` with `RESOURCE_EXHAUSTED` trailers, so a body too large to buffer never dispatches truncated.

```mermaid
flowchart TD
    A[recv or send re-arm] --> B{submission queue has space?}
    B -- yes --> S[arm the SQE now]
    B -- no --> C{process_queue_len greater than 0?}
    C -- no --> X[close the connection]
    C -- yes --> D{park ring full?}
    D -- yes --> X
    D -- no --> P[park fd plus generation]
    P --> R[drainParked re-arms in FIFO order next pass]
```

**When to use:** set `process_queue_len` when a `.URING` deployment faces connection bursts or accept storms that can outrun the submission queue (churny short-lived connections, reconnect floods), sized to the peak connections per worker. Leave it off for steady keep-alive load, where the submission queue never fills and the ring never engages.

See `docs/zix-config-en.md` for the field reference.

<br>

### HTTP/2

`zix.Http2` is an HTTP/2 server in its own right: h2c (cleartext) by default, or h2 over TLS when a `Tls.Context` is attached (ALPN negotiates h2, which browsers require for HTTP/2). It is also the h2c transport that `zix.Grpc` runs on.

**When to use:** reach for `zix.Http2` directly when you need raw HTTP/2 framing (h2c or h2-over-TLS) without gRPC semantics, for example an h2 endpoint for a browser or an h2 client. For ordinary web traffic `zix.Http1` / `zix.Http` lead the benchmarks, and for RPC use `zix.Grpc` (which rides this engine).

<br>

#### gRPC h2c

`zix.Grpc` is a gRPC server and client over h2c. Routes are registered at compile time. All 4 RPC types are supported (unary, server streaming, client streaming, bidirectional).

```zig
const std = @import("std");
const zix = @import("zix");

fn sayHelloHandler(
    req: *zix.Grpc.Request,
    res: *zix.Grpc.Response,
    ctx: *zix.Grpc.Context,
) !void {
    _ = ctx;
    const msg = req.recvMessage() orelse {
        res.finish(.INVALID_ARGUMENT, "no message");
        return;
    };
    // decode msg (proto3), encode reply
    var reply: [256]u8 = undefined;
    const n = zix.Grpc.encodeString(1, "Hello!", &reply);
    res.sendMessage("application/grpc+proto", reply[0..n]);
    res.finish(.OK, "");
}

pub fn main(process: std.process.Init) !void {
    var server = zix.Grpc.Server.init(
        zix.Grpc.Router(&[_]zix.Grpc.Route{
            .{ .path = "/helloworld.Greeter/SayHello", .handler = sayHelloHandler },
        }),
        .{
            .io   = process.io,
            .ip   = "127.0.0.1",
            .port = 8083,
        },
    );
    defer server.deinit();
    try server.run();
}
```

```sh
# Test with grpcurl
grpcurl -plaintext -d '{"name":"world"}' 127.0.0.1:8083 helloworld.Greeter/SayHello
```

**HandlerFn:** `fn(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) anyerror!void`

- Path is resolved by the route table before the handler is called.
- `req.recvMessage()` returns each buffered client message or `null` when done.
- `res.sendMessage(content_type, data)` sends a response DATA frame (first call also sends HEADERS).
- `res.finish(status, message)` sends the grpc-status trailer. Must be called exactly once.
- Unary routes (`is_server_streaming = false`, the default) dispatch synchronously on the connection thread. Server-streaming routes require `is_server_streaming = true` on the `Route` entry and each run on a dedicated thread. `Server.init` is gRPC's one deliberate exception to the family's `Server.init(handler, config)` shape: it takes `Router(&routes)` itself (not `.dispatch`), because the engine must see `is_server_streaming` before it decides how to dispatch (measured to matter by a wide per-core RPS margin between sync-inline and task-spawn dispatch).

**GrpcClient:**

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
```

**Minimal protobuf codec** (no codegen required for simple schemas):

```zig
var out: [256]u8 = undefined;
var pos: usize = 0;
pos += zix.Grpc.encodeString(1, "world",  out[pos..]); // field 1: string
pos += zix.Grpc.encodeInt32( 2, 42,       out[pos..]); // field 2: int32
pos += zix.Grpc.encodeDouble(3, 1.5,      out[pos..]); // field 3: double
// send out[0..pos] as the gRPC message payload
```

**Dispatch models:** `.ASYNC`, `.EPOLL`, `.URING` (the last two Linux-only, the field is required with no default). The gRPC EPOLL and URING models are shared-nothing multiplexed event loops: each worker owns a private `SO_REUSEPORT` listener and one epoll instance, and drives many non-blocking h2 connections through a resumable HTTP/2 state machine. `workers` is the worker count (0 = cpu_count). Off Linux, `run()` returns `error.ZixDispatchModelUnsupported`: pick `.ASYNC` there. See [`docs/concurrency-en.md`](docs/concurrency-en.md) for details.

**Context timeout:** Three inputs, tightest wins:

```zig
var server = zix.Grpc.Server.init(
    zix.Grpc.Router(&[_]zix.Grpc.Route{
        // per-route 3s cap, tightens the 5s global cap
        .{ .path = "/helloworld.Greeter/SayHello", .handler = sayHelloHandler, .timeout_ms = 3_000 },
        // per-route 10s cap, global 5s cap still wins. Echo sends N responses so is_server_streaming = true
        .{ .path = "/helloworld.Greeter/Echo", .handler = echoHandler, .timeout_ms = 10_000, .is_server_streaming = true },
    }),
    .{
        .io                = process.io,
        .ip                = "127.0.0.1",
        .port              = 8083,
        .handler_timeout_ms = 5_000, // global cap, also combined with Route.timeout_ms and grpc-timeout header
    },
);
```

Handlers check `ctx.isExpired()` between steps. Override `ctx.deadline_ns` directly for per-call extension: `ctx.deadline_ns = zix.Grpc.wallClockNs() + 30 * std.time.ns_per_s`. The `grpc_timeout.zig` example below shows the full demo.

**Examples:**
- [examples/grpc_server.zig](examples/grpc_server.zig) - gRPC server, dispatch model picked per target
- [examples/grpc_client.zig](examples/grpc_client.zig) - gRPC client: unary and streaming
- [examples/grpc_multi_server.zig](examples/grpc_multi_server.zig) + [examples/grpc_multi_client.zig](examples/grpc_multi_client.zig) - one port, two services
- [examples/grpc_location_server.zig](examples/grpc_location_server.zig) - Location service, dispatch model picked per target
- [examples/grpc_location_client.zig](examples/grpc_location_client.zig) - Location service client
- [examples/grpc_timeout.zig](examples/grpc_timeout.zig) - Context timeout: global, per-route, override

**When to use:** use `zix.Grpc` for internal service-to-service RPC where you want typed methods, streaming, and deadlines without standing up a TLS terminator or sidecar (h2c speaks plaintext on a trusted network). All four RPC shapes multiplex over one connection, so prefer it over hand-rolled TCP framing for structured request/response between your own services. Put a proxy in front (see the TLS proxy doc) when it must cross an untrusted boundary.

See [`docs/hld-grpc-en.md`](docs/hld-grpc-en.md) for full documentation including all 4 RPC type patterns and TLS proxy setup.

<br>

### TLS (https / h2)

The Http1 and Http2 servers serve cleartext by default. Attach a `zix.Tls.Context` to opt into TLS on a gated path, leaving the cleartext engines untouched. The context loads the cert / key and validates the policy once at startup, then every connection reuses it. For Http2 and gRPC the `.EPOLL` / `.URING` models terminate TLS in the dispatch worker and multiplex many connections per core, so https does not spawn a thread per connection.

```zig
var tls = try zix.Tls.Context.init(allocator, io, .{
    .cert_path = "examples/certs/ecdsa_p256_cert.pem",
    .key_path  = "examples/certs/ecdsa_p256_key.pem",
    .alpn      = &.{ .HTTP_1_1 }, // .H2 for the Http2 server
});
defer tls.deinit();

var server = zix.Http1.Server.init(handler, .{ .io = io, .ip = "127.0.0.1", .port = 9060, .tls = &tls, .dispatch_model = .EPOLL });
```

With `tls` set the server is TLS-only on `port`. Add `tls_port` to serve BOTH from one server (the dual listener,): cleartext on `port` and TLS on `tls_port` from the same worker fleet, instead of launching a second server that duplicates workers, fd tables, and caches. Available on Http1, Http, Http2, and Grpc, every dispatch model (under `.URING` the TLS side runs on the ring).

```zig
var server = zix.Http1.Server.init(handler, .{
    .io = io,
    .ip = "127.0.0.1",
    .port = 9076, // cleartext
    .tls = &tls,
    .tls_port = 9077, // https, same workers
    .dispatch_model = .EPOLL,
});
```

The two paths are required, the rest default to a secure posture (TLS 1.2 floor, 1.3 preferred, ECDHE-only). `Tls.Context.Config` also exposes `min_version` / `max_version`, `curves`, `ciphers`, `prefer_server_ciphers`, and `hsts_max_age_s`. Curves and ciphers are validated to the implemented set, so an unsupported value is a startup error. The cert can be ECDSA P-256, Ed25519, or RSA: `Tls.Context.init` detects the key type from the cert (an RSA cert requires TLS 1.3 and signs the CertificateVerify with `rsa_pss_rsae_sha256`). For a new deployment prefer Ed25519 (cheapest handshake signature), then ECDSA P-256, then RSA (use RSA to serve a pre-issued RSA cert). See [docs/zix-deploy-en.md](docs/zix-deploy-en.md) for per-type config snippets and Docker image deployment.

- [examples/tls/tls_http1_basic.zig](examples/tls/tls_http1_basic.zig) - https/1.1
- [examples/tls/tls_http2_basic.zig](examples/tls/tls_http2_basic.zig) - h2 over TLS
- [examples/tls/tls_http1_ed25519.zig](examples/tls/tls_http1_ed25519.zig) - Ed25519 server cert
- [examples/tls/tls_http1_dual.zig](examples/tls/tls_http1_dual.zig) - dual listener (cleartext + https, one server)

<br>

### Raw TCP

`zix.Tcp` is a raw TCP stream server and client. The handler is baked into the server type at `init` and `io` is a config field, so `run()` takes no argument (). The per-connection handler owns the stream and runs under `.ASYNC` / `.EPOLL`. For the completion-based `.URING` ring there is a separate per-frame callback path, `initFramed`. Default frame format: 4-byte big-endian length prefix.

```zig
const std = @import("std");
const zix = @import("zix");

fn myHandler(stream: std.Io.net.Stream, io: std.Io) void {
    defer stream.close(io);
    var rbuf: [4100]u8 = undefined;
    var rdr = stream.reader(io, &rbuf);
    var buf: [4096]u8 = undefined;
    while (true) {
        const len = rdr.interface.takeVarInt(u32, .big, 4) catch return;
        if (len == 0 or len > buf.len) return;
        rdr.interface.readSliceAll(buf[0..len]) catch return;
        const msg = buf[0..len];
        _ = msg; // process msg
        // write response with stream.writer()
    }
}

pub fn main(process: std.process.Init) !void {
    // handler is baked into the server type at init, io lives in config, run() takes no argument
    var server = try zix.Tcp.Server.init(myHandler, .{
        .io   = process.io,
        .ip   = "127.0.0.1",
        .port = 9300,
        .dispatch_model = .ASYNC,
    });
    defer server.deinit();
    try server.run();
    // built-in echo default is explicit: zix.Tcp.Server.init(zix.Tcp.echoHandler, .{ ... })
}
```

**Per-frame callback (`.URING` ring):** when the handler does not need to own the connection, register a `FrameFn` that the engine calls once per decoded frame. This is the only path that runs natively on the io_uring ring:

```zig
fn onFrame(payload: []const u8, fd: std.posix.fd_t) void {
    _ = payload; // engine owns the connection; reply on fd
    _ = fd;
}

var server = try zix.Tcp.Server.initFramed(onFrame, .{
    .io   = process.io,
    .ip   = "127.0.0.1",
    .port = 9304,
    .dispatch_model = .URING,
});
defer server.deinit();
try server.run();
```

**Frame format:** `[u32 big-endian payload_len][payload bytes]`. Both the built-in `echoHandler` and `TcpClient.sendMsg`/`recvMsg` use this format.

**TcpClient:**

```zig
var client = try zix.Tcp.Client.connect(.{
    .ip   = "127.0.0.1",
    .port = 9300,
}, io);
defer client.deinit(io);

try client.sendMsg(io, "hello");
var buf: [4096]u8 = undefined;
const reply = try client.recvMsg(io, &buf);
```

**CLI arg override** (no rebuild needed): `initArgs` / `initFramedArgs` are `init` / `initFramed` plus `--ip` / `--port` parsing from `process.minimal.args`, so one built binary can bind a different address or port. The examples use the plain `init` / `initFramed`. Reach for the `Args` variants only when you want runtime override.

```zig
var server = try zix.Tcp.Server.initArgs(myHandler, .{ .io = process.io, .ip = "127.0.0.1", .port = 9300 }, process.minimal.args);
var client = try zix.Tcp.Client.connectArgs(.{ .ip = "127.0.0.1", .port = 9300 }, io, process.minimal.args);
```

**When to use:** reach for `zix.Tcp` when you own the wire protocol: a custom binary framing, a private RPC, a proxy, or a probe where HTTP/gRPC overhead is unwanted. Use the per-connection handler (`init`) for stateful, request/response or streaming sessions where the handler drives the socket. Use the per-frame `initFramed` callback when the work is stateless per frame and you want the `.URING` ring (engine owns the connection, the callback never blocks). If you only need same-host IPC, prefer `zix.Uds`. If you need request routing or browsers, prefer `zix.Http1` / `zix.Http`.

**Examples:**
- [examples/tcp_server.zig](examples/tcp_server.zig)
- [examples/tcp_client.zig](examples/tcp_client.zig)

[`docs/hld-tcp-en.md`](docs/hld-tcp-en.md) for details.

<br>

### FIX 4.x

`zix.Fix` is a FIX 4.x session layer server and client. SOH-delimited (0x01) framing. Session handling (Logon/Logout/Heartbeat) is built in. Application messages are dispatched to a comptime router or echoed when no routes are registered.

Echo mode (no routing):

```zig
const std = @import("std");
const zix = @import("zix");

pub fn main(process: std.process.Init) !void {
    var server = try zix.Fix.Server.init(null, .{
        .io                   = process.io,
        .ip                   = "127.0.0.1",
        .port                 = 9500,
        .comp_id              = "SERVER",
        .dispatch_model       = .ASYNC,
        .heartbeat_timeout_ms = 30_000, // 0 = disabled (default)
    });
    defer server.deinit();
    try server.run();
}
```

Router mode (application message dispatch):

```zig
fn handleNewOrder(req: *zix.Fix.Request, res: *zix.Fix.Response, ctx: *zix.Fix.Context) !void {
    if (ctx.isExpired()) return;
    const symbol = req.getField(.Symbol) orelse return;
    res.sendMessage(zix.Fix.MsgType.ExecutionReport, &[_]zix.Fix.BuildField{
        .{ .tag = .Symbol, .value = symbol },
        .{ .tag = .OrdStatus, .value = "0" },
    });
}

const router = zix.Fix.Router(&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle, .handler = handleNewOrder, .timeout_ms = 500 },
});

var server = try zix.Fix.Server.init(
    router.dispatch,
    .{
        .io             = process.io,
        .ip             = "0.0.0.0",
        .port           = 9500,
        .comp_id        = "BROKER",
        .dispatch_model = .ASYNC,
        .handler_timeout_ms    = 200,
        .conn_timeout_ms       = 60_000,
    },
);
```

`FixClient`:

```zig
var client = try zix.Fix.Client.connect(.{
    .ip             = "127.0.0.1",
    .port           = 9500,
    .comp_id        = "CLIENT",
    .target_comp_id = "SERVER",
}, io);
defer client.deinit(io);

try client.logon(io, 30);
try client.sendMessage(io, zix.Fix.MsgType.NewOrderSingle, &[_]zix.Fix.BuildField{
    .{ .tag = .ClOrdID,  .value = "order-001" },
    .{ .tag = .Symbol,   .value = "AAPL" },
    .{ .tag = .Side,     .value = "1" },
    .{ .tag = .OrderQty, .value = "100" },
});
const msg = try client.recvMessage(io);
_ = msg;
try client.logout(io);
```

**Session messages handled automatically:**

| MsgType (tag 35) | Server action |
| :- | :- |
| `A` (Logon) | Reply with Logon, CompIDs swapped |
| `5` (Logout) | Reply with Logout, then close |
| `0` (Heartbeat) | Reply with Heartbeat |
| `1` (TestRequest) | Reply with Heartbeat |
| any other (routes non-empty) | Dispatch to matching route handler |
| any other (routes empty) | Echo unchanged |

**`zix.Fix.MsgType`**: namespace struct of 47 compile-time string constants for FIX MsgType values (FIX 4.0-4.4). Use named constants instead of raw strings: `MsgType.NewOrderSingle` (`"D"`), `MsgType.ExecutionReport` (`"8"`), `MsgType.Logon` (`"A"`), etc.

**Dispatch models:** `.ASYNC` (suited to long-lived FIX sessions and the only portable model), `.EPOLL`, `.URING` (both Linux-only: shared-nothing per-core workers). Off Linux, `run()` returns `error.ZixDispatchModelUnsupported`: pick `.ASYNC` there.

**When to use:** use `zix.Fix` when you integrate with financial counterparties over FIX 4.x: order entry, execution reports, market-data sessions. Session mechanics (Logon/Logout/Heartbeat/TestRequest, sequence handling) are built in, so you write only application-message handlers. Use echo mode for a conformance harness and router mode for real trading logic. For any non-financial protocol use `zix.Tcp` instead.

**Examples:**
- [examples/fix_server.zig](examples/fix_server.zig)
- [examples/fix_server_trading.zig](examples/fix_server_trading.zig)
- [examples/fix_client.zig](examples/fix_client.zig)
- [examples/fix_client_raw.zig](examples/fix_client_raw.zig)
- [examples/fix_client_trading.zig](examples/fix_client_trading.zig)

[`docs/hld-fix-en.md`](docs/hld-fix-en.md) for details.

<br>

### UDS (Unix Domain Sockets)

Same-host IPC over a Unix stream socket. The server accepts connections and dispatches each as a concurrent task. Both sides use a 4-byte length-prefixed frame format.

```zig
// Process A: UDS server (data provider)
pub fn main(process: std.process.Init) !void {
    // handler is baked at init, io lives in config, run() takes no argument
    var server = try zix.Uds.Server.init(zix.Uds.echoHandler, .{
        .io        = process.io,
        .path      = "/tmp/app.sock",
        .allocator = std.heap.smp_allocator,
    });
    defer server.deinit();
    try server.run();
    // custom handler: zix.Uds.Server.init(myHandler, .{ .io = process.io, ... })
}
```

```zig
// Process B: UDS client (consumer)
var client = try zix.Uds.Client.connect(.{ .path = "/tmp/app.sock" }, io);
defer client.deinit(io);

try client.sendMsg(io, "get");              // sends [u32 len][payload]
var buf: [4096]u8 = undefined;
const reply = try client.recvMsg(io, &buf); // reads [u32 len][payload]
```

Custom handler: receives the raw stream directly, passed to `init`:

```zig
fn myHandler(stream: std.Io.net.Stream, io: std.Io) void {
    defer stream.close(io);
    // read/write frames using stream.reader() and stream.writer()
}

var server = try zix.Uds.Server.init(myHandler, .{
    .io        = process.io,
    .path      = "/tmp/app.sock",
    .allocator = std.heap.smp_allocator,
});
defer server.deinit();
try server.run();
```

**Frame format:** `[u32 payload_len, big-endian, 4 bytes][payload bytes]`. Frames with payload > `max_recv_buf` (default 4096) close the connection.

**When to use:** choose UDS for same-host IPC between cooperating processes (a sidecar, a local agent, a privileged helper) where you want stream semantics without a TCP port or the network stack. It is faster and more secure than loopback TCP (filesystem permissions guard the socket). Across hosts, use `zix.Tcp`.

**Examples:**
- [examples/uds_server.zig](examples/uds_server.zig) - full working example
- [examples/uds_http.zig](examples/uds_http.zig) - full working example (HTTP over UDS)
- [examples/uds_client.zig](examples/uds_client.zig) - length-prefixed UDS client
- [examples/http_uds_client.zig](examples/http_uds_client.zig) - HTTP/1.1-over-UDS client

[`docs/hld-uds-en.md`](docs/hld-uds-en.md) for details.

<br>

### Channel

Typed, fiber-safe in-process message passing. A buffered ring queue that connects producer and consumer tasks (OS threads or `io.concurrent` fibers) within the same process.

```zig
const MyChan = zix.Channel(u32);

// capacity 8: send blocks when full, recv blocks when empty
var ch = try MyChan.init(std.heap.smp_allocator, 8);
defer ch.deinit();

// producer (runs in its own thread / task)
try ch.send(io, 42);
ch.close(io); // signal done: receivers drain, then get error.ZixClosed

// consumer (runs in its own thread / task)
while (true) {
    const v = ch.recv(io) catch break; // error.ZixClosed when channel is drained and closed
    // process v
}
```

`send` and `recv` require an `io` valid on the calling thread. Each OS thread needs its own `std.Io` (e.g. from `std.Io.Threaded`):

```zig
var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{});
defer threaded.deinit();
const io = threaded.io();

const t = try std.Thread.spawn(.{}, workerFn, .{ &ch, io });
t.join();
```

**Examples:**
- [examples/channel_basic.zig](examples/channel_basic.zig) - producer/consumer: two OS threads, Channel(u32)
- [examples/channel_worker_pool.zig](examples/channel_worker_pool.zig) - fan-out: one producer, many consumer workers
- [examples/channel_pipeline.zig](examples/channel_pipeline.zig) - multi-stage pipeline: backpressure flows upstream
- [examples/channel_ipc_a.zig](examples/channel_ipc_a.zig) + [examples/channel_ipc_b.zig](examples/channel_ipc_b.zig) - inter-process coordination pair
- [examples/uds_http.zig](examples/uds_http.zig) - HTTP + UDS + Channel: full integration pattern

**When to use:** use a `Channel` to hand typed messages between tasks inside one process: producer/consumer, fan-out worker pools, or backpressured pipelines. The bounded ring applies backpressure for you (send blocks when full), which makes it the right primitive for decoupling a fast producer from slower consumers. For cross-process messaging, pair it with UDS.

For design details see [`docs/hld-channel-en.md`](docs/hld-channel-en.md).

<br>

### UDP

Two modes. The typed `zix.Udp.Server(Packet)` is a type-safe messaging server: the user defines their own `extern struct` packet, and zix handles endianness, size validation, and concurrency. The raw `zix.Udp.Raw(handler)` serves variable-length datagrams with no fixed struct, with `recvmmsg` / `sendmmsg` batching and per-core SO_REUSEPORT workers.

```zig
const std = @import("std");
const zix = @import("zix");

const Packet = extern struct {
    id:       [16]u8,
    kind:     i32,
    register: u32,
    position: [3]f64,
};

const MyServer = zix.Udp.Server(Packet);

pub fn main(process: std.process.Init) !void {
    // Pass process.minimal.args and set .allow_args = true to read --ip / --port overrides.
    var server = try MyServer.init(.{
        .io         = process.io,
        .allocator  = std.heap.smp_allocator,
        .ip         = "127.0.0.1",
        .port       = 9100,
        .dispatch_model = .ASYNC, // typed server runs a single async loop
        .endianness = .LITTLE,
        .broadcast  = true,   // relay each packet to all connected clients
        .auto_ack   = false,
        .conn_timeout_ms = 5000,
        .poll_timeout_ms = 2000,
    }, .{});
    defer server.deinit();
    try server.run();
}
```

Client (concurrent send + receive):

```zig
const MyClient = zix.Udp.Client(Packet);

pub fn main(process: std.process.Init) !void {
    const io = process.io;
    // Pass process.minimal.args and set .allow_args = true to read
    // --bind-ip / --bind-port / --server-port overrides.
    var client = try MyClient.init(.{
        .ip          = "127.0.0.1", // server address
        .server_port = 9100,
        .bind_port   = 9101,
        .endianness  = .LITTLE,
    }, io, .{});
    defer client.deinit();

    // spawn receive task alongside send loop
    _ = io.concurrent(receiveLoop, .{&client}) catch {};

    const p = Packet{ .id = [_]u8{0} ** 16, .kind = 1, .register = 0, .position = .{ 0.0, 0.0, 0.0 } };
    while (true) {
        client.send(p) catch {};
        try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(1000), .awake);
    }
}
```

Raw-bytes mode (variable-length datagrams, no fixed struct):

```zig
fn handler(dg: []const u8, peer: *const std.Io.net.IpAddress, sink: *zix.Udp.Sink) void {
    sink.reply(dg); // echo back to the sender
}

const Echo = zix.Udp.Raw(handler);

pub fn main(process: std.process.Init) !void {
    var server = try Echo.init(.{
        .io        = process.io,
        .allocator = std.heap.smp_allocator,
        .ip        = "0.0.0.0",
        .port      = 9064,
        .dispatch_model = .EPOLL, // per-core SO_REUSEPORT workers (.ASYNC = single worker)
    }, .{});
    defer server.deinit();
    try server.run();
}
```

**When to use:** reach for UDP when you want low-latency, fire-and-forget datagrams: telemetry, game state, discovery, heartbeats, or broadcast/relay to many peers, accepting best-effort delivery. Use the typed `Server(Packet)` for a fixed `extern struct` contract, the raw `Raw(handler)` for arbitrary byte payloads and the batched per-core path. If you need ordering, retransmission, or large payloads, use `zix.Tcp` instead.

**Examples:**
- [examples/udp_server.zig](examples/udp_server.zig) - typed server, full working example with broadcast and configurable ports
- [examples/udp_client.zig](examples/udp_client.zig) - matching client
- [examples/udp_server_raw.zig](examples/udp_server_raw.zig) - raw-bytes echo server (recvmmsg / sendmmsg batching, dispatch models)
- [examples/udp_server_tickrate.zig](examples/udp_server_tickrate.zig) - game-server-like tick loop on the raw path, broadcasts a world snapshot per tick (--tickrate, 64 or 128)
- [examples/udp_client_tickrate.zig](examples/udp_client_tickrate.zig) - matching client, run several instances with distinct --bind-port values

[`docs/hld-udp-en.md`](docs/hld-udp-en.md) for details.

<br>

### HTTP/3

HTTP/3 runs over QUIC, which runs over UDP, so `zix.Http3` sits on the same `zix.Udp` datagram substrate above, not on the TCP / TLS stack. It is a pure-Zig HTTP/3 server over QUIC (RFC 9114 / 9000 / 9001 / 9002). The QUIC transport, packet protection, TLS 1.3 handshake glue, and QPACK header compression are all written from the RFCs and proven byte-exact against the RFC worked examples. TLS 1.3 is folded into the QUIC handshake (there is no cleartext mode and no TLS record layer), configured by the same `zix.Tls.Context` as the TCP engines, so an ECDSA P-256, Ed25519, or RSA cert all work.

Routes are a comptime table (`zix.Http3.Router`), the same shape as `zix.Http1` / `zix.Http2`, dispatched on the decoded request path.

```zig
const std = @import("std");
const zix = @import("zix");

fn home(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.send("hello over http/3\n");
}

const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
    .{ .path = "/", .handler = home },
});

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = "examples/certs/ecdsa_p256_cert.pem",
        .key_path  = "examples/certs/ecdsa_p256_key.pem",
    });
    defer tls.deinit();

    var server = zix.Http3.Server.init(Routes.dispatch, .{
        .io             = process.io,
        .allocator      = std.heap.smp_allocator,
        .ip             = "127.0.0.1",
        .port           = 9063,
        .dispatch_model = .ASYNC,
        .tls            = &tls,
    });
    defer server.deinit();

    try server.run();
}
```

```sh
# Test with a curl built with HTTP/3 (run from the repo root so the cert path resolves)
curl --http3-only -k https://127.0.0.1:9063/
```

**HandlerFn:** `fn(req: *const zix.Http3.Request, res: *zix.Http3.Response, ctx: *zix.Http3.Context) anyerror!void`

- `req.method` and `req.path` are populated from the wire. The response body handed to `res.send` is copied after the handler returns, so it may point at static or handler-owned memory.
- `req.body` carries the request body, with `req.bodyReceived()` for how many body bytes arrived and `req.bodyComplete()` for whether that is all of it, the same pair as `zix.Http1`. A request with a body rarely arrives in one packet, so the engine holds it until the client ends its QUIC stream and runs the handler once, with the whole body. `max_request_stream_bytes` (8192 by default) is the largest body a handler can be given whole: raise it to the largest upload the routes accept. Past it the body is delivered cut and reads false, so a handler can refuse a fragment instead of parsing one. When every one of the worker's `max_pending_request_streams` slots is busy with a request still arriving, a new one is answered 503 rather than run against a body the engine knows it is missing. The slice borrows the decode buffer, so copy it to keep it past the handler call.
- `req.accept_encoding` carries the client's Accept-Encoding (empty when absent). A handler negotiates a pre-compressed body against it and calls `res.setContentEncoding(.br)` (or `.gzip`), which emits the `content-encoding` response header. The engine never compresses on the send path: `res.body` must already be encoded (serve a pre-built `.br` / `.gz` file), so there is no per-request codec cost.
- `ctx` carries `stream_id` (the raw escape hatch, QUIC has no per-request fd), `io`, a per-request arena allocator, and the timeout helpers (`withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut`), same shape as every other engine. A handler error auto-completes as one 500 when nothing was sent yet (`res.sent`).
- `run()` requires a non-zero port and a TLS context: it returns `error.ZixPortNotConfigured` or `error.ZixTlsRequired` otherwise (`init` only stores the config).

**Dispatch models:** `.ASYNC` runs one single-worker recv loop with internal connection-id demux (migration-safe). `.EPOLL` / `.URING` run one SO_REUSEPORT worker per core with epoll readiness or io_uring completion on top (`.URING` folds to the epoll worker loop when io_uring is unavailable), and are Linux-only. Per-core connection-id steering is deferred (phase 3).

**Example:** [examples/tls/http3_basic.zig](examples/tls/http3_basic.zig) (port 9063) serves `/`, a query-sum `/baseline2`, a 256 KiB `/big` that exercises the multi-packet streamed send path, a `/negotiated` that serves a brotli-precompressed body with `content-encoding: br` when the client accepts br, and an `/echo` that answers a POST with the byte count it received, whether that was the whole body, and the body itself.

See [`docs/hld-http3-en.md`](docs/hld-http3-en.md) and [`docs/lld-http3-en.md`](docs/lld-http3-en.md) for the full design and per-layer internals.

<br>

### WebTransport

`zix.Webtransport` is WebTransport over HTTP/3, served by `zix.Http3` on the QUIC connection it already owns: a browser (or any WebTransport client) opens a session with an extended CONNECT (RFC 9220) and then uses reliable data streams and unreliable datagrams on that one connection, alongside ordinary HTTP/3 requests. Pure-Zig from the drafts, with no library in the loop.

Two revisions are accepted at once. draft-ietf-webtrans-http3-16 is the current one (token `webtransport-h3`, `SETTINGS_WT_ENABLED` 0x2c7cf000, session-level flow control, `RESET_STREAM_AT` on a stream reset), and the deployed draft-07 (token `webtransport`, `SETTINGS_ENABLE_WEBTRANSPORT` 0x2b603742) is what browsers and aioquic still send. The server advertises both in one SETTINGS frame, and the CONNECT `:protocol` token decides which one the session speaks.

```zig
const std = @import("std");
const zix = @import("zix");

// A plain HTTP/3 route: WebTransport sessions and ordinary requests share one connection.
fn home(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.send("hello over http/3\n");
}

/// Decide a session: null accepts, a status refuses it.
fn onSession(session: *zix.Webtransport.Session) ?u16 {
    const request = session.sessionRequest();
    if (!std.mem.eql(u8, request.path, "/echo")) return 404;

    // A unidirectional stream the server opens for this session.
    if (session.openUni()) |stream| {
        _ = stream.write("hello from zix\n");
        stream.finish();
    }

    return null;
}

/// Echo whatever arrives on a data stream. A short write is normal back pressure.
fn onStream(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    _ = session;
    _ = stream.write(stream.read());
    stream.finish();
}

/// Echo a datagram. A datagram is never queued: false means it did not go.
fn onDatagram(session: *zix.Webtransport.Session, datagram: []const u8) void {
    _ = session.sendDatagram(datagram);
}

fn onClose(session: *zix.Webtransport.Session) void {
    const info = session.closeInfo();
    std.log.info("session {d} closed: {s} code={d}", .{ session.id(), @tagName(info.reason), info.code });
}

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = "examples/certs/ecdsa_p256_cert.pem",
        .key_path  = "examples/certs/ecdsa_p256_key.pem",
    });
    defer tls.deinit();

    const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
        .{ .path = "/", .handler = home },
    });

    var server = zix.Http3.Server.init(Routes.dispatch, .{
        .io             = process.io,
        .allocator      = std.heap.smp_allocator,
        .ip             = "127.0.0.1",
        .port           = 9089,
        .dispatch_model = .ASYNC,
        .tls            = &tls,
        .webtransport = .{
            .enabled = true,
            .max_sessions_per_connection = 4,
            .max_streams_bidi = 16,
            .max_streams_uni = 16,
            .max_session_data = 1 << 20,
            .handler = .{
                .on_session = onSession,
                .on_stream = onStream,
                .on_datagram = onDatagram,
                .on_close = onClose,
            },
        },
    });
    defer server.deinit();

    try server.run();
}
```

**Handler:** five optional callbacks. `on_session` decides a CONNECT (null accepts, an HTTP status refuses, and the engine answers the request stream either way), `on_stream` gets a data stream chunk, `on_stream_reset` gets a stream the peer aborted, `on_datagram` gets one datagram with its routing already stripped, and `on_close` gets the session after it ended.

- `Session` answers through `openBidi`, `openUni`, `sendDatagram`, `close`, and `drain`, and reports `id()`, `dialect()`, `state()`, `isOpen()`, `sessionRequest()`, `streamsAvailable(kind)`, and `closeInfo()`. `Stream` answers through `write`, `finish`, `reset`, and `stop`, and reports `id()`, `kind()`, `initiator()`, `read()`, `chunk_offset`, `finished()`, `resetCode()`, and `writable()`.
- Lifetimes follow the rest of zix: a session, a stream, and every slice they hand over are valid for the callback that produced them. An application that needs the bytes later copies them, and a handle captured past its callback is inert rather than dangling.
- A short `write` is back pressure, not an error: the peer has not acknowledged what is queued, so the remainder goes out from the next callback. `sendDatagram` returns false when the datagram could not go now (no datagram negotiation, payload past the peer's frame limit, or no congestion-window room) and never queues it for later.
- Callbacks arrive on the worker that owns the QUIC connection, one datagram at a time, so a handler runs single-threaded per connection and needs no lock. The dispatcher is the HTTP/3 one, unchanged.
- Limits are advertised and enforced: `max_sessions_per_connection` (429 when reached, 503 when the worker pool has no slot), `max_streams_bidi` / `max_streams_uni` per session, `max_session_data` for the session-level byte budget, `stream_send_bytes` as the per-stream write window, and `max_datagram_frame_size` for both directions. A pre-session stream past the worker's buffer is reset with `WT_BUFFERED_STREAM_REJECTED`, and every stream of a closing session is reset with `WT_SESSION_GONE`.
- `legacy_dialect = false` accepts only the current revision. Turn it off only when every client is known to speak it, since every shipping browser still sends the deployed token.
- Origin validation is the application's: the engine hands `on_session` the request's `origin` (a browser always sends one) and does not invent a policy.

**Example:** [examples/tls/http3_webtransport.zig](examples/tls/http3_webtransport.zig) (port 9089) accepts sessions on `/echo`, echoes every data-stream chunk and every datagram, opens one unidirectional stream per session with a banner, and prints the session lifecycle on stderr. Built with `zig build example-http3_webtransport`. Drive it with any WebTransport over HTTP/3 client, and `zig build test-runner-webtransport` drives it end to end from the in-tree client.

See [`docs/hld-webtransport-en.md`](docs/hld-webtransport-en.md) and [`docs/lld-webtransport-en.md`](docs/lld-webtransport-en.md) for the full design and per-file internals.

<br>

### WebRTC

`zix.Webrtc` is a WebRTC peer, which is what lets a browser reach the server over something other than HTTP or WebSocket: unreliable delivery, a per-channel ordering choice, and audio and video. Everything arrives on one UDP port and is sorted by its first byte (RFC 7983): ICE connectivity checks carried over STUN, the DTLS 1.2 handshake, the SCTP association and its data channels, and optionally SRTP media. All of it is written from the RFCs, with `std.crypto` underneath and no OpenSSL.

zix answers, it never gathers. The ICE agent is lite and the DTLS role is always server, which is what fixes data channels to odd stream identifiers.

```zig
const std = @import("std");
const zix = @import("zix");

fn onEvent(event: zix.Webrtc.Event, ctx: *zix.Webrtc.Context) !void {
    switch (event) {
        .CHANNEL_OPEN => |channel| std.log.info("channel {d} open", .{channel}),
        .CHANNEL_CLOSED => |channel| std.log.info("channel {d} closed", .{channel}),
        .MESSAGE => |message| try ctx.send(message.channel, message.kind, message.payload),
    }
}

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = "examples/certs/ecdsa_p256_cert.pem",
        .key_path  = "examples/certs/ecdsa_p256_key.pem",
    });
    defer tls.deinit();

    var server = zix.Webrtc.Server.init(onEvent, .{
        .io             = process.io,
        .allocator      = std.heap.smp_allocator,
        .ip             = "127.0.0.1",
        .port           = 9083,
        .dispatch_model = .ASYNC,
        .ice_ufrag      = "zixanswer",
        .ice_password   = "zixanswerpasswordaaaaaa",
        .peer_ice_ufrag = "zixdialer",
        .tls            = &tls,
    });
    defer server.deinit();

    try server.run();
}
```

**HandlerFn:** `fn(event: zix.Webrtc.Event, ctx: *zix.Webrtc.Context) anyerror!void`

- Three events: `CHANNEL_OPEN` and `CHANNEL_CLOSED` carry a stream identifier, `MESSAGE` carries `channel`, `kind` and `payload`. A `payload` is borrowed for the length of the call and dies on the next one, so anything worth keeping has to be copied out.
- `ctx` answers: `send(channel, kind, bytes)`, `broadcast(kind, bytes)`, `openChannel(request)`, `close(channel)`, `channelCount()`. The reach of `broadcast` is one worker, which is the whole room under `.ASYNC` and this core's share under `.EPOLL` or `.URING`.
- `run()` validates before it binds: `error.ZixPortNotConfigured`, `error.ZixIceCredentialsRequired`, `error.ZixIceCredentialsInvalid`, `error.ZixTlsRequired`, `error.ZixUnsupportedCertificateKey` (the key must be ECDSA P-256), and `error.ZixDispatchModelUnsupported` off Linux.
- A browser draws a fresh ICE ufrag for every peer connection, so a browser-facing server sets `accept_any_peer_ice_ufrag = true` and lets `ice_password` be the gate.

**Dispatch models:** `.ASYNC` runs one worker and runs everywhere. `.EPOLL` and `.URING` run one SO_REUSEPORT worker per core and are Linux-only. There is deliberately no CPU steering knob here: a WebRTC peer is its 4-tuple, and steering would split one session across two workers mid-handshake.

**Media:** off by default. With `carry_media` on, the server forwards audio and video between its peers without decoding a frame: a packet is opened once with the sender's key, its RTP header is rewritten per receiver, and it is sealed again under each receiver's key. RTCP is answered, never forwarded.

**Examples:** eight, on ports 9081 to 9088.

| Example | Port | What it shows |
| :- | :- | :- |
| [webrtc_signaling](examples/webrtc/webrtc_signaling.zig) | 9081 | a WebSocket room relay, zix is not a peer |
| [webrtc_stun](examples/webrtc/webrtc_stun.zig) | 9082 | a STUN binding server plus a page that reads its own reflexive address |
| [webrtc_datachannel_echo](examples/webrtc/webrtc_datachannel_echo.zig) | 9083 | the smallest server, echoes what a peer sends |
| [webrtc_native_pair](examples/webrtc/webrtc_native_pair.zig) | dials 9083 | zix dialing zix, no browser involved |
| [webrtc_datachannel_chat](examples/webrtc/webrtc_datachannel_chat.zig) | 9085 | one message to every other browser in the room |
| [webrtc_file_transfer](examples/webrtc/webrtc_file_transfer.zig) | 9086 | a binary channel carrying a file |
| [webrtc_sfu_broadcast](examples/webrtc/webrtc_sfu_broadcast.zig) | 9087 | the forwarding unit, one sender and many watchers |
| [webrtc_video_call](examples/webrtc/webrtc_video_call.zig) | 9088 | a mesh call through the relay, zix carries no media |

Load the browser pages by the machine's network address, not `localhost`: a browser gathers no loopback candidate and will not pair with one. `webrtc_sfu_broadcast` is the exception, because its sender page also needs a secure context for the camera, so it stays on `http://localhost` and asks for the address to publish through a `?at=` query parameter.

See [`docs/hld-webrtc-en.md`](docs/hld-webrtc-en.md) and [`docs/lld-webrtc-en.md`](docs/lld-webrtc-en.md) for the full design and per-layer internals.

<br>

### Logger

Structured file logger with automatic per-protocol event logging. Thread-safe: safe to call from background OS threads.

```zig
const std = @import("std");
const zix = @import("zix");

// Logger does not create save_path automatically, caller's responsibility.
// Silently ignores "already exists", safe to call on every start.
fn createLogDir(io: std.Io) void {
    std.Io.Dir.cwd().createDirPath(io, "./logs") catch {};
}

pub fn main(process: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();

    createLogDir(process.io);

    var logger = try zix.Logger.init(arena.allocator(), .{
        .save_path      = "./logs",
        .save_file      = "app",
        .save_min_level = .INFO,
        .console        = .ALWAYS,
    });
    defer logger.deinit();

    // System event: any component, any level
    logger.system(.INFO,  "startup", "listening on {d}", .{9000});
    logger.system(.ERROR, "db",      "connect failed: {}", .{error.ConnectionRefused});

    // Wire into HTTP server for automatic per-request access logging
    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io     = process.io,
        .ip     = "127.0.0.1",
        .port   = 9000,
        .logger = &logger,
    });
    defer server.deinit();
    try server.run();
}
```

Log files are written to `save_path/YYYY-MM-DD/save_file-NNNNNN.log`. Each line is a newline-terminated record:

```
# System event format:
2026-05-16 12:34:56.789 INFO   [startup] listening on 9000
2026-05-16 12:34:56.789 ERROR  [db] connect failed: ConnectionRefused

# HTTP access format (2xx/3xx=INFO, 4xx=WARN, 5xx=ERROR, other=DEBUG):
2026-05-16 12:34:56.789 INFO   GET /api/users 200 512 "MyBot/2.0" "http://example.com"
2026-05-16 12:34:56.789 WARN   GET /missing 404 0 "-" "-"
2026-05-16 12:34:56.789 ERROR  POST /crash 500 0 "-" "-"

# gRPC stream close:
2026-05-25 10:15:33.201 INFO   [grpc:rpc] 127.0.0.1:56789 /helloworld.Greeter/SayHello status=0 recv=16 sent=22 dur=1ms
```

| Config field | Default | Description |
| :- | :- | :- |
| `console` | `.OFF` | Console mode: `.OFF`, `.DEBUG_ONLY` (debug builds only), `.ALWAYS` |
| `console_min_level` | `.INFO` | Minimum level for console output |
| `save_path` | `""` | Directory root for log files. Must already exist. `""` disables file logging |
| `save_file` | `"log"` | Base filename. `"log"` writes `log-000000.log`, `log-000001.log`, ... |
| `save_min_level` | `.INFO` | Minimum level for file output |
| `max_lines` | 1,000,000 | Lines per file before rotating to the next sequence number |

**Per-protocol log methods:**

| Method | Auto-called by | Line format |
| :- | :- | :- |
| `system(level, component, fmt, args)` | all servers (lifecycle) | `DATE TIME LEVEL  [component] message` |
| `access(method, path, status, bytes, ua, origin)` | HTTP server | `DATE TIME LEVEL  METHOD PATH STATUS BYTES "UA" "ORIGIN"` |
| `conn(peer, dur_ms, err)` | TCP server | `DATE TIME LEVEL  [tcp:conn] PEER dur=NNNms ERR` |
| `packet(dir, peer, size, err)` | UDP server | `DATE TIME LEVEL  [udp:pkt] DIRECTION PEER size=N ERR` |
| `frame(dir, sock_path, size, err)` | UDS (manual) | `DATE TIME LEVEL  [uds:frame] DIRECTION SOCKPATH size=N ERR` |
| `session(msg_type, sender, target, seq, state)` | FIX server | `DATE TIME LEVEL  [fix:sess] 35=TYPE sender=S target=T seq=N STATE` |
| `rpc(peer, path, grpc_status, recv, sent, dur_ms)` | gRPC server | `DATE TIME LEVEL  [grpc:rpc] PEER PATH status=N recv=N sent=N dur=Nms` |

Levels: `.DEBUG`(0) `.INFO`(1) `.WARN`(2) `.ERROR`(3). The file backend uses a 64 KB write buffer flushed on date rollover, sequence rotation, explicit `logger.flush()`, or `logger.deinit()`.

Wire a logger into any server by setting `logger: &logger` in its config. See [`docs/hld-logger-en.md`](docs/hld-logger-en.md) for full documentation.

**When to use:** wire a `Logger` into any server in production for structured, rotating file logs with per-protocol event lines, and call `logger.system()` for your own lifecycle and error events. Console modes keep development output readable while files stay authoritative. It is safe to call from background OS threads, so one logger can serve the whole process.

<br>

### JSON (jzon)

`zix.jzon` is JSON in both directions, written on the standard library. Two calls carry it: `serialize` turns a typed value into JSON text, `deserialize` turns JSON text back into a typed value. A render allocates nothing, it is handed a buffer and returns how many bytes it used. A parse allocates only what the result points at, out of the allocator handed in, so an arena reset frees a whole parse in one step.

```zig
const std = @import("std");
const zix = @import("zix");

const Order = struct {
    id: u64,
    customer: []const u8,
    tags: []const []const u8,
};

// serialize: no allocator, the buffer is the whole budget
var buf: [256]u8 = undefined;
const len = try zix.jzon.serialize(&buf, Order{
    .id       = 7,
    .customer = "Rekha Nair",
    .tags     = &.{ "priority", "gift" },
}, .{});
// buf[0..len] is {"id":7,"customer":"Rekha Nair","tags":["priority","gift"]}

// deserialize: everything the result points at comes from this allocator
var arena: std.heap.ArenaAllocator = .init(std.heap.smp_allocator);
defer arena.deinit();

const order = try zix.jzon.deserialize(Order, arena.allocator(), buf[0..len], .{});
```

Both calls take a comptime options struct naming which path runs. Every write path renders the same bytes and every read path reads back the same value, so a strategy is a cost decision and nothing else, changed at the call site with no other line moving. Because it is comptime, only the path named is compiled into the binary.

**Write strategies (`zix.jzon.SerializeStrategy`):**

| Strategy | What it runs |
| :- | :- |
| `.STD` | `std.json.Stringify`, which renders every shape std renders |
| `.GENERATED_FMT` | generated from the type, integers through `std.fmt` |
| `.GENERATED` | generated from the type, integer digits written straight into the buffer |
| `.GENERATED_VECTOR` | as `.GENERATED`, with strings scanned one vector lane at a time |

**Read strategies (`zix.jzon.DeserializeStrategy`):**

| Strategy | What it runs |
| :- | :- |
| `.STD` | `std.json` reflection, which parses every shape std parses |
| `.SCANNER` | tokens from `std.json.Scanner`, with the field dispatch generated from the type |
| `.GENERATED` | generated from the type, over jzon's own read cursor, one byte at a time |
| `.GENERATED_VECTOR` | as `.GENERATED`, one vector lane at a time |

`.GENERATED_VECTOR` is not always the quickest. It pays on documents that arrive laid out with whitespace or carry long strings, and costs on minified traffic with short fields, which is why it stays a call-site choice rather than a default.

**Read options (`zix.jzon.DeserializeOptions`):**

| Field | Default | What it decides |
| :- | :- | :- |
| `strategy` | `.STD` | which read path runs |
| `strings` | `.COPY` | `.COPY` copies every string into the allocator, `.BORROW` points a string with no escape at the document, which then has to outlive the value |
| `unknown` | `.REJECT` | `.REJECT` fails on a key the type does not declare, `.SKIP` steps over the key and its whole value however deep it nests |

**Errors:** a render reports `error.NoSpaceLeft` and nothing else. A parse reports one set whichever path ran: `UnknownField`, `MissingField`, `UnknownEnumValue`, `Truncated`, `Unexpected`, `BadNumber`, `BadEscape`, `OutOfMemory`.

A field type a generated path has no JSON form for is a compile error naming the type, never a runtime failure, and `.STD` still takes that shape.

**Examples:** six, none of them a server, so each runs and exits. jzon is a standalone package under `src/jzon` with its own `build.zig`, so build them from there with `zig build examples` (or `zig build jzon-examples` from the repo root).

| Example | What it shows |
| :- | :- |
| [serialize](src/jzon/examples/serialize.zig) | a value into a fixed buffer, every write strategy, and what a buffer too small reports |
| [deserialize](src/jzon/examples/deserialize.zig) | a request body into a typed value on an arena, every read strategy, reset between bodies |
| [strings](src/jzon/examples/strings.zig) | `.COPY` against `.BORROW`, and what borrowing asks of the document's lifetime |
| [unknown_keys](src/jzon/examples/unknown_keys.zig) | `.REJECT` against `.SKIP` on a document carrying more than the type declares |
| [bench_serialize](src/jzon/examples/bench_serialize.zig) | what each write strategy costs per render, against the default's rate |
| [bench_deserialize](src/jzon/examples/bench_deserialize.zig) | what each read strategy costs per parse, on a minified document and a laid-out one |

The two bench examples want `-Doptimize=ReleaseFast`. A Debug build measures the safety checks rather than the paths, and the rows collapse onto each other.

A fifth example is a server, so it lives with the engine examples rather than in the package and is built from the repo root with `zig build example-http1_jzon`.

| Example | What it shows |
| :- | :- |
| [http1_jzon](examples/http1_jzon.zig) | an HTTP/1.1 route reading a JSON body into a record on the per-request arena and answering with a record rendered into a stack buffer, nothing allocated on the response path |

| Document | Description |
| :- | :- |
| [`docs/jzon/README-en.md`](docs/jzon/README-en.md) | jzon: import, quickstart both directions, strategies, options, type coverage, errors, testing |
| [`docs/jzon/hld-en.md`](docs/jzon/hld-en.md) | jzon: layers, components, the write and read flows, allocation model, error model |
| [`docs/jzon/lld-en.md`](docs/jzon/lld-en.md) | jzon: cursors, escape rules, the vector scan, number paths, field bookkeeping, the differences from the default path |
| [`docs/jzon/benchmark-en.md`](docs/jzon/benchmark-en.md) | jzon: what each path costs per render and per parse, with the method and the system it was measured on |

**When to use:** reach for `.{}` first, which is the std-backed path and takes every shape std takes. Move a hot handler to `.GENERATED` when the shape is a plain record and the parse or the render is on the request path, and add `.strings = .BORROW` when the value dies with the buffer it was read out of.

<br>

## Drivers

Database and metrics drivers, written in pure Zig on the standard library like the engines. Each lives under `src/driver/<name>/` with its own build, examples, and container-backed test suites, and initializes from a URL string or a config struct.

| Driver | Description |
| :- | :- |
| [`postgrez`](docs/driver/postgrez/README-en.md) | PostgreSQL: prepared statements, pipelining, COPY, LISTEN and NOTIFY, pool, executor, TLS 1.3 |
| [`rediz`](docs/driver/rediz/README-en.md) | Redis: RESP3 with an in-place RESP2 fallback, pipelining, deferred write-behind, pool, TLS 1.3 |
| [`prometheuz`](docs/driver/prometheuz/README-en.md) | Prometheus: scrape, remote write, PromQL instant and range query |

Each linked README covers install, quickstart, both init styles, and points to its own hld, lld, and config docs.

<br>

## zixer

`zixer` is the proxy gateway that ships with the engines. It is a program you run, not a library you link: every behavior comes from plain text config files, so a service goes behind it without a line of code. One daemon holds every site, and a site is one file naming an engine, a port, and where the traffic goes.

```
engine: http1
ip: 0.0.0.0
port: 443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000
```

```bash
zig build zixer            # builds zig-out/bin/zixer-<arch>-<os>-<optimize>
zixer init                 # scaffold the root dir: main.cfg, sites/, logs/
zixer status               # validate every config, exit 1 on any fault
zixer start example.cfg    # spawns the daemon when none is running
zixer restart example.cfg  # re-read one site file, what a certbot deploy hook calls
zixer daemon stop          # unbind every site and exit
```

The `engine` key picks the edge, and every engine except `udp` re-originates the request rather than forwarding it byte for byte:

| Engine | Client side | Upstream leg |
| :- | :- | :- |
| http1 | HTTP/1.1, optional TLS, websocket upgrade, SSE, static files | HTTP/1.1, keep-alive |
| http2 | h2 with a prior-knowledge sniff, rfc 8441 websocket | HTTP/1.1 per stream |
| grpc | h2 only | h2, so trailers survive the hop |
| http3 | QUIC and HTTP/3, TLS always | HTTP/1.1 |
| udp | raw datagrams, one flow per client | raw datagrams |

| Document | Description |
| :- | :- |
| [`docs/zixer/README-en.md`](docs/zixer/README-en.md) | zixer: build, quickstart, root dir, commands, site keys, what each engine does at the edge |
| [`docs/zixer/how-to-use-en.md`](docs/zixer/how-to-use-en.md) | zixer: build, first site, one recipe per shape, certbot renewal, troubleshooting |
| [`docs/zixer/config-en.md`](docs/zixer/config-en.md) | zixer config reference: every main.cfg and site key, defaults, cross-field rules, fault texts |
| [`docs/zixer/hld-en.md`](docs/zixer/hld-en.md) | zixer: process model, components, site lifecycle, engines, concurrency model, TLS and ACME |
| [`docs/zixer/lld-en.md`](docs/zixer/lld-en.md) | zixer: config grammar, control wire, registry rules, per-edge internals, fixed limits |

Runnable demos for every shape live in [`examples/proxies/`](examples/proxies/README-en.md), one upstream plus one site config each, and `zig build zixer-test-runner-all` drives all 15, each in its own throwaway root and its own bounded child process.

**When to use:** put it in front of services you already run when you want TLS termination, static files, round-robin upstreams, or a protocol change at the edge, and you want that described in a file rather than written in code. Reach for the engines directly instead when the behavior belongs inside your own program.

<br>

## Summary

```
A surgical backend library & engine with wiring tools.
That will bring you performance, efficiency, & transparency.
```

<br>

## AI Policies

- __*You can use it as your own tool.*__
- __*Issue & Pull Request must made on your behalf.*__
- __*The last decision and judgement it's on our end (you and maintainers).*__

<br>

---

###### end of readme
