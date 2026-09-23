# LLD: zix.Http3

Internal implementation details for the HTTP/3 (QUIC) layer. For design rationale see [`docs/hld-http3-en.md`](hld-http3-en.md).

The engine is layered, and each file's `//!` doc comment tags its layer: C (crypto bottom), Q (QUIC transport), T (TLS-over-QUIC glue), P (QPACK), L (loss recovery), H (HTTP/3 semantics). Every deterministic module is proven byte-exact against the RFC worked examples in its in-file tests.

---

## Layer C: crypto.zig

The deterministic crypto bottom of the QUIC stack (RFC 9001). Pure functions plus one usage-accounting struct, no connection state.

- `initial_salt` (RFC 9001 5.2) and `initialSecrets(dcid)`: HKDF-Extract(salt, ikm=dcid), then `expandLabel` with `"client in"` / `"server in"` to split the client and server Initial secrets.
- `expandLabel(out, secret, label, context)`: the TLS 1.3 HKDF-Expand-Label form (RFC 8446 7.1), the `"tls13 "` prefix plus the label.
- `AesKeys { key: [16]u8, iv: [12]u8, hp: [16]u8 }` with `fromSecret`: derives the packet key, IV, and header-protection key via the `"quic key"` / `"quic iv"` / `"quic hp"` labels (RFC 9001 5.1). `ChaChaKeys` is the wider ChaCha20 sibling (implemented, not wired).
- `aeadNonce(iv, packet_number)`: XOR the packet number into the low bytes of the IV (RFC 9001 5.3).
- `headerMaskAes(hp, sample)`: the header-protection mask, AES-ECB(hp, sample) (RFC 9001 5.4.1). `headerMaskChaCha` is the ChaCha20 form (not wired).
- Deferred but tested: `retryTag` / `retryKeyNonce` (Retry integrity, RFC 9001 5.8), `nextKeyUpdateSecret` (key ratchet, 6.1), `KeyUsage` with `confidentialityLimit` / `integrityLimit` (AEAD usage limits, 6.6).

The live path is AES-128-GCM only.

---

## Layer Q: the QUIC transport

### varint.zig

QUIC variable-length integers (RFC 9000 section 16). The top two bits of the first byte give the base-2 log of the length (1 / 2 / 4 / 8 bytes), the rest is the value in network order.

- `Varint { value: u64, len: usize }`, `read(data)` decodes, `write(out, value)` encodes at the minimal length (`encodedLen` picks it), setting the `0x00` / `0x40` / `0x80` / `0xc0` prefix bits.

### packet.zig

Long / short header parsing and packet numbers (RFC 9000 section 17).

- `parseLongHeader(data)`: validates the Header Form bit, the Fixed Bit (MUST be 1, else discard), reads the 4-byte version, DCID and SCID (each length capped at 20), and returns `packet_type` (0 = Initial, 2 = Handshake) plus the leftover `rest`.
- `decodePacketNumber(largest_pn, truncated_pn, pn_nbits)`: RFC 9000 Appendix A.3 packet number reconstruction. Computes `expected = largest_pn + 1`, a half-window around it, and the candidate `(expected & ~mask) | truncated_pn`, then adjusts by one window if the candidate falls outside the half-window. The window comparison is done in signed `i128`, not `u64`, so a small packet number does not underflow. This is the correctness fix that let connections survive past the first packet-number wrap.
- `packetNumberLength`, `ShortHeader`, and `parseShortHeader` are the full-RFC reference (implemented and tested). The live path uses a simpler inline packet-number-length rule on send and parses the short header inline in `protection.zig`.

### frame.zig

QUIC transport frame parsing (RFC 9000 sections 12 / 19).

- `parseFrame(data)` reads one frame: `0x00` PADDING (coalesces a run of zeros), `0x01` PING, `0x06` CRYPTO (offset + length + data), `0x07` NEW_TOKEN (validated, non-empty), `0x08..0x0f` STREAM (the OFF / LEN / FIN bit-flag scheme). An unknown frame type is a `FrameEncodingError`.
- `Space` (initial / handshake / zero_rtt / one_rtt) and `framePermittedIn` model the RFC 9000 Table 3 per-space permission matrix. Implemented and tested, not enforced on the serve path yet.

This file is QUIC-transport frames only. ACK lives in `flow.zig`, close frames in `close.zig`, HTTP/3 frames in `h3.zig` / `response.zig`.

### flow.zig

Flow control, ACK, and path validation (RFC 9000 4 / 19.3 / 19.17).

- `FlowLimit { limit, used }`: `consume(end)` raises `FlowControlError` past the limit, `advertise(new_limit)` only ever increases.
- `parseAck(data, ack_delay_exponent)`: parses ACK type 0x02 / 0x03 (0x03 carries ECN counts), resolving the relative range encoding (smallest = largest - range, next largest = previous smallest - gap - 2) into absolute inclusive `Range`s, and decodes the delay with the ack-delay exponent.
- `parsePathData` / `pathValidates`: PATH_CHALLENGE / PATH_RESPONSE echo (implemented, not yet driven by the migration path).

Incoming MAX_DATA (0x10) / MAX_STREAM_DATA (0x11) frames (the client's grants for the server's replies) are applied in `dispatch/common.zig` (`applyStreamCredit`). The outgoing grants (the server rolling its own one-time handshake budgets forward) live in `connection.zig`: `replenishBidiStreams` for the MAX_STREAMS stream-count credit and `replenishMaxData` for the MAX_DATA byte credit, fed by `request.zig` (`streamBytes`) and encoded by `response.zig` (`buildMaxStreams` / `buildMaxData`). The per-stream grant is `reassembly.PendingStream.replenishStreamData`, encoded by `buildMaxStreamData` (0x11) and sent while a request is still arriving: nothing else would carry it, since a held request has no reply yet.

### stream.zig (deferred)

Stream id namespace and send / receive state machines (RFC 9000 2 / 3 / 5.1.1), plus a connection-id pool with `active_connection_id_limit`.

- `streamType(id)` by `id & 0x03`: client_bidi (0), server_bidi (1), client_uni (2), server_uni (3).
- `sendTransition` / `recvTransition`: the Figure 2 / Figure 3 state machines as pure transition functions (a `null` result is an illegal event).
- `ConnIdPool` and `parseNewConnectionId`: CID pooling for migration.

Implemented and unit-tested, not wired into the serve path (the v1 engine does not migrate or pool CIDs). NEW_CONNECTION_ID is currently skipped when parsing requests.

### close.zig

Connection close, stateless reset, and anti-amplification (RFC 9000 19.19 / 10.2 / 10.3 / 8.1).

- `parseConnectionClose`: type `0x1c` (QUIC, carries a Frame Type field) or `0x1d` (application, no Frame Type).
- `CloseState` (open / closing / draining / closed) and `closeTransition(state, event)`: the RFC 9000 10.2 termination state machine. `maySendInState` is false for draining.
- `AntiAmplification { received, sent, validated }`: `maySend(bytes)` is `validated or sent + bytes <= 3 * received`, the 3x cap before address validation (RFC 9000 8.1). `initialDatagramValid(size)` enforces the 1200-byte client Initial floor.
- `isStatelessReset` / `resetSizeAllowed`: stateless-reset detection and its own amplification guard.

---

## Layer T: TLS over QUIC

### keyschedule.zig

The QUIC handshake key schedule (RFC 8446 7.1 secret tree + RFC 9001 5.1 quic labels). Reuses `src/tls/key_schedule.zig` (`Transcript`, `HkdfSha256`, `deriveSecret`) for the TLS 1.3 machinery, then layers the QUIC per-level key derivation on top via `crypto.AesKeys.fromSecret`.

- `handshakeKeys(shared, transcript_hash)`: `early = Extract(0, 0)`, `derived = deriveSecret(early, "derived", "")`, `handshake_secret = Extract(derived, shared)`, then `"s hs traffic"` / `"c hs traffic"` traffic secrets, returning `HandshakeKeys { server, client, handshake_secret, server_traffic, client_traffic }`.
- `applicationKeys(handshake_secret, transcript_through_finished)`: the 1-RTT master secret and `"s ap traffic"` / `"c ap traffic"` application secrets, returning `AppKeys { server, client }`.

### tls.zig (glue, partly deferred)

The join between the TLS 1.3 handshake and QUIC (RFC 9001 section 4): the handshake messages ride CRYPTO frames, not TLS records.

- `CryptoStream { buf: [4096]u8, present: [4096]bool }`: reassembles CRYPTO frames by offset (`insert`, `readableLen`, `readable`), idempotent on overlap / duplicate. This is live (the Initial-level stream lives on the `Connection`).
- `quicKey`, `clientInitialSecret`, `tlsVersionAcceptable`, `InitialKeys` (the 4.9.1 Initial-key discard tracker), and `ZeroRttPolicy` (0-RTT rejected by default) are implemented and tested but not yet gating the serve path.

### serverhello.zig

ServerHello generation, the start of the server send path.

- `buildServerHelloInitial(...)`: from the parsed ClientHello, run the server side of X25519 ECDHE, `handshake.negotiate` + `handshake.serializeServerHello` (reusing `src/tls`), wrap the ServerHello in a CRYPTO frame at offset 0, and `protection.sealInitial` it. Updates the transcript with ClientHello + ServerHello and derives Handshake keys via `keyschedule.handshakeKeys`. Returns the packet bytes plus the ECDHE shared secret. Handles the common X25519 path (curl's default).

### flight.zig

The server's Handshake-level TLS flight.

- `encodeTransportParams(...)`: the QUIC transport parameters (RFC 9000 18.2): `original_destination_connection_id` (0x00) and `initial_source_connection_id` (0x0f) carry the client's first DCID and the server SCID byte-exact (curl validates them), plus `max_idle_timeout` (0x01), `initial_max_data` (0x04), the three `initial_max_stream_data_*` (0x05 / 0x06 / 0x07), and `initial_max_streams_bidi` / `_uni` (0x08 / 0x09).
- `buildEncryptedExtensions(...)`: EncryptedExtensions with the ALPN `h3` extension and the `quic_transport_parameters` extension (0x0039), hand-built here because QUIC needs both, which the TLS record layer omits.
- `buildHandshakeFlight(...)`: EncryptedExtensions + `certificate.buildCertificate` + `buildCertificateVerify` + `buildFinished` (from `src/tls/certificate.zig`), each fed into the transcript, wrapped in one CRYPTO frame and sealed with the Handshake keys (`protection.sealHandshake`).

### transport_params.zig

Client transport parameter parsing (RFC 9000 18). The server must respect the limits the client advertises before sending.

- `parse(ext_body)` walks the varint-framed (id, length, value) entries and pulls out the four the response path needs: `initial_max_data` (0x04), `initial_max_stream_data_bidi_local` (0x05, the limit for the server's reply on the client-initiated bidi request stream), `ack_delay_exponent` (0x0a, default 3, clamped to 0..20), and `max_udp_payload_size` (0x03, floored at 1200). Every other parameter is skipped.
- `fromClientHello(client_hello)` finds the 0x0039 extension by manually walking the ClientHello structure.

---

## protection.zig: packet protection (open + seal)

Removes / applies header protection and AEAD, the inverse pair around the packet number (RFC 9001 5.3 / 5.4). AES-128-GCM throughout.

Open (receive):
- `openInitial` (packet_type 0), `openHandshake` (packet_type 2), `openShort` (1-RTT). Each samples 16 ciphertext bytes at `pn_offset + 4`, computes the mask with `crypto.headerMaskAes`, unmasks the first byte (low 4 bits for a long header, low 5 for a short header) and the packet-number bytes, builds the nonce, and AEAD-decrypts with the unprotected header as associated data. `openShort` reconstructs the packet number with `packet.decodePacketNumber` when a `largest_pn` is tracked, else uses the truncated wire value (the first packet has no prior largest).
- A long-header packet ends where its Length field says it does, not at the end of the datagram (`packet.longPacketBounds`): a client is free to write more after its Initial (a coalesced packet, or the padding it adds to reach the 1200-byte floor), and reading the AEAD tag from the datagram's end authenticates the wrong bytes and fails on every such client. A short header has no Length field, so its packet runs to the end of the datagram and is always the last one in it (RFC 9000 12.2).

Seal (send):
- `sealInitial`, `sealHandshake`, `sealShort`: build the header, sample and mask, AEAD-encrypt. `short_seal_overhead_max` bounds the 1-RTT overhead (`1 + 20 + 4 + tag_length`).

---

## Layer P: QPACK header compression

### qpack.zig (live, static-only)

QPACK static-table field lines (RFC 9204). A static-only field section uses a Required-Insert-Count-0 / Base-0 prefix (two zero bytes).

- `decodePrefixedInt` / `encodePrefixedInt`: the RFC 7541 5.1 prefixed integer every representation rides on.
- `static_table`: the leading 44 entries (indices 0..43) of RFC 9204 Appendix A, covering the pseudo-headers plus common fields (`:method` GET/POST/etc. at 17..21, `:status` 200/304/404/503 at 25..28, `:path` at 1, `:authority` at 0), and the content-negotiation entries used by the serve path: `accept-encoding` (index 31, request input) and `content-encoding` br / gzip (indices 42 / 43, response output).
- `decodeIndexedFieldLine` (RFC 9204 4.5.2) and `decodeLiteralNameRef` (4.5.4) for decode, `encodeStaticIndexedFieldLine` for encode.
- `StreamRegistry`: the at-most-one encoder / decoder stream check (implemented, not enforced yet).

### qpack_dynamic.zig (deferred)

The dynamic table and decoder-stream instructions (RFC 9204 3.2 / 4.4). `DynamicTable` (append-with-eviction, 32-byte per-entry overhead, `setCapacity`), the Required-Insert-Count / Base transform, and the Section Acknowledgment / Stream Cancellation / Insert Count Increment decoder instructions, plus the QPACK error codes. Fully implemented and unit-tested, not wired: there is no non-zero dynamic-capacity config, so the live path is static-only.

### huffman.zig (live)

The RFC 7541 Appendix B Huffman decoder QPACK shares with HPACK, used for string literals (a request `:path` arrives Huffman-encoded).

- `decode(out, input)`: walks the bitstream MSB-first, emitting a symbol the moment the accumulated bits match a code of that exact length. The 256-symbol code table is bucketed and sorted by bit length in a comptime block (`HuffmanIndex`), so decode only scans the bucket for the current bit length. Trailing all-ones bits are EOS padding, ignored. Returns `null` on output overflow or an unresolvable code past 30 bits. The live decode is invoked from `dispatch/common.zig` (`decodePath`) into the connection's `path_scratch` when the request carries the Huffman flag.

---

## Layer H: HTTP/3 semantics

### request.zig (live)

Decodes a request out of a decrypted 1-RTT payload.

- `parseRequests(payload, out)`: scans for client-initiated bidi STREAM frames (`stream.id & 0x03 == 0`), decoding each in arrival order up to `max_requests_per_packet` (96). `parseRequest` returns the first.
- `decodeRequestStream` walks the HTTP/3 frames inside the stream data for the first HEADERS frame (type 0x01), and `decodeHeaders` QPACK-decodes the field section, reading the RIC / Base prefix and then indexed or literal-name-ref field lines. It captures `:method` and `:path` (the pseudo-headers, first) and `accept-encoding` (a regular field, so the scan continues past the pseudo-headers to reach it), stopping once all three are in hand.
- The walk continues past HEADERS for the DATA frames (type 0x00) that carry the request body. The first one is kept as `body` (a slice into the payload, no copy) and every one of them is counted into `body_received`, so a body split across frames is delivered in part and reported short rather than silently truncated. DATA before HEADERS is refused (H3_FRAME_UNEXPECTED), a trailing field section ends the walk, and a malformed or truncated frame after HEADERS ends it too: the request line still answers, the body is simply not marked whole.
- `FrameWalk` is that walk, shared so both decodes agree on what a frame is and when a frame ran past the bytes that arrived. `decodeAssembledRequest(stream_data, ended)` is the second decode: given a buffer the caller owns, it moves each DATA payload up behind the previous one so a body written as several DATA frames becomes one slice. Every payload moves backwards by at least the frame header it leaves behind, so the move never overwrites a byte the walk has not read. The read-only decodes cannot do this, since the decrypted packet payload is walked again afterwards for flow-control accounting.
- `DecodedRequest { method, path, path_huffman, accept_encoding, accept_encoding_huffman, body, body_received, body_complete }` carries the Huffman flags through, expanded later by `decodePath` / `decodeAcceptEncoding`, and `dispatch/common.buildRequest` maps the whole set onto the handler's `core.Request`.
- `body_complete` is decided in two halves: `decodeRequestStream` vouches that the frames read out whole and that `body` holds every byte counted, and the caller adds what only the STREAM frame knows, the FIN bit at offset 0 (`ParsedStream` carries both). A client that has not ended its stream never reports a whole body.
- `parseStreamPieces(payload, out)` is what the serve path walks: every client bidi STREAM frame with its offset, its FIN bit, its raw bytes, and a decoded request when the bytes start the stream. A frame past offset 0 is a continuation, the body of a request whose head arrived in an earlier packet, and decodes to no request on its own. `parseRequests` is the same walk keeping only the heads. `decodeStreamRequest(stream_data, ended)` decodes either shape: one packet's stream bytes, or bytes reassembled across packets.

### reassembly.zig (live)

Holds a request whose client has not finished sending it. A client with a body commonly writes its HEADERS frame in one packet and its DATA frame in the next (curl does), so answering the head would run the handler with an empty body and let the real body arrive after the response.

- `Pool.feed(now_us, cid, stream_id, offset, data, fin)` returns `ready` with the assembled stream, `waiting` with the slot holding it, or `refused`. Bytes go in at their stream offset with a bitset of which have arrived beside them and only the contiguous prefix is read, so a reordered or retransmitted frame is harmless and a gap holds the request back. This is the shape `tls.CryptoStream` uses for a ClientHello that spans two packets.
- `Pool.init(allocator, streams, stream_bytes)` sizes it from the server config (`max_pending_request_streams`, `max_request_stream_bytes`), and each worker loop owns one for its life beside its connection table. Worker-owned, not per-connection: per connection it would have been paid 256 times over, once for every eagerly allocated slot in the connection table, for something only a handful of requests use at any moment. `streams` of 0 opens a pool that holds nothing and costs nothing.
- A slot is reclaimed once nothing has fed it for `stale_us` (2 seconds), so a client that opens a request and stops does not hold one for the worker's life. `open` prefers a free slot, then a stale one, then (only for a frame carrying a request head) a slot holding nothing usable: after a burst of refusals the clients whose heads were refused keep sending bodies, and those orphan fragments would otherwise fill every slot and lock the pool out of serving anything.
- `replenishStreamData(window)` keeps the client's per-stream credit ahead of what it has sent (RFC 9000 4.2), the per-stream twin of `Connection.replenishMaxData`. A held request has no reply to carry a MAX_STREAM_DATA, so without this an upload larger than the handshake allowance (`flight.initial_max_stream_data`, 256 KiB) stops halfway: the client waits for credit, the engine waits for the rest of the request, and neither moves until the connection times out.
- `dispatch/common.takeReadyRequest` is the policy on top: a request that arrived whole in one packet is served straight from the decrypted payload with no copy and no slot (every GET, and every POST a client wrote in one go), anything else is held, and a held request is served the moment its stream ends. A body past `max_request_stream_bytes` is served cut, with `slot.dropped` folded into `body_received` and `body_complete` forced false. A request head with no slot to assemble it in is answered 503, never run against a body the engine knows it is missing.

### response.zig (live)

Serializes a full 1-RTT QUIC payload.

- `buildResponse(...)` assembles, in order: an optional ACK frame (`buildAck` / `buildAckRanges`), an optional HANDSHAKE_DONE (0x1e), an optional server control stream (stream id 3) carrying the stream-type byte 0x00 plus an empty SETTINGS frame `{0x04, 0x00}`, an optional MAX_STREAMS (`buildMaxStreams`, type 0x12), an optional MAX_DATA (`buildMaxData`, type 0x10), then the request-stream content, and optionally an application CONNECTION_CLOSE (0x1d, H3_NO_ERROR = 0x0100).
- `buildRequestStreamContent`: an HTTP/3 HEADERS frame (type 0x01) with a static-only QPACK prefix (RIC 0 / Base 0) plus the indexed `:status` line (`statusFieldLine` maps 103/200/304/404/503 to static indices 24..28, one byte each, and spells any other status out as a literal field line borrowing the `:status` name from entry 24, so a 413 or a 500 reaches the client as itself rather than as the index for 200) and, when the handler set one, an indexed `content-encoding` line (`contentEncodingFieldLine` emits static index 42 for br / 43 for gzip, nothing for identity), followed by a DATA frame (type 0x00) with the body, wrapped in a STREAM frame with FIN. `buildStreamPrefix` (the large-body path) takes the same `content_encoding`, so a resumed multi-packet body keeps its header. The engine emits the field but never compresses: the handler owns the coded body.

### static.zig (live)

The `public_dir` fallback (ADR-064), called from `Router.dispatch` after every route misses and before the 404. `serve(req, res, ctx, req_path) bool` rejects `..`, asks the shared cache for a snapshot of the resolved file, sets the content type and coding, calls `res.send(snapshot)`, and records the pinned slot on `ctx.static_slot`. It returns false (so the router sends its 404) for a traversal attempt, an absent file, a file past `SNAPSHOT_MAX_BYTES`, a full cache table, or no cache installed at all.

Unlike the other engines there is no uncached fallback path, because there is no other body source that outlives the handler. `releasePin(slot)` is the counterpart the engine calls when the body is finished with, and it accepts a null slot so callers need no guard.

`core.invokeHandler` RETURNS `ctx.static_slot` rather than releasing it, since the handler call ends long before the body does. `dispatch/common.sendResponseFD` then owns the pin and releases it down whichever of three paths the response takes: immediately when the whole response fitted one packet (its bytes are already copied into the packet), immediately when no send-stream slot was free (the body will never be sent, so nothing will retire it later), or by handing it to `SendStream.static_slot` for the pump to hold until the last range is acknowledged.

### h3.zig (deferred)

The full HTTP/3 framing and semantics (RFC 9114): the `FrameType` enum (data 0x00, headers 0x01, cancel_push 0x03, settings 0x04, push_promise 0x05, goaway 0x07, max_push_id 0x0d), the control-stream `settings-first` state machine (`ControlStream`), the request frame-order state machine (`requestFrameTransition`), full message validation (`validateMessage`: lowercase names, pseudo-header ordering, mandatory / prohibited pseudo-headers, Content-Length vs DATA sum), GOAWAY / MAX_PUSH_ID monotonicity trackers, and the 17 HTTP/3 error codes plus the grease range. Implemented and unit-tested, not wired: the live request path handles the minimal framing inline in `dispatch/common.zig`.

---

## connection.zig: per-connection state

`Connection` ties the layers together: the Initial keys, the CRYPTO reassembly stream, the RTT estimator and congestion controller, the anti-amplification budget and close state, and the HTTP/3 control stream. It is fixed-size (no per-packet heap), stored inside the CID table slot.

Handshake phase is tracked by flags set on the send path (in `dispatch/common.zig`) rather than a single enum: `server_hello_sent`, `handshake_ready` (Handshake keys derived), `app_ready` (1-RTT keys derived), then `close_state`.

Key fields and methods:
- `dcid`, `our_scid`, `peer_scid`, `peer_addr` (overwritten per received datagram, so a 4-tuple change transparently retargets sends), `initial_client` / `initial_server`, `hs_keys`, `app_keys`, `handshake_transcript`.
- `AckTracker { largest_pn, received_mask: u64 }`: a 64-bit sliding bitmask of received packet numbers (bit 0 = largest), so the server emits honest ACK ranges.
- `SendStream` (up to 64 per connection): a response body streamed across packets (`stream_id`, `body`, `content_encoding`, `sent`, `high_water`, `unacked`, `stream_limit`, `static_slot`). The prefix is rebuilt per packet, so `content_encoding` is stored to keep the `content-encoding` header consistent across a resumed body. `static_slot` is the static cache pin backing `body` when the response came from `public_dir` (null for a handler-produced body, which owns its own lifetime).
- `releaseStaticPin(stream)` / `releaseAllStaticPins()`: hand a retired stream's cache pin back so the entry can expire. The first is idempotent by clearing the slot, since a stream can retire down more than one path (acknowledged, or abandoned when the connection goes away). Releasing while the pump could still read `body` would let the mapping be torn down under it, so both are called only where the stream is provably finished with: `onAckFrame` when a stream completes, and `sweepMaintenance` when a connection goes idle.
- `SentRange` ring (128 entries): the loss-detection log. `recordSentRange` overwrites the oldest slot, decrementing `bytes_in_flight` and the owning stream's `unacked` first if it was still in flight (prevents a leak / truncation).
- `replenishBidiStreams(highest_bidi_id, window)`: the rolling MAX_STREAMS credit. Tracks the client's highest request stream, and once it has used more than half the current window, raises the cumulative grant to `high_water + window` and returns the new value (else `null`), so the connection never stalls once the initial allowance is spent.
- `replenishMaxData(bytes_received, window)`: the rolling MAX_DATA credit, the byte twin of the stream-count credit above. Accumulates the STREAM-frame payload bytes each packet carried (`request.streamBytes`, all streams, since connection-level flow control counts them all) and, once consumption crosses half the current window, raises the cumulative grant to `consumed + window` and returns the new value (else `null`). Without it the connection deadlocks once the client has sent `initial_max_data` bytes of requests, whatever stream credit remains. Retransmitted bytes may be counted twice, which only grants credit early (a grant is a limit, so overshooting is harmless while undershooting stalls the peer).
- `onAckFrame(ack, now_us)`: samples RTT from the packet matching `ack.largest`, retires acked ranges, credits `cc.onAckedBytes`, resets the PTO backoff, and declares loss for still-outstanding earlier ranges (`recovery.packetLost`), rewinding those streams and calling `cc.onCongestionEvent()` once per ACK if any loss occurred.
- `onMaintenance(now_us, max_idle_us)`: the time-driven sweep. On Probe Timeout it declares outstanding ranges lost and rewinds the streams for retransmission, but does NOT cut the congestion window (a PTO is not a congestion signal, RFC 9002 6.2). Loss never evicts a connection. It reports `idle = true` only on idle-timeout silence or a `draining` / `closed` close state (a received CONNECTION_CLOSE evicts promptly).

---

## Layer L: recovery.zig

Sender-side loss detection and congestion control (RFC 9002). Integer microseconds and integer bytes throughout, so every value is exact.

- `RttEstimator.onSample`: the RFC 9002 5.1..5.3 EWMA (`smoothed = (7*smoothed + adjusted)/8`, `rttvar = (3*rttvar + |smoothed - adjusted|)/4`), with the ack-delay adjustment.
- `packetLost`: lost when `largest_acked - packet_number >= 3` (the reordering threshold) or the time-since-sent passes `lossTimeThreshold` (`9/8 * max(smoothed, latest)`, floored at the 1ms granularity).
- `computePto` (`smoothed + max(4*rttvar, granularity) + max_ack_delay`) and `ptoWithBackoff` (`base << backoff`, capped at a 64x backoff).
- `CongestionController` (NewReno): `congestion_window` starts at `max(config initial window, 2 * max_datagram_size)`, `onAckedBytes` grows it (slow start adds the acked bytes, congestion avoidance adds `mds * acked / cwnd`), `onCongestionEvent` halves it into `ssthresh`, `onPersistentCongestion` collapses it to the minimum. The window bounds `pumpStream` against `bytes_in_flight`.

---

## demux.zig: the connection-id table

A QUIC connection is keyed by its Destination Connection ID, not by a socket.

- `ConnId { bytes: [20]u8, len: u8 }` with `fromSlice` (truncates to 20) and `eql`.
- `Table(T, capacity)`: a fixed-capacity store (no allocation, returns null on overflow) with an embedded open-addressing hash index (load factor 0.5, Wyhash-keyed, tombstone deletion) for O(1) find, so a per-packet demux does not cost a linear scan. `put` inserts, `find` looks up, `addAlias` adds a second key resolving to an existing slot (used to alias the server SCID onto the connection after ServerHello), `remove` tombstones every bucket pointing at the slot.
- Production instance: `demux.Table(Connection, 256)`, one per worker, heap-allocated. A new connection is created when a long-header Initial packet (packet_type 0) arrives for an unknown DCID.

The v1 engine's `.ASYNC` model runs one worker that owns the whole table, so a connection migration (a 4-tuple change) is just a new peer address on an existing CID, with no cross-core routing.

---

## server.zig and dispatch/

`Server.init(handler, config)` (server.zig) is a thin facade: `init` stores the config, `run` validates (`error.ZixPortNotConfigured` on a zero port, `error.ZixTlsRequired` on a null TLS context) then switches on `config.dispatch_model` into the per-model `dispatch/` entry point. All models are Linux-only.

- `dispatch/common.zig`: the shared machinery. `workerLoop` (recvmmsg in, `serveDatagram` per datagram, sendmmsg out), `runSingle` (one worker on the calling thread, ASYNC). `serveDatagram` walks the packets one datagram carries (RFC 9000 12.2): a long header says where its packet ends, a short header runs to the end of the datagram and is therefore last, and trailing bytes whose Fixed Bit is clear (the padding a client adds to reach the 1200-byte floor) stop the walk. `servePacket` then runs one packet: `processDatagram` demuxes by DCID and decrypts (`openInitial` / `openHandshake` / `openShort`). `serveDatagram` drives the matching step: `sendServerHello` on a complete ClientHello, or `sendResponse` on a 1-RTT request. `sendResponse` applies ACKs (feeding `onAckFrame`), parses requests, replenishes bidi stream credit and the connection-wide byte credit (charging the packet's stream bytes via `streamBytes` into `replenishMaxData`), coalesces the ACK + HANDSHAKE_DONE + SETTINGS + MAX_STREAMS + MAX_DATA + small responses into one sealed packet (a `COALESCE_PAYLOAD_MAX` budget), registers oversized bodies as `SendStream`s, and `pumpStream`s each active stream within the congestion window (a due grant not yet sealed rides the first pumped packet, like the ACK). `sweepMaintenance` runs `onMaintenance` per connection at a bounded interval, retransmitting PTO-expired flights and evicting idle / closed connections, calling `releaseAllStaticPins` before the eviction so a body abandoned mid-flight does not pin its cache entry for the life of the process.
- `dispatch/async.zig`, `pool.zig`, `mixed.zig`: thin wrappers into `runSingle` / `runMulti`.
- `dispatch/epoll.zig`: `workerLoopEpoll`, an epoll readiness loop draining to EAGAIN on the same per-core shape, calling the shared `serveDatagram` / `sweepMaintenance`. It arms an epoll timeout so the maintenance sweep runs during an I/O lull.
- `dispatch/uring.zig`: `workerLoopUring`, a real io_uring completion loop (multishot recv on a provided buffer ring when available, else a pool of one-shot recv SQEs), with a double-buffered send path so sends never block the loop. Folds to `epoll.workerLoopEpoll` per-worker when io_uring init fails.

Binding is `datagram.open(ip, port, reuse)` from `src/udp/datagram.zig`, `reuse = true` (SO_REUSEPORT) for the per-core models so several workers share the port.

---

###### end of lld-http3
