# How to use zixer

zixer is a proxy gateway you run as a program. You put your service behind it by writing one config file, not by changing your service. This page walks from an empty machine to a running site, then gives one recipe per shape.

Every key mentioned here is described in full in `config-en.md`.

<br>

## Build

zixer builds from the zix repository:

```bash
zig build zixer
```

The binary lands in `zig-out/bin/zixer-<triplet>-<optimize>`, i.e. `zixer-x86_64-linux-debug`. Without `-Doptimize` the mode is `debug`. Copy it anywhere on your path. The rest of this page writes it as `zixer`.

```bash
$ zixer version
zixer 0.5.0 (zig 0.17.0, x86_64-linux)
```

zixer has no version of its own: it ships with the engines and reports the package version, so the line above names exactly which build is running.

<br>

## Five minutes to a proxied service

Say you already run something on `127.0.0.1:3000`.

```bash
zixer init
```

That creates the root dir, which is `$HOME/.zixer` unless you say otherwise:

```
~/.zixer
|
|___/sites
|   |___example.cfg.sample
|
|___/logs
|
|___main.cfg
```

Write one site file:

```bash
cat > ~/.zixer/sites/api.cfg <<'CFG'
engine: http1
ip: 0.0.0.0
port: 8080
upstreams: 127.0.0.1:3000
CFG
```

Check it before starting anything. This reads the same parser the daemon reads:

```bash
$ zixer status
# /home/you/.zixer/main.cfg
main.cfg:
status: ok
...

# /home/you/.zixer/sites/api.cfg
api.cfg:
status: ok
engine: http1
ip: 0.0.0.0
port: 8080
tls: false
upstreams: 127.0.0.1:3000
```

Start it. The daemon is spawned for you the first time:

```bash
$ zixer start api.cfg
api.cfg started on 0.0.0.0:8080

$ curl -s http://127.0.0.1:8080/
```

Stop one site, or everything:

```bash
zixer stop api.cfg
zixer daemon stop
```

<br>

## Choosing where the root dir lives

Three ways, first hit wins:

```bash
zixer --dir /srv/zixer status        # explicit, per command
export ZIXER_DIR=/srv/zixer          # for a shell or a service unit
# neither: $HOME/.zixer
```

Whichever you pick, use the same one for every command, including the one that spawns the daemon. A bare `zixer` reports which root it would use and whether it is initialized.

Keep the path short. The daemon holds a unix socket at `<root>/control.sock`, and that whole string must fit the platform limit (108 bytes on Linux). A path too deep is refused with `control socket path is too long for this platform`.

<br>

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

`status` exits 1 when anything is wrong, so it works as a gate in a deploy script:

```bash
zixer --dir /srv/zixer status || exit 1
zixer --dir /srv/zixer restart api.cfg
```

<br>

## Applying a config change

| you changed | to apply |
| :- | :- |
| one site file | `zixer restart <site.cfg>`, which re-reads that file from disk |
| `main.cfg` | `zixer daemon stop`, then start your sites again |
| a certificate on disk | `zixer restart <site.cfg>` |

A running site never picks up an edit by itself. That is deliberate: a config edit becomes live when you say so, and `status` lets you check it first.

<br>

## Recipes

### Static site

No backend at all. zixer is the origin:

```
engine: http1
ip: 0.0.0.0
port: 8080
public_dir: /var/www/site
```

A directory request maps to `index.html`. If a `.br` or `.gz` sibling sits next to a file, it is served to a client that accepts that coding, with `Vary: Accept-Encoding` on the response.

### Single page app

Any path that is not a real file answers the app shell, so client-side routing works on a refresh:

```
engine: http1
ip: 0.0.0.0
port: 8080
public_dir: /var/www/app/dist
spa_fallback: index.html
```

### Static assets beside a backend

Only `/assets/...` comes off disk, everything else is proxied:

```
engine: http1
ip: 0.0.0.0
port: 8080
upstreams: 127.0.0.1:3000
public_dir: /var/www/app/dist
public_prefix: /assets
```

The prefix is required as soon as a site has both planes and a fallback, otherwise a genuine 404 from the backend would disappear into the app shell.

Note that the request path is joined onto `public_dir` as it arrives, so `public_prefix: /assets` needs a real `assets/` directory inside `public_dir`.

### Making a static site fast

Every recipe above re-opens the file on each request. Worse, a browser sends
`Accept-Encoding: gzip, deflate, br`, so zixer looks for a `.br` sibling, then
a `.gz` sibling, then the file: three opens for one response when the file has
no sibling.

One key changes that. The file is kept open, the sibling choice is made once,
and the next request is a lookup:

```
engine: http1
ip: 0.0.0.0
port: 8080
public_dir: /var/www/app/dist
spa_fallback: index.html
public_dir_cache_ttl_ms: 60000
```

The window doubles as the reload path. An edited file keeps serving its old
bytes until the window passes, then the next request re-opens it. Nothing has
to restart. So pick the window as the deploy lag you would accept:

| your files change | window to set |
| :- | :- |
| only on deploy, a built bundle | `60000` or more, they are stable between releases |
| by hand, while someone is watching a browser | `1000`, a reload shows the change |
| constantly, generated per request | leave it out, an entry would be stale before it is used |

Set `public_dir_cache_max_entries` in `main.cfg` when the site serves more than
256 files. It is daemon-wide, because there is one table for the whole process
and every site shares it. There is no site-level version of that key.

A site can opt out on its own with `public_dir_cache_ttl_ms: 0` while the
daemon leaves the cache on for everything else.

Two things happen for free once this is on. Large files, 64 KB and up, go
straight from the kernel to the socket on a cleartext http1 site and never
enter zixer's memory. And the cache can never break a request: anything it
cannot answer falls through to the plain open, which is also what produces the
404 and the `spa_fallback` page.

### Several backends

Requests rotate over the list. A backend that refuses a connection is skipped for a few seconds and then tried again:

```
engine: http1
ip: 0.0.0.0
port: 8080
upstreams: 127.0.0.1:3000, 127.0.0.1:3001, 127.0.0.1:3002
```

Upstream hosts must be ip literals. `localhost:3000` passes the config check and then fails on every request.

### TLS at the edge

The backend stays cleartext, so nothing behind zixer needs a certificate:

```
engine: http1
ip: 0.0.0.0
port: 443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000
```

The certificate decides which names the site answers. A request for a host the certificate does not cover is answered `421`, which is the correct answer for a misdirected request rather than a silent wrong-site response.

### Renewal with certbot

Add the challenge path to the site and let certbot write into the webroot:

```
acme_webroot: /var/www/acme
```

```bash
certbot certonly --webroot -w /var/www/acme -d example.com \
  --deploy-hook 'zixer --dir /srv/zixer restart example.cfg'
```

A TLS site on a port other than 80 also binds port 80 for the challenge, so the process needs that privilege. Port 80 has to be free for it: a program already holding it fails the start with `challenge port 80 is already in use`.

That port 80 listener is called the cleartext companion, and the next recipe uses it for something else.

`acme_proxy` is the other way to answer the challenge, not a way around port 80. The companion still holds the port and relays the challenge path to the address you name, which is what `certbot certonly --standalone --http-01-port 9080` expects:

```
acme_proxy: 127.0.0.1:9080
```

### Moving every request to https

A browser typing a bare host name goes to port 80 in cleartext. One key sends it
on to the https origin instead of leaving it unanswered:

```
engine: http1
ip: 0.0.0.0
port: 443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000

force_https: true
```

This binds port 80 the same way the challenge does, so the same privilege and
the same free-port rule apply, and a site that also has acme keys serves both
from the one listener. The redirect is `301` for GET and HEAD and `308` for
every other method, so a POST is repeated with its body rather than turned into
a GET.

Add `redirect_host` when the `Location` should name something other than the
`Host` the client sent, i.e. moving `www.example.com` onto the bare name:

```
force_https: true
redirect_host: example.com
```

### Bounding a slow client

Nothing above stops a client from opening a connection, sending half a request
head, and holding it. Two keys do:

```
engine: http1
ip: 0.0.0.0
port: 8080
upstreams: 127.0.0.1:3000

client_timeout_ms: 30 * 1000
client_conn_limit: 4096
```

`client_timeout_ms` is how long one exchange may take. Past it the site cuts the
connection and answers `408 request timeout`. `client_conn_limit` is how many
connections the site tracks at once, and one arriving with every slot taken is
answered `503 too many connections` before it has sent a byte.

Both are off by default, and the limit only means anything while the budget is
set. Pick the budget as the slowest ordinary request the site should tolerate,
because an upload from a phone on a bad connection is a slow client too:

| the site serves | budget to set |
| :- | :- |
| ordinary api requests | `30 * 1000` or less |
| file uploads from browsers | `300 * 1000`, or leave it out |
| a public edge facing the internet | set one, an unbounded edge is what a slow-request flood needs |

A websocket, an SSE stream, and a grpc stream are not cut. Each one holds its
slot at handover instead of running a budget, so a long-lived stream keeps
working while ordinary exchanges stay bounded. An http3 site refuses both keys,
because the cut works on a socket and every QUIC connection there shares one.

### Adding headers on either leg

Two optional blocks at the end of a site file, one per leg:

```
engine: http1
ip: 0.0.0.0
port: 443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000

[response_headers]
strict-transport-security: max-age=31536000
x-frame-options: DENY

[request_headers]
x-real-ip: $client_ip
x-forwarded-proto: $scheme
```

`[response_headers]` goes on what the site answers a client, `[request_headers]`
on what it sends the backend. A value may name `$client_ip`, `$scheme`, or
`$host`, which is how a backend behind a terminating edge learns the real client
address and the scheme the request arrived on. `$scheme` is the site's own `tls`
setting and never anything the client claimed.

A section runs to the end of the file, so every flat key has to come above the
first `[` line. A site key written below one is reported by name rather than
quietly served as a header.

A name already on the message is replaced, not joined, so `x-frame-options` here
overrides whatever the backend sent. Names the edge owns are refused when the
file is read, i.e. `content-length`, `via`, `date`, and the hop-by-hop list, and
`config-en.md` has the full list with each fault text.

### HTTP/2

```
engine: http2
ip: 0.0.0.0
port: 8443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000
```

Clients speak h2, the backend keeps speaking HTTP/1.1. A websocket over extended CONNECT is bridged to an ordinary websocket backend.

### gRPC

```
engine: grpc
ip: 0.0.0.0
port: 50051
upstreams: 127.0.0.1:9109
```

Both legs are h2 so trailers, and therefore the grpc status, survive the hop. A grpc site cannot serve static files.

### HTTP/3

```
engine: http3
ip: 0.0.0.0
port: 443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000
```

TLS is not optional here, it is part of QUIC. The port is UDP, so open it in the firewall as UDP.

### Datagram forward

A blind relay, one flow per client, which is what a media path in front of a WebRTC engine needs:

```
engine: udp
ip: 0.0.0.0
port: 3478
upstreams: 127.0.0.1:9083
```

Nothing is parsed and nothing is rewritten. Each client gets its own socket toward the backend, so the backend sees one distinct peer per client.

<br>

## Running it as a service

The daemon runs in the foreground with `zixer daemon`, which is what a service manager wants. Start your sites after it is up:

```bash
ZIXER_DIR=/srv/zixer zixer daemon
```

The daemon writes to two places at once: `logs_dir/<date>/zixer-000000.log`, and the console it was started on. `log_level` sets the threshold for both, `info` by default. `logs_dir` must already exist, which `zixer init` handles and `zixer status` checks, and a daemon that cannot write there keeps the console output.

<br>

## Troubleshooting

| what you see | what it means | what to do |
| :- | :- | :- |
| `zixer is not initialized` | no `main.cfg` under the root | `zixer init`, or point `--dir` at the right root |
| `daemon did not answer after spawn` | the daemon could not start | run `zixer daemon` in the foreground and read the message |
| `control socket path is too long for this platform` | the root dir path is too deep | move the root somewhere shorter |
| `api.cfg has config errors` | the site did not validate | `zixer status api`, fix each listed key |
| `port 8080 is already used by other.cfg` | another started site owns it | change the port, or stop the other site |
| `port 8080 is already in use` | a listener outside this daemon owns it | find it with `ss -ltnp`, then stop it or change the port |
| `challenge port 80 is already used by other.cfg` | another started site already owns the port 80 companion, which acme keys and `force_https` both ask for | keep those keys on one site, and let the others renew from its webroot |
| `challenge port 80 is already in use` | a listener outside this daemon owns port 80 | find it with `ss -ltnp` and stop it, the companion has to hold port 80 |
| `bind failed (BadUpstreamAddress)` | a udp site upstream is not an ip literal | write the address, not a name |
| `502 all upstreams failed` | every backend refused or failed | check the backend, and that the upstream address is an ip literal |
| `503 no upstream available` | every backend is in its cooldown window | check the backends, retry after a few seconds |
| `504 upstream timeout` | the backend accepted the connection and then said nothing for `upstream_timeout_ms` | check the backend, raise the value, or set `upstream_timeout_ms: 0` if it really thinks that long |
| `504 upstream connect timeout` | the connect itself ran past `upstream_connect_timeout_ms`, so the backend never accepted | check that the address is reachable, then raise the value or set it to `0` |
| `408 request timeout` | one client exchange ran past `client_timeout_ms` and the site cut it | raise the value for a site serving slow uploads, or leave it if the client really is stuck |
| `503 too many connections` | every `client_conn_limit` slot is taken | raise the limit, or find out why connections are not being released |
| `421 misdirected request` | the Host is not covered by `tls_cert` | use a name the certificate covers, or issue one that covers it |
| `404 not found` on a static path | the file is not under `public_dir` | check the path, and remember that `public_prefix` is not stripped before the join |
| the acme challenge 404s | the token is not under the webroot | it must be at `<acme_webroot>/.well-known/acme-challenge/<token>` |
| an edit did nothing | the site is running the old file | `zixer restart <site.cfg>` |

<br>

## Where to look next

| question | page |
| :- | :- |
| what does this key do exactly | `config-en.md` |
| how is the gateway put together | `hld-en.md` |
| what happens on the wire | `lld-en.md` |
| can I see a working example of each shape | `examples/proxies/README-en.md` in the repository |
