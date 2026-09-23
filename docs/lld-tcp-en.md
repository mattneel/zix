# LLD: zix.Tcp (raw stream)

Internal implementation details. For design rationale see [`docs/hld-tcp-en.md`](hld-tcp-en.md) and ADR-022.

---

## server.zig

### Server namespace and factory types

```zig
// Fieldless namespace with comptime constructors (ADR-038).
pub const Server = struct {
    pub fn init(comptime handler: HandlerFn, config: TcpServerConfig) !TcpServerImpl(handler)
    pub fn initArgs(comptime handler: HandlerFn, config: TcpServerConfig, args: anytype) !TcpServerImpl(handler)
    pub fn initFramed(comptime frame_fn: FrameFn, config: TcpServerConfig) !TcpFramedServerImpl(frame_fn)
    pub fn initFramedArgs(comptime frame_fn: FrameFn, config: TcpServerConfig, args: anytype) !TcpFramedServerImpl(frame_fn)
};

// Per-connection factory: handler baked into the type, run() takes only io.
fn TcpServerImpl(comptime handler: HandlerFn) type        // .init(config) -> error.ZixPortNotConfigured if port == 0; .deinit() no-op; .run() reads config.io
fn TcpFramedServerImpl(comptime frame_fn: FrameFn) type   // .init(config); .deinit(); .run() -> ring on .URING, else frameAdapter fallback

// Free dispatch workers (handler kept as a runtime value, same shape as zix.Http1):
fn serveDispatch(cfg: TcpServerConfig, handler: HandlerFn) !void  // ASYNC/EPOLL switch, rejects a Linux-only model off Linux
fn runEpoll(cfg: TcpServerConfig, handler: HandlerFn) !void
```

The handler (or per-frame callback) is comptime-known at the type boundary, but the internal worker functions take it as a runtime value, so `serveDispatch` / `runEpoll` are shared across every specialization with no per-handler code bloat (ADR-038). The built-in echo default is the public `zix.Tcp.echoHandler`, passed explicitly to `init`.

### serveDispatch ASYNC path

```
1. resolve ip:port -> addr
2. addr.listen(io, .{ .mode = .stream, .protocol = .tcp, .reuse_address = true, .kernel_backlog = cfg.kernel_backlog })
3. defer net_server.deinit(io)
4. loop:
       stream = net_server.accept(io)
       task = ConnTask{ stream, io, handler }
       io.async(dispatchConn, .{task})
```

Single accept thread. Each connection is dispatched as an `io.async()` task. The accept loop never blocks on connection handling.

### runEpoll (EPOLL path, dispatch/epoll.zig)

```
1. worker_count = cfg.workers (0 -> cpu_count)
2. bind_gate = shared BindOrderGate; steering = cfg.reuseport_cbpf ? Steering{gate, worker_count} : null
3. spawn worker_count threads: epollWorkerEntry(ctx)
4. join threads
```

Per worker:

```
pinToCpu(worker_id)
bind_turn = BindTurn.begin(steering, worker_id)   <- serializes binds: group index i = worker i
listener = resolve(ip:port) + listen(reuse_address = true, kernel_backlog)
if steering: attachCpuSteering(listener_fd, group_size)   <- SO_ATTACH_REUSEPORT_CBPF
bind_turn.release()
set listener non-blocking; epoll_create1; epoll_ctl ADD listener
loop:
    epoll_wait(events)
    for each readable listener event:
        loop: accept4() until EAGAIN
            applyConnTimeout(conn_fd, recv_timeout_ms, send_timeout_ms)
            io.async(dispatchConn, ConnTask{ stream, io, handler, logger })
```

One `SO_REUSEPORT` listener and one epoll instance per worker (shared-nothing): the kernel load-balances connections across workers with no shared queue and no cross-thread fd handoff. Each accepted connection still runs the blocking `HandlerFn` through `io.async`, so the epoll loop itself never blocks on a handler, it returns to `epoll_wait` immediately after dispatch. A per-worker accepted-connection counter reports through `logger.system()` at worker exit (REUSEPORT skew visibility, ADR-061).

### runFramedUring (URING framed path, dispatch/uring.zig)

Only `Server.initFramed`'s `FrameFn` runs natively on the ring: a blocking per-connection `HandlerFn` cannot, so its `.URING` folds to the `.EPOLL` path above. One ring plus one `SO_REUSEPORT` listener per worker (shared-nothing), a per-worker fd-indexed connection slab (`uring_max_conns_per_worker`, demand-paged via `slab.mapZeroedSlots`), and a coalescing response sink (`RespSink`, `tl_resp_sink`) that stages a frame handler's replies into one send per readable batch.

```
runFramedUring(cfg, io, frame_fn):
    worker_count = cfg.workers (0 -> cpu_count)
    steering = cfg.reuseport_cbpf ? Steering : null
    spawn worker_count threads: uringFrameWorkerFn(frame_fn)(ctx)
    join threads
```

Per worker:

```
pinToCpu(worker_id)
bind under BindTurn (group index i = worker i); attachCpuSteering if steering
slots = mapZeroedSlots(?*UringConn, max_conns)
ring = initUringRing()   <- SINGLE_ISSUER | DEFER_TASKRUN | CQSIZE | CLAMP, flagless fallback on init failure
armAccept()   <- multishot accept SQE
loop:
    submit_and_wait(1)
    for each cqe:
        accept -> handleAccept: alloc UringConn{ buf: max_recv_buf, send_buf: uring_send_buf_size }, armRecv
        recv   -> handleRecv: accumulate into conn.buf, dispatch() the complete frames, submitSend or armRecv
        send   -> handleSend: partial-send retry (memmove the unsent tail), else armRecv or finishClose if closing
```

`dispatch()` parses every complete length-prefixed frame in the connection buffer (`FRAME_LEN_PREFIX` = 4-byte big-endian length, `FRAME_MAX_PAYLOAD` = 1 MiB), calls `frame_fn(payload, fd)` per frame with a `RespSink` installed as `tl_resp_sink` so `writeAllFD` / `frameRespond` coalesce into `conn.send_buf` instead of writing the fd directly, then compacts the trailing partial frame to the front of the buffer.

Half-duplex per connection: `armRecv` fires again only once any staged reply's `send` completes (or immediately when a pass produced no reply), so a connection with a reply owed never races a second `recv` against the pending `send`. `beginClose` defers the actual close behind an in-flight or staged send (drains fully before `finishClose`), and each slot's `gen` counter guards a completion against a slot already recycled by a closed-then-reaccepted fd.

Falls back to `.EPOLL` (the blocking `frameAdapter` wrapping `frame_fn` in a `HandlerFn`, see `common.zig`) when `uringUnavailableReason()` is non-null at startup (seccomp/sandbox, `RLIMIT_MEMLOCK` too low for the ring size, or a pre-io_uring kernel), decided once in `server.zig` before the worker fleet spawns.

### ConnTask

```zig
const ConnTask = struct {
    stream:  std.Io.net.Stream,
    io:      std.Io,
    handler: HandlerFn,
    logger:  ?*Logger,
};

fn dispatchConn(task: ConnTask) void {
    task.handler(task.stream, task.io);
    if (task.logger) |lg| lg.conn(peer, elapsed_ms, null);
}
```

`dispatchConn` is the comptime-known function passed to `io.async()`. The runtime function pointer (`handler`) is stored inside `ConnTask` and called through at runtime.

### echoHandler()

```
defer stream.close(io)
var rbuf, wbuf [4096+4]u8 = undefined
var payload_buf [4096]u8 = undefined
rdr = stream.reader(io, &rbuf)
wtr = stream.writer(io, &wbuf)
loop:
    len = rdr.interface.takeVarInt(u32, .big, 4)   <- reads exactly 4 bytes as big-endian u32
    if len == 0 or len > 4096: return              <- oversized or empty frame -> close
    rdr.interface.readSliceAll(payload_buf[0..len]) <- reads exactly len bytes
    writeInt(u32, &hdr, len, .big)
    wtr.interface.writeAll(&hdr)
    wtr.interface.writeAll(payload_buf[0..len])
    wtr.interface.flush()
```

Stack buffers only: no heap allocation inside `echoHandler`. Uses `takeVarInt` (reads exactly N bytes as int) and `readSliceAll` (reads exactly N bytes, errors on short read) rather than the `readSliceShort` loop used in `zix.Uds.echoHandler`.

---

## client.zig

### TcpClient

```zig
pub const TcpClient = struct {
    stream: std.Io.net.Stream,
    config: TcpClientConfig,

    pub fn connect(config: TcpClientConfig, io: std.Io) !Self
    pub fn connectArgs(config: TcpClientConfig, io: std.Io, args: anytype) !Self
    pub fn deinit(self: *Self, io: std.Io) void        // stream.close(io)
    pub fn sendMsg(self: *Self, io: std.Io, msg: []const u8) !void
    pub fn recvMsg(self: *Self, io: std.Io, buf: []u8) ![]u8
};
```

### connect()

```
if config.port == 0: return error.ZixPortNotConfigured
addr = IpAddress.resolve(io, config.ip, config.port)
stream = addr.connect(io, .{ .mode = .stream, .protocol = .tcp })
```

### sendMsg()

```
if msg.len > config.max_recv_buf: return error.ZixMessageTooLarge
var wbuf [4096+4]u8 = undefined
wtr = stream.writer(io, &wbuf)
writeInt(u32, &hdr, msg.len, .big)
wtr.interface.writeAll(&hdr)
wtr.interface.writeAll(msg)
wtr.interface.flush()
```

Stack write buffer (4100 bytes). All writes are buffered and sent in a single flush syscall for small messages.

### recvMsg()

```
var rbuf [4096+4]u8 = undefined
rdr = stream.reader(io, &rbuf)
len = rdr.interface.takeVarInt(u32, .big, 4) catch return error.ZixConnectionClosed
if len > buf.len: return error.ZixMessageTooLarge
rdr.interface.readSliceAll(buf[0..len]) catch return error.ZixConnectionClosed
return buf[0..len]
```

Stack read buffer (4100 bytes). Returns a slice into the caller's `buf`. The caller controls buffer lifetime.

### connectArgs() / initArgs()

```zig
var it = std.process.Args.Iterator.init(args);
_ = it.skip();   // skip argv[0]
while (it.next()) |arg| {
    if eql(arg, "--ip")   -> cfg.ip   = next val
    if eql(arg, "--port") -> cfg.port = parseInt(next val) catch cfg.port
}
```

Pattern shared by `TcpServer.initArgs` and `TcpClient.connectArgs`. Unknown args are silently skipped. Parsing failure for `--port` keeps the config default.

---

## config.zig

```zig
pub const DispatchModel = enum(u8) {
    ASYNC = 0,   // the only portable model
    EPOLL = 1,   // Linux-only, native
    URING = 2,   // Linux-only, native for the framed path only (initFramed)
};

pub const TcpServerConfig = struct {
    io:                         std.Io,
    ip:                         []const u8,
    port:                       u16,
    dispatch_model:             DispatchModel,
    kernel_backlog:             u31   = 4096,
    workers:                    usize = 0,
    worker_stack_size_bytes:    usize = 512 * 1024,
    reuseport_cbpf:             bool  = false,
    max_recv_buf:               usize = 4096,
    uring_send_buf_size:        usize = 64 * 1024,
    uring_max_conns_per_worker: usize = 1 << 16,
    recv_timeout_ms:            u32   = 0,
    send_timeout_ms:            u32   = 0,
    logger:                     ?*Logger = null,
};

pub const TcpClientConfig = struct {
    ip:              []const u8,
    port:            u16,
    max_recv_buf:    usize = 4096,
    recv_timeout_ms: u32   = 0,
    send_timeout_ms: u32   = 0,
};
```

`DispatchModel` is defined once in `src/tcp/config.zig` and re-exported as `zix.Tcp.DispatchModel`. HTTP and FIX configs import it from there. The backing type is `u8` per the project enum convention.

`max_recv_buf` in both configs is a runtime validation threshold, not a comptime buffer size. The I/O buffers in `echoHandler`, `sendMsg`, and `recvMsg` are stack-allocated to `4096 + 4` bytes regardless of the config value.

`reuseport_cbpf` (ADR-061) steers a new connection to the worker on the receiving CPU instead of the 4-tuple hash, `.EPOLL` / `.URING` only. `uring_send_buf_size` and `uring_max_conns_per_worker` size the `.URING` per-worker send buffer and connection slab respectively, no effect under the other dispatch models. `recv_timeout_ms` / `send_timeout_ms` set `SO_RCVTIMEO` / `SO_SNDTIMEO` per connection, 0 disables each.

---

###### end of lld-tcp
