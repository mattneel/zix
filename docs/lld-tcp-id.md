# LLD: zix.Tcp (raw stream)

Detail implementasi internal. Untuk dasar keputusan desain lihat [`docs/hld-tcp-id.md`](hld-tcp-id.md) dan ADR-022.

---

## server.zig

### Namespace Server dan factory type

```zig
// Namespace tanpa field dengan constructor comptime (ADR-038).
pub const Server = struct {
    pub fn init(comptime handler: HandlerFn, config: TcpServerConfig) !TcpServerImpl(handler)
    pub fn initArgs(comptime handler: HandlerFn, config: TcpServerConfig, args: anytype) !TcpServerImpl(handler)
    pub fn initFramed(comptime frame_fn: FrameFn, config: TcpServerConfig) !TcpFramedServerImpl(frame_fn)
    pub fn initFramedArgs(comptime frame_fn: FrameFn, config: TcpServerConfig, args: anytype) !TcpFramedServerImpl(frame_fn)
};

// Factory per-connection: handler dibakukan ke tipe, run() hanya menerima io.
fn TcpServerImpl(comptime handler: HandlerFn) type        // .init(config) -> error.ZixPortNotConfigured jika port == 0; .deinit() no-op; .run() membaca config.io
fn TcpFramedServerImpl(comptime frame_fn: FrameFn) type   // .init(config); .deinit(); .run() -> ring di .URING, selain itu fallback frameAdapter

// Worker dispatch bebas (handler disimpan sebagai nilai runtime, bentuk sama seperti zix.Http1):
fn serveDispatch(cfg: TcpServerConfig, handler: HandlerFn) !void  // switch ASYNC/EPOLL, menolak model khusus Linux di luar Linux
fn runEpoll(cfg: TcpServerConfig, handler: HandlerFn) !void
```

Handler (atau callback per-frame) diketahui comptime di batas tipe, tetapi fungsi worker internal menerimanya sebagai nilai runtime, sehingga `serveDispatch` / `runEpoll` dibagi lintas setiap spesialisasi tanpa code bloat per-handler (ADR-038). Default echo bawaan adalah `zix.Tcp.echoHandler` publik, dilewatkan secara eksplisit ke `init`.

### serveDispatch jalur ASYNC

```
1. resolve ip:port -> addr
2. addr.listen(io, .{ .mode = .stream, .protocol = .tcp, .reuse_address = true, .kernel_backlog = cfg.kernel_backlog })
3. defer net_server.deinit(io)
4. loop:
       stream = net_server.accept(io)
       task = ConnTask{ stream, io, handler }
       io.async(dispatchConn, .{task})
```

Satu accept thread. Setiap koneksi didispatch sebagai task `io.async()`. Accept loop tidak pernah memblokir pada penanganan koneksi.

### runEpoll (jalur EPOLL, dispatch/epoll.zig)

```
1. worker_count = cfg.workers (0 -> cpu_count)
2. bind_gate = BindOrderGate bersama; steering = cfg.reuseport_cbpf ? Steering{gate, worker_count} : null
3. spawn worker_count thread: epollWorkerEntry(ctx)
4. join thread
```

Per worker:

```
pinToCpu(worker_id)
bind_turn = BindTurn.begin(steering, worker_id)   <- menyerialkan bind: group index i = worker i
listener = resolve(ip:port) + listen(reuse_address = true, kernel_backlog)
jika steering: attachCpuSteering(listener_fd, group_size)   <- SO_ATTACH_REUSEPORT_CBPF
bind_turn.release()
set listener non-blocking; epoll_create1; epoll_ctl ADD listener
loop:
    epoll_wait(events)
    untuk tiap event listener yang readable:
        loop: accept4() sampai EAGAIN
            applyConnTimeout(conn_fd, recv_timeout_ms, send_timeout_ms)
            io.async(dispatchConn, ConnTask{ stream, io, handler, logger })
```

Satu listener `SO_REUSEPORT` dan satu instance epoll per worker (shared-nothing): kernel melakukan load-balance koneksi lintas worker tanpa antrian bersama dan tanpa handoff fd lintas thread. Tiap koneksi yang diterima tetap menjalankan `HandlerFn` blocking lewat `io.async`, jadi loop epoll sendiri tidak pernah blocking pada handler, ia kembali ke `epoll_wait` segera setelah dispatch. Counter koneksi-diterima per-worker dilaporkan lewat `logger.system()` saat worker keluar (visibilitas skew REUSEPORT, ADR-061).

### runFramedUring (jalur framed URING, dispatch/uring.zig)

Hanya `FrameFn` milik `Server.initFramed` yang berjalan native di ring: `HandlerFn` per-koneksi yang blocking tidak bisa, jadi `.URING`-nya fold ke jalur `.EPOLL` di atas. Satu ring plus satu listener `SO_REUSEPORT` per worker (shared-nothing), satu slab koneksi fd-indexed per-worker (`uring_max_conns_per_worker`, demand-paged lewat `slab.mapZeroedSlots`), dan sebuah sink response coalescing (`RespSink`, `tl_resp_sink`) yang men-stage balasan frame handler jadi satu send per batch yang readable.

```
runFramedUring(cfg, io, frame_fn):
    worker_count = cfg.workers (0 -> cpu_count)
    steering = cfg.reuseport_cbpf ? Steering : null
    spawn worker_count thread: uringFrameWorkerFn(frame_fn)(ctx)
    join thread
```

Per worker:

```
pinToCpu(worker_id)
bind di bawah BindTurn (group index i = worker i); attachCpuSteering jika steering
slots = mapZeroedSlots(?*UringConn, max_conns)
ring = initUringRing()   <- SINGLE_ISSUER | DEFER_TASKRUN | CQSIZE | CLAMP, fallback flagless saat init gagal
armAccept()   <- SQE multishot accept
loop:
    submit_and_wait(1)
    untuk tiap cqe:
        accept -> handleAccept: alokasi UringConn{ buf: max_recv_buf, send_buf: uring_send_buf_size }, armRecv
        recv   -> handleRecv: akumulasi ke conn.buf, dispatch() frame yang lengkap, submitSend atau armRecv
        send   -> handleSend: retry partial-send (memmove sisa yang belum terkirim), jika tidak armRecv atau finishClose jika closing
```

`dispatch()` mem-parse tiap frame length-prefixed yang lengkap di buffer koneksi (`FRAME_LEN_PREFIX` = panjang big-endian 4 byte, `FRAME_MAX_PAYLOAD` = 1 MiB), memanggil `frame_fn(payload, fd)` per frame dengan `RespSink` terpasang sebagai `tl_resp_sink` sehingga `writeAllFD` / `frameRespond` coalesce ke `conn.send_buf` alih-alih menulis fd langsung, lalu memampatkan frame parsial yang tersisa ke depan buffer.

Half-duplex per koneksi: `armRecv` menyala lagi hanya setelah `send` dari balasan yang di-stage selesai (atau segera jika satu pass tidak menghasilkan balasan), jadi koneksi dengan balasan yang masih berutang tidak pernah membuat `recv` kedua balapan dengan `send` yang pending. `beginClose` menunda close sesungguhnya di belakang send yang in-flight atau ter-stage (mengalir habis dulu sebelum `finishClose`), dan counter `gen` tiap slot menjaga sebuah completion dari slot yang sudah didaur ulang oleh fd yang closed-lalu-diterima-ulang.

Fallback ke `.EPOLL` (`frameAdapter` blocking yang membungkus `frame_fn` jadi `HandlerFn`, lihat `common.zig`) ketika `uringUnavailableReason()` non-null saat startup (seccomp/sandbox, `RLIMIT_MEMLOCK` terlalu rendah untuk ukuran ring, atau kernel pre-io_uring), diputuskan sekali di `server.zig` sebelum worker fleet di-spawn.

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

`dispatchConn` adalah fungsi yang diketahui pada comptime yang diteruskan ke `io.async()`. Function pointer runtime (`handler`) disimpan di dalam `ConnTask` dan dipanggil saat runtime.

### echoHandler()

```
defer stream.close(io)
var rbuf, wbuf [4096+4]u8 = undefined
var payload_buf [4096]u8 = undefined
rdr = stream.reader(io, &rbuf)
wtr = stream.writer(io, &wbuf)
loop:
    len = rdr.interface.takeVarInt(u32, .big, 4)   <- membaca tepat 4 byte sebagai big-endian u32
    if len == 0 or len > 4096: return              <- frame kosong atau terlalu besar -> tutup
    rdr.interface.readSliceAll(payload_buf[0..len]) <- membaca tepat len byte
    writeInt(u32, &hdr, len, .big)
    wtr.interface.writeAll(&hdr)
    wtr.interface.writeAll(payload_buf[0..len])
    wtr.interface.flush()
```

Hanya menggunakan stack buffer: tidak ada alokasi heap di dalam `echoHandler`. Menggunakan `takeVarInt` (membaca tepat N byte sebagai integer) dan `readSliceAll` (membaca tepat N byte, error jika kurang) alih-alih loop `readSliceShort` yang digunakan di `zix.Uds.echoHandler`.

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

Stack write buffer (4100 byte). Semua penulisan di-buffer dan dikirim dalam satu flush syscall untuk pesan berukuran kecil.

### recvMsg()

```
var rbuf [4096+4]u8 = undefined
rdr = stream.reader(io, &rbuf)
len = rdr.interface.takeVarInt(u32, .big, 4) catch return error.ZixConnectionClosed
if len > buf.len: return error.ZixMessageTooLarge
rdr.interface.readSliceAll(buf[0..len]) catch return error.ZixConnectionClosed
return buf[0..len]
```

Stack read buffer (4100 byte). Mengembalikan slice ke dalam `buf` milik pemanggil. Pemanggil mengendalikan masa hidup buffer.

### connectArgs() / initArgs()

```zig
var it = std.process.Args.Iterator.init(args);
_ = it.skip();   // skip argv[0]
while (it.next()) |arg| {
    if eql(arg, "--ip")   -> cfg.ip   = next val
    if eql(arg, "--port") -> cfg.port = parseInt(next val) catch cfg.port
}
```

Pola yang sama digunakan oleh `TcpServer.initArgs` dan `TcpClient.connectArgs`. Argumen yang tidak dikenal dilewati tanpa pesan error. Kegagalan parsing `--port` mempertahankan nilai default dari config.

---

## config.zig

```zig
pub const DispatchModel = enum(u8) {
    ASYNC = 0,   // satu-satunya model portabel
    EPOLL = 1,   // Linux-only, native
    URING = 2,   // Linux-only, native hanya untuk jalur framed (initFramed)
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

`DispatchModel` didefinisikan sekali di `src/tcp/config.zig` dan di-re-export sebagai `zix.Tcp.DispatchModel`. Config HTTP dan FIX mengimpornya dari sana. Tipe backing adalah `u8` sesuai konvensi enum dalam proyek ini.

`max_recv_buf` pada kedua config merupakan ambang validasi runtime, bukan ukuran buffer comptime. Buffer I/O di `echoHandler`, `sendMsg`, dan `recvMsg` dialokasikan di stack dengan ukuran `4096 + 4` byte terlepas dari nilai config.

`reuseport_cbpf` (ADR-061) mengarahkan koneksi baru ke worker pada CPU penerima, bukan hash 4-tuple, hanya `.EPOLL` / `.URING`. `uring_send_buf_size` dan `uring_max_conns_per_worker` mengatur ukuran send buffer per-worker dan slab koneksi untuk `.URING`, tanpa efek pada dispatch model lain. `recv_timeout_ms` / `send_timeout_ms` mengatur `SO_RCVTIMEO` / `SO_SNDTIMEO` per koneksi, 0 menonaktifkan masing-masing.

---

###### end of lld-tcp
