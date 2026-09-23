# HLD: zix.Logger

Event logger terstruktur dengan penulisan yang thread-safe dan integrasi protokol otomatis.

---

## Status

Sudah diimplementasi. Lihat ADR-023 untuk dasar keputusan desain.

---

## Tujuan

- Thread-safe dari konteks apapun termasuk background OS thread (tidak ada dependensi pada `std.Io`).
- Signature metode per-event yang terstruktur, bukan gaya printf dengan string kategori.
- Tipe log spesifik per protokol: `conn()`, `packet()`, `frame()`, `session()` menghasilkan baris yang dapat di-parse oleh mesin tanpa pasca-pemrosesan.
- Rotasi file: subdirektori harian plus nomor urut per berkas, tanpa perlu tooling eksternal.
- Nol alokasi dan tanpa syscall di thread pemanggil: satu record disalin ke write buffer 64 KB, dan sebuah flush thread di latar belakang yang melakukan setiap penulisan.
- Pemanggil memiliki allocator, lifetime logger adalah `init`/`deinit`.

---

## Struktur Berkas

```
src/logger/
    logger.zig   // Logger struct with nested Config, Level, ConsoleMode, Dir
    sink.zig     // Sink: the lock-free buffer indirection a write lands in
    flush.zig    // Flusher: the background thread that drains sinks to disk
    windows_file.zig // the Windows file-open path
```

Ekspor dari `src/lib.zig`:
```zig
pub const Logger = @import("logger/logger.zig").Logger;
// zix.Logger, zix.Logger.Level, zix.Logger.ConsoleMode, zix.Logger.Dir, zix.Logger.Config
```

---

## API Publik

| Simbol | Tipe | Deskripsi |
| :- | :- | :- |
| `zix.Logger` | struct | `init(allocator, config)` / `deinit()` / `flush()` |
| `zix.Logger.Config` | struct | Field konfigurasi (tipe nested pada struct) |
| `zix.Logger.Level` | enum(u8) | `DEBUG=0` `INFO=1` `WARN=2` `ERROR=3` |
| `zix.Logger.ConsoleMode` | enum(u8) | `OFF=0` `DEBUG_ONLY=1` `ALWAYS=2` |
| `zix.Logger.Dir` | enum(u8) | `RECV=0` `SEND=1`: arah untuk `packet()` dan `frame()` |

---

## Field Konfigurasi

| Field | Default | Deskripsi |
| :- | :- | :- |
| `console` | `.OFF` | Mode output ke console |
| `console_min_level` | `.INFO` | Level minimum yang dicetak ke console |
| `console_fd` | `null` | Descriptor tujuan record console dan laporan file-suspension. `null` berarti stderr. Descriptor dimiliki pemanggil dan harus tetap terbuka selama logger hidup |
| `save_path` | `""` | Direktori root untuk berkas log. Harus sudah ada. `""` menonaktifkan logging ke berkas |
| `save_file` | `"log"` | Nama berkas dasar. Berkas dinamai `<save_file>-NNNNNN.log` |
| `save_min_level` | `.INFO` | Level minimum yang ditulis ke berkas |
| `max_lines` | 1.000.000 | Jumlah baris per berkas sebelum rotasi ke nomor urut berikutnya |

---

## Metode Log

| Metode | Dipanggil otomatis oleh | Level | Format baris |
| :- | :- | :- | :- |
| `system(level, component, fmt, args)` | semua server (lifecycle) | ditentukan pemanggil | `DATE TIME LEVEL  [component] message` |
| `access(component, method, path, status, bytes, client_ip, ua, origin)` | zix.Http, zix.Http1, zix.Http2, zix.Http3 (per-request), zixer (per-exchange) | diturunkan dari status | `DATE TIME LEVEL  [component:access] METHOD PATH STATUS BYTES "CLIENT_IP" "UA" "ORIGIN"` |
| `conn(peer, dur_ms, err)` | TCP server (per penutupan koneksi) | INFO / WARN | `DATE TIME LEVEL  [tcp:conn] PEER dur=NNNms ERR` |
| `packet(dir, peer, size, err)` | UDP server (per datagram) | INFO / WARN | `DATE TIME LEVEL  [udp:pkt] DIRECTION PEER size=N ERR` |
| `frame(dir, sock_path, size, err)` | UDS (manual) | INFO / WARN | `DATE TIME LEVEL  [uds:frame] DIRECTION SOCKPATH size=N ERR` |
| `session(msg_type, sender, target, seq, state)` | FIX server (per pesan) | INFO | `DATE TIME LEVEL  [fix:sess] 35=TYPE sender=S target=T seq=N STATE` |
| `rpc(peer, path, grpc_status, recv_bytes, sent_bytes, dur_ms)` | gRPC server (per penutupan stream) | INFO / WARN | `DATE TIME LEVEL  [grpc:rpc] PEER PATH status=N recv=N sent=N dur=Nms` |

### Penurunan Level

- `access()`: 2xx/3xx=INFO, 4xx=WARN, 5xx=ERROR, lainnya=DEBUG.
- `conn()`: `err == null` -> INFO, `err != null` -> WARN.
- `packet()`, `frame()`: sama dengan `conn()`.
- `session()`: selalu INFO.
- `rpc()`: `grpc_status == 0` -> INFO, `grpc_status != 0` -> WARN.
- `system()`: pemanggil menyediakan level secara eksplisit.

---

## Contoh Format Log

```
2026-05-23 14:22:01.456 INFO   [startup] server listening on 9300
2026-05-23 14:22:01.789 INFO   [http1:access] GET /api/items 200 512 "203.0.113.7" "curl/8.1" "-"
2026-05-23 14:22:01.790 WARN   [http1:access] GET /missing 404 0 "203.0.113.7" "-" "-"
2026-05-23 14:22:02.100 INFO   [tcp:conn] 127.0.0.1:54321 dur=12ms -
2026-05-23 14:22:02.200 INFO   [udp:pkt] recv 127.0.0.1:5001 size=56 -
2026-05-23 14:22:02.300 INFO   [uds:frame] recv /tmp/app.sock size=8 -
2026-05-23 14:22:02.400 INFO   [fix:sess] 35=A sender=CLIENT target=ZIX seq=1 Logon
2026-05-25 10:15:33.201 INFO   [grpc:rpc] 127.0.0.1:56789 /helloworld.Greeter/SayHello status=0 recv=16 sent=22 dur=1ms
```

---

## Rotasi File

Berkas ditulis ke `<save_path>/YYYY-MM-DD/<save_file>-NNNNNN.log`:
- Direktori tanggal baru dibuat otomatis pada penulisan pertama di hari kalender yang baru.
- Saat `line_count` mencapai `max_lines`, nomor urut dinaikkan dan berkas baru dibuka.
- Nomor urut maksimum adalah 999.999. Setelah habis, logging ke berkas ditangguhkan dan pesan ditulis ke stderr.
- `save_path` itu sendiri harus sudah ada: logger tidak membuatnya. Gunakan helper `createLogDir` sebelum `Logger.init`.

---

## Keamanan Thread

Semua metode log aman dipanggil secara bersamaan dari OS thread manapun:
- Spinlock (atomic CAS) menserialisasi penyalinan ke shared write buffer. Lock dipegang untuk satu `memcpy`, tidak pernah melintasi syscall.
- `rawWrite` menggunakan syscall POSIX `write` langsung, dan file sink Windows memakai ntdll langsung: tidak ada dependensi pada `std.Io`, aman di background OS thread.
- Tidak ada `std.debug.print` atau path apapun melalui `std.Options.debug_io`. Aman selama `zig build test-all`.

### Flush Thread

Setiap destinasi yang aktif memiliki dua write buffer. Producer mengisi satu buffer sementara flush thread menulis buffer lainnya, sehingga tidak ada pemanggil yang menunggu disk.

- Flush thread dijalankan pada record pertama, karena `Logger.init` mengembalikan nilai dan thread membutuhkan alamat akhir tempat logger tinggal.
- Penulisan dilakukan dengan lock dilepas. Buffer yang sudah diserahkan tidak boleh disentuh sampai penulisannya selesai, dan itulah yang menjaga rotasi serta close agar tidak berebut dengannya.
- Record tidak pernah dibuang. Ketika kedua buffer penuh, producer menunggu penulisan yang sedang berjalan, dihitung oleh `stallCount()` sehingga disk yang tidak sanggup mengejar terlihat, bukan diam-diam.
- Record `ERROR` ditulis keluar sebelum pemanggilan kembali, sehingga sebuah crash tidak menelan record yang menjelaskan crash itu.
- `flush()` dan `deinit()` menulis semua yang tersisa di buffer pada thread pemanggil sebelum kembali.

**Trade-off durabilitas**: sebuah crash dapat kehilangan sampai satu buffer record yang belum sempat ditulis. `flush()` dan aturan `ERROR` adalah dua cara untuk memaksa batasnya.

### Timestamp

Setiap record dan setiap direktori harian distempel dalam UTC+0000. Logger tidak membaca timezone lokal, sehingga armada yang tersebar di banyak region menghasilkan satu urutan yang dapat dibandingkan.

---

## Penyambungan Protokol

Setiap server menerima `logger: ?*Logger = null` opsional di konfigurasinya. Saat tidak null, logging otomatis aktif:

| Protokol | Metode yang dipanggil otomatis | Field konfigurasi |
| :- | :- | :- |
| HTTP | `access()` per request, `system()` lifecycle | `HttpServerConfig.logger` |
| HTTP/1.1 | `access()` per request, `system()` lifecycle | `Http1ServerConfig.logger` |
| HTTP/2 | `access()` per stream, `system()` lifecycle | `Http2ServerConfig.logger` |
| HTTP/3 | `access()` per request, `system()` lifecycle | `Http3ServerConfig.logger` |
| TCP | `conn()` saat koneksi ditutup, `system()` lifecycle | `TcpServerConfig.logger` |
| UDP | `packet()` per datagram, `system()` lifecycle | `UdpServerConfig.logger` |
| UDS | `system()` lifecycle | `UdsServerConfig.logger` |
| FIX | `session()` per pesan, `system()` lifecycle | `FixServerConfig.logger` |
| gRPC | `rpc()` saat stream ditutup, `system()` lifecycle | `GrpcServerConfig.logger` |
| Channel | tidak ada server config, panggil `logger.system()` secara manual | n/a |

`frame()` tersedia untuk penggunaan manual di dalam UDS handler (handler memiliki stream, sehingga event di level frame dikendalikan oleh pemanggil).

---

## Penggunaan

```zig
fn createLogDir(io: std.Io) void {
    std.Io.Dir.cwd().createDirPath(io, "./logs") catch {};
}

pub fn main(process: std.process.Init) !void {
    createLogDir(process.io);

    var logger = try zix.Logger.init(std.heap.smp_allocator, .{
        .save_path      = "./logs",
        .save_file      = "app",
        .save_min_level = .INFO,
        .console        = .ALWAYS,
    });
    defer logger.deinit();

    // Event lifecycle manual
    logger.system(.INFO, "startup", "server starting on port {d}", .{9300});

    // Sambungkan ke server (logging access/conn/packet/session otomatis)
    var server = try zix.Tcp.Server.init(myHandler, .{
        .io     = process.io,
        .ip     = "127.0.0.1",
        .port   = 9300,
        .logger = &logger,
    });
    defer server.deinit();
    try server.run();
}
```

---

## Contoh

Semua contoh server jaringan menyertakan blok inisialisasi logger yang sudah dikomentari di bagian atas dan dapat diaktifkan tanpa perubahan kode:
- `examples/tcp_server.zig`
- `examples/fix_server.zig`
- `examples/udp_server.zig`
- `examples/uds_server.zig`
- `examples/http_basic.zig`
- `examples/grpc_location_server.zig` (logger sudah terhubung dan aktif secara default)
- `examples/grpc_multi_server.zig` (logger sudah terhubung dan aktif secara default)

---

###### end of hld-logger
