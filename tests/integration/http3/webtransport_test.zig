//! Integration tests: the WebTransport over HTTP/3 paths that only work when the pieces agree: the
//! request decode that has to recognise a session request, the SETTINGS codec a client reads before it
//! sends one, and the transport parameters the feature is built on. The bytes here are built by hand
//! from the same public primitives a peer uses, so what is asserted is the wire contract rather than a
//! decode driven by an encoder that shares its mistakes.

const std = @import("std");
const zix = @import("zix");

const Webtransport = zix.Webtransport;
const h3 = zix.Http3.h3;
const huffman = zix.Http3.huffman;
const qpack = zix.Http3.qpack;
const request = zix.Http3.request;
const transport_params = zix.Http3.transport_params;
const varint = zix.Http3.varint;

/// QPACK static-table indices (RFC 9204 Appendix A) for what an extended CONNECT names.
const method_connect: u64 = 15;
const method_get: u64 = 17;
const scheme_https: u64 = 23;
const authority_name: u64 = 0;
const path_name: u64 = 1;

/// Huffman("webtransport-h3"), from the RFC 7541 Appendix B table every QPACK endpoint uses. The
/// decode below is what proves the constant: a wrong one names no dialect.
const huffman_token = [_]u8{ 0xf0, 0x58, 0xd3, 0x60, 0xea, 0x45, 0x67, 0xb1, 0x2b, 0x4e, 0xcf };

/// The fields of the session request the decode is fed, for the message validation that decides whether
/// what came off the wire is a legal HTTP/3 request at all.
const session_request_fields = [_]h3.Field{
    .{ .name = ":method", .value = "CONNECT" },
    .{ .name = ":scheme", .value = "https" },
    .{ .name = ":authority", .value = "example.com" },
    .{ .name = ":path", .value = "/upload" },
    .{ .name = ":protocol", .value = "webtransport-h3" },
};

/// The same request with GET instead of CONNECT, which is the shape RFC 9220 4 forbids.
const get_with_protocol_fields = [_]h3.Field{
    .{ .name = ":method", .value = "GET" },
    .{ .name = ":scheme", .value = "https" },
    .{ .name = ":authority", .value = "example.com" },
    .{ .name = ":path", .value = "/upload" },
    .{ .name = ":protocol", .value = "webtransport-h3" },
};

/// The same request with no token at all, which is a plain GET and nothing else.
const plain_get_fields = [_]h3.Field{
    .{ .name = ":method", .value = "GET" },
    .{ .name = ":scheme", .value = "https" },
    .{ .name = ":authority", .value = "example.com" },
    .{ .name = ":path", .value = "/upload" },
};

// --------------------------------------------------------- //

/// Encode a Literal Field Line with Literal Name (RFC 9204 4.5.6): the only representation that can
/// carry a name no static entry holds, which is exactly what `:protocol` is (RFC 9220 4).
///
/// Param:
/// out - []u8 (destination, must hold the line)
/// name - []const u8 (the field name, spelled out)
/// value - []const u8 (the field value, already Huffman-coded when `value_huffman` is set)
/// value_huffman - bool (whether the value carries the H bit)
///
/// Return:
/// - usize (bytes written)
fn encodeLiteralFieldLine(out: []u8, name: []const u8, value: []const u8, value_huffman: bool) usize {
    var pos = qpack.encodePrefixedInt(out, 3, 0x20, name.len);
    @memcpy(out[pos..][0..name.len], name);
    pos += name.len;

    pos += qpack.encodePrefixedInt(out[pos..], 7, if (value_huffman) 0x80 else 0x00, value.len);
    @memcpy(out[pos..][0..value.len], value);

    return pos + value.len;
}

/// The field section of a request carrying `:protocol`: the request line and the target fields an
/// extended CONNECT needs (RFC 9220 4), then the upgrade token under a literal name.
///
/// Param:
/// out - []u8 (destination, must hold the section)
/// method_index - u64 (QPACK static index of the `:method` value)
/// protocol - []const u8 (the `:protocol` value, coded already when `protocol_huffman` is set)
/// protocol_huffman - bool (whether the token is Huffman-coded)
///
/// Return:
/// - []const u8 (the section, borrowing `out`)
fn requestSection(out: []u8, method_index: u64, protocol: []const u8, protocol_huffman: bool) []const u8 {
    var pos: usize = 2;
    out[0] = 0x00; // Required Insert Count 0
    out[1] = 0x00; // Base 0

    pos += qpack.encodeStaticIndexedFieldLine(out[pos..], method_index);
    pos += qpack.encodeStaticIndexedFieldLine(out[pos..], scheme_https);
    pos += qpack.encodeStaticLiteralNameRef(out[pos..], authority_name, "example.com");
    pos += qpack.encodeStaticLiteralNameRef(out[pos..], path_name, "/upload");
    pos += encodeLiteralFieldLine(out[pos..], ":protocol", protocol, protocol_huffman);

    return out[0..pos];
}

/// The request-stream bytes carrying one field section: the HEADERS frame type, its length, then the
/// section (RFC 9114 4.1).
fn headersContent(out: []u8, section: []const u8) []const u8 {
    var pos: usize = 1;
    out[0] = 0x01; // HEADERS
    pos += varint.write(out[pos..], section.len);
    @memcpy(out[pos..][0..section.len], section);
    pos += section.len;

    return out[0..pos];
}

/// Wrap request-stream bytes in the one STREAM frame a client sends them in, ending the stream, which
/// is the shape the engine's request scan reads off a decrypted 1-RTT payload.
fn requestPayload(out: []u8, stream_bytes: []const u8) []const u8 {
    var pos: usize = 1;
    out[0] = 0x0b; // STREAM | LEN | FIN
    pos += varint.write(out[pos..], 0); // stream id 0, the client's first request stream
    pos += varint.write(out[pos..], stream_bytes.len);
    @memcpy(out[pos..][0..stream_bytes.len], stream_bytes);
    pos += stream_bytes.len;

    return out[0..pos];
}

/// The one request the engine's scan decodes out of a payload.
fn onlyRequest(payload: []const u8) request.DecodedRequest {
    var pieces: [2]request.StreamPiece = undefined;
    const count = request.parseStreamPieces(payload, &pieces);
    std.debug.assert(count == 1);

    return pieces[0].request.?;
}

/// The SETTINGS payload a server control stream opens with: the control stream type, the frame type,
/// and the frame length, then the payload a client reads (RFC 9114 6.2.1).
fn settingsPayload(control_stream: []const u8) []const u8 {
    const frame_len = varint.read(control_stream[2..]) catch unreachable;

    return control_stream[2 + frame_len.len ..][0..@intCast(frame_len.value)];
}

/// One transport parameter: its identifier, the length of its value, and the value, each a varint
/// (RFC 9000 18.1). A null value is the empty value RESET_STREAM_AT advertises.
fn writeParam(out: []u8, id: u64, value: ?u64) usize {
    var encoded: [8]u8 = undefined;
    const value_len = if (value) |v| varint.write(&encoded, v) else 0;

    var pos = varint.write(out, id);
    pos += varint.write(out[pos..], value_len);
    @memcpy(out[pos..][0..value_len], encoded[0..value_len]);

    return pos + value_len;
}

/// Wrap a quic_transport_parameters extension body in a minimal ClientHello, the message the handshake
/// parse walks: handshake header, legacy_version, random, session id, cipher suites, compression
/// methods, then the extension list (RFC 8446 4.1.2).
fn buildClientHello(out: []u8, params: []const u8) []const u8 {
    var pos: usize = 4; // the handshake header, filled in at the end
    std.mem.writeInt(u16, out[pos..][0..2], 0x0303, .big);
    pos += 2;
    @memset(out[pos..][0..32], 0);
    pos += 32;
    out[pos] = 0; // legacy_session_id
    pos += 1;
    std.mem.writeInt(u16, out[pos..][0..2], 2, .big); // cipher_suites
    pos += 2;
    std.mem.writeInt(u16, out[pos..][0..2], 0x1301, .big);
    pos += 2;
    out[pos] = 1; // legacy_compression_methods
    pos += 1;
    out[pos] = 0x00;
    pos += 1;

    const extensions_len_at = pos;
    pos += 2;
    const extensions_start = pos;

    std.mem.writeInt(u16, out[pos..][0..2], transport_params.extension_type, .big);
    pos += 2;
    std.mem.writeInt(u16, out[pos..][0..2], @intCast(params.len), .big);
    pos += 2;
    @memcpy(out[pos..][0..params.len], params);
    pos += params.len;

    std.mem.writeInt(u16, out[extensions_len_at..][0..2], @intCast(pos - extensions_start), .big);

    out[0] = 0x01; // client_hello, then the three-byte body length
    out[1] = @intCast((pos - 4) >> 16);
    out[2] = @intCast(((pos - 4) >> 8) & 0xff);
    out[3] = @intCast((pos - 4) & 0xff);

    return out[0..pos];
}

// --------------------------------------------------------- //

test "zix webtransport: the request decode reports the token a WebTransport session is opened with" {
    // The exact bytes a browser sends for an extended CONNECT: :method CONNECT from the static table,
    // :scheme, :authority and :path because the extended form still names a resource, and :protocol
    // spelled out under a literal name because no static entry carries it (RFC 9220 4). A decode that
    // loses the token here loses every session, whatever else works.
    var section_buf: [256]u8 = undefined;
    const section = requestSection(&section_buf, method_connect, Webtransport.draft.upgrade_token.draft16, false);

    var content_buf: [512]u8 = undefined;
    const content = headersContent(&content_buf, section);

    var payload_buf: [1024]u8 = undefined;
    const decoded = onlyRequest(requestPayload(&payload_buf, content));

    try std.testing.expectEqualStrings("CONNECT", decoded.method);
    try std.testing.expectEqualStrings("/upload", decoded.path);
    try std.testing.expectEqualStrings("example.com", decoded.authority);
    try std.testing.expectEqualStrings("webtransport-h3", decoded.protocol);
    try std.testing.expect(!decoded.protocol_huffman);

    // The token is what picks the dialect, so this request is a draft-16 session request without
    // anything else about it being inspected.
    try std.testing.expectEqual(Webtransport.Dialect.draft16, Webtransport.draft.dialectForToken(decoded.protocol).?);

    // And what the decode read is a well-formed HTTP/3 request: `:protocol` on a CONNECT with all three
    // target fields is exactly the extended form (RFC 9114 4.3.1 / RFC 9220 4).
    try h3.validateMessage(.request, &session_request_fields, null, 0);
}

test "zix webtransport: a Huffman-coded protocol token still names the dialect" {
    // A client is free to Huffman-code the token, and the decode leaves a value in the coding it
    // arrived in: the layer that recognises a session request expands it before matching. This is that
    // expansion, fed the bytes a Huffman-capable client sends.
    var section_buf: [256]u8 = undefined;
    const section = requestSection(&section_buf, method_connect, &huffman_token, true);

    var content_buf: [512]u8 = undefined;
    const content = headersContent(&content_buf, section);

    var payload_buf: [1024]u8 = undefined;
    const decoded = onlyRequest(requestPayload(&payload_buf, content));

    try std.testing.expectEqualStrings("CONNECT", decoded.method);
    try std.testing.expect(decoded.protocol_huffman);
    try std.testing.expectEqualSlices(u8, &huffman_token, decoded.protocol);

    // Expanding it lands on the same token the literal case carries, so a session request works in
    // either coding: a token that only matched when written out would be a session no browser opens.
    var scratch: [32]u8 = undefined;
    const token_len = huffman.decode(&scratch, decoded.protocol).?;

    try std.testing.expectEqualStrings("webtransport-h3", scratch[0..token_len]);
    try std.testing.expectEqual(Webtransport.Dialect.draft16, Webtransport.draft.dialectForToken(scratch[0..token_len]).?);

    // The coded bytes name no dialect on their own, which is why the expansion above is not optional: a
    // receiver that compared the compressed value would refuse every client that codes it.
    try std.testing.expect(Webtransport.draft.dialectForToken(decoded.protocol) == null);
}

test "zix webtransport: a protocol on a request that is not CONNECT is malformed" {
    // RFC 9220 4: `:protocol` extends CONNECT alone. The decode still reports the field, which is what
    // lets both the message validator and the session predicate catch it: a GET carrying a WebTransport
    // token must never be read as a session request.
    var section_buf: [256]u8 = undefined;
    const section = requestSection(&section_buf, method_get, Webtransport.draft.upgrade_token.draft16, false);

    var content_buf: [512]u8 = undefined;
    const content = headersContent(&content_buf, section);

    var payload_buf: [1024]u8 = undefined;
    const decoded = onlyRequest(requestPayload(&payload_buf, content));

    try std.testing.expectEqualStrings("GET", decoded.method);
    try std.testing.expectEqualStrings("webtransport-h3", decoded.protocol);

    // Malformed by the message rules the engine applies to every request.
    try std.testing.expect(h3.isMalformed(.request, &get_with_protocol_fields, null, 0));

    // A session request needs the method and the token together: the token is there and the method is
    // not, so the CONNECT predicate this token feeds cannot be satisfied by a GET.
    try std.testing.expectEqual(Webtransport.Dialect.draft16, Webtransport.draft.dialectForToken(decoded.protocol).?);
    try std.testing.expect(!std.mem.eql(u8, decoded.method, "CONNECT"));

    // The same request without the token is a plain GET, and nothing about it is malformed: the token is
    // what makes the difference, not the method.
    try std.testing.expect(!h3.isMalformed(.request, &plain_get_fields, null, 0));
}

test "zix webtransport: the settings a WebTransport server advertises are the ones a client needs" {
    // The settings a config with the feature on maps to: the three support flags a client checks before
    // it sends a session request (H3_DATAGRAM, extended CONNECT, and the binding itself), the draft-16
    // limits a session starts from, and the deployed pair so a draft-07 client sees support too (3.1 /
    // 5.5 / draft-07 3.1).
    const advertised = h3.ServerSettings{
        .enable_connect_protocol = true,
        .h3_datagram = true,
        .webtransport = true,
        .wt_initial_max_streams_uni = 16,
        .wt_initial_max_streams_bidi = 16,
        .wt_initial_max_data = 1 << 20,
        .legacy_webtransport = true,
    };

    var out: [256]u8 = undefined;
    const len = h3.writeServerControlStream(&out, advertised).?;

    // The control stream type, then a SETTINGS frame: what a client reads is the frame's payload.
    try std.testing.expectEqual(@as(u8, h3.control_stream), out[0]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(h3.FrameType.settings)), out[1]);

    const client = h3.parseClientSettings(settingsPayload(out[0..len]));
    try std.testing.expect(!client.malformed);
    try std.testing.expect(client.enable_connect_protocol);
    try std.testing.expect(client.h3_datagram);
    try std.testing.expectEqual(@as(u64, 1), client.wt_enabled);
    try std.testing.expectEqual(@as(u64, 16), client.wt_initial_max_streams_uni);
    try std.testing.expectEqual(@as(u64, 16), client.wt_initial_max_streams_bidi);
    try std.testing.expectEqual(@as(u64, 1 << 20), client.wt_initial_max_data);
    try std.testing.expectEqual(@as(u64, 1), client.enable_webtransport);
    try std.testing.expectEqual(@as(u64, 1), client.webtransport_max_sessions);

    // A config with the feature off still opens its control stream with the empty SETTINGS frame the
    // engine sent before WebTransport existed, so a plain HTTP/3 connection is unchanged and no client
    // reads support out of it.
    const plain_len = h3.writeServerControlStream(&out, .{}).?;
    try std.testing.expectEqual(@as(usize, 3), plain_len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x04, 0x00 }, out[0..plain_len]);

    const disabled = h3.parseClientSettings(settingsPayload(out[0..plain_len]));
    try std.testing.expect(!disabled.malformed);
    try std.testing.expect(!disabled.enable_connect_protocol);
    try std.testing.expect(!disabled.h3_datagram);
    try std.testing.expectEqual(@as(u64, 0), disabled.wt_enabled);
    try std.testing.expectEqual(@as(u64, 0), disabled.enable_webtransport);
    try std.testing.expectEqual(@as(u64, 0), disabled.webtransport_max_sessions);
}

test "zix webtransport: the WebTransport transport parameters parse out of the client hello" {
    // max_datagram_frame_size (0x20, RFC 9221 3) and reset_stream_at (0x1d, reliable reset 3) are what
    // the feature is built on: without the first a session has only streams, and without the second a
    // draft-16 reset cannot carry the stream header. They arrive beside the flow control limits the
    // response path reads.
    var body: [64]u8 = undefined;
    var pos: usize = 0;
    pos += writeParam(body[pos..], 0x04, 1 << 20);
    pos += writeParam(body[pos..], 0x05, 4096);
    pos += writeParam(body[pos..], 0x20, 1200);
    pos += writeParam(body[pos..], 0x1d, null);

    const params = transport_params.parse(body[0..pos]);
    try std.testing.expectEqual(@as(u64, 1 << 20), params.initial_max_data);
    try std.testing.expectEqual(@as(u64, 4096), params.initial_max_stream_data_bidi_local);
    try std.testing.expectEqual(@as(u64, 1200), params.max_datagram_frame_size);
    try std.testing.expect(params.reset_stream_at);

    // The same bytes inside the ClientHello a server parses: the extension lookup is what decides
    // whether the feature is offered at all, and it has to find them where the parameters sit.
    var hello_buf: [256]u8 = undefined;
    const from_hello = transport_params.fromClientHello(buildClientHello(&hello_buf, body[0..pos])).?;
    try std.testing.expectEqual(params.initial_max_data, from_hello.initial_max_data);
    try std.testing.expectEqual(params.max_datagram_frame_size, from_hello.max_datagram_frame_size);
    try std.testing.expect(from_hello.reset_stream_at);

    // The frame size the handshake carried is the one the datagram layer enforces: a payload at the
    // boundary goes out and one byte past it does not, which is the arithmetic a sender has to do
    // before it queues anything.
    const session_id: u64 = 0;
    const fits = Webtransport.datagram.maxPayloadBytes(from_hello.max_datagram_frame_size, session_id);

    try std.testing.expect(fits != 0);
    try std.testing.expect(Webtransport.datagram.payloadFits(from_hello.max_datagram_frame_size, session_id, fits));
    try std.testing.expect(!Webtransport.datagram.payloadFits(from_hello.max_datagram_frame_size, session_id, fits + 1));
}
