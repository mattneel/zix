# HLD: zix.Http2

Engine server HTTP/2 (h2c) pure-Zig: frame codec, HPACK, dan state machine multiplexed yang resumable di atas raw fd I/O, tanpa `std.http` pada jalur frame.

---

## Tujuan

- h2c pure-Zig: frame codec plus HPACK (static table, dynamic table, Huffman) tanpa C FFI dan tanpa `std.http` pada jalur frame.
- Satu handler per stream yang selesai: handler menerima trio `req`/`res`/`ctx` (ADR-063), `Response` menulis langsung ke fd di baliknya.
- Multiplexed sejak rancangan: model `.EPOLL` / `.URING` menggerakkan banyak koneksi dan banyak stream konkuren dari satu worker thread melalui state machine yang resumable, tanpa thread per stream.
- Router dibangun saat comptime, `Server.init` menerima handler runtime (ADR-063), nol heap untuk routing.
- Raw `std.posix` I/O pada jalur data: `std.Io` hanya dipakai untuk plumbing listen/accept.
- TLS native (ALPN h2) bersifat tambahan di atas default h2c, sehingga dispatch cleartext tidak tersentuh.

---

## Posisi: zix.Http2 vs zix.Http1 vs zix.Grpc

Ketiganya adalah engine raw-fd dengan tiga model dispatch yang sama dan (sejak ADR-063) trio handler `req`/`res`/`ctx` yang sama. `zix.Http1` dan `zix.Grpc` tetap membakukan routing ke dalam tipe `Server` saat comptime, `Server` milik `zix.Http2` menerima handler runtime yang dibangun dari `Router` comptime (lihat bentuk `Server.init` di bawah). Perbedaannya pada protokol dan apa yang diekspos `Response` / `Context` masing-masing.

| Aspek | `zix.Http1` | `zix.Http2` | `zix.Grpc` |
| :- | :- | :- | :- |
| Protokol | HTTP/1.1 | HTTP/2 h2c | gRPC di atas HTTP/2 h2c |
| Signature handler | `fn(*Request, *Response, *Context) anyerror!void` (trio, ADR-062) | `fn(*Request, *Response, *Context) anyerror!void` (trio, ADR-063) | `fn(*Request, *Response, *Context) anyerror!void` (trio, ADR-063) |
| Konkurensi per koneksi | satu request pada satu waktu (pipelined) | banyak stream konkuren | banyak stream konkuren |
| Codec header | parse teks mentah | HPACK | HPACK |
| Allocator / context per-request | arena per-request via `Context` | stack arena per-request via `Context` | stack arena per-request via `Context` |
| Response streaming | helper chunked / SSE | DATA dengan flow control (`sendResponseStreamFD`, raw escape hatch) | `res.sendMessage` |
| Kebijakan error handler | auto-500 jika belum ada yang dijawab | auto-500 jika belum ada yang dijawab | call yang masih terbuka ditutup dengan `grpc-status 13` (INTERNAL) |
| Bentuk `Server.init` | `init(handler, config)`, `Router(routes).dispatch` | `init(handler, config)`, `Router(routes).dispatch` | `init(Router(routes), config)` (satu pengecualian: engine harus melihat `Route.is_server_streaming` sebelum dispatch) |
| Relasi layer | standalone | standalone | dibangun di atas `zix.Http2` |

Pakai `zix.Http2` untuk HTTP/2 kelas browser atau prior-knowledge dengan kontrol frame mentah. Pakai `zix.Grpc` saat payload-nya gRPC (ia memakai ulang layer frame dan HPACK engine ini). Pakai `zix.Http1` saat satu request per koneksi sudah cukup.

---

## Model Runtime

Tiga model dispatch, dipilih melalui `config.dispatch_model` (enum `DispatchModel`). Wajib: pemanggil harus menyetelnya secara eksplisit (tidak ada default). `.EPOLL` dan `.URING` khusus Linux, dan `run()` menolak keduanya di luar Linux dengan `error.ZixDispatchModelUnsupported` (ADR-065).

### .ASYNC: Thread-per-connection di atas core blocking

Satu task `io.async` memiliki koneksi sepanjang hidupnya dan menjalankan loop h2c blocking (`serveH2cLoop`), membaca satu frame sekaligus dan men-dispatch setiap stream yang lengkap secara inline. Ini model portabel, bentuk yang sama dengan `zix.Http1`.

```mermaid
flowchart TD
    MAIN["Server.run()"] --> A["1 accept thread\nio.async() per connection"]
    A --> SERVE["core.serveConn(routes, fd, opts)"]
    SERVE --> PRE{"PRI preface?"}
    PRE -->|yes| DIRECT["h2c direct"]
    PRE -->|no| UP["h2c upgrade (Upgrade: h2c)"]
    DIRECT --> LOOP["serveH2cLoop\nread frame -> dispatch complete stream"]
    UP --> LOOP
    LOOP --> LOOP
```

- Satu accept thread, setiap koneksi di-dispatch sebagai task `io.async` konkuren. `workers` diabaikan.
- Satu-satunya model yang tersedia di semua platform, jadi ini model yang dipakai setiap target non-Linux.

### .EPOLL: Event Loop Multiplexed Shared-Nothing (khusus Linux)

```mermaid
flowchart TD
    MAIN["Server.run()"] --> SPAWN["spawn workers mux workers"]
    SPAWN --> W["epollMuxWorker\nprivate SO_REUSEPORT listener\nprivate epoll instance\nprivate ConnTable (fd -> MuxConn)"]
    W --> WAIT["epoll_wait (drain up to 512 events)"]
    WAIT --> EV{"event fd?"}
    EV -->|listener| ACCEPT["acceptAll\naccept4 NONBLOCK to EAGAIN\nMuxConn.init, register in epoll"]
    EV -->|connection| READ["beginCoalesce\nmux.onReadable(routes, conn)\nendCoalesce (one write per batch)"]
    ACCEPT --> WAIT
    READ --> WAIT
```

- Setiap worker memiliki listener pribadi, instance epoll pribadi, dan `ConnTable` ter-index fd. Kernel menyeimbangkan koneksi baru di antara listener `SO_REUSEPORT` per-worker, sehingga tidak ada accept thread, tidak ada queue bersama, dan tidak ada handoff fd antar thread.
- Satu worker menggerakkan banyak koneksi non-blocking melalui state machine h2 yang resumable di `mux.zig`, satu `MuxConn` per fd, sehingga konkurensi dibatasi oleh jumlah koneksi, bukan jumlah thread.
- Setiap frame yang ditulis oleh readable batch (HEADERS plus DATA per stream, dikali jumlah stream dalam batch) di-coalesce menjadi satu `write()` melalui sink per-worker (`beginCoalesce` / `endCoalesce`), alih-alih satu write per frame.
- `workers` adalah jumlah mux worker (0 = cpu count). Handler berjalan inline pada worker, jadi harus tetap terbatas: handler yang lama memblokir koneksi lain pada worker itu.
- Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported` setelah mencatat model mana yang ditolak: pakai `.ASYNC` di sana.

### .URING: Event Loop io_uring Shared-Nothing (khusus Linux)

Topologi shared-nothing, satu-listener-per-worker yang sama dengan `.EPOLL`, tetapi completion-based: satu multishot accept dan satu recv per koneksi disubmit sebagai SQE dan dipanen sebagai CQE (ADR-037 Phase 4). Setiap recv mengisi read accumulator koneksi, lalu `mux.processRing` menggerakkan state machine yang resumable yang sama. Handler tetap menulis balasannya langsung ke fd (non-blocking), di-batch oleh coalescing sink yang sama.

`.URING` memeriksa io_uring sekali saat startup (`initUringRing`). Saat ring tidak tersedia (kernel lama, sandbox seccomp, atau cap `RLIMIT_MEMLOCK` yang terlalu rendah untuk ring), ia melipat ke loop shared-nothing `.EPOLL`, sehingga memilih `.URING` tidak pernah membuat server terdampar tepat setelah binding. Itu capability gap saat runtime di Linux. Di luar Linux model-nya ditolak langsung dengan `error.ZixDispatchModelUnsupported`.

---

## Struktur Berkas

```mermaid
graph TD
    zix["src/lib.zig\npublic API root"] --> Http2["tcp/http2/Http2.zig\nzix.Http2 namespace"]

    Http2 --> core["core.zig\nblocking h2c loop\nserveConn + Router"]
    Http2 --> mux["mux.zig\nresumable MuxConn state machine\nflow control + stream pool"]
    Http2 --> frame["frame.zig\nframe codec + control-frame senders\nsendResponseFD / sendResponseEncodedFD"]
    Http2 --> hpack["hpack.zig\nstatic table + Huffman\ndecoder + encoder + respHeaderBlock"]
    Http2 --> config["config.zig\nHttp2ServerConfig"]
    Http2 --> server["server.zig\nServer + dispatch_model switch"]
    Http2 --> static["static.zig\nfallback public_dir\nHEADERS + frame DATA yang dibatasi"]

    server --> dispatch["dispatch/\nasync epoll uring + common"]
    server --> tls_serve["tls_serve.zig\nthread-per-conn TLS terminator"]
    server --> tls_mux["tls_mux.zig\nmultiplexed per-core TLS terminator"]

    dispatch --> core
    dispatch --> mux
    mux --> frame
    mux --> hpack
    core --> frame
    core --> hpack
    static --> frame
    static --> hpack
    static --> static_cache["utils/static_cache.zig\ncache file terbuka bersama"]
```

---

## API Publik

Diakses melalui `const zix = @import("zix");`

| Simbol | Tipe | Deskripsi |
| :- | :- | :- |
| `zix.Http2.Server` | struct | `init(handler, config)`, lalu `run()` / `deinit()` (ADR-063: `handler` adalah `HandlerFn` runtime, bukan tabel route comptime) |
| `zix.Http2.ServerConfig` | struct | Konfigurasi server (lihat bagian Http2ServerConfig) |
| `zix.Http2.DispatchModel` | enum(u8) | `.ASYNC`(0, portabel) `.EPOLL`(1, hanya Linux) `.URING`(2, hanya Linux) |
| `zix.Http2.HandlerFn` | type | `*const fn(req: *Request, res: *Response, ctx: *Context) anyerror!void` (trio ADR-063, mencerminkan Http1/ADR-062) |
| `zix.Http2.Route` | struct | `{ path, handler, kind = .EXACT }` |
| `zix.Http2.RouteKind` | enum(u8) | `.EXACT` `.PREFIX` (tanpa `.PARAM` pada tahap ini) |
| `zix.Http2.Router` | fn | `Router(comptime routes) type`, mengembalikan tipe dengan `dispatch` yang cocok persis dengan `HandlerFn` (bisa langsung dipakai sebagai handler `Server.init`); path tak cocok mendapat 404 `text/plain` |
| `zix.Http2.Request` | struct | `{ method, path, query, headers, body }`, view zero-copy atas header/body stream yang di-decode, plus `header(name)` dan `queryParam(name)` |
| `zix.Http2.Response` | struct | Builder tipis atas `frame.sendResponseFD` / `sendResponseEncodedFD`: `setStatus` / `setContentType` / `send` / `sendJson` / `sendText` / `sendNoContent`, semuanya `!void`. `sent: bool` menjaga auto-500 |
| `zix.Http2.Context` | struct | `fd`, `sid`, `deadline_ns` + `withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut`, `io`, dan `allocator` stack-arena (`FixedBufferAllocator`, tanpa pemanggilan heap) |
| `zix.Http2.ServeOpts` | struct | Opsi serve per-connection yang dibangun dari config |
| `zix.Http2.serveConn` | fn | `serveConn(handler, fd, opts, io)`: entry point koneksi blocking langsung |
| `zix.Http2.Header` | struct | `{ name: []const u8, value: []const u8 }` header request hasil decode |
| `zix.Http2.sendResponseFD` | fn | `sendResponseFD(fd, sid, status, content_type, body)`: HEADERS plus DATA, END_STREAM pada frame terakhir (langsung, tanpa metering) |
| `zix.Http2.sendResponseEncodedFD` | fn | `sendResponseFD` plus header `content-encoding` (menyajikan body pra-kompres) |
| `zix.Http2.sendResponseStreamFD` | fn | Pengiriman dengan flow control untuk body besar milik pemanggil (dipacu oleh WINDOW_UPDATE, body harus hidup lebih lama dari stream) |
| `zix.Http2.serveCached` / `sendCachedFD` / `cacheTtl` | fn | Response cache per-worker (ADR-036), opt-in via `response_cache` (`.EPOLL` / `.URING`) |
| `zix.Http2.HpackEncoder` / `HpackDecoder` / `HpackEntry` | type | Tipe codec HPACK |
| `zix.Http2.huffEncode` / `huffDecode` | fn | Codec Huffman HPACK |
| `zix.Http2.respHeaderBlock` | fn | Meng-encode blok `[:status, content-type, content-encoding, content-length]` yang di-cache |
| `zix.Http2.FrameHeader` + `parseFrameHeader` / `writeFrameHeaderFD` / `encodeFrameHeader` / `readFrameHeader` | type / fn | Codec frame-header untuk framing kustom |
| `zix.Http2.sendSettingsFD` / `sendSettingsAckFD` / `sendPingAckFD` / `sendGoawayFD` / `sendRstStreamFD` / `sendWindowUpdateFD` | fn | Pengirim control-frame |
| `zix.Http2.FRAME_TYPE_*` / `FLAG_*` / `ERR_*` / `SETTINGS_*` | const | Konstanta frame, flag, error, dan settings RFC 7540 |
| `zix.Http2.PREFACE` / `HPACK_STATIC` | const | String connection preface, static table HPACK |

---

## Http2ServerConfig

Field utama (tabel lengkap ada di [`docs/zix-config-id.md`](zix-config-id.md)):

```zig
pub const Http2ServerConfig = struct {
    io:             std.Io,        // hanya plumbing listen/accept, harus hidup lebih lama dari server
    ip:             []const u8,
    port:           u16,           // harus non-zero
    dispatch_model: DispatchModel, // wajib, tidak ada default
    kernel_backlog: u31   = 1024,
    workers:        usize = 0,     // .EPOLL/.URING: 0 = cpu_count mux worker. Diabaikan oleh .ASYNC
    worker_stack_size_bytes: usize = 512 * 1024,
    busy_poll_us:   u32   = 0,     // window spin SO_BUSY_POLL (.EPOLL/.URING), 0 = tidak diset
    max_streams:    u32   = 128,   // SETTINGS_MAX_CONCURRENT_STREAMS yang diiklankan
    max_frame_size: u32   = 16384, // SETTINGS_MAX_FRAME_SIZE yang diiklankan
    max_header_scratch: usize = 4096,       // scratch decode HPACK per koneksi
    max_body:       usize = 16384, // body request maksimum yang di-buffer per stream (body di atas ini di-shed dengan 413)
    max_recv_buf:   usize = 32 * 1024,      // floor read-buffer per-connection (.EPOLL/.URING)
    tls_write_buf_initial_bytes: usize = 16 * 1024,
    response_cache: bool  = false, // response cache per-worker (ADR-036), semua model
    handler_timeout_ms: u32 = 0,   // deadline global yang diseed ke Context.deadline_ns, 0 = tanpa deadline
    public_dir:     []const u8 = "",        // root file static, "" menonaktifkan penyajian static
    public_dir_cache_ttl_ms:      u32 = 0,  // 0 = tidak pernah di-cache, default bawaan
    public_dir_cache_max_entries: u32 = 256,// slot cache static, satu per file plus sibling-nya
    tls:            ?*Tls.Context = null,   // non-null menyajikan h2 di atas TLS (ALPN h2), selain itu h2c cleartext
    logger:         ?*Logger = null,        // baris lifecycle saja, lihat bagian Logging
};
```

Catatan: `workers` adalah jumlah mux worker pada `.EPOLL` / `.URING` (0 = cpu count), dan meng-oversubscribe-nya hanya menambah churn scheduler. `.ASYNC` mengabaikannya. `max_recv_buf` adalah floor: read accumulator mux diukur sebesar nilai yang lebih besar antara ia dan satu frame maksimum, sehingga floor yang lebih besar memangkas `read()` dan compaction buffer untuk frame besar. `tls` opt-in ke h2 di atas TLS: saat non-null server menyajikan pada jalur TLS ter-gate (model dispatch cleartext tidak tersentuh), dan untuk HTTP/2 ALPN context sebaiknya menyertakan `.H2`. Field `response_cache` dan `cache_*` mengonfigurasi cache per-worker yang opt-in (ADR-036), dibaca saat runtime pada `.EPOLL` dan `.URING`.

`handler_timeout_ms` (ADR-063) adalah deadline global: diseed ke `Context.deadline_ns` saat dispatch, 0 berarti tanpa deadline. Handler bisa memperketat atau menghapus deadline-nya sendiri via `ctx.setTimeout` / `withDeadline`, dicek dengan `ctx.isExpired()` di antara langkah-langkah (engine tidak pernah menginterupsi handler yang sedang berjalan, ini opt-in).

---

## Model Handler

```zig
fn home(req: *zix.Http2.Request, res: *zix.Http2.Response, ctx: *zix.Http2.Context) !void {
    _ = req;
    _ = ctx;

    try res.sendText("hello");
}

const router = zix.Http2.Router(&[_]zix.Http2.Route{
    .{ .path = "/", .handler = home },
});

var server = zix.Http2.Server.init(
    router.dispatch,
    .{ .io = process.io, .ip = "0.0.0.0", .port = 8082, .dispatch_model = .EPOLL },
);
defer server.deinit();
try server.run();
```

- `Server.init` menerima `handler: HandlerFn` runtime (ADR-063), dibangun via `Router(&[_]Route{...}).dispatch`. Route sendiri tetap comptime (dibakukan ke dalam tipe router), tapi server tidak lagi membakukan tabel route ke dalam tipenya sendiri, sehingga `Server` adalah satu struct konkret, bukan generik.
- Handler dipanggil sekali per stream yang selesai (END_HEADERS plus END_STREAM), via `core.invokeHandler` yang membangun trio lalu men-dispatch. `req.method`, `req.headers`, dan `req.body` semuanya menunjuk ke buffer per-stream dan hanya valid selama pemanggilan berlangsung.
- `ctx.allocator` adalah stack arena per-request (`FixedBufferAllocator`, tanpa pemanggilan heap), `ctx.io` membawa `std.Io` koneksi, dan `ctx.deadline_ns` / `isExpired()` mencakup timeout Layer B (lihat `handler_timeout_ms` di atas).
- Handler mengembalikan `anyerror!void`. Saat error, `invokeHandler` otomatis menyelesaikan satu 500 (`frame.sendResponseFD(fd, sid, 500, "text/plain", "Internal Server Error")`), tapi hanya ketika `!res.sent`, sehingga response yang sudah terkirim sebagian tidak pernah rusak.
- Response keluar melalui `Response.send` / `sendJson` / `sendText` / `sendNoContent`, builder tipis atas writer `frame.sendResponseFD` / `sendResponseEncodedFD` yang sama seperti sebelumnya (wire byte-identical, ADR-063 hanya mengubah apa yang membungkus pemanggilan). Body besar berumur proses tetap memakai escape hatch `mux.sendResponseStreamFD` mentah secara langsung (dipacu oleh flow control), tidak dibungkus oleh `Response`.
- Engine memetakan path ke handler melalui `Router(routes).dispatch` sebelum pemanggilan (EXACT lalu PREFIX terpanjang, path tak cocok mencoba fallback static di bawah lalu mendapat 404 `text/plain`), sehingga handler tidak mem-parse atau mencocokkan path itu sendiri.

---

## Penyajian File Static

`public_dir` (ADR-064) menyajikan route yang tidak cocok sebagai file sebelum 404. Kosong (default) menonaktifkannya, dan direktori yang tidak ada gagal saat `run()` dengan `error.ZixPublicDirNotFound`, bukan mem-404-kan setiap request file saat runtime.

```mermaid
flowchart TD
    A["router: tidak ada route cocok"] --> B{"ctx.public_dir diisi?"}
    B -->|tidak| Z["404 Not Found"]
    B -->|ya| C{"path mengandung '..'?"}
    C -->|ya| Z
    C -->|tidak| D["negosiasi encoding, resolve file"]
    D -->|tidak ada| Z
    D -->|ketemu| E{"ada header Range?"}
    E -->|tidak ada atau malformed| F["200, file utuh"]
    E -->|terpenuhi| G["206 dengan Content-Range"]
    E -->|melewati akhir| H["416, header saja"]
    F --> I["satu frame HEADERS, lalu frame DATA"]
    G --> I
    I --> J["frame DATA terakhir membawa END_STREAM"]
```

- Satu frame HEADERS membawa status, content type, `content-length`, `accept-ranges`, dan `content-range` bila response-nya 206. File kosong menutup stream pada HEADERS tanpa DATA sama sekali.
- Frame DATA dibatasi oleh `SETTINGS_MAX_FRAME_SIZE` milik **peer**, bukan `max_frame_size` server ini. Keduanya nilai berbeda: `max_frame_size` adalah yang server ini iklankan akan diterimanya, dan mengukur frame keluar dengan nilai itu justru yang dijawab peer patuh dengan `FRAME_SIZE_ERROR`. Nilai peer datang dari mux, dari frame SETTINGS di tengah koneksi, atau dari header base64 `HTTP2-Settings` pada upgrade h2c.
- Range (RFC 7233) disajikan: 206 untuk range yang terpenuhi, 416 dengan `Content-Range: bytes */length` untuk range well-formed yang melewati akhir file, dan header malformed diabaikan sehingga file utuh yang dikirim, sesuai bagian 3.1. Header multi-range dijawab range pertama saja.
- Kedua jalur dibangun, yang di-cache maupun yang tidak, jadi `public_dir` berperilaku sama baik `public_dir_cache_ttl_ms` diatur maupun tidak. Bila diatur, request berulang berbiaya satu lookup hash alih-alih open plus stat, dan sibling `.br` / `.gz` di-resolve sekali saat insert alih-alih diprobe per request. Setiap header varian yang di-cache membawa `Vary: Accept-Encoding`.
- Zero copy (`sendfile`) selalu ditolak di engine ini, termasuk cleartext, karena hook coalescing mux (`frame.write_hook`) terpasang di setiap batch dan write socket langsung akan menaruh body mendahului frame yang sudah di-stage. Body dipotong dari snapshot resident sebagai gantinya.
- Pengiriman static memakai jalur `frame.sendResponseFD` tanpa metering yang sama seperti `Response.send`, bukan `mux.sendResponseStreamFD` yang dipacu window. Itu konsisten dengan bagian lain engine ini dan layak ditinjau bersama jalur tersebut, bukan terpisah.
- `public_dir_upload` tidak ditawarkan di sini. `zix.Http2` tidak punya konvensi handler upload, tidak seperti `zix.Http` dan `zix.Http1`.

---

## State Machine Multiplexed

Model `.EPOLL` / `.URING` menggerakkan `mux.zig`, satu `MuxConn` per fd. Read accumulator (`rbuf`, dilacak oleh `rstart` / `rend`) bertahan lintas readable event dan menahan frame parsial sampai sisanya tiba, sehingga worker dapat me-resume koneksi di tengah frame dan menggerakkan banyak koneksi dari satu thread.

Sebuah koneksi maju melalui fase-fase preface, lalu sebuah frame loop:

```mermaid
stateDiagram-v2
    [*] --> await_preface
    await_preface --> h2: PRI preface + server SETTINGS
    await_preface --> await_upgrade: HTTP/1.1 Upgrade
    await_upgrade --> await_preface2: 101 written
    await_preface2 --> h2: preface + server SETTINGS
    h2 --> h2: frame loop
```

Di dalam fase `.h2` frame loop membaca header 9-byte, menunggu payload penuh tiba di `rbuf` (mengembalikan `keep_alive` saat belum), lalu men-dispatch berdasarkan tipe:

- SETTINGS: terapkan header-table size dan initial window milik peer (menyesuaikan send window setiap stream terbuka sesuai RFC 7540 6.9.2), lalu ACK dan berikan WINDOW_UPDATE level-koneksi.
- HEADERS / CONTINUATION: klaim satu stream slot, HPACK-decode blok ke dalam header stream, dan dispatch saat END_HEADERS plus END_STREAM terlihat.
- DATA: kembalikan WINDOW_UPDATE untuk koneksi dan stream, salin payload ke dalam body stream, dan dispatch saat END_STREAM. Body yang melewati `max_body` di-shed dengan 413 dan END_STREAM alih-alih dipotong, hanya window koneksi yang dikredit untuk byte yang dibuang.
- WINDOW_UPDATE: tumbuhkan send window koneksi atau stream dan resume response body yang terparkir.
- RST_STREAM: lepaskan stream slot. PING: balas dengan ACK. GOAWAY: tutup koneksi.

Pelanggaran protokol (stream id 0 di tempat yang ilegal, frame kelewat besar, preface yang buruk) mengirim GOAWAY atau RST_STREAM. `core.serveH2cLoop` blocking menjalankan protokol yang sama di atas blocking read dengan array stream per-connection alih-alih slot ter-pool.

---

## HPACK

`hpack.zig` adalah codec HPACK lengkap tanpa dependensi eksternal.

- Request decoder: static table 61-entri plus dynamic table (hingga 128 entri) yang didukung buffer berumur koneksi (`dyn_buf`, 8 KB) dengan eviction terbatas ukuran dan compaction in-place. Nilai indexed dan literal disalin ke scratch per-stream milik pemanggil, sehingga slice header hasil decode tetap stabil bahkan setelah scratch dipakai ulang untuk stream berikutnya. String ber-kode Huffman di-decode secara on the fly.
- Response encoder: stateless (static table plus literal-without-indexing, tidak pernah dynamic table atau size update), sehingga suatu blok header identik secara byte pada setiap koneksi.
- `respHeaderBlock`: meng-encode `[:status, content-type, content-encoding, content-length]`. Karena encoder-nya stateless, prefix `[:status, content-type, content-encoding]` di-cache per triple berbeda (cache append-only dengan lock-free-read) dan hanya `content-length` yang bervariasi yang di-encode ulang per pemanggilan, sehingga jalur response panas melewati scan static-table berulang dan encode Huffman dari content-type yang sama.

---

## Flow Control

Flow control sisi-kirim mengikuti RFC 7540 6.9. Setiap `MuxConn` membawa send window level-koneksi, dan setiap stream terbuka membawa send window-nya sendiri, keduanya dimulai pada 65535 (disesuaikan dengan initial window yang diiklankan peer).

- `pumpBody` mengirim DATA yang dibatasi oleh `min(connection window, stream window, max_frame_size)`. Yang tidak muat diparkir pada stream (`pending_body`, `pending_end`) dan stream slot tetap dipinjam. END_STREAM menumpang pada frame terakhir hanya setelah seluruh body keluar.
- Sebuah WINDOW_UPDATE me-resume kerja yang terparkir: `resumeStream` untuk grant level-stream, `resumeAll` untuk grant level-koneksi. Slot dibebaskan setelah body-nya terkuras penuh.
- `sendResponseStreamFD(fd, sid, status, content_type, content_encoding, body)` adalah entry publik. Body-nya direferensikan, bukan disalin, jadi harus hidup lebih lama dari stream (cache berumur proses, bukan scratch buffer per-request). Tanpa connection context aktif (jalur serve non-mux blocking) ia jatuh kembali ke pengiriman langsung tanpa metering.
- DATA masuk mengembalikan WINDOW_UPDATE untuk koneksi maupun stream agar peer terus mengirim.

---

## h2 di atas TLS

Menyetel `config.tls` (sebuah `*Tls.Context`) opt-in ke HTTP/2 di atas TLS (TLS 1.3 dengan fallback 1.2, ALPN h2). Switch `run()` di `server.zig` memilih salah satu dari dua terminator berdasarkan `dispatch_model`:

- `.EPOLL` / `.URING`: `tls_mux.runTlsMux`. Satu epoll worker `SO_REUSEPORT` per core melakukan terminasi TLS di tempat via session yang resumable (`tcp/tls/tls_session.zig`) dan mem-multiplex banyak koneksi per worker, tanpa socketpair dan tanpa thread per koneksi. Mux h2 yang resumable mengonsumsi plaintext hasil dekripsi, dan frame balasannya dienkripsi kembali menjadi TLS record melalui frame write hook thread-local. Ciphertext keluar yang tidak muat di-stage per koneksi dan di-flush pada EPOLLOUT berikutnya, sehingga klien lambat tidak pernah memarkir worker.
- `.ASYNC`: `tls_serve.runTls`. Sebuah accept loop menyerahkan setiap koneksi ke worker thread-nya sendiri, yang menjalankan terminator bersama (`tcp/tls/h2_terminator.zig`) dengan driver inline-mux yang menggerakkan mux resumable yang sama langsung di atas stream hasil dekripsi (satu thread per koneksi, tanpa socketpair). Jalur ini juga menyajikan TLS 1.2.

Write hook (`frame.write_hook`) adalah mekanisme bersama: mux menulis plaintext melalui `frame.writeAllFD`, dan hook menyegelnya menjadi record pada jalur TLS (hook yang sama mem-batch frame menjadi satu write per readable batch pada jalur cleartext `.EPOLL` / `.URING`). Cert / key / policy berada di `Tls.Context` (ADR-047), dipakai ulang lintas engine. TLS berjalan pada performance band-nya sendiri. Lihat [`docs/hld-tls-id.md`](hld-tls-id.md).

---

## Logging

`config.logger` hanya menerima baris lifecycle server (notice listening, fallback io_uring, fallback non-Linux) via `logger.system()`. Saat null, baris lifecycle dicetak ke stderr hanya pada Debug build dan diam pada release build.

Access logging per-stream adalah tanggung jawab engine, bukan handler. Saat `config.logger` diisi, engine menulis satu record `[http2:access]` setelah setiap stream yang dilayani, mengambil status dan jumlah byte dari `Response`. Handler yang membingkai byte-nya sendiri lewat `frame.sendResponseFD` tetap tercatat, tetapi jumlah byte-nya terbaca 0, sehingga handler seperti itu boleh memanggil `logger.access()` sendiri di titik ukuran sebenarnya diketahui.

---

## Model Memori

| Lingkup | Penyimpanan | Masa hidup |
| :- | :- | :- |
| Tabel route | comptime (nol biaya heap) | Proses |
| Frame payload + array stream (.ASYNC) | `smp_allocator`: satu payload buffer plus `max_streams` slot `Stream` inline (masing-masing membawa buffer body dan header-scratch-nya sendiri) | Koneksi |
| MuxConn per-connection (.EPOLL/.URING) | `smp_allocator`: read accumulator (floor `max_recv_buf`) plus array pointer `*MuxStream` selebar `max_streams` dan flag slot | Koneksi |
| State stream terbuka (.EPOLL/.URING) | pool `MuxStream` thread-local per-worker (free-list), buffer `max_body` dan `max_header_scratch` tiap slot dipakai ulang lintas peminjaman | Stream konkuren (dikembalikan ke pool saat close) |
| Dynamic table HPACK | inline di decoder koneksi (`dyn_buf`, 8 KB) | Koneksi |
| Response cache per-worker (opt-in) | `smp_allocator`, `cache_max_entries` * `cache_max_value_bytes` per worker | Worker thread |
| Alokasi handler | `ctx.allocator`: stack `FixedBufferAllocator` (`CTX_ARENA_BYTES`, tanpa pemanggilan heap), direset per request | Request |
| Cache file static (opt-in) | satu mapping demand-paged yang dipakai bersama semua worker dan semua engine HTTP dalam proses, `public_dir_cache_max_entries` slot berisi file terbuka, ukurannya, dan header yang sudah dirender | Proses |

Mux `.EPOLL` / `.URING` meminjam tiap stream slot dari pool thread-local per-worker (free-list berisi `MuxStream`), sehingga memori stream residen mengikuti jumlah stream konkuren pada worker itu, bukan jumlah koneksi dikali `max_streams`. Koneksi idle hanya menahan array pointer selebar `max_streams` dan read buffer-nya, bukan `max_streams` buffer stream penuh. Stream yang tertutup mengembalikan slot-nya (buffer dipertahankan) ke pool untuk peminjaman berikutnya, sehingga steady state tidak melakukan alokasi per-stream. Jalur blocking `.ASYNC` sebaliknya menyediakan array `Stream` inline per-connection di muka.

---

## Batasan yang Diketahui

| Batas | Perilaku |
| :- | :- |
| Body request per stream | Di-buffer hingga `max_body` (default 16 KB). Body yang melewati kapasitas buffer di-shed dengan 413 dan END_STREAM, jadi handler tidak pernah melihat slice terpotong dan body korup tidak pernah di-dispatch. Hanya window koneksi yang dikredit untuk byte yang dibuang, menjaga koneksi tetap dapat dipakai untuk stream lainnya |
| Stream konkuren | Diiklankan sebagai `max_streams` (`SETTINGS_MAX_CONCURRENT_STREAMS`). Stream yang dibuka melebihi itu dijawab dengan `REFUSED_STREAM`, jadi nilai yang diiklankan minimal harus sebesar jumlah concurrent-stream peer |
| Upgrade h2c (.EPOLL/.URING) | Disajikan minimal pada jalur mux: `101` lalu connection preface, request yang dibawa pada stream 1 tidak dilayani. Klien prior-knowledge (kasus h2c yang umum) tidak terpengaruh. Model blocking `.ASYNC` melayani request stream-1 hasil upgrade |
| Scratch blok header | `max_header_scratch` per koneksi (default 4 KB). Set header yang meluapkannya dijawab dengan `COMPRESSION_ERROR` dan RST_STREAM |
| Ukuran frame | Frame yang lebih besar dari `max_frame_size` plus slack adalah `FRAME_SIZE_ERROR` dan menutup koneksi dengan GOAWAY. DATA keluar diukur dengan nilai yang diiklankan peer, tidak pernah dengan nilai ini |
| File static | `public_dir` menyajikan file utuh dan range tunggal. Header multi-range dijawab range pertama saja, dan tidak ada companion `public_dir_upload` di engine ini |
| TLS | h2 di atas TLS (TLS 1.3 + 1.2, ALPN h2), opt-in via `config.tls`, pada perf band-nya sendiri. `.EPOLL` / `.URING` melakukan terminasi di worker epoll-mux event-driven, `.ASYNC` per koneksi di worker thread. Lihat [`docs/hld-tls-id.md`](hld-tls-id.md) |

Endpoint yang membutuhkan body request besar sebaiknya membacanya dalam frame DATA di dalam `max_body`, atau memindahkan transfer besar ke desain streaming (model ter-buffer mencakup body yang terbatas).

Untuk detail implementasi lihat [`docs/lld-http2-id.md`](lld-http2-id.md). Untuk terminator TLS lihat [`docs/hld-tls-id.md`](hld-tls-id.md).

---

###### end of hld-http2
