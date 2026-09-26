# localbench: http3-uring

zix.Http3 on the `.URING` dispatch model: one SO_REUSEPORT worker per core on UDP 8443, the kernel load-balancing by 4-tuple. Pure-Zig QUIC on
`std.crypto` (RFC 9000, 9001, 9002, 9114), NewReno with PTO retransmit and
rolling MAX_STREAMS / MAX_DATA credit.

QUIC on UDP 8443. TLS 1.3 rides inside the handshake and ALPN h3 is negotiated
by the engine. There is no cleartext mode, so a missing certificate is fatal
here rather than something to degrade past.

<br>

## What is cached, and what is not

| Route | Per request |
| :- | :- |
| `/baseline2` | the sum computed from the query |
| `/static/*` | engine `public_dir`, 30 s window, see below |

No response cache and nothing pre-serialized at startup.

**The static window is mandatory on this engine.** An HTTP/3 response body
outlives the handler call: a body too large for one packet is parked in a
send-stream slot and read again for every packet, and again for every
retransmission, until the client acknowledges all of it. So the body cannot be
handler memory. It comes from the static cache as mapped bytes with the pin
held past the handler, which means `public_dir_cache_ttl_ms` above zero is
what makes static serving work at all. At zero the router serves no file and
falls through to 404.

That is a protocol constraint, not a caching choice, and it is the one place
localbench holds something past a request on purpose.

<br>

## Profiles

| Profile | Drives |
| :- | :- |
| `baseline-h3` | `/baseline2?a=..&b=..` over QUIC |
| `static-h3` | 20-file mix, br and gzip negotiated |

<br>

## The POST body, and why the handler checks it

`/baseline2` sums the query and the POST body, the same shape as the h1 and h2
baselines, so the three answer the same number for the same request.

The handler asks `req.bodyComplete()` before it reads `req.body`, which the TCP
entries have no reason to do. Over QUIC a request can span packets, and the
engine assembles it in a worker-owned pool sized by
`max_request_stream_bytes`. A body past that size is delivered cut, with
`bodyReceived()` counting what really arrived. Summing a fragment would answer
a wrong number under a 200, so this entry answers 413 instead.

`baseline-h3` drives GET, so none of this is on the measured path: a request
that arrives whole in one packet never touches the pool.

<br>

## Layout

```
http3-uring
|
|___/src
|   |___/handlers
|   |   |___baseline.zig               (the /baseline2 route)
|   |
|   |___/shared
|   |   |___paths.zig                  (fixture and certificate paths)
|   |
|   |___main.zig                       (route table + server config)
|
|___build.zig
|___build.zig.zon
|___meta.json
|___README.md
```

<br>

## Run it

```bash
./scripts/localbench-build.sh http3-uring
./scripts/localbench-validate.sh http3-uring
./scripts/localbench-run.sh http3-uring
```

With a Zig++ toolchain, `ZIX_IO=threadz` runs the server on `std.Io.Threadz`: each
io_uring loop is a task pinned to one Threadz worker, on that worker's ring, rather
than a thread with a ring of its own. A Zig without Threadz ignores the variable.

```bash
ZIG_BIN=<zig++> ./scripts/localbench-build.sh http3-uring
ZIX_IO=threadz ./scripts/localbench-run.sh http3-uring
```

Validation drives QUIC directly with `curl --http3-only`, which refuses to
fall back to TCP, so a pass is HTTP/3 and nothing else.
