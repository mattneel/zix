# localbench: http2-grpc-uring

zix.Grpc over h2c on the `.URING` dispatch model: one SO_REUSEPORT listener plus io_uring completion ring per worker, shared-nothing across cores. Built on zix.Http2,
so h2 streams are multiplexed per connection and replies use comptime-cached
HPACK blocks.

Cleartext h2c on 8080. TLS termination, when wanted, belongs to a proxy in
front.

<br>

## What is cached

Nothing. Both RPCs are a single add and a reply of a few bytes, well under any
cache crossover, so a lookup would cost more than the work it saves.

<br>

## RPCs

| RPC | Shape |
| :- | :- |
| `benchmark.BenchmarkService/GetSum` | unary, `SumRequest{a, b}` to `SumReply{a + b}` |
| `benchmark.BenchmarkService/StreamSum` | server-streaming, `count` replies of `a + b + i` |

`is_server_streaming` on the route is what the engine reads before any handler
runs, to pick sync-inline against task-spawn dispatch. That is why
`Server.init` takes the router TYPE rather than a bare handler pointer: a
unary handler must not pay a task allocation and a header copy per call.

<br>

## Profiles

| Profile | Tool | Drives |
| :- | :- | :- |
| `unary-grpc` | h2load | GetSum, 100 streams in flight |
| `stream-grpc` | ghz | StreamSum |

<br>

## Layout

```
http2-grpc-uring
|
|___/src
|   |___/handlers
|   |   |___getsum.zig                 (the unary RPC)
|   |   |___streamsum.zig              (the server-streaming RPC)
|   |
|   |___/shared
|   |   |___sumrequest.zig             (proto3 decode both RPCs share)
|   |
|   |___main.zig                       (route table + server config)
|
|___build.zig
|___build.zig.zon
|___meta.json
|___README.md
```

`SumRequest` and `StreamRequest` differ only by the trailing count field, so
one reader covers both: a `SumRequest` simply leaves count at its default.

<br>

## Run it

```bash
./scripts/localbench-build.sh http2-grpc-uring
./scripts/localbench-validate.sh http2-grpc-uring
./scripts/localbench-run.sh http2-grpc-uring
```

With a Zig++ toolchain, `ZIX_IO=threadz` runs the server on `std.Io.Threadz`: each
io_uring loop is a task pinned to one Threadz worker, on that worker's ring, rather
than a thread with a ring of its own. A Zig without Threadz ignores the variable.

```bash
ZIG_BIN=<zig++> ./scripts/localbench-build.sh http2-grpc-uring
ZIX_IO=threadz ./scripts/localbench-run.sh http2-grpc-uring
```

Validation drives the service with `grpcurl` against the arena's own
`requests/benchmark.proto`, so it needs `grpcurl` on PATH. The server carries
no reflection service, which is why the schema comes from that file.
