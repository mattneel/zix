# RFC Conformance Reference

Spec source files and the MUST / MUST NOT conformance checklists derived from them, for the raw HTTP/1.1, HTTP/2, HTTP/3, and TLS engine work in 0.5.x, plus the RSA signing, response compression, and proxy gateway (zixer) reference material.

Each checklist is grounded in the current-generation RFCs. Obsoleted predecessors are kept with an -obsoleted.txt suffix for diffing only, not for implementation.

## Checklists

| File | Protocol | Grounded in |
| :- | :- | :- |
| http1-conformance-must-checklist.md | HTTP/1.1 | 9112, 9110, 3986 |
| http2-conformance-must-checklist.md | HTTP/2 | 9113, 7541, 9110 |
| http3-conformance-must-checklist.md | HTTP/3 | 9114, 9204, 9000, 9001, 9002, 8999 |
| tls-conformance-must-checklist.md | TLS 1.3 (https, h2) | 8446, 7301, 6066, 5280, 6125 |

TLS is a shared layer. The three HTTP checklists reference tls-conformance-must-checklist.md rather than repeating it. HTTP/3 uses the same TLS 1.3 handshake but replaces the TLS record layer with QUIC packet protection (RFC 9001).

## Dependency map

```mermaid
graph TD
    U["RFC 3986 URI"]
    SEM["RFC 9110 HTTP Semantics + 9111 Caching"]
    U --> SEM
    SEM --> QRY["QUERY method: 10008 + 9651 Structured Fields"]
    SEM --> H1["HTTP/1.1: 9112"]
    SEM --> H2["HTTP/2: 9113 + 7541 HPACK"]
    SEM --> H3["HTTP/3: 9114 + 9204 QPACK"]
    H3 --> Q["QUIC: 9000 + 9001 + 9002 + 8999"]
    T["TLS: 8446 (+5246) + 7301 + 6066 + 5280 + 6125"]
    H1 -.https.-> T
    H2 -.h2.-> T
    Q --> T
```

## Active RFC inventory

| Layer | RFC | Title |
| :- | :- | :- |
| Foundational | 3986 | URI Generic Syntax |
| | 5234 | ABNF |
| HTTP semantics | 9110 | HTTP Semantics |
| | 9111 | HTTP Caching |
| | 10008 | The HTTP QUERY Method (safe and idempotent, carries content) |
| | 9651 | Structured Field Values for HTTP (grammar RFC 10008 section 3 cites for Accept-Query) |
| HTTP/1.1 | 9112 | HTTP/1.1 |
| HTTP/2 | 9113 | HTTP/2 |
| | 7541 | HPACK |
| HTTP/3 | 9114 | HTTP/3 |
| | 9204 | QPACK |
| | 9220 | Bootstrapping WebSockets with HTTP/3 (extended CONNECT over HTTP/3, the SETTINGS_ENABLE_CONNECT_PROTOCOL opt-in) |
| | 9297 | HTTP Datagrams and the Capsule Protocol (quarter stream id framing, SETTINGS_H3_DATAGRAM opt-in, capsule framing) |
| QUIC | 9000 | QUIC transport |
| | 9001 | QUIC-TLS |
| | 9002 | QUIC Loss Detection and Congestion Control |
| | 8999 | Version-Independent Properties of QUIC |
| | 9221 | An Unreliable Datagram Extension to QUIC (DATAGRAM frames 0x30 and 0x31, the max_datagram_frame_size transport parameter) |
| TLS | 8446 | TLS 1.3 |
| | 8448 | Example Handshake Traces for TLS 1.3 (byte-level known-answer oracle) |
| | 5246 | TLS 1.2 (optional fallback) |
| | 7301 | ALPN |
| | 6066 | TLS Extensions (SNI) |
| | 5280 | X.509 PKIX certificate path validation |
| | 6125 | Service Identity |
| Crypto / RSA | 8017 | PKCS#1 v2.2 (RSA primitives, PSS, PKCS1-v1_5, OAEP) |
| | 4055 | RSASSA-PSS / OAEP algorithm identifiers in X.509 |
| | 5756 | Updates to 4055 (RSA-PSS / OAEP parameters) |
| | 3279 | RSA key and signature identifiers in X.509 |
| JOSE | 7518 | JWA (RS256 / PS256 / ES256 signature algorithms) |
| | 7517 | JWK key representation |
| Compression | 1951 | DEFLATE Compressed Data Format |
| | 7932 | Brotli Compressed Data Format (format + static dictionary in Appendix A) |
| Proxy / gateway | 7239 | Forwarded HTTP Extension (standard form of X-Forwarded-*) |
| | 9209 | The Proxy-Status HTTP Response Header Field |
| | 8441 | Bootstrapping WebSockets with HTTP/2 (Extended CONNECT) |
| ACME | 8555 | Automatic Certificate Management Environment (http-01 webroot flow) |
| WebTransport | draft-ietf-webtrans-http3-16 | WebTransport over HTTP/3, revision 16 (normative target, `webtransport-h3` token) |
| | draft-ietf-webtrans-http3-07 | WebTransport over HTTP/3, revision 07 (deployed dialect, `webtransport` token, browser and aioquic interop) |
| | draft-ietf-quic-reliable-stream-reset-09 | QUIC Stream Resets with Partial Delivery (RESET_STREAM_AT 0x24 and the reset_stream_at 0x1d transport parameter, required for WebTransport data stream resets) |

## Obsoleted (reference only)

| File | Superseded by |
| :- | :- |
| rfc2818-obsoleted.txt | 9110 (https binding moved to 4.2.2) |
| rfc7230-obsoleted.txt | 9112 |
| rfc7540-obsoleted.txt | 9113 |

## Notes

- RFC 10008 has no checklist file of its own. It carries only four MUSTs, small enough to state here: refuse a QUERY whose `Content-Type` is missing or inconsistent with the content (section 2), never sniff the content to repair a missing or wrong type (section 2.1), incorporate the request content into any cache key (section 2.7), and process `Accept-Query` as an RFC 9651 structured field (section 3). zix refuses to cache a QUERY response outright, which satisfies 2.7 without a content-aware key, and leaves the type check to the handler because the engine cannot know which types a route accepts.
- Strict surface totals: HTTP/1.1 about 130 MUST, HTTP/2 about 216, the HTTP/3 + QUIC path about 619 across five specs, TLS 1.3 about 330 in RFC 8446 alone.
- The gating prerequisite for HTTP/3 and for any https or h2 is the TLS 1.3 handshake engine (RFC 8446) plus X.509 path validation (RFC 5280). The QUIC packet, header, and Retry protection math is pure-Zig on std.crypto, but the handshake state machine is what realistically forces binding a C TLS library.
- Out-of-scope extensions, only if a feature lands: 7617 / 7616 / 6750 (auth schemes), 6265 (cookies). 8441 moved out of this list when the proxy gateway work planned WebSocket on its h2 edge, and 9220 moved out with the WebTransport binding, which needs extended CONNECT over h3.
- The WebTransport binding is draft-ietf-webtrans-http3-16 (normative target, `webtransport-h3` token) with draft-ietf-webtrans-http3-07 (deployed dialect, `webtransport` token, SETTINGS_ENABLE_WEBTRANSPORT 0x2b603742 and SETTINGS_WEBTRANSPORT_MAX_SESSIONS 0xc671706a) accepted for browser and aioquic interop. The extensions it requires are vendored alongside it: 9297 (HTTP Datagrams and the Capsule Protocol), 9221 (QUIC DATAGRAM frames), draft-ietf-quic-reliable-stream-reset-09 (RESET_STREAM_AT, required by the binding for data stream resets).
- The Proxy / gateway and ACME rows ground the zixer proxy gateway work. The intermediary rules live in specs already vendored above: 9110 (hop-by-hop strip, Via) and 9112 (framing precedence, why the upstream leg is always re-originated). 7239 standardizes the Forwarded header, 9209 adds Proxy-Status for reporting why a gateway failed, 8441 carries WebSocket over the h2 edge, 8555 grounds the ACME http-01 webroot passthrough. 6455 (WebSocket) and 6066 / 7301 (SNI / ALPN routing) were already in tree.
- TLS version policy: zix offers TLS 1.3 (RFC 8446, default) and optionally TLS 1.2 (RFC 5246) only. TLS 1.0 and 1.1 are deprecated by RFC 8996 (March 2021, "MUST NOT be used"), SSL 3.0 by RFC 7568, SSL 2.0 by RFC 6176. These deprecation memos are policy authorities, not implementation specs, so they are not vendored as .txt here. Offering TLS 1.0 / 1.1 caps an SSL Labs grade at B, so they are never put on the wire (the A+ target).
- Compression rows are reference for the gzip / deflate / brotli response compression item. gzip and deflate ride `std.compress.flate` (the DEFLATE algorithm is RFC 1951, here for grounding), so RFC 1951 is informational, not authored. The container framing RFCs are NOT vendored because std handles them: zlib (RFC 1950, the on-the-wire `deflate` token wrapper) and gzip (RFC 1952). RFC 7932 IS the one that matters: brotli is a std-gap, so it is authored from this spec, dictionary and all (Appendix A).
- The Crypto / RSA and JOSE rows are reference material, not a conformance checklist target. They ground the RSA signing roadmap item: std verifies RSA but cannot sign with an RSA private key, so PKCS#1 v2.2 (8017) is the spec to author from if an RSA certificate or RS256 issuance is ever required. RFC 8017 is the canonical one. 4055 / 5756 / 3279 cover the X.509 identifiers, 7518 / 7517 the JWS / JWK use.
