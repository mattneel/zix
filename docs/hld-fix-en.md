# HLD: zix.Fix

FIX 4.x session protocol server. SOH-delimited (0x01) tag=value framing. Built entirely in Zig: no C FFI, no external libraries.

---

## Status

Implemented. See ADR-024 for design rationale.

---

## Goals

- Explicit over implicit: same config and dispatch-model pattern as `zix.Tcp`.
- SOH-delimited framing: no length prefix, delimiter-based message boundary detection.
- Session layer built in: Logon / Logout / Heartbeat / TestRequest handled automatically, all other messages are echoed.
- No heap allocation in `serveConn`: stack buffers throughout.
- ASYNC, EPOLL, and URING dispatch. Required with no default: ASYNC suits long-lived FIX sessions and is the only portable model. EPOLL and URING run shared-nothing per-core workers on Linux, and `run()` rejects both off Linux with `error.ZixDispatchModelUnsupported` (ADR-065).
- `io: std.Io` in config (not passed to `run()`).

---

## Source Layout

```
src/tcp/fix/
    Fix.zig      // namespace aggregator
    core.zig     // parsing, building, checksum, serveConn, MsgType, FixRequest, FixResponse, FixContext, HandlerFn, FixRoute
    config.zig   // FixServerConfig, FixClientConfig
    server.zig   // FixServer: thin run() switch over dispatch/ (ASYNC, EPOLL, URING)
    dispatch/    // per-model files: async.zig, epoll.zig, uring.zig, common.zig
    router.zig   // comptime FixRouter
    client.zig   // FixClient
```

Export from `src/lib.zig`:
```zig
pub const Fix = @import("tcp/fix/Fix.zig");
// zix.Fix.Server, zix.Fix.ServerConfig, zix.Fix.Client, zix.Fix.ClientConfig, zix.Fix.serveConn, ...
```

---

## Public API

| Symbol | Type | Description |
| :- | :- | :- |
| `zix.Fix.Server` | struct | `init(handler, config)` / `deinit()` / `run()` (ADR-063: `handler: ?HandlerFn`, built via `Router(&routes).dispatch`; `null` keeps echo mode) |
| `zix.Fix.ServerConfig` | struct | See Server Config Fields below |
| `zix.Fix.ServeOpts` | struct | `{ logger, default_heartbeat_secs, heartbeat_timeout_ms, conn_timeout_ms, handler_timeout_ms, handler }`: options for `serveConn` |
| `zix.Fix.Client` | struct | `connect(config, io)` / `deinit(io)` / `logon(io, heart_bt_int)` / `logout(io)` / `sendMessage(io, msg_type, extra)` / `recvMessage(io)` |
| `zix.Fix.ClientConfig` | struct | See Client Config Fields below |
| `zix.Fix.DispatchModel` | enum(u8) | Re-export of `zix.Tcp.DispatchModel` |
| `zix.Fix.Tag` | enum(u16) | Nonexhaustive enum of standard FIX 4.x tag numbers. Use `@enumFromInt` for custom tags not listed |
| `zix.Fix.MsgType` | struct | Namespace of compile-time string constants for FIX MsgType (tag 35) values. See MsgType Constants section |
| `zix.Fix.HandlerFn` | type | `*const fn (req: *Request, res: *Response, ctx: *Context) anyerror!void` (ADR-063 trio): application message handler |
| `zix.Fix.Route` | struct | `{ msg_type: []const u8, handler: HandlerFn, timeout_ms: u32 = 0 }`: one application message route |
| `zix.Fix.Request` | struct | `{ fields: []const Field }`, `getField(tag) ?[]const u8`: zero-copy view over the received message |
| `zix.Fix.Response` | struct | `sendMessage(msg_type, fields)`: builder over `buildMessage` plus the SOH-framed write, independent of `Context` |
| `zix.Fix.Context` | struct | Per-connection context passed to each handler. Fields: `sender_comp_id`, `target_comp_id`, `deadline_ns`. Methods: `withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut` |
| `zix.Fix.Router(routes)` | comptime fn | Returns a comptime dispatch type with `dispatch(req, res, ctx) anyerror!void`, matching `HandlerFn` exactly |
| `zix.Fix.wallClockNs` | fn | `std.os.linux.clock_gettime(.REALTIME)` -> u64 nanoseconds (same as `zix.Grpc.wallClockNs`) |
| `zix.Fix.Field` | struct | `{ tag: Tag, value: []const u8 }`: zero-copy slice into receive buffer |
| `zix.Fix.BuildField` | struct | `{ tag: Tag, value: []const u8 }`: input to `buildMessage` |
| `zix.Fix.SOH` | u8 | `0x01`: field delimiter |
| `zix.Fix.VERSION` | []const u8 | `"FIX.4.2"` |
| `zix.Fix.MAX_FIELDS` | usize | 64: max fields parsed per message |
| `zix.Fix.MAX_MSG_SIZE` | usize | 8192: max message bytes |
| `zix.Fix.findMessageEnd` | fn | Scans buf for end of first complete FIX message, returns index past final SOH or null |
| `zix.Fix.parseFields` | fn | Parses raw bytes into `[]Field` (zero-copy slices into buf) |
| `zix.Fix.getField` | fn | Returns value of first field with given `Tag`, or null |
| `zix.Fix.computeChecksum` | fn | Sum of all bytes mod 256 |
| `zix.Fix.verifyChecksum` | fn | Returns true if tag-10 checksum matches computed value |
| `zix.Fix.buildMessage` | fn | Builds a complete FIX message into caller-supplied output buffer |
| `zix.Fix.serveConn` | fn | Session handler: `serveConn(stream, io, comp_id, opts)` (reads messages, dispatches Logon/Logout/Heartbeat, routes application messages) |

---

## Server Config Fields

| Field | Default | Description |
| :- | :- | :- |
| `io` | required | Io backend. Caller-provided, must outlive the server |
| `ip` | required | Bind address |
| `port` | required | Bind port. Must be non-zero |
| `comp_id` | required | Server SenderCompID (tag 49) |
| `dispatch_model` | required, no default | ASYNC, EPOLL, or URING (EPOLL and URING are Linux-only: native epoll / io_uring, rejected off Linux with error.ZixDispatchModelUnsupported) |
| `kernel_backlog` | 1024 | TCP listen backlog |
| `workers` | 0 (cpu_count) | Accept thread count. Ignored by ASYNC |
| `worker_stack_size_bytes` | 512 KiB | Worker thread stack for EPOLL / URING handler threads. Demand-paged, costs little until the depth is used |
| `reuseport_cbpf` | false | SO_ATTACH_REUSEPORT_CBPF steering (EPOLL / URING): a new connection goes to the worker on the receiving CPU instead of the 4-tuple hash. Silent no-op on a kernel pre-4.5 |
| `uring_send_buf_size` | 64 KiB | Per-connection send buffer for URING. No effect under the other dispatch models |
| `uring_max_conns_per_worker` | 65536 | Max concurrent connections one URING worker tracks (fd-indexed slab). Connections past the cap are refused |
| `default_heartbeat_secs` | 30 | Default HeartBtInt (seconds) echoed in the Logon response when the client omits tag 108 |
| `logger` | null | Optional logger for lifecycle and per-message session events |
| `heartbeat_timeout_ms` | 0 | Heartbeat timeout in ms. 0 = disabled. When non-zero: after this interval with no incoming message, TestRequest (35=1) is sent. If no response arrives within another interval, Logout (35=5) is sent and the connection closes. Only applies after Logon, before Logon, timeout closes silently. |
| `conn_timeout_ms` | 0 | Idle connection timeout in ms. 0 = disabled. Only takes effect when `heartbeat_timeout_ms` is 0: if no message arrives within this interval, the connection is closed, no TestRequest dance, just close. |
| `handler_timeout_ms` | 0 | Server-wide default max handler processing time in ms. 0 = no cap. Tightened per-route by `Route.timeout_ms`. Sets `Context.deadline_ns` before dispatch. |

---

## Client Config Fields

| Field | Description |
| :- | :- |
| `ip` | required, server address |
| `port` | required, server port. Must be non-zero |
| `comp_id` | required, this client's SenderCompID (tag 49) |
| `target_comp_id` | required, server's TargetCompID (tag 56) |

---

## Protocol Overview

FIX (Financial Information eXchange) 4.x uses SOH (0x01) as a field delimiter. Each field is `tag=value\x01`. A complete message starts at tag-8 (BeginString) and ends with tag-10 (Checksum) followed by a final SOH:

```
8=FIX.4.2\x019=26\x0135=A\x0149=CLIENT\x0156=SERVER\x0134=1\x0198=0\x01108=30\x0110=NNN\x01
```

Key standard tags:

| Tag | Name | Role |
| :- | :- | :- |
| 8 | BeginString | Always `FIX.4.2` in this implementation |
| 9 | BodyLength | Byte count from tag-35 to end of tag-10 value (before final SOH) |
| 35 | MsgType | `A`=Logon, `5`=Logout, `0`=Heartbeat, `1`=TestRequest, `D`=NewOrderSingle, etc. |
| 49 | SenderCompID | Sending party identity |
| 56 | TargetCompID | Receiving party identity |
| 34 | MsgSeqNum | Per-session sequence number (starts at 1) |
| 10 | Checksum | Sum of all message bytes mod 256, formatted as 3-digit decimal |

---

## Tag Enum

FIX tag numbers are transmitted as ASCII integers on the wire (e.g. `35`, `49`, `108`). Reading numeric literals in code requires knowing the FIX spec by memory. `zix.Fix.Tag` is a nonexhaustive `enum(u16)` that maps standard tag numbers to named constants, the wire format is unchanged.

```zig
pub const Tag = enum(u16) {
    MsgType      = 35,
    SenderCompID = 49,
    TargetCompID = 56,
    MsgSeqNum    = 34,
    HeartBtInt   = 108,
    // ... 55 tags total
    _,  // catch-all: any u16 is a valid Tag value
};
```

### Covered tags

Session layer: `BeginString` (8), `BodyLength` (9), `CheckSum` (10), `MsgSeqNum` (34), `MsgType` (35), `SenderCompID` (49), `SenderSubID` (50), `SendingTime` (52), `TargetCompID` (56), `TargetSubID` (57), `PossDupFlag` (43), `PossResend` (97), `EncryptMethod` (98), `HeartBtInt` (108), `TestReqID` (112), `OrigSendingTime` (122), `GapFillFlag` (123), `LastMsgSeqNumProcessed` (369).

Order and execution: `Account` (1), `AvgPx` (6), `ClOrdID` (11), `CumQty` (14), `Currency` (15), `ExecID` (17), `ExecTransType` (20), `HandlInst` (21), `LastPx` (31), `LastShares` (32), `OrderID` (37), `OrderQty` (38), `OrdStatus` (39), `OrdType` (40), `OrigClOrdID` (41), `Price` (44), `Side` (54), `StopPx` (99), `TimeInForce` (59), `TransactTime` (60), `ExecType` (150), `LeavesQty` (151).

Instrument: `SecurityID` (48), `SecurityIDSource` (22), `Symbol` (55), `Text` (58), `ExDestination` (100), `SecurityType` (167), `MaturityMonthYear` (200), `SecurityExchange` (207), `TradeDate` (75).

Repeating group counts: `NoRelatedSym` (146), `NoMDEntries` (268), `NoPartyIDs` (453), `NoUnderlyings` (539), `NoLegs` (555).

### How to use

Reading a field by name:

```zig
const msgtype  = zix.Fix.getField(fslice, .MsgType)      orelse return;
const sender   = zix.Fix.getField(fslice, .SenderCompID) orelse "";
const seq_str  = zix.Fix.getField(fslice, .MsgSeqNum)    orelse "0";
```

Building a message with named fields:

```zig
try client.sendMessage(io, "D", &[_]zix.Fix.BuildField{
    .{ .tag = .ClOrdID,  .value = "ORD-001" },
    .{ .tag = .Symbol,   .value = "AAPL" },
    .{ .tag = .Side,     .value = "1" },
    .{ .tag = .OrderQty, .value = "100" },
    .{ .tag = .OrdType,  .value = "2" },
    .{ .tag = .Price,    .value = "185.50" },
});
```

### Custom and extension tags

The enum is nonexhaustive (`_`). Any `u16` is a valid `Tag` value: use `@enumFromInt` for tags not listed:

```zig
const my_tag: zix.Fix.Tag = @enumFromInt(9999);
const extra = [_]zix.Fix.BuildField{
    .{ .tag = @enumFromInt(9001), .value = "custom-data" },
};
```

`parseFields` converts wire integers to `Tag` via `@enumFromInt` automatically, no conversion needed when reading received fields.

### Considerations

- The backing type is `u16`, matching the `Field.tag` and `BuildField.tag` fields. No runtime cost vs storing a raw `u16`.
- Unknown tags received from the wire (`parseFields`) become nonexhaustive enum values: they compare correctly with `==` and print as their integer value.
- The enum does not validate tag values or enforce FIX version restrictions. All semantic validation remains the application's responsibility.
- `getField` accepts `Tag`: passing a raw integer literal directly no longer compiles. Use the named constant or `@enumFromInt(n)`.

---

## Session Layer

`serveConn` implements the FIX session layer automatically. No handler callback: all session logic is inside `serveConn`:

| MsgType (tag 35) | Server action |
| :- | :- |
| `A` (Logon) | Respond with Logon (`A`), CompIDs swapped, seq=1 |
| `5` (Logout) | Respond with Logout (`5`), then close connection |
| `0` (Heartbeat) | Respond with Heartbeat (`0`) |
| `1` (TestRequest) | Respond with Heartbeat (`0`) |
| any other (routes non-empty) | Dispatch to matching `Route.handler` via `FixRouter`. If no route matches, message is silently ignored |
| any other (routes empty) | Echo the message back unchanged (backward-compatible echo mode) |

Bad checksum closes the connection without a response.

---

## MsgType Constants

FIX MsgType values (tag 35) are ASCII strings, not integers. `zix.Fix.MsgType` is a namespace struct of 44 compile-time string constants covering FIX 4.0-4.4. Use these instead of raw string literals to avoid typos and aid readability.

```zig
// Session
zix.Fix.MsgType.Heartbeat                   // "0"
zix.Fix.MsgType.TestRequest                 // "1"
zix.Fix.MsgType.ResendRequest               // "2"
zix.Fix.MsgType.Reject                      // "3"
zix.Fix.MsgType.SequenceReset               // "4"
zix.Fix.MsgType.Logout                      // "5"
zix.Fix.MsgType.Logon                       // "A"

// Application (single-char)
zix.Fix.MsgType.ExecutionReport             // "8"
zix.Fix.MsgType.OrderCancelReject           // "9"
zix.Fix.MsgType.IOIAcknowledgement          // "6"
zix.Fix.MsgType.IOI                         // "C"
zix.Fix.MsgType.NewOrderSingle              // "D"
zix.Fix.MsgType.NewOrderList                // "E"
zix.Fix.MsgType.OrderCancelRequest          // "F"
zix.Fix.MsgType.OrderCancelReplaceRequest   // "G"
zix.Fix.MsgType.OrderStatusRequest          // "H"
zix.Fix.MsgType.Allocation                  // "J"
// ... and more (Quote, MarketData*, Security*, TradingSession*, etc.)

// Application (two-char, FIX 4.3-4.4)
zix.Fix.MsgType.TradeCaptureReport          // "AE"
zix.Fix.MsgType.OrderMassStatusRequest      // "AF"
```

Usage in route table and `sendMessage`:

```zig
&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle,    .handler = handleNewOrder },
    .{ .msg_type = zix.Fix.MsgType.OrderCancelRequest, .handler = handleCancel },
},

// in handler:
res.sendMessage(zix.Fix.MsgType.ExecutionReport, &[_]zix.Fix.BuildField{ ... });

// in client:
try client.sendMessage(io, zix.Fix.MsgType.NewOrderSingle, &order_fields);
```

---

## Router and Application Message Dispatch

Routes are wrapped in `Fix.Router(&routes)` and `.dispatch` is passed to `Fix.Server.init()` (ADR-063, mirrors the rest of the family). Session messages (Logon/Logout/Heartbeat/TestRequest) are always handled internally by `serveConn`. Only application messages (everything else) reach the router.

```zig
const router = zix.Fix.Router(&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle,    .handler = handleNewOrder,   .timeout_ms = 500 },
    .{ .msg_type = zix.Fix.MsgType.OrderCancelRequest, .handler = handleCancel,     .timeout_ms = 500 },
});

var server = try zix.Fix.Server.init(
    router.dispatch,
    .{
        .io                    = process.io,
        .ip                    = "0.0.0.0",
        .port                  = 9500,
        .comp_id               = "BROKER",
        .dispatch_model        = .ASYNC,
        .conn_timeout_ms       = 60_000,
        .handler_timeout_ms    = 200,
    },
);
```

`Server.init` takes `handler: ?HandlerFn`. Passing `null` enables echo mode (backward-compatible: all non-session messages are echoed).

### HandlerFn

```zig
fn handleNewOrder(req: *zix.Fix.Request, res: *zix.Fix.Response, ctx: *zix.Fix.Context) !void {
    if (ctx.isExpired()) return;
    const symbol = req.getField(.Symbol) orelse return;
    res.sendMessage(zix.Fix.MsgType.ExecutionReport, &[_]zix.Fix.BuildField{
        .{ .tag = .Symbol,    .value = symbol },
        .{ .tag = .OrdStatus, .value = "0" },
    });
}
```

### FixRequest / FixResponse / FixContext (ADR-063 trio)

| Type | Members |
| :- | :- |
| `FixRequest` | `fields: []const Field`, `getField(tag) ?[]const u8` (zero-copy view over the received message's fields) |
| `FixResponse` | `sendMessage(msg_type, fields)`: build and send a FIX response on this connection (swapped CompIDs), independent of `FixContext` so a handler may send from a captured closure after the context goes out of scope |
| `FixContext` | `sender_comp_id`, `target_comp_id` (session identity), `deadline_ns: ?u64` (absolute deadline, CLOCK_REALTIME nanoseconds, tightest of `handler_timeout_ms` / `Route.timeout_ms`, null = no deadline), `withTimeout` / `setTimeout` / `withDeadline` / `isExpired()` / `timedOut()`, `io`, and a stack-arena `allocator` (`FixedBufferAllocator`, no heap call) |

### Deadline Override

```zig
ctx.deadline_ns = zix.Fix.wallClockNs() + 2 * std.time.ns_per_s; // extend to 2 s
ctx.deadline_ns = null;                                            // disable
// or via the helpers: ctx.setTimeout(2_000); ctx.withDeadline(deadline_ns);
```

### FixRouter (comptime)

`FixRouter(routes)` generates a comptime `dispatch` function matching `HandlerFn` exactly: `inline for` unrolled at comptime, zero runtime cost.

```zig
const r = zix.Fix.Router(&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle, .handler = handleNewOrder },
});
try r.dispatch(req, res, ctx);
```

`dispatch` reads the message type off `req.getField(.MsgType)` itself, matches it against the route table, tightens `ctx.deadline_ns` with `Route.timeout_ms` when set, then calls `route.handler(req, res, ctx)`. Pass `router.dispatch` to `Server.init` for the normal server path; call it directly only when driving `serveConn` manually.

---

## Handler Error Policy

The handler returns `anyerror!void`, and `res.sendMessage` returns an error union rather than `void`, so both the build step and the socket write are reportable.

| Condition | What the engine sends |
| :- | :- |
| the handler returned an error having sent nothing | Reject (`35=3`) with `RefSeqNum` (tag 45) of the failed message and `Text` (tag 58) `handler error` |
| the handler returned an error after sending a message | nothing, the message it sent stands as the answer |
| the handler caught the error itself | nothing, the handler owns the answer |

`res.sendMessage` reports two failures a handler could not see before:

- `error.ZixFixMessageTooLarge` when the built message does not fit `MAX_MSG_SIZE`.
- `error.BrokenPipe` when the counterparty is gone.

`try` is how the Reject above is reached. A handler that wants to answer differently catches instead:

```zig
fn handleNewOrder(req: *zix.Fix.Request, res: *zix.Fix.Response, ctx: *zix.Fix.Context) anyerror!void {
    // try: a failure here is answered with a Reject carrying the RefSeqNum
    const filled = try matchOrder(req);

    // catch: the answer is the handler's, the engine adds nothing
    res.sendMessage(zix.Fix.MsgType.ExecutionReport, filled.fields) catch {
        try res.sendMessage(zix.Fix.MsgType.OrderCancelReject, filled.reject_fields);
    };
}
```

A Reject is never sent on top of a message the handler already sent: to a counterparty that reads as two contradictory answers to one message.

## Framing

FIX uses delimiter-based framing (SOH = 0x01), not length-prefix framing. The receive loop accumulates bytes via `takeByte` until `findMessageEnd` detects a complete message. This avoids the `readSliceShort` deadlock that occurs when a large buffer is passed but the message is shorter than the buffer capacity (the buffer-larger-than-message deadlock).

```
recv_buf:  [complete message][leftover bytes][free]
                                      ^
                                      shifted after each message
```

---

## Dispatch Models

Same three models as `zix.Http.Server`. The field is required with no default. ASYNC suits long-lived FIX sessions and is the only portable model:

| Model | Workers | Notes |
| :- | :- | :- |
| `.ASYNC` | 1 accept thread | Long-lived sessions, standard FIX deployments, every platform |
| `.EPOLL` | cpu_count (Linux-only) | Shared-nothing: one SO_REUSEPORT listener and one epoll instance per worker. Rejected off Linux. |
| `.URING` | cpu_count (Linux-only) | Shared-nothing io_uring workers running a resumable session processor (`core.processFixRing`) per readable batch (ADR-037). Rejected off Linux. |

---

## Server Lifecycle

```
Fix.Server.init(handler, config): validates port != 0, io taken from config
    -> .run(): dispatches via dispatch_model, blocks until error
Fix.Server.deinit(): no-op (resources released in run() via defer)
```

---

## Logger Integration

When `config.logger` is non-null:
- `system(.INFO, "fix", ...)` on bind and shutdown.
- `session(msg_type, sender, target, seq, state)` after each message processed in `serveConn`.

See `docs/hld-logger-en.md` for log line format details.

---

## Examples

| File | Role | Port |
| :- | :- | :- |
| `examples/fix_server.zig` | echo-mode server, dispatch model picked per target (`.URING` on Linux, `.ASYNC` elsewhere) | 9048 |
| `examples/fix_server_trading.zig` | `.ASYNC` server with router: NewOrderSingle + OrderCancelRequest, JSON append, logger, timeouts | 9500 |
| `examples/fix_client.zig` | `FixClient` high-level client | 9500 |
| `examples/fix_client_raw.zig` | raw core primitives client | 9500 |
| `examples/fix_client_trading.zig` | trading client: buy/cancel/sell/cancel flow | 9500 |

---

###### end of hld-fix
