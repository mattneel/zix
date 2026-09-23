# LLD: zix.Tls (TLS 1.3 + 1.2 pure-Zig)

Detail implementasi internal. Untuk rasional desain lihat [`docs/hld-tls-id.md`](hld-tls-id.md) dan ADR-045 / 046 / 047.

`zix.Tls` bersifat sans-I/O. Handshake server didorong oleh `connection.serverHandshake`, client oleh `client.zig` / `tls12_client.zig`. Engine memiliki socket loop. Http1 thread-per-koneksi di `tcp/http1/tls_serve.zig`. Http2 dan Grpc memilih antara dua jalur lewat `dispatch_model` (ADR-052): `.EPOLL` / `.URING` memakai `tcp/http2/tls_mux.zig` dan `tcp/http2/grpc/tls_mux.zig` multipleks per-core di atas session resumable di `tcp/tls/tls_session.zig`, dan `.ASYNC` memakai `tcp/http2/tls_serve.zig` dan `tcp/http2/grpc/tls_serve.zig` di atas terminator bersama `tcp/tls/h2_terminator.zig`.

---

## wire.zig

`Reader` dan `Writer` di atas byte slice, big-endian. `Reader.readU8 / readU16 / readU24 / readBytes` dengan cek batas. `Writer.writeU8 / writeU16 / writeU24 / writeBytes`, plus `placeU16 / patchU16` untuk back-patch panjang setelah body ditulis (dipakai tiap field TLS panjang-variabel). Tanpa alokasi: caller menyediakan `buf`.

## handshake.zig

### Enum wire

```zig
pub const CipherSuite = enum(u16) {
    AES_128_GCM_SHA256 = 0x1301,
    AES_256_GCM_SHA384 = 0x1302,           // dideklarasi, belum diimplementasi
    CHACHA20_POLY1305_SHA256 = 0x1303,     // dideklarasi, belum diimplementasi
    ECDHE_ECDSA_AES128_GCM_SHA256 = 0xc02b, // suite floor TLS 1.2
    _,
};
pub const NamedGroup = enum(u16) { SECP256R1 = 0x0017, X25519 = 0x001d, _ };
pub const SignatureScheme = enum(u16) { RSA_PKCS1_SHA256 = 0x0401, ECDSA_SECP256R1_SHA256 = 0x0403, RSA_PSS_RSAE_SHA256 = 0x0804, ED25519 = 0x0807, _ };
```

`server_cipher_prefs = {AES_128_GCM_SHA256}` dan `server_group_prefs = {X25519, SECP256R1}` adalah default bawaan.

### Parse ClientHello

`parseClientHello` mengembalikan struct `ok` atau `alert`. Ia mencatat `offers_tls13` (dari supported_versions), `has_signature_algorithms`, `has_supported_groups`, body mentah `signature_schemes` dan `supported_groups`, key_share per-group (`x25519_share`, `secp256r1_share`), `sni`, dan ProtocolNameList `alpn` mentah. Helper: `offersCipher`, `offersGroup`, `hasKeyShare`, `offersSignatureScheme`.

### negotiate

```zig
pub fn negotiate(hello, key_exchange, group_prefs: []const NamedGroup) Outcome
```

Mengembalikan `legacy_version` saat 1.3 tidak ditawarkan (caller turun ke track 1.2), alert `MISSING_EXTENSION` tanpa sig-algs / groups, `hello_retry_request` saat curve pilihan tidak punya key_share, selain itu `server_hello`. `pickCipher` mengiterasi `server_cipher_prefs`. `pickGroup` mengiterasi `group_prefs` terkonfigurasi (jadi `Tls.Context.curves` yang dibatasi / diurut ulang dihormati), mengembalikan yang pertama juga ditawarkan client.

### Serializer

`serializeServerHello` menulis ServerHello dengan supported_versions (0x0304) dan key_share. `serializeHelloRetryRequest` menulis HRR dengan random sentinel HRR khusus (SHA-256 dari "HelloRetryRequest") dan extension key_share yang menamai hanya group untuk retry.

## key_schedule.zig

`Secret = [32]u8`, SHA-256 sepanjang jalur (jadi hanya suite 1.3 AES-128-GCM / SHA-256 yang dapat dihormati). `Transcript` membungkus SHA-256 berjalan dari pesan handshake, `update(bytes)` dan `current()`. `HkdfSha256.extract` / `deriveSecret` / `expandLabel` membangun early, handshake, dan master secret serta traffic key per RFC 8446 7.1.

## record.zig

`protect(out, plaintext, content_type, key, iv, seq)` membangun record AEAD: nonce per-record adalah `iv XOR seq` (seq 8-byte rata kanan), additional data adalah header record, inner plaintext adalah `content || content_type` (RFC 8446 5.2). `deprotect` membalikkannya dan mengembalikan inner content type. `ContentType` menyebut handshake / application_data / alert / change_cipher_spec.

## certificate.zig

```zig
pub const SigningKey = union(enum) {
    ecdsa_p256: EcdsaP256.KeyPair,
    ed25519: Ed25519.KeyPair,
    rsa: rsa.PrivateKey,
    pub fn scheme(self) SignatureScheme  // .ECDSA_SECP256R1_SHA256, .ED25519, atau .RSA_PSS_RSAE_SHA256
};
```

Builder untuk Certificate, CertificateVerify, dan Finished. CertificateVerify menandatangani `0x20 * 64 || context-string || 0x00 || transcript-hash` (RFC 8446 4.4.3) dengan scheme key: ECDSA mengeluarkan signature DER, Ed25519 64 byte mentah, dan key RSA signature PSS `rsa_pss_rsae_sha256` via `signPss` (`buildCertificateVerify` menerima salt-nya, jalur ECDSA / Ed25519 mengabaikannya). `verify_data` Finished adalah `HMAC(finished_key, transcript-hash)`, diverifikasi byte-exact terhadap trace RFC 8448 in-file.

## connection.zig

### HandshakeOptions

```zig
certificate_der, signing_key,
ephemeral_secret: [32]u8, server_random: [32]u8,   // fresh per koneksi
alpn_prefs: []const Alpn = &.{},
group_prefs: []const NamedGroup = &server_group_prefs,
request_client_cert: bool = false,                  // CertificateRequest mTLS
```

### serverHandshake

Parse ClientHello, `negotiate(&hello, &.{}, opts.group_prefs)`, seed transcript dengan ClientHello, lalu `completeHandshake`. `completeHandshake` menjaga `cipher == AES_128_GCM_SHA256`, mengecek client menawarkan scheme signing key (`NoCommonSignatureScheme` jika tidak), menegosiasi ALPN, menjalankan `computeKeyExchange` untuk curve, menulis ServerHello + EncryptedExtensions + Certificate + CertificateVerify + Finished, dan menurunkan application key ke sebuah `Connection`.

### HelloRetryRequest

`serverHelloRetry` menegosiasi hanya untuk menemukan group, men-serialize HRR, dan seed transcript dengan `message_hash` sintetik dari ClientHello1 (`0xfe 00 00 <hash_len> || Hash(CH1)`, RFC 8446 4.4.1) diikuti HRR. Ia mengembalikan `RetryFlight { to_send, state }`. `serverHandshakeAfterRetry` mengonsumsi ClientHello2, re-negotiate dengan `state.opts.group_prefs`, memastikan group cocok, dan menjalankan `completeHandshake` di transcript yang dibawa.

### Connection

Memegang application key + client-handshake key dan tiga sequence number (`server_app_seq`, `client_app_seq`, `client_hs_seq`). `writeAppData` meng-encrypt dan menaikkan `server_app_seq`. `readAppData` men-decrypt dan mengklasifikasi inner type (RFC 8446 5.1): application_data mengembalikan plaintext, alert -> `PeerClosed`, handshake pasca-handshake -> `UnexpectedMessage`. `verifyClientFinished` mengecek client Finished terhadap transcript. `encryptedAlert` / `closeNotify` membangun alert keluar.

## context.zig

`Version = enum(u8) { TLS_1_2 = 0x12, TLS_1_3 = 0x13 }` (terurut untuk min <= max). `Context.init` memanggil `validate(config)` yang I/O-free, membaca PEM cert / key, `pemToDer`, menduplikasi DER ke slice milik sendiri, lalu mendeteksi tipe key dari `cert.pub_key_algo` (`.X9_62_id_ecPublicKey` -> ECDSA via `ecdsaScalarFromSec1`, `.curveEd25519` -> Ed25519 via `ed25519SeedFromPkcs8`, `.rsaEncryption` -> RSA via `rsa.PrivateKey.fromDer`, menolak di bawah RSA-2048 dengan `ZixRsaKeyTooSmall`). Buffer DER key berukuran untuk key PKCS#8 RSA, lebih besar dari key EC. `handshakeOptions(ephemeral, random, pss_salt)` mengisi `HandshakeOptions` dari context plus random per-koneksi (salt hanya dikonsumsi oleh CertificateVerify RSA). `allowsTls13` / `allowsTls12` membaca version range.

### validate (honesty boundary)

Menolak list curve / cipher kosong, curve di luar {X25519, SECP256R1}, cipher di luar {AES_128_GCM_SHA256, ECDHE_ECDSA_AES128_GCM_SHA256}, version range terbalik, ceiling 1.3 tanpa AES_128_GCM_SHA256, dan floor 1.2 tanpa suite 1.2 atau secp256r1. Error: `ZixTlsUnsupportedCurve`, `ZixTlsUnsupportedCipher`, `ZixTlsInvalidVersionRange`, `ZixTlsMissingCipherForVersion`, `ZixTlsMissingCurveForTls12`, `ZixTlsNoCurves`, `ZixTlsNoCiphers`.

## pem.zig

`pemToDer(out, pem)` men-decode base64 satu blok PEM. `ecdsaScalarFromSec1` mengekstrak scalar privat 32-byte dari key EC SEC1. `ed25519SeedFromPkcs8` mengekstrak seed 32-byte setelah prefix PKCS#8 `04 22 04 20`.

## rsa.zig

Signer RSA (ADR-048), sisi server saja. `PrivateKey.fromDer(der, is_pkcs8)` mem-parse RSAPrivateKey two-prime (RFC 8017 A.1.2): wrapper PKCS#8 dibuka dulu ke OCTET STRING di dalamnya, lalu modulus `n` dan private exponent `d` disalin ke buffer tetap milik sendiri (leading-zero dibuang). `signPkcs1v15(message, out)` adalah jalur EMSA-PKCS1-v1_5 deterministik (RFC 8017 9.2): `0x00 01 PS 00 || DigestInfo || SHA256(message)`. `signPss(message, salt, out)` adalah EMSA-PSS (RFC 8017 9.1) dengan MGF1, salt diinjeksi oleh pemanggil sehingga encoding-nya deterministik dan bisa diuji unit. Keduanya berakhir di RSASP1 via Chinese Remainder Theorem (RFC 8017 5.1.2): dua modexp setengah-lebar atas prime `p` dan `q` (faktor CRT kini dipakai, bukan hanya `n` dan `d`), masing-masing dijalankan lewat Montgomery modexp constant-time di `montgomery.zig` (jalur asm ADCX / ADOX fused di x86_64+ADX, CIOS portable selain itu), lalu digabung kembali dan I2OSP ke `k` byte. `std.crypto.ff.Modulus.powWithEncodedExponent` adalah fallback untuk lebar prime yang tidak dicakup jalur Montgomery.

## cert_verify.zig

`verifyChain(chain_der, anchor_der, now_sec)` memverifikasi chain [leaf, intermediate, ...] ke anchor: signature tiap link via std `Parsed.verify`, plus walk extension manual untuk basicConstraints (cA / pathLen), keyUsage (keyCertSign), dan penanganan critical-ext (wrapper extensions `[3]` terbaca sebagai tag `.bitstring` dari `std.crypto.Certificate.der.Element`, dicerminkan di sini). `verifyCertIdentity(end_entity_der, host)` mengecek DNS SAN (std `verifyHostName`) atau IPv4 SAN (`sanHasIp4`, men-scan GeneralName `0x87 0x04 <4 byte>`, karena std hanya DNS).

## tcp/http1/tls_serve.zig

`runTls` membaca `config.tls.?` (context) dan menjalankan accept loop. `serveConnTls(fd, handler, ctx)`:

1. baca record ClientHello, generate `ephemeral_secret` + `server_random` + `pss_salt` (getrandom), bangun `opts = ctx.handshakeOptions(...)`.
2. version policy: jika `!ctx.allowsTls13()`, langsung ke jalur 1.2 (ECDSA saja, jika tidak `ZixTls12RequiresEcdsa`).
3. ronde HelloRetryRequest jika `serverHelloRetry` mengembalikan satu, jika tidak `serverHandshake`. Saat `ZixUnsupportedTlsVersion`: jika `!ctx.allowsTls12()` kirim alert `protocol_version`, jika tidak ambil jalur 1.2.
4. baca (ChangeCipherSpec) + client Finished, lalu satu record aplikasi -> `readAppData` -> `core.parseHead`.
5. Host vs identitas cert (`verifyCertIdentity`) -> 421 saat mismatch, jika tidak jalankan handler dengan capture sink in-memory (`runHandlerToBuffer`) dan `writeAppData` response, lalu `closeNotify`.

`readRecord` / `readAll` / `writeAll` memakai `std.os.linux.read` / `write` dengan switch errno (tanpa wrapper std.posix demi portabilitas lintas 0.16 / 0.17).

### SSE / streaming melalui TLS (ADR-054)

Jalur thread-per-koneksi juga melayani handler streaming (SSE) melalui TLS, di kedua `zix.Http1` (`core.zig`) dan `zix.Http` (`response.zig`). `serveRequests` memasang `TlsStreamSink` per-koneksi, writer type-erased (`StreamSinkFor(@TypeOf(conn))`) yang memegang koneksi hidup dan fd: tiap write mengenkripsi satu TLS record (`conn.writeAppData`) dan mengirimnya. `writeAllFD` memeriksa buffered capture sink dulu, lalu stream sink, jadi response normal menjaga jalur cepat ter-buffer. Handler memilih streaming dengan `res.sendStream()` (`zix.Http`) atau `beginStream()` / `res.sendStream()` (`zix.Http1`, no-op di cleartext), yang melepas capture sink jadi write berikutnya jatuh ke stream sink. `runHandlerToBuffer` / `processRequestToBuffer` melaporkan outcome streamed (capture sink dilepas) jadi loop close setelah stream selesai. Jalur `tls_mux` multipleks tetap request / response saja.

### WebSocket melalui TLS (ADR-055)

WebSocket dibangun di atas stream sink yang sama untuk write half dan menambah read half (dekripsi record, parse frame). Handler yang dilayani melalui TLS memanggil `WebSocket.serveTls(fd, key, on_frame)`: ia melepas capture, menulis `101` lewat stream sink (terenkripsi), dan mendaftarkan handoff (`requestWebSocket` / `takeWebSocket`, dibagi dengan jalur `.EPOLL` cleartext di `zix.Http1`, ditambahkan ke `zix.Http`). Setelah handler return, `serveRequests` mengambil handoff dan menjalankan `serveWsTls`: baca satu ciphertext record, dekripsi (`conn.readAppData`), akumulasi, lalu `WebSocket.pump` frame lengkap (text / binary -> `on_frame`, ping auto-pong, close auto-echo). `pump` meng-coalesce frame keluar pass itu dan flush lewat `writeAllFD`, yang stream sink enkripsi sebagai satu record. `send` melalui TLS dirutekan sama. `zix.Http` memperoleh bagian engine-driven (`WsFrameFn`, `send`, `pump`, `upgradeFd`, handoff) jadi kedua engine berbagi bentuk `on_frame(fd, opcode, payload)`. Rooms / broadcast hanya cleartext (tiap koneksi punya TLS session sendiri), jadi wss bersifat per-koneksi. Jalur `tls_mux` multipleks membuang handoff (WS thread-per-koneksi saja).

## tcp/tls/h2_terminator.zig (terminator h2-over-TLS bersama)

`serveConnTls(fd, ctx, driver)` adalah terminator engine-agnostic yang dipakai jalur `.ASYNC` dari Http2 dan Grpc. Ia menjalankan handshake (version policy + fallback 1.2 ke `serveConnTls12`, yang menerima `driver` yang sama), memastikan ALPN memilih h2 (`ZixAlpnNotH2` jika tidak), memverifikasi client Finished, lalu memanggil `driver.drive(fd, &conn, &record_buf)`. Driver memiliki koneksi sampai close: ia menjalankan mux h2 resumable langsung di atas record terdekripsi dan menyegel frame engine kembali ke record TLS lewat write hook thread-local. Tanpa socketpair, tanpa thread kedua.

## tcp/http2/tls_serve.zig dan tcp/http2/grpc/tls_serve.zig

Ini jalur `.ASYNC`. `runTls` membaca `config.tls.?`, menjalankan accept loop, dan menyerahkan tiap koneksi ke worker thread-nya sendiri, yang memanggil `serveConnTls` dengan `MuxDriver(routes)`. `drive` milik driver yang berbeda: Http2 menjalankan `mux.processRing` di atas `mux.MuxConn`, Grpc menjalankan `core.grpcMuxProcessRing` di atas `GrpcMuxConn` lalu `flushStage` untuk cork balasan yang di-stage. Keduanya menyegel frame ke record TLS lewat `frame.write_hook`, state machine resumable yang sama dengan model cleartext `.EPOLL` / `.URING`, jadi tidak ada race write per-stream. Model dispatch `.EPOLL` / `.URING` justru memakai `tls_mux.zig` multipleks di bawah.

## tcp/tls/tls_session.zig (session server TLS 1.3 resumable)

Linchpin dari jalur multipleks (ADR-052). Session server TLS 1.3 sans-blocking-I/O yang digerakkan satu worker epoll untuk banyak koneksi sekaligus. `Session.init(cert_der, signing_key, alpn_prefs)` menyemai random. `feed(input, to_send_buf, plain_buf)` mengakumulasi ciphertext di `rbuf` internal, memproses tiap record lengkap, dan mengembalikan `FeedResult{ to_send, plaintext, outcome }`. State machine `Phase` berjalan `hello -> finished -> established -> closed`: di `hello` ia memanggil `serverHandshake` dan mengeluarkan flight, di `finished` ia memverifikasi client Finished, di `established` ia men-decrypt application data. `encrypt` menyegel plaintext jadi record, `closeNotify` mengeluarkan alert close. Hanya TLS 1.3: ClientHello 1.2-saja ditolak dengan fatal alert (fallback 1.2 tetap di `tls_serve.zig`).

## tcp/http2/tls_mux.zig dan tcp/http2/grpc/tls_mux.zig (dispatch multipleks)

Jalur `.EPOLL` / `.URING` (ADR-052). `runTlsMux` men-spawn satu worker per core, masing-masing dengan listener `SO_REUSEPORT` dan instance epoll sendiri. Slab `TlsConn` (di-index oleh fd) memegang `tls_session.Session`, mux h2 / gRPC, dan buffer ciphertext keluar yang di-stage yang meng-arm `EPOLLOUT` saat `EAGAIN` untuk backpressure. `onReadable` membaca ciphertext, memanggil `session.feed`, mengirim flight handshake, dan pada outcome established memberi plaintext terdekripsi ke mux (`processRing` / `grpcMuxProcessRing`), yang frame-nya disegel kembali ke record lewat `frame.write_hook` yang menunjuk `hookWrite`. Satu worker memultipleks banyak koneksi, jadi konkurensi tinggi tidak men-spawn thread per koneksi.

## tls12_*.zig

Track 1.2 mencerminkan lapisan 1.3: `tls12_prf` (key schedule PRF SHA-256), `tls12_record` (AES-GCM 1.2 dengan nonce eksplisit 8-byte), `tls12_version` (`selectVersion` + downgrade sentinel di ServerHello.random, RFC 8446 4.1.3), `tls12_connection` (`serverFlight1` + `serverFinish`, ECDHE-ECDSA-AES128-GCM, secp256r1), dan `tls12_client`.

## dtls_*.zig

Track DTLS 1.2 (RFC 6347), hanya dijangkau `zix.Webrtc`. Sembilan berkas, dan `zix.Tls` tidak mengekspor ulang satu pun. Internal per berkas ada di [`docs/lld-webrtc-id.md`](lld-webrtc-id.md), karena setiap jebakan di sana menghadap WebRTC. Tiga yang paling penting bagi pembaca TLS:

- `dtls_connection.zig` menyusun flight-nya **sendiri** (2, 4 dan 6) dan hanya memakai ulang primitif daun dari track 1.2. Ia tidak bisa memakai ulang `tls12_connection.zig`: berkas itu meng-hash byte berbingkai TLS, sementara RFC 6347 bagian 4.2.6 menuntut transcript diambil di atas header DTLS 12 byte seolah tidak terfragmentasi, tanpa ClientHello pertama dan HelloVerifyRequest. Ketidakcocokan ini tidak terlihat sampai peer sungguhan menolak pesan Finished.
- `dtls_record.zig` menambahkan epoch, sequence 48 bit, dan window anti-replay di atas AEAD yang sama. Window harus diperiksa sebelum AEAD lalu diperbarui sesudahnya, kalau tidak sequence palsu yang jauh di depan akan membersihkannya.
- `dtls_exporter.zig` adalah ekspor keying material RFC 5705 plus pemisahan SRTP RFC 5764. DTLS-SRTP memakai bentuk seed **tanpa context**: mengoper slice kosong menambahkan dua byte nol dan diam-diam merusak interop.
