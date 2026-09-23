# zixer

A proxy gateway you run as a program, built on the zix engines, standard library only.

- Config driven: a service goes behind it by writing one text file, not by changing the service.
- One daemon holds many independent sites, one site per file, each with its own port and engine.
- Terminates http1 (with SSE and WebSocket), http2 (with rfc 8441), gRPC, and http3, then re-originates http1 to the backend. Plus a per-flow udp forward.
- TLS at the edge with ACME http-01 for certbot, and a cert reload that is just `zixer restart`.
- Static files per site, round-robin upstreams with O(1) availability, bounded retry, and rfc 9209 `Proxy-Status` on every local failure.
- Bounded on both legs: how long one client exchange may take, how many client connections a site tracks, and how long a connect to a backend may run.
- Headers a site adds on either leg, written as a block in its config file, with the client address, the scheme, and the request authority available as tokens.
- Validation first: an unknown key, a bad value, or a key that cannot apply is refused with a fix hint, never a silent default.
- Builds on Zig 0.16 and 0.17.

For the walkthrough see `how-to-use-en.md`, for the architecture see `hld-en.md`, for the wire-level details see `lld-en.md`, for every config key see `config-en.md`.

## Build

zixer is an executable that ships from the zix repository, not a package you depend on:

```bash
zig build zixer
```

The binary lands in `zig-out/bin/zixer-<triplet>-<optimize>`, i.e. `zixer-x86_64-linux-debug`. Without `-Doptimize` the mode is `debug`. Copy it anywhere on your path. The rest of this page writes it as `zixer`.

```bash
$ zixer version
zixer 0.5.0 (zig 0.17.0, x86_64-linux)
```

zixer has no version of its own. It ships with the engines and reports the package version, so that line names exactly which build is running.

## Quickstart

Say something already runs on `127.0.0.1:3000`:

```bash
zixer init
```

Write `~/.zixer/sites/api.cfg`:

```
engine: http1
ip: 0.0.0.0
port: 8080

upstreams: 127.0.0.1:3000
```

Then check it and serve it:

```bash
zixer status
zixer start api.cfg
```

`http://localhost:8080/` now reaches the service, and the service was not touched.

## The root dir

Everything zixer reads lives under one directory:

```
~/.zixer
|
|___/sites
|   |___example.cfg.sample             (written by init, inert)
|   |___api.cfg                        (one site per file)
|
|___/logs
|
|___main.cfg
|___control.sock                       (created by the daemon while it runs)
```

The root resolves as `--dir <path>`, then `ZIXER_DIR`, then `$HOME/.zixer`.

## The commands

| you want to | run |
| :- | :- |
| create the root dir | `zixer init` |
| check every config | `zixer status` |
| check one config | `zixer status api` (the `.cfg` is optional) |
| see what sites exist | `zixer list` |
| serve a site | `zixer start api.cfg` |
| stop serving it | `zixer stop api.cfg` |
| apply an edit to a site file | `zixer restart api.cfg` |
| stop everything | `zixer daemon stop` |
| run the daemon in the foreground | `zixer daemon` |

`status` exits 1 when anything is wrong, so it works as a gate in a deploy script. A running site never picks up an edit by itself: a config change becomes live when you say so.

## Site config

Flat `key: value` lines, `#` comments, comma-separated lists, integer math on numeric values, and two optional `[section]` blocks at the end:

| key | meaning |
| :- | :- |
| `engine` | `http1`, `http2`, `grpc`, `http3`, or `udp` |
| `ip`, `port` | the listening socket |
| `tls`, `tls_cert`, `tls_key` | terminate TLS at this edge |
| `force_https`, `redirect_host` | a cleartext companion on port 80 that moves every request to this site's https origin |
| `acme_webroot`, `acme_proxy` | answer the rfc 8555 http-01 challenge |
| `upstreams` | comma list of `host:port` backends, picked round-robin |
| `public_dir`, `public_prefix`, `spa_fallback` | serve static files from this site |
| `public_dir_cache_ttl_ms` | keep those files open between requests, `0` is off |
| `kernel_backlog`, `max_recv_buf` | listener tuning |
| `client_timeout_ms`, `client_conn_limit` | how long one client exchange may take, and how many client connections the site tracks |
| `upstream_timeout_ms` | how long the edge waits on a silent upstream before answering 504 |
| `upstream_connect_timeout_ms`, `upstream_idle_ttl_ms` | the connect budget per backend attempt, and how long an unused backend connection is kept |
| `process_limit`, `process_queue_len`, `process_queue_timeout_ms` | overload valve, how many requests may run against the backends at once |
| `[response_headers]`, `[request_headers]` | headers this site adds on the client leg and on the upstream leg |

A site needs `upstreams` or `public_dir`. Everything else has a default. See `config-en.md` for the per-key rules, which engine each applies to, and every fault message.

The two header sections take the same `name: value` lines, and a value may name
`$client_ip`, `$scheme`, or `$host`:

```
[response_headers]
x-frame-options: DENY

[request_headers]
x-real-ip: $client_ip
```

A section runs to the end of the file, so every flat key comes first.

## What each engine does at the edge

| engine | client side | upstream side |
| :- | :- | :- |
| http1 | http1, SSE and WebSocket pass through | http1, keep-alive reused |
| http2 | h2 prior knowledge or ALPN, rfc 8441 extended CONNECT | http1, re-originated per stream |
| grpc | h2 with trailers | h2 end to end, so trailers survive |
| http3 | QUIC terminated in zixer | http1, re-originated per stream |
| udp | raw datagrams, one flow per client address | one ephemeral socket per flow |

Every request is re-originated: zixer parses the client framing and builds its own upstream message, so raw client bytes never splice through.

## Demos

`examples/proxies/` carries one demo per shape, each an upstream `.zig` plus a site `.cfg` that runs from any root:

```bash
zig build zixer-examples
```

See `examples/proxies/README-en.md` for the matrix and the drive commands.

## Testing

```
zig build zixer-unit-test        # in-process, no daemon
zig build zixer-test-runner-all  # every demo, started and driven end to end
```

`zixer-unit-test` is a separate step from zix's own `unit-test` and `test-all`, because zixer keeps its own build files. The runner builds a throwaway root copied from `examples/proxies`, so a run never disturbs a developer's daemon.
