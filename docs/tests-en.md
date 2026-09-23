# Tests: zix

---

## Running Tests

```sh
# unit tests only (silent on success)
zig build unit-test

# integration tests: components wired together, no live server
zig build integration-test

# behaviour tests: observable API contracts
zig build behaviour-test

# edge tests: boundary conditions and error paths
zig build edge-test

# all of the above at once
zig build test-all
```

`zig build` alone does **not** run tests: test steps are separate named steps not wired into the default install step.

Platform behavior: with a foreign `-Dtarget` every suite compiles for that target and execution is skipped with a warning. On a non-Linux host, tests that exercise the Linux-only EPOLL / URING paths print a warn and skip, and tests scaffolded on Linux-only syscalls skip silently. The `test-runner-*` steps behave the same way: a foreign target compiles the runner plus its servers and passes, and on a non-Linux host every EPOLL / URING scenario reports a PASS line with a warn instead of running.

---

## Unit Tests

Source: `src/lib.zig`. Each module is exercised via `std.testing.refAllDecls`, which verifies every public declaration compiles and any inline `test` blocks pass.

### zix.Tcp (raw)

| Module | Coverage |
| :- | :- |
| `tcp/config.zig` | `refAllDecls` + behavioral: `TcpServerConfig` defaults (kernel_backlog=4096, max_recv_buf=4096, workers=0) with dispatch_model required (set explicitly), `DispatchModel` gapless backing values with only the three maintained models, the dropped POOL / MIXED names resolving to nothing, `TcpClientConfig` defaults (max_recv_buf=4096) |
| `tcp/server.zig` | `refAllDecls` + behavioral: port zero -> `error.ZixPortNotConfigured`, valid config succeeds and deinit is safe, valid EPOLL config succeeds and deinit is safe |
| `tcp/client.zig` | `refAllDecls` |

### zix.Http

| Module | Coverage |
| :- | :- |
| `tcp/http/method.zig` | `refAllDecls` + round-trip over every code including `QUERY` (RFC 10008), QUERY resolving from its wire token and never reported as GET, case-sensitive matching, `codeFromString` reporting an unknown token as null, a token past `MAX_TOKEN_LEN` refused by the length switch, `enumFromString` keeping its GET fallback |
| `tcp/http/status.zig` | `refAllDecls` |
| `tcp/http/content.zig` | `refAllDecls` + round-trip: `typeFromString` / `stringFromEnum` for every enum variant, `typeFromHeader` parameter stripping, an unknown or oversized value reporting no match |
| `tcp/http/parser.zig` | `refAllDecls` + behavioral: incomplete returns null, minimal GET offsets, path+query split, header offsets, keep_alive flag, all methods, an unimplemented method reporting UnknownMethod (501) apart from a malformed request line (400), chunked flag set/false, chunked coding list, chunkedEnd complete/partial/watermark-resume/terminator-in-data/trailers/pipelined/invalid-hex, dechunkInPlace over its own buffer/overlapping move/chunk order |
| `tcp/http/request.zig` | `refAllDecls` + behavioral: method, path, query string, queryParam (present / absent / flag), pathSegments, queryParams, header lookup (case-insensitive), body delivery (segmented Content-Length and chunked arrival over a non-blocking fd, a body far larger than the read buffer, short read reported when the peer closes early) |
| `tcp/http/response.zig` | `refAllDecls` + behavioral: setStatus, setContentType, setKeepAlive, addHeader, `HeaderSize.value()`, injection guard (CR/LF), TooManyHeaders, `SseWriter` wire formats, `Response.streaming` default |
| `tcp/http/router.zig` | `refAllDecls` + behavioral: matchParam, route registration (kind + path preserved) |
| `tcp/http/static.zig` | `refAllDecls` + behavioral: mimeType, parseRangeHeader |
| `tcp/http/websocket.zig` | `refAllDecls` + behavioral: acceptKey RFC vector, buildFrame + parseFrame round-trip, masked frame |
| `tcp/http/context.zig` | `refAllDecls` + behavioral: `timedOut` null deadline returns false, `isExpired` null deadline returns false |
| `tcp/http/server.zig` | `refAllDecls` + behavioral: `EpollConnTable` slab alloc / free lifecycle, filled-bytes accounting, out-of-range fd returns null, `getAvailableCpuCount` returns at least 1, `effectiveCacheEntries` honors the memory ceiling, EPOLL `processRequest` serves a cache miss then a hit, `processRequest` body outcomes (bodyComplete true for a fully-read Content-Length or chunked body and false when the handler never reads, 413 for a declared or chunked body past the limit, 100 Continue sent for a body-carrying Expect and skipped without one, close when a plain or coding-list chunked body is left unread or the peer stops early, a chunked body arriving after the head is delivered) |

### zix.Http1

| Module | Coverage |
| :- | :- |
| `tcp/http1/method.zig` | `refAllDecls` + round-trip over every code including `QUERY` (RFC 10008), QUERY resolving from its wire token and never reported as GET, case-sensitive matching, `codeFromString` reporting an unknown token as null, a token past `MAX_TOKEN_LEN` refused by the length switch, `enumFromString` keeping its GET fallback |
| `tcp/http1/content.zig` | `refAllDecls` + round-trip: `typeFromString` / `stringFromEnum` for every enum variant, the RFC 10008 query types resolving from their strings, the 33-byte longest media type fitting the lowercase buffer, a value past `MAX_TYPE_LEN` reporting no match instead of panicking, `typeFromHeader` dropping parameters and staying case-insensitive |
| `tcp/http1/core.zig` | `refAllDecls` + behavioral: parseHead (GET fields, query split from path, POST Content-Length, HTTP/1.0 keep_alive default + Connection override, Expect 100-continue), getHeader case-insensitive, queryParam, parseRange, percentDecode, buildSimpleHeaderInto, sendSimpleFD into the active RespSink with no buffer bounce, cache no-op / store-then-hit / key separation by path and query, chunkedFrame walk (asks for more mid-body, terminator length, malformed vs too-large vs unfinished, data that spells the terminator, pipelined stop), decodeChunkedInBuf (in-place decode, source untouched while unfinished), ASYNC serveConn body path (fitting and over-large delivery with bodyReceived / bodyComplete reporting, the start of the body rather than drain leftovers, drain keeps the pipelined request, 413 declared and chunked past the buffer, 400 malformed chunked, 100 Continue, chunked arriving after the head, pipelined request behind a chunked body) |
| `tcp/http1/request.zig` | `refAllDecls` + behavioral: body returns the engine-delivered slice, bodyReceived defaults to the slice length and takes the engine override, bodyComplete defaults true and takes the engine override, fromRaw parses a raw buffer with body |
| `tcp/http1/server.zig` | `refAllDecls` + behavioral: config validation (ASYNC / EPOLL / URING), serveEpollConn answers a pipelined burst in order, EPOLL cache miss-then-hit + effectiveCacheEntries memory ceiling, ConnTable slab lifecycle + ws_recv_buf sizing, serveEpollWs drains to EAGAIN, parseGetFastPath (GET / query / rejects POST and HTTP/1.0 / raw headers), initUringRing yields a usable ring, URING finishClose rings the close (`prep_close`) and recycles the slot |
| `tcp/http1/dispatch/epoll.zig` (Linux) | behavioral body path: drain-then-serve reports the counted total, exact drain leaves the pipelined request intact, a peer that quits mid-drain is never served, a fitting body waits for the full count, 413 for a declared body past the limit and a chunked body past the body buffer, 400 on malformed chunked, one 100 Continue while the body is still arriving |
| `tcp/http1/dispatch/uring.zig` (Linux) | behavioral body path: a fully-present chunked body decodes, an oversized body is deferred and served with the counted total, a deferred request stays parked while its drain is unfinished, a fitting body waits for the full count, 413 declared and chunked, 400 malformed chunked, 100 Continue while the body is still arriving |
| `tcp/http1/websocket.zig` | `refAllDecls` + behavioral: acceptKey RFC 6455 vector, buildFrame/parseFrame round-trip, SIMD unmask matches scalar (and tail bytes), buildHeader prefix, pump echoes over a socketpair, pumpRing stages then reports close, broadcast fan-out (+ dead-fd skip, empty list) |
| `tcp/http1/router.zig` | `refAllDecls` + behavioral: matchParam, comptime router |
| `tcp/http1/config.zig` | `refAllDecls` (default values exercised by `tests/behaviour/http1/config_test.zig`) |

### zix.Udp

| Module | Coverage |
| :- | :- |
| `udp/config.zig` | `refAllDecls` + defaults: `UdpServerConfig`, `UdpClientConfig`, `allow_args` default, and `Endianness` enum backing values |
| `udp/packet.zig` | `refAllDecls` + behavioral: NATIVE no-op, u8 array not swapped, LITTLE/BIG round-trip, non-native swaps integers and float array elements, `FeedbackResult` all variants |
| `udp/server.zig` | `refAllDecls` + behavioral: port zero -> `error.ZixPortNotConfigured`, nonzero port succeeds, config fields preserved |
| `udp/client.zig` | `refAllDecls` |

### zix.Uds

| Module | Coverage |
| :- | :- |
| `uds/config.zig` | `refAllDecls` + defaults: `UdsServerConfig` (kernel_backlog=128, max_recv_buf=4096), `UdsClientConfig` |
| `uds/server.zig` | `refAllDecls` + behavioral: empty path -> `error.ZixPathEmpty`, valid path succeeds and deinit is safe |
| `uds/client.zig` | `refAllDecls` |

### zix.Http.Client

| Module | Coverage |
| :- | :- |
| `tcp/http/client_config.zig` | `refAllDecls` + defaults: `HttpClientConfig` (connect_timeout_ms=0, response_timeout_ms=0, read_timeout_ms=0, max_response_body=4MB, follow_redirects=true, max_redirects=3, h2_max_read_rounds=4096, user_agent=`zon_options.user_agent`, version=HTTP_1, tls_verify=true, tls_ca_path=null) |
| `tcp/http/client.zig` | `refAllDecls` + behavioral: `.HTTP_2` over a non-https URL is rejected before connecting, `.HTTP_3` yields `UnsupportedVersion`, a server that never answers yields `ResponseTimeout`, a complete reply is not cut short by an idle bound, a body that goes quiet mid-transfer yields `ReadTimeout` |
| `tcp/http/h2_client.zig` | `refAllDecls` + behavioral: `methodHasBody` + `skipRequestHeader`, `putFrame` round-trips through the frame parser, `putWindowUpdate` encodes the increment big-endian, `headerBlock` strips PADDED and PRIORITY prefixes, `dataPayload` strips DATA padding, a peer that accepts and never speaks yields `ResponseTimeout` |
| `tcp/http/sse_client.zig` | `refAllDecls` + behavioral: `splitField` (data / event / retry / bare field name / name mismatch / no leading space preserved), `parseHttpUrl` (basic, default port 80, https returns `TlsNotSupported`), a server that never answers yields `ResponseTimeout`, a stream that goes quiet yields `ReadTimeout` (not a clean close) |
| `tcp/http/ws_client.zig` | `refAllDecls` + behavioral: acceptKey RFC 6455 vector, `parseWsUrl` (basic, no path defaults to /, default port 80, wss returns `TlsNotSupported`, non-ws returns `InvalidUrl`), a server that never answers yields `ResponseTimeout`, a peer that sends no frame yields `ReadTimeout` |

### zix.Channel

| Module | Coverage |
| :- | :- |
| `channel/channel.zig` | `refAllDecls` + behavioral: `Channel(u32)` init capacity and count, ring buffer tail arithmetic |

### zix.Fix

| Module | Coverage |
| :- | :- |
| `tcp/fix/config.zig` | `refAllDecls` + behavioral: `FixServerConfig` required fields (ip, port, comp_id), dispatch_model required (set explicitly), workers defaults to 0, kernel_backlog default 1024, heartbeat_timeout_ms defaults to 0, `FixClientConfig` required fields (ip, port, comp_id, target_comp_id) |
| `tcp/fix/core.zig` | `refAllDecls` + behavioral: `parseFields` round-trip, `getField` lookup and null case, `computeChecksum` known vector, `verifyChecksum` valid/truncated/bad, `findMessageEnd` complete/partial/no-terminator, `buildMessage` produces valid checksum |
| `tcp/fix/server.zig` | `refAllDecls` + behavioral: port zero -> `error.ZixPortNotConfigured`, valid config succeeds, deinit is safe |
| `tcp/fix/client.zig` | `refAllDecls` + behavioral: `FixClient.connect` port zero -> `error.ZixPortNotConfigured` |
| `tcp/fix/router.zig` | `refAllDecls` + behavioral: dispatch calls the matching handler, no match leaves the handler uncalled, route timeout sets `deadline_ns` |

### zix.Http2

| Module | Coverage |
| :- | :- |
| `tcp/http2/frame.zig` | `refAllDecls` + behavioral: `FRAME_TYPE_HEADERS=0x01`, `FLAG_END_STREAM=0x01`, `ERR_NO_ERROR=0`, `writeFrameHeader`/`readFrameHeader` roundtrip via pipe, PREFACE starts with `PRI`, `sendSettings` writes a valid 9-byte SETTINGS frame via pipe |
| `tcp/http2/hpack.zig` | `refAllDecls` + behavioral: Huffman encode/decode roundtrip, `HpackEncoder.writeHeader` produces indexed entry from static table, `HpackDecoder.decode` decodes indexed `:method GET`, dynamic table eviction respects max_size, `HPACK_STATIC` index 8 is `:status 200` |
| `tcp/http2/core.zig` | `refAllDecls` + behavioral: `ServeOpts` struct defaults, `HandlerFn` is a function pointer type |
| `tcp/http2/config.zig` | `refAllDecls` + behavioral: `Http2ServerConfig` required fields compile, dispatch_model required (set explicitly), workers defaults to 0, max_streams=128 and max_frame_size=16384 |
| `tcp/http2/server.zig` | `refAllDecls` + behavioral: port zero -> `error.ZixPortNotConfigured`, valid config succeeds and deinit is safe |
| `tcp/http2/static.zig` | `refAllDecls` + behavioral: zero copy is refused for a coalescing batch and the sentinel fd, a file is framed as HEADERS plus DATA with END_STREAM, traversal / a missing file / an oversize path are rejected, a body past the max frame size is chunked, an empty file closes the stream on HEADERS, the brotli sibling is picked from the cache |

### zix.Grpc

| Module | Coverage |
| :- | :- |
| `tcp/http2/grpc/status.zig` | `refAllDecls` + behavioral: OK=0, CANCELLED=1, UNIMPLEMENTED=12, UNAUTHENTICATED=16 |
| `tcp/http2/grpc/frame.zig` | `refAllDecls` + behavioral: `readGrpcPrefix` / `writeGrpcPrefix` roundtrip, compress flag preserved, message length preserved, `sendGrpcError` includes `content-type` header |
| `tcp/http2/grpc/proto.zig` | `refAllDecls` + behavioral: `encodeVarint` / `decodeVarint` roundtrip, `encodeString` produces LEN wire type, `encodeInt32` produces VARINT wire type, `encodeDouble` / `decodeDouble` roundtrip (positive and negative values), `MessageReader` iterates all fields |
| `tcp/http2/grpc/timeout.zig` | `refAllDecls` + behavioral: H/M/S/m/u/n units convert correctly, single-char returns null, empty returns null |
| `tcp/http2/grpc/core.zig` | `refAllDecls` + behavioral: `parsePath` valid and invalid inputs, `detectContentType` proto/json/unknown, `GrpcContext.recvMessage` empty body returns null, `Route.timeout_ms` defaults to zero, `GrpcContext.isExpired` null/past/future deadline, `GrpcServeOpts.handler_timeout_ms` defaults to zero, Router dispatches to matching handler |
| `tcp/http2/grpc/config.zig` | `refAllDecls` + behavioral: `GrpcServerConfig` required fields and defaults (handler_timeout_ms=0), `GrpcClientConfig` required fields |
| `tcp/http2/grpc/server.zig` | `refAllDecls` + behavioral: port zero -> `error.ZixPortNotConfigured`, valid config succeeds, deinit is safe |
| `tcp/http2/grpc/client.zig` | `refAllDecls` + behavioral: `GrpcClient.connect` port zero -> `error.ZixPortNotConfigured` |

### zix.Http3

The HTTP/3 (QUIC) layers are pure-Zig from the RFCs, so each carries the spec's own worked example as an in-file test. `zix.Http3` also exports these as primitives (mirroring `zix.Http2`), and the live round trip is driven by a native client hand-rolled from them in `test-runner-http3` / `test-runner-all`.

| Module | Coverage |
| :- | :- |
| `udp/http3/crypto.zig` | `refAllDecls` + behavioral: Initial secrets / AES-128-GCM keys from a connection id match the RFC 9001 Appendix A.1 worked example, AEAD nonce and header-mask helpers |
| `udp/http3/protection.zig` | `refAllDecls` + behavioral: seal-then-open round-trip for Initial / Handshake / 1-RTT packets, header protection applied and removed, a flipped byte fails AEAD |
| `udp/http3/keyschedule.zig` | `refAllDecls` + behavioral: handshake keys from ECDHE + transcript, 1-RTT application keys from the handshake secret + transcript through Finished |
| `udp/http3/qpack.zig` | `refAllDecls` + behavioral: prefixed-integer encode / decode, indexed field line, literal-with-name-reference, the static table entries |
| `udp/http3/huffman.zig` | `refAllDecls` + behavioral: decode of the RFC 7541 Appendix C.4 `www.example.com` vector and a request path with digits and symbols |
| `udp/http3/varint.zig` / `packet.zig` / `frame.zig` | `refAllDecls` + behavioral: varint read / write round-trip, long / short header parse, CRYPTO and STREAM frame parse |
| `udp/http3/request.zig` / `response.zig` | `refAllDecls` + behavioral: `parseRequest` recovers `:method` / `:path` past a leading ACK, `streamBytes` sums stream payload bytes across streams and skips non-stream frames, `buildResponse` carries the control SETTINGS plus a HEADERS / DATA reply and rides a due MAX_STREAMS / MAX_DATA grant (`buildMaxStreams` / `buildMaxData` encode) |
| `udp/http3/connection.zig` | `refAllDecls` + behavioral: `init` derives the Initial keys from the connection id (RFC 9001 A.1), the anti-amplification 3x cap, `sendDatagramSize` clamps to config / client / ceiling, `replenishBidiStreams` and `replenishMaxData` raise their grants past the one-time allowances, `reserveSendStream` pool bounds, `AckTracker` hole tracking, `onAckFrame` RTT sampling |
| `udp/http3/router.zig` | `refAllDecls` + behavioral: dispatch calls the matching handler, the query is stripped before matching, no match returns 404 |
| `udp/http3/config.zig` / `server.zig` | `refAllDecls` + behavioral: required config fields and defaults, a null `Tls.Context` is rejected at run |
| `udp/http3/static.zig` | `refAllDecls` + behavioral: content-encoding maps only what the response path can emit, serve declines when caching is off (the body must outlive the handler, so it can only come from the cache), the response is filled from cached bytes and the pin is KEPT, the body stays readable after the handler frame is gone, a `.br` sibling is picked and named, traversal and a missing file are rejected, exactly one pin is held and `releasePin` returns it, a released pin lets the entry be reclaimed, an in-flight body is immune to the file being rewritten in place |

### zix.Webtransport

WebTransport over HTTP/3 is a feature of `zix.Http3` (`Http3ServerConfig.webtransport`), so the binding's modules are pure-Zig from their own drafts: each one carries the codepoints, the RFC layouts, and crafted byte streams as in-file tests. The live round trip is driven end to end by a native client hand-rolled from the HTTP/3 primitives in `test-runner-webtransport` / `test-runner-all`.

| Module | Coverage |
| :- | :- |
| `udp/http3/webtransport/draft.zig` | `refAllDecls` + behavioral: the two upgrade tokens select their dialect and an unknown token selects neither, the draft-16 codepoints against the IANA registrations (settings, stream type and signal value, error codes, capsule types), the deployed draft-07 pair still accepted, the application error mapping at both ends of the range and over an exhaustive sweep that no encoded value is a reserved grease codepoint, a reserved codepoint inside the range carrying no application error, and the flow control capsule classification |
| `udp/http3/webtransport/capsule.zig` | `refAllDecls` + behavioral: RFC 9297 3.2 capsule framing, the close capsule's application code and message with its UTF-8 character-boundary truncation, the flow control capsules encoding and decoding one varint, the streaming reader handing over capsules split across datagrams, skipping an unknown capsule without buffering it, skipping an oversized known capsule, a refused capsule stopping the reader, and a huge declared length consuming exactly what it declares while buffering nothing |
| `udp/http3/webtransport/datagram.zig` | `refAllDecls` + behavioral: the RFC 9221 4 frame forms (both types, empty datagrams, a length past the buffer, a truncated header), the encoded frame size the peer's limit counts, the limit gating every send, the RFC 9297 2.1 quarter stream id carrying the session, the HTTP/3 datagram round tripping through it, and the payload budget subtracting both layers of framing overhead |
| `udp/http3/webtransport/stream_header.zig` | `refAllDecls` + behavioral: the 0x54 / 0x41 layout for both kinds with one-byte and two-byte session ids, a stream that opens with another protocol refused, the session id rule for a client-initiated bidirectional stream, the reliable reset size covering the header, and the stream id space a data stream can live in |
| `udp/http3/webtransport/session.zig` | `refAllDecls` + behavioral: the send buffer taking what it can and reporting back pressure, a long stream reusing one buffer across acknowledgements, a loss rewinding the sent offset without disturbing the queue, a reset always covering the stream header, the receive side replenishing credit before it runs dry, flow control only enabled when both endpoints declare it, the session data limit enforced and charged, the incoming stream count limited per kind, opening streams respecting the peer's limit, the monotonic rule for `WT_MAX_DATA` and `WT_MAX_STREAMS`, the endpoint raising its own limits as the peer consumes them, a session ending with the peer's close information, streams attaching and detaching, and a session id being its CONNECT stream id |
| `udp/http3/webtransport/pool.zig` | `refAllDecls` + behavioral: slots handed out, refused past capacity, and recycled; every stream slot carrying its own send buffer; the orphan table holding a bounded set of pre-session streams; buffered streams replayed only to their own session; a tiny configured buffer raised to one that can hold a stream header; and an empty pool refusing every acquisition |
| `udp/http3/webtransport/Webtransport.zig` | `refAllDecls` + behavioral: the default config offering nothing until it is enabled, a config that outgrows the connection tables refused by the field name that crossed them, the pool sizing following the advertised limits, and the stream kind and dialect vocabulary the application sees |

### zix.Webrtc

Every WebRTC layer is written from its own RFC, so each file carries its tests in-file and the
layers with published vectors are pinned byte for byte against them. `zix.Webrtc` exports the
layers as primitives too, so a peer or a test harness can build the other side of the wire.

| Module | Coverage |
| :- | :- |
| `udp/webrtc/demux.zig` | `refAllDecls` + behavioral: every first byte routes to its RFC 7983 section 7 kind, including the ranges the RFC 5764 text did not have |
| `udp/webrtc/stun/message.zig` | `refAllDecls` + behavioral: the XOR-MAPPED-ADDRESS vector `192.0.2.1:32853` byte for byte, strict framing (trailing bytes and unpadded final attributes refused), MESSAGE-INTEGRITY over a rewritten header length |
| `udp/webrtc/stun/binding.zig` | `refAllDecls` + behavioral: the RFC 8489 section 6.3.1 request rules, silent discard and a too-small buffer both reporting null |
| `udp/webrtc/ice/*.zig` | `refAllDecls` + behavioral: the RFC 5769 section 2.1 sample request pins the MAC, the CRC and two attribute types at once, USERNAME split with this agent's ufrag first, 487 for every tiebreaker, 400 and 401 unsigned against 420 and 487 signed |
| `udp/webrtc/sctp/*.zig` | `refAllDecls` + behavioral across 20 files: CRC32c written little endian with the Castagnoli polynomial, gap ack blocks as offsets, missing reports counted below the highest newly acked TSN only, a full 4-way handshake plus data, heartbeat, shutdown and abort between two in-memory associations |
| `udp/webrtc/datachannel/*.zig` | `refAllDecls` + behavioral: the seven payload types, DCEP OPEN and ACK round-trip, stream identifier parity by DTLS role, messages reported ahead of closes, deferred reset processing, two peers talking in memory |
| `udp/webrtc/sdp/*.zig` | `refAllDecls` + behavioral across 18 files: CRLF and bare LF both read, media-section lookup ahead of session level, a missing `a=sctp-port` refused, the session id capped at 62 bits, and a candidate written into every carried media section |
| `udp/webrtc/media/*.zig` | `refAllDecls` + behavioral: RFC 3711 B.2 and B.3 and RFC 2202 case 1 pinned byte for byte, the KDF label XORed at byte 7, one profile carrying two tag lengths, ROC estimate kept separate from accept, the SRTCP index stopping rather than wrapping |
| `udp/webrtc/dispatch/*.zig` | `refAllDecls` + behavioral: each model's `pass()` drives a whole session against a real bound socket with the real `Dialer`, so a difference between the models is a difference in the loop |
| `udp/webrtc/config.zig` / `server.zig` | `refAllDecls` + behavioral: every `run()` rejection in order (port, ICE credentials present, ICE credentials legal, TLS present, key is ECDSA P-256, dispatch model against the platform) |
| `tls/dtls_*.zig` | `refAllDecls` + behavioral: anti-replay checked before the AEAD and updated after, reassembly tracked by bitmap so overlapping fragments are legal, the record sequence carried past the HelloVerifyRequest, RFC 5705 export in its no-context seed form |

### zix.Logger

| Module | Coverage |
| :- | :- |
| `logger/logger.zig` | `refAllDecls` + behavioral: init and deinit with no save_path, system() below save_min_level is silent, access() below save_min_level is silent, statusLevel mapping (100=DEBUG 200=INFO 301=INFO 404=WARN 500=ERROR), conn/packet/frame/session/rpc below save_min_level are silent |

### zix.Utils

| Module | Coverage |
| :- | :- |
| `utils/file.zig` | `refAllDecls` + behavioral: extension, save |
| `utils/multipart.zig` | `refAllDecls` + behavioral: `Parser` parse + getField |
| `utils/media_type.zig` | `refAllDecls` + behavioral: `stripParameters` drops a charset parameter, leaves a bare value unchanged, trims the space before a parameter, keeps a multipart boundary out of the result, handles more than one parameter, yields empty for an empty value or a lone semicolon. `equalIgnoreParameters` ignores case, rejects a different subtype, and rejects a prefix that is not the whole type |
| `utils/response_cache.zig` | `refAllDecls` + behavioral: store-then-lookup returns identical bytes, miss on absent key, expired entry refetches, oversize value bypasses store, ttl 0 never fresh, distinct keys coexist via probing, `max_entries` rounded down to power of two, `hashKey` separates by query |
| `utils/static_cache.zig` | `refAllDecls` + behavioral: path join rejects traversal / absolute / oversize, header carries `Vary` and only encodes when compressed, entry count clamped and rounded to a power of two, second request reuses the same open file, a miss caches nothing, ttl 0 never touches the table, `.br` / `.gz` siblings picked up and negotiated, a file with no sibling serves identity, an expired entry is reclaimed and re-opened, a pinned slot survives reclaim, a full table degrades to null, a sweep frees room, `install` is process-wide and `shutdown` clears it |
| `utils/dispatch_support.zig` | `refAllDecls` + behavioral: `.ASYNC` is supported on every platform, `.EPOLL` / `.URING` support follows the target os tag, `rejectedName` reports the model tag, `Error` carries the single canonical reject error |
| `utils/static_send.zig` | `refAllDecls` + behavioral: the copy path writes the whole body through the engine write, honours an offset and a partial length, a zero-length range never touches the socket, a body larger than the copy buffer loops, a failing engine write surfaces as BrokenPipe. Linux only: the zero-copy path delivers exact bytes over a real socket, honours an offset, and reports BrokenPipe on a closed peer |
| `utils/socket_poll.zig` | `refAllDecls` + behavioral: `readableWithin` skips the wait when the budget is zero, `waitReady` reports a datagram already queued on the socket, `waitReady` reports not ready when nothing arrives in the budget |
| `utils/counter_scale.zig` | `refAllDecls` + behavioral: `scaleCounter` converts a reading below one whole second, holds past the point where the direct form overflows u64 in nanoseconds and again in microseconds, keeps the sub-second remainder instead of truncating to whole seconds, converts under a frequency that divides neither the counter nor the scale evenly, and keeps rising across the overflow boundary |

### multiplexers (src/multiplexers/, internal)

| Module | Coverage |
| :- | :- |
| `multiplexers/ring.zig` | `refAllDecls` + behavioral: io_uring `user_data` round-trip preserves `{ op, gen, fd }`, each `OpKind` variant (`accept` / `recv` / `send` / `timeout` / `close`) decodes back, max generation does not bleed into the fd field |

---

## Integration Tests

Source: `tests/integration/`. Each file is a standalone test executable compiled with the `zix` module imported. These tests exercise components wired together against mock inputs, no live socket, no `std.Io` scheduler.

### tests/integration/tcp/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `TcpServer.init` valid config | init with real ip and port succeeds, deinit is safe |
| `TcpServer.init` EPOLL dispatch model | init with `.EPOLL` dispatch model succeeds, deinit is safe |
| `TcpServer.init` port zero | returns `error.ZixPortNotConfigured` |
| `HandlerFn` type check | `zix.Tcp.echoHandler` satisfies `zix.Tcp.HandlerFn` |
| `TcpClient.connect` port zero | returns `error.ZixPortNotConfigured` before any socket call |

### tests/integration/http/

#### `request_test.zig`

| Test | What it verifies |
| :- | :- |
| `pathParam()` single param | captured segment returned by name (absent name returns null) |
| `pathParam()` hyphenated names | `:tenant-id`, `:tenant-branch` (http_paths example pattern) |
| `body()` chunked single chunk decoded correctly | `"5\r\nhello\r\n0\r\n\r\n"` -> `"hello"` |
| `body()` chunked multiple chunks assembled | `"3\r\nfoo\r\n4\r\nbarr\r\n0\r\n\r\n"` -> `"foobarr"` |
| `body()` chunked empty body returns empty string | terminal chunk only -> `""` |
| `body()` returns body_cache without touching reader | pre-set `body_cache` short-circuits read, second call returns same pointer |

#### `router_test.zig`

| Test | What it verifies |
| :- | :- |
| Exact match | `dispatch` returns true, correct handler called |
| Param populates `path_params` | `req.path_params` set after param dispatch. `req.pathParam()` returns the value. |
| Two path params both populated | multi-param route captures both segments |
| Prefix routes to handler | prefix match returns true and calls handler |

#### `context_test.zig`

| Test | What it verifies |
| :- | :- |
| `withTimeout` / `withDeadline` timing | 60s budget not expired. 10ms budget exceeded after 50ms sleep. |

#### `header_index_test.zig`

| Test | What it verifies |
| :- | :- |
| Empty index returns null | no headers indexed (all lookups return null) |
| Case-insensitive lookup | pre-populated map: `Content-Type` found via `content-type` |

#### `sse_test.zig`

| Test | What it verifies |
| :- | :- |
| `SseWriter.writeEvent` wire format | `"data: ping\n\n"` via `std.Io.Writer.fixed` buffer |
| `SseWriter.writeNamedEvent` wire format | `"event: update\ndata: 99\n\n"` |
| `SseWriter.comment` wire format | `": keepalive\n"` |

### tests/integration/http1/

#### `server_test.zig`

| Test | What it verifies |
| :- | :- |
| `Http1Server.init` valid config, deinit is safe | init succeeds and deinit does not error |
| `Http1Server.init` URING dispatch model | the model is accepted and stored |
| `Http1Server.init` EPOLL dispatch model | the model is accepted and stored |
| `Http1Server.init` URING dispatch model | the model is accepted and stored |

#### `router_test.zig`

| Test | What it verifies |
| :- | :- |
| Router dispatch routes to matching handler | an exact path reaches its handler |
| Router dispatch selects correct route among multiple | the right handler wins with several registered |
| Router dispatch unknown path writes 404 | no match falls through to the 404 |

#### `tls_dual_test.zig`

| Test | What it verifies |
| :- | :- |
| Dual listener EPOLL serves cleartext on port | cleartext leg answers on `port` |
| Dual listener EPOLL serves TLS on tls_port with the same routes | the TLS leg serves the same route table |
| Dual listener URING serves cleartext on port | cleartext leg answers under the ring |
| Dual listener URING serves TLS on-ring on tls_port | the TLS leg runs on the ring |
| Dual listener ASYNC serves cleartext on port | cleartext leg answers on the thread model |
| Dual listener ASYNC serves TLS via the extra accept thread | the TLS leg gets its own accept thread |
| `tls_port` equal to `port` is rejected at run | returns `error.ZixTlsPortConflict` |

#### `static_cache_test.zig`

Drives the real router path over a socketpair, so what is asserted is the bytes a client receives.

| Test | What it verifies |
| :- | :- |
| Router serves an unmatched path from the static cache | 200 with the right content type and body |
| Router still 404s an unmatched path with no file behind it | a missing file is still a 404 |
| Router keeps routed paths ahead of the static cache | a routed handler wins over a file that would shadow it |
| Router repeats a cached file byte for byte across requests | the replayed header and body are identical to the cold response |
| Router serves the same file uncached when no cache is installed | the shipped default still serves through the original path |

### tests/integration/websocket/

#### `websocket_test.zig`

| Test | What it verifies |
| :- | :- |
| `parseFrame` binary opcode | FIN, opcode, payload round-trip |
| `parseFrame` ping with payload | opcode, payload content |
| `parseFrame` pong opcode | opcode |
| `parseFrame` close with empty payload | opcode, zero-length payload |
| Round-trip all opcodes | buildFrame -> parseFrame for text, binary, ping, pong, close |
| `RoomMap` init / deinit | no connections (no crash or leak) |

### tests/integration/udp/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `UdpServer.init` valid config | init with real ip and port succeeds |
| `UdpServer.init` port zero | returns `error.ZixPortNotConfigured` |
| `UdpClient.init` zero bind_port | returns `error.ZixPortNotConfigured` before any socket call |

#### `packet_test.zig`

| Test | What it verifies |
| :- | :- |
| Round-trip LITTLE | `toEndian` -> `fromEndian` restores original bytes |
| Round-trip BIG | same for BIG endian |
| `FeedbackResult.packet` value | `.packet` variant stores and returns the full packet |

### tests/integration/http/ (client)

#### `client_test.zig`

| Test | What it verifies |
| :- | :- |
| `HttpClient.init` and `deinit` | no requests: init + deinit is safe with Threaded io |
| `ClientResponse.header()` on mock head bytes | lookup by name and case-insensitive lookup |
| `ClientResponse.iterateHeaders()` | counts all headers from raw head bytes |
| `ClientRequestOpts` defaults | `headers` empty, `body` null, `connect_timeout_ms` null |

### tests/integration/uds/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `UdsServer.init` valid path | succeeds and `deinit` is safe |
| `HandlerFn` type check | `zix.Uds.echoHandler` satisfies `zix.Uds.HandlerFn` |

### tests/integration/logger/

#### `logger_test.zig`

| Test | What it verifies |
| :- | :- |
| `Logger.system()` writes line to file | `[component]` tag and message text appear in log file |
| `Logger.access()` writes line to file | method, path, status, bytes all appear in log file |
| Absent UA and origin logged as dash | empty `""` args produce `"-"` in the quoted fields |
| Present UA appears in file | non-empty UA string written as-is |
| 5xx status maps to ERROR level | `access()` with status 500 writes `ERROR` label |
| `anyerror` arg formats correctly | `{}` format of an error value renders the error name |

### tests/integration/fix/

#### `server_test.zig`

| Test | What it verifies |
| :- | :- |
| `FixServer` init and deinit do not error | valid config succeeds, deinit is safe |
| `FixServer` init port zero | returns `error.ZixPortNotConfigured` |
| Logon handshake and echo round-trip succeed | send Logon, receive Logon reply with MsgType=A send NewOrderSingle, receive echo, send Logout, receive Logout reply |
| Multiple sequential messages are all echoed | three NewOrderSingle messages echoed with ClOrdID preserved across all |

### tests/integration/http2/

#### `server_test.zig`

Ports: 18082-18085.

| Test | What it verifies |
| :- | :- |
| `Http2Server.init` and deinit do not error | valid config succeeds, deinit is safe |
| `Http2Server.init` port zero | returns `error.ZixPortNotConfigured` |
| `Http2 HandlerFn` type is a function pointer | `zix.Http2.HandlerFn` assignment compiles |
| Http2 GET / returns Hello World over h2c direct | h2c PRI preface + HEADERS + DATA round-trip returns response body |
| Http2 POST /echo returns request body | POST with body DATA frame, server echoes body back |
| Http2 two sequential streams on same connection | stream IDs 1 and 3 each receive correct responses |
| Http2 h2c upgrade GET / returns Hello World | HTTP/1.1 `Upgrade: h2c` -> 101 Switching Protocols -> h2c response |

### tests/integration/http3/

#### `static_test.zig`

Builds the trio the engine builds and calls `Router.dispatch`, so what is asserted is the response
the engine would go on to frame, including the cache pin it hands back.

| Test | What it verifies |
| :- | :- |
| Router serves an unmatched path from the static cache | 200, correct body and content type, and `static_slot` is handed back still pinned |
| Router 404s an unmatched path with no file behind it | a missing file is a 404 and no pin is taken |
| Router keeps routed paths ahead of the static fallback | a routed handler wins over a file that would shadow it |
| Router 404s static paths when caching is off | the file exists, but this engine has no safe body source without the cache |
| Router serves a multi-packet body that outlives the dispatch call | a 64 KiB body reads back intact after the Context is gone |

#### `webtransport_test.zig`

The WebTransport over HTTP/3 paths that only work when the pieces agree: the request decode that has to recognize a session request, the SETTINGS codec a client reads before it sends one, and the transport parameters the feature is built on. The bytes are built by hand from the same public primitives a peer uses, so what is asserted is the wire contract rather than a decode driven by an encoder that shares its mistakes.

| Test | What it verifies |
| :- | :- |
| the request decode reports the token a WebTransport session is opened with | the exact bytes of an extended CONNECT (`:method CONNECT`, `:scheme`, `:authority`, `:path`, and `:protocol` under a literal name) decode to the token, and the token names the dialect |
| a Huffman-coded protocol token still names the dialect | the decode leaves the value in the coding it arrived in, so the layer that recognizes a session request expands it before matching |
| a protocol on a request that is not CONNECT is malformed | `:protocol` extends CONNECT alone (RFC 9220 4), and a GET carrying a WebTransport token is never read as a session request |
| the settings a WebTransport server advertises are the ones a client needs | the three support flags a client checks, the draft-16 session limits, and the deployed pair so a draft-07 client sees support too |
| the WebTransport transport parameters parse out of the client hello | `max_datagram_frame_size` (0x20) and `reset_stream_at` (0x1d) parse beside the flow control limits the response path reads |

### tests/integration/webrtc/

#### `exchange_test.zig`

The CI exit gate for the engine: a whole session between two in-memory peers, no port and no sleep.
This is what proves the eight sans-I/O layers agree when two independent instances meet.

| Test | What it verifies |
| :- | :- |
| A dialer and an answerer carry a message end to end | ICE, DTLS, SCTP and DCEP all complete, and a payload survives the round trip |
| The answerer nominates the pair the checks came from | an ice-lite agent selects on a verified check, not on a candidate it invented |
| The channel lands on an even identifier because the dialer opened it | the DTLS role decides parity, and getting it wrong is invisible against a peer that shares the mistake |
| Neither peer is left with a deadline it will never meet | every timer the session armed is either met or retired |

### tests/integration/grpc/

#### `server_test.zig`

Ports: 18200-18206.

| Test | What it verifies |
| :- | :- |
| `GrpcServer.init` and deinit do not error | valid config succeeds, deinit is safe |
| `GrpcServer.init` port zero | returns `error.ZixPortNotConfigured` |
| gRPC unary returns greeting | `greetHandler` reads one message, replies `"Hello, world!"` |
| gRPC server streaming sends multiple responses | `echoHandler` sends two messages, client receives both in order |
| gRPC client streaming collects all messages | `collectHandler` buffers three messages, replies with count `"got 3"` |
| gRPC bidirectional echoes each message | `echoHandler` echoes `"ping"` then `"pong"` from two client messages |
| gRPC unknown method returns UNIMPLEMENTED | `dispatchHandler` replies with `GrpcStatus.UNIMPLEMENTED` for unknown path |
| gRPC trailers-only error is received as INVALID_ARGUMENT | `errorOnlyHandler` calls `res.finish(INVALID_ARGUMENT, ...)` without sending data, client receives the error status |
| gRPC two streams on same connection both return OK | two sequential unary RPCs on one connection, both streams receive correct responses |

### tests/integration/channel/

#### `channel_test.zig`

| Test | What it verifies |
| :- | :- |
| `Channel(u32)` init capacity | `buf.len == 8`, `count == 0`, `head == 0` |
| `Channel([]const u8)` compiles | slice element type accepted |
| `Channel(struct)` compiles | struct element type accepted |
| `Channel(u32)` send and recv round-trip | send then recv returns the sent value |
| `Channel(u32)` drain after close | send two items, close, recv both, third recv returns `error.ZixClosed` |

---

## Behaviour Tests

Source: `tests/behaviour/`. Each file verifies observable API contracts that callers rely on: the "what does this always do" properties.

### tests/behaviour/dispatch/

#### `platform_gate_test.zig`

The cross-engine `DispatchModel` platform contract (ADR-065), asserted once for the whole tree.

| Test | What it verifies |
| :- | :- |
| `DispatchModel` is one shared type | every engine namespace (Tcp, Http, Http1, Http2, Grpc, Fix, Udp, Http3) re-exports the same type |
| `DispatchModel` carries exactly ASYNC, EPOLL, URING | an exhaustive switch with no else prong, so a fourth variant breaks the build |
| the dropped POOL and MIXED names resolve to nothing | `std.meta.stringToEnum` returns null for both |
| backing values are gapless with ASYNC as zero | 0 / 1 / 2, and a zero-init config lands on the portable model |
| `isSupported` accepts ASYNC everywhere | the portable model is never rejected |
| `isSupported` gates EPOLL and URING on the target os | true only on a Linux target |
| the rejected model is named in the log line | `rejectedName` returns the model tag, so an operator sees which one was refused |
| ASYNC config is accepted by every engine | init stores the portable model without starting an accept loop |
| the grpc engine takes the shared model on its Router-typed server | `Grpc.Server.init(Router(&routes), ...)` stores `.ASYNC` |

### tests/behaviour/tcp/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `TcpServerConfig` dispatch_model is required (set explicitly) | `.ASYNC` stored as set |
| `TcpServerConfig` kernel_backlog default | 4096 |
| `TcpServerConfig` max_recv_buf default | 4096 |
| `TcpServerConfig` workers default | 0 (auto) |
| `TcpClientConfig` max_recv_buf default | 4096 |
| TCP frame length header | 4-byte big-endian u32 encodes and decodes correctly |
| TCP frame zero-length payload | encodes as four zero bytes |
| TCP frame header size | always exactly 4 bytes |
| `DispatchModel.ASYNC` is zero value | `@intFromEnum(.ASYNC) == 0` |

### tests/behaviour/http/

#### `request_test.zig`

| Test | What it verifies |
| :- | :- |
| `path()` strips query string | `"/api/users?limit=10"` -> `"/api/users"` |
| `path()` returns full target when no `?` | `"/api/users/alice"` unchanged |
| `path()` root path | `"/"` returns `"/"` |
| `query()` returns portion after `?` | `"q=hello&lang=zig"` |
| `query()` returns empty when no `?` | `""` |
| `body()` chunked produces same payload as Content-Length | chunked `"world"` matches `body_cache = "world"` |
| `body()` second call returns cached result | `b1.ptr == b2.ptr` after two body() calls |
| `method()` resolves each method | DELETE/PATCH/PUT/OPTIONS/HEAD/GET/POST all resolved |

#### `router_test.zig`

| Test | What it verifies |
| :- | :- |
| Exact beats param regardless of registration order | exact registered after param still wins |
| Param beats prefix regardless of registration order | param registered after prefix still wins |
| Prefix: longest match wins | `/api/users` beats `/api` for `/api/users/alice` |
| Prefix matches its own path exactly | `/api` matches `/api` |
| Query string transparent for param dispatch | `"/users/bob?role=admin"` captures `bob` via `:id` |
| Query string transparent for exact dispatch | `"/about?ref=menu"` matches `/about` |

#### `content_test.zig`

| Test | What it verifies |
| :- | :- |
| Text group extensions | html/htm/css/txt/csv |
| Application group extensions | json/map/js/min.js/xml/pdf/wasm/zip/gz/tar/7z/rar/rtf |
| Image group extensions | png/jpg/jpeg/gif/svg/webp/ico |
| Audio group extensions | mp3/wav/flac/mid/midi |
| Video group extensions | mp4/webm/ogg/mpeg/avi/mov/wmv/flv/mkv |
| Font group extensions | ttf/otf/woff/woff2 |
| Matching is case-insensitive | HTML, PNG, JS, JSON, JPG, JPEG, CSS, WOFF2 |
| `fromExtension()` returns correct MIME string | representative set |
| Alias pairs produce identical MIME strings | jpg==jpeg, mid==midi, html==htm, js==min.js, json==map |

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| Buffer size defaults | `kernel_backlog`, `max_recv_buf`, `max_allocator_size` all 4096 |
| Timeout defaults are disabled | `conn_timeout_ms == 0`, `handler_timeout_ms == 0` |
| Static serving disabled by default | `public_dir == ""`, `public_dir_upload == "u"` |
| `dispatch_model` is required (no default) | caller must set it in `HttpServerConfig` |
| `workers` defaults to auto-size | `workers == 0` |
| `max_request_headers` defaults to `.LARGE` | enum variant and `.value()` == 64 |
| `RequestHeaderSize` tier values | MINIMAL=16, COMMON=32, LARGE=64 |
| `RequestHeaderSize.CUSTOM(N)` capped at 64 | values above 64 silently return 64 |
| `max_response_headers` defaults to MINIMAL (16) | enum value and `.value()` |
| `HeaderSize` tier values | MINIMAL=16, COMMON=32, LARGE=64, EXTRA_LARGE=128 |
| `HeaderSize.CUSTOM(N)` returns N | 7 and 100 |
| `Response` status defaults to OK | `init()` invariant |

#### `sse_test.zig`

| Test | What it verifies |
| :- | :- |
| `ContentType.TEXT_EVENT_STREAM.asString()` | returns `"text/event-stream"` |
| `Response.streaming` defaults to false | `init()` invariant |

#### `query_test.zig`

RFC 10008 QUERY support on the `zix.Http` engine, held to the same contract as the raw engine.

| Test | What it verifies |
| :- | :- |
| Accepts a QUERY request line | the parser rejected QUERY outright before this |
| A QUERY request is distinguishable from a GET | the typed code differs |
| A QUERY request carries its content like a POST | chunked body delivery |
| A QUERY request exposes its declared Content-Type | section 2 |
| A QUERY without Content-Type reports no type | the 400 case |
| An unsupported query content type reports no match, never sniffed | section 2.1 |
| Every query content type RFC 10008 names is recognised | the table matches the raw engine's |
| Http and Http1 agree on what a QUERY request is | one answer from both engines |
| A method it does not implement draws 501, not 400 | the line tokenized, so the request was not malformed |
| Http and Http1 answer an unimplemented method identically | byte-identical response |

### tests/behaviour/http1/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `dispatch_model` is required and stored as set | the field round-trips |
| `workers` defaults to zero (auto) | zero means auto-size |
| `kernel_backlog` default is 1024 | the shipped default |
| Buffer size defaults | `max_recv_buf` 6 KiB, `compression_max_out` 256 KiB |
| Compression defaults | off, `min_size` 256, `max_out` 256 KiB |
| `DispatchModel` integer backing values | `ASYNC` is the zero value |
| Static cache is off by default | `public_dir_cache_ttl_ms` 0, `public_dir_cache_max_entries` 256 |
| Static cache fields are stored as set | both round-trip |
| Static cache knobs are independent of the response cache knobs | the two caches share no state |

#### `core_test.zig`

| Test | What it verifies |
| :- | :- |
| `parseHead` extracts method, path, and version | the request line is split correctly |
| `parseHead` HTTP/1.1 defaults keep_alive to true | RFC default persistence |
| `parseHead` `Connection: close` disables keep_alive | the header overrides the default |
| `getHeader` returns value case-insensitively | header lookup ignores case |
| `queryParam` returns value for named param | query parsing by name |

#### `query_test.zig`

RFC 10008 QUERY support through the public `zix.Http1` surface.

| Test | What it verifies |
| :- | :- |
| `parseHead` reads QUERY off the request line | the method token survives the parse |
| `Request.method` resolves a QUERY request to QUERY | the typed code, not a fallback |
| A QUERY request is distinguishable from a GET | the defect this closes: unknown tokens used to resolve to GET |
| A QUERY request carries its content like a POST | Content-Length framing and `body()` delivery |
| A QUERY request exposes its declared Content-Type | section 2 needs the handler to read it |
| A QUERY without Content-Type reports no type | the 400 case |
| An unsupported query content type reports no match, never sniffed | section 2.1 forbids guessing from the body |
| Every query content type RFC 10008 names is recognised | sql, jsonpath, graphql, x-www-form-urlencoded, multipart/form-data |
| A QUERY response is never filed under the request cache key | section 2.7, the key carries no content |
| Refusing QUERY leaves GET on the same path cacheable | the refusal is scoped to the method |
| The query content types compose a valid Accept-Query value | section 3, an RFC 9651 sf-list of bare items |
| A method it does not implement draws 501, not a wrong answer | RFC 9110 section 15.6.2 |
| QUERY is implemented, so it parses instead of drawing 501 | the same gate that refuses an unknown method passes QUERY |

### tests/behaviour/websocket/

#### `websocket_test.zig`

| Test | What it verifies |
| :- | :- |
| FIN bit always set | byte[0] & 0x80 for text, binary, ping, pong, close |
| Server frames unmasked | byte[1] & 0x80 == 0 for all opcodes (RFC 6455 5.1) |

### tests/behaviour/udp/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `UdpServerConfig` conn_timeout_ms | default 5000 |
| `UdpServerConfig` poll_timeout_ms | default 2000 |
| `UdpServerConfig` auto_ack | default false |
| `UdpServerConfig` broadcast | default false |
| `UdpServerConfig` endianness | default LITTLE |
| `UdpServerConfig` allow_args | default false |
| `Udp.DispatchModel` re-export | resolves to the shared dispatch enum |
| `UdpClientConfig` endianness | default LITTLE |
| `UdpClientConfig` recv_timeout_ms | default 0 (disabled) |

#### `packet_test.zig`

| Test | What it verifies |
| :- | :- |
| `toEndian` NATIVE is a no-op | bytes unchanged on any host |
| u8 array fields never swapped | `id [4]u8` untouched by LITTLE and BIG |
| Non-native swaps integer fields | `i32` field byte-swapped |
| Non-native swaps float array elements | `[2]f64` elements each swapped |

### tests/behaviour/http/ (client)

#### `client_test.zig`

| Test | What it verifies |
| :- | :- |
| `ClientConfig` connect/response/read timeout defaults | all 0 (disabled) |
| `ClientConfig` max_response_body default | 4 MB (1024 * 1024 * 4) |
| `ClientConfig` follow_redirects default | true |
| `ClientConfig` max_redirects default | 3 |
| `ClientConfig` user_agent default | matches `zix.Http.default_user_agent` (library version string from `build.zig.zon`) |
| `ClientResponse.status()` | returns status_code field |
| `ClientResponse.body()` | returns body_data slice |
| `ClientResponse.header()` case-insensitive | matches regardless of header name casing |
| `ClientResponse.deinit()` zero-length body | safe, no crash or leak |

### tests/behaviour/uds/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `UdsServerConfig` backlog default | 128 |
| `UdsServerConfig` max_recv_buf default | 4096 |
| `UdsClientConfig` stores path | path field preserved |
| UDS frame length header | 4-byte big-endian u32 encodes and decodes correctly |
| UDS frame zero-length payload | encodes as four zero bytes |
| UDS frame header size | always exactly 4 bytes |

### tests/behaviour/fix/

#### `session_test.zig`

| Test | What it verifies |
| :- | :- |
| Logon response has MsgType=A and CompIDs swapped | reply tag-35="A", tag-49=SERVER, tag-56=CLIENT, tag-34=1 |
| NewOrderSingle body fields are preserved in echo | tag-11 (ClOrdID), tag-55 (Symbol), tag-54 (Side), tag-38 (Qty) all present in echo |
| Clean Logout causes no server-side error | server error field is null after Logout exchange |

### tests/behaviour/logger/

#### `logger_test.zig`

| Test | What it verifies |
| :- | :- |
| `Level` backing values | DEBUG=0 INFO=1 WARN=2 ERROR=3 |
| `ConsoleMode` backing values | OFF=0 DEBUG_ONLY=1 ALWAYS=2 |
| `Config` defaults | console=OFF, console_min_level=INFO, save_path="", save_file="log", save_min_level=INFO, max_lines=1_000_000 |
| `Logger` init and deinit with no save_path | no crash or leak |
| `Logger` flush with no save_path is a no-op | no crash |
| `Http.ServerConfig.logger` defaults to null | `cfg.logger == null` invariant |
| `Http.Context.logger` defaults to null | `ctx.logger == null` invariant |
| `Http.Response.bytes_written` defaults to 0 | `res.bytes_written == 0` after `init()` |

### tests/behaviour/http2/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `Http2ServerConfig` dispatch_model is required (no default) | caller must set it explicitly |
| `Http2ServerConfig` max_streams defaults to 128 | `max_streams == 128` invariant |
| `Http2ServerConfig` max_frame_size defaults to 16384 | `max_frame_size == 16384` invariant |
| `Http2` HandlerFn can be assigned to a local variable | `zix.Http2.HandlerFn` type assignment compiles |
| `Http2` PREFACE length is 24 | `zix.Http2.PREFACE.len == 24` |
| `Http2` ERR_NO_ERROR is zero | `zix.Http2.ERR_NO_ERROR == 0` |
| `Http2` FLAG_END_STREAM and FLAG_END_HEADERS are distinct | `FLAG_END_STREAM != FLAG_END_HEADERS` |

### tests/behaviour/http3/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| Static serving is off by default | empty `public_dir`, ttl 0, 256 entries |
| Static fields are stored as set | all three round-trip |
| Static serving needs caching, unlike the other engines | pins the deliberate asymmetry: on Http3 a ttl of 0 disables static serving entirely, because the response body outlives its handler |

#### `webtransport_test.zig`

The `zix.Webtransport` surface an application and a peer depend on, driven through the handles a caller actually holds: the engine hooks here are the dispatch layer's contract (open a stream, send a datagram, close a session) implemented over a worker pool, so a session and a stream move the way a connection moves them, minus the socket.

| Test | What it verifies |
| :- | :- |
| the HTTP/3 server config carries the feature off and costs nothing while it is | the default is disabled, and an off config advertises nothing |
| a config past the connection ceilings is refused by the field that crossed them | `capacityError` names the field, and the ceilings themselves are accepted |
| the pool sizing a config asks for is the window a stream has to write into | the pool config a `Config` maps onto carries the stream buffer size through |
| the token a client sends is the dialect its session speaks | the CONNECT `:protocol` token decides draft-16 or draft-07, and an unknown token decides neither |
| a stream is a write window, a FIN closes it, and only an acknowledgement finishes it | the write/back-pressure contract, the FIN rule, and the send-finished predicate |
| a session enforces the data limit it advertised and raises it as the peer consumes it | the session data limit rejects what crosses it and a capsule raises it |
| a datagram is framed with its session's quarter stream id and bounded by the peer's limit | the HTTP/3 datagram layout and the payload budget against the advertised frame size |

### tests/behaviour/webrtc/

#### `session_test.zig`

| Test | What it verifies |
| :- | :- |
| A peer answers a connectivity check before anything is negotiated | ICE runs ahead of DTLS, so a check is answered on a peer with no session yet |
| The association only exists once the handshake finishes | SCTP is inside DTLS, so nothing is readable before the handshake completes |
| A peer that says nothing is dropped on its idle deadline | `peer_idle_ms` is enforced, which is what covers a browser closing its tab |
| Every datagram pushes the idle deadline back | a live but quiet peer is not dropped |
| A dialer keeps asking until a check is answered | the retransmit timer drives the client half, not a fixed count |

### tests/behaviour/grpc/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `GrpcServerConfig` defaults | dispatch_model=ASYNC, kernel_backlog=1024, workers=0, max_streams=128, max_frame_size=16384, max_body=16384 |
| `GrpcClientConfig` basic fields | ip and port fields preserved |
| `GrpcStatus` enum values | OK=0, CANCELLED=1, UNIMPLEMENTED=12, UNAUTHENTICATED=16 |
| `GrpcContext.recvMessage` empty body | returns null immediately |
| `GrpcPrefix` roundtrip | writePrefix -> readPrefix preserves compress flag and message length |
| `parsePath` valid path | `/helloworld.Greeter/SayHello` -> `package_service="helloworld.Greeter"`, `method="SayHello"` |
| `parseTimeout` seconds | `"2S"` -> 2,000,000,000 nanoseconds |

### tests/behaviour/channel/

#### `channel_test.zig`

| Test | What it verifies |
| :- | :- |
| `closed` field defaults to false | `init()` invariant |
| `head` starts at zero | `init()` invariant |
| Ring tail formula is `(head + count) % buf.len` | manually set state verifies arithmetic |
| `send` increments count | count goes from 0 to 1 after one send |
| `recv` decrements count | count returns to 0 after recv |
| `close` sets closed field | `ch.closed == true` after close |

---

## Edge Tests

Source: `tests/edge/`. Each file verifies boundary conditions and error paths.

### tests/edge/tcp/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| `TcpServer.init` port zero | returns `error.ZixPortNotConfigured` |
| `DispatchModel` backing values stable | ASYNC=0, EPOLL=1, URING=2 |
| `DispatchModel` dropped names gone | `stringToEnum` returns null for POOL and MIXED |
| TCP frame max u32 length | `maxInt(u32)` encodes and decodes correctly via big-endian |

### tests/edge/http/

#### `request_test.zig`

| Test | What it verifies |
| :- | :- |
| `queryParam` key present with empty value | `"?k="` -> `""` (not null) |
| `queryParam` key absent returns null | key not in query string |
| `queryParam` no query string at all returns null | target has no `?` |
| `body()` chunked invalid hex is an error, not an empty body | `"zz"` chunk size -> `error.ZixInvalidChunkedBody`, `bodyComplete()` false (the engine answers 400) |
| `body()` chunked missing terminal chunk returns partial data | no `0\r\n\r\n` -> partial data returned |
| `body()` chunked single-byte chunks | `1\r\na\r\n1\r\nb\r\n1\r\nc\r\n0\r\n\r\n` -> `"abc"` |

#### `router_test.zig`

| Test | What it verifies |
| :- | :- |
| No registered route returns false | empty router, `dispatch` returns false |
| Prefix `/api` does NOT match `/apiv2` | next char after prefix must be `/` or end-of-path |

#### `response_test.zig`

| Test | What it verifies |
| :- | :- |
| CR in header name -> `InvalidHeaderName` | injection guard |
| LF in header name -> `InvalidHeaderName` | injection guard |
| CR in header value -> `InvalidHeaderValue` | injection guard |
| LF in header value -> `InvalidHeaderValue` | injection guard |
| Buffer grows from 4 to 5 on 5th header | initial cap=4, growth to min(8, max_response_headers) |
| `max_response_headers=1` rejects second header | no growth: `TooManyHeaders` immediately |
| `HeaderSize.CUSTOM(0).value()` | returns 0 |

#### `content_test.zig`

| Test | What it verifies |
| :- | :- |
| Unknown extension -> `APPLICATION_OCTET_STREAM` | xyz, bin, dat, unknown |
| Empty string -> `APPLICATION_OCTET_STREAM` | `typeFromExtension("")` |
| `fromExtension` unknown -> `"application/octet-stream"` | string form of fallback |

#### `query_test.zig`

QUERY boundary conditions on the `zix.Http` engine.

| Test | What it verifies |
| :- | :- |
| Matches the QUERY token exactly, as it does every method | RFC 9110 section 9.1, method names are case-sensitive |
| A five-byte token that is not QUERY is still refused | the length arm is not a catch-all |
| An unimplemented method answers 501, a broken line answers 400 | the status comes from the error |
| A QUERY with zero Content-Length frames as bodyless | framing |
| A chunked QUERY body decodes to the same bytes as Content-Length | the two framings agree |
| A QUERY keeps both its query string and its content | target parameters survive |
| The longest query content type is matched, not truncated | 33 bytes |
| An absurd Content-Type reports no match instead of overrunning | bounded |
| An empty Content-Type value reports no match | empty, lone semicolon, whitespace |
| A multipart QUERY boundary parameter does not defeat the match | parameters stripped |
| Both engines answer the same for a parameterised query type | the two content tables stay in step |

### tests/edge/websocket/

#### `websocket_test.zig`

| Test | What it verifies |
| :- | :- |
| 0 bytes -> null | fewer than 2 bytes (can't read header) |
| 1 byte -> null | fewer than 2 bytes |
| Truncated payload -> null | header says 5 bytes but only 3 present |
| Extended 16-bit length (126-tier) | 130-byte payload: byte[1] carries 126 marker |
| `acceptKey` key too long -> `error.ZixKeyTooLong` | key >= 93 bytes exceeds 128-byte hash_input |

### tests/edge/udp/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| Port zero | `UdpServer.init` returns `error.ZixPortNotConfigured` |
| Non-zero port | `UdpServer.init` succeeds |

#### `packet_test.zig`

| Test | What it verifies |
| :- | :- |
| `Endianness` enum backing values stable | NATIVE=0, LITTLE=1, BIG=2 |
| `FeedbackResult` ack/nack are tag-only | active tag matches .ack and .nack |

### tests/edge/http/ (client)

#### `client_test.zig`

| Test | What it verifies |
| :- | :- |
| Unsupported scheme -> `error.ZixUrlSchemeUnsupported` | `ftp://` scheme not accepted |
| Missing host -> `error.ZixUrlHostMissing` | `http://` with no host |
| Malformed URL -> `error.ZixUrlMalformed` | `:::bad` fails at parse |
| `ClientResponse.header()` absent name | returns null |
| `RequestOpts.connect_timeout_ms` override | null, 0, and non-zero are distinct values |

### tests/edge/uds/

#### `config_test.zig`

| Test | What it verifies |
| :- | :- |
| Empty path -> `error.ZixPathEmpty` | `UdsServer.init(.{ .path = "" })` returns PathEmpty |

### tests/edge/logger/

#### `logger_test.zig`

| Test | What it verifies |
| :- | :- |
| `statusLevel` 2xx boundary | `access()` does not crash for every status class (100-599) |
| `Level` enum ordering | DEBUG < INFO < WARN < ERROR via `@intFromEnum` |
| `system()` below `save_min_level` is silent | calls below threshold do not open a file (`file_fd == -1`) |
| `access()` below `save_min_level` is silent | same: `file_fd == -1` after filtered call |
| `system()` with empty component does not panic | `component = ""` is safe |
| `system()` with empty format does not panic | `fmt = ""` is safe |
| `access()` with empty method and path does not panic | empty strings are safe |
| `init` with empty `save_path`, `file_fd` stays invalid | `file_fd == -1` with `save_path = ""` |
| Console OFF (no output or panic for any level) | all four levels produce no crash with `console = .OFF` |

### tests/edge/fix/

#### `session_test.zig`

| Test | What it verifies |
| :- | :- |
| `parseFields` handles maximum number of fields without panic | `MAX_FIELDS - 1` tag=value pairs parsed without overflow or crash |
| `verifyChecksum` returns false for truncated message | message missing final SOH checksum delimiter |
| `findMessageEnd` returns null for message with tag-10 value but no final SOH | partial checksum field returns null |
| `buildMessage` with zero extra fields produces valid message | output passes `verifyChecksum` and `parseFields` round-trip |
| Message arriving in two TCP segments is reassembled correctly | split Logon across two flushes, server still replies with MsgType=A |
| Bad checksum causes server to close without server-side error propagation | corrupted message byte closes connection `ctx.err == null` |

### tests/edge/http1/

#### `body_test.zig`

Content-Length is what every dispatch model uses to decide whether a body is delivered whole, waited for, or drained, so a value the parser rejects changes which path a request takes.

| Test | What it verifies |
| :- | :- |
| absent Content-Length frames the request as bodyless | no header -> `content_length` 0, chunked flag false |
| zero Content-Length frames the request as bodyless | `Content-Length: 0` -> 0 |
| non-numeric Content-Length falls back to zero | `abc` -> 0 |
| Content-Length with a trailing space falls back to zero | `5 ` -> 0 |
| Content-Length past u64 falls back to zero | 23-digit value -> 0 |
| Content-Length is read case-insensitively | `cOnTeNt-LeNgTh` honored |
| chunked request sets the chunked flag beside Content-Length | both header values are kept |
| Expect 100-continue is flagged for a body-carrying request | `expect_continue` true |
| Request bodyReceived is zero for a bodyless request | and `body()` returns empty |
| Request bodyReceived tracks the delivered slice by default | 4-byte slice -> 4 |
| Request bodyComplete is true for a bodyless request | nothing declared, nothing could fall short |
| Request bodyComplete is independent of the delivered length | a short delivered slice stays complete, the engine override makes it false |

#### `core_test.zig`

| Test | What it verifies |
| :- | :- |
| `parseHead` missing CRLF terminator | returns `IncompleteHeader` |
| `parseHead` empty request line | returns `InvalidRequest` |
| `parseHead` missing HTTP version | returns `InvalidRequest` |
| `queryParam` key with empty value | returns an empty string, not null |
| `queryParam` absent key | returns null |
| `parseRange` start beyond total | returns null |
| `parseRange` missing `bytes=` prefix | returns null |
| `percentDecode` encoded space | decoded in place |

#### `static_cache_test.zig`

Every case here ends in a null hit, which the engines treat as "serve it uncached".

| Test | What it verifies |
| :- | :- |
| Declines a path that escapes public_dir | traversal, absolute, and empty are refused before any open |
| Declines a resolved path longer than its buffer | an oversize path is declined, not truncated |
| With ttl 0 never stores anything | the disabled default consumes no slot |
| Declines a directory | a directory opens but is not servable, so it is not published |
| Serves a zero-byte file as a real hit | `Content-Length: 0`, still a hit |
| Expiry is exact at the window boundary | fresh at `insert + ttl - 1`, expired at `insert + ttl` |
| Keeps serving after the table fills with pinned entries | a full table declines the new path and leaves held entries intact |
| Negotiation falls back to identity when a client rejects everything | serving the plain file beats refusing it |
| Init survives an absurd entry request | clamped against the descriptor budget, still a power of two |

#### `query_test.zig`

QUERY boundary conditions: the two peer-controlled values a QUERY puts on paths that bodyless methods never reached.

| Test | What it verifies |
| :- | :- |
| A lowercase method token is refused, not folded | RFC 9110 section 9.1, method names are case-sensitive |
| Http1 and Http answer a lowercase method the same way | one shared method table, so the two engines cannot drift apart again |
| A method token past the known maximum is refused, not truncated | bounded by the length switch |
| An unimplemented method answers 501, a broken line answers 400 | the two failures stay apart |
| A malformed request line is not reported as an unknown method | a line that never tokenized says nothing about the method |
| A QUERY with an empty method-adjacent target still parses | root target |
| Zero and absent Content-Length frame as bodyless | nothing declared means nothing to read |
| A chunked QUERY sets the chunked flag | chunked framing is method-agnostic |
| A QUERY may carry Expect 100-continue | the large-body handshake |
| A QUERY body past the receive buffer reports what arrived | `bodyReceived` vs `content_length`, the case a GET cannot express |
| A QUERY keeps both its query string and its content | the target parameters are not replaced by the body |
| The longest query content type is matched, not truncated | 33 bytes, the value that overran the old buffer |
| An absurd Content-Type reports no match instead of overrunning | a peer controls this header |
| An empty Content-Type value reports no match | empty, lone semicolon, whitespace |
| A multipart QUERY boundary parameter does not defeat the match | parameters are stripped first |
| A QUERY store is refused even when the response fits the cache | not a size effect |
| A QUERY encoded store is refused on the compressed path too | the per-encoding slots carry the same refusal |

### tests/edge/http2/

#### `server_test.zig`

Port: 18100.

| Test | What it verifies |
| :- | :- |
| bad PRI preface causes server to close connection | malformed preface bytes -> server closes the connection cleanly |
| client sends GOAWAY and server connection loop exits | GOAWAY frame -> server exits the frame loop without error |
| `Http2Server.init` rejects port zero | returns `error.ZixPortNotConfigured` |
| `HpackDecoder` decode of empty block returns zero headers | `decode(&.{}, ...)` returns 0 headers without error |
| `writeFrameHeader` stream_id high bit is cleared on read | `stream_id = 0x7FFF_FFFF` roundtrips correctly via pipe |

### tests/edge/http3/

#### `static_test.zig`

The boundaries where the engine has to decline rather than hand its send path a body it cannot hold.

| Test | What it verifies |
| :- | :- |
| Declines a file past the snapshot ceiling | over 8 MiB is declined for bytes, while the descriptor path still resolves it for the other engines |
| Serves a file exactly at the snapshot ceiling | the ceiling is inclusive |
| Serves a zero-byte file as an empty body | an empty slice is already stable, nothing is snapshotted |
| Bytes are a snapshot, not a window onto the file | an in-place rewrite does not change bytes already handed out |
| Bytes survive a truncation to a shorter file | the dangerous shape: the file shrinks while a response is still sending |
| Declines every unsafe path before touching the disk | traversal, absolute, and empty |
| Bytes are snapshotted once and reused across requests | one copy backs concurrent responses, and each holds its own pin |

#### `webtransport_test.zig`

The boundaries of `zix.Webtransport` at its public surface, and the hostile input a peer is free to send: a capsule stream that declares more than the reader holds, an application error at the ends of its range, a send window whose bookkeeping is full, a pool at its last slot, and a session that has already ended.

| Test | What it verifies |
| :- | :- |
| the capsule reader holds a value up to its limit and skips one past it | `max_known_value` is exactly the largest capsule the binding defines, one byte more is skipped in place, and the capsule behind it still arrives |
| a capsule value one byte short of its own length is not delivered | the declared length is what the reader trusts, so a short capsule is still arriving |
| the application error mapping spans the 32-bit ends without landing on a grease code | `0` and `0xffffffff` map to the ends of the application range, and a framing error code does not decode as one |
| a peer reset reports an application code only when it carried one | a code outside the application range reads as a reset with no application code |
| a stream whose sent-range list is full is offered no more bytes | the list is bounded, and a full list stops the pump rather than sending a byte it could no longer account for |
| a reset covers at least the header of the kind it resets | a reliable reset delivers the header, or the peer could not tell which session the stream belonged to |
| the pool refuses past its last slot and the pre-session table holds nothing it refuses | a one-slot pool refuses the second session instead of serving it out of the first one's slot |
| a closed session refuses streams and datagrams and clips its close message | a closed session opens nothing, sends nothing, and reports a message no longer than the limit |

### tests/edge/webrtc/

#### `session_test.zig`

Everything arrives on one port and is sorted by its first byte, so the boundaries here are about
what a peer does with a datagram it cannot use.

| Test | What it verifies |
| :- | :- |
| A peer survives every first byte there is | all 256 values are classified and none of them panics |
| An empty datagram is dropped and changes nothing | no state moves on a zero-length receive |
| A DTLS record whose length runs off the end is not read past | the declared length is never trusted over the buffer |
| A STUN message with the right first byte and nothing else is refused | routing is not validation, the magic cookie still has to check out |
| Application data before the handshake finishes goes nowhere | epoch 1 records are refused until there are epoch 1 keys |
| The same garbage a thousand times still leaves the peer alive | a repeated bad datagram exhausts nothing |
| A dialer refuses a response carrying somebody else's transaction | the transaction id is checked, not just the message type |

### tests/edge/grpc/

#### `server_test.zig`

Ports: 18220-18221.

| Test | What it verifies |
| :- | :- |
| `readGrpcPrefix` with 4 bytes | returns `error.ZixTooShort` |
| `readGrpcPrefix` with empty slice | returns `error.ZixTooShort` |
| `GrpcContext.recvMessage` body shorter than prefix | body has 3 bytes (need 5 for prefix): returns null |
| `GrpcContext.recvMessage` msg_len exceeds body | prefix claims 100 bytes but body has only 5: returns null |
| `parsePath` empty string | returns null |
| `parsePath` no leading slash | returns null |
| `parsePath` only slash | returns null |
| `detectContentType` no header | returns UNKNOWN |
| `detectContentType` text/plain | returns UNKNOWN |
| `parseTimeout` single character | returns null |
| `GrpcClient.connect` port zero | returns `error.ZixPortNotConfigured` |
| `serveConn` closes cleanly on immediate client disconnect | server accepts, client disconnects immediately, no crash or error |
| gRPC finish-only handler delivers error status to client | handler calls `res.finish(INVALID_ARGUMENT, ...)` only, client receives the error status without any data frames |

### tests/edge/channel/

#### `channel_test.zig`

| Test | What it verifies |
| :- | :- |
| Capacity 1 allocates exactly one slot | `buf.len == 1`, `count == 0` |
| Ring head wraps at `buf.len` | `(3+1) % 4 == 0` |
| Full boundary: `count == buf.len` | tail index wraps back to head |
| `send` after close | returns `error.ZixClosed` |
| `recv` on empty closed channel | returns `error.ZixClosed` |

---

###### end of tests
