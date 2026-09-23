# README

<h1 align="center">
    <b><i>ZIX</i></b>
</h1>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <b><i>Zero sIX; 06;</i></b>
</p>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Sebuah high-performance network backend library & engine yang ditulis dalam Zig.</i>
</p>

<div align="center">
    <img src="zix-logo.svg" alt="zix-logo" style="display: block; margin: auto;" align="center" width="512px">
</div>

<hr>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Di mana penghubung bertemu kehendak.</i>
</p>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Setiap byte dimiliki, setiap thread dipertimbangkan, setiap rute eksplisit.</i>
</p>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Tanpa cost tersembunyi. Hanya clean-metal dan kode yang transparan - terprediksi berdasarkan prinsip</i>
</p>

<hr>

<p align="center" style="color: #C3C3C3;font-color: #C3C3C3;">
    <i>Kamu adalah pemikir. Pengutak-atik.. Perakit... Pembangun, Bukan hanya pengguna/programmer....</i>
</p>

<br>

# Daftar Isi

- [Dokumentasi](./README-id.md#dokumentasi)
- [Catatan Penting](./README-id.md#catatan-penting)
- [Catatan Kontribusi Penting](./README-id.md#catatan-kontribusi-penting)
- [Repositori](./README-id.md#repositori)
- [Alasan & Motivasi](./README-id.md#alasan-sebuah-motivasi)
- [Fitur Utama](./README-id.md#fitur-utama)
- [Konsistensi Config Server](./README-id.md#konsistensi-config-server)
- [Model Memori](./README-id.md#model-memori)
- [Persyaratan](./README-id.md#persyaratan)
- [Memulai](./README-id.md#memulai)
- [Build](./README-id.md#build)
- [Pengujian](./README-id.md#pengujian)
- [Contoh](./README-id.md#contoh)
    - [HTTP/1](./README-id.md#http1)
    - [Minimal](./README-id.md#contoh-minimal)
    - [Routing](./README-id.md#routing)
    - [Error Handler](./README-id.md#error-handler)
    - [Model Konkurensi](./README-id.md#model-konkurensi)
    - [Timeout](./README-id.md#timeout)
    - [Middleware](./README-id.md#middleware)
    - [WebSocket](./README-id.md#websocket)
    - [SSE](./README-id.md#sse-server-sent-events)
    - [HTTP Client](./README-id.md#http-client)
    - [File Statis & Unggah](./README-id.md#file-statis--unggah)
    - [Kapasitas Header Respons](./README-id.md#kapasitas-header-respons-headersize)
    - [Kapasitas Header Permintaan](./README-id.md#kapasitas-header-permintaan-requestheadersize)
    - [Kesadaran Cache Respons](./README-id.md#kesadaran-cache-respons-response_cache)
        - [Kapan menguntungkan](./README-id.md#kapan-menguntungkan)
        - [Aturan dan kondisi](./README-id.md#aturan-dan-kondisi)
    - [Kesadaran Process Queue](./README-id.md#kesadaran-process-queue-process_queue_len)
        - [Kapan aktif](./README-id.md#kapan-aktif)
        - [Aturan dan sizing](./README-id.md#aturan-dan-sizing)
    - [HTTP/2 h2c](./README-id.md#http2-h2c)
        - [gRPC h2c](./README-id.md#grpc-h2c)
    - [TLS (https / h2)](./README-id.md#tls-https--h2)
    - [Raw TCP](./README-id.md#raw-tcp)
    - [FIX 4.x](./README-id.md#fix-4x)
    - [UDS (Unix Domain Sockets)](./README-id.md#uds-unix-domain-sockets)
    - [Channel](./README-id.md#channel)
    - [UDP](./README-id.md#udp)
    - [HTTP/3](./README-id.md#http3)
    - [WebTransport](./README-id.md#webtransport)
    - [WebRTC](./README-id.md#webrtc)
    - [Logger](./README-id.md#logger)
    - [JSON (jzon)](./README-id.md#json-jzon)
- [Driver](./README-id.md#driver)
- [zixer](./README-id.md#zixer)
- [AI Policies](./README-id.md#ai-policies)

<br>

## Dokumentasi

| Dokumen | Keterangan |
| :- | :- |
| [`docs/hld-http-id.md`](docs/hld-http-id.md) | HTTP: tujuan, model runtime, API, router, WebSocket, SSE, model memori |
| [`docs/hld-http1-id.md`](docs/hld-http1-id.md) | HTTP/1: tujuan engine ramping, model dispatch, model handler, router, WebSocket, model memori |
| [`docs/hld-http2-id.md`](docs/hld-http2-id.md) | HTTP/2: tujuan, model dispatch, mux state machine, HPACK, flow control, TLS, model memori |
| [`docs/hld-tcp-id.md`](docs/hld-tcp-id.md) | TCP stream mentah: tujuan, API, format frame, model dispatch |
| [`docs/hld-udp-id.md`](docs/hld-udp-id.md) | UDP: tujuan, model runtime, API, model paket, endianness, disconnect |
| [`docs/hld-uds-id.md`](docs/hld-uds-id.md) | UDS: tujuan, API, format frame, siklus hidup server/client |
| [`docs/hld-channel-id.md`](docs/hld-channel-id.md) | Channel: tujuan, model, API, persyaratan konkurensi, contoh |
| [`docs/hld-fix-id.md`](docs/hld-fix-id.md) | FIX 4.x: tujuan, gambaran protokol, lapisan sesi, model dispatch, konfigurasi |
| [`docs/hld-grpc-id.md`](docs/hld-grpc-id.md) | gRPC h2c: tujuan, arsitektur, API, 4 tipe RPC, codec, model dispatch |
| [`docs/hld-proxy-id.md`](docs/hld-proxy-id.md) | Reverse proxy (nginx, haproxy) untuk zix.Http1, zix.Http, zix.Grpc |
| [`docs/hld-logger-id.md`](docs/hld-logger-id.md) | Logger: tujuan, API, metode log, format, rotasi file, pemasangan protokol |
| [`docs/hld-tls-id.md`](docs/hld-tls-id.md) | TLS: tujuan, version policy, Tls.Context, alur handshake, integrasi engine, client |
| [`docs/hld-http3-id.md`](docs/hld-http3-id.md) | HTTP/3 (QUIC): tujuan, runtime model, API, router, dispatch model, handshake, QPACK, memory model |
| [`docs/hld-webtransport-id.md`](docs/hld-webtransport-id.md) | WebTransport over HTTP/3: tujuan, kedua dialect, negosiasi session, API, dispatch, flow control, memory model, catatan keamanan |
| [`docs/hld-webrtc-id.md`](docs/hld-webrtc-id.md) | WebRTC: tujuan, runtime model, API, ICE-lite, data channel, forwarding media, dispatch model, memory model |
| [`docs/lld-http-id.md`](docs/lld-http-id.md) | HTTP: struktur data internal dan algoritma |
| [`docs/lld-http1-id.md`](docs/lld-http1-id.md) | HTTP/1: parsing internal, write helper, router, engine EPOLL, codec WebSocket |
| [`docs/lld-http2-id.md`](docs/lld-http2-id.md) | HTTP/2: mux state machine, pool slot stream per worker, cache HPACK, frame loop, flow control, dispatch |
| [`docs/lld-grpc-id.md`](docs/lld-grpc-id.md) | gRPC: helper build/send frame, mux dispatch, pool slot stream per worker, coalescing server-streaming, TLS serve paths |
| [`docs/lld-tcp-id.md`](docs/lld-tcp-id.md) | TCP: struktur data internal dan algoritma |
| [`docs/lld-udp-id.md`](docs/lld-udp-id.md) | UDP: struktur data internal dan algoritma |
| [`docs/lld-uds-id.md`](docs/lld-uds-id.md) | UDS: struktur server/client internal dan penanganan frame |
| [`docs/lld-fix-id.md`](docs/lld-fix-id.md) | FIX: struktur data internal dan algoritma serveConn |
| [`docs/lld-channel-id.md`](docs/lld-channel-id.md) | Channel: internal ring buffer, locking, algoritma send/recv |
| [`docs/lld-logger-id.md`](docs/lld-logger-id.md) | Logger: buffer tulis internal, spinlock, algoritma rotasi |
| [`docs/lld-tls-id.md`](docs/lld-tls-id.md) | TLS: internal wire / handshake / key-schedule / record, validate Tls.Context, jalur serve |
| [`docs/lld-http3-id.md`](docs/lld-http3-id.md) | HTTP/3 (QUIC): internal per-layer (crypto, packet, frame, flow, recovery, QPACK, connection, demux, dispatch) |
| [`docs/lld-webtransport-id.md`](docs/lld-webtransport-id.md) | WebTransport: internal per-file (codepoint draft, capsule, datagram, header stream, session dan pool), hook engine, limitnya |
| [`docs/lld-webrtc-id.md`](docs/lld-webrtc-id.md) | WebRTC: internal per-layer (demux, STUN, ICE, DTLS, SCTP, data channel, SDP, media, dispatch) |
| [`docs/zix-deploy-id.md`](docs/zix-deploy-id.md) | Deployment: bangun Docker image (zig fetch atau vendor) dan konfigurasi TLS context untuk Ed25519 / ECDSA P-256 / RSA |
| [`docs/zix-config-id.md`](docs/zix-config-id.md) | Referensi config: tiap field config dengan default, efek, dan trade-off tuning-nya (engine server plus TLS context) |
| [`docs/concurrency-id.md`](docs/concurrency-id.md) | Model dispatch: ASYNC, EPOLL, URING. Jumlah thread, kecocokan protokol. |
| [`docs/design-considerations-id.md`](docs/design-considerations-id.md) | Pertimbangan desain, design pattern, dan konvensi penamaan |
| [`docs/coding-guideline-id.md`](docs/coding-guideline-id.md) | Coding style: layout source, naming, anatomi file, doc comment, config, test, aturan prosa |
| [`docs/systems-thinking-id.md`](docs/systems-thinking-id.md) | Systems thinking: biaya eksplisit, alokasi terbatas, keterlibatan kernel, tooling measurement, gate dua-sisi |
| [`docs/adr-id.md`](docs/adr-id.md) | Architecture Decision Records |
| [`docs/headers-id.md`](docs/headers-id.md) | Kapasitas header respons: tingkatan, keamanan, penanganan error |
| [`docs/tests-id.md`](docs/tests-id.md) | Tingkatan pengujian (unit / integration / behaviour / edge) dan cara menjalankan |
<!-- | [`rnd/rfc/README.md`](rnd/rfc/README.md) | Checklist conformance MUST / MUST NOT berbasis RFC untuk raw HTTP/1.1, HTTP/2, HTTP/3, dan TLS 1.3 | -->

Dokumentasi driver (setiap README menyebar ke dokumen hld, lld, dan config miliknya):

| Dokumen | Keterangan |
| :- | :- |
| [`docs/driver/postgrez/README-id.md`](docs/driver/postgrez/README-id.md) | Driver PostgreSQL: mulai cepat, init URL dan config, prepared statement, pool, executor |
| [`docs/driver/rediz/README-id.md`](docs/driver/rediz/README-id.md) | Driver Redis: mulai cepat, init URL dan config, pipelining, deferred write-behind, pool |
| [`docs/driver/prometheuz/README-id.md`](docs/driver/prometheuz/README-id.md) | Driver Prometheus: scrape, remote write, query PromQL |

<br>

## Catatan Penting

Zix dispatch model untuk IOCP dan KQUEUE tidak didukung.

__*Platform Development Status:*__ <br>
<img src="https://img.shields.io/badge/x86__64-Linux-brightgreen">
<img src="https://img.shields.io/badge/aarch64-Linux-brightgreen">
<img src="https://img.shields.io/badge/x86__64-Windows-yellow">
<img src="https://img.shields.io/badge/aarch64-MacOS-yellow">
<img src="https://img.shields.io/badge/x86__64-FreeBSD-yellow">
<img src="https://img.shields.io/badge/x86__64-NetBSD-yellow">
<img src="https://img.shields.io/badge/x86__64-OpenBSD-yellow">

> hijau: tervalidasi di hardware native. <br>
> kuning: terverifikasi cross-build (module, examples, test suite, dan runner ter-compile, EPOLL / URING ditolak di run() dengan error.ZixDispatchModelUnsupported, jadi target tersebut memakai ASYNC).

__*Maintained Platforms:*__
- x86_64-linux:
    - Maintainers:
        - @prothegee
    ---
- aarch64-linux:
    - Maintainers:
        - @prothegee
    ---
- x86_64-windows:
    - Mencari kontributor dan maintainer.
    ---
- aarch64-macos:
    - Mencari kontributor dan maintainer.
    ---
- x86_64-freebsd:
    - Mencari kontributor dan maintainer.
    ---
- x86_64-netbsd:
    - Mencari kontributor dan maintainer.
    ---
- x86_64-openbsd:
    - Mencari kontributor dan maintainer.

<br>

## Catatan Kontribusi Penting

- Membantu Zig, membantu Zix.
- Zig harus menjadi ekosistemnya.
- Satu file, satu tanggung jawab.
- Selalu gunakan dan dorong penggunaan Zig dan std-nya.
- Setiap perubahan signifikan memerlukan RnD/PoC.
- Mencakup pengujian yang belum tercakup adalah kontribusi yang baik.
- Persempit pemikiran sistem lalu bersikap eksplisit.
- "Nice to have" dan "mungkin kita perlu ini" bersifat tersier.
- Selalu perbaiki dari sisi kita terlebih dahulu daripada dari sisi fitur Zig.
- Apa pun yang dapat dikontrol atau disesuaikan oleh penelepon/pengguna, sediakanlah hal tersebut bagi mereka jika memungkinkan.
- Jika bias/ambigu, coba diskusikan. Minimal libatkan 1-2 entitas lain.
- Jangan gunakan abstraksi yang bergantung pada mesin atau tujuan tertentu, hindarilah jika memang harus.
- Fast path raw-syscall Linux x86_64/aarch64 itu guarded, perubahan di situ bisa merusak implementasi.
- Kamu dan timmu (Junior/Mid/Senior) menggunakan bahasa selain Inggris, kamu bisa berkontribusi dalam bahasa tersebut.

<br>

### Kontribusi Catatan Ekstra

- [Milestones.](https://codeberg.org/prothegee/zix/milestones)

- [Buka isu baru.](https://codeberg.org/prothegee/zix/issues/new)

- [Coding Guideline.](docs/coding-guideline-id.md)

- [System Thinking Guideline.](docs/systems-thinking-id.md)

- [Pengumuman & Perubahan Besar.](https://codeberg.org/prothegee/zix/issues/238)

<br>

## Repositori

- [Codeberg sebagai Utama](https://codeberg.org/prothegee/zix)
- [Github sebagai Mirror #1](https://github.com/prothegee/zix)

<br>

## Alasan.. Sebuah Motivasi...

<details close>
<summary>Pola Pikir:</summary>

```
Cara kita berpikir, adalah bagaimana sistem dimulai.
Waktu untuk membaca dan berpikir dari baris-baris yang ada,
membuat "kita" berpikir ulang, berdebat, dan mendekati alur program.

Ketika "generasi berikutnya" tidak mau belajar masa lalu dan masa kini. Apa yang akan terjadi?
Jika mereka tidak mau menggunakan/belajar/antusias tentang bahasa dan sistem build, mereka akan..?

Untuk menjadi modern dengan sedikit kerumitan, "keajaiban" harus lebih atau kurang?

Zig (juga bahasa pemrograman lain) dapat melengkapi program yang ada
dan mampu membuat program yang baik, tetapi ketika performa kritis pilihan kita sedikit/sulit.

Pekerjaan saya sebagian besar 80% backend dan 20% frontend.
Jadi sistem jaringan/komunikasi sangat penting di bagian saya.
Dari monolith, micro-service, hingga modular micro-service.

Di awal Zig (sebelum 0.16.x), saya menikmati bahasanya.
Zig fleksibel, tetapi "varian warna" membuat saya kembali ke Go & C++.
Jadi pada pertengahan 2025 rencananya hanya ide dan beberapa desain arsitektur.

Jadi ketika Zig 0.16.x dirilis, dan awal Maret 2026. Saya memulai langkah.
Sekarang saya bisa mendapatkan kembali transparansi, kendali yang lebih, dan pendekatan yang lebih eksplisit.
```

<!--
Mengapa bukan rust:
- Terlalu banyak "gunakan saja tokio/smol" membuat saya berpikir ulang.
- Kode Rust saya sebagai profesional masih 70% sync, sedikit async.
- Rust dalam kasus saya untuk melengkapi sistem yang ada, pembaca/penulis QR & Barcode menggantikan C++.
-->

</details>

<br>

<details open>

<summary>Prinsip-prinsip motivasi:</summary>

__*1. Eksplisit Daripada Implisit.*__

__*2. Modular & Dapat Dirawat.*__

__*3. Arsitektur Mengutamakan Performa.*__

__*4. Fitur Praktis, Siap Digunakan.*__

__*5. Model Konkurensi Modern yang Efisien.*__

__*6. Manajemen Memori yang Dapat Diprediksi dan Transparan.*__

> Kami mengutamakan kejelasan, kontrol, dan performa.

</details>

<br>

## Fitur Utama

__*0. Zero dependencies:*__

Hanya Zig standard library. Tanpa paket pihak ketiga (dependency set `build.zig.zon` kosong),
tanpa C library, dan tanpa linking libc: TLS 1.3 / 1.2 berjalan pure-Zig di atas `std.crypto`
(tanpa OpenSSL), gzip / deflate di `std.compress.flate` plus encoder gzip cepat in-tree untuk
body dinamis kecil, dan brotli, QUIC, HPACK, serta QPACK ditulis in-tree dari RFC masing-masing.

> Satu `zig build` mengompilasi seluruh stack dari source tanpa ada yang perlu di-vendor,
di-pin, atau terus di-patch, jadi supply chain-nya adalah Zig toolchain plus repository ini.

<br>

__*1. Stack protokol lengkap dalam satu tempat:*__

Tcp (raw), Udp, Uds (Unix domain sockets), Http (HTTP/1.1), Http1 (varian
hot-path-optimized), Http2 (h2c), Http3 (HTTP/3 melalui QUIC, plus WebTransport over HTTP/3), Webrtc
(data channel dan media), Grpc (gRPC melalui h2c), Fix (FIX 4.x), plus Channel dan Logger.

> Satu model memori/threading yang koheren untuk backend monolith, micro-service, dan
modular-micro-service, alih-alih menggabungkan banyak library terpisah dengan
konvensi yang berbeda.

<br>

__*2. Library client di seluruh stack:*__

Setiap engine mengirimkan client yang cocok: `zix.Http.Client`, client gRPC, dan client `zix.Tcp`, `zix.Udp`, `zix.Uds`, dan `zix.Fix` mentah, plus client SSE (`sse_client`) dan WebSocket (`ws_client`) khusus.

> Panggil dan uji service-mu sendiri dengan library yang sama yang melayaninya, alih-alih mem-vendor client terpisah per protokol.

<br>

__*3. Tiga model dispatch yang dapat dipilih:*__

- ASYNC (satu accept thread, io.async() per koneksi): latensi terendah pada beban moderat, dan satu-satunya model yang tersedia di semua platform.
- EPOLL (shared-nothing: setiap worker memiliki SO_REUSEPORT listener + epoll instance, level-triggered, tanpa antrian bersama): khusus Linux, terbaik untuk jumlah koneksi tinggi.
- URING (shared-nothing io_uring: topologi thread-per-core yang sama dengan EPOLL, tetapi completion-based sehingga sebagian besar transisi syscall di-batch ke dalam ring): khusus Linux.

> Strategi konkurensi adalah pilihan konfigurasi yang disengaja, bukan default implementasi. Http1, Http, Grpc, Fix, dan Http2 mengimplementasikan ketiganya secara native di Linux. Di luar Linux, EPOLL dan URING ditolak di run() alih-alih diturunkan diam-diam, jadi pemanggil tidak pernah mengira mendapat model yang tidak ia dapatkan.

<br>

__*4. Arsitektur shared-nothing:*__

Di bawah `.EPOLL` dan `.URING` setiap worker memiliki listener SO_REUSEPORT pribadi, event loop-nya sendiri, slab koneksi, dan response cache, tanpa queue bersama, tanpa handoff fd antar-thread, dan tanpa locking. State dipartisi berdasarkan kepemilikan, bukan dijaga oleh mutex.

> Menskala dengan menambah worker independen, satu per core, jadi hot path tidak pernah berebut dan response cache lock-free berdasarkan kepemilikan.

<br>

__*5. Konfigurasi eksplisit dan flat:*__

Tanpa sub-config bertingkat: setiap field (mis. dispatch_model, max_response_headers: .MINIMAL, workers) berada di level teratas dan eksplisit.

> Dapat diprediksi sebagai prinsip. Kamu melihat persis apa yang server lakukan tanpa
menelusuri default yang diwariskan.

<br>

__*6. HTTP/1 zix.Http1 yang dioptimasi pada hot-path:*__

- Menghapus HeadParser, header Date yang di-cache secara thread-local, sendSimpleFD yang dikonsolidasi, serveConn(fd, handler, opts), kapasitas response-header yang dapat dikonfigurasi.

> Memangkas jalur request umum tanpa mengorbankan API yang eksplisit.

<br>

__*7. Penanganan request HTTP yang composable:*__

Router comptime dengan parameter path (`matchParam`) yang dibagikan oleh `zix.Http` dan `zix.Http1`, komposisi wrapper comptime untuk middleware di kedua engine (fungsi handler-masuk, handler-keluar, lihat [Middleware](./README-id.md#middleware)), static file serving, parsing multipart dan file upload (`multipart.Parser`), dan parsing HTTP range request (`parseRange`) untuk partial content.

> Setiap bagian adalah bagian engine yang eksplisit dan opt-in, dengan pencocokan route diselesaikan saat compile time. Kamu menyusun hanya apa yang dibutuhkan sebuah request alih-alih mewarisi pipeline tetap.

<br>

__*8. WebSocket dan SSE (kedua engine HTTP):*__

WebSocket yang dikelola engine pada `zix.Http` dan `zix.Http1` (RFC 6455, ping auto-pong, close auto-echo, broadcast fan-out, write coalescing per-event di model multiplexed), tersedia di semua dispatch model, dan Server-Sent Events dengan client SSE yang cocok.

> Koneksi long-lived bergaya push ditangani oleh engine itu sendiri, bukan ditempelkan di dalam handler.

<br>

__*9. Multiplexed gRPC (h2c):*__

Multiplexed async epoll dengan resumable HTTP/2 state machine, blok reply HPACK yang di-cache saat comptime, initial window besar, buffered reads, max_streams=128 untuk menghindari REFUSED_STREAM burst. Context timeout (handler_timeout_ms, Route.timeout_ms, ctx.isExpired()).

> Keempat tipe RPC (unary, server streaming, client streaming, bidirectional)
dimultipleks melalui satu koneksi h2c tanpa thread per stream, dengan deadline client
dihormati end-to-end. Service internal berbicara gRPC secara langsung, tanpa TLS
terminator atau sidecar.

<br>

__*10. FIX 4.x:*__

FixContext, sebuah struct MsgType (47 konstanta), routing berbasis session, contoh trading.

> Pesan finansial domain-specific sebagai warga engine, bukan ditempelkan ke raw
TCP.

<br>

__*11. Channel (primitive konkurensi dan IPC bertipe):*__

`Channel(T)` bounded generik dengan `send` / `recv` / `close` dan semantik drain-after-close, dapat dipakai untuk fan-out in-process, worker pool, dan koordinasi antar-proses.

> Blok bangunan kecil dan bertipe untuk mengoordinasi kerja, primitive yang sama baik peer-nya thread maupun proses.

<br>

__*12. Logger yang sadar protokol:*__

Tipe log per protokol: conn (TCP), packet (UDP), frame (UDS), session (FIX), rpc (gRPC), access() khusus HTTP, Channel khusus system.

> Kosakata log cocok dengan unit kerja aktual pada setiap protokol.

<br>

__*13. Kesadaran Cache Respons:*__

Response cache opt-in per-worker yang dibagikan oleh `zix.Http1`, `zix.Http`, dan `zix.Grpc`. Handler membangun respons sekali, engine menyimpannya di bawah key yang diturunkan dari request, dan request cocok berikutnya memutar ulang byte tersimpan tanpa rebuild dan tanpa re-serialization. Data oriented (structure of arrays plus satu flat payload slab), lock-free by ownership (satu instance per owner thread, tidak pernah dibagi), dengan TTL lazy on-access. Aktif di semua dispatch model: satu cache per multiplexed worker, satu per io pool thread pada `.ASYNC`.

> Alat yang kamu pakai secara sengaja, bukan layer tersembunyi. Menguntungkan di atas body ~4 KiB (JSON berat ~32 KiB terukur +34% throughput) dan zero-regression wash di bawahnya.

<br>

__*14. Kesadaran Process Queue:*__

Backpressure submission-queue per-worker yang opt-in pada `zix.Http1` dan `zix.Http` di bawah `.URING`. Saat burst mengisi submission queue io_uring, re-arm recv atau send yang seharusnya menutup koneksi diparkir pada FIFO ring per-worker (hanya referensi, fd plus generation, reject-newest) dan dicoba ulang pada loop pass berikutnya. `process_queue_len` mengatur panjang ring, `0` (default) mematikannya. Tanpa efek pada dispatch model lain.

> Katup keandalan, bukan knob throughput. Di bawah accept storm atau churn koneksi ia menjaga kerja overflow tetap berjalan alih-alih membuang koneksi, dan terukur no-op saat submission queue tidak jenuh.

<br>

__*15. TLS pure-Zig (https, h2, wss):*__

TLS 1.3 dengan floor TLS 1.2, di atas `std.crypto`, tanpa OpenSSL. Opt-in dan additive: `zix.Http1` dan `zix.Http` menyajikan https/1.1, `zix.Http2` dan `zix.Grpc` menyajikan h2 di atas TLS (ALPN h2), dan SSE serta WebSocket berjalan di atas TLS (wss) pada jalur thread-per-koneksi. Sertifikat server bisa ECDSA P-256, Ed25519, atau RSA, dikonfigurasi oleh `Tls.Context` milik pemanggil (curve / cipher tervalidasi, HSTS). Client native yang memverifikasi (`zix.Tls.Client`) memeriksa chain dan hostname.

> Transport terenkripsi adalah gate config di depan engine cleartext yang tak berubah, bukan server terpisah, jadi handler yang sama menyajikan http dan https.

<br>

__*16. HTTP/3 di atas QUIC, pure-Zig:*__

`zix.Http3` menyajikan HTTP/3 (RFC 9114) di atas QUIC (RFC 9000 / 9001 / 9002), dibangun dari RFC di atas `std.crypto`: packet protection, handshake TLS 1.3 di atas CRYPTO stream, loss recovery, QPACK, dan dispatch per-core di atas substrat `zix.Udp`. `Router` comptime dan `Tls.Context` yang sama dengan engine TCP. `zix.Webtransport` melengkapinya dengan WebTransport over HTTP/3 (RFC 9220 / 9297 / 9221): session, stream data yang reliabel, dan datagram yang tidak reliabel dimultipleks di koneksi yang sama, berbicara draft-ietf-webtrans-http3-16 dan dialect draft-07 deployed yang masih dikirim browser.

> Transport HTTP terbaru hadir in-tree tanpa C QUIC library, berbagi router dan config TLS yang sudah dipakai untuk HTTP/1 dan HTTP/2, dan binding WebTransport yang menghadap browser menumpang koneksi, sertifikat, serta congestion controller yang sama.

<br>

__*17. Peer WebRTC, pure-Zig:*__

`zix.Webrtc` menjawab browser lewat WebRTC: ICE-lite (RFC 8445) di atas STUN, DTLS 1.2 (RFC 6347), data channel SCTP (RFC 9260 / 8831 / 8832), offer dan answer SDP, serta forwarding media SRTP opsional (RFC 3711 / 5764), semuanya di satu port UDP dan semuanya ditulis dari RFC di atas `std.crypto`. Media diteruskan, tidak pernah didekode: tidak ada codec di dalam engine.

> Satu-satunya transport yang ditawarkan browser yang memberi pengiriman tidak reliabel, urutan per channel, serta audio dan video, tanpa C WebRTC library dan dengan bentuk config serta dispatch model yang sama seperti engine lain.

<br>

__*18. Kompresi respons (gzip / deflate / brotli):*__

Negosiasi `Accept-Encoding` pada `zix.Http1` dan `zix.Http`: gzip dan deflate di atas `std.compress.flate` (body dinamis kecil memakai encoder gzip cepat in-tree), plus brotli dari encoder / decoder in-tree yang ditulis dari RFC 7932 (`std` tidak punya brotli). Opt-in per server, dengan size floor, skip media-type yang sudah ter-compressed, dan `Vary: Accept-Encoding`. HTTP/3 menyajikan body statis pre-compressed dengan `content-encoding`.

> Respons lebih kecil di jaringan nyata tanpa dependensi kompresi, mati secara default jadi hot path cleartext tak tersentuh sampai di-opt-in.

<br>

__*19. Routing comptime, tanpa alokasi:*__

Satu `Router` comptime yang dibagikan oleh `zix.Http`, `zix.Http1`, `zix.Http2`, `zix.Grpc`, dan `zix.Http3`: route table adalah argumen comptime, jadi matching (`.EXACT` via `StaticStringMap`, `.PARAM`, `.PREFIX` longest-prefix, query di-strip lebih dulu) tidak melakukan alokasi runtime.

> Biaya routing dibayar saat compile-time, jadi jalur request tidak menambah traffic heap dan setiap engine mencocokkan path dengan cara yang sama.

<br>

__*20. Memori terbatas, proporsional terhadap kerja:*__

Alokasi eksplisit dan ter-cap: satu arena per koneksi atau request, pool slot-stream per-worker pada engine h2 / gRPC multipleks (memori stream residen mengikuti stream konkuren, bukan connections * max_streams, memangkas footprint 4096-koneksi 6 sampai 12x), dan response cache lock-free. Tanpa pertumbuhan heap per-request yang tersembunyi.

> Memori mengikuti kerja in-flight, bukan jumlah koneksi, jadi footprint tetap terprediksi dari idle sampai saturasi.

<br>

__*21. Harness test conformance yang hermetik:*__

Test berjalan tanpa tool eksternal: runner 69-protokol yang menggerakkan client native buatan sendiri (raw socket, client QUIC native, TLS native), plus unit test vektor-RFC untuk codec wire (TLS key schedule, HPACK / QPACK, packet QUIC), ditemukan lewat `std.testing.refAllDecls`.

> Kebenaran diperiksa terhadap RFC secara in-tree tanpa curl / openssl / websocat, jadi suite-nya reproducible di mana pun toolchain bisa build.

<br>

__*22. Static file serving dengan dukungan range:*__

`public_dir` pada keempat engine HTTP menyajikan route yang tak cocok sebagai file sebelum fallback 404, dengan pemeriksaan path aman-traversal, dan companion upload multipart (`public_dir_upload`) pada `zix.Http` dan `zix.Http1`. Range request (RFC 7233, 206 / 416) disajikan pada `zix.Http`, `zix.Http1`, dan `zix.Http2`, hanya file utuh pada `zix.Http3`.

Atur `public_dir_cache_ttl_ms` di atas 0 agar file yang sudah di-resolve tetap terbuka dengan header responsnya sudah dirender, sehingga request berikutnya hanya membayar satu hash lookup alih-alih open plus stat, dan sibling terkompresi `.br` atau `.gz` di-resolve sekali dari disk alih-alih diprobe per request. Default-nya mati, dan pada `zix.Http3` inilah yang mengaktifkan penyajian static sama sekali (lihat [Configuration](./docs/zix-config-id.md)).

> Aset statis dan upload disajikan oleh engine pada port yang sama dengan API, tanpa file server terpisah.

<br>

__*23. Dokumentasi multi-bahasa:*__

Setiap dokumen punya variannya sendiri.

> Dukungan: en - English, id - Bahasa

<br>

## Konsistensi Config Server

Setiap config server berbagi satu kosakata: konsep yang sama memakai nama field dan tipe yang sama di `zix.Tcp`, `zix.Http1`, `zix.Http`, `zix.Grpc`, dan `zix.Fix`. Memindahkan config antar protokol bersifat mekanis, bukan belajar ulang. Field berikut umum untuk semuanya:

| Field | Tipe | Arti |
| :- | :- | :- |
| `io` | `std.Io` | Backend I/O, wajib, harus hidup lebih lama dari server |
| `ip` | `[]const u8` | Alamat bind |
| `port` | `u16` | Port bind, harus bukan nol |
| `dispatch_model` | `DispatchModel` | `.ASYNC`, `.EPOLL`, `.URING` (wajib, tidak ada default) |
| `kernel_backlog` | `u31` | Backlog listen TCP |
| `workers` | `usize` | Jumlah worker accept atau EPOLL, `0` memilih cpu_count |
| `logger` | `?*Logger` | Logger opsional, milik pemanggil |

Field buffer, socket, timeout, dan cache memakai nama yang sama di mana pun protokol memiliki fitur tersebut:

| Field | Tipe | Ada di |
| :- | :- | :- |
| `max_recv_buf` | `usize` | semua server engine (cap per-frame, read buffer, atau slot datagram per engine) |
| `large_body_rcvbuf` | `usize` | `zix.Http1`, `zix.Http` |
| `busy_poll_us` | `u32` | `zix.Http1`, `zix.Http`, `zix.Http2`, `zix.Grpc`, `zix.Udp` raw, `zix.Http3` |
| `reuseport_cbpf` | `bool` | semua server engine kecuali `zix.Uds` (grup listener atau socket `.EPOLL` / `.URING`) |
| `conn_timeout_ms` | `u32` | `zix.Http`, `zix.Fix`, `zix.Udp` |
| `handler_timeout_ms` | `u32` | `zix.Http1`, `zix.Http`, `zix.Grpc`, `zix.Fix` |
| `response_cache` dan empat field `cache_*` | lihat [Kesadaran Cache Respons](#kesadaran-cache-respons-response_cache) | `zix.Http1`, `zix.Http`, `zix.Grpc` |
| `process_queue_len` | `usize` | `zix.Http1`, `zix.Http` (park ring submission-queue `.URING`, lihat [Kesadaran Process Queue](#kesadaran-process-queue-process_queue_len)) |
| `compress`, `compression_min_size`, `compression_max_out` | `bool` / `usize` / `usize` | `zix.Http1`, `zix.Http` |
| `webtransport` | `zix.Webtransport.Config` | `zix.Http3` (WebTransport over HTTP/3: session, stream, datagram, lihat [WebTransport](#webtransport)) |

Beberapa perbedaan disengaja, bukan drift:

- `zix.Http1` tidak punya `conn_timeout_ms`: ia tidak menjalankan timer thread connection-registry (lihat catatan Timeout di docs LLD HTTP/1).
- `zix.Http2` dan `zix.Grpc` memakai `max_recv_buf` sebagai floor read-buffer per koneksi dan mengukur data per-stream dengan field protokol (`max_body`, `max_frame_size`, `max_header_scratch`).
- Kompresi response runtime (`compress` plus ukuran `compression_*`, engine mengompresi secara langsung) ada di `zix.Http1` dan `zix.Http`, yang menegosiasi terhadap Accept-Encoding dan mengompresi body sendiri. `zix.Http3` juga menegosiasi tapi tidak membawa codec runtime: handler membaca `req.accept_encoding` dan menyetel `res.content_encoding` pada body yang sudah ter-compressed (menyajikan file `.br` / `.gz`), jadi tidak ada config `compress` padanya. `zix.Grpc` memakai kompresi `grpc-encoding` per-message miliknya sendiri, dan raw transport (`zix.Tcp`, `zix.Udp`, `zix.Uds`, `zix.Fix`) tidak punya negosiasi konten HTTP.
- `zix.Udp` (datagram) membawa `ip` / `port` / `logger` untuk jalur typed, plus knob jalur raw `dispatch_model` / `workers` / `reuse_address` / `recv_batch` / `send_batch` / `max_recv_buf` (dipakai `zix.Udp.Raw`). `zix.Uds` (local socket) membawa `kernel_backlog` / `max_recv_buf` / `logger` plus path socket-nya. Tiap engine hanya mengambil subset yang berlaku.

Untuk referensi per-field lengkap (tiap field config dengan default-nya, apa yang dipengaruhi, kapan dinaikkan atau diturunkan, dan trade-off-nya), lihat [`docs/zix-config-id.md`](./docs/zix-config-id.md).

<br>

## Model Memori

### HTTP

| Cakupan | Allocator | Masa hidup |
| :- | :- | :- |
| Tabel rute | tanpa biaya heap | N/A |
| Buffer I/O baca/tulis | `smp_allocator` | Koneksi |
| Alokasi per-permintaan (`ctx.allocator`) | `ArenaAllocator` per-koneksi, direset setiap permintaan | Permintaan |

Handler menerima `ctx.allocator`, sebuah arena yang direset di antara permintaan. Alokasi apa pun yang dibuat di dalam handler secara otomatis direklamasi di akhir permintaan tanpa panggilan `free`.

Rute dibakukan comptime ke dalam tipe server pada `zix.Http1`; pada `zix.Http` handler adalah field `HandlerFn` runtime (ADR-063), dibangun dari `Router` comptime. Keduanya sama-sama tidak memerlukan allocator untuk penyimpanan rute.

### UDP

| Cakupan | Allocator | Masa hidup |
| :- | :- | :- |
| Daftar rekaman client | `config.allocator` (milik pemanggil) | Masa hidup proses server |
| Snapshot peer (broadcast) | `config.allocator` | Dispatch satu paket |
| Buffer terima | Stack | Satu iterasi loop terima |

`config.allocator` harus berupa general-purpose allocator (misalnya `std.heap.smp_allocator`). `ArenaAllocator` tidak cocok: snapshot peer broadcast dialokasikan dan dibebaskan per paket: `ArenaAllocator.free()` adalah no-op, sehingga snapshot menumpuk tanpa batas hingga server berhenti. Lihat [`docs/hld-udp-id.md`](docs/hld-udp-id.md) untuk penjelasan lengkap dan PoC.

Jalur raw (`zix.Udp.Raw`,) mengalokasikan recv / send batch dan array worker-thread-nya dari `config.allocator` sekali saat startup, bukan per paket, jadi caveat arena tidak berlaku di sana.

### HTTP/2 dan gRPC

Mux `.EPOLL` / `.URING` HTTP/2 dan gRPC sama-sama memakai pool slot stream per worker, jadi memori stream residen mengikuti stream konkuren, bukan `max_streams` per koneksi. Model thread-path (`.ASYNC`) tetap memakai array stream per-koneksi yang dialokasikan heap (alokasi stack dari `max_streams` struct `Stream` akan meluap stack thread). Handler menerima trio `req`/`res`/`ctx` yang sama seperti engine lainnya (ADR-063): `ctx.allocator` adalah arena per-permintaan yang didukung buffer stack tetap (tanpa pemanggilan heap), direset per permintaan, bukan per koneksi.

### WebTransport over HTTP/3

`zix.Webtransport` adalah fitur `zix.Http3`, jadi ia menambah satu pool milik worker dan tidak menambah apa pun per paket.

| Cakupan | Allocator | Lifetime |
| :- | :- | :- |
| Worker pool (slot session, slot stream, send buffer, buffer pra-session) | `config.allocator`, sekali saat worker mulai | Lifetime worker, dilepas saat worker keluar |
| Slot session | di dalam pool | Lifetime session, didaur ulang saat close |
| Slot stream data dan send buffer-nya | di dalam pool, satu alokasi terpisah untuk semua buffer | Lifetime stream, didaur ulang saat kedua half stream selesai |
| Buffer stream pra-session | di dalam pool | Sampai session-nya muncul, atau sampai stream-nya ditolak |
| State WebTransport per koneksi (`Connection.wt`) | inline di slot koneksi | Lifetime koneksi, ukuran tetap (tanpa heap per paket) |

Jalur receive tidak mengalokasi apa pun: session dan stream datang dari pool, dan pool mengembalikan null alih-alih tumbuh, sehingga peer tidak bisa memaksa server mengalokasi. Biaya memori WebTransport satu worker persis `pool_streams * stream_send_bytes` plus `pool_orphan_streams * pool_orphan_bytes` (1 MiB send buffer plus 8 KiB buffer orphan pada default), dibayar sekali dan tidak bergantung pada jumlah koneksi. `zix.Webtransport.capacityError` menolak config yang melewati plafon compile-time alih-alih memotong fitur secara diam-diam.

Sizing pool lengkap dan biaya per koneksi ada di [`docs/hld-webtransport-id.md`](docs/hld-webtransport-id.md).

Untuk detail memori lengkap lihat [`docs/hld-http-id.md`](docs/hld-http-id.md) dan [`docs/hld-udp-id.md`](docs/hld-udp-id.md). Untuk model threading lihat [`docs/concurrency-id.md`](docs/concurrency-id.md).

<br>

## Persyaratan

- [Zig](https://ziglang.org/):
    - [x] 0.16.x:
        - 0.16.0
    - [x] 0.17.x (Experimental):
        - 0.17.0-dev.1933+e19a73c2d

<br>

## Memulai

Ambil zix ke proyekmu:

Lakukan zig fetch save https: <br>
`codeberg.org`
```sh
zig fetch --save "https://codeberg.org/prothegee/zix/archive/MAJOR.MINOR.x.tar.gz"
```
`github.com`
```sh
zig fetch --save "https://github.com/prothegee/zix/archive/refs/heads/MAJOR.MINOR.x.tar.gz"
```

<br>

Atau,

gunakan zig fetch save git+https: <br>
`codeberg.org`
```sh
zig fetch --save "git+https://codeberg.org/prothegee/zix#MAJOR.MINOR.x"
```
`github.com`
```sh
zig fetch --save "git+https://github.com/prothegee/zix#MAJOR.MINOR.x"
```

> Gunakan `.../zix#main` untuk upstream.

<br>

Tambahkan ke proyekmu (file `build.zig`):

```zig
// const exe = ...;

const zix = b.dependency("zix", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zix", zix.module("zix"));

// ...
```

<br>

## Build

zix dikonsumsi sebagai Zig module (source), bukan dikirim sebagai library prebuilt. Repositori mendefinisikan module `zix` dengan `b.addModule`, jadi tidak ada artifact `addStaticLibrary` atau `addSharedLibrary`. Menjalankan `zig build` sendirian menjalankan step `install` default tanpa ada yang diinstal: tidak ada `.a`, tidak ada `.so`, tidak ada apa pun di bawah `zig-out/lib`. Ia meng-compile module graph dan hanya berguna sebagai pengecekan cepat "apakah masih compile".

Entry point yang sebenarnya adalah step bernama. Daftarkan kapan saja dengan `zig build -l`:

| Step | Fungsinya |
| :- | :- |
| `zig build` | Hanya meng-compile module graph. Tidak ada artifact yang dihasilkan, karena zix adalah source module. |
| `zig build test-all` | Menjalankan tes unit, integration, behaviour, dan edge. |
| `zig build unit-test` | Menjalankan tes unit saja. Juga `integration-test`, `behaviour-test`, `edge-test`. |
| `zig build examples` | Membangun setiap example ke `zig-out/bin/`. Binary dinamai `zix-example-<name>-<arch>-<os>-<optimize>`, jadi hasil build beberapa target dan beberapa optimize mode bisa hidup berdampingan. Tanpa `-Doptimize`, mode-nya `debug`. |
| `zig build example-<group>` | Membangun satu grup example, misalnya `example-http1` atau `example-grpc`. |
| `zig build example-<name>` | Membangun satu example ke `zig-out/bin/`, misalnya `example-http1_websocket`. Binary yang terinstal membawa target triple dan optimize mode, jalankan dari sana. |
| `zig build test-runner-<name>` | Menjalankan pengecekan integrasi server plus client, misalnya `test-runner-http1-websocket`. |
| `zig build test-runner-all` | Menjalankan setiap runner integrasi server plus client. |

Binary example yang dibangun ada di `zig-out/bin/`. Untuk membangun semua example, lalu menjalankan satu di background dan menghentikannya:

```sh
zig build examples                                             # bangun setiap example ke zig-out/bin/
./zig-out/bin/zix-example-http1_websocket-x86_64-linux-debug & # jalankan satu di background
kill %1                                                        # hentikan
```

Setiap step menerima `-Dtarget=<arch>-<os>`, mencakup tujuh target: x86_64-linux, x86_64-windows, aarch64-macos, aarch64-linux, x86_64-freebsd, x86_64-netbsd, x86_64-openbsd. Pada target foreign, step tes dan runner meng-compile semuanya dan melewati eksekusi dengan warning. `scripts/build-all-targets.sh` menyapu setiap opsi build zix dan para driver di ketujuh target.

Tidak ada output library `zig build install` dan tidak ada `-Doptimize` yang diperlukan untuk pengecekan compile biasa. Untuk mengonsumsi zix di proyek lain, ikuti Memulai di atas: ia ditambahkan sebagai dependency `build.zig.zon` dan diimpor dengan `exe.root_module.addImport("zix", zix.module("zix"))`, tidak pernah di-link sebagai system library.

<br>

## Pengujian

```sh
zig build unit-test        # pengujian unit (tes inline src/)
zig build integration-test # pengujian integrasi (komponen terhubung)
zig build behaviour-test   # pengujian behaviour (kontrak API yang dapat diamati)
zig build edge-test        # pengujian edge (kondisi batas dan jalur error)
zig build test-all         # semua di atas
```

`zig build` saja tidak menjalankan tes. Lihat [`docs/tests-id.md`](docs/tests-id.md) untuk detail cakupan lengkap.

Cross-target: dengan `-Dtarget` foreign, setiap suite ter-compile untuk target itu dan eksekusi dilewati dengan warning. Di host non-Linux, tes yang menguji jalur EPOLL / URING (Linux-only) mencetak warn lalu skip, jadi suite tetap hijau di setiap platform yang didukung.

<br>

## Contoh

Untuk contoh lebih lengkap lihat direktori `examples`.

Jalankan `zig build examples` untuk membangun semua contoh (baca `build.zig` untuk detail lebih lanjut).

### HTTP/1

Zix memiliki dua model API untuk HTTP/1, `zix.Http` dan `zix.Http1`.

`zix.Http` bergantung pada `std.http` Zig dan berfungsi sebagai pendekatan yang mudah, sedangkan `zix.Http1` tidak.

**Kapan digunakan:** kedua engine berbagi handler trio yang sama (`fn(*Request, *Response, *Context) anyerror!void`, permukaan caller-identical, ADR-062), router comptime yang sama, dan model dispatch yang sama. Pilih `zix.Http` saat kamu ingin layer berfitur lengkap (client stack, penanganan body yang lebih kaya). Pilih `zix.Http1` saat kamu ingin engine hot-path yang ramping dengan overhead per-request terendah: trio-nya adalah stack view plus arena reset, dan helper tulis fd mentah tetap tersedia sebagai escape hatch.

<br>

### Contoh Minimal

Auto I/O (work-queue thread pool, default):
```zig
const std = @import("std");
const zix = @import("zix");

pub fn homeHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req; _ = ctx;
    try res.send("hello from zix");
}

pub fn main(process: std.process.Init) !void {
    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io   = process.io,
        .ip   = "127.0.0.1",
        .port = 9000,
    });
    defer server.deinit();
    try server.run();
}
```

Manual I/O (batas konkurensi eksplisit via `concurrent_limit`, dispatch `.ASYNC`):
```zig
pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{
        .concurrent_limit = std.Io.Limit.limited(4), // pin ke 4 tugas concurrent
        // .concurrent_limit = .unlimited             // biarkan runtime memutuskan
    });
    defer threaded.deinit();

    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io             = threaded.io(),
        .ip             = "127.0.0.1",
        .port           = 9000,
        .dispatch_model = .ASYNC, // .ASYNC menggunakan io pemanggil secara langsung
    });
    defer server.deinit();
    try server.run();
}
```

**Contoh:**
- [examples/http_basic.zig](examples/http_basic.zig) - model dispatch dipilih per target (`.URING` di Linux, `.ASYNC` di platform lain)
- [examples/http_manual_concurrent.zig](examples/http_manual_concurrent.zig) - kontrol konkurensi eksplisit via `Io.Threaded`
- [examples/http1_basic.zig](examples/http1_basic.zig) - `zix.Http1` mentah: model dispatch dipilih per target
- [examples/http1_json.zig](examples/http1_json.zig)
- [examples/http1_jzon.zig](examples/http1_jzon.zig) - body JSON masuk dan body JSON keluar lewat [jzon](./README-id.md#json-jzon)
- [examples/http1_params.zig](examples/http1_params.zig)
- [examples/http1_paths.zig](examples/http1_paths.zig)
- [examples/http1_query.zig](examples/http1_query.zig) - method QUERY (RFC 10008)
- [examples/http1_middleware.zig](examples/http1_middleware.zig)
- [examples/http1_cache.zig](examples/http1_cache.zig)
- [examples/http1_manual_concurrent.zig](examples/http1_manual_concurrent.zig)

**Kapan digunakan:** mulai dari sini untuk layanan HTTP biasa. Auto I/O (default) adalah jalur paling sederhana dan membiarkan runtime mengukur thread pool-nya sendiri. Beralih ke manual I/O dengan `concurrent_limit` hanya saat kamu harus membatasi konkurensi secara eksplisit: memori terbatas, anggaran worker tetap, atau load test deterministik.

<br>

### Routing

Rute didaftarkan pada waktu kompilasi via `zix.Http.Router(&[_]zix.Http.Route{...})`, dan `.dispatch` diteruskan ke `Server.init`. Setiap entri `Route` memiliki `path`, `handler`, dan `kind` opsional (`.EXACT` secara default):

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/about",           .handler = aboutHandler },
    // exact (default): hanya cocok dengan /about

    .{ .path = "/api",             .handler = apiHandler,    .kind = .PREFIX },
    // prefix: cocok dengan /api, /api/foo, /api/foo/bar, TIDAK /apiv2

    .{ .path = "/users/:id",       .handler = userHandler,   .kind = .PARAM },
    // param: cocok dengan /users/alice, menangkap id="alice"
    // baca di dalam handler: req.pathParam("id")

    .{ .path = "/:tenant/:branch", .handler = branchHandler, .kind = .PARAM },
    // multi-param: req.pathParam("tenant"), req.pathParam("branch")
}).dispatch, .{ .ip = "127.0.0.1", .port = 9000 });
```

**Prioritas:**

```
exact  >  param  >  prefix (prefix lebih panjang mengalahkan yang lebih pendek)
```

Prioritas exact dan prefix tidak bergantung pada urutan pendaftaran. **Rute param adalah pengecualian**: ketika dua pola memiliki jumlah segmen yang sama dan keduanya cocok, entri pertama dalam tabel rute yang menang. Daftarkan pola yang lebih literal sebelum pola all-param dengan kedalaman yang sama:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    // Urutan yang benar: /path/user/:id menang untuk /path/user/alice
    .{ .path = "/path/user/:id",        .handler = userHandler,   .kind = .PARAM },
    .{ .path = "/path/:tenant/:branch", .handler = tenantHandler, .kind = .PARAM },
}).dispatch, .{ ... });
```

| Terdaftar | Permintaan | Pemenang | Alasan |
| :- | :- | :- | :- |
| `/path/info` (exact) + `/path/:id` (param) | `/path/info` | `/path/info` | exact mengalahkan param |
| `/path/:id` (param) + `/path` (prefix) | `/path/alice` | `/path/:id` | param mengalahkan prefix |
| `/api/v2` + `/api` (keduanya prefix) | `/api/v2/foo` | `/api/v2` | prefix lebih panjang menang |
| `/path/user/:id` (ke-1) + `/path/:a/:b` (ke-2) | `/path/user/alice` | `/path/user/:id` | literal lebih banyak didaftarkan pertama |

**Pencocokan seperti Regex**: zix tidak memiliki mesin regex. Rute prefix (`.kind = .PREFIX`) mencakup path yang terdaftar dan sub-path di bawahnya. Pemfilteran tambahan dilakukan di dalam handler dengan operasi string biasa pada `req.path()`:

```zig
// Dalam tabel rute:
.{ .path = "/secret", .handler = secretHandler, .kind = .PREFIX },

// Di dalam secretHandler: ekstrak sub-path dan terapkan logika kustom
const sub = req.path()["/secret/".len..];  // misalnya "file.txt"
// cek ekstensi, kedalaman, query params, header, dll.
```

**Contoh:**
- [examples/http_params.zig](examples/http_params.zig) - penanganan parameter query dan form
- [examples/http_paths.zig](examples/http_paths.zig) - pola routing parameter path
- [examples/http_query.zig](examples/http_query.zig) - method QUERY (RFC 10008)
- [examples/http_json.zig](examples/http_json.zig) - penanganan respons JSON

**Mesin `zix.Http1` mentah**: mesin tingkat rendah menyediakan `Router` comptime yang sama dengan jenis `.EXACT` / `.PREFIX` / `.PARAM` yang identik, prioritas `exact > param > prefix` yang sama, dan handler trio yang sama, jadi penangkapan param terbaca identik: `req.pathParam("id")` (fungsi bebas `zix.Http1.pathParam("id")` tetap ada sebagai padanan raw-layer):

```zig
const Router = zix.Http1.Router(&[_]zix.Http1.Route{
    .{ .path = "/",          .handler = homeHandler },
    .{ .path = "/secret",    .handler = secretHandler, .kind = .PREFIX },
    .{ .path = "/users/:id", .handler = userHandler,   .kind = .PARAM },
});

var server = zix.Http1.Server.init(Router.dispatch, .{ .ip = "0.0.0.0", .port = 9100 });

// di dalam userHandler:
const id = req.pathParam("id") orelse return;
```

Penangkapan param per-rute dibatasi 8 param per pencocokan..

**Contoh:**
- [examples/http1_static.zig](examples/http1_static.zig) - rute prefix yang digunakan

**Kapan digunakan:** pakai route table comptime setiap kali sebuah layanan punya lebih dari satu endpoint. Pilih `.EXACT` untuk path tetap, `.PARAM` untuk id resource, dan `.PREFIX` untuk sub-tree atau fallthrough ke static serving. Daftarkan pola yang lebih literal sebelum pola all-param dengan kedalaman sama agar rute yang dimaksud menang.

<br>

### Error Handler

Setiap handler mengembalikan `anyerror!void`, dan setiap engine memakai satu aturan: **handler yang mengembalikan error dijawab tepat satu kali**. Kalau belum menjawab apa pun, engine mengirim default protokolnya. Kalau sudah menjawab, engine diam, bukan menempelkan jawaban kedua di atas yang pertama.

| engine | default saat handler belum menjawab apa pun |
| :- | :- |
| `zix.Http` | `500`, `text/plain`, body `Internal Server Error` |
| `zix.Http1` | `500`, `text/plain`, body `Internal Server Error` |
| `zix.Http2` | `500`, `text/plain`, body `Internal Server Error` |
| `zix.Http3` | `500`, body kosong |
| `zix.Grpc` | trailer berisi `grpc-status 13` (INTERNAL) |
| `zix.Fix` | Reject (`35=3`) yang membawa RefSeqNum dari pesan yang gagal |

"Sudah menjawab" menghitung dua cara menjawab: builder `Response` dan fd writer (`zix.Http1.sendSimpleFD`, `zix.Http2.sendResponseFD`, `writeAllFD`). Handler yang menjawab lewat salah satunya tidak dijawab lagi.

`try` adalah cara mencapai default itu. Error yang ditangkap sendiri oleh handler tidak pernah sampai ke engine, jadi handler yang menentukan apa yang diterima caller:

```zig
fn handler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
    // try: kegagalan dilengkapi engine dengan default di atas
    const row = try db.fetch(req.param("id").?);

    // catch: jawabannya milik kamu, engine tidak menambahkan apa pun
    res.sendJson(row.json) catch {
        res.setStatus(.SERVICE_UNAVAILABLE);
        try res.sendText("coba lagi sebentar");
    };
}
```

Pilihan yang sama ada di setiap engine, dengan kosakata engine itu sendiri:

```zig
// zix.Grpc
try res.sendMessage(ct, reply);                 // kegagalan menutup call dengan grpc-status 13
res.sendMessage(ct, reply) catch {              // penutupannya milik kamu
    try res.finish(zix.Grpc.Status.UNAVAILABLE, "backend down");
};

// zix.Fix
try res.sendMessage(zix.Fix.MsgType.ExecutionReport, fields);  // kegagalan dijawab dengan Reject
res.sendMessage(zix.Fix.MsgType.ExecutionReport, fields) catch {
    try res.sendMessage(zix.Fix.MsgType.OrderCancelReject, reason_fields);
};
```

Satu pengecualian: `zix.Http3.Response.send` mengembalikan `void`, bukan error union. Ia hanya menyimpan body, engine yang mengirimnya setelah handler selesai, jadi tidak ada yang bisa di-`try` di baris itu. Error handler tetap sampai ke engine dan tetap menjadi 500.

### Model Konkurensi

Tiga model dispatch, dipilih via `config.dispatch_model` (enum `DispatchModel`). Field ini wajib: pemanggil harus menyetelnya secara eksplisit (tidak ada default). `.EPOLL` dan `.URING` khusus Linux, jadi pemanggil portabel memilih model per target saat comptime:

```zig
const DISPATCH_MODEL: zix.Http1.DispatchModel = if (builtin.os.tag == .linux) .URING else .ASYNC;
```

**`.ASYNC` (accept tunggal, dispatch `io.async()`):**

Satu accept thread mendispatch setiap koneksi via `io.async()`. `workers` diabaikan. Diutamakan untuk SSE dan WebSocket (koneksi long-lived hanya memakai satu task, bukan slot worker). Cocok juga untuk `concurrent_limit` eksplisit. Ini satu-satunya model yang tersedia di semua platform.

```zig
pub fn main(process: std.process.Init) !void {
    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io = process.io,
        .dispatch_model = .ASYNC, // wajib: .ASYNC, .EPOLL, atau .URING
        // workers = 0 -> cpu_count worker untuk .EPOLL / .URING, diabaikan oleh .ASYNC
    });
```

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .ASYNC,
});
```

**`.EPOLL` (shared-nothing epoll worker, khusus Linux):**

Setiap worker memiliki `SO_REUSEPORT` listener dan satu `epoll` instance tersendiri. Kernel mendistribusikan koneksi baru ke worker. Tidak ada antrian bersama, tidak ada mutex, tidak ada handoff fd antar thread. Level-triggered `EPOLLIN` menjaga koneksi tetap terdaftar setelah setiap request tanpa re-arm eksplisit. Koneksi keep-alive yang idle tidak menahan thread. Terbaik untuk request berumur pendek throughput tinggi di Linux. Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported`: pakai `.ASYNC` di sana.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .EPOLL,
    .workers        = 0, // 0 = cpu_count worker (default)
});
```

**`.URING` (shared-nothing io_uring worker, khusus Linux):**

Topologi thread-per-core, shared-nothing yang sama dengan `.EPOLL` (satu `SO_REUSEPORT` listener dan satu ring per worker, tanpa antrian bersama), tetapi completion-based alih-alih readiness-based, sehingga sebagian besar transisi syscall di-batch ke dalam ring. Accept, recv, send, dan close semuanya berjalan di ring (`zix.Http1` me-ring close-nya via `prep_close`, jadi worker terus memanen completion lintas teardown koneksi di bawah churn). Diimplementasikan secara native oleh `zix.Http1`, `zix.Http`, `zix.Grpc`, `zix.Fix`, dan `zix.Http2`. Handler per-connection `zix.Tcp` tidak punya ring native dan melipat (fold) ke `.EPOLL` (jalur per-frame `initFramed`-nya memang berjalan di ring). Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported`: pakai `.ASYNC` di sana.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .URING,
    .workers        = 0, // 0 = cpu_count worker (default)
});
```

---

__*In the nutshell:*__
- Looking for high throughput? Use `.EPOLL` or `.URING`.
- Looking for consistent latency? Use `.ASYNC`.
- Di platform non-Linux? Pakai `.ASYNC`, satu-satunya model yang tersedia di sana.

> Dalam banyak kasus untuk throughput tinggi,
> zix EPOLL sebagian besar unggul dalam efisiensi memori dan zix URING memiliki throughput lebih tinggi.
> Namun dalam beberapa kasus, kinerjanya dapat bervariasi, lihat benchmark historis di dalam direktori `docs/benchmark` untuk referensi.
> Uring tidak diizinkan di beberapa lingkungan karena alasan tertentu (misalnya, dari sudut pandang keamanan). Tetapi Anda memiliki pilihan.

**Kapan digunakan:** model dispatch adalah satu knob yang membentuk ulang seluruh server. Pakai `.ASYNC` saat latensi dan koneksi berumur panjang (SSE, WebSocket) penting atau saat target bukan Linux, dan `.EPOLL` / `.URING` di Linux untuk jumlah koneksi tertinggi dengan biaya per-request terendah. Di kotak dev loopback keduanya seri pada throughput dan `.URING` menang terutama pada cache locality. Di mesin many-core, ring close membuat `.URING` menjaga core-nya tetap sibuk lewat connection churn, di mana ia mencapai paritas atau lebih baik dari `.EPOLL` di setiap beban yang diukur dengan memori jauh lebih sedikit.

**Mengapa per-engine:** setiap engine mengimplementasikan model-model ini di `server.zig`-nya sendiri, bukan di belakang satu multiplexer bersama. Pemisahan ini disengaja dan justru merupakan optimasinya: ia membuat tiap engine menyetel hot path-nya sendiri. `zix.Http1` mengukir buffer koneksi dari slab contiguous demand-paged (tanpa heap call per-accept), sementara `zix.Grpc` dan `zix.Fix` memegang pointer heap per-koneksi karena koneksinya membawa state sesi h2 atau FIX. Hanya primitive byte-identical yang dibagikan (codec `user_data` `.URING` di `src/multiplexers/ring.zig`): bagikan primitive yang harus cocok, pertahankan dispatch loop per-engine..

> Beban kerja kita tidak sama, apa yang cocok untuk Anda mungkin tidak cocok untuk orang lain.
> Uji beban kerja Anda bila memungkinkan, mungkin dengan rasio 1:4 dari lingkungan produksi.
> Zix tidak akan mendikte pendekatan Anda.

Lihat [`docs/concurrency-id.md`](docs/concurrency-id.md) untuk detail arsitektur, jumlah thread, dan kapan sebaiknya memilih masing-masing model.

<br>

### Timeout

Dua lapisan timeout independen, keduanya dinonaktifkan secara default (`0`):

**`conn_timeout_ms`**: penjaga koneksi tingkat jaringan (Layer D). Thread timer menutup koneksi yang telah terbuka lebih lama dari ini tanpa selesai. Melindungi jalur accept dari klien yang macet sebelum atau saat mengirim header. Efektif hanya di `.ASYNC` (event loop `.EPOLL` / `.URING` mengelola masa hidup koneksinya sendiri).

**`handler_timeout_ms`**: anggaran eksekusi per-handler (Layer B). Mengatur `ctx.deadline` sebelum setiap dispatch. Handler ikut serta dengan memanggil `ctx.isExpired()` di antara langkah-langkah yang mahal.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/slow", .handler = slowHandler },
}).dispatch, .{
    .io                 = process.io,
    .ip                 = "127.0.0.1",
    .port               = 9000,
    .conn_timeout_ms    = 30_000, // tutup koneksi macet setelah 30 detik
    .handler_timeout_ms = 5_000,  // anggaran handler: 5 detik
});
```

Handler yang menggunakan anggaran:

```zig
pub fn slowHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req;

    doStep1(ctx.io);
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

Untuk menimpa deadline di dalam handler (jendela lebih pendek atau lebih panjang dari anggaran global):

```zig
ctx.setTimeout(2_000); // timpa ke 2 detik dari sekarang terlepas dari cap global
```

`ctx.isExpired()` adalah no-op (selalu mengembalikan `false`) ketika `handler_timeout_ms == 0`. `ctx.timedOut()` adalah alias untuk `ctx.isExpired()`. `conn_timeout_ms` harus >= `handler_timeout_ms` agar koneksi tidak terputus sebelum handler dapat mengirim 408. Lihat `docs/adr-id.md` untuk alasan desain.

**Contoh:**
- [examples/http_timeout_resp.zig](examples/http_timeout_resp.zig)
- [examples/http1_timeout_resp.zig](examples/http1_timeout_resp.zig) - `zix.Http1` mentah, memakai `zix.Http1.isExpired()` plus `ctx.setTimeout()` / `ctx.timedOut()` milik trio

**Kapan digunakan:** setel `handler_timeout_ms` setiap kali handler bisa berjalan lama (panggilan eksternal, komputasi berat) dan kamu ingin ia keluar secara kooperatif dengan 408 alih-alih menahan thread. Tambahkan `conn_timeout_ms` di bawah `.ASYNC` untuk mengusir client yang stall sebelum menyelesaikan request. Biarkan keduanya 0 untuk trafik internal tepercaya dengan kerja terbatas.

<br>

### Middleware

Middleware disusun pada waktu kompilasi menggunakan fungsi wrapper. Setiap wrapper menerima `comptime next: zix.Http.HandlerFn` dan mengembalikan `HandlerFn` baru (tanpa alokasi heap, tanpa chain runner runtime).

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

fn withBasicAuth(comptime next: zix.Http.HandlerFn) zix.Http.HandlerFn {
    return struct {
        fn handle(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) anyerror!void {
            // validasi Authorization: Basic <base64(user:pass)>
            // ...
            return next(req, res, ctx);
        }
    }.handle;
}
```

Susun dari kiri ke kanan, wrapper paling luar dijalankan pertama:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    // hanya pengecekan origin
    .{ .path = "/public",  .handler = withOriginCheck(publicHandler) },
    // pengecekan origin -> basic auth -> handler
    .{ .path = "/private", .handler = withOriginCheck(withBasicAuth(privateHandler)) },
}).dispatch, .{ .io = process.io, .ip = "127.0.0.1", .port = 9008 });
```

```
# contoh curl
curl -H "Origin: http://localhost" "http://localhost:9008/public"                         # 200
curl "http://localhost:9008/public"                                                       # 403

curl -H "Origin: http://localhost" -u "admin:secret" "http://localhost:9008/private"      # 200
curl -H "Origin: http://localhost" "http://localhost:9008/private"                        # 401
curl "http://localhost:9008/private"                                                      # 403
```

**Contoh:**
- [examples/http_middleware.zig](examples/http_middleware.zig)

**Kapan digunakan:** susun middleware untuk perhatian lintas-sektoral yang membungkus banyak rute: auth, cek origin/CORS, rate limit, request logging. Karena rantai dibangun saat comptime tanpa heap dan tanpa runner runtime, biayanya nol per request, jadi pilih ini daripada boilerplate per-handler setiap kali guard yang sama berulang di banyak rute.

<br>

### WebSocket

Broadcast berbasis ruang melalui RFC 6455. Handler param mengupgrade koneksi dan memasuki loop frame per-task, tidak perlu thread terpisah.

```zig
var ws_rooms: zix.Http.WebSocket.RoomMap = undefined;

pub fn wsHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    const room_id = req.pathParam("room-id") orelse return;

    // Baca query param SEBELUM upgrade() (tidak tersedia setelah handshake 101).
    const display_name = req.queryParam("name") orelse "anonymous";

    // ekstrak Sec-WebSocket-Key dari header, lalu handshake
    var accept_buf: [64]u8 = undefined;
    const accept = try zix.Http.WebSocket.acceptKey(ws_key, &accept_buf);
    try zix.Http.WebSocket.upgrade(ctx.stream, ctx.io, accept); // menulis 101 secara langsung

    // heap-alokasi conn, bergabung ke ruang, keduanya dibersihkan via defer (LIFO)
    const conn = try std.heap.smp_allocator.create(zix.Http.WebSocket.Conn);
    conn.* = .{ .stream = ctx.stream, .io = ctx.io };
    defer std.heap.smp_allocator.destroy(conn);
    ws_rooms.join(room_id, conn, ctx.io);
    defer ws_rooms.leave(room_id, conn, ctx.io);  // berjalan sebelum destroy

    // loop frame:
    //   text/binary -> broadcast "[display_name] payload" ke ruang
    //   ping        -> pong
    //   close       -> echo frame close + break
    //   EOF / error -> frame close best-effort + break
    _ = display_name;
}

pub fn main(process: std.process.Init) !void {
    ws_rooms = zix.Http.WebSocket.RoomMap.init(std.heap.smp_allocator);
    defer ws_rooms.deinit();

    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/ws/:room-id", .handler = wsHandler, .kind = .PARAM },
    }).dispatch, .{ .io = process.io, .ip = "127.0.0.1", .port = 9008 });
    defer server.deinit();
    try server.run();
}
```

```
# Sambungkan dengan wscat atau websocat, ?name mengatur nama display broadcast
wscat    -c "ws://localhost:9008/ws/lobby?name=alice"
websocat    "ws://localhost:9008/ws/lobby?name=alice"

# ?name opsional, hilangkan untuk "anonymous"
wscat    -c "ws://localhost:9008/ws/lobby"
```

**Prioritas:** exact > param > prefix. `/ws/:room-id` adalah rute param, jadi `/ws/lobby` menangkap `room-id = "lobby"`.

`ctx.stream` adalah TCP stream mentah yang diekspos via `Context`. Server menetapkannya untuk **setiap** koneksi sebelum memanggil handler mana pun: handler HTTP mengabaikannya, handler WebSocket menggunakannya setelah upgrade 101.

**Menggabungkan HTTP, static, dan WebSocket dalam satu server**: daftarkan semua tipe handler bersamaan, routing menangani dispatch. Rute yang tidak cocok diteruskan ke static serving:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/",          .handler = homeHandler },
    .{ .path = "/api",       .handler = apiHandler,  .kind = .PREFIX },
    .{ .path = "/ws/:room-id", .handler = wsHandler, .kind = .PARAM },
}).dispatch, .{
    .io         = process.io,
    .ip         = "127.0.0.1",
    .port       = 9008,
    .public_dir = "./public", // file statis untuk rute yang tidak cocok
});
```

**Contoh:**
- [examples/http_websocket.zig](examples/http_websocket.zig) - contoh lengkap yang berfungsi
- [examples/http_ws_client.zig](examples/http_ws_client.zig) - client yang cocok
- [examples/http1_websocket.zig](examples/http1_websocket.zig) - `zix.Http1.WebSocket` mentah: echo `/ws` plus room broadcast `/ws/:room-id`

**Kapan digunakan:** pakai WebSocket untuk push dua arah latensi rendah (chat, presence, dashboard live, state game). Pasangkan dengan `.ASYNC` agar koneksi berumur panjang tidak pernah menahan thread pool, dan gunakan `broadcast` build-once saat satu pesan menyebar ke satu room. Jika aliran data satu arah server-ke-client, pilih SSE: lebih sederhana dan reconnect native di browser.

**Build-once broadcast fanout**: pada jalur `zix.Http1` yang dikelola engine, `zix.Http1.WebSocket.broadcast(conns, opcode, payload)` men-serialize frame satu kali saja dan menulis byte yang sama ke setiap fd dalam room yang dikelola pemanggil, sehingga sebuah broadcast hanya berbiaya satu serialization tidak peduli berapa banyak member yang dijangkau. Write yang gagal ke peer mati dilewati (engine EPOLL memanen fd itu pada event berikutnya), dan jalur payload besar membangun header sekali dan menulis payload tanpa menyalinnya ke staging buffer. `zix.Http.WebSocket.RoomMap.broadcast` tingkat tinggi mengikuti bentuk build-once, fan-out yang sama dengan room registry yang dikelola server.

<br>

### SSE (Server-Sent Events)

Push satu arah dari server melalui HTTP/1.1: tanpa handshake WebSocket, reconnect `EventSource` native browser.

```zig
// GET /events: streaming "tick N" sekali per detik
pub fn eventsHandler(req: *zix.Http.Request, res: *zix.Http.Response, ctx: *zix.Http.Context) !void {
    _ = req;
    const sse = try res.sendStream(); // mengirim header SSE, mengembalikan SseWriter
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var buf: [32]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "tick {d}", .{i}) catch break;
        sse.writeEvent(msg) catch break;                                       // data: tick N\n\n
        std.Io.sleep(ctx.io, std.Io.Duration.fromMilliseconds(1000), .awake) catch break;
    }
    // handler selesai -> koneksi ditutup -> EventSource reconnect otomatis
}
```

| Metode `SseWriter` | Format wire |
| :- | :- |
| `writeEvent(data)` | `data: <data>\n\n` |
| `writeNamedEvent(event, data)` | `event: <event>\ndata: <data>\n\n` |
| `comment(text)` | `: <text>\n` (keepalive) |

**Model dispatch:** gunakan `.ASYNC`. Koneksi SSE bersifat long-lived, dan `.ASYNC` mendispatch setiap koneksi via `io.async()`, jadi satu stream terbuka hanya memakai satu task alih-alih menahan slot worker event loop.

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/events", .handler = eventsHandler },
}).dispatch, .{
    .io             = process.io,
    .dispatch_model = .ASYNC, // diutamakan untuk SSE: koneksi long-lived tidak menahan pool thread
});
```

```sh
curl -N http://localhost:9010/events
```

**Contoh:**
- [examples/http_sse.zig](examples/http_sse.zig) - contoh lengkap dengan halaman HTML yang kompatibel dengan browser
- [examples/http_sse_client.zig](examples/http_sse_client.zig) - client yang cocok
- [examples/http1_sse.zig](examples/http1_sse.zig) - engine `zix.Http1` mentah

**Kapan digunakan:** pilih SSE untuk push server satu arah melalui HTTP biasa (stream progres, notifikasi, log tailing, metrik live) saat client tidak perlu mengirim frame balik. Lebih ringan dari WebSocket dan `EventSource` reconnect otomatis. Selalu jalankan di bawah `.ASYNC`, yang memakai satu task per stream terbuka alih-alih menahan worker event loop.

<br>

### HTTP Client

`zix.Http.Client` membuat permintaan HTTP keluar. Setiap panggilan mengembalikan `ClientResponse` yang dimiliki pemanggil dan harus dilepas dengan `deinit()`.

```zig
var client = zix.Http.Client.init(.{
    .allocator         = arena.allocator(),
    .io                = process.io,
    .connect_timeout_ms = 5000,       // error.Timeout jika koneksi TCP memakan waktu > 5 detik
    .max_response_body  = 64 * 1024,  // error.ZixBodyTooLarge jika body melebihi 64 KB
});
defer client.deinit();

// GET
var resp = try client.get("http://127.0.0.1:9000/", .{});
defer resp.deinit();
std.debug.print("{d}: {s}\n", .{ resp.status(), resp.body() });

// GET dengan inspeksi header
if (resp.header("content-type")) |ct| {
    std.debug.print("content-type: {s}\n", .{ct});
}

// POST dengan body dan header kustom
const extra = [_]std.http.Header{
    .{ .name = "X-Trace-Id", .value = "abc-123" },
};
var post_resp = try client.post("http://127.0.0.1:9000/api/items", .{
    .headers = &extra,
    .body    = "{\"name\":\"widget\"}",
});
defer post_resp.deinit();

// Timpa timeout koneksi per-permintaan
var fast = try client.get("http://127.0.0.1:9000/health", .{
    .connect_timeout_ms = 500,
});
defer fast.deinit();
```

| Shorthand metode | Mengirim body? |
| :- | :- |
| `client.get(url, opts)` | tidak |
| `client.head(url, opts)` | tidak |
| `client.post(url, opts)` | ya (Content-Length: 0 jika opts.body null) |
| `client.put(url, opts)` | ya |
| `client.patch(url, opts)` | ya |
| `client.delete(url, opts)` | tidak |
| `client.request(method, url, opts)` | tergantung metode |

| Error | Kondisi |
| :- | :- |
| `error.ZixUrlMalformed` | URL-nya tidak bisa di-parse |
| `error.ZixUrlSchemeUnsupported` | skemanya bukan yang dipahami transport ini |
| `error.ZixUrlHostMissing` | URL-nya tidak membawa host |
| `error.ZixUrlPortInvalid` | port-nya bukan angka dalam rentang |
| `error.ZixUrlPathTooLong` | path dan query-nya tidak muat di buffer request |
| `error.ZixBodyTooLarge` | body respons melebihi `max_response_body` |
| `error.Timeout` | koneksi TCP melebihi `connect_timeout_ms` |

Redirect diikuti secara otomatis hingga `max_redirects` (default 3). Atur `follow_redirects = false` untuk menerima respons 3xx secara langsung.

`zix.Http.Client` yang sama bekerja terhadap server `zix.Http1` mentah via `.version = .HTTP_1` (selector versi, dengan `HTTP_2` dan `HTTP_3` direservasi).

**Contoh:**
- [examples/http_client.zig](examples/http_client.zig)
- [examples/http1_client.zig](examples/http1_client.zig) - menyetel `.version = .HTTP_1`

[`docs/hld-http-id.md`](docs/hld-http-id.md) untuk detail.

**Kapan digunakan:** pakai `zix.Http.Client` untuk panggilan keluar dari handler atau tool mandiri: health check, request antar-service, webhook, atau mengambil endpoint yang diketahui. Setel `connect_timeout_ms` dan `max_response_body` untuk membatasi peer tak tepercaya, dan matikan `follow_redirects` saat kamu harus memeriksa 3xx sendiri.

<br>

### File Statis & Unggah

Atur `public_dir` di `HttpServerConfig` untuk mengaktifkan static file serving. `server.run()` mengembalikan `error.ZixPublicDirNotFound` jika direktori tidak ada. Gunakan helper `createInitDirs` untuk membuat semua direktori yang diperlukan sebelum `Server.init`:

```zig
fn createInitDirs(io: std.Io) void {
    std.Io.Dir.cwd().createDirPath(io, "./public") catch {};
    std.Io.Dir.cwd().createDirPath(io, "./public/u") catch {};
}

pub fn main(process: std.process.Init) !void {
    createInitDirs(process.io); // idempoten, aman dipanggil setiap start

    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/upload", .handler = uploadHandler },
    }).dispatch, .{
        .io                = process.io,
        .ip                = "127.0.0.1",
        .port              = 9005,
        .public_dir        = "./public", // divalidasi saat run(); "" = dinonaktifkan
        .public_dir_upload = "u",
    });
```

- Rute yang tidak cocok diteruskan ke static serving dari `public_dir`.
- Range request (`Range: bytes=...`) -> `206 Partial Content` (RFC 7233).
- Directory traversal (`..`) ditolak.

**Unggah**: parse body multipart di dalam handler, opsional ganti nama sebelum menyimpan:

```zig
var parser = zix.utils.multipart.Parser.init(ctx.allocator, boundary);
defer parser.deinit();
try parser.parse(try req.body());

if (parser.getField("file")) |f| {
    // kamu bisa mengganti nama file sebelum menyimpan dengan mengganti string filename, misalnya:
    //   const filename = "custom_name.txt"
    // atau membuatnya secara dinamis:
    //   const filename = try std.fmt.allocPrint(ctx.allocator, "{s}_{s}", .{ sessionid, f.filename orelse "upload" });
    const filename = f.filename orelse "upload";
    const path = try zix.utils.file.save(ctx.io, ctx.allocator, "./public/u", filename, f.data);
    _ = path; // dialokasikan arena, valid untuk permintaan ini
}
```

`zix.utils.file.save` membuat direktori tujuan jika diperlukan dan mengembalikan salinan path milik pemanggil.

```
# contoh curl: unggah file dengan metadata JSON
curl -X POST "http://localhost:9005/upload" \
  -F "file=@/path/to/file.txt" \
  -F 'data={"userid":0,"sessionid":"01944f5a-0000-7000-8000-000000000000"}'
```

**Contoh:**
- [examples/http1_static_cached.zig](examples/http1_static_cached.zig) - fallback yang sama dengan `public_dir_cache_ttl_ms` diatur, memperlihatkan jalur cache dan pengambilan sibling `.br` / `.gz`
- [examples/tls/http3_static.zig](examples/tls/http3_static.zig) - penyajian static di atas HTTP/3, di mana cache-lah yang membuatnya mungkin sama sekali
- [examples/http_static.zig](examples/http_static.zig) - contoh lengkap yang berfungsi termasuk static serving, range request, dan unggah multipart

**Kapan digunakan:** aktifkan `public_dir` untuk menyajikan frontend hasil build, aset, atau unduhan dari server yang sama, dengan range request ditangani otomatis. Pakai jalur multipart untuk unggahan pengguna saat kamu mengontrol target penyimpanan. Dengan `public_dir_cache_ttl_ms` diatur, respons cleartext menyerahkan file ke kernel lewat `sendfile`, jadi byte-nya tidak pernah masuk user space. CDN tetap jawaban yang tepat untuk distribusi file massal lintas region: ini untuk kemudahan dan aset co-located.

**Penting:** pertimbangkan untuk menyesuaikan kolom `max_recv_buf` berdasarkan ukuran *chunk* file unggahan saat menyediakan fitur unggah.

<br>

### Kapasitas Header Respons (`HeaderSize`)

`HttpServerConfig.max_response_headers` mengontrol berapa banyak header kustom yang akan diterima `res.addHeader()` per respons. Pilih tingkatan yang sesuai dengan deployment-mu:

| Varian | Cap | Penggunaan umum |
| :- | :- | :- |
| `.MINIMAL` | 16 | **Default.** API internal sederhana, lingkungan terkontrol, handler polos |
| `.COMMON` | 32 | Sebagian besar aplikasi web, single proxy |
| `.LARGE` | 64 | CDN + proxy, load balancer, API berat CORS |
| `.EXTRA_LARGE` | 128 | k8s, service mesh, stack forwarding berat |
| `.{ .CUSTOM = N }` | N | Cap eksplisit, dialokasikan arena tepat N slot per permintaan |

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .max_response_headers = .LARGE,                // 64 header
    // .max_response_headers = .{ .CUSTOM = 48 },  // eksplisit
});
```

`addHeader()` mengembalikan `error.ZixTooManyHeaders` ketika cap tercapai dan `error.ZixInvalidHeaderName` / `error.ZixInvalidHeaderValue` jika nama atau nilai mengandung CR atau LF (penjaga injeksi header).

`.{ .CUSTOM = N }` mengalokasikan tepat N slot dari arena per-permintaan (tanpa ceiling, tanpa clamping).

**Contoh:**
- [examples/http_xtra_headers.zig](examples/http_xtra_headers.zig) - demonstrasi yang berfungsi
- [examples/http1_xtra_headers.zig](examples/http1_xtra_headers.zig) - `zix.Http1` mentah, membangun header secara manual dengan penjaga injeksi CR/LF

[`docs/headers-id.md`](docs/headers-id.md) untuk panduan keamanan dan pemilihan tingkatan.

**Kapan digunakan:** naikkan `max_response_headers` hanya sejauh yang dibutuhkan deployment-mu. Pertahankan `.MINIMAL` untuk API internal, naik ke `.LARGE` / `.EXTRA_LARGE` di belakang CDN, proxy, atau stack CORS-heavy yang menambah banyak header forwarding. Cap yang lebih ketat adalah penjaga murah terhadap pertumbuhan header liar dan di-arena tepat sebesar tingkatan yang kamu pilih.

<br>

### Kapasitas Header Permintaan (`RequestHeaderSize`)

`HttpServerConfig.max_request_headers` mengontrol berapa banyak header yang diterima server per permintaan. Permintaan yang melebihi cap ditolak dengan `431 Request Header Fields Too Large`.

| Varian | Cap | Catatan |
| :- | :- | :- |
| `.MINIMAL` | 16 | API ketat, layanan internal |
| `.COMMON` | 32 | Sebagian besar aplikasi web |
| `.LARGE` | 64 | **Default.** Batas penyimpanan parser. CDN, proxy, API berat CORS |
| `.{ .CUSTOM = N }` | N (dibatasi 64) | Cap eksplisit nilai di atas 64 secara diam-diam dibatasi ke batas parser |

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/", .handler = homeHandler },
}).dispatch, .{
    .max_request_headers = .COMMON,                // 32 header
    // .max_request_headers = .{ .CUSTOM = 24 },   // eksplisit
});
```

Batas penyimpanan parser adalah 64: nilai `CUSTOM` di atas 64 secara diam-diam dibatasi. Lihat `zix.Http.RequestHeaderSize`.

**Kapan digunakan:** turunkan `max_request_headers` (`.MINIMAL` / `.COMMON`) pada layanan internal ketat untuk menolak blok header berlebih lebih awal dengan 431. Pertahankan default `.LARGE` untuk endpoint publik di belakang proxy yang sah menambah header. Plafon parser keras adalah 64, jadi `CUSTOM` di atas itu secara diam-diam dibatasi.

<br>

### Kesadaran Cache Respons (`response_cache`)

`zix.Http1`, `zix.Http`, dan `zix.Grpc` berbagi response cache per-worker yang opt-in. Handler membangun responnya sekali, engine menyimpannya di bawah sebuah key yang diturunkan dari request, dan request berikutnya yang cocok memutar ulang byte tersimpan tanpa membangun ulang. Sebuah hit melewati pembangunan body handler sekaligus serialization. Cache ini data oriented (structure of arrays plus satu payload slab datar), lock-free by ownership (satu instance per worker, tidak pernah dibagi), dan freshness memakai lazy on-access TTL.

Apa yang menjadi key dan nilai yang di-cache bergantung pada engine:

| Engine | Cache key | Nilai yang di-cache |
| :- | :- | :- |
| `zix.Http1`, `zix.Http` | method, path, query | respons HTTP yang sudah di-serialize penuh, ditulis verbatim |
| `zix.Grpc` (unary) | path, pesan request | pesan respons, di-frame ulang per stream (HPACK dan stream id tetap benar) |

Secara default fitur ini mati. Aktifkan pada dispatch model `.EPOLL` atau `.URING`:

```zig
var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
    .{ .path = "/report", .handler = reportHandler },
}).dispatch, .{
    .ip = "0.0.0.0",
    .port = 8080,
    .dispatch_model = .EPOLL,
    .response_cache = true,                  // aktifkan cache per-worker
    .cache_max_entries = 256,                // slot, dibulatkan turun ke pangkat dua
    .cache_max_value_bytes = 16 * 1024,      // batas respons per-slot
    .cache_ttl_ms = 1000,                    // freshness default
    // .cache_max_total_bytes = 4 * 1024 * 1024, // batas memori cache per-worker opsional
});
```

Sebuah miss membangun dan menyimpan respons, sebuah hit yang fresh disajikan verbatim:

```zig
fn reportHandler(req: *zix.Http.Request, res: *zix.Http.Response, _: *zix.Http.Context) !void {
    if (res.sendFromCache(req)) return;          // hit fresh: byte cache sudah ditulis

    const body = try buildExpensiveReport(req);  // hanya berjalan saat miss
    res.setContentType(.APPLICATION_JSON);
    try res.sendCached(req, body, 0);            // ttl 0 memakai cache_ttl_ms
}
```

Engine `zix.Http1` mentah mengekspos ide yang sama lewat `cacheLookup` dan `sendWithCacheFD` (atau `res.sendFromCache` / `res.sendCached` milik trio).

Untuk handler gRPC unary, opt-in berada di response builder. `res.serveCached` memutar ulang pesan reply tersimpan (di-frame ulang untuk stream saat ini dan diselesaikan dengan OK), dan `res.sendCached` mengirim sekaligus menyimpan reply. Aktifkan dengan nama field yang sama pada `GrpcServerConfig` (`response_cache`, `cache_max_entries`, dan seterusnya) di bawah `.EPOLL` atau `.URING`:

```zig
fn sayHello(req: *zix.Grpc.Request, res: *zix.Grpc.Response, _: *zix.Grpc.Context) !void {
    if (res.serveCached("application/grpc")) return; // hit fresh: reply terkirim, stream selesai

    const reply = buildExpensiveReply(req.recvMessage()); // hanya berjalan saat miss
    res.sendCached("application/grpc", reply, 0);          // ttl 0 memakai cache_ttl_ms
    res.finish(.OK, "");
}
```

#### Kapan menguntungkan

Crossover yang terukur di loopback berkisar 4 KiB body respons. Di bawah itu biaya didominasi kernel dan cache impas. Di atasnya kerja yang dihemat tumbuh seiring ukuran body.

| Bentuk respons | Efek cache |
| :- | :- |
| Serialization yang berat komputasi (JSON besar, output yang dirender) di atas ~4 KiB | Kasus terbaik, gain besar (JSON berat ~32 KiB terukur +34% throughput) |
| Respons kecil di bawah ~2 KiB | Impas, terikat kernel, tanpa regresi |
| File statis yang dibaca dari disk | Marginal: OS page cache sudah menyajikan file dengan murah, lebih baik pakai sendfile atau splice |
| Body unik per-request (tanpa pengulangan key) | Tidak ada manfaat, setiap request miss |

#### Aturan dan kondisi

- Opt-in saja. Mati secara default, dan handler harus memanggil `res.sendFromCache` lalu `res.sendCached` (engine HTTP), `res.serveCached` lalu `res.sendCached` (gRPC), atau `cacheLookup` / `sendWithCacheFD` milik `zix.Http1` mentah.
- Hanya `.EPOLL` dan `.URING` di rilis ini. Dispatch model lain membiarkan cache tidak terpasang dan API menurun menjadi plain send.
- Untuk HTTP key adalah method, path, dan query: dua request yang hanya berbeda query string adalah entri yang berbeda, dan Anda tidak boleh mem-cache respons yang bervariasi pada header atau cookie. Saat respons dikompresi (`sendNegotiateFD` / `sendGzipCachedFD`), content-encoding juga dilipat ke dalam key (`hashKeyEncoded`), sehingga varian gzip dan brotli menempati entri berbeda. Untuk gRPC key adalah path plus pesan request, sehingga hanya request yang identik yang hit.
- Respons QUERY tidak pernah disimpan. Key HTTP tidak membawa content request, jadi dua request QUERY ke satu path dengan body berbeda akan berbagi satu jawaban. RFC 10008 section 2.7 menjadikan cache respons QUERY berstatus MAY, jadi kedua engine HTTP menolak penyimpanannya langsung. Tidak ada yang berubah untuk method lain.
- Cache hanya yang aman diputar ulang selama jendela TTL. Untuk HTTP byte yang sama (termasuk `Date` yang ditangkap) disajikan sampai entri kedaluwarsa, jadi jaga `cache_ttl_ms` tetap pendek untuk konten yang sensitif waktu.
- Respons lebih besar dari `cache_max_value_bytes` melewati cache dan jatuh kembali ke plain send. Untuk gRPC batas ini berlaku pada pesan respons. Jaga tetap ramping agar hanya respons di atas crossover yang menempati slot.
- Memori per-worker adalah `cache_max_entries * cache_max_value_bytes`, dikali jumlah worker, secara opsional dibatasi oleh `cache_max_total_bytes`.

**Mengapa hanya `.EPOLL` / `.URING`:** cache adalah instance thread-local, tidak pernah dibagi dan tidak pernah dikunci (lock-free by ownership). Invariant itu hanya berlaku saat satu thread milik zix memasang cache (alokasi, set, free saat keluar) dan menjadi satu-satunya thread yang menyentuhnya. Worker shared-nothing `.EPOLL` dan worker `.URING` one-thread-per-ring sama-sama memenuhinya.

| Model | Menjalankan handler di | Status cache |
| :- | :- | :- |
| `.EPOLL` | worker thread shared-nothing milik zix, satu per core | terpasang: lifecycle bersih, satu thread pemilik, jalur yang di-benchmark |
| `.URING` | ring worker shared-nothing milik zix, satu per core | terpasang: lifecycle satu-thread-pemilik yang sama dengan `.EPOLL` |
| `.ASYNC` | task `io.async()` di executor pool `std.Io`, bukan milik zix | tidak terpasang: tidak ada hook pasang per-thread, dan task tidak ditambatkan ke satu thread, sehingga cache bersama akan butuh lock dan merusak desain lock-free |

Di model mana pun perilakunya aman, hanya tidak aktif: saat cache tidak terpasang, `response_cache = true` dan pemanggilan `sendFromCache` / `sendCached` menurun menjadi plain send (tanpa error, tanpa caching).

```mermaid
flowchart TD
    A[Request masuk] --> B{response_cache dan EPOLL/URING?}
    B -- tidak --> P[Plain send]
    B -- ya --> C{sendFromCache hit dan fresh?}
    C -- ya --> W[Tulis byte cache, tanpa bangun ulang]
    C -- tidak --> D[Bangun respons]
    D --> E{body lebih besar dari cache_max_value_bytes?}
    E -- ya --> P
    E -- tidak --> S[sendCached: tulis lalu simpan di bawah key]
```

**Kapan digunakan:** nyalakan cache untuk respons panas, berulang, komputasi-berat di atas ~4 KiB (laporan ter-render, agregat JSON besar) yang disajikan di bawah `.EPOLL` atau `.URING`. Biarkan mati untuk respons kecil yang kernel-bound, body unik per-request, atau apa pun yang bervariasi pada header atau cookie, di mana ia tidak menambah manfaat. Baca aturan di atas sebelum men-cache apa pun yang sensitif waktu.

Lihat `docs/adr-id.md` untuk rasional desain dan angka terukur.

<br>

### Kesadaran Process Queue (`process_queue_len`)

`zix.Http1` dan `zix.Http` berbagi ring backpressure submission-queue per-worker yang opt-in di bawah dispatch model `.URING`. Saat burst koneksi mengisi submission queue io_uring, re-arm recv atau send yang seharusnya menutup koneksi diparkir pada FIFO ring per-worker, hanya menyimpan referensi (fd plus tag generation, tidak pernah byte request), dan dicoba ulang pada loop pass berikutnya. Tanpa ini, re-arm yang jatuh saat submission queue penuh menutup koneksi, dan re-arm multishot-accept yang hilang membuat worker berhenti menerima sama sekali sementara backlog kernel terisi.

Hanya `.URING`, pada `zix.Http1` dan `zix.Http`. Tekanan submission-queue yang dijaganya tidak ada pada thread model atau `.EPOLL`, jadi field ini inert di sana.

Aktifkan dengan menyetel panjang ring (`0`, mati, secara default):

```zig
var server = zix.Http1.Server.init(handler, .{
    .ip = "0.0.0.0",
    .port = 8080,
    .dispatch_model = .URING,
    .process_queue_len = 4096,   // kapasitas park-ring per-worker, 0 = mati
});
```

Atur ring sekitar puncak koneksi bersamaan yang ditangani satu worker: satu koneksi memarkir paling banyak satu entry pada satu waktu, jadi ring tidak pernah butuh slot lebih dari koneksi hidup worker itu. Nilai jauh di atas itu hanya mencadangkan slab yang menjadi resident seiring waktu tanpa manfaat.

#### Kapan aktif

Ring ini no-op pada beban normal dan hanya bekerja saat submission queue benar-benar jenuh.

| Workload | Efek |
| :- | :- |
| Keep-alive koneksi rendah yang stabil | No-op, submission queue tidak pernah penuh |
| Burst koneksi di atas kedalaman submission-queue (accept storm, churn) | Re-arm overflow diparkir dan dicoba ulang pass berikutnya alih-alih koneksi dibuang |
| Overload berkelanjutan melewati kapasitas ring | Reject-newest: entry terbaru jatuh ke jalur close sementara kerja terparkir tertua tetap terkuras dalam urutan kedatangan |

#### Aturan dan sizing

- Opt-in saja. `process_queue_len = 0` (default) membiarkan ring tidak dialokasikan dan perilaku close-on-full tidak berubah.
- Hanya `.URING`, dan hanya pada `zix.Http1` dan `zix.Http`. Dispatch model lain dan `.EPOLL` tidak pernah mengisi submission queue, jadi field ini inert.
- Stream tidak pernah masuk ring. WebSocket, SSE, dan gRPC streaming diatur oleh protocol flow control (window HTTP/2 dan `max_streams`, QUIC MAX_DATA dan MAX_STREAMS) dan di-shed dengan sinyal protokolnya sendiri, bukan diparkir.
- Reject-newest. Saat ring penuh re-arm terbaru ditolak (koneksi ditutup), jadi kerja terparkir selalu terkuras tertua-dulu dan flood tidak bisa membuat koneksi lebih awal kelaparan.
- Memori per-worker adalah `process_queue_len` kali beberapa byte per entry (sebuah referensi, bukan buffer request), kali jumlah worker.
- Sizing: sekitar puncak koneksi bersamaan per worker. Di atas itu slot ekstra tidak terjangkau, di bawahnya burst bisa kena reject-newest lebih cepat.

Guard terkait namun terpisah menutupi body request oversize: pada `zix.Http2` body DATA yang melewati buffer stream di-shed dengan `413` dan END_STREAM (hanya window koneksi yang dikredit), dan pada `zix.Grpc` dengan trailer `RESOURCE_EXHAUSTED`, jadi body yang terlalu besar untuk di-buffer tidak pernah men-dispatch terpotong.

```mermaid
flowchart TD
    A[re-arm recv atau send] --> B{submission queue punya ruang?}
    B -- ya --> S[arm SQE sekarang]
    B -- tidak --> C{process_queue_len lebih dari 0?}
    C -- tidak --> X[tutup koneksi]
    C -- ya --> D{park ring penuh?}
    D -- ya --> X
    D -- tidak --> P[park fd plus generation]
    P --> R[drainParked re-arm dalam urutan FIFO pass berikutnya]
```

**Kapan digunakan:** setel `process_queue_len` saat deployment `.URING` menghadapi burst koneksi atau accept storm yang bisa melampaui submission queue (koneksi churny berumur pendek, flood reconnect), diukur sekitar puncak koneksi per worker. Biarkan mati untuk beban keep-alive stabil, di mana submission queue tidak pernah penuh dan ring tidak pernah aktif.

Lihat `docs/zix-config-id.md` untuk referensi field.

<br>

### HTTP/2

`zix.Http2` adalah server HTTP/2 yang berdiri sendiri: h2c (cleartext) secara default, atau h2 over TLS saat sebuah `Tls.Context` dipasang (ALPN menegosiasikan h2, yang diwajibkan browser untuk HTTP/2). Ia juga merupakan transport h2c yang dijalankan oleh `zix.Grpc`.

**Kapan digunakan:** jangkau `zix.Http2` secara langsung saat kamu butuh framing HTTP/2 mentah (h2c atau h2-over-TLS) tanpa semantik gRPC, misalnya endpoint h2 untuk browser atau client h2. Untuk trafik web biasa `zix.Http1` / `zix.Http` memimpin benchmark, dan untuk RPC pakai `zix.Grpc` (yang berjalan di atas engine ini).

<br>

#### gRPC h2c

`zix.Grpc` adalah server dan client gRPC melalui h2c. Rute didaftarkan pada waktu kompilasi. Semua 4 tipe RPC didukung (unary, server streaming, client streaming, bidirectional).

```zig
const std = @import("std");
const zix = @import("zix");

fn sayHelloHandler(
    req: *zix.Grpc.Request,
    res: *zix.Grpc.Response,
    ctx: *zix.Grpc.Context,
) !void {
    _ = ctx;
    const msg = req.recvMessage() orelse {
        res.finish(.INVALID_ARGUMENT, "no message");
        return;
    };
    // decode msg (proto3), encode balasan
    var reply: [256]u8 = undefined;
    const n = zix.Grpc.encodeString(1, "Hello!", &reply);
    res.sendMessage("application/grpc+proto", reply[0..n]);
    res.finish(.OK, "");
}

pub fn main(process: std.process.Init) !void {
    var server = zix.Grpc.Server.init(
        zix.Grpc.Router(&[_]zix.Grpc.Route{
            .{ .path = "/helloworld.Greeter/SayHello", .handler = sayHelloHandler },
        }),
        .{
            .io   = process.io,
            .ip   = "127.0.0.1",
            .port = 8083,
        },
    );
    defer server.deinit();
    try server.run();
}
```

```sh
# Uji dengan grpcurl
grpcurl -plaintext -d '{"name":"world"}' 127.0.0.1:8083 helloworld.Greeter/SayHello
```

**HandlerFn:** `fn(req: *zix.Grpc.Request, res: *zix.Grpc.Response, ctx: *zix.Grpc.Context) anyerror!void`

- Path diselesaikan oleh tabel rute sebelum handler dipanggil.
- `req.recvMessage()` mengembalikan setiap pesan client yang di-buffer atau `null` jika selesai.
- `res.sendMessage(content_type, data)` mengirim frame DATA respons (panggilan pertama juga mengirim HEADERS).
- `res.finish(status, message)` mengirim trailer grpc-status. Harus dipanggil tepat sekali.
- Route unary (`is_server_streaming = false`, default) di-dispatch secara sinkron pada connection thread. Route server-streaming memerlukan `is_server_streaming = true` pada entri `Route` dan masing-masing berjalan pada thread tersendiri. `Server.init` adalah satu pengecualian sengaja gRPC dari bentuk keluarga `Server.init(handler, config)`: ia menerima `Router(&routes)` itu sendiri (bukan `.dispatch`), karena engine harus melihat `is_server_streaming` sebelum memutuskan cara dispatch (terukur berpengaruh besar pada RPS per-core antara jalur sync-inline dan task-spawn).

**GrpcClient:**

```zig
var client = try zix.Grpc.Client.connect(.{
    .ip   = "127.0.0.1",
    .port = 8083,
}, process.io);
defer client.deinit();

// Unary convenience
var buf: [4096]u8 = undefined;
const resp = try client.unary(
    "/helloworld.Greeter/SayHello",
    "application/grpc+proto",
    request_bytes,
    &buf,
);
```

**Codec protobuf minimal** (tidak memerlukan codegen untuk skema sederhana):

```zig
var out: [256]u8 = undefined;
var pos: usize = 0;
pos += zix.Grpc.encodeString(1, "world",  out[pos..]); // field 1: string
pos += zix.Grpc.encodeInt32( 2, 42,       out[pos..]); // field 2: int32
pos += zix.Grpc.encodeDouble(3, 1.5,      out[pos..]); // field 3: double
// kirim out[0..pos] sebagai payload pesan gRPC
```

**Model dispatch:** `.ASYNC`, `.EPOLL`, `.URING` (dua terakhir khusus Linux, field-nya wajib tanpa default). Model gRPC EPOLL dan URING adalah multiplexed event loop shared-nothing: setiap worker memiliki `SO_REUSEPORT` listener dan satu epoll instance tersendiri, dan menjalankan banyak koneksi h2 non-blocking melalui resumable HTTP/2 state machine. `workers` adalah jumlah worker (0 = cpu_count). Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported`: pakai `.ASYNC` di sana. Lihat [`docs/concurrency-id.md`](docs/concurrency-id.md) untuk detail.

**Timeout context:** Tiga input, yang paling ketat menang:

```zig
var server = zix.Grpc.Server.init(
    zix.Grpc.Router(&[_]zix.Grpc.Route{
        // cap per-rute 3 detik, memperketat cap global 5 detik
        .{ .path = "/helloworld.Greeter/SayHello", .handler = sayHelloHandler, .timeout_ms = 3_000 },
        // cap per-rute 10 detik, cap global 5 detik tetap menang. Echo mengirim N respons sehingga is_server_streaming = true
        .{ .path = "/helloworld.Greeter/Echo", .handler = echoHandler, .timeout_ms = 10_000, .is_server_streaming = true },
    }),
    .{
        .io                = process.io,
        .ip                = "127.0.0.1",
        .port              = 8083,
        .handler_timeout_ms = 5_000, // cap global, juga digabungkan dengan Route.timeout_ms dan header grpc-timeout
    },
);
```

Handler memeriksa `ctx.isExpired()` di antara langkah-langkah. Timpa `ctx.deadline_ns` secara langsung untuk perpanjangan per-panggilan: `ctx.deadline_ns = zix.Grpc.wallClockNs() + 30 * std.time.ns_per_s`. Contoh `grpc_timeout.zig` di bawah menunjukkan demo lengkap.

**Contoh:**
- [examples/grpc_server.zig](examples/grpc_server.zig) - Server gRPC, model dispatch dipilih per target
- [examples/grpc_client.zig](examples/grpc_client.zig) - Client gRPC: unary dan streaming
- [examples/grpc_multi_server.zig](examples/grpc_multi_server.zig) + [examples/grpc_multi_client.zig](examples/grpc_multi_client.zig) - satu port, dua layanan
- [examples/grpc_location_server.zig](examples/grpc_location_server.zig) - Layanan lokasi, model dispatch dipilih per target
- [examples/grpc_location_client.zig](examples/grpc_location_client.zig) - Client layanan lokasi
- [examples/grpc_timeout.zig](examples/grpc_timeout.zig) - Timeout konteks: global, per-rute, override

**Kapan digunakan:** pakai `zix.Grpc` untuk RPC antar-service internal saat kamu ingin metode bertipe, streaming, dan deadline tanpa mendirikan TLS terminator atau sidecar (h2c berbicara plaintext di jaringan tepercaya). Keempat bentuk RPC dimultipleks melalui satu koneksi, jadi pilih ini daripada framing TCP buatan tangan untuk request/response terstruktur antar service-mu sendiri. Pasang proxy di depan (lihat dokumen proxy TLS) saat ia harus melintasi batas tak tepercaya.

Lihat [`docs/hld-grpc-id.md`](docs/hld-grpc-id.md) untuk dokumentasi lengkap termasuk semua 4 pola tipe RPC dan setup proxy TLS.

<br>

### TLS (https / h2)

Server Http1 dan Http2 melayani cleartext secara default. Pasang sebuah `zix.Tls.Context` untuk opt-in ke TLS di jalur ber-gate, membiarkan engine cleartext tidak tersentuh. Context memuat cert / key dan memvalidasi policy sekali saat startup, lalu tiap koneksi memakainya ulang. Untuk Http2 dan gRPC, model `.EPOLL` / `.URING` menterminasi TLS di dispatch worker dan memultipleks banyak koneksi per core, jadi https tidak men-spawn thread per koneksi.

```zig
var tls = try zix.Tls.Context.init(allocator, io, .{
    .cert_path = "examples/certs/ecdsa_p256_cert.pem",
    .key_path  = "examples/certs/ecdsa_p256_key.pem",
    .alpn      = &.{ .HTTP_1_1 }, // .H2 untuk server Http2
});
defer tls.deinit();

var server = zix.Http1.Server.init(handler, .{ .io = io, .ip = "127.0.0.1", .port = 9060, .tls = &tls, .dispatch_model = .EPOLL });
```

Dengan `tls` diisi, server menjadi TLS-only di `port`. Tambahkan `tls_port` untuk melayani KEDUANYA dari satu server (dual listener,): cleartext di `port` dan TLS di `tls_port` dari worker fleet yang sama, alih-alih meluncurkan server kedua yang menduplikasi worker, tabel fd, dan cache. Tersedia di Http1, Http, Http2, dan Grpc, semua dispatch model (di bawah `.URING` sisi TLS berjalan di ring).

```zig
var server = zix.Http1.Server.init(handler, .{
    .io = io,
    .ip = "127.0.0.1",
    .port = 9076, // cleartext
    .tls = &tls,
    .tls_port = 9077, // https, worker yang sama
    .dispatch_model = .EPOLL,
});
```

Dua path wajib diisi, sisanya default ke postur aman (floor TLS 1.2, 1.3 diutamakan, ECDHE-only). `Tls.Context.Config` juga mengekspos `min_version` / `max_version`, `curves`, `ciphers`, `prefer_server_ciphers`, dan `hsts_max_age_s`. Curve dan cipher divalidasi ke set yang diimplementasi, jadi value yang tidak didukung adalah error saat startup. Cert bisa ECDSA P-256, Ed25519, atau RSA: `Tls.Context.init` mendeteksi tipe key dari cert (cert RSA membutuhkan TLS 1.3 dan menandatangani CertificateVerify dengan `rsa_pss_rsae_sha256`). Untuk deployment baru utamakan Ed25519 (signature handshake termurah), lalu ECDSA P-256, lalu RSA (pakai RSA untuk menyajikan cert RSA yang sudah diterbitkan). Lihat [docs/zix-deploy-id.md](docs/zix-deploy-id.md) untuk snippet config per tipe dan deployment Docker image.

- [examples/tls/tls_http1_basic.zig](examples/tls/tls_http1_basic.zig) - https/1.1
- [examples/tls/tls_http2_basic.zig](examples/tls/tls_http2_basic.zig) - h2 over TLS
- [examples/tls/tls_http1_ed25519.zig](examples/tls/tls_http1_ed25519.zig) - server cert Ed25519
- [examples/tls/tls_http1_dual.zig](examples/tls/tls_http1_dual.zig) - dual listener (cleartext + https, satu server)

<br>

### Raw TCP

`zix.Tcp` adalah server dan client TCP stream mentah. Handler dibakukan ke dalam tipe server pada `init` dan `io` adalah field config, sehingga `run()` tidak menerima argumen (). Handler per-connection memiliki stream dan berjalan di bawah `.ASYNC` / `.EPOLL`. Untuk ring `.URING` yang completion-based ada jalur callback per-frame terpisah, `initFramed`. Format frame default: length prefix big-endian 4 byte.

```zig
const std = @import("std");
const zix = @import("zix");

fn myHandler(stream: std.Io.net.Stream, io: std.Io) void {
    defer stream.close(io);
    var rbuf: [4100]u8 = undefined;
    var rdr = stream.reader(io, &rbuf);
    var buf: [4096]u8 = undefined;
    while (true) {
        const len = rdr.interface.takeVarInt(u32, .big, 4) catch return;
        if (len == 0 or len > buf.len) return;
        rdr.interface.readSliceAll(buf[0..len]) catch return;
        const msg = buf[0..len];
        _ = msg; // proses msg
        // tulis respons dengan stream.writer()
    }
}

pub fn main(process: std.process.Init) !void {
    // handler dibakukan pada init, io ada di config, run() tidak menerima argumen
    var server = try zix.Tcp.Server.init(myHandler, .{
        .io   = process.io,
        .ip   = "127.0.0.1",
        .port = 9300,
        .dispatch_model = .ASYNC,
    });
    defer server.deinit();
    try server.run();
    // default echo bawaan eksplisit: zix.Tcp.Server.init(zix.Tcp.echoHandler, .{ ... })
}
```

**Callback per-frame (ring `.URING`):** ketika handler tidak perlu memiliki koneksi, daftarkan sebuah `FrameFn` yang dipanggil engine sekali per frame ter-decode. Ini satu-satunya jalur yang berjalan native di ring io_uring:

```zig
fn onFrame(payload: []const u8, fd: std.posix.fd_t) void {
    _ = payload; // engine memiliki koneksi; balas pada fd
    _ = fd;
}

var server = try zix.Tcp.Server.initFramed(onFrame, .{
    .io   = process.io,
    .ip   = "127.0.0.1",
    .port = 9304,
    .dispatch_model = .URING,
});
defer server.deinit();
try server.run();
```

**Format frame:** `[u32 big-endian payload_len][payload bytes]`. Baik `echoHandler` bawaan maupun `TcpClient.sendMsg`/`recvMsg` menggunakan format ini.

**TcpClient:**

```zig
var client = try zix.Tcp.Client.connect(.{
    .ip   = "127.0.0.1",
    .port = 9300,
}, io);
defer client.deinit(io);

try client.sendMsg(io, "hello");
var buf: [4096]u8 = undefined;
const reply = try client.recvMsg(io, &buf);
```

**Override argumen CLI** (tanpa rebuild): `initArgs` / `initFramedArgs` adalah `init` / `initFramed` plus parsing `--ip` / `--port` dari `process.minimal.args`, sehingga satu binary yang sudah di-build bisa bind ke address atau port berbeda. Contoh memakai `init` / `initFramed` polos. Pakai varian `Args` hanya saat kamu ingin override runtime.

```zig
var server = try zix.Tcp.Server.initArgs(myHandler, .{ .io = process.io, .ip = "127.0.0.1", .port = 9300 }, process.minimal.args);
var client = try zix.Tcp.Client.connectArgs(.{ .ip = "127.0.0.1", .port = 9300 }, io, process.minimal.args);
```

**Kapan digunakan:** pakai `zix.Tcp` ketika kamu memiliki protokol wire-nya sendiri: framing biner kustom, RPC privat, proxy, atau probe di mana overhead HTTP/gRPC tidak diinginkan. Pakai handler per-connection (`init`) untuk sesi stateful, request/response atau streaming di mana handler menggerakkan socket. Pakai callback per-frame `initFramed` ketika kerjanya stateless per frame dan kamu ingin ring `.URING` (engine memiliki koneksi, callback tidak pernah blocking). Jika hanya butuh IPC same-host, pilih `zix.Uds`. Jika butuh request routing atau browser, pilih `zix.Http1` / `zix.Http`.

**Contoh:**
- [examples/tcp_server.zig](examples/tcp_server.zig)
- [examples/tcp_client.zig](examples/tcp_client.zig)

[`docs/hld-tcp-id.md`](docs/hld-tcp-id.md) untuk detail.

<br>

### FIX 4.x

`zix.Fix` adalah server dan client lapisan sesi FIX 4.x. Framing SOH-delimited (0x01). Penanganan sesi (Logon/Logout/Heartbeat) sudah built-in. Pesan aplikasi didispatch ke router comptime atau di-echo ketika tidak ada rute yang terdaftar.

Mode echo (tanpa routing):

```zig
const std = @import("std");
const zix = @import("zix");

pub fn main(process: std.process.Init) !void {
    var server = try zix.Fix.Server.init(null, .{
        .io                   = process.io,
        .ip                   = "127.0.0.1",
        .port                 = 9500,
        .comp_id              = "SERVER",
        .dispatch_model       = .ASYNC,
        .heartbeat_timeout_ms = 30_000, // 0 = dinonaktifkan (default)
    });
    defer server.deinit();
    try server.run();
}
```

Mode router (dispatch pesan aplikasi):

```zig
fn handleNewOrder(req: *zix.Fix.Request, res: *zix.Fix.Response, ctx: *zix.Fix.Context) !void {
    if (ctx.isExpired()) return;
    const symbol = req.getField(.Symbol) orelse return;
    res.sendMessage(zix.Fix.MsgType.ExecutionReport, &[_]zix.Fix.BuildField{
        .{ .tag = .Symbol, .value = symbol },
        .{ .tag = .OrdStatus, .value = "0" },
    });
}

const router = zix.Fix.Router(&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle, .handler = handleNewOrder, .timeout_ms = 500 },
});

var server = try zix.Fix.Server.init(
    router.dispatch,
    .{
        .io                    = process.io,
        .ip                    = "0.0.0.0",
        .port                  = 9500,
        .comp_id               = "BROKER",
        .dispatch_model        = .ASYNC,
        .handler_timeout_ms    = 200,
        .conn_timeout_ms       = 60_000,
    },
);
```

`FixClient`:

```zig
var client = try zix.Fix.Client.connect(.{
    .ip             = "127.0.0.1",
    .port           = 9500,
    .comp_id        = "CLIENT",
    .target_comp_id = "SERVER",
}, io);
defer client.deinit(io);

try client.logon(io, 30);
try client.sendMessage(io, zix.Fix.MsgType.NewOrderSingle, &[_]zix.Fix.BuildField{
    .{ .tag = .ClOrdID,  .value = "order-001" },
    .{ .tag = .Symbol,   .value = "AAPL" },
    .{ .tag = .Side,     .value = "1" },
    .{ .tag = .OrderQty, .value = "100" },
});
const msg = try client.recvMessage(io);
_ = msg;
try client.logout(io);
```

**Pesan sesi ditangani otomatis:**

| MsgType (tag 35) | Aksi server |
| :- | :- |
| `A` (Logon) | Balas dengan Logon, CompID ditukar |
| `5` (Logout) | Balas dengan Logout, lalu tutup |
| `0` (Heartbeat) | Balas dengan Heartbeat |
| `1` (TestRequest) | Balas dengan Heartbeat |
| lainnya (routes non-kosong) | Dispatch ke handler rute yang sesuai |
| lainnya (routes kosong) | Echo tanpa perubahan |

**`zix.Fix.MsgType`**: namespace struct berisi 47 konstanta string compile-time untuk nilai MsgType FIX (FIX 4.0-4.4). Gunakan konstanta bernama daripada string mentah: `MsgType.NewOrderSingle` (`"D"`), `MsgType.ExecutionReport` (`"8"`), `MsgType.Logon` (`"A"`), dll.

**Model dispatch:** `.ASYNC` (cocok untuk sesi FIX long-lived dan satu-satunya model portabel), `.EPOLL`, `.URING` (keduanya khusus Linux: worker per-core shared-nothing). Di luar Linux, `run()` mengembalikan `error.ZixDispatchModelUnsupported`: pakai `.ASYNC` di sana.

**Kapan digunakan:** pakai `zix.Fix` saat kamu berintegrasi dengan counterparty finansial melalui FIX 4.x: order entry, execution report, sesi market-data. Mekanika sesi (Logon/Logout/Heartbeat/TestRequest, penanganan sequence) sudah built-in, jadi kamu hanya menulis handler pesan aplikasi. Pakai mode echo untuk harness konformansi dan mode router untuk logika trading nyata. Untuk protokol non-finansial pakai `zix.Tcp`.

**Contoh:**
- [examples/fix_server.zig](examples/fix_server.zig)
- [examples/fix_server_trading.zig](examples/fix_server_trading.zig)
- [examples/fix_client.zig](examples/fix_client.zig)
- [examples/fix_client_raw.zig](examples/fix_client_raw.zig)
- [examples/fix_client_trading.zig](examples/fix_client_trading.zig)

[`docs/hld-fix-id.md`](docs/hld-fix-id.md) untuk detail.

<br>

### UDS (Unix Domain Sockets)

IPC dalam host yang sama melalui Unix stream socket. Server menerima koneksi dan mendispatch masing-masing sebagai tugas concurrent. Kedua sisi menggunakan format frame dengan length prefix 4 byte.

```zig
// Proses A: server UDS (penyedia data)
pub fn main(process: std.process.Init) !void {
    // handler dibakukan pada init, io ada di config, run() tidak menerima argumen
    var server = try zix.Uds.Server.init(zix.Uds.echoHandler, .{
        .io        = process.io,
        .path      = "/tmp/app.sock",
        .allocator = std.heap.smp_allocator,
    });
    defer server.deinit();
    try server.run();
    // handler kustom: zix.Uds.Server.init(myHandler, .{ .io = process.io, ... })
}
```

```zig
// Proses B: client UDS (konsumer)
var client = try zix.Uds.Client.connect(.{ .path = "/tmp/app.sock" }, io);
defer client.deinit(io);

try client.sendMsg(io, "get");              // mengirim [u32 len][payload]
var buf: [4096]u8 = undefined;
const reply = try client.recvMsg(io, &buf); // membaca [u32 len][payload]
```

Handler kustom: menerima stream mentah secara langsung, dilewatkan ke `init`:

```zig
fn myHandler(stream: std.Io.net.Stream, io: std.Io) void {
    defer stream.close(io);
    // baca/tulis frame menggunakan stream.reader() dan stream.writer()
}

var server = try zix.Uds.Server.init(myHandler, .{
    .io        = process.io,
    .path      = "/tmp/app.sock",
    .allocator = std.heap.smp_allocator,
});
defer server.deinit();
try server.run();
```

**Format frame:** `[u32 payload_len, big-endian, 4 bytes][payload bytes]`. Frame dengan payload > `max_recv_buf` (default 4096) menutup koneksi.

**Kapan digunakan:** pilih UDS untuk IPC same-host antar proses yang bekerja sama (sidecar, agen lokal, helper berprivilese) saat kamu ingin semantik stream tanpa port TCP atau network stack. Lebih cepat dan lebih aman dari TCP loopback (izin filesystem menjaga socket). Antar host, pakai `zix.Tcp`.

**Contoh:**
- [examples/uds_server.zig](examples/uds_server.zig) - contoh lengkap yang berfungsi
- [examples/uds_http.zig](examples/uds_http.zig) - contoh lengkap yang berfungsi (HTTP over UDS)
- [examples/uds_client.zig](examples/uds_client.zig) - client UDS length-prefixed
- [examples/http_uds_client.zig](examples/http_uds_client.zig) - client HTTP/1.1-over-UDS

[`docs/hld-uds-id.md`](docs/hld-uds-id.md) untuk detail.

<br>

### Channel

Pengiriman pesan dalam proses yang aman untuk fiber dan bertipe. Antrian ring buffer yang menghubungkan tugas producer dan consumer (OS thread atau fiber `io.concurrent`) dalam proses yang sama.

```zig
const MyChan = zix.Channel(u32);

// kapasitas 8: send memblokir saat penuh, recv memblokir saat kosong
var ch = try MyChan.init(std.heap.smp_allocator, 8);
defer ch.deinit();

// producer (berjalan di thread/task-nya sendiri)
try ch.send(io, 42);
ch.close(io); // sinyal selesai: receiver menguras, lalu mendapatkan error.ZixClosed

// consumer (berjalan di thread/task-nya sendiri)
while (true) {
    const v = ch.recv(io) catch break; // error.ZixClosed ketika channel dikuras dan ditutup
    // proses v
}
```

`send` dan `recv` memerlukan `io` yang valid di thread pemanggil. Setiap OS thread memerlukan `std.Io`-nya sendiri (misalnya dari `std.Io.Threaded`):

```zig
var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{});
defer threaded.deinit();
const io = threaded.io();

const t = try std.Thread.spawn(.{}, workerFn, .{ &ch, io });
t.join();
```

**Contoh:**
- [examples/channel_basic.zig](examples/channel_basic.zig) - producer/consumer: dua OS thread, Channel(u32)
- [examples/channel_worker_pool.zig](examples/channel_worker_pool.zig) - fan-out: satu producer, banyak consumer worker
- [examples/channel_pipeline.zig](examples/channel_pipeline.zig) - pipeline multi-tahap: backpressure mengalir ke hulu
- [examples/channel_ipc_a.zig](examples/channel_ipc_a.zig) + [examples/channel_ipc_b.zig](examples/channel_ipc_b.zig) - pasangan koordinasi antar-proses
- [examples/uds_http.zig](examples/uds_http.zig) - HTTP + UDS + Channel: pola integrasi penuh

**Kapan digunakan:** pakai `Channel` untuk mengoper pesan bertipe antar task dalam satu proses: producer/consumer, worker pool fan-out, atau pipeline ber-backpressure. Ring berbatas menerapkan backpressure untukmu (send blocking saat penuh), yang membuatnya primitif tepat untuk memisahkan producer cepat dari consumer yang lebih lambat. Untuk pesan lintas-proses, pasangkan dengan UDS.

Untuk detail desain lihat [`docs/hld-channel-id.md`](docs/hld-channel-id.md).

<br>

### UDP

Dua mode. Typed `zix.Udp.Server(Packet)` adalah server messaging yang aman tipe: pengguna mendefinisikan `extern struct` paket mereka sendiri, dan zix menangani endianness, validasi ukuran, dan konkurensi. Raw `zix.Udp.Raw(handler)` melayani datagram variable-length tanpa struct tetap, dengan batching `recvmmsg` / `sendmmsg` dan worker SO_REUSEPORT per-core.

```zig
const std = @import("std");
const zix = @import("zix");

const Packet = extern struct {
    id:       [16]u8,
    kind:     i32,
    register: u32,
    position: [3]f64,
};

const MyServer = zix.Udp.Server(Packet);

pub fn main(process: std.process.Init) !void {
    // Berikan process.minimal.args dan set .allow_args = true untuk membaca override --ip / --port.
    var server = try MyServer.init(.{
        .io         = process.io,
        .allocator  = std.heap.smp_allocator,
        .ip         = "127.0.0.1",
        .port       = 9100,
        .dispatch_model = .ASYNC, // typed server menjalankan satu async loop
        .endianness = .LITTLE,
        .broadcast  = true,   // relay setiap paket ke semua client yang terhubung
        .auto_ack   = false,
        .conn_timeout_ms = 5000,
        .poll_timeout_ms = 2000,
    }, .{});
    defer server.deinit();
    try server.run();
}
```

Client (send + receive concurrent):

```zig
const MyClient = zix.Udp.Client(Packet);

pub fn main(process: std.process.Init) !void {
    const io = process.io;
    // Berikan process.minimal.args dan set .allow_args = true untuk membaca
    // override --bind-ip / --bind-port / --server-port.
    var client = try MyClient.init(.{
        .ip          = "127.0.0.1", // alamat server
        .server_port = 9100,
        .bind_port   = 9101,
        .endianness  = .LITTLE,
    }, io, .{});
    defer client.deinit();

    // spawn tugas receive bersamaan dengan loop send
    _ = io.concurrent(receiveLoop, .{&client}) catch {};

    const p = Packet{ .id = [_]u8{0} ** 16, .kind = 1, .register = 0, .position = .{ 0.0, 0.0, 0.0 } };
    while (true) {
        client.send(p) catch {};
        try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(1000), .awake);
    }
}
```

Mode raw-bytes (datagram variable-length, tanpa struct tetap):

```zig
fn handler(dg: []const u8, peer: *const std.Io.net.IpAddress, sink: *zix.Udp.Sink) void {
    sink.reply(dg); // echo back to the sender
}

const Echo = zix.Udp.Raw(handler);

pub fn main(process: std.process.Init) !void {
    var server = try Echo.init(.{
        .io        = process.io,
        .allocator = std.heap.smp_allocator,
        .ip        = "0.0.0.0",
        .port      = 9064,
        .dispatch_model = .EPOLL, // worker SO_REUSEPORT per-core (.ASYNC = satu worker)
    }, .{});
    defer server.deinit();
    try server.run();
}
```

**Kapan digunakan:** pakai UDP saat kamu ingin datagram fire-and-forget latensi rendah: telemetri, state game, discovery, heartbeat, atau broadcast/relay ke banyak peer, menerima pengiriman best-effort. Pakai typed `Server(Packet)` untuk kontrak `extern struct` tetap, raw `Raw(handler)` untuk payload byte sembarang dan jalur batched per-core. Jika kamu butuh urutan, retransmisi, atau payload besar, pakai `zix.Tcp`.

**Contoh:**
- [examples/udp_server.zig](examples/udp_server.zig) - server typed, contoh lengkap dengan broadcast dan port yang dapat dikonfigurasi
- [examples/udp_client.zig](examples/udp_client.zig) - client yang cocok
- [examples/udp_server_raw.zig](examples/udp_server_raw.zig) - server echo raw-bytes (batching recvmmsg / sendmmsg, dispatch model)
- [examples/udp_server_tickrate.zig](examples/udp_server_tickrate.zig) - tick loop ala game server di path raw, broadcast world snapshot per tick (--tickrate, 64 atau 128)
- [examples/udp_client_tickrate.zig](examples/udp_client_tickrate.zig) - client yang cocok, jalankan beberapa instance dengan --bind-port berbeda

[`docs/hld-udp-id.md`](docs/hld-udp-id.md) untuk detail.

<br>

### HTTP/3

HTTP/3 berjalan di atas QUIC, yang berjalan di atas UDP, jadi `zix.Http3` berada pada substrat datagram `zix.Udp` yang sama di atas, bukan pada stack TCP / TLS. Ini adalah server HTTP/3 pure-Zig di atas QUIC (RFC 9114 / 9000 / 9001 / 9002). Transport QUIC, packet protection, glue handshake TLS 1.3, dan kompresi header QPACK semuanya ditulis dari RFC dan dibuktikan byte-exact terhadap worked example RFC. TLS 1.3 dilipat ke dalam handshake QUIC (tidak ada mode cleartext dan tidak ada TLS record layer), dikonfigurasi oleh `zix.Tls.Context` yang sama seperti engine TCP, jadi cert ECDSA P-256, Ed25519, atau RSA semuanya bekerja.

Route adalah table comptime (`zix.Http3.Router`), berbentuk sama seperti `zix.Http1` / `zix.Http2`, di-dispatch pada path request terdekode.

```zig
const std = @import("std");
const zix = @import("zix");

fn home(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.send("hello over http/3\n");
}

const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
    .{ .path = "/", .handler = home },
});

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = "examples/certs/ecdsa_p256_cert.pem",
        .key_path  = "examples/certs/ecdsa_p256_key.pem",
    });
    defer tls.deinit();

    var server = zix.Http3.Server.init(Routes.dispatch, .{
        .io             = process.io,
        .allocator      = std.heap.smp_allocator,
        .ip             = "127.0.0.1",
        .port           = 9063,
        .dispatch_model = .ASYNC,
        .tls            = &tls,
    });
    defer server.deinit();

    try server.run();
}
```

```sh
# Uji dengan curl yang dibangun dengan HTTP/3 (jalankan dari root repo agar path cert resolve)
curl --http3-only -k https://127.0.0.1:9063/
```

**HandlerFn:** `fn(req: *const zix.Http3.Request, res: *zix.Http3.Response, ctx: *zix.Http3.Context) anyerror!void`

- `req.method` dan `req.path` diisi dari wire. Body response yang diserahkan ke `res.send` disalin setelah handler kembali, jadi boleh menunjuk ke memori static atau milik handler.
- `req.body` membawa body request, dengan `req.bodyReceived()` untuk berapa byte body yang tiba dan `req.bodyComplete()` untuk apakah itu keseluruhannya, pasangan yang sama seperti `zix.Http1`. Request dengan body jarang tiba dalam satu paket, jadi engine menahannya sampai client mengakhiri stream QUIC-nya lalu menjalankan handler sekali, dengan body utuh. `max_request_stream_bytes` (default 8192) adalah body terbesar yang bisa diberikan utuh ke handler: naikkan ke upload terbesar yang diterima route. Melewatinya, body diantar terpotong dan terbaca false, jadi handler bisa menolak fragment alih-alih mem-parsing-nya. Ketika seluruh `max_pending_request_streams` slot milik worker sedang sibuk dengan request yang masih tiba, request baru dijawab 503, bukan dijalankan atas body yang engine tahu belum lengkap. Slice-nya meminjam buffer dekode, jadi salin bila ingin menyimpannya melewati pemanggilan handler.
- `req.accept_encoding` membawa Accept-Encoding klien (kosong jika tidak ada). Handler menegosiasi body pre-compressed terhadapnya lalu memanggil `res.setContentEncoding(.br)` (atau `.gzip`), yang memancarkan header response `content-encoding`. Engine tidak pernah mengompresi di jalur kirim: `res.body` harus sudah ter-encode (menyajikan file `.br` / `.gz` yang sudah jadi), jadi tidak ada biaya codec per-request.
- `ctx` membawa `stream_id` (raw escape hatch, QUIC tidak punya fd per-request), `io`, allocator arena per-request, dan helper timeout (`withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut`), bentuk yang sama seperti engine lainnya. Error handler otomatis diselesaikan sebagai satu 500 ketika belum ada yang terkirim (`res.sent`).
- `run()` membutuhkan port non-zero dan TLS context: ia mengembalikan `error.ZixPortNotConfigured` atau `error.ZixTlsRequired` jika tidak (`init` hanya menyimpan config).

**Dispatch model:** `.ASYNC` menjalankan satu loop recv single-worker dengan connection-id demux internal (migration-safe). `.EPOLL` / `.URING` menjalankan satu worker SO_REUSEPORT per core dengan readiness epoll atau completion io_uring di atasnya (`.URING` fold ke loop worker epoll saat io_uring tidak tersedia), dan keduanya khusus Linux. Connection-id steering per-core ditunda (fase 3).

**Contoh:** [examples/tls/http3_basic.zig](examples/tls/http3_basic.zig) (port 9063) menyajikan `/`, query-sum `/baseline2`, `/big` 256 KiB yang menguji jalur kirim streamed multi-packet, `/negotiated` yang menyajikan body brotli-precompressed dengan `content-encoding: br` saat klien menerima br, dan `/echo` yang menjawab POST dengan jumlah byte yang diterima, apakah itu body utuh, beserta body-nya.

Lihat [`docs/hld-http3-id.md`](docs/hld-http3-id.md) dan [`docs/lld-http3-id.md`](docs/lld-http3-id.md) untuk desain lengkap dan internal per-layer.

<br>

### WebTransport

`zix.Webtransport` adalah WebTransport over HTTP/3, dilayani `zix.Http3` di koneksi QUIC yang sudah dimilikinya: browser (atau client WebTransport apa pun) membuka session dengan extended CONNECT (RFC 9220) lalu memakai stream data yang reliabel dan datagram yang tidak reliabel di satu koneksi itu, berdampingan dengan request HTTP/3 biasa. Pure-Zig dari draft-nya, tanpa library di dalamnya.

Dua revisi diterima sekaligus. draft-ietf-webtrans-http3-16 adalah revisi saat ini (token `webtransport-h3`, `SETTINGS_WT_ENABLED` 0x2c7cf000, flow control level session, `RESET_STREAM_AT` pada reset stream), dan draft-07 deployed (token `webtransport`, `SETTINGS_ENABLE_WEBTRANSPORT` 0x2b603742) adalah yang masih dikirim browser dan aioquic. Server mengiklankan keduanya di satu SETTINGS frame, dan token `:protocol` pada CONNECT yang menentukan mana yang diucapkan sebuah session.

```zig
const std = @import("std");
const zix = @import("zix");

// Route HTTP/3 biasa: session WebTransport dan request biasa berbagi satu koneksi.
fn home(_: *const zix.Http3.Request, res: *zix.Http3.Response, _: *zix.Http3.Context) !void {
    res.send("hello over http/3\n");
}

fn onSession(session: *zix.Webtransport.Session) ?u16 {
    const request = session.sessionRequest();
    if (!std.mem.eql(u8, request.path, "/echo")) return 404;

    // Stream unidirectional yang dibuka server untuk session ini.
    if (session.openUni()) |stream| {
        _ = stream.write("hello from zix\n");
        stream.finish();
    }

    return null;
}

/// Pantulkan apa pun yang tiba di stream data. Tulisan pendek adalah back pressure yang normal.
fn onStream(session: *zix.Webtransport.Session, stream: *const zix.Webtransport.Stream) void {
    _ = session;
    _ = stream.write(stream.read());
    stream.finish();
}

/// Pantulkan sebuah datagram. Datagram tidak pernah diantre: false berarti tidak terkirim.
fn onDatagram(session: *zix.Webtransport.Session, datagram: []const u8) void {
    _ = session.sendDatagram(datagram);
}

fn onClose(session: *zix.Webtransport.Session) void {
    const info = session.closeInfo();
    std.log.info("session {d} closed: {s} code={d}", .{ session.id(), @tagName(info.reason), info.code });
}

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = "examples/certs/ecdsa_p256_cert.pem",
        .key_path  = "examples/certs/ecdsa_p256_key.pem",
    });
    defer tls.deinit();

    const Routes = zix.Http3.Router(&[_]zix.Http3.Route{
        .{ .path = "/", .handler = home },
    });

    var server = zix.Http3.Server.init(Routes.dispatch, .{
        .io             = process.io,
        .allocator      = std.heap.smp_allocator,
        .ip             = "127.0.0.1",
        .port           = 9089,
        .dispatch_model = .ASYNC,
        .tls            = &tls,
        .webtransport = .{
            .enabled = true,
            .max_sessions_per_connection = 4,
            .max_streams_bidi = 16,
            .max_streams_uni = 16,
            .max_session_data = 1 << 20,
            .handler = .{
                .on_session = onSession,
                .on_stream = onStream,
                .on_datagram = onDatagram,
                .on_close = onClose,
            },
        },
    });
    defer server.deinit();

    try server.run();
}
```

**Handler:** lima callback opsional. `on_session` memutuskan sebuah CONNECT (null menerima, status HTTP menolak, dan engine menjawab stream request-nya pada kedua kasus), `on_stream` menerima chunk stream data, `on_stream_reset` menerima stream yang dibatalkan peer, `on_datagram` menerima satu datagram dengan routing-nya sudah dilepas, dan `on_close` menerima session setelah berakhir.

- `Session` menjawab lewat `openBidi`, `openUni`, `sendDatagram`, `close`, dan `drain`, serta melaporkan `id()`, `dialect()`, `state()`, `isOpen()`, `sessionRequest()`, `streamsAvailable(kind)`, dan `closeInfo()`. `Stream` menjawab lewat `write`, `finish`, `reset`, dan `stop`, serta melaporkan `id()`, `kind()`, `initiator()`, `read()`, `chunk_offset`, `finished()`, `resetCode()`, dan `writable()`.
- Lifetime mengikuti sisa zix: session, stream, dan setiap slice yang diserahkannya valid untuk callback yang menghasilkannya. Aplikasi yang membutuhkan byte-nya nanti harus menyalinnya, dan handle yang disimpan melewati callback-nya bersifat inert, bukan menggantung.
- `write` yang pendek adalah back pressure, bukan error: peer belum mengakui apa yang diantre, jadi sisanya keluar dari callback berikutnya. `sendDatagram` mengembalikan false ketika datagram tidak bisa dikirim sekarang (tanpa negosiasi datagram, payload melewati limit frame peer, atau tidak ada ruang congestion window) dan tidak pernah mengantrenya untuk nanti.
- Callback tiba di worker yang memiliki koneksi QUIC, satu datagram pada satu waktu, sehingga handler berjalan single-threaded per koneksi dan tidak butuh lock. Dispatcher-nya milik HTTP/3, tidak berubah.
- Limit diiklankan dan ditegakkan: `max_sessions_per_connection` (429 saat tercapai, 503 saat pool worker tidak punya slot), `max_streams_bidi` / `max_streams_uni` per session, `max_session_data` untuk anggaran byte level session, `stream_send_bytes` sebagai write window per stream, dan `max_datagram_frame_size` di kedua arah. Stream pra-session melewati buffer worker direset dengan `WT_BUFFERED_STREAM_REJECTED`, dan setiap stream session yang menutup direset dengan `WT_SESSION_GONE`.
- `legacy_dialect = false` hanya menerima revisi saat ini. Matikan hanya ketika setiap client diketahui mengucapkannya, karena setiap browser yang beredar masih mengirim token deployed.
- Validasi origin milik aplikasi: engine menyerahkan `origin` request ke `on_session` (browser selalu mengirimnya) dan tidak mengarang kebijakan.

**Contoh:** [examples/tls/http3_webtransport.zig](examples/tls/http3_webtransport.zig) (port 9089) menerima session di `/echo`, memantulkan setiap chunk stream data dan setiap datagram, membuka satu stream unidirectional per session dengan banner, dan mencetak lifecycle session ke stderr. Dibangun dengan `zig build example-http3_webtransport`. Gerakkan dengan client WebTransport over HTTP/3 mana pun, dan `zig build test-runner-webtransport` menggerakkannya end to end dari client in-tree.

Lihat [`docs/hld-webtransport-id.md`](docs/hld-webtransport-id.md) dan [`docs/lld-webtransport-id.md`](docs/lld-webtransport-id.md) untuk desain lengkap dan internal per-file.

<br>

### WebRTC

`zix.Webrtc` adalah peer WebRTC, yang memungkinkan browser menjangkau server lewat sesuatu selain HTTP atau WebSocket: pengiriman tidak reliabel, pilihan urutan per channel, serta audio dan video. Semuanya datang di satu port UDP lalu dipilah dari byte pertamanya (RFC 7983): ICE connectivity check yang dibawa lewat STUN, handshake DTLS 1.2, association SCTP beserta data channel-nya, dan opsional media SRTP. Semuanya ditulis dari RFC, dengan `std.crypto` di bawahnya dan tanpa OpenSSL.

zix menjawab, ia tidak pernah gathering. ICE agent-nya lite dan role DTLS-nya selalu server, dan itulah yang mengunci data channel ke stream identifier ganjil.

```zig
const std = @import("std");
const zix = @import("zix");

fn onEvent(event: zix.Webrtc.Event, ctx: *zix.Webrtc.Context) !void {
    switch (event) {
        .CHANNEL_OPEN => |channel| std.log.info("channel {d} open", .{channel}),
        .CHANNEL_CLOSED => |channel| std.log.info("channel {d} closed", .{channel}),
        .MESSAGE => |message| try ctx.send(message.channel, message.kind, message.payload),
    }
}

pub fn main(process: std.process.Init) !void {
    var tls = try zix.Tls.Context.init(std.heap.smp_allocator, process.io, .{
        .cert_path = "examples/certs/ecdsa_p256_cert.pem",
        .key_path  = "examples/certs/ecdsa_p256_key.pem",
    });
    defer tls.deinit();

    var server = zix.Webrtc.Server.init(onEvent, .{
        .io             = process.io,
        .allocator      = std.heap.smp_allocator,
        .ip             = "127.0.0.1",
        .port           = 9083,
        .dispatch_model = .ASYNC,
        .ice_ufrag      = "zixanswer",
        .ice_password   = "zixanswerpasswordaaaaaa",
        .peer_ice_ufrag = "zixdialer",
        .tls            = &tls,
    });
    defer server.deinit();

    try server.run();
}
```

**HandlerFn:** `fn(event: zix.Webrtc.Event, ctx: *zix.Webrtc.Context) anyerror!void`

- Tiga event: `CHANNEL_OPEN` dan `CHANNEL_CLOSED` membawa stream identifier, `MESSAGE` membawa `channel`, `kind` dan `payload`. Sebuah `payload` dipinjam selama panggilan itu saja dan mati pada panggilan berikutnya, jadi apa pun yang perlu disimpan harus disalin keluar.
- `ctx` adalah tempat menjawab: `send(channel, kind, bytes)`, `broadcast(kind, bytes)`, `openChannel(request)`, `close(channel)`, `channelCount()`. Jangkauan `broadcast` adalah satu worker, yang berarti seluruh room di bawah `.ASYNC` dan bagian room milik core ini di bawah `.EPOLL` atau `.URING`.
- `run()` memvalidasi sebelum bind: `error.ZixPortNotConfigured`, `error.ZixIceCredentialsRequired`, `error.ZixIceCredentialsInvalid`, `error.ZixTlsRequired`, `error.ZixUnsupportedCertificateKey` (kuncinya harus ECDSA P-256), dan `error.ZixDispatchModelUnsupported` di luar Linux.
- Browser menarik ufrag ICE baru untuk setiap peer connection, jadi server yang menghadap browser mengisi `accept_any_peer_ice_ufrag = true` lalu membiarkan `ice_password` menjadi gerbangnya.

**Dispatch model:** `.ASYNC` menjalankan satu worker dan berjalan di mana saja. `.EPOLL` dan `.URING` menjalankan satu worker SO_REUSEPORT per core dan khusus Linux. Di sini sengaja tidak ada knob steering CPU: satu peer WebRTC adalah 4-tuple-nya, dan steering akan memecah satu sesi ke dua worker di tengah handshake.

**Media:** mati secara default. Dengan `carry_media` menyala, server meneruskan audio dan video antar peer-nya tanpa mendekode satu frame pun: paket dibuka sekali dengan kunci pengirim, header RTP-nya ditulis ulang untuk tiap penerima, lalu disegel kembali dengan kunci masing-masing penerima. RTCP dijawab, tidak pernah diteruskan.

**Example:** delapan, di port 9081 sampai 9088.

| Example | Port | Yang ditunjukkan |
| :- | :- | :- |
| [webrtc_signaling](examples/webrtc/webrtc_signaling.zig) | 9081 | relay room WebSocket, zix bukan peer |
| [webrtc_stun](examples/webrtc/webrtc_stun.zig) | 9082 | server STUN binding plus halaman yang membaca alamat reflexive-nya sendiri |
| [webrtc_datachannel_echo](examples/webrtc/webrtc_datachannel_echo.zig) | 9083 | server terkecil, memantulkan yang dikirim peer |
| [webrtc_native_pair](examples/webrtc/webrtc_native_pair.zig) | memanggil 9083 | zix memanggil zix, tanpa browser |
| [webrtc_datachannel_chat](examples/webrtc/webrtc_datachannel_chat.zig) | 9085 | satu pesan ke setiap browser lain di room |
| [webrtc_file_transfer](examples/webrtc/webrtc_file_transfer.zig) | 9086 | channel biner yang membawa sebuah berkas |
| [webrtc_sfu_broadcast](examples/webrtc/webrtc_sfu_broadcast.zig) | 9087 | unit forwarding, satu pengirim dan banyak penonton |
| [webrtc_video_call](examples/webrtc/webrtc_video_call.zig) | 9088 | panggilan mesh lewat relay, zix tidak membawa media |

Buka halaman browser lewat alamat jaringan mesin, bukan `localhost`: browser tidak mengumpulkan candidate loopback dan tidak akan memasangkannya. `webrtc_sfu_broadcast` adalah pengecualian, karena halaman pengirimnya juga butuh secure context untuk kamera, jadi ia tetap di `http://localhost` lalu menanyakan alamat yang akan dipublikasikan lewat query parameter `?at=`.

Lihat [`docs/hld-webrtc-id.md`](docs/hld-webrtc-id.md) dan [`docs/lld-webrtc-id.md`](docs/lld-webrtc-id.md) untuk desain lengkap dan internal per-layer.

<br>

### Logger

Logger file terstruktur dengan logging event per-protokol otomatis. Thread-safe: aman dipanggil dari OS thread latar belakang.

```zig
const std = @import("std");
const zix = @import("zix");

// Logger tidak membuat save_path secara otomatis, tanggung jawab pemanggil.
// Mengabaikan "already exists" secara diam-diam, aman dipanggil setiap start.
fn createLogDir(io: std.Io) void {
    std.Io.Dir.cwd().createDirPath(io, "./logs") catch {};
}

pub fn main(process: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();

    createLogDir(process.io);

    var logger = try zix.Logger.init(arena.allocator(), .{
        .save_path      = "./logs",
        .save_file      = "app",
        .save_min_level = .INFO,
        .console        = .ALWAYS,
    });
    defer logger.deinit();

    // Event sistem: komponen mana saja, level mana saja
    logger.system(.INFO,  "startup", "listening on {d}", .{9000});
    logger.system(.ERROR, "db",      "connect failed: {}", .{error.ConnectionRefused});

    // Pasangkan ke server HTTP untuk logging akses per-permintaan otomatis
    var server = zix.Http.Server.init(zix.Http.Router(&[_]zix.Http.Route{
        .{ .path = "/", .handler = homeHandler },
    }).dispatch, .{
        .io     = process.io,
        .ip     = "127.0.0.1",
        .port   = 9000,
        .logger = &logger,
    });
    defer server.deinit();
    try server.run();
}
```

File log ditulis ke `save_path/YYYY-MM-DD/save_file-NNNNNN.log`. Setiap baris adalah rekaman yang diakhiri newline:

```
# Format event sistem:
2026-05-16 12:34:56.789 INFO   [startup] listening on 9000
2026-05-16 12:34:56.789 ERROR  [db] connect failed: ConnectionRefused

# Format akses HTTP (2xx/3xx=INFO, 4xx=WARN, 5xx=ERROR, lainnya=DEBUG):
2026-05-16 12:34:56.789 INFO   GET /api/users 200 512 "MyBot/2.0" "http://example.com"
2026-05-16 12:34:56.789 WARN   GET /missing 404 0 "-" "-"
2026-05-16 12:34:56.789 ERROR  POST /crash 500 0 "-" "-"

# Penutupan stream gRPC:
2026-05-25 10:15:33.201 INFO   [grpc:rpc] 127.0.0.1:56789 /helloworld.Greeter/SayHello status=0 recv=16 sent=22 dur=1ms
```

| Field config | Default | Keterangan |
| :- | :- | :- |
| `console` | `.OFF` | Mode konsol: `.OFF`, `.DEBUG_ONLY` (hanya debug build), `.ALWAYS` |
| `console_min_level` | `.INFO` | Level minimum untuk output konsol |
| `save_path` | `""` | Root direktori untuk file log. Harus sudah ada. `""` menonaktifkan file logging |
| `save_file` | `"log"` | Nama file dasar. `"log"` menulis `log-000000.log`, `log-000001.log`, ... |
| `save_min_level` | `.INFO` | Level minimum untuk output file |
| `max_lines` | 1.000.000 | Baris per file sebelum berotasi ke nomor urut berikutnya |

**Metode log per-protokol:**

| Metode | Dipanggil otomatis oleh | Format baris |
| :- | :- | :- |
| `system(level, component, fmt, args)` | semua server (lifecycle) | `DATE TIME LEVEL  [component] message` |
| `access(method, path, status, bytes, ua, origin)` | server HTTP | `DATE TIME LEVEL  METHOD PATH STATUS BYTES "UA" "ORIGIN"` |
| `conn(peer, dur_ms, err)` | server TCP | `DATE TIME LEVEL  [tcp:conn] PEER dur=NNNms ERR` |
| `packet(dir, peer, size, err)` | server UDP | `DATE TIME LEVEL  [udp:pkt] DIRECTION PEER size=N ERR` |
| `frame(dir, sock_path, size, err)` | UDS (manual) | `DATE TIME LEVEL  [uds:frame] DIRECTION SOCKPATH size=N ERR` |
| `session(msg_type, sender, target, seq, state)` | server FIX | `DATE TIME LEVEL  [fix:sess] 35=TYPE sender=S target=T seq=N STATE` |
| `rpc(peer, path, grpc_status, recv, sent, dur_ms)` | server gRPC | `DATE TIME LEVEL  [grpc:rpc] PEER PATH status=N recv=N sent=N dur=Nms` |

Level: `.DEBUG`(0) `.INFO`(1) `.WARN`(2) `.ERROR`(3). Backend file menggunakan write buffer 64 KB yang di-flush saat rollover tanggal, rotasi urutan, `logger.flush()` eksplisit, atau `logger.deinit()`.

Pasangkan logger ke server mana saja dengan mengatur `logger: &logger` di konfigurasinya. Lihat [`docs/hld-logger-id.md`](docs/hld-logger-id.md) untuk dokumentasi lengkap.

**Kapan digunakan:** pasangkan `Logger` ke server mana saja di produksi untuk log file terstruktur yang berotasi dengan baris event per-protokol, dan panggil `logger.system()` untuk event lifecycle dan error milikmu. Mode console menjaga output development tetap terbaca sementara file tetap otoritatif. Aman dipanggil dari OS thread background, jadi satu logger bisa melayani seluruh proses.

<br>

### JSON (jzon)

`zix.jzon` adalah JSON dua arah, ditulis di atas standard library. Dua panggilan yang membawanya: `serialize` mengubah nilai bertipe menjadi teks JSON, `deserialize` mengubah teks JSON kembali menjadi nilai bertipe. Proses render tidak mengalokasikan apa pun, ia diberi sebuah buffer dan mengembalikan berapa byte yang dipakai. Proses parse hanya mengalokasikan apa yang ditunjuk hasilnya, dari allocator yang diberikan, sehingga reset arena membebaskan satu parse utuh dalam satu langkah.

```zig
const std = @import("std");
const zix = @import("zix");

const Order = struct {
    id: u64,
    customer: []const u8,
    tags: []const []const u8,
};

// serialize: tanpa allocator, buffer adalah seluruh anggarannya
var buf: [256]u8 = undefined;
const len = try zix.jzon.serialize(&buf, Order{
    .id       = 7,
    .customer = "Rekha Nair",
    .tags     = &.{ "priority", "gift" },
}, .{});
// buf[0..len] berisi {"id":7,"customer":"Rekha Nair","tags":["priority","gift"]}

// deserialize: semua yang ditunjuk hasilnya berasal dari allocator ini
var arena: std.heap.ArenaAllocator = .init(std.heap.smp_allocator);
defer arena.deinit();

const order = try zix.jzon.deserialize(Order, arena.allocator(), buf[0..len], .{});
```

Kedua panggilan menerima struct options comptime yang menyebut jalur mana yang berjalan. Setiap jalur tulis menghasilkan byte yang sama dan setiap jalur baca membaca kembali nilai yang sama, jadi strategy adalah keputusan biaya semata, diganti di call site tanpa baris lain ikut berubah. Karena comptime, hanya jalur yang disebut yang ikut dikompilasi ke binary.

**Strategy tulis (`zix.jzon.SerializeStrategy`):**

| Strategy | Yang dijalankan |
| :- | :- |
| `.STD` | `std.json.Stringify`, yang merender setiap bentuk yang dirender std |
| `.GENERATED_FMT` | digenerate dari tipenya, integer lewat `std.fmt` |
| `.GENERATED` | digenerate dari tipenya, digit integer ditulis langsung ke buffer |
| `.GENERATED_VECTOR` | seperti `.GENERATED`, dengan string dipindai satu vector lane sekaligus |

**Strategy baca (`zix.jzon.DeserializeStrategy`):**

| Strategy | Yang dijalankan |
| :- | :- |
| `.STD` | refleksi `std.json`, yang mem-parse setiap bentuk yang di-parse std |
| `.SCANNER` | token dari `std.json.Scanner`, dengan dispatch field digenerate dari tipenya |
| `.GENERATED` | digenerate dari tipenya, di atas read cursor milik jzon, satu byte sekaligus |
| `.GENERATED_VECTOR` | seperti `.GENERATED`, satu vector lane sekaligus |

`.GENERATED_VECTOR` tidak selalu paling cepat. Ia menguntungkan pada dokumen yang datang tertata dengan whitespace atau membawa string panjang, dan merugi pada trafik minified dengan field pendek, karena itu ia tetap pilihan di call site dan bukan default.

**Options baca (`zix.jzon.DeserializeOptions`):**

| Field | Default | Yang ditentukan |
| :- | :- | :- |
| `strategy` | `.STD` | jalur baca mana yang berjalan |
| `strings` | `.COPY` | `.COPY` menyalin setiap string ke allocator, `.BORROW` mengarahkan string tanpa escape ke dokumennya, sehingga dokumen itu harus hidup lebih lama daripada nilainya |
| `unknown` | `.REJECT` | `.REJECT` gagal pada key yang tidak dideklarasikan tipenya, `.SKIP` melangkahi key beserta seluruh nilainya sedalam apa pun bersarangnya |

**Error:** proses render melaporkan `error.NoSpaceLeft` dan tidak ada yang lain. Proses parse melaporkan satu set yang sama jalur mana pun yang berjalan: `UnknownField`, `MissingField`, `UnknownEnumValue`, `Truncated`, `Unexpected`, `BadNumber`, `BadEscape`, `OutOfMemory`.

Tipe field yang tidak punya bentuk JSON di jalur generated adalah compile error yang menyebut tipenya, bukan kegagalan runtime, dan `.STD` tetap menerima bentuk itu.

**Contoh:** enam, tidak ada yang berupa server, jadi masing-masing berjalan lalu selesai. jzon adalah package mandiri di bawah `src/jzon` dengan `build.zig` miliknya sendiri, jadi bangun dari sana dengan `zig build examples` (atau `zig build jzon-examples` dari root repo).

| Contoh | Yang ditunjukkan |
| :- | :- |
| [serialize](src/jzon/examples/serialize.zig) | sebuah nilai ke buffer tetap, setiap strategy tulis, dan apa yang dilaporkan buffer yang terlalu kecil |
| [deserialize](src/jzon/examples/deserialize.zig) | body permintaan menjadi nilai bertipe di atas arena, setiap strategy baca, reset di antara body |
| [strings](src/jzon/examples/strings.zig) | `.COPY` berhadapan dengan `.BORROW`, dan apa yang diminta borrow terhadap masa hidup dokumennya |
| [unknown_keys](src/jzon/examples/unknown_keys.zig) | `.REJECT` berhadapan dengan `.SKIP` pada dokumen yang membawa lebih dari yang dideklarasikan tipenya |
| [bench_serialize](src/jzon/examples/bench_serialize.zig) | biaya setiap strategy tulis per render, dibanding laju default |
| [bench_deserialize](src/jzon/examples/bench_deserialize.zig) | biaya setiap strategy baca per parse, pada dokumen minified dan dokumen yang ditata rapi |

Dua contoh bench ini butuh `-Doptimize=ReleaseFast`. Build Debug mengukur safety check, bukan jalurnya, dan barisnya jadi saling menempel.

Contoh kelima berupa server, jadi ia tinggal bersama contoh engine, bukan di dalam package, dan dibangun dari root repo dengan `zig build example-http1_jzon`.

| Contoh | Yang ditunjukkan |
| :- | :- |
| [http1_jzon](examples/http1_jzon.zig) | route HTTP/1.1 yang membaca body JSON menjadi record di atas arena per-permintaan lalu menjawab dengan record yang dirender ke buffer stack, tanpa alokasi apa pun di jalur respons |

| Dokumen | Deskripsi |
| :- | :- |
| [`docs/jzon/README-id.md`](docs/jzon/README-id.md) | jzon: import, mulai cepat dua arah, strategy, options, cakupan tipe, error, testing |
| [`docs/jzon/hld-id.md`](docs/jzon/hld-id.md) | jzon: layer, komponen, alur tulis dan alur baca, model alokasi, model error |
| [`docs/jzon/lld-id.md`](docs/jzon/lld-id.md) | jzon: cursor, aturan escape, vector scan, jalur angka, pembukuan field, perbedaan dari jalur default |
| [`docs/jzon/benchmark-id.md`](docs/jzon/benchmark-id.md) | jzon: biaya tiap jalur per render dan per parse, dengan metode dan sistem tempat diukurnya |

**Kapan digunakan:** pakai `.{}` lebih dulu, itu jalur berbasis std dan menerima setiap bentuk yang diterima std. Pindahkan handler yang panas ke `.GENERATED` ketika bentuknya record biasa dan parse atau render-nya ada di jalur permintaan, lalu tambahkan `.strings = .BORROW` ketika nilainya mati bersama buffer tempat ia dibaca.

<br>

## Driver

Driver database dan metrics, ditulis murni dengan Zig di atas standard library seperti para engine. Masing-masing tinggal di `src/driver/<name>/` dengan build, contoh, dan suite test berbasis container miliknya sendiri, dan bisa init dari string URL atau struct config.

| Driver | Keterangan |
| :- | :- |
| [`postgrez`](docs/driver/postgrez/README-id.md) | PostgreSQL: prepared statement, pipelining, COPY, LISTEN dan NOTIFY, pool, executor, TLS 1.3 |
| [`rediz`](docs/driver/rediz/README-id.md) | Redis: RESP3 dengan fallback RESP2 di tempat, pipelining, deferred write-behind, pool, TLS 1.3 |
| [`prometheuz`](docs/driver/prometheuz/README-id.md) | Prometheus: scrape, remote write, query PromQL instant dan range |

Setiap README yang ditaut mencakup instalasi, mulai cepat, kedua gaya init, dan menunjuk ke dokumen hld, lld, dan config miliknya.

<br>

## zixer

`zixer` adalah proxy gateway yang dikirim bersama para engine. Ia program yang kamu jalankan, bukan library yang kamu link: tiap perilaku datang dari file config teks biasa, jadi sebuah service bisa ditaruh di belakangnya tanpa satu baris kode. Satu daemon memegang semua site, dan satu site adalah satu file yang menyebut engine, port, dan ke mana trafiknya pergi.

```
engine: http1
ip: 0.0.0.0
port: 443
tls: true
tls_cert: /etc/letsencrypt/live/example.com/fullchain.pem
tls_key: /etc/letsencrypt/live/example.com/privkey.pem
upstreams: 127.0.0.1:3000
```

```bash
zig build zixer            # membangun zig-out/bin/zixer-<arch>-<os>-<optimize>
zixer init                 # membuat kerangka root dir: main.cfg, sites/, logs/
zixer status               # memvalidasi tiap config, keluar 1 bila ada fault
zixer start example.cfg    # men-spawn daemon bila belum ada yang berjalan
zixer restart example.cfg  # membaca ulang satu file site, yang dipanggil deploy hook certbot
zixer daemon stop          # melepas tiap site lalu keluar
```

Key `engine` memilih edge, dan tiap engine kecuali `udp` melakukan re-origination pada request alih-alih meneruskannya byte per byte:

| Engine | Sisi client | Leg upstream |
| :- | :- | :- |
| http1 | HTTP/1.1, TLS opsional, upgrade websocket, SSE, file static | HTTP/1.1, keep-alive |
| http2 | h2 dengan sniff prior knowledge, websocket rfc 8441 | HTTP/1.1 per stream |
| grpc | h2 saja | h2, supaya trailer selamat melewati hop |
| http3 | QUIC dan HTTP/3, TLS selalu | HTTP/1.1 |
| udp | datagram mentah, satu flow per client | datagram mentah |

| Dokumen | Keterangan |
| :- | :- |
| [`docs/zixer/README-id.md`](docs/zixer/README-id.md) | zixer: build, mulai cepat, root dir, perintah, key site, apa yang dilakukan tiap engine di edge |
| [`docs/zixer/how-to-use-id.md`](docs/zixer/how-to-use-id.md) | zixer: build, site pertama, satu resep per bentuk, renewal certbot, penelusuran masalah |
| [`docs/zixer/config-id.md`](docs/zixer/config-id.md) | Rujukan config zixer: tiap key main.cfg dan site, default, aturan lintas field, teks fault |
| [`docs/zixer/hld-id.md`](docs/zixer/hld-id.md) | zixer: process model, komponen, siklus hidup site, engine, concurrency model, TLS dan ACME |
| [`docs/zixer/lld-id.md`](docs/zixer/lld-id.md) | zixer: grammar config, wire control, aturan registry, internal per edge, batas tetap |

Demo yang bisa dijalankan untuk tiap bentuk ada di [`examples/proxies/`](examples/proxies/README-id.md), masing-masing satu upstream plus satu config site, dan `zig build zixer-test-runner-all` menjalankan ke-15-nya, masing-masing di root sementara sendiri dan child process sendiri yang dibatasi waktu.

**Kapan digunakan:** taruh di depan service yang sudah kamu jalankan saat kamu ingin terminasi TLS, file static, upstream round-robin, atau perubahan protocol di edge, dan kamu ingin itu dijelaskan di sebuah file alih-alih ditulis sebagai kode. Pakai engine-nya langsung bila perilakunya memang milik program kamu sendiri.

<br>

## Rangkuman

```
Sebuah surgical backend library & engine dengan wiring tools.
Yang akan memberikan Anda kinerja, efisiensi, dan transparansi.
```

<br>

## AI Policies

- __*Anda dapat menggunakannya sebagai alat internal.*__
- __*Issue & Pull Request harus dibuat atas nama Anda.*__
- __*Keputusan dan penilaian akhir berada di tangan kami (Anda dan para maintainer).*__

<br>

---

###### end of readme
