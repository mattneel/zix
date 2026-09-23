# CHANGELOG

<!--
IMPORTANT:
- Do not remove this
- Naming file is always based on year
- The latest is always on top, bottom next is previous change
- Format:
```
## MAJOR.MINOR.PATCH (YYYY-MM-DD)

__*Update:*__

- Foo

- Bar:
    - Baz

    ---

- Qux:
    - Quux

<br>

__*Fix:*__

- ISSUE_FIX_SHORT_NAME:
    - ISSUE_LINK
    - SHORT_SUMMARY
    - PROFILE_CONTRIBUTOR:
        - NAME_OR_USERNAME / PROFILE_LINK

    ---

- SAME_AS_ABOVE:
    - BUT JUST ONE

<br>

## PREVIOUS_CHANGELOG
...
```
-->

<br>

## X.Y.Z (YYYY-MM-DD)

### __**Fitur Baru:**__

#### Modul Baru: `zix.Webtransport` (WebTransport over HTTP/3)

WebTransport over HTTP/3 sebagai fitur `zix.Http3` (ADR-069), dilayani di koneksi QUIC yang sudah dimiliki engine. Diaktifkan dengan `Http3ServerConfig.webtransport`, dan request HTTP/3 biasa tetap dilayani di koneksi yang sama.

- **Dua dialect di wire, keduanya diterima.** draft-ietf-webtrans-http3-16 (token `webtransport-h3`, `SETTINGS_WT_ENABLED` 0x2c7cf000, flow control level session, `RESET_STREAM_AT` pada reset stream) dan draft-07 deployed (token `webtransport`, `SETTINGS_ENABLE_WEBTRANSPORT` 0x2b603742, `SETTINGS_WEBTRANSPORT_MAX_SESSIONS` 0xc671706a) yang masih dikirim browser dan aioquic. Server mengiklankan kedua codepoint di satu SETTINGS frame, dan token `:protocol` pada CONNECT yang memilih dialect session.
- **Public API `zix.Webtransport`:** `Config` pada server HTTP/3, `Handler` dengan lima callback opsional (`on_session`, `on_stream`, `on_stream_reset`, `on_datagram`, `on_close`), dan dua handle, `Session` (`openBidi`, `openUni`, `sendDatagram`, `close`, `drain`, `streamsAvailable`, `closeInfo`) serta `Stream` (`read`, `write`, `finish`, `reset`, `stop`). Handler tidak pernah menyebut stream id, frame, atau capsule.
- **Wire:** extended CONNECT over HTTP/3 (RFC 9220) membuka session, capsule protocol (RFC 9297 3) membawa close dan drain plus capsule flow control draft-16, HTTP/3 datagram (RFC 9297 2) menumpang QUIC DATAGRAM frame (RFC 9221) dengan kunci quarter stream id, dan stream data adalah stream QUIC yang dibuka dengan type 0x54 (unidirectional) atau signal value 0x41 (bidirectional) lalu session id. Reset draft-16 memakai `RESET_STREAM_AT` (draft-ietf-quic-reliable-stream-reset-09) dengan reliable size yang mencakup header stream, sehingga asosiasi session bertahan meski payload-nya dibuang.
- **Codepoint:** capsule `WT_CLOSE_SESSION` 0x2843, `WT_DRAIN_SESSION` 0x78ae, `WT_MAX_DATA` 0x190B4D3D, `WT_DATA_BLOCKED` 0x190B4D41, `WT_MAX_STREAMS` 0x190B4D3F / 0x190B4D40, `WT_STREAMS_BLOCKED` 0x190B4D43 / 0x190B4D44; error code `WT_SESSION_GONE` 0x170d7b68, `WT_BUFFERED_STREAM_REJECTED` 0x3994bd84, `WT_FLOW_CONTROL_ERROR` 0x045d4487; application error code dipetakan ke rentang terreservasi 0x52e4a40fa8db sampai 0x52e5ac983162 sambil melewati setiap codepoint grease HTTP/3.
- **Milik worker, kapasitas tetap.** Session, stream data beserta send buffer-nya, dan buffer stream pra-session berasal dari pool yang dialokasikan sekali per worker, sehingga jalur receive tidak mengalokasi apa pun dan pool menolak alih-alih tumbuh. `Webtransport.capacityError` melaporkan field yang melewati plafon compile-time (`connection_session_cap` 8 session, `connection_stream_cap` 32 stream per koneksi, dan maxima pool) alih-alih memotong fitur secara diam-diam.
- **Penolakan adalah jawaban protokol, bukan drop.** Plafon session dijawab 429 dan pool penuh 503 pada stream request; stream pra-session melewati buffer direset dengan `WT_BUFFERED_STREAM_REJECTED`; pelanggaran flow control session menutup session dengan `WT_FLOW_CONTROL_ERROR`; dan setiap stream session yang berakhir direset dengan `WT_SESSION_GONE`.
- **Contoh:** [examples/tls/http3_webtransport.zig](examples/tls/http3_webtransport.zig) pada 127.0.0.1:9089, dibangun sebagai `zig build example-http3_webtransport`: menerima session di `/echo`, memantulkan setiap chunk stream data dan setiap datagram, membuka satu stream unidirectional per session dengan banner, dan mencetak lifecycle session ke stderr.
- **Runner:** `zig build test-runner-webtransport` menjalankan contoh itu dan menggerakkannya end to end dengan client HTTP/3 buatan sendiri (extended CONNECT dijawab 2xx, banner pada stream unidirectional, echo stream data bidirectional, dan echo datagram). Step ini juga bagian dari `test-runner-all`.
- **Dokumentasi:** [`docs/hld-webtransport-id.md`](docs/hld-webtransport-id.md) / [`docs/hld-webtransport-en.md`](docs/hld-webtransport-en.md) dan [`docs/lld-webtransport-id.md`](docs/lld-webtransport-id.md) / [`docs/lld-webtransport-en.md`](docs/lld-webtransport-en.md), plus ADR-069.
- **Contoh (browser):** [examples/tls/webtransport_live.zig](examples/tls/webtransport_live.zig) di 127.0.0.1:9443, dibangun sebagai `zig build example-webtransport_live`: satu proses, satu nomor port, dua transport — halaman lewat HTTPS/1.1 di TCP dan session lewat HTTP/3 di UDP, dilayani pada route yang sama, sehingga halaman dan session berbagi satu origin. Isinya adalah live view atas state milik server: tick pada stream bidirectional menjadi increment event bertipe yang dirender sebagai patch DOM, sebuah datagram membawa note yang tidak reliabel dan mengembalikan patch-nya, stream kedua mengunggah 64 KiB dengan progress event sementara tick tetap mengalir, dan reconnect membuka session baru yang menyinkronkan ulang dari snapshot. Dijalankan end to end di Chromium (session terbuka, stream unidirectional yang dibuka server, 5 tick, satu note datagram, unggahan 64 KiB dengan 5 tick terselip di tengahnya, dan reconnect yang menyinkronkan ulang pada revisi yang event-nya terlewat). Lihat bagian "Menjalankan demo browser" di HLD untuk dua flag Chromium yang dibutuhkan sertifikat self-signed.
- **Harness interop:** [scripts/webtransport_interop.py](scripts/webtransport_interop.py) menjalankan contoh `http3_webtransport` dengan aioquic dan melaporkan PASS/FAIL untuk handshake, extended CONNECT, echo stream bidirectional, echo datagram, dan stream unidirectional yang dibuka server. Ia adalah client independen berbasis skrip; demo browser adalah versi visualnya.
- **Contoh (aksi durable):** [examples/tls/webtransport_tasks.zig](examples/tls/webtransport_tasks.zig) di 127.0.0.1:9444, dibangun sebagai `zig build example-webtransport_tasks`: halaman mengirim typed form event dengan idempotency key lewat stream reliabel, server memvalidasi dan mengotorisasi, satu transaksi menulis task dan job-nya, worker me-lease dan menjalankan job, satu transaksi completion menulis update task, penyelesaian job, dan baris outbox, dispatcher mempublikasikannya, dan view yang terotorisasi mengirim patch berevisi. Datagram hanya membawa typing hint dari halaman, tidak pernah sebuah mutasi.
- **Modul slice durable:** [examples/durable/tasks.zig](examples/durable/tasks.zig) memuatnya di satu tempat — schema, store, feed tenant in-process, worker dan dispatcher — beserta invarian yang membentuk milestone ini: satu transaksi per langkah, lease alih-alih lock, `(tenant_id, idempotency_key)` untuk idempotensi, revisi per tenant yang diambil di dalam transaksi yang mengubah state, dan baris outbox yang baru ditandai terpublikasi setelah feed menerimanya (sehingga crash di antaranya memutar ulang event dan view yang sudah menerapkan revisi N mengabaikan apa pun ≤ N).
- **Suite acceptance:** `zig build test-durable` menjalankan tujuh skenario terhadap PostgreSQL nyata (`-Ddurable-dsn=`, database terpisah memang disengaja: worker me-lease job siap paling tua milik tenant mana pun, jadi server yang hidup dan berbagi tabel akan menyelesaikan job milik suite). Submission tidak valid atau tidak terotorisasi tidak menyimpan apa pun; transaksi yang tidak pernah commit tidak menyimpan satu pun sisipan; submission ganda menghasilkan satu task dan satu job; job milik worker yang mati dipulihkan setelah lease-nya kedaluwarsa dengan `attempts` bertambah; crash setelah commit tetapi sebelum publikasi tetap terkirim; event yang diputar ulang tidak menggeser view; dan view yang restart membangun ulang state, beserta revisinya, dari database.
- **Benchmark:** [scripts/bench_durable_tasks.py](scripts/bench_durable_tasks.py) menjalankan slice ini sebagai workload dan mengukur dua angka yang penting — submit sampai commit, dan submit sampai patch completion — melalui satu session WebTransport. Terukur di sini (WSL2, loopback lokal, build Debug, satu session berurutan, poll 10 ms, job simulasi 40 ms milik demo): 200 aksi, **commit p50 3,3 ms / p99 4,4 ms**, **end-to-end p50 65,5 ms / p99 88,1 ms / max 89,1 ms**, 14,1 aksi/s. Target subsecond karena itu terukur dengan headroom sekitar satu orde besaran, dan angkanya dapat direproduksi dengan skrip dan contoh ini.
- **Belum di pass ini:** varian WebTransport over HTTP/2 berbasis capsule, session 0-RTT, keying-material exporter, priority signalling, dan drain session yang dipicu GOAWAY. Lihat tabel Belum Diwire di HLD.

<br>

### __**Fixed:**__

#### WebTransport over HTTP/3: prefiks yang sudah di-ACK di pensiunkan, sehingga stream patch berumur panjang tidak macet

    - Fixed: stream data WebTransport macet begitu buffer-nya penuh, padahal seluruh byte-nya sudah di-ACK. `SendSide.noteSent` menggabungkan kiriman yang berurutan ke rentang outstanding sebelumnya, sementara acknowledgement datang per paket — yaitu ekor dari rentang gabungan itu — dan `noteAcked` hanya memensiunkan rentang yang tercakup utuh. Akibatnya prefiks tidak pernah bebas, `acked` tetap nol, buffer stream 16 KiB penuh, dan stream melaporkan tidak ada lagi yang bisa dikirim: view yang mengalirkan patch durable macet setelah sekitar 16 KiB padahal peer sudah mengonfirmasi semuanya. `noteAcked` kini memangkas kepala rentang yang tercakup sebagian, sehingga acknowledgement per paket menguras buffer seiring stream maju. Ditutup oleh `zix webtransport: 4.1 a merged send range frees its prefix from per-packet acknowledgements`.
    - Ditemukan oleh benchmark slice durable, workload yang membuatnya terlihat: 200 aksi CreateTask berurutan pada satu session macet di sekitar request 34 sebelum perbaikan, dan selesai dengan p99 88,1 ms sesudahnya. Contoh echo tidak bisa menunjukkannya — ia menjawab dengan beberapa lusin byte, yang tidak pernah memenuhi buffer stream.
    - Jalur tulis milik contoh belajar pelajaran yang sama: sebuah stream write mengembalikan berapa byte yang diterima, jadi view kini menyangga apa yang engine tidak terima dan melanjutkannya pada poll berikutnya, serta memajukan cursor hanya untuk baris yang diterima utuh. Patch yang sudah ditandai terpublikasi oleh outbox tidak pernah hilang.

#### WebTransport over HTTP/3: satu alokator untuk setiap stream id yang diinisiasi server

    - Fixed: stream control server ditulis dari literal di ketiga jalur prologue sementara WebTransport menyimpan counter-nya sendiri, jadi reservasi id itu hanya komentar, bukan fakta. Setiap stream yang diinisiasi server — stream control lebih dulu, lalu stream QPACK atau WebTransport apa pun yang dibuka engine ini — kini mengambil id-nya dari satu alokator per koneksi (`Connection.takeServerStreamId`), dan itulah yang membuat invarian "semua stream yang diinisiasi server punya id unik dalam satu koneksi" menjadi struktural, bukan kondisional. Ditutup oleh `zix http3: every server-initiated stream id is unique, control stream included`, tes yang gagal pada kode lama: ia memaku id stream control, sesuatu yang sebelumnya tidak dijaga siapa pun.

#### WebTransport over HTTP/3: handshake dikonfirmasi saat Finished client tiba

    - Fixed: browser tidak bisa membuka session sama sekali. Client berhak menunggu handshake terkonfirmasi sebelum mengirim data 1-RTT apa pun, dan Chromium memang menunggu: ia menahan SETTINGS, CONNECT, dan setiap request sampai `HANDSHAKE_DONE` tiba, sementara engine hanya menulis konfirmasi ketika sebuah paket 1-RTT datang — deadlock yang tidak pernah terlihat oleh aioquic maupun client in-tree, karena keduanya mengirim 1-RTT lebih awal. Server kini memverifikasi Finished milik client dan mengirim prologue 1-RTT sekali pakainya (`HANDSHAKE_DONE`, lalu SETTINGS stream control) pada giliran yang sama, yang juga momen paling awal yang diizinkan RFC 9000 17.2.1.
    - Fixed: Finished dari client didekripsi lalu dibuang, sehingga handshake tidak pernah selesai di sisi server. Byte CRYPTO level Handshake kini direassemble dan Finished diperiksa terhadap client handshake-traffic secret atas transcript sampai server Finished (RFC 8446 4.4.4). Finished yang tidak lolos verifikasi membiarkan handshake tidak terkonfirmasi: tidak ada konfirmasi, tidak ada session, dan koneksi mati oleh idle timeout, sehingga peer yang tidak pernah membuktikan penguasaan kunci tidak pernah mencapai jalur request. Ditutup oleh tes `zix http3: a client Finished verifies against the client handshake secret and the server-Finished transcript`.
    - Fixed: CONNECTION_CLOSE level Handshake (client menolak sertifikat atau transport parameter) didekripsi lalu dijatuhkan, sehingga koneksi hanya diam. Kini dicatat pada level WARN beserta kode alert dan deskripsi dari peer, tempat sebuah kegagalan interop menyebut dirinya sendiri.
    - Fixed: stream unidirectional pertama yang dibuka server mendapat id 3, yaitu stream control HTTP/3 milik server sendiri: setiap stream unidirectional yang dibuka session malah menambahkan byte-nya ke stream control dan merusaknya bagi peer (client melihat stream type 0x54 dan sebuah banner menempel pada SETTINGS-nya). Id unidirectional kini mulai dari 7, id pertama yang disisakan stream control. Ditutup oleh tes `zix http3: a server's WebTransport stream ids skip the control stream (RFC 9114 6.2.1)`.
    - Fixed: client HTTP/3 milik runner mengharapkan banner tersebut pada stream 3, dan itulah yang membuat tabrakan di atas lolos dari tesnya sendiri. Client kini mengharapkan id yang benar menurut protokol, sehingga runner gagal jika engine suatu saat memakai ulang stream control.
    - Docs: HLD (kedua bahasa) mendapat bagian "Handshake dan Konfirmasi", satu butir keamanan tentang aturan konfirmasi, demo browser di tabel contoh, dan panduan "Menjalankan demo browser" berisi flag sertifikat Chromium; bagian Fitur Baru changelog mendapat demo dan harness interop.

#### HTTP/3 over QUIC

Dua cacat yang sudah ada sebelumnya di engine dan muncul ke permukaan oleh pekerjaan WebTransport, keduanya ditemukan oleh client nyata, bukan oleh client in-tree.

- **Paket long-header dibatasi field Length miliknya sendiri, bukan akhir datagram (`src/udp/http3/protection.zig`).** AEAD membaca tag-nya melewati batas paket: client yang menulis apa pun setelah Initial-nya (paket yang dikoalesikan, atau padding yang ditambahkan aioquic untuk mencapai lantai datagram 1200 byte) mengautentikasi byte yang salah lalu gagal, sehingga handshake-nya tidak pernah mulai. `packet.longPacketBounds` sekarang menyediakan akhir paket dan dipakai bersama oleh walk paket terkoalesi, sehingga aritmetika yang sama menentukan keduanya. Initial aioquic hasil capture (field Length 478 byte di dalam datagram 1200 byte) gagal sebelumnya dan kini terbuka, dan aioquic menyelesaikan handshake QUIC / TLS terhadap engine lalu membuka session.
- **Setiap paket yang dibawa satu datagram dilayani, bukan hanya yang pertama (`src/udp/http3/dispatch/common.zig`).** `serveDatagram` membaca paket pertama sebuah datagram lalu berhenti, sehingga paket 1-RTT yang dikoalesikan setelah paket Initial atau Handshake dibuang diam-diam. Ia kini menelusuri paket-paket dalam satu datagram (RFC 9000 12.2), dengan `servePacket` sebagai langkah per paket, dan itulah yang diandalkan client yang mengoalesikan flight pertamanya.

<br>

__**Update:**__
- Memperkenalkan `zix.utils.charsets` dari `src/utils/charsets.zig`:
    - Mengkover mulai dari `alphabet`, `ALPHABET`, `ALPHANUMERIC`, `NUMERIC_STRING`, `punctuation`, `ALPHANUMERIC_PUNCTUATION`, `base32`, dan `base64`.
    - User/caller bisa menggunakan ini ketika mereka membutuhkan.
    - Untuk kontributor/maintainer, semua repeatable charset harus digunakan atau dipanggil dari sini.

- Menambahkan utils generator dalam `src/utils/generator.zig`.

- Menambahkan utils check `src/utils/Check.zig`:
    - `string`:
        - `isNumericSigned` untuk mengecek string adalah signed number.
        - `isNumericUnsigned` untuk mengecek string adalah unsigned number.
        - `isDecimal` untuk mengecek string adalah decimal number.

- Menambahkan utils base32 `src/utils/base32.zig`, mengkover:
    - Encode.
    - Decode.
    - RFC 4648 test vectors + roundtrip.

- Menambahkan utils base64 `src/utils/base64.zig`, mengkover:
    - Encode.
    - Decode.
    - RFC 4648 test vectors + roundtrip.

<br>

## 0.5.0 (2026-08-26)

### __**Fitur Baru:**__

#### TLS 1.3 Stack

Implementasi penuh di atas `std.crypto`, tanpa OpenSSL:
- **Server TLS 1.3** (RFC 8446) + **fallback TLS 1.2** (RFC 5246/5288, ECDHE-ECDSA-AES128-GCM).
- **Klien verifikasi native** `zix.Tls.Client` (1.3 dan 1.2) dengan ALPN, verifikasi rantai X.509 + hostname.
- Mendukung sertifikat **ECDSA P-256**, **Ed25519**, dan **RSA**.
- RSA minimum 2048-bit, modexp Montgomery waktu-konstan, tanda tangan PSS.
- **Dual listener TLS**: satu server melayani cleartext di `port` DAN TLS di `tls_port`.
- **HTTPS/1.1, h2 over TLS, gRPC over TLS, dan WebSocket over TLS (wss)** semuanya dilayani.
- **SSE over TLS** pada jalur thread-per-connection.
- Dispatch TLS multiplexed di bawah `.EPOLL`/`.URING` (tanpa thread per koneksi).

CATATAN:
- Pertimbangkan menggunakan Ed25519 atau ECDSA P-256 (RSA agak lambat).

---

#### Tiga Driver Internal

1. **`postgrez`** (PostgreSQL)
   - Wire protocol 3.2 dengan fallback 3.0 (PostgreSQL 15+).
   - SCRAM-SHA-256 dan SCRAM-PLUS (channel binding), auth cleartext.
   - TLS 1.3, COPY streaming, LISTEN/NOTIFY, prepared statements, pipelining query.
   - `Pool` thread-safe, `Executor` batching.

2. **`rediz`** (Redis)
   - RESP3 via HELLO dengan fallback RESP2 (Redis 7 atau 8).
   - Helper nilai bertipe, raw command escape hatch.
   - Pipelining command, jalur write-behind ditangguhkan.
   - `Pool` thread-safe, TLS 1.3.

3. **`prometheuz`** (Prometheus)
   - Parser format eksposisi teks 0.0.4, poller `Scraper` latar belakang.
   - Push `remote_write` (protobuf + snappy).
   - Query PromQL instant dan ranged.
   - Registry metrik (`Counter`, `Gauge`).

---

#### Eksekutabel Baru: `zixer` (Proxy Gateway)

Gateway berbasis konfigurasi yang dibangun di atas engine:
- **Daemon tunggal** mengelola banyak site independen, masing-masing dengan port dan engine sendiri.
- **Lima tipe edge**: `http1`, `http2`, `grpc`, `http3`, `udp`.
- **Terminasi TLS** di edge (stack TLS zix), negosiasi ALPN, 421 untuk Host yang tidak cocok.
- **Upstream round-robin** dengan ketersediaan O(1), cooldown saat gagal.
- **Dibatasi di kedua sisi**: client_timeout_ms, conn_limit, upstream_timeout_ms, process_limit.
- **Pelayanan file statis** dengan sibling precompressed .br/.gz.
- **`Proxy-Status`** (RFC 9209) pada error yang dihasilkan gateway.
- **Pendamping port 80** untuk pembaruan ACME http-01 dan pengalihan `force_https`.
- **Injeksi header**: interpolasi `$client_ip`, `$scheme`, `$host`.
- **Validasi** mengumpulkan semua kesalahan sebelum binding, matematika numerik (mis. `16 * 1024`).
- **15 demo yang dapat dijalankan** di `examples/proxies/`.
- Dokumentasi lengkap di `docs/zixer/` (Inggris dan Indonesia, masing-masing 5 file).

---

#### Engine Baru: `zix.Webrtc` (Peer WebRTC)

Server WebRTC dibangun dari RFC 7983, 8445, 8489, 6347, 9260, 8831, dan 8832. Melayani:
- **Pemeriksaan konektivitas ICE** melalui STUN.
- **Handshake DTLS 1.2** (ECDHE-ECDSA P-256 saja).
- **Asosiasi SCTP** dengan data channel.
- **Mode Selective Forwarding Unit (SFU)** untuk media (penulisan ulang header RTP per penerima).
- Tiga model dispatch: `.ASYNC` (cross-platform), `.EPOLL`, `.URING` (Linux).
- Delapan contoh pada port 9081–9088, termasuk demo yang digerakkan oleh browser.

<br>

---

### __**Peningkatan Engine Inti:**__

#### HTTP/3 over QUIC

- Implementasi penuh RFC 9000/9001/9002/9114.
- **Pemulihan loss dan kontrol kongesti** (ACK-driven, NewReno, PTO dengan backoff).
- **QPACK** static-table field lines, decoder Huffman RFC 7541.
- **Rolling flow-control**: hibah MAX_STREAMS dan MAX_DATA diperbarui seiring pemakaian klien.
- **Negosiasi content-encoding**: `accept-encoding`, `content-encoding` br/gzip (static table indeks 31/42/43).
- **Worker SO_REUSEPORT per-core** di bawah `.EPOLL`/`.URING`.
- Test runner native dengan klien QUIC buatan sendiri.

---

#### Dispatch Native HTTP/2

- **Loop multiplexed shared-nothing `.EPOLL`/`.URING`** (sebelumnya hanya `.POOL`).
- **Stream-slot pool per-worker**: memori residen melacak stream konkuren, bukan `connections * max_streams`.
- **Cache prefix header respons HPACK**: triple panas [:status, content-type, content-encoding] digunakan ulang.
- **Query-stripping** dan routing prefix (mirip `zix.Http1`).
- **Penggabungan DATA-frame** untuk gRPC server-streaming (5000 pesan -> ~3 frame).
- **Terminator TLS** dibagi dengan gRPC melalui `h2_terminator.zig`.

---

#### Perombakan Body Permintaan

**14 cacat diperbaiki** di kedua engine HTTP:
- `bodyReceived()` dan `bodyComplete()` baru pada kedua view permintaan.
- Satu decoder chunked bersama (`chunkedFrame`/`decodeChunkedInBuf`/`readChunkedBody`).
- Konfig `max_request_body` (default 8 MiB, 0 menonaktifkan).
- `Expect: 100-continue` dijawab pada setiap model.
- `.EPOLL` menunda handler sampai body terkuras penuh (bukan parsial).
- Daftar `Transfer-Encoding` yang diakhiri `chunked` dikenali dengan benar.
- Body berukuran besar dibuang dengan 413 (bukan dipotong).
- Frame chunked malformed -> 400.

---

#### Trio Request/Response/Context (ADR-062/063)

- **Semua engine** sekarang menggunakan `HandlerFn(req: *Request, res: *Response, ctx: *Context) anyerror!void`.
- `Context` membawa: `io`, arena stack per-permintaan (`FixedBufferAllocator`), helper timeout.
- **Router** dengan `zix.ENGINE.Router(&[_]Route{...}).dispatch`.
- `zix.Grpc` adalah pengecualian: menerima `Router(&routes)` sendiri (membawa metadata `is_server_streaming`).
- **Auto-500** pada error untuk `zix.Http`, `zix.Http2`, `zix.Http3`, pass-through diam untuk `zix.Grpc`/`zix.Fix`.

---

#### Kompresi Respons

- **Encoder/decoder brotli** in-tree dari RFC 7932 (kamus statis 122.784 byte disematkan).
- Negosiasi `Accept-Encoding` (gzip/deflate/brotli) dengan q-values, wildcard, batas ukuran.
- `sendNegotiated` pada kedua engine HTTP, aktif di bawah `.EPOLL`/`.URING`.
- **Encoder gzip cepat** (`compression.flate_fast`): LZ greedy, Huffman tetap, untuk body di bawah 64 KiB.

---

#### Perombakan Pelayanan File Statis (ADR-064)

- **`static_cache.zig`**: tabel bersama per proses (fd terbuka, ukuran, header 200 pra-render).
- **`static_send.zig`**: `sendfile` pada Linux cleartext, baca posisional + tulis untuk terenkripsi/di-staging.
- **Sibling `.br` dan `.gz` precompressed** diambil sekali, dilayani dengan `Vary: Accept-Encoding`.
- **Range requests** (RFC 7233) pada `zix.Http`, `zix.Http1`, `zix.Http2`, penanganan 206/416.
- Konfig baru: `public_dir_cache_ttl_ms` (default 0), `public_dir_cache_max_entries` (256).
- `public_dir` pada `zix.Http2`/`zix.Http3` (sebelumnya tidak ada).

---

#### Penulisan Ulang Parser Multipart

- **Pemindaian linear** (sebelumnya O(parts × size)), sekarang O(size).
- **Zero-copy**: tanpa duplikasi alokator, semua field meminjam body.
- **Framing benar**: hanya dua byte CRLF yang dihapus (bukan semua leading/trailing).
- **Batas penutup tanpa CRLF di akhir** diterima (perilaku umum klien).
- **Ekstraksi nama field benar**: hanya cocok di awal parameter, bukan di dalam filename.
- Pelaporan error lengkap: `ZixMultipartNoBoundary`, `ZixMultipartUnterminated`.

---

#### Mode Datagram UDP Mentah

- `zix.Udp.Raw(handler)` melayani datagram panjang variabel.
- **Linux**: batching `recvmmsg`/`sendmmsg`, worker `SO_REUSEPORT` per-core.
- **`.URING`** multishot recv dengan buffer ring (256 buffer).
- **Dukungan GSO** di belakang `.URING`.
- Contoh: `udp_server_raw.zig` (port 9064).

<br>

---

### __**Platform & Build:**__

#### Dukungan Kompilasi Lintas Platform

- **Membangun dengan Zig 0.16.x dan 0.17.x** untuk: x86_64-linux, x86_64-windows, aarch64-macos, aarch64-linux, x86_64-freebsd, x86_64-netbsd, x86_64-openbsd.
- **Windows**: shim ntdll (`NtReadFile`/`NtWriteFile`/`NtClose` + partial-disconnect AFD).
- **BSD**: `TCP_NODELAY` diselesaikan pada comptime.
- **Jalur khusus Linux** dijaga (loop EPOLL/URING, afinitas CPU, madvise, batching UDP).
- **`scripts/build-all-targets.sh`** menyapu semua opsi pada semua target.

---

#### Paritas Fitur `.ASYNC` (ADR-066)

- **Kompresi dan cache respons** sekarang berfungsi di bawah `.ASYNC`.
- **TLS over `.ASYNC`** diperbaiki di macOS, FreeBSD, NetBSD, OpenBSD (pembagian tiga arah `windows`/`linux`/`posix`).
- **Fallback datagram portabel HTTP/3** di luar Linux.
- **Path socket Unix-domain** diselesaikan menjadi path absolut (AF_UNIX Windows membutuhkannya).
- Substrat bersama baru: `fd_io.zig`, `socket_pair.zig`, `socket_path.zig`, `async_cache.zig`.

---

#### `.POOL` dan `.MIXED` Dihapus (ADR-065)

- DispatchModel sekarang: `ASYNC = 0`, `EPOLL = 1`, `URING = 2`.
- Di luar Linux, `.EPOLL`/`.URING` mengembalikan `error.ZixDispatchModelUnsupported`.
- `pool_size` dihapus, `workers` digunakan sebagai gantinya.
- 16 file dispatch dihapus, 34 contoh -> 7 terpadu.

<br>

---

### __**Optimasi Kinerja:**__

#### Memori

- **Pemadatan recv-slab EPOLL Http1**: dikemas ke koneksi aktif, puncak ~704->281 MiB.
- **Batas idle-pool URING Http1**: eviction LRU pool reconnect hangat, dibatasi oleh knop konfig.
- **Stream-slot pool Http2/gRPC**:
  - `connections * max_streams` -> hanya stream konkuren.
  - Http2: potongan memori 6×, peningkatan throughput 8–20%.
  - gRPC: potongan memori 12× (916->77 MiB), peningkatan throughput 8–11%.
- **Seal-in-place TLS**: enkripsi-gabung dua slice plaintext menjadi satu record tanpa salinan staging.

---

#### Throughput

- **Submit intra-batch `.URING`**: SQE didorong setiap 16 completion (bukan hanya setelah batch penuh): peningkatan 4–5%.
- **Penyatuan wakeup adaptif `.URING`**: 32 completion per enter dengan guard stall 20us.
- **Fast path accept `.URING`**: SQE dikirim segera di dalam handler accept: penurunan p99 ~30%.
- **Cache prefix header respons HPACK**: peningkatan 18–26% pada sel body kecil.
- **Encoder gzip cepat**: 4–5× lebih cepat dari std pada rasio serupa.

</details>

---

<details>

<summary><b>I/O</b></summary>

- **Multishot recv `.URING`** untuk UDP/HTTP3 (buffer ring, 256 buffers)
- **Backpressure antrian submit** (`process_queue_len`): parkir pada SQ penuh daripada menutup
- **Perbaikan re-arm accept hilang** di semua dispatch `.URING`

<br>

---

### __**Klien & Transport:**__

#### Timeout Klien HTTP

- `response_timeout_ms` dan `read_timeout_ms` sekarang ditegakkan.
- Dijaga oleh poll kesiapan (`socket_poll.zig`).
- Pembacaan descriptor mentah klien HTTP/2 diperbaiki (tanpa syscall Linux di macOS/BSD).
- Klien SSE/WebSocket mendapatkan field yang sama.

---

#### Klien TLS

- Klien verifikasi native (`zix.Tls.Client` 1.3, `zix.Tls.Client12`).
- ALPN, verifikasi rantai X.509 + hostname (RFC 5280/6125).

---

#### WebSocket over TLS

- WSS pada jalur thread-per-connection (`.ASYNC`/`.POOL`/`.MIXED`).
- `WebSocket.serveTls(fd, key, on_frame)` mengenkripsi melalui stream sink.
- Auto-pong, auto-echo close, jalur mux ditambahkan melalui ADR-060.

---

#### SSE over TLS

- `res.stream()` over TLS; `zix.Http1.beginStream()` (no-op di cleartext).

<br>

---

### __**Diagnostik & Logging:**__

#### Perombakan Logger

- Shim `logSystem` menerima `Logger.Level`.
- Tanpa logger: memanggil `std.log` pada level yang sesuai.
- `.ERROR`/`.WARN` bertahan di build release.
- Penulisan gagal mencoba ulang `.INTR`/`.AGAIN`, menjaga konsol.
- Per-peer/per-paket pada `.WARN` atau lebih rendah, bind/accept/config pada `.ERROR`.

---

#### Pelaporan Error

- **Semua 21 situs bind** sekarang menjawab dengan `error.Zix<Engine>ListenFailed` + satu baris menyebutkan alamat, penyebab, jumlah worker.
- **Nama error diawali produk**: `Zix`, `Zixer`, `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`.
- **jzon** mendapat `lastFailure()` dengan nama field dan posisi byte.
- **Error yang digabung dipisah**: sertifikat/kunci tidak ditemukan, adalah direktori, terlalu besar, tidak terbaca.
- **`reuseport_cbpf` tidak lagi diam**: penolakan kernel dilaporkan sekali per proses.

---

#### Logging Zixer

- Kunci `log_level` di main.cfg (debug/info/warn/error, default info).
- Setiap jawaban edge ditulis sekali: 5xx di `.WARN`, 4xx di `.DEBUG`.
- Pemberitahuan startup/gagal daemon pada logger (bukan stdout).

---

#### Windows

- **Overflow clock monoton diperbaiki**: matematika bagi-dulu (sebelumnya kali-dulu, overflow ~31 menit uptime).
- **`recv_timeout_ms` UDP ditegakkan**: poll kesiapan berbasis AFD (sebelumnya blocking, tanpa timeout).

<br>

---

### __**Perubahan Breaking API:**__

#### Model Dispatch

- **Field konfig wajib** (tanpa default): `dispatch_model` harus diatur secara eksplisit.
- `.POOL` dan `.MIXED` dihapus -> gunakan `.ASYNC`, `.EPOLL`, atau `.URING`.

---

#### Inisialisasi Server

- Semua `Server.init` sekarang infallible, config disimpan, validasi dipindah ke `run()`.
- `zix.Http.Server.init` menghilangkan argumen comptime `stack_threshold`.
- `zix.Http3.Http3(handler)` generik -> `zix.Http3.Server.init(handler, config)`.

---

#### Signature Handler

- Semua engine: `HandlerFn(req: *Request, res: *Response, ctx: *Context) anyerror!void`.
- `zix.Http1`: raw `fn(head, body, fd)` dihapus, `initRaw` dihapus, middleware dihapus.

---

#### Helper Respons Diganti Nama (ADR-059)

- `fdWriteAll` -> `writeAllFD`.
- `writeSimple` -> `sendSimpleFD`.
- `writeJson` -> `sendJsonFD`.
- `writeGzip` -> `sendGzipFD`.
- `writeNegotiated` -> `sendNegotiateFD`.
- `writeChunkedStart` -> `sendChunkedStartFD`.
- Dan semua `write*` lainnya -> `send*` / `*FD` sesuai taksonomi.

---

#### Penanganan Metode HTTP (RFC 10008)

- **Metode QUERY** didukung (RFC 10008).
- `Method.codeFromString` adalah **pencocokan eksak** (case-sensitive, RFC 9110).
- Metode tidak didukung -> `501 Not Implemented`.
- `zix.Http1` tidak lagi menerima metode huruf kecil (`get`/`Post`/`delete`).

---

#### Tipe Konten

- `Content.Type.NA` dihapus, pencarian mengembalikan `?Type`.
- `enumFromString` -> `typeFromString`, keduanya mengembalikan null jika tidak cocok.

---

#### Nama Error

- Semua nama error publik diawali produk: `ZixPortNotConfigured`, `ZixTlsCertFileNotFound`, dll.
- Error std tetap menggunakan nama std (OutOfMemory, WriteFailed, dll.).

---

#### Field Konfig Dihapus/Diganti Nama

- `pool_size` dihapus dari semua konfig.
- `pool_stack_size_bytes` dihapus dari `zix.Fix`.
- `max_client_response` dihapus dari `HttpServerConfig`.
- `max_gzip_out` -> `compression_max_out`.
- `connection_timeout_ms` -> `conn_timeout_ms` (koreksi dokumen).

---

#### Breaking Khusus QUERY

- **Tidak ada caching untuk respons QUERY** (kunci cache hash(method+path+query), tanpa body).
- **Tipe media ditambahkan**: `application/x-www-form-urlencoded`, `application/jsonpath`, `application/sql`, `multipart/form-data`.
- **`zix.Http.Client`** tidak dapat mengirim QUERY melalui TCP (std.http.Method tertutup).
- **`requestUds`** dapat membawa QUERY, klien HTTP/2 sekarang mengirim body dengan QUERY.

<br>

---

### __**Tes & Validasi:**__

#### Ekspansi Runner

- **55 protokol** (sebelumnya 34) di semua engine dan model dispatch.
- **Eksekusi sadar platform**: target asing dikompilasi dan dilewati dengan peringatan.
- **Langkah build test-run bernama** untuk diagnostik `--summary all`.
- **52 skenario lulus di setiap platform** (linux_only_labels kosong).

---

#### Tes Driver Tanpa Docker

- `test-behaviour` dan `test-edge` untuk `postgrez`, `rediz`, `prometheuz`.
- Server in-process berbicara protokol nyata, tanpa container/daemon.
- Semua 7 jalur CI manual menjalankannya (sebelumnya hanya jalur Linux).
- `test-integration` dan `test-runner` tetap khusus container (langkah lokal).

---

#### Cakupan

- **86 tes unit/perilaku/edge baru** untuk metode QUERY.
- **~80 tes unit/edge baru** untuk penanganan body permintaan.
- **Suite tes lengkap** di semua 55 protokol runner dan 13 demo proxy zixer.

<br>

---

### __**Contoh & Demo:**__

#### Contoh Baru (Port)

- `http1_query.zig` (9079), `http_query.zig` (9080).
- `http1_compression.zig` (9058), `http_compression.zig` (9059).
- `udp_server_raw.zig` (9064), `udp_server_tickrate.zig`, `udp_client_tickrate.zig`.
- `tls/tls_http1_basic.zig` (9060), `tls/tls_http2_basic.zig` (9061).
- `tls/tls_http1_ed25519.zig` (9062).
- `tls/tls_http1_sse.zig` (9073), `tls/tls_http1_ws.zig` (9074), `tls/tls_http_ws.zig` (9075).
- `tls/tls_http1_dual.zig` (9076 cleartext/9077 TLS).
- `tls/tls_http_basic.zig` (9071), `tls/tls_http_sse.zig` (9072).
- `http3_basic.zig` (9063).
- `http2_basic_{async,pool,mixed,epoll,uring}.zig` (9065-9069).
- **8 contoh WebRTC** (9081-9088): signalling relay, STUN binding, data echo, pasangan zix-to-zix, room chat, transfer file, siaran media, panggilan video mesh.

---

#### Contoh File Statis

- Semua contoh yang menggunakan `public_dir` sekarang menggunakan jalur caching/serving baru.
- Sibling `.br` dan `.gz` precompressed diambil secara otomatis.

<br>

---

### __**Dokumentasi:**__

#### Dokumen Baru

- **`docs/zixer/`**: README, how-to-use, config, HLD, LLD (Inggris + Indonesia).
- **`docs/driver/postgrez/`**: README, HLD, LLD, ref config (EN + ID).
- **`docs/driver/rediz/`**: README, HLD, LLD, ref config (EN + ID).
- **`docs/driver/prometheuz/`**: README, HLD, LLD, ref config (EN + ID).
- **`docs/hld-http3-en.md`**, **`lld-http3-en.md`** (dan -id).
- **`docs/hld-tls-en.md`**, **`lld-tls-en.md`** (dan -id).
- **`docs/hld-grpc-en.md`**, **`hld-grpc-proxy-en.md`** (dan -id) diperbarui untuk TLS native.

---

#### Koreksi

- Dokumen `zix.Http`: TLS didukung (sebelumnya "proxy-terminated by design").
- Dokumen `zix.Grpc`: cache respons dan dual listener TLS dicatat.
- `zix.Uds`/`zix.Tcp`: encoding frame adalah big-endian (sebelumnya little-endian).
- `zix.Fix`: `connection_timeout_ms` -> `conn_timeout_ms`.
- `zix.Tcp`: `max_msg_len` -> `max_recv_buf`.

<br>

---

### __**Riwayat Versi:**__

- **0.5.0-rc1** (2026-07-15): Rilis kandidat awal
- **0.5.x-rc2** (2026-07-27): Suite tes driver, build lintas platform, perombakan body
- **0.5.x-rc3** (2026-08-14): zixer, WebRTC, pemulihan loss QUIC, perbaikan bug final

<br>

## 0.5.x-rc3 (2026-08-14)

__*Fix:*__

- Setiap engine menjawab handler yang gagal tepat satu kali, dan hanya bila handler meninggalkan pemanggilnya menunggu. Yang dihitung sebagai sudah dijawab kini termasuk fd writer, bukan hanya builder `Response`: `zix.Http1` dan `zix.Http2` dulu hanya melacaknya di `Response.sent`, jadi handler yang menjawab lewat `sendSimpleFD` atau `sendResponseFD` lalu mengembalikan error terbaca oleh engine seolah belum pernah menjawab, dan mendapat response kedua yang menempel di response pertama. Peer yang membacanya melihat satu response diikuti `HTTP/1.1 500 Internal Server Error`, atau HEADERS frame kedua di stream yang sudah dilihatnya tertutup. Kedua engine kini memeriksa fd writer juga, jadi handler dijawab sekali lewat jalur mana pun ia menjawab.

- `zix.Grpc` dan `zix.Fix` melaporkan error yang dulu ditelan oleh send-nya. `res.sendMessage` mengembalikan `void` di keduanya, dan kegagalan build atau peer yang sudah tiada dibuang di dalam engine, jadi handler tidak bisa membedakan pesan yang terkirim dari yang tidak pernah berangkat, dan tidak punya apa pun untuk di-`try` atau di-`catch`. Keduanya kini mengembalikan error union: `try` menyerahkan kegagalannya ke engine, dan handler yang ingin menjawab dengan cara lain menangkapnya sendiri. `zix.Grpc.Response.sendHeaders`, `finish`, `sendCached` dan `serveCached` ikut berubah, dan `zix.Fix` melaporkan `error.ZixFixMessageTooLarge` untuk pesan yang tidak muat di `MAX_MSG_SIZE`.

- `zix.Grpc` dan `zix.Fix` menjawab handler yang mengembalikan error. Dulu keduanya meneruskannya diam-diam (ADR-063, "current wire behavior kept"), jadi caller ditinggal menunggu call yang tidak akan pernah membawa status dan counterparty menunggu pesan yang tidak akan pernah datang. Call gRPC yang ditinggal terbuka kini ditutup dengan `grpc-status 13` (INTERNAL), dan pesan FIX yang gagal di handler dijawab dengan Reject (35=3) yang membawa RefSeqNum dari pesan yang gagal itu. Call yang sudah ditutup handler, atau pesan yang sudah dijawabnya, dibiarkan persis seperti yang handler tinggalkan. Error yang ditelan sendiri oleh handler tetap urusan handler itu di semua engine, engine tidak menambahkan apa pun.

- Enam entry `localbench/http1-*` melaporkan kegagalan send-nya, bukan menelannya. `baseline` dan `upload` mengakhiri render yang gagal dengan `catch return` kosong, yang tidak menjawab apa pun dan meninggalkan client menunggu sampai read timeout. `baseline`, `upload`, `pipeline` dan `json` masing-masing membawa 500 buatan tangan di dalam `catch` pada send yang baru saja gagal, menulis response kedua ke descriptor yang sudah menerima sebagian response pertama. Responder 400 / 404 / 503 bersama di `shared/response.zig` menelannya begitu saja. Semuanya kini `try`, jadi engine menyelesaikan request yang gagal sekali saja, dan upgrade di entry websocket juga `try`: `WebSocket.serve` menulis 101 sendiri, jadi `catch` lama yang menjawab "handshake failed" menempelkan body HTTP ke upgrade yang baru tertulis separuh. Dua jalur tetap `void` karena tidak ada frame handler tersisa untuk dilapori, dan masing-masing menyatakannya di tempat: callback frame, yang berjalan jauh setelah handler-nya selesai, dan jalur completion database di `shared/dbpg.zig`, yang memarkir tulisan yang belum selesai alih-alih menggagalkannya.

<br>

__*Update:*__

- `examples/udp_server_tickrate.zig` dan `examples/udp_client_tickrate.zig` adalah pasangan berbentuk game server di path UDP raw. Client mengirim state-nya kapan saja, server hanya menyimpan state terakhir per client, dan tick loop tetap melakukan broadcast world snapshot ke semua client yang terhubung sekali per tick: `--tickrate` memilih cadence (default 64, 128 rate umum lainnya), `--ip` / `--port` di server dan `--bind-ip` / `--bind-port` / `--server-ip` / `--server-port` di client tetap opsional, setiap flag yang tidak ada memakai default-nya. Engine sendiri tidak mendapat konsep tick: tick loop, registry client, dan pengiriman snapshot semuanya hidup di example. `test-runner-udp-tickrate` menjalankan kedua executable dan ikut `test-runner-all`, memastikan re-broadcast per tick, proses client kedua, dan datagram salah ukuran tidak pernah masuk ke stream.

- Tiga example udp dijalankan sebagai binary hasil build. Header-nya dulu menulis `zig run examples/<file>.zig -- <flags>`, yang tidak mungkin jalan: example meng-import zix, dan hanya build system yang menyambungkan module itu. Setiap komentar usage kini berada di `pub fn main` dan menunjukkan langkah `zig build example-<name>` serta binary terpasang dengan flag-nya, dan kedua server menyalakan `allow_args` sehingga `--ip` / `--port` benar-benar dibaca (flag yang tidak ada tetap memakai default, jadi test runner melihat server yang sama seperti sebelumnya).

- `examples/http1_static_cached.zig` pindah dari port 9077 ke 9039: 9077 sudah milik listener TLS `examples/tls/tls_http1_dual.zig`, jadi kedua example tidak bisa jalan berdampingan. Setiap example kini bind port miliknya sendiri.

- `localbench-run.sh` menaikkan soft limit file descriptor miliknya sendiri sebelum tier pertama jalan, supaya jumlah connection yang diminta memang beban yang benar-benar diterima server. Load generator membuka satu descriptor per connection dan tidak ada satu pun yang menaikkan limit itu sendiri, jadi di mesin yang masih memakai default 1024 setiap tier di atas kira-kira seribu connection sebenarnya mengukur hal lain: `wrk` tetap jalan dengan 1013 connection yang berhasil dibuka dan sisanya dihitung sebagai `Socket errors: connect`, sedangkan `h2load` langsung abort pada connect pertama yang gagal, yang membuat semua profile HTTP/2 di 1024c dan 4096c terbaca nol. Hanya soft limit yang berubah, jadi tidak perlu privilege, dan nilai lama serta nilai barunya dicetak ke log run. `localbench-isolate.sh` menjalankan script ini sebagai child dan ikut mewarisinya. Angka di atas kira-kira seribu connection yang direkam sebelum perubahan ini tidak sebanding dengan angka yang direkam sesudahnya.

- `zix.utils.multipart` menolak body yang tidak bisa dibaca utuh, bukan mem-parse sebagiannya. Body yang terpotong tidak membawa closing boundary, dan parser dulu diam saja lalu mengembalikan field seadanya, yang bagi handler terbaca persis seperti request yang memang tidak membawa field sama sekali. `parse` kini melaporkan `error.ZixMultipartNoBoundary` saat boundary pembuka tidak ada, yang berlaku untuk body kosong, dan `error.ZixMultipartUnterminated` saat sudah ada part tapi closing boundary tidak pernah datang. Urusan ukuran dijawab engine lebih dulu: cek `req.bodyComplete()`, dan `req.bodyReceived()` terhadap `req.body().len`, sebelum mem-parse.

- `zix.utils.multipart` mempertahankan seluruh byte file yang diunggah. Isi part dulu di-trim dari semua byte CR dan LF di awal dan akhir, padahal yang termasuk framing hanya satu CRLF tepat sebelum boundary berikutnya, jadi file biner yang byte awal atau akhirnya kebetulan line terminator kehilangan byte itu dan tersimpan rusak. Kini tepat dua byte framing itu saja yang dilepas. Closing boundary tanpa CRLF di belakangnya juga diterima, bentuk yang banyak dikirim client dan dulu membuat part terakhir hilang, dan teks boundary yang muncul di dalam file tidak lagi memecah file itu jadi dua.

- `zix.utils.multipart` memindai body satu kali. Tiap part dulu memakan dua pencarian dari posisi berjalan sampai ujung body, jadi upload besar dengan banyak part menghabiskan waktu sebanding jumlah part dikali ukuran. Pemindaian kini hanya maju, sehingga biayanya linear terhadap ukuran body apa pun isinya.

- `zix.utils.multipart` tidak menyalin apa pun. Data pada file field dulu diduplikasi ke allocator, jadi sebuah upload memakan dua kali ukurannya sendiri demi salinan yang tidak melampaui masa hidup apa pun: semua slice lain dalam `Field`, termasuk name-nya, memang sudah meminjam body. Kini semuanya meminjam body, dan `deinit` tinggal membebaskan daftar field-nya saja. Apa pun yang harus bertahan setelah handler selesai adalah salinan yang dibuat pemanggil, hal yang selama ini sudah berlaku untuk nama field.

- `zix.utils.multipart` membaca nama field yang ditulis client setelah nama file. Pencariannya dulu mencari `name="` di mana saja dalam Content-Disposition, dan `filename="` mengeja itu di dalam dirinya sendiri, sehingga `filename="a.bin"; name="upload"` melaporkan field itu bernama `a.bin`. Sekarang parameter hanya dicocokkan di tempat sebuah parameter dimulai, jadi urutan mana pun terbaca sama.

- `zix.Http2` dan gRPC tidak lagi melayani request body yang tidak utuh. Peer bisa mendeklarasikan `content-length: 100`, mengirim 40 byte DATA, menyetel END_STREAM, dan 40 byte itu diserahkan ke handler seolah-olah itu request lengkapnya: panjang yang dideklarasikan tidak pernah dicocokkan dengan yang datang, di semua dispatch model. RFC 9113 8.1.1 menyebut request seperti itu malformed, yaitu stream error bertipe PROTOCOL_ERROR, dan kedua engine kini menjawabnya begitu: stream-nya direset dan slot-nya dibebaskan tanpa dispatch. Pengecekannya ada di file baru `src/tcp/http2/stream_body.zig` dan dipakai bersama oleh keempat state machine (blocking dan multiplexed, untuk h2 dan untuk gRPC), jadi https ikut mendapatkannya lewat mux yang sama dengan model cleartext. Body yang tidak mendeklarasikan apa-apa tetap berakhir di titik yang ditentukan END_STREAM, yang merupakan bentuk h2 biasa dan tidak terpengaruh.

- `zix.Http2` dan gRPC menjawab peer yang memutus di tengah request. Stream yang dibuka lalu tidak pernah diakhiri dulu menutup koneksi tanpa satu kata pun, jadi client tidak bisa membedakan request yang ditinggalkan dari crash, timeout, atau koneksi yang putus. Semua model kini mengirim `GOAWAY(PROTOCOL_ERROR)` lebih dulu, disegel ke dalam record di jalur TLS seperti frame lain, dan koneksi yang tidak punya request berjalan tetap ditutup tanpa satu byte pun karena itu memang akhir koneksi yang wajar. Stream yang hanya dipegang oleh response body yang terparkir di flow-control window bukan request berjalan: request itu sudah datang utuh dan utangnya ada di sisi server.

- Request besar lewat https sampai ke `zix.Http2` dan gRPC. TLS session menyusun ulang satu record ke buffer 17408 byte dan mengakhiri koneksi kalau diberi lebih, sementara keempat jalur baca h2 dan gRPC menyiapkan 32 KiB ciphertext lalu menyuapkannya sekaligus. Koneksi yang sepi tidak pernah mengisi satu pembacaan penuh, jadi ini baru terlihat begitu request besar membuat socket-nya sibuk: lewat isi satu record, koneksinya mati begitu saja, tanpa status dan tanpa reset. Setiap jalur kini mengukur pembacaannya dari `Session.readRoom()`, perbaikan yang sama yang sudah dipakai `zix.Http1`, sehingga request yang membentang di beberapa TLS record dilayani utuh baik di `.EPOLL` maupun `.URING`.

- `zix.Http2` membuang request body kelewat besar di `.ASYNC` alih-alih memotongnya. Model blocking menyalin sebanyak yang muat di buffer per stream, membuang sisanya, lalu men-dispatch handler dengan body yang bukan kiriman client dan juga tidak ditandai kependekan. Kini ia menjawab `413` dengan END_STREAM dan membebaskan slot-nya, persis seperti yang sudah dilakukan `.EPOLL` dan `.URING`, jadi ketiga model sepakat dan tidak ada handler yang menerima body yang diam-diam dipendekkan.

- Upload lewat https jalan di `zix.Http1`. Jalur TLS menahan seluruh request, head plus body, di satu buffer per koneksi berukuran tetap, jadi upload yang lebih besar dari itu tidak bisa dilayani: `.EPOLL` dan `.URING` menutup koneksi tanpa status di atas 17251 byte, dan `.ASYNC` lebih parah, menjawab `200` hanya dengan isi satu record pertama (16227 byte) lalu diam-diam membuang sisanya, karena ia membaca satu TLS record dan tidak pernah mengakumulasi. Keduanya kini memakai bentuk yang sudah dipakai event loop cleartext, di file baru `src/tcp/http1/tls_feed.zig`: body yang terlalu besar untuk dibuffer tidak pernah dibuffer, head-nya diparkir, sisa byte-nya dihitung saat datang, dan request-nya dilayani begitu hitungannya mencapai panjang yang dideklarasikan. Buffer membatasi head, bukan upload, jadi memori per koneksi tidak lagi mengikuti ukuran upload, dan upload 20 MiB dilayani di ketiga model. `config.max_request_body` kini juga ditegakkan di TLS, yang sebelumnya diabaikan di semua model, sehingga body yang dideklarasikan kelewat besar dijawab `413` alih-alih diterima atau dibuang, dan peer yang berhenti di tengah dijawab `400`.

- Ada plafon kedua di bawahnya: TLS session menyusun ulang satu record ke buffer 17408 byte dan mengakhiri koneksi kalau diberi lebih, sementara kedua jalur baca http1 menyiapkan 32 KiB ciphertext lalu menyuapkannya sekaligus. Koneksi yang sepi tidak pernah mengisi satu pembacaan penuh, jadi ini baru muncul begitu upload besar membuat socket-nya sibuk. `Session.readRoom()` yang baru melaporkan berapa yang akan diterima satu feed, dan kedua jalur baca mengukur pembacaannya dari situ. `zix.Http2` dan gRPC membaca dengan cara yang sama dan punya batas laten yang sama di jalur request masing-masing, yang tidak disentuh perubahan ini.

- `zix.Http1` menjawab request yang berhenti dikirim peer-nya. Di `.EPOLL` dan `.URING`, body yang sudah dideklarasikan tapi tidak pernah selesai datang dulu menutup koneksi tanpa satu byte pun, jadi client tidak bisa membedakan upload yang ditolak dari crash, timeout, atau koneksi yang putus. Kedua model kini menjawab `400 Bad Request` dengan `Connection: close` lalu membuang request-nya, baik body-nya masih ditampung di buffer maupun sudah di-drain dari socket. Handler di sana tetap tidak pernah dipanggil dengan body separuh, dan itulah arti `bodyComplete()` yang selalu true di kedua model: `.ASYNC` membaca body-nya inline dan memang menjalankan handler dengan apa pun yang sudah sampai, dan dokumentasinya kini menyebutkan model mana melakukan apa, bukan menggambarkan satu model seolah-olah itu perilaku engine-nya. Koneksi yang ditutup peer di antara dua request tidak berutang apa-apa dan tetap tidak dijawab.

- `localbench/` adalah benchmark suite yang tinggal di dalam repository. Delapan belas server zig berdiri sendiri, satu untuk tiap pasangan engine dan dispatch model (HTTP/1.1, varian WebSocket-nya, HTTP/2, gRPC, HTTP/3 dan gateway zixer, masing-masing dalam `.ASYNC`, `.EPOLL` dan `.URING`), semuanya bergantung pada checkout ini lewat path sehingga membangun satu entry berarti membangun source zix lokal. Empat script membungkusnya: `localbench-build.sh`, `localbench-validate.sh` untuk membuktikan sebuah entry menjawab dengan benar sebelum diukur, `localbench-run.sh`, dan `localbench-isolate.sh` untuk run yang sudah dikondisikan tenang sehingga angkanya layak dikutip. Fixture dibaca dari checkout tetangga dan tidak ada yang disalin masuk, dan load generator yang tidak terpasang membuat profil yang membutuhkannya dilewati, bukan menggagalkan run. `localbench/README-en.md` dan `README-id.md` memuat panduannya.

- Logger melaporkan kegagalannya sendiri. Write yang gagal dulu hilang begitu saja dan `.INTR` diperlakukan sebagai akhir, jadi sinyal yang datang di tengah write menghilangkan barisnya. `rawWrite` kini mengulang `.INTR` dan `.AGAIN` serta menjawab dengan errno-nya, sehingga write file yang gagal menangguhkan sink file dan menyebutkan alasannya di stderr, dengan console tetap jalan. Record yang lebih panjang dari buffer dulu dibuang utuh: sekarang disimpan dan ditandai, karena record yang dibuang menghilangkan fakta bahwa ada sesuatu yang terjadi. Pesan kegagalan open dulu tidak menyebut path maupun penyebabnya, menebak "ensure save_path exists" untuk masalah permission, direktori hilang, dan path kepanjangan sekaligus. Sekarang ia mencetak penyebab sebenarnya dan path-nya, dan hasil `mkdirat` tidak lagi dibuang.

- Error yang menggabungkan beberapa penyebab ke satu nama sudah dipisah, dan yang memegang path-nya sekarang mencetaknya. `Tls.Context.init` memisahkan not-found, is-a-directory, too-large, dan unreadable untuk certificate maupun key, jadi masalah permission tidak lagi terbaca sebagai salah ketik. `zix.utils.file.load` sama. `public_dir` yang hilang dipisah dari yang bukan direktori dan yang tidak bisa dimasuki proses, di keempat engine yang memeriksanya. `zix.utils.static_send` memisahkan kegagalan baca disk dari peer yang mati, yang tadinya berbagi `error.BrokenPipe`. `error.ZixInvalidUrl` menjadi lima nama di client http, sse, dan websocket: malformed, skema tidak didukung, host hilang, port tidak valid, path kepanjangan. Balasan control zixer kini membawa path yang dikonfigurasi untuk semuanya.

- jzon menjawab field mana dan byte ke berapa. `JzonUnknownField`, `JzonMissingField`, dan `JzonUnknownEnumValue` tidak pernah menyebut field-nya, dan `JzonTruncated` tidak pernah menyebut posisinya, karena error value tidak bisa membawa keduanya. `jzon.lastFailure()` yang baru bisa, dibaca tepat setelah parse mengembalikan error, dan setiap error yang bisa dijelaskannya menyebutnya di doc comment masing-masing.

- Sisa jalur yang diam kini bersuara. `zix.Http1` dan `zix.Http` menolak port nol di `run()` seperti enam engine lainnya, alih-alih membiarkan port yang terlupa muncul belakangan sebagai kegagalan jaringan. Static cache yang tidak bisa dipasang menyebutkannya alih-alih terlihat persis seperti caching yang memang mati, dan dua notice cache yang sudah ada kini lewat logger yang dikonfigurasi, bukan melewatinya. Handshake TLS yang gagal tercatat di DEBUG alih-alih menutup socket tanpa sepatah kata. `reuseport_cbpf` tidak lagi jadi no-op diam: kernel yang menolak `SO_ATTACH_REUSEPORT_CBPF` dilaporkan sekali per proses, dan grup-nya tetap memakai hash default.

- Listener yang gagal bind kini menyebutkannya dan menghentikan server. Tiap worker shared-nothing melakukan bind di thread-nya sendiri, jadi bind yang gagal hanya mengakhiri thread itu dan tidak lebih: parent melakukan join, tidak melihat apa-apa, dan `run()` mengembalikan sukses sementara prosesnya keluar dengan kode 0 tanpa listening. Port yang sudah dipakai, port 80 tanpa privilege, dan `ip` yang salah semuanya terlihat sama, dan build release tanpa logger tidak mencetak apa pun. File baru `src/multiplexers/listen_report.zig` memberi tiap worker dalam satu grup SO_REUSEPORT satu laporan yang diisi sebelum melayani, dan grup itu menunggu di belakangnya, sehingga server entah listening di semua worker atau gagal di semuanya. Ke-21 bind site di http1, http2, grpc, zix.Http, tcp, fix, dan empat TLS multiplexer kini menjawab dengan `error.Zix<Engine>ListenFailed` dan satu baris yang menyebut alamatnya, penyebabnya, dan berapa worker yang tidak bisa bind. Empat thread accept TLS yang tadinya membuang kegagalannya dengan `catch {}` kini menyebut apa yang mati dan bahwa cleartext masih melayani.

- Baris "listening on" dipindah ke bawah bind di sepuluh file itu. Sebelumnya baris itu dicetak sebelum listener-nya ada, jadi ia mengklaim alamat yang mungkin tidak pernah diambil server.

- Nama error kini membawa prefix product yang memilikinya, sehingga sebuah nama menyebut kegagalan milik siapa sebelum menyebut apa yang gagal. `Zix` di seluruh tree engine, `Zixer` di bawah `src/zixer`, dan tiap package standalone memakai namanya sendiri: `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`. Ini rename yang breaking untuk setiap nama error publik: `error.PortNotConfigured` menjadi `error.ZixPortNotConfigured`, `error.TlsCertFileNotFound` menjadi `error.ZixTlsCertFileNotFound`, dan pemanggil yang men-switch sebuah nama harus ikut menyesuaikan. Error yang dilempar std lewat fungsi yang sama tetap memakai nama dari std (`OutOfMemory`, `WriteFailed`, `ReadFailed`, `EndOfStream`, `BrokenPipe`, `NoSpaceLeft`, `Overflow`, `InvalidSignature`, `CertificateHostMismatch`, `SignatureVerificationFailed`), karena memberi prefix hanya pada raise site lokal akan menyisakan dua nama untuk satu kondisi di error set yang sama.

- Shim `logSystem` tiap engine kini menerima level. Sebelumnya semuanya tercatat sebagai `.INFO`, sehingga kegagalan bind dan baris startup yang sehat tidak bisa dibedakan, dan tanpa logger ia menulis lewat `std.debug.print` di balik gate build debug, sehingga build release tanpa logger kehilangan semua diagnostik. Tiap shim sekarang menerima `Logger.Level` dan, tanpa logger, memanggil `std.log` pada level yang cocok lewat scoped logger. Default level milik std sendiri yang menyaring, `.ERROR` dan `.WARN` bertahan di build release, dan pemanggil yang menyetel `std.options.logFn` bisa mengarahkan atau membungkam semuanya. Aturan yang dipakai pada 125 call site: kegagalan yang dipicu satu remote peer atau satu datagram bukan error tingkat server, jadi event per-peer dan per-paket tercatat di `.WARN` atau lebih rendah sementara bind, listen, accept, dan penolakan config tercatat di `.ERROR`.

- zixer menulis log. Sebelumnya tidak ada logger sama sekali di 66 file, sehingga begitu sebuah site ter-bind executable-nya tidak menghasilkan output runtime apa pun: client bisa melihat 502 sementara operator tidak melihat apa-apa. Key `log_level` baru di main.cfg (`debug`, `info`, `warn`, `error`, default `info`) menggerakkan file log di bawah `logs_dir` dan console sekaligus, dan daemon menyerahkan logger-nya ke tiap site dan tiap worker. Tiap jawaban edge ditulis sekali, dengan status yang memilih level-nya: 5xx tercatat di `.WARN`, 4xx di `.DEBUG` supaya client yang buruk tidak membanjiri log. Notice startup dan kegagalan milik daemon sendiri ikut pindah ke logger, karena command yang menulis ke stdout pada posisi yang ia lacak sendiri dan logger yang append ke stderr akan saling menimpa di bawah `zixer daemon > file 2>&1`.

- Monotonic clock Windows overflow setelah sekitar setengah jam uptime mesin. `zix.utils` dan executor postgrez sama-sama mengubah performance counter menjadi satuan waktu dengan `counter * scale / frequency`, yang mengalikan sebelum membagi, sehingga hasil kalinya keluar dari u64 begitu counter melewati `u64 max / scale`. Windows melaporkan counter 10 MHz, yang menempatkan batas itu di sekitar 31 menit uptime untuk nanosecond dan 21 hari untuk microsecond. Build safe panic dengan `integer overflow` dan menjatuhkan thread pemanggilnya, build release wrap dan melaporkan waktu tempuh yang ngawur. File baru `src/utils/counter_scale.zig` membagi lebih dulu, sehingga perkalian yang tersisa selalu dibatasi oleh frequency, dan executor postgrez memakai bentuk yang sama secara lokal karena module driver tidak bisa meng-import utils milik zix. Kedua query counter juga berhenti membuang status-nya: query yang ditolak menjawab 0 alih-alih membagi dengan pembacaan yang tidak pernah ditulis.

- Tabel `Method`, `Status`, dan `Content` masing-masing menyimpan switch enum-ke-string dua kali: satu `toString` privat di balik `asString`, dan satu `stringFromEnum` publik yang identik. Itu 122 arm duplikat per engine, dan satu-satunya yang menjaga kedua salinan tetap sejalan adalah test yang menegaskan keduanya cocok. `stringFromEnum` kini menjadi satu-satunya switch dan `asString` memanggilnya, jadi kedua penulisan itu tidak bisa berbeda. Tidak ada perubahan bagi pemanggil: kedua nama tetap publik dan mengembalikan hal yang sama seperti sebelumnya.

- Dukungan method HTTP QUERY di kedua engine HTTP/1 (RFC 10008):
    - QUERY bersifat safe dan idempotent seperti GET dan membawa content seperti POST, untuk pertanyaan yang terlalu besar atau terlalu terstruktur untuk muat di query string URL. `Method.Code` mendapat `QUERY` di `zix.Http` dan `zix.Http1`, dan `req.method()` mengembalikannya di keduanya.
    - Sebelum ini, `zix.Http1` mem-parse request QUERY dengan baik lalu melaporkannya sebagai `GET`, karena `enumFromString` menjawab `GET` untuk token apa pun yang tidak dikenalinya, sehingga handler tidak bisa membedakan pertanyaan yang dibawa di content dari GET biasa. `zix.Http` menolak request line-nya mentah-mentah dengan `error.ZixInvalidRequest`, jadi ia tidak pernah sampai ke route sama sekali.
    - Perubahan perilaku: method yang tidak diimplementasikan engine kini menjawab `501 Not Implemented`. `error.ZixUnknownMethod` yang baru hanya muncul saat request line ter-tokenisasi dan hanya method-nya yang tidak didukung, jadi baris yang memang rusak tetap menjawab `400` (RFC 9110 section 15.6.2). `Method.codeFromString` melaporkan tidak ada kecocokan sebagai null, sementara `enumFromString` mempertahankan fallback GET untuk head yang dibangun manual.
    - Response QUERY tidak pernah di-cache. Cache key-nya `hash(method, path, query)` dan tidak membawa content request, jadi dua request QUERY ke satu path dengan body berbeda akan berbagi satu jawaban. Meng-cache response QUERY berstatus MAY di RFC 10008 section 2.7, jadi penyimpanannya ditolak langsung di kedua engine. Hanya jalur penyimpanan yang memeriksa ini, jadi jalur lookup tetap dengan biayanya semula.
    - Empat media type ditambahkan ke kedua tabel content: `application/x-www-form-urlencoded`, `application/jsonpath`, `application/sql`, dan `multipart/form-data`. `application/graphql` sudah ada sebelumnya.
    - Memperbaiki buffer overrun laten di kedua tabel `content.zig`. Lookup-nya menyalin ke huruf kecil di buffer tetap 32 byte sementara `std.ascii.lowerString` meng-assert output-nya muat, dan `application/x-www-form-urlencoded` panjangnya 33 byte, jadi build safe panic dan build release menulis melewati ujung. Batasnya kini `MAX_TYPE_LEN` bernama dengan penjaga panjang yang menolak nilai kepanjangan sebelum penyalinan. Fungsi itu belum punya pemanggil sebelumnya, jadi belum ada yang mencapainya.
    - Breaking: `Content.Type.NA` dihapus dan lookup-nya mengembalikan `?Type`. `enumFromString` menjadi `typeFromString`, dan ia bersama `typeFromHeader` melaporkan tidak ada kecocokan sebagai null. `NA` menjadi string `"n/a"`, yang bukan media type dan bisa sampai ke wire lewat `setContentType(.NA)`, dan ia mewakili tiga hal sekaligus (header tidak ada, type tidak dikenali, nilai kepanjangan). Sisi response sudah membawa `content_type: ?Content.Type`, jadi tidak ada yang butuh sentinel.
    - Baru `src/utils/media_type.zig`: `stripParameters` dan `equalIgnoreParameters`, sehingga `application/sql` dengan parameter charset cocok dengan type polosnya. `Content.typeFromHeader` adalah entry point header mentah yang dibangun di atasnya. Ia tidak pernah memeriksa content, yang dilarang RFC 10008 section 2.1.
    - `zix.Http.Client` tidak bisa mengirim QUERY lewat TCP, karena ia membungkus `std.http.Client` dan `std.http.Method` adalah himpunan tertutup yang lebih tua dari RFC 10008. Ia kini melaporkan `error.UnsupportedMethod` sebelum membuka socket, bukan setelah terhubung. `requestUds` menulis request line-nya sendiri, jadi jalur itu memang membawa QUERY. Client HTTP/2 mengirimnya beserta body, padahal `methodHasBody` hanya menyebut POST, PUT, dan PATCH dan akan mengirim pertanyaan tanpa isi.
    - Kegagalan parse melalui TLS kini menjawab sebelum menutup. `tls_serve.zig` dan `tls_mux.zig` memutus koneksi tanpa status, jadi method yang tidak diimplementasikan atau request rusak melalui https tidak bisa dibedakan dari koneksi mati. Keduanya kini menulis status seperti yang sudah dilakukan cabang 421. Jalur ini belum punya pengujian tingkat wire.
    - Penegakan Content-Type tetap kebijakan handler, bukan kebijakan engine: engine tidak bisa tahu type apa yang diterima sebuah route tanpa config baru, dan method yang jarang dipakai tidak boleh menambah cabang di hot path. `Accept-Query` (section 3) adalah nilai header biasa yang ditulis handler, jadi parser RFC 9651 tidak ditambahkan.
    - Breaking: `Method.codeFromString` kini pencocokan persis dan menjadi satu-satunya tabel method untuk tiap engine. Kedua parser request-line HTTP/1 menyimpan salinan pribadi tabel itu, satu melipat case dan satu tidak, sehingga `query` huruf kecil diterima `zix.Http1` tetapi dijawab 501 oleh `zix.Http`. RFC 9110 section 9.1 menetapkan nama method case-sensitive, jadi kedua engine kini menolaknya. `zix.Http1` sebelumnya menerima method apa pun dalam case apa pun (`get`, `Post`, `delete`), dan kini tidak lagi. Tabel duplikat di `http1/parser.zig` dan `http/parser.zig` dihapus, berikut salinan huruf kecil yang dulu dibuat lookup-nya.
    - `examples/http1_query.zig` (port 9079) dan `examples/http_query.zig` (port 9080) membawa pola sisi handler-nya: peta 400 / 415 / 422 / 406, header `Accept-Query`, dan route yang menerima dua content type tetapi menjawab satu.
    - Baru `tests/runner/checks_query.zig` menjalankan sepuluh kasus terhadap example yang berjalan lewat raw socket, termasuk token `query` huruf kecil yang dijawab 501 oleh kedua engine. Ini pemeriksaan tingkat wire pertama untuk QUERY, dan `zig build test-runner-http1-query` / `test-runner-http-query` serta `test-runner-all` menjalankannya.
    - Cakupan: 86 pengujian unit, perilaku, dan edge baru, termasuk `tests/behaviour/http/query_test.zig`, `tests/behaviour/http1/query_test.zig`, `tests/edge/http/query_test.zig`, dan `tests/edge/http1/query_test.zig`.

    ---

- Body request kini berarti hal yang sama di setiap engine dan dispatch model (14 defect diperbaiki di `zix.Http` dan `zix.Http1`):
    - Baru di kedua request view: `bodyReceived()` dan `bodyComplete()`. Hitungan berasal dari pembacaan yang mengonsumsi body, tidak pernah dari header Content-Length yang bisa dibohongi client, dan flag-nya membedakan upload yang selesai dari yang diputus peer. Sebelumnya, upload yang sama melaporkan batas pengantaran pada `.ASYNC` dan 0 pada `.EPOLL`.
    - Satu decoder chunked bersama di `http1/core.zig` (`chunkedFrame` / `decodeChunkedInBuf` / `readChunkedBody`), sehingga body chunked di-framing identik di ketiga model. Walk-nya memisahkan "belum tiba" dari "rusak" dari "terlalu besar": chunk frame yang malformed kini menjawab `400` dan body chunked melewati buffer `413`, yang dulu keduanya terbaca sebagai "terus menunggu" sampai koneksi penuh dan mati tanpa jawaban.
    - Field config baru `max_request_body` di kedua engine (default 8 MiB, 0 menghapus cek): Content-Length yang dideklarasikan melewatinya ditolak dengan `413` sebelum satu byte body pun dibaca atau dialokasikan, sehingga client tidak bisa membuat worker mengonsumsi byte sebanyak apa pun hanya dengan mengklaim ukuran. Chunked tidak mendeklarasikan panjang di muka, jadi dibatasi body buffer di `zix.Http1` dan tumbuh menuju limit hanya saat byte tiba di `zix.Http`.
    - `.EPOLL` `zix.Http1` kini menunda handler sampai body over-large selesai di-drain, lalu menyajikannya dengan total terhitung, urutan yang sudah dipakai `.URING`. `.ASYNC` memberi handler awal body dan bukan sisa drain, menjaga request yang pipelined di belakang body chunked, dan menutup setelah decode chunked gagal alih-alih salah mem-parse sisa byte body sebagai request berikutnya.
    - `Expect: 100-continue` dijawab di setiap model kedua engine. Dulu hanya `.ASYNC` di `zix.Http1` dan `zix.Http` tidak pernah mengirimnya, sehingga client seperti itu menunggu timeout-nya sendiri di setiap request.
    - `zix.Http`: coding list `Transfer-Encoding` yang berakhir `chunked` dikenali sebagai chunked, `body()` menunggu body tersegmen di fd non-blocking alih-alih memotong di short read pertama, body chunked yang tiba setelah head sampai ke handler alih-alih tiba kosong, dan koneksi yang body-nya tidak pernah dibaca (atau diputus peer) ditutup alih-alih bertahan keep-alive dengan byte body masih di socket.
    - Perubahan perilaku: baris ukuran chunked yang bukan hex kini `error.ZixInvalidChunkedBody` dijawab `400`, yang dulu menghasilkan body kosong dan 200.
    - Cakupan: sekitar 80 tes unit dan edge baru, termasuk suite framing `tests/edge/http1/body_test.zig`.

    ---

- Breaking: dispatch model `.POOL` dan `.MIXED` dihapus (ADR-065):
    - `DispatchModel` kini `ASYNC = 0`, `EPOLL = 1`, `URING = 2` di kedelapan engine. Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported` untuk `.EPOLL` dan `.URING` alih-alih diam-diam turun ke `.POOL`, dan mencatat model mana yang ditolak. Fallback lama mengubah profil throughput, memori, dan latency pemanggil hanya dengan satu baris log sebagai penanda, dan server tanpa logger terkonfigurasi tidak berkata apa-apa.
    - `pool_size` dihapus dari kedelapan config, dan `pool_stack_size_bytes` dari `zix.Fix`. Di `zix.Http2` dan `zix.Grpc`, `pool_size` adalah jumlah worker `.EPOLL` / `.URING` sementara `workers` hanya milik POOL dan MIXED, jadi keduanya dialihkan ke `workers`. Keduanya default 0, jadi perilaku default tidak berubah.
    - 16 berkas `dispatch/pool.zig` dan `dispatch/mixed.zig` dihapus, berikut `ConnQueue`, `WorkerCtx`, `PoolCtx`, dan `AsyncWorkerCtx`.
    - 34 example bernomor per model diringkas menjadi 7 example terpadu, masing-masing memilih model per target secara comptime. Dua leg test-runner ikut hilang: `http1-drain` hanya menyisakan leg URING, dan `grpc-stream` kini berbagi port 9032 dengan `grpc`.
    - Predikat bersama baru `src/utils/dispatch_support.zig`, dibaca di awal setiap `run()` sebelum ia membuka listener atau men-spawn thread, sehingga config yang ditolak tidak meninggalkan apa pun.

    ---

- Setiap fitur kini bekerja di bawah `.ASYNC` di setiap platform yang didukung (ADR-066):
    - Response compression dan response cache menjangkau `.ASYNC`. Keduanya switch threadlocal per worker yang hanya dipasang `dispatch/epoll.zig` dan `dispatch/uring.zig`, sehingga server dengan `compress = true` di `.ASYNC` mengembalikan body tanpa kompresi dan tanpa error sama sekali. Promosi WebSocket milik engine lebih buruk: `core.zig` menerima handoff-nya lalu membuangnya, sehingga koneksi berakhir.
    - Perbaikan: TLS di atas `.ASYNC` rusak di macOS, FreeBSD, NetBSD dan OpenBSD. Enam berkas terpisah `if (windows) ... else <syscall Linux>`, sehingga keempat platform itu jatuh ke cabang Linux dan mengeluarkan nomor syscall Linux. Ia tetap terkompilasi, itulah sebabnya tidak ada sweep cross-build yang menangkapnya. Setiap titik semacam itu kini memakai pemisahan tiga arah `windows` / `linux` / `posix`.
    - HTTP/3 mendapat fallback datagram portable. `runSingle` miliknya sebelumnya hanya mencatat satu baris lalu mengembalikan void di luar Linux, sehingga `run()` melaporkan sukses dan tidak pernah mem-bind socket.
    - Path Unix-domain socket dan channel IPC kini di-resolve menjadi path absolut yang diturunkan sama persis oleh kedua ujung, bukan path relatif (langsung ditolak bind AF_UNIX Windows) atau `/tmp/...` (lokasi yang tidak dimiliki Windows).
    - Substrate bersama baru: `src/utils/fd_io.zig` (read / write / close / readiness blocking di descriptor mentah), `src/utils/socket_pair.zig` (pasangan terhubung, socketpair di POSIX dan loopback di Windows), `src/utils/socket_path.zig`, dan `src/utils/async_cache.zig` (response cache `.ASYNC`, satu per io pool thread, dengan registry dan reclaim karena threadlocal tidak punya destructor).
    - `examples/http1_websocket_uring.zig` dihapus: `http1_websocket.zig` sudah berjalan `.URING` di Linux dan karena itu sudah menjalankan `websocket.pumpRing`. Route echo `/ws` miliknya dipindahkan dan runner-nya menjadi `test-runner-http1-websocket-echo`. Port 9029 dipensiunkan, tidak dipakai ulang.
    - `tests/runner/common.zig:linux_only_labels` kini kosong: kelima puluh dua skenario runner diharapkan lulus di setiap platform. 85 test unit, integration dan edge melepas guard skip `!= .linux`, karena yang membuatnya Linux-only adalah harness test-nya (`socketpair`, `pipe2`, `memfd_create`), bukan perilaku yang diuji.
    - Tidak ada yang menyentuh jalur pemasangan `.EPOLL` / `.URING` di sini: setup cache dan compression per worker mereka tetap sama byte demi byte.

    ---

- Test suite tanpa docker untuk ketiga driver:
    - Step baru `test-behaviour` dan `test-edge` di `postgrez`, `rediz`, dan `prometheuz`, masing-masing menjalankan server in-process di bawah `tests/inproc/` yang berbicara protokol sungguhan. Keduanya tidak butuh container maupun daemon, sehingga ketujuh leg CI menjalankannya, padahal sebelumnya hanya leg Linux yang bisa menjalankan `test-integration` berbasis container.
    - `postgrez` mencakup protokol wire PG v3 termasuk SCRAM-SHA-256 dan varian PLUS ber-channel-binding, auth cleartext, siklus extended query, COPY, LISTEN / NOTIFY, dan handshake TLS 1.3. `rediz` mencakup RESP2 dan RESP3 dengan keyspace nyata, auth ACL, CLIENT KILL, dan TLS. `prometheuz` mendapat cakupan end-to-end pertamanya, dengan satu endpoint HTTP mewakili exporter, receiver remote-write, dan query API sekaligus.
    - Setiap lapisan framing diverifikasi terhadap codec milik driver sendiri, bukan terhadap dirinya sendiri: pesan yang dibangun `src/protocol/frontend.zig` milik driver dibaca ulang oleh parser test, builder test dibaca ulang oleh `src/protocol/backend.zig`, dan server SCRAM berjalan melawan klien `src/auth/scram.zig` yang sungguhan, ketiganya di bawah `src/driver/postgrez/`.
    - `test-integration` dan `test-runner` tidak berubah dan tetap khusus container, dan tidak ada lagi leg CI yang memanggilnya: keduanya menarik image dari registry publik, sehingga gangguan registry membuat leg merah karena sesuatu yang bukan cacat zix. Sekarang keduanya adalah step lokal, tempat PostgreSQL 18 atau Redis 8 sungguhan menjadi intinya. Server in-process tidak menjalankan SQL maupun PromQL, jadi ia membuktikan jalur wire dan cara driver menanganinya, bukan bahwa sebuah query bermakna seperti maksud penulisnya.

    ---

- Penyajian file statis `public_dir` dirombak, dan diperluas ke keempat engine HTTP (ADR-064):
    - Modul baru `src/utils/static_cache.zig`, satu tabel yang dipakai bersama semua worker dan semua engine HTTP dalam satu proses, menyimpan descriptor terbuka sebuah file, ukurannya, dan header 200-nya yang sudah dirender. Request berikutnya hanya membayar satu hash lookup alih-alih open plus stat.
    - Modul baru `src/utils/static_send.zig`, yang memiliki satu tugas: memindahkan rentang byte ke socket. `sendfile` di Linux untuk respons cleartext, positional read plus fungsi tulis engine sendiri untuk yang lain. Zero copy ditolak setiap kali respons dienkripsi atau di-staging, jadi tidak ada jalur yang bisa menaruh plaintext di wire.
    - Dua field config flat baru di `zix.Http`, `zix.Http1`, `zix.Http2`, dan `zix.Http3`: `public_dir_cache_ttl_ms` (default 0) dan `public_dir_cache_max_entries` (default 256). Default 0 berarti tidak pernah di-cache, jadi deployment yang sudah ada berperilaku persis seperti sebelumnya.
    - Sibling terkompresi `.br` dan `.gz` diambil dari disk, di-resolve sekali saat entry dibuat alih-alih diprobe per request, dan setiap varian membawa `Vary: Accept-Encoding`. Tidak ada kompresi on the fly.
    - Range (RFC 7233) disajikan dari file yang di-cache pada `zix.Http`, `zix.Http1`, dan `zix.Http2`, dengan header 206 dirender per request dan 416 untuk range well-formed yang melewati akhir file. Header yang malformed diabaikan dan file utuh yang dikirim, sesuai RFC 7233 bagian 3.1. `zix.Http3` hanya menyajikan file utuh.

    ---

- `public_dir` di `zix.Http2` dan `zix.Http3`, yang sebelumnya tidak punya penyajian file statis sama sekali:
    - `zix.Http2` membingkai file sebagai satu frame HEADERS plus frame DATA yang dibatasi `SETTINGS_MAX_FRAME_SIZE` peer, yang terakhir membawa END_STREAM. Jalur dengan cache dan tanpa cache keduanya dibangun, jadi `public_dir` berperilaku sama baik caching aktif maupun tidak.
    - `zix.Http3` berbeda karena keharusan: body respons HTTP/3 hidup lebih lama dari handler-nya, karena body yang terlalu besar untuk satu paket diparkir di slot send-stream dan dibaca ulang untuk setiap paket dan setiap retransmisi. Karena itu body-nya berasal dari snapshot yang ditahan cache, dan pin cache ditahan selama respons berlangsung. Inilah sebabnya `public_dir_cache_ttl_ms = 0` menonaktifkan penyajian static sepenuhnya di engine itu, bukan sekadar menonaktifkan cache-nya.
    - Pemetaan file (mmap) sudah diukur dan ditolak untuk snapshot itu: menulis ulang file di tempat (yang terjadi saat menyalin build baru ke atas file yang sedang disajikan) mengubah byte di bawah respons yang masih membacanya, dan file yang menyusut akan fault melewati ujungnya sendiri. Snapshot tidak bisa berubah di bawah sebuah respons.

    ---

- Timeout `zix.Http.Client` sekarang diberlakukan, dan setiap read client keluarga HTTP dibatasi:
    - `response_timeout_ms` dan `read_timeout_ms` dulunya disimpan tapi tidak pernah diterapkan, jadi server yang menerima koneksi lalu diam memarkir pemanggil selamanya. Keduanya kini menjaga read di balik readiness poll (`src/utils/socket_poll.zig`): `error.ZixResponseTimeout` saat head response tidak pernah datang, `error.ZixReadTimeout` saat body macet di tengah transfer. Budget 0 mempertahankan perilaku blocking lama byte demi byte.
    - Batas yang sama mencakup jalur request Unix-domain-socket, read handshake dan record client HTTP/2, serta read TLS mentah milik test runner. Client SSE dan WebSocket mendapat dua field config yang sama, membatasi head response dan setiap read event / frame berikutnya.
    - `read_timeout_ms` hanya mencakup body Content-Length: body chunked atau close-delimited tidak punya jumlah byte untuk mengakhiri loop, jadi tetap pada read tanpa batas dan hanya `response_timeout_ms` yang berlaku.
    - Test runner mencoba ulang check yang gagal dengan `ResponseTimeout` / `ReadTimeout`: check itu mengembalikan error, jadi cleanup-nya berjalan dan tidak ada server yatim menahan port, itulah yang membuat retry aman.
    - Diperbaiki sekalian: read dan write raw descriptor client HTTP/2 memakai nomor syscall Linux di setiap platform non-Windows, dan macOS plus ketiga BSD langsung mematikan proses seperti itu. Kedua jalur kini melewati `src/utils/fd_io.zig`, three-way split `windows` / `linux` / `posix` bersama.

<br>

- `recv_timeout_ms` client `zix.Udp` sekarang berlaku di Windows:
    - `receiveFeedback` sebelumnya jatuh ke blocking receive di Windows, jadi client yang menunggu peer yang diam tidak pernah timeout (ini sumber hang CI Windows). Receive sekarang dijaga readiness poll berbasis AFD yang sama dengan client keluarga TCP, jadi `error.ZixRecvTimeout` berlaku di semua platform.
- Step build test-run diberi nama untuk diagnostik `--summary all`:
    - `testRunStep` di `zix-build-tests.zig` sekarang menandai setiap Run step tes integration / behaviour / edge dengan path sumbernya (`run.setName(src)`), jadi `zig build <step> --summary all` menunjukkan file mana yang sedang pending atau masih berjalan, bukan label generik `run test`. Tidak ada perubahan build-command atau eksekusi tes.
- Engine baru `zix.Webrtc`, sebuah peer WebRTC (ADR-067):
    - Browser tidak bisa membuka socket mentah, dan WebRTC satu-satunya transport yang ia tawarkan ke server yang memberi pengiriman tidak reliabel, pilihan urutan per channel, serta audio dan video. `zix.Webrtc.Server.init(handler, config)` menjawabnya, dengan bentuk config datar, `DispatchModel`, dan `Tls.Context` yang sama seperti engine lain.
    - Semuanya datang di satu port UDP lalu dipilah dari byte pertamanya (RFC 7983): ICE connectivity check di atas STUN (RFC 8445 / 8489), handshake DTLS 1.2 (RFC 6347), association SCTP beserta data channel-nya (RFC 9260 / 8831 / 8832), dan opsional media SRTP (RFC 3711 / 5764). Offer dan answer SDP (RFC 8866 / 8829) menegosiasikan semuanya. Ditulis dari RFC di atas `std.crypto`, tanpa OpenSSL dan tanpa C WebRTC library.
    - Tiga event sampai ke handler: `CHANNEL_OPEN`, `CHANNEL_CLOSED`, dan `MESSAGE`. Handler menjawab lewat `ctx.send`, `ctx.broadcast`, `ctx.openChannel`, `ctx.close`, dan `ctx.channelCount`. Payload `MESSAGE` dipinjam selama panggilan itu saja dan mati pada panggilan berikutnya.
    - Forwarding media mati secara default. Dengan `carry_media` menyala, server menjadi selective forwarding unit: paket dibuka sekali dengan kunci pengirim, header RTP-nya ditulis ulang untuk tiap penerima, lalu disegel kembali dengan kunci masing-masing penerima. Tidak ada yang didekode, tidak ada codec di dalam engine. RTCP dijawab, bukan diteruskan, karena sebuah report menamai stream dengan identifier sebelum penulisan ulang. Server meminta keyframe ke sumber ketika penerima baru diterima, karena tidak ada apa pun di browser yang memintanya mewakili penonton.
    - Ketiga dispatch model tersedia: `.ASYNC` menjalankan satu worker di setiap platform, `.EPOLL` dan `.URING` menjalankan satu worker SO_REUSEPORT per core di Linux. Sengaja tidak ada knob steering CPU, berbeda dari UDP raw dan HTTP/3: satu peer WebRTC adalah 4-tuple-nya, dan steering berbasis CPU penerima akan memecah satu sesi ke dua worker di tengah handshake. `max_peers` dihitung per worker, jadi N worker menampung sampai N kali nilai itu. Jangkauan `ctx.broadcast` adalah satu worker.
    - `run()` memvalidasi sebelum bind: `error.ZixPortNotConfigured`, `error.ZixIceCredentialsRequired`, `error.ZixIceCredentialsInvalid`, `error.ZixTlsRequired`, `error.ZixUnsupportedCertificateKey` (kuncinya harus ECDSA P-256, karena satu-satunya suite DTLS 1.2 di sini adalah ECDHE-ECDSA), dan `error.ZixDispatchModelUnsupported` di luar Linux.
    - `accept_any_peer_ice_ufrag` baru dan mati secara default. Browser menarik ufrag ICE baru untuk setiap peer connection, jadi tanpa flag ini setiap check dari browser ditolak dengan 401. Menyalakannya menyisakan `ice_password` sebagai satu-satunya gerbang, yang memang sudah begitu efeknya dengan satu set credential milik server.
    - Delapan example di port 9081 sampai 9088, empat di antaranya digerakkan browser: relay signalling WebSocket, server STUN binding, echo data channel, pasangan zix ke zix, chat room, transfer berkas, broadcast forwarding media, dan panggilan video mesh. Buka halaman browser lewat alamat jaringan mesin, bukan `localhost`, karena browser tidak mengumpulkan candidate loopback dan tidak akan memasangkannya.
    - DTLS 1.2 mendarat di `src/tls/` dengan prefix datar `dtls_`, bersebelahan dengan kode TLS 1.2 dan 1.3 yang primitifnya dipakai bersama: record layer dengan anti-replay, fragmentasi handshake dan perakitan ulang yang aman terhadap tumpang tindih, cookie HMAC stateless, state machine retransmit, ekspor keying material RFC 5705, ekstensi `use_srtp` RFC 5764, plus driver sisi server dan sisi client. Ia tidak memegang public surface terpisah.
- Baris hasil test runner sekarang menyebut example yang dijalankannya:
    - Sebuah check melapor sebagai `zix-example-<file>-<arch>-<os>`, bukan label pendek, jadi satu baris menyebut berkas yang bisa dibuka pembaca, sama seperti yang sudah dicetak suite driver. Namanya disusun di `tests/runner/report_name.zig` (std saja, dengan step test sendiri), karena runner membangun salinannya sendiri untuk tiap example alih-alih menjalankan binary yang terpasang. `--only` menerima label pendek maupun nama yang dicetak.

<br>

- Executable baru `zixer`, proxy gateway yang digerakkan config dan dibangun di atas engine zix:
    - Sebuah service dipasang di belakangnya dengan menulis satu file teks, bukan dengan mengubah service-nya. Satu daemon memegang banyak site yang saling bebas, satu site per file `.cfg`, masing-masing dengan port dan engine sendiri. `zig build zixer` menghasilkan `zig-out/bin/zixer-<triplet>-<optimize>`, dan ia tidak punya versi sendiri: `zixer version` melaporkan versi paket, jadi satu binary menyebut build engine tempat ia dipotong.
    - Command: `init` menyiapkan root dir, `status` memvalidasi tiap config dan keluar dengan kode 1 pada fault apa pun, `list` menyebut file site, `start` / `stop` / `restart` bekerja pada satu site lewat unix control socket, dan `daemon` / `daemon stop` menjalankan serta mengakhiri proses yang memegang listener. `start` pertama menyalakan daemon ketika socket-nya diam. Site yang sedang berjalan tidak pernah mengambil hasil edit dengan sendirinya, jadi `restart` adalah yang dipanggil hook renewal certificate setelah file barunya mendarat di disk.
    - Lima edge, dipilih oleh key `engine`: `http1` (SSE, tunnel websocket rfc 6455, dan file static), `http2` (sniff prior-knowledge atau ALPN, dengan extended CONNECT rfc 8441 dijembatani ke backend websocket h1), `grpc` (h2 di kedua leg supaya trailer selamat melewati hop), `http3` (QUIC dan HTTP/3 diterminasi di zixer), dan `udp` (forward datagram per flow, satu socket ephemeral per alamat client). Setiap engine kecuali `udp` me-re-originate: framing client diurai lalu pesan upstream dibangun baru, jadi byte mentah client tidak pernah disambung langsung.
    - TLS diterminasi di edge lewat stack TLS zix, dengan daftar ALPN diambil dari engine site dan `Host` yang tidak dicakup certificate dijawab 421. Leg upstream tetap cleartext, jadi tidak ada yang di belakang gateway perlu certificate. Renewal http-01 dijawab dari `acme_webroot` atau direlay lewat `acme_proxy`, dan `force_https` bersama `redirect_host` memindahkan request cleartext ke origin https (301 untuk GET dan HEAD, 308 untuk metode lain, jadi pengulangannya tidak pernah membuang body). Keduanya berjalan di listener pendamping port 80 yang di-bind sebuah site TLS di samping listener-nya sendiri, dan kegagalan bind di sana menggagalkan seluruh `start` alih-alih membiarkan renewal rusak diam-diam.
    - File static per site lewat `public_dir`, `public_prefix`, dan `spa_fallback`, dengan sibling terkompresi `.br` dan `.gz` dicek terhadap `Accept-Encoding`. `public_dir_cache_ttl_ms` menjaga file itu tetap terbuka antar request, memakai tabel yang sudah dibangun `zix.utils.static_cache`, jadi satu file memakan satu descriptor untuk daemon, bukan satu per accept loop. Cache ini tidak pernah bisa menggagalkan request: apa pun yang tidak bisa ia jawab jatuh ke open biasa.
    - Upstream dipilih round-robin dengan pengecekan ketersediaan O(1), dan kegagalan connect menandai sebuah backend turun selama window cooldown yang dicek ulang saat pemilihan, jadi tidak ada thread probe dan tidak ada health check. Koneksi keep-alive yang idle di-cache per upstream dan dituakan oleh satu thread latar per site. `Proxy-Status` rfc 9209 ikut di tiap kegagalan yang dibuat gateway sendiri, jadi 502 yang ia tulis terbaca berbeda dari 502 yang dikirim upstream.
    - Dibatasi di kedua leg. `client_timeout_ms` dan `client_conn_limit` membatasi berapa lama satu pertukaran client boleh berjalan dan berapa koneksi client yang dilacak sebuah site, di mana koneksi yang lewat budget-nya dipotong dari thread sweeper lalu dijawab 408, dan koneksi yang lewat plafonnya ditolak 503 sebelum ia mengirim satu byte pun. `upstream_timeout_ms` membatasi tunggu terhadap backend yang diam, `upstream_connect_timeout_ms` membatasi satu percobaan connect, dan `upstream_idle_ttl_ms` membatasi berapa lama koneksi backend yang tidak dipakai disimpan. `process_limit`, `process_queue_len`, dan `process_queue_timeout_ms` adalah katup beban di depan backend, dan pertukaran berumur panjang (sebuah websocket, stream SSE, stream grpc) mengembalikan slot-nya saat handover alih-alih memakunya selama umur socket.
    - Dua blok `[section]` opsional di akhir file site, `[response_headers]` dan `[request_headers]`, menambahkan header di leg client dan di leg upstream. Sebuah nilai boleh menyebut `$client_ip`, `$scheme`, atau `$host`, dan scheme-nya berasal dari setting `tls` milik site itu sendiri, bukan dari apa pun yang diklaim client.
    - Validasi datang sebelum apa pun di-bind. Key yang tidak dikenal, nilai yang salah, atau key yang tidak bisa berlaku pada engine ini ditolak dengan fix hint, bukan default diam-diam. Nilai numerik menerima integer math (`16 * 1024`), di mana pembagian yang tidak pas adalah fault, bukan pemotongan. Fault dikumpulkan alih-alih dilempar satu per satu, jadi satu laporan menunjukkan seluruh masalah dalam satu file sekaligus, dan `status` membaca parser yang sama dengan yang dibaca daemon.
    - `workers` menjalankan beberapa accept loop per site, masing-masing dengan listener, pool upstream, dan cache idle sendiri, dan batas idle milik site dibagi di antara mereka supaya backend tidak kehilangan lebih banyak kapasitasnya hanya karena edge menjalankan lebih banyak loop. Di Windows jumlahnya 1, karena address reuse di sana adalah pengambilalihan, bukan penggabungan.
    - Celah yang disebutkan, ditulis di dokumentasi alih-alih dibiarkan ditemukan sendiri: tidak ada yang menulis ke `logs_dir`, `dispatch` divalidasi dan dilaporkan tetapi tidak ada yang membacanya, tidak ada routing per path, rate limit, atau cache response, dan `main.cfg` dibaca sekali per daemon alih-alih di-reload.
    - Dokumentasinya adalah `docs/zixer/README-id.md`, `how-to-use-id.md`, `config-id.md`, `hld-id.md`, dan `lld-id.md`, masing-masing berpasangan dengan versi Inggris. 15 demo yang bisa dijalankan ada di `examples/proxies/`, satu upstream plus satu config site masing-masing, dan `zig build zixer-test-runner-all` menyalakan semuanya di root sementara masing-masing lalu menggerakkannya end to end. `zig build zixer-unit-test` adalah suite in-process dan merupakan step terpisah dari milik zix sendiri, karena zixer memegang file build-nya sendiri.

<br>

- Identifier di test suite diganti nama: setiap nama satu sampai empat karakter yang maknanya harus ditebak sekarang menyebut isinya:
    - `tests/runner/all_runner.zig` mendeklarasikan ke-55 trampoline check-nya sebagai `fn f`, nama yang tidak membawa apa pun. Sekarang `fn call`, bentuk yang sudah dipakai `tests/zixer/all_runner.zig`. Variabel lokal scheduler mengikuti: `c` jadi `check`, `Fut` / `futs` jadi `CheckFuture` / `futures`, `fill` jadi `path_idx`, dan `cpu` jadi `cpu_count` karena isinya jumlah, bukan sebuah core.
    - Tiap test block HTTP/3 menyimpan helper hex privat bernama `fn h`. Sekarang `fn hexBytes` di semua 15 berkas dan 167 titik panggil. Stub handler di dalam test block (`fn h`, `fn f`) jadi `fn handle`, dan factory handler `const H` di `src/tcp/http2/router.zig` jadi `Handlers`.
    - Sekitar 48 berkas di bawah `tests/` memuat variabel lokal yang harus dilacak balik ke baris deklarasinya: `t` jadi `server_thread`, `sa` jadi `server_addr`, `al` jadi `allocator`, `rd` / `wr` jadi `reader` / `writer`, `fh` jadi `frame`, `hbuf` jadi `header_buf`, `hdec` / `enc` jadi `hpack_decoder` / `hpack_encoder`, `flen` jadi `flight_len`, `rnd` jadi `random_bytes`, `fba` jadi `pem_fixed_buf`. Test client HTTP/3 mendapat sapuan terdalam, termasuk `w` jadi `writer`, `u8v` / `u16v` jadi `writeU8` / `writeU16`, serta `pp` / `fl` / `cl` / `rp` jadi `payload_len` / `fields_len` / `content_len` / `payload_pos`.
    - Singkatan domain yang terbatas dan sudah umum tetap pada panjang naturalnya dan tidak disentuh: `io`, `ctx`, `buf`, `fd`, `len`, `pos`, `conn`, `req`, `res`, `gpa`, `cfg`, dan istilah QUIC `sid`, `scid`, `dcid`.
    - Hanya penamaan, tidak ada perubahan perilaku. Diverifikasi dengan test suite penuh, seluruh 55 protokol runner, dan 13 demo proxy zixer.

<br>

## 0.5.x-rc2 (2026-07-27)

__*Update:*__

- Breaking: `zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Fix` mendapat trio Request/Response/Context dan idiom Router eksplisit (ADR-063), menyamai `zix.Http1` (ADR-062) dan `zix.Http3`:
    - `HandlerFn` sekarang `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void` pada setiap engine. `zix.Http2` sebelumnya tidak punya trio sama sekali (argumen mentah `method`/`headers`/`body`/`fd`/`sid`), `zix.Grpc` punya headers mentah plus `GrpcContext`, `zix.Fix` punya fields mentah plus `FixContext`. `Request` dan `Response` adalah view/builder tipis atas writer wire yang sudah ada di tiap engine (keluaran byte-identical), `Context` membawa `io`, allocator stack arena per-request (`FixedBufferAllocator`, tanpa pemanggilan heap), dan helper timeout `withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut`.
    - Router: `Server.init(handler, config)` di mana-mana, `handler` dibangun via `zix.ENGINE.Router(&[_]zix.ENGINE.Route{...}).dispatch`. `zix.Fix.Server.init` menerima `handler: ?HandlerFn`, `null` mempertahankan mode echo-only yang sudah ada. `zix.Grpc.Server.init` adalah satu pengecualian: ia menerima `Router(&routes)` itu sendiri, bukan `.dispatch`, karena engine membaca `Route.is_server_streaming` sebelum dispatch untuk memilih sync-inline vs task-spawn, dan pointer handler polos tidak bisa membawa metadata itu (terukur berbeda jauh RPS per-core antara kedua jalur sebelum diputuskan).
    - `zix.Http3` mendapat `Context` dan error channel `anyerror!void` (`Request` / `Response` sudah ada sebelumnya), `Server.init(handler, config)` sudah ada sebelumnya dan tidak berubah.
    - Kebijakan wire saat handler error: `zix.Http`, `zix.Http2`, `zix.Http3` otomatis mengirim satu 500 saat handler error dan belum ada yang terkirim. `zix.Grpc` dan `zix.Fix` meneruskan error secara diam-diam, perilaku wire saat ini dipertahankan.
    - Field config baru per engine: `handler_timeout_ms` pada `Http2ServerConfig` dan `Http3ServerConfig` (keduanya sebelumnya tidak punya konsep timeout), diseed ke `Context.deadline_ns` saat dispatch.
    - Migrasi: setiap example dan tes integration/edge/behaviour di kelima engine diperbarui ke bentuk pemanggilan baru. `zig build test-all` dan `zig build examples` hijau pada `zig-0.16` dan `zig-0.17`.

    ---

- Dukungan cross-build platform, example dengan suffix target, tes dan runner yang sadar platform:
    - Seluruh tree (module, examples, keempat test suite, test runner, dan driver postgrez / rediz / prometheuz) ter-build dengan Zig 0.16.x dan Zig 0.17.x untuk x86_64-linux, x86_64-windows, aarch64-macos, aarch64-linux, x86_64-freebsd, x86_64-netbsd, dan x86_64-openbsd. Socket I/O Windows menumpang shim ntdll kecil (`src/utils/windows_io.zig`: NtReadFile / NtWriteFile / NtClose plus AFD partial-disconnect), BSD mendapat TCP_NODELAY yang diresolusi comptime (`std.posix.TCP` bernilai void di sana pada Zig 0.16), dan setiap jalur Linux-only (loop EPOLL / URING, CPU affinity, madvise, batching raw UDP) dijaga comptime. Di target non-Linux `.EPOLL` / `.URING` tetap fallback ke `.POOL`. Windows menurun di tempat platformnya tidak punya primitif: file logging pada logger ditangguhkan (console logging tetap jalan), timeout berbasis poll menjadi blocking read, tanpa CPU pinning, UDS dan raw UDP mengembalikan error runtime.
    - Binary example yang terinstal dinamai `example-<name>-<arch>-<os>` (driver: `<driver>-example-<name>-<arch>-<os>`), jadi hasil build per target hidup berdampingan di `zig-out/bin`.
    - Test suite sadar platform: pada `-Dtarget` foreign setiap suite ter-compile dan eksekusi dilewati dengan warning, di host non-Linux tes EPOLL / URING mencetak warn lalu skip, dan tes berpijak syscall Linux skip tanpa pesan.
    - `aarch64-linux` tetap compile-only meski host memiliki qemu-user terdaftar di `binfmt_misc` (yang jika dibiarkan akan mengeksekusi binary hasil cross-compile secara transparan): step tes bergantung langsung pada compile artifact, bukan pada Run step, jadi cakupannya deterministik terlepas dari konfigurasi emulator host.
    - Runner sadar platform: target foreign meng-compile runner beserta server-nya lalu lolos dengan warning, dan di host non-Linux setiap skenario EPOLL / URING melaporkan `PASS <label> (WARN: ... Linux-only, scenario skipped ...)`.
    - `scripts/build-all-targets.sh` menyapu setiap opsi build zix dan ketiga driver di ketujuh target, mencatat leg yang gagal alih-alih berhenti, dan melaporkannya di akhir.

    ---

- Breaking: handler hot path `zix.Http1` menjadi trio Request/Response/Context (ADR-062):
    - `HandlerFn` kini `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void`, menggantikan raw `fn(head: *const ParsedHead, body: []const u8, fd: fd_t) void`, menyamai bentuk `zix.Http`. `Request` adalah view zero-copy, `Response` mendelegasikan ke fd writer yang sudah ada dan byte-identical, `Context` membawa `io`, arena per-request, fd, dan hook deadline. `core.invokeHandler` membangun trio per request dan menulis tepat satu 500 saat handler error tanpa sudah mengirim response, di semua dispatch model termasuk jalur buffer TLS.
    - Penamaan `send*` kanonis di kedua engine: `zix.Http1` mengganti nama `json` / `text` / `raw` menjadi `sendJson` / `sendText` / `sendRaw` dan memperoleh `sendNoContent`, `sendFromCache`, `sendCached`, `sendNegotiated`, `sendStream`, `setKeepAlive`, `addHeader`. `zix.Http` mengganti nama `noContent` / `serveCached` / `stream` menjadi `sendNoContent` / `sendFromCache` / `sendStream` dan memperoleh `sendText`, `sendRaw`. `Request.param` menjadi `pathParam` pada `zix.Http1`, kedua engine memperoleh `queryParams`, `pathSegments`, `body()`, `fromRaw`, `keepAlive`. Permukaan trio bertipe di kedua engine: `setStatus(Status.Code)`, `setContentType(Content.Type)`, `req.method()` mengembalikan `Method.Code`.
    - `initRaw` milik `zix.Http1` dan hook `RawFn` dihapus, `Server.init(handler, config)` adalah satu-satunya pintu. `middleware.zig` dihapus dari `zix.Http` (komposisi wrapper comptime, `examples/http_middleware.zig` / `examples/http1_middleware.zig`, adalah idiom middleware di kedua engine sekarang).
    - Migrasi: ganti nama call site `json` / `text` / `raw` / `noContent` / `serveCached` / `stream` / `param` sesuai pemetaan di atas, ganti handler raw `fn(head, body, fd) void` dengan signature trio, dan hapus pemakaian `initRaw` apa pun. Semua handler in-src, tiap `examples/http1_*.zig` dan `examples/tls/tls_http1_*.zig`, serta test integrasi http1 sudah dimigrasikan sebagai bagian dari perubahan ini.

    ---

- Encoder gzip cepat untuk response dinamis (`compression.flate_fast`):
    - Encoder gzip in-tree (LZ greedy di atas hash table single-probe, coding fixed-Huffman, tabel kode bit-reversed yang di-precompute, akumulator 64-bit) untuk body di bawah 64 KiB, beberapa kali lebih cepat dari matcher std dengan rasio mendekati level tercepat std. Output adalah gzip RFC 1952 standar, teruji round-trip terhadap decoder std termasuk input kosong, incompressible, seragam, dan mendekati cap.
    - `sendGzipFD` `zix.Http1` otomatis memakai jalur ini untuk body di dalam cap, body lebih besar tetap lewat jalur `std.compress.flate`. Tidak ada perubahan API.
    - Pada isolate bench lokal, cell json gzip dinamis naik dari ~35K menjadi 154-173K pada 512/4096/16384 koneksi.

    ---

- Latency jalur kirim `zix.Http1` dan render di tempat:
    - Intra-batch submit `.URING`: saat men-dispatch batch completion yang dalam (128 completion atau lebih), SQE send yang ter-stage didorong ke kernel tiap 16 completion alih-alih hanya setelah seluruh batch, sehingga response awal langsung berangkat tanpa menunggu dispatch semua request setelahnya. Batch dangkal melewati stride ini. Pada isolate bench lokal ini mengangkat cell json render-dinamis 4-5% dan cell pipelined serta baseline 4096-koneksi 2-5%, dengan cell 512-koneksi tidak berubah.
    - Wakeup coalescing adaptif `.URING`: loop worker yang panas menunggu hingga 32 completion per enter (wait_nr = setengah reap terakhir, turun ke 1 saat beban mereda) dengan SQE timeout 20 mikrodetik sebagai penjaga stall, sehingga kedatangan yang tersebar berhenti membangunkan worker sekali per completion. Loop yang dingin berperilaku persis seperti sebelumnya.
    - Jalur cepat accept `.URING`: SQE recv koneksi yang baru di-accept langsung di-submit di dalam handler accept alih-alih setelah sisa batch completion di-dispatch, memangkas accept-to-first-byte di bawah churn koneksi (p99 api-4 turun sekitar 30% lokal).
    - `responseReserve(fd, max_body)` / `responseCommit(fd, status, content_type, body_len)`: handler yang membangun body secara dinamis bisa me-render langsung ke buffer response sink, jadi byte body ditulis tepat sekali (tanpa buffer scratch di handler, tanpa salinan staging) dan engine membangun header sederhana tepat di depannya. Reserve yang ditolak (batch pipelined sedang berjalan, region tidak muat) tidak men-stage apa pun dan handler jatuh kembali ke `writeAllFD`. Berlaku di `.URING`, `.EPOLL`, dan jalur capture TLS.
    - Short send `.URING`: jendela ter-stage kini maju di tempat (`staged_off`) alih-alih menggeser sisa ke depan buffer.

    ---

- Lane DB engine-worker: `zix.Http1` `.URING` mendapat external fd watch dan `postgrez` mendapat `dispatch.Line`:
    - `zix.Http1.uringWatchFd(fd)` meng-arm watch readable multishot untuk fd asing (socket driver) di ring milik worker, dan `zix.Http1.setExternalHandler(cb)` mendaftarkan callback per-worker yang berjalan di thread worker. Engine mempertahankan watch (multishot yang lapsed di-re-arm selama fd hidup), dan submission queue yang penuh mem-park arm ke process queue, sehingga watch tidak pernah hilang selama parking punya ruang. Engine `.URING` lain mengabaikan op completion baru ini.
    - `postgrez.dispatch.Line`: pipeline satu-koneksi tanpa reactor (open, submit, flush, pump, pending) untuk pemanggil yang memiliki event loop sendiri. submit men-stage, pemanggil flush sekali per batch (pump juga flush) sehingga banyak request keluar dalam satu write, pump membaca dan mengantar reply ter-frame sesuai urutan submit, dan peer yang tertutup muncul sebagai `error.ConnectionClosed`. `Transport` tidak berubah.
    - Bersama-sama, worker server bisa memiliki koneksi database pipelined di ring-nya sendiri, sehingga reply di-decode, dirender, dan ditulis di core yang memiliki socket klien, tanpa handoff antar thread.

    ---

- `zix.Http1` `.URING`: body request oversized (lebih besar dari receive buffer) kini di-drain sebelum handler-nya berjalan, dan byte yang diterima dihitung lalu diekspos sebagai `Request.bodyReceived()`:
    - Sebelumnya handler berjalan lebih dulu dengan slice body kosong (response bisa keluar sebelum body selesai tiba) dan sisa yang di-drain dibuang tanpa dihitung, sehingga `head.content_length` adalah satu-satunya ukuran yang bisa dilaporkan handler. Engine kini menghitung setiap byte yang di-drain, menunda handler sampai drain selesai, dan `req.bodyReceived()` mengembalikan total terhitung. Pada semua dispatch model nilainya sama dengan `body().len` saat body muat di buffer. Request body kecil menempuh jalur yang identik seperti sebelumnya, `.EPOLL` dan model thread mempertahankan urutan lamanya.

    ---

- Dua driver database internal, `postgrez` (PostgreSQL) dan `rediz` (Redis), murni Zig std saja, tanpa dependency C:
    - `postgrez`: wire protocol 3.2 dengan fallback 3.0 di tempat (PostgreSQL 15 minimum), encoding nilai binary-first dengan fallback text per parameter, prepared statement, query pipelining, `Executor` batching, `Pool` thread-safe, auth SCRAM dan SCRAM-PLUS (channel binding) serta cleartext, TLS 1.3, streaming COPY, LISTEN dan NOTIFY.
    - `rediz`: RESP3 lewat HELLO dengan fallback RESP2 di tempat (Redis 7 dan 8), helper nilai bertipe plus jalan pintas raw command, command pipelining dan jalur deferred write-behind, `Pool` thread-safe, TLS 1.3.
    - Kedua driver berbagi config `dispatch_model`: `.ASYNC` (jalur pooled / executor, default) atau `.EPOLL` / `.URING` (`Transport`, dispatch termultipleks satu-thread yang mem-pipeline banyak request per koneksi, cleartext saja).
    - Dokumentasi: `docs/driver/postgrez` dan `docs/driver/rediz` (README, HLD, LLD, referensi config, Inggris dan Indonesia).

    ---

- `prometheuz`, driver internal ketiga (Prometheus dan node-exporter), murni Zig std saja, tanpa dependency C:
    - Parser Prometheus text exposition format 0.0.4 (scrape), `Scraper` poller latar belakang, push `remote_write` (protobuf plus snappy), query PromQL instant dan ranged, dan registry metrik yang ditulis aplikasi (`Counter`, `Gauge`) untuk nilai yang tidak pernah berasal dari scrape.
    - Client HTTP/1.1 minimal milik sendiri, cleartext saja: berbeda dengan `postgrez`/`rediz` tidak ada transport pooled atau multipleks, GET/POST dengan body response `Content-Length` atau chunked adalah satu-satunya transport yang dibutuhkan driver ini.
    - Dokumentasi: `docs/driver/prometheuz` (README, HLD, LLD, referensi config, Inggris dan Indonesia).

<br>

__*Fix:*__

- Penyambungan `send_timeout_ms` client (`zix.Uds`, `zix.Tcp`, `zix.Fix`):
    - Field config `send_timeout_ms` sisi client diterima tetapi tidak pernah ditegakkan (helper peninggalan yang menyetel `SO_SNDTIMEO` ada tetapi tidak pernah dipanggil). `UdsClient.sendMsg`, `TcpClient.sendMsg`, dan `FixClient.sendMessage` kini melakukan poll pada socket untuk kesiapan tulis sebelum mengirim dan mengembalikan `error.SendTimeout` saat expired, pendekatan yang sama yang sudah dipakai untuk `recv_timeout_ms` (`SO_RCVTIMEO` tidak dipakai: `std.Io.Threaded` panic pada `EAGAIN`). `FixClient` juga memperoleh field `send_timeout_ms` itu sendiri, sebelumnya tidak dibawa sama sekali dari config-nya.

    ---

- Koreksi dokumentasi di `docs/` dan README:
    - `zix.Http`: dokumentasi mengklaim tidak ada dukungan TLS ("proxy-terminated by design"), TLS sudah tersedia sejak ADR-053.
    - `zix.Grpc`: dokumentasi tidak menyebutkan response cache (ADR-036) maupun dual listener TLS (ADR-060), keduanya sudah diimplementasikan.
    - `zix.Uds`: dokumentasi (dan perbandingan pada dokumentasi `zix.Tcp` sendiri, serta ADR-022) mengklaim frame UDS memakai little-endian, padahal memakai big-endian, sama seperti TCP, dan selalu begitu (ADR-010).
    - `zix.Fix`: dokumentasi dan sebuah contoh terpakai memakai nama field `connection_timeout_ms`, field sebenarnya adalah `conn_timeout_ms`.
    - `zix.Tcp`: dokumentasi memakai `max_msg_len`, field sebenarnya adalah `max_recv_buf`. `docs/lld-tcp-en/id.md` juga sebelumnya tidak memuat model dispatch `.EPOLL` / `.URING` sama sekali.

<br>

## 0.5.0-rc1 (2026-07-15)

__*Update:*__
- Zig 0.17 (eksperimental) support: satu source tree build di Zig 0.16.x dan 0.17.x, sedikit divergensi API `std.Io` di-gate di balik cek comptime `ZIG_SEMVER` (ADR-044).

- Breaking: `dispatch_model` kini field config wajib tanpa default. Setiap config server (`Http1ServerConfig`, `HttpServerConfig`, `Http2ServerConfig`, `GrpcServerConfig`, `FixServerConfig`, `TcpServerConfig`, `UdpServerConfig`, `Http3ServerConfig`) melepas default `.ASYNC`, jadi pemanggil harus menyetel `dispatch_model` secara eksplisit.

- Breaking: `Server.init` seragam dan infallible di seluruh engine keluarga HTTP (ADR-014):
    - `zix.Http`, `zix.Http2`, `zix.Grpc`, dan `zix.Http3` kini menyimpan config saat `init` dan tidak bisa gagal, dengan validasi port dan TLS dipindah ke `run()` (`error.PortNotConfigured`, `error.TlsRequired`). Ini mengikuti `zix.Http1`, jadi setiap engine dikonstruksi dengan cara yang sama: `init` membaked comptime handler atau tabel route ke dalam tipe, `run()` memvalidasi lalu melayani.
    - `zix.Http3` mendapat struct `Server`: `zix.Http3.Server.init(handler, config)` menggantikan entry point fungsi-generik `zix.Http3.Http3(handler)` (generic kini menjadi `Http3ServerImpl` privat).
    - `zix.Http.Server.init` melepas argumen comptime `stack_threshold` di depan, jadi pemanggilannya menjadi `Server.init(routes, config)`. Buffer baca per-koneksi tinggal di stack thread koneksi ketika `max_recv_buf` muat pada konstanta internal `stack_read_buf_max` (4096) dan alokasi heap jika tidak, dengan `max_recv_buf` (config) sebagai knob tuning. Field `HttpServerConfig` `max_client_response` yang tidak terpakai dihapus.
    - Migrasi: `zix.Http.Server.init(4096, &routes, cfg)` menjadi `zix.Http.Server.init(&routes, cfg)`. `const S = zix.Http3.Http3(handler); var s = try S.init(cfg)` menjadi `var s = zix.Http3.Server.init(handler, cfg)`. Lepas `try` pada init `zix.Http2` / `zix.Grpc` / `zix.Http` (port tidak valid kini muncul dari `run()`). Hapus setiap `.max_client_response = N` dari `HttpServerConfig`.

- Jalur serve https `zix.Http` (ADR-053):
    - `zix.Http` memperoleh TLS opt-in (`config.tls`), engine HTTP ketiga yang melayani https/1.1. Setiap koneksi menjalankan handshake (TLS 1.3, dengan fallback 1.2 ECDSA) dan loop request keep-alive di worker thread-nya sendiri, response router ditangkap lewat response sink milik engine lalu dienkripsi, jadi handler menulis Response biasa dan jalur cleartext tidak menambah biaya hot-path. Response ter-buffer secara default (WebSocket adalah follow-up, SSE / streaming melalui TLS mendarat di ADR-054). Example baru `examples/tls/tls_http_basic.zig` (port 9071).
    - Worker TLS Http2 dan gRPC yang multipleks kini pin per-core dan menghitung worker count dari cpuset yang tersedia (paritas ADR-052 dengan `tls_mux` Http1), jadi cpuset yang di-pin cgroup tidak lagi meng-oversubscribe satu core di bawah handshake storm.

    ---

- SSE / streaming melalui TLS (ADR-054):
    - `zix.Http` dan `zix.Http1` melayani Server-Sent Events melalui TLS di jalur thread-per-koneksi (`.ASYNC` / `.POOL` / `.MIXED`). Stream sink per-koneksi (`TlsStreamSink`, type-erased atas koneksi TLS 1.3 / 1.2 hidup) mengenkripsi satu TLS record per write dan mengirimnya seketika, menggantikan buffered capture hanya ketika handler memilih streaming. `fdWriteAll` memeriksa buffered sink dulu, lalu stream sink, jadi response normal menjaga jalur cepat ter-buffer tetap utuh.
    - `zix.Http` memakai ulang `res.stream()` (tanpa simbol publik baru, kini menjaga stream sink aktif melalui TLS). `zix.Http1` memperoleh `beginStream()`, no-op di cleartext, jadi satu fd-handler melayani cleartext dan TLS. Jalur `tls_mux` multipleks (`.EPOLL` / `.URING`) tetap request / response saja (kemudian dibuka oleh ADR-060 di bawah).
    - Example baru `examples/tls/tls_http_sse.zig` (port 9072) dan `examples/tls/tls_http1_sse.zig` (port 9073), dengan runner step `test-runner-tls-http-sse` / `test-runner-tls-http1-sse` (client `zix.Tls` native, tanpa curl), dilipat ke `test-runner-all`. `examples/http1_sse.zig` kini memanggil `beginStream()`.

    ---

- WebSocket melalui TLS (ADR-055):
    - `zix.Http` dan `zix.Http1` melayani WebSocket melalui TLS (wss) di jalur thread-per-koneksi (`.ASYNC` / `.POOL` / `.MIXED`). Handler memanggil `WebSocket.serveTls(fd, key, on_frame)`: ia mengirim `101` terenkripsi lewat ADR-054 stream sink dan mendaftarkan handoff, lalu loop serve https menjalankan inline frame loop atas TLS session (dekripsi record, parse frame, `on_frame` untuk text / binary, ping di-auto-pong, close di-auto-echo). Frame keluar memakai ulang ADR-054 stream sink, jadi tiap pump pass mengenkripsi frame ter-coalesce sebagai satu record.
    - `zix.Http1` memakai ulang frame codec-nya (`parseFrame` / `pump` / `send`) dan handoff `requestWebSocket` / `takeWebSocket`. `zix.Http` memperoleh bagian engine-driven yang cocok (`WsFrameFn`, `send`, `pump`, handoff, `upgradeFd`), jadi `on_frame(fd, opcode, payload)` dan `serveTls` yang sama jalan di kedua engine. Rooms / broadcast tidak dilayani melalui TLS (enkripsi per-session), jadi wss bersifat per-koneksi / echo. Jalur `tls_mux` multipleks tetap request / response saja (kemudian dibuka untuk `zix.Http1` oleh ADR-060 di bawah).
    - Example baru `examples/tls/tls_http1_ws.zig` (port 9074) dan `examples/tls/tls_http_ws.zig` (port 9075), dengan runner step `test-runner-tls-http1-ws` / `test-runner-tls-http-ws` (client `zix.Tls` native, tanpa websocat), dilipat ke `test-runner-all`.

    ---

- TLS dual listener (ADR-060):
    - Field config flat baru `tls_port: u16 = 0` pada `Http1ServerConfig`, `HttpServerConfig`, `Http2ServerConfig`, dan `GrpcServerConfig`: dengan `tls` diisi dan `tls_port` non-zero, SATU server melayani cleartext di `port` DAN TLS di `tls_port` dari worker fleet yang sama, menggantikan setup dua-peluncuran yang menduplikasi worker, tabel fd, dan cache. `tls_port == port` ditolak di `run()` (`error.TlsPortConflict`). Default tidak berubah: `tls` null tetap cleartext-only, `tls` diisi dengan `tls_port` 0 tetap TLS-only.
    - Transport TLS per-koneksi dibagi di `src/multiplexers/tls_conn.zig` (session + staging backpressure + tabel slot fd), menggantikan empat salinan nyaris identik di file `tls_mux.zig`. Loop engine tetap per-engine (ADR-050).
    - Di bawah `.URING` sisi TLS berjalan di ring (op user_data `tls_accept` / `tls_recv` / `tls_send`), tanpa fleet epoll tersembunyi. Di bawah `.EPOLL` listener TLS bergabung ke epoll yang sama, ditandai di data word event. Thread model melayani sisi TLS dengan satu accept thread tambahan.
    - Loop mux `zix.Http1` kini menampung WebSocket dan SSE melalui TLS (encrypt-on-write lewat stream sink per-koneksi), dan loop mux `zix.Http` menampung `res.stream()` melalui TLS, membuka batasan thread-path ADR-054 / ADR-055 di sana.
    - Contoh baru `examples/tls/tls_http1_dual.zig` (port 9076 cleartext / 9077 TLS), check runner `tls-http1-dual`, dan integration test dual-listener per-engine.

    ---

- Dispatch `.EPOLL` / `.URING` native untuk `zix.Http2` (ADR-043):
    - `zix.Http2` h2c memperoleh loop multiplexed shared-nothing yang sebelumnya dilipat ke `.POOL`. Sebuah mux state machine h2 yang resumable (`src/tcp/http2/mux.zig`, satu `MuxConn` per fd, akumulator baca bertahan lintas event readable) digerakkan oleh `dispatch/epoll.zig` (satu listener `SO_REUSEPORT` plus epoll plus slab `ConnTable` per worker) dan `dispatch/uring.zig` (satu ring io_uring per worker, multishot accept, `user_data` ber-tag generation). Di ring, worker memegang accept plus recv dan handler menulis reply langsung ke fd non-blocking (tanpa cork per-stream). `.URING` memprobe ring saat startup dan jatuh ke `.EPOLL` ketika io_uring tidak tersedia, keduanya dilipat ke `.POOL` di luar Linux.
    - `zix.Http2.Router` memperoleh query-stripping dan `.kind = .PREFIX`, meniru `zix.Http1`: query di-strip sebelum matching, route EXACT memakai `StaticStringMap`, PREFIX mencocokkan prefix terdaftar terpanjang pada batas segment. `RouteKind` diekspor.
    - Keluarga example baru `examples/http2_basic_{1_async,2_pool,3_mixed,4_epoll,5_uring}.zig` (port 9065-9069) dengan step runner `test-runner-http2-{async,pool,mixed,epoll,uring}`, dilipat ke `test-runner-all`.

    ---

- Optimasi memori dan throughput `zix.Http2` (pool slot-stream per-worker, ADR-058):
    - Pool slot stream per worker (`src/tcp/http2/mux.zig`): mux `.EPOLL` / `.URING` meminjam slot tiap stream (tabel header plus buffer body / scratch) dari free-list thread-local saat stream dibuka dan mengembalikannya saat ditutup, jadi memori stream residen mengikuti stream konkuren, bukan `connections * max_streams`. Tiap koneksi hanya menyimpan array pointer selebar `max_streams`, dan steady state tidak melakukan alokasi per-stream (buffer dipakai ulang lintas pinjaman). Pada 4096 koneksi ini memangkas memori baseline-h2c sekitar 6x sambil menaikkan throughput 8 sampai 20 persen, karena slot hot yang di-pool punya cache working set lebih rapat dibanding tabel per-koneksi lama yang sparse.
    - Cache prefix header respons HPACK (`src/tcp/http2/hpack.zig`, `respHeaderBlock`): blok `[:status, content-type, content-encoding]` untuk triple yang hot di-encode sekali dan dipakai ulang byte-identik lintas koneksi (encoder stateless, tidak pernah dynamic table), hanya `content-length` yang di-encode per balasan. Menaikkan cell body-kecil 18 sampai 26 persen pada CPU lebih rendah.
    - Seal-in-place pada jalur record TLS 1.3 (`src/tls/record.zig` `protect2`, `src/tls/connection.zig` `writeAppData2`, `src/tcp/tls/tls_session.zig` `encrypt2`): gather-encrypt yang menyegel dua slice plaintext ke satu record tanpa copy staging.
    - Default config: `Http2ServerConfig` / `ServeOpts` default `max_streams` 16 ke 128 (concurrency yang diiklankan, murah sekarang slot di-pool) dan `max_body` 64 KiB ke 16 KiB (body request yang di-buffer per stream, body lebih besar di-shed dari stream dengan 413). `max_header_scratch` tetap 4 KiB.

- Optimasi memori dan throughput `zix.Grpc` (pool slot-stream per-worker, ADR-058):
    - Pool slot-stream per-worker (`src/tcp/http2/grpc/core.zig`): mux gRPC `.EPOLL` / `.URING` meminjam slot tiap stream (tabel header plus buffer body / scratch) dari free-list thread-local saat stream dibuka dan mengembalikannya saat ditutup, sehingga memori stream residen mengikuti stream konkuren alih-alih `connections * max_streams`. Tiap koneksi hanya menyimpan array pointer selebar `max_streams`, dan steady state tidak melakukan alokasi per-stream (buffer dipakai ulang lintas pinjam). Pada 1024 koneksi ini memangkas memori unary-grpc sekitar 12x (916 ke 77 MiB) sambil menaikkan throughput 8 sampai 11 persen, hasil dua-sumbu yang sama seperti pool Http2. Path blocking `.ASYNC` / `.POOL` / `.MIXED` mempertahankan array per-koneksinya sendiri, tak berubah.
    - Default config: `GrpcServerConfig` / `GrpcServeOpts` default `max_streams` 16 ke 128 (concurrency yang diiklankan, murah sekarang slot di-pool) dan `max_body` 64 KiB ke 16 KiB (body request yang di-buffer per stream, body lebih besar di-shed dari stream dengan RESOURCE_EXHAUSTED). `max_header_scratch` tetap 4 KiB.

    ---

- gRPC over TLS dan terminator h2-over-TLS bersama:
    - `zix.Grpc` melayani TLS native (TLS 1.3, dengan fallback 1.2, ALPN h2) via `tls: ?*Tls.Context`, aditif di atas default h2c. Jalur TLS menggerakkan mux state machine gRPC resumable (`grpcMuxProcessRing`) langsung di atas record terdekripsi, engine single-owner yang sama dengan model cleartext `.EPOLL` / `.URING`, jadi tidak punya race write per-stream.
    - Terminator h2-over-TLS difaktorkan ke `src/tcp/tls/h2_terminator.zig` yang bersama dan engine-agnostic (handshake 1.3 / 1.2, ALPN h2). Ia menjalankan driver inline-mux dari pemanggil di atas record terdekripsi dan menyegel frame engine kembali ke record TLS lewat write hook thread-local, tanpa socketpair dan tanpa thread kedua. `tls_serve.zig` `zix.Http2` dan `zix.Grpc` adalah wrapper tipis yang menyuplai driver.
    - Dispatch TLS multipleks (ADR-052): untuk `.EPOLL` / `.URING`, satu worker epoll `SO_REUSEPORT` per core menterminasi TLS di tempat lewat session TLS 1.3 resumable (`src/tcp/tls/tls_session.zig`) dan memultipleks banyak koneksi per worker (`tls_mux.zig`), jadi Http2 https dan gRPC TLS tidak lagi men-spawn thread per koneksi di konkurensi tinggi. `.ASYNC` / `.POOL` / `.MIXED` tetap memakai terminator thread-per-koneksi, yang juga melayani fallback 1.2.
    - Docs `hld-grpc`, `hld-tls`, `lld-tls`, dan `hld-grpc-proxy` (en dan -id) diperbarui untuk gRPC TLS native.

    ---

- Response compression (gzip / deflate / brotli):
    - Negosiasi `Accept-Encoding` dengan gzip dan deflate. Codec bersama baru `src/utils/compression/flate.zig` (container-parameterized di atas `std.compress.flate`: gzip = RFC 1952, deflate = zlib-wrapped RFC 1950, bukan raw) plus facade `compression.zig` (negosiasi q-value, penanganan `q=0` dan wildcard, size floor, skip media-type yang sudah terkompresi, dispatch encode/decode).
    - brotli (`br`) bergabung ke facade sebagai `src/utils/compression/brotli.zig`, codec in-tree yang ditulis dari RFC 7932 (std tidak punya brotli): decoder lengkap plus encoder, meng-embed static dictionary Appendix A 122,784 byte (`brotli_dictionary.bin`). `.BR` ada di `supported_default`, tetapi gzip tetap default pada q yang sama (encoder in-tree belum kompetitif dengan gzip pada body kecil), jadi brotli disajikan ketika client memintanya. Interop diverifikasi dua arah terhadap `brotli` CLI sistem. Encoder selalu juga menghasilkan stream store-only dan mengembalikan yang lebih kecil, jadi sebuah body tidak pernah membesar (body sangat kecil cukup fallback ke identity).
    - `zix.Http1` menyajikannya via `core.writeNegotiated(fd, head, status, content_type, body)`, `zix.Http` via `Response.sendNegotiated(req, body)`, keduanya menyetel `Content-Encoding` dan `Vary: Accept-Encoding`. Aktif pada `.EPOLL` dan `.URING`, default off. gRPC tetap memakai `grpc-encoding` per-message miliknya, raw transport tidak punya negosiasi HTTP.
    - `std.compress.flate.Compress` berukuran sekitar 230 KB dan hidup di encode scratch per-worker yang di-map secara lazy (tidak pernah jadi temporary stack), menjaga hot path bebas syscall alokasi. Worker yang mengompresi tetap di-spawn dengan floor stack 2 MiB (demand-paged, RSS mendekati nol) alih-alih default 512 KB, headroom untuk rantai panggilan codec yang lebih dalam. Encoder brotli membangun index dictionary-nya di heap dan dictionary-nya sendiri adalah `@embedFile` `.rodata`, jadi tidak menambah tekanan stack.
    - Codec caller-buffer parity: `brotli.zig` menambah `compressBrotli` / `decompressBrotli` (varian buffer-into di samping tiap varian alloc), jadi cocok dengan bentuk four-function `flate.zig`. `flate.zig` dan `brotli.zig` kini punya named `EncodeError` / `DecodeError` yang serasi (`BufferTooSmall` dibagi), dan `compressBound` mendokumentasikan bahwa brotli tidak pernah membesar sedangkan flate bisa. `writeGzipCached` yang bespoke tetap gzip-only secara desain (A/B json-comp menunjukkan pengganti unified-nya turun sekitar 1.2 sampai 6.8%), jadi tidak ada kembaran `writeBrotliCached`, brotli lewat `writeNegotiated`.
    - Example baru `http1_compression` (port 9058) dan `http_compression` (port 9059), masing-masing dengan `/data` (negotiated) plus route eksplisit `/gzip` `/deflate` `/br` yang memaksa satu coding lewat facade `compression.encode`. Step runner individual `test-runner-http1-compression` / `test-runner-http-compression` (raw-socket, menguji br / gzip / deflate / identity / size-floor), dan kedua example dilipat ke `test-runner-all` sebagai baris `http-compression` / `http1-compression` (raw-socket read, decode, value-check tiap coding), menjadikan runner 69 protokol.

    ---

- TLS (https / h2), pure-Zig di atas `std.crypto`, tanpa OpenSSL:
    - Server TLS 1.3 (RFC 8446) plus floor TLS 1.2 (RFC 5246 / 5288, ECDHE-ECDSA-AES128-GCM), 1.3 diutamakan, tidak pernah di bawah 1.2 (1.0 / 1.1 / SSL tidak pernah ditawarkan, RFC 8996). Handshake sans-I/O di `src/tls`, engine HTTP memiliki socket loop.
    - Client native yang memverifikasi `zix.Tls.Client` (1.3) dan `zix.Tls.Client12` (1.2): menawarkan ALPN, memverifikasi signature server dan chain X.509 + hostname (RFC 5280 / 6125).
    - https bersifat opt-in dan aditif (ADR-046): `zix.Http1` menyajikan https/1.1 dan `zix.Http2` menyajikan h2 over TLS (ALPN h2), keduanya jalur ber-gate di depan engine cleartext yang tidak diubah. HelloRetryRequest, penanganan alert masuk, dan misdirected-request 421 (RFC 9110 7.4) sudah terpasang.
    - TLS server dikonfigurasi oleh object `Tls.Context` milik pengguna (ADR-047), dimodelkan pada logger: `Tls.Context.init(allocator, io, config)` memuat cert / key dan memvalidasi policy sekali. `Tls.Context.Config` mengekspos `cert_path`, `key_path`, `alpn`, `min_version` / `max_version`, `curves`, `ciphers`, `prefer_server_ciphers`, `hsts_max_age_s`. Curve dan cipher adalah allow-list tervalidasi (value tidak didukung = error saat startup). Certificate ECDSA P-256 dan Ed25519, ECDHE-only (tanpa dhparam).
    - Certificate server RSA (ADR-048): certificate RSA menandatangani CertificateVerify TLS 1.3 dengan `rsa_pss_rsae_sha256` (pure-Zig, Montgomery modexp constant-time di `montgomery.zig` plus EMSA-PKCS1-v1_5 / EMSA-PSS, minimum RSA-2048). RSA membutuhkan TLS 1.3, tipe certificate default tetap ECDSA P-256.
    - Example baru di `examples/tls/`: `tls_http1_basic` (9060), `tls_http2_basic` (9061), `tls_http1_ed25519` (9062), dengan step runner yang dilipat ke `test-runner-all`.
    - Docs: `docs/hld-tls-id.md` / `docs/lld-tls-id.md` (dan -en), ADR-045 / 046 / 047 / 048.

    ---

- Mode datagram UDP raw-bytes `zix.Udp.Raw` (ADR-049):
    - `zix.Udp.Raw(handler)` melayani datagram variable-length (hingga `max_recv_buf`) berdampingan dengan typed `zix.Udp.Server(Packet)`. Handler menerima byte datagram, peer, dan `Sink` untuk membalas. Di Linux ia mem-batch receive / send via `recvmmsg` / `sendmmsg`, balasan digabung jadi satu `sendmmsg` per batch yang diterima, dengan worker `SO_REUSEPORT` per-core di bawah `.EPOLL` / `.URING` (satu worker di bawah `.ASYNC` / `.POOL` / `.MIXED`).
    - Dispatch dipartisi sesuai ADR-043: `src/udp/dispatch/` (satu file per model plus `common.zig`) dengan `run()` switch tipis, plus `src/udp/datagram.zig` (socket raw-fd + primitive `recvmmsg` / `sendmmsg`) dan `src/udp/core.zig` (`HandlerFn`, `Sink`). Typed `Server(Packet)` tidak berubah, `dispatch_model` non-ASYNC padanya di-fold dengan notice yang dicatat. Non-Linux jatuh ke satu loop `std.Io.net`.
    - Example baru `examples/udp_server_raw.zig` (port 9064) dengan runner step `test-runner-udp-raw`, dilipat ke `test-runner-all`. GSO dan jalur submission io_uring khusus di balik `.URING` menyusul di ADR-056 (di bawah), GRO / ECN tetap ditunda.

    ---

- Engine HTTP/3 melalui QUIC `zix.Http3`, pure-Zig di atas `std.crypto`, di substrate `zix.Udp` (ADR-051):
    - `zix.Http3.Server.init(handler, config)` melayani HTTP/3 (RFC 9114) melalui QUIC (RFC 9000 / 9001 / 9002), dengan comptime `zix.Http3.Router` yang mengikuti `zix.Http1` / `zix.Http2` (EXACT / PARAM / PREFIX, query di-strip sebelum matching). TLS 1.3 wajib, dikonfigurasi oleh `Tls.Context` user-owned yang sama dengan engine TCP.
    - Layer QUIC / TLS / QPACK yang deterministik adalah pure-Zig dari RFC: packet protection (header protection plus AEAD), key schedule (Initial / Handshake / 1-RTT), handshake TLS 1.3 di atas CRYPTO-stream (ServerHello plus flight EE / Certificate / CertificateVerify / Finished), QPACK static-table field line, dan decoder Huffman RFC 7541 untuk request path.
    - Dispatch model (Linux-only): `.ASYNC` menjalankan satu recv loop single-worker dengan demux connection-id internal (migration-safe). `.POOL` / `.MIXED` menjalankan satu worker recvmmsg SO_REUSEPORT per core, dan `.EPOLL` / `.URING` menambah readiness epoll / completion io_uring pada bentuk per-core itu (`.URING` fold ke loop worker epoll saat io_uring tidak tersedia). Connection-id steering per-core ditunda (ADR-049 phase 3, ADR-050).
    - Loss recovery dan congestion control di hot-path (ADR-056, menggantikan penundaan ADR-051): deteksi loss berbasis ACK (RFC 9002), estimator RTT, Probe Timeout dengan backoff, dan congestion window gaya NewReno kini berjalan di jalur serve, jadi path yang lossy pulih alih-alih satu packet tail yang hilang memacetkan seluruh response. Sebuah maintenance sweep berbasis timer (tiap 5 ms) me-re-pump range in-flight yang timed-out. Hanya loss yang terdeteksi ACK yang memotong congestion window, sebuah PTO me-retransmit tanpa mengurangi cwnd (RFC 9002 6.2). Model `.EPOLL` dan `.URING` kini menjalankan worker `SO_REUSEPORT` per-core yang sebenarnya (tiap worker memiliki tabel connection-id-nya sendiri, `.URING` adalah ring io_uring nyata dengan fallback ke loop `.EPOLL`) alih-alih fold ke worker single v1. Sebuah slot koneksi direklamasi hanya saat close atau idle melewati `max_idle_ms`, tidak pernah karena loss, jadi peer yang hidup-tapi-lossy tetap tersambung. Pada potongan yang sama `zix.Udp` raw memperoleh ADR-049 phase dua-nya (ring recv io_uring nyata di balik `.URING` plus UDP GSO). Steering connection-id lintas-core untuk migrasi di tengah koneksi tetap ditunda.
    - `zix.Http3` mengekspor primitive low-level-nya (`crypto`, `protection`, `keyschedule`, `qpack`, `huffman`, `packet`, `varint`, `frame`, plus `tls_key_schedule`), cara yang sama `zix.Http2` mengekspor primitive frame / HPACK-nya, sehingga sebuah peer bisa membangun sisi lain dari wire.
    - Example baru `examples/tls/http3_basic.zig` (port 9063). Runner menggerakkan client QUIC native yang hermetic, hand-rolled dari primitive itu (tanpa tool eksternal), dengan runner step `test-runner-http3` dilipat ke `test-runner-all`.
    - Docs: `docs/hld-http3-id.md` / `docs/lld-http3-id.md` (dan -en).

    ---

- `zix.utils.multipart` (parser multipart dipindah):
    - Parser `multipart/form-data` dipindah dari `src/tcp/http/upload.zig` ke `src/utils/multipart.zig`, byte parsing yang protocol-agnostic dan dibagikan oleh `zix.Http` dan `zix.Http1`. Type di-rename `MultipartParser` menjadi `Parser` dan `MultipartField` menjadi `Field`, jadi path kanonikalnya `zix.utils.multipart.Parser` / `zix.utils.multipart.Field`. `zix.Http.Multipart` / `zix.Http.MultipartField` tetap ada sebagai thin alias (tanpa break). `examples/http_static.zig` dan `examples/http1_static.zig` memanggil path kanonikal, dan `examples/http1_static.zig` mendapat route upload kedua (`/upload-multipart`) yang mendemokannya pada `zix.Http1`.

    ---

- Server config (knob) ditambahkan:
    - `compress` (bool), `compression_min_size` (usize), dan `compression_max_out` (usize) pada `zix.Http1` dan `zix.Http`. Field gzip-spesifik `max_gzip_out` di-rename menjadi `compression_max_out` yang codec-agnostic.
    - `tls` (`?*Tls.Context`) pada `zix.Http1`, `zix.Http2`, dan `zix.Grpc`, gate opt-in https. Menggantikan field flat `tls_cert_path` / `tls_key_path` / `tls_alpn` / `hsts_max_age_s` Http1 (ADR-047).
    - `dispatch_model`, `workers`, `reuse_address`, `recv_batch`, `send_batch`, `max_recv_buf` pada `zix.Udp` (`UdpServerConfig`), dipakai jalur raw (`zix.Udp.Raw`, ADR-049). Additive, typed `Server(Packet)` tidak berubah.
    - `public_dir` dan `public_dir_upload` pada `zix.Http1` (`Http1ServerConfig`), static file serving untuk route yang tidak match, meniru `zix.Http`. `public_dir` yang non-empty divalidasi saat `run()` dan menghasilkan `error.PublicDirNotFound` jika tidak ada.
    - `uring_send_buf_size` (default 16 KiB), `uring_idle_pool_floor` (default 8), dan `uring_idle_pool_ceiling` (default 256) pada `zix.Http1` (`Http1ServerConfig`), menyetel send buffer per-koneksi `.URING` dan batas warm reconnect-pool (lihat entri optimasi memori Http1 / Http).

    ---

- DATA-frame coalescing untuk gRPC server-streaming (ADR-057):
    - Server-streaming `zix.Grpc` memadatkan pesan berurutan menjadi DATA frame HTTP/2 yang lebih sedikit dan lebih besar (hingga max frame size default 16 KiB) alih-alih satu DATA frame per pesan. Reply `count = 5000` turun dari 5000 DATA frame kecil menjadi sekitar 3, memangkas byte header frame di wire dan biaya parse per-frame di klien. Perbaikan ini ada di `muxDispatch` bersama, jadi `.URING`, `.EPOLL`, dan kedua jalur mux TLS mewarisinya. Unary tetap satu frame per pesan dan byte-nya persis sama. Jalur thread (`.ASYNC` / `.POOL` / `.MIXED`) belum dipadatkan. `zix.Grpc.Client` bawaan meng-unpack beberapa pesan dari satu DATA frame (tiap `recvResponse` menguras sisa frame sebelum membaca frame berikutnya), sesuai coalescing-nya.

    ---

- Negosiasi content-encoding HTTP/3:
    - `zix.Http3` mendapat content-negotiation pada response. `req.accept_encoding` mengekspos Accept-Encoding klien (didekode dari QPACK static entry 31 atau literal, Huffman diperluas), dan handler memanggil `res.setContentEncoding(.br)` / `.gzip`, yang memancarkan header response `content-encoding` sebagai satu QPACK indexed line (indeks static 42 br / 43 gzip). Engine tidak pernah mengompresi di jalur kirim: handler menyajikan body yang sudah ter-compressed (file `.br` / `.gz` yang sudah jadi), jadi tidak ada biaya codec per-request dan aturan perf / memory tetap terpenuhi. Menyajikan varian pre-compressed yang lebih kecil berarti lebih sedikit packet per response, itulah yang menggerakkan static-serving.
    - Static table QPACK diperluas dari indeks 0..28 ke 0..43 (RFC 9204 Appendix A), mencakup `accept-encoding` (31) dan `content-encoding` br / gzip (42 / 43). Decoder request menelusuri melewati pseudo-header untuk menangkap `accept-encoding`, dan `buildRequestStreamContent` / `buildStreamPrefix` memancarkan line `content-encoding` (`SendStream` menyimpan coding-nya agar body multi-packet yang di-resume tetap membawa header-nya). Perubahan ini ada di `dispatch/common.zig` bersama, jadi setiap dispatch model mewarisinya.
    - `zix.Http3.ContentEncoding` diekspor. `examples/tls/http3_basic.zig` mendapat route `/negotiated` yang menyajikan body brotli-precompressed dengan `content-encoding: br` saat klien menerima br. Docs `hld-http3`, `lld-http3` (en dan -id) diperbarui.

    ---

- Rolling flow-control credit HTTP/3 (MAX_STREAMS + MAX_DATA):
    - Handshake QUIC mengiklankan dua budget sekali-pakai ke client, `max_streams` request stream dan `initial_max_data` (1 MiB) byte request seluruh connection. Keduanya kini digulir maju saat client memakainya: grant MAX_STREAMS (frame 0x12, `replenishBidiStreams`) naik saat request stream pensiun, dan grant MAX_DATA (frame 0x10, `replenishMaxData`) naik saat byte request terpakai. Tiap grant dipancarkan begitu konsumsi melewati separuh window-nya dan menumpang prologue reply yang ter-coalesce, seperti ACK.
    - Memperbaiki deadlock seumur connection: tanpa byte grant, connection membisu setelah kira-kira `initial_max_data` request, client terblokir pada connection flow control dan request in-flight terakhirnya tak pernah terjawab, sehingga throughput connection berumur panjang mentok di konstanta yang tidak bergantung hardware. Dengan kedua grant menggulir, connection melayani tanpa batas.
    - Bagian baru: `flight.initial_max_data` (nilai yang diiklankan sekaligus window replenish, satu const), `Connection.replenishMaxData`, `request.streamBytes` (menjumlah byte payload STREAM sebuah packet lintas semua stream, karena flow control level connection menghitung semuanya), dan `response.buildMaxData` plus `Framing.max_data`. Wiring ada di `dispatch/common.zig` bersama, jadi semua dispatch model mewarisinya. Unit test mencakup matematika replenish, encoding frame, dan penghitungan byte.

    ---

- Taksonomi penamaan send / write / FD untuk response-API (ADR-059):
    - Permukaan penulisan response di-rename pada dua sumbu independen agar call site terbaca tanpa ambiguitas: fungsi yang mengirim response, atau komunikasi keluar apa pun, adalah `send*`, sebuah write murni tanpa send adalah `write*`, dan signature yang menerima parameter `fd` mentah diakhiri `FD` (sebuah fd yang ditahan di dalam struct, dijangkau lewat `self`, tidak dihitung, jadi method objek tetap bersih).
    - Breaking untuk kode yang memanggil helper response secara langsung. Helper fd-level di core di-rename lintas setiap engine: `fdWriteAll` -> `writeAllFD`, `fdWriteAllRaw` -> `writeAllRawFD`, `writeSimple` -> `sendSimpleFD`, `writeSimpleNoBody` -> `sendSimpleNoBodyFD`, `writeJson` -> `sendJsonFD`, `writeGzip` -> `sendGzipFD`, `writeGzipCached` -> `sendGzipCachedFD`, `writeBrotli` -> `sendBrotliFD`, `writeNegotiated` -> `sendNegotiateFD`, `writeChunkedStart` / `writeChunk` / `writeChunkedEnd` -> `sendChunkedStartFD` / `sendChunkFD` / `sendChunkedEndFD`, `writeRange` -> `sendRangeFD`, `write100Continue` -> `send100ContinueFD`. Body dan parameter fungsi tak berubah, hanya nama dan teks doc / comment yang merujuknya.
    - Engine yang mampu compression mengekspos enam yang sama: `sendGzipFD`, `sendGzipCachedFD`, `sendBrotliFD`, `sendBrotliCachedFD`, `sendNegotiateFD`, `sendNegotiateCachedFD`. Negotiate merutekan secara internal lewat jalur gzip / brotli bersama, jadi kebijakan compression ada di satu tempat, dan primitif precompressed / caller-encoded (`sendResponseEncodedFD`) tetap menjadi lapisan yang dibangun keenam fungsi itu di atasnya.
    - Digulirkan engine demi engine (`zix.Http1`, WebSocket-nya, `zix.Http2`, `zix.Grpc`, `zix.Http3`, lalu full server plus tls / dispatch bersama), tiap langkah di-gate oleh suite test penuh. Entri HttpArena dan example bawaan pindah ke nama baru (call site saja, tanpa perubahan behavior). Docs `hld-http1`, `lld-http1`, `lld-http`, `lld-http2`, `lld-grpc`, `lld-tls` (en dan -id) diperbarui. Lihat ADR-059.

    ---

- Optimasi memori `zix.Http1` dan `zix.Http` (kompaksi recv-slab EPOLL, batas idle-pool URING):
    - Kompaksi recv-slab EPOLL (`src/tcp/http1/dispatch/epoll.zig`, di-port ke `dispatch/common.zig` milik `zix.Http`): slab receive per-worker diindeks oleh fd global (`slab[fd * buf_size]`), jadi page yang tersentuh tersebar di seluruh ruang 64K-fd dan menahan residen jauh lebih banyak dari yang dibutuhkan set koneksi hidup. Sebuah free-list slot kompak per-worker (tiap `Conn` membawa `slot`, `acquireSlot` memakai ulang slot yang sudah ditutup sebelum menaikkan high-water mark, `free` mengembalikan stride page-aligned via `MADV_DONTNEED`) memampatkan memori residen ke jumlah koneksi hidup terlepas dari nilai fd. Pada jumlah koneksi tinggi ini memangkas memori Http1 puncak sekitar 2.5x (kira-kira 704 ke 281 MiB), membawa `.EPOLL` ke paritas `.URING`, dengan throughput tertahan dalam noise loopback.
    - Batas idle-pool URING (`src/tcp/http1/dispatch/uring.zig`): warm reconnect pool kini meng-evict tail yang paling lama tidak dipakai (`evictColdTail`, list warm MRU plus stack cold) melewati sebuah batas, mengecilkan `send_buf` per-koneksi yang tumbuh kembali ke ukuran dasar saat dilepas, dan mem-prewarm floor residen kecil saat startup untuk menghindari badai page-fault cold-start. Mereklamasi cold tail (bukan hot head yang diambil reconnect berikutnya) menjaga reklamasi keluar dari hot path churn, jadi memori turun tanpa biaya throughput. Dibatasi oleh knob config `uring_send_buf_size` / `uring_idle_pool_floor` / `uring_idle_pool_ceiling` di atas.

    ---

- Penempatan CPU worker (engine multiplexed Linux, ADR-061):
    - Field config flat baru `reuseport_cbpf: bool = false` di semua server config kecuali `zix.Uds`: memasang steering SO_ATTACH_REUSEPORT_CBPF pada grup `SO_REUSEPORT` per-worker (`src/multiplexers/reuseport.zig`), sehingga kernel menyerahkan koneksi baru (TCP) atau tiap datagram (UDP) ke listener index = CPU penerima mod workers alih-alih hash 4-tuple. Listener bind di dalam thread worker yang berpacu, jadi bind-order gate khusus startup menserialkan join grup (worker i = group index i). Opt-in, default false: netral rps pada box loopback, menyasar host multi-CPU tempat NIC RSS menyebarkan softirq. Jangan pernah aktifkan pada jalur QUIC: steering per paket merusak flow affinity QUIC (paket satu flow mendarat di worker berbeda) dan meruntuhkan throughput.
    - Pinning worker meluas ke `zix.Tcp` dan `zix.Fix` (worker `.EPOLL` / `.URING`, jumlah sadar-cpuset plus pin per-core), dan urutan pin semua engine kini mengisi physical core lebih dulu, SMT sibling setelahnya (topologi sysfs, urutan mask dipertahankan bila sysfs absen).
    - Counter beban per-worker melapor saat worker keluar melalui system logger (request, frame, koneksi diterima, atau message, per engine), sehingga distribusi yang miring antar worker bisa diamati. Dua engine h2-mux (`zix.Http2`, `zix.Grpc`) tidak membawa counter ini: increment threadlocal di hot loop mux-nya terukur sekitar 1 persen throughput pada jutaan req/s, jadi dijauhkan dari hot path mereka.

- Receive multishot `zix.Udp` raw `.URING`: ring per-core memasang `recvmsg` multishot dengan provided buffer ring (mencerminkan layer recv `zix.Http3`, 256 buffer), menggantikan re-arm per completion, dengan slot pool one-shot dipertahankan sebagai fallback.

    ---

- Backpressure submission-queue `.URING` (process queue):
    - Field config flat baru `process_queue_len: usize = 0` pada `Http1ServerConfig` dan `HttpServerConfig`: pada `.URING`, re-arm recv atau send yang menemukan submission queue penuh diparkir pada FIFO ring per-worker sepanjang nilai ini (hanya referensi, fd plus generation, reject-newest) dan dicoba ulang pada loop pass berikutnya alih-alih menutup koneksi. 0 (default) mematikan fitur, dan tanpa efek pada dispatch model lain. Atur sekitar puncak koneksi bersamaan per worker.
    - Perbaikan lost-accept re-arm lintas dispatch `.URING` `zix.Http1`, `zix.Http`, `zix.Grpc`, dan `zix.Http2`: re-arm multishot-accept yang jatuh saat SQ penuh membuat worker tidak bisa accept lagi sementara backlog kernel terisi. Worker kini mencatat miss (`accept_pending` / `tls_accept_pending`) dan mencoba ulang arm tepat setelah submit berikutnya, jadi SQ penuh tidak lagi mengunci accept.
    - Kehilangan submission-queue `.URING` `zix.Http3` diperbaiki (`src/udp/http3/dispatch/uring.zig`): re-arm `recvmsg` multishot yang hilang saat SQ penuh membuat worker tuli permanen (retry `recv_unarmed` sticky kini me-re-arm-nya), re-arm slot one-shot yang hilang saat SQ penuh membocorkan slot (daftar pending re-arm terbatas kini memulihkannya), dan tail send yang dibatasi SQ penuh terbuang saat buffer swap (swap kini ditunda selama tail belum terkirim).
    - Body request oversize di-shed alih-alih dipotong: `zix.Http2` menjawab body DATA yang melewati buffer stream dengan `413` dan END_STREAM (hanya window koneksi yang dikredit untuk byte yang dibuang), dan `zix.Grpc` mengakhiri stream dengan trailer `RESOURCE_EXHAUSTED`. Sebelumnya body dipotong diam-diam ke kapasitas, yang bisa men-dispatch message korup. Frame DATA berikutnya untuk stream yang di-shed dijawab dengan RST_STREAM, dan stream lain pada koneksi tetap berjalan.

<br>

__*Fix:*__

- Drain body besar `zix.Http1` di bawah model thread:
    - Di bawah `.ASYNC` / `.POOL` / `.MIXED`, body request yang lebih besar dari receive buffer dipotong di batas buffer dan byte yang belum terbaca merusak request keep-alive berikutnya di koneksi itu. Jalur thread kini menguras sisanya sebelum melayani request berikutnya, cocok dengan perilaku `.EPOLL` / `.URING`.

    ---

- Truncation body request `zix.Http` di bawah `.EPOLL` / `.URING`:
    - Body request multi-segment (upload besar atau chunked yang terpecah lintas read) dipotong ketika `body()` / `readChunkedBody()` kena `EAGAIN` di tengah body. Reader kini mem-poll fd dan mencoba ulang hingga `body_read_timeout_ms` (default 30s), jadi upload terbaca penuh. Jalur GET hot kembali lebih awal dan tidak membayar apa pun.

<br>

## 0.4.0 (2026-06-19)

__*Ditambahkan:*__

- Penskalaan churn io_uring dan overflow response on-ring (ADR-041):
    - Teardown `.URING` `zix.Http1` kini me-ring close-nya (`prep_close`, ditag dengan `OpKind.close` bersama yang baru) alih-alih `linux.close` sinkron, mendaur ulang slot koneksi lebih dulu dan jatuh ke close sinkron hanya saat SQ sesaat penuh. Di bawah connection churn, close sinkron memblokir worker antar koneksi, jadi ring nyaris tidak mengaktifkan core-nya. Dengan ring close, worker terus memanen completion lintas teardown. Di mesin 64-core ini mengangkat cell churn (limited-conn, json) dari jauh di belakang `.EPOLL` ke paritas atau lebih baik, dengan memori jauh lebih sedikit, jadi `.URING` kini mencapai paritas atau lebih baik di setiap cell yang diukur.
    - `RespSink` (`tcp/http1/core.zig`) menumbuhkan buffer staging-nya saat overflow ketika didukung oleh allocator: loop `.URING` memasangnya di atas `send_buf` per-koneksi dengan cap 1 MiB (`URING_SEND_BUF_MAX`), jadi response yang lebih besar dari buffer ter-stage tumbuh di tempat (realloc power-of-two, tidak pernah menyusut, dipakai ulang oleh koneksi yang didaur ulang) dan tetap keluar sebagai satu on-ring send, alih-alih menahan worker di write off-ring yang memblokir. Jalur `.EPOLL` tidak memasang grow allocator dan tidak berubah (flush-on-overflow).
    - `OpKind` io_uring bersama dan helper ring dipindahkan dari `src/tcp/io_uring` ke `src/multiplexers/ring.zig`. Setiap engine io_uring membawa arm `.close => {}`. Hanya `zix.Http1` yang meng-arm ring close untuk saat ini.

    ---

- `io` server ke dalam config dan handler-at-init `zix.Uds` (ADR-039):
    - `zix.Tcp`, `zix.Udp`, dan `zix.Uds` kini membawa `io: std.Io` sebagai field config pertama, sehingga `run()` tidak menerima argumen, mengikuti lima engine server. Setiap server zix kini dikonstruksi dengan config yang membawa `io` dan dilayani dengan `run()` tanpa argumen.
    - `zix.Uds` mengadopsi bentuk factory ADR-038: `Server.init(comptime handler, config)` membakukan handler ke dalam tipe, dan `zix.Uds.echoHandler` bawaan dilewatkan secara eksplisit. Jalur `run(io, handler)` / `runWith` dihapus.
    - Breaking: setiap call site server `zix.Tcp` / `zix.Udp` / `zix.Uds` menambah `.io = process.io` dan menghapus argumen `run`. Client tetap menerima `io` sebagai parameter `connect()` (ditunda ke keputusan terpisah).

    ---

- Model dispatch io_uring (`.URING`, ADR-037):
    - Model dispatch shared-nothing baru `.URING = 4`: topologi thread-per-core yang sama dengan `.EPOLL` (satu `SO_REUSEPORT` listener dan satu completion ring per worker, tanpa queue bersama), tetapi completion-based, sehingga sebagian besar transisi syscall di-batch ke dalam ring. Khusus Linux, fallback ke `.POOL` di non-Linux.
    - Native di `zix.Http1` (engine referensi, plus pump WebSocket di atas `BufferGroup`), `zix.Http`, `zix.Grpc` (h2 multiplexed), dan `zix.Fix` (`core.processFixRing` resumable per batch readable). `zix.Http2` melipat ke `.POOL` dan handler per-connection `zix.Tcp` melipat ke `.EPOLL`.
    - Request body di ring (`zix.Http1`): body request chunked yang sepenuhnya ada di recv buffer di-decode di tempat, dan body yang lebih besar dari `max_recv_buf` dijawab lalu sisanya di-drain dari socket dengan satu recv `MSG_TRUNC` (kernel membuang byte di tempat, zero copy, dibatasi pada panjang yang dideklarasikan), mengikuti drain `.EPOLL`. Jadi `.URING` melayani upload besar dan request chunked, bukan hanya yang ter-buffer.
    - Di loopback `.URING` setara `.EPOLL` pada throughput dan total CPU, menang terutama pada cache locality per-request. Pilih `.EPOLL` sebagai default, `.URING` untuk beban sustained dan pipelined.

    ---

- Reshape API server `zix.Tcp` (ADR-038):
    - Handler dibakukan ke dalam tipe server pada `init`, sehingga `run` tidak menerima argumen handler, mengikuti `zix.Http1` / `zix.Grpc` (ADR-039 kemudian memindahkan `io` ke config, sehingga `run()` tidak menerima apa pun). `zix.Tcp.Server` kini namespace tanpa field dengan constructor comptime `init(handler, config)` / `initArgs(handler, config, args)` (per-connection) dan `initFramed(frame_fn, config)` / `initFramedArgs(frame_fn, config, args)` (ring per-frame).
    - Breaking: `runWith` dan `runFramed` dihapus. Default echo bawaan adalah `zix.Tcp.echoHandler` publik, dilewatkan secara eksplisit. Handler per-connection berjalan `.ASYNC` / `.POOL` / `.MIXED` / `.EPOLL` (`.URING` melipat ke `.EPOLL`). Callback `FrameFn` per-frame baru (`initFramed`) berjalan native di ring `.URING`.

    ---

- `Http2ServerConfig.logger`:
    - Field opsional baru `logger: ?*Logger` pada `Http2ServerConfig`, demi konsistensi dengan config server lain. Bila diset, baris lifecycle `zix.Http2` dirutekan melalui `logger.system(.INFO, "http2", ...)` alih-alih `std.debug.print` yang hanya Debug.

    ---

- Konstanta frame `zix.Http2`:
    - Byte frame-type HTTP/2 diganti nama dari `FT_*` menjadi `FRAME_TYPE_*` yang dieja penuh (`FT_DATA` -> `FRAME_TYPE_DATA`, dan seterusnya). Breaking untuk kode apa pun yang mereferensi `zix.Http2.FT_*`.
    - `pub const FRAME_HEADER_LEN` baru (9) di modul frame h2 (di-re-export dari `zix.Http2`) menamai panjang frame header 9-octet, menggantikan literal `9` inline di seluruh codec frame h2 dan gRPC.

    ---

- Response cache awareness (opt-in, ADR-036):
    - Modul bersama baru `src/utils/response_cache.zig`: precomputed-response cache per-worker yang lock-free (structure-of-arrays slab, open addressing, lazy on-access TTL). Mati secara default, dipasang di bawah `.EPOLL` dan `.URING`. Dispatch model lain membiarkannya tidak terpasang dan API menurun menjadi plain send.
    - Lima field config flat dengan nama yang identik di `Http1ServerConfig`, `HttpServerConfig`, dan `GrpcServerConfig`: `response_cache` (`bool`, default `false`), `cache_max_entries` (`u32`), `cache_max_value_bytes` (`u32`), `cache_ttl_ms` (`u32`), dan `cache_max_total_bytes` (`usize`).
    - `zix.Http`: `res.serveCached(req)` dan `res.sendCached(req, body, ttl)` mem-cache respons yang sudah di-serialize penuh, di-key pada method, path, dan query. `zix.Http1` tetap memakai `cacheLookup` / `cacheStore` / `writeWithCache`.
    - `zix.Grpc` (unary): `ctx.serveCached(content_type)` dan `ctx.sendCached(content_type, data, ttl)` mem-cache pesan respons, di-key pada path plus body request, di-frame ulang per stream sehingga HPACK dan stream id tetap benar.
    - Crossover terukur dekat 4 KiB: JSON berat ~32 KiB +34% throughput di c512, tanpa regresi di bawah ~2 KiB. Lihat ADR-036.

    ---

- WebSocket build-once broadcast fanout:
    - Baru `zix.Http1.WebSocket.broadcast(conns, opcode, payload)`: men-serialize frame sekali dan menulis byte yang sama ke setiap fd dalam room yang dikelola pemanggil, sehingga sebuah broadcast hanya berbiaya satu serialization tidak peduli jumlah member. Write yang gagal ke peer mati dilewati (engine EPOLL memanen fd itu pada event berikutnya), dan jalur payload besar membangun header sekali dan menulis payload tanpa salinan staging.
    - `zix.Http.WebSocket.RoomMap.broadcast` memakai ulang satu staging buffer untuk semua member alih-alih membuat ulang per koneksi (build once, fan out).

    ---

- Http epoll shared-nothing:
    - `zix.Http` `.EPOLL` ditulis ulang dari model terpusat (satu accept thread mendorong ke `ConnQueue` bersama, pool worker pop) menjadi arsitektur shared-nothing yang cocok dengan `zix.Http1`. Setiap worker mengikat `SO_REUSEPORT` listener tersendiri, membuat `epoll` instance tersendiri, dan menjalankan event loop level-triggered tersendiri. Kernel mendistribusikan koneksi baru ke worker tanpa antrian bersama, tanpa mutex, dan tanpa handoff fd.
    - `workers` (bukan `pool_size`) sekarang adalah jumlah worker EPOLL untuk `zix.Http`. `0` memilih cpu_count. `pool_size` diabaikan secara diam untuk `.EPOLL` (pemanggil yang menggunakan `.pool_size = N` dengan `.EPOLL` harus migrasi ke `.workers = N`).
    - Level-triggered `EPOLLIN` menggantikan `EPOLLONESHOT`. Tidak perlu re-arm eksplisit setelah setiap request: koneksi tetap terdaftar dan re-fires saat data baru tiba.
    - Throughput: 428k menjadi 451k req/s di c1000 (`wrk -c1000 -t4 -d10s`), mempersempit gap vs `zix.Http1` dari 11% menjadi 6,8%. Gap yang tersisa bersifat struktural (alokasi arena per request). Lihat ADR-034.

    ---

- Http1 EPOLL slab, RawFn, dan kontrol Date:
    - `zix.Http1` `.EPOLL` kini menyokong setiap koneksi terdaftar dengan slab buffer receive per-koneksi (`ConnTable`), berukuran `max_recv_buf`, sehingga sebuah koneksi mengakumulasi satu request penuh tanpa alokasi ulang per event.
    - Tipe handler baru `zix.Http1.RawFn` plus `zix.Http1.Server.initRaw`: handler raw menerima fd koneksi dan head yang sudah diparse serta memiliki kendali penuh atas wire, melewati jalur response terkelola (streaming, framing kustom).
    - Field config baru `send_date_header` (default `true` untuk kepatuhan RFC 7231). Set `false` untuk membuang header `Date` dan menghemat 37 byte per response pada jalur panas di mana klien tidak membutuhkannya.
    - `buildSimpleHeaderInto` menulis status line dan header ke sink milik pemanggil, jalur cepat untuk penulis slab.

    ---

- Optimasi WebSocket:
    - Unmask SIMD: `parseFrame` pada engine WebSocket `zix.Http1` dan `zix.Http` kini meng-unmask payload klien dengan XOR `@Vector(16, u8)` selebar 16 byte terhadap mask 4 byte yang direplikasi, dengan ekor skalar untuk sisanya. Menggantikan loop per-byte `i % 4`.
    - Field config baru `ws_recv_buf` pada `Http1ServerConfig` (default `0`, jatuh ke `max_recv_buf`). Set lebih besar dari `max_recv_buf` untuk memberi koneksi WebSocket EPOLL ruang lebih mengakumulasi frame pipelined sebelum compact dan re-read.
    - Pembacaan WebSocket EPOLL `zix.Http1` kini menguras hingga `EAGAIN` per wakeup (baca semua frame tersedia dalam satu event) dan menggabungkan write, alih-alih satu frame per wakeup.
    - WebSocket `zix.Http`: `buildHeader` (framing header-only ke buffer pemanggil), jalur broadcast `RoomMap` yang dibersihkan.

    ---

- Staging dan corking per-koneksi gRPC mux:
    - `GrpcMuxConn` kini memiliki `stage_buf` 64 KB (sebelumnya `ReplyStage.buf` inline 4096 byte). Satu panggilan streaming ~5000 pesan (~85 KB puncak) flush dalam dua write, dan ~100 reply unary konkuren (~6 KB) digabung menjadi satu write. `ReplyStage.buf` kini slice milik pemanggil. Jalur inline blocking tetap memakai backing stack 4096 byte.
    - Frame SETTINGS server dipra-komputasi sekali per koneksi: `buildSettingsFrame` mengisi blob 33 byte di `GrpcMuxConn.init`, dan handshake menambahkannya apa adanya alih-alih meng-encode ulang loop parameter pada setiap koneksi.
    - `TCP_CORK` membungkus handler streaming di `muxDispatch`: kernel menggabungkan beberapa flush stage perantara yang dihasilkan handler streaming menjadi lebih sedikit segmen TCP, lalu uncork saat kembali. Reply unary tidak terpengaruh (sudah single-write). No-op pada non-Linux.

    ---

- Timeout epoll dinamis (worker gRPC, TCP, FIX):
    - Loop worker EPOLL kini membalik timeout `epoll_wait` ke `0` setelah satu batch event aktif (busy-poll batch siap berikutnya) dan kembali ke `-1` (blok) saat sebuah wakeup mengembalikan nol event. Menukar spin ketat di bawah beban demi latensi lebih rendah antar batch beruntun tanpa membakar core saat idle.

    ---

- Pemecahan build:
    - `build.zig` dipecah menjadi sub-file terfokus yang diimpor oleh root: `zix-build-examples.zig`, `zix-build-tests.zig`, `zix-build-test_runner.zig`. Root `build.zig` menyusut dari ~682 baris ke wiring modul dan step. Tanpa perubahan perintah build.
    - File sumber root library diganti nama dari `src/zix.zig` menjadi `src/lib.zig` (mengikuti konvensi `lib.zig` Zig). Modul tetap terdaftar sebagai `b.addModule("zix", ...)`, sehingga API publik tidak berubah: pengguna tetap `@import("zix")` dan memakai `zix.Http`, `zix.Grpc`, dll.

    ---

- Init logging server terpadu dan ter-gate Debug:
    - Setiap server (`zix.Http`, `zix.Http1`, `zix.Http2`, `zix.Grpc`, `zix.Fix`, `zix.Tcp`, `zix.Udp`, `zix.Uds`) kini mengeluarkan baris lifecycle (listening, fallback EPOLL, error accept) melalui satu bentuk `logSystem` ter-gate: rute ke `config.logger` bila diset, selain itu `std.debug.print` hanya pada Debug build, diam pada release. Server release tanpa logger tidak mengeluarkan init noise.
    - Menghapus print mentah junk dan duplikat: `zix.Grpc` sebelumnya mencetak tiap baris listening mentah sekaligus me-log-nya. `zix.Http2`/`zix.Fix`/`zix.Tcp` mencetak baris lifecycle/fallback mentah tanpa syarat. Baris init `zix.Udp`/`zix.Uds` kini juga muncul pada Debug build tanpa logger (sebelumnya logger-only).
    - `zix.Channel.init` mendapat notice init khusus Debug (`zix channel: init <T> cap=<N>`), ditekan pada release dan di bawah test runner (`builtin.is_test`) untuk menghindari peracunan IPC test.
    - Menyusun ulang komentar `src/tcp/http1/server.zig` untuk membuang referensi benchmark eksternal yang usang.

    ---

<br>

__*Perbaikan:*__

- Write stream gRPC dan HTTP/2 di bawah EPOLL:
    - `fdWriteAll` (`src/tcp/http2/frame.zig`) kini menangani `EAGAIN` pada socket EPOLL non-blocking dengan buffer kirim penuh: ia poll fd hingga bisa ditulis lalu mengulang write, alih-alih memperlakukan write parsial sebagai broken pipe. Socket blocking tidak pernah masuk cabang ini. Memperbaiki reply streaming yang terpotong dan stream error semu di bawah konkurensi tinggi.

<br>

## 0.3.0 (2026-06-10)

__*Ditambahkan:*__

- Http1 router prefix param:
    - `zix.Http1.Router` mendapat jenis rute `.PREFIX` dan `.PARAM` (menambah `RouteKind` dan field `kind` pada `zix.Http1.Route`, default `.EXACT`), mencapai paritas dengan router `zix.Http` dan prioritas `exact > param > prefix` (ADR-004). Param path yang ditangkap dibaca dengan fungsi bebas baru `zix.Http1.pathParam(name)` (thread-local per-handler, karena handler Http1 tidak punya `Request`, lihat ADR-029), dibatasi 8 param per pencocokan.
    - Pass prefix kini menjaga byte batas di belakang `startsWith`. Perbaikan yang sama diterapkan ke router `zix.Http`, yang membaca satu byte melewati path permintaan yang lebih pendek dari prefix terdaftar (panic pada Debug/ReleaseSafe, pembacaan out-of-bounds yang tersamarkan pada ReleaseFast).
    - Kompatibel mundur: `.kind` default ke `.EXACT`, jadi tabel rute Http1 exact-only yang ada tidak berubah. `examples/http1_static.zig` kini merutekan `/secret` via rute `.PREFIX`. Lihat ADR-033.

    ---

- Epoll max events 512:
    - Batch epoll (jumlah event yang dikuras per `epoll_wait`) dinaikkan dari 256 ke 512 di seluruh server epoll native (`zix.Tcp`, `zix.Http`, `zix.Fix`, `zix.Grpc`, `zix.Http1`) dan diseragamkan menjadi satu konstanta file-level bernama dan terdokumentasi `EPOLL_MAX_EVENTS: usize = 512` per server. Campuran sebelumnya antara const `epoll_max_events` huruf kecil dan literal `256` inline dihapus.
    - 512 memungkinkan worker mengosongkan ready-fd set dalam satu syscall pada jumlah koneksi tinggi: worker dengan lebih dari 256 fd readable tidak lagi butuh `epoll_wait` kedua. Tidak ada perubahan API publik, konstanta ini adalah default internal yang disetel. Lihat ADR-032.

    ---

- Http config naming consistency:
    - Penggantian nama field `HttpServerConfig` demi konsistensi lintas API (nilai default tidak berubah): `max_kernel_backlog` menjadi `kernel_backlog` (kini menyamai `Tcp`, `Fix`, `Http1`, `http2`, dan `Grpc` yang sudah memakai nama tanpa awalan), dan `max_client_request` menjadi `max_recv_buf` (menyamai `zix.Http1`).
    - Migrasi: ganti nama field di sisi pemanggil. `.max_kernel_backlog = N` menjadi `.kernel_backlog = N`, dan `.max_client_request = N` menjadi `.max_recv_buf = N`. `max_allocator_size` dan `max_client_response` tidak berubah (tidak ada padanannya di luar `zix.Http`).

    ---

- Http1 handler at init:
    - `zix.Http1.Server.init` kini menerima handler comptime sebagai argumen pertama dan menanamkannya ke tipe server, sehingga `run()` tidak lagi menerima argumen. Ini menyamai `zix.Http` dan `zix.Grpc` yang mendaftarkan route di init. Inti server tetap agnostik terhadap routing: handler boleh berupa `Router(routes).dispatch`, `HandlerFn` biasa, atau rantai middleware.
    - Migrasi: `Server.init(.{ ... })` lalu `server.run(Routes.dispatch)` menjadi `Server.init(Routes.dispatch, .{ ... })` lalu `server.run()`.

    ---

- Grpc epoll multiplexed:
    - `.EPOLL` pada `zix.Grpc` ditulis ulang dari pool blocking thread-per-koneksi menjadi event loop multiplex shared-nothing. Tiap worker memiliki listener `SO_REUSEPORT` privat, instance epoll sendiri, dan tabel koneksi privat ber-indeks fd, kernel menyeimbangkan koneksi antar worker. Satu worker menjalankan banyak koneksi non-blocking melalui state machine HTTP/2 resumable (`GrpcMuxConn` / `grpcMuxOnReadable`), sehingga konkurensi dibatasi jumlah koneksi, bukan jumlah thread.
    - Setiap route, termasuk server-streaming, di-dispatch inline pada worker di bawah `.EPOLL` (tanpa thread per stream, tanpa write mutex koneksi). Handler streaming berjalan di event loop dan harus terbatas, pakai `.ASYNC` untuk stream tak terbatas. Jalur blocking `serveGrpcConn` tidak berubah untuk `.ASYNC` / `.POOL` / `.MIXED`.
    - `pool_size` kini adalah jumlah worker multiplex untuk `.EPOLL` (0 = jumlah cpu), bukan ukuran pool blocking. Lihat ADR-031.

    ---

- Grpc unary hotpath:
    - Reply unary dan streaming (HEADERS awal, tiap DATA, trailer, dan frame kontrol) digabung menjadi satu `write()` per event readable melalui cork `ReplyStage` per koneksi.
    - `SETTINGS_INITIAL_WINDOW_SIZE` dinaikkan ke 16 MB dengan bump window koneksi sekali, sehingga body request kecil tidak lagi memicu `WINDOW_UPDATE` per-DATA, window koneksi di-replenish secara bulk hanya melewati threshold.
    - Pembacaan frame ter-buffer (pasangan HEADERS plus DATA berbiaya satu `read()`), dan `body` / `header_scratch` per stream dipindah ke slice backing per koneksi berukuran `max_body` / `max_header_scratch` alih-alih array inline tetap.
    - Blok header reply yang konstan (`:status 200` + `content-type: application/grpc+proto`, dan trailer `grpc-status: 0`) dienkode HPACK sekali di comptime dan di-memcpy pada jalur panas. `HpackEncoder.writeString` kini menandai hasil Huffman sebagai `?usize` agar encoder berjalan di comptime. Content-type / status lain memakai encoder dinamis.
    - Efek gabungan: unary ~110k ke ~420k req/s pada 256 koneksi, streaming ~2.6k ke ~28k panggilan/s. Lihat ADR-031.

    ---

- Http1 logger field:
    - `Http1ServerConfig.logger: ?*Logger` ditambahkan. Server merutekan baris siklus hidup (listening, fallback EPOLL) melaluinya.
    - Logging akses per-request bersifat handler-side: handler Http1 menulis ke fd dan mengembalikan void, sehingga server tidak dapat mengamati status atau byte respons. Handler memanggil `logger.access()` sendiri (contoh memakai global modul).

    ---

- Http1 examples parity and completion:
    - 9 contoh `http1_*` yang ada disetarakan secara presentasi dengan `http_*` (blok konstanta yang dapat disetel penuh, scaffolding logger berkomentar pada keluarga basic).
    - 6 contoh baru melengkapi set (total 15): `http1_manual_concurrent`, `http1_sse`, `http1_xtra_headers`, `http1_client`, `http1_timeout_resp`, `http1_websocket`.

    ---

- Http1 handler timeout:
    - `Http1ServerConfig.handler_timeout_ms` plus `zix.Http1.setTimeout()` dan `zix.Http1.isExpired()`. Server memasang deadline thread-local sebelum setiap dispatch di keempat model.
    - `statusPhrase` mendapat `408 Request Timeout`. Lihat ADR-029.

    ---

- Http1 websocket:
    - Modul baru `zix.Http1.WebSocket`: codec frame RFC 6455 (`parseFrame` / `buildFrame` / `buildHeader` / `acceptKey`) dan `upgrade()` melalui I/O fd mentah.
    - Loop frame dimiliki engine di bawah `.EPOLL`: handler memanggil `WebSocket.serve(fd, key, on_frame)` untuk menyerahkan koneksi ke loop epoll. Engine meng-echo via `on_frame` per event readable (`fn(fd, opcode, payload) void`), membalas ping dengan pong dan meng-echo close secara otomatis. Tidak ada worker yang terparkir per koneksi.
    - `WebSocket.send` menggabungkan setiap frame yang dihasilkan dalam satu event readable ke satu `write()`, sehingga burst pipelined berbiaya satu syscall, bukan satu per frame.
    - `zix.Http1.WsFrameFn` diekspor. WebSocket milik engine hanya untuk `.EPOLL`: di bawah `.ASYNC` / `.POOL` handoff dibersihkan dan koneksi berakhir. Lihat ADR-030.

    ---

- Http1 large body drain:
    - Di bawah `.EPOLL`, body request yang lebih besar dari `max_recv_buf` tidak lagi mengembalikan `431`. Engine memanggil handler dengan body kosong (endpoint body-besar memakai nilai Content-Length), lalu membaca dan membuang sisa byte body lintas event sehingga koneksi tetap bisa dipakai untuk keep-alive. Body yang muat di buffer tidak berubah.

    ---

- Http client version selector:
    - `zix.Http.Client` mendapat field konfigurasi `version` (`zix.Http.ClientVersion`: `HTTP_1`, `HTTP_2`, `HTTP_3`, default `HTTP_1`).
    - `HTTP_2` dan `HTTP_3` mengembalikan `error.UnsupportedVersion` sampai backend tersedia. Lihat ADR-028.

    ---

- Http1 writesimple hotpath:
    - `zix.Http1.writeSimple` kini membangun header respons dengan encoder byte langsung (`buildSimpleHeader` via `appendStatusCode` / `appendDec` / `appendBytes`), menggantikan `std.fmt.bufPrint`.
    - Body kecil (hingga 3840 byte) disalin bersama header ke satu buffer stack kontigu dan dikirim dengan satu `write()`. Body di atas 3840 byte memakai fallback `writev` inline untuk menghindari penyalinan payload besar.
    - `cachedDate()` memanggil `clock_gettime` hanya setiap 256 request via penghitung tick thread-local, bukan per-request.
    - Terukur ~450k ke ~612k req/s pada c128 dibanding jalur `writev`-saja sebelumnya. Lihat ADR-026.

    ---

- Response header default minimal:
    - Default `HttpServerConfig.max_response_headers` diturunkan dari `.COMMON` (32) ke `.MINIMAL` (16).
    - `zix.Http1`: cap `MAX_HEADERS` 32 ke 16, field baru `Http1ServerConfig.max_headers: u8 = 16`.
    - Perubahan perilaku: handler yang menambahkan 17 hingga 32 header kustom kini mengenai `error.TooManyHeaders` sampai tier dinaikkan. Lihat ADR-027.

    ---

<br>

__*Diperbaiki:*__

- Http1 websocket epoll echo:
    - Echo WebSocket `zix.Http1` tidak bekerja di bawah `.EPOLL`: handshake berhasil tetapi tidak ada frame yang ter-echo. Loop `read()` blocking pada handler langsung mengembalikan `EAGAIN` pada socket non-blocking milik engine. Loop frame milik engine (`WebSocket.serve`, lihat ADR-030) menggantikan pola itu. Contoh `http1_websocket` kini memakai `.EPOLL`.

<br>

## 0.2.2 (2026-06-06)

__*Ditambahkan:*__

- Grpc unary inline dispatch:
    - Route unary (`Route.is_server_streaming = false`, default) kini di-dispatch secara sinkron pada connection thread. Tidak ada alokasi Task per panggilan, tidak ada salinan `header_scratch` 4 KB, tidak ada enqueue `io.async`, tidak ada acquire/release ConnMutex.
    - Route server-streaming memerlukan `is_server_streaming = true` pada entri `Route` untuk menggunakan dispatch thread-per-stream.
    - Field baru pada `zix.Grpc.Route`: `is_server_streaming: bool = false`.

    ---

- Grpc bench fixtures:
    - Menambahkan `examples/grpc_hello_req.bin` dan `examples/grpc_location_req.bin`: fixture biner berframing gRPC untuk benchmarking dengan h2load dan ghz.
    - Perintah benchmark h2load dan ghz ditambahkan ke seluruh 8 contoh server gRPC.

    ---

<br>

__*Diperbaiki:*__

- n/a

<br>

## 0.2.1 (2026-06-05)

__*Ditambahkan:*__

- n/a

<br>

__*Diperbaiki:*__

- Grpc content type:
    - https://codeberg.org/prothegee/zix/issues/67
    - `sendGrpcError` tidak menyertakan `content-type` pada frame HEADERS trailers-only. Client gRPC menolak respons dengan error content-type. Semua frame HEADERS yang dikirim server kini menyertakan `content-type: application/grpc+proto` sesuai spesifikasi gRPC.

<br>

- Grpc concurrent stream:
    - https://codeberg.org/prothegee/zix/issues/68
    - RPC server-streaming bersamaan pada koneksi h2 yang sama dapat mengalami deadlock saat buffer kirim TCP penuh di bawah backpressure. Setiap stream kini di-dispatch pada thread tersendiri yang berbagi write mutex tingkat koneksi, mencegah interleaving frame.

<br>

## 0.2.0 (2026-06-02)

__*Ditambahkan:*__

- Menambahkan TCP raw

- Menambahkan gRPC h2c

- Menambahkan FIX (over TCP)

- Menambahkan EPOLL ke dispatch model

- ASYNC adalah default dispatch model

- Handler/router (Http & gRPC) kini menggunakan comptime

- Dokumentasi dibagi menjadi Bahasa Inggris (en) dan Bahasa Indonesia (id)

<br>

__*Diperbaiki:*__

- n/a

<br>

## 0.1.0 (2026-05-16)

__*Ditambahkan:*__

- Rilis awal, jaringan library Zig 0.16.x (minimum_zig_version: 0.16.0-dev.2974+83c7aba12):
    - HTTP:
        - Server dengan tiga dispatch model: POOL, ASYNC, MIXED
        - Router dengan pencocokan exact, param, dan prefix
        - Middleware (comptime, zero-allocation)
        - WebSocket upgrade
        - Server-Sent Events (SSE)
        - Upload multipart
        - Penyajian berkas statis
        - HTTP client

        ---

    - UDP:
        - Server dan client generik atas tipe paket yang didefinisikan pengguna
        - Snapshot peer broadcast per paket

        ---

    - Unix Domain Sockets (UDS):
        - Server dan client dengan framing

        ---

    - Channel:
        - Pengiriman pesan ring buffer in-process, generik atas tipe elemen

        ---

    - Utils:
        - Helper penyimpanan berkas, resolusi tipe MIME

        ---

<br>

__*Diperbaiki:*__

- n/a

<br>

---

###### end of changelog
