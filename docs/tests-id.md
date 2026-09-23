# Pengujian: zix

---

## Cara Menjalankan

```sh
# hanya pengujian unit (tidak ada output saat berhasil)
zig build unit-test

# pengujian integrasi: komponen dihubungkan, tanpa server aktif
zig build integration-test

# pengujian perilaku: kontrak API yang dapat diamati
zig build behaviour-test

# pengujian edge: kondisi batas dan jalur error
zig build edge-test

# semua langkah di atas sekaligus
zig build test-all
```

`zig build` saja **tidak** menjalankan pengujian: langkah pengujian adalah langkah bernama tersendiri yang tidak terhubung ke langkah install default.

Perilaku platform: dengan `-Dtarget` foreign, setiap suite ter-compile untuk target itu dan eksekusi dilewati dengan warning. Di host non-Linux, tes yang menguji jalur EPOLL / URING (Linux-only) mencetak warn lalu skip, dan tes yang berpijak pada syscall Linux-only skip tanpa pesan. Langkah `test-runner-*` berperilaku sama: target foreign meng-compile runner beserta server-nya lalu lolos, dan di host non-Linux setiap skenario EPOLL / URING melaporkan baris PASS dengan warn alih-alih berjalan.

---

## Pengujian Unit

Sumber: `src/lib.zig`. Setiap modul diuji melalui `std.testing.refAllDecls`, yang memverifikasi bahwa setiap deklarasi publik berhasil dikompilasi dan setiap blok `test` inline lolos.

### zix.Tcp (raw)

| Modul | Cakupan |
| :- | :- |
| `tcp/config.zig` | `refAllDecls` + perilaku: default `TcpServerConfig` (kernel_backlog=4096, max_recv_buf=4096, workers=0) dengan dispatch_model wajib (disetel eksplisit), nilai backing `DispatchModel` gapless dengan hanya tiga model yang dirawat, nama POOL / MIXED yang dilepas tidak lagi resolve, default `TcpClientConfig` (max_recv_buf=4096) |
| `tcp/server.zig` | `refAllDecls` + perilaku: port nol menghasilkan `error.ZixPortNotConfigured`, konfigurasi valid berhasil dan deinit aman, konfigurasi EPOLL valid berhasil dan deinit aman |
| `tcp/client.zig` | `refAllDecls` |

### zix.Http

| Modul | Cakupan |
| :- | :- |
| `tcp/http/method.zig` | `refAllDecls` + round-trip semua code termasuk `QUERY` (RFC 10008), QUERY diselesaikan dari token wire-nya dan tidak pernah dilaporkan sebagai GET, pencocokan case-sensitive, `codeFromString` melaporkan token tak dikenal sebagai null, token melebihi `MAX_TOKEN_LEN` ditolak oleh length switch, `enumFromString` mempertahankan fallback GET |
| `tcp/http/status.zig` | `refAllDecls` |
| `tcp/http/content.zig` | `refAllDecls` + round-trip: `typeFromString` / `stringFromEnum` untuk setiap varian enum, pelepasan parameter `typeFromHeader`, nilai tidak dikenal atau kepanjangan melaporkan tidak ada kecocokan |
| `tcp/http/parser.zig` | `refAllDecls` + perilaku: input tidak lengkap menghasilkan null, offset GET minimal, pemisahan path+query, offset header, flag keep_alive, semua method, method tidak diimplementasikan melaporkan UnknownMethod (501) terpisah dari request line yang rusak (400), flag chunked aktif/nonaktif, coding list chunked, chunkedEnd lengkap/parsial/resume-watermark/terminator-di-data/trailer/pipelined/hex-tidak-valid, dechunkInPlace di buffer sendiri/pemindahan overlap/urutan chunk |
| `tcp/http/request.zig` | `refAllDecls` + perilaku: method, path, query string, queryParam (ada / tidak ada / flag), pathSegments, queryParams, pencarian header (case-insensitive), pengantaran body (Content-Length dan chunked yang tiba tersegmen di fd non-blocking, body jauh lebih besar dari read buffer, short read dilaporkan saat peer menutup lebih awal) |
| `tcp/http/response.zig` | `refAllDecls` + perilaku: setStatus, setContentType, setKeepAlive, addHeader, `HeaderSize.value()`, penjaga injeksi (CR/LF), TooManyHeaders, format wire `SseWriter`, default `Response.streaming` |
| `tcp/http/router.zig` | `refAllDecls` + perilaku: matchParam, registrasi route (kind + path tersimpan) |
| `tcp/http/static.zig` | `refAllDecls` + perilaku: mimeType, parseRangeHeader |
| `tcp/http/websocket.zig` | `refAllDecls` + perilaku: vektor RFC acceptKey, round-trip buildFrame + parseFrame, frame bermasker |
| `tcp/http/context.zig` | `refAllDecls` + perilaku: `timedOut` dengan deadline null menghasilkan false, `isExpired` dengan deadline null menghasilkan false |
| `tcp/http/server.zig` | `refAllDecls` + perilaku: siklus hidup alloc / free slab `EpollConnTable`, akuntansi filled-bytes, fd di luar jangkauan menghasilkan null, `getAvailableCpuCount` menghasilkan minimal 1, `effectiveCacheEntries` menghormati plafon memori, EPOLL `processRequest` melayani cache miss lalu hit, hasil body `processRequest` (bodyComplete true untuk body Content-Length atau chunked yang terbaca penuh dan false saat handler tidak pernah membaca, 413 untuk body yang dideklarasikan atau chunked melewati limit, 100 Continue dikirim untuk Expect ber-body dan dilewati tanpanya, tutup saat body biasa atau chunked coding-list tidak dibaca atau peer berhenti lebih awal, body chunked yang tiba setelah head tetap diantar) |

### zix.Http1

| Modul | Cakupan |
| :- | :- |
| `tcp/http1/method.zig` | `refAllDecls` + round-trip semua code termasuk `QUERY` (RFC 10008), QUERY diselesaikan dari token wire-nya dan tidak pernah dilaporkan sebagai GET, pencocokan case-sensitive, `codeFromString` melaporkan token tak dikenal sebagai null, token melebihi `MAX_TOKEN_LEN` ditolak oleh length switch, `enumFromString` mempertahankan fallback GET |
| `tcp/http1/content.zig` | `refAllDecls` + round-trip: `typeFromString` / `stringFromEnum` untuk setiap varian enum, query type RFC 10008 diselesaikan dari string-nya, media type terpanjang 33 byte muat di buffer huruf kecil, nilai melebihi `MAX_TYPE_LEN` melaporkan tidak ada kecocokan alih-alih panic, `typeFromHeader` melepas parameter dan tetap case-insensitive |
| `tcp/http1/core.zig` | `refAllDecls` + perilaku: parseHead (field GET, pemisahan query dari path, POST Content-Length, default keep_alive HTTP/1.0 + override Connection, Expect 100-continue), getHeader case-insensitive, queryParam, parseRange, percentDecode, buildSimpleHeaderInto, sendSimpleFD ke RespSink aktif tanpa bounce buffer, cache no-op / store-lalu-hit / pemisahan key per path dan query, walk chunkedFrame (minta lebih di tengah body, panjang terminator, malformed vs too-large vs belum selesai, data yang mengeja terminator, berhenti di request pipelined), decodeChunkedInBuf (decode di tempat, source tak tersentuh selama belum selesai), jalur body ASYNC serveConn (pengantaran body muat dan over-large dengan pelaporan bodyReceived / bodyComplete, awal body dan bukan sisa drain, drain menjaga request pipelined, 413 dideklarasikan dan chunked melewati buffer, 400 chunked malformed, 100 Continue, chunked tiba setelah head, request pipelined di belakang body chunked) |
| `tcp/http1/request.zig` | `refAllDecls` + perilaku: body mengembalikan slice yang diantar engine, bodyReceived default ke panjang slice dan menerima override engine, bodyComplete default true dan menerima override engine, fromRaw mem-parse buffer mentah dengan body |
| `tcp/http1/server.zig` | `refAllDecls` + perilaku: validasi config (ASYNC / EPOLL / URING), serveEpollConn menjawab burst pipelined secara berurutan, cache EPOLL miss-lalu-hit + plafon memori effectiveCacheEntries, siklus hidup slab ConnTable + sizing ws_recv_buf, serveEpollWs men-drain ke EAGAIN, parseGetFastPath (GET / query / menolak POST dan HTTP/1.0 / raw headers), initUringRing menghasilkan ring yang dapat dipakai |
| `tcp/http1/dispatch/epoll.zig` (Linux) | perilaku jalur body: drain-lalu-sajikan melaporkan total terhitung, drain tepat menjaga request pipelined tetap utuh, peer yang berhenti di tengah drain tidak pernah dilayani, body yang muat menunggu hitungan penuh, 413 untuk body yang dideklarasikan melewati limit dan body chunked melewati body buffer, 400 pada chunked malformed, satu 100 Continue selagi body masih berdatangan |
| `tcp/http1/dispatch/uring.zig` (Linux) | perilaku jalur body: body chunked yang hadir penuh ter-decode, body oversized ditunda dan disajikan dengan total terhitung, request yang ditunda tetap parkir selama drain-nya belum selesai, body yang muat menunggu hitungan penuh, 413 dideklarasikan dan chunked, 400 chunked malformed, 100 Continue selagi body masih berdatangan |
| `tcp/http1/websocket.zig` | `refAllDecls` + perilaku: acceptKey vektor RFC 6455, round-trip buildFrame/parseFrame, SIMD unmask cocok dengan scalar (dan tail bytes), prefix buildHeader, pump echo lewat socketpair, pumpRing stage lalu melaporkan close, broadcast fan-out (+ skip fd mati, list kosong) |
| `tcp/http1/router.zig` | `refAllDecls` + perilaku: matchParam, router comptime |
| `tcp/http1/config.zig` | `refAllDecls` (nilai default diuji oleh `tests/behaviour/http1/config_test.zig`) |

### zix.Udp

| Modul | Cakupan |
| :- | :- |
| `udp/config.zig` | `refAllDecls` + default: `UdpServerConfig`, `UdpClientConfig`, default `allow_args`, dan nilai backing enum `Endianness` |
| `udp/packet.zig` | `refAllDecls` + perilaku: NATIVE tanpa operasi, array u8 tidak ditukar, round-trip LITTLE/BIG, non-native menukar elemen integer dan float array, semua varian `FeedbackResult` |
| `udp/server.zig` | `refAllDecls` + perilaku: port nol menghasilkan `error.ZixPortNotConfigured`, port bukan-nol berhasil, field konfigurasi tersimpan |
| `udp/client.zig` | `refAllDecls` |

### zix.Uds

| Modul | Cakupan |
| :- | :- |
| `uds/config.zig` | `refAllDecls` + default: `UdsServerConfig` (kernel_backlog=128, max_recv_buf=4096), `UdsClientConfig` |
| `uds/server.zig` | `refAllDecls` + perilaku: path kosong menghasilkan `error.ZixPathEmpty`, path valid berhasil dan deinit aman |
| `uds/client.zig` | `refAllDecls` |

### zix.Http.Client

| Modul | Cakupan |
| :- | :- |
| `tcp/http/client_config.zig` | `refAllDecls` + default: `HttpClientConfig` (connect_timeout_ms=0, response_timeout_ms=0, read_timeout_ms=0, max_response_body=4MB, follow_redirects=true, max_redirects=3, h2_max_read_rounds=4096, user_agent=`zon_options.user_agent`, version=HTTP_1, tls_verify=true, tls_ca_path=null) |
| `tcp/http/client.zig` | `refAllDecls` + perilaku: `.HTTP_2` pada URL non-https ditolak sebelum connect, `.HTTP_3` menghasilkan `UnsupportedVersion`, server yang tidak pernah menjawab menghasilkan `ResponseTimeout`, reply lengkap tidak terpotong oleh bound idle, body yang diam di tengah transfer menghasilkan `ReadTimeout` |
| `tcp/http/h2_client.zig` | `refAllDecls` + perilaku: `methodHasBody` + `skipRequestHeader`, `putFrame` round-trip melalui parser frame, `putWindowUpdate` meng-encode increment big-endian, `headerBlock` melepas prefix PADDED dan PRIORITY, `dataPayload` melepas padding DATA, peer yang menerima koneksi lalu tidak pernah bicara menghasilkan `ResponseTimeout` |
| `tcp/http/sse_client.zig` | `refAllDecls` + perilaku: `splitField` (data / event / retry / nama field telanjang / nama tidak cocok / tanpa spasi depan dipertahankan), `parseHttpUrl` (dasar, port default 80, https menghasilkan `TlsNotSupported`), server yang tidak pernah menjawab menghasilkan `ResponseTimeout`, stream yang diam menghasilkan `ReadTimeout` (bukan close bersih) |
| `tcp/http/ws_client.zig` | `refAllDecls` + perilaku: vektor acceptKey RFC 6455, `parseWsUrl` (dasar, tanpa path default ke /, port default 80, wss menghasilkan `TlsNotSupported`, non-ws menghasilkan `InvalidUrl`), server yang tidak pernah menjawab menghasilkan `ResponseTimeout`, peer yang tidak mengirim frame menghasilkan `ReadTimeout` |

### zix.Channel

| Modul | Cakupan |
| :- | :- |
| `channel/channel.zig` | `refAllDecls` + perilaku: kapasitas dan jumlah init `Channel(u32)`, aritmetika tail ring buffer |

### zix.Fix

| Modul | Cakupan |
| :- | :- |
| `tcp/fix/config.zig` | `refAllDecls` + perilaku: field wajib `FixServerConfig` (ip, port, comp_id), dispatch_model wajib (disetel eksplisit), workers default 0, kernel_backlog default 1024, heartbeat_timeout_ms default 0, field wajib `FixClientConfig` (ip, port, comp_id, target_comp_id) |
| `tcp/fix/core.zig` | `refAllDecls` + perilaku: round-trip `parseFields`, pencarian `getField` dan kasus null, vektor `computeChecksum` yang diketahui, `verifyChecksum` valid/terpotong/salah, `findMessageEnd` lengkap/parsial/tanpa-terminator, `buildMessage` menghasilkan checksum valid |
| `tcp/fix/server.zig` | `refAllDecls` + perilaku: port nol menghasilkan `error.ZixPortNotConfigured`, konfigurasi valid berhasil, deinit aman |
| `tcp/fix/client.zig` | `refAllDecls` + perilaku: `FixClient.connect` port nol menghasilkan `error.ZixPortNotConfigured` |
| `tcp/fix/router.zig` | `refAllDecls` + perilaku: dispatch memanggil handler yang cocok, tanpa kecocokan handler tidak dipanggil, timeout route menyetel `deadline_ns` |

### zix.Http2

| Modul | Cakupan |
| :- | :- |
| `tcp/http2/frame.zig` | `refAllDecls` + perilaku: `FRAME_TYPE_HEADERS=0x01`, `FLAG_END_STREAM=0x01`, `ERR_NO_ERROR=0`, round-trip `writeFrameHeader`/`readFrameHeader` melalui pipe, PREFACE dimulai dengan `PRI`, `sendSettings` menulis frame SETTINGS 9-byte valid melalui pipe |
| `tcp/http2/hpack.zig` | `refAllDecls` + perilaku: round-trip encode/decode Huffman, `HpackEncoder.writeHeader` menghasilkan entri terindeks dari static table, `HpackDecoder.decode` mendekode `:method GET` terindeks, eviksi dynamic table menghormati max_size, indeks `HPACK_STATIC` ke-8 adalah `:status 200` |
| `tcp/http2/core.zig` | `refAllDecls` + perilaku: default struct `ServeOpts`, `HandlerFn` adalah tipe function pointer |
| `tcp/http2/config.zig` | `refAllDecls` + perilaku: field wajib `Http2ServerConfig` berhasil dikompilasi, dispatch_model wajib (disetel eksplisit), workers default 0, max_streams=128 dan max_frame_size=16384 |
| `tcp/http2/server.zig` | `refAllDecls` + perilaku: port nol menghasilkan `error.ZixPortNotConfigured`, konfigurasi valid berhasil dan deinit aman |
| `tcp/http2/static.zig` | `refAllDecls` + perilaku: zero copy ditolak untuk batch coalescing dan fd sentinel, file dibingkai sebagai HEADERS plus DATA dengan END_STREAM, traversal / file hilang / path kepanjangan ditolak, body melebihi max frame size dipotong, file kosong menutup stream di HEADERS, sibling brotli dipilih dari cache |

### zix.Grpc

| Modul | Cakupan |
| :- | :- |
| `tcp/http2/grpc/status.zig` | `refAllDecls` + perilaku: OK=0, CANCELLED=1, UNIMPLEMENTED=12, UNAUTHENTICATED=16 |
| `tcp/http2/grpc/frame.zig` | `refAllDecls` + perilaku: round-trip `readGrpcPrefix` / `writeGrpcPrefix`, flag compress tersimpan, panjang pesan tersimpan, `sendGrpcError` menyertakan header `content-type` |
| `tcp/http2/grpc/proto.zig` | `refAllDecls` + perilaku: round-trip `encodeVarint` / `decodeVarint`, `encodeString` menghasilkan wire type LEN, `encodeInt32` menghasilkan wire type VARINT, round-trip `encodeDouble` / `decodeDouble` (nilai positif dan negatif), `MessageReader` mengiterasi semua field |
| `tcp/http2/grpc/timeout.zig` | `refAllDecls` + perilaku: satuan H/M/S/m/u/n dikonversi dengan benar, karakter tunggal menghasilkan null, kosong menghasilkan null |
| `tcp/http2/grpc/core.zig` | `refAllDecls` + perilaku: `parsePath` input valid dan tidak valid, `detectContentType` proto/json/tidak diketahui, `GrpcContext.recvMessage` body kosong menghasilkan null, `Route.timeout_ms` default nol, `GrpcContext.isExpired` deadline null/lampau/mendatang, `GrpcServeOpts.handler_timeout_ms` default nol, Router mendispatch ke handler yang cocok |
| `tcp/http2/grpc/config.zig` | `refAllDecls` + perilaku: field wajib dan default `GrpcServerConfig` (handler_timeout_ms=0), field wajib `GrpcClientConfig` |
| `tcp/http2/grpc/server.zig` | `refAllDecls` + perilaku: port nol menghasilkan `error.ZixPortNotConfigured`, konfigurasi valid berhasil, deinit aman |
| `tcp/http2/grpc/client.zig` | `refAllDecls` + perilaku: `GrpcClient.connect` port nol menghasilkan `error.ZixPortNotConfigured` |

### zix.Http3

Layer HTTP/3 (QUIC) adalah pure-Zig dari RFC, jadi tiap modul membawa worked example dari spec-nya sendiri sebagai test in-file. `zix.Http3` juga mengekspor ini sebagai primitive (mengikuti `zix.Http2`), dan round trip live digerakkan oleh client native yang hand-rolled dari primitive itu di `test-runner-http3` / `test-runner-all`.

| Modul | Cakupan |
| :- | :- |
| `udp/http3/crypto.zig` | `refAllDecls` + perilaku: Initial secret / key AES-128-GCM dari connection id cocok dengan worked example RFC 9001 Appendix A.1, helper AEAD nonce dan header-mask |
| `udp/http3/protection.zig` | `refAllDecls` + perilaku: round-trip seal-lalu-open untuk packet Initial / Handshake / 1-RTT, header protection diterapkan dan dilepas, satu byte yang di-flip gagal AEAD |
| `udp/http3/keyschedule.zig` | `refAllDecls` + perilaku: handshake key dari ECDHE + transcript, application key 1-RTT dari handshake secret + transcript sampai Finished |
| `udp/http3/qpack.zig` | `refAllDecls` + perilaku: encode / decode prefixed-integer, indexed field line, literal-with-name-reference, entri static table |
| `udp/http3/huffman.zig` | `refAllDecls` + perilaku: decode vector `www.example.com` RFC 7541 Appendix C.4 dan sebuah request path dengan digit dan simbol |
| `udp/http3/varint.zig` / `packet.zig` / `frame.zig` | `refAllDecls` + perilaku: round-trip read / write varint, parse long / short header, parse frame CRYPTO dan STREAM |
| `udp/http3/request.zig` / `response.zig` | `refAllDecls` + perilaku: `parseRequest` memulihkan `:method` / `:path` melewati ACK di depan, `streamBytes` menjumlah byte payload stream lintas stream dan melewati frame non-stream, `buildResponse` membawa control SETTINGS plus balasan HEADERS / DATA dan menumpangkan grant MAX_STREAMS / MAX_DATA yang jatuh tempo (encode `buildMaxStreams` / `buildMaxData`) |
| `udp/http3/connection.zig` | `refAllDecls` + perilaku: `init` menurunkan Initial key dari connection id (RFC 9001 A.1), cap anti-amplification 3x, `sendDatagramSize` meng-clamp ke config / client / ceiling, `replenishBidiStreams` dan `replenishMaxData` menaikkan grant melewati allowance sekali-pakai, batas pool `reserveSendStream`, pelacakan lubang `AckTracker`, sampling RTT `onAckFrame` |
| `udp/http3/router.zig` | `refAllDecls` + perilaku: dispatch memanggil handler yang cocok, query di-strip sebelum matching, tidak ada match mengembalikan 404 |
| `udp/http3/config.zig` / `server.zig` | `refAllDecls` + perilaku: field config wajib dan default, `Tls.Context` null ditolak saat run |
| `udp/http3/static.zig` | `refAllDecls` + perilaku: content-encoding hanya memetakan yang bisa dikirim jalur respons, serve menolak ketika caching mati (body harus hidup lebih lama dari handler, jadi hanya bisa dari cache), respons diisi dari byte cache dan pin DITAHAN, body tetap terbaca setelah frame handler hilang, sibling `.br` dipilih dan dinamai, traversal dan file hilang ditolak, tepat satu pin ditahan dan `releasePin` mengembalikannya, pin yang dilepas membuat entry bisa di-reclaim, body in-flight kebal terhadap file yang ditulis ulang di tempat |

### zix.Webtransport

WebTransport over HTTP/3 adalah fitur `zix.Http3` (`Http3ServerConfig.webtransport`), jadi modul-modul binding ini pure-Zig dari draft-nya sendiri: masing-masing membawa codepoint, layout RFC, dan byte stream yang dibuat khusus sebagai test in-file. Round trip live digerakkan end to end oleh client native yang hand-rolled dari primitive HTTP/3 di `test-runner-webtransport` / `test-runner-all`.

| Modul | Cakupan |
| :- | :- |
| `udp/http3/webtransport/draft.zig` | `refAllDecls` + perilaku: kedua upgrade token memilih dialect-nya dan token tak dikenal tidak memilih keduanya, codepoint draft-16 terhadap registrasi IANA (setting, stream type dan signal value, error code, capsule type), pasangan draft-07 deployed yang masih diterima, pemetaan application error di kedua ujung rentang dan melalui sapuan menyeluruh bahwa tidak ada nilai hasil encode yang merupakan codepoint grease terreservasi, codepoint terreservasi di dalam rentang yang tidak membawa application error, dan klasifikasi capsule flow control |
| `udp/http3/webtransport/capsule.zig` | `refAllDecls` + perilaku: framing capsule RFC 9297 3.2, application code dan message pada capsule close dengan pemotongan di batas karakter UTF-8, capsule flow control yang mengencode dan mendekode satu varint, reader streaming yang menyerahkan capsule yang terbelah antar datagram, melewati capsule tak dikenal tanpa membuffernya, melewati capsule dikenal yang kebesaran, capsule yang ditolak menghentikan reader, dan panjang deklarasi raksasa yang mengonsumsi persis yang dideklarasikannya sambil membuffer nol |
| `udp/http3/webtransport/datagram.zig` | `refAllDecls` + perilaku: bentuk frame RFC 9221 4 (kedua tipe, datagram kosong, panjang melewati buffer, header terpotong), ukuran frame terencode yang dihitung limit peer, limit yang membatasi setiap pengiriman, quarter stream id RFC 9297 2.1 yang membawa session, HTTP/3 datagram yang round trip melewatinya, dan anggaran payload yang mengurangi kedua lapisan overhead framing |
| `udp/http3/webtransport/stream_header.zig` | `refAllDecls` + perilaku: layout 0x54 / 0x41 untuk kedua kind dengan session id satu dan dua byte, stream yang dibuka dengan protokol lain ditolak, aturan session id untuk stream bidirectional yang diinisiasi client, reliable reset size yang mencakup header, dan ruang stream id tempat stream data bisa hidup |
| `udp/http3/webtransport/session.zig` | `refAllDecls` + perilaku: send buffer mengambil sebanyak yang bisa dan melaporkan back pressure, stream panjang memakai ulang satu buffer di seluruh pengakuan, loss yang memundurkan offset terkirim tanpa mengganggu antrean, reset yang selalu mencakup header stream, receive side yang mengisi ulang kredit sebelum kering, flow control yang hanya aktif ketika kedua endpoint mendeklarasikan, limit data session yang ditegakkan dan ditagih, jumlah stream masuk yang dibatasi per kind, membuka stream yang menghormati limit peer, aturan monotonik untuk `WT_MAX_DATA` dan `WT_MAX_STREAMS`, endpoint yang menaikkan limitnya sendiri saat peer menghabiskannya, session yang berakhir dengan informasi close peer, stream yang attach dan detach, dan session id yang merupakan stream id CONNECT-nya |
| `udp/http3/webtransport/pool.zig` | `refAllDecls` + perilaku: slot dibagikan, ditolak melewati kapasitas, dan didaur ulang; setiap slot stream membawa send buffer-nya sendiri; tabel orphan menahan himpunan terbatas stream pra-session; stream yang dibuffer diputar ulang hanya ke session-nya; buffer konfigurasi yang sangat kecil dinaikkan ke ukuran yang bisa menahan header stream; dan pool kosong yang menolak setiap akuisisi |
| `udp/http3/webtransport/Webtransport.zig` | `refAllDecls` + perilaku: config default yang tidak menawarkan apa pun sampai diaktifkan, config yang melewati tabel koneksi ditolak dengan nama field yang melewatinya, sizing pool yang mengikuti limit yang diiklankan, dan kosakata stream kind serta dialect yang dilihat aplikasi |

### zix.Webrtc

Setiap lapis WebRTC ditulis dari RFC-nya sendiri, jadi setiap berkas membawa test-nya di dalam
berkas dan lapis yang punya vector terbit dipatok byte demi byte terhadapnya. `zix.Webrtc` juga
mengekspor lapisnya sebagai primitif, sehingga peer atau harness test bisa membangun sisi seberang.

| Modul | Cakupan |
| :- | :- |
| `udp/webrtc/demux.zig` | `refAllDecls` + perilaku: setiap byte pertama dirutekan ke kind RFC 7983 bagian 7 miliknya, termasuk rentang yang belum ada di teks RFC 5764 |
| `udp/webrtc/stun/message.zig` | `refAllDecls` + perilaku: vector XOR-MAPPED-ADDRESS `192.0.2.1:32853` byte demi byte, framing ketat (byte sisa dan attribute terakhir tanpa padding ditolak), MESSAGE-INTEGRITY di atas panjang header yang ditulis ulang |
| `udp/webrtc/stun/binding.zig` | `refAllDecls` + perilaku: aturan request RFC 8489 bagian 6.3.1, silent discard dan buffer terlalu kecil sama-sama melaporkan null |
| `udp/webrtc/ice/*.zig` | `refAllDecls` + perilaku: sample request RFC 5769 bagian 2.1 memaku MAC, CRC dan dua tipe atribut sekaligus, pemisahan USERNAME dengan ufrag agent ini di depan, 487 untuk setiap tiebreaker, 400 dan 401 tanpa tanda tangan berbanding 420 dan 487 yang ditandatangani |
| `udp/webrtc/sctp/*.zig` | `refAllDecls` + perilaku di 20 berkas: CRC32c ditulis little endian dengan polinomial Castagnoli, gap ack block sebagai offset, missing report hanya dihitung di bawah TSN tertinggi yang baru di-ack, handshake 4 arah penuh plus data, heartbeat, shutdown dan abort antara dua association di memori |
| `udp/webrtc/datachannel/*.zig` | `refAllDecls` + perilaku: tujuh payload type, round-trip DCEP OPEN dan ACK, paritas stream identifier menurut role DTLS, pesan dilaporkan mendahului penutupan, pemrosesan reset yang ditunda, dua peer bicara di memori |
| `udp/webrtc/sdp/*.zig` | `refAllDecls` + perilaku di 18 berkas: CRLF dan LF telanjang sama-sama terbaca, pencarian media section mendahului level session, `a=sctp-port` yang hilang ditolak, session id dibatasi 62 bit, dan candidate ditulis di setiap media section yang dibawa |
| `udp/webrtc/media/*.zig` | `refAllDecls` + perilaku: RFC 3711 B.2 dan B.3 serta RFC 2202 kasus 1 dipatok byte demi byte, label KDF di-XOR pada byte 7, satu profile membawa dua panjang tag, estimate ROC dipisah dari accept, index SRTCP berhenti alih-alih berputar |
| `udp/webrtc/dispatch/*.zig` | `refAllDecls` + perilaku: `pass()` tiap model menjalankan sesi utuh terhadap socket sungguhan yang di-bind dengan `Dialer` sungguhan, sehingga perbedaan antar model adalah perbedaan pada loop |
| `udp/webrtc/config.zig` / `server.zig` | `refAllDecls` + perilaku: setiap penolakan `run()` berurutan (port, credential ICE ada, credential ICE sah, TLS ada, kunci ECDSA P-256, dispatch model terhadap platform) |
| `tls/dtls_*.zig` | `refAllDecls` + perilaku: anti-replay diperiksa sebelum AEAD dan diperbarui sesudahnya, perakitan ulang dilacak bitmap sehingga fragment tumpang tindih tetap sah, record sequence dibawa melewati HelloVerifyRequest, ekspor RFC 5705 dalam bentuk seed tanpa context |

### zix.Logger

| Modul | Cakupan |
| :- | :- |
| `logger/logger.zig` | `refAllDecls` + perilaku: init dan deinit tanpa save_path, system() di bawah save_min_level tidak menghasilkan output, access() di bawah save_min_level tidak menghasilkan output, pemetaan statusLevel (100=DEBUG 200=INFO 301=INFO 404=WARN 500=ERROR), conn/packet/frame/session/rpc di bawah save_min_level tidak menghasilkan output |

### zix.Utils

| Modul | Cakupan |
| :- | :- |
| `utils/file.zig` | `refAllDecls` + perilaku: extension, save |
| `utils/multipart.zig` | `refAllDecls` + perilaku: `Parser` parse + getField |
| `utils/media_type.zig` | `refAllDecls` + perilaku: `stripParameters` melepas parameter charset, membiarkan nilai polos apa adanya, memangkas spasi sebelum parameter, menjaga boundary multipart keluar dari hasil, menangani lebih dari satu parameter, menghasilkan kosong untuk nilai kosong atau titik koma tunggal. `equalIgnoreParameters` mengabaikan case, menolak subtype berbeda, dan menolak prefix yang bukan keseluruhan type |
| `utils/response_cache.zig` | `refAllDecls` + perilaku: store-lalu-lookup mengembalikan byte identik, miss pada key yang tidak ada, entry kedaluwarsa refetch, value oversize melewati store, ttl 0 tidak pernah fresh, key berbeda hidup berdampingan via probing, `max_entries` dibulatkan turun ke power of two, `hashKey` memisahkan berdasarkan query |
| `utils/static_cache.zig` | `refAllDecls` + perilaku: penggabungan path menolak traversal / absolut / kepanjangan, header membawa `Vary` dan hanya menyebut encoding bila terkompresi, jumlah entry di-clamp dan dibulatkan ke power of two, request kedua memakai file terbuka yang sama, miss tidak menyimpan apa pun, ttl 0 tidak pernah menyentuh tabel, sibling `.br` / `.gz` diambil dan dinegosiasi, file tanpa sibling menyajikan identity, entry kedaluwarsa di-reclaim dan dibuka ulang, slot yang di-pin selamat dari reclaim, tabel penuh turun ke null, sweep membebaskan ruang, `install` process-wide dan `shutdown` membersihkannya |
| `utils/dispatch_support.zig` | `refAllDecls` + perilaku: `.ASYNC` didukung di semua platform, dukungan `.EPOLL` / `.URING` mengikuti os tag target, `rejectedName` melaporkan tag model, `Error` membawa satu error penolakan kanonik |
| `utils/static_send.zig` | `refAllDecls` + perilaku: jalur copy menulis seluruh body lewat fungsi tulis engine, menghormati offset dan panjang parsial, range nol-panjang tidak pernah menyentuh socket, body lebih besar dari buffer copy melakukan loop, kegagalan tulis engine muncul sebagai BrokenPipe. Khusus Linux: jalur zero-copy mengirim byte persis lewat socket sungguhan, menghormati offset, dan melaporkan BrokenPipe saat peer tertutup |
| `utils/socket_poll.zig` | `refAllDecls` + perilaku: `readableWithin` melewati penantian saat budget nol, `waitReady` melaporkan datagram yang sudah antre di socket, `waitReady` melaporkan belum siap saat tidak ada yang datang dalam budget |
| `utils/counter_scale.zig` | `refAllDecls` + perilaku: `scaleCounter` mengonversi pembacaan di bawah satu detik penuh, tetap benar melewati titik di mana bentuk langsung overflow u64 dalam nanosecond dan lagi dalam microsecond, menjaga sisa sub-detik alih-alih memotongnya ke detik penuh, mengonversi pada frequency yang tidak membagi habis counter maupun scale, dan tetap naik saat melewati batas overflow |

### multiplexers (src/multiplexers/, internal)

| Modul | Cakupan |
| :- | :- |
| `multiplexers/ring.zig` | `refAllDecls` + perilaku: round-trip `user_data` io_uring mempertahankan `{ op, gen, fd }`, setiap varian `OpKind` (`accept` / `recv` / `send` / `timeout` / `close`) ter-decode kembali, generation maksimum tidak bocor ke field fd |

---

## Pengujian Integrasi

Sumber: `tests/integration/`. Setiap berkas adalah executable pengujian mandiri yang dikompilasi dengan modul `zix` yang diimpor. Pengujian ini menguji komponen yang dihubungkan terhadap input tiruan, tanpa socket aktif, tanpa scheduler `std.Io`.

### tests/integration/tcp/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `TcpServer.init` konfigurasi valid | init dengan ip dan port nyata berhasil, deinit aman |
| `TcpServer.init` dispatch model EPOLL | init dengan dispatch model `.EPOLL` berhasil, deinit aman |
| `TcpServer.init` port nol | menghasilkan `error.ZixPortNotConfigured` |
| Pemeriksaan tipe `HandlerFn` | `zix.Tcp.echoHandler` memenuhi `zix.Tcp.HandlerFn` |
| `TcpClient.connect` port nol | menghasilkan `error.ZixPortNotConfigured` sebelum pemanggilan socket apa pun |

### tests/integration/http/

#### `request_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `pathParam()` satu param | segmen yang ditangkap dikembalikan berdasarkan nama (nama tidak ada menghasilkan null) |
| `pathParam()` nama dengan tanda hubung | `:tenant-id`, `:tenant-branch` (pola contoh http_paths) |
| `body()` chunk tunggal chunked didekode dengan benar | `"5\r\nhello\r\n0\r\n\r\n"` -> `"hello"` |
| `body()` beberapa chunk chunked dirakit | `"3\r\nfoo\r\n4\r\nbarr\r\n0\r\n\r\n"` -> `"foobarr"` |
| `body()` body chunked kosong menghasilkan string kosong | hanya chunk terminal -> `""` |
| `body()` mengembalikan body_cache tanpa menyentuh reader | `body_cache` yang sudah diset mempersingkat pembacaan, panggilan kedua mengembalikan pointer yang sama |

#### `router_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Pencocokan tepat | `dispatch` menghasilkan true, handler yang benar dipanggil |
| Param mengisi `path_params` | `req.path_params` diset setelah dispatch param. `req.pathParam()` mengembalikan nilainya. |
| Dua path param keduanya terisi | route multi-param menangkap kedua segmen |
| Prefix mengarah ke handler | pencocokan prefix menghasilkan true dan memanggil handler |

#### `context_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Penentuan waktu `withTimeout` / `withDeadline` | anggaran 60 detik belum habis. Anggaran 10ms terlampaui setelah sleep 50ms. |

#### `header_index_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Indeks kosong menghasilkan null | tidak ada header yang diindeks (semua pencarian menghasilkan null) |
| Pencarian case-insensitive | map yang sudah diisi: `Content-Type` ditemukan melalui `content-type` |

#### `sse_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Format wire `SseWriter.writeEvent` | `"data: ping\n\n"` melalui `std.Io.Writer.fixed` buffer |
| Format wire `SseWriter.writeNamedEvent` | `"event: update\ndata: 99\n\n"` |
| Format wire `SseWriter.comment` | `": keepalive\n"` |

### tests/integration/http1/

#### `server_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| `Http1Server.init` config valid, deinit aman | init berhasil dan deinit tidak error |
| `Http1Server.init` dispatch model URING | model diterima dan disimpan |
| `Http1Server.init` dispatch model EPOLL | model diterima dan disimpan |
| `Http1Server.init` dispatch model URING | model diterima dan disimpan |

#### `router_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| Dispatch router mengarah ke handler yang cocok | path exact sampai ke handler-nya |
| Dispatch router memilih route yang benar di antara beberapa | handler yang tepat menang saat beberapa terdaftar |
| Dispatch router path tak dikenal menulis 404 | tanpa kecocokan jatuh ke 404 |

#### `tls_dual_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| Dual listener EPOLL melayani cleartext di port | kaki cleartext menjawab di `port` |
| Dual listener EPOLL melayani TLS di tls_port dengan route yang sama | kaki TLS melayani tabel route yang sama |
| Dual listener URING melayani cleartext di port | kaki cleartext menjawab di bawah ring |
| Dual listener URING melayani TLS on-ring di tls_port | kaki TLS berjalan di ring |
| Dual listener ASYNC melayani cleartext di port | kaki cleartext menjawab di model thread |
| Dual listener ASYNC melayani TLS via accept thread tambahan | kaki TLS mendapat accept thread sendiri |
| `tls_port` sama dengan `port` ditolak saat run | mengembalikan `error.ZixTlsPortConflict` |

#### `static_cache_test.zig`

Menjalankan jalur router sungguhan lewat socketpair, jadi yang diuji adalah byte yang diterima klien.

| Tes | Yang diverifikasi |
| :- | :- |
| Router menyajikan path tak cocok dari static cache | 200 dengan content type dan body yang benar |
| Router tetap 404 untuk path tak cocok tanpa file di baliknya | file yang tidak ada tetap 404 |
| Router menjaga path ber-route di depan static cache | handler ber-route menang atas file yang akan menutupinya |
| Router mengulang file yang di-cache byte demi byte antar request | header dan body yang diputar ulang identik dengan respons dingin |
| Router menyajikan file yang sama tanpa cache ketika tidak ada cache terpasang | default bawaan tetap melayani lewat jalur lama |

### tests/integration/websocket/

#### `websocket_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `parseFrame` opcode binary | round-trip FIN, opcode, payload |
| `parseFrame` ping dengan payload | opcode, konten payload |
| `parseFrame` opcode pong | opcode |
| `parseFrame` close dengan payload kosong | opcode, payload panjang nol |
| Round-trip semua opcode | buildFrame -> parseFrame untuk text, binary, ping, pong, close |
| Init / deinit `RoomMap` | tanpa koneksi (tanpa crash atau leak) |

### tests/integration/udp/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `UdpServer.init` konfigurasi valid | init dengan ip dan port nyata berhasil |
| `UdpServer.init` port nol | menghasilkan `error.ZixPortNotConfigured` |
| `UdpClient.init` bind_port nol | menghasilkan `error.ZixPortNotConfigured` sebelum pemanggilan socket apa pun |

#### `packet_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Round-trip LITTLE | `toEndian` -> `fromEndian` memulihkan byte asli |
| Round-trip BIG | sama untuk endian BIG |
| Nilai `FeedbackResult.packet` | varian `.packet` menyimpan dan mengembalikan packet lengkap |

### tests/integration/http/ (client)

#### `client_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `HttpClient.init` dan `deinit` | tanpa request: init + deinit aman dengan io Threaded |
| `ClientResponse.header()` pada byte head tiruan | pencarian berdasarkan nama dan pencarian case-insensitive |
| `ClientResponse.iterateHeaders()` | menghitung semua header dari byte head mentah |
| Default `ClientRequestOpts` | `headers` kosong, `body` null, `connect_timeout_ms` null |

### tests/integration/uds/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `UdsServer.init` path valid | berhasil dan `deinit` aman |
| Pemeriksaan tipe `HandlerFn` | `zix.Uds.echoHandler` memenuhi `zix.Uds.HandlerFn` |

### tests/integration/logger/

#### `logger_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `Logger.system()` menulis baris ke berkas | tag `[component]` dan teks pesan muncul di berkas log |
| `Logger.access()` menulis baris ke berkas | method, path, status, bytes semuanya muncul di berkas log |
| UA dan origin yang tidak ada dicatat sebagai strip | argumen `""` kosong menghasilkan `"-"` di field yang dikutip |
| UA yang ada muncul di berkas | string UA tidak kosong ditulis apa adanya |
| Status 5xx dipetakan ke level ERROR | `access()` dengan status 500 menulis label `ERROR` |
| Argumen `anyerror` diformat dengan benar | format `{}` dari nilai error menghasilkan nama error |

### tests/integration/fix/

#### `server_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `FixServer` init dan deinit tidak error | konfigurasi valid berhasil, deinit aman |
| `FixServer` init port nol | menghasilkan `error.ZixPortNotConfigured` |
| Handshake Logon dan round-trip echo berhasil | kirim Logon, terima balasan Logon dengan MsgType=A kirim NewOrderSingle, terima echo, kirim Logout, terima balasan Logout |
| Beberapa pesan berurutan semuanya di-echo | tiga pesan NewOrderSingle di-echo dengan ClOrdID tersimpan di semua |

### tests/integration/http2/

#### `server_test.zig`

Port: 18082-18085.

| Pengujian | Yang diverifikasi |
| :- | :- |
| `Http2Server.init` dan deinit tidak error | konfigurasi valid berhasil, deinit aman |
| `Http2Server.init` port nol | menghasilkan `error.ZixPortNotConfigured` |
| Tipe `Http2 HandlerFn` adalah function pointer | penugasan `zix.Http2.HandlerFn` berhasil dikompilasi |
| Http2 GET / mengembalikan Hello World melalui h2c direct | round-trip h2c preface PRI + HEADERS + DATA mengembalikan body response |
| Http2 POST /echo mengembalikan body request | POST dengan frame DATA body, server meng-echo body kembali |
| Http2 dua stream berurutan pada koneksi yang sama | stream ID 1 dan 3 masing-masing menerima response yang benar |
| Http2 h2c upgrade GET / mengembalikan Hello World | HTTP/1.1 `Upgrade: h2c` -> 101 Switching Protocols -> response h2c |

### tests/integration/http3/

#### `static_test.zig`

Membangun trio yang dibangun engine lalu memanggil `Router.dispatch`, jadi yang diuji adalah respons
yang akan dibingkai engine, termasuk pin cache yang dikembalikannya.

| Tes | Yang diverifikasi |
| :- | :- |
| Router menyajikan path tak cocok dari static cache | 200, body dan content type benar, dan `static_slot` dikembalikan masih ter-pin |
| Router 404 untuk path tak cocok tanpa file di baliknya | file yang tidak ada adalah 404 dan tidak ada pin diambil |
| Router menjaga path ber-route di depan fallback static | handler ber-route menang atas file yang akan menutupinya |
| Router 404 untuk path static ketika caching mati | file-nya ada, tapi engine ini tidak punya sumber body yang aman tanpa cache |
| Router menyajikan body multi-paket yang hidup lebih lama dari panggilan dispatch | body 64 KiB terbaca utuh setelah Context hilang |

#### `webtransport_test.zig`

Jalur WebTransport over HTTP/3 yang hanya bekerja ketika bagian-bagiannya sepakat: decode request yang harus mengenali session request, codec SETTINGS yang dibaca client sebelum mengirimnya, dan transport parameter yang menjadi fondasi fiturnya. Byte-nya dibangun tangan dari primitive publik yang sama yang dipakai peer, jadi yang diuji adalah kontrak wire, bukan decode yang digerakkan encoder yang berbagi kesalahan yang sama.

| Tes | Yang diverifikasi |
| :- | :- |
| Decode request melaporkan token yang dipakai membuka session WebTransport | byte persis sebuah extended CONNECT (`:method CONNECT`, `:scheme`, `:authority`, `:path`, dan `:protocol` di bawah literal name) ter-decode menjadi token, dan token itu menyebut dialect-nya |
| Token protokol yang Huffman-coded tetap menyebut dialect-nya | decode membiarkan nilainya dalam coding saat kedatangannya, jadi layer yang mengenali session request memperluasnya sebelum mencocokkan |
| Protokol pada request yang bukan CONNECT adalah malformed | `:protocol` hanya memperluas CONNECT (RFC 9220 4), dan GET yang membawa token WebTransport tidak pernah dibaca sebagai session request |
| Setting yang diiklankan server WebTransport adalah yang dibutuhkan client | ketiga support flag yang diperiksa client, limit session draft-16, dan pasangan deployed supaya client draft-07 juga melihat dukungan |
| Transport parameter WebTransport ter-parse dari client hello | `max_datagram_frame_size` (0x20) dan `reset_stream_at` (0x1d) ter-parse di samping limit flow control yang dibaca jalur respons |

### tests/integration/webrtc/

#### `exchange_test.zig`

Gerbang exit CI untuk engine ini: satu sesi utuh antara dua peer di memori, tanpa port dan tanpa
sleep. Inilah yang membuktikan delapan lapis sans-I/O sepakat ketika dua instance independen bertemu.

| Test | Yang diverifikasi |
| :- | :- |
| Dialer dan answerer membawa satu pesan dari ujung ke ujung | ICE, DTLS, SCTP dan DCEP semuanya selesai, dan payload selamat pulang pergi |
| Answerer menominasikan pair asal check tersebut | agent ice-lite memilih berdasarkan check terverifikasi, bukan candidate karangannya sendiri |
| Channel mendarat di identifier genap karena dialer yang membukanya | role DTLS menentukan paritas, dan salah di sini tidak terlihat terhadap peer yang berbagi kesalahan yang sama |
| Tidak ada peer yang ditinggali deadline yang tidak akan pernah terpenuhi | setiap timer yang dipasang sesi itu terpenuhi atau dipensiunkan |

### tests/integration/grpc/

#### `server_test.zig`

Port: 18200-18206.

| Pengujian | Yang diverifikasi |
| :- | :- |
| `GrpcServer.init` dan deinit tidak error | konfigurasi valid berhasil, deinit aman |
| `GrpcServer.init` port nol | menghasilkan `error.ZixPortNotConfigured` |
| gRPC unary mengembalikan salam | `greetHandler` membaca satu pesan, membalas `"Hello, world!"` |
| gRPC server streaming mengirim beberapa response | `echoHandler` mengirim dua pesan, client menerima keduanya berurutan |
| gRPC client streaming mengumpulkan semua pesan | `collectHandler` menyangga tiga pesan, membalas dengan jumlah `"got 3"` |
| gRPC bidirectional meng-echo setiap pesan | `echoHandler` meng-echo `"ping"` lalu `"pong"` dari dua pesan client |
| gRPC method tidak dikenal mengembalikan UNIMPLEMENTED | `dispatchHandler` membalas dengan `GrpcStatus.UNIMPLEMENTED` untuk path tidak dikenal |
| gRPC error trailers-only diterima sebagai INVALID_ARGUMENT | `errorOnlyHandler` memanggil `res.finish(INVALID_ARGUMENT, ...)` tanpa mengirim data, client menerima status error |
| gRPC dua stream pada koneksi yang sama keduanya mengembalikan OK | dua RPC unary berurutan pada satu koneksi, kedua stream menerima respons yang benar |

### tests/integration/channel/

#### `channel_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Kapasitas init `Channel(u32)` | `buf.len == 8`, `count == 0`, `head == 0` |
| `Channel([]const u8)` berhasil dikompilasi | tipe elemen slice diterima |
| `Channel(struct)` berhasil dikompilasi | tipe elemen struct diterima |
| Round-trip send dan recv `Channel(u32)` | send lalu recv mengembalikan nilai yang dikirim |
| `Channel(u32)` drain setelah close | kirim dua item, close, recv keduanya, recv ketiga menghasilkan `error.ZixClosed` |

---

## Pengujian Perilaku

Sumber: `tests/behaviour/`. Setiap berkas memverifikasi kontrak API yang dapat diamati yang diandalkan oleh pemanggil: properti "apa yang selalu dilakukan ini".

### tests/behaviour/dispatch/

#### `platform_gate_test.zig`

Kontrak platform `DispatchModel` lintas-engine (ADR-065), dipastikan sekali untuk seluruh tree.

| Pengujian | Yang diverifikasi |
| :- | :- |
| `DispatchModel` adalah satu tipe bersama | setiap namespace engine (Tcp, Http, Http1, Http2, Grpc, Fix, Udp, Http3) mengekspor ulang tipe yang sama |
| `DispatchModel` berisi tepat ASYNC, EPOLL, URING | switch exhaustive tanpa arm else, jadi varian keempat merusak build |
| nama POOL dan MIXED yang dilepas tidak lagi resolve | `std.meta.stringToEnum` mengembalikan null untuk keduanya |
| nilai backing gapless dengan ASYNC sebagai nol | 0 / 1 / 2, dan config zero-init mendarat di model portabel |
| `isSupported` menerima ASYNC di mana pun | model portabel tidak pernah ditolak |
| `isSupported` menggerbangi EPOLL dan URING pada os target | true hanya pada target Linux |
| model yang ditolak dinamai di baris log | `rejectedName` mengembalikan tag model, jadi operator melihat mana yang ditolak |
| config ASYNC diterima setiap engine | init menyimpan model portabel tanpa memulai accept loop |
| engine grpc menerima model bersama di server ber-tipe Router | `Grpc.Server.init(Router(&routes), ...)` menyimpan `.ASYNC` |

### tests/behaviour/tcp/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Default dispatch_model `TcpServerConfig` | `.ASYNC` (nilai nol) |
| Default kernel_backlog `TcpServerConfig` | 4096 |
| Default max_recv_buf `TcpServerConfig` | 4096 |
| Default workers `TcpServerConfig` | 0 (otomatis) |
| Default max_recv_buf `TcpClientConfig` | 4096 |
| Header panjang frame TCP | u32 big-endian 4-byte di-encode dan di-decode dengan benar |
| Payload panjang nol frame TCP | di-encode sebagai empat byte nol |
| Ukuran header frame TCP | selalu tepat 4 byte |
| `DispatchModel.ASYNC` adalah nilai nol | `@intFromEnum(.ASYNC) == 0` |

### tests/behaviour/http/

#### `request_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `path()` menghapus query string | `"/api/users?limit=10"` -> `"/api/users"` |
| `path()` mengembalikan target penuh jika tidak ada `?` | `"/api/users/alice"` tidak berubah |
| `path()` root path | `"/"` mengembalikan `"/"` |
| `query()` mengembalikan bagian setelah `?` | `"q=hello&lang=zig"` |
| `query()` mengembalikan kosong jika tidak ada `?` | `""` |
| `body()` chunked menghasilkan payload sama dengan Content-Length | chunked `"world"` cocok dengan `body_cache = "world"` |
| `body()` panggilan kedua mengembalikan hasil yang di-cache | `b1.ptr == b2.ptr` setelah dua pemanggilan body() |
| `method()` menyelesaikan setiap method | DELETE/PATCH/PUT/OPTIONS/HEAD/GET/POST semuanya diselesaikan |

#### `router_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Exact mengalahkan param terlepas dari urutan registrasi | exact yang didaftarkan setelah param tetap menang |
| Param mengalahkan prefix terlepas dari urutan registrasi | param yang didaftarkan setelah prefix tetap menang |
| Prefix: pencocokan terpanjang menang | `/api/users` mengalahkan `/api` untuk `/api/users/alice` |
| Prefix mencocokkan path-nya sendiri secara tepat | `/api` cocok dengan `/api` |
| Query string transparan untuk dispatch param | `"/users/bob?role=admin"` menangkap `bob` melalui `:id` |
| Query string transparan untuk dispatch exact | `"/about?ref=menu"` cocok dengan `/about` |

#### `content_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Ekstensi grup teks | html/htm/css/txt/csv |
| Ekstensi grup aplikasi | json/map/js/min.js/xml/pdf/wasm/zip/gz/tar/7z/rar/rtf |
| Ekstensi grup gambar | png/jpg/jpeg/gif/svg/webp/ico |
| Ekstensi grup audio | mp3/wav/flac/mid/midi |
| Ekstensi grup video | mp4/webm/ogg/mpeg/avi/mov/wmv/flv/mkv |
| Ekstensi grup font | ttf/otf/woff/woff2 |
| Pencocokan case-insensitive | HTML, PNG, JS, JSON, JPG, JPEG, CSS, WOFF2 |
| `fromExtension()` mengembalikan string MIME yang benar | kumpulan representatif |
| Pasangan alias menghasilkan string MIME identik | jpg==jpeg, mid==midi, html==htm, js==min.js, json==map |

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Default ukuran buffer | `kernel_backlog`, `max_recv_buf`, `max_allocator_size` semuanya 4096 |
| Default timeout dinonaktifkan | `conn_timeout_ms == 0`, `handler_timeout_ms == 0` |
| Penyajian static dinonaktifkan secara default | `public_dir == ""`, `public_dir_upload == "u"` |
| `dispatch_model` wajib (tidak ada default) | pemanggil harus menyetelnya di `HttpServerConfig` |
| Default `workers` ukuran otomatis | `workers == 0` |
| `max_request_headers` default ke `.LARGE` | varian enum dan `.value()` == 64 |
| Nilai tier `RequestHeaderSize` | MINIMAL=16, COMMON=32, LARGE=64 |
| `RequestHeaderSize.CUSTOM(N)` dibatasi di 64 | nilai di atas 64 diam-diam mengembalikan 64 |
| `max_response_headers` default ke MINIMAL (16) | nilai enum dan `.value()` |
| Nilai tier `HeaderSize` | MINIMAL=16, COMMON=32, LARGE=64, EXTRA_LARGE=128 |
| `HeaderSize.CUSTOM(N)` mengembalikan N | 7 dan 100 |
| Status `Response` default ke OK | invarian `init()` |

#### `sse_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `ContentType.TEXT_EVENT_STREAM.asString()` | mengembalikan `"text/event-stream"` |
| `Response.streaming` default ke false | invarian `init()` |

#### `query_test.zig`

Dukungan QUERY RFC 10008 di engine `zix.Http`, dipegang pada kontrak yang sama dengan raw engine.

| Pengujian | Yang diverifikasi |
| :- | :- |
| Menerima request line QUERY | parser dulu menolak QUERY mentah-mentah |
| Request QUERY bisa dibedakan dari GET | kode bertipe-nya berbeda |
| Request QUERY membawa content-nya seperti POST | pengantaran body chunked |
| Request QUERY memaparkan Content-Type yang dideklarasikan | section 2 |
| QUERY tanpa Content-Type melaporkan tidak ada type | kasus 400 |
| Query content type yang tidak didukung melaporkan tidak ada kecocokan, tidak pernah ditebak | section 2.1 |
| Semua query content type yang disebut RFC 10008 dikenali | tabelnya sama dengan raw engine |
| Http dan Http1 sepakat tentang apa itu request QUERY | satu jawaban dari kedua engine |
| Method yang tidak diimplementasikan menarik 501, bukan 400 | request line ter-tokenisasi, jadi request-nya tidak rusak |
| Http dan Http1 menjawab method tak terimplementasi secara identik | response byte-identik |

### tests/behaviour/http1/

#### `config_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| `dispatch_model` wajib dan disimpan apa adanya | field round-trip |
| `workers` default nol (auto) | nol berarti auto-size |
| Default `kernel_backlog` 1024 | default bawaan |
| Default ukuran buffer | `max_recv_buf` 6 KiB, `compression_max_out` 256 KiB |
| Default kompresi | mati, `min_size` 256, `max_out` 256 KiB |
| Nilai backing integer `DispatchModel` | `ASYNC` adalah nilai nol |
| Static cache mati secara default | `public_dir_cache_ttl_ms` 0, `public_dir_cache_max_entries` 256 |
| Field static cache disimpan apa adanya | keduanya round-trip |
| Knob static cache independen dari knob response cache | kedua cache tidak berbagi state |

#### `core_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| `parseHead` mengekstrak method, path, dan versi | request line dipisah dengan benar |
| `parseHead` HTTP/1.1 default keep_alive true | persistensi default RFC |
| `parseHead` `Connection: close` mematikan keep_alive | header menimpa default |
| `getHeader` mengembalikan nilai tanpa peduli kapitalisasi | lookup header mengabaikan case |
| `queryParam` mengembalikan nilai untuk param bernama | parsing query berdasarkan nama |

#### `query_test.zig`

Dukungan QUERY RFC 10008 lewat permukaan publik `zix.Http1`.

| Pengujian | Yang diverifikasi |
| :- | :- |
| `parseHead` membaca QUERY dari request line | token method bertahan melewati parse |
| `Request.method` menyelesaikan request QUERY menjadi QUERY | kode bertipe, bukan fallback |
| Request QUERY bisa dibedakan dari GET | defect yang ditutup: token tak dikenal dulu jatuh ke GET |
| Request QUERY membawa content-nya seperti POST | framing Content-Length dan pengantaran `body()` |
| Request QUERY memaparkan Content-Type yang dideklarasikan | section 2 butuh handler bisa membacanya |
| QUERY tanpa Content-Type melaporkan tidak ada type | kasus 400 |
| Query content type yang tidak didukung melaporkan tidak ada kecocokan, tidak pernah ditebak | section 2.1 melarang menebak dari body |
| Semua query content type yang disebut RFC 10008 dikenali | sql, jsonpath, graphql, x-www-form-urlencoded, multipart/form-data |
| Response QUERY tidak pernah masuk request cache key | section 2.7, key-nya tidak membawa content |
| Menolak QUERY tidak membuat GET di path sama ikut tidak bisa di-cache | penolakan hanya untuk method itu |
| Query content type menyusun nilai Accept-Query yang valid | section 3, sf-list RFC 9651 berisi bare item |
| Method yang tidak diimplementasikan menarik 501, bukan jawaban salah | RFC 9110 section 15.6.2 |
| QUERY diimplementasikan, jadi ia di-parse dan bukan menarik 501 | gate yang menolak method tak dikenal meloloskan QUERY |

### tests/behaviour/websocket/

#### `websocket_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Bit FIN selalu diset | byte[0] & 0x80 untuk text, binary, ping, pong, close |
| Frame server tidak bermasker | byte[1] & 0x80 == 0 untuk semua opcode (RFC 6455 5.1) |

### tests/behaviour/udp/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `UdpServerConfig` conn_timeout_ms | default 5000 |
| `UdpServerConfig` poll_timeout_ms | default 2000 |
| `UdpServerConfig` auto_ack | default false |
| `UdpServerConfig` broadcast | default false |
| `UdpServerConfig` endianness | default LITTLE |
| `UdpServerConfig` allow_args | default false |
| Re-export `Udp.DispatchModel` | resolve ke enum dispatch bersama |
| `UdpClientConfig` endianness | default LITTLE |
| `UdpClientConfig` recv_timeout_ms | default 0 (nonaktif) |

#### `packet_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `toEndian` NATIVE adalah operasi tanpa efek | byte tidak berubah pada host apa pun |
| Field array u8 tidak pernah ditukar | `id [4]u8` tidak disentuh oleh LITTLE dan BIG |
| Non-native menukar field integer | field `i32` di-byte-swap |
| Non-native menukar elemen float array | elemen `[2]f64` masing-masing ditukar |

### tests/behaviour/http/ (client)

#### `client_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Default timeout connect/response/read `ClientConfig` | semuanya 0 (dinonaktifkan) |
| Default max_response_body `ClientConfig` | 4 MB (1024 * 1024 * 4) |
| Default follow_redirects `ClientConfig` | true |
| Default max_redirects `ClientConfig` | 3 |
| Default user_agent `ClientConfig` | cocok dengan `zix.Http.default_user_agent` (string versi library dari `build.zig.zon`) |
| `ClientResponse.status()` | mengembalikan field status_code |
| `ClientResponse.body()` | mengembalikan slice body_data |
| `ClientResponse.header()` case-insensitive | cocok terlepas dari casing nama header |
| `ClientResponse.deinit()` body panjang nol | aman, tanpa crash atau leak |

### tests/behaviour/uds/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Default backlog `UdsServerConfig` | 128 |
| Default max_recv_buf `UdsServerConfig` | 4096 |
| `UdsClientConfig` menyimpan path | field path tersimpan |
| Header panjang frame UDS | u32 big-endian 4-byte di-encode dan di-decode dengan benar |
| Payload panjang nol frame UDS | di-encode sebagai empat byte nol |
| Ukuran header frame UDS | selalu tepat 4 byte |

### tests/behaviour/fix/

#### `session_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Response Logon memiliki MsgType=A dan CompID ditukar | balasan tag-35="A", tag-49=SERVER, tag-56=CLIENT, tag-34=1 |
| Field body NewOrderSingle tersimpan dalam echo | tag-11 (ClOrdID), tag-55 (Symbol), tag-54 (Side), tag-38 (Qty) semuanya ada dalam echo |
| Logout bersih tidak menyebabkan error di sisi server | field error server adalah null setelah pertukaran Logout |

### tests/behaviour/logger/

#### `logger_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Nilai backing `Level` | DEBUG=0 INFO=1 WARN=2 ERROR=3 |
| Nilai backing `ConsoleMode` | OFF=0 DEBUG_ONLY=1 ALWAYS=2 |
| Default `Config` | console=OFF, console_min_level=INFO, save_path="", save_file="log", save_min_level=INFO, max_lines=1_000_000 |
| `Logger` init dan deinit tanpa save_path | tanpa crash atau leak |
| `Logger` flush tanpa save_path adalah operasi tanpa efek | tanpa crash |
| `Http.ServerConfig.logger` default ke null | invarian `cfg.logger == null` |
| `Http.Context.logger` default ke null | invarian `ctx.logger == null` |
| `Http.Response.bytes_written` default ke 0 | `res.bytes_written == 0` setelah `init()` |

### tests/behaviour/http2/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `Http2ServerConfig` dispatch_model wajib (tidak ada default) | pemanggil harus menyetelnya eksplisit |
| `Http2ServerConfig` max_streams default ke 128 | invarian `max_streams == 128` |
| `Http2ServerConfig` max_frame_size default ke 16384 | invarian `max_frame_size == 16384` |
| `Http2` HandlerFn dapat ditugaskan ke variabel lokal | penugasan tipe `zix.Http2.HandlerFn` berhasil dikompilasi |
| Panjang `Http2` PREFACE adalah 24 | `zix.Http2.PREFACE.len == 24` |
| `Http2` ERR_NO_ERROR adalah nol | `zix.Http2.ERR_NO_ERROR == 0` |
| `Http2` FLAG_END_STREAM dan FLAG_END_HEADERS berbeda | `FLAG_END_STREAM != FLAG_END_HEADERS` |

### tests/behaviour/http3/

#### `config_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| Penyajian static mati secara default | `public_dir` kosong, ttl 0, 256 entry |
| Field static disimpan apa adanya | ketiganya round-trip |
| Penyajian static butuh caching, berbeda dari engine lain | mengunci asimetri yang disengaja: di Http3 ttl 0 mematikan penyajian static sepenuhnya, karena body respons hidup lebih lama dari handler-nya |

#### `webtransport_test.zig`

Permukaan `zix.Webtransport` yang diandalkan aplikasi dan peer, digerakkan lewat handle yang benar-benar dipegang pemanggil: hook engine di sini adalah kontrak layer dispatch (buka stream, kirim datagram, tutup session) yang diimplementasikan di atas worker pool, sehingga session dan stream bergerak seperti koneksi menggerakkannya, tanpa socket.

| Tes | Yang diverifikasi |
| :- | :- |
| Config server HTTP/3 membawa fiturnya mati dan tidak memakan biaya selama itu | default-nya nonaktif, dan config yang mati tidak mengiklankan apa pun |
| Config melewati plafon koneksi ditolak dengan field yang melewatinya | `capacityError` menyebut field-nya, dan plafonnya sendiri diterima |
| Sizing pool yang diminta sebuah config adalah window yang dipakai stream untuk menulis | config pool yang dipetakan sebuah `Config` membawa ukuran send buffer stream |
| Token yang dikirim client adalah dialect yang diucapkan session-nya | token `:protocol` pada CONNECT menentukan draft-16 atau draft-07, dan token tak dikenal tidak menentukan keduanya |
| Stream adalah write window, FIN menutupnya, dan hanya pengakuan yang menyelesaikannya | kontrak tulis / back pressure, aturan FIN, dan predikat send-finished |
| Session menegakkan limit data yang diiklankannya dan menaikkannya saat peer menghabiskannya | limit data session menolak yang melewatinya dan sebuah capsule menaikkannya |
| Datagram diframe dengan quarter stream id session-nya dan dibatasi limit peer | layout HTTP/3 datagram dan anggaran payload terhadap ukuran frame yang diiklankan |

### tests/behaviour/webrtc/

#### `session_test.zig`

| Test | Yang diverifikasi |
| :- | :- |
| Peer menjawab connectivity check sebelum apa pun dinegosiasikan | ICE berjalan mendahului DTLS, jadi check dijawab pada peer yang belum punya sesi |
| Association baru ada setelah handshake selesai | SCTP berada di dalam DTLS, jadi tidak ada yang terbaca sebelum handshake selesai |
| Peer yang diam dilepas pada deadline idle-nya | `peer_idle_ms` ditegakkan, dan itulah yang menangani browser menutup tab |
| Setiap datagram mendorong mundur deadline idle | peer yang hidup tapi diam tidak ikut dilepas |
| Dialer terus bertanya sampai satu check dijawab | timer retransmit yang menggerakkan sisi client, bukan hitungan tetap |

### tests/behaviour/grpc/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Default `GrpcServerConfig` | dispatch_model=ASYNC, kernel_backlog=1024, workers=0, max_streams=128, max_frame_size=16384, max_body=16384 |
| Field dasar `GrpcClientConfig` | field ip dan port tersimpan |
| Nilai enum `GrpcStatus` | OK=0, CANCELLED=1, UNIMPLEMENTED=12, UNAUTHENTICATED=16 |
| `GrpcContext.recvMessage` body kosong | menghasilkan null segera |
| Round-trip `GrpcPrefix` | writePrefix -> readPrefix mempertahankan flag compress dan panjang pesan |
| `parsePath` path valid | `/helloworld.Greeter/SayHello` -> `package_service="helloworld.Greeter"`, `method="SayHello"` |
| `parseTimeout` detik | `"2S"` -> 2.000.000.000 nanodetik |

### tests/behaviour/channel/

#### `channel_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Field `closed` default ke false | invarian `init()` |
| `head` dimulai dari nol | invarian `init()` |
| Rumus tail ring adalah `(head + count) % buf.len` | state yang diset secara manual memverifikasi aritmetika |
| `send` menaikkan count | count naik dari 0 ke 1 setelah satu send |
| `recv` menurunkan count | count kembali ke 0 setelah recv |
| `close` mengeset field closed | `ch.closed == true` setelah close |

---

## Pengujian Edge

Sumber: `tests/edge/`. Setiap berkas memverifikasi kondisi batas dan jalur error.

### tests/edge/tcp/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `TcpServer.init` port nol | menghasilkan `error.ZixPortNotConfigured` |
| Nilai backing `DispatchModel` stabil | ASYNC=0, EPOLL=1, URING=2 |
| Nama `DispatchModel` yang dilepas hilang | `stringToEnum` mengembalikan null untuk POOL dan MIXED |
| Panjang frame TCP maksimum u32 | `maxInt(u32)` di-encode dan di-decode dengan benar melalui big-endian |

### tests/edge/http/

#### `request_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `queryParam` key ada dengan nilai kosong | `"?k="` -> `""` (bukan null) |
| `queryParam` key tidak ada menghasilkan null | key tidak ada dalam query string |
| `queryParam` tidak ada query string sama sekali menghasilkan null | target tidak memiliki `?` |
| `body()` chunked hex tidak valid adalah error, bukan body kosong | ukuran chunk `"zz"` -> `error.ZixInvalidChunkedBody`, `bodyComplete()` false (engine menjawab 400) |
| `body()` chunked chunk terminal yang hilang mengembalikan data parsial | tidak ada `0\r\n\r\n` -> data parsial dikembalikan |
| `body()` chunked chunk satu-byte | `1\r\na\r\n1\r\nb\r\n1\r\nc\r\n0\r\n\r\n` -> `"abc"` |

#### `router_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Tidak ada route yang terdaftar menghasilkan false | router kosong, `dispatch` menghasilkan false |
| Prefix `/api` TIDAK cocok dengan `/apiv2` | karakter berikutnya setelah prefix harus `/` atau akhir-path |

#### `response_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| CR dalam nama header menghasilkan `InvalidHeaderName` | penjaga injeksi |
| LF dalam nama header menghasilkan `InvalidHeaderName` | penjaga injeksi |
| CR dalam nilai header menghasilkan `InvalidHeaderValue` | penjaga injeksi |
| LF dalam nilai header menghasilkan `InvalidHeaderValue` | penjaga injeksi |
| Buffer tumbuh dari 4 ke 5 pada header ke-5 | kapasitas awal=4, pertumbuhan ke min(8, max_response_headers) |
| `max_response_headers=1` menolak header kedua | tanpa pertumbuhan: `TooManyHeaders` segera |
| `HeaderSize.CUSTOM(0).value()` | menghasilkan 0 |

#### `content_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Ekstensi tidak dikenal menghasilkan `APPLICATION_OCTET_STREAM` | xyz, bin, dat, unknown |
| String kosong menghasilkan `APPLICATION_OCTET_STREAM` | `typeFromExtension("")` |
| `fromExtension` tidak dikenal menghasilkan `"application/octet-stream"` | bentuk string dari fallback |

#### `query_test.zig`

Kondisi batas QUERY di engine `zix.Http`.

| Pengujian | Yang diverifikasi |
| :- | :- |
| Mencocokkan token QUERY persis, seperti semua method | RFC 9110 section 9.1, nama method case-sensitive |
| Token lima byte yang bukan QUERY tetap ditolak | lengan length bukan catch-all |
| Method tak terimplementasi menjawab 501, request line rusak menjawab 400 | status berasal dari error-nya |
| QUERY dengan Content-Length nol di-framing tanpa body | framing |
| Body QUERY chunked menghasilkan byte sama dengan Content-Length | kedua framing sepakat |
| QUERY menyimpan query string dan content sekaligus | parameter target bertahan |
| Query content type terpanjang dicocokkan, bukan dipotong | 33 byte |
| Content-Type absurd melaporkan tidak ada kecocokan alih-alih melampaui buffer | dibatasi |
| Nilai Content-Type kosong melaporkan tidak ada kecocokan | kosong, titik koma tunggal, spasi |
| Parameter boundary QUERY multipart tidak menggagalkan pencocokan | parameter dilepas |
| Kedua engine menjawab sama untuk query type berparameter | dua tabel content tetap sejalan |

### tests/edge/websocket/

#### `websocket_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| 0 byte menghasilkan null | kurang dari 2 byte (tidak dapat membaca header) |
| 1 byte menghasilkan null | kurang dari 2 byte |
| Payload terpotong menghasilkan null | header menyatakan 5 byte tetapi hanya 3 yang ada |
| Panjang 16-bit extended (tier 126) | payload 130-byte: byte[1] membawa marker 126 |
| `acceptKey` key terlalu panjang menghasilkan `error.ZixKeyTooLong` | key >= 93 byte melebihi hash_input 128-byte |

### tests/edge/udp/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Port nol | `UdpServer.init` menghasilkan `error.ZixPortNotConfigured` |
| Port bukan-nol | `UdpServer.init` berhasil |

#### `packet_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Nilai backing enum `Endianness` stabil | NATIVE=0, LITTLE=1, BIG=2 |
| `FeedbackResult` ack/nack hanya tag | tag aktif cocok dengan .ack dan .nack |

### tests/edge/http/ (client)

#### `client_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Skema tidak didukung menghasilkan `error.ZixUrlSchemeUnsupported` | skema `ftp://` tidak diterima |
| Host tidak ada menghasilkan `error.ZixUrlHostMissing` | `http://` tanpa host |
| URL tidak valid menghasilkan `error.ZixUrlMalformed` | `:::bad` gagal saat parse |
| `ClientResponse.header()` nama tidak ada | menghasilkan null |
| Override `RequestOpts.connect_timeout_ms` | null, 0, dan bukan-nol adalah nilai yang berbeda |

### tests/edge/uds/

#### `config_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Path kosong menghasilkan `error.ZixPathEmpty` | `UdsServer.init(.{ .path = "" })` menghasilkan PathEmpty |

### tests/edge/logger/

#### `logger_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Batas `statusLevel` 2xx | `access()` tidak crash untuk setiap kelas status (100-599) |
| Pengurutan enum `Level` | DEBUG < INFO < WARN < ERROR melalui `@intFromEnum` |
| `system()` di bawah `save_min_level` tidak menghasilkan output | pemanggilan di bawah ambang tidak membuka berkas (`file_fd == -1`) |
| `access()` di bawah `save_min_level` tidak menghasilkan output | sama: `file_fd == -1` setelah pemanggilan yang difilter |
| `system()` dengan component kosong tidak panic | `component = ""` aman |
| `system()` dengan format kosong tidak panic | `fmt = ""` aman |
| `access()` dengan method dan path kosong tidak panic | string kosong aman |
| `init` dengan `save_path` kosong, `file_fd` tetap tidak valid | `file_fd == -1` dengan `save_path = ""` |
| Console OFF: tidak ada output atau panic untuk semua level | keempat level tidak menghasilkan crash dengan `console = .OFF` |

### tests/edge/fix/

#### `session_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| `parseFields` menangani jumlah field maksimum tanpa panic | `MAX_FIELDS - 1` pasang tag=value di-parse tanpa overflow atau crash |
| `verifyChecksum` menghasilkan false untuk pesan terpotong | pesan yang tidak memiliki delimiter checksum SOH akhir |
| `findMessageEnd` menghasilkan null untuk pesan dengan nilai tag-10 tetapi tanpa SOH akhir | field checksum parsial menghasilkan null |
| `buildMessage` dengan nol field extra menghasilkan pesan valid | output lolos `verifyChecksum` dan round-trip `parseFields` |
| Pesan yang datang dalam dua segmen TCP dirakit dengan benar | Logon terpecah di dua flush, server tetap membalas dengan MsgType=A |
| Checksum yang buruk menyebabkan server menutup tanpa propagasi error di sisi server | byte pesan yang rusak menutup koneksi `ctx.err == null` |

### tests/edge/http1/

#### `body_test.zig`

Content-Length adalah yang dipakai setiap dispatch model untuk memutuskan apakah body diantar utuh, ditunggu, atau di-drain, sehingga nilai yang ditolak parser mengubah jalur yang diambil sebuah request.

| Tes | Yang diverifikasi |
| :- | :- |
| Content-Length absen mem-framing request sebagai tanpa body | tanpa header -> `content_length` 0, flag chunked false |
| Content-Length nol mem-framing request sebagai tanpa body | `Content-Length: 0` -> 0 |
| Content-Length non-numerik jatuh ke nol | `abc` -> 0 |
| Content-Length dengan spasi di akhir jatuh ke nol | `5 ` -> 0 |
| Content-Length melewati u64 jatuh ke nol | nilai 23 digit -> 0 |
| Content-Length dibaca case-insensitive | `cOnTeNt-LeNgTh` dihormati |
| request chunked menyalakan flag chunked di samping Content-Length | kedua nilai header disimpan |
| Expect 100-continue di-flag untuk request ber-body | `expect_continue` true |
| Request bodyReceived nol untuk request tanpa body | dan `body()` mengembalikan kosong |
| Request bodyReceived mengikuti slice yang diantar secara default | slice 4 byte -> 4 |
| Request bodyComplete true untuk request tanpa body | tidak ada yang dideklarasikan, tidak ada yang bisa kurang |
| Request bodyComplete tidak bergantung panjang yang diantar | slice pendek tetap complete, override engine membuatnya false |

#### `core_test.zig`

| Tes | Yang diverifikasi |
| :- | :- |
| `parseHead` tanpa terminator CRLF | mengembalikan `IncompleteHeader` |
| `parseHead` request line kosong | mengembalikan `InvalidRequest` |
| `parseHead` tanpa versi HTTP | mengembalikan `InvalidRequest` |
| `queryParam` key dengan nilai kosong | mengembalikan string kosong, bukan null |
| `queryParam` key tidak ada | mengembalikan null |
| `parseRange` start melebihi total | mengembalikan null |
| `parseRange` tanpa prefix `bytes=` | mengembalikan null |
| `percentDecode` spasi ter-encode | didekode di tempat |

#### `static_cache_test.zig`

Setiap kasus di sini berakhir dengan hit null, yang oleh engine diperlakukan sebagai "sajikan tanpa cache".

| Tes | Yang diverifikasi |
| :- | :- |
| Menolak path yang keluar dari public_dir | traversal, absolut, dan kosong ditolak sebelum open apa pun |
| Menolak path hasil resolve yang lebih panjang dari buffer-nya | path kepanjangan ditolak, bukan dipotong |
| Dengan ttl 0 tidak pernah menyimpan apa pun | default nonaktif tidak memakai slot |
| Menolak sebuah direktori | direktori bisa dibuka tapi tidak bisa disajikan, jadi tidak dipublikasikan |
| Menyajikan file nol byte sebagai hit sungguhan | `Content-Length: 0`, tetap sebuah hit |
| Kedaluwarsa persis di batas window | segar di `insert + ttl - 1`, kedaluwarsa di `insert + ttl` |
| Tetap melayani setelah tabel penuh oleh entry yang di-pin | tabel penuh menolak path baru dan membiarkan entry yang ditahan utuh |
| Negosiasi jatuh ke identity ketika klien menolak semuanya | menyajikan file polos lebih baik daripada menolaknya |
| Init selamat dari permintaan entry yang absurd | di-clamp terhadap budget descriptor, tetap power of two |

#### `query_test.zig`

Kondisi batas QUERY: dua nilai yang dikendalikan peer, yang dibawa QUERY ke jalur yang tak pernah dilewati method tanpa body.

| Pengujian | Yang diverifikasi |
| :- | :- |
| Token method huruf kecil ditolak, bukan dilipat | RFC 9110 section 9.1, nama method case-sensitive |
| Http1 dan Http menjawab method huruf kecil dengan cara yang sama | satu tabel method bersama, jadi kedua engine tidak bisa berpisah lagi |
| Token method melebihi maksimum yang dikenal ditolak, bukan dipotong | dibatasi oleh length switch |
| Method tak terimplementasi menjawab 501, request line rusak menjawab 400 | dua kegagalan tetap terpisah |
| Request line rusak tidak dilaporkan sebagai method tak dikenal | baris yang tidak pernah ter-tokenisasi tidak berkata apa pun soal method |
| QUERY dengan target minimal tetap di-parse | target root |
| Content-Length nol dan tidak ada sama-sama di-framing tanpa body | tidak ada yang dideklarasikan berarti tidak ada yang dibaca |
| QUERY chunked menyalakan flag chunked | framing chunked tidak bergantung method |
| QUERY boleh membawa Expect 100-continue | handshake untuk body besar |
| Body QUERY melebihi receive buffer melaporkan yang sudah tiba | `bodyReceived` vs `content_length`, kasus yang tidak bisa diungkapkan GET |
| QUERY menyimpan query string dan content sekaligus | parameter target tidak digantikan body |
| Query content type terpanjang dicocokkan, bukan dipotong | 33 byte, nilai yang dulu melampaui buffer |
| Content-Type absurd melaporkan tidak ada kecocokan alih-alih melampaui buffer | header ini dikendalikan peer |
| Nilai Content-Type kosong melaporkan tidak ada kecocokan | kosong, titik koma tunggal, spasi |
| Parameter boundary QUERY multipart tidak menggagalkan pencocokan | parameter dilepas lebih dulu |
| Penyimpanan QUERY ditolak walau response-nya muat di cache | bukan efek ukuran |
| Penyimpanan QUERY ter-encode juga ditolak di jalur terkompresi | slot per-encoding membawa penolakan yang sama |

### tests/edge/http2/

#### `server_test.zig`

Port: 18100.

| Pengujian | Yang diverifikasi |
| :- | :- |
| Preface PRI yang buruk menyebabkan server menutup koneksi | byte preface tidak valid -> server menutup koneksi dengan bersih |
| Client mengirim GOAWAY dan loop koneksi server keluar | frame GOAWAY -> server keluar dari frame loop tanpa error |
| `Http2Server.init` menolak port nol | menghasilkan `error.ZixPortNotConfigured` |
| Dekode `HpackDecoder` dari blok kosong menghasilkan nol header | `decode(&.{}, ...)` menghasilkan 0 header tanpa error |
| `writeFrameHeader` bit tinggi stream_id dihapus saat dibaca | `stream_id = 0x7FFF_FFFF` di-roundtrip dengan benar melalui pipe |

### tests/edge/http3/

#### `static_test.zig`

Batas-batas di mana engine harus menolak alih-alih menyerahkan body yang tidak bisa ia tahan ke jalur kirimnya.

| Tes | Yang diverifikasi |
| :- | :- |
| Menolak file melewati batas snapshot | di atas 8 MiB ditolak untuk byte, sementara jalur descriptor tetap me-resolve-nya untuk engine lain |
| Menyajikan file persis di batas snapshot | batasnya inklusif |
| Menyajikan file nol byte sebagai body kosong | slice kosong sudah stabil, tidak ada yang di-snapshot |
| Byte adalah snapshot, bukan jendela ke file | penulisan ulang di tempat tidak mengubah byte yang sudah diberikan |
| Byte selamat dari pemotongan ke file lebih pendek | bentuk berbahaya: file menyusut saat respons masih dikirim |
| Menolak setiap path tidak aman sebelum menyentuh disk | traversal, absolut, dan kosong |
| Byte di-snapshot sekali dan dipakai ulang antar request | satu salinan menopang respons konkuren, dan masing-masing menahan pin sendiri |

#### `webtransport_test.zig`

Batas-batas `zix.Webtransport` di permukaan publiknya, dan input hostile yang bebas dikirim peer: aliran capsule yang mendeklarasikan lebih dari yang ditahan reader, application error di kedua ujung rentangnya, send window yang pembukuannya penuh, pool di slot terakhirnya, dan session yang sudah berakhir.

| Tes | Yang diverifikasi |
| :- | :- |
| Reader capsule menahan nilai sampai limitnya dan melewati satu byte di atasnya | `max_known_value` persis capsule terbesar yang didefinisikan binding, satu byte lebih dilewati di tempat, dan capsule di belakangnya tetap tiba |
| Nilai capsule yang satu byte lebih pendek dari panjangnya tidak dikirim | panjang yang dideklarasikan adalah yang dipercaya reader, jadi capsule yang pendek masih dianggap sedang tiba |
| Pemetaan application error mencakup kedua ujung 32-bit tanpa jatuh di codepoint grease | `0` dan `0xffffffff` memetakan ke ujung rentang application error, dan error code framing tidak ter-decode sebagai salah satunya |
| Reset peer melaporkan application code hanya ketika membawanya | kode di luar rentang aplikasi terbaca sebagai reset tanpa application code |
| Stream yang daftar rentang terkirimnya penuh tidak ditawari byte lagi | daftarnya terbatas, dan daftar penuh menghentikan pump alih-alih mengirim byte yang tidak lagi bisa dipertanggungjawabkannya |
| Reset mencakup minimal header dari kind yang diresetnya | reset reliabel mengirimkan header, atau peer tidak bisa tahu stream itu milik session mana |
| Pool menolak di atas slot terakhirnya dan tabel pra-session tidak menahan yang ditolaknya | pool satu slot menolak session kedua alih-alih melayaninya dari slot session pertama |
| Session tertutup menolak stream dan datagram serta memotong pesan close-nya | session tertutup tidak membuka apa pun, tidak mengirim apa pun, dan melaporkan pesan tidak lebih panjang dari limitnya |

### tests/edge/webrtc/

#### `session_test.zig`

Semuanya datang di satu port lalu dipilah dari byte pertamanya, jadi batas-batas di sini soal apa
yang dilakukan peer terhadap datagram yang tidak bisa ia pakai.

| Test | Yang diverifikasi |
| :- | :- |
| Peer selamat menghadapi semua kemungkinan byte pertama | ke-256 nilai diklasifikasikan dan tidak ada yang panik |
| Datagram kosong dibuang dan tidak mengubah apa pun | tidak ada state yang bergerak pada receive berukuran nol |
| Record DTLS yang panjangnya melampaui ujung buffer tidak dibaca melewatinya | panjang yang dideklarasikan tidak pernah dipercaya melebihi buffer |
| Pesan STUN dengan byte pertama benar dan selebihnya kosong ditolak | routing bukan validasi, magic cookie tetap harus cocok |
| Application data sebelum handshake selesai tidak sampai ke mana pun | record epoch 1 ditolak sampai ada kunci epoch 1 |
| Sampah yang sama seribu kali tetap membiarkan peer hidup | datagram buruk berulang tidak menghabiskan apa pun |
| Dialer menolak respons yang membawa transaction milik orang lain | transaction id ikut diperiksa, bukan hanya tipe pesannya |

### tests/edge/grpc/

#### `server_test.zig`

Port: 18220-18221.

| Pengujian | Yang diverifikasi |
| :- | :- |
| `readGrpcPrefix` dengan 4 byte | menghasilkan `error.ZixTooShort` |
| `readGrpcPrefix` dengan slice kosong | menghasilkan `error.ZixTooShort` |
| `GrpcContext.recvMessage` body lebih pendek dari prefix | body memiliki 3 byte (butuh 5 untuk prefix): menghasilkan null |
| `GrpcContext.recvMessage` msg_len melebihi body | prefix mengklaim 100 byte tetapi body hanya memiliki 5: menghasilkan null |
| `parsePath` string kosong | menghasilkan null |
| `parsePath` tanpa slash awal | menghasilkan null |
| `parsePath` hanya slash | menghasilkan null |
| `detectContentType` tanpa header | menghasilkan UNKNOWN |
| `detectContentType` text/plain | menghasilkan UNKNOWN |
| `parseTimeout` karakter tunggal | menghasilkan null |
| `GrpcClient.connect` port nol | menghasilkan `error.ZixPortNotConfigured` |
| `serveConn` menutup dengan bersih saat client langsung memutus koneksi | server menerima, client memutus koneksi segera, tanpa crash atau error |
| gRPC handler finish-only menyampaikan status error ke client | handler hanya memanggil `res.finish(INVALID_ARGUMENT, ...)`, client menerima status error tanpa frame data apa pun |

### tests/edge/channel/

#### `channel_test.zig`

| Pengujian | Yang diverifikasi |
| :- | :- |
| Kapasitas 1 mengalokasikan tepat satu slot | `buf.len == 1`, `count == 0` |
| Head ring membungkus di `buf.len` | `(3+1) % 4 == 0` |
| Batas penuh: `count == buf.len` | indeks tail membungkus kembali ke head |
| `send` setelah close | menghasilkan `error.ZixClosed` |
| `recv` pada channel tertutup yang kosong | menghasilkan `error.ZixClosed` |

---

###### akhir pengujian
