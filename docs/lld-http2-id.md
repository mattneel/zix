# LLD: zix.Http2 (h2c HTTP/2)

Detail implementasi internal. Untuk rasional desain lihat [`docs/hld-http2-id.md`](hld-http2-id.md), ADR-043 (split `dispatch/` per-engine), dan ADR-052 (TLS multiplex).

Model blocking (`.ASYNC`) memakai satu jalur koneksi (`core.serveConn` -> `serveH2cLoop`). Model `.EPOLL` dan `.URING` menggerakkan state machine terpisah, resumable, non-blocking (`mux.zig`) yang menjadi fokus utama dokumen ini. Keduanya bermuara ke satu `Router` comptime. Jalur TLS (`config.tls != null`) terminasi di tempat, baik secara multiplex (`tls_mux.zig`, untuk `.EPOLL` / `.URING`) atau thread-per-connection (`tls_serve.zig`, yang juga melayani TLS 1.2).

---

## mux.zig

State machine h2c resumable untuk `.EPOLL` / `.URING`. Satu `MuxConn` per fd. read accumulator `rbuf` persisten lintas event readable dan menyimpan frame parsial sampai sisanya tiba, sehingga satu worker menggerakkan banyak koneksi. Frame koneksi dan respons ditulis langsung ke fd via helper `frame.*` (yang poll saat EAGAIN untuk socket non-blocking), dan handler berjalan inline pada worker, jadi seperti mux gRPC ia harus tetap bounded.

### MuxStream

Satu stream dalam satu koneksi, dipinjam dari pool per-worker selama terbuka.

```zig
const MuxStream = struct {
    id: u31 = 0,
    state: StreamState = .IDLE,                          // IDLE | OPEN | HALF_CLOSED_REMOTE | CLOSED
    headers: [frame.MAX_HEADERS]hpack.Header = undefined,// inline, MAX_HEADERS = 64
    header_count: usize = 0,
    header_scratch: []u8 = &.{},                         // buffer dari pool, berukuran opts.max_header_scratch
    body: []u8 = &.{},                                   // buffer dari pool, berukuran opts.max_body
    body_len: usize = 0,
    end_headers: bool = false,
    end_stream: bool = false,

    send_window: i64 = 65535,          // sisa receive window peer untuk stream ini (RFC 7540 6.9)
    pending_body: []const u8 = &.{},   // ekor body belum terkirim karena dibatasi window, dilanjutkan oleh WINDOW_UPDATE
    pending_end: bool = false,

    next_free: ?*MuxStream = null,     // link freelist, valid hanya saat idle di pool
};
```

`headers` adalah array inline. `body` dan `header_scratch` adalah buffer milik stream ter-pool itu sendiri, berukuran sesuai serve options dan dipakai ulang lintas peminjaman. `pending_body` menunjuk ke memori milik pemanggil yang harus hidup lebih lama dari stream (cache statik), jadi slot tetap dipinjam sampai ia terkuras.

### MuxConn

State h2 per koneksi milik heap, satu per fd, privat bagi worker pemiliknya.

```zig
pub const MuxConn = struct {
    fd: std.posix.fd_t,
    opts: core.ServeOpts,

    rbuf: []u8,                 // read accumulator, persisten lintas event, menyimpan frame parsial
    rstart: usize,
    rend: usize,

    hpack_dec: hpack.HpackDecoder,
    streams: []*MuxStream,      // array pointer: conn idle memesan max_streams pointer, bukan buffer
    slots: []bool,

    last_stream_id: u31,
    phase: MuxPhase,            // await_preface | await_upgrade | await_preface2 | h2

    send_window: i64 = 65535,      // send window level koneksi (semua DATA kita)
    peer_init_window: i64 = 65535, // SETTINGS_INITIAL_WINDOW_SIZE peer, window per-stream awal

    pub fn init(fd, opts) ?*MuxConn   // satu alloc masing-masing untuk conn, rbuf, streams, slots; null saat OOM
    pub fn deinit(self) void          // mengembalikan stream yang masih terbuka ke pool dulu
};
```

`rbuf` berukuran `max(opts.conn_read_buf_min, opts.max_frame_size + frame.FRAME_PAYLOAD_SLACK + 9)`. Karena `streams` menyimpan pointer, state per-stream yang berat (tabel header inline plus buffer body / scratch) tidak dipesan saat koneksi dibuka, melainkan dipinjam dari pool saat stream dibuka.

### Pool stream-slot per-worker

Strategi alokasi kunci. Satu worker menggerakkan banyak koneksi dari satu thread, dan tiap koneksi meminjam satu `MuxStream` hanya selama stream terbuka, mengembalikannya saat tutup. freelist adalah threadlocal (shared-nothing per worker, tanpa atomics), sehingga memori stream residen mengikuti stream konkuren pada worker, bukan koneksi dikali `max_streams`. Buffer dialokasikan sekali per stream ter-pool dan dipakai ulang lintas peminjaman, sehingga steady state melakukan nol alokasi per-stream.

```zig
threadlocal var stream_pool: ?*MuxStream = null;

fn acquireStream(opts) ?*MuxStream  // pop freelist (sudah ter-reset bersih) atau tumbuhkan dengan stream baru + buffer
fn releaseStream(st) void           // reset skalar (st.* = .{}), pertahankan body / header_scratch, LIFO push
fn releaseSlot(conn, slot) void     // tandai slot bebas dan kembalikan stream pinjamannya ke pool
```

`acquireStream` mem-pop freelist saat tidak kosong (slot sudah dibersihkan saat release) dan mengembalikannya jika buffernya memenuhi `opts.max_body` / `opts.max_header_scratch`, selain itu ia menumbuhkan pool dengan `MuxStream` baru plus body `max_body` dan scratch `max_header_scratch`. `releaseStream` menyimpan dua buffer itu, mereset setiap skalar ke default, memulihkan buffer, dan mem-push LIFO agar stream yang hot dipakai ulang lebih dulu.

### slotFor / findSlot

`slotFor(conn, stream_id)` mengklaim slot bebas pertama, meminjam stream via `acquireStream`, men-stamp id-nya, dan mengembalikan index (null saat `max_streams` atau saat alokasi pool gagal, pemanggil lalu mengirim `RST_STREAM REFUSED_STREAM`). `findSlot(stream_id, streams, used)` mencari stream terbuka berdasarkan id. Keduanya scan linear atas `max_streams`.

### muxProcess / muxFrameLoop

`muxProcess` adalah mesin fase handshake, lalu loop frame:

- `await_preface`: butuh 3 byte. Jika bukan `"PRI"`, set `await_upgrade` dan panggil `muxHandleUpgrade`. Selain itu butuh `PREFACE` 24-byte, validasi, kirim SETTINGS server, set `h2`.
- `await_upgrade`: `muxHandleUpgrade` (akumulasi sampai `\r\n\r\n`, balas `400` tanpa `Upgrade: h2c`, `101` dengan header itu, lalu `await_preface2`, dan request stream-1 tidak dilayani).
- `await_preface2`: setelah `101`, validasi preface, kirim SETTINGS, set `h2`.
- `h2`: `muxFrameLoop`.

`muxFrameLoop` berjalan atas byte ter-buffer selama satu frame utuh tersedia:

```
loop:
    jika ter-buffer < 9 -> return .keep_alive
    fh = parseFrameHeader(rbuf[rstart..][0..9])
    jika fh.length > max_payload -> GOAWAY FRAME_SIZE_ERROR, return .close
    jika ter-buffer < 9 + fh.length -> return .keep_alive
    majukan melewati header + payload
    switch fh.frame_type:
        SETTINGS      -> lewati ACK; terapkan HEADER_TABLE_SIZE (resize + evictTo) dan
                         INITIAL_WINDOW_SIZE (geser send_window tiap stream terbuka sebesar
                         delta, RFC 7540 6.9.2); kirim ACK + satu WINDOW_UPDATE koneksi
        WINDOW_UPDATE -> stream 0: send_window += inc, resumeAll; selain itu findSlot,
                         stream.send_window += inc, resumeStream
        HEADERS       -> guard id; slotFor; reset stream; send_window = peer_init_window;
                         buang padding / priority; hpack decode ke header_scratch;
                         saat END_HEADERS + END_STREAM -> muxDispatch
        CONTINUATION  -> findSlot; append-decode; dispatch saat END
        DATA          -> findSlot; buang padding; WINDOW_UPDATE(0) + WINDOW_UPDATE(sid) untuk
                         panjang data; salin ke body, shed dengan 413 melewati max_body;
                         dispatch saat END_STREAM
        RST_STREAM    -> findSlot -> releaseSlot
        PING          -> lewati ACK; sendPingAckFD
        GOAWAY        -> return .close
        PRIORITY      -> abaikan
```

Kegagalan decode mengirim `RST_STREAM COMPRESSION_ERROR` dan membebaskan slot. `sendServerSettings` mengiklankan `MAX_CONCURRENT_STREAMS`, `INITIAL_WINDOW_SIZE` 65535, `MAX_FRAME_SIZE`, dan `ENABLE_PUSH` 0.

### muxDispatch

Mengekstrak method / path dari pseudo-header yang sudah di-decode (perbandingan ber-gate panjang: `:path` = 5, `:method` = 7), mengeset `active_conn = conn`, mencatat `tl_req_path` / `tl_req_body` hanya saat response cache terpasang, dan memanggil `core.Router(routes).dispatch`. Setelah handler kembali, slot dibebaskan kecuali body respons di-park pada window (`pending_body.len > 0`), yang dalam kasus itu `WINDOW_UPDATE` berikutnya melanjutkan dan membebaskannya.

### pumpBody / resumeStream / resumeAll / sendResponseStreamFD

Flow control sisi-kirim (`active_conn` adalah threadlocal yang mengikat send handler yang sedang berjalan kembali ke window koneksinya).

- `pumpBody(conn, stream, body, end)`: menulis DATA hingga `min(conn.send_window, stream.send_window)` dan `max_frame_size`, mengurangi kedua window per chunk, mengeset END_STREAM hanya pada chunk terakhir setelah seluruh body keluar, dan mem-park sisanya di `pending_body` / `pending_end`.
- `resumeStream(conn, slot)`: setelah window stream bertambah, mem-`pumpBody` ekor yang di-park dan membebaskan slot saat ia terkuras penuh.
- `resumeAll(conn)`: setelah window koneksi bertambah, melanjutkan setiap stream yang di-park.
- `sendResponseStreamFD(fd, sid, status, content_type, content_encoding, body)`: entry respons ber-flow-control. Tanpa `active_conn` atau tanpa slot yang cocok, ia jatuh kembali ke `frame.sendResponseEncodedFD` (langsung, tanpa meter). Selain itu ia menulis HEADERS (`sendRespHeadersFD` -> `hpack.respHeaderBlock`) lalu `pumpBody(..., true)`. Body direferensikan, tidak disalin, jadi ia harus hidup lebih lama dari stream (cache seumur-proses).

### onReadable / processRing

`onReadable` (`.EPOLL`) berulang: kompaksi `rbuf`, `read` ke `rbuf[rend..]` (WouldBlock -> `keep_alive`, 0 atau error -> `close`), lalu `muxProcess`, mengulang sampai EAGAIN. Epoll level-triggered memicu ulang bila ada lagi. `processRing` (`.URING`) adalah pass pemrosesan yang sama tanpa loop baca dan tanpa flush penutup: ring memiliki recv dan meng-arm ulang setelah ini kembali.

---

## hpack.zig

Tabel statik, codec Huffman, decoder (dengan eviction dynamic-table), encoder stateless, dan cache response-prefix.

### respHeaderBlock + cache response-header

`respHeaderBlock(dst, status, content_type, content_encoding, content_length)` mengenkode satu blok header respons penuh. Prefix `[:status, content-type, content-encoding]` dilayani dari cache append-only global-proses, hanya `content_length` (yang bervariasi) yang dienkode per panggilan. `content_length` yang null menghilangkan field itu (respons END_STREAM tanpa body).

Cache-nya adalah `g_resp_prefix: [32]RespPrefix` dengan count yang di-publish secara release dan sebuah spinlock (`g_resp_prefix_lock`). Reader men-scan `0..count` lock-free, spinlock hanya men-serialize insert yang langka (satu per triple berbeda). Ia byte-identik pada setiap koneksi karena `HpackEncoder` stateless: tabel statik plus literal-without-indexing, tidak pernah dynamic table atau size update, jadi byte ter-cache plus content-length per-panggilan adalah HPACK yang valid. Triple yang terlalu panjang atau cache penuh jatuh kembali ke encode langsung, jadi kebenaran tidak pernah bergantung pada hit. Sebuah test menegaskan `respHeaderBlock` cocok dengan empat panggilan `writeHeader` byte-per-byte.

### HpackDecoder

```zig
pub const HpackDecoder = struct {
    dyn: [128]HpackEntry = undefined,
    dyn_count, dyn_size, max_size = 4096,
    dyn_buf: [8192]u8 = undefined,   // entry dyn[] selalu slice ke sini, tidak pernah scratch per-panggilan
    dyn_buf_pos,
};
```

`decode(block, out, scratch)` menangani representasi indexed, literal-with-incremental-indexing, dynamic-table-size-update, dan literal-without-indexing. Setiap slice yang di-decode menunjuk ke `scratch` milik pemanggil. Entry dinamis disalin ke `dyn_buf` (seumur-koneksi), jadi lookup indexed tetap valid setelah scratch sebuah slot stream dipakai ulang (regresi yang sudah diperbaiki). `evictTo(target)` membuang entry tertua sampai tabel muat, `compactDynBuf` memadatkan ulang entry hidup di depan `dyn_buf` saat ia penuh, dan `addDynamic` mengukur entry sebagai `name.len + value.len + 32`. Literal Huffman lewat `huffDecode`.

### HpackEncoder

`init(buf)` atas buffer pemanggil, `writeHeader(name, value)`: kecocokan persis static-table dienkode sebagai indexed, kecocokan static name-only sebagai literal name-indexed (tidak pernah ditambahkan ke dynamic table), selain itu literal penuh. `writeString` memilih Huffman saat lebih pendek dan menandai hasil Huffman sebagai `?usize` agar evaluasi comptime (blok ter-cache) mempertahankan optional bahkan saat cabang error secara statik tak terjangkau. Stateless: tanpa dynamic table, tanpa size update.

---

## frame.zig

Codec frame, pengirim control-frame, dan konstanta (`FRAME_TYPE_*`, `FLAG_*`, `ERR_*`, `SETTINGS_*`, `PREFACE`, `FRAME_HEADER_LEN` 9, `FRAME_PAYLOAD_SLACK` 256, `DEFAULT_MAX_FRAME_SIZE` 16384, `MAX_HEADERS` 64).

`FrameHeader` adalah `{ length: u24, frame_type: u8, flags: u8, stream_id: u31 }`. `parseFrameHeader` / `encodeFrameHeader` tidak melakukan I/O (untuk write ter-buffer atau ter-stage), `writeFrameHeaderFD` dan `readFrameHeader` menambahkan I/O fd.

`writeAllFD` memeriksa `write_hook` threadlocal: saat diset (jalur seal TLS, atau sink coalescing) ia menyerahkan plaintext ke hook, selain itu ia memanggil `writeAllRawFD`, write-all blocking yang poll pada `POLL.OUT` untuk EAGAIN socket non-blocking dan retry saat INTR. `writeAllRawFD` juga jalur flush milik hook itu sendiri, jadi flush coalescing tidak masuk ulang ke hook.

`sendSettingsFD` / `sendSettingsAckFD` / `sendPingAckFD` / `sendGoawayFD` / `sendRstStreamFD` / `sendWindowUpdateFD` masing-masing mengenkode satu control frame. `sendResponseFD` -> `sendResponseEncodedFD` adalah respons langsung tanpa meter (tanpa flow control): HEADERS via `respHeaderBlock`, lalu body di-frame dalam chunk DATA `<= DEFAULT_MAX_FRAME_SIZE` dengan END_STREAM pada yang terakhir (atau pada HEADERS saat body kosong). Body di atau di bawah `SEND_STAGE_BODY_MAX` (4 KiB) keluar sebagai satu staged write, yang lebih besar sebagai satu vectored write per chunk DATA (blok HEADERS menumpang chunk pertama, write hook menerima tiap pasangan sebagai dua append). Body besar yang mungkin melebihi window peer memakai `mux.sendResponseStreamFD` sebagai gantinya.

---

## core.zig

Pemrosesan request bersama, router, dan jalur koneksi blocking.

### ServeOpts / Router / Route

`ServeOpts` menyimpan tuning per-koneksi dengan default berikut:

| field | default |
| :- | :- |
| `max_streams` | 128 |
| `max_frame_size` | 16384 (`DEFAULT_MAX_FRAME_SIZE`) |
| `max_header_scratch` | 4096 |
| `max_body` | 16384 |
| `conn_read_buf_min` | 32 * 1024 |
| `tls_write_buf_initial` | 16 * 1024 |
| `response_cache` | false |
| `public_dir` | "" (kosong menonaktifkan fallback static) |

`HandlerFn` adalah `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void` (trio ADR-063, dibangun saat dispatch oleh `core.invokeHandler`). `Route` adalah `{ path, handler, kind = .EXACT }` dengan `RouteKind` `EXACT | PREFIX`. `Router(comptime routes)` membangun tabel comptime: route `EXACT` di-resolve lewat `StaticStringMap` (O(1)), route `PREFIX` mencocokkan prefix terdaftar terpanjang pada batas segment-path, query string dibuang dulu, dan path yang tak cocok mengirim `404`. `Router(routes).dispatch` sendiri cocok persis dengan `HandlerFn`, jadi `Server.init` menerima `router.dispatch` sebagai nilai runtime biasa, bukan tabel route.

Response cache per-worker (ADR-036) juga berada di sini: `tl_cache`, `serveCached` / `sendCached`, dan `requestKey` (Wyhash atas path + body). Ia dipasang oleh worker `.EPOLL` / `.URING` dan di-key dari `tl_req_path` / `tl_req_body`, yang dicatat `muxDispatch`.

`invokeHandler` menerima `peer_max_frame_size: u32` sebagai parameter eksplisit lalu menyalinnya ke `Context.max_frame_size`, yang dipakai fallback static untuk mengukur frame DATA. Ia sengaja dipisahkan dari `ServeOpts.max_frame_size`: field itu adalah iklan sisi-terima server ini, dan memakainya sebagai batas keluar justru yang dijawab peer patuh dengan `FRAME_SIZE_ERROR`. Tiga call site memasok nilai yang benar:

| call site | sumber nilai peer |
| :- | :- |
| `mux.zig` (`.EPOLL` / `.URING`) | `conn.peer_max_frame_size`, yang memang sudah dilacak mux untuk `pumpBody` |
| `core.serveH2cLoop` (model blocking) | variabel lokal berjalan, diperbarui dari setiap frame SETTINGS dengan validasi 16384..16777215 yang sama seperti mux, karena peer boleh menaikkannya di tengah koneksi |
| `core.serveH2cUpgrade` | didekode dari header base64 `HTTP2-Settings`, sehingga response stream-1 yang dibawa sudah benar sebelum satu frame pun dipertukarkan |

`Context.public_dir` diisi dari `ServeOpts.public_dir` di titik yang sama, jadi router mencapai root static tanpa threadlocal (berbeda dengan `zix.Http1`, yang tetap memakai `tl_static_dir`).

### Jalur blocking (serveConn / serveH2cLoop)

`serveConn` mengeset `TCP_NODELAY` dan memanggil `serveConnInner`, yang membaca 3 byte: `"PRI"` menjalankan preface h2c-direct (validasi, `sendSettingsFD`, `serveH2cLoop`), selain itu menjalankan `serveH2cUpgrade` (handshake `Upgrade: h2c` HTTP/1.1, yang melayani request stream-1 awal lalu `serveH2cLoop`). `serveH2cLoop` mengalokasikan buffer payload plus tabel slot `[]Stream` dan menjalankan switch frame yang sama dengan mux memakai `readFrameHeader` + `recvExact` blocking, men-dispatch inline via `dispatchStream`. Perhatikan `Stream` blocking adalah struct inline tetap (`body: [65536]u8`, `header_scratch: [4096]u8`) yang ditahan sedalam `max_streams` per koneksi, berbeda dengan buffer ter-pool milik mux yang berukuran sesuai serve options.

---

## static.zig

Fallback `public_dir` (ADR-064), dipanggil dari `Router.dispatch` setelah semua route meleset dan sebelum 404. `serve(req, ctx, req_path, max_frame_size) bool` mengembalikan false untuk percobaan traversal, file yang tidak ada, atau `ctx.public_dir` kosong, lalu router mengirim 404-nya.

`serve` mencoba `serveCached` lebih dulu dan jatuh ke open langsung bila proses tidak memasang cache static. Keduanya berakhir di kode framing yang sama, jadi `public_dir` berperilaku identik baik `public_dir_cache_ttl_ms` diatur maupun tidak.

| fungsi | peran |
| :- | :- |
| `acquireHit` | menegosiasikan encoding dari `accept-encoding`, lalu menanyakan cache. Karena `zeroCopyAllowed` selalu false di sini, ia menanyakan `acquireMapped` dulu (snapshot resident) dan jatuh ke hit descriptor biasa di atas `SNAPSHOT_MAX_BYTES`, sehingga file besar tetap memakai descriptor yang di-cache alih-alih turun ke jalur non-cache |
| `segmentFor` | mengubah header `Range` menjadi `Segment`. Mengembalikan segment file utuh bila header tidak ada atau malformed (RFC 7233 bagian 3.1 meminta mengabaikannya), dan null bila well-formed tapi tak terpenuhi, yang menjadi isyarat bagi pemanggil untuk menjawab 416 |
| `sendFramed` | satu frame HEADERS (status, content type, `content-length`, `accept-ranges`, dan `content-range` untuk 206) lalu frame DATA, masing-masing dibatasi `max_frame_size`, yang terakhir berflag END_STREAM |
| `sendRangeNotSatisfiable` | 416 dengan `Content-Range: bytes */length`, header saja, END_STREAM pada frame HEADERS |
| `zeroCopyAllowed` | selalu false di engine ini. `dispatch/common.beginCoalesce` memasang `frame.write_hook` di setiap batch, termasuk cleartext, jadi `sendfile` akan menaruh body mendahului frame yang sudah di-stage di sink |

`Segment` membawa `{ offset, length, status, content_range }`, sehingga 200 dan 206 berbagi satu jalur framing dan hanya blok header-nya yang berbeda. `Content-Length` membawa panjang segment, bukan ukuran file, kalau tidak client menunggu byte yang tidak pernah datang. File kosong menutup stream pada HEADERS tanpa frame DATA sama sekali.

Parsing Range sendiri tidak lokal: ia datang dari `src/utils/http_range.zig`, dipakai bersama engine lain. `parseSpec` (membaca header) dan `resolve` (clamp terhadap panjang yang diketahui) sengaja dipisah menjadi dua pemanggilan, karena menggabungkannya menjadi satu hasil nullable membuat perbedaan abaikan-versus-416 mustahil diungkapkan.

---

## dispatch/ dan tls_mux.zig

`server.zig` memuat tipe publik `Http2Server` dan `run()` switch tipis: `.ASYNC` mempertahankan struktur accept-thread (`common.ConnTask` plus `common.dispatchConn`) dan memanggil `core.serveConn`, `.EPOLL` memanggil `epoll.runEpoll`, `.URING` memanggil `uring.runUring`, dan `config.tls != null` mengarahkan `.EPOLL` / `.URING` ke `tls_mux.runTlsMux`, selain itu semua ke `tls_serve.runTls`. Sebelum semua itu, `run()` menolak `.EPOLL` / `.URING` di luar Linux dengan `error.ZixDispatchModelUnsupported` (ADR-065).

### dispatch/epoll.zig

`ConnTable` adalah map fd -> `*MuxConn` privat per-worker, ber-indeks berdasarkan fd atas `slab.mapZeroedSlots(MAX_FD = 1 << 16)` (kernel-zeroed, demand-paged), tidak dibagi antar worker. `acceptAll` menguras `accept4(NONBLOCK | CLOEXEC)` sampai EAGAIN, mengeset `TCP_NODELAY` dan busy-poll opsional, membangun `MuxConn`, dan meregistrasi `EPOLL.IN | RDHUP`. `epollMuxWorkerFn(routes)` mem-pin ke sebuah CPU, membuka listener `SO_REUSEPORT` privat plus instance epoll-nya sendiri dan response cache opsional, dan menjalankan `epoll_wait` (hingga 512 event): listener menggerakkan `acceptAll`, fd koneksi menjalankan `beginCoalesce` -> `mux.onReadable` -> `endCoalesce` (tutup saat kegagalan write batch). `runEpoll` men-spawn `worker_count = workers` (0 = jumlah CPU tersedia) thread dan men-join mereka.

### dispatch/uring.zig

Bentuk io_uring dari loop yang sama (ADR-037 Phase 4). `initUringRing` meminta `SINGLE_ISSUER | DEFER_TASKRUN | CQSIZE | CLAMP` dan jatuh kembali ke ring tanpa flag. Sebuah worker meng-arm multishot accept, memegang tabel slot `[]?*UringConn` ber-indeks fd, dan menandai tiap `user_data` dengan `gen: u24` agar recv CQE basi untuk fd yang dipakai ulang dibuang (`lookup`). `armRecv` mengompaksi akumulator lalu mem-posting satu `prep_recv` ke `rbuf[rend..]` (satu recv in-flight per koneksi), dan `handleRecv` memajukan `rend`, menjalankan `beginCoalesce` -> `mux.processRing` -> `endCoalesce`, lalu meng-arm ulang. Respons pergi direct-to-fd pada socket non-blocking (tanpa reply cork yang dikirim via ring). `runUring` menyelidiki ring saat startup dan jatuh kembali ke `runEpoll` saat io_uring tidak tersedia.

### dispatch/common.zig

`serveOpts(cfg)` memetakan `Http2ServerConfig` ke `core.ServeOpts` (`max_recv_buf` -> `conn_read_buf_min`, `tls_write_buf_initial_bytes` -> `tls_write_buf_initial`, plus field cache dan `public_dir`). Ia juga memuat `setNoDelay`, `setBusyPoll`, `pinToCpu` dan `getAvailableCpuCount` (keduanya sadar cgroup-mask), dan `effectiveCacheEntries` (menghormati `cache_max_total_bytes`).

Sink write-coalescing adalah primitif batching untuk mux cleartext: `MuxCoalesceSink` (threadlocal 64 KiB, satu per worker) dipasang sebagai `frame.write_hook` oleh `beginCoalesce(fd)` dan dibongkar oleh `endCoalesce()`. Selama terpasang, setiap frame yang mux tulis dalam satu batch readable (HEADERS, DATA, SETTINGS, WINDOW_UPDATE) di-stage ke satu buffer dan keluar sebagai satu write, sehingga batch banyak-stream menjadi satu segmen alih-alih satu segmen kecil per frame di bawah `TCP_NODELAY`. Ia flush saat penuh dan menulis frame kelewat besar langsung tembus, jadi kebenaran tidak pernah bergantung pada ukuran buffer. `endCoalesce` mengembalikan apakah sebuah write gagal selama batch.

### tls_mux.zig

h2 multiplex atas TLS 1.3 (ADR-052): satu listener `SO_REUSEPORT` plus satu instance epoll per worker, tiap koneksi menerminasi TLS di tempat via `tls_session.Session` resumable (tanpa socketpair, tanpa thread per koneksi). Sebuah `TlsConn` memegang session, state h2 `?*MuxConn` (dialokasikan begitu handshake terbentuk dan ALPN memilih h2), buffer backpressure ciphertext-keluar (`wbuf` / `woff` / `wlen`, di-flush saat EPOLLOUT), dan buffer staging `plain`. Pass-nya: recv ciphertext -> `session.feed` mendekripsi -> `feedMux` meng-append plaintext ke `h2.rbuf` dan menjalankan `mux.processRing` -> frame reply mux di-route lewat `frame.write_hook = hookWrite` -> di-seal ke record TLS -> `sendRaw`.

`hookWrite` adalah gather seal-in-place. Ia mengakumulasi plaintext ke `plain`, dan kapan pun prefix ter-stage plus write baru melengkapi satu record penuh ia menyeal record itu langsung dari sumber dengan `sealGather` -> `conn.tls.encrypt2(prefix, tail, sealed)` (yang menembus ke `connection.writeAppData2` dan `record.protect2`), meng-gather prefix ter-stage dengan slice dari sumber. Ini menghindari penyalinan payload DATA besar ke `plain` dulu, hanya sisa sub-record yang di-stage. Toggle `seal_in_place` adalah `const` comptime agar jalur gather bisa di-A/B terhadap fallback accumulate-then-seal (`flushPlain` -> `encrypt`) tanpa mengubah perilaku lain. `sendRaw` menjaga urutan record (nonce AEAD adalah nomor urut record): jika ciphertext sudah ter-stage ia meng-append alih-alih menulis langsung, jadi record berikutnya tidak pernah menyalip yang ter-stage di wire.

---

###### end of lld-http2
