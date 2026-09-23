# LLD: zix.Uds

Internal implementation details. For design rationale see [`docs/hld-uds-en.md`](hld-uds-en.md) and ADR-010.

---

## server.zig

### Server namespace and factory type

```zig
// Namespace with a comptime constructor (ADR-039), mirroring zix.Tcp.
pub const UdsServer = struct {
    pub fn init(comptime handler: HandlerFn, config: UdsServerConfig) !UdsServerImpl(handler)
};

// Per-connection factory: handler baked into the type, io from config.io.
fn UdsServerImpl(comptime handler: HandlerFn) type {
    // config: UdsServerConfig
    // pub fn init(config) !Self          -> error.ZixPathEmpty if config.path is empty
    // pub fn deinit(self) void           -> no-op: resources released inside run()
    // pub fn run(self) !void             -> reads config.io, runs the accept loop
}
```

The built-in echo default is the public `zix.Uds.echoHandler`, passed explicitly to `init`.

### run()

```
1. unlink config.path (ignore error, stale socket cleanup)
2. UnixAddress.init(config.path)
3. ua.listen(io, .{ .kernel_backlog = config.kernel_backlog }) -> net_server
4. defer: net_server.deinit(io) + unlink config.path
5. accept loop:
       stream = net_server.accept(io) catch |err| { log warn; continue }   // blocks until connection
       applyConnTimeout(stream.socket.handle, config.recv_timeout_ms, config.send_timeout_ms)
       task = ConnTask{ stream, io, logger: config.logger }
       io.concurrent(dispatch, .{task}) catch dispatch(task)
```

Accept is single-threaded (`.ASYNC`-style pattern). Each connection has `SO_RCVTIMEO` / `SO_SNDTIMEO` applied (`applyConnTimeout`, a no-op when both are 0), then is dispatched via `io.concurrent()` so the accept loop is not blocked by slow handlers. `dispatch` is a local closure logging "connection accepted" (when a logger is set) before calling the comptime-baked `handler`.

### ConnTask

Private struct passed by value to `io.concurrent()`:

```zig
const ConnTask = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    logger: ?*Logger,
};
```

### echoHandler()

```
defer stream.close(io)
loop:
    read 4-byte header (loop until 4 bytes received)
    len = readInt(u32, &hdr, .big)
    if len > payload_buf.len (4096): return  // oversized, close
    read len payload bytes
    write hdr + payload back (echo)
    flush
```

Stack buffers only (no heap allocation inside `echoHandler`).

---

## client.zig

### UdsClient

```zig
pub const UdsClient = struct {
    stream: std.Io.net.Stream,
    config: UdsClientConfig,

    pub fn connect(config: UdsClientConfig, io: std.Io) !Self
    pub fn deinit(self: *Self, io: std.Io) void   // calls stream.close(io)
    pub fn sendMsg(self: *Self, io: std.Io, msg: []const u8) !void
    pub fn recvMsg(self: *Self, io: std.Io, buf: []u8) ![]u8
};
```

### sendMsg()

```
if config.send_timeout_ms > 0:
    poll(fd, POLLOUT, config.send_timeout_ms) -> error.ZixSendTimeout on 0 ready   // SO_SNDTIMEO is not used: std.Io.Threaded panics on EAGAIN
write [u32 len, BE][payload]
flush
```

Stack write buffer (4096 bytes). Blocks until the frame is sent.

### recvMsg()

```
if config.recv_timeout_ms > 0:
    poll(fd, POLLIN, config.recv_timeout_ms) -> error.ZixRecvTimeout on 0 ready   // SO_RCVTIMEO is not used: std.Io.Threaded panics on EAGAIN
read 4-byte header (loop until 4 bytes)
len = readInt(u32, &hdr, .big)
if len > buf.len: return error.ZixMessageTooLarge
read len payload bytes into buf[0..len]
return buf[0..len]
```

Stack read buffer (4096 bytes). Returns a slice into the caller's `buf`.

---

## config.zig

```zig
pub const UdsServerConfig = struct {
    io:              std.Io,
    allocator:       std.mem.Allocator,  // unused in current impl: reserved for future extensions
    path:            []const u8,
    kernel_backlog:  u31   = 128,
    max_recv_buf:    usize = 4096,
    recv_timeout_ms: u32   = 0,
    send_timeout_ms: u32   = 0,
    logger:          ?*Logger = null,
};

pub const UdsClientConfig = struct {
    path:            []const u8,
    recv_timeout_ms: u32 = 0,
    send_timeout_ms: u32 = 0,
};
```

`allocator` is present in `UdsServerConfig` for API consistency with `UdpServerConfig` and to allow future extensions (e.g. connection pool, per-connection allocations). The current implementation does not heap-allocate: all buffers are stack-local inside the handler.

`recv_timeout_ms` / `send_timeout_ms` set `SO_RCVTIMEO` / `SO_SNDTIMEO` on the server (`applyConnTimeout`, one call per accepted connection). On the client both are enforced via `pollReady` instead (see [client.zig](#clientzig)), not `setsockopt`.

---

###### end of lld-uds
