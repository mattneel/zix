# CHANGELOG

<!--
IMPORTANT:
- Do not remove this
- Naming file is always based on year
- The latest is always on top, bottom next is previous change
- Format:
```
## MAJOR.MINOR.PATCH (YYYY-MM-DD)

__**Update:**__

- Foo

- Bar:
    - Baz

    ---

- Qux:
    - Quux

<br>

__**Fix:**__

- ISSUE_FIX_SHORT_NAME:
    - ISSUE_LINK
    - SHORT_SUMMARY
    - PROFILE_CONTRIBUTOR:
        - NAME_OR_USERNAME / PROFILE_LINK

    ---

- SAME_AS_ABOVE:
    - BUT JUST ONE

<br>

## PREVIOUS_CHANGELOG
...
```
-->

<br>

## X.Y.Z (YYYY-MM-DD)

### __**New Features:**__

#### New Module: `zix.Webtransport` (WebTransport over HTTP/3)

WebTransport over HTTP/3 as a feature of `zix.Http3` (ADR-069), served on the QUIC connection the engine already owns. Turns on with `Http3ServerConfig.webtransport`, and an ordinary HTTP/3 request keeps being served on the same connection.

- **Two dialects on the wire, both accepted.** draft-ietf-webtrans-http3-16 (token `webtransport-h3`, `SETTINGS_WT_ENABLED` 0x2c7cf000, session-level flow control, `RESET_STREAM_AT` on a stream reset) and the deployed draft-07 (token `webtransport`, `SETTINGS_ENABLE_WEBTRANSPORT` 0x2b603742, `SETTINGS_WEBTRANSPORT_MAX_SESSIONS` 0xc671706a) that browsers and aioquic still send. The server advertises both codepoints in one SETTINGS frame, and the CONNECT `:protocol` token picks the session's dialect.
- **Public API `zix.Webtransport`:** `Config` on the HTTP/3 server, `Handler` with five optional callbacks (`on_session`, `on_stream`, `on_stream_reset`, `on_datagram`, `on_close`), and two handles, `Session` (`openBidi`, `openUni`, `sendDatagram`, `close`, `drain`, `streamsAvailable`, `closeInfo`) and `Stream` (`read`, `write`, `finish`, `reset`, `stop`). A handler never names a stream id, a frame, or a capsule.
- **Wire:** extended CONNECT over HTTP/3 (RFC 9220) opens the session, the capsule protocol (RFC 9297 3) carries close and drain plus the draft-16 flow control capsules, HTTP/3 datagrams (RFC 9297 2) ride QUIC DATAGRAM frames (RFC 9221) keyed by the quarter stream id, and a data stream is a QUIC stream that opens with the type 0x54 (unidirectional) or the signal value 0x41 (bidirectional) followed by the session id. A draft-16 reset uses `RESET_STREAM_AT` (draft-ietf-quic-reliable-stream-reset-09) with a reliable size covering the stream header, so the session association survives the discarded payload.
- **Codepoints:** capsules `WT_CLOSE_SESSION` 0x2843, `WT_DRAIN_SESSION` 0x78ae, `WT_MAX_DATA` 0x190B4D3D, `WT_DATA_BLOCKED` 0x190B4D41, `WT_MAX_STREAMS` 0x190B4D3F / 0x190B4D40, `WT_STREAMS_BLOCKED` 0x190B4D43 / 0x190B4D44; error codes `WT_SESSION_GONE` 0x170d7b68, `WT_BUFFERED_STREAM_REJECTED` 0x3994bd84, `WT_FLOW_CONTROL_ERROR` 0x045d4487; application error codes map into the reserved range 0x52e4a40fa8db to 0x52e5ac983162 while skipping every HTTP/3 grease codepoint.
- **Worker-owned, fixed capacity.** Sessions, data streams with their send buffers, and pre-session stream buffers come from a pool allocated once per worker, so the receive path allocates nothing and the pool refuses instead of growing. `Webtransport.capacityError` reports the field that outgrows the compile-time ceilings (`connection_session_cap` 8 sessions, `connection_stream_cap` 32 streams per connection, and the pool maxima) rather than silently truncating the feature.
- **Refusals are protocol answers, not drops.** A session ceiling is answered 429 and a full pool 503 on the request stream; a pre-session stream past the buffer is reset with `WT_BUFFERED_STREAM_REJECTED`; a session flow control violation closes the session with `WT_FLOW_CONTROL_ERROR`; and every stream of an ending session is reset with `WT_SESSION_GONE`.
- **Example:** [examples/tls/http3_webtransport.zig](examples/tls/http3_webtransport.zig) on 127.0.0.1:9089, built as `zig build example-http3_webtransport`: it accepts sessions on `/echo`, echoes every data-stream chunk and every datagram, opens one unidirectional stream per session with a banner, and prints the session lifecycle on stderr.
- **Runner:** `zig build test-runner-webtransport` spawns that example and drives it end to end with the hand-rolled HTTP/3 client (extended CONNECT answered 2xx, the banner on the unidirectional stream, a bidirectional data-stream echo, and a datagram echo). The step is also part of `test-runner-all`.
- **Docs:** [`docs/hld-webtransport-en.md`](docs/hld-webtransport-en.md) / [`docs/hld-webtransport-id.md`](docs/hld-webtransport-id.md) and [`docs/lld-webtransport-en.md`](docs/lld-webtransport-en.md) / [`docs/lld-webtransport-id.md`](docs/lld-webtransport-id.md), plus ADR-069.
- **Example (browser):** [examples/tls/webtransport_live.zig](examples/tls/webtransport_live.zig) on 127.0.0.1:9443, built as `zig build example-webtransport_live`: one process, one port number, two transports — the page over HTTPS/1.1 on TCP and the session over HTTP/3 on UDP, served on the same route, so the page and the session share one origin. It is a live view of server-owned state: ticks on a bidirectional stream become typed increment events rendered as DOM patches, a datagram carries an unreliable note and returns its patch, a second stream uploads 64 KiB with progress events while the ticks keep flowing, and reconnecting opens a new session that resynchronizes from the snapshot. Driven end to end in Chromium (session open, the server-opened unidirectional stream, 5 ticks, a datagram note, a 64 KiB upload with 5 ticks interleaved mid-upload, and a reconnect that resynchronized at the revision the events were missed at). See the HLD's "Driving the browser demo" for the two Chromium flags a self-signed certificate needs.
- **Interop harness:** [scripts/webtransport_interop.py](scripts/webtransport_interop.py) drives the `http3_webtransport` example with aioquic and reports PASS/FAIL for the handshake, the extended CONNECT, the bidirectional stream echo, the datagram echo, and the server-opened unidirectional stream. It is the scripted independent client; the browser demo is the visual one.
- **Not in this pass:** the capsule-based WebTransport over HTTP/2 variant, 0-RTT sessions, keying-material exporters, priority signalling, and a GOAWAY-initiated session drain. See the HLD's Not Yet Wired table.

<br>

### __**Fixed:**__

#### WebTransport over HTTP/3: the handshake is confirmed when the client's Finished arrives

    - Fixed: a browser could not open a session at all. A client is entitled to wait for the handshake to be confirmed before it sends any 1-RTT data, and Chromium does: it held its SETTINGS, its CONNECT, and every request until `HANDSHAKE_DONE` arrived, while the engine only wrote the confirmation when a 1-RTT packet arrived — a deadlock that aioquic and the in-tree client never exposed, because both send 1-RTT early. The server now verifies the client's Finished and leaves its one-time 1-RTT prologue (`HANDSHAKE_DONE`, then the control stream's SETTINGS) in the same turn, which is also the earliest moment RFC 9000 17.2.1 permits it.
    - Fixed: the client Finished was decrypted and discarded, so the handshake was never complete on the server side. Handshake-level CRYPTO bytes are now reassembled and the Finished is checked against the client handshake-traffic secret over the transcript through the server Finished (RFC 8446 4.4.4). A Finished that does not verify leaves the handshake unconfirmed: no confirmation, no session, and the connection idles out, so a peer that never proved key possession never reaches the request path. Covered by `zix http3: a client Finished verifies against the client handshake secret and the server-Finished transcript`.
    - Fixed: a Handshake-level CONNECTION_CLOSE (a client rejecting the certificate or a transport parameter) was decrypted and dropped, so the connection simply went quiet. It is now logged at WARN with the peer's alert code and description, which is where an interop failure names itself.
    - Fixed: the first server-opened unidirectional WebTransport stream was handed the id 3, which is the server's own HTTP/3 control stream: every unidirectional stream a session opened appended its bytes to the control stream instead, corrupting it for the peer (a client saw the stream type 0x54 and a banner tacked onto its SETTINGS). Unidirectional ids now start at 7, the first one the control stream leaves free. Covered by `zix http3: a server's WebTransport stream ids skip the control stream (RFC 9114 6.2.1)`.
    - Fixed: the runner's HTTP/3 client expected that banner on stream 3, which is what let the collision above pass its own test. The client now expects the protocol-correct id, so the runner fails if the engine ever reuses the control stream again.
    - Docs: the HLDs (both languages) gain a "Handshake and Confirmation" section, a security bullet on the confirmation rule, the browser demo in the examples table, and a "Driving the browser demo" walkthrough with the Chromium certificate flags; the changelog's New Features gains the demo and the interop harness.

#### HTTP/3 over QUIC

Two pre-existing defects in the engine that the WebTransport work surfaced, both hit by a real client rather than by the in-tree one.

- **A long-header packet is bounded by its own Length field, not by the end of the datagram (`src/udp/http3/protection.zig`).** The AEAD read its tag past the packet: a client that writes anything after its Initial (a coalesced packet, or the padding aioquic adds to reach the 1200-byte datagram floor) authenticated the wrong bytes and failed, so the handshake never started. `packet.longPacketBounds` now supplies the packet end and is shared with the coalesced-packet walk, so the same arithmetic decides both. A captured aioquic Initial (a 478-byte Length field inside a 1200-byte datagram) failed before and opens now, and aioquic completes the QUIC / TLS handshake against the engine and opens a session.
- **Every packet a datagram carries is served, not only the first (`src/udp/http3/dispatch/common.zig`).** `serveDatagram` read the first packet of a datagram and stopped, so a 1-RTT packet coalesced after an Initial or a Handshake packet was silently dropped. It now walks the packets of one datagram (RFC 9000 12.2), with `servePacket` as the per-packet step, which is what a client that coalesces its first flight depends on.

<br>

__**Update:**__
- Introduce `zix.utils.charsets` from `src/utils/charsets.zig`:
    - Covered from `alphabet`, `ALPHABET`, `ALPHANUMERIC`, `NUMERIC_STRING`, `punctuation`, `ALPHANUMERIC_PUNCTUATION`, `base32`, and `base64`.
    - User/caller can use this whenever they need it.
    - For contributor/maintainer, all repeatable must be use and call from there.

- Add utils generator in `src/utils/generator.zig`.

- Add utils check `src/utils/Check.zig`:
    - `string`:
        - `isNumericSigned` to check string is signed number.
        - `isNumericUnsigned` to check string is unsigned number.
        - `isDecimal` to check string is decimal number.

- Add utils base32 `src/utils/base32.zig`, covered:
    - Encode.
    - Decode.
    - RFC 4648 test vectors + roundtrip.

- Add utils base64 `src/utils/base64.zig`, covered:
    - Encode.
    - Decode.
    - RFC 4648 test vectors + roundtrip.

<br>

## 0.5.0 (2026-08-26)

### __**New Features:**__

#### TLS 1.3 Stack

Full implementation on `std.crypto`, no OpenSSL:
- **TLS 1.3 server** (RFC 8446) + **TLS 1.2 fallback** (RFC 5246/5288, ECDHE-ECDSA-AES128-GCM).
- **Native verifying client** `zix.Tls.Client` (1.3 and 1.2) with ALPN, X.509 chain + hostname verification.
- **ECDSA P-256**, **Ed25519**, and **RSA** certificates supported.
- RSA minimum 2048-bit, constant-time Montgomery modexp, PSS signatures.
- **TLS dual listener**: one server serves cleartext on `port` AND TLS on `tls_port`.
- **HTTPS/1.1, h2 over TLS, gRPC over TLS, and WebSocket over TLS (wss)** all served.
- **SSE over TLS** on thread-per-connection path.
- Multiplexed TLS dispatch under `.EPOLL`/`.URING` (no thread per connection).

NOTE:
- Consider use Ed25519 or ECDSA P-256 (RSA is a bit slow).

---

#### Three Internal Drivers

1. **`postgrez`** (PostgreSQL)
   - Wire protocol 3.2 with 3.0 fallback (PostgreSQL 15+).
   - SCRAM-SHA-256 and SCRAM-PLUS (channel binding), cleartext auth.
   - TLS 1.3, COPY streaming, LISTEN/NOTIFY, prepared statements, query pipelining.
   - Thread-safe `Pool`, batching `Executor`.

2. **`rediz`** (Redis)
   - RESP3 via HELLO with RESP2 fallback (Redis 7 or 8).
   - Typed value helpers, raw command escape hatch.
   - Command pipelining, deferred write-behind path.
   - Thread-safe `Pool`, TLS 1.3.

3. **`prometheuz`** (Prometheus)
   - Text exposition 0.0.4 parser, background `Scraper` poller.
   - `remote_write` push (protobuf + snappy).
   - PromQL instant and ranged query.
   - Metric registry (`Counter`, `Gauge`).

---

#### New Executable: `zixer` (Proxy Gateway)

A config-driven gateway built on the engines:
- **Single daemon** manages multiple independent sites, each with its own port and engine
- **Five edge types**: `http1`, `http2`, `grpc`, `http3`, `udp`
- **TLS termination** at the edge (zix TLS stack), ALPN negotiation, 421 for mismatched Host
- **Round-robin upstreams** with O(1) availability, cooldown on failure
- **Bounded on both legs**: client_timeout_ms, conn_limit, upstream_timeout_ms, process_limit
- **Static file serving** with precompressed .br/.gz siblings
- **`Proxy-Status`** (RFC 9209) on gateway-produced errors
- **Port 80 companion** for ACME http-01 renewal and `force_https` redirects
- **Header injection**: `$client_ip`, `$scheme`, `$host` interpolation
- **Validation** collects all faults before binding, numeric math (e.g., `16 * 1024`)
- **15 runnable demos** under `examples/proxies/`
- Complete documentation in `docs/zixer/` (English and Indonesian, 5 files each)

---

#### New Engine: `zix.Webrtc` (WebRTC Peer)

A WebRTC server built from RFCs 7983, 8445, 8489, 6347, 9260, 8831, and 8832. Serves:
- **ICE connectivity checks** over STUN.
- **DTLS 1.2 handshake** (ECDHE-ECDSA P-256 only).
- **SCTP association** with data channels.
- **Selective Forwarding Unit (SFU)** mode for media (RTP header rewrite per receiver).
- Three dispatch models: `.ASYNC` (cross-platform), `.EPOLL`, `.URING` (Linux).
- Eight examples on ports 9081–9088, including browser-driven demos.

<br>

---

### __**Core Engine Improvement:**__

#### HTTP/3 over QUIC

- Full RFC 9000/9001/9002/9114 implementation.
- **Loss recovery and congestion control** (ACK-driven, NewReno, PTO with backoff).
- **QPACK** static-table field lines, RFC 7541 Huffman decoder.
- **Flow-control rolling**: MAX_STREAMS and MAX_DATA grants replenish as client spends.
- **Content-encoding negotiation**: `accept-encoding`, `content-encoding` br/gzip (static table indices 31/42/43).
- **Per-core SO_REUSEPORT workers** under `.EPOLL`/`.URING`.
- Native test runner with hand-rolled QUIC client.

---

#### HTTP/2 Native Dispatch

- **`.EPOLL`/`.URING` shared-nothing multiplexed loops** (was `.POOL`-only).
- **Per-worker stream-slot pool**: resident memory tracks concurrent streams, not `connections * max_streams`.
- **HPACK response-header prefix cache**: hot triple [:status, content-type, content-encoding] reused.
- **Query-stripping** and prefix routing (mirrors `zix.Http1`).
- **DATA-frame coalescing** for gRPC server-streaming (5000 messages -> ~3 frames).
- **TLS terminator** shared with gRPC via `h2_terminator.zig`.

---

#### Request Body Overhaul

**14 defects fixed** across both HTTP engines:
- New `bodyReceived()` and `bodyComplete()` on both request views.
- One shared chunked decoder (`chunkedFrame`/`decodeChunkedInBuf`/`readChunkedBody`).
- `max_request_body` config (default 8 MiB, 0 disables).
- `Expect: 100-continue` answered on every model.
- `.EPOLL` defers handler until body fully drained (not partial).
- `Transfer-Encoding` list ending in `chunked` correctly recognized.
- Oversized body sheds with 413 (not truncated).
- Malformed chunked frame -> 400.

---

#### Request/Response/Context Trio (ADR-062/063)

- **All engines** now use `HandlerFn(req: *Request, res: *Response, ctx: *Context) anyerror!void`.
- `Context` carries: `io`, per-request stack arena (`FixedBufferAllocator`), timeout helpers.
- **Router** with `zix.ENGINE.Router(&[_]Route{...}).dispatch`.
- `zix.Grpc` is the exception: takes `Router(&routes)` itself (carries `is_server_streaming` metadata).
- **Auto-500** on error for `zix.Http`, `zix.Http2`, `zix.Http3`, silent pass-through for `zix.Grpc`/`zix.Fix`.

---

#### Response Compression

- **brotli** in-tree encoder/decoder from RFC 7932 (122,784-byte static dictionary embedded).
- `Accept-Encoding` negotiation (gzip/deflate/brotli) with q-values, wildcards, size floor.
- `sendNegotiated` on both HTTP engines, active under `.EPOLL`/`.URING`.
- **Fast gzip encoder** (`compression.flate_fast`): greedy LZ, fixed Huffman, for bodies under 64 KiB.

---

#### Static File Serving Rework (ADR-064)

- **`static_cache.zig`**: shared table per process (open fd, size, prerendered 200 header).
- **`static_send.zig`**: `sendfile` on Linux cleartext, positional read + write for encrypted/staged.
- **Precompressed `.br` and `.gz` siblings** picked up once, served with `Vary: Accept-Encoding`.
- **Range requests** (RFC 7233) on `zix.Http`, `zix.Http1`, `zix.Http2`, 206/416 handling.
- New config: `public_dir_cache_ttl_ms` (default 0), `public_dir_cache_max_entries` (256)
- `public_dir` on `zix.Http2`/`zix.Http3` (had none before).

---

#### Multipart Parser Rewrite

- **Linear scan** (was O(parts × size)), now O(size).
- **Zero-copy**: no allocator duplication, all fields borrow the body.
- **Correct framing**: only two CRLF bytes removed (not all leading/trailing).
- **Closing boundary without trailing CRLF** accepted (common client behavior).
- **Correct field name extraction**: matches only at parameter start, not inside filename.
- Full error reporting: `ZixMultipartNoBoundary`, `ZixMultipartUnterminated`.

---

#### UDP Datagram Raw Mode

- **Linear scan** (was O(parts × size)), now O(size).
- **Zero-copy**: no allocator duplication, all fields borrow the body.
- **Correct framing**: only two CRLF bytes removed (not all leading/trailing).
- **Closing boundary without trailing CRLF** accepted (common client behavior).
- **Correct field name extraction**: matches only at parameter start, not inside filename.
- Full error reporting: `ZixMultipartNoBoundary`, `ZixMultipartUnterminated`.

<br>

---

### __**Platform & Build:**__

#### Cross-Platform Compiled Support

- **Builds with Zig 0.16.x and 0.17.x** for: x86_64-linux, x86_64-windows, aarch64-macos, aarch64-linux, x86_64-freebsd, x86_64-netbsd, x86_64-openbsd.
- **Windows**: ntdll shim (`NtReadFile`/`NtWriteFile`/`NtClose` + AFD partial-disconnect).
- **BSDs**: `TCP_NODELAY` resolved at comptime.
- **Linux-only paths** gated (EPOLL/URING loops, CPU affinity, madvise, UDP batching).
- **`scripts/build-all-targets.sh`** sweeps all options over all targets.

---

#### `.ASYNC` Feature Parity (ADR-066)

- **Response compression and cache** now work under `.ASYNC`.
- **TLS over `.ASYNC`** fixed on macOS, FreeBSD, NetBSD, OpenBSD (three-way `windows`/`linux`/`posix` split).
- **HTTP/3 portable datagram fallback** off Linux.
- **Unix-domain socket paths** resolved to absolute paths (Windows AF_UNIX requires it).
- New shared substrate: `fd_io.zig`, `socket_pair.zig`, `socket_path.zig`, `async_cache.zig`.

---

#### `.POOL` and `.MIXED` Removed (ADR-065)

- DispatchModel now: `ASYNC = 0`, `EPOLL = 1`, `URING = 2`.
- Off Linux, `.EPOLL`/`.URING` return `error.ZixDispatchModelUnsupported`.
- `pool_size` removed `workers` used instead.
- 16 dispatch files deleted, 34 examples -> 7 unified.

<br>

---

### __**Performance Optimizations:**__

#### Memory

- **Http1 EPOLL recv-slab compaction**: packed to live connections, peak ~704->281 MiB.
- **Http1 URING idle-pool bound**: warm reconnect pool LRU eviction bounded by config knobs.
- **Http2/gRPC stream-slot pools**:
  - `connections * max_streams` -> concurrent streams only.
  - Http2: 6× memory cut, 8–20% throughput lift.
  - gRPC: 12× memory cut (916->77 MiB), 8–11% throughput lift.
- **TLS seal-in-place**: gather-encrypt two plaintext slices into one record without staging copy.

---

#### Throughput

- **`.URING` intra-batch submit**: SQEs pushed every 16 completions (not only after full batch): 4–5% lift.
- **`.URING` adaptive wakeup coalescing**: 32 completions per enter with 20us stall guard.
- **`.URING` accept fast path**: SQE submitted immediately inside accept handler: ~30% p99 drop.
- **HPACK response-header prefix cache**: 18–26% lift on small-body cells.
- **Fast gzip encoder**: 4–5x faster than std at similar ratio.

---

#### I/O

- **`.URING` multishot recv** for UDP/HTTP3 (buffer ring, 256 buffers).
- **Submission-queue backpressure** (`process_queue_len`): park on full SQ instead of closing.
- **Lost-accept re-arm fix** across all `.URING` dispatches.

<br>

---

### __**Client & Transport:**__

#### HTTP Client Timeouts

- `response_timeout_ms` and `read_timeout_ms` now enforced.
- Gated by readiness poll (`socket_poll.zig`).
- HTTP/2 client raw descriptor reads fixed (no Linux syscalls on macOS/BSD).
- SSE/WebSocket clients gain same fields.

---

#### TLS Client

- Native verifying client (`zix.Tls.Client` 1.3, `zix.Tls.Client12`).
- ALPN, X.509 chain + hostname verification (RFC 5280/6125).

---

#### WebSocket over TLS

- WSS on thread-per-connection path.
- `WebSocket.serveTls(fd, key, on_frame)` encrypts through stream sink.
- Auto-pong, auto-echo close, mux path added via ADR-060.

---

#### SSE over TLS

- `res.stream()` over TLS `zix.Http1.beginStream()` (no-op in cleartext).

<br>

---

### __**Diagnostic & Logging:**__

#### Logger Overhaul

- `logSystem` shim takes `Logger.Level`.
- Without logger: calls `std.log` at matching level.
- `.ERROR`/`.WARN` survive release builds.
- Failed writes retry `.INTR`/`.AGAIN` keep console.
- Per-peer/per-packet at `.WARN` or lower, bind/accept/config at `.ERROR`.

---

##### Error Reporting

- **All 21 bind sites** now answer with `error.Zix<Engine>ListenFailed` + one line naming address, cause, worker count.
- **Error names prefixed by product**: `Zix`, `Zixer`, `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`.
- **jzon** gains `lastFailure()` with field name and byte position.
- **Split collapsed errors**: certificate/key not-found, is-a-directory, too-large, unreadable.
- **`reuseport_cbpf` no longer silent**: kernel refusal reported once per process.

---

#### Zixer Logging

- **All 21 bind sites** now answer with `error.Zix<Engine>ListenFailed` + one line naming address, cause, worker count.
- **Error names prefixed by product**: `Zix`, `Zixer`, `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`.
- **jzon** gains `lastFailure()` with field name and byte position.
- **Split collapsed errors**: certificate/key not-found, is-a-directory, too-large, unreadable.
- **`reuseport_cbpf` no longer silent**: kernel refusal reported once per process.

---

##### Windows

- **Monotonic clock overflow fixed**: divide-first math (was multiply-first, overflow at ~31 min uptime).
- **UDP `recv_timeout_ms` enforced**: AFD-based readiness poll (was blocking, no timeout).

<br>

---

### __**API Breaking Changes:**__

#### Dispatch Model

- **Required config field** (no default): `dispatch_model` must be set explicitly.
- `.POOL` and `.MIXED` removed -> use `.ASYNC`, `.EPOLL`, or `.URING`.

---

#### Server Init

- All `Server.init` now infallible, config stored, validation moved to `run()`.
- `zix.Http.Server.init` drops comptime `stack_threshold` argument.
- `zix.Http3.Http3(handler)` generic -> `zix.Http3.Server.init(handler, config)`.

---

#### Handler Signature

- All engines: `HandlerFn(req: *Request, res: *Response, ctx: *Context) anyerror!void`.
- `zix.Http1`: raw `fn(head, body, fd)` removedm `initRaw` removed, middleware deleted.

---

#### Response Helpers Renamed (ADR-059)

- `fdWriteAll` -> `writeAllFD`.
- `writeSimple` -> `sendSimpleFD`.
- `writeJson` -> `sendJsonFD`.
- `writeGzip` -> `sendGzipFD`.
- `writeNegotiated` -> `sendNegotiateFD`.
- `writeChunkedStart` -> `sendChunkedStartFD`.
- And all other `write*` -> `send*` / `*FD` per taxonomy.

---

#### HTTP Method Handling (RFC 10008)

- **QUERY method** supported (RFC 10008).
- `Method.codeFromString` is **exact match** (case-sensitive, RFC 9110).
- Unsupported method -> `501 Not Implemented`.
- `zix.Http1` no longer accepts lowercase methods (`get`/`Post`/`delete`).

---

#### Content Type

- `Content.Type.NA` removed, lookups return `?Type`.
- `enumFromString` -> `typeFromString`, both return null on no match.

---

#### Error Names

- All public error names prefixed with product: `ZixPortNotConfigured`, `ZixTlsCertFileNotFound`, etc.
- std errors keep std names (OutOfMemory, WriteFailed, etc.).

---

#### Config Fields Removed/Renamed

- `pool_size` removed from all configs.
- `pool_stack_size_bytes` removed from `zix.Fix`.
- `max_client_response` removed from `HttpServerConfig`.
- `max_gzip_out` -> `compression_max_out`.
- `connection_timeout_ms` -> `conn_timeout_ms` (docs correction).

---

#### QUERY-Specific Breaking

- **No caching for QUERY responses** (cache key hashes method+path+query, no body).
- **Media types added**: `application/x-www-form-urlencoded`, `application/jsonpath`, `application/sql`, `multipart/form-data`.
- **`zix.Http.Client`** cannot send QUERY over TCP (std.http.Method closed set).
- **`requestUds`** can carry QUERY, HTTP/2 client now sends body with QUERY.

<br>

---

### __**Test & Validation:**__

#### Runner Expansion

- **55 protocols** (was 34) across all engines and dispatch models.
- **Platform-aware execution**: foreign targets compile and skip with warning.
- **Named test-run build steps** for `--summary all` diagnostics.
- **52 scenarios pass on every platform** (linux_only_labels empty).

---

#### Docker-Free Driver Tests

- `test-behaviour` and `test-edge` for `postgrez`, `rediz`, `prometheuz`.
- In-process servers speak real protocol, no container/daemon needed.
- All 7 manual CI legs run them (previously only Linux leg could).
- `test-integration` and `test-runner` remain container-only (local steps).

---

#### Coverage

- **86 new unit/behaviour/edge tests** for QUERY method.
- **~80 new unit/edge tests** for request body handling.
- **Full test suite** across all 55 runner protocols and 13 zixer proxy demos.

<br>

---

### __**Examples & Demos:**__

#### New Examples (Ports)

- `http1_query.zig` (9079), `http_query.zig` (9080).
- `http1_compression.zig` (9058), `http_compression.zig` (9059).
- `udp_server_raw.zig` (9064), `udp_server_tickrate.zig`, `udp_client_tickrate.zig`.
- `tls/tls_http1_basic.zig` (9060), `tls/tls_http2_basic.zig` (9061).
- `tls/tls_http1_ed25519.zig` (9062).
- `tls/tls_http1_sse.zig` (9073), `tls/tls_http1_ws.zig` (9074), `tls/tls_http_ws.zig` (9075).
- `tls/tls_http1_dual.zig` (9076 cleartext/9077 TLS).
- `tls/tls_http_basic.zig` (9071), `tls/tls_http_sse.zig` (9072).
- `http3_basic.zig` (9063).
- `http2_basic_{async,pool,mixed,epoll,uring}.zig` (9065-9069).
- **8 WebRTC examples** (9081-9088): signalling relay, STUN binding, data echo, zix-to-zix pair, room chat, file transfer, media broadcast, mesh video call.

---

#### Static File Examples

- All `public_dir`-using examples now use the new caching/serving paths.
- Precompressed `.br` and `.gz` siblings automatically picked up.

<br>

---

### __**Documentation:**__

#### New Docs

- **`docs/zixer/`**: README, how-to-use, config, HLD, LLD (English + Indonesian).
- **`docs/driver/postgrez/`**: README, HLD, LLD, config ref (EN + ID).
- **`docs/driver/rediz/`**: README, HLD, LLD, config ref (EN + ID).
- **`docs/driver/prometheuz/`**: README, HLD, LLD, config ref (EN + ID).
- **`docs/hld-http3-en.md`**, **`lld-http3-en.md`** (and -id).
- **`docs/hld-tls-en.md`**, **`lld-tls-en.md`** (and -id).
- **`docs/hld-grpc-en.md`**, **`hld-grpc-proxy-en.md`** (and -id) updated for native TLS.

---

#### Corrections

- `zix.Http` docs: TLS supported (was "proxy-terminated by design").
- `zix.Grpc` docs: response cache and TLS dual listener noted.
- `zix.Uds`/`zix.Tcp`: frame encoding is big-endian (was little-endian).
- `zix.Fix`: `connection_timeout_ms` -> `conn_timeout_ms`.
- `zix.Tcp`: `max_msg_len` -> `max_recv_buf`.

<br>

----

### __**Version History:**__

- **0.5.0-rc1** (2026-07-15): Initial release candidate
- **0.5.x-rc2** (2026-07-27): Driver test suites, platform cross-build, body overhaul
- **0.5.x-rc3** (2026-08-14): zixer, WebRTC, QUIC loss recovery, final bug fixes

<br>

## 0.5.x-rc3 (2026-08-14)

__*Fix:*__

- Every engine answers a failed handler exactly once, and only when the handler left the caller waiting. What counts as answered now includes the fd writers, not just the `Response` builder: `zix.Http1` and `zix.Http2` tracked it in `Response.sent` alone, so a handler that answered with `sendSimpleFD` or `sendResponseFD` and then returned an error read to the engine as never having answered, and got a second response glued onto the first. A peer reading that saw one response followed by `HTTP/1.1 500 Internal Server Error`, or a second HEADERS frame on a stream it had already seen closed. Both engines now check the fd writers as well, so the handler is answered once whichever way it answered.

- `zix.Grpc` and `zix.Fix` report the errors their sends used to swallow. `res.sendMessage` returned `void` on both, and a build failure or a dead peer was dropped inside the engine, so a handler could not tell a delivered message from one that never left, and had nothing to `try` or to `catch`. Both return an error union now: `try` hands the failure to the engine, and a handler that wants to answer differently catches it. `zix.Grpc.Response.sendHeaders`, `finish`, `sendCached` and `serveCached` moved with it, and `zix.Fix` reports `error.ZixFixMessageTooLarge` for a message that does not fit `MAX_MSG_SIZE`.

- `zix.Grpc` and `zix.Fix` answer a handler that returns an error. Both used to pass it through silently (ADR-063, "current wire behavior kept"), so a caller was left waiting on a call that would never carry a status and a counterparty on a message that would never arrive. A gRPC call the handler left open is now closed with `grpc-status 13` (INTERNAL), and a FIX message the handler failed on is answered with a Reject (35=3) carrying the RefSeqNum of the message that failed. A call the handler already closed, or a message it already answered, is left exactly as the handler left it. An error the handler swallows itself is still the handler's own business on every engine, the engine adds nothing to it.

- The six `localbench/http1-*` entries report their send failures instead of swallowing them. `baseline` and `upload` ended a failed render with a bare `catch return`, which answered nothing and left the client waiting for the read timeout. `baseline`, `upload`, `pipeline` and `json` each carried a hand-rolled 500 inside a `catch` on the send that had just failed, writing a second response down a descriptor that had already taken part of the first. The shared 400 / 404 / 503 responders in `shared/response.zig` swallowed theirs outright. All of them are `try` now, so the engine completes a failed request once, and the websocket entries' upgrade is `try` as well: `WebSocket.serve` writes the 101 itself, so the old `catch` answering "handshake failed" appended an HTTP body to a half-written upgrade. Two paths stay `void` because there is no handler frame left to report into, and each says so in place: the frame callback, which runs long after the handler returned, and the database completion path in `shared/dbpg.zig`, which parks an unfinished write rather than failing it.

<br>

__*Update:*__

- `examples/udp_server_tickrate.zig` and `examples/udp_client_tickrate.zig` are a game-server-shaped pair on the raw UDP path. Clients send their state whenever they want, the server keeps only the latest state per client, and a fixed tick loop broadcasts a world snapshot to every connected client once per tick: `--tickrate` picks the cadence (64 the default, 128 the other common rate), `--ip` / `--port` on the server and `--bind-ip` / `--bind-port` / `--server-ip` / `--server-port` on the client stay optional, every missing flag keeps its default. The engine itself gained no tick concept: the tick loop, the client registry, and the snapshot sends all live in the example. `test-runner-udp-tickrate` drives both executables and rides `test-runner-all`, asserting the per-tick re-broadcast, the second client process, and that wrong-size datagrams never enter the stream.

- The three udp examples are run as built binaries. Their headers used to say `zig run examples/<file>.zig -- <flags>`, which cannot work: the examples import zix, and only the build system wires that module in. Each usage comment now sits on `pub fn main` and shows the `zig build example-<name>` step and the installed binary with its flags, and the two servers set `allow_args` so `--ip` / `--port` are actually read (a missing flag keeps the default, so the test runners see the same server as before).

- `examples/http1_static_cached.zig` moved from port 9077 to 9039: 9077 already belongs to the TLS listener of `examples/tls/tls_http1_dual.zig`, so the two examples could not run side by side. Every example now binds a port of its own.

- `localbench-run.sh` raises its own soft file descriptor limit before the first tier runs, so a connection count is the load the server actually receives. A load generator opens one descriptor per connection and none of them lifts the limit itself, so on a box left at the usual 1024 every tier above roughly a thousand connections was measuring something else: `wrk` carried on with the 1013 connections it managed to open and counted the remainder under `Socket errors: connect`, while `h2load` aborts outright on its first failed connect, which took every HTTP/2 profile at 1024c and 4096c to zero. Only the soft limit moves, so no privilege is needed, and the old and the new value are printed into the run log. `localbench-isolate.sh` runs this script as a child and inherits it. Numbers recorded above roughly a thousand connections before this are not comparable with numbers recorded after it.

- `zix.utils.multipart` refuses a body it cannot read whole instead of parsing part of one. A short body carries no closing boundary, and the parser used to return quietly with whatever fields it had found, which reads to a handler exactly like a request that carried no fields at all. `parse` now reports `error.ZixMultipartNoBoundary` when no opening boundary is present, which an empty body is, and `error.ZixMultipartUnterminated` when parts were found but the closing boundary never arrived. The engines answer the size question first: check `req.bodyComplete()`, and `req.bodyReceived()` against `req.body().len`, before parsing.

- `zix.utils.multipart` keeps every byte of an uploaded file. Part content was trimmed of all leading and trailing CR and LF bytes, when only the single CRLF in front of the next boundary is framing, so a binary file whose own first or last bytes were line terminators lost them and was saved corrupt. Exactly those two framing bytes now come off. A closing boundary with no trailing CRLF is also accepted, which plenty of clients send and which used to drop the final part, and the boundary text appearing inside a file no longer splits that file in two.

- `zix.utils.multipart` scans a body once. Each part cost two searches running from the current position to the end of the body, so a large upload with many parts spent time in proportion to parts times size. The scan now moves forward only, which makes the cost linear in the body size whatever it carries.

- `zix.utils.multipart` copies nothing. A file field's data used to be duplicated onto the allocator, so an upload cost twice its own size for a copy that outlived nothing: every other slice in a `Field`, its name included, already borrowed the body. All of them now borrow it, and `deinit` has only the field list left to free. Anything that must survive the handler call is the caller's copy to make, which was already true of the field names.

- `zix.utils.multipart` reads the field name a client writes after the file name. The lookup searched for `name="` anywhere in the Content-Disposition, and `filename="` spells that inside itself, so `filename="a.bin"; name="upload"` reported the field as being called `a.bin`. A parameter is now only matched where one starts, so either order reads the same.

- `zix.Http2` and gRPC no longer serve a request body that is not whole. A peer could declare `content-length: 100`, send 40 bytes of DATA, set END_STREAM, and have those 40 bytes handed to a handler as though they were the whole request: the declared length was never checked against what arrived, on any dispatch model. RFC 9113 8.1.1 makes such a request malformed, a stream error of type PROTOCOL_ERROR, and both engines now answer it that way, resetting the stream and freeing its slot without dispatching. The check lives in new `src/tcp/http2/stream_body.zig` and is shared by all four state machines (blocking and multiplexed, for h2 and for gRPC), so https inherits it through the same mux the cleartext models drive. A body that declares nothing still ends where END_STREAM says it does, which is the ordinary h2 shape and is unaffected.

- `zix.Http2` and gRPC answer a peer that hangs up part way through a request. A stream opened and never ended used to close the connection with nothing said, so a client could not tell an abandoned request from a crash, a timeout, or a dropped connection. Every model now sends `GOAWAY(PROTOCOL_ERROR)` first, sealed into a record on the TLS paths like any other frame, and a connection with no request in flight still closes without a byte because that is the ordinary end of a connection. A stream held only by a response body parked on a flow-control window is not a request in flight: that request arrived whole and the debt is the server's.

- A large request over https reaches `zix.Http2` and gRPC. The TLS session reassembles one record into a 17408 byte buffer and terminates the connection when handed more, while all four h2 and gRPC read paths staged 32 KiB of ciphertext and fed it in one go. A quiet connection never filled a read, so this only showed once a large request kept the socket busy: past one record's worth the connection simply died, with no status and no reset. Each path now sizes its read by `Session.readRoom()`, the same fix `zix.Http1` already carries, so a request spanning several TLS records is served whole on `.EPOLL` and `.URING` alike.

- `zix.Http2` sheds an oversized request body on `.ASYNC` instead of truncating it. The blocking model copied whatever fit its per-stream buffer, dropped the rest, and dispatched the handler with a body that was neither what the client sent nor marked as short. It now answers `413` with END_STREAM and frees the slot, which is what `.EPOLL` and `.URING` already did, so the three models agree and no handler receives a silently shortened body.

- Uploads over https work on `zix.Http1`. The TLS paths held the whole request, head plus body, in one fixed per-connection buffer, so an upload larger than it could not be served: `.EPOLL` and `.URING` closed the connection with no status past 17251 bytes, and `.ASYNC` was worse, answering `200` with only the first record's worth (16227 bytes) and silently dropping the rest, because it read one TLS record and never accumulated. Both now use the shape the cleartext event loops already had, in new `src/tcp/http1/tls_feed.zig`: a body too large to buffer is never buffered, its head is parked, the remaining bytes are counted as they arrive, and the request is served once the count reaches the declared length. The buffer bounds the head rather than the upload, so connection memory no longer tracks upload size, and a 20 MiB upload is served on all three models. `config.max_request_body` is now enforced over TLS too, where it was previously ignored on every model, so an oversized declared body answers `413` instead of being accepted or dropped, and a peer that stops part way answers `400`.

- A second ceiling under that one: the TLS session reassembles one record into a 17408 byte buffer and terminates the connection when handed more, while both http1 read paths staged 32 KiB of ciphertext and fed it all at once. A quiet connection never filled a read, so this only appeared once a large upload kept the socket busy. New `Session.readRoom()` reports what a feed will accept and both read paths size their read by it. `zix.Http2` and gRPC read the same way and have the same latent limit on their own request paths, which this change does not touch.

- `zix.Http1` answers a request the peer stopped sending. On `.EPOLL` and `.URING` a declared body that never finished arriving used to close the connection without a byte, so a client could not tell a refused upload from a crash, a timeout, or a dropped connection. Both models now answer `400 Bad Request` with `Connection: close` and drop the request, whether its body was still buffering or already draining off the socket. A handler is still never invoked with a partial body there, which is what `bodyComplete()` reading true on those two models means: `.ASYNC` reads the body inline and does run the handler on whatever arrived, and the doc now says which model does which instead of describing one of them as the engine. A connection the peer closes between requests owes nothing and is still answered with nothing.

- `localbench/` is a benchmark suite that lives in the repository. Eighteen standalone zig servers, one per engine and dispatch model pairing (HTTP/1.1, its WebSocket variant, HTTP/2, gRPC, HTTP/3 and the zixer gateway, each in `.ASYNC`, `.EPOLL` and `.URING`), every one depending on this checkout by path so building an entry builds the local zix source. Four scripts wrap them: `localbench-build.sh`, `localbench-validate.sh` to prove an entry answers correctly before it is measured, `localbench-run.sh`, and `localbench-isolate.sh` for a quiesced run whose numbers are worth quoting. Fixtures are read out of a sibling checkout and nothing is copied in, and a missing load generator skips the profiles that need it rather than failing the run. `localbench/README-en.md` and `README-id.md` carry the walkthrough.

- The logger reports its own failures. A write that failed used to vanish and `.INTR` was treated as terminal, so a signal arriving mid-write lost the line. `rawWrite` now retries `.INTR` and `.AGAIN` and answers with the errno, so a failed file write suspends the file sink and says why on stderr, keeping the console. A record longer than the buffer used to be dropped whole: it is now kept and marked, because a dropped record loses the fact that anything happened. The open-failure message named neither the path nor the cause, guessing "ensure save_path exists" for permission problems, missing directories and over-long paths alike. It now prints the real cause and the path, and the `mkdirat` result is no longer discarded.

- Errors that collapsed several causes into one name are split, and whoever holds the path now prints it. `Tls.Context.init` separates not-found, is-a-directory, too-large and unreadable for both the certificate and the key, so a permission problem no longer reports as a typo. `zix.utils.file.load` does the same. A missing `public_dir` separates from one that is not a directory and one the process cannot enter, across all four engines that check it. `zix.utils.static_send` separates a disk read failure from a dead peer, which shared `error.BrokenPipe`. `error.ZixInvalidUrl` became five names across the http, sse and websocket clients: malformed, unsupported scheme, missing host, invalid port, path too long. zixer's control replies now carry the configured path for every one of these.

- jzon answers which field and which byte. `JzonUnknownField`, `JzonMissingField` and `JzonUnknownEnumValue` never said which field, and `JzonTruncated` never said where, because an error value cannot carry either. New `jzon.lastFailure()` does, read right after a parse returns an error, and every error it can explain names it in its own doc comment.

- The remaining silent paths speak up. `zix.Http1` and `zix.Http` reject port zero at `run()` like the other six engines, instead of letting a forgotten port surface later as a network failure. A static cache that could not be installed says so rather than looking exactly like caching being off, and the two existing cache notices go through the configured logger instead of around it. A failed TLS handshake files at DEBUG rather than closing the socket with nothing said. `reuseport_cbpf` is no longer a silent no-op: a kernel that refuses `SO_ATTACH_REUSEPORT_CBPF` is reported once per process, and the group keeps the default hash.

- A listener that fails to bind now says so and stops the server. Each shared-nothing worker binds inside its own thread, so a failed bind ended that thread and nothing else: the parent joined, saw nothing, and `run()` returned success while the process exited 0 without listening. A port already in use, port 80 without privileges and a bad `ip` all looked identical, and a release build with no logger printed nothing at all. New `src/multiplexers/listen_report.zig` gives every worker in a SO_REUSEPORT group one report it files before serving, and the group waits behind it, so a server either listens on every worker or fails on all of them. All 21 bind sites across http1, http2, grpc, zix.Http, tcp, fix and the four TLS multiplexers now answer with `error.Zix<Engine>ListenFailed` and one line naming the address, the cause, and how many workers could not bind. The four TLS accept threads that dropped their failure with `catch {}` now name what died and say that cleartext is still serving.

- The "listening on" line moved below the bind in those ten files. It used to be printed before the listener existed, so it claimed an address the server may never have taken.

- Error names now carry the prefix of the product that owns them, so a name says whose failure it is before it says what failed. `Zix` across the engine tree, `Zixer` under `src/zixer`, and each standalone package keeps its own: `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`. This is a breaking rename of every public error name: `error.PortNotConfigured` is now `error.ZixPortNotConfigured`, `error.TlsCertFileNotFound` is now `error.ZixTlsCertFileNotFound`, and a caller switching on a name has to follow. An error std raises through the same function keeps the name std gave it (`OutOfMemory`, `WriteFailed`, `ReadFailed`, `EndOfStream`, `BrokenPipe`, `NoSpaceLeft`, `Overflow`, `InvalidSignature`, `CertificateHostMismatch`, `SignatureVerificationFailed`), because prefixing only the local raise site would leave two names for one condition in the same error set.

- Every engine's `logSystem` shim takes a level. It used to file everything at `.INFO`, so a bind failure and a healthy startup line were indistinguishable, and without a logger it wrote through `std.debug.print` behind a debug-build gate, so a release build with no logger lost every diagnostic. Each shim now takes a `Logger.Level` and, with no logger attached, calls `std.log` at the matching level through a scoped logger. std's own default level does the filtering, `.ERROR` and `.WARN` survive a release build, and a caller who sets `std.options.logFn` can route or silence any of it. The rule applied across the 125 call sites: a failure driven by one remote peer or one datagram is not a server-level error, so per-peer and per-packet events file at `.WARN` or lower while bind, listen, accept and config rejection file at `.ERROR`.

- zixer writes a log. It had no logger anywhere across 66 files, so once a site was bound the executable produced no runtime output at all: a client could see a 502 while the operator saw nothing. New `log_level` key in main.cfg (`debug`, `info`, `warn`, `error`, default `info`) drives a log file under `logs_dir` and the console together, and the daemon hands its logger to every site and every worker. Each edge answer is written once, with the status picking the level: a 5xx files at `.WARN`, a 4xx at `.DEBUG` so a bad client cannot flood the log. The daemon's own startup and failure notices moved onto the logger too, because a command writing to stdout at a position it tracks itself and a logger appending to stderr would overwrite each other under `zixer daemon > file 2>&1`.

- The Windows monotonic clock overflowed after about half an hour of machine uptime. `zix.utils` and the postgrez executor both turned the performance counter into a time unit with `counter * scale / frequency`, which multiplies before it divides, so the product leaves u64 once the counter passes `u64 max / scale`. Windows reports a 10 MHz counter, which puts that at roughly 31 minutes of uptime for nanoseconds and 21 days for microseconds. A safe build panicked with `integer overflow` and took the calling thread down with it, a release build wrapped and reported nonsense elapsed times. New `src/utils/counter_scale.zig` divides first, so the surviving multiply is always bounded by the frequency, and the postgrez executor carries the same shape locally because a driver module cannot import zix's utils. Both counter queries also stopped discarding their status: a refused query answers 0 instead of dividing by a reading that was never written.

- The `Method`, `Status`, and `Content` tables each carried their enum-to-string switch twice: a private `toString` behind `asString`, and an identical public `stringFromEnum`. That is 122 duplicated arms per engine, and the only thing keeping the two copies honest was a test asserting they agreed. `stringFromEnum` is now the one switch and `asString` calls it, so the two spellings cannot disagree. No caller changes: both names stay public and return what they always did.

- HTTP QUERY method support on both HTTP/1 engines (RFC 10008):
    - QUERY is safe and idempotent like GET and carries content like POST, for a question too large or too structured to fit a URL query string. `Method.Code` gains `QUERY` on `zix.Http` and `zix.Http1`, and `req.method()` returns it on both.
    - Before this, `zix.Http1` parsed a QUERY request fine and then reported it as `GET`, because `enumFromString` answered `GET` for any token it did not recognise, so a handler could not tell a question carried in the content from a plain GET. `zix.Http` rejected the request line outright with `error.ZixInvalidRequest`, so it never reached a route at all.
    - Behaviour change: a method the engine does not implement now answers `501 Not Implemented`. New `error.ZixUnknownMethod` is raised only when the request line tokenized and the method alone is unsupported, so a genuinely malformed line still answers `400` (RFC 9110 section 15.6.2). `Method.codeFromString` reports no match as null, while `enumFromString` keeps its GET fallback for a hand-built head.
    - A QUERY response is never cached. The cache key is `hash(method, path, query)` and carries no request content, so two QUERY requests to one path with different bodies would have shared an answer. Caching a QUERY response is a MAY in RFC 10008 section 2.7, so the store is refused outright on both engines. Only the store path checks this, so the lookup path keeps its cost.
    - Four media types added to both content tables: `application/x-www-form-urlencoded`, `application/jsonpath`, `application/sql`, and `multipart/form-data`. `application/graphql` was already present.
    - Fixed a latent buffer overrun in both `content.zig` tables. The lookup lowercased into a fixed 32-byte buffer while `std.ascii.lowerString` asserts the output fits, and `application/x-www-form-urlencoded` is 33 bytes, so a safe build panicked and a release build wrote past the end. The bound is now a named `MAX_TYPE_LEN` with a length guard that refuses an oversized value before the copy. The function had no callers before, so nothing had reached it.
    - Breaking: `Content.Type.NA` is removed and the lookups return `?Type`. `enumFromString` becomes `typeFromString`, and it and `typeFromHeader` both report no match as null. `NA` stringified to `"n/a"`, which is not a media type and could reach the wire through `setContentType(.NA)`, and it stood for three different things at once (header absent, type unrecognised, value absurdly long). The response side already carried `content_type: ?Content.Type`, so nothing needed a sentinel.
    - New `src/utils/media_type.zig`: `stripParameters` and `equalIgnoreParameters`, so `application/sql` with a charset parameter matches the bare type. `Content.typeFromHeader` is the raw-header entry point built on it. It never inspects the content, which RFC 10008 section 2.1 forbids.
    - `zix.Http.Client` cannot put a QUERY on the wire over TCP, because it wraps `std.http.Client` and `std.http.Method` is a closed set that predates RFC 10008. It now reports `error.UnsupportedMethod` before opening a socket instead of after connecting. `requestUds` writes its own request line, so that path does carry QUERY. The HTTP/2 client sends it with its body, where `methodHasBody` listed only POST, PUT, and PATCH and would have sent a question with nothing asked.
    - A parse failure over TLS now answers before closing. `tls_serve.zig` and `tls_mux.zig` dropped the connection with no status, so an unimplemented method or a malformed request over https was indistinguishable from a dead connection. Both now write the status the way the existing 421 branch does. This path has no wire-level test yet.
    - Content-Type enforcement stays handler policy rather than engine policy: the engine cannot know which types a route accepts without new config, and a rare method must not add a branch to the hot path. `Accept-Query` (section 3) is a plain header value the handler writes, so no RFC 9651 parser was added.
    - Breaking: `Method.codeFromString` is now an exact match and is the single method table for each engine. Both HTTP/1 request-line parsers kept a private copy of that table, one folding case and one not, so `query` in lowercase was accepted by `zix.Http1` and answered 501 by `zix.Http`. RFC 9110 section 9.1 makes method names case-sensitive, so both engines now refuse it. `zix.Http1` previously accepted any method in any case (`get`, `Post`, `delete`), and no longer does. The duplicate tables in `http1/parser.zig` and `http/parser.zig` are deleted, and the lowercase copy the lookup used to make is gone with them.
    - `examples/http1_query.zig` (port 9079) and `examples/http_query.zig` (port 9080) carry the handler-side pattern: the 400 / 415 / 422 / 406 map, the `Accept-Query` header, and a route accepting two content types while answering one.
    - New `tests/runner/checks_query.zig` drives ten cases against a running example over a raw socket, including a lowercase `query` token that both engines answer with 501. It is the first wire-level check for QUERY, and `zig build test-runner-http1-query` / `test-runner-http-query` plus `test-runner-all` all run it.
    - Coverage: 86 new unit, behaviour, and edge tests, including `tests/behaviour/http/query_test.zig`, `tests/behaviour/http1/query_test.zig`, `tests/edge/http/query_test.zig`, and `tests/edge/http1/query_test.zig`.

    ---

- Request bodies now mean the same thing on every engine and dispatch model (14 defects fixed across `zix.Http` and `zix.Http1`):
    - New on both request views: `bodyReceived()` and `bodyComplete()`. The count comes from the reads that consumed the body, never from the Content-Length header a client can lie about, and the flag tells a finished upload from one the peer cut short. Before, the same upload reported the delivery cap under `.ASYNC` and 0 under `.EPOLL`.
    - One shared chunked decoder in `http1/core.zig` (`chunkedFrame` / `decodeChunkedInBuf` / `readChunkedBody`), so a chunked body is framed identically on all three models. The walk separates "not arrived yet" from "broken" from "too big": a malformed chunk frame now answers `400` and a chunked body past the buffer `413`, where both used to read as "keep waiting" until the connection filled and died with no answer.
    - New config field `max_request_body` on both engines (default 8 MiB, 0 removes the check): a declared Content-Length past it is refused with `413` before a byte of the body is read or allocated, so a client cannot make a worker consume an arbitrary number of bytes by claiming a size. Chunked declares no length up front, so it is bounded by the body buffer on `zix.Http1` and grows toward the limit only as bytes arrive on `zix.Http`.
    - `zix.Http1` `.EPOLL` now defers the handler until an over-large body has drained, then serves it with the counted total, the ordering `.URING` already used. `.ASYNC` hands the handler the start of the body rather than drain leftovers, keeps a request pipelined behind a chunked body, and closes after a failed chunked decode instead of misparsing leftover body bytes as the next request.
    - `Expect: 100-continue` is answered on every model of both engines. It was `.ASYNC`-only on `zix.Http1` and `zix.Http` never sent it, so such a client waited out its own timeout on every request.
    - `zix.Http`: a `Transfer-Encoding` coding list ending in `chunked` is recognized as chunked, `body()` waits for a segmented body on a non-blocking fd instead of truncating at the first short read, a chunked body arriving after the head reaches the handler instead of arriving empty, and a connection whose body was never read (or cut short by the peer) closes instead of staying keep-alive with body bytes still on the socket.
    - Behaviour change: a chunked size line that is not hex is now `error.ZixInvalidChunkedBody` answered with `400`, where it used to yield an empty body and a 200.
    - Coverage: about 80 new unit and edge tests, including the `tests/edge/http1/body_test.zig` framing suite.

    ---

- Breaking: the `.POOL` and `.MIXED` dispatch models are removed (ADR-065):
    - `DispatchModel` is now `ASYNC = 0`, `EPOLL = 1`, `URING = 2` on all eight engines. Off Linux, `run()` returns `error.ZixDispatchModelUnsupported` for `.EPOLL` and `.URING` instead of silently downgrading to `.POOL`, and logs which model was rejected. The old fallback changed a caller's throughput, memory, and latency profile with nothing but a log line to say so, and a server with no logger configured said nothing at all.
    - `pool_size` is removed from all eight configs, and `pool_stack_size_bytes` from `zix.Fix`. On `zix.Http2` and `zix.Grpc` `pool_size` was the `.EPOLL` / `.URING` worker count while `workers` was POOL and MIXED only, so both are repointed onto `workers`. Both defaulted to 0, so default behaviour is unchanged.
    - The 16 `dispatch/pool.zig` and `dispatch/mixed.zig` files are deleted, along with `ConnQueue`, `WorkerCtx`, `PoolCtx`, and `AsyncWorkerCtx`.
    - The 34 numbered per-model examples collapse to 7 unified ones, each picking its model per target at comptime. Two test-runner legs are lost with them: `http1-drain` keeps only its URING leg, and `grpc-stream` now shares port 9032 with `grpc`.
    - New shared predicate `src/utils/dispatch_support.zig`, consulted at the top of every `run()` before it opens a listener or spawns a thread, so a rejected config leaves nothing behind.

    ---

- Every feature now works under `.ASYNC` on every supported platform (ADR-066):
    - Response compression and the response cache reached `.ASYNC`. Both are per-worker threadlocal switches that only `dispatch/epoll.zig` and `dispatch/uring.zig` installed, so a server with `compress = true` on `.ASYNC` was returning uncompressed bodies with no error at all. The engine-owned WebSocket promotion was worse: `core.zig` took the handoff and dropped it, ending the connection.
    - Fixed: TLS over `.ASYNC` was broken on macOS, FreeBSD, NetBSD and OpenBSD. Six files split `if (windows) ... else <Linux syscall>`, so those four platforms fell into the Linux branch and issued Linux syscall numbers. It compiled, which is why no cross-build sweep caught it. Every such site is now a three-way `windows` / `linux` / `posix` split.
    - HTTP/3 gained a portable datagram fallback. Its `runSingle` previously logged a line and returned void off Linux, so `run()` reported success and never bound a socket.
    - Unix-domain socket and channel IPC paths are now resolved to an absolute path both ends derive identically, instead of a relative path (rejected outright by the Windows AF_UNIX bind) or `/tmp/...` (a location Windows does not have).
    - New shared substrate: `src/utils/fd_io.zig` (blocking read / write / close / readiness on a raw descriptor), `src/utils/socket_pair.zig` (a connected pair, socketpair on POSIX and loopback on Windows), `src/utils/socket_path.zig`, and `src/utils/async_cache.zig` (the `.ASYNC` response cache, one per io pool thread, with a registry and reclaim because a threadlocal has no destructor).
    - `examples/http1_websocket_uring.zig` is deleted: `http1_websocket.zig` already runs `.URING` on Linux and so already exercises `websocket.pumpRing`. Its `/ws` echo route moved across and its runner became `test-runner-http1-websocket-echo`. Port 9029 is retired, not reused.
    - `tests/runner/common.zig:linux_only_labels` is now empty: all 52 runner scenarios are expected to pass on every platform. 85 unit, integration and edge tests dropped their `!= .linux` skip guard, because what made them Linux-only was the test harness (`socketpair`, `pipe2`, `memfd_create`) and not the behaviour under test.
    - Nothing here touches the `.EPOLL` / `.URING` install path: their per-worker cache and compression setup is byte for byte what it was.

    ---

- Docker-free test suites for all three drivers:
    - New `test-behaviour` and `test-edge` steps on `postgrez`, `rediz`, and `prometheuz`, each driving an in-process server under `tests/inproc/` that speaks the real protocol. They need no container and no daemon, so all seven CI legs run them, where previously only the Linux leg could run the container-backed `test-integration`.
    - `postgrez` covers the PG v3 wire protocol including SCRAM-SHA-256 and its channel-bound PLUS variant, cleartext auth, the extended query cycle, COPY, LISTEN / NOTIFY, and a TLS 1.3 handshake. `rediz` covers RESP2 and RESP3 with a real keyspace, ACL auth, CLIENT KILL, and TLS. `prometheuz` gets its first end-to-end coverage at all, with one HTTP endpoint standing in for the exporter, the remote-write receiver, and the query API.
    - Each framing layer is verified against the driver's own codec rather than against itself: messages built by the driver's own `src/protocol/frontend.zig` are read back by the test parser, the test builder is read back by `src/protocol/backend.zig`, and the SCRAM server runs against the real `src/auth/scram.zig` client, all three under `src/driver/postgrez/`.
    - `test-integration` and `test-runner` are unchanged and stay container-only, and no CI leg invokes them any more: they pull an image from a public registry, so a registry outage reddens a leg over something that is not a zix defect. They are local steps now, where a real PostgreSQL 18 or Redis 8 is the point. The in-process server runs no SQL and no PromQL, so it proves the wire path and the driver's handling of it, never that a query means what its author intended.

    ---

- `public_dir` static file serving reworked, and extended to all four HTTP engines (ADR-064):
    - New `src/utils/static_cache.zig`, a table shared by every worker and every HTTP engine in the process, holding a resolved file's open descriptor, its size, and its prerendered 200 header. A repeat request costs a hash lookup instead of an open plus a stat.
    - New `src/utils/static_send.zig`, which owns moving a byte range to a socket: `sendfile` on Linux for a cleartext response, a positional read plus the engine's own write otherwise. Zero copy is refused whenever a response is encrypted or staged, so no path can put plaintext on the wire.
    - Two new flat config fields on `zix.Http`, `zix.Http1`, `zix.Http2`, and `zix.Http3`: `public_dir_cache_ttl_ms` (default 0) and `public_dir_cache_max_entries` (default 256). The default of 0 means never cached, so an existing deployment behaves exactly as before.
    - Precompressed `.br` and `.gz` siblings are picked up from disk, resolved once when the entry is built rather than probed per request, and every variant carries `Vary: Accept-Encoding`. Nothing is compressed on the fly.
    - Range (RFC 7233) is served from the cached file on `zix.Http`, `zix.Http1`, and `zix.Http2`, with the 206 header rendered per request and 416 for a well-formed range past the end. A malformed header is ignored and the whole file is sent, which is what RFC 7233 section 3.1 asks for. `zix.Http3` serves whole files only.

    ---

- `public_dir` on `zix.Http2` and `zix.Http3`, which had no static file serving at all:
    - `zix.Http2` frames a file as one HEADERS frame plus DATA frames capped at the peer's `SETTINGS_MAX_FRAME_SIZE`, the last carrying END_STREAM. Both the cached and uncached paths are built, so `public_dir` behaves the same whether or not caching is enabled.
    - `zix.Http3` differs by necessity: an HTTP/3 response body outlives its handler, since a body too large for one packet is parked in a send-stream slot and re-read for every packet and every retransmission. Its body therefore comes from a cache-held snapshot, and the cache pin is held for the whole response. This is why `public_dir_cache_ttl_ms = 0` disables static serving entirely on that engine rather than merely disabling the cache.
    - A file mapping was measured and rejected for that snapshot: rewriting a file in place (what copying a new build over a served file does) changes the bytes under a response still reading them, and a file that shrank would fault past its own end. A snapshot cannot be changed underneath a response.

    ---

- `zix.Http.Client` timeouts are now enforced, and every HTTP-family client read is bounded:
    - `response_timeout_ms` and `read_timeout_ms` were stored but never applied, so a server that accepted the connection and then went quiet parked the caller forever. Both now gate the read behind a readiness poll (`src/utils/socket_poll.zig`): `error.ZixResponseTimeout` when the response head never arrives, `error.ZixReadTimeout` when the body stalls mid-transfer. A budget of 0 keeps the old blocking behaviour byte for byte.
    - The same bound covers the Unix-domain-socket request path, the HTTP/2 client's handshake and record reads, and the test runner's raw TLS reads. The SSE and WebSocket clients gain the same two config fields, bounding the response head and every subsequent event / frame read.
    - `read_timeout_ms` covers Content-Length bodies only: a chunked or close-delimited body has no byte count to end the loop on, so it keeps the unbounded read and only `response_timeout_ms` applies.
    - The test runner retries a check that fails with `ResponseTimeout` / `ReadTimeout`: the check returned an error, so its cleanup ran and no orphan server holds the port, which is what makes the retry safe.
    - Fixed along the way: the HTTP/2 client's raw descriptor reads and writes issued Linux syscall numbers on every non-Windows platform, and macOS plus the three BSDs kill such a process outright. Both paths now route through `src/utils/fd_io.zig`, the shared `windows` / `linux` / `posix` three-way split.

<br>

- `zix.Udp` client `recv_timeout_ms` now enforced on Windows:
    - `receiveFeedback` previously degraded to a blocking receive on Windows, so a client waiting on a silent peer never timed out (this was the source of the Windows CI hang). The receive is now gated by the same AFD-based readiness poll the TCP-family clients use, so `error.ZixRecvTimeout` fires on every platform.
- Named test-run build steps for `--summary all` diagnostics:
    - `zix-build-tests.zig`'s `testRunStep` now tags each integration / behaviour / edge test's `Run` step with its source path (`run.setName(src)`), so `zig build <step> --summary all` shows which file a pending or still-running step belongs to instead of a generic `run test`. No build-command or test-execution change.

<br>

- New engine `zix.Webrtc`, a WebRTC peer (ADR-067):
    - A browser cannot open a raw socket, and WebRTC is the only transport it offers a server that gives unreliable delivery, a per-channel ordering choice, and audio and video. `zix.Webrtc.Server.init(handler, config)` answers one, with the same flat config shape, the same `DispatchModel`, and the same `Tls.Context` as every other engine.
    - Everything arrives on one UDP port and is sorted by its first byte (RFC 7983): ICE connectivity checks over STUN (RFC 8445 / 8489), the DTLS 1.2 handshake (RFC 6347), the SCTP association and its data channels (RFC 9260 / 8831 / 8832), and optionally SRTP media (RFC 3711 / 5764). SDP offer and answer (RFC 8866 / 8829) negotiate all of it. Written from the RFCs on `std.crypto`, with no OpenSSL and no C WebRTC library.
    - Three events reach a handler: `CHANNEL_OPEN`, `CHANNEL_CLOSED`, and `MESSAGE`. A handler answers through `ctx.send`, `ctx.broadcast`, `ctx.openChannel`, `ctx.close`, and `ctx.channelCount`. A `MESSAGE` payload is borrowed for the length of the call and dies on the next one.
    - Media forwarding is off by default. With `carry_media` on, the server becomes a selective forwarding unit: a packet is opened once with the sender's key, its RTP header is rewritten per receiver, and it is sealed again under each receiver's key. Nothing is decoded, there is no codec in the engine. RTCP is answered rather than forwarded, because a report names streams by their pre-rewrite identifiers. The server asks a source for a keyframe when a new receiver is admitted, since nothing in a browser asks on a watcher's behalf.
    - All three dispatch models: `.ASYNC` runs one worker on every platform, `.EPOLL` and `.URING` run one SO_REUSEPORT worker per core on Linux. There is deliberately no CPU steering knob, unlike raw UDP and HTTP/3: a WebRTC peer is its 4-tuple, and receive-CPU steering would split one session across two workers mid-handshake. `max_peers` is counted per worker, so N workers hold up to N times that. The reach of `ctx.broadcast` is one worker.
    - `run()` validates before it binds: `error.ZixPortNotConfigured`, `error.ZixIceCredentialsRequired`, `error.ZixIceCredentialsInvalid`, `error.ZixTlsRequired`, `error.ZixUnsupportedCertificateKey` (the key must be ECDSA P-256, since the one DTLS 1.2 suite here is ECDHE-ECDSA), and `error.ZixDispatchModelUnsupported` off Linux.
    - `accept_any_peer_ice_ufrag` is new and off by default. A browser draws a fresh ICE ufrag for every peer connection, so without it every check from a browser is refused with 401. Turning it on leaves `ice_password` as the only gate, which is what it always effectively was with one server-wide credential set.
    - Eight examples on ports 9081 to 9088, four driven by a browser: a WebSocket signalling relay, a STUN binding server, a data channel echo, a native zix-to-zix pair, a room chat, a file transfer, a media forwarding broadcast, and a mesh video call. Load the browser pages by the machine's network address rather than `localhost`, because a browser gathers no loopback candidate and will not pair with one.
    - DTLS 1.2 landed in `src/tls/` with a flat `dtls_` prefix, beside the TLS 1.2 and 1.3 code it shares primitives with: record layer with anti-replay, handshake fragmentation and overlap-safe reassembly, stateless HMAC cookies, the retransmit state machine, RFC 5705 keying material export, the RFC 5764 `use_srtp` extension, plus a server driver and a client. It keeps no separate public surface.
- Test runner result lines now name the example they run:
    - A check reports as `zix-example-<file>-<arch>-<os>` instead of a short label, so a line names a file a reader can open, matching what the driver suites already print. The name is composed in `tests/runner/report_name.zig` (std only, with its own test step), because the runner builds its own copy of each example rather than running the installed binary. `--only` accepts either the short label or the printed name.

<br>

- New executable `zixer`, a config-driven proxy gateway built on the engines:
    - A service goes behind it by writing one text file, not by changing the service. One daemon holds many independent sites, one site per `.cfg` file, each with its own port and engine. `zig build zixer` produces `zig-out/bin/zixer-<triplet>-<optimize>`, and it carries no version of its own: `zixer version` reports the package version, so a binary names the engine build it was cut from.
    - Commands: `init` scaffolds the root dir, `status` validates every config and exits 1 on any fault, `list` names the site files, `start` / `stop` / `restart` act on one site over a unix control socket, and `daemon` / `daemon stop` run and end the process that owns the listeners. The first `start` spawns the daemon when the socket is silent. A running site never picks up an edit by itself, so `restart` is what a certificate renewal hook calls once new files land on disk.
    - Five edges, chosen by the `engine` key: `http1` (SSE, the rfc 6455 websocket tunnel, and static files), `http2` (prior-knowledge sniff or ALPN, with rfc 8441 extended CONNECT bridged to an h1 websocket backend), `grpc` (h2 on both legs so trailers survive the hop), `http3` (QUIC and HTTP/3 terminated in zixer), and `udp` (a per-flow datagram forward, one ephemeral socket per client address). Every engine except `udp` re-originates: the client framing is parsed and a fresh upstream message is built, so raw client bytes never splice through.
    - TLS terminates at the edge over the zix TLS stack, with the ALPN list taken from the site engine and a `Host` the certificate does not cover answered 421. The upstream leg stays cleartext, so nothing behind the gateway needs a certificate. http-01 renewal is answered from `acme_webroot` or relayed through `acme_proxy`, and `force_https` with `redirect_host` moves a cleartext request to the https origin (301 for GET and HEAD, 308 for every other method, so the repeat never drops a body). Both live on a port 80 companion listener a TLS site binds beside its own, and a bind failure there fails the whole `start` rather than leaving renewal silently broken.
    - Static files per site through `public_dir`, `public_prefix`, and `spa_fallback`, with precompressed `.br` and `.gz` siblings probed against `Accept-Encoding`. `public_dir_cache_ttl_ms` keeps those files open between requests, using the table `zix.utils.static_cache` already builds, so one file costs one descriptor for the daemon rather than one per accept loop. The cache can never fail a request: anything it cannot answer falls through to the plain open.
    - Upstreams are picked round-robin with O(1) availability, and a connect failure marks a backend down for a cooldown window that is re-checked at pick time, so there is no probe thread and no health check. Idle keep-alive connections are cached per upstream and aged out by one background thread per site. rfc 9209 `Proxy-Status` rides on every failure the gateway itself produced, so a 502 it wrote reads differently from a 502 an upstream sent.
    - Bounded on both legs. `client_timeout_ms` and `client_conn_limit` bound how long one client exchange may take and how many client connections a site tracks, where a connection past its budget is cut from a sweeper thread and answered 408, and a connection past the ceiling is refused 503 before it has sent a byte. `upstream_timeout_ms` bounds the wait on a silent backend, `upstream_connect_timeout_ms` bounds one connect attempt, and `upstream_idle_ttl_ms` bounds how long an unused backend connection is kept. `process_limit`, `process_queue_len`, and `process_queue_timeout_ms` are the overload valve in front of the backend, and a long-lived exchange (a websocket, an SSE stream, a grpc stream) hands its slot back at handover rather than pinning it for the life of the socket.
    - Two optional `[section]` blocks at the end of a site file, `[response_headers]` and `[request_headers]`, add headers on the client leg and on the upstream leg. A value may name `$client_ip`, `$scheme`, or `$host`, and the scheme comes from the site's own `tls` setting rather than from anything a client claimed.
    - Validation comes before anything binds. An unknown key, a bad value, or a key that cannot apply to this engine is refused with a fix hint, never a silent default. Numeric values take integer math (`16 * 1024`), where an inexact division is a fault rather than a truncation. Faults are collected rather than raised one at a time, so one report shows every problem in a file at once, and `status` reads the same parser the daemon reads.
    - `workers` runs several accept loops per site, each with its own listener, upstream pool, and idle cache, and the site's idle bound is divided between them so a backend never loses more of its capacity because the edge runs more loops. On Windows the count is 1, because address reuse there is a takeover rather than a join.
    - Named gaps, written into the docs rather than left to be discovered: nothing writes into `logs_dir`, `dispatch` is validated and reported but nothing reads it, there is no per-path routing, rate limiting, or response caching, and `main.cfg` is read once per daemon rather than reloaded.
    - Docs are `docs/zixer/README-en.md`, `how-to-use-en.md`, `config-en.md`, `hld-en.md`, and `lld-en.md`, each with a Bahasa Indonesia twin. 15 runnable demos live under `examples/proxies/`, one upstream plus one site config each, and `zig build zixer-test-runner-all` starts every one in its own throwaway root and drives it end to end. `zig build zixer-unit-test` is the in-process suite and is a separate step from zix's own, because zixer keeps its own build files.

<br>

- Test-suite identifiers renamed: every one-to-four character name whose meaning had to be guessed now says what it holds:
    - `tests/runner/all_runner.zig` declared all 55 of its check trampolines as `fn f`, a name that carries nothing. They are `fn call`, the same shape `tests/zixer/all_runner.zig` already used. The scheduler locals follow: `c` is `check`, `Fut` / `futs` are `CheckFuture` / `futures`, `fill` is `path_idx`, and `cpu` is `cpu_count` because it holds a count rather than a core.
    - The HTTP/3 test blocks each kept a private hex helper called `fn h`. It is `fn hexBytes` across all 15 files and 167 call sites. Handler stubs inside test blocks (`fn h`, `fn f`) are `fn handle`, and the `const H` handler factory in `src/tcp/http2/router.zig` is `Handlers`.
    - About 48 files under `tests/` carried locals a reader had to trace back to a declaration line: `t` is `server_thread`, `sa` is `server_addr`, `al` is `allocator`, `rd` / `wr` are `reader` / `writer`, `fh` is `frame`, `hbuf` is `header_buf`, `hdec` / `enc` are `hpack_decoder` / `hpack_encoder`, `flen` is `flight_len`, `rnd` is `random_bytes`, `fba` is `pem_fixed_buf`. The HTTP/3 test client took the deepest pass, including `w` to `writer`, `u8v` / `u16v` to `writeU8` / `writeU16`, and `pp` / `fl` / `cl` / `rp` to `payload_len` / `fields_len` / `content_len` / `payload_pos`.
    - Bounded, well-known abbreviations keep their natural length and were left alone: `io`, `ctx`, `buf`, `fd`, `len`, `pos`, `conn`, `req`, `res`, `gpa`, `cfg`, and the QUIC terms `sid`, `scid`, `dcid`.
    - Names only, no behaviour change. Verified with the full test suite, all 55 runner protocols, and the 13 zixer proxy demos.

<br>

## 0.5.x-rc2 (2026-07-27)

__*Update:*__

- Breaking: `zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Fix` gain the Request/Response/Context trio and the explicit Router idiom (ADR-063), matching `zix.Http1` (ADR-062) and `zix.Http3`:
    - `HandlerFn` is now `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void` on every engine. `zix.Http2` had none of the trio before (raw `method`/`headers`/`body`/`fd`/`sid` args), `zix.Grpc` had raw headers plus `GrpcContext`, `zix.Fix` had raw fields plus `FixContext`. `Request` and `Response` are thin views/builders over each engine's existing wire writers (byte-identical output), `Context` carries `io`, a per-request stack arena allocator (`FixedBufferAllocator`, no heap call), and the timeout helpers `withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut`.
    - Router: `Server.init(handler, config)` everywhere, `handler` built via `zix.ENGINE.Router(&[_]zix.ENGINE.Route{...}).dispatch`. `zix.Fix.Server.init` takes `handler: ?HandlerFn`, `null` keeps the existing echo-only mode. `zix.Grpc.Server.init` is the one exception: it takes `Router(&routes)` itself, not `.dispatch`, because the engine reads `Route.is_server_streaming` before dispatch to pick sync-inline vs task-spawn, and a bare handler pointer cannot carry that metadata (measured by a wide per-core RPS margin between the two paths before deciding).
    - `zix.Http3` gains `Context` and the `anyerror!void` error channel (`Request` / `Response` already existed), `Server.init(handler, config)` was already in place and is unchanged.
    - Handler-error wire policy: `zix.Http`, `zix.Http2`, `zix.Http3` auto-send one 500 when the handler errors and nothing was sent yet. `zix.Grpc` and `zix.Fix` pass the error through silently, current wire behavior kept.
    - New per-engine config field: `handler_timeout_ms` on `Http2ServerConfig` and `Http3ServerConfig` (both had no timeout concept before), seeded onto `Context.deadline_ns` at dispatch.
    - Migration: every example and integration/edge/behaviour test across all five engines was updated to the new call shape. `zig build test-all` and `zig build examples` are green on `zig-0.16` and `zig-0.17`.

    ---

- Platform cross-build support, target-suffixed examples, platform-aware tests and runners:
    - The whole tree (module, examples, all four test suites, the test runners, and the postgrez / rediz / prometheuz drivers) builds with Zig 0.16.x and Zig 0.17.x for x86_64-linux, x86_64-windows, aarch64-macos, aarch64-linux, x86_64-freebsd, x86_64-netbsd, and x86_64-openbsd. Windows socket I/O rides a small ntdll shim (`src/utils/windows_io.zig`: NtReadFile / NtWriteFile / NtClose plus the AFD partial-disconnect), the BSDs get TCP_NODELAY resolved comptime (`std.posix.TCP` is void there on Zig 0.16), and every Linux-only path (EPOLL / URING loops, CPU affinity, madvise, raw UDP batching) is comptime-gated. On non-Linux targets `.EPOLL` / `.URING` keep falling back to `.POOL`. Windows degrades where the platform lacks the primitive: logger file logging is suspended (console logging stays), poll-based timeouts become blocking reads, no CPU pinning, UDS and raw UDP return runtime errors.
    - Installed example binaries are named `example-<name>-<arch>-<os>` (drivers: `<driver>-example-<name>-<arch>-<os>`), so per-target builds coexist in `zig-out/bin`.
    - Test suites are platform-aware: on a foreign `-Dtarget` every suite compiles and execution is skipped with a warning, on a non-Linux host the EPOLL / URING tests print a warn and skip, and Linux-scaffolded tests skip silently.
    - `aarch64-linux` stays compile-only even on a host with qemu-user registered in `binfmt_misc` (which would otherwise execute the cross-compiled binary transparently): the test steps depend on the compile artifact directly instead of a Run step, so coverage is deterministic regardless of host emulator configuration.
    - Runners are platform-aware: a foreign target compiles the runner plus its servers and passes with a warning, and on a non-Linux host every EPOLL / URING scenario reports `PASS <label> (WARN: ... Linux-only, scenario skipped ...)`.
    - `scripts/build-all-targets.sh` sweeps every build option of zix and the three drivers over all seven targets, records failing legs instead of aborting, and reports them at the end.

    ---

- Breaking: `zix.Http1` hot path handler becomes the Request/Response/Context trio (ADR-062):
    - `HandlerFn` is now `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void`, replacing the raw `fn(head: *const ParsedHead, body: []const u8, fd: fd_t) void`, matching `zix.Http`'s shape. `Request` is a zero-copy view, `Response` delegates to the existing byte-identical fd writers, `Context` carries `io`, a per-request arena, the fd, and deadline hooks. `core.invokeHandler` builds the trio per request and writes exactly one 500 on a handler error that has not already sent a response, on every dispatch model including the TLS buffer path.
    - Canonical `send*` naming on both engines: `zix.Http1` renames `json` / `text` / `raw` to `sendJson` / `sendText` / `sendRaw` and gains `sendNoContent`, `sendFromCache`, `sendCached`, `sendNegotiated`, `sendStream`, `setKeepAlive`, `addHeader`. `zix.Http` renames `noContent` / `serveCached` / `stream` to `sendNoContent` / `sendFromCache` / `sendStream` and gains `sendText`, `sendRaw`. `Request.param` becomes `pathParam` on `zix.Http1`, both engines gain `queryParams`, `pathSegments`, `body()`, `fromRaw`, `keepAlive`. Typed trio surface on both: `setStatus(Status.Code)`, `setContentType(Content.Type)`, `req.method()` returns `Method.Code`.
    - `zix.Http1`'s `initRaw` and the `RawFn` hook are removed, `Server.init(handler, config)` is the single entry. `middleware.zig` is deleted from `zix.Http` (comptime wrapper composition, `examples/http_middleware.zig` / `examples/http1_middleware.zig`, is the middleware idiom on both engines now).
    - Migration: rename `json` / `text` / `raw` / `noContent` / `serveCached` / `stream` / `param` call sites per the mapping above, replace a raw `fn(head, body, fd) void` handler with the trio signature, and drop any `initRaw` usage. All in-src handlers, every `examples/http1_*.zig` and `examples/tls/tls_http1_*.zig`, and the http1 integration tests were migrated as part of this change.

    ---

- Fast gzip encoder for dynamic responses (`compression.flate_fast`):
    - An in-tree gzip encoder (greedy LZ over a single-probe hash table, fixed-Huffman coding, precomputed bit-reversed code tables, 64-bit accumulator) for bodies under 64 KiB, several times faster than the std matcher at a ratio near the std fastest level. Output is standard RFC 1952 gzip, round-trip covered against the std decoder including empty, incompressible, uniform, and near-cap inputs.
    - `zix.Http1` `sendGzipFD` takes this path automatically for bodies inside the cap, larger bodies keep the `std.compress.flate` path. No API change.
    - On the local isolate bench the dynamic gzip json cell moved from ~35K to 154-173K across 512/4096/16384 connections.

    ---

- `zix.Http1` send-path latency and in-place render:
    - `.URING` intra-batch submit: while dispatching a deep completion batch (128 or more completions), staged send SQEs are pushed to the kernel every 16 completions instead of only after the whole batch, so early responses leave immediately instead of waiting for every later request's dispatch. Shallow batches skip the stride. On the local isolate bench this lifted the dynamic-render json cell 4-5% and the 4096-connection pipelined and baseline cells 2-5%, with the 512-connection cells unchanged.
    - `.URING` adaptive wakeup coalescing: a hot worker loop waits for up to 32 completions per enter (wait_nr = half the last reap, decaying to 1 as load drops) with a 20 microsecond timeout SQE as the stall guard, so staggered arrivals stop waking the worker once per completion. A cool loop behaves exactly as before.
    - `.URING` accept fast path: a freshly accepted connection's recv SQE is submitted immediately inside the accept handler instead of after the rest of the completion batch dispatches, cutting accept-to-first-byte under connection churn (api-4 p99 dropped about 30% locally).
    - `responseReserve(fd, max_body)` / `responseCommit(fd, status, content_type, body_len)`: a handler that builds its body dynamically can render straight into the response sink's buffer, so the body bytes are written exactly once (no handler-side scratch buffer, no staging copy) and the engine builds the simple header directly in front of them. A refused reserve (pipelined batch in progress, region does not fit) stages nothing and the handler falls back to `writeAllFD`. Works on `.URING`, `.EPOLL`, and the TLS capture path.
    - `.URING` short send: the staged window now advances in place (`staged_off`) instead of shifting the remainder to the buffer front.

    ---

- Engine-worker DB lanes: `zix.Http1` `.URING` gains an external fd watch and `postgrez` gains `dispatch.Line`:
    - `zix.Http1.uringWatchFd(fd)` arms a multishot readable watch for a foreign fd (a driver socket) on the worker's own ring, and `zix.Http1.setExternalHandler(cb)` registers the per-worker callback that runs on the worker thread. The engine sustains the watch (a lapsed multishot re-arms while the fd is alive), and a full submission queue parks the arm on the process queue, so a watch is never dropped while parking has room. The other `.URING` engines ignore the new completion op.
    - `postgrez.dispatch.Line`: a reactor-less single-connection pipeline (open, submit, flush, pump, pending) for a caller that owns its own event loop. submit stages, the caller flushes once per batch (pump flushes too) so many requests leave in one write, pump reads and delivers framed replies in submit order, and a closed peer surfaces as `error.ConnectionClosed`. `Transport` is unchanged.
    - Together a server worker can own pipelined database connections on its own ring, so a reply decodes, renders, and writes on the core that owns the client socket, with no cross-thread handoff.

    ---

- `zix.Http1` `.URING`: an oversized request body (larger than the receive buffer) now drains before its handler runs, and the received bytes are counted and exposed as `Request.bodyReceived()`:
    - Previously the handler ran first with an empty body slice (so the response could leave before the body finished arriving) and the drained remainder was discarded uncounted, leaving `head.content_length` as the only size a handler could report. The engine now counts every drained byte, defers the handler to drain completion, and `req.bodyReceived()` returns the counted total. On every dispatch model it equals `body().len` whenever the body fit the buffer. Small-body requests take the identical path as before, `.EPOLL` and the thread models keep their existing order.

    ---

- Two internal database drivers, `postgrez` (PostgreSQL) and `rediz` (Redis), pure Zig std only, no C dependency:
    - `postgrez`: wire protocol 3.2 with an in-place 3.0 fallback (PostgreSQL 15 minimum), binary-first value encoding with a text fallback per parameter, prepared statements, query pipelining, a batching `Executor`, a thread-safe `Pool`, SCRAM and SCRAM-PLUS (channel binding) plus cleartext auth, TLS 1.3, COPY streaming, LISTEN and NOTIFY.
    - `rediz`: RESP3 via HELLO with an in-place RESP2 fallback (Redis 7 and 8), typed value helpers plus a raw command escape hatch, command pipelining and a deferred write-behind path, a thread-safe `Pool`, TLS 1.3.
    - Both drivers share a `dispatch_model` config: `.ASYNC` (the pooled / executor path, the default) or `.EPOLL` / `.URING` (`Transport`, a single-thread multiplexed dispatch that pipelines many requests per connection, cleartext only).
    - Docs: `docs/driver/postgrez` and `docs/driver/rediz` (README, HLD, LLD, config reference, English and Indonesian).

    ---

- `prometheuz`, a third internal driver (Prometheus and node-exporter), pure Zig std only, no C dependency:
    - Prometheus text exposition format 0.0.4 parser (scrape), a background `Scraper` poller, `remote_write` push (protobuf plus snappy), PromQL instant and ranged query, and an app-authored metric registry (`Counter`, `Gauge`) for values that never come from a scrape.
    - Own minimal HTTP/1.1 client, cleartext only: unlike `postgrez`/`rediz` there is no pooled or multiplexed transport, GET/POST over `Content-Length` or chunked response bodies is the only transport this driver needs.
    - Docs: `docs/driver/prometheuz` (README, HLD, LLD, config reference, English and Indonesian).

<br>

__*Fix:*__

- Client `send_timeout_ms` wiring (`zix.Uds`, `zix.Tcp`, `zix.Fix`):
    - The client-side `send_timeout_ms` config field was accepted but never enforced (a leftover helper that set `SO_SNDTIMEO` existed but was never called). `UdsClient.sendMsg`, `TcpClient.sendMsg`, and `FixClient.sendMessage` now poll the socket for writability before sending and return `error.SendTimeout` on expiry, the same approach already used for `recv_timeout_ms` (`SO_RCVTIMEO` is not used: `std.Io.Threaded` panics on `EAGAIN`). `FixClient` also gained the `send_timeout_ms` field itself, previously dropped from its config entirely.

    ---

- Documentation corrections across `docs/` and the README:
    - `zix.Http`: docs claimed no TLS support ("proxy-terminated by design"), TLS has been available since ADR-053.
    - `zix.Grpc`: docs had no mention of the response cache (ADR-036) or the TLS dual listener (ADR-060), both already implemented.
    - `zix.Uds`: docs (and the `zix.Tcp` docs' own comparison, and ADR-022) claimed UDS frames use little-endian, they use big-endian, matching TCP, and always have (ADR-010).
    - `zix.Fix`: docs and a worked example used the field name `connection_timeout_ms`, the real field is `conn_timeout_ms`.
    - `zix.Tcp`: docs used `max_msg_len`, the real field is `max_recv_buf`. `docs/lld-tcp-en/id.md` was also missing the `.EPOLL` / `.URING` dispatch models entirely.

<br>

## 0.5.0-rc1 (2026-07-15)

__*Update:*__
- Zig 0.17 (experimental) support: one source tree builds on Zig 0.16.x and 0.17.x, the few `std.Io` API divergences gated behind a comptime `ZIG_SEMVER` check (ADR-044).

- Breaking: `dispatch_model` is now a required config field with no default. Every server config (`Http1ServerConfig`, `HttpServerConfig`, `Http2ServerConfig`, `GrpcServerConfig`, `FixServerConfig`, `TcpServerConfig`, `UdpServerConfig`, `Http3ServerConfig`) drops the `.ASYNC` default, so the caller must set `dispatch_model` explicitly.

- Breaking: `Server.init` is uniform and infallible across the HTTP-family engines (ADR-014):
    - `zix.Http`, `zix.Http2`, `zix.Grpc`, and `zix.Http3` now store the config at `init` and cannot fail, with port and TLS validation moved to `run()` (`error.PortNotConfigured`, `error.TlsRequired`). This matches `zix.Http1`, so every engine constructs the same way: `init` bakes the comptime handler or route table into the type, `run()` validates then serves.
    - `zix.Http3` gains a `Server` struct: `zix.Http3.Server.init(handler, config)` replaces the `zix.Http3.Http3(handler)` generic-function entry point (the generic is now the private `Http3ServerImpl`).
    - `zix.Http.Server.init` drops its leading comptime `stack_threshold` argument, so the call is `Server.init(routes, config)`. The per-connection read buffer sits on the connection thread stack when `max_recv_buf` fits the internal `stack_read_buf_max` (4096) and heap-allocates otherwise, with `max_recv_buf` (config) the tuning knob. The unused `HttpServerConfig` field `max_client_response` is removed.
    - Migration: `zix.Http.Server.init(4096, &routes, cfg)` becomes `zix.Http.Server.init(&routes, cfg)`. `const S = zix.Http3.Http3(handler); var s = try S.init(cfg)` becomes `var s = zix.Http3.Server.init(handler, cfg)`. Drop `try` on `zix.Http2` / `zix.Grpc` / `zix.Http` init (an invalid port now surfaces from `run()`). Remove any `.max_client_response = N` from an `HttpServerConfig`.

- `zix.Http` https serve path (ADR-053):
    - `zix.Http` gains opt-in TLS (`config.tls`), the third HTTP engine to serve https/1.1. Each connection runs the handshake (TLS 1.3, with a 1.2 ECDSA fallback) and the keep-alive request loop on its own worker thread, the router response captured through the engine's existing response sink and encrypted, so a handler writes a normal Response and the cleartext path adds no hot-path cost. Buffered responses by default (WebSocket is a follow-up, SSE / streaming over TLS landed in ADR-054). New example `examples/tls/tls_http_basic.zig` (port 9071).
    - The multiplexed Http2 and gRPC TLS workers now pin per-core and size the worker count by the available cpuset (ADR-052 parity with Http1's `tls_mux`), so a cgroup-pinned cpuset no longer oversubscribes one core under a handshake storm.

    ---

- SSE / streaming over TLS (ADR-054):
    - `zix.Http` and `zix.Http1` serve Server-Sent Events over TLS on the thread-per-connection path (`.ASYNC` / `.POOL` / `.MIXED`). A per-connection stream sink (`TlsStreamSink`, type-erased over the live TLS 1.3 / 1.2 connection) encrypts one TLS record per write and sends it immediately, replacing the buffered capture only when a handler opts into streaming. `fdWriteAll` checks the buffered sink first, then the stream sink, so a normal response keeps the buffered fast path untouched.
    - `zix.Http` reuses `res.stream()` (no new public symbol, it now keeps the stream sink active over TLS). `zix.Http1` gains `beginStream()`, a no-op in cleartext, so one fd-handler serves cleartext and TLS. The multiplexed `tls_mux` path (`.EPOLL` / `.URING`) stays request / response only (later lifted by ADR-060 below).
    - New examples `examples/tls/tls_http_sse.zig` (port 9072) and `examples/tls/tls_http1_sse.zig` (port 9073), with runner steps `test-runner-tls-http-sse` / `test-runner-tls-http1-sse` (native `zix.Tls` client, no curl), folded into `test-runner-all`. `examples/http1_sse.zig` now calls `beginStream()`.

    ---

- WebSocket over TLS (ADR-055):
    - `zix.Http` and `zix.Http1` serve WebSocket over TLS (wss) on the thread-per-connection path (`.ASYNC` / `.POOL` / `.MIXED`). A handler calls `WebSocket.serveTls(fd, key, on_frame)`: it sends the `101` encrypted through the ADR-054 stream sink and registers a handoff, then the https serve loop runs an inline frame loop over the TLS session (decrypt records, parse frames, `on_frame` for text / binary, ping auto-ponged, close auto-echoed). Outbound frames re-use the ADR-054 stream sink, so each pump pass encrypts its coalesced frames as one record.
    - `zix.Http1` re-uses its existing frame codec (`parseFrame` / `pump` / `send`) and the `requestWebSocket` / `takeWebSocket` handoff. `zix.Http` gains the matching engine-driven pieces (`WsFrameFn`, `send`, `pump`, the handoff, `upgradeFd`), so the same `on_frame(fd, opcode, payload)` and `serveTls` work on both engines. Rooms / broadcast are not served over TLS (per-session encryption), so wss is per-connection / echo. The multiplexed `tls_mux` path stays request / response only (later lifted for `zix.Http1` by ADR-060 below).
    - New examples `examples/tls/tls_http1_ws.zig` (port 9074) and `examples/tls/tls_http_ws.zig` (port 9075), with runner steps `test-runner-tls-http1-ws` / `test-runner-tls-http-ws` (native `zix.Tls` client, no websocat), folded into `test-runner-all`.

    ---

- TLS dual listener (ADR-060):
    - New flat config field `tls_port: u16 = 0` on `Http1ServerConfig`, `HttpServerConfig`, `Http2ServerConfig`, and `GrpcServerConfig`: with `tls` set and `tls_port` non-zero, ONE server serves cleartext on `port` AND TLS on `tls_port` from the same worker fleet, replacing the two-launch setup that duplicated workers, fd tables, and caches. `tls_port == port` is rejected at `run()` (`error.TlsPortConflict`). Defaults unchanged: `tls` null stays cleartext-only, `tls` set with `tls_port` 0 stays TLS-only.
    - The per-connection TLS transport is shared in `src/multiplexers/tls_conn.zig` (session + backpressure staging + fd slot table), replacing four near-identical copies in the `tls_mux.zig` files. Engine loops stay per-engine (ADR-050).
    - Under `.URING` the TLS side rides the ring (`tls_accept` / `tls_recv` / `tls_send` user_data ops), no hidden epoll fleet. Under `.EPOLL` the TLS listener joins the same epoll, tagged in the event data word. The thread models serve the TLS side with one extra accept thread.
    - The `zix.Http1` mux loop now hosts WebSocket and SSE over TLS (encrypt-on-write through the per-connection stream sink), and the `zix.Http` mux loop hosts `res.stream()` over TLS, lifting the ADR-054 / ADR-055 thread-path restriction there.
    - New example `examples/tls/tls_http1_dual.zig` (ports 9076 cleartext / 9077 TLS), runner check `tls-http1-dual`, and per-engine dual-listener integration tests.

    ---

- `zix.Http2` native `.EPOLL` / `.URING` dispatch (ADR-043):
    - `zix.Http2` h2c gains the shared-nothing multiplexed loops it previously folded to `.POOL`. A resumable h2 mux state machine (`src/tcp/http2/mux.zig`, one `MuxConn` per fd, the read accumulator persists across readable events) is driven by `dispatch/epoll.zig` (one `SO_REUSEPORT` listener plus epoll plus a slab `ConnTable` per worker) and `dispatch/uring.zig` (one io_uring ring per worker, multishot accept, generation-tagged `user_data`). On the ring the worker owns accept plus recv and the handler writes the reply straight to the non-blocking fd (no per-stream cork). `.URING` probes the ring at startup and falls back to `.EPOLL` when io_uring is unavailable, both fold to `.POOL` off Linux.
    - `zix.Http2.Router` gains query-stripping and `.kind = .PREFIX`, mirroring `zix.Http1`: the query is stripped before matching, EXACT routes use a `StaticStringMap`, PREFIX matches the longest registered prefix on a segment boundary. `RouteKind` is exported.
    - New example family `examples/http2_basic_{1_async,2_pool,3_mixed,4_epoll,5_uring}.zig` (ports 9065-9069) with runner steps `test-runner-http2-{async,pool,mixed,epoll,uring}`, folded into `test-runner-all`.

    ---

- `zix.Http2` memory and throughput optimization (per-worker stream-slot pool, ADR-058):
    - Per-worker stream-slot pool (`src/tcp/http2/mux.zig`): the `.EPOLL` / `.URING` mux borrows each stream's slot (header table plus body / scratch buffers) from a thread-local free-list on stream open and returns it on close, so resident stream memory tracks concurrent streams instead of `connections * max_streams`. Each connection keeps only a `max_streams`-wide pointer array, and the steady state does no per-stream allocation (buffers reused across borrows). At 4096 connections this cut baseline-h2c memory about 6x while lifting throughput 8 to 20 percent, because the pooled hot slots have a tighter cache working set than the old sparse per-connection table.
    - HPACK response-header prefix cache (`src/tcp/http2/hpack.zig`, `respHeaderBlock`): the `[:status, content-type, content-encoding]` block for a hot triple is encoded once and reused byte-identical across connections (a stateless encoder, never the dynamic table), only `content-length` is encoded per reply. Lifted the small-body cells 18 to 26 percent at lower CPU.
    - Seal-in-place on the TLS 1.3 record path (`src/tls/record.zig` `protect2`, `src/tls/connection.zig` `writeAppData2`, `src/tcp/tls/tls_session.zig` `encrypt2`): a gather-encrypt that seals two plaintext slices into one record without a staging copy.
    - Config defaults: `Http2ServerConfig` / `ServeOpts` default `max_streams` 16 to 128 (advertised concurrency, cheap now the slot is pooled) and `max_body` 64 KiB to 16 KiB (buffered request body per stream, a larger body sheds the stream with 413). `max_header_scratch` stays 4 KiB.

- `zix.Grpc` memory and throughput optimization (per-worker stream-slot pool, ADR-058):
    - Per-worker stream-slot pool (`src/tcp/http2/grpc/core.zig`): the `.EPOLL` / `.URING` gRPC mux borrows each stream's slot (header table plus body / scratch buffers) from a thread-local free-list on stream open and returns it on close, so resident stream memory tracks concurrent streams instead of `connections * max_streams`. Each connection keeps only a `max_streams`-wide pointer array, and the steady state does no per-stream allocation (buffers reused across borrows). At 1024 connections this cut unary-grpc memory about 12x (916 to 77 MiB) while lifting throughput 8 to 11 percent, the same both-axes result as the Http2 pool. The blocking `.ASYNC` / `.POOL` / `.MIXED` path keeps its own per-connection arrays, unchanged.
    - Config defaults: `GrpcServerConfig` / `GrpcServeOpts` default `max_streams` 16 to 128 (advertised concurrency, cheap now the slot is pooled) and `max_body` 64 KiB to 16 KiB (buffered request body per stream, a larger body sheds the stream with RESOURCE_EXHAUSTED). `max_header_scratch` stays 4 KiB.

    ---

- gRPC over TLS and a shared h2-over-TLS terminator:
    - `zix.Grpc` serves native TLS (TLS 1.3, with a 1.2 fallback, ALPN h2) via `tls: ?*Tls.Context`, additive over the h2c default. The TLS path drives the resumable gRPC mux state machine (`grpcMuxProcessRing`) directly over the decrypted records, the same single-owner engine as the cleartext `.EPOLL` / `.URING` models, so it has no per-stream write races.
    - The h2-over-TLS terminator is factored into a shared, engine-agnostic `src/tcp/tls/h2_terminator.zig` (handshake 1.3 / 1.2, ALPN h2). It runs a caller-supplied inline-mux driver over the decrypted records and seals the engine's frames back into TLS records through a thread-local write hook, with no socketpair and no second thread. `zix.Http2` and `zix.Grpc` `tls_serve.zig` are thin wrappers supplying the driver.
    - Multiplexed TLS dispatch (ADR-052): for `.EPOLL` / `.URING`, one `SO_REUSEPORT` epoll worker per core terminates TLS in place via a resumable TLS 1.3 session (`src/tcp/tls/tls_session.zig`) and multiplexes many connections per worker (`tls_mux.zig`), so Http2 https and gRPC TLS no longer spawn a thread per connection at high concurrency. `.ASYNC` / `.POOL` / `.MIXED` keep the thread-per-connection terminator, which also serves the 1.2 fallback.
    - Docs `hld-grpc`, `hld-tls`, `lld-tls`, and `hld-grpc-proxy` (en and -id) updated for native gRPC TLS.

    ---

- Response compression (gzip / deflate / brotli):
    - `Accept-Encoding` negotiation with gzip and deflate. New shared codec `src/utils/compression/flate.zig` (container-parameterized over `std.compress.flate`: gzip = RFC 1952, deflate = zlib-wrapped RFC 1950, not raw) plus the `compression.zig` facade (q-value negotiation, `q=0` and wildcard handling, size floor, already-compressed media-type skip, encode/decode dispatch).
    - brotli (`br`) joins the facade as `src/utils/compression/brotli.zig`, an in-tree codec authored from RFC 7932 (std has no brotli): a complete decoder plus an encoder, embedding the 122,784-byte Appendix A static dictionary (`brotli_dictionary.bin`). `.BR` is in `supported_default`, but gzip stays the default at equal q (the in-tree encoder is not yet competitive with gzip on small bodies), so brotli is served when the client prefers it. Interop is verified both ways against the system `brotli` CLI. The encoder always also produces a store-only stream and returns the smaller, so a body never grows (a tiny body simply falls back to identity).
    - `zix.Http1` serves it via `core.writeNegotiated(fd, head, status, content_type, body)`, `zix.Http` via `Response.sendNegotiated(req, body)`, both setting `Content-Encoding` and `Vary: Accept-Encoding`. Active under `.EPOLL` and `.URING`, off by default. gRPC keeps its own per-message `grpc-encoding`, the raw transports have no HTTP negotiation.
    - `std.compress.flate.Compress` is about 230 KB and lives in a per-worker lazily mapped encode scratch (never a stack temporary), keeping the hot path free of allocation syscalls. A compressing worker still spawns with a 2 MiB stack floor (demand-paged, near-zero RSS) instead of the default 512 KB, headroom for the deeper codec call chains. The brotli encoder builds its dictionary index on the heap and the dictionary itself is `@embedFile` `.rodata`, so it adds no stack pressure.
    - Codec caller-buffer parity: `brotli.zig` gains `compressBrotli` / `decompressBrotli` (a buffer-into variant beside each alloc variant), so it mirrors `flate.zig`'s four-function shape. `flate.zig` and `brotli.zig` now expose matching named `EncodeError` / `DecodeError` (`BufferTooSmall` shared), and `compressBound` documents that brotli never expands while flate can. The bespoke `writeGzipCached` stays gzip-only by design (a json-comp A/B showed the unified replacement regresses about 1.2 to 6.8%), so no `writeBrotliCached` twin is added, brotli rides `writeNegotiated`.
    - New examples `http1_compression` (port 9058) and `http_compression` (port 9059), each with `/data` (negotiated) plus explicit `/gzip` `/deflate` `/br` routes that force one coding through the `compression.encode` facade. Individual runner steps `test-runner-http1-compression` / `test-runner-http-compression` (raw-socket, exercising br / gzip / deflate / identity / size-floor), and both examples are folded into `test-runner-all` as the `http-compression` / `http1-compression` rows (raw-socket read, decode, value-check each coding), taking the runner to 69 protocols.

    ---

- TLS (https / h2), pure-Zig on `std.crypto`, no OpenSSL:
    - TLS 1.3 server (RFC 8446) plus a TLS 1.2 floor (RFC 5246 / 5288, ECDHE-ECDSA-AES128-GCM), 1.3 preferred, never below 1.2 (1.0 / 1.1 / SSL never offered, RFC 8996). Sans-I/O handshake in `src/tls`, the HTTP engine owns the socket loop.
    - Native verifying client `zix.Tls.Client` (1.3) and `zix.Tls.Client12` (1.2): offers ALPN, verifies the server signature and the X.509 chain + hostname (RFC 5280 / 6125).
    - https is opt-in and additive (ADR-046): `zix.Http1` serves https/1.1 and `zix.Http2` serves h2 over TLS (ALPN h2), both a gated path in front of the unchanged cleartext engines. HelloRetryRequest, inbound-alert handling, and the misdirected-request 421 (RFC 9110 7.4) are wired.
    - Server TLS is configured by a user-owned `Tls.Context` object (ADR-047), mirroring the logger: `Tls.Context.init(allocator, io, config)` loads the cert / key and validates the policy once. `Tls.Context.Config` exposes `cert_path`, `key_path`, `alpn`, `min_version` / `max_version`, `curves`, `ciphers`, `prefer_server_ciphers`, `hsts_max_age_s`. Curves and ciphers are validated allow-lists (an unsupported value is a startup error). ECDSA P-256 and Ed25519 certificates, ECDHE-only (no dhparam).
    - RSA server certificates (ADR-048): an RSA cert signs the TLS 1.3 CertificateVerify with `rsa_pss_rsae_sha256` (pure-Zig, a constant-time Montgomery modexp in `montgomery.zig` plus EMSA-PKCS1-v1_5 / EMSA-PSS, RSA-2048 minimum). RSA requires TLS 1.3, the default cert type stays ECDSA P-256.
    - New examples in `examples/tls/`: `tls_http1_basic` (9060), `tls_http2_basic` (9061), `tls_http1_ed25519` (9062), with runner steps folded into `test-runner-all`.
    - Docs: `docs/hld-tls-en.md` / `docs/lld-tls-en.md` (and -id), ADR-045 / 046 / 047 / 048.

    ---

- Raw-bytes UDP datagram mode `zix.Udp.Raw` (ADR-049):
    - `zix.Udp.Raw(handler)` serves variable-length datagrams (up to `max_recv_buf`) alongside the typed `zix.Udp.Server(Packet)`. The handler takes the datagram bytes, the peer, and a `Sink` to reply through. On Linux it batches receive / send via `recvmmsg` / `sendmmsg`, replies coalescing into one `sendmmsg` per received batch, with per-core `SO_REUSEPORT` workers under `.EPOLL` / `.URING` (a single worker under `.ASYNC` / `.POOL` / `.MIXED`).
    - Dispatch is partitioned per ADR-043: `src/udp/dispatch/` (one file per model plus `common.zig`) with a thin `run()` switch, plus `src/udp/datagram.zig` (raw-fd socket + `recvmmsg` / `sendmmsg` primitives) and `src/udp/core.zig` (`HandlerFn`, `Sink`). The typed `Server(Packet)` is unchanged, a non-ASYNC `dispatch_model` on it folds with a logged notice. Non-Linux falls back to a single `std.Io.net` loop.
    - New example `examples/udp_server_raw.zig` (port 9064) with runner step `test-runner-udp-raw`, folded into `test-runner-all`. GSO and a dedicated io_uring submission path behind `.URING` land later with ADR-056 (below), GRO / ECN stay deferred.

    ---

- HTTP/3 over QUIC engine `zix.Http3`, pure-Zig on `std.crypto`, on the `zix.Udp` substrate (ADR-051):
    - `zix.Http3.Server.init(handler, config)` serves HTTP/3 (RFC 9114) over QUIC (RFC 9000 / 9001 / 9002), with a comptime `zix.Http3.Router` mirroring `zix.Http1` / `zix.Http2` (EXACT / PARAM / PREFIX, query stripped before matching). TLS 1.3 is mandatory, configured by the same user-owned `Tls.Context` as the TCP engines.
    - The deterministic QUIC / TLS / QPACK layers are pure-Zig from the RFCs: packet protection (header protection plus AEAD), the key schedule (Initial / Handshake / 1-RTT), CRYPTO-stream TLS 1.3 handshake (ServerHello plus the EE / Certificate / CertificateVerify / Finished flight), QPACK static-table field lines, and the RFC 7541 Huffman decoder for request paths.
    - Dispatch models (Linux-only): `.ASYNC` runs one single-worker recv loop with internal connection-id demux (migration-safe). `.POOL` / `.MIXED` run one SO_REUSEPORT recvmmsg worker per core, and `.EPOLL` / `.URING` add epoll readiness / io_uring completion on that per-core shape (`.URING` folds to the epoll worker loop when io_uring is unavailable). Per-core connection-id steering is deferred (ADR-049 phase 3, ADR-050).
    - Hot-path loss recovery and congestion control (ADR-056, superseding the ADR-051 deferrals): ACK-driven loss detection (RFC 9002), an RTT estimator, a Probe Timeout with backoff, and a NewReno congestion window now run on the serve path, so a lossy path recovers instead of a dropped tail packet stalling the whole response. A timer-driven maintenance sweep (every 5 ms) re-pumps a timed-out in-flight range. Only ack-detected loss cuts the congestion window, a PTO retransmits without reducing cwnd (RFC 9002 6.2). The `.EPOLL` and `.URING` models now run real per-core `SO_REUSEPORT` workers (each owns its own connection-id table, `.URING` a real io_uring ring falling back to the `.EPOLL` loop) instead of folding to the single v1 worker. A connection slot is reclaimed only on close or idle past `max_idle_ms`, never on loss, so a live-but-lossy peer stays connected. On the same cut `zix.Udp` raw gains its ADR-049 phase two (a real io_uring recv ring behind `.URING` plus UDP GSO). Cross-core connection-id steering for mid-connection migration stays deferred.
    - `zix.Http3` exports its low-level primitives (`crypto`, `protection`, `keyschedule`, `qpack`, `huffman`, `packet`, `varint`, `frame`, plus `tls_key_schedule`), the same way `zix.Http2` exports its frame / HPACK primitives, so a peer can build the other side of the wire.
    - New example `examples/tls/http3_basic.zig` (port 9063). The runner drives a hermetic native QUIC client hand-rolled from those primitives (no external tool), with runner step `test-runner-http3` folded into `test-runner-all`.
    - Docs: `docs/hld-http3-en.md` / `docs/lld-http3-en.md` (and -id).

    ---

- `zix.utils.multipart` (multipart parser relocated):
    - The `multipart/form-data` parser moved from `src/tcp/http/upload.zig` to `src/utils/multipart.zig`, protocol-agnostic byte parsing shared by `zix.Http` and `zix.Http1`. Types renamed `MultipartParser` to `Parser` and `MultipartField` to `Field`, so the canonical path is `zix.utils.multipart.Parser` / `zix.utils.multipart.Field`. `zix.Http.Multipart` / `zix.Http.MultipartField` stay as thin aliases (no break). `examples/http_static.zig` and `examples/http1_static.zig` call the canonical path, and `examples/http1_static.zig` gains a second upload route (`/upload-multipart`) demonstrating it on `zix.Http1`.

    ---

- Server config (knob) added:
    - `compress` (bool), `compression_min_size` (usize), and `compression_max_out` (usize) on `zix.Http1` and `zix.Http`. The gzip-specific `max_gzip_out` was renamed to the codec-agnostic `compression_max_out`.
    - `tls` (`?*Tls.Context`) on `zix.Http1`, `zix.Http2`, and `zix.Grpc`, the https opt-in gate. Replaces the flat `tls_cert_path` / `tls_key_path` / `tls_alpn` / Http1 `hsts_max_age_s` fields (ADR-047).
    - `dispatch_model`, `workers`, `reuse_address`, `recv_batch`, `send_batch`, `max_recv_buf` on `zix.Udp` (`UdpServerConfig`), used by the raw path (`zix.Udp.Raw`, ADR-049). Additive, the typed `Server(Packet)` is unchanged.
    - `public_dir` and `public_dir_upload` on `zix.Http1` (`Http1ServerConfig`), static file serving for unmatched routes mirroring `zix.Http`. A non-empty `public_dir` is validated at `run()` and yields `error.PublicDirNotFound` when absent.
    - `uring_send_buf_size` (default 16 KiB), `uring_idle_pool_floor` (default 8), and `uring_idle_pool_ceiling` (default 256) on `zix.Http1` (`Http1ServerConfig`), tuning the `.URING` per-connection send buffer and the warm reconnect-pool bounds (see the Http1 / Http memory optimization entry).

    ---

- gRPC server-streaming DATA-frame coalescing (ADR-057):
    - `zix.Grpc` server-streaming packs consecutive messages into fewer, larger HTTP/2 DATA frames (up to the 16 KiB default max frame size) instead of one DATA frame per message. A `count = 5000` reply drops from 5000 tiny DATA frames to about 3, cutting the frame-header bytes on the wire and the client's per-frame parse cost. The fix lives in the shared `muxDispatch`, so `.URING`, `.EPOLL`, and both TLS mux paths inherit it. Unary keeps one frame per message and is byte-for-byte unchanged. The thread path (`.ASYNC` / `.POOL` / `.MIXED`) is not coalesced yet. The bundled `zix.Grpc.Client` unpacks multiple messages from one DATA frame (each `recvResponse` drains the frame's leftover before reading the next), matching the coalescing.

    ---

- HTTP/3 content-encoding negotiation:
    - `zix.Http3` gains content-negotiation on the response. `req.accept_encoding` exposes the client's Accept-Encoding (decoded from the QPACK static entry 31 or a literal, Huffman expanded), and a handler calls `res.setContentEncoding(.br)` / `.gzip`, which emits the `content-encoding` response header as one QPACK indexed line (static index 42 br / 43 gzip). The engine never compresses on the send path: the handler serves an already-compressed body (a pre-built `.br` / `.gz` file), so there is no per-request codec cost and the perf / memory rule holds. Serving the smaller pre-compressed variant is fewer packets per response, which is what moves static serving.
    - The QPACK static table extends from indices 0..28 to 0..43 (RFC 9204 Appendix A), covering `accept-encoding` (31) and `content-encoding` br / gzip (42 / 43). The request decoder scans past the pseudo-headers to capture `accept-encoding`, and `buildRequestStreamContent` / `buildStreamPrefix` emit the `content-encoding` line (`SendStream` stores the coding so a resumed multi-packet body keeps its header). The change lives in the shared `dispatch/common.zig`, so every dispatch model inherits it.
    - `zix.Http3.ContentEncoding` is exported. `examples/tls/http3_basic.zig` gains a `/negotiated` route that serves a brotli-precompressed body with `content-encoding: br` when the client accepts br. Docs `hld-http3`, `lld-http3` (en and -id) updated.

    ---

- HTTP/3 rolling flow-control credit (MAX_STREAMS + MAX_DATA):
    - The QUIC handshake advertises two one-time budgets to the client, `max_streams` request streams and `initial_max_data` (1 MiB) of request bytes across the connection. Both are now rolled forward as the client spends them: the MAX_STREAMS grant (frame 0x12, `replenishBidiStreams`) rises as request streams retire, and the MAX_DATA grant (frame 0x10, `replenishMaxData`) rises as request bytes are consumed. Each grant is emitted once consumption crosses half its window and rides the coalesced reply prologue like the ACK.
    - Fixes a connection-lifetime deadlock: without the byte grant, a connection went silent after about `initial_max_data` of requests, the client blocked on connection flow control and its last in-flight requests were never answered, so a long-lived connection's throughput capped at a hardware-independent constant. With both grants rolling, a connection serves indefinitely.
    - New pieces: `flight.initial_max_data` (the advertised value and the replenish window, one const), `Connection.replenishMaxData`, `request.streamBytes` (sums a packet's STREAM payload bytes across all streams, since connection-level flow control counts them all), and `response.buildMaxData` plus `Framing.max_data`. The wiring lives in the shared `dispatch/common.zig`, so every dispatch model inherits it. Unit tests cover the replenish math, the frame encoding, and the byte counting.

    ---

- Response-API send / write / FD naming taxonomy (ADR-059):
    - The response-writing surface is renamed on two independent axes so a call site reads unambiguously: a function that sends a response, or any outbound communication, is `send*`, a pure write with no send is `write*`, and a signature that takes a raw `fd` parameter ends in `FD` (an fd held inside a struct, reached through `self`, does not count, so object methods stay clean).
    - Breaking for code calling the response helpers directly. The core fd-level helpers rename across every engine: `fdWriteAll` -> `writeAllFD`, `fdWriteAllRaw` -> `writeAllRawFD`, `writeSimple` -> `sendSimpleFD`, `writeSimpleNoBody` -> `sendSimpleNoBodyFD`, `writeJson` -> `sendJsonFD`, `writeGzip` -> `sendGzipFD`, `writeGzipCached` -> `sendGzipCachedFD`, `writeBrotli` -> `sendBrotliFD`, `writeNegotiated` -> `sendNegotiateFD`, `writeChunkedStart` / `writeChunk` / `writeChunkedEnd` -> `sendChunkedStartFD` / `sendChunkFD` / `sendChunkedEndFD`, `writeRange` -> `sendRangeFD`, `write100Continue` -> `send100ContinueFD`. Function bodies and parameters are unchanged, only names and the doc / comment text that references them.
    - Compression-capable engines expose the same six: `sendGzipFD`, `sendGzipCachedFD`, `sendBrotliFD`, `sendBrotliCachedFD`, `sendNegotiateFD`, `sendNegotiateCachedFD`. Negotiate routes internally through the shared gzip / brotli path, so the compression policy lives in one place, and the precompressed / caller-encoded primitive (`sendResponseEncodedFD`) stays as the layer those six build on.
    - Rolled out engine by engine (`zix.Http1`, its WebSocket, `zix.Http2`, `zix.Grpc`, `zix.Http3`, then the full server plus shared tls / dispatch), each step gated by the full test suite. HttpArena entries and the bundled examples move to the new names (call sites only, no behavior change). Docs `hld-http1`, `lld-http1`, `lld-http`, `lld-http2`, `lld-grpc`, `lld-tls` (en and -id) updated. See ADR-059.

    ---

- `zix.Http1` and `zix.Http` memory optimization (EPOLL recv-slab compaction, URING idle-pool bound):
    - EPOLL recv-slab compaction (`src/tcp/http1/dispatch/epoll.zig`, ported to `zix.Http`'s `dispatch/common.zig`): the per-worker receive slab was indexed by global fd (`slab[fd * buf_size]`), so touched pages scattered across the whole 64K-fd space and held far more resident than the live connection set needed. A compact per-worker slot free-list (each `Conn` carries a `slot`, `acquireSlot` reuses a closed slot before bumping a high-water mark, `free` returns the page-aligned stride via `MADV_DONTNEED`) packs resident memory to the live count regardless of fd values. At high connection counts this cut peak Http1 memory about 2.5x (roughly 704 to 281 MiB), bringing `.EPOLL` to `.URING` parity, with throughput held within loopback noise.
    - URING idle-pool bound (`src/tcp/http1/dispatch/uring.zig`): the warm reconnect pool now evicts its least-recently-used tail (`evictColdTail`, a warm MRU list plus a cold stack) past a bound, shrinks a grown per-connection `send_buf` back to the base size on release, and prewarms a small resident floor at startup to avoid a cold-start page-fault storm. Reclaiming the cold tail (not the hot head a reconnect grabs next) keeps the reclaim off the churn hot path, so memory drops without a throughput cost. Bounded by the `uring_send_buf_size` / `uring_idle_pool_floor` / `uring_idle_pool_ceiling` config knobs above.

    ---

- Worker CPU placement (Linux multiplexed engines, ADR-061):
    - New flat config field `reuseport_cbpf: bool = false` on every server config except `zix.Uds`: attach SO_ATTACH_REUSEPORT_CBPF steering to the per-worker `SO_REUSEPORT` group (`src/multiplexers/reuseport.zig`), so the kernel hands a new connection (TCP) or each datagram (UDP) to listener index = receiving CPU mod workers instead of hashing the 4-tuple. Listeners bind inside racing worker threads, so a startup-only bind-order gate serializes the group joins (worker i = group index i). Opt-in, default false: rps-neutral on a loopback box, it targets multi-CPU hosts where NIC RSS spreads softirqs. Never enable it on the QUIC path: per-packet steering breaks QUIC flow affinity (a flow's packets land on different workers) and collapses throughput.
    - Worker pinning extends to `zix.Tcp` and `zix.Fix` (`.EPOLL` / `.URING` workers, cpuset-aware count plus per-core pin), and every engine's pin order now fills physical cores first, SMT siblings after (sysfs topology, mask order kept when sysfs is absent).
    - Per-worker load counters report at worker exit through the system logger (requests, frames, accepted connections, or messages, per engine), so a skewed distribution across workers is observable. The two h2-mux engines (`zix.Http2`, `zix.Grpc`) do not carry the counter: a threadlocal increment in their mux hot loop measured about 1 percent of throughput at multi-million req/s, so it stays off their hot path.

- `zix.Udp` raw `.URING` multishot receive: the per-core ring arms a multishot `recvmsg` with a provided buffer ring (mirroring `zix.Http3`'s recv layer, 256 buffers), replacing per-completion re-arms, with the one-shot slot pool kept as the fallback.

    ---

- `.URING` submission-queue backpressure (process queue):
    - New flat config field `process_queue_len: usize = 0` on `Http1ServerConfig` and `HttpServerConfig`: under `.URING`, a recv or send re-arm that finds the submission queue full is parked on a per-worker FIFO ring of this length (references only, fd plus generation, reject-newest) and retried on the next loop pass instead of closing the connection. 0 (default) keeps the feature off, and it has no effect under the other dispatch models. Size it to about the peak concurrent connections per worker.
    - Lost-accept re-arm fix across the `zix.Http1`, `zix.Http`, `zix.Grpc`, and `zix.Http2` `.URING` dispatches: a multishot-accept re-arm dropped on a full SQ left the worker unable to accept again while the kernel backlog filled. The worker now records the miss (`accept_pending` / `tls_accept_pending`) and retries the arm right after the next submit, so a full SQ no longer wedges accept.
    - `zix.Http3` `.URING` submission-queue losses fixed (`src/udp/http3/dispatch/uring.zig`): a multishot `recvmsg` re-arm lost to a full SQ left the worker permanently deaf (a sticky `recv_unarmed` retry now re-arms it), a one-shot slot re-arm lost to a full SQ leaked the slot (a bounded pending re-arm list now recovers it), and a send tail capped by a full SQ was discarded on the buffer swap (the swap now defers while a tail is still unsent).
    - Oversize request body sheds instead of truncating: `zix.Http2` answers a DATA body past the stream buffer with `413` and END_STREAM (crediting only the connection window for the discarded bytes), and `zix.Grpc` ends the stream with `RESOURCE_EXHAUSTED` trailers. Previously the body was silently truncated to the cap, which could dispatch a corrupt message. A later DATA frame for a shed stream is answered with RST_STREAM, and the connection's other streams continue.

<br>

__*Fix:*__

- `zix.Http1` large-body drain under the thread models:
    - Under `.ASYNC` / `.POOL` / `.MIXED`, a request body larger than the receive buffer was truncated at the buffer boundary and its unread bytes corrupted the next keep-alive request on the connection. The thread path now drains the remainder before serving the next request, matching the `.EPOLL` / `.URING` behavior.

    ---

- `zix.Http` request-body truncation under `.EPOLL` / `.URING`:
    - A multi-segment request body (a large or chunked upload split across reads) was truncated when `body()` / `readChunkedBody()` hit `EAGAIN` mid-body. The reader now polls the fd and retries up to `body_read_timeout_ms` (default 30s), so an upload is read in full. The hot GET path returns early and pays nothing.

<br>

## 0.4.0 (2026-06-19)

__*Update:*__
- io_uring churn scaling and on-ring response overflow (ADR-041):
    - `zix.Http1` `.URING` teardown now rings the close (`prep_close`, tagged with a new shared `OpKind.close`) instead of a synchronous `linux.close`, recycling the connection slot first and falling back to a synchronous close only when the SQ is momentarily full. Under connection churn the synchronous close blocked the worker between connections, so the ring barely engaged its cores. With the ring close the worker keeps reaping completions across teardowns. On the 64-core box this lifts the churn cells (limited-conn, json) from far behind `.EPOLL` to parity or better, at a fraction of the memory, so `.URING` now reaches parity or better on every measured cell.
    - `RespSink` (`tcp/http1/core.zig`) grows its staging buffer on overflow when backed by an allocator: the `.URING` loop installs it over the per-connection `send_buf` with a 1 MiB cap (`URING_SEND_BUF_MAX`), so a response larger than the staged buffer grows in place (power-of-two realloc, never shrinks, reused by the recycled connection) and still leaves as one on-ring send, instead of stalling the worker on a blocking off-ring write. The `.EPOLL` path installs no grow allocator and is unchanged (flush-on-overflow).
    - The shared io_uring `OpKind` and ring helpers moved from `src/tcp/io_uring` to `src/multiplexers/ring.zig`. Every io_uring engine carries a `.close => {}` arm. Only `zix.Http1` arms the ring close for now.

    ---

- Server `io` into config and `zix.Uds` handler-at-init (ADR-039):
    - `zix.Tcp`, `zix.Udp`, and `zix.Uds` now carry `io: std.Io` as the first config field, so `run()` takes no argument, matching the five engine servers. Every zix server is now constructed with a config that carries `io` and served with a no-argument `run()`.
    - `zix.Uds` adopts the ADR-038 factory shape: `Server.init(comptime handler, config)` bakes the handler into the type, and the built-in `zix.Uds.echoHandler` is passed explicitly. The `run(io, handler)` / `runWith` path is removed.
    - Breaking: every `zix.Tcp` / `zix.Udp` / `zix.Uds` server call site adds `.io = process.io` and drops the `run` argument. Clients keep `io` as a `connect()` parameter (deferred to a separate decision).

    ---

- io_uring dispatch model (`.URING`, ADR-037):
    - New shared-nothing `.URING = 4` dispatch model: same thread-per-core topology as `.EPOLL` (one `SO_REUSEPORT` listener and one completion ring per worker, no shared queue), but completion-based, so most syscall transitions are batched into the ring. Linux-only, falls back to `.POOL` on non-Linux.
    - Native across `zix.Http1` (reference engine, plus the WebSocket pump on a `BufferGroup`), `zix.Http`, `zix.Grpc` (multiplexed h2), and `zix.Fix` (resumable `core.processFixRing` per readable batch). `zix.Http2` folds to `.POOL` and the `zix.Tcp` per-connection handler folds to `.EPOLL`.
    - Request bodies on the ring (`zix.Http1`): a chunked request body fully present in the recv buffer is decoded in place, and a body larger than `max_recv_buf` is answered then its remainder is drained off the socket with a single `MSG_TRUNC` recv (the kernel discards the bytes in place, zero copy, capped at the declared length), mirroring the `.EPOLL` drain. So `.URING` serves large uploads and chunked requests, not only buffered ones.
    - On loopback `.URING` matches `.EPOLL` on throughput and total CPU, winning mainly on per-request cache locality. Prefer `.EPOLL` by default, `.URING` for sustained, pipelined load.

    ---

- `zix.Tcp` server API reshape (ADR-038):
    - The handler is baked into the server type at `init`, so `run` takes no handler argument, mirroring `zix.Http1` / `zix.Grpc` (ADR-039 then moves `io` into config, so `run()` takes nothing). `zix.Tcp.Server` is now a fieldless namespace with comptime constructors `init(handler, config)` / `initArgs(handler, config, args)` (per-connection) and `initFramed(frame_fn, config)` / `initFramedArgs(frame_fn, config, args)` (per-frame ring).
    - Breaking: `runWith` and `runFramed` are removed. The built-in echo default is the public `zix.Tcp.echoHandler`, passed explicitly. The per-connection handler runs `.ASYNC` / `.POOL` / `.MIXED` / `.EPOLL` (`.URING` folds to `.EPOLL`). The new per-frame `FrameFn` callback (`initFramed`) runs natively on the `.URING` ring.

    ---

- `Http2ServerConfig.logger`:
    - New optional `logger: ?*Logger` field on `Http2ServerConfig`, for consistency with the other server configs. When set, `zix.Http2` lifecycle lines route through `logger.system(.INFO, "http2", ...)` instead of the Debug-only `std.debug.print`.

    ---

- `zix.Http2` frame constants:
    - The HTTP/2 frame-type bytes are renamed from `FT_*` to the spelled-out `FRAME_TYPE_*` (`FT_DATA` -> `FRAME_TYPE_DATA`, and so on). Breaking for any code referencing `zix.Http2.FT_*`.
    - New `pub const FRAME_HEADER_LEN` (9) in the h2 frame module (re-exported from `zix.Http2`) names the 9-octet frame header length, replacing the inline `9` literals across the h2 and gRPC frame codecs.

    ---

- Response cache awareness (opt-in, ADR-036):
    - New shared `src/utils/response_cache.zig`: a per-worker, lock-free precomputed-response cache (structure-of-arrays slab, open addressing, lazy on-access TTL). Off by default, installed under `.EPOLL` and `.URING`. The other dispatch models leave it uninstalled and the API degrades to a plain send.
    - Five flat config fields with identical names across `Http1ServerConfig`, `HttpServerConfig`, and `GrpcServerConfig`: `response_cache` (`bool`, default `false`), `cache_max_entries` (`u32`), `cache_max_value_bytes` (`u32`), `cache_ttl_ms` (`u32`), and `cache_max_total_bytes` (`usize`).
    - `zix.Http`: `res.serveCached(req)` and `res.sendCached(req, body, ttl)` cache the full serialized response, keyed on method, path, and query. `zix.Http1` keeps `cacheLookup` / `cacheStore` / `writeWithCache`.
    - `zix.Grpc` (unary): `ctx.serveCached(content_type)` and `ctx.sendCached(content_type, data, ttl)` cache the response message, keyed on path plus request body, re-framed per stream so HPACK and stream id stay correct.
    - Measured crossover near 4 KiB: heavy ~32 KiB JSON +34% throughput at c512, zero regression below ~2 KiB. See ADR-036.

    ---

- WebSocket build-once broadcast fanout:
    - New `zix.Http1.WebSocket.broadcast(conns, opcode, payload)`: serializes the frame once and writes the same bytes to every fd in a caller-maintained room, so a broadcast costs one serialization regardless of member count. A failed write to a dead peer is skipped (the EPOLL engine reaps that fd on its next event), and the large-payload path builds the header once and writes the payload without a staging copy.
    - `zix.Http.WebSocket.RoomMap.broadcast` reuses a single staging buffer across all members instead of re-creating one per connection (build once, fan out).

    ---

- Http epoll shared-nothing:
    - `zix.Http` `.EPOLL` was rewritten from a centralized model (one accept thread pushing to a shared `ConnQueue`, pool workers popping) into a shared-nothing architecture matching `zix.Http1`. Each worker binds its own `SO_REUSEPORT` listener, creates its own `epoll` instance, and runs its own level-triggered event loop. The kernel distributes new connections across workers with no shared queue, no mutex, and no fd handoff.
    - `workers` (not `pool_size`) is now the EPOLL worker count for `zix.Http`. `0` selects cpu_count. `pool_size` is silently ignored for `.EPOLL` (callers using `.pool_size = N` with `.EPOLL` must migrate to `.workers = N`).
    - Level-triggered `EPOLLIN` replaces `EPOLLONESHOT`. No explicit re-arm after each request: connections stay registered and re-fire when new data arrives.
    - Throughput: 428k to 451k req/s at c1000 (`wrk -c1000 -t4 -d10s`), closing the gap vs `zix.Http1` from 11% to 6.8%. Remaining gap is structural (arena allocation per request). See ADR-034.

    ---

- Http1 EPOLL slab, RawFn, and Date control:
    - `zix.Http1` `.EPOLL` now backs each registered connection with a per-connection receive buffer slab (`ConnTable`), sized by `max_recv_buf`, so a connection accumulates a full request without re-allocating per event.
    - New `zix.Http1.RawFn` handler type plus `zix.Http1.Server.initRaw`: a raw handler receives the connection fd and the parsed head and owns the wire directly, bypassing the managed response path for full control (streaming, custom framing).
    - New `send_date_header` config field (default `true` for RFC 7231 compliance). Set `false` to drop the `Date` header and save 37 bytes per response on hot paths where the client does not need it.
    - `buildSimpleHeaderInto` writes the status line and headers into a caller sink, the fast path for the slab writer.

    ---

- WebSocket optimization:
    - SIMD unmask: `parseFrame` in both `zix.Http1` and `zix.Http` WebSocket engines now unmasks the client payload with a 16-wide `@Vector(16, u8)` XOR against a replicated 4-byte mask, with a scalar tail for the remainder. Replaces the per-byte `i % 4` loop.
    - New `ws_recv_buf` config field on `Http1ServerConfig` (default `0`, falls back to `max_recv_buf`). Set larger than `max_recv_buf` to give EPOLL WebSocket connections more room to accumulate pipelined frames before a compact and re-read.
    - `zix.Http1` EPOLL WebSocket reads now drain to `EAGAIN` per wakeup (read all available frames in one event) and coalesce writes, instead of one frame per wakeup.
    - `zix.Http` WebSocket: `buildHeader` (header-only framing into a caller buffer), cleaned `RoomMap` broadcast path.

    ---

- gRPC mux per-connection staging and corking:
    - `GrpcMuxConn` now owns a 64 KB `stage_buf` (was an inline 4096-byte `ReplyStage.buf`). One streaming call of ~5000 messages (~85 KB peak) flushes in two writes, and ~100 concurrent unary replies (~6 KB) coalesce into one write. `ReplyStage.buf` is now a caller-owned slice. The blocking inline path keeps a 4096-byte stack backing.
    - Server SETTINGS frame is precomputed once per connection: `buildSettingsFrame` fills a 33-byte blob in `GrpcMuxConn.init`, and the handshake appends it as-is instead of re-encoding the parameter loop on every connection.
    - `TCP_CORK` wraps streaming handlers in `muxDispatch`: the kernel coalesces the multiple intermediate stage flushes a streaming handler produces into fewer TCP segments, then uncorks on return. Unary replies are unaffected (already single-write). No-op on non-Linux.

    ---

- Dynamic epoll timeout (gRPC, TCP, FIX workers):
    - The EPOLL worker loop now flips `epoll_wait` timeout to `0` after a batch of active events (busy-poll for the next ready batch) and back to `-1` (block) when a wakeup returns zero events. Trades a tight spin under load for lower latency between back-to-back batches without burning a core while idle.

    ---

- Build split:
    - `build.zig` was split into focused sub-files imported by the root: `zix-build-examples.zig`, `zix-build-tests.zig`, `zix-build-test_runner.zig`. The root `build.zig` shrank from ~682 lines to the module and step wiring. No build-command changes.
    - The library root source file was renamed `src/zix.zig` to `src/lib.zig` (matching Zig's `lib.zig` convention). The module is still registered as `b.addModule("zix", ...)`, so the public API is unchanged: consumers still `@import("zix")` and use `zix.Http`, `zix.Grpc`, etc.

    ---

- Unified, Debug-gated server init logging:
    - Every server (`zix.Http`, `zix.Http1`, `zix.Http2`, `zix.Grpc`, `zix.Fix`, `zix.Tcp`, `zix.Udp`, `zix.Uds`) now emits lifecycle lines (listening, EPOLL fallback, accept errors) through one gated `logSystem` shape: route to `config.logger` when set, otherwise `std.debug.print` only in Debug builds, silent in release. A release server with no logger emits no init noise.
    - Removed the junk and duplicate raw prints: `zix.Grpc` previously printed each listening line raw and also logged it. `zix.Http2`/`zix.Fix`/`zix.Tcp` printed raw lifecycle/fallback lines unconditionally. `zix.Udp`/`zix.Uds` init lines now also appear in Debug builds without a logger (were logger-only before).
    - `zix.Channel.init` gained a Debug-only init notice (`zix channel: init <T> cap=<N>`), suppressed in release and under the test runner (`builtin.is_test`) to avoid poisoning the test IPC.
    - Reworded a `src/tcp/http1/server.zig` comment to drop a stale external benchmark reference.

    ---

<br>

__*Fix:*__

- gRPC and HTTP/2 stream write under EPOLL:
    - `fdWriteAll` (`src/tcp/http2/frame.zig`) now handles `EAGAIN` on a non-blocking EPOLL socket with a full send buffer: it polls the fd for writable then retries, instead of treating the partial write as a broken pipe. Blocking sockets never hit this branch. Fixes truncated streaming replies and spurious stream errors under high concurrency.

<br>

## 0.3.0 (2026-06-10)

__*Update:*__
- Http1 router prefix param:
    - `zix.Http1.Router` gains `.PREFIX` and `.PARAM` route kinds (added `RouteKind` and a `kind` field on `zix.Http1.Route`, default `.EXACT`), reaching parity with the `zix.Http` router and its `exact > param > prefix` priority (ADR-004). Captured path params are read with the new free function `zix.Http1.pathParam(name)` (a per-handler thread-local, since the Http1 handler has no `Request`, see ADR-029), capped at 8 params per match.
    - The prefix pass now guards the boundary byte behind `startsWith`. The same fix was applied to the `zix.Http` router, which read one byte past a request path shorter than a registered prefix (a panic in Debug/ReleaseSafe, a masked out-of-bounds read in ReleaseFast).
    - Backward compatible: `.kind` defaults to `.EXACT`, so existing exact-only Http1 route tables are unchanged. `examples/http1_static.zig` now routes `/secret` via a `.PREFIX` route. See ADR-033.

    ---

- Epoll max events 512:
    - The epoll batch (max events drained per `epoll_wait`) is raised from 256 to 512 across all native epoll servers (`zix.Tcp`, `zix.Http`, `zix.Fix`, `zix.Grpc`, `zix.Http1`) and unified into one named, documented file-level constant `EPOLL_MAX_EVENTS: usize = 512` per server. The previous mix of a lowercase `epoll_max_events` const and inline `256` literals is removed.
    - 512 lets a worker clear its ready-fd set in a single syscall at high connection counts: a worker holding more than 256 readable fds no longer needs a second `epoll_wait`. No public API change, the constant is an internal tuned default. See ADR-032.

    ---

- Httpconfig naming consistency:
    - `HttpServerConfig` field renames for API-wide consistency (defaults unchanged): `max_kernel_backlog` becomes `kernel_backlog` (now matching `Tcp`, `Fix`, `Http1`, `http2`, and `Grpc`, which already used the bare name), and `max_client_request` becomes `max_recv_buf` (matching `zix.Http1`).
    - Migration: rename the fields at the call site. `.max_kernel_backlog = N` becomes `.kernel_backlog = N`, and `.max_client_request = N` becomes `.max_recv_buf = N`. `max_allocator_size` and `max_client_response` are unchanged (no equivalent exists outside `zix.Http`).

    ---

- Http1 handler at init:
    - `zix.Http1.Server.init` now takes the comptime handler as its first argument and bakes it into the server type, so `run()` takes no argument. This matches `zix.Http` and `zix.Grpc`, which register routes at init. The server core stays routing-agnostic: the handler may be a `Router(routes).dispatch`, a bare `HandlerFn`, or a middleware chain.
    - Migration: `Server.init(.{ ... })` then `server.run(Routes.dispatch)` becomes `Server.init(Routes.dispatch, .{ ... })` then `server.run()`.

    ---

- Grpc epoll multiplexed:
    - `zix.Grpc` `.EPOLL` was rewritten from a blocking thread-per-connection pool into a shared-nothing multiplexed event loop. Each worker owns a private `SO_REUSEPORT` listener, its own epoll instance, and a private fd-indexed connection table, the kernel balances connections across workers. One worker drives many non-blocking connections through a resumable HTTP/2 state machine (`GrpcMuxConn` / `grpcMuxOnReadable`), so concurrency is bounded by connection count, not thread count.
    - Every route, including server-streaming, is dispatched inline on the worker under `.EPOLL` (no per-stream thread, no connection write mutex). A streaming handler runs on the event loop and must stay bounded, use `.ASYNC` for unbounded streams. The blocking `serveGrpcConn` path is unchanged for `.ASYNC` / `.POOL` / `.MIXED`.
    - `pool_size` is now the multiplexing worker count for `.EPOLL` (0 = cpu count), not a blocking pool size. See ADR-031.

    ---

- Grpc unary hotpath:
    - Unary and streaming replies (initial HEADERS, every DATA, the trailer, and control frames) are coalesced into one `write()` per readable event via a per-connection `ReplyStage` cork.
    - `SETTINGS_INITIAL_WINDOW_SIZE` raised to 16 MB with a one-time connection-window bump, so small request bodies no longer trigger a per-DATA `WINDOW_UPDATE`, the connection window is replenished in bulk only past a threshold.
    - Buffered frame reads (a HEADERS plus DATA pair costs one `read()`), and per-stream `body` / `header_scratch` moved to per-connection backing slices sized to `max_body` / `max_header_scratch` instead of fixed inline arrays.
    - The constant reply header blocks (`:status 200` + `content-type: application/grpc+proto`, and the `grpc-status: 0` trailer) are HPACK-encoded once at comptime and memcpy'd on the hot path. `HpackEncoder.writeString` now types the Huffman result as `?usize` so the encoder runs at comptime. Other content-types / statuses use the dynamic encoder.
    - Combined effect: unary ~110k to ~420k req/s at 256 connections, streaming ~2.6k to ~28k calls/s. See ADR-031.

    ---

- Gttp1 logger field:
    - `Http1ServerConfig.logger: ?*Logger` added. The server routes lifecycle lines (listening, EPOLL fallback) through it.
    - Per-request access logging is handler-side: the Http1 handler writes to the fd and returns void, so the server cannot observe response status or bytes. Handlers call `logger.access()` themselves (examples use a module global).

    ---

- Gttp1 examples parity and completion:
    - The 9 existing `http1_*` examples were brought to `http_*` presentation parity (full tunable constant block, commented logger scaffolding in the basic family).
    - 6 new examples complete the set (15 total): `http1_manual_concurrent`, `http1_sse`, `http1_xtra_headers`, `http1_client`, `http1_timeout_resp`, `http1_websocket`.

    ---

- Gttp1 handler timeout:
    - `Http1ServerConfig.handler_timeout_ms` plus `zix.Http1.setTimeout()` and `zix.Http1.isExpired()`. The server arms a thread-local deadline before each dispatch across all four models.
    - `statusPhrase` gained `408 Request Timeout`. See ADR-029.

    ---

- Http1 websocket:
    - New `zix.Http1.WebSocket` module: RFC 6455 frame codec (`parseFrame` / `buildFrame` / `buildHeader` / `acceptKey`) and `upgrade()` over raw fd I/O.
    - Engine-owned frame loop under `.EPOLL`: a handler calls `WebSocket.serve(fd, key, on_frame)` to hand the connection to the epoll loop. The engine echoes via `on_frame` per readable event (`fn(fd, opcode, payload) void`), auto-ponging ping and auto-echoing close. No worker is parked per connection.
    - `WebSocket.send` coalesces every frame produced during one readable event into a single `write()`, so a pipelined burst costs one syscall instead of one per frame.
    - `zix.Http1.WsFrameFn` exported. Engine-owned WebSocket is `.EPOLL` only: under `.ASYNC` / `.POOL` the handoff is cleared and the connection ends. See ADR-030.

    ---

- Http1 large body drain:
    - Under `.EPOLL`, a request body larger than `max_recv_buf` no longer returns `431`. The engine dispatches the handler with an empty body (large-body endpoints use the Content-Length value), then reads and discards the remaining body bytes across events so the connection stays usable for keep-alive. Bodies that fit the buffer are unchanged.

    ---

- Http client version selector:
    - `zix.Http.Client` gained a `version` config field (`zix.Http.ClientVersion`: `HTTP_1`, `HTTP_2`, `HTTP_3`, default `HTTP_1`).
    - `HTTP_2` and `HTTP_3` return `error.UnsupportedVersion` until backends are wired. See ADR-028.

    ---

- Http1 writesimple hotpath:
    - `zix.Http1.writeSimple` now builds the response header with a direct byte encoder (`buildSimpleHeader` via `appendStatusCode` / `appendDec` / `appendBytes`), replacing `std.fmt.bufPrint`.
    - Small bodies (up to 3840 bytes) are copied with the header into one contiguous stack buffer and sent with a single `write()`. Bodies above 3840 bytes fall back to inline `writev` to avoid copying a large payload.
    - `cachedDate()` calls `clock_gettime` only every 256 requests via a thread-local tick counter, not per-request.
    - Measured ~450k to ~612k req/s at c128 vs the prior `writev`-only path. See ADR-026.

    ---

- Response header default minimal:
    - `HttpServerConfig.max_response_headers` default lowered from `.COMMON` (32) to `.MINIMAL` (16).
    - `zix.Http1`: `MAX_HEADERS` cap 32 to 16, new `Http1ServerConfig.max_headers: u8 = 16`.
    - Behavioral change: handlers adding 17 to 32 custom headers now hit `error.TooManyHeaders` until the tier is raised. See ADR-027.

    ---

<br>

__*Fix:*__

- Http1 websocket epoll echo:
    - `zix.Http1` WebSocket echo did not work under `.EPOLL`: the handshake succeeded but no frame was ever echoed. The handler's blocking `read()` loop returned `EAGAIN` at once on the engine's non-blocking sockets. The engine-owned frame loop (`WebSocket.serve`, see ADR-030) replaces that pattern. The `http1_websocket` example now uses `.EPOLL`.

<br>

## 0.2.2 (2026-06-06)

__*Update:*__
- Grpc unary inline dispatch:
    - Unary routes (`Route.is_server_streaming = false`, the default) now dispatch synchronously on the connection thread. No per-call Task alloc, no 4 KB `header_scratch` copy, no `io.async` enqueue, no ConnMutex acquire/release.
    - Server-streaming routes require `is_server_streaming = true` on the `Route` entry to use thread-per-stream dispatch.
    - New field on `zix.Grpc.Route`: `is_server_streaming: bool = false`.

    ---

- Grpc bench fixtures:
    - Added `examples/grpc_hello_req.bin` and `examples/grpc_location_req.bin`: properly gRPC-framed binary fixtures for h2load and ghz benchmarking.
    - h2load and ghz benchmark commands added to all 8 gRPC server examples.

    ---

<br>

__*Fix:*__

- n/a

<br>

## 0.2.1 (2026-06-05)

__*Update:*__
- n/a

<br>

__*Fix:*__

- Grpc content type:
    - https://codeberg.org/prothegee/zix/issues/67
    - `sendGrpcError` omitted `content-type` in the trailers-only HEADERS frame. gRPC clients rejected the response with a content-type error. All HEADERS frames sent by the server now include `content-type: application/grpc+proto` per the gRPC spec.

<br>

- Grpc concurrent stream:
    - https://codeberg.org/prothegee/zix/issues/68
    - Concurrent server-streaming RPCs on the same h2 connection could deadlock when the TCP send buffer filled under backpressure. Each stream is now dispatched on a dedicated thread sharing a connection-level write mutex, preventing frame interleaving.

<br>

## 0.2.0 (2026-06-02)

__*Update:*__
- Adding TCP raw

- Adding gRPC h2c

- Adding FIX (over TCP)

- Adding EPOLL dispatch model

- ASYNC is default dispatch model

- Handler/router (Http & gRPC) now use comptime

- Documentation split into English (en) and Bahasa (id)

<br>

__*Fix:*__

- n/a

<br>

## 0.1.0 (2026-05-16)

__*Update:*__
- Initial release, Zig 0.16.x network library (minimum_zig_version: 0.16.0-dev.2974+83c7aba12):
    - HTTP:
        - Server with three dispatch models: POOL, ASYNC, MIXED
        - Router with exact, param, and prefix matching
        - Middleware (comptime, zero-allocation)
        - WebSocket upgrade
        - Server-Sent Events (SSE)
        - Multipart upload
        - Static file serving
        - HTTP client

        ---

    - UDP:
        - Generic server and client over user-defined packet type
        - Broadcast peer snapshot per packet

        ---

    - Unix Domain Sockets (UDS):
        - Framed server and client

        ---

    - Channel:
        - In-process ring-buffer message passing, generic over element type

        ---

    - Utils:
        - File save helper, MIME type resolution

        ---

<br>

__*Fix:*__

- n/a

<br>

---

###### end of changelog
