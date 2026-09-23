# HLD: zix.Http

HTTP server dan client yang dibangun di atas `std.Io` Zig 0.16.x.

---

## Tujuan

### Server
- Eksplisit lebih utama dari implisit: tidak ada magic, setiap perilaku dinamai dalam config atau registrasi.
- Satu berkas, satu tanggung jawab.
- Indirection minimal pada hot path.
- Tidak ada alokasi tersembunyi di dalam handler.
- Routing yang dapat diprediksi: prioritas dispatch bersifat deterministik.

### Client
- Konfigurasi eksplisit: allocator, io, timeout, batas body, dan kebijakan redirect semuanya dinamai.
- Response bertipe: status code, pencarian header, dan bytes body semuanya dimiliki oleh pemanggil.
- Error yang dinamai: `InvalidUrl`, `BodyTooLarge` muncul sebelum pemanggil harus memeriksa error stdlib.
- Tidak ada alokasi tersembunyi: setiap alokasi menggunakan allocator yang disuplai pemanggil.

---

## Model Runtime

Tiga model dispatch, dipilih melalui `config.dispatch_model` (enum `DispatchModel`). Wajib: pemanggil harus menyetelnya secara eksplisit (tidak ada default). `.EPOLL` dan `.URING` khusus Linux, jadi pemanggil portabel memilih model per target saat comptime dan `run()` menolak model khusus Linux di luar Linux dengan `error.ZixDispatchModelUnsupported` (ADR-065).

### .ASYNC: Accept Tunggal, Dispatch io.async()

```mermaid
flowchart TD
    MAIN["main()\nServer.run()"] --> D["net_server.accept(io)\nsuspends until TCP connection"]
    D --> E["io.async(handleConnection)"]
    E --> D
    E --> F["handleConnection()"]
    F --> G["stack/heap read_buf"]
    G --> H["pasang thread-local kompresi + cache"]
    H --> I["ArenaAllocator per-connection"]
    I --> J["keep-alive loop\nhandleOneRequest"]
    J --> K["recv sampai terminator header"]
    K -->|close or reset| Z["stream.close()"]
    K --> L["build Request + Response + Context"]
    L --> M["Router.dispatch()"]
    M -->|matched| N["HandlerFn"]
    M -->|no match| O{"public_dir set?"}
    O -->|yes| P["static.serve()"]
    O -->|no| Q["404 Not Found"]
    P -->|file not found| Q
    N --> J
    P --> J
    Q --> J
```

- Satu accept thread. Setiap koneksi di-dispatch sebagai task konkuren melalui `io.async()`.
- `workers` diabaikan (selalu tepat satu accept thread).
- Direkomendasikan untuk SSE dan WebSocket: satu stream terbuka hanya memakai satu task, bukan slot worker event loop.
- Satu-satunya model yang tersedia di semua platform, jadi ini model yang dipakai setiap target non-Linux.

### .EPOLL: Shared-Nothing epoll Worker (Linux-only)

```mermaid
flowchart TD
    MAIN["main(process)\nServer.run()"] --> SPAWN["spawn cpu_count worker\n(atau workers = N)"]
    SPAWN --> W1["Worker 0\nSO_REUSEPORT listener\nepoll_create1"]
    SPAWN --> W2["Worker 1\nSO_REUSEPORT listener\nepoll_create1"]
    SPAWN --> WN["Worker N-1\n..."]
    W1 --> EL["event loop\nepoll_wait(1024)"]
    EL -->|listener fd| ACC["drain accept4(SOCK_CLOEXEC)\nsetNoDelay\nepoll_ctl ADD EPOLLIN+RDHUP"]
    EL -->|conn fd RDHUP/ERR| CLOSE["epoll_ctl DEL\nclose(fd)"]
    EL -->|conn fd readable| SERVE["read sampai EAGAIN\nprocessRequest(fd)\nparse + dispatch + send"]
    SERVE -->|keep-alive| EL
    SERVE -->|close| CLOSE
    ACC --> EL
```

- Setiap worker memiliki satu `SO_REUSEPORT` listener dan satu `epoll` instance. Kernel mendistribusikan koneksi baru ke worker tanpa antrian bersama.
- Level-triggered `EPOLLIN`: koneksi tetap terdaftar setelah setiap request dan re-fires saat data baru tiba. Tidak perlu re-arm eksplisit.
- Fd non-blocking: worker membaca sampai EAGAIN ke buffer koneksi, lalu `processRequest` melakukan parse/dispatch/send secara sinkron dan mengembalikan worker ke `epoll_wait`.
- `workers` mengontrol jumlah worker (0 = cpu_count).
- Terbaik untuk request berumur pendek throughput tinggi di Linux. Tidak cocok untuk SSE atau WebSocket (blocking read akan menahan worker).
- Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported`: pakai `.ASYNC` di sana.

### .URING: Worker io_uring Shared-Nothing (Linux-only)

Topologi thread-per-core, shared-nothing yang sama dengan `.EPOLL` (satu `SO_REUSEPORT` listener dan satu ring per worker, tanpa queue bersama), tetapi completion-based alih-alih readiness-based: accept, read, dan write disubmit sebagai SQE dan dipanen sebagai CQE, sehingga sebagian besar transisi syscall di-batch ke dalam ring (`self.runUring(io)`, ADR-037 Fase 4).

- `workers` mengontrol jumlah worker (0 = cpu_count).
- Terbaik untuk beban sustained dan pipelined di mana ring yang di-batch mengamortisasi syscall. Di loopback setara `.EPOLL` pada throughput dan menang terutama pada cache locality. Di mesin many-core, ring close (`prep_close`, ADR-041, native ke `zix.Http1` untuk saat ini) membuat worker terus memanen completion lewat connection churn, di mana `.URING` mencapai paritas atau lebih baik dengan memori jauh lebih sedikit.
- Seperti `.EPOLL`, serve per-connection bersifat blocking begitu request siap, jadi tidak cocok untuk SSE atau WebSocket.
- Saat io_uring sendiri tidak tersedia di host (kernel lama, `RLIMIT_MEMLOCK` rendah, sandbox) engine melipat ke loop `.EPOLL` dengan notice yang dicatat. Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported`: pakai `.ASYNC` di sana.

`zix.Http.Server` menerima nilai `std.Io` yang opak dan tidak memiliki atau memanggil deinit pada backend tersebut. Lihat [`docs/concurrency-id.md`](concurrency-id.md) untuk detail jumlah thread dan perbandingan model.

---

## Struktur Berkas

```mermaid
graph TD
    zix["src/lib.zig\npublic API root"]

    zix --> Http["tcp/http/Http.zig\nzix.Http"]
    zix --> Tcp["tcp/Tcp.zig\nzix.Tcp"]
    zix --> Udp["udp/Udp.zig\nzix.Udp"]
    zix --> Uds["uds/Uds.zig\nzix.Uds"]
    zix --> Channel["channel/Channel.zig\nzix.Channel"]
    zix --> Logger["logger/logger.zig\nzix.Logger"]
    zix --> utils["utils/file.zig\nzix.utils.file"]
    Tcp -.->|re-exports| Http

    Http --> server["server.zig\nServer"]
    Http --> config["config.zig\nHttpServerConfig"]
    Http --> client["client.zig\nHttpClient + ClientResponse"]
    Http --> client_config["client_config.zig\nHttpClientConfig"]
    Http --> router["router.zig\nRouter + HandlerFn"]
    Http --> request["request.zig\nRequest"]
    Http --> response["response.zig\nResponse + HttpHeader"]
    Http --> context["context.zig\nContext"]
    Http --> static["static.zig"]
    Http --> multipart["utils/multipart.zig\nParser + Field"]
    Http --> websocket["websocket.zig\nWebSocket"]
    Http --> method["method.zig\nMethod.Code"]
    Http --> status["status.zig\nStatus.Code"]
    Http --> content["content.zig\nContent.Type"]

    Logger --> logger_impl["logger.zig\nLogger + Level\nConsoleMode + Config"]
    server -.->|optional access log| logger_impl
```

---

## Dependensi Modul

```mermaid
graph LR
    server --> config
    server --> router
    server --> request
    server --> response
    server --> context
    server --> static

    client --> client_config
    client --> method

    router --> request
    router --> response
    router --> context

    request --> method
    response --> status

    static --> content
    static --> utils_file["utils/file.zig"]
    upload --> self["self-contained"]

    middleware --> request
    middleware --> response
    middleware --> context
```

---

## API Publik

Diakses melalui `const zix = @import("zix");`

| Simbol | Tipe | Deskripsi |
| :- | :- | :- |
| `zix.Http.Server` | struct | Siklus hidup: `init(handler, config)` / `deinit()` / `run()` (ADR-063: `handler` dibangun via `Router(&routes).dispatch`, `Server` adalah satu struct konkret) |
| `zix.Http.ServerConfig` | struct | Konfigurasi server (lihat bagian HttpServerConfig) |
| `zix.Http.Client` | struct | HTTP client: `init` / `deinit` / `get` / `head` / `post` / `put` / `delete` / `patch` / `request` |
| `zix.Http.ClientConfig` | struct | Konfigurasi client (lihat bagian HttpClientConfig) |
| `zix.Http.ClientResponse` | struct | Response yang telah di-parse: `status` / `header` / `iterateHeaders` / `body` / `deinit` |
| `zix.Http.ClientRequestOpts` | struct | Opsi per-request: `headers`, `body`, override `connect_timeout_ms` |
| `zix.Http.Request` | struct | Reader per-request: method, path, query, header, body, bodyReceived, bodyComplete |
| `zix.Http.Response` | struct | Writer per-request: send, sendJson, noContent, addHeader, stream |
| `zix.Http.SseWriter` | struct | Penulis event SSE yang dikembalikan oleh `res.sendStream()`: writeEvent, writeNamedEvent, comment |
| `zix.Http.Context` | struct | Konteks per-request: io, allocator, stream (TCP mentah), deadline (anggaran handler opsional), logger (pointer logger opsional) |
| `zix.Logger` | struct | Logger berkas dan konsol: `init` / `deinit` / `flush` / `system` / `access` |
| `zix.Logger.Config` | struct | Konfigurasi logger: console, save_path (harus sudah ada, dibuat oleh pemanggil), save_file, level minimum, max_lines |
| `zix.Logger.Level` | enum(u8) | `DEBUG`(0) `INFO`(1) `WARN`(2) `ERROR`(3) |
| `zix.Logger.ConsoleMode` | enum(u8) | `OFF`(0) `DEBUG_ONLY`(1) `ALWAYS`(2) |
| `zix.Http.HandlerFn` | type | `*const fn(*Request, *Response, *Context) anyerror!void` |
| `zix.Http.Header` | struct | `{ name: []const u8, value: []const u8 }` |
| `zix.Tcp.DispatchModel` | enum(u8) | Model dispatch: `.ASYNC`(0, portabel) `.EPOLL`(1, Linux saja) `.URING`(2, io_uring Linux saja). Di luar Linux `run()` mengembalikan `error.ZixDispatchModelUnsupported` untuk dua yang terakhir |
| `zix.Http.RequestHeaderSize` | union(enum) | Batas header request: `.MINIMAL`(16) `.COMMON`(32) `.LARGE`(64) `.{ .CUSTOM = N }` |
| `zix.Http.default_user_agent` | `[]const u8` | String user agent client dari `build.zig.zon` (contoh: `"zix/0.5.0"`) |
| `zix.Http.HeaderSize` | union(enum) | Batas header response: `.MINIMAL`(16) `.COMMON`(32) `.LARGE`(64) `.EXTRA_LARGE`(128) `.{ .CUSTOM = N }` |
| `zix.Http.ContentType` | enum | Representasi MIME bertipe aman |
| `zix.Http.Content` | namespace | `typeFromExtension(ext)`, `fromExtension(ext)` |
| `zix.Http.Multipart` | struct | Parse body `multipart/form-data` (alias dari `zix.utils.multipart.Parser`) |
| `zix.Http.MultipartField` | struct | `{ name, filename, content_type, data, is_file }` (alias dari `zix.utils.multipart.Field`) |
| `zix.Http.WebSocket` | namespace | Parsing frame, handshake, broadcast room |
| `zix.Http.WebSocket.Opcode` | enum | continuation text binary close ping pong |
| `zix.Http.WebSocket.Frame` | struct | `{ fin, opcode, payload }` |
| `zix.Http.WebSocket.Conn` | struct | Handle per-koneksi `{ stream, io }` |
| `zix.Http.WebSocket.RoomMap` | struct | Registri room bernama: init / join / leave / broadcast / deinit |
| `zix.Http.WebSocket.parseFrame` | fn | Parse satu frame dari buffer byte, mengembalikan `?ParseResult` |
| `zix.Http.WebSocket.buildFrame` | fn | Serialisasi frame server-ke-client (tanpa mask) |
| `zix.Http.WebSocket.acceptKey` | fn | Hitung `Sec-WebSocket-Accept` dari `Sec-WebSocket-Key` |
| `zix.Http.WebSocket.upgrade` | fn | Tulis `101 Switching Protocols` ke `ctx.stream` |
| `zix.Http.WebSocket.serveTls` | fn | WebSocket melalui TLS (wss): `101` terenkripsi + inline frame loop engine-driven (ADR-055) |
| `zix.Http.WebSocket.send` | fn | Kirim satu server frame, ter-coalesce sink (dipakai dari callback `on_frame` melalui TLS) |
| `zix.utils.file.save` | fn | Tulis bytes ke `dir/filename`, membuat direktori bila belum ada |
| `zix.Tcp.Http.Method.Code` | enum | GET HEAD POST PUT DELETE PATCH OPTIONS TRACE CONNECT QUERY (RFC 10008) |
| `zix.Tcp.Http.Status.Code` | enum | Status code HTTP lengkap 1xx--5xx |

---

## HttpServerConfig

```zig
pub const HttpServerConfig = struct {
    io:                   std.Io,                         // backend io dari pemanggil, wajib, harus outlive server
    ip:                   []const u8,
    port:                 u16,
    dispatch_model:       DispatchModel,    // required: ASYNC, EPOLL, or URING (EPOLL/URING Linux-only)
    kernel_backlog:   u31               = 1024,     // TCP listen() backlog
    max_recv_buf:   usize             = 6 * 1024,  // read buffer per connection
    large_body_rcvbuf:    usize             = 0,          // SO_RCVBUF pada jalur large-body/upload, 0 = default kernel
    max_request_body:     usize             = 8 * 1024 * 1024, // batas body request, body() menolak melewatinya dengan 413 (0 = tanpa cek Content-Length)
    compress:             bool              = false,      // negosiasi gzip / deflate / brotli, opt-in via resp.sendNegotiated (semua model)
    compression_min_size: usize             = 256,        // lewati body di bawah floor ini
    compression_max_out:  usize             = 256 * 1024, // cap output terkompresi codec-agnostic
    max_allocator_size:   usize             = 1024 * 4,  // per-connection arena backing size
    max_request_headers:  RequestHeaderSize = .LARGE,    // request header cap, requests exceeding -> 431
    max_response_headers: HeaderSize        = .MINIMAL,  // custom response header cap, arena-allocated per request
    public_dir:           []const u8        = "",         // static file root, "" disables static serving
    public_dir_upload:    []const u8        = "u",        // upload subdir under public_dir
    public_dir_cache_ttl_ms:      u32       = 0,          // 0 = tidak pernah di-cache, default bawaan
    public_dir_cache_max_entries: u32       = 256,        // slot static cache, satu per file
    conn_timeout_ms:      u32               = 0,          // Layer D: connection guard. 0 = disabled, .ASYNC only
    handler_timeout_ms:   u32               = 0,          // Layer B: handler budget. 0 = disabled; ctx.isExpired() / ctx.timedOut()
    workers:              usize             = 0,          // 0 = cpu_count worker untuk .EPOLL / .URING, diabaikan oleh .ASYNC
    tls:                  ?*zix.Tls.Context = null,       // non-null melayani engine ini lewat TLS (https native), jika tidak cleartext
    tls_port:             u16               = 0,          // port pendamping dual-listener, 0 = single-listener; lihat docs/hld-tls-id.md
    logger:               ?*zix.Logger      = null,       // access logger. null = no HTTP access logging
};
```

Listing di atas diringkas: referensi field lengkap (compression, response cache, uring tuning, REUSEPORT steering) ada di [`docs/zix-config-id.md`](zix-config-id.md).

Pemanggil memiliki `io`: `zix.Http.Server` tidak memanggil `deinit` padanya. Tabel route dioper sebagai argumen comptime ke `Server.init` sehingga tidak ada alokasi runtime untuk routing.

Untuk panduan pemilihan batas header dan keamanan, lihat [`docs/headers-id.md`](headers-id.md).

---

## Siklus Hidup Koneksi

`.ASYNC` (task io.async() menangani koneksi):

```mermaid
sequenceDiagram
    participant Client
    participant Accept as Accept loop
    participant Sched as io Threaded pool
    participant Task as connection task
    participant Router
    participant Handler as HandlerFn
    participant Static as static.serve()

    Client->>Accept: TCP connect
    Accept->>Sched: io.async(connEntry, ...)
    Note over Accept: immediately back to accept()

    Sched->>Task: schedule the connection
    Task->>Task: alloc read_buf
    Task->>Task: ArenaAllocator init

    loop keep-alive
        Client->>Task: HTTP request
        Task->>Task: recv sampai terminator header
        Task->>Task: build Request + Response + Context
        Task->>Router: dispatch(req, res, ctx)

        alt route matched
            Router->>Handler: handler(req, res, ctx)
            Handler->>Client: HTTP response
        else no route
            Router->>Static: serve(req_path, public_dir)
            alt file found
                Static->>Client: 200 or 206 response
            else file not found
                Static->>Client: 404 Not Found
            end
        end

        Task->>Task: arena.reset()
    end

    Client->>Task: connection close
    Task->>Task: free read_buf + write_buf, arena.deinit()
```

---

## Request

View zero-copy atas head request yang sudah di-parse dan fd koneksi, tempat `body()` membaca.

| Method | Mengembalikan | Catatan |
| :- | :- | :- |
| `method()` | `Method.Code` | Diselesaikan oleh request-line parser milik engine ini sendiri. Method yang tidak diimplementasikan tidak pernah sampai ke handler: parse melaporkan `error.ZixUnknownMethod` dan caller menjawab 501 |
| `path()` | `[]const u8` | Target tanpa query string |
| `query()` | `[]const u8` | Raw query string setelah `?` |
| `queryParam(key)` | `?[]const u8` | Satu key dari query string |
| `queryParams(allocator)` | `![]QueryParam` | Semua query param. Key tanpa nilai memiliki `value = null` |
| `pathSegments(allocator)` | `![][]const u8` | Segmen tidak kosong yang dipisahkan oleh `/` |
| `pathParam(name)` | `?[]const u8` | Capture bernama dari param route. null bila tidak ditangkap |
| `header(name)` | `?[]const u8` | Pencarian case-insensitive. Indeks O(1) dibangun pada pemanggilan pertama |
| `body()` | `![]const u8` | Membaca body: bytes `Content-Length` atau chunked transfer yang sudah di-decode, dibatasi `max_request_body` (`error.ZixRequestBodyTooLarge` dijawab `413`, chunked malformed `error.ZixInvalidChunkedBody` dijawab `400`). Di-cache setelah pemanggilan pertama. |
| `bodyReceived()` | `u64` | Byte body yang benar-benar dikonsumsi pembacaan, bukan yang diklaim header |
| `bodyComplete()` | `bool` | Apakah akhir body yang dideklarasikan atau ter-framing tercapai. False berarti peer memutus body, atau handler tidak pernah membacanya |

---

## Method QUERY (RFC 10008)

QUERY bersifat safe dan idempotent seperti `GET`, dan membawa content seperti `POST`. Ia ada untuk pertanyaan yang terlalu besar atau terlalu terstruktur untuk muat di query string URL.

Request-line parser engine ini menerimanya dan `req.method()` mengembalikan `.QUERY`. Selebihnya persis sama dengan `zix.Http1`, jadi sebuah handler berperilaku sama di kedua engine. Lihat bagian QUERY di HLD `zix.Http1` untuk peta kebutuhan lengkap, tabel status (400 / 415 / 422 / 406), dan content type yang ada di tabel.

Dua hal khusus engine ini:

| Hal | Rincian |
| :- | :- |
| Token method dicocokkan persis | RFC 9110 section 9.1 menetapkan nama method case-sensitive. Kedua engine HTTP/1 membaca tabel yang sama (`Method.codeFromString`), jadi `query` huruf kecil bukan method QUERY di keduanya: ia menamai method yang tidak diimplementasikan kedua engine (501) |
| Response QUERY tidak pernah di-cache | `sendCached` jatuh ke pengiriman biasa untuk QUERY, karena request key-nya `hash(method, path, query)` dan tidak membawa content (RFC 10008 section 2.7) |

---

## Response

Menyangga status response dan menulis saat `send()` atau padanannya dipanggil.

| Method | Catatan |
| :- | :- |
| `setStatus(Status.Code)` | Default: `.OK` |
| `setContentType(Content.Type)` | Header opt-in, tidak dikirim kecuali diset secara eksplisit |
| `setKeepAlive(bool)` | Header opt-in, tidak dikirim kecuali diset secara eksplisit |
| `addHeader(name, value)` | Hingga `max_response_headers` header tambahan. CR/LF ditolak |
| `send(body)` | Menulis response HTTP/1.1 penuh dan flush |
| `sendJson(body)` | Menetapkan `content_type = application/json`, lalu memanggil `send` |
| `sendText(body)` | Menetapkan `content_type = text/plain`, lalu memanggil `send` |
| `sendRaw(bytes)` | Menulis byte wire milik caller apa adanya, tanpa serialisasi |
| `sendNoContent()` | Menetapkan status `.NO_CONTENT`, mengirim body kosong |
| `sendStream()` | Mengirim header SSE (tanpa `Content-Length`), mengembalikan `SseWriter`. Menetapkan `streaming = true` sehingga loop keep-alive keluar setelah handler kembali |
| `sendFromCache(req)` | `true` saat fresh cache hit (sudah ditulis), jika tidak `false` |
| `sendCached(req, body, ttl_ms)` | Mengirim `body`, lalu menyimpannya di bawah kunci request untuk hit `sendFromCache` berikutnya |
| `sendNegotiated(req, body)` | Mengirim `body` terkompresi sesuai `Accept-Encoding` (opt-in lewat `setCompression`), jika tidak identik dengan `send` |

Response ditulis ke `std.Io.Writer` yang mendasarinya. Buffer header 4 KB membatasi ukuran header gabungan. `error.ZixBufferTooSmall` dikembalikan jika terlampaui.

### Header otomatis yang dikirim oleh send()

`send()` selalu mengirim `Content-Length` dan `Date`. `Content-Type` dan `Connection` hanya dikirim bila handler menetapkannya secara eksplisit:

| Header | Nilai | Dikirim? |
| :- | :- | :- |
| `Content-Type` | dari `setContentType()` | hanya bila `setContentType()` dipanggil (dilewati untuk 204) |
| `Content-Length` | `body.len` | selalu (dilewati untuk 204 No Content sesuai RFC 7230) |
| `Connection` | `keep-alive` atau `close` | hanya bila `setKeepAlive()` dipanggil |
| `Date` | timestamp UTC RFC 7231 | selalu |

**Logika `Connection`** (dikirim hanya bila handler memanggil `setKeepAlive()`):
- Tidak dikirim sama sekali bila `setKeepAlive()` tidak pernah dipanggil.
- `keep-alive` bila `setKeepAlive(true)` dipanggil **dan** `req.head.keep_alive` (di-parse dari header request `Connection` client) bernilai true.
- `close` bila handler memanggil `setKeepAlive(false)` **atau** client mengirim `Connection: close`.

**Logika `Date`** (lintas platform, sadar proxy):
1. `server.zig` memindai header request satu kali sebelum dispatch untuk nilai `Date` yang diteruskan proxy. Bila ditemukan, disimpan di `res.date_cache`.
2. Bila tidak ada, `res.date_cache` diisi dari cache date atomik global (diperbarui oleh background timer thread setiap 500 ms). Satu atomic load per request, tanpa syscall clock.
3. `send()` membaca `res.date_cache` langsung tanpa pemindaian header saat pengiriman.
4. Format IMF-fixdate: `Thu, 08 May 2026 12:34:56 GMT`.

### Kebijakan error handler

Handler mengembalikan `anyerror!void`. Saat handler mengembalikan error, engine yang menyelesaikan response, tetapi hanya bila handler belum menulis apa pun (`Response.sent`), sehingga response yang terkirim sebagian tidak pernah rusak:

| Kondisi | Yang dikirim engine sebagai penutup |
| :- | :- |
| `req.body_too_large`: body chunked melewati `max_request_body` | `413`, `text/plain`, body `Payload Too Large` |
| `req.body_malformed`: framing chunk tidak bisa di-parse | `400`, `text/plain`, body `Bad Request` |
| error lainnya | `500`, `text/plain`, body `Internal Server Error` |

Dua yang pertama adalah kesalahan client, jadi tidak menjadi `500`. Hanya body chunked yang sampai ke cabang itu: `Content-Length` yang dideklarasikan melewati batas ditolak sebelum handler berjalan.

Dua konsekuensi yang perlu diketahui:

- `send()` yang gagal tidak pernah menghasilkan `500`. `send()` menandai response sebagai terkirim sebelum menulis ke socket, jadi `try res.send(...)` yang gagal sampai ke engine dengan `Response.sent` sudah true. Error dibuang dan koneksi mati pada read atau write berikutnya, satu-satunya penanganan yang tersisa: socket yang baru saja menolak write juga tidak bisa membawa `500`.
- Error yang ditangkap sendiri oleh handler tidak pernah sampai ke engine, jadi handler itu yang menentukan apa yang diterima client. `try res.send(...)` memakai tabel di atas, `res.send(...) catch { ... }` menjawab dengan caranya sendiri. Engine ini tidak mengekspos fd writer, jadi `Response.sent` sudah mewakili seluruhnya di sini, berbeda dari `zix.Http1` dan `zix.Http2` yang jawaban lewat fd-nya ikut dihitung.
- Penulisan penutup itu best effort. Saat gagal, tidak ada percobaan kedua dan tidak ada baris log dari jalur itu.

---

## Routing

### Registrasi: tabel route comptime

Route dioper saat kompilasi sebagai argumen kedua ke `Server.init`. Setiap `Route` memiliki `path`, sebuah `handler`, dan `kind` opsional (`RouteKind = .EXACT` sebagai default):

| `kind` | Contoh pola | Perilaku |
| :- | :- | :- |
| `.EXACT` (default) | `"/about"` | Cocok hanya bila path penuh sama dengan `path` |
| `.PREFIX` | `"/api"` | Cocok dengan `path` dan sub-path apapun, BUKAN segmen parsial |
| `.PARAM` | `"/users/:id"` | Segmen `:name` ditangkap, literal harus cocok persis |

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/about",           .handler = aboutHandler },
    .{ .path = "/api",             .handler = apiHandler,    .kind = .PREFIX },
    .{ .path = "/users/:id",       .handler = userHandler,   .kind = .PARAM },
    .{ .path = "/:tenant/:branch", .handler = branchHandler, .kind = .PARAM },
}).dispatch, .{ .ip = "127.0.0.1", .port = 9000 });
```

Handler mengakses segmen yang ditangkap melalui `req.pathParam("id")`. Sub-path prefix dibaca melalui `req.path()["/api".len..]`.

### Dispatch: aturan prioritas

```
Pass 1: exact routes   pencarian hash map O(1)          (urutan registrasi tidak relevan)
Pass 2: param routes   pola pertama yang cocok menang   (urutan registrasi penting)
Pass 3: prefix routes  prefix terpanjang yang cocok menang  (urutan registrasi tidak relevan)

exact > param > prefix (prefix lebih panjang mengalahkan prefix lebih pendek)
```

Pass 1 dan 3 bersifat deterministik terlepas dari urutan registrasi. **Pass 2 adalah pengecualian**: bila dua pola param memiliki jumlah segmen yang sama dan keduanya cocok, yang terdaftar pertama menang. Daftarkan pola yang lebih literal sebelum pola all-param dengan kedalaman yang sama.

```mermaid
flowchart TD
    A["dispatch(req, res, ctx)"] --> B["Pass 1: exact_map.get(path) O(1)"]
    B --> C{"exact match?"}
    C -->|yes| DONE["call handler, return true"]
    C -->|no| D["Pass 2: scan param routes\nin registration order"]
    D --> E{"pattern matches?"}
    E -->|yes| F["write path_params to req"]
    F --> DONE
    E -->|no| G["Pass 3: scan prefix routes\ncollect all that match"]
    G --> H{"any prefix matched?"}
    H -->|no| Z["return false"]
    H -->|yes| I["pick longest prefix"]
    I --> DONE
```

### Tabel prioritas

| Route yang terdaftar | Request | Pemenang | Alasan |
| :- | :- | :- | :- |
| `/path/info` (exact) + `/path/:id` (param) | `/path/info` | `/path/info` | exact mengalahkan semua |
| `/path/:id` (param) + `/path` (prefix) | `/path/alice` | `/path/:id` | param mengalahkan prefix |
| `/api/v2` (prefix) + `/api` (prefix) | `/api/v2/foo` | `/api/v2` | prefix lebih panjang menang |
| `/path` (prefix) | `/pathfoo` | tidak ada cocok | karakter berikutnya harus `/` atau akhir string |
| `/path/user/:id` (reg. ke-1) + `/path/:a/:b` (reg. ke-2) | `/path/user/alice` | `/path/user/:id` | lebih banyak literal terdaftar pertama |
| `/path/:a/:b` (reg. ke-1) + `/path/user/:id` (reg. ke-2) | `/path/user/alice` | `/path/:a/:b` | urutan salah, all-param menang secara tak terduga |

### Pencocokan mirip regex

zix tidak memiliki regex engine. Gunakan `kind = .PREFIX` untuk mencocokkan prefix path. Penyaringan tambahan dilakukan di dalam handler pada `req.path()`.

| Maksud regex | Padanan zix |
| :- | :- |
| `/secret/(.*)` | Route `.PREFIX` pada `"/secret"`, sub-path via `req.path()["/secret".len..]` |
| `/files/.*\.pdf` | Route `.PREFIX` pada `"/files"`, periksa `std.mem.endsWith(u8, sub, ".pdf")` di handler |
| `/v[0-9]+/.*` | Route `.PREFIX` pada `"/v"`, parse segmen berikutnya dengan `std.fmt.parseInt` |

---

## Berkas Statis

Ada dua jalur di balik satu entry point (ADR-064). Jalur cache dicoba lebih dulu dan memiliki
request begitu file-nya resolve. Jalur ini tidak aktif kecuali `public_dir_cache_ttl_ms` diatur,
jadi konfigurasi default menjalankan jalur open-stat-copy yang lama tanpa perubahan.

```mermaid
flowchart TD
    A["static.serve(req, fd, path, public_dir, io)"] --> B{"static cache installed?"}
    B -->|no| N["uncached path"]
    B -->|yes| C["negotiate encoding, ask the cache"]
    C --> D{"cache hit?"}
    D -->|no| N
    D -->|yes| E{"Range header present?"}
    E -->|yes| F["render 206 header, send the range"]
    E -->|no| G["replay the prerendered 200 header"]
    F --> S["send body: sendfile in cleartext, copy under TLS"]
    G --> S
    S --> H["return true"]
    N --> I{"path contains '..'?"}
    I -->|yes| Z["return false, traversal rejected"]
    I -->|no| J{"file exists?"}
    J -->|no| Z
    J -->|yes| K["200 or 206, stream in 8 KiB chunks"]
    K --> H
```

- Bila `public_dir` tidak kosong, `Http.Server.run()` memvalidasi direktori saat startup, dan
  memasang static cache bersama ketika `public_dir_cache_ttl_ms` di atas 0.
- Directory traversal (`..`) ditolak di kedua jalur.
- Tipe MIME diselesaikan dari ekstensi berkas melalui `zix.Http.Content.typeFromExtension`.
- Header `Range` didukung di kedua jalur: `206 Partial Content` (RFC 7233), `416` bila tidak terpenuhi.
- Jalur cache mengirim `Vary: Accept-Encoding` karena ia melakukan negosiasi. Jalur tanpa cache tidak
  bernegosiasi, jadi ia tidak mengklaim vary.
- Cache dipakai bersama oleh semua worker dan semua engine HTTP dalam satu proses, jadi satu file
  memakai satu descriptor untuk proses, bukan satu per worker. Lihat `docs/zix-config-id.md`.

---

## Upload

`zix.utils.multipart.Parser` mem-parse body `multipart/form-data` menjadi field (juga tersedia sebagai alias `zix.Http.Multipart`). `zix.utils.file.save` menulis bytes ke disk. Keduanya tidak dihubungkan ke server secara otomatis (handler memanggilnya langsung).

```zig
var parser = zix.utils.multipart.Parser.init(ctx.allocator, boundary);
defer parser.deinit();
try parser.parse(try req.body());

if (parser.getField("file")) |f| {
    const filename = f.filename orelse "upload";
    const path = try zix.utils.file.save(ctx.io, ctx.allocator, "./public/u", filename, f.data);
    _ = path; // arena-allocated, valid for this request
}
```

---

## Serving Berkas dengan Kontrol Akses

Periksa keberadaan berkas sebelum param agar persyaratan autentikasi tidak terungkap untuk path yang tidak ada.

```mermaid
flowchart TD
    A["GET /secret/<file>"] --> B{"file exists?"}
    B -->|no| C["404 Not Found"]
    B -->|yes| D{"sec param present and correct?"}
    D -->|no| E["403 Forbidden"]
    D -->|yes| F["200 with MIME type"]
```

| Request | Berkas ada | sec=abc123 | Response |
| :- | :- | :- | :- |
| `/secret/file.txt?sec=abc123` | ya | ya | 200 |
| `/secret/file.txt` | ya | tidak | 403 |
| `/secret/missing.txt?sec=abc123` | tidak | n/a | 404 |

---

## WebSocket

Broadcast berbasis room mengikuti RFC 6455, diimplementasikan di atas TCP stream mentah yang sudah dipegang server HTTP.

```mermaid
sequenceDiagram
    participant C as Client
    participant H as wsHandler task
    participant R as RoomMap

    C->>H: GET /ws/:room-id (Upgrade: websocket)
    H->>H: acceptKey(Sec-WebSocket-Key)
    H->>C: 101 Switching Protocols
    H->>R: join(room-id, conn)

    loop frame loop
        C->>H: WS frame (text/binary/ping/close)
        alt text or binary
            H->>R: broadcast(room-id, "[name] payload")
            R->>C: frame to all room members
        else ping
            H->>C: pong frame
        else close (peer-initiated)
            H->>C: echo close frame
        else EOF or RST or error
            H->>C: best-effort close frame
        end
    end

    H->>R: leave(room-id, conn)
```

### Context.stream

`ctx.stream` adalah `std.Io.net.Stream` mentah untuk koneksi TCP yang aktif. Server selalu menetapkannya sebelum memanggil handler apapun.

- **HTTP handler**: menerima `ctx.stream` yang valid dan tidak boleh menggunakannya.
- **WebSocket handler**: menggunakan `ctx.stream` setelah `zix.Http.WebSocket.upgrade()` menyerahkan koneksi.

### Context.isExpired / timedOut: anggaran eksekusi handler (Layer B)

Bila `config.handler_timeout_ms > 0`, server menetapkan `ctx.deadline` sebelum setiap dispatch handler. Handler opt-in dengan memanggil `ctx.isExpired()` di antara langkah-langkah yang mahal dan mengembalikan 408 lebih awal alih-alih memblokir pool thread. `ctx.timedOut()` adalah alias dari `ctx.isExpired()`.

```zig
pub fn slowHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req;

    doStep1(ctx.io); // e.g. DB query, external call
    if (ctx.isExpired()) {
        res.setStatus(.REQUEST_TIMEOUT);
        return res.sendJson("{\"error\":\"timeout\"}");
    }

    doStep2(ctx.io);
    if (ctx.isExpired()) {
        res.setStatus(.REQUEST_TIMEOUT);
        return res.sendJson("{\"error\":\"timeout\"}");
    }

    try res.sendJson("{\"result\":\"ok\"}");
}
```

`ctx.isExpired()` selalu aman dipanggil: mengembalikan `false` bila `deadline` null (yaitu `handler_timeout_ms == 0`). Pemeriksaan adalah satu kali baca dan bandingkan clock, tanpa syscall bila deadline belum terlampaui.

`ctx.setTimeout(ms)` mengubah `ctx.deadline` di tempat menjadi `now + ms`. Gunakan ini di dalam handler untuk menimpa anggaran global server dengan jendela yang lebih pendek atau lebih panjang:

```zig
ctx.setTimeout(2_000); // this handler caps itself to 2s regardless of global budget
```

`ctx.withTimeout(ms)` dan `ctx.withDeadline(ts)` mengembalikan salinan ctx yang dimodifikasi dengan deadline baru (non-mutating, untuk pola sub-anggaran tanpa mengubah deadline penerima).

Untuk connection guard level jaringan (Layer D, `conn_timeout_ms`) lihat ADR-018.

### Pola handler

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/ws/:room-id", .handler = wsHandler, .kind = .PARAM },
}).dispatch, .{ .io = process.io, .ip = "127.0.0.1", .port = 9000, .dispatch_model = .ASYNC });

pub fn wsHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    const room_id = req.pathParam("room-id") orelse return;
    const display_name = req.queryParam("name") orelse "anonymous";

    // extract Sec-WebSocket-Key before upgrade
    var ws_key: ?[]const u8 = null;
    var it = req.inner.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "sec-websocket-key")) ws_key = h.value;
    }

    var accept_buf: [64]u8 = undefined;
    const accept = try zix.Http.WebSocket.acceptKey(ws_key.?, &accept_buf);
    try zix.Http.WebSocket.upgrade(ctx.stream, ctx.io, accept);

    const conn = try std.heap.smp_allocator.create(zix.Http.WebSocket.Conn);
    conn.* = .{ .stream = ctx.stream, .io = ctx.io };
    defer std.heap.smp_allocator.destroy(conn);
    ws_rooms.join(room_id, conn, ctx.io);
    defer ws_rooms.leave(room_id, conn, ctx.io);

    _ = display_name; // used in frame loop broadcast prefix
    // frame loop: read, dispatch, compact buffer ...
}
```

### Siklus hidup RoomMap

| Panggilan | Kapan |
| :- | :- |
| `RoomMap.init(smp_allocator)` | satu kali di `main()` sebelum `server.run()` |
| `join(room, conn, io)` | awal setiap WS handler |
| `leave(room, conn, io)` | di-defer segera setelah join |
| `broadcast(room, msg, io)` | setiap frame text/binary |
| `RoomMap.deinit()` | proses shutdown |

---

## SSE (Server-Sent Events)

Push server satu arah melalui HTTP/1.1. Client menggunakan API `EventSource` browser atau `curl -N`. Tidak diperlukan handshake upgrade.

```mermaid
sequenceDiagram
    participant C as Client (EventSource)
    participant H as Handler task

    C->>H: GET /events
    H->>C: HTTP/1.1 200 OK\nContent-Type: text/event-stream\n...
    loop event loop
        H->>C: data: tick 0\n\n
        H->>C: data: tick 1\n\n
    end
    H->>H: handler returns
    H->>C: TCP close
    C->>C: auto-reconnect after retry ms
```

### res.sendStream()

`res.sendStream()` (di-rename dari `stream()`, ADR-062) mengirim header response SSE (tanpa `Content-Length`) dan mengembalikan `SseWriter`. Koneksi tetap terbuka selama handler menulis event. Saat handler kembali, `handleConnection` melihat `res.streaming == true` dan menutup koneksi alih-alih mengulang untuk request berikutnya.

| Method `SseWriter` | Format wire |
| :- | :- |
| `writeEvent(data)` | `data: <data>\n\n` |
| `writeNamedEvent(event, data)` | `event: <event>\ndata: <data>\n\n` |
| `comment(text)` | `: <text>\n` |

### Persyaratan konkurensi

Koneksi SSE berumur panjang. Event loop `.EPOLL` dan `.URING` akan menahan satu worker selama durasi penuh stream. `.ASYNC` lebih disarankan: setiap koneksi berjalan sebagai task konkuren melalui `io.async()`, jadi satu stream terbuka hanya memakai satu task, bukan slot worker.

### Pola handler

```zig
pub fn eventsHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req;
    const sse = try res.sendStream();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var buf: [32]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "tick {d}", .{i}) catch break;
        sse.writeEvent(msg) catch break;
        std.Io.sleep(ctx.io, std.Io.Duration.fromMilliseconds(1000), .awake) catch break;
    }
}
```

Lihat `examples/http_sse.zig`.

---

## Middleware

Disusun saat comptime menggunakan fungsi wrapper. Tidak ada alokasi heap, tidak ada runtime chain runner.

```zig
fn withOriginCheck(comptime next: zix.Http.HandlerFn) zix.Http.HandlerFn {
    return struct {
        fn handle(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
            const origin = req.header("origin") orelse "";
            if (!isAllowedOrigin(origin)) {
                res.setStatus(.FORBIDDEN);
                try res.sendJson("{\"error\":\"forbidden origin\"}");
                return;
            }
            return next(req, res, ctx);
        }
    }.handle;
}
```

Susun dari kiri ke kanan: wrapper paling luar berjalan pertama. Route didaftarkan saat kompilasi melalui `Server.init`:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/public",  .handler = withOriginCheck(publicHandler) },
    .{ .path = "/private", .handler = withOriginCheck(withBasicAuth(privateHandler)) },
}).dispatch, .{ .io = process.io, .ip = "127.0.0.1", .port = 9000 });
```

Setiap nilai `next` yang unik menghasilkan fungsi tersendiri saat comptime. Lihat `examples/http_middleware.zig`.

---

## Model Memori

```mermaid
graph TD
    COMPTIME["comptime route table\nzero heap cost"] -->|Router dispatch| ROUTER["Router(routes)\ncomptime zero-size type"]
    SMP["std.heap.smp_allocator"] -->|per connection| RB["read_buf + write_buf\nfreed on close"]
    SMP -->|per connection| Arena["ArenaAllocator\nreset per request\ndeinit on close"]
    Arena -->|per request| REQ["body_cache\nResponse buffers\nhandler allocations\nextra_buf ([]HttpHeader)"]
    SMP -->|WebSocket| WS["Conn + room list entries\nWS session lifetime"]
```

| Cakupan | Allocator | Masa hidup | Cocok untuk Arena? |
| :- | :- | :- | :- |
| Tabel route | comptime (tanpa biaya heap) | Proses | n/a: konstanta comptime, tidak ada alokasi |
| Buffer I/O baca/tulis | `smp_allocator` | Koneksi | Tidak: dibebaskan secara individual saat koneksi ditutup |
| Alokasi per-request | `ArenaAllocator` per-koneksi yang direset setiap request | Request | Ya: sudah by design |
| `Conn` WebSocket + entri room | `smp_allocator` | Sesi WS | Tidak: dibebaskan secara individual saat sesi berakhir |

---

## Http Client

`zix.Http.Client` membungkus `std.http.Client` dengan konfigurasi eksplisit, error yang dinamai, dan `ClientResponse` yang dimiliki pemanggil.

### HttpClientConfig

```zig
pub const HttpClientConfig = struct {
    allocator:           std.mem.Allocator, // owns response body + head copies
    io:                  std.Io,            // event-loop backend, not owned by client
    connect_timeout_ms:  u32 = 0,          // 0 = no timeout. enforced via connectTcpOptions
    response_timeout_ms: u32 = 0,          // 0 = no timeout. error.ZixResponseTimeout when the head never arrives
    read_timeout_ms:     u32 = 0,          // 0 = no timeout. error.ZixReadTimeout when the body stalls (Content-Length only)
    max_response_body:   usize = 1024 * 1024 * 4, // error.ZixBodyTooLarge when exceeded
    follow_redirects:    bool = true,
    max_redirects:       u8   = 3,
    h2_max_read_rounds:  usize = 4096,                       // bound read-loop client HTTP/2, max frame-read rounds
    user_agent:          []const u8 = zon_options.user_agent, // library version string (e.g. "zix/0.5.0"); "" omits
    version:             Version = .HTTP_1,                  // .HTTP_1 (std client) atau .HTTP_2 (h2 over TLS 1.3, https saja)
    tls_ca_path:         ?[]const u8 = null,                 // CA PEM tambahan untuk https. null = system roots
    tls_verify:          bool = true,                        // verifikasi chain cert server + hostname pada https
};
```

### Siklus hidup request

```mermaid
sequenceDiagram
    participant Caller
    participant Client as HttpClient
    participant Std as std.http.Client
    participant Server as HTTP server

    Caller->>Client: client.get(url, opts)
    Client->>Client: Uri.parse(url)
    Client->>Client: Protocol.fromUri(uri)
    Client->>Std: connectTcpOptions(host, port, .{ timeout })
    Std->>Server: TCP connect
    Client->>Std: request(method, uri, .{ connection, redirect_behavior, headers })
    Client->>Std: sendBodiless() or sendBodyUnflushed() + end()
    Std->>Server: HTTP request
    Server->>Std: HTTP response head + body
    Client->>Client: receiveHead(redirect_buf)
    Client->>Client: gpa.dupe(head.bytes)
    Client->>Client: response.reader().allocRemaining(gpa, .limited(max_response_body))
    Client->>Caller: ClientResponse{ status_code, head_bytes, body_data }
```

### Error yang dinamai

| Error | Kapan |
| :- | :- |
| `error.ZixUrlMalformed` | `Uri.parse` gagal |
| `error.ZixUrlSchemeUnsupported` | skemanya bukan http maupun https |
| `error.ZixUrlHostMissing` | komponen host-nya tidak ada |
| `error.ZixUrlPathTooLong` | path dan query-nya tidak muat di buffer request |
| `error.ZixBodyTooLarge` | body response melebihi `max_response_body` bytes |
| `error.Timeout` | koneksi TCP melebihi `connect_timeout_ms` (dari `std.Io`) |
| `error.ZixResponseTimeout` | server menerima koneksi tapi tidak mengirim head response dalam `response_timeout_ms` |
| `error.ZixReadTimeout` | body macet melewati `read_timeout_ms` di tengah transfer (hanya body Content-Length) |

Error lain dari `std.http.Client` diteruskan tanpa perubahan (OutOfMemory, ConnectionRefused, dll.).

### Memori ClientResponse

`ClientResponse` memiliki dua alokasi heap, keduanya menggunakan `config.allocator`:

| Field | Sumber | Perlu dibebaskan? |
| :- | :- | :- |
| `head_bytes: []u8` | `gpa.dupe(response.head.bytes)` | Ya, melalui `deinit()` |
| `body_data: []u8` | `body_reader.allocRemaining(gpa, ...)` | Ya bila len > 0, melalui `deinit()` |

Panggil `resp.deinit()` untuk melepas keduanya. Setelah `deinit()`, semua slice yang dikembalikan oleh `status()`, `header()`, `body()` tidak lagi valid.

### Penanganan redirect

- `follow_redirects: true` (default): `std.http.Client` mengikuti hingga `max_redirects` hop secara otomatis. Setiap hop membuka koneksi baru.
- `follow_redirects: false`: `ClientResponse` membawa response 3xx langsung (pemanggil membaca `header("location")`).
- Method yang membawa body (POST, PUT, PATCH) yang menerima redirect mengembalikan `error.RedirectRequiresResend` (perilaku std).

### Fitur yang ditangguhkan

| Fitur | Status |
| :- | :- |
| TLS / HTTPS (client) | https via `version = .HTTP_2` (h2 over TLS 1.3, `h2_client.zig`), mempercayai cert server lewat `tls_ca_path` / `tls_verify`. Jalur client HTTP/1 bersifat cleartext |
| Reuse koneksi keep-alive pool | diwarisi dari pool `std.http.Client` (aktif secara default) |

---

## Belum Diimplementasikan

| Fitur | Lokasi | Catatan |
| :- | :- | :- |
| Chain runner middleware | dihapus (ADR-062) | Komposisi wrapper comptime adalah idiom middleware, lihat `examples/http_middleware.zig` |

TLS untuk server ini (https native, opt-in lewat `config.tls`, dual listener lewat `config.tls_port`) sudah diimplementasikan, lihat [`docs/hld-tls-id.md`](hld-tls-id.md).

Untuk desain UDP lihat [`docs/hld-udp-id.md`](hld-udp-id.md). Untuk UDS lihat [`docs/hld-uds-id.md`](hld-uds-id.md).

---

###### end of hld-http
