//! Minimal hand-rolled HTTP/3 (QUIC over TLS 1.3) client for the test runners.
//!
//! What:
//! - zix ships an HTTP/3 server but no QUIC client, so this drives the peer side of the wire from the
//!   exported zix.Http3 primitives (crypto / protection / keyschedule / qpack / packet / varint /
//!   frame) plus the TLS 1.3 handshake bytes. This mirrors how the HTTP/2 runner hand-rolls a client
//!   from zix.Http2 frame and HPACK primitives.
//! - It performs one full round trip: send Initial(ClientHello), receive ServerHello + the server
//!   Handshake flight, derive the handshake then 1-RTT keys, send the request on stream 0, and return
//!   the decrypted response body. It is built against THIS server: a plain request needs only
//!   :method + :path, so the request itself is minimal.
//! - It carries the WebTransport over HTTP/3 path as well, which the test-runner-webtransport step
//!   drives: the client's SETTINGS advertise the surface a session needs, an extended CONNECT opens one
//!   on stream 0, a bidirectional data stream carries the 0x41 signal value, the session id and a
//!   payload, and one datagram goes each way inside a QUIC DATAGRAM frame.
//!
//! Note:
//! - A WebTransport session does read the client's transport parameters, unlike a plain request: the
//!   streams the server opens are bounded by initial_max_stream_data_bidi_remote (0x06) and
//!   initial_max_stream_data_uni (0x07), and max_datagram_frame_size (0x20) is what permits a DATAGRAM
//!   frame at all. The session request is refused without 0x20 and SETTINGS_H3_DATAGRAM (draft-16 3.1).
//! - The session uses the draft-ietf-webtrans-http3-16 token `webtransport-h3`. The deployed draft-07
//!   token `webtransport` opens the same session on this server, and the draft-16 one is used here
//!   because it is the revision the engine's session settings and flow control capsules belong to.

const std = @import("std");
const zix = @import("zix");
const socket_poll = zix.utils.socket_poll;

const h3 = zix.Http3;
const crypto = h3.crypto;
const protection = h3.protection;
const keyschedule = h3.keyschedule;
const qpack = h3.qpack;
const packet = h3.packet;
const varint = h3.varint;
const tls_key_schedule = h3.tls_key_schedule;
const X25519 = std.crypto.dh.X25519;

const BIND_PORT: u16 = 9195;
const CID_LEN: usize = 8;
const INITIAL_MIN: usize = 1162; // pad the client Initial payload so the packet clears QUIC's 1200 floor.

/// The largest DATAGRAM frame this client accepts (RFC 9221 3, transport parameter max_datagram_frame_size).
/// The recommended value: it accepts any datagram that fits one QUIC packet, and it is the parameter a
/// WebTransport session requires before a server will send or accept one (draft-16 3.1).
const DATAGRAM_FRAME_SIZE: u64 = 1200;

// --------------------------------------------------------- //

/// A tiny big-endian TLS writer: enough to serialize a ClientHello by hand (the TLS layer has no
/// public ClientHello builder that carries no transport params).
const Writer = struct {
    buf: []u8,
    pos: usize = 0,

    fn writeU8(self: *Writer, value: u8) void {
        self.buf[self.pos] = value;
        self.pos += 1;
    }

    fn writeU16(self: *Writer, value: u16) void {
        std.mem.writeInt(u16, self.buf[self.pos..][0..2], value, .big);
        self.pos += 2;
    }

    fn bytes(self: *Writer, data: []const u8) void {
        @memcpy(self.buf[self.pos..][0..data.len], data);
        self.pos += data.len;
    }

    /// Reserve a u16 length slot, returning its offset for a later patch.
    fn placeU16(self: *Writer) usize {
        const slot = self.pos;
        self.pos += 2;

        return slot;
    }

    /// Back-patch a u16 length slot with the bytes written since it was reserved.
    fn patchU16(self: *Writer, slot: usize) void {
        std.mem.writeInt(u16, self.buf[slot..][0..2], @intCast(self.pos - slot - 2), .big);
    }

    /// Reserve a u24 length slot (the TLS handshake message length), returning its offset.
    fn placeU24(self: *Writer) usize {
        const slot = self.pos;
        self.pos += 3;

        return slot;
    }

    /// Back-patch a u24 length slot with the bytes written since it was reserved.
    fn patchU24(self: *Writer, slot: usize) void {
        const len: u24 = @intCast(self.pos - slot - 3);
        self.buf[slot] = @intCast(len >> 16);
        self.buf[slot + 1] = @intCast((len >> 8) & 0xff);
        self.buf[slot + 2] = @intCast(len & 0xff);
    }
};

/// Serialize a minimal TLS 1.3 ClientHello (RFC 8446 4.1.2) offering AES_128_GCM_SHA256, X25519, and
/// ECDSA-P256 signatures, with our X25519 key share, ALPN h3, and the quic_transport_parameters
/// extension RFC 9001 3 requires of every QUIC endpoint. The zix h3 engine serves a client that
/// omits them, a server that honours the client's flow-control limits cannot: with no limits
/// announced, it has no credit to send a response with.
fn buildClientHello(buf: []u8, client_random: [32]u8, x25519_pub: [32]u8, scid: []const u8) []const u8 {
    var writer = Writer{ .buf = buf };

    writer.writeU8(0x01); // CLIENT_HELLO
    const body = writer.placeU24(); // handshake message length

    writer.writeU16(0x0303); // legacy_version TLS 1.2
    writer.bytes(&client_random);
    writer.writeU8(0x00); // empty session_id

    writer.writeU16(0x0002); // cipher_suites length
    writer.writeU16(0x1301); // TLS_AES_128_GCM_SHA256

    writer.writeU8(0x01); // compression methods length
    writer.writeU8(0x00); // null compression

    const exts = writer.placeU16();

    writer.writeU16(0x002b); // supported_versions
    const versions_ext = writer.placeU16();
    writer.writeU8(0x02); // list length
    writer.writeU16(0x0304); // TLS 1.3
    writer.patchU16(versions_ext);

    writer.writeU16(0x000a); // supported_groups
    const groups_ext = writer.placeU16();
    writer.writeU16(0x0002); // list length
    writer.writeU16(0x001d); // X25519
    writer.patchU16(groups_ext);

    writer.writeU16(0x000d); // signature_algorithms
    const sigalgs_ext = writer.placeU16();
    writer.writeU16(0x0002); // list length
    writer.writeU16(0x0403); // ECDSA_SECP256R1_SHA256
    writer.patchU16(sigalgs_ext);

    writer.writeU16(0x0033); // key_share
    const kshare = writer.placeU16();
    writer.writeU16(0x0024); // client_shares length (2 + 2 + 32)
    writer.writeU16(0x001d); // X25519
    writer.writeU16(0x0020); // key_exchange length 32
    writer.bytes(&x25519_pub);
    writer.patchU16(kshare);

    writer.writeU16(0x0010); // application_layer_protocol_negotiation
    const alpn = writer.placeU16();
    writer.writeU16(0x0003); // protocol list length
    writer.writeU8(0x02); // protocol name length
    writer.bytes("h3");
    writer.patchU16(alpn);

    writer.writeU16(0x0039); // quic_transport_parameters
    const params = writer.placeU16();
    var param_buf: [128]u8 = undefined;
    var param_len: usize = 0;
    param_len += varint.write(param_buf[param_len..], 0x0f); // initial_source_connection_id
    param_len += varint.write(param_buf[param_len..], scid.len);
    @memcpy(param_buf[param_len..][0..scid.len], scid);
    param_len += scid.len;
    putParam(&param_buf, &param_len, 0x04, 1 << 20); // initial_max_data
    putParam(&param_buf, &param_len, 0x05, 1 << 18); // initial_max_stream_data_bidi_local
    putParam(&param_buf, &param_len, 0x06, 1 << 18); // initial_max_stream_data_bidi_remote
    putParam(&param_buf, &param_len, 0x07, 1 << 18); // initial_max_stream_data_uni
    putParam(&param_buf, &param_len, 0x08, 8); // initial_max_streams_bidi
    putParam(&param_buf, &param_len, 0x09, 8); // initial_max_streams_uni
    putParam(&param_buf, &param_len, 0x20, DATAGRAM_FRAME_SIZE); // max_datagram_frame_size
    writer.bytes(param_buf[0..param_len]);
    writer.patchU16(params);

    writer.patchU16(exts);
    writer.patchU24(body);

    return writer.buf[0..writer.pos];
}

/// Append one varint-coded transport parameter (id, then its varint value).
fn putParam(buf: []u8, len: *usize, id: u64, value: u64) void {
    len.* += varint.write(buf[len.*..], id);

    var value_buf: [8]u8 = undefined;
    const value_len = varint.write(&value_buf, value);
    len.* += varint.write(buf[len.*..], value_len);
    @memcpy(buf[len.*..][0..value_len], value_buf[0..value_len]);
    len.* += value_len;
}

/// Parse a ServerHello's X25519 key_share value (RFC 8446 4.1.3). The layout is fixed by
/// serializeServerHello: KEY_SHARE is the first extension.
fn serverKeyShare(server_hello: []const u8) ?[32]u8 {
    // type(1) + len(3) + version(2) + random(32) + session_id_len(1) ...
    var pos: usize = 4 + 2 + 32;
    if (pos >= server_hello.len) return null;

    const session_id_len = server_hello[pos];
    pos += 1 + session_id_len;
    pos += 2 + 1; // cipher_suite(2) + compression(1)
    if (pos + 2 > server_hello.len) return null;

    pos += 2; // extensions length
    while (pos + 4 <= server_hello.len) {
        const ext_type = std.mem.readInt(u16, server_hello[pos..][0..2], .big);
        const ext_len = std.mem.readInt(u16, server_hello[pos + 2 ..][0..2], .big);
        pos += 4;
        if (pos + ext_len > server_hello.len) return null;

        if (ext_type == 0x0033) {
            // KEY_SHARE: group(2) + key_exchange_len(2) + key_exchange.
            if (ext_len < 4) return null;
            const ke_len = std.mem.readInt(u16, server_hello[pos + 2 ..][0..2], .big);
            if (ke_len != 32 or pos + 4 + 32 > server_hello.len) return null;

            var out: [32]u8 = undefined;
            @memcpy(&out, server_hello[pos + 4 ..][0..32]);

            return out;
        }

        pos += ext_len;
    }

    return null;
}

/// Return the data of the first CRYPTO frame in a decrypted Initial / Handshake payload. The server
/// seals exactly one CRYPTO frame (the ServerHello, or the EE+Cert+CertVerify+Finished flight) per
/// packet, so this is the whole TLS message stream at that level.
fn firstCryptoData(payload: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos < payload.len) {
        const ftype = varint.read(payload[pos..]) catch return null;
        pos += ftype.len;

        switch (ftype.value) {
            0x00, 0x01 => {}, // PADDING, PING
            0x06 => {
                const offset = varint.read(payload[pos..]) catch return null;
                pos += offset.len;
                const length = varint.read(payload[pos..]) catch return null;
                pos += length.len;
                const len: usize = @intCast(length.value);
                if (pos + len > payload.len) return null;

                return payload[pos .. pos + len];
            },
            else => return null,
        }
    }

    return null;
}

/// Walk a decrypted 1-RTT payload and copy every STREAM frame belonging to `stream_id` into
/// `assembly` at its own offset, growing the contiguous prefix in `covered`. The ACK /
/// HANDSHAKE_DONE / control-stream frames the server leads with are skipped.
///
/// Note:
/// - Assembling before parsing is what makes this a client rather than a guess: a server is free
///   to split one HTTP/3 frame across packets, so a chunk taken on its own may start in the middle
///   of a frame header. Chunks that would leave a gap are ignored, the server retransmits them.
fn collectStream(payload: []const u8, stream_id: u64, assembly: []u8, covered: *usize) void {
    var pos: usize = 0;
    while (pos < payload.len) {
        const ftype = varint.read(payload[pos..]) catch return;
        pos += ftype.len;

        switch (ftype.value) {
            0x00, 0x01, 0x1e => {}, // PADDING, PING, HANDSHAKE_DONE
            0x02, 0x03 => { // ACK
                pos = skipAck(payload, pos, ftype.value == 0x03) orelse return;
            },
            0x08...0x0f => {
                const parsed = parseStream(payload[pos - ftype.len ..]) orelse return;
                if (parsed.id == stream_id) absorb(parsed, assembly, covered);

                pos = (pos - ftype.len) + parsed.consumed;
            },
            else => return,
        }
    }
}

/// Copy one stream chunk into the assembly buffer at its offset. A chunk that starts past the
/// contiguous prefix is dropped: it would leave a hole this simple assembler cannot track.
fn absorb(parsed: ParsedStream, assembly: []u8, covered: *usize) void {
    const start: usize = @intCast(parsed.offset);
    if (start > covered.*) return;
    if (start + parsed.data.len > assembly.len) return;

    @memcpy(assembly[start..][0..parsed.data.len], parsed.data);

    const end = start + parsed.data.len;
    if (end > covered.*) covered.* = end;
}

const ParsedStream = struct { id: u64, offset: u64, data: []const u8, fin: bool, consumed: usize };

/// Parse one STREAM frame (RFC 9000 19.8) at the start of `buf`.
fn parseStream(buf: []const u8) ?ParsedStream {
    const frame_type = buf[0];
    var pos: usize = 1;

    const id = varint.read(buf[pos..]) catch return null;
    pos += id.len;

    var offset_value: u64 = 0;
    if (frame_type & 0x04 != 0) {
        const offset = varint.read(buf[pos..]) catch return null;
        offset_value = offset.value;
        pos += offset.len;
    }

    const length: usize = if (frame_type & 0x02 != 0) blk: {
        const len = varint.read(buf[pos..]) catch return null;
        pos += len.len;
        break :blk @intCast(len.value);
    } else buf.len - pos;
    if (pos + length > buf.len) return null;

    return .{ .id = id.value, .offset = offset_value, .data = buf[pos .. pos + length], .fin = frame_type & 0x01 != 0, .consumed = pos + length };
}

/// Walk the HTTP/3 frames of a request-stream payload and copy the first DATA frame's body into out.
fn httpDataBody(stream_data: []const u8, out: []u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos < stream_data.len) {
        const ftype = varint.read(stream_data[pos..]) catch return null;
        pos += ftype.len;
        const length = varint.read(stream_data[pos..]) catch return null;
        pos += length.len;

        const len: usize = @intCast(length.value);
        if (pos + len > stream_data.len) return null;

        if (ftype.value == 0x00) { // DATA
            if (len > out.len) return null;
            @memcpy(out[0..len], stream_data[pos .. pos + len]);

            return out[0..len];
        }

        pos += len;
    }

    return null;
}

/// Skip an ACK frame's body, returning the position after it.
fn skipAck(buf: []const u8, start: usize, ecn: bool) ?usize {
    var pos = start;
    var i: usize = 0;
    const fixed: usize = 4; // Largest, Delay, Range Count, First Range
    while (i < fixed) : (i += 1) {
        const field = varint.read(buf[pos..]) catch return null;
        pos += field.len;
    }
    if (ecn) {
        var ecn_idx: usize = 0;
        while (ecn_idx < 3) : (ecn_idx += 1) {
            const field = varint.read(buf[pos..]) catch return null;
            pos += field.len;
        }
    }

    return pos;
}

// --------------------------------------------------------- //

/// The 1-RTT keys and the server's Source Connection ID, the result of a completed handshake.
const Connected = struct {
    app_keys: keyschedule.AppKeys,
    server_scid: [20]u8,
    server_scid_len: usize,

    fn scid(self: *const Connected) []const u8 {
        return self.server_scid[0..self.server_scid_len];
    }
};

/// Run the QUIC + TLS 1.3 handshake on a bound socket: send Initial(ClientHello), receive ServerHello
/// then the server Handshake flight, and derive the handshake then 1-RTT keys.
fn connect(io: std.Io, sock: anytype, server: *const std.Io.net.IpAddress, dcid: []const u8, scid: []const u8, client_random: [32]u8, ephemeral: [32]u8) !Connected {
    const x25519_pub = X25519.recoverPublicKey(ephemeral) catch return error.X25519;

    const secrets = crypto.initialSecrets(dcid);
    const initial_client = crypto.AesKeys.fromSecret(secrets.client);
    const initial_server = crypto.AesKeys.fromSecret(secrets.server);

    var hello_buf: [512]u8 = undefined;
    const client_hello = buildClientHello(&hello_buf, client_random, x25519_pub, scid);

    var transcript = tls_key_schedule.Transcript.init();
    transcript.update(client_hello);

    // Initial payload: a CRYPTO frame carrying the ClientHello, padded over the 1200-byte floor.
    var init_payload: [1500]u8 = undefined;
    var payload_len: usize = 0;
    init_payload[payload_len] = 0x06; // CRYPTO
    payload_len += 1;
    payload_len += varint.write(init_payload[payload_len..], 0); // offset
    payload_len += varint.write(init_payload[payload_len..], client_hello.len);
    @memcpy(init_payload[payload_len..][0..client_hello.len], client_hello);
    payload_len += client_hello.len;
    while (payload_len < INITIAL_MIN) : (payload_len += 1) init_payload[payload_len] = 0x00; // PADDING

    var initial_pkt: [1600]u8 = undefined;
    const initial = try protection.sealInitial(&initial_pkt, initial_client, dcid, scid, 0, init_payload[0..payload_len]);

    // First send may hit an unbound server socket. A failure here is not fatal, the retransmit loop
    // below resends the Initial until the server answers or the budget is spent.
    sock.send(io, server, initial) catch {};

    // Receive ServerHello (Initial) then the Handshake flight, deriving keys as each arrives.
    var hs_keys: keyschedule.HandshakeKeys = undefined;
    var result = Connected{ .app_keys = undefined, .server_scid = undefined, .server_scid_len = 0 };
    var have_server_hello = false;
    var have_app = false;

    var init_pn: u32 = 0;
    var sends: usize = 1;
    while (!have_app) {
        var recv_buf: [2048]u8 = undefined;
        const msg = receiveWithin(io, sock, &recv_buf, HANDSHAKE_TIMEOUT_MS) orelse {
            // No response yet. The server's UDP socket may not be bound (there is no accept to poll),
            // or a packet was lost under load. Retransmit the Initial with a fresh packet number, the
            // QUIC reliability the handshake depends on, until the budget is spent.
            if (sends >= 25) break;
            sends += 1;
            init_pn += 1;

            // A send may report a stale ECONNREFUSED (ICMP port-unreachable queued before the
            // server bound its UDP socket). That is transient, keep retransmitting until the budget
            // is spent rather than giving up on the first refusal.
            var rt_pkt: [1600]u8 = undefined;
            const retransmit = protection.sealInitial(&rt_pkt, initial_client, dcid, scid, init_pn, init_payload[0..payload_len]) catch continue;
            sock.send(io, server, retransmit) catch continue;
            continue;
        };
        const data = msg.data;
        if (data.len == 0 or data[0] & 0x80 == 0) continue;

        const hdr = packet.parseLongHeader(data) catch continue;

        if (hdr.packet_type == 0 and !have_server_hello) {
            var open_buf: [2048]u8 = undefined;
            const opened = protection.openInitial(data, initial_server, &open_buf) catch continue;
            const server_hello = firstCryptoData(opened.payload) orelse continue;

            transcript.update(server_hello);
            const server_pub = serverKeyShare(server_hello) orelse return error.ZixNoServerKeyShare;
            const shared = X25519.scalarmult(ephemeral, server_pub) catch return error.X25519;
            hs_keys = keyschedule.handshakeKeys(shared, transcript.current());

            @memcpy(result.server_scid[0..hdr.scid.len], hdr.scid);
            result.server_scid_len = hdr.scid.len;
            have_server_hello = true;
        } else if (hdr.packet_type == 2 and have_server_hello and !have_app) {
            var open_buf: [2048]u8 = undefined;
            const opened = protection.openHandshake(data, hs_keys.server, &open_buf) catch continue;
            const flight = firstCryptoData(opened.payload) orelse continue;

            transcript.update(flight);
            result.app_keys = keyschedule.applicationKeys(hs_keys.handshake_secret, transcript.current());
            have_app = true;
        }
    }

    if (!have_app) return error.ZixHandshakeIncomplete;

    return result;
}

/// Authority every request carries. It matches the fixture certificate, so a server that refuses a
/// name it holds no certificate for still answers this client.
const AUTHORITY: []const u8 = "localhost";

/// The QPACK static-table indices for the methods this client sends (RFC 9204 Appendix A).
const METHOD_GET: u64 = 17;
const METHOD_POST: u64 = 20;
const METHOD_CONNECT: u64 = 15;

/// Seal a 1-RTT request packet: an HTTP/3 HEADERS frame on `stream_id`, followed by a DATA frame when
/// the request carries a body, sealed under the client 1-RTT keys with `client_pn`. The returned slice
/// points into `pkt_buf`, which the caller owns.
///
/// Note:
/// - All four pseudo-headers RFC 9114 4.3.1 requires are sent. A server free to shape its own
///   handler surface can serve less, a gateway rebuilding an http1 request cannot: without
///   :scheme and :authority there is no absolute target and no Host to send upstream.
/// - The STREAM frame carries FIN, so the whole request (headers and body) is one frame and the
///   server sees a client that has finished sending.
///
/// Param:
/// method_index - u64 (QPACK static index of the :method, METHOD_GET or METHOD_POST)
/// body - []const u8 (request body, empty for a request that carries none)
fn buildRequest(app_keys: keyschedule.AppKeys, server_scid: []const u8, stream_id: u64, client_pn: u32, method_index: u64, path: []const u8, body: []const u8, pkt_buf: []u8) ![]const u8 {
    var fields: [256]u8 = undefined;
    var fields_len: usize = 0;
    fields[0] = 0x00; // Required Insert Count 0
    fields[1] = 0x00; // Base 0
    fields_len = 2;
    fields_len += qpack.encodeStaticIndexedFieldLine(fields[fields_len..], method_index); // :method
    fields_len += qpack.encodeStaticIndexedFieldLine(fields[fields_len..], 23); // :scheme https
    fields_len += qpack.encodePrefixedInt(fields[fields_len..], 4, 0x50, 0); // :authority literal, static name index 0
    fields_len += qpack.encodePrefixedInt(fields[fields_len..], 7, 0x00, AUTHORITY.len); // value length, non-Huffman
    @memcpy(fields[fields_len..][0..AUTHORITY.len], AUTHORITY);
    fields_len += AUTHORITY.len;
    fields_len += qpack.encodePrefixedInt(fields[fields_len..], 4, 0x50, 1); // :path literal, static name index 1
    fields_len += qpack.encodePrefixedInt(fields[fields_len..], 7, 0x00, path.len); // value length, non-Huffman
    @memcpy(fields[fields_len..][0..path.len], path);
    fields_len += path.len;

    var content: [512]u8 = undefined;
    var content_len: usize = 0;
    content[0] = 0x01; // HEADERS frame
    content_len = 1;
    content_len += varint.write(content[content_len..], fields_len);
    @memcpy(content[content_len..][0..fields_len], fields[0..fields_len]);
    content_len += fields_len;

    if (body.len != 0) {
        // DATA frame (RFC 9114 7.2.1), the frame the request body travels in. Refused rather than
        // truncated when it would not fit, so a short body can never be read as the whole one.
        if (content_len + 1 + 8 + body.len > content.len) return error.ZixRequestTooLarge;

        content[content_len] = 0x00;
        content_len += 1;
        content_len += varint.write(content[content_len..], body.len);
        @memcpy(content[content_len..][0..body.len], body);
        content_len += body.len;
    }

    var req_payload: [1024]u8 = undefined;
    var payload_pos: usize = 0;
    req_payload[0] = 0x0b; // STREAM | LEN | FIN
    payload_pos = 1;
    payload_pos += varint.write(req_payload[payload_pos..], stream_id);
    payload_pos += varint.write(req_payload[payload_pos..], content_len); // data length
    @memcpy(req_payload[payload_pos..][0..content_len], content[0..content_len]);
    payload_pos += content_len;

    return try protection.sealShort(pkt_buf, app_keys.client, server_scid, client_pn, req_payload[0..payload_pos]);
}

/// Receive and decrypt 1-RTT packets, assembling `stream_id` until its HTTP/3 frames carry a
/// complete DATA body. Bare ACK / control packets the server interleaves are skipped.
fn recvBody(io: std.Io, sock: anytype, app_keys: keyschedule.AppKeys, stream_id: u64, body_out: []u8) ![]const u8 {
    var assembly: [ASSEMBLY_BYTES]u8 = undefined;
    var covered: usize = 0;

    var attempts: usize = 0;
    while (attempts < 16) : (attempts += 1) {
        var recv_buf: [2048]u8 = undefined;
        const msg = receiveWithin(io, sock, &recv_buf, RECV_TIMEOUT_MS) orelse break;
        const data = msg.data;
        if (data.len == 0 or data[0] & 0x80 != 0) continue;

        var open_buf: [2048]u8 = undefined;
        // This test client does a single short round trip, so the server's packet numbers stay well
        // under the truncation boundary: no prior-largest reconstruction is needed (null).
        const opened = protection.openShort(data, app_keys.server, CID_LEN, null, &open_buf) catch continue;
        collectStream(opened.payload, stream_id, &assembly, &covered);

        if (httpDataBody(assembly[0..covered], body_out)) |body| return body;
    }

    return error.NoResponse;
}

/// Do one HTTP/3 GET round trip against a local QUIC server, returning the decrypted response body.
///
/// Param:
/// io - std.Io
/// server_ip - []const u8 (the server address, e.g. 127.0.0.1)
/// server_port - u16
/// path - []const u8 (the request :path, sent as a non-Huffman literal)
/// body_out - []u8 (scratch the returned body slice points into)
///
/// Return:
/// - the response body (slice into body_out)
/// - an error if any handshake or framing step fails
pub fn fetch(io: std.Io, server_ip: []const u8, server_port: u16, path: []const u8, body_out: []u8) ![]const u8 {
    return roundTrip(io, server_ip, server_port, METHOD_GET, path, "", body_out);
}

/// Do one HTTP/3 POST round trip, sending `body` as the request DATA frame and returning the decrypted
/// response body. This is what proves a request body reaches the handler: everything else about the
/// exchange is identical to fetch.
///
/// Param:
/// path - []const u8 (the request :path)
/// body - []const u8 (the request body, sent as one DATA frame after HEADERS)
/// body_out - []u8 (scratch the returned response body slice points into)
///
/// Return:
/// - the response body (slice into body_out)
/// - an error if any handshake or framing step fails
pub fn post(io: std.Io, server_ip: []const u8, server_port: u16, path: []const u8, body: []const u8, body_out: []u8) ![]const u8 {
    return roundTrip(io, server_ip, server_port, METHOD_POST, path, body, body_out);
}

/// Handshake, send one request on client bidi stream 0, and read its response.
fn roundTrip(io: std.Io, server_ip: []const u8, server_port: u16, method_index: u64, path: []const u8, body: []const u8, body_out: []u8) ![]const u8 {
    var rnd: [16 + 16 + 32 + 32]u8 = undefined;
    io.random(&rnd);
    const dcid = rnd[0..CID_LEN];
    const scid = rnd[16 .. 16 + CID_LEN];
    const client_random: [32]u8 = rnd[32..64].*;
    const ephemeral: [32]u8 = rnd[64..96].*;

    const local = try std.Io.net.IpAddress.parse("127.0.0.1", BIND_PORT);
    const sock = try local.bind(io, .{ .mode = .dgram, .protocol = .udp });
    defer sock.close(io);

    const server = try std.Io.net.IpAddress.parse(server_ip, server_port);
    const conn = try connect(io, sock, &server, dcid, scid, client_random, ephemeral);

    var req_pkt: [1200]u8 = undefined;
    const request_packet = try buildRequest(conn.app_keys, conn.scid(), 0, 0, method_index, path, body, &req_pkt);
    try sock.send(io, &server, request_packet);

    return recvBody(io, sock, conn.app_keys, 0, body_out);
}

/// Do TWO HTTP/3 GET round trips on ONE connection, on client bidi streams 0 then 4, returning both
/// decrypted bodies. This exercises request multiplexing: a single QUIC connection serving more
/// than one request. The two responses are read in send order.
///
/// Return:
/// - a struct of the two bodies (slices into body0_out / body1_out)
/// - an error if the handshake fails or either response is missing
pub fn fetchTwo(io: std.Io, server_ip: []const u8, server_port: u16, path0: []const u8, path1: []const u8, body0_out: []u8, body1_out: []u8) !struct { []const u8, []const u8 } {
    var rnd: [16 + 16 + 32 + 32]u8 = undefined;
    io.random(&rnd);
    const dcid = rnd[0..CID_LEN];
    const scid = rnd[16 .. 16 + CID_LEN];
    const client_random: [32]u8 = rnd[32..64].*;
    const ephemeral: [32]u8 = rnd[64..96].*;

    const local = try std.Io.net.IpAddress.parse("127.0.0.1", BIND_PORT);
    const sock = try local.bind(io, .{ .mode = .dgram, .protocol = .udp });
    defer sock.close(io);

    const server = try std.Io.net.IpAddress.parse(server_ip, server_port);
    const conn = try connect(io, sock, &server, dcid, scid, client_random, ephemeral);

    var req0_pkt: [1200]u8 = undefined;
    const req0 = try buildRequest(conn.app_keys, conn.scid(), 0, 0, METHOD_GET, path0, "", &req0_pkt);
    try sock.send(io, &server, req0);

    var req1_pkt: [1200]u8 = undefined;
    const req1 = try buildRequest(conn.app_keys, conn.scid(), 4, 1, METHOD_GET, path1, "", &req1_pkt);
    try sock.send(io, &server, req1);

    const body0 = try recvBody(io, sock, conn.app_keys, 0, body0_out);
    const body1 = try recvBody(io, sock, conn.app_keys, 4, body1_out);

    return .{ body0, body1 };
}

// --------------------------------------------------------- //
// WebTransport over HTTP/3
// --------------------------------------------------------- //

/// The upgrade token the WebTransport CONNECT carries (draft-ietf-webtrans-http3-16 9.1). The deployed
/// draft-07 token is `webtransport`, which this server accepts as well.
const WEBTRANSPORT_TOKEN: []const u8 = "webtransport-h3";

/// The HTTP/3 settings a WebTransport client advertises (draft-16 3.1): extended CONNECT, HTTP/3
/// datagrams, and the draft-16 WebTransport flag. The server refuses a session whose SETTINGS lack the
/// datagram support, so these are load-bearing rather than decoration.
const SETTING_ENABLE_CONNECT_PROTOCOL: u64 = 0x08;
const SETTING_H3_DATAGRAM: u64 = 0x33;
const SETTING_WT_ENABLED: u64 = 0x2c7cf000;

/// The HTTP/3 control stream type, its SETTINGS frame type, and the HEADERS frame type a response
/// status arrives in (RFC 9114 6.2.1 / 6.2.3 / 7.2.2).
const CONTROL_STREAM_TYPE: u64 = 0x00;
const SETTINGS_FRAME_TYPE: u64 = 0x04;
const HEADERS_FRAME_TYPE: u64 = 0x01;

/// The WebTransport stream opening values (draft-16 4.2 / 4.3): the unidirectional stream type, and the
/// signal value that turns a request stream into a bidirectional data stream. Each is followed by the
/// session id, and everything after that is application bytes.
const WT_UNI_STREAM_TYPE: u64 = 0x54;
const WT_BIDI_SIGNAL: u64 = 0x41;

/// The QUIC DATAGRAM frame type this client sends (RFC 9221 4): the explicit-length form, whose payload
/// is the HTTP/3 datagram framing.
const DATAGRAM_FRAME_TYPE: u64 = 0x31;

/// The client-initiated stream ids this client uses (RFC 9000 2.1): 2 is its control stream, 0 is the
/// WebTransport CONNECT stream (which is the session id), and 4 is the data stream it opens.
const CONTROL_STREAM_ID: u64 = 2;
const CONNECT_STREAM_ID: u64 = 0;
const DATA_STREAM_ID: u64 = 4;

/// The first server-initiated unidirectional stream, where a server that opens one per session writes.
const SERVER_UNI_STREAM_ID: u64 = 3;

/// Bytes one tracked stream accumulates, and the largest payload a data stream or a datagram carries
/// here. Both are small: this drives a session banner, one echo, and one datagram.
const WT_TRACK_BYTES: usize = 4096;
const WT_PAYLOAD_BYTES: usize = 1024;
const WT_DATAGRAM_BYTES: usize = 1100;

/// Per-packet wait inside a WebTransport read, and how many packets one read waits through before it
/// reports the response missing.
const WT_RECV_TIMEOUT_MS: u32 = 1500;
const WT_RECV_ATTEMPTS: usize = 12;

/// One stream the session is reassembling: which stream, the contiguous bytes so far, and whether the
/// peer ended it.
const WtTrack = struct {
    id: u64 = 0,
    buf: [WT_TRACK_BYTES]u8 = undefined,
    covered: usize = 0,
    fin: bool = false,

    /// Copy one stream chunk at its offset and note a FIN. A chunk that starts past the contiguous
    /// prefix is dropped: it would leave a hole this accumulator cannot track, and the peer resends it.
    fn absorb(self: *WtTrack, parsed: ParsedStream) void {
        const start: usize = @intCast(parsed.offset);
        if (start > self.covered) return;
        if (start + parsed.data.len > self.buf.len) return;

        @memcpy(self.buf[start..][0..parsed.data.len], parsed.data);

        const end = start + parsed.data.len;
        if (end > self.covered) self.covered = end;
        self.fin = self.fin or parsed.fin;
    }
};

/// What a session has assembled from each stream a WebTransport exchange uses: the CONNECT stream (the
/// session's response), the server's banner stream, and the client's own data stream.
const WtRecv = struct {
    connect: WtTrack = .{ .id = CONNECT_STREAM_ID },
    banner: WtTrack = .{ .id = SERVER_UNI_STREAM_ID },
    data: WtTrack = .{ .id = DATA_STREAM_ID },

    /// The accumulator for `stream_id`, or null for a stream this client does not read.
    fn forStream(self: *WtRecv, stream_id: u64) ?*WtTrack {
        if (stream_id == self.connect.id) return &self.connect;
        if (stream_id == self.banner.id) return &self.banner;
        if (stream_id == self.data.id) return &self.data;

        return null;
    }
};

/// One SETTINGS entry (RFC 9114 6.2.4): the identifier and its value, both varints.
const Setting = struct { identifier: u64, value: u64 };

/// A parsed QUIC DATAGRAM frame: its data field, and the bytes the frame occupied.
const ParsedDatagram = struct { data: []const u8, consumed: usize };

/// Parse a DATAGRAM frame at the start of `buf` (RFC 9221 4). This client sends and reads the
/// explicit-length form; the no-length form owns the rest of the payload if a peer sends one.
fn parseDatagramFrame(buf: []const u8) ?ParsedDatagram {
    if (buf.len == 0) return null;

    if (buf[0] == 0x30) return .{ .data = buf[1..], .consumed = buf.len };
    if (buf[0] != DATAGRAM_FRAME_TYPE) return null;

    const length = varint.read(buf[1..]) catch return null;
    const header = 1 + length.len;
    const data_len: usize = std.math.cast(usize, length.value) orelse return null;
    if (data_len > buf.len - header) return null;

    return .{ .data = buf[header..][0..data_len], .consumed = header + data_len };
}

/// Write a WebTransport stream header: the type or signal value, then the session id.
fn writeWtHeader(out: []u8, kind_value: u64, session_id: u64) usize {
    var pos: usize = 0;
    pos += varint.write(out[pos..], kind_value);
    pos += varint.write(out[pos..], session_id);

    return pos;
}

/// A parsed WebTransport stream header: the session the stream belongs to, and the bytes it took.
const WtHeader = struct { session_id: u64, len: usize };

/// Parse the header at the start of a WebTransport data stream (draft-16 4.2 / 4.3). Null while the
/// header is still arriving, or when the stream does not open with `expected_value`.
fn parseWtHeader(expected_value: u64, buf: []const u8) ?WtHeader {
    const value = varint.read(buf) catch return null;
    if (value.value != expected_value) return null;

    const session = varint.read(buf[value.len..]) catch return null;

    return .{ .session_id = session.value, .len = value.len + session.len };
}

/// The field section of the first HEADERS frame in `track`, or null while it is still arriving. The
/// server leads a CONNECT stream with that frame, so this is the session's response.
fn responseFields(track: *const WtTrack) ?[]const u8 {
    var pos: usize = 0;
    while (pos < track.covered) {
        const ftype = varint.read(track.buf[pos..track.covered]) catch return null;
        pos += ftype.len;
        const length = varint.read(track.buf[pos..track.covered]) catch return null;
        pos += length.len;

        const len: usize = @intCast(length.value);
        if (pos + len > track.covered) return null;
        if (ftype.value == HEADERS_FRAME_TYPE) return track.buf[pos..][0..len];

        pos += len;
    }

    return null;
}

/// The `:status` value of a response field section, or null when it carries none. Both representations
/// the engine's encoder produces are read: an indexed static field line (a status the static table
/// holds) and a literal field line borrowing the `:status` name from it (RFC 9204 4.5.2 / 4.5.4).
fn responseStatus(fields: []const u8) ?[]const u8 {
    var pos: usize = 2; // Encoded Field Section Prefix: Required Insert Count, Base
    while (pos < fields.len) {
        if (qpack.decodeIndexedFieldLine(fields[pos..])) |line| {
            pos += line.len;
            if (!line.static) continue;

            const entry = qpack.staticEntry(line.index) orelse continue;
            if (std.mem.eql(u8, entry.name, ":status")) return entry.value;

            continue;
        } else |_| {}

        const literal = qpack.decodeLiteralNameRef(fields[pos..]) catch return null;
        pos += literal.len;
        if (!literal.static) continue;

        const entry = qpack.staticEntry(literal.name_index) orelse continue;
        if (std.mem.eql(u8, entry.name, ":status")) return literal.value;
    }

    return null;
}

/// Walk a decrypted 1-RTT payload, folding what a WebTransport session reads into its accumulator:
/// stream chunks, and the datagrams whose HTTP/3 framing names its session. The controls the server
/// interleaves (ACK, HANDSHAKE_DONE, MAX_STREAMS, MAX_DATA) are skipped by their own field counts.
fn collectWebtransport(payload: []const u8, session: *WebtransportSession) void {
    var pos: usize = 0;
    while (pos < payload.len) {
        const ftype = varint.read(payload[pos..]) catch return;
        pos += ftype.len;

        switch (ftype.value) {
            0x08...0x0f => {
                const parsed = parseStream(payload[pos - ftype.len ..]) orelse return;
                if (session.recv.forStream(parsed.id)) |track| track.absorb(parsed);

                pos = (pos - ftype.len) + parsed.consumed;
            },
            0x30, 0x31 => {
                const parsed = parseDatagramFrame(payload[pos - ftype.len ..]) orelse return;
                session.absorbDatagram(parsed.data);

                pos = (pos - ftype.len) + parsed.consumed;
            },
            else => {
                // Everything else a server sends alongside (PADDING, PING, ACK, HANDSHAKE_DONE,
                // MAX_DATA, MAX_STREAMS, and the rest) carries no state this client reads.
                const skipped = h3.request.skipFrame(payload[pos - ftype.len ..]) orelse return;

                pos = (pos - ftype.len) + skipped;
            },
        }
    }
}

/// A WebTransport session on the wire: the bound socket, the 1-RTT keys, the CONNECT stream id, and
/// everything the server has sent so far.
///
/// Note:
/// - The receive side accumulates per stream because the server may split a chunk across packets, and
///   because the banner a server opens its own stream with can arrive before the CONNECT response:
///   every read waits for the one item it needs and leaves the rest accumulated for the next call.
/// - One session per connection is what this client models, so the session id is a fixed stream id and
///   only the streams an exchange uses are tracked.
pub const WebtransportSession = struct {
    io: std.Io,
    sock: std.Io.net.Socket,
    server: std.Io.net.IpAddress,
    keys: keyschedule.AppKeys,
    server_scid: [20]u8,
    server_scid_len: usize,
    /// The packet number the next 1-RTT send is sealed with.
    pn: u32 = 0,
    /// The largest packet number decrypted so far, so a truncated packet number keeps recovering.
    largest_pn: ?u64 = null,
    /// The CONNECT stream id, which is the session id (draft-16 3.2).
    session_id: u64 = CONNECT_STREAM_ID,
    recv: WtRecv = .{},
    /// The last datagram payload the server sent, with the HTTP/3 datagram framing already stripped.
    datagram: [WT_DATAGRAM_BYTES]u8 = undefined,
    datagram_len: usize = 0,

    /// The server's Source Connection ID: the Destination CID of every 1-RTT packet sent after the
    /// handshake.
    fn scid(self: *const WebtransportSession) []const u8 {
        return self.server_scid[0..self.server_scid_len];
    }

    /// Close the session's socket. The server sees the connection go away and reports the session as
    /// closed, which is the same end a client that simply stops sends.
    pub fn close(self: *WebtransportSession) void {
        self.sock.close(self.io);
    }

    /// Seal one 1-RTT packet carrying a single STREAM frame (RFC 9000 19.8, length and FIN bits set
    /// explicitly) and send it.
    fn sendStream(self: *WebtransportSession, stream_id: u64, fin: bool, data: []const u8) !void {
        var payload: [WT_PAYLOAD_BYTES + 64]u8 = undefined;
        payload[0] = if (fin) 0x0b else 0x0a; // STREAM | LEN, with or without FIN
        var pos: usize = 1;
        pos += varint.write(payload[pos..], stream_id);
        pos += varint.write(payload[pos..], data.len);
        @memcpy(payload[pos..][0..data.len], data);
        pos += data.len;

        var pkt: [1600]u8 = undefined;
        const sealed = try protection.sealShort(&pkt, self.keys.client, self.scid(), self.pn, payload[0..pos]);
        self.pn += 1;

        return self.sock.send(self.io, &self.server, sealed);
    }

    /// Send the client control stream (client unidirectional stream 2): the control stream type, then
    /// the SETTINGS frame (RFC 9114 6.2.1 / 6.2.3). The WebTransport entries are what makes a session
    /// possible at all: the server refuses a CONNECT whose SETTINGS lack the datagram support, and it
    /// refuses one that arrives before the SETTINGS (draft-16 7.1 / 3.1).
    fn sendControlStream(self: *WebtransportSession) !void {
        const entries = [_]Setting{
            .{ .identifier = SETTING_ENABLE_CONNECT_PROTOCOL, .value = 1 },
            .{ .identifier = SETTING_H3_DATAGRAM, .value = 1 },
            .{ .identifier = SETTING_WT_ENABLED, .value = 1 },
        };

        var settings: [64]u8 = undefined;
        var settings_len: usize = 0;
        for (entries) |entry| {
            settings_len += varint.write(settings[settings_len..], entry.identifier);
            settings_len += varint.write(settings[settings_len..], entry.value);
        }

        var stream: [96]u8 = undefined;
        stream[0] = @intCast(CONTROL_STREAM_TYPE);
        var pos: usize = 1;
        stream[pos] = @intCast(SETTINGS_FRAME_TYPE);
        pos += 1;
        pos += varint.write(stream[pos..], settings_len);
        @memcpy(stream[pos..][0..settings_len], settings[0..settings_len]);
        pos += settings_len;

        return self.sendStream(CONTROL_STREAM_ID, false, stream[0..pos]);
    }

    /// Send the extended CONNECT that opens the session, on stream 0 (draft-16 3.2, RFC 9220 4): the
    /// request carries :method CONNECT, :scheme, :authority, :path and the `:protocol` upgrade token.
    ///
    /// Note:
    /// - The CONNECT stream is not finished. It stays open for the session's capsules, and a FIN on it
    ///   is what tells the peer the session is over (draft-16 6).
    fn sendConnect(self: *WebtransportSession, path: []const u8) !void {
        var fields: [512]u8 = undefined;
        fields[0] = 0x00; // Required Insert Count 0
        fields[1] = 0x00; // Base 0
        var fields_len: usize = 2;
        fields_len += qpack.encodeStaticIndexedFieldLine(fields[fields_len..], METHOD_CONNECT);
        fields_len += qpack.encodeStaticIndexedFieldLine(fields[fields_len..], 23); // :scheme https
        fields_len += qpack.encodePrefixedInt(fields[fields_len..], 4, 0x50, 0); // :authority, static name index 0
        fields_len += qpack.encodePrefixedInt(fields[fields_len..], 7, 0x00, AUTHORITY.len); // value length, non-Huffman
        @memcpy(fields[fields_len..][0..AUTHORITY.len], AUTHORITY);
        fields_len += AUTHORITY.len;
        fields_len += qpack.encodePrefixedInt(fields[fields_len..], 4, 0x50, 1); // :path, static name index 1
        fields_len += qpack.encodePrefixedInt(fields[fields_len..], 7, 0x00, path.len);
        @memcpy(fields[fields_len..][0..path.len], path);
        fields_len += path.len;

        // :protocol has no static-table entry, so it is a literal field line with a literal name: 0010,
        // the name length in the low three bits, H clear, then the name and the value as plain strings
        // (RFC 9204 4.5.6). That is the representation the server's decoder reads it from.
        const protocol_name = ":protocol";
        fields_len += qpack.encodePrefixedInt(fields[fields_len..], 3, 0x20, protocol_name.len);
        @memcpy(fields[fields_len..][0..protocol_name.len], protocol_name);
        fields_len += protocol_name.len;
        fields_len += qpack.encodePrefixedInt(fields[fields_len..], 7, 0x00, WEBTRANSPORT_TOKEN.len);
        @memcpy(fields[fields_len..][0..WEBTRANSPORT_TOKEN.len], WEBTRANSPORT_TOKEN);
        fields_len += WEBTRANSPORT_TOKEN.len;

        var stream: [640]u8 = undefined;
        stream[0] = @intCast(HEADERS_FRAME_TYPE);
        var pos: usize = 1;
        pos += varint.write(stream[pos..], fields_len);
        @memcpy(stream[pos..][0..fields_len], fields[0..fields_len]);
        pos += fields_len;

        return self.sendStream(CONNECT_STREAM_ID, false, stream[0..pos]);
    }

    /// Seal one 1-RTT packet carrying a DATAGRAM frame (RFC 9221 4, type 0x31 with an explicit length)
    /// whose payload is the HTTP/3 datagram framing: the session's quarter stream id, then the
    /// application bytes (RFC 9297 2.1, draft-16 4.5).
    fn sendDatagram(self: *WebtransportSession, payload: []const u8) !void {
        var body: [WT_DATAGRAM_BYTES]u8 = undefined;
        var body_len = varint.write(&body, self.session_id / 4);
        if (payload.len > body.len - body_len) return error.ZixPayloadTooLarge;
        @memcpy(body[body_len..][0..payload.len], payload);
        body_len += payload.len;

        var frame: [WT_DATAGRAM_BYTES + 16]u8 = undefined;
        frame[0] = @intCast(DATAGRAM_FRAME_TYPE);
        var pos: usize = 1;
        pos += varint.write(frame[pos..], body_len);
        @memcpy(frame[pos..][0..body_len], body[0..body_len]);
        pos += body_len;

        var pkt: [1600]u8 = undefined;
        const sealed = try protection.sealShort(&pkt, self.keys.client, self.scid(), self.pn, frame[0..pos]);
        self.pn += 1;

        return self.sock.send(self.io, &self.server, sealed);
    }

    /// Read one 1-RTT packet and fold its frames into the accumulator. False when nothing arrived in
    /// time, or when the datagram was not a 1-RTT packet this client can decrypt.
    fn pumpOnce(self: *WebtransportSession, timeout_ms: u32) bool {
        var recv_buf: [2048]u8 = undefined;
        const msg = receiveWithin(self.io, self.sock, &recv_buf, timeout_ms) orelse return false;
        const data = msg.data;
        if (data.len == 0 or data[0] & 0x80 != 0) return false;

        var open_buf: [2048]u8 = undefined;
        const opened = protection.openShort(data, self.keys.server, CID_LEN, self.largest_pn, &open_buf) catch return false;
        self.largest_pn = @max(self.largest_pn orelse 0, opened.packet_number);
        collectWebtransport(opened.payload, self);

        return true;
    }

    /// Wait for the server's response to the CONNECT and check its status: the session is open once the
    /// 2xx HEADERS are on the wire, and a refusal arrives as any other status on the same stream
    /// (draft-16 3.2).
    fn waitConnectResponse(self: *WebtransportSession) !void {
        var attempts: usize = 0;
        while (attempts < WT_RECV_ATTEMPTS) : (attempts += 1) {
            if (responseFields(&self.recv.connect)) |fields| {
                const status = responseStatus(fields) orelse return error.ZixNoResponseStatus;
                if (status.len != 3 or status[0] != '2') return error.ZixSessionRefused;

                return;
            }

            _ = self.pumpOnce(WT_RECV_TIMEOUT_MS);
        }

        return error.NoResponse;
    }

    /// Wait for `payload_len` bytes on the data stream and copy them into `out`.
    fn waitStreamEcho(self: *WebtransportSession, payload_len: usize, out: []u8) ![]const u8 {
        if (payload_len > out.len) return error.ZixEchoTooLarge;

        var attempts: usize = 0;
        while (attempts < WT_RECV_ATTEMPTS) : (attempts += 1) {
            if (self.recv.data.covered >= payload_len) {
                @memcpy(out[0..payload_len], self.recv.data.buf[0..payload_len]);

                return out[0..payload_len];
            }

            _ = self.pumpOnce(WT_RECV_TIMEOUT_MS);
        }

        return error.NoResponse;
    }

    /// Wait for the server's datagram and copy its payload into `out`. Whatever length arrived is what
    /// is returned, so a short or padded echo is compared rather than hidden.
    fn waitDatagram(self: *WebtransportSession, out: []u8) ![]const u8 {
        var attempts: usize = 0;
        while (attempts < WT_RECV_ATTEMPTS) : (attempts += 1) {
            if (self.datagram_len != 0) {
                if (self.datagram_len > out.len) return error.ZixEchoTooLarge;
                @memcpy(out[0..self.datagram_len], self.datagram[0..self.datagram_len]);

                return out[0..self.datagram_len];
            }

            _ = self.pumpOnce(WT_RECV_TIMEOUT_MS);
        }

        return error.NoResponse;
    }

    /// Read the server's unidirectional stream: its stream header, then the application bytes up to the
    /// FIN. The header is not part of what is returned, so the caller sees what the server wrote.
    fn waitBanner(self: *WebtransportSession, out: []u8) ![]const u8 {
        var attempts: usize = 0;
        while (attempts < WT_RECV_ATTEMPTS) : (attempts += 1) {
            const track = &self.recv.banner;
            if (track.fin) {
                const header = parseWtHeader(WT_UNI_STREAM_TYPE, track.buf[0..track.covered]) orelse return error.ZixNotWebtransport;
                if (header.session_id != self.session_id) return error.ZixWrongSession;

                const payload = track.buf[header.len..track.covered];
                if (payload.len > out.len) return error.ZixEchoTooLarge;
                @memcpy(out[0..payload.len], payload);

                return out[0..payload.len];
            }

            _ = self.pumpOnce(WT_RECV_TIMEOUT_MS);
        }

        return error.NoResponse;
    }

    /// Route one HTTP/3 datagram to this session: the payload is the quarter stream id, then the
    /// application bytes (RFC 9297 2.1). A datagram for another session, or one that is not there, is
    /// dropped, which is what "unreliable" means at this layer.
    fn absorbDatagram(self: *WebtransportSession, data: []const u8) void {
        const quarter = varint.read(data) catch return;
        if (quarter.value != self.session_id / 4) return;

        const payload = data[quarter.len..];
        if (payload.len > self.datagram.len) return;

        @memcpy(self.datagram[0..payload.len], payload);
        self.datagram_len = payload.len;
    }
};

/// Open a WebTransport session: handshake, the client control stream with its SETTINGS, the extended
/// CONNECT on stream 0, then wait for the server's 2xx response.
///
/// Param:
/// io - std.Io
/// server_ip - []const u8 (the server address, e.g. 127.0.0.1)
/// server_port - u16
/// path - []const u8 (the CONNECT :path, the resource the session is requested from)
///
/// Return:
/// - WebtransportSession (the caller closes it with `WebtransportSession.close`)
/// - an error when the handshake fails, the server refuses the session, or its 2xx does not arrive
pub fn webtransportConnect(io: std.Io, server_ip: []const u8, server_port: u16, path: []const u8) !WebtransportSession {
    var rnd: [16 + 16 + 32 + 32]u8 = undefined;
    io.random(&rnd);
    const dcid = rnd[0..CID_LEN];
    const scid = rnd[16 .. 16 + CID_LEN];
    const client_random: [32]u8 = rnd[32..64].*;
    const ephemeral: [32]u8 = rnd[64..96].*;

    const local = try std.Io.net.IpAddress.parse("127.0.0.1", BIND_PORT);
    const sock = try local.bind(io, .{ .mode = .dgram, .protocol = .udp });

    const server = try std.Io.net.IpAddress.parse(server_ip, server_port);
    // A handshake that fails leaves no session to close, so the socket goes back here.
    const conn = connect(io, sock, &server, dcid, scid, client_random, ephemeral) catch |err| {
        sock.close(io);

        return err;
    };

    var session = WebtransportSession{
        .io = io,
        .sock = sock,
        .server = server,
        .keys = conn.app_keys,
        .server_scid = conn.server_scid,
        .server_scid_len = conn.server_scid_len,
    };
    errdefer session.close();

    // SETTINGS first: a CONNECT that arrives before them, or one whose SETTINGS lack the datagram
    // support, is refused rather than served (draft-16 7.1 / 3.1).
    try session.sendControlStream();
    try session.sendConnect(path);

    try session.waitConnectResponse();

    return session;
}

/// Write `payload` on a new WebTransport bidirectional data stream and return what the server echoes
/// back on that stream.
///
/// Note:
/// - The stream opens with the 0x41 signal value and the session id (draft-16 4.3), then the payload,
///   and the client's send half is finished so the server sees a whole chunk and ends its own half.
/// - The echo arrives on the client's own stream id, at offset 0 of the server's send direction, so
///   there is no second header in front of it.
///
/// Param:
/// session - *WebtransportSession (a session from `webtransportConnect`)
/// payload - []const u8 (the application bytes to send)
/// echo_out - []u8 (scratch the returned echo slice points into)
///
/// Return:
/// - the echoed payload (slice into echo_out)
/// - an error when the payload does not fit or the echo does not arrive
pub fn webtransportStream(session: *WebtransportSession, payload: []const u8, echo_out: []u8) ![]const u8 {
    if (payload.len > WT_PAYLOAD_BYTES) return error.ZixPayloadTooLarge;

    var data: [WT_PAYLOAD_BYTES + 16]u8 = undefined;
    var len = writeWtHeader(&data, WT_BIDI_SIGNAL, session.session_id);
    @memcpy(data[len..][0..payload.len], payload);
    len += payload.len;

    try session.sendStream(DATA_STREAM_ID, true, data[0..len]);

    return session.waitStreamEcho(payload.len, echo_out);
}

/// Send one WebTransport datagram and return what the server echoes back.
///
/// Param:
/// session - *WebtransportSession (a session from `webtransportConnect`)
/// payload - []const u8 (the application bytes the datagram carries)
/// echo_out - []u8 (scratch the returned echo slice points into)
///
/// Return:
/// - the echoed payload (slice into echo_out)
/// - an error when the payload does not fit or the echo does not arrive
pub fn webtransportDatagram(session: *WebtransportSession, payload: []const u8, echo_out: []u8) ![]const u8 {
    try session.sendDatagram(payload);

    return session.waitDatagram(echo_out);
}

/// Read the WebTransport unidirectional stream the server opened for the session: the stream header is
/// consumed, and what is returned is the bytes before the FIN.
///
/// Param:
/// session - *WebtransportSession (a session from `webtransportConnect`)
/// out - []u8 (scratch the returned slice points into)
///
/// Return:
/// - the stream's application bytes (slice into out)
/// - an error when the stream does not open with the WebTransport type, names another session, or ends
///   without arriving
pub fn webtransportBanner(session: *WebtransportSession, out: []u8) ![]const u8 {
    return session.waitBanner(out);
}

/// Largest response one stream may assemble before the client gives up on it.
const ASSEMBLY_BYTES: usize = 64 * 1024;

/// Per-response wait for a 1-RTT packet.
const RECV_TIMEOUT_MS: u32 = 3000;

// Per-attempt wait for a handshake packet. Short enough that the Initial is retransmitted
// promptly when the first send is lost, the retransmit loop spends at most 25 of these.
const HANDSHAKE_TIMEOUT_MS: u32 = 600;

/// Receive one datagram within `timeout_ms`, or null when nothing arrived in time.
///
/// Note:
/// - Readiness first, then a plain receive. A timed std.Io receive races the receive against a
///   timer, which the Windows backend cannot do for a socket: it answers
///   error.ConcurrencyUnavailable, which every caller here reads as a lost packet and retries
///   until the budget is spent. Readiness plus a blocking receive needs no concurrency.
/// - A receive that fails after readiness is reported the same as a timeout: to the QUIC loops
///   above, both mean this attempt produced no packet.
fn receiveWithin(io: std.Io, sock: std.Io.net.Socket, buf: []u8, timeout_ms: u32) ?std.Io.net.IncomingMessage {
    const ready = socket_poll.waitReady(sock.handle, socket_poll.READABLE, timeout_ms) catch return null;
    if (!ready) return null;

    return sock.receive(io, buf) catch null;
}
