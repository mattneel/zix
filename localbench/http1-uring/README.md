# localbench: http1-uring

zix.Http1 on the `.URING` dispatch model, serving the HttpArena HTTP/1.1
surface against the HttpArena fixtures, run natively with no containers for
the server itself.

Cleartext on 8080, TLS 1.3 on 8081.

<br>

## What is cached, and what is not

| Route | Per request |
| :- | :- |
| `/json/{count}?m=M` | every field serialized from typed dataset values, gzip compressed from the body just rendered |
| `/baseline11` | the sum computed from the query and the body |
| `/pipeline` | a fixed response, no inputs |
| `/upload` | the body ingested, the counted total answered |
| `/async-db` | a live query on the worker's postgres lane |
| `/static/*` | engine `public_dir`, 30 s window, see below |
| `/crud/items/{id}` | 200 ms row cache, see below |

No response cache anywhere, and nothing is pre-serialized at startup. That was
the review point against the old entry, and it is what `handlers/json.zig` and
`shared/dataset.zig` are written around: the dataset stays typed, and every
field is rendered per request.

Two caches remain. Both are required by the thing they serve.

**crud rows, 200 ms.** That profile IS a cache-aside test: the validator wants
`X-Cache: MISS` on the first read of an id, `HIT` on the second, and `MISS`
again after a write. `shared/crudcache.zig` holds a decoded database row, never
a rendered response, so the status line, headers, and framing are built on
every reply.

**engine static, 30 s window.** `.br` and `.gz` negotiation only happens when a
cache slot is filled (`src/utils/static_cache.zig:662`), and the lookup
short-circuits at `ttl_ms == 0` (`:312`). With the window at zero the engine
answers the 204800-byte `app.js` instead of the 47275-byte `app.js.br`, which
measures a different thing than the profile asks for. For comparison, the old
entry's `handlers/static.zig` cached static far harder: a permanent open
descriptor plus a prerendered header per name, with no TTL and no eviction.

<br>

## One thing the engine cannot express

### Upload holds only what fits the receive buffer

`/upload` answers `req.bodyReceived()`, which the engine counts from the reads
that actually received the bytes. The `Content-Length` header value is never
used, so a lying header cannot inflate it, and `max_request_body` is raised to
24 MB so the profile's 20 MB template is ingested rather than refused with 413
before it is read.

The delivered bytes are copied into the worker's own sink first, so the server
really takes the upload into memory. Bytes beyond the connection receive buffer
are drained and counted by the engine itself: `zix.Http1` exposes no streaming
body sink, and `req.body()` returns only what fit the buffer
(`src/tcp/http1/request.zig:102`). Holding all 20 MB would need a receive
buffer that large on every connection, which at this profile's 256 connections
costs more memory than the rest of the entry put together.

<br>

## Layout

```
http1-uring
|
|___/src
|   |___main.zig                (route table, server config, startup)
|   |
|   |___/handlers
|   |   |___asyncdb.zig         (GET /async-db)
|   |   |___baseline.zig        (GET|POST /baseline11)
|   |   |___crud.zig            (/crud/items)
|   |   |___json.zig            (GET /json/{count})
|   |   |___pipeline.zig        (GET /pipeline)
|   |   |___upload.zig          (POST /upload)
|   |
|   |___/shared
|       |___crudcache.zig       (200 ms row cache, crud only)
|       |___dataset.zig         (typed fixture load, no pre-render)
|       |___dbpg.zig            (postgres lanes)
|       |___response.zig        (400 / 404 / 503)
|       |___util.zig            (byte appenders, JSON escaping)
|
|___build.zig
|___build.zig.zon               (.zix = .{ .path = "../.." })
|___meta.json                   (subscribed profiles)
|___README.md
```

`/static` has no handler: the engine serves it from `public_dir`.

<br>

## Running it

Every path comes from the environment and none has a default, so the run script
is the single source of truth for where fixtures and certificates live. A
missing variable names itself and exits non-zero rather than guessing a path
that would resolve against whatever directory the process started in.

| Variable | Required | Meaning |
| :- | :- | :- |
| `ZIX_DATA_DIR` | yes | HttpArena `data/` directory. `dataset.json` is read from it, `/static/*` resolves under it |
| `ZIX_TLS_CERT` | yes | certificate for the 8081 listener |
| `ZIX_TLS_KEY` | yes | its private key |
| `DATABASE_URL` | no | absent leaves `/async-db` and `/crud` answering 503 and opens no connection |
| `DATABASE_MAX_CONN` | no | total connections across workers, otherwise derived from the CPU count |
| `ZIX_IO` | no | `threadz` runs the server on Zig++'s `std.Io.Threadz`, each io_uring loop a task pinned to one Threadz worker, on that worker's ring. A Zig without Threadz ignores it |

`scripts/localbench-run.sh` sets all of these. Starting the binary by hand
means setting them by hand.

<br>

## Database plane

Each engine worker owns a lane: one or more pipelined postgres connections that
the worker itself pumps, so a reply decodes, renders, and writes on the core
that owns the client socket. Statements are prepared once per connection, so a
request sends only Bind plus Execute.

Under `.URING` the lane's connection descriptors are armed on the worker's own
ring, so a reply arrives as an ordinary completion and the request path never
blocks. The `.EPOLL` and `.ASYNC` entries have no such watch and wait on their
own reply instead, which is why the same query reads slower there.
