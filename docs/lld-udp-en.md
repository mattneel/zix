# LLD: zix.Udp

Internal implementation details for the UDP layer. For design rationale see [`docs/hld-udp-en.md`](hld-udp-en.md).

---

## server.zig: UdpServer(Packet)

### Comptime size assert

At the top of `UdpServer(Packet)`:
```zig
// RFC 768: max UDP payload = 65,535 - 8 (UDP header) - 20 (min IPv4 header) = 65,507 bytes.
if (@sizeOf(Packet) > 65_507) @compileError("Packet size exceeds maximum UDP payload of 65,507 bytes (RFC 768)");
```

Fires at build time, not runtime.

### ClientRecord

```zig
const ClientRecord = struct {
    from:      std.Io.net.IpAddress,   // remote address used as client identity
    last_seen: std.Io.Clock.Timestamp, // for timeout-based disconnect detection
    index:     usize,                  // monotonic counter: for log output only
};
```

Client identity is the remote address. The index is informational, it is not stable across reconnects and is not used for routing.

### Receive loop

```
1. Bind: IpAddress.parse(ip, port) -> addr.bind(io, .dgram .udp) -> Socket
2. poll_timeout = Io.Timeout { .duration = fromMilliseconds(poll_timeout_ms) }
3. Loop:
      msg = socket.receiveTimeout(io, buf, poll_timeout)
      if Timeout:
        now = Timestamp.now(io, .awake)
        checkDisconnections(clients, now, conn_timeout_ms)
        last_check = now
        continue
      if msg.flags.trunc or msg.data.len != @sizeOf(Packet):
        if error_report: socket.send(io, &msg.from, &[_]u8{0x15})
        continue
      now = Timestamp.now(io, .awake)
      upsert ClientRecord for msg.from
      rate-limited checkDisconnections (if elapsed >= poll_timeout_ms since last_check)
      if broadcast: heap-alloc peer snapshot []IpAddress from clients
      io.concurrent(processPacket, Task{ ... })
```

### Task

```zig
const Task = struct {
    buf:          [@sizeOf(Packet)]u8,  // copy of received datagram bytes
    from:         std.Io.net.IpAddress, // sender address
    socket:       std.Io.net.Socket,    // shared: UDP send is kernel-atomic per datagram
    io:           std.Io,
    config:       UdpServerConfig,
    peers:        []std.Io.net.IpAddress, // heap-allocated snapshot, freed in processPacket
    sender_index: usize,
};
```

`Task` is passed by value to `io.concurrent()`. All fields are value types or handles that are safe to copy (no shared mutable state except `socket`, which is safe because UDP `send()` is kernel-atomic per datagram).

### processPacket()

```
defer: if peers.len > 0 -> task.config.allocator.free(peers)

if auto_ack:   socket.send(io, &from, &[_]u8{0x06})
if auto_echo:  socket.send(io, &from, &buf)
if broadcast:
    for each peer in peers:
        socket.send(io, peer, &buf)
        // SECURITY: no sender validation, spoofed IPs can trigger broadcast
        // PERF: N sequential send() syscalls, sendmmsg could reduce to 1
```

### checkDisconnections()

```
i = 0
while i < clients.items.len:
    elapsed = durationTo(clients.items[i].last_seen, now).raw.toMilliseconds()
    if elapsed >= timeout_ms:
        clients.swapRemove(i)  // O(1), order not preserved but does not matter
    else:
        i += 1
```

`swapRemove` replaces the removed entry with the last entry. Order of the clients list is not significant.

---

## client.zig: UdpClient(Packet)

### Comptime size assert

Same as server, fires at build time.

### init()

```
1. if bind_port == 0 or server_port == 0: return error.ZixPortNotConfigured
2. bind_addr = IpAddress.parse(config.bind_ip, bind_port)
3. socket = bind_addr.bind(io, .dgram .udp)  // one socket for both send and receive
4. dest = IpAddress.parse(config.ip, server_port)
5. return Self { config, socket, dest, io }
```

A single socket is used for both `send()` and `receiveFeedback()`. The server replies to the client's bound address.

### send()

```
wire = toEndian(Packet, packet_data, config.endianness)
socket.send(io, &dest, std.mem.asBytes(&wire))
```

### receiveFeedback()

```
if config.recv_timeout_ms > 0:
    if poll(socket, recv_timeout_ms) not ready: return error.ZixRecvTimeout  // poll, not SO_RCVTIMEO
buf: [@sizeOf(Packet)]u8 = undefined
msg = socket.receive(io, &buf)         // blocking unless the poll above timed out
if msg.data.len == 1:
    if data[0] == 0x06: return .ack
    else:               return .nack
if msg.data.len == @sizeOf(Packet):
    wire_pkt: Packet = @bitCast(buf)
    return .{ .packet = fromEndian(Packet, wire_pkt, config.endianness) }
return error.ZixUnexpectedPacketSize
```

Length dispatch is the decoding mechanism. ACK/NACK are single-byte responses, a full packet echo or broadcast relay has exactly `@sizeOf(Packet)` bytes.

---

## packet.zig: Endianness helpers

### swapFields() / swapField()

```
swapFields(T, ptr):
    inline for fields of T:
        swapField(field.type, &field_ptr)

swapField(T, ptr):
    switch typeInfo(T):
        .int   -> ptr.* = @byteSwap(ptr.*)
        .float -> Int = meta.Int(.unsigned, bits)
                  ptr.* = @bitCast(@byteSwap(@as(Int, @bitCast(ptr.*))))
        .array -> if @sizeOf(child) > 1:   // skip u8 arrays
                      for each element: swapField(child, &elem)
        else   -> no-op
```

`inline for` over struct fields is evaluated at comptime: the loop body is unrolled into per-field operations with no runtime branch overhead.

Float swapping uses `@bitCast` to reinterpret the float as an unsigned integer of the same bit width, applies `@byteSwap`, then reinterprets back. This is correct for IEEE 754 byte reversal.

### toEndian() / fromEndian()

```
toEndian(Packet, pkt, endianness):
    if endianness == .NATIVE: return pkt    // no-op
    native = builtin.cpu.arch.endian()
    target = if endianness == .LITTLE: .little else .big
    if native == target: return pkt         // already correct, no-op
    result = pkt
    swapFields(Packet, &result)
    return result

fromEndian = toEndian   // swap is its own inverse
```

Both functions return a new value while the original is not modified.

---

## config.zig: allow_args / Endianness / Configs

### allow_args gate

Both configs carry `allow_args: bool = false`. `init(config, args)` reads `--ip` / `--port` (server) or `--bind-ip` / `--bind-port` / `--server-port` (client) from `args` only when the flag is set, through `applyServerArgs` / `applyClientArgs`. A missing or unrecognized flag keeps the config value. The arg parse is compiled only when `args` is a real `std.process.Args`, so passing `.{}` (no CLI) skips it at comptime. The port guard runs regardless: a zero resolved port yields `error.ZixPortNotConfigured`.

### Enum backing values

`Endianness` is `enum(u8)`. Its integer values are stable and tested explicitly to catch accidental reordering.

```
Endianness: NATIVE=0, LITTLE=1, BIG=2
```

Stability matters because this enum may appear in serialized configs or be compared across build versions.

---

## Raw-bytes path (ADR-049)

The raw-bytes datagram server (`zix.Udp.Raw`) is separate from the typed engine above and mirrors the `zix.Http1` layout (`core.zig` + `dispatch/` + a thin `run()` switch). See ADR-049 for the design.

- `datagram.zig`: the raw-fd primitives. `open` uses raw `std.os.linux` syscalls (`socket` / `bind`, since `std.posix` no longer wraps them after the std.Io migration) plus the `std.posix.setsockopt` safe wrapper for SO_REUSEADDR / SO_REUSEPORT. `RecvBatch` carves one backing buffer into `recv_batch` MTU slots wired into the `mmsghdr` / `iovec` / name arrays for `recvmmsg`, called with `MSG_WAITFORONE` so it returns on the first datagram instead of blocking for the whole batch. `SendBatch.queue` copies each reply into its own backing buffer (so a reply that points into the receive buffer stays valid), and `flush` drains the queue with `sendmmsg`, handling partial sends. `errno` is read from the raw syscall return via `std.posix.errno`.
- `core.zig`: `HandlerFn` and `Sink`. `Sink.reply` reuses the kernel-filled sender `sockaddr.in` with no conversion, `Sink.replyTo` converts a `std.Io.net.IpAddress`. A full batch flushes mid-handler then re-queues.
- `dispatch/common.zig`: `workerLoop` (recvmmsg in, handler per datagram, sendmmsg out), `runSingle` (one worker on the calling thread, ASYNC), and `runFallback` (non-Linux, the portable single `std.Io.net` loop that `runSingle` delegates to). `dispatch/async.zig` delegates to `runSingle`. `dispatch/epoll.zig` and `dispatch/uring.zig` own their own per-core loops (`workerLoopEpoll`, and `workerLoopUring` a real io_uring ring with epoll fallback).
- `raw.zig`: `Raw(comptime handler)` with `init` / `deinit` and a `run()` that switches on `config.dispatch_model`.

---

###### end of lld-udp
