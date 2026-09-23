# Deploying the WebTransport demo to Fly.io

The local loop stays the fast path. This exists so the demo also has a URL anyone can open in a browser
with no flags at all.

## Why this configuration is not the usual one

Two things here differ from an ordinary Fly app, and both are load-bearing.

**The services have no `handlers`.** Fly's edge proxy terminates TLS for any service that has them, turning
the connection into plaintext inside their network. QUIC cannot survive that: the handshake has to reach
this process and end here, because a WebTransport client never sends a cleartext byte to start with. An
empty `handlers` array makes the proxy a wire, which is what Fly documents for UDP and TCP pass-through.

**The certificate is issued to this machine.** A certificate the edge holds is no use to a QUIC server - the
handshake needs the private key - so `entrypoint.sh` runs certbot in standalone mode, which needs port 80
passed through as well. That is also why the app cannot live on a `*.fly.dev` hostname: nobody but Fly can
issue a certificate for a name Fly owns, and this app has to hold the key.

The UDP listener binds a numeric address. Fly requires UDP listeners on `fly-global-services`, and
`entrypoint.sh` resolves that name before starting the server. `ZIX_SESSION_IP`, `ZIX_CERT`, `ZIX_KEY` and
`DATABASE_URL` are the environment overrides the example reads; without them it keeps its local defaults.

### The port UDP forwards to

Fly rewrites the port for a TCP service and does **not** rewrite it for UDP - it rewrites only the IP. A UDP
service of external 443 into internal 9444 therefore delivers datagrams to the machine on **443**, where
nothing is listening, while the QUIC server waits on 9444 for traffic that can never arrive. The symptoms
are a client stuck on `QUIC_NETWORK_IDLE_TIMEOUT` with `num_undecryptable_packets: 0`, and a packet capture
on the internal port that records nothing at all while datagrams are demonstrably being sent. The UDP
service forwards 443 to 443 and the session port is 443; the TCP service keeps 443 to 9444, which Fly does
honour.

## Staged deployment

`DOMAIN` is optional. With it, the machine obtains and holds a certificate a browser trusts, and no browser
flag is needed. Without it, the bundled development certificate is served instead and browsers need
`--ignore-certificate-errors-spki-list` - the machine still runs, which is what lets the passthrough be
verified before a domain exists. `https://<app>.fly.dev/` is enough to check the wiring, because the pin
applies to a key rather than to a name.

Auto-stop is off deliberately: Fly decides a machine is idle from proxy traffic, and these services have no
proxy, so a machine serving a live WebTransport session looks idle. Stopping it drops every session.

## The sequence

```sh
# 1. The app, a dedicated IPv4, and somewhere to keep the certificate. Raw UDP pass-through needs its own
#    address: a shared one routes through the proxy.
fly apps create zix-webtransport-demo --org personal
fly ips allocate-v4 --app zix-webtransport-demo
fly volumes create certs --app zix-webtransport-demo --region iad --size 1 --yes

# 2. A database. The durable slice is the demo, and it panics without one. Either create a Fly Postgres and
#    attach it (this sets DATABASE_URL), or point DATABASE_URL at a Postgres you already run.
fly postgres create --name zix-demo-db --region iad --vm-size shared-cpu-1x --initial-cluster-size 1
fly postgres attach zix-demo-db --app zix-webtransport-demo

# 3. The certificate inputs. Point the domain's A record at the address `fly ips list` reports, DNS-only if
#    it is behind Cloudflare: a proxying DNS provider would terminate the TLS this setup exists to protect.
fly secrets set --app zix-webtransport-demo DOMAIN=demo.example.com ACME_EMAIL=you@example.com

# 4. Deploy. Fly builds remotely, so no local Docker is needed.
fly deploy --app zix-webtransport-demo
```

Then open `https://<DOMAIN>/` and press *open session*. In a browser: `sessions: 1`, `session: open`.

## Renewal

Certificates last 90 days and the renewal loop replaces the file on the volume; the running process reads
it at startup, so a renewal takes effect on the next restart. `fly apps restart zix-webtransport-demo` after
a renewal is the one manual step, and `fly logs` shows the renewal loop's output if it ever fails.

## Verifying it

```sh
curl -sI "https://<DOMAIN>/" | head -6          # the page, over a certificate a browser trusts
fly logs --app zix-webtransport-demo            # the app's own lines: listening, seeds, sessions
```

The listener line to look for is `listening on <address>:9444 (fallback)` for HTTP/3 and
`listening on 0.0.0.0:9444 (https/1.1 TLS, ...)` for the page. If the QUIC one is missing, the machine could
not bind UDP: check that `ZIX_SESSION_IP` resolved to the address `fly ips list` shows.
