# zix Config Reference

What every adjustable zix configuration field means, and how changing it affects a running process. Covers the server engines and the TLS context, plus shared components (the Logger) that any engine attaches by pointer. One section per config. Each field lists its default, what it controls, and the tuning trade-offs.

It is indexed by config field: one section per config struct, each field with its default and what the source enforces.

Note: a server attaches a Logger through its `logger` field (a pointer). The Logger's own sizing knobs live once on the Logger config (see the Logger section), not on each server config.

## How to read the columns

A cell is left blank when it does not apply (a required handle like `io` has no tuning trade-off).

| column | meaning |
| :- | :- |
| field | the config struct field name |
| default | the value used when the field is omitted |
| controls | what the field does |
| perf impact | where it sits (hot path, per-conn, per-worker, startup) and which metric it moves |
| how to tweak | direction of change for a goal |
| if lower | consequence of a smaller value |
| if higher | consequence of a larger value |
| knob consequence | the main risk if it is misconfigured |

## Dispatch model (shared by all TCP-family engines)

`dispatch_model` selects the whole concurrency strategy. It is required: set it explicitly, there is no default. Values:

| value | meaning |
| :- | :- |
| `.ASYNC` | one accept thread, one `io.async()` per connection. Best for low latency at moderate connection counts. |
| `.EPOLL` | shared-nothing: each worker owns one SO_REUSEPORT listener plus one epoll instance. Best for very high connection counts. Linux-only, `run()` returns `error.ZixDispatchModelUnsupported` elsewhere. |
| `.URING` | shared-nothing io_uring: same per-core topology as `.EPOLL`, completion-based so most syscalls are batched away. Linux-only, probes the ring at startup and folds to `.EPOLL` when io_uring is unavailable. |

## HTTP/1 (`Http1ServerConfig`)

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, must be non-zero | | | | | zero is not validated: binds a kernel-chosen ephemeral port |
| dispatch_model | required | concurrency model (see table above) | picks the whole strategy | `.EPOLL`/`.URING` for high connection counts on Linux | | | wrong model caps throughput, off Linux only `.ASYNC` runs |
| kernel_backlog | 1024 | TCP listen backlog before accept() | kernel accept queue depth | raise under bursty connection storms | new connections dropped during a burst | more kernel memory for the queue | too low drops connections during spikes |
| workers | 0 | accept thread count, 0 = cpu_count | parallelism across cores | leave 0 (auto), or pin a count | fewer cores used | oversubscription and context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the .EPOLL/.URING handler threads | per-thread RSS (demand-paged) | raise for deep handlers or large stack locals, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| worker_stack_compress_bytes | 2097152 | worker stack when compression is on, applied as a floor: effective stack is max(worker_stack_size_bytes, this) | per-thread RSS under .EPOLL/.URING with compression | raise if a compressing handler needs more | flate (about 230 KB on the handler frame) can overflow a small stack | wasted RSS per worker | no effect when compression is off |
| busy_poll_us | 50 | SO_BUSY_POLL spin window in microseconds for accepted connections (.EPOLL) | hot, kernel busy-spins before sleeping the worker | raise to cut tail latency under load, 0 to save idle CPU | shorter spin, more idle-sleep wakeups, higher tail latency | cores spin at 100% when idle | no-op without kernel SO_BUSY_POLL support |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): a new connection goes to listener index = receiving CPU mod workers instead of the 4-tuple hash | connection placement (per SYN, zero hot-path cost) | enable on multi-core hosts so a connection is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| max_recv_buf | 6144 | read buffer per connection on every dispatch model (.EPOLL / .URING slots, the .ASYNC pool-thread pair), bounds the head and the body slice a handler sees | per-conn memory and max request size | raise for large request headers | large requests rejected | more memory per connection | too low rejects valid large requests |
| large_body_rcvbuf | 0 | SO_RCVBUF applied only on the large-body path (a body bigger than the read buffer, ie uploads), 0 leaves the kernel default | upload ingest speed and per-conn memory while a large body is in flight | raise for faster upload ingestion | uploads ingest slower (narrow kernel-default window) | more memory during a large body (256 KiB targets about 256 MiB resident at 256c) | only the upload path touches it, small-request cells are unaffected |
| max_request_body | 8388608 | largest request body the engine takes: a declared Content-Length past it is refused with 413 before the body is read or drained, 0 removes the check | one compare per body-carrying request, nothing on the hot GET path | lower to bound uploads, 0 to trust the declared length | legitimate large uploads refused with 413 | a client can make a worker consume more bytes per request | chunked declares no length up front, so it is bounded by the body buffer instead (413 past it) |
| ws_recv_buf | 0 | per-connection receive buffer for WebSocket connections, 0 falls back to max_recv_buf | per-WS-conn memory and WS pipelined-burst depth | raise above max_recv_buf to hold a deeper pipelined burst | more compact-and-reread churn for WS | more memory per WS connection | .EPOLL sizes the recv buffer, .URING sizes the frame-accumulation buffer and unmask scratch, 0 reuses max_recv_buf |
| uring_send_buf_size | 16384 | per-connection send buffer for the .URING dispatch model (the send half, max_recv_buf covers recv) | per-conn memory under .URING | raise for larger single responses, lower to shrink per-conn memory | more buffer growth on big responses | more memory per connection | no effect under other dispatch models |
| uring_idle_pool_floor | 8 | warm idle slot floor per worker under .URING (also the strides pretouched at startup) | warm memory vs first-touch faults on new connections | raise to keep more slots warm for bursty churn, lower to shrink idle memory | more page faults after a quiet spell | more idle slots kept resident | warm cap is clamp(live_count, floor, ceiling), no effect under other models |
| uring_idle_pool_ceiling | 256 | absolute warm idle slot ceiling per worker under .URING, holds the warm set below live_count at high concurrency | resident memory at high connection counts | raise to keep more warm for reconnect, lower to shrink the resident set under churn | more page faults on reconnect at high concurrency | more closed slots kept resident (cache and TLB pressure) | the fix for the high-connection regression where the warm set tracked live_count, no effect under other models |
| process_queue_len | 0 (off) | per-worker FIFO ring (.URING) that parks a recv or send re-arm when the submission queue is full and retries it next loop pass instead of closing the connection, 0 disables the feature | per-worker slab, references only (fd + generation), engages only when the SQ fills under a burst | size to about peak concurrent connections per worker so an SQ-full burst parks instead of dropping connections | ring fills sooner under a burst, the newest entry is rejected and that connection falls back to close | more reserved slab per worker (entry count times a few bytes) | no effect under other dispatch models, a value far above peak connections per worker reserves slab that faults resident over time for no gain |
| max_response_headers | `.MINIMAL` (16) | max custom response headers (addHeader capacity, ADR-062) | per-response memory, lazily allocated on first addHeader | raise the tier for many custom headers | extra headers cannot be set | more per-response memory | requests that add none pay nothing |
| conn_timeout_ms | 0 | connection lifetime guard in ms, 0 = disabled (ADR-062) | background timer eviction on `.ASYNC` | set to evict long-lived connections on the blocking model | connections cut sooner | longer-lived connections | documented no-op on `.EPOLL`/`.URING` (their event loops own connection lifetime) |
| handler_timeout_ms | 0 | per-handler execution budget in ms, 0 = disabled | cooperative deadline | set to bound slow handlers | handlers cut off sooner | slow handlers run longer | handlers must check isExpired() for it to take effect |
| send_date_header | true | include the Date header in every response (RFC 7231) | 37 bytes per response | leave on for compliance, off to shrink responses | | | off drops a standard header |
| public_dir | "" | root directory for static file serving, empty disables it | disk I/O on static hits | set to serve static files for routes that match no handler | | | non-empty is validated at run(), a missing dir yields error.ZixPublicDirNotFound |
| public_dir_upload | "u" | upload subdirectory under public_dir, a declarative path an upload handler writes to by convention | | set the upload path | | | relative to public_dir, the engine does not auto-wire uploads |
| public_dir_cache_ttl_ms | 0 | how long a resolved static file stays cached in ms, 0 = never cached (ADR-064) | one open descriptor per cached variant instead of an open plus a stat per request | set above 0 to keep static files open and their 200 header prerendered | every request re-opens and re-reads the file | a file edited on disk takes up to one window to appear | 0 is byte for byte the behaviour shipped before ADR-064 |
| public_dir_cache_max_entries | 256 | static cache slot count, one slot per file plus its .br and .gz siblings | descriptors and a demand-paged slot table | raise for a larger public_dir | files past the table serve uncached | more descriptors held | rounded down to a power of two, clamped against the process descriptor budget |
| compress | false | enable gzip/deflate/brotli response compression with Accept-Encoding negotiation | CPU vs body size, only pays off over a real network | enable when serving over a network, leave off for loopback benchmarks | | | on a loopback benchmark it is pure CPU cost |
| compression_min_size | 256 | minimum body size in bytes before compression is attempted | per-response check | raise to skip compressing small bodies | tiny bodies compressed for little gain | larger bodies sent uncompressed | too low wastes CPU on small bodies |
| compression_max_out | 262144 | max compressed output bytes across all codings | per-compressed-response cap | raise to compress larger bodies | larger bodies sent uncompressed | more CPU and memory before bailing | a body over this is sent uncompressed |
| response_cache | false | enable the per-worker response cache (ADR-036) | memory for cached responses | enable for hot, repeatable responses | | | off makes the cache API a no-op |
| cache_max_entries | 256 | cache slot count, rounded down to a power of two | per-worker memory = entries * value_bytes | raise for more distinct cached keys | fewer keys cached, more misses | more per-worker memory | per-worker, times the worker count |
| cache_max_value_bytes | 16384 | per-slot response cap, larger responses bypass the cache | per-slot memory | raise to cache larger responses | large responses bypass the cache | more per-worker memory | keep lean, caching pays off above a few KiB |
| cache_ttl_ms | 1000 | default cache freshness in ms | cache hit rate vs staleness | raise for higher hit rate, lower for fresher data | entries expire sooner, more misses | staler responses served | too high serves stale data |
| cache_max_total_bytes | 0 | optional ceiling on per-worker cache memory, 0 = no ceiling | caps total cache memory | set to bound cache RAM | effective entry count reduced to fit | uses the full entries * value_bytes | 0 disables the ceiling |
| tls | null | TLS context for https (opt-in), null = cleartext | enables TLS, a separate perf band | attach a context to serve https | | | null serves cleartext |
| tls_port | 0 | companion https bind port for the dual listener (ADR-060) | one worker fleet serves cleartext + TLS | set with tls to serve both from one server | 0 keeps single-listener behavior | | requires tls set, must differ from port |
| logger | null | optional logger for lifecycle lines | | attach for server logging | | | per-request access logging is the handler's job |

## HTTP/2 (`Http2ServerConfig`)

h2c cleartext by default, h2-over-TLS when `tls` is set.

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is rejected |
| dispatch_model | required | concurrency model | picks the strategy | `.EPOLL`/`.URING` on Linux for scale | | | `.URING` folds to `.EPOLL` when io_uring is unavailable, off Linux only `.ASYNC` runs |
| kernel_backlog | 1024 | TCP listen backlog | kernel accept queue | raise under connection storms | connections dropped during a burst | more kernel memory | too low drops connections |
| workers | 0 | accept thread count, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores used | context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the .EPOLL/.URING and TLS handler threads | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| busy_poll_us | 0 | SO_BUSY_POLL spin window in microseconds for accepted connections (.EPOLL / .URING) | hot, kernel busy-spins before sleeping the worker | set to e.g. 50 to cut tail latency under load | shorter spin, more idle-sleep wakeups | cores spin at 100% when idle | 0 leaves it unset, no-op without kernel SO_BUSY_POLL support |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): a new connection goes to listener index = receiving CPU mod workers instead of the 4-tuple hash | connection placement (per SYN, zero hot-path cost) | enable on multi-core hosts so a connection is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| max_recv_buf | 32768 | per-connection read buffer floor (.EPOLL / .URING mux) | per-conn read buffer, hot | raise to cut read() and compaction for large frames | more reads and compactions for big frames | more memory per connection | reader is max(this, one max frame) |
| tls_write_buf_initial_bytes | 16384 | initial capacity of the per-connection TLS pending-write buffer (grows on demand) | per-conn, TLS path | raise to avoid early reallocation under big responses | more reallocations under large responses | more idle memory per TLS conn | minor, amortization only |
| max_streams | 128 | max concurrent streams per connection (advertised SETTINGS_MAX_CONCURRENT_STREAMS) | per-conn slot pointer table, stream slots pooled per worker | raise for highly multiplexed clients | clients see REFUSED_STREAM sooner | wider pointer array, higher advertised concurrency | too low serializes a multiplexed client |
| max_frame_size | 16384 | MAX_FRAME_SIZE setting advertised to clients (bytes) | bytes per DATA frame | raise to send larger frames | more frames per response | larger per-frame buffers | bounded by the HTTP/2 spec range |
| max_header_scratch | 4096 | HPACK decode scratch per stream | per-stream buffer, pooled by concurrency | raise for large header sets | large header blocks rejected | more memory per concurrent stream | too low rejects valid headers |
| max_body | 16384 | max request body buffered per stream (bytes), larger is truncated | per-stream buffer, pooled by concurrency | raise for larger request bodies | bodies over this are truncated | more memory per concurrent stream | over-large wastes pool memory at peak concurrency |
| response_cache | false | enable the per-worker response cache (ADR-036), opt-in via serveCached/sendCached | cache memory | enable for hot, repeatable responses | | | off makes the cache API a plain send |
| cache_max_entries | 256 | cache slot count (power of two) | per-worker memory | raise for more keys | more misses | more memory | times the worker count |
| cache_max_value_bytes | 16384 | per-slot response cap | per-slot memory | raise for larger cached responses | large responses bypass the cache | more memory | keep lean |
| cache_ttl_ms | 1000 | default cache freshness in ms | hit rate vs staleness | raise for hit rate, lower for freshness | sooner expiry, more misses | staler data | too high serves stale data |
| cache_max_total_bytes | 0 | per-worker cache memory ceiling, 0 = none | caps cache memory | set to bound cache RAM | entry count reduced to fit | full entries * value_bytes | 0 disables the ceiling |
| tls | null | TLS context for h2-over-TLS (ALPN h2), null = h2c | enables TLS | attach a context with ALPN h2 | | | browsers require ALPN h2 for HTTP/2 over TLS |
| tls_port | 0 | companion h2-over-TLS bind port for the dual listener (ADR-060) | one worker fleet serves h2c + h2-over-TLS | set with tls to serve both from one server | 0 keeps single-listener behavior | | requires tls set, must differ from port |
| public_dir | "" | root directory for static file serving, empty disables it (ADR-064) | disk I/O on static hits | set to serve static files for routes that match no handler | | | Range (RFC 7233) served, 206 or 416, a multi-range header answers the first range |
| public_dir_cache_ttl_ms | 0 | how long a resolved static file stays cached in ms, 0 = never cached | one open descriptor per cached variant instead of an open plus a stat per request | set above 0 to keep static files open and their siblings resolved | every request re-opens and re-reads the file | a file edited on disk takes up to one window to appear | shares the process table with the other engines |
| public_dir_cache_max_entries | 256 | static cache slot count, one slot per file plus its .br and .gz siblings | descriptors and a demand-paged slot table | raise for a larger public_dir | files past the table serve uncached | more descriptors held | rounded down to a power of two, clamped against the process descriptor budget |
| logger | null | optional logger for lifecycle lines | | attach for logging | | | per-request logging is the handler's job |

## gRPC (`GrpcServerConfig`)

gRPC over HTTP/2. h2c cleartext by default, h2-over-TLS when `tls` is set.

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is rejected |
| dispatch_model | required | concurrency model | picks the strategy | `.EPOLL`/`.URING` on Linux for scale | | | off Linux only `.ASYNC` runs |
| kernel_backlog | 1024 | TCP listen backlog | kernel accept queue | raise under storms | dropped connections | more kernel memory | too low drops connections |
| workers | 0 | accept thread count, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores | context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the .EPOLL/.URING and TLS handler threads | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| busy_poll_us | 0 | SO_BUSY_POLL spin window in microseconds for accepted connections (.EPOLL / .URING) | hot, kernel busy-spins before sleeping the worker | set to e.g. 50 to cut tail latency under load | shorter spin, more idle-sleep wakeups | cores spin at 100% when idle | 0 leaves it unset, no-op without kernel SO_BUSY_POLL support |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): a new connection goes to listener index = receiving CPU mod workers instead of the 4-tuple hash | connection placement (per SYN, zero hot-path cost) | enable on multi-core hosts so a connection is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| max_recv_buf | 65536 | per-connection read buffer floor (.EPOLL / .URING) | per-conn read buffer, hot | raise to cut read() and compaction for large frames | more reads and compactions for big frames | more memory per connection | reader is max(this, one max frame) |
| tls_write_buf_initial_bytes | 16384 | initial capacity of the per-connection TLS pending-write buffer (grows on demand) | per-conn, TLS path | raise to avoid early reallocation under big replies | more reallocations under large replies | more idle memory per TLS conn | minor, amortization only |
| max_streams | 128 | max concurrent h2 streams per connection (advertised SETTINGS_MAX_CONCURRENT_STREAMS) | per-conn slot pointer table, stream slots pooled per worker | raise for highly multiplexed clients | clients see REFUSED_STREAM sooner | wider pointer array, higher advertised concurrency | too low serializes a multiplexed client |
| max_frame_size | 16384 | MAX_FRAME_SIZE advertised to clients (bytes) | bytes per DATA frame | raise for larger frames | more frames per message | larger per-frame buffers | bounded by the HTTP/2 spec range |
| max_header_scratch | 4096 | HPACK decode scratch per stream | per-stream buffer, pooled by concurrency | raise for large header sets | large header blocks rejected | more memory per concurrent stream | too low rejects valid headers |
| max_body | 16384 | max request body buffered per stream (bytes), larger is truncated | per-stream buffer, pooled by concurrency | raise for larger messages | messages over this are truncated | more memory per concurrent stream | over-large wastes pool memory at peak concurrency |
| handler_timeout_ms | 0 | global handler timeout cap in ms, 0 = disabled | cooperative deadline | set to bound slow handlers | handlers cut sooner | slow handlers run longer | Route.timeout_ms and the grpc-timeout header tighten it further |
| compress | false | gzip DATA-frame compression for clients advertising grpc-accept-encoding: gzip | CPU vs message size | enable over a network | | | pure CPU cost on loopback |
| response_cache | false | enable the per-worker unary response cache | cache memory | enable for hot unary responses | | | off makes the cache API a plain send |
| cache_max_entries | 256 | cache slot count (power of two) | per-worker memory | raise for more keys | more misses | more memory | times the worker count |
| cache_max_value_bytes | 16384 | per-slot response-message cap | per-slot memory | raise for larger cached messages | large messages bypass the cache | more memory | keep lean |
| cache_ttl_ms | 1000 | default cache freshness in ms | hit rate vs staleness | raise for hit rate, lower for freshness | sooner expiry, more misses | staler data | too high serves stale data |
| cache_max_total_bytes | 0 | per-worker cache memory ceiling, 0 = none | caps cache memory | set to bound cache RAM | entry count reduced to fit | full entries * value_bytes | 0 disables the ceiling |
| tls | null | TLS context for gRPC over TLS (ALPN h2), null = h2c | enables TLS | attach a context with ALPN h2 | | | gRPC runs on HTTP/2, needs ALPN h2 over TLS |
| tls_port | 0 | companion gRPC-over-TLS bind port for the dual listener (ADR-060) | one worker fleet serves h2c + TLS | set with tls to serve both from one server | 0 keeps single-listener behavior | | requires tls set, must differ from port |
| logger | null | optional logger, lifecycle plus per-rpc | | attach for logging | | | |

## HTTP (convenience engine, `HttpServerConfig`)

The batteries-included path. Same compression and cache field set as HTTP/1, plus arena and header-tier knobs.

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is not validated: binds a kernel-chosen ephemeral port |
| dispatch_model | required | concurrency model | picks the strategy | `.EPOLL`/`.URING` on Linux for scale | | | off Linux only `.ASYNC` runs |
| kernel_backlog | 1024 | TCP listen backlog | kernel accept queue | raise under storms | dropped connections | more kernel memory | too low drops connections |
| workers | 0 | accept thread count, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores | context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the .EPOLL/.URING handler threads | per-thread RSS (demand-paged) | raise for deep handlers or large stack locals, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| worker_stack_compress_bytes | 2097152 | worker stack when compression is on, applied as a floor: effective stack is max(worker_stack_size_bytes, this) | per-thread RSS under .EPOLL/.URING with compression | raise if a compressing handler needs more | flate (about 230 KB on the handler frame) can overflow a small stack | wasted RSS per worker | no effect when compression is off |
| busy_poll_us | 50 | SO_BUSY_POLL spin window in microseconds for accepted connections (.EPOLL) | hot, kernel busy-spins before sleeping the worker | raise to cut tail latency under load, 0 to save idle CPU | shorter spin, more idle-sleep wakeups, higher tail latency | cores spin at 100% when idle | no-op without kernel SO_BUSY_POLL support |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): a new connection goes to listener index = receiving CPU mod workers instead of the 4-tuple hash | connection placement (per SYN, zero hot-path cost) | enable on multi-core hosts so a connection is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| max_recv_buf | 6144 | read buffer per request, over-size requests get 431 | per-conn memory and max request size | raise for large requests | requests rejected with 431 | more memory per connection | too low rejects valid requests |
| large_body_rcvbuf | 0 | SO_RCVBUF applied only while reading a large request body (uploads), 0 leaves the kernel default | upload ingest speed and per-conn memory while a large body is in flight | raise for faster upload ingestion | uploads ingest slower (narrow kernel-default window) | more memory during a large body (256 KiB targets about 256 MiB resident at 256c) | only the upload path touches it, small-request handlers are unaffected |
| body_read_timeout_ms | 30000 | max ms Request.body() waits for the next segment of a multi-segment body on the non-blocking .EPOLL / .URING fd | upload path only, bounds a stalled client | lower to drop stalled uploaders sooner | uploads from slow clients cut sooner | a stalled client holds the worker longer | the hot GET path has no body and never waits here |
| max_request_body | 8388608 | largest request body body() takes, counted from what actually arrives: a declared length past it is refused with 413 before the allocation, a chunked body stops at the byte that crosses it (413) | bounds the per-request body allocation and socket time | lower to bound uploads, 0 to trust the declared length | legitimate large uploads refused with 413 | bigger per-request allocations possible | 0 removes the Content-Length check only, a chunked body keeps an internal ceiling either way |
| uring_send_buf_size | 16384 | per-connection send buffer for the .URING dispatch model (max_recv_buf covers recv) | per-conn memory under .URING | raise for larger responses, lower to shrink per-conn memory | more buffer growth on big responses | more memory per connection | no effect under other dispatch models |
| uring_idle_pool_floor | 8 | warm idle-connection pool floor per worker under .URING | warm-pool memory vs allocator hits on new connections | raise to keep more connections warm for bursty churn, lower to shrink idle memory | more allocator hits after a quiet spell | more idle connections kept resident | no effect under other dispatch models |
| uring_idle_pool_ceiling | 256 | absolute warm idle-pool ceiling per worker under .URING (ADR-062) | resident memory at high connection counts | raise to keep more warm for reconnect, lower to shrink the resident set | more allocator hits on reconnect | more closed connections kept resident | clamps between floor and ceiling like zix.Http1 |
| process_queue_len | 0 (off) | per-worker FIFO ring (.URING) that parks a recv or send re-arm when the submission queue is full and retries it next loop pass instead of closing the connection, 0 disables the feature | per-worker slab, references only (fd + generation), engages only when the SQ fills under a burst | size to about peak concurrent connections per worker so an SQ-full burst parks instead of dropping connections | ring fills sooner under a burst, the newest entry is rejected and that connection falls back to close | more reserved slab per worker (entry count times a few bytes) | no effect under other dispatch models, mirrors zix.Http1 |
| max_allocator_size | 4096 | initial arena capacity per connection, grows if exceeded | per-conn memory, reallocation | raise to avoid early arena growth | more arena growth events | more idle memory per connection | grows automatically anyway |
| max_request_headers | `.LARGE` | max request headers, over-tier rejected with 431 | parse storage | raise the tier for header-heavy clients | header-heavy requests rejected | more parse storage | custom values above 64 are capped at 64 |
| max_response_headers | `.MINIMAL` (16) | max custom response headers, arena-allocated to this size | per-response memory | raise the tier for many custom headers | extra headers cannot be set | more per-response memory | sized exactly per request |
| conn_timeout_ms | 0 | connection lifetime guard in ms, 0 = disabled | background timer eviction | set to evict long-lived connections | connections cut sooner | longer-lived connections | should be >= handler_timeout_ms |
| handler_timeout_ms | 0 | per-handler budget in ms, 0 = disabled | cooperative deadline | set to bound slow handlers | handlers cut sooner | slow handlers run longer | handlers must check ctx.isExpired() |
| send_date_header | true | include the Date header in every response (RFC 7231, ADR-062) | 37 bytes per response | leave on for compliance, off to shrink responses | | | off drops a standard header |
| public_dir | "" | root directory for static file serving, empty disables it | disk I/O on static hits | set to serve static files | | | empty disables static serving |
| public_dir_upload | "u" | upload subdirectory under public_dir for multipart uploads | | set the upload path | | | relative to public_dir |
| public_dir_cache_ttl_ms | 0 | how long a resolved static file stays cached in ms, 0 = never cached (ADR-064) | one open descriptor per cached variant instead of an open plus a stat per request | set above 0 to keep static files open and their 200 header prerendered | every request re-opens and re-reads the file | a file edited on disk takes up to one window to appear | shares the process table with the other engines |
| public_dir_cache_max_entries | 256 | static cache slot count, one slot per file plus its .br and .gz siblings | descriptors and a demand-paged slot table | raise for a larger public_dir | files past the table serve uncached | more descriptors held | rounded down to a power of two, clamped against the process descriptor budget |
| compress | false | enable gzip/deflate/brotli with Accept-Encoding | CPU vs body size | enable over a network | | | pure CPU cost on loopback |
| compression_min_size | 256 | min body size before compression | per-response check | raise to skip small bodies | small bodies compressed | larger bodies skip compression | too low wastes CPU |
| compression_max_out | 262144 | max compressed output bytes | per-response cap | raise for larger bodies | larger bodies uncompressed | more CPU before bailing | over this is sent uncompressed |
| response_cache | false | enable the per-worker response cache | cache memory | enable for hot responses | | | off makes the cache API a plain send |
| cache_max_entries | 256 | cache slot count (power of two) | per-worker memory | raise for more keys | more misses | more memory | times the worker count |
| cache_max_value_bytes | 16384 | per-slot response cap | per-slot memory | raise for larger cached responses | large responses bypass the cache | more memory | keep lean |
| cache_ttl_ms | 1000 | default cache freshness in ms | hit rate vs staleness | raise for hit rate, lower for freshness | sooner expiry, more misses | staler data | too high serves stale data |
| cache_max_total_bytes | 0 | per-worker cache memory ceiling, 0 = none | caps cache memory | set to bound cache RAM | entry count reduced to fit | full entries * value_bytes | 0 disables the ceiling |
| tls | null | TLS context for https (opt-in, ADR-053), null = cleartext | enables TLS, a separate perf band | attach a context to serve https | | | null serves cleartext |
| tls_port | 0 | companion https bind port for the dual listener (ADR-060) | one worker fleet serves cleartext + TLS | set with tls to serve both from one server | 0 keeps single-listener behavior | | requires tls set, must differ from port |
| logger | null | optional logger, engine writes one [component:access] record per response | | attach for access logging | | | injects ctx.logger for handlers |

## TCP (`TcpServerConfig`)

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is rejected |
| dispatch_model | required | concurrency model | picks the strategy | `.EPOLL`/`.URING` on Linux for scale | | | off Linux only `.ASYNC` runs |
| kernel_backlog | 4096 | TCP listen backlog | kernel accept queue | raise under storms | dropped connections | more kernel memory | too low drops connections |
| workers | 0 | accept thread count, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores | context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the .EPOLL/.URING handler threads | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): a new connection goes to listener index = receiving CPU mod workers instead of the 4-tuple hash | connection placement (per SYN, zero hot-path cost) | enable on multi-core hosts so a connection is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| max_recv_buf | 4096 | max payload bytes per frame, over-size closes the connection | per-conn memory and max frame | raise for larger frames | large frames close the connection | more memory per connection | too low closes valid large frames |
| uring_send_buf_size | 65536 | per-connection send buffer for the .URING framed model (max_recv_buf covers recv) | per-conn memory under .URING | raise for larger frames, lower to shrink per-conn memory | more buffer growth on big frames | more memory per connection | no effect under other dispatch models |
| uring_max_conns_per_worker | 65536 | max concurrent connections one .URING worker tracks (fd-indexed slab) | per-worker slab, demand-paged | raise for very high concurrency, lower to shrink the slab | connections rejected past the cap | larger upfront slab (demand-paged) | only the .URING model |
| recv_timeout_ms | 0 | socket receive timeout per connection (SO_RCVTIMEO), 0 = disabled | blocks recv past this | set to drop stalled peers | peers dropped sooner | slow peers tolerated longer | 0 waits indefinitely |
| send_timeout_ms | 0 | socket send timeout per connection (SO_SNDTIMEO), 0 = disabled | blocks send past this | set to drop slow consumers | consumers dropped sooner | slow consumers tolerated longer | 0 waits indefinitely |
| logger | null | optional logger, lifecycle plus per-connection close | | attach for logging | | | |

## UDP (`UdpServerConfig`)

The typed messaging path runs a single async receive loop. The batch and worker knobs apply to the raw-bytes path (`zix.Udp.Raw`, ADR-049).

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| allocator | required | backing allocator, must be general-purpose | | | | | ArenaAllocator leaks broadcast snapshots |
| ip | required | bind address | | | | | |
| port | required | bind port, must be non-zero | | | | | zero rejected at init |
| allow_args | false | when true, init reads `--ip` / `--port` from the args it is passed | startup only | set true to override ip and port at runtime | | | args are ignored when false |
| dispatch_model | required | concurrency for the raw path, EPOLL/URING run per-core workers | picks the strategy | `.EPOLL`/`.URING` for the raw path at scale | | | typed path folds a non-ASYNC model to a single loop |
| workers | 0 | worker count for per-core models, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores | context-switching | only for EPOLL/URING |
| worker_stack_size_bytes | 524288 | worker thread stack for the per-core raw workers (.EPOLL / .URING) | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| busy_poll_us | 0 | SO_BUSY_POLL spin window in microseconds for the per-core raw worker socket (.EPOLL / .URING) | recvmmsg wake-up latency | set to e.g. 50 to cut wake-up latency under load | shorter spin, more idle-sleep wakeups | cores spin when idle | 0 leaves it unset, no-op without kernel SO_BUSY_POLL support |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): socket index = receiving CPU mod workers per packet instead of the 4-tuple hash | packet placement (in-kernel, zero hot-path cost) | enable on multi-core hosts so a datagram is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| reuse_address | false | set SO_REUSEADDR + SO_REUSEPORT for multi-worker binding | enables kernel load-balancing | enable for per-core workers | | | required for multi-worker port sharing |
| recv_batch | 32 | datagrams received per recvmmsg syscall (raw path) | syscalls per batch | raise to cut syscalls under load | more syscalls per datagram | larger batch buffers | too low loses batching benefit |
| send_batch | 32 | replies coalesced per sendmmsg flush (raw path) | syscalls per flush | raise to cut syscalls under load | more flush syscalls | larger batch buffers | too low loses batching benefit |
| max_recv_buf | 1500 | max datagram size, receive buffer per slot (raw path) | per-slot memory | match to path MTU | larger datagrams truncated | more per-slot memory | 1500 is the common Ethernet MTU |
| gso_enabled | false | UDP GSO (UDP_SEGMENT): coalesce consecutive same-destination replies into one sendmsg per group | send-path syscalls | enable when replies burst to one peer (multi-packet flights) | | fewer send syscalls, lower CPU | probed at startup, off on kernels older than 4.18, helps only multi-packet same-peer batches |
| endianness | `.LITTLE` | wire endianness contract with clients (the typed server relays raw bytes without decoding, the client applies it on every send and receive) | client-side per-packet conversion | `.LITTLE` for cross-language clients, `.BIG` for network order | | | must match across clients and server |
| conn_timeout_ms | 5000 | ms of silence before a client is considered disconnected | liveness tracking | lower for faster disconnect detection | clients dropped sooner | dead clients linger | too low drops slow but live clients |
| poll_timeout_ms | 2000 | receive poll interval in ms, sets disconnect check frequency | wakeup frequency | lower for more responsive checks | more frequent wakeups | slower disconnect detection | trades CPU for responsiveness |
| auto_ack | false | send a 0x06 ACK byte on successful receipt | one extra send per packet | enable for at-least-once feedback | | | adds reply traffic |
| error_report | false | send a 0x15 NACK byte on a malformed or oversized packet | one extra send on error | enable for error feedback | | | adds reply traffic |
| auto_echo | false | echo the received packet back as-is | one extra send per packet | enable for echo behavior | | | adds reply traffic |
| broadcast | false | relay the received packet to all connected clients | a send per connected client | enable for fan-out | | | per-packet cost scales with client count |
| logger | null | optional logger, lifecycle plus per-datagram | | attach for logging | | | |

## HTTP/3 (`Http3ServerConfig`)

QUIC over UDP. Requires a TLS 1.3 context (no cleartext mode).

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| allocator | required | backing allocator, general-purpose | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is rejected |
| dispatch_model | required | concurrency: .EPOLL is an epoll readiness loop, .URING an io_uring completion loop, each one SO_REUSEPORT worker per core | picks the strategy | `.EPOLL`/`.URING` for multicore scale | | | ASYNC runs a single worker with CID demux, EPOLL/URING run one per core. .URING folds to .EPOLL when io_uring is unavailable |
| workers | 0 | worker count for per-core models, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores | context-switching | only for EPOLL/URING |
| worker_stack_size_bytes | 524288 | worker thread stack for the per-core workers (.EPOLL / .URING) | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| busy_poll_us | 0 | SO_BUSY_POLL spin window in microseconds for the per-core worker socket (.EPOLL / .URING) | recvmmsg wake-up latency | set to e.g. 50 to cut wake-up latency under load | shorter spin, more idle-sleep wakeups | cores spin when idle | 0 leaves it unset, no-op without kernel SO_BUSY_POLL support |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): socket index = receiving CPU mod workers per packet instead of the 4-tuple hash | packet placement (in-kernel) | leave false on the QUIC path | | | per-packet CPU steering breaks QUIC flow affinity (a flow's packets land on different workers and miss the connection state), measured as a throughput collapse. No-op when the kernel lacks the option (pre-4.5) |
| recv_batch | 32 | datagrams received per recvmmsg syscall | syscalls per batch | raise to cut syscalls | more syscalls | larger buffers | too low loses batching |
| send_batch | 32 | packets coalesced per sendmmsg flush | syscalls per flush | raise to cut syscalls | more flushes | larger buffers | too low loses batching |
| max_recv_buf | 1500 | max datagram size, receive buffer per slot | per-slot memory | match to path MTU | datagrams truncated | more memory | 1500 is the common Ethernet MTU |
| socket_rcvbuf | 4194304 | requested SO_RCVBUF per per-core UDP socket, holds the burst arriving between recvmmsg batches | packet loss on a syscall-bound run (loss becomes retransmits) | leave high, lower only to trim memory on a tiny deployment | more dropped datagrams under burst, more retransmits | more kernel socket memory per worker | capped at net.core.rmem_max (and doubled internally), 0 leaves the kernel default |
| socket_sndbuf | 4194304 | requested SO_SNDBUF per per-core UDP socket, so a coalesced GSO send flight is not throttled | send throttling under a large flight | leave high, lower only to trim memory | a large send flight stalls on a small buffer | more kernel socket memory per worker | capped at net.core.wmem_max, 0 leaves the kernel default |
| gso_enabled | true | UDP GSO (UDP_SEGMENT): coalesce a multi-packet response flight to one peer into one sendmsg | send-path syscalls, hot | leave on, disable only to A/B or on a constrained kernel | | fewer send syscalls, lower CPU and higher throughput | probed at startup, falls back to plain sendmmsg on kernels older than 4.18 |
| cid_len | 8 | server-issued connection ID length in bytes (RFC 9000) | per-packet CID handling | leave at 8, fixed length enables per-core steering | shorter, fewer distinct CIDs | longer CID overhead per packet | enables future per-core CID steering |
| max_idle_ms | 30000 | connection idle timeout in ms (RFC 9000 10.1) | liveness | lower for faster reclaim of idle connections | idle connections closed sooner | idle connections linger | too low closes slow but live connections |
| max_streams | 128 | max concurrent request streams (RFC 9000 4.6) | per-conn stream state | raise for highly multiplexed clients | clients blocked sooner | more per-conn state | too low serializes a multiplexed client |
| max_datagram_size | 1200 | wire size targeted for a 1-RTT response datagram, effective size is min(this, client max_udp_payload_size, 16 KiB ceiling) | packet sizing and cwnd, hot | raise (e.g. 8192) only where path MTU is known large (loopback, jumbo LAN): fewer packets per response, so less per-packet header/AEAD/ack work (the static-h3 wall) | smaller packets, more per-packet work | fewer packets, less per-packet work, but a value above the real path MTU fragments on a WAN | never over-sends past the client's advertised limit, also the initial cwnd basis, 1200 is the QUIC minimum |
| max_stream_chunk | 0 (derive) | explicit cap on STREAM-frame payload bytes per 1-RTT packet, 0 derives it from the datagram size | bytes per packet, hot | leave 0 so raising max_datagram_size widens packets automatically | a small non-zero value forces more packets per response | a large non-zero value approaches the datagram size | 0 means datagram size minus the frame and tag room |
| max_inflight_packets | 128 | response packets in flight per connection before waiting for acks (congestion-window ceiling and loss-detection ring depth) | multi-packet response throughput, hot | raise for higher per-connection throughput on large responses | smaller send bursts, gentler on a constrained client receive buffer, lower per-conn throughput | bigger window, a large response streams in fewer ACK-clocked rounds, more send bookkeeping | clamped to the compile-time ring capacity (128 packets, connection.zig max_sent_ranges), raising past it needs that bumped and a rebuild |
| initial_window_packets | 32 | initial congestion window in packets, how much of a response goes out before the first ack (RFC 9002 7.2) | first-flight latency, hot | raise on a low-loss path so a response needs fewer ACK-clocked rounds | smaller first burst, more rounds for a big response | larger first burst, fewer rounds, risk of loss and bufferbloat on a real lossy network | effective first burst is min of this, max_inflight_packets, and the ring capacity |
| max_pending_request_streams | 16 | request streams one worker assembles at once, only a request the client split across packets takes a slot | worker memory: this * max_request_stream_bytes * 9/8 per worker | raise where many clients upload at once, 0 turns holding off for a server whose routes take no body | a burst of concurrent uploads is answered 503 sooner | more memory held per worker | a request that arrives whole in one packet (every conforming GET) never touches the pool, so this costs the GET path nothing |
| max_request_stream_bytes | 8192 | bytes one assembled request stream may hold, the largest request body a handler can be given whole | worker memory, see the row above | raise to the largest upload the routes accept | a body past it is delivered cut, bodyComplete() false | more memory held per worker | raised to 1024 when set smaller, a cut body still reports what really arrived through bodyReceived() |
| public_dir | "" | root directory for static file serving, empty disables it (ADR-064) | one snapshot in memory per served file | set to serve static files for routes that match no handler | | | whole-file 200 only, Range is not served over HTTP/3, and it does nothing unless public_dir_cache_ttl_ms is set |
| public_dir_cache_ttl_ms | 0 | how long a resolved static file stays cached in ms, 0 = static serving OFF on this engine | holds each served file in memory | set above 0 to enable static serving at all | | a file edited on disk takes up to one window to appear | UNLIKE the other engines, 0 disables static serving entirely: an HTTP/3 response body outlives its handler, so a file can only be served out of the cache |
| public_dir_cache_max_entries | 256 | static cache slot count, one slot per file plus its .br and .gz siblings | descriptors, plus a snapshot per file this engine serves | raise for a larger public_dir | files past the table are not served here | more memory held | rounded down to a power of two, clamped against the process descriptor budget, and each snapshot is capped at 8 MiB |
| tls | null (required) | TLS 1.3 context: cert, key, ALPN, QUIC needs TLS 1.3 | enables QUIC | attach a TLS 1.3 context | | | null is rejected, QUIC has no cleartext mode |
| logger | null | optional logger for lifecycle lines | | attach for logging | | | |

## WebRTC (`WebrtcServerConfig`)

ICE-lite, DTLS 1.2, SCTP data channels, optional SRTP media forwarding, all on one UDP port. Requires a TLS context whose key is ECDSA P-256 (no cleartext mode).

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| allocator | required | backing allocator, general-purpose | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is rejected at run() |
| dispatch_model | required | concurrency: .ASYNC is one portable worker, .EPOLL and .URING are one SO_REUSEPORT worker per core | picks the strategy | `.EPOLL`/`.URING` on Linux for multicore scale | | | off Linux only `.ASYNC` runs. There is no CPU steering knob: a peer is its 4-tuple and steering would split a session |
| workers | 0 | worker count for the per-core models, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores used | context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the per-core workers | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | ignored by `.ASYNC` |
| max_recv_buf | 1500 | max datagram size, receive buffer per slot | per-slot memory | match to path MTU | datagrams truncated | more memory | 1500 is the common Ethernet MTU |
| socket_rcvbuf | 1048576 | requested SO_RCVBUF in bytes | dropped datagrams under burst | leave high, lower only to trim memory | more loss under burst | more kernel socket memory | 0 keeps the kernel default |
| socket_sndbuf | 1048576 | requested SO_SNDBUF in bytes | send throttling under a large flight | leave high, lower only to trim memory | a flight stalls on a small buffer | more kernel socket memory | 0 keeps the kernel default |
| ice_ufrag | "" (required) | this agent's ufrag, the first half of the USERNAME every check carries | | set it, or publish the same value in the SDP answer | | | empty is rejected at run() |
| ice_password | "" (required) | this agent's password, the key every check is verified against | | set it, or publish the same value in the SDP answer | | | empty is rejected at run(), and it is the only real gate |
| peer_ice_ufrag | "" | the peer's ufrag, the second half of that USERNAME | | set when signalling has told you the peer's ufrag | | | empty means checks are refused with 401 until it is known. Ignored when accept_any_peer_ice_ufrag is set |
| accept_any_peer_ice_ufrag | false | take a check whatever the peer calls itself, leaving ice_password as the only gate | | set to true for any browser client | | | a browser draws a fresh ufrag per peer connection, so without this every check is refused. Off by default so a server that names one peer keeps refusing everybody else |
| tls | null (required) | TLS context: the certificate and the key that signs the ServerKeyExchange | enables DTLS | attach a context whose key is ECDSA P-256 | | | null is rejected at run(), and so is a key that is not ECDSA P-256 (the one DTLS 1.2 suite here is ECDHE-ECDSA, RFC 5289) |
| max_handshake_fragment | 1024 | largest handshake fragment body this server emits | records per flight | lower if the path MTU is small | more fragments per flight | a record may exceed the path MTU and be dropped | sized so a record fits the path MTU |
| carry_media | false | whether this server forwards audio and video between its peers | enables the SRTP path and its buffers | set to true for a forwarding server | | media buffers are allocated per peer | off means no keys are exported and RTP is dropped where it is routed. The SDP answer has its own separate switch, set both |
| path_max_bytes | 1200 | largest SCTP packet that fits the path, DTLS overhead already taken off | fragments per message | raise only where the path MTU is known large | more fragments per message | packets may exceed the path MTU | 1200 matches the conservative WebRTC default |
| outbound_streams | 128 | how many outbound streams the association asks for | per-association state | raise for many concurrent channels | fewer channels available | more per-association state | negotiated down to what the peer offers |
| inbound_streams | 128 | how many inbound streams the association accepts | per-association state | raise for many concurrent channels | peer limited sooner | more per-association state | |
| max_channels | 64 | how many channels one peer may have open at once, counted from both sides | per-peer registry | raise for channel-heavy peers | opens refused sooner | more per-peer memory | |
| max_peers | 64 | how many peers one worker holds at once | per-worker memory | raise for a bigger room | new peers dropped sooner | more memory per worker | counted PER WORKER, so N workers hold up to N * max_peers. A datagram from a new peer past the ceiling is dropped, which reads to that peer as an unanswered check |
| peer_idle_ms | 30000 | how long a peer may go without a datagram before it is dropped | reclaim speed | lower for faster reclaim | live but quiet peers dropped | dead peers linger | covers a browser closing its tab without a graceful shutdown |
| tick_interval_ms | 250 | how often the engine looks at its peers when no datagram is arriving | idle CPU, and the floor on retransmit lateness | lower for tighter timers, raise to quiet an idle server | more wakeups on an idle server | a retransmit or an idle drop can be this late | the wait is deadline-derived and capped by this, so it is also the cost of a fully silent server |
| logger | null | optional logger for lifecycle lines | | attach for logging | | | the engine is silent without one, which is the wrong default for a browser demo |

## FIX (`FixServerConfig`)

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| ip | required | bind address | | | | | |
| port | required | bind port, non-zero | | | | | zero is rejected |
| comp_id | required | server SenderCompID (tag 49) | | | | | required for the FIX session |
| dispatch_model | required | concurrency model | picks the strategy | `.EPOLL`/`.URING` on Linux for scale | | | off Linux only `.ASYNC` runs |
| kernel_backlog | 1024 | TCP listen backlog | kernel accept queue | raise under storms | dropped connections | more kernel memory | too low drops connections |
| workers | 0 | accept/event-loop workers, 0 = cpu_count | parallelism | leave 0 (auto) | fewer cores | context-switching | ignored by `.ASYNC` |
| worker_stack_size_bytes | 524288 | worker thread stack for the .EPOLL and .URING handler threads | per-thread RSS (demand-paged) | raise for deep handlers, lower to trim RSS | stack overflow in deep handlers | wasted RSS per worker | cost is low until the depth is used |
| reuseport_cbpf | false | SO_ATTACH_REUSEPORT_CBPF steering (.EPOLL / .URING): a new connection goes to listener index = receiving CPU mod workers instead of the 4-tuple hash | connection placement (per SYN, zero hot-path cost) | enable on multi-core hosts so a connection is served on the core that received it | | | no-op when the kernel lacks the option (pre-4.5) |
| uring_send_buf_size | 65536 | per-connection send buffer for the .URING dispatch model | per-conn memory under .URING | raise for larger replies, lower to shrink per-conn memory | more buffer growth on big replies | more memory per connection | no effect under other dispatch models |
| uring_max_conns_per_worker | 65536 | max concurrent connections one .URING worker tracks (fd-indexed slab) | per-worker slab, demand-paged | raise for very high concurrency, lower to shrink the slab | connections rejected past the cap | larger upfront slab (demand-paged) | only the .URING model |
| default_heartbeat_secs | 30 | default HeartBtInt (seconds) echoed in the Logon response when the client omits tag 108 | not perf, session liveness | raise to reduce heartbeat traffic, lower for faster dead-peer detection | more heartbeat messages | slower dead-session detection | only used when the client omits tag 108 |
| heartbeat_timeout_ms | 0 | ms before sending TestRequest, then Logout on no reply, 0 = disabled | session liveness | lower for faster dead-session detection | more heartbeat traffic, faster detection | slower to detect dead sessions | only takes effect after Logon |
| conn_timeout_ms | 0 | idle close in ms when heartbeat is off, 0 = disabled | session liveness | set when not using heartbeats | connections closed sooner | idle sessions linger | no TestRequest is sent before closing |
| handler_timeout_ms | 0 | per-message handler budget in ms, 0 = disabled | cooperative deadline | set to bound slow handlers | handlers cut sooner | slow handlers run longer | per-route Route.timeout_ms overrides this |
| logger | null | optional logger, lifecycle plus per-message session() | | attach for logging | | | |

## UDS (`UdsServerConfig`)

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | required | std.Io backend | | | | | |
| allocator | required | backing allocator | | | | | |
| path | required | filesystem path for the socket file (max 107 bytes) | | | | | unlinked before bind and at exit |
| kernel_backlog | 128 | listen backlog before accept() | kernel accept queue | raise under storms | dropped connections | more kernel memory | too low drops connections |
| max_recv_buf | 4096 | max payload bytes per frame, over-size closes the connection | per-conn memory and max frame | raise for larger frames | large frames close the connection | more memory per connection | too low closes valid large frames |
| recv_timeout_ms | 0 | socket receive timeout (SO_RCVTIMEO), 0 = disabled | blocks recv past this | set to drop stalled peers | peers dropped sooner | slow peers tolerated | 0 waits indefinitely |
| send_timeout_ms | 0 | socket send timeout (SO_SNDTIMEO), 0 = disabled | blocks send past this | set to drop slow consumers | consumers dropped sooner | slow consumers tolerated | 0 waits indefinitely |
| logger | null | optional logger for lifecycle lines | | attach for logging | | | |

## TLS context (`Tls.Context.Config`)

Server-side TLS policy, validated once at init. Attach the built `Tls.Context` by pointer to an engine's `tls` field. Omitting the optional fields yields the secure default (forward secrecy, AEAD, ECDHE-only).

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| cert_path | required | PEM path to the end-entity certificate (ECDSA P-256, Ed25519, or RSA) | startup load | | | | required |
| key_path | required | PEM path to the private key matching cert_path | startup load | | | | required, must match the cert |
| alpn | empty | ALPN protocols offered, in server-preference order | handshake | set `.{ .HTTP_1_1 }` for Http1, `.{ .H2 }` for Http2 | | | browsers need ALPN h2 for HTTP/2 over TLS |
| min_version | `.TLS_1_2` | version floor, valid range TLS 1.2 to 1.3 | handshake compatibility | raise to `.TLS_1_3` to require 1.3 | | | 1.0/1.1 are never offered (RFC 8996) |
| max_version | `.TLS_1_3` | version ceiling | handshake | lower only for legacy interop | | | a 1.2 ceiling rejects 1.3 |
| curves | default ECDHE set | ECDHE curves in preference order | handshake key exchange | reorder for client compatibility | | | an unsupported value (P384, MLKEM768) is rejected at init |
| ciphers | default AEAD set | AEAD cipher suites in preference order, 1.3 and 1.2 | handshake | reorder for client compatibility | | | an unsupported value (AES_256, CHACHA20, any RSA suite) is rejected at init |
| prefer_server_ciphers | true | honor server cipher order over the client's | handshake selection | leave on for predictable selection | | | with the single-suite set the choice is identical either way |
| hsts_max_age_s | 0 | HSTS max-age in seconds (RFC 6797), 0 = off | one response header | set to enable Strict-Transport-Security | | | a long value pins clients to https |

## Logger (`Logger.Config`)

Build one Logger with this config and attach it by pointer to any engine's `logger` field. Most of the Logger's sizing is compile-time. The one runtime knob is the file write-buffer.

| field | default | controls | perf impact | how to tweak | if lower | if higher | knob consequence |
| :- | :- | :- | :- | :- | :- | :- | :- |
| console | `.OFF` | console output mode | | set to enable console output | | | |
| console_min_level | `.INFO` | minimum level for console output | | raise to quiet the console | | | |
| console_fd | `null` | descriptor console records go to, null means stderr | | set to send console output somewhere else | | | the caller owns the descriptor and must keep it open for the logger's whole life |
| save_path | "" | directory for log files, empty disables file logging | disk I/O when set | set to enable file logging | | | the directory must already exist |
| save_file | "log" | base name for log files | | set the file base name | | | |
| save_min_level | `.INFO` | minimum level for file output | | raise to log fewer lines to file | | | |
| max_lines | 1000000 | lines per file before rotating to the next sequence number | rotation frequency | raise for fewer, larger files | more frequent rotation | larger files | |
| write_buf_size | 65536 | file write-buffer size in bytes, batches log lines per write() to disk | log write() batching | raise to cut disk syscalls, lower to bound memory | more frequent flushes | larger buffered loss window on crash | minor |

## Notes

- Required fields (`io`, `ip`, `port`, `allocator`, `path`, `comp_id`, `cert_path`, `key_path`, `ice_ufrag`, `ice_password`) have no default and must be set. A zero `port` is rejected at init by `zix.Tcp` / `zix.Udp` / `zix.Fix` (and their clients), and at `run()` by `zix.Http2` / `zix.Grpc` / `zix.Http3` / `zix.Webrtc`. `zix.Http1` and `zix.Http` do not validate it (port 0 binds a kernel-chosen ephemeral port).
- `io`, `logger`, and `tls` are caller-owned: they are passed by handle or pointer and must outlive the server.
- `.EPOLL` and `.URING` are Linux-only. Off Linux `run()` returns `error.ZixDispatchModelUnsupported`, so pick `.ASYNC` there. The TLS paths follow the model: `.EPOLL` / `.URING` terminate in the multiplexed tls_mux workers, `.ASYNC` in tls_serve.
- The compression and response-cache features are active only under `.EPOLL` and `.URING` (shared-nothing, one owner per worker).
