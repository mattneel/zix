# Public WebTransport deployment

How a zix HTTP/3 and WebTransport endpoint is served on the public internet, from a browser, with no
browser flags and no certificate warnings.

---

## Status

Demonstrated. A WebTransport session opens from a stock browser against a hostname with a certificate from
a public authority, with TLS terminated by the server process itself.

---

## Goal

- A browser reaches the endpoint with nothing installed, no `--origin-to-force-quic-on`, and no
  `--ignore-certificate-errors-spki-list`.
- The server process owns the TLS session end to end.
- One origin serves the page and the session, which WebTransport requires: a session's URL must be the
  page's own origin, because a browser will not discover HTTP/3 for an origin it has never had an
  advertisement for.

---

## Shape

```
browser
  |  HTTPS/1.1 over TCP    -> the page       (external 443, internal 9444)
  |  HTTP/3 over QUIC/UDP  -> the session    (external 443, internal 443)
  |
  v
platform edge (a wire, not a TLS terminator)
  |
  v
zix process: TLS terminated here, both listeners on one origin
```

Two transports on one hostname. The page arrives over TCP and the session over UDP, and the origin is the
same for both. The page advertises the HTTP/3 service with `Alt-Svc` on the port the browser connected to,
which is what lets a browser that has never seen the endpoint use HTTP/3 for the session.

---

## Platform requirements

These come from deploying on Fly.io and are recorded because each one fails in a way that does not name
its cause.

| Requirement | What breaks without it |
| :- | :- |
| Services carry no `handlers` | The edge terminates TLS and re-originates plaintext, so the QUIC handshake never reaches the process. A service with an empty handler list is a pass-through wire. |
| The UDP listener binds the port the datagram arrives on | The port in a UDP service is not rewritten, only the address. A service of external 443 into internal 9444 delivers datagrams on 443, so a listener on 9444 waits for traffic that cannot arrive. TCP services do rewrite the port. |
| The UDP listener binds the platform's UDP address | The address a UDP listener must bind is not the wildcard. The reply's source address is taken from the bound address, and a reply from another address is dropped by the edge. |
| A dedicated IPv4 address | A shared address cannot carry the UDP route. |
| Certificate obtained by the machine | A certificate the edge holds is no use: the handshake needs the private key. |

The symptom of the port rule is worth stating on its own: a client reports `QUIC_NETWORK_IDLE_TIMEOUT`
with `num_undecryptable_packets: 0`, and a packet capture filtered on the internal port records nothing
while datagrams are demonstrably being sent.

---

## Certificate

The certificate is issued to the machine, over a DNS-01 challenge, by an ACME client with a DNS provider
plugin. DNS-01 rather than HTTP-01 because it needs no inbound port: on a deployment whose whole design is
that TLS ends inside it, an HTTP challenge port is a second surface that exists only to be probed.

- The certificate and key live on the machine's volume, so a restart reuses them.
- The ACME client's key is converted to the form this server's PEM reader accepts (SEC1 rather than
  PKCS#8).
- Renewal runs on the machine.

### The chain is served whole

The PEM reader decodes every CERTIFICATE block of the document, end-entity first, and the TLS Certificate
message carries each one as an entry, so a client receives the leaf and the intermediates that chain it
back to its authority. That is what a strict client needs: one that does not already hold the intermediate
reports that it cannot get the local issuer certificate and refuses the connection. The entrypoint
therefore copies the ACME client's fullchain file rather than reducing it to a single certificate.

A chain is several kilobytes, which is more than one QUIC Handshake packet carries, so the server splits
the handshake flight across as many packets as it needs, each with its CRYPTO frame at the offset the peer
reassembles from.

---

## Verification

Each layer is checked on its own, because a failure at one looks like a failure at the next.

| Layer | Check | Expected |
| :- | :- | :- |
| DNS | resolve the hostname | the dedicated address |
| TLS | request the page without a verification override | a certificate from a public authority |
| Edge pass-through | request the page and inspect the issuer | the app's certificate, not the edge's |
| Listeners | the process log | two listeners: HTTP/3 on the forwarded UDP port, HTTPS/1.1 on the internal port |
| UDP delivery | a capture on the forwarded port while sending | datagrams arriving at the machine |
| Chain | inspect the certificate the server presents | the leaf plus the intermediates that chain it to its authority |
| Session | press the page's session control | session open, reported over HTTP/3 |
| Session request | the page's protocol panel | two connections kept apart: the document's own, and the session over HTTP/3 with the binding the server agreed; the session rows are the CONNECT the server received, down to the `:protocol` token, the path and the authority |
| Counters | the page's view state | messages received on the stream, patches that moved the durable view, and the durable revision: a measurement reply is a message and not a patch |
| Rate | press the page's measure control | round trips on both channels with the batch each percentile came from, and one 4 KiB exchange labelled as one exchange |

---

## What this is not

- Not a scale-to-zero endpoint. Fly.io does not start a stopped machine on an inbound UDP packet, because
  UDP services bind the UDP address directly and never traverse the proxy that decides to start machines.
  A stopped endpoint has to be started by something else: a request to an HTTP service, or an API call.
- Not a general reverse-proxy deployment. The pass-through is what makes QUIC work and it also means the
  platform cannot inspect, route, or transform the traffic.
