# localbench: http1-ws-uring

zix.Http1 WebSocket on the `.URING` dispatch model: one SO_REUSEPORT listener plus io_uring completion ring per worker, shared-nothing across cores.

Cleartext on 8080. `GET /ws` upgrades, then the engine drives the echo loop.

<br>

## What is cached

Nothing. Echo is per connection, so there is nothing to share between them and
no state that outlives a frame.

<br>

## Profiles

| Profile | Drives |
| :- | :- |
| `echo-ws` | one message at a time per connection |
| `echo-ws-pipeline` | 16 messages in flight per connection |
| `echo-ws-limited` | a 10 ms think time between messages |

All three are the same server and the same route. What changes is the shape of
the load, so the coalescing path is what separates them: a pipelined burst is
answered as one write.

<br>

## Layout

```
http1-ws-uring
|
|___/src
|   |___/handlers
|   |   |___ws.zig                     (the /ws route)
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
./scripts/localbench-build.sh http1-ws-uring
./scripts/localbench-validate.sh http1-ws-uring
./scripts/localbench-run.sh http1-ws-uring
```

With a Zig++ toolchain, `ZIX_IO=threadz` runs the server on `std.Io.Threadz`: each
io_uring loop is a task pinned to one Threadz worker, on that worker's ring, rather
than a thread with a ring of its own. A Zig without Threadz ignores the variable.

```bash
ZIG_BIN=<zig++> ./scripts/localbench-build.sh http1-ws-uring
ZIX_IO=threadz ./scripts/localbench-run.sh http1-ws-uring
```
