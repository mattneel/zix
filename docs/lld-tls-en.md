# LLD: zix.Tls (pure-Zig TLS 1.3 + 1.2)

Internal implementation details. For design rationale see [`docs/hld-tls-en.md`](hld-tls-en.md) and ADR-045 / 046 / 047.

`zix.Tls` is sans-I/O. The server handshake is driven by `connection.serverHandshake`, the client by `client.zig` / `tls12_client.zig`. The engines own the socket loop. Http1 is thread-per-connection in `tcp/http1/tls_serve.zig`. Http2 and Grpc select between two paths by `dispatch_model` (ADR-052): `.EPOLL` / `.URING` use the per-core multiplexed `tcp/http2/tls_mux.zig` and `tcp/http2/grpc/tls_mux.zig` over a resumable session in `tcp/tls/tls_session.zig`, and `.ASYNC` uses `tcp/http2/tls_serve.zig` and `tcp/http2/grpc/tls_serve.zig` over the shared terminator `tcp/tls/h2_terminator.zig`.

---

## wire.zig

`Reader` and `Writer` over a byte slice, big-endian. `Reader.readU8 / readU16 / readU24 / readBytes` with bounds checks. `Writer.writeU8 / writeU16 / writeU24 / writeBytes`, plus `placeU16 / patchU16` to back-patch a length once the body is written (used for every variable-length TLS field). No allocation: the caller supplies `buf`.

## handshake.zig

### Wire enums

```zig
pub const CipherSuite = enum(u16) {
    AES_128_GCM_SHA256 = 0x1301,
    AES_256_GCM_SHA384 = 0x1302,           // declared, not implemented
    CHACHA20_POLY1305_SHA256 = 0x1303,     // declared, not implemented
    ECDHE_ECDSA_AES128_GCM_SHA256 = 0xc02b, // TLS 1.2 floor suite
    _,
};
pub const NamedGroup = enum(u16) { SECP256R1 = 0x0017, X25519 = 0x001d, _ };
pub const SignatureScheme = enum(u16) { RSA_PKCS1_SHA256 = 0x0401, ECDSA_SECP256R1_SHA256 = 0x0403, RSA_PSS_RSAE_SHA256 = 0x0804, ED25519 = 0x0807, _ };
```

`server_cipher_prefs = {AES_128_GCM_SHA256}` and `server_group_prefs = {X25519, SECP256R1}` are the built-in defaults.

### ClientHello parse

`parseClientHello` returns an `ok` struct or an `alert`. It records `offers_tls13` (from supported_versions), `has_signature_algorithms`, `has_supported_groups`, the raw `signature_schemes` and `supported_groups` bodies, the per-group key_shares (`x25519_share`, `secp256r1_share`), `sni`, and the raw `alpn` ProtocolNameList. Helpers: `offersCipher`, `offersGroup`, `hasKeyShare`, `offersSignatureScheme`.

### negotiate

```zig
pub fn negotiate(hello, key_exchange, group_prefs: []const NamedGroup) Outcome
```

Returns `legacy_version` when 1.3 is not offered (the caller drops to the 1.2 track), a `MISSING_EXTENSION` alert without sig-algs / groups, `hello_retry_request` when the chosen curve has no key_share, else `server_hello`. `pickCipher` iterates `server_cipher_prefs`. `pickGroup` iterates the configured `group_prefs` (so a restricted / reordered `Tls.Context.curves` is honored), returning the first the client also offered.

### Serializers

`serializeServerHello` writes the ServerHello with supported_versions (0x0304) and key_share. `serializeHelloRetryRequest` writes the HRR with the special HRR random sentinel (SHA-256 of "HelloRetryRequest") and a key_share extension naming only the group to retry with.

## key_schedule.zig

`Secret = [32]u8`, SHA-256 throughout (so only the AES-128-GCM / SHA-256 1.3 suite is honorable). `Transcript` wraps a running SHA-256 of the handshake messages, `update(bytes)` and `current()`. `HkdfSha256.extract` / `deriveSecret` / `expandLabel` build the early, handshake, and master secrets and the traffic keys per RFC 8446 7.1.

## record.zig

`protect(out, plaintext, content_type, key, iv, seq)` builds an AEAD record: the per-record nonce is `iv XOR seq` (8-byte seq right-aligned), the additional data is the record header, the inner plaintext is `content || content_type` (RFC 8446 5.2). `deprotect` reverses it and returns the inner content type. `ContentType` enumerates handshake / application_data / alert / change_cipher_spec.

## certificate.zig

```zig
pub const SigningKey = union(enum) {
    ecdsa_p256: EcdsaP256.KeyPair,
    ed25519: Ed25519.KeyPair,
    rsa: rsa.PrivateKey,
    pub fn scheme(self) SignatureScheme  // .ECDSA_SECP256R1_SHA256, .ED25519, or .RSA_PSS_RSAE_SHA256
};
```

Builders for Certificate, CertificateVerify, and Finished. CertificateVerify signs `0x20 * 64 || context-string || 0x00 || transcript-hash` (RFC 8446 4.4.3) with the key's scheme: ECDSA emits a DER signature, Ed25519 the raw 64 bytes, and an RSA key the `rsa_pss_rsae_sha256` PSS signature via `signPss` (`buildCertificateVerify` takes the salt, the ECDSA / Ed25519 paths ignore it). Finished `verify_data` is `HMAC(finished_key, transcript-hash)`, verified byte-exact against the RFC 8448 trace in-file.

## connection.zig

### HandshakeOptions

```zig
certificate_der, signing_key,
ephemeral_secret: [32]u8, server_random: [32]u8,   // fresh per connection
alpn_prefs: []const Alpn = &.{},
group_prefs: []const NamedGroup = &server_group_prefs,
request_client_cert: bool = false,                  // mTLS CertificateRequest
```

### serverHandshake

Parse ClientHello, `negotiate(&hello, &.{}, opts.group_prefs)`, seed the transcript with the ClientHello, then `completeHandshake`. `completeHandshake` guards `cipher == AES_128_GCM_SHA256`, checks the client offered the signing key's scheme (`NoCommonSignatureScheme` otherwise), negotiates ALPN, runs `computeKeyExchange` for the curve, writes ServerHello + EncryptedExtensions + Certificate + CertificateVerify + Finished, and derives the application keys into a `Connection`.

### HelloRetryRequest

`serverHelloRetry` negotiates only to find the group, serializes the HRR, and seeds the transcript with the synthetic `message_hash` of ClientHello1 (`0xfe 00 00 <hash_len> || Hash(CH1)`, RFC 8446 4.4.1) followed by the HRR. It returns a `RetryFlight { to_send, state }`. `serverHandshakeAfterRetry` consumes ClientHello2, re-negotiates with `state.opts.group_prefs`, asserts the group matches, and runs `completeHandshake` on the carried transcript.

### Connection

Holds the application + client-handshake keys and three sequence numbers (`server_app_seq`, `client_app_seq`, `client_hs_seq`). `writeAppData` encrypts and bumps `server_app_seq`. `readAppData` decrypts and classifies the inner type (RFC 8446 5.1): application_data returns the plaintext, alert -> `PeerClosed`, post-handshake handshake -> `UnexpectedMessage`. `verifyClientFinished` checks the client Finished against the transcript. `encryptedAlert` / `closeNotify` build outbound alerts.

## context.zig

`Version = enum(u8) { TLS_1_2 = 0x12, TLS_1_3 = 0x13 }` (ordered for min <= max). `Context.init` calls the I/O-free `validate(config)`, reads the cert / key PEM, `pemToDer`, duplicates the DER into an owned slice, then detects the key type from `cert.pub_key_algo` (`.X9_62_id_ecPublicKey` -> ECDSA via `ecdsaScalarFromSec1`, `.curveEd25519` -> Ed25519 via `ed25519SeedFromPkcs8`, `.rsaEncryption` -> RSA via `rsa.PrivateKey.fromDer`, rejecting below RSA-2048 with `ZixRsaKeyTooSmall`). The key DER buffer is sized for an RSA PKCS#8 key, larger than an EC key. `handshakeOptions(ephemeral, random, pss_salt)` fills a `HandshakeOptions` from the context plus the per-connection randoms (the salt is consumed only by an RSA CertificateVerify). `allowsTls13` / `allowsTls12` read the version range.

### validate (the honesty boundary)

Rejects empty curve / cipher lists, any curve outside {X25519, SECP256R1}, any cipher outside {AES_128_GCM_SHA256, ECDHE_ECDSA_AES128_GCM_SHA256}, an inverted version range, a 1.3 ceiling missing AES_128_GCM_SHA256, and a 1.2 floor missing the 1.2 suite or secp256r1. Errors: `ZixTlsUnsupportedCurve`, `ZixTlsUnsupportedCipher`, `ZixTlsInvalidVersionRange`, `ZixTlsMissingCipherForVersion`, `ZixTlsMissingCurveForTls12`, `ZixTlsNoCurves`, `ZixTlsNoCiphers`.

## pem.zig

`pemToDer(out, pem)` base64-decodes a single PEM block. `ecdsaScalarFromSec1` extracts the 32-byte private scalar from a SEC1 EC key. `ed25519SeedFromPkcs8` extracts the 32-byte seed after the `04 22 04 20` PKCS#8 prefix.

## rsa.zig

The RSA signer (ADR-048), server-side only. `PrivateKey.fromDer(der, is_pkcs8)` parses a two-prime RSAPrivateKey (RFC 8017 A.1.2): a PKCS#8 wrapper is unwrapped to its inner OCTET STRING first, then the modulus `n` and private exponent `d` are copied into owned fixed buffers (leading-zero stripped). `signPkcs1v15(message, out)` is the deterministic EMSA-PKCS1-v1_5 path (RFC 8017 9.2): `0x00 01 PS 00 || DigestInfo || SHA256(message)`. `signPss(message, salt, out)` is EMSA-PSS (RFC 8017 9.1) with MGF1, the salt injected by the caller so the encoding is deterministic and unit-testable. Both end in RSASP1 via the Chinese Remainder Theorem (RFC 8017 5.1.2): two half-width modexps over the primes `p` and `q` (the CRT factors are now used, not just `n` and `d`), each run through the constant-time Montgomery modexp in `montgomery.zig` (a fused ADCX / ADOX asm path on x86_64+ADX, a portable CIOS otherwise), then recombined and I2OSP to `k` bytes. `std.crypto.ff.Modulus.powWithEncodedExponent` is the fallback for prime widths the Montgomery path does not cover.

## cert_verify.zig

`verifyChain(chain_der, anchor_der, now_sec)` verifies a [leaf, intermediate, ...] chain to an anchor: each link's signature via std `Parsed.verify`, plus a manual extension walk for basicConstraints (cA / pathLen), keyUsage (keyCertSign), and critical-ext handling (the `[3]` extensions wrapper reads as tag `.bitstring` from `std.crypto.Certificate.der.Element`, mirrored here). `verifyCertIdentity(end_entity_der, host)` checks a DNS SAN (std `verifyHostName`) or an IPv4 SAN (`sanHasIp4`, scanning for the `0x87 0x04 <4 bytes>` GeneralName, since std is DNS-only).

## tcp/http1/tls_serve.zig

`runTls` reads `config.tls.?` (the context) and runs the accept loop. `serveConnTls(fd, handler, ctx)`:

1. read the ClientHello record, generate `ephemeral_secret` + `server_random` + `pss_salt` (getrandom), build `opts = ctx.handshakeOptions(...)`.
2. version policy: if `!ctx.allowsTls13()`, go straight to the 1.2 path (ECDSA only, else `ZixTls12RequiresEcdsa`).
3. HelloRetryRequest round if `serverHelloRetry` returns one, else `serverHandshake`. On `ZixUnsupportedTlsVersion`: if `!ctx.allowsTls12()` send a `protocol_version` alert, else take the 1.2 path.
4. read (ChangeCipherSpec) + client Finished, then one application record -> `readAppData` -> `core.parseHead`.
5. Host vs cert identity (`verifyCertIdentity`) -> 421 on mismatch, else run the handler with the in-memory capture sink (`runHandlerToBuffer`) and `writeAppData` the response, then `closeNotify`.

`readRecord` / `readAll` / `writeAll` use `std.os.linux.read` / `write` with an errno switch (no std.posix wrapper for portability across 0.16 / 0.17).

### SSE / streaming over TLS (ADR-054)

The thread-per-connection path also serves a streaming handler (SSE) over TLS, on both `zix.Http1` (`core.zig`) and `zix.Http` (`response.zig`). `serveRequests` arms a per-connection `TlsStreamSink`, a type-erased writer (`StreamSinkFor(@TypeOf(conn))`) holding the live connection and fd: each write encrypts one TLS record (`conn.writeAppData`) and sends it. `writeAllFD` checks the buffered capture sink first, then the stream sink, so a normal response keeps the buffered fast path. A handler opts into streaming with `res.sendStream()` (`zix.Http`) or `beginStream()` / `res.sendStream()` (`zix.Http1`, a no-op in cleartext), which detaches the capture sink so the next writes fall through to the stream sink. `runHandlerToBuffer` / `processRequestToBuffer` report the streamed outcome (the capture sink was detached) so the loop closes after the stream ends. The multiplexed `tls_mux` path stays request / response only.

### WebSocket over TLS (ADR-055)

WebSocket builds on the same stream sink for the write half and adds the read half (decrypt records, parse frames). A handler served over TLS calls `WebSocket.serveTls(fd, key, on_frame)`: it detaches the capture, writes the `101` through the stream sink (encrypted), and registers a handoff (`requestWebSocket` / `takeWebSocket`, shared with the cleartext `.EPOLL` path on `zix.Http1`, added to `zix.Http`). After the handler returns, `serveRequests` takes the handoff and runs `serveWsTls`: read one ciphertext record, decrypt (`conn.readAppData`), accumulate, then `WebSocket.pump` the complete frames (text / binary -> `on_frame`, ping auto-ponged, close auto-echoed). `pump` coalesces the pass's outbound frames and flushes via `writeAllFD`, which the stream sink encrypts as one record. `send` over TLS routes the same way. `zix.Http` gains the engine-driven pieces (`WsFrameFn`, `send`, `pump`, `upgradeFd`, the handoff) so both engines share the `on_frame(fd, opcode, payload)` shape. Rooms / broadcast are cleartext-only (each connection has its own TLS session), so wss is per-connection. The multiplexed `tls_mux` path drops any handoff (WS is thread-per-connection only).

## tcp/tls/h2_terminator.zig (shared h2-over-TLS terminator)

`serveConnTls(fd, ctx, driver)` is the engine-agnostic terminator used by the `.ASYNC` path of both Http2 and Grpc. It runs the handshake (version policy + 1.2 fallback to `serveConnTls12`, which takes the same `driver`), asserts ALPN selected h2 (`ZixAlpnNotH2` otherwise), verifies the client Finished, then calls `driver.drive(fd, &conn, &record_buf)`. The driver owns the connection until close: it runs the resumable h2 mux inline over the decrypted records and seals the engine's frames back into TLS records through a thread-local write hook. No socketpair, no second thread.

## tcp/http2/tls_serve.zig and tcp/http2/grpc/tls_serve.zig

This is the `.ASYNC` path. `runTls` reads `config.tls.?`, runs the accept loop, and hands each connection to its own worker thread, which calls `serveConnTls` with a `MuxDriver(routes)`. The driver's `drive` is what differs: Http2 runs `mux.processRing` over a `mux.MuxConn`, Grpc runs `core.grpcMuxProcessRing` over a `GrpcMuxConn` then `flushStage` to cork the staged reply. Both seal frames into TLS records through `frame.write_hook`, the same resumable state machine as the cleartext `.EPOLL` / `.URING` models, so there are no per-stream write races. The `.EPOLL` / `.URING` dispatch models instead use the multiplexed `tls_mux.zig` below.

## tcp/tls/tls_session.zig (resumable TLS 1.3 server session)

The linchpin of the multiplexed path (ADR-052). A sans-blocking-I/O TLS 1.3 server session that one epoll worker drives for many connections at once. `Session.init(cert_der, signing_key, alpn_prefs)` seeds the randoms. `feed(input, to_send_buf, plain_buf)` accumulates ciphertext in an internal `rbuf`, processes each complete record, and returns a `FeedResult{ to_send, plaintext, outcome }`. The `Phase` state machine runs `hello -> finished -> established -> closed`: in `hello` it calls `serverHandshake` and emits the flight, in `finished` it verifies the client Finished, in `established` it decrypts application data. `encrypt` seals plaintext into a record, `closeNotify` emits the close alert. TLS 1.3 only: a 1.2-only ClientHello is refused with a fatal alert (the 1.2 fallback stays on `tls_serve.zig`).

## tcp/http2/tls_mux.zig and tcp/http2/grpc/tls_mux.zig (multiplexed dispatch)

The `.EPOLL` / `.URING` path (ADR-052). `runTlsMux` spawns one worker per core, each with its own `SO_REUSEPORT` listener and epoll instance. A `TlsConn` slab (indexed by fd) holds the `tls_session.Session`, the h2 / gRPC mux, and a staged outbound-ciphertext buffer that arms `EPOLLOUT` on `EAGAIN` for backpressure. `onReadable` reads ciphertext, calls `session.feed`, sends the handshake flight, and on the established outcome feeds the decrypted plaintext into the mux (`processRing` / `grpcMuxProcessRing`), whose frames are sealed back into records via `frame.write_hook` pointed at `hookWrite`. One worker multiplexes many connections, so high concurrency does not spawn a thread per connection.

## tls12_*.zig

The 1.2 track mirrors the 1.3 layers: `tls12_prf` (SHA-256 PRF key schedule), `tls12_record` (1.2 AES-GCM with the explicit 8-byte nonce), `tls12_version` (`selectVersion` + the downgrade sentinel in ServerHello.random, RFC 8446 4.1.3), `tls12_connection` (`serverFlight1` + `serverFinish`, ECDHE-ECDSA-AES128-GCM, secp256r1), and `tls12_client`.

## dtls_*.zig

The DTLS 1.2 track (RFC 6347), reached only by `zix.Webrtc`. Nine files, and `zix.Tls` re-exports none of them. Per-file internals are in [`docs/lld-webrtc-en.md`](lld-webrtc-en.md), because every trap here is a WebRTC-facing one. The three that matter most to a TLS reader:

- `dtls_connection.zig` composes its **own** flights (2, 4 and 6) and reuses only leaf primitives from the 1.2 track. It cannot reuse `tls12_connection.zig`: that file hashes TLS-framed bytes, while RFC 6347 section 4.2.6 needs the transcript taken over DTLS 12-byte headers as-if-unfragmented, excluding the first ClientHello and the HelloVerifyRequest. The mismatch is invisible until a real peer rejects the Finished message.
- `dtls_record.zig` adds epoch, a 48-bit sequence, and an anti-replay window on top of the same AEAD. The window must be checked before the AEAD and updated after, or a forged far-ahead sequence clears it.
- `dtls_exporter.zig` is RFC 5705 keying material export plus the RFC 5764 SRTP split. DTLS-SRTP uses the **no-context** seed form: passing an empty slice appends a 2-byte zero and silently breaks interop.
