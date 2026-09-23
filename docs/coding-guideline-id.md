## Panduan Coding Zix

Cara kode ditulis di zix, diturunkan dari implementasi yang sudah ada. Ini adalah house style untuk `src/`, `tests/`, `examples/`, dan file build. Setiap aturan menyebut tempat nyata di tree sehingga konvensinya bisa dicek terhadap kode hidup, bukan sekadar diklaim.

Prinsip utama di balik setiap aturan di bawah: kode dibaca seperti kode yang sudah ada di sekitarnya. Cocokkan naming, kepadatan komentar, dan idiom file di sekitarnya sebelum memperkenalkan yang baru.

---

## 1. Layout source

Setiap subsystem adalah satu Zig file-as-struct namespace, di-export sekali dari `src/lib.zig`. Public type module sebuah subsystem adalah `PascalCase.zig` (`Tcp.zig`, `Udp.zig`, `Http1.zig`, `Channel.zig`), dan hanya me-re-export surface domain tersebut:

```zig
//! zix tcp

pub const Server = @import("server.zig").Server;
pub const Client = @import("client.zig").TcpClient;
pub const HandlerFn = @import("server.zig").HandlerFn;
pub const DispatchModel = @import("config.zig").DispatchModel;
pub const ServerConfig = @import("config.zig").TcpServerConfig;
```

> Beri setiap subsystem satu namespace type (`zix.Http1`, `zix.Grpc`, ...). Letakkan implementasi di file lowercase (`server.zig`, `config.zig`, `client.zig`) dan re-export hanya nama publik dari aggregator `PascalCase.zig`.

File implementasi lowercase membawa logic, file PascalCase adalah pintunya. `lib.zig` adalah satu-satunya root: ia mendaftar setiap subsystem (`pub const Tcp = @import("tcp/Tcp.zig");`) dan mengelompokkan helper lepasan di bawah namespace struct (`pub const utils = struct { ... }`).

> Sebuah subsystem menjadi publik hanya ketika ia punya baris di `src/lib.zig`. Tidak ada yang sampai ke `zix.*` secara tidak sengaja.

**Test discovery tidak rekursif.** Setiap file `src/` baru yang punya test WAJIB mendapat baris `std.testing.refAllDecls(@import("..."))` sendiri di blok unit-test `lib.zig`, dikelompokkan di bawah komentar engine-nya. Jika terlewat, test file itu diam-diam tidak pernah jalan padahal unit-test tetap exit 0.

```zig
test "zix: unit test" {
    // # zix.Http
    std.testing.refAllDecls(@import("tcp/http/router.zig"));
    std.testing.refAllDecls(@import("tcp/http/response.zig"));
    // ... satu baris per file yang punya test
}
```

> Setelah menambah file `src/` yang punya test, tambahkan baris `refAllDecls`-nya di `src/lib.zig` dalam perubahan yang sama. Tanpa pengecualian.

---

## 2. Naming

| Jenis | Aturan | Contoh |
| :- | :- | :- |
| File public type module | `PascalCase.zig` | `Http1.zig`, `Channel.zig` |
| File implementasi | `lowercase.zig` | `server.zig`, `config.zig` |
| Type / struct / enum | `PascalCase` | `TcpServerConfig`, `DispatchModel`, `RespSink` |
| Function | `camelCase` | `serveDispatch`, `frameRespond`, `uringUnavailableReason` |
| Field / variable / const binding | `snake_case` | `dispatch_model`, `max_recv_buf`, `worker_stack_size_bytes`(gunakan `_var` jika penggunaan dalam hal private) |
| Enum value domain / publik / config | `UPPER_CASE` | `ASYNC`, `EPOLL`, `URING` |
| Error | `error.<Product><Domain><Condition>` | `error.ZixPortNotConfigured`, `error.ZixHttp1ListenFailed` (lihat bagian 9) |
| Konstanta versi comptime | `UPPER_CASE` | `ZIG_SEMVER.MAJOR` |

Enum yang memodelkan pilihan publik, domain, atau config adalah `UPPER_CASE` (`DispatchModel`, content type, status, logger level). Pengecualian sempit yang dipertahankan di tree adalah enum internal control-flow (outcome gaya `keep_alive` / `close`) dan nilai protocol-mirroring (opcode WebSocket `text` / `binary` yang mencerminkan nama wire). Kalau ragu, pakai `UPPER_CASE`.

**Pakai nama pendek hanya ketika nama itu jelas mewakili tujuannya.** Ujinya adalah apakah pembaca yang belum pernah melihat file-nya paham, bukan jumlah karakter. Bentuk pendek yang jelas boleh: `conn`, `cfg`, `ctx`, `fd`, `io`, `str`. Nama yang tidak membawa tujuannya harus dieja: `handler` bukan `h`, `stream` bukan `s`, `worker` bukan `w`, `paths` bukan `p`, `cache` bukan `c`.

Nama satu karakter hanya untuk dua kasus: idiom loop dan count `i` / `n`, dan notasi kripto / aritmetika modular yang mengikuti rumusnya (`p`, `q`, `d`, `n`, `m` di `rsa.zig`, `montgomery.zig`, `ff.zig`). Parameter fungsi satu karakter selain itu tidak boleh, eja namanya.

> Beri nama untuk pembaca yang belum pernah melihat file-nya. Jika nama pendek butuh komentar agar dimengerti, itu nama yang salah.

---

## 3. Anatomi file

File mengikuti bentuk tetap dari atas ke bawah:

```zig
//! zix tcp config

const std = @import("std");
const Logger = @import("../logger/logger.zig").Logger;

// --------------------------------------------------------- //

/// Connection dispatch model. ...
pub const DispatchModel = enum(u8) { ... };

// --------------------------------------------------------- //

/// TCP stream server configuration. ...
pub const TcpServerConfig = struct { ... };

// --------------------------------------------------------- //
// --------------------------------------------------------- //

test "zix tcp: TcpServerConfig, default field values" { ... }
```

1. **Module doc comment** `//! zix <subsystem>` di baris 1, sebuah identitas lowercase singkat (`//! zix udp namespace aggregator`, `//! zix logger`). Satu pengecualian branding di `src/lib.zig` (`//! Zero sIX; 06;`) memang disengaja, jangan pernah diubah.
2. **Import** dengan `const std = @import("std");` lebih dulu, lalu import proyek.
3. **Comment spacer** `// --------------------------------------------------------- //` memisahkan deklarasi besar.
4. **Deklarasi**, masing-masing didahului doc comment-nya.
5. **Test** di bawah, dibuka dengan double comment spacer (dua baris spacer), satu-satunya tempat double spacer diizinkan.

> Pertahankan urutannya: header, import, decl yang dipisah spacer, lalu double-spacer dan test.

Comment spacer adalah aturan visual sekaligus separator. Ketika kode makin panjang, pengelompokan ini bisa jadi petunjuk bahwa bagian itu sudah terlalu besar dan kandidat untuk di-refactor demi maintainability. Satu spacer di depan diikuti baris label adalah bentuk yang diizinkan:

```zig
// --------------------------------------------------------- //
// Public surface re-exported from the dispatch helpers.

pub const HandlerFn = common.HandlerFn;
```

---

## 4. Doc comment

Deklarasi publik membawa doc comment `///`. Pakai set label dengan `:` setelah subjek, bukan bentuk verb, jangan pernah `;` sebagai pemisah prosa:

- `Note:` (title case, bukan `NOTE:`)
- `Param:` dengan entry `name - type (description)`, satu spasi di sekitar `-`, tanpa padding column-align
- `Return:` (bukan `Returns`), entry-nya baris outcome ber-bullet `-`, bukan baris type telanjang
- `Usage:` hanya ketika tidak-jelas bagi junior dev, dan sample kode dibungkus fence ```zig

```zig
/// THE ONLY SOURCE OF TRUTH for Zig SEMVER for zix source code.
///
/// Note:
/// - Do not create in other place!
pub const ZIG_SEMVER = struct { ... };
```

Field config masing-masing mendapat satu baris `///` yang menyatakan unit, default, dan arti 0 atau null:

```zig
/// Socket receive timeout per accepted connection in milliseconds (SO_RCVTIMEO). 0 = disabled.
recv_timeout_ms: u32 = 0,
/// Optional logger. When non-null, ... Caller owns. Must outlive the server.
logger: ?*Logger = null,
```

> Jangan beri padding dua-sampai-empat spasi setelah label `:`. Pengecualiannya adalah bullet `Note:` multi-baris yang baris lanjutannya rata di bawah teks. Tulis outcome `Return:` sebagai bullet `-`.

---

## 5. Formatting kode (baris kosong antar fase)

Jalankan `zig fmt .` sebelum commit apa pun. Di luar formatting, fase berbeda dalam body sebuah function dipisah satu baris kosong demi keterbacaan, bahkan tanpa komentar. Batas fasenya:

| Batas | Baris kosong sebelum |
| :- | :- |
| Guard / early return -> logic utama | statement non-guard pertama |
| Preparation / build -> send / write / commit | write atau commit pertama |
| Computation -> return | `return` (terutama struct literal multi-baris) |
| `defer x.deinit()` -> eksekusi utama | statement nyata pertama |

```zig
pub fn init(config: TcpServerConfig) !Self {
    if (config.port == 0) return error.ZixPortNotConfigured;

    return .{ .config = config };
}
```

```zig
var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
defer threaded.deinit();

const cfg = TcpServerConfig{ .io = threaded.io(), .ip = "127.0.0.1", .port = 9300 };
```

Pengecualian yang tidak butuh baris kosong: mutex guard (`defer unlock` tepat di atas critical section-nya) dan setup chain sefase (`defer free(x)` di atas loop yang memakai `x`).

> Setelah menulis body function, scan tiap baris untuk batas fase. Penutup `}` sebuah guard dan `if (...) return ...;` satu baris masing-masing diikuti baris kosong. Computation terakhir sebelum `return` didahului satu baris kosong.

---

## 6. Config: flat, tanpa builder

Setiap config adalah satu struct flat di `*/config.zig`. Tanpa sub-config bersarang, tanpa fluent builder. Field wajib (`io`, `ip`, `port`) tidak punya default dan diletakkan lebih dulu, setiap field lain membawa default eksplisit:

```zig
pub const TcpServerConfig = struct {
    io: std.Io,            // required, caller-provided, must outlive the server
    ip: []const u8,        // required
    port: u16,             // required, must be non-zero
    dispatch_model: DispatchModel,  // required
    kernel_backlog: u31 = 4096,
    max_recv_buf: usize = 4096,
    // ...
};
```

Tunable baru adalah field top-level baru, bukan method builder atau objek bersarang. Ketika sebuah field benar-benar cross-engine, ia ditambahkan ke seluruh config engine demi konsistensi. Field yang scope-nya satu kapabilitas (misal knob response-cache atau compression) ditambahkan hanya ke config engine yang punya kapabilitas itu, mencocokkan footprint yang ada alih-alih semua 8 config.

> Tambahkan field top-level. Beri default eksplisit dan satu baris doc yang menyatakan unit serta arti 0 / null.

---

## 7. Bentuk public type (lifecycle)

Sebuah server type dispesialisasi terhadap handler comptime-nya sehingga `run` tidak menerima argumen handler, mencocokkan bentuk `zix.Http1` / `zix.Grpc`. Setiap type memakai `const Self = @This();` dan lifecycle `init` / `deinit` / `run`:

```zig
fn TcpServerImpl(comptime handler: HandlerFn) type {
    return struct {
        config: TcpServerConfig,

        const Self = @This();

        pub fn init(config: TcpServerConfig) !Self {
            if (config.port == 0) return error.ZixPortNotConfigured;

            return .{ .config = config };
        }

        pub fn deinit(_: *Self) void {}

        /// Listen and serve. Selects the concurrency model from config.dispatch_model.
        pub fn run(self: *const Self) !void {
            return serveDispatch(self.config, handler);
        }
    };
}
```

- `init` memvalidasi field wajib lebih dulu dan mengembalikan error (`error.ZixPortNotConfigured`) alih-alih panic.
- `deinit` selalu ada bahkan ketika kosong (`pub fn deinit(_: *Self) void {}`), supaya caller bisa `defer server.deinit()` secara seragam.
- `io` selalu disediakan caller lewat config dan harus outlive server. Zix tidak memiliki event loop.

> Bake handler ke dalam type saat comptime. Validasi di `init`, bebaskan di `deinit`, layani di `run`. Pertahankan ketiganya bahkan ketika salah satunya no-op.

---

## 8. Dispatch model dan fallback platform

Concurrency adalah satu enum `DispatchModel` (`ASYNC`, `EPOLL`, `URING`), tiap model di file sendiri di bawah `dispatch/` (ADR-043), dipilih oleh `switch` tipis di server. `.ASYNC = 0` adalah zero value sehingga config zero-init mendapat default yang masuk akal, dan itu satu-satunya model yang tersedia di semua platform.

Dua ketidakcocokan berbeda, ditangani dengan dua cara berbeda (ADR-065):

- **Model yang tidak bisa dijalankan OS target** (`.EPOLL` / `.URING` di luar Linux) adalah config error. `run()` mencatat model mana yang ditolak lalu mengembalikan `error.ZixDispatchModelUnsupported`. Ia tidak pernah menurunkan model: pemanggil yang meminta loop per-core lalu diam-diam mendapat sesuatu yang lain tidak punya cara untuk tahu.
- **Model yang tidak bisa dipakai host saat ini** (io_uring tidak tersedia di Linux, umumnya cap `RLIMIT_MEMLOCK`) adalah capability gap. `.URING` melipat ke loop EPOLL dan mencatat alasannya, sehingga server tidak hilang tepat setelah bind.

Cek platform-nya satu predikat bersama, dikonsultasi sebelum server mem-bind apa pun:

```zig
if (!dispatch_support.isSupported(cfg.dispatch_model)) {
    common.logSystem(cfg, "{s} dispatch is Linux-only, use .ASYNC on this platform.", .{dispatch_support.rejectedName(cfg.dispatch_model)});

    return error.ZixDispatchModelUnsupported;
}
```

Arm `switch`-nya tetap memakai comptime OS gate juga, karena loop khusus Linux hanya bisa di-compile di Linux:

```zig
.EPOLL => if (comptime builtin.target.os.tag == .linux)
    epoll_model.runEpoll(cfg, handler)
else
    error.ZixDispatchModelUnsupported,
```

> Pilih comptime gating untuk fakta build-time (`comptime builtin.target.os.tag`), runtime probe hanya untuk fakta host-time (memlock, ketersediaan ring). Selalu catat alasannya. Jangan pernah biarkan server diam-diam hilang setelah bind, dan jangan pernah biarkan ia diam-diam menyajikan model yang tidak diminta pemanggil.

> Model yang zix pertahankan adalah model yang bisa zix rawat. `.POOL` dan `.MIXED` dilepas di ADR-065 tepat karena alasan itu, dan `.KQUEUE` / `.IOCP` tetap nama yang dipesan sampai masing-masing punya maintainer.

Guard yang sama berlaku untuk fast path Linux-only manapun yang ditambahkan murni demi performa, bukan cuma dispatch model (misalnya helper `wallClockNs` / `nowUs` yang memanggil `std.os.linux.clock_gettime` langsung, bukan lewat `std.posix.system`). Branch Linux (`comptime builtin.target.os.tag == .linux`, mencakup x86_64-linux dan aarch64-linux secara identik) adalah platform utama yang guarded: pertahankan agar tetap byte-identical dengan yang sudah terbukti, dan tambahkan tiap platform lain sebagai branch terpisah di sampingnya, jangan digabung jadi satu implementasi bersama.

---

## 9. Penanganan error

Sebuah error punya dua tugas, dan keduanya bukan tugas yang sama. Error VALUE adalah yang dipakai caller untuk bercabang. Log LINE adalah yang dipakai pembaca untuk debug. Nama saja tidak bisa menyebut file mana, port mana, atau field mana yang gagal, jadi aturan di bawah mencakup kedua sisi.

### 9.1 Naming

- Nama error ber-PascalCase pada `error.` dan dibaca `<Product><Domain><Condition>`: `error.ZixPortNotConfigured`, `error.ZixHttp1ListenFailed`, `error.ZixTlsCertFileNotFound`.
- Prefix product mengikuti siapa yang memiliki file-nya, bukan nama repository. `Zix` di tree engine, `Zixer` di bawah `src/zixer`, dan package standalone memakai namanya sendiri: `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`.
- Error std yang dilempar ulang apa adanya tetap memakai nama dari std: `OutOfMemory`, `WriteFailed`, `ReadFailed`, `EndOfStream`, `BrokenPipe`, `NoSpaceLeft`, `Overflow`, `Unexpected`. std meneruskan nama tanpa prefix lewat fungsi yang sama, jadi memberi prefix hanya pada raise site lokal akan menyisakan dua nama untuk satu kondisi di error set yang sama.
- Nama yang bisa diterima caller di luar package harus unik terhadap KONDISI-nya, bukan hanya terhadap subsystem: `error.ZixHttp1RequestLineTruncated`, bukan `error.ZixTruncated` yang dipakai bersama. Pakai ulang nama yang sudah ada hanya kalau kondisinya memang sama, bukan karena mirip.
- Parser sans-I/O boleh memakai nama sempit yang dipakai bersama di dalam error set-nya sendiri, karena value itu dipetakan ke domain error sebelum sampai ke pembaca.
- Jangan pernah menaruh `@src().file` atau `@src().line` di pesan. Keduanya menunjuk ke source zix, bukan ke config pembaca. Nama yang unik terhadap kondisinya sudah menunjukkan lokasi raise-nya.

### 9.2 Log line, error value, atau keduanya

Dua pertanyaan yang menentukan: apakah ada caller yang bisa menindaklanjuti, dan apakah pembaca sudah tahu subjeknya.

| Situasi | Yang dikeluarkan | Alasan |
| :- | :- | :- |
| Parser sans-I/O atau helper internal, caller sudah memegang input-nya | error value saja | caller sudah punya subjeknya, dan log line di sini akan menyala per paket |
| Tidak ada error union untuk dikembalikan: fungsi `void`, worker thread yang di-spawn, accept loop | log line saja | tidak ada yang bisa bercabang di atasnya, jadi baris itu SENDIRI adalah laporannya |
| Entry point publik yang memegang nilai hasil config pembaca: path, port, dir, url | keduanya | value-nya dipakai caller untuk bercabang, baris log-nya membawa subjek yang tidak bisa dibawa namanya |

```zig
const cert_pem = std.Io.Dir.cwd().readFileAlloc(io, config.cert_path, allocator, .limited(CERT_MAX_BYTES)) catch |err| {
    logSystem(config, .ERROR, "tls cert read failed: {s} ({})", .{ config.cert_path, err });

    return switch (err) {
        error.FileNotFound => error.ZixTlsCertFileNotFound,
        error.AccessDenied => error.ZixTlsCertFileUnreadable,
        else => error.ZixTlsCertFileReadFailed,
    };
};
```

Dua kesalahan yang dilarang aturan ini:

- Nge-log lalu menelan error di tempat fungsinya MASIH BISA mengembalikan error. Itu menyembunyikan kegagalan yang sebenarnya bisa ditangani caller.
- Mengembalikan nama telanjang di config boundary. `error.ZixTlsCertFileNotFound` sendirian tetap tidak menyebut file mana, jadi path-nya masuk ke baris log.

### 9.3 Bentuk

- Validasi input di boundary (`init`) dan kembalikan error lebih awal sebagai guard, dengan baris kosong sesudahnya.
- Pakai `errdefer` untuk membatalkan konstruksi parsial, `defer` untuk cleanup tanpa syarat.
- Jangan menggabung beberapa penyebab ke satu nama. Switch pada penyebabnya kalau penyebab itu menuntut perbaikan yang berbeda: not-found, permission denied, dan is-a-directory adalah tiga tindakan berbeda bagi pembaca.

> Kembalikan error bernama, jangan panic pada kondisi yang recoverable. Sebut kondisinya, sebut subjeknya di baris log, dan jangan biarkan pembaca menebak sisi mana yang hilang.

---

## 10. Memory dan allocator

Tidak ada satu allocator "yang dipilih". Allocator dipilih berdasarkan lifetime dan ownership data, dan arena adalah pengecualian, bukan default. Di tree yang hidup, general-purpose allocator yang thread-safe adalah yang dominan, arena hanya muncul di mana ada titik bulk-reset yang nyata, dan tabel hot-path yang terbatas punya allocator-nya sendiri.

| Allocator | Kapan | Di mana di tree |
| :- | :- | :- |
| `std.heap.smp_allocator` (general-purpose, thread-safe) | default untuk state long-lived dan shared: map koneksi dan stream, array thread worker, tabel HPACK, state per-connection. Pakai ini kapan pun data tidak punya titik reset tunggal yang bersih atau disentuh dari lebih dari satu thread | setiap `dispatch/` dan `core.zig` |
| `std.heap.ArenaAllocator` | hanya ketika lifetime-nya scope sejati dengan satu bulk reset dan satu owner: backing response-cache, arena per-connection `zix.Http` | `utils/response_cache.zig`, `tcp/http/server.zig` |
| Slab demand-paged (custom contiguous) | tabel koneksi hot-path yang terbatas, satu `mmap` diukir per worker, tanpa heap call per-accept, slot kosong hanyalah `buf.len == 0` | `multiplexers/slab.zig` |
| `std.heap.page_allocator` | buffer page-granular yang diserahkan ke kernel (provided-buffer ring) | `tcp/http1/dispatch/uring.zig` |
| `std.testing.allocator` | test saja, sekaligus menangkap leak | setiap blok test |

Arena adalah pilihan yang salah, pakai `smp_allocator`, ketika salah satu ini berlaku:

- Data di-share antar worker thread. Arena tidak thread-safe.
- Lifetime tidak punya titik reset tunggal, misal sebuah connection atau stream yang hidup tak terbatas dan membebaskan objek satu per satu (idle-conn pool me-reuse, bukan bulk-reset).
- Objek direklamasi satu per satu alih-alih sekaligus.

Jadi "prefer arena if applicable" bergantung pada "if applicable": di server shared-nothing, long-lived-connection, thread-per-core, itu adalah minoritas dari situs alokasi, itulah kenapa `smp_allocator` mendominasi tree dan slab membawa hot path.

Type yang memiliki buffer membebaskan di `deinit`. Apa pun yang disediakan caller (`io`, `logger`) dipinjam, didokumentasikan sebagai "caller owns, must outlive", dan tidak pernah dibebaskan oleh zix.

> Pilih allocator dari lifetime dan ownership data. Default ke `smp_allocator` untuk state shared atau long-lived, raih arena hanya pada scope bulk-reset single-owner sejati, dan pakai slab untuk tabel hot-path terbatas. Jangan memaksakan arena di mana lifetime-nya tidak cocok.

---

## 11. Test

Test berada di bawah file yang dicakupnya (Zig menemukannya lewat `refAllDecls`). Nama test membawa prefix domain dari surface yang diuji: `test "zix <domain>: <subject>, <case>"` (`zix tcp:`, `zix http1:`, `zix grpc:`, `zix tls:`, `zix channel:`), dan test driver memakai nama driver-nya (`postgrez auth:`, `rediz protocol:`):

```zig
test "zix tcp: TcpServerConfig, default field values" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();

    const cfg = TcpServerConfig{ .io = threaded.io(), .ip = "127.0.0.1", .port = 9300 };
    try std.testing.expectEqualStrings("127.0.0.1", cfg.ip);
    try std.testing.expectEqual(@as(u16, 9300), cfg.port);
}
```

Setelah mengimplementasikan function, field, atau behavior baru, tambahkan test yang mencakupnya dalam perubahan yang sama (unit, behaviour, edge, dan integration bila perlu). Sebuah file belum selesai, dan file berikutnya belum dimulai, sampai kode baru punya test.

> Letakkan test berdampingan dengan kodenya. Beri nama `zix <domain>: subject, case`. Behavior baru dikirim bersama test-nya, bukan menyusul.

Kalau sebuah test cuma relevan di satu platform (contohnya dispatch model EPOLL/URING yang Linux-only), bungkus skip-nya dalam block eksplisit, bukan satu baris guard polos, supaya pemisahan platform-nya kebaca sebagai dua region yang beda. Block itu menyebut alasannya lewat `std.log.info` lalu return biasa. Jangan pakai `return error.SkipZigTest`: test-nya dilaporkan di luar hitungan pass, dan itu kebaca sebagai lubang di run, bukan keputusan yang memang dibuat kodenya.

```zig
test "zix grpc: dual listener, EPOLL serves h2c on port" {
    if (builtin.os.tag != .linux) {
        // windows / other-platform region: EPOLL/URING dispatch models are
        // Linux-only, nothing is spawned here, nothing to retry or clean up.
        std.log.info("EPOLL/URING is Linux-only, test skipped", .{});
        return;
    }

    // linux region: real server + retry + timeout
    ...
}
```

Kalau region linux-nya spawn server di background buat ditest, retry connect-nya pakai jumlah percobaan tetap (batas atas yang pasti, bukan loop tanpa batas). Cleanup/shutdown eksplisit buat server itu cuma ditambahkan kalau engine-nya memang punya jalur stop: jangan pura-pura cleanup thread yang memang tidak pernah bisa return.

---

## 12. Komentar dan prosa (di kode dan dokumen)

Ini berlaku untuk `//`, `///`, `//!`, dan setiap dokumen markdown:

- Satu `-` boleh sebagai definer setelah subjek `:` atau di dalam `()` (`Support: en - English, id - Bahasa`), dan di entry param `name - type`. Tidak boleh sebagai pemisah klausa yang mengambang bebas.
- Diagram pakai mermaid, bukan text-art.
- Directory tree pakai ASCII polos dengan connector `|___` dan entry direktori berprefix `/`, jangan pernah box-drawing Unicode.

> Sebelum beranjak dari komentar atau blok doc mana pun, scan tiap kalimat untuk em-dash atau `;` yang dipakai sebagai pemisah lalu restrukturkan.

---

## 13. Gating versi Zig

Zix mendukung dua versi Zig lewat satu comptime source of truth, `zix.ZIG_SEMVER` (ADR-044). Branch spesifik-versi di-gate saat comptime sehingga hanya branch aktif yang dikompilasi, yang tidak aktif tidak pernah di-type-check masuk ke binary:

```zig
if (comptime ZIG_SEMVER.MINOR == 16) {
    // 0.16 std.Io path
} else {
    // 0.17 std.Io path
}
```

`ZIG_SEMVER` dideklarasikan sekali di `src/lib.zig` dan tidak di tempat lain. Build script menyimpan copy build-only-nya sendiri.

> Gate perbedaan versi saat comptime terhadap `ZIG_SEMVER`. Jangan branch versi saat runtime, dan jangan deklarasikan ulang konstantanya.

---

## 14. Commit dan dokumentasi

- Jalankan `zig fmt .` sebelum menyusun pesan commit.
- Satu commit per file. File yang berkaitan erat dan tak terpisahkan dalam satu direktori baru boleh berbagi satu commit.
- Dokumentasi datang berpasangan `-en.md` / `-id.md`. Ketika menerjemahkan ke Bahasa Indonesia, pertahankan istilah teknis Inggris di mana pun terjemahan paksa akan menyimpang dari makna baku (shared-nothing, slab, dispatch, hot path, throughput, comptime, dan sejenisnya).

> Commit per file dengan pesan bermakna setelah `zig fmt .`. Jaga dokumen tetap dwibahasa, dan pertahankan istilah teknis dalam Inggris di dalam terjemahan lainnya.

---

## 15. Baca/tulis file di unix dan Windows

Setiap operasi file lewat `std.Io.Dir.cwd()` (`createFile`, `readFileAlloc`, `deleteFile`). Kalau sub_path-nya absolute, dir handle-nya diabaikan, jadi satu bentuk panggilan ini melayani path relative maupun absolute. Jangan pakai varian `*Absolute` (`deleteFileAbsolute`, `openFileAbsolute`): varian itu cuma menerima path absolute, yang memaksa call site pecah jadi dua bentuk begitu satu platform butuh path relative.

Jangan pernah hardcode path absolute gaya unix (`/tmp/...`) di kode yang bakal di-open, ditulis, atau di-bind oleh Windows. Windows me-resolve `/tmp/...` terhadap drive aktif (contohnya `D:\tmp\...`), dan kalau direktori itu tidak ada, operasinya gagal dengan NTSTATUS OBJECT_PATH_NOT_FOUND (muncul sebagai `error.FileNotFound` di operasi file, atau `error.Unexpected` di bind socket). Idiomnya pakai path cwd-relative, tanpa branch platform karena bentuk ini me-resolve sama di mana pun:

```zig
const cert_path = "tmp/zix_rsa_integration_cert.pem";

try writeFile(io, cert_path, cert_pem);
defer std.Io.Dir.cwd().deleteFile(io, cert_path) catch {};
```

Aturan yang sama berlaku untuk path unix domain socket yang diberikan ke `std.Io.net.UnixAddress`: Windows mendukung AF_UNIX, tapi bind-nya me-resolve path persis seperti open file, jadi path socket `/tmp/...` gagal juga di sana. Ini juga berarti UDS server harus membersihkan socket file-nya lewat `cwd().deleteFile`, jangan `deleteFileAbsolute`, karena path relative bakal gagal kena assert absolute-path milik fungsi itu sendiri.

Path production mengikuti pemanggil: `Tls.Context.init` membaca `cert_path` / `key_path` lewat `cwd().readFileAlloc`, jadi config boleh membawa bentuk mana pun dan bentuk yang tepat adalah urusan deployment, bukan urusan zix.

> Arahkan setiap operasi file lewat `std.Io.Dir.cwd()` dan biarkan path-nya yang menentukan relative vs absolute. Jangan pernah hardcode `/tmp` untuk apa pun yang disentuh Windows: pakai path cwd-relative di mana-mana.
