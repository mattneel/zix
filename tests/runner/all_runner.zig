// Test runner for all protocols.
//
// Invoked by `zig build test-runner-all`. The build pushes one server binary
// path per check as argv, in the exact order of the `checks` table below: that
// table is the single source of truth for order, labels, ports, and arity, so
// adding a server means adding one row here (and the matching path in the
// build) rather than editing three parallel lists.
//
// The checks run concurrently in bounded waves (see runWaves): each check is
// self-contained (own server process, unique port), so they no longer block one
// another. Results are collected by table index and reported in table order, so
// the output stays stable. A check that shares a filesystem resource with
// another (the two /tmp/zix.sock users) carries a `resource` tag, and the
// scheduler never runs two checks with the same tag at once.
//
// Every check body runs in a child copy of this binary rather than in the
// runner itself (see isolate.zig): the runner respawns itself with `--only
// <label>`, which gives a parked check an upper bound the parent can enforce.
// The child prints its own PASS or FAIL line and the parent forwards it, so
// running a check alone is just `test-runner-all --only <label> <server path>`.
//
// A result line names the example the check runs, as its installed binary is
// named: `PASS zix-example-http_basic-x86_64-linux-debug`. The short `label` in the
// table stays the selector, and `--only` takes either that or the reported
// name, so rerunning one check is a copy of whatever the output said.
//
// The check bodies live in sibling files grouped by concern:
//   wire.zig         low-level TLS record / header / h2-frame-scan helpers
//   checks_http.zig  arena + http1 engines, h2c, http3
//   checks_tls.zig   https/1.1, h2, gRPC, SSE, WebSocket over TLS 1.3
//   checks_rpc.zig   gRPC + FIX
//   checks_misc.zig  TCP, UDP, UDS, Channel
//   checks_jzon.zig  a JSON request body and a JSON response body through jzon
//   checks_webrtc.zig  ICE + DTLS + SCTP + data channel, one whole session
//   report_name.zig  what a check calls itself in its result line

const std = @import("std");
const common = @import("common.zig");
const isolate = @import("isolate.zig");
const group_run = @import("group_run.zig");
const report_name = @import("report_name.zig");
const checks_http = @import("checks_http.zig");
const checks_tls = @import("checks_tls.zig");
const checks_rpc = @import("checks_rpc.zig");
const checks_misc = @import("checks_misc.zig");
const checks_query = @import("checks_query.zig");
const checks_jzon = @import("checks_jzon.zig");
const checks_webrtc = @import("checks_webrtc.zig");

// --------------------------------------------------------- //

/// Uniform check entry point: every wrapper in the `checks` table has this shape and pulls the server
/// path(s) it needs out of the per-check `paths` slice (length equals the row's `arity`).
const RunFn = *const fn (std.Io, []const []const u8) anyerror!void;

const Check = struct {
    /// Short selector, what `--only` takes and what the off-platform skip reads.
    label: []const u8,
    /// The example this check exercises, by file stem. What the check reports itself as is built
    /// from this, so a result line names a file a reader can open.
    example: []const u8,
    run: RunFn,
    /// Number of consecutive argv server paths this check consumes (uds-http and channel-ipc take 2).
    arity: u8 = 1,
    /// Shared filesystem path this check needs exclusively, or null. The scheduler never runs two
    /// checks with the same tag concurrently.
    resource: ?[]const u8 = null,
    /// CPU-heavy startup or handshake (TLS / QUIC). The scheduler caps how many of these run at once
    /// so a wave of them cannot starve each other into bind or handshake timeouts.
    heavy: bool = false,
};

const zix_sock = "tmp/zix.sock";
const zix_ipc_sock = "tmp/zix_ipc.sock";

const checks = [_]Check{
    // Basic per-engine checks: one unified example each, on the dispatch model its target picks.
    .{ .label = "http", .example = "http_basic", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttp(io, paths[0], 9000);
        }
    }.call },
    .{ .label = "http1", .example = "http1_basic", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttp1(io, paths[0], 9015);
        }
    }.call },
    .{ .label = "grpc", .example = "grpc_server", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_rpc.runGrpc(io, paths[0], 9032);
        }
    }.call },
    .{ .label = "tcp", .example = "tcp_server", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runTcp(io, paths[0], 9043);
        }
    }.call },
    .{ .label = "fix", .example = "fix_server", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_rpc.runFix(io, paths[0], 9048);
        }
    }.call },
    .{ .label = "http2", .example = "http2_basic", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttp2(io, paths[0], 9065);
        }
    }.call },
    .{ .label = "udp", .example = "udp_server", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runUdp(io, paths[0]);
        }
    }.call },
    .{ .label = "udp-raw", .example = "udp_server_raw", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runUdpRaw(io, paths[0]);
        }
    }.call },
    .{ .label = "uds", .example = "uds_server", .resource = zix_sock, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runUds(io, paths[0]);
        }
    }.call },

    // HTTP feature checks.
    .{ .label = "http-json", .example = "http_json", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9005, "/status", "", "server");
        }
    }.call },
    .{ .label = "http-middleware", .example = "http_middleware", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9006, "/public", "http://127.0.0.1", "public");
        }
    }.call },
    .{ .label = "http-params", .example = "http_params", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9007, "/echo?foo=bar", "", "foo");
        }
    }.call },
    .{ .label = "http-paths", .example = "http_paths", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9008, "/path", "", "");
        }
    }.call },
    .{ .label = "http-query", .example = "http_query", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_query.runHttpQuery(io, paths[0], 9080);
        }
    }.call },
    .{ .label = "http-timeout-resp", .example = "http_timeout_resp", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9010, "/ping", "", "pong");
        }
    }.call },
    .{ .label = "http-xtra-headers", .example = "http_xtra_headers", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpHeader(io, paths[0], 9011, "/info", "X-Server", "zix");
        }
    }.call },
    .{ .label = "http-manual-concurrent", .example = "http_manual_concurrent", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9014, "/", "", "hello");
        }
    }.call },
    .{ .label = "http-static", .example = "http_static", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpStatic(io, paths[0], 9009, "http_text_file.txt", "this is http text file example.", null);
        }
    }.call },
    .{ .label = "http-sse", .example = "http_sse", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runSse(io, paths[0], 9012);
        }
    }.call },
    .{ .label = "http-websocket", .example = "http_websocket", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runWs(io, paths[0], 9013, "/ws/lobby");
        }
    }.call },
    .{ .label = "http-compression", .example = "http_compression", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpCompression(io, paths[0], 9059);
        }
    }.call },

    // HTTP1 feature checks.
    .{ .label = "http1-json", .example = "http1_json", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9020, "/status", "", "server");
        }
    }.call },
    .{ .label = "http1-middleware", .example = "http1_middleware", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9021, "/public", "http://127.0.0.1", "public");
        }
    }.call },
    .{ .label = "http1-params", .example = "http1_params", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9022, "/echo?foo=bar", "", "foo");
        }
    }.call },
    .{ .label = "http1-paths", .example = "http1_paths", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9023, "/path", "", "");
        }
    }.call },
    .{ .label = "http1-query", .example = "http1_query", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_query.runHttpQuery(io, paths[0], 9079);
        }
    }.call },
    .{ .label = "http1-timeout-resp", .example = "http1_timeout_resp", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9025, "/ping", "", "pong");
        }
    }.call },
    .{ .label = "http1-xtra-headers", .example = "http1_xtra_headers", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpHeader(io, paths[0], 9026, "/info", "X-Server", "zix");
        }
    }.call },
    .{ .label = "http1-manual-concurrent", .example = "http1_manual_concurrent", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9030, "/", "", "hello");
        }
    }.call },
    .{ .label = "http1-static", .example = "http1_static", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpStatic(io, paths[0], 9024, "http1_text_file.txt", "this is http1 text file example.", "/upload-multipart");
        }
    }.call },
    .{ .label = "http1-sse", .example = "http1_sse", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runSse(io, paths[0], 9027);
        }
    }.call },
    .{ .label = "http1-websocket", .example = "http1_websocket", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runWs(io, paths[0], 9028, "/ws/lobby");
        }
    }.call },
    .{ .label = "http1-cache", .example = "http1_cache", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpGet(io, paths[0], 9031, "/cache?kb=1", "", "ok");
        }
    }.call },
    .{ .label = "http1-compression", .example = "http1_compression", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttpCompression(io, paths[0], 9058);
        }
    }.call },

    // gRPC feature checks.
    .{ .label = "grpc-location", .example = "grpc_location_server", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_rpc.runGrpcLocation(io, paths[0], 9038);
        }
    }.call },
    .{ .label = "grpc-multi", .example = "grpc_multi_server", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_rpc.runGrpcMulti(io, paths[0]);
        }
    }.call },
    .{ .label = "grpc-timeout", .example = "grpc_timeout", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_rpc.runGrpcTimeout(io, paths[0]);
        }
    }.call },

    // FIX trading check.
    .{ .label = "fix-trading", .example = "fix_server_trading", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_rpc.runFixTrading(io, paths[0]);
        }
    }.call },

    // UDS HTTP check (two server binaries: uds_server + uds_http).
    .{ .label = "uds-http", .example = "uds_http", .arity = 2, .resource = zix_sock, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runUdsHttp(io, paths[0], paths[1]);
        }
    }.call },

    // Channel self-terminating checks.
    .{ .label = "channel-basic", .example = "channel_basic", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runChannelSelfterm(io, paths[0]);
        }
    }.call },
    .{ .label = "channel-pipeline", .example = "channel_pipeline", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runChannelSelfterm(io, paths[0]);
        }
    }.call },
    .{ .label = "channel-worker-pool", .example = "channel_worker_pool", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runChannelSelfterm(io, paths[0]);
        }
    }.call },

    // Channel IPC check (two server binaries: ipc_a + ipc_b).
    .{ .label = "channel-ipc", .example = "channel_ipc_a", .arity = 2, .resource = zix_ipc_sock, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runChannelIpc(io, paths[0], paths[1]);
        }
    }.call },

    // TLS checks (native clients, no curl): https/1.1, ed25519 variant, h2, gRPC over h2.
    .{ .label = "tls-http1", .example = "tls_http1_basic", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTls(io, paths[0], 9060);
        }
    }.call },
    .{ .label = "tls-http1-ed25519", .example = "tls_http1_ed25519", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsHttp1Ed25519(io, paths[0], 9062);
        }
    }.call },
    .{ .label = "tls-http2", .example = "tls_http2_basic", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsHttp2(io, paths[0], 9061);
        }
    }.call },
    .{ .label = "tls-grpc", .example = "tls_grpc_basic", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsGrpc(io, paths[0], 9070);
        }
    }.call },

    // HTTP/3 check (QUIC over TLS 1.3, native hand-rolled client, no external tool).
    .{ .label = "http3-basic", .example = "http3_basic", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runHttp3(io, paths[0], 9063);
        }
    }.call },

    // SSE over TLS (ADR-054): https streaming on the arena and http1 engines, native TLS client.
    .{ .label = "tls-http-sse", .example = "tls_http_sse", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsSse(io, paths[0], 9072);
        }
    }.call },
    .{ .label = "tls-http1-sse", .example = "tls_http1_sse", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsSse(io, paths[0], 9073);
        }
    }.call },

    // WebSocket over TLS (ADR-055): wss echo on the http1 and arena engines, native TLS client.
    .{ .label = "tls-http1-ws", .example = "tls_http1_ws", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsWs(io, paths[0], 9074);
        }
    }.call },
    .{ .label = "tls-http-ws", .example = "tls_http_ws", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsWs(io, paths[0], 9075);
        }
    }.call },

    // https/1.1 over TLS 1.3 on the arena engine (zix.Http). Appended last so the argv order of the
    // existing checks stays stable. Same native TLS GET as tls-http1, different engine.
    .{ .label = "tls-http", .example = "tls_http_basic", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTls(io, paths[0], 9071);
        }
    }.call },

    // Dual listener (config.tls_port, ADR-060): appended last so the argv order of the existing
    // checks stays stable. One server answers cleartext AND https from the same worker fleet.
    .{ .label = "tls-http1-dual", .example = "tls_http1_dual", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_tls.runTlsHttp1Dual(io, paths[0], 9076, 9077);
        }
    }.call },

    // WebRTC data channel: ICE, DTLS, SCTP, and DCEP in one session between two zix processes.
    // Appended last so the argv order of the existing checks stays stable.
    .{ .label = "webrtc-datachannel", .example = "webrtc_datachannel_echo", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_webrtc.runWebrtc(io, paths[0], 9083);
        }
    }.call },

    // jzon in both directions over http1: the case table, then a rendered record posted back as a
    // request body. Appended last so the argv order of the existing checks stays stable.
    .{ .label = "http1-jzon", .example = "http1_jzon", .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_jzon.runJzon(io, paths[0], 9033);
        }
    }.call },

    // udp tickrate pair (server + client executables, arity 2). Appended last so the
    // argv order of the existing checks stays stable.
    .{ .label = "udp-tickrate", .example = "udp_server_tickrate", .arity = 2, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_misc.runUdpTickrate(io, paths[0], paths[1]);
        }
    }.call },

    // WebTransport over HTTP/3: an extended CONNECT session on /echo, a data stream echo, a datagram
    // echo, and the banner the server writes on the unidirectional stream it opens. Appended last so
    // the argv order of the existing checks stays stable.
    .{ .label = "webtransport", .example = "http3_webtransport", .heavy = true, .run = &struct {
        fn call(io: std.Io, paths: []const []const u8) anyerror!void {
            return checks_http.runWebtransport(io, paths[0], 9089);
        }
    }.call },
};

/// Total argv server paths the checks table consumes (sum of every row's arity).
const total_paths = blk: {
    var sum: usize = 0;
    for (checks) |c| sum += c.arity;
    break :blk sum;
};

/// Widest arity in the table, sizing the child's path buffer.
const max_arity = blk: {
    var widest: u8 = 1;
    for (checks) |c| widest = @max(widest, c.arity);
    break :blk widest;
};

/// The check that owns argv path `index`, for naming a missing path.
fn labelForPath(index: usize) []const u8 {
    var seen: usize = 0;
    for (checks) |c| {
        seen += c.arity;
        if (index < seen) return c.label;
    }

    return "unknown";
}

/// The table row carrying `label`, or null when no row does.
///
/// Note:
/// - Takes the short label or the name a result line printed, so rerunning one check is a copy of
///   whatever the output said.
fn findCheck(label: []const u8) ?Check {
    for (checks) |c| {
        if (std.mem.eql(u8, c.label, label)) return c;

        var buf: [report_name.MAX_LEN]u8 = undefined;

        if (std.mem.eql(u8, report_name.write(&buf, c.example), label)) return c;
    }

    return null;
}

// --------------------------------------------------------- //

/// Running tally so the final count is derived from the actual number of report() calls, not a
/// hardcoded total.
const Tally = struct { total: usize = 0, failed: usize = 0 };

fn exitMissing(name: []const u8) noreturn {
    std.debug.print("FAIL: missing {s} server path\n", .{name});
    std.process.exit(1);
}

/// Print a check's own outcome. Only a child copy of the runner calls this, since only a child runs
/// a check body.
fn report(label: []const u8, result: anyerror!void, tally: *Tally) void {
    tally.total += 1;
    if (result) {
        common.printPass(label);
    } else |err| {
        _ = common.takeFallbackNote();
        std.debug.print("FAIL {s}: {}\n", .{ label, err });
        tally.failed += 1;
    }
}

/// Print what a check's child reported and fold the outcome into the tally. Only the parent calls
/// this, and it calls it as it awaits each slot, which is what keeps results in table order however
/// the checks themselves finished.
fn forwardResult(io: std.Io, result: isolate.Result, tally: *Tally) void {
    tally.total += 1;
    if (result.verdict != .PASSED) tally.failed += 1;

    isolate.forward(io, result.report);
}

// --------------------------------------------------------- //

/// One concurrent task: run a check in its own child process, retrying the whole check while its
/// verdict says another attempt is worth spawning (see isolate.attemptCap). The check is
/// self-contained (the child spawns its own server and kills it on return, even on error), so each
/// retry respawns from a clean slate. A short backoff between attempts lets a momentary load spike
/// clear instead of respawning straight back into it.
fn runIsolatedCheck(
    io: std.Io,
    self_exe: []const u8,
    label: []const u8,
    paths: []const []const u8,
    timeout_ms: u32,
    report_buf: []u8,
) isolate.Result {
    var attempt: usize = 1;
    while (true) : (attempt += 1) {
        const result = isolate.runIsolated(io, self_exe, label, paths, timeout_ms, report_buf);
        if (attempt >= isolate.attemptCap(result.verdict)) return result;

        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(750), .awake) catch {};
    }
}

/// Child mode: run exactly one check, print its result line, and exit with the code the parent reads.
/// One attempt only, since retries belong to the parent.
///
/// Note:
/// - The first thing this does is take a process group of its own, before the check spawns any
///   server. A check that parks is killed by the parent, and a killed process runs no defers, so
///   the group is the only handle left on the server it started.
fn runOneCheck(io: std.Io, arg_iter: *std.process.Args.Iterator) noreturn {
    group_run.leadOwnGroup();

    const label = arg_iter.next() orelse exitMissing(isolate.ONLY_FLAG);
    const check = findCheck(label) orelse {
        std.debug.print("FAIL: no check named {s}\n", .{label});
        std.process.exit(isolate.Exit.FAILED);
    };

    var paths: [max_arity][]const u8 = undefined;
    for (0..check.arity) |i| paths[i] = arg_iter.next() orelse exitMissing(label);

    var name_buf: [report_name.MAX_LEN]u8 = undefined;

    var tally: Tally = .{};
    const result = check.run(io, paths[0..check.arity]);
    report(report_name.write(&name_buf, check.example), result, &tally);

    if (result) {
        std.process.exit(isolate.Exit.PASSED);
    } else |err| {
        std.process.exit(if (isolate.isRetriable(err)) isolate.Exit.RETRIABLE else isolate.Exit.FAILED);
    }
}

/// Whether any in-flight slot in the current wave already holds this shared resource.
fn resourceBusy(active: []const ?[]const u8, res: []const u8) bool {
    for (active) |held| {
        if (held) |h| {
            if (std.mem.eql(u8, h, res)) return true;
        }
    }

    return false;
}

/// Hard ceiling on wave width, sizing the per-wave slot arrays. The live width is chosen at runtime
/// from the CPU count (see waveWidth) and is always <= this.
const WAVE_MAX = 16;

/// Live wave width scaled to the host. Each engine server spawns a worker pool sized to the CPU
/// count (a multiplexed server is one worker per CPU), so starting too many servers at once oversubscribes the
/// cores, starves a fresh server's accept threads, and the runner's connect probe then gets refused
/// (a flaky "ServerStartTimeout"). Conservative on purpose: a small box can only bring up a few of
/// these heavyweight servers at a time, a large box scales out. The per-check retry (see runCheck) is
/// the safety net for the occasional starved server, so this need not be tuned all the way to zero.
fn waveWidth(cpu_count: usize) usize {
    return std.math.clamp(cpu_count / 4, 2, WAVE_MAX);
}

/// Live cap on concurrent CPU-heavy TLS / QUIC checks (crypto handshakes plus a worker pool), tighter
/// than waveWidth. On a small box this serializes them so each gets the cores it needs to hand shake.
fn maxHeavy(cpu_count: usize) usize {
    return std.math.clamp(cpu_count / 12, 1, 3);
}

// --------------------------------------------------------- //

/// Run every check concurrently in waves whose width is scaled to the host, reporting each result as
/// its wave completes. Two limits shape a wave: a check whose `resource` tag is already in flight is
/// deferred so two checks that share a filesystem path never overlap, and at most `max_heavy` of the
/// CPU-heavy TLS / QUIC checks run at once so a wave cannot starve them into timeouts.
///
/// Output streams in stable table order: a wave is a contiguous block of checks, waves run in index
/// order, and within a wave the slots are awaited and reported in index order. report() runs only
/// here on the main thread (never on the concurrent check threads), so the prints never interleave.
fn runWaves(io: std.Io, self_exe: []const u8, all_paths: []const []const u8, tally: *Tally, cpu_count: usize, timeout_ms: u32) void {
    const wave_width = waveWidth(cpu_count);
    const max_heavy = maxHeavy(cpu_count);
    const CheckFuture = std.Io.Future(isolate.Result);

    var check_idx: usize = 0;
    var path_cursor: usize = 0;
    while (check_idx < checks.len) {
        var futures: [WAVE_MAX]CheckFuture = undefined;
        var slot_check: [WAVE_MAX]usize = undefined;
        var slot_res: [WAVE_MAX]?[]const u8 = undefined;
        // One report buffer per slot: the child writes its line here while the wave is in flight, and
        // the parent reads it back when it awaits that slot.
        var slot_report: [WAVE_MAX][isolate.REPORT_MAX]u8 = undefined;
        var count: usize = 0;
        var heavy_count: usize = 0;

        while (check_idx < checks.len and count < wave_width) {
            const check = checks[check_idx];
            if (common.skipDispatchOffPlatform(check.label)) {
                tally.total += 1;
                path_cursor += check.arity;
                check_idx += 1;
                continue;
            }
            if (check.resource) |res| {
                if (resourceBusy(slot_res[0..count], res)) break;
            }
            if (check.heavy and heavy_count == max_heavy) break;

            const paths = all_paths[path_cursor..][0..check.arity];
            futures[count] = io.async(runIsolatedCheck, .{ io, self_exe, check.label, paths, timeout_ms, slot_report[count][0..] });
            slot_check[count] = check_idx;
            slot_res[count] = check.resource;

            if (check.heavy) heavy_count += 1;
            path_cursor += check.arity;
            count += 1;
            check_idx += 1;
        }

        for (0..count) |slot| {
            const result = futures[slot].await(io);
            forwardResult(io, result, tally);
        }
    }
}

pub fn main(process: std.process.Init) void {
    const io = process.io;

    var arg_iter = common.argsIterator(process.minimal.args);

    // argv[0] is how a check gets respawned as a child, so it is kept rather than skipped. zig build
    // invokes the runner by its emitted path, which is what std.process.spawn needs.
    const self_exe = arg_iter.next() orelse exitMissing("runner path");
    const first = arg_iter.next() orelse exitMissing(labelForPath(0));

    // Child mode: this copy runs one check and exits, it never schedules a wave.
    if (std.mem.eql(u8, first, isolate.ONLY_FLAG)) runOneCheck(io, &arg_iter);

    // Collect server paths in argv order, one slot per declared check path.
    var all_paths: [total_paths][]const u8 = undefined;
    all_paths[0] = first;
    var path_idx: usize = 1;
    while (path_idx < total_paths) : (path_idx += 1) {
        all_paths[path_idx] = arg_iter.next() orelse exitMissing(labelForPath(path_idx));
    }

    // Run all checks concurrently in bounded waves (width scaled to the host), streaming each wave's
    // results in table order as it completes. The per-check kill bound is the native default unless
    // the environment widens it (the qemu CI legs do).
    const cpu_count = std.Thread.getCpuCount() catch 4;
    const check_timeout_ms = isolate.checkTimeoutMs(process.environ_map.get(isolate.CHECK_TIMEOUT_ENV));

    var tally: Tally = .{};

    runWaves(io, self_exe, &all_paths, &tally, cpu_count, check_timeout_ms);

    if (tally.failed > 0) {
        std.debug.print("{d}/{d} example(s) failed\n", .{ tally.failed, tally.total });
        std.process.exit(1);
    }

    std.debug.print("zix: all {d} examples passed\n", .{tally.total});
}
