# gRPC h2c Desain Tingkat Tinggi: zix.Grpc

## Tujuan

- Server dan client gRPC h2c (HTTP/2 cleartext) diimplementasikan tanpa C FFI.
- Semua 4 tipe RPC: unary, server streaming, client streaming, bidirectional streaming.
- Semua 3 model dispatch: ASYNC (portabel), EPOLL (hanya Linux), URING (hanya Linux). Wajib, tidak ada default.
- Codec protobuf minimal (tipe wire varint + LEN) untuk encoding payload tanpa codegen.
- Parsing header grpc-timeout, serialisasi trailer grpc-status.
- TLS native (TLS 1.3 / 1.2, ALPN h2) via `Tls.Context`, aditif di atas default h2c. Reverse proxy (nginx, haproxy) tetap opsi untuk offloading.

## Arsitektur

```mermaid
graph LR
    Z[zix.Grpc] --> H[zix.Http2]
    H --> T[std.Io / std.posix]
    Z --> P[proto.zig codec]
    Z --> S[status.zig]
    Z --> TO[timeout.zig]
```

`zix.Grpc` dibangun di atas `zix.Http2`. Frame loop gRPC (`serveGrpcConn`) mereplikasi h2c stream loop dari `zix.Http2.serveConn`, keduanya men-dispatch bentuk trio `req`/`res`/`ctx` yang sama (ADR-063), tapi engine gRPC tambahan membaca `Route.is_server_streaming` sebelum memanggil handler untuk mendukung streaming tanpa antrian antar thread (lihat Pola Handler).

## Struktur Berkas

| Berkas | Peran |
| :- | :- |
| `src/tcp/http2/grpc/Grpc.zig` | namespace: semua re-export publik |
| `src/tcp/http2/grpc/core.zig` | `GrpcContext`, `GrpcRequest`, `GrpcResponse`, `HandlerFn`, `Router`, `serveGrpcConn` (model blocking), `GrpcMuxConn` + `grpcMuxOnReadable` (multiplex `.EPOLL`), `parsePath`, `detectContentType`, `wallClockNs`, `computeDeadline`, `peerStr` |
| `src/tcp/http2/grpc/config.zig` | `GrpcServerConfig`, `GrpcClientConfig` |
| `src/tcp/http2/grpc/server.zig` | `GrpcServer`: `run()` switch tipis yang men-dispatch ke berkas per-model di bawah `dispatch/` (dan ke jalur serve TLS saat `cfg.tls != null`) |
| `src/tcp/http2/grpc/dispatch/` | berkas dispatch per-model: `async.zig`, `epoll.zig` (multiplex `epollMuxWorkerFn` + `GrpcConnTable`), `uring.zig` (`.URING`), `common.zig` (helper bersama) |
| `src/tcp/http2/grpc/tls_serve.zig` | `runTls`: jalur handler TLS blocking (per koneksi) |
| `src/tcp/http2/grpc/tls_mux.zig` | `runTlsMux`: jalur dispatch TLS multiplex |
| `src/tcp/http2/grpc/client.zig` | `GrpcClient`: openStream, sendMessage, endStream, recvResponse, unary |
| `src/tcp/http2/grpc/frame.zig` | struct `GrpcPrefix`, `readGrpcPrefix`, `writeGrpcPrefix`, helper frame `send*`/`build*` (`buildGrpcHeaders`/`buildGrpcDataHeader`/`buildGrpcTrailer`/`buildGrpcError`), blok reply cache comptime |
| `src/tcp/http2/grpc/proto.zig` | konstanta tipe wire `WT_*`, `encodeVarint`, `decodeVarint`, `encodeString`, `encodeInt32`, `encodeDouble`, `decodeDouble`, `MessageReader` |
| `src/tcp/http2/grpc/status.zig` | enum `GrpcStatus` (u8), OK=0 sampai UNAUTHENTICATED=16 |
| `src/tcp/http2/grpc/timeout.zig` | `parseTimeout`: parser header grpc-timeout |

## API Publik

| Simbol | Catatan |
| :- | :- |
| `zix.Grpc.Server` | `init(Router(&routes), config)`, `deinit()`, `run()!void` (ADR-063: satu pengecualian dari `init(handler, config)` keluarga engine, lihat Pola Handler di bawah) |
| `zix.Grpc.Client` | `connect(config, io)!Self`, `deinit()`, `openStream`, `sendMessage`, `endStream`, `recvResponse`, `unary` |
| `zix.Grpc.Request` | view `{ path, headers }`, `header(name)`, `recvMessage()`. Wrapper delegasi tipis atas `Context`, tanpa logika internal yang dipindah |
| `zix.Grpc.Response` | `sendHeaders()`, `sendMessage()`, `finish()`, `serveCached()`, `sendCached()`. Wrapper delegasi tipis atas `Context`, wire byte-identical |
| `zix.Grpc.Context` | `withTimeout()` / `setTimeout()` / `withDeadline()` / `isExpired()` / `timedOut()`, `io`, dan `allocator` stack-arena (`FixedBufferAllocator`, tanpa pemanggilan heap) |
| `zix.Grpc.HandlerFn` | `*const fn (req: *Request, res: *Response, ctx: *Context) anyerror!void` (trio ADR-063). Error yang dikembalikan menutup call yang masih terbuka dengan `grpc-status 13` |
| `zix.Grpc.Route` | `struct { path: []const u8, handler: HandlerFn, timeout_ms: u32 = 0, is_server_streaming: bool = false }` |
| `zix.Grpc.Router(routes)` | tipe comptime: `pub const route_slice`, `dispatch(req, res, ctx) anyerror!void` (mengirim UNIMPLEMENTED jika tidak ada route yang cocok). `Server.init` menerima TIPE Router itu sendiri, bukan `.dispatch`, karena engine membaca `Route.is_server_streaming` dari `route_slice` sebelum dispatch |
| `zix.Grpc.ServerConfig` | lihat field konfigurasi di bawah |
| `zix.Grpc.ClientConfig` | `ip`, `port` |
| `zix.Grpc.DispatchModel` | ASYNC=0 (portabel), EPOLL=1 (hanya Linux), URING=2 (hanya Linux), wajib tanpa default |
| `zix.Grpc.Status` | enum(u8): OK=0 ... UNAUTHENTICATED=16 |
| `zix.Grpc.ContentType` | PROTO, JSON, UNKNOWN |
| `zix.Grpc.ServeOpts` | `GrpcServeOpts`: opsi per koneksi yang diteruskan ke `serveConn` |
| `zix.Grpc.Path` | `package_service: []const u8`, `method: []const u8` |
| `zix.Grpc.Prefix` | `compress: bool`, `msg_len: u32` |
| `zix.Grpc.readPrefix` | `fn(body: []const u8) error{TooShort}!Prefix` |
| `zix.Grpc.writePrefix` | `fn(buf: *[5]u8, compress: bool, msg_len: u32) void` |
| `zix.Grpc.sendHeadersFD` | `fn(fd, sid, content_type) !void`: kirim HEADERS awal (tanpa END_STREAM) |
| `zix.Grpc.sendDataFD` | `fn(fd, sid, msg) !void`: kirim DATA dengan prefix gRPC 5 byte |
| `zix.Grpc.sendTrailerFD` | `fn(fd, sid, grpc_status, grpc_message) !void`: kirim HEADERS trailer (END_STREAM) |
| `zix.Grpc.sendErrorFD` | `fn(fd, sid, grpc_status, grpc_message) !void`: error trailers-only, tanpa frame DATA |
| `zix.Grpc.parsePath` | `fn(path: []const u8) ?Path` |
| `zix.Grpc.detectContentType` | `fn(headers: []const Header) ContentType` |
| `zix.Grpc.parseTimeout` | `fn(value: []const u8) ?u64` (nanodetik) |
| `zix.Grpc.serveConn` | `fn(comptime RouterType, fd, opts, io) void`: titik masuk koneksi langsung |
| `zix.Grpc.ClientResponse` | `union(enum) { data: []const u8, status: GrpcStatus }` |
| `zix.Grpc.wallClockNs` | `fn() u64`: waktu wall-clock saat ini dalam nanodetik (CLOCK_REALTIME). Digunakan untuk menimpa `ctx.deadline_ns` saat runtime. |

## Field GrpcServerConfig

| Field | Default | Deskripsi |
| :- | :- | :- |
| `io` | wajib | backend `std.Io` yang disediakan pemanggil |
| `ip` | wajib | alamat bind |
| `port` | wajib | port listen, 0 -> `error.ZixPortNotConfigured` |
| `dispatch_model` | wajib, tanpa default | `.ASYNC`, `.EPOLL`, atau `.URING` (dua terakhir hanya Linux, native, ditolak di luar Linux dengan error.ZixDispatchModelUnsupported) |
| `kernel_backlog` | 1024 | backlog `listen()` |
| `workers` | 0 | 0 -> cpu_count worker multiplex untuk EPOLL dan URING. Diabaikan oleh ASYNC |
| `max_streams` | 128 | maksimum stream HTTP/2 konkuren per koneksi (SETTINGS_MAX_CONCURRENT_STREAMS yang diiklankan) |
| `max_frame_size` | 16384 | ukuran frame HTTP/2 maksimum yang diiklankan |
| `max_header_scratch` | 4096 | buffer scratch decode HPACK per stream (di-pool per worker) |
| `max_body` | 16384 | total maksimum body gRPC yang di-buffer per stream (semua frame DATA), body di atas ini di-shed dengan RESOURCE_EXHAUSTED |
| `logger` | `null` | `*zix.Logger` opsional, jika diatur, mencatat setiap penutupan stream melalui `rpc()` dan startup/shutdown melalui `system()` |
| `handler_timeout_ms` | 0 | batas timeout handler global (ms), 0 = dinonaktifkan. Digabungkan dengan `Route.timeout_ms` dan header `grpc-timeout` saat dispatch |
| `compress` | `false` | kompresi gzip frame DATA untuk client yang mengiklankan `grpc-accept-encoding: gzip` |
| `response_cache` | `false` | cache response unary per-worker (ADR-036), opt-in lewat `res.serveCached` / `res.sendCached` (`.EPOLL` / `.URING`) |
| `cache_max_entries` | 256 | jumlah slot cache response, dibulatkan ke bawah ke pangkat dua |
| `cache_max_value_bytes` | 16384 | cap pesan response per slot, pesan lebih besar melewati cache |
| `cache_ttl_ms` | 1000 | freshness cache default, handler boleh memberi TTL sendiri per store |
| `cache_max_total_bytes` | 0 | ceiling opsional memori cache per-worker, 0 menonaktifkan ceiling |
| `tls` | `null` | non-null melayani gRPC lewat TLS (ALPN h2) alih-alih h2c, lihat [TLS](#tls) |
| `tls_port` | 0 | port pendamping dual-listener (butuh `tls`), 0 = single-listener |

Field tuning lain (`worker_stack_size_bytes`, `busy_poll_us`, `reuseport_cbpf`, `max_recv_buf`, `tls_write_buf_initial_bytes`) dibahas di [`docs/zix-config-id.md`](zix-config-id.md).

## Pola Handler

Route didaftarkan saat kompilasi dan dibungkus dalam `Router(&routes)`. Handler menerima trio `req`/`res`/`ctx` (ADR-063), path sudah diselesaikan oleh tabel route.

```zig
fn echoHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    while (req.recvMessage()) |msg| {
        res.sendMessage("application/grpc+proto", msg);
    }
    res.finish(zix.Grpc.Status.OK, "");
}

var server = zix.Grpc.Server.init(
    zix.Grpc.Router(&[_]zix.Grpc.Route{
        .{ .path = "/pkg.Svc/Echo", .handler = echoHandler, .is_server_streaming = true },
    }),
    .{ .io = io, .ip = "127.0.0.1", .port = 8083 },
);
defer server.deinit();
try server.run();
```

`Server.init` adalah satu pengecualian sengaja gRPC dari bentuk `Server.init(handler, config)` keluarga engine (ADR-063): ia menerima `Router(&routes)` itu sendiri, bukan `.dispatch`, karena engine membaca `Route.is_server_streaming` dari `route_slice` router sebelum memanggil handler, untuk memilih dispatch sync-inline (unary, murah) vs task-spawn (streaming). Terukur: sync-inline kira-kira dua orde magnitude lebih tinggi RPS per-core dibanding task-spawn untuk handler unary sederhana, jadi kehilangan metadata itu di balik pointer `HandlerFn` polos bukan penyederhanaan yang bisa diterima.

Aturan penting:
- `res.finish()` harus selalu dipanggil sebelum return. Fungsi ini mengirim trailer grpc-status.
- `res.sendMessage()` mengirim HEADERS respons awal pada panggilan pertama. Jangan memanggil `res.sendHeaders()` secara manual jika menggunakan `sendMessage`.
- `req.recvMessage()` mengembalikan `null` saat semua pesan client telah dikonsumsi (client mengirim END_STREAM).
- Error handler menutup call. Saat handler mengembalikan error tanpa memanggil `res.finish`, engine menutup stream dengan `grpc-status 13` (INTERNAL) dan grpc-message `handler error`, jadi caller tidak pernah ditinggal menunggu stream yang tidak akan membawa status. Call yang sudah ditutup handler mempertahankan status pilihan handler itu. Error yang ditangkap sendiri oleh handler tidak pernah sampai ke engine, jadi handler itu yang menentukan apa yang diterima caller: `try res.sendMessage(...)` memakai default, `res.sendMessage(...) catch { ... }` menjawab dengan caranya sendiri.
- Route unary (`is_server_streaming = false`, default) di-dispatch secara sinkron pada connection thread. Route server-streaming (`is_server_streaming = true`) masing-masing berjalan pada thread tersendiri yang berbagi write mutex tingkat koneksi.
- Server mem-buffer semua DATA client sebelum melakukan dispatch handler.
- `parsePath` dan dispatch berbasis path di dalam handler tidak diperlukan: tabel route menangani hal tersebut.
- Handler unary boleh opt-in ke cache response per-worker: `if (res.serveCached(content_type)) return;` sebelum kerja yang mahal, `res.sendCached(content_type, reply, ttl_ms)` sebagai ganti `sendMessage` untuk menyimpannya. Butuh `response_cache = true`, jika tidak turun ke `sendMessage` biasa.

## Deadline Konteks

Tiga input menentukan `ctx.deadline_ns` saat dispatch:

| Input | Lokasi | Catatan |
| :- | :- | :- |
| `GrpcServerConfig.handler_timeout_ms` | config | batas global (0 = dinonaktifkan) |
| `Route.timeout_ms` | tabel route comptime | default per route (0 = gunakan batas global) |
| header `grpc-timeout` | request client | di-parse oleh `parseTimeout` (berlaku jika lebih ketat) |

`ctx.deadline_ns: ?u64` adalah yang paling ketat dari ketiganya (nanodetik CLOCK_REALTIME). `null` berarti tidak ada deadline. `Router.dispatch` menerapkan `Route.timeout_ms` setelah deadline global diatur, sehingga timeout per route hanya memperketat, tidak pernah memperlunak.

Handler memeriksa deadline secara eksplisit:

```zig
fn slowHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    if (ctx.isExpired()) {
        res.finish(zix.Grpc.Status.DEADLINE_EXCEEDED, "");
        return;
    }
    const msg = req.recvMessage() orelse {
        res.finish(zix.Grpc.Status.INVALID_ARGUMENT, "no message");
        return;
    };
    res.sendMessage("application/grpc+proto", msg);
    res.finish(zix.Grpc.Status.OK, "");
}
```

Pola penimpaan deadline handler (kanonik):

```zig
ctx.deadline_ns = wallClockNs() + 60 * std.time.ns_per_s; // perpanjang ke 60 detik dari sekarang
ctx.deadline_ns = null; // nonaktifkan untuk panggilan ini
// atau lewat helper: ctx.setTimeout(60_000); ctx.withDeadline(deadline_ns);
```

Risiko saat menimpa:
- Memperpanjang melewati `grpc-timeout` client membuang pekerjaan pada koneksi yang sudah mati.
- `null` menonaktifkan semua penegakan deadline.
- Memperpanjang tanpa terlebih dahulu memanggil `ctx.isExpired()` secara diam-diam melanjutkan melewati deadline yang sudah kedaluwarsa.

Contoh timeout per route:

```zig
var server = zix.Grpc.Server.init(
    zix.Grpc.Router(&[_]zix.Grpc.Route{
        .{ .path = "/svc.Svc/FastOp", .handler = fastHandler, .timeout_ms = 500    },
        .{ .path = "/svc.Svc/SlowOp", .handler = slowHandler, .timeout_ms = 30_000 },
    }),
    .{ .io = process.io, .ip = "127.0.0.1", .port = 8083, .handler_timeout_ms = 5000 },
);
```

## Semua 4 Tipe RPC

Handler unary dan client-streaming menggunakan `is_server_streaming = false` (default). Handler server-streaming dan bidirectional harus menetapkan `is_server_streaming = true` pada entri `Route` untuk mencegah deadlock di bawah backpressure flow-control.

### Unary (1 request, 1 respons)

```zig
fn unaryHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    const msg = req.recvMessage() orelse {
        res.finish(zix.Grpc.Status.INVALID_ARGUMENT, "no message");
        return;
    };
    res.sendMessage("application/grpc+proto", msg);
    res.finish(zix.Grpc.Status.OK, "");
}
```

### Server Streaming (1 request, N respons)

```zig
fn serverStreamHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    _ = req.recvMessage();
    res.sendMessage("application/grpc+proto", "result-1");
    res.sendMessage("application/grpc+proto", "result-2");
    res.sendMessage("application/grpc+proto", "result-3");
    res.finish(zix.Grpc.Status.OK, "");
}
```

### Client Streaming (N request, 1 respons)

```zig
fn clientStreamHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    var count: usize = 0;
    while (req.recvMessage()) |_| count += 1;
    var buf: [32]u8 = undefined;
    const reply = std.fmt.bufPrint(&buf, "got {d}", .{count}) catch "got ?";
    res.sendMessage("application/grpc+proto", reply);
    res.finish(zix.Grpc.Status.OK, "");
}
```

### Bidirectional Streaming (N request, M respons)

```zig
fn bidiHandler(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) !void {
    _ = ctx;
    while (req.recvMessage()) |msg| {
        res.sendMessage("application/grpc+proto", msg);
    }
    res.finish(zix.Grpc.Status.OK, "");
}
```

Catatan: semua pesan client di-buffer sebelum handler dipanggil. Bidirectional streaming yang benar-benar saling bergantian (server mengirim sebelum client selesai) membutuhkan arsitektur yang berbeda. Desain berbasis buffer mencakup semua 4 pola untuk ukuran pesan yang terbatas.

## Penggunaan GrpcClient

```zig
var client = try zix.Grpc.Client.connect(.{
    .ip   = "127.0.0.1",
    .port = 8083,
}, process.io);
defer client.deinit();

// Convenience unary
var buf: [4096]u8 = undefined;
const resp = try client.unary(
    "/helloworld.Greeter/SayHello",
    "application/grpc+proto",
    request_bytes,
    &buf,
);

// Manual streaming
const sid = try client.openStream("/svc.Svc/Echo", "application/grpc+proto");
try client.sendMessage(sid, "msg1");
try client.sendMessage(sid, "msg2");
try client.endStream(sid);

var rbuf: [4096]u8 = undefined;
while (true) {
    const r = try client.recvResponse(sid, &rbuf);
    switch (r) {
        .data   => |d| { _ = d; },
        .status => |s| { _ = s; break; },
    }
}
```

## Protokol Wire

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server

    C->>S: HEADERS (POST :path, content-type, END_HEADERS)
    C->>S: DATA (prefix 5 byte + message, END_STREAM)
    S->>C: HEADERS (:status 200, content-type, END_HEADERS)
    S->>C: DATA (prefix 5 byte + message, END_STREAM=false)
    S->>C: HEADERS (grpc-status 0, END_HEADERS, END_STREAM)
```

### Prefix pesan gRPC 5 byte

```
+----------+-------------------------------+
| Compress | Message Length (4 byte, BE)   |
|  Flag(1) |                               |
+----------+-------------------------------+
| Message payload                          |
+------------------------------------------+
```

Flag compress bernilai 1 saat payload pesan dikompresi gzip, selain itu 0. Kompresi bersifat opt-in lewat config server `compress` dan hanya berlaku saat client mengiklankan `grpc-accept-encoding: gzip`, di mana server juga mengeluarkan `grpc-encoding: gzip` pada HEADERS frame awal.

### Jalur error (trailers-only)

Saat handler memanggil `res.finish(status, msg)` tanpa mengirim data apa pun, server mengirim satu frame HEADERS dengan `:status 200`, `content-type`, `grpc-status`, dan `grpc-message` dengan `FLAG_END_STREAM`. HTTP `:status` selalu 200 sesuai protokol wire gRPC, error gRPC yang sebenarnya ada di trailer `grpc-status`. `content-type` selalu disertakan sesuai spesifikasi gRPC untuk memastikan kompatibilitas client.

## Model Dispatch

| Model | Accept thread | Dispatch koneksi | Catatan |
| :- | :- | :- | :- |
| `.ASYNC` | 1 | `io.async()` per koneksi | direkomendasikan untuk stream tak terbatas atau berumur panjang |
| `.EPOLL` | per worker | event loop multiplex (hanya Linux) | throughput tertinggi, lihat di bawah |
| `.URING` | per worker | loop io_uring multiplex (hanya Linux) | bentuk sama dengan `.EPOLL`, berbasis completion |

`.EPOLL` spesifik Linux. Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported` setelah mencatat model mana yang ditolak, jadi pakai `.ASYNC` di sana. `.URING` adalah desain multiplex shared-nothing yang sama di atas ring io_uring (`runUring`, ADR-037 Phase 4): berbasis completion bukan readiness, worker `workers` (0 = cpu_count), hanya Linux, dan ditolak di luar Linux dengan cara yang sama. Saat io_uring sendiri tidak tersedia di host Linux, `.URING` melipat ke loop `.EPOLL` dengan notice yang dicatat.

### `.EPOLL` bersifat multiplex dan shared-nothing

`.EPOLL` tidak memarkir satu thread per koneksi. Ia menjalankan `workers` thread worker (0 = jumlah cpu), masing-masing memiliki listener `SO_REUSEPORT` privat, instance epoll sendiri, dan tabel koneksi privat ber-indeks fd. Kernel menyeimbangkan koneksi baru ke listener tiap worker, jadi tidak ada accept thread, tidak ada antrian bersama, dan tidak ada handoff fd lintas-thread. Satu worker menjalankan banyak koneksi non-blocking melalui state machine HTTP/2 yang resumable (`GrpcMuxConn`), sehingga konkurensi dibatasi oleh jumlah koneksi, bukan jumlah thread. `epoll_wait` tiap worker menguras hingga `EPOLL_MAX_EVENTS` (512) event siap per pemanggilan (ADR-032). Desain tingkat rendahnya ada di `lld-grpc-id.md`.

Dua konsekuensi berbeda dari model lain:

- `workers` adalah jumlah worker multiplex untuk `.EPOLL` (nilai optimal sekitar jumlah cpu). Memberi nilai terlalu besar hanya menambah churn scheduler.
- Setiap route, termasuk server-streaming, di-dispatch inline pada worker (tanpa thread per stream). Handler streaming berjalan di event loop, jadi harus terbatas - stream yang berjalan lama atau tak terbatas memblokir koneksi lain pada worker itu. Gunakan `.ASYNC` untuk streaming tak terbatas, tempat spawn thread per stream tetap berlaku untuk route server-streaming.
- Reply server-streaming memadatkan banyak pesan gRPC ke tiap DATA frame HTTP/2 (hingga max frame size default 16 KiB) alih-alih satu frame per pesan, jadi stream yang banyak-pesan memakai jauh lebih sedikit frame di wire dan jauh lebih sedikit parsing per-frame di klien. Lihat LLD untuk mekanismenya.

`max_streams` yang diiklankan harus minimal sebanyak jumlah stream konkuren client. Sebuah client (misalnya benchmark dengan 100 stream paralel per koneksi) membuka stream secara optimistis sebelum melihat SETTINGS server, dan yang melebihi `max_streams` dijawab dengan `REFUSED_STREAM`.

## Siklus Hidup

```mermaid
flowchart TD
    A[GrpcServer.run] --> B{dispatch_model}
    B -->|ASYNC| C[single accept thread\nio.async per conn]
    B -->|EPOLL| EP[N workers\nlistener SO_REUSEPORT\n+ epoll masing-masing]
    C --> F[serveGrpcConn blocking]
    D --> F
    E --> F
    EP --> MX[grpcMuxOnReadable\nstate per-conn resumable]
    F --> G{h2c preface?}
    G -->|PRI| H[h2c direct]
    G -->|GET/POST| I[h2c upgrade]
    H --> J[frame loop blocking]
    I --> J
    J -->|HEADERS stream| K[buffer DATA]
    K -->|END_STREAM| L[dispatchStream]
    L -->|is_server_streaming=false| LI[inline pada conn thread]
    L -->|is_server_streaming=true| LS[spawn thread]
    LI --> M[HandlerFn: trio req/res/ctx]
    LS --> M
    MX -->|tiap frame lengkap| MI[muxDispatch inline\nreply di-stage ke cork]
    MI --> M
    M --> N[res.finish mengirim trailers]
```

## Codec Protobuf Minimal

`proto.zig` menyediakan konstanta tipe wire dan primitif encode/decode untuk proto3. Tidak diperlukan compiler berkas `.proto` maupun kode yang di-generate untuk skema sederhana.

| Fungsi | Catatan |
| :- | :- |
| `encodeVarint(buf, value)` | encode u64 menjadi 1-10 byte, mengembalikan byte yang ditulis |
| `decodeVarint(buf)` | mengembalikan `{value: u64, consumed: usize}` atau error |
| `encodeString(field_number, s, buf)` | tipe wire LEN (2), mengembalikan byte yang ditulis |
| `encodeInt32(field_number, val, buf)` | tipe wire VARINT (0), mengembalikan byte yang ditulis |
| `encodeDouble(field_number, val, buf)` | tipe wire I64 (1), IEEE 754 little-endian 8 byte, mengembalikan byte yang ditulis |
| `decodeDouble(payload)` | membaca `*const [8]u8`, mengembalikan `f64` |
| `MessageReader.init(buf)` | membungkus buffer pesan yang telah diserialisasi |
| `MessageReader.next()` | mengembalikan `?ProtoField` dengan `field_number`, `wire_type`, `payload` |

Contoh encoding `HelloRequest { string name = 1; }`:

```zig
var out: [256]u8 = undefined;
const n = zix.Grpc.encodeString(1, "world", &out);
// kirim out[0..n] sebagai payload pesan gRPC
```

## TLS

`zix.Grpc` melayani h2c (cleartext) secara default. Menyetel `tls: ?*Tls.Context` di config opt-in ke gRPC over TLS (TLS 1.3, dengan fallback 1.2, ALPN h2), dengan dua jalur serve yang dipilih oleh `dispatch_model` (ADR-052). Pada `.EPOLL` / `.URING`, satu worker epoll `SO_REUSEPORT` per core menterminasi TLS di tempat lewat session resumable (`tcp/tls/tls_session.zig`) dan memultipleks banyak koneksi per worker (`grpc/tls_mux.zig`), tanpa socketpair dan tanpa thread per koneksi. Pada `.ASYNC`, terminator thread-per-koneksi (`grpc/tls_serve.zig`) menjalankan `tcp/tls/h2_terminator.zig` bersama dengan driver inline-mux yang menggerakkan mux gRPC resumable langsung di atas record terdekripsi dan menyegel frame kembali ke record TLS lewat write hook thread-local (dipakai juga oleh Http2). Cert / key / policy berada di `Tls.Context` (ADR-047), dipakai ulang lintas engine. Dengan `tls_port` diisi bersama `tls`, SATU server melayani h2c di `port` dan gRPC over TLS di `tls_port` dari worker fleet yang sama (ADR-060).

```mermaid
graph LR
    C[gRPC client\nTLS/port 8443] -->|grpc over tls| Z[zix.Grpc server\nTLS terminator + engine h2c]
```

Reverse proxy tetap alternatif ketika TLS offload, routing, atau berbagi port dengan service lain diinginkan. Lihat [`docs/hld-proxy-id.md`](hld-proxy-id.md) untuk contoh konfigurasi nginx dan haproxy.

## Contoh

| Berkas | Pola |
| :- | :- |
| `examples/grpc_server.zig` | model dispatch dipilih per target (URING di Linux, ASYNC di platform lain): handler SayHello, Echo, dan StreamSum, port 9032 |
| `examples/grpc_client.zig` | demo unary call dan manual streaming, port 8083 |
| `examples/grpc_timeout.zig` | demo context timeout: handler_timeout_ms, Route.timeout_ms, ctx.isExpired(), penimpaan ctx.deadline_ns, port 8084 |
| `examples/grpc_location_server.zig` | location.Location/SendLocationAndSave, model dispatch dipilih per target, port 9038 |
| `examples/grpc_location_client.zig` | client layanan lokasi: encode field double, decode respons bool |
| `examples/grpc_multi_server.zig` | ASYNC, helloworld.Greeter + location.Location pada satu port (10102), logger terhubung |
| `examples/grpc_multi_client.zig` | memanggil kedua layanan pada satu koneksi, port 10102 |
| `examples/protobuf/helloworld.proto` | skema proto3 untuk helloworld.Greeter/SayHello |
| `examples/protobuf/location.proto` | skema proto3 untuk location.Location/SendLocationAndSave |

## Pengujian

| Tier | Berkas | Jumlah |
| :- | :- | :- |
| unit | inline di `src/tcp/http2/grpc/*.zig` melalui `refAllDecls` | ~40 |
| integration | `tests/integration/grpc/server_test.zig` | 9 |
| behaviour | `tests/behaviour/grpc/config_test.zig` | 7 |
| edge | `tests/edge/grpc/server_test.zig` | 13 |

Port: integration 18200-18206, edge 18220-18221.

---

###### end of hld-grpc
