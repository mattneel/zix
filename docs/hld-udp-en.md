# HLD: zix.Udp

UDP server and client built on Zig 0.16.x `std.Io`. No relation to the TCP/HTTP layer.

---

## Goals

- Explicit over implicit: every behavior named in config.
- Cross-language interoperability: client can be Go, C++, Rust, or any language that speaks the same extern struct layout.
- No hardcoded packet type: user defines their own `extern struct`, zix is parameterized over it at comptime.
- Configurable endianness applied transparently on send and receive.
- Separation of concern: `src/udp/` has no import from `src/tcp/`.

---

## Runtime Model

### Server

```mermaid
flowchart TD
    A["UdpServer(Packet).run()"] --> B["IpAddress.bind(io, .dgram .udp)"]
    B --> C["receive loop"]
    C --> D["socket.receiveTimeout(io, buf, poll_timeout)"]
    D -->|Timeout| E["checkDisconnections(clients, now)"]
    E --> C
    D -->|datagram| F{"size == @sizeOf(Packet)?"}
    F -->|no| G["drop + optional NACK\n(0x15)"]
    G --> C
    F -->|yes| H["update ClientRecord\nor register new client"]
    H --> I{"broadcast enabled?"}
    I -->|yes| J["heap-alloc peer snapshot\n[]IpAddress"]
    I -->|no| K["peers = empty slice"]
    J --> L["io.concurrent(processPacket, task)"]
    K --> L
    L --> C
    L --> M["processPacket(task)"]
    M --> N{"auto_ack?"}
    N -->|yes| O["send 0x06 ACK to sender"]
    N -->|no| P{" "}
    O --> P
    P --> Q{"auto_echo?"}
    Q -->|yes| R["send buf back to sender"]
    Q -->|no| S{" "}
    R --> S
    S --> T{"broadcast?"}
    T -->|yes| U["send buf to each peer\nfree peer snapshot"]
    T -->|no| V["free peer snapshot (empty)"]
```

### Client

```mermaid
flowchart TD
    A["UdpClient(Packet).init(config, io, args)"] --> B["bind config.bind_ip:bind_port"]
    B --> C["resolve server IpAddress"]
    C --> D["client ready"]
    D --> E["send(packet)"]
    E --> F["toEndian(packet, config.endianness)"]
    F --> G["socket.send(io, dest, bytes)"]
    D --> H["receiveFeedback()"]
    H --> P{"recv_timeout_ms > 0 and poll times out?"}
    P -->|yes| Q["error.ZixRecvTimeout"]
    P -->|no| I["socket.receive(io, buf)"]
    I --> J{"len == 1?"}
    J -->|0x06| K[".ack"]
    J -->|other| L[".nack"]
    J -->|no| M{"len == @sizeOf(Packet)?"}
    M -->|yes| N["fromEndian(packet)\n.packet(Packet)"]
    M -->|no| O["error.ZixUnexpectedPacketSize"]
```

---

## Source Layout

```mermaid
graph TD
    zix["src/lib.zig"] --> Udp["udp/Udp.zig\nzix.Udp"]

    Udp --> config["config.zig\nEndianness, DispatchModel\nUdpServerConfig, UdpClientConfig"]
    Udp --> packet["packet.zig\nFeedbackResult\ntoEndian, fromEndian"]
    Udp --> server["server.zig\nUdpServer(Packet) (typed)"]
    Udp --> client["client.zig\nUdpClient(Packet)"]
    Udp --> core["core.zig\nHandlerFn, Sink (raw)"]
    Udp --> datagram["datagram.zig\nraw-fd socket\nrecvmmsg / sendmmsg"]
    Udp --> raw["raw.zig\nRaw(handler) facade\nrun() switch"]
    raw --> dispatch["dispatch/\ncommon + async /\nepoll / uring"]
```

---

## Public API

Access via `const zix = @import("zix");`

| Symbol | Type | Description |
| :- | :- | :- |
| `zix.Udp.Server(Packet)` | generic fn | Returns `UdpServer(Packet)` type (typed messaging) |
| `zix.Udp.Client(Packet)` | generic fn | Returns `UdpClient(Packet)` type |
| `zix.Udp.Raw(handler)` | generic fn | Returns the raw-bytes datagram server type (ADR-049) |
| `zix.Udp.Sink` | struct | Reply queue handed to a raw handler (`reply`, `replyTo`) |
| `zix.Udp.HandlerFn` | fn type | Raw handler: `fn([]const u8, *const IpAddress, *Sink) void` |
| `zix.Udp.DispatchModel` | enum(u8) | Shared with the TCP engines, selects the raw worker shape |
| `zix.Udp.ServerConfig` | struct | Server configuration |
| `zix.Udp.ClientConfig` | struct | Client configuration |
| `zix.Udp.Endianness` | enum(u8) | `NATIVE`, `LITTLE`, `BIG` |
| `zix.Udp.FeedbackResult(Packet)` | union(enum) | `.ack`, `.nack`, `.packet(Packet)` |
| `zix.Udp.toEndian(Packet, pkt, end)` | fn | Apply endianness before wire send |
| `zix.Udp.fromEndian(Packet, pkt, end)` | fn | Apply endianness after wire receive |

### UdpServer(Packet) methods

| Method | Description |
| :- | :- |
| `init(config, args)` | Port must be non-zero. When `config.allow_args` is set, reads `--ip` / `--port` from `args`, otherwise pass `.{}` and args are ignored |
| `run()` | Bind socket (io from config.io), enter receive loop. Blocks until error. |
| `deinit()` | Release resources. |

### UdpClient(Packet) methods

| Method | Description |
| :- | :- |
| `init(config, io, args)` | Binds socket immediately. When `config.allow_args` is set, reads `--bind-ip` / `--bind-port` / `--server-port` from `args`, otherwise pass `.{}` and args are ignored |
| `send(packet)` | Apply endianness and send to server |
| `receiveFeedback()` | Blocking receive: returns `FeedbackResult` |
| `deinit()` | Close socket. |

---

## UdpServerConfig

```zig
pub const UdpServerConfig = struct {
    io:                    std.Io,                     // caller-owned, must outlive the server
    allocator:             std.mem.Allocator,          // caller-owned (client list + broadcast snapshots, raw batches)
    ip:                    []const u8,                 // bind address
    port:                  u16,                        // bind port & must be non-zero
    allow_args:            bool       = false,          // when true, init reads --ip / --port from args
    endianness:            Endianness = .LITTLE,
    conn_timeout_ms:       u32        = 5000, // silence before client considered disconnected
    poll_timeout_ms:       i64        = 2000, // receiveTimeout interval for disconnect checks
    auto_ack:              bool       = false, // send 0x06 ACK to sender on receipt
    error_report:          bool       = false, // send 0x15 NACK on malformed/oversized datagram
    auto_echo:             bool       = false, // send received packet back to sender only
    broadcast:             bool       = false, // relay received packet to all connected clients
    logger:                ?*Logger   = null,  // lifecycle + per-packet logging when set

    // Datagram-transport knobs (ADR-049), used by the raw-bytes path (zix.Udp.Raw). The typed
    // path runs a single async loop: it folds a non-ASYNC dispatch_model with a notice and does
    // not use the batch / worker knobs.
    dispatch_model:        DispatchModel, // required. .EPOLL / .URING = per-core workers
    workers:               usize         = 0,      // 0 = one worker per CPU
    reuse_address:         bool          = false,  // SO_REUSEADDR + SO_REUSEPORT
    recv_batch:            usize         = 32,     // recvmmsg batch size
    send_batch:            usize         = 32,     // sendmmsg batch size
    max_recv_buf:          usize         = 1500,   // raw datagram buffer (typed uses @sizeOf(Packet))
    busy_poll_us:          u32           = 0,      // SO_BUSY_POLL spin window (0 = unset)
    reuseport_cbpf:        bool          = false,  // steer a datagram to the worker on the receiving CPU (ADR-061)
    worker_stack_size_bytes: usize       = 512 * 1024, // per-core worker thread stack
    gso_enabled:           bool          = false,  // UDP GSO on the send path
};
```

`io`, `allocator`, `ip`, and `port` are required (no defaults). `auto_ack` and `auto_echo` are independent: both can be true simultaneously (ACK then echo). `broadcast` sends to all clients, `auto_echo` sends only to the sender. The datagram-transport fields apply to the raw-bytes path (`zix.Udp.Raw`, see [Raw-bytes Mode](#raw-bytes-mode-adr-049)), the typed `Server(Packet)` leaves them unused beyond folding a non-ASYNC `dispatch_model`.

---

## UdpClientConfig

```zig
pub const UdpClientConfig = struct {
    ip:          []const u8, // server address to send packets to
    server_port: u16,        // server port & must be non-zero
    bind_ip:     []const u8 = "127.0.0.1", // local bind address, "0.0.0.0" for all interfaces
    bind_port:   u16,        // local port: server uses this to send responses back
    allow_args:  bool       = false, // when true, init reads --bind-ip / --bind-port / --server-port
    endianness:  Endianness = .LITTLE, // must match server
    recv_timeout_ms: u32    = 0,  // receive timeout via poll, 0 = blocking
};
```

`ip`, `server_port`, and `bind_port` are required (no defaults). `bind_ip` defaults to loopback (override with `--bind-ip` when `allow_args` is set), and `recv_timeout_ms` defaults to a blocking receive. `UdpClient` makes no heap allocations (all buffers are stack-allocated), so no `allocator` field is needed.

---

## Packet Model

The user defines their own `extern struct`. zix is parameterized over it at comptime.

```zig
// User-defined: must be an extern struct for fixed C ABI layout.
// All clients and the server must use the exact same definition.
const Packet = extern struct {
    id:          [16]u8,   // u8 arrays are NOT byte-swapped (identity bytes)
    packet_type: i32,      // swapped on non-native endian
    register:    u32,      // swapped on non-native endian
    position:    [3]f64,   // each element swapped on non-native endian
};

const MyServer = zix.Udp.Server(Packet);
const MyClient = zix.Udp.Client(Packet);
```

zix enforces at comptime (RFC 768):
```
@sizeOf(Packet) must be <= 65,507 bytes
(65,535 - 8 UDP header - 20 min IPv4 header)
```

---

## allow_args

A single `init(config, args)` takes the process args. The `allow_args` flag decides whether they are read.

| allow_args | Behavior | CLI key |
| :- | :- | :- |
| `false` (default) | Args are ignored. Port comes from the config struct. Pass `.{}` for `args`. | none |
| `true` | Recognized flags override the config. A missing or unknown flag keeps the config value. | `--ip` / `--port` (server), `--bind-ip` / `--bind-port` / `--server-port` (client) |

The port guard is independent of `allow_args`: `init()` fails with `error.ZixPortNotConfigured` when the resolved port is zero. Validation happens at `init()`, not at `run()`.

---

## Endianness

| Value | Description |
| :- | :- |
| `NATIVE` | No swap. Same machine only (unsafe across platforms or languages). |
| `LITTLE` | Swap if native is big-endian. Recommended for cross-language use (x86, ARM). |
| `BIG` | Swap if native is little-endian. Network byte order (RFC 791 convention). |

Endianness conversion is transparent: applied inside `send()` and `receive()`. User declares once in config. `toEndian` and `fromEndian` are the same operation (swap is its own inverse).

Swapping rules by field type:
- `int`: `@byteSwap`
- `float`: reinterpret as unsigned int, `@byteSwap`, reinterpret back
- `[N]T` where T is not u8: swap each element recursively
- `[N]u8`: no swap (identity bytes, e.g. id fields)

---

## Disconnect Detection

UDP has no connection state. Disconnect detection is purely timeout-based.

```mermaid
flowchart TD
    A["packet arrives"] --> B["update ClientRecord.last_seen"]
    B --> C{"poll_timeout_ms\nelapsed since last check?"}
    C -->|yes| D["checkDisconnections()"]
    C -->|no| E["skip check"]
    F["receiveTimeout (Timeout error)"] --> D
    D --> G["for each client:\nelapsed = now - last_seen"]
    G --> H{"elapsed >= conn_timeout_ms?"}
    H -->|yes| I["swapRemove from clients list\nlog disconnect"]
    H -->|no| J["keep client"]
```

Worst-case detection delay: `conn_timeout_ms + poll_timeout_ms`. There is no OS-level signal equivalent to TCP FIN.

---

## Feedback Shape

| Scenario | Server behavior | Client decodes as |
| :- | :- | :- |
| `auto_ack = true` | Send 1 byte `0x06` to sender | `.ack` |
| `error_report = true` | Send 1 byte `0x15` to sender on bad datagram | `.nack` |
| `auto_echo = true` | Send full packet back to sender | `.packet(Packet)` |
| `broadcast = true` | Send full packet to all connected clients | `.packet(Packet)` |

ACK/NACK byte values (`0x06`, `0x15`) are ASCII control codes (ACK, NAK). They are an application-level convention, not mandated by any RFC.

---

## Concurrency Model

Matches the TCP/HTTP pattern: the caller owns the `io` backend. Pass `process.io` for runtime-managed concurrency or `threaded.io()` for an explicit cap. `io.concurrent()` is used internally to dispatch `processPacket`.

---

## Memory Model

```mermaid
graph TD
    CA["config.allocator\ncaller-owned\nMUST be general-purpose"] -->|client list| CL["Managed(ClientRecord)\nprocess lifetime"]
    CA -->|broadcast peers| PS["[]IpAddress per packet\nallocated before concurrent dispatch\nfreed inside processPacket"]
    Stack["Stack"] -->|receive buffer| RB["[@sizeOf(Packet)]u8\nper receive loop iteration"]
```

| Scope | Allocator | Lifetime |
| :- | :- | :- |
| ClientRecord list | `config.allocator` | Server process lifetime |
| Peer snapshot (broadcast) | `config.allocator` | Single packet dispatch |
| Receive buffer | Stack | Single receive loop iteration |
| Socket | OS | `init()` to `deinit()` |

### Why ArenaAllocator is not suitable

`ArenaAllocator.free()` is a no-op: memory is only reclaimed when the entire arena is deinited. The broadcast peer snapshot is allocated and freed on every packet. Using an arena silently converts each `free(peers)` into a no-op, causing unbounded memory growth for the lifetime of the server:

```zig
// Each packet received when broadcast = true:
allocator.alloc(IpAddress, N)  // real allocation, arena grows
allocator.free(peers)          // no-op on ArenaAllocator, memory never reclaimed
// After M packets: M * N * @sizeOf(IpAddress) bytes held permanently
```

Use `std.heap.smp_allocator` (or any general-purpose allocator) so that `free()` is real. `std.testing.allocator` (backed by `GeneralPurposeAllocator`) is the correct choice in tests: it will catch any leak if the `free` path is ever broken.

---

## RFC Notes

- **RFC 768 (UDP)**: Port 0 is reserved. `init()` rejects it with `error.ZixPortNotConfigured`. Max payload is 65,507 bytes, enforced at comptime via `@compileError`.
- **RFC 791 / network convention**: `Endianness.BIG` corresponds to network byte order (big-endian).
- Timeout-based disconnect detection has no RFC (application-level behavior since UDP is connectionless).
- ACK (0x06) and NACK (0x15) byte values are ASCII control codes, not defined by any UDP RFC.

---

## Logger Integration

`UdpServerConfig.logger: ?*Logger = null`. When non-null:
- `system(.INFO, "udp", ...)` on bind and shutdown.
- `packet(.RECV, peer, size, err)` inside `processPacket` after each received datagram. `peer` is the sender address. `size` is `@sizeOf(Packet)`.

```zig
var logger = try zix.Logger.init(std.heap.smp_allocator, .{
    .console = .ALWAYS,
});
defer logger.deinit();

var server = try MyServer.init(.{
    .allocator = std.heap.smp_allocator,
    .ip        = "127.0.0.1",
    .port      = 9100,
    .logger    = &logger,
});
```

`frame()` is not auto-called by the UDP server (UDP has no framing layer). Use `logger.frame()` manually inside custom processing logic if needed.

See `docs/hld-logger-en.md` for log line format and config details.

---

## Raw-bytes Mode (ADR-049)

Alongside the typed `Server(Packet)`, `zix.Udp.Raw(handler)` serves variable-length datagrams with no fixed packet struct. It is the datagram-transport substrate the `zix.Http3` (QUIC) engine sits on, useful on its own for echo, DNS-style, and telemetry servers.

- Handler: `fn(datagram: []const u8, peer: *const std.Io.net.IpAddress, sink: *Sink) void`. It gets the bytes as received (up to `max_recv_buf`), the peer, and a `Sink`. `sink.reply(bytes)` answers the sender with no address conversion, `sink.replyTo(peer, bytes)` answers an explicit peer.
- Batched I/O (Linux): receive in `recvmmsg` batches (`recv_batch`), send in `sendmmsg` batches (`send_batch`). Replies coalesce into one `sendmmsg` per received batch. Non-Linux falls back to a single `std.Io.net` receive loop.
- Dispatch (`dispatch_model`, the same enum as the TCP engines, partitioned per ADR-043 into `src/udp/dispatch/`): `.ASYNC` runs a single worker. `.EPOLL` / `.URING` run one SO_REUSEPORT worker per CPU (per-core shared-nothing) and are Linux-only, rejected off Linux with `error.ZixDispatchModelUnsupported`. `.EPOLL` is an epoll readiness loop, `.URING` a real io_uring completion loop (epoll fallback when io_uring is unavailable).

```zig
fn handler(dg: []const u8, peer: *const std.Io.net.IpAddress, sink: *zix.Udp.Sink) void {
    sink.reply(dg); // echo back to the sender
}

const Echo = zix.Udp.Raw(handler);
var server = try Echo.init(.{ .io = io, .allocator = std.heap.smp_allocator, .ip = "0.0.0.0", .port = 9064, .dispatch_model = .ASYNC }, .{});
try server.run();
```

See `examples/udp_server_raw.zig` and ADR-049 (`docs/adr-en.md`).

---

## Not Yet Implemented

| Feature | Note |
| :- | :- |
| `sendmmsg` batching in the typed broadcast loop | Done in the raw path (`zix.Udp.Raw`). The typed broadcast still does N sequential `send()` |
| Raw GRO / ECN | Deferred (ADR-049 phase 2): need hardware-validated cmsg paths (GRO coalescing needs a splitter). GSO (UDP_SEGMENT) is implemented (`gso_enabled`) |
| Configurable feedback struct | Typed echo sends the raw packet back. Production could use a tagged result |
| Server tick-rate presets (64 / 128 Hz) | Not built in the engine. `examples/udp_server_tickrate.zig` shows the pattern: a fixed tick loop on `Raw(handler)` broadcasting a world snapshot per tick |

---

###### end of hld-udp
