# localbench: http2-uring

zix.Http2 on the `.URING` dispatch model: one SO_REUSEPORT listener plus io_uring completion ring per worker, shared-nothing across cores.

One server, two listeners through `tls_port`: h2c on 8082 and h2 over
TLS 1.3 (ALPN h2) on 8443, from the same worker fleet. No second launch, so no
doubled workers and no doubled fd table.

<br>

## What is cached, and what is not

| Route | Per request |
| :- | :- |
| `/baseline2` | the sum computed from the query and the body |
| `/json/{count}?m=M` | every field serialized from typed dataset values |
| `/static/*` | engine `public_dir`, 30 s window, see below |

No response cache, and nothing is pre-serialized at startup. `handlers/json.zig`
and `shared/dataset.zig` are written around that: the dataset stays typed and
every field is rendered per request, through jzon on `.GENERATED`.

**engine static, 30 s window.** `.br` and `.gz` negotiation only happens when a
cache slot is filled, and the lookup short-circuits at `ttl_ms == 0`. With the
window at zero the engine answers the 204800-byte `app.js` instead of the
47275-byte `app.js.br`, which measures a different thing than the profile asks
for. The window is also the staleness window: a file edited on disk shows up
within it.

<br>

## Profiles

| Profile | Port | Notes |
| :- | :- | :- |
| `baseline-h2` | 8443 | h2 over TLS |
| `static-h2` | 8443 | 20-file mix, br and gzip negotiated |
| `baseline-h2c` | 8082 | prior-knowledge cleartext h2 |
| `json-h2c` | 8082 | 7 fixed (count, m) pairs |

The h2c port answers h2 only. A plain HTTP/1.1 request there is refused rather
than served, so a run labelled h2c cannot quietly be measuring h1.

<br>

## Layout

```
http2-uring
|
|___/src
|   |___/handlers
|   |   |___baseline.zig               (the /baseline2 route)
|   |   |___json.zig                   (the /json route)
|   |
|   |___/shared
|   |   |___dataset.zig                (typed fixture load, jzon)
|   |   |___paths.zig                  (fixture and certificate paths)
|   |   |___response.zig               (400, 404, 503 responders)
|   |
|   |___main.zig                       (route table + server config)
|
|___build.zig
|___build.zig.zon
|___meta.json
|___README.md
```

There is no static handler. `/static` is the engine's `public_dir` fallback,
which the router reaches before writing its 404.

<br>

## Run it

```bash
./scripts/localbench-build.sh http2-uring
./scripts/localbench-validate.sh http2-uring
./scripts/localbench-run.sh http2-uring
```

With a Zig++ toolchain, `ZIX_IO=threadz` runs the server on `std.Io.Threadz`: each
io_uring loop is a task pinned to one Threadz worker, on that worker's ring, rather
than a thread with a ring of its own. A Zig without Threadz ignores the variable.

```bash
ZIG_BIN=<zig++> ./scripts/localbench-build.sh http2-uring
ZIX_IO=threadz ./scripts/localbench-run.sh http2-uring
```
