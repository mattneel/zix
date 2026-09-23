# HLD: zix.Fix

Server protokol sesi FIX 4.x. Framing tag=value dengan delimiter SOH (0x01). Dibangun seluruhnya dalam Zig: tanpa C FFI, tanpa library eksternal.

---

## Status

Sudah diimplementasikan. Lihat ADR-024 untuk alasan desain.

---

## Tujuan

- Eksplisit bukan implisit: pola konfigurasi dan dispatch model yang sama dengan `zix.Tcp`.
- Framing berbasis delimiter SOH: tanpa length prefix, deteksi batas pesan berbasis delimiter.
- Lapisan sesi sudah terintegrasi: Logon / Logout / Heartbeat / TestRequest ditangani secara otomatis, semua pesan lainnya di-echo.
- Tidak ada heap allocation di `serveConn`: stack buffer digunakan di seluruh implementasi.
- Dispatch ASYNC, EPOLL, dan URING. Wajib tanpa default: ASYNC cocok untuk sesi FIX berumur panjang dan satu-satunya model portabel. EPOLL dan URING menjalankan worker per-core shared-nothing di Linux, dan `run()` menolak keduanya di luar Linux dengan `error.ZixDispatchModelUnsupported` (ADR-065).
- `io: std.Io` di dalam konfigurasi (tidak diteruskan ke `run()`).

---

## Struktur Berkas

```
src/tcp/fix/
    Fix.zig      // namespace aggregator
    core.zig     // parsing, building, checksum, serveConn, MsgType, FixRequest, FixResponse, FixContext, HandlerFn, FixRoute
    config.zig   // FixServerConfig, FixClientConfig
    server.zig   // FixServer: run() switch tipis di atas dispatch/ (ASYNC, EPOLL, URING)
    dispatch/    // berkas per-model: async.zig, epoll.zig, uring.zig, common.zig
    router.zig   // comptime FixRouter
    client.zig   // FixClient
```

Ekspor dari `src/lib.zig`:
```zig
pub const Fix = @import("tcp/fix/Fix.zig");
// zix.Fix.Server, zix.Fix.ServerConfig, zix.Fix.Client, zix.Fix.ClientConfig, zix.Fix.serveConn, ...
```

---

## API Publik

| Simbol | Tipe | Deskripsi |
| :- | :- | :- |
| `zix.Fix.Server` | struct | `init(handler, config)` / `deinit()` / `run()` (ADR-063: `handler: ?HandlerFn`, dibangun via `Router(&routes).dispatch`; `null` mempertahankan mode echo) |
| `zix.Fix.ServerConfig` | struct | Lihat Field Konfigurasi Server di bawah |
| `zix.Fix.ServeOpts` | struct | `{ logger, default_heartbeat_secs, heartbeat_timeout_ms, conn_timeout_ms, handler_timeout_ms, handler }`: opsi untuk `serveConn` |
| `zix.Fix.Client` | struct | `connect(config, io)` / `deinit(io)` / `logon(io, heart_bt_int)` / `logout(io)` / `sendMessage(io, msg_type, extra)` / `recvMessage(io)` |
| `zix.Fix.ClientConfig` | struct | Lihat Field Konfigurasi Client di bawah |
| `zix.Fix.DispatchModel` | enum(u8) | Re-export dari `zix.Tcp.DispatchModel` |
| `zix.Fix.Tag` | enum(u16) | Enum nonexhaustive dari nomor tag FIX 4.x standar. Gunakan `@enumFromInt` untuk tag kustom yang tidak terdaftar |
| `zix.Fix.MsgType` | struct | Namespace konstanta string compile-time untuk nilai MsgType (tag 35) FIX. Lihat bagian Konstanta MsgType |
| `zix.Fix.HandlerFn` | tipe | `*const fn (req: *Request, res: *Response, ctx: *Context) anyerror!void` (trio ADR-063): handler pesan aplikasi |
| `zix.Fix.Route` | struct | `{ msg_type: []const u8, handler: HandlerFn, timeout_ms: u32 = 0 }`: satu rute pesan aplikasi |
| `zix.Fix.Request` | struct | `{ fields: []const Field }`, `getField(tag) ?[]const u8`: view zero-copy atas pesan yang diterima |
| `zix.Fix.Response` | struct | `sendMessage(msg_type, fields)`: builder atas `buildMessage` plus penulisan ber-frame SOH, independen dari `Context` |
| `zix.Fix.Context` | struct | Konteks per-koneksi yang diteruskan ke setiap handler. Field: `sender_comp_id`, `target_comp_id`, `deadline_ns`. Method: `withTimeout` / `setTimeout` / `withDeadline` / `isExpired` / `timedOut` |
| `zix.Fix.Router(routes)` | comptime fn | Menghasilkan tipe dispatch comptime dengan `dispatch(req, res, ctx) anyerror!void`, cocok persis dengan `HandlerFn` |
| `zix.Fix.wallClockNs` | fn | `std.os.linux.clock_gettime(.REALTIME)` menghasilkan u64 nanosecond (sama dengan `zix.Grpc.wallClockNs`) |
| `zix.Fix.Field` | struct | `{ tag: Tag, value: []const u8 }`: zero-copy slice ke receive buffer |
| `zix.Fix.BuildField` | struct | `{ tag: Tag, value: []const u8 }`: input untuk `buildMessage` |
| `zix.Fix.SOH` | u8 | `0x01`: delimiter field |
| `zix.Fix.VERSION` | []const u8 | `"FIX.4.2"` |
| `zix.Fix.MAX_FIELDS` | usize | 64: jumlah field maksimum yang diparse per pesan |
| `zix.Fix.MAX_MSG_SIZE` | usize | 8192: byte pesan maksimum |
| `zix.Fix.findMessageEnd` | fn | Memindai buf untuk akhir pesan FIX pertama yang lengkap, mengembalikan indeks setelah SOH terakhir atau null |
| `zix.Fix.parseFields` | fn | Mengurai byte mentah menjadi `[]Field` (zero-copy slice ke buf) |
| `zix.Fix.getField` | fn | Mengembalikan value field pertama dengan `Tag` yang diberikan, atau null |
| `zix.Fix.computeChecksum` | fn | Jumlah semua byte mod 256 |
| `zix.Fix.verifyChecksum` | fn | Mengembalikan true jika checksum tag-10 sesuai dengan nilai yang dihitung |
| `zix.Fix.buildMessage` | fn | Membangun pesan FIX lengkap ke dalam output buffer yang disediakan pemanggil |
| `zix.Fix.serveConn` | fn | Handler sesi: `serveConn(stream, io, comp_id, opts)` (membaca pesan, mendispatch Logon/Logout/Heartbeat, merutekan pesan aplikasi) |

---

## Field Konfigurasi Server

| Field | Default | Deskripsi |
| :- | :- | :- |
| `io` | wajib | Backend Io. Disediakan pemanggil, harus melampaui masa hidup server |
| `ip` | wajib | Alamat bind |
| `port` | wajib | Port bind. Harus bukan nol |
| `comp_id` | wajib | SenderCompID server (tag 49) |
| `dispatch_model` | wajib, tanpa default | ASYNC, EPOLL, atau URING (EPOLL dan URING Linux-only: epoll native / io_uring, ditolak di luar Linux dengan error.ZixDispatchModelUnsupported) |
| `kernel_backlog` | 1024 | TCP listen backlog |
| `workers` | 0 (cpu_count) | Jumlah accept thread. Diabaikan oleh ASYNC |
| `worker_stack_size_bytes` | 512 KiB | Stack worker thread untuk handler EPOLL / URING. Demand-paged, biaya kecil sampai kedalamannya terpakai |
| `reuseport_cbpf` | false | Steering SO_ATTACH_REUSEPORT_CBPF (EPOLL / URING): koneksi baru masuk ke worker pada CPU penerima, bukan hash 4-tuple. Silent no-op pada kernel pre-4.5 |
| `uring_send_buf_size` | 64 KiB | Buffer send per-koneksi untuk URING. Tanpa efek pada dispatch model lain |
| `uring_max_conns_per_worker` | 65536 | Maksimum koneksi konkuren yang dilacak satu worker URING (slab fd-indexed). Koneksi melewati cap ditolak |
| `default_heartbeat_secs` | 30 | HeartBtInt default (detik) yang di-echo pada respons Logon saat client melewatkan tag 108 |
| `logger` | null | Logger opsional untuk event siklus hidup dan sesi per-pesan |
| `heartbeat_timeout_ms` | 0 | Heartbeat timeout dalam ms. 0 = dinonaktifkan. Ketika bernilai non-zero: setelah interval ini tanpa pesan masuk, TestRequest (35=1) dikirim. Jika tidak ada respons yang datang dalam interval berikutnya, Logout (35=5) dikirim dan koneksi ditutup. Hanya berlaku setelah Logon, sebelum Logon, timeout menutup koneksi secara diam-diam. |
| `conn_timeout_ms` | 0 | Idle connection timeout dalam ms. 0 = dinonaktifkan. Hanya berlaku saat `heartbeat_timeout_ms` bernilai 0: jika tidak ada pesan yang datang dalam interval ini, koneksi ditutup, tanpa TestRequest dance, langsung tutup. |
| `handler_timeout_ms` | 0 | Batas waktu pemrosesan handler server-wide dalam ms. 0 = tanpa batas. Diperketat per-rute oleh `Route.timeout_ms`. Mengatur `Context.deadline_ns` sebelum dispatch. |

---

## Field Konfigurasi Client

| Field | Deskripsi |
| :- | :- |
| `ip` | wajib, alamat server |
| `port` | wajib, port server. Harus bukan nol |
| `comp_id` | wajib, SenderCompID client ini (tag 49) |
| `target_comp_id` | wajib, TargetCompID server (tag 56) |

---

## Ikhtisar Protokol

FIX (Financial Information eXchange) 4.x menggunakan SOH (0x01) sebagai delimiter field. Setiap field berformat `tag=value\x01`. Pesan lengkap dimulai dari tag-8 (BeginString) dan diakhiri dengan tag-10 (Checksum) diikuti SOH terakhir:

```
8=FIX.4.2\x019=26\x0135=A\x0149=CLIENT\x0156=SERVER\x0134=1\x0198=0\x01108=30\x0110=NNN\x01
```

Tag standar utama:

| Tag | Nama | Peran |
| :- | :- | :- |
| 8 | BeginString | Selalu `FIX.4.2` dalam implementasi ini |
| 9 | BodyLength | Jumlah byte dari tag-35 hingga akhir nilai tag-10 (sebelum SOH terakhir) |
| 35 | MsgType | `A`=Logon, `5`=Logout, `0`=Heartbeat, `1`=TestRequest, `D`=NewOrderSingle, dll. |
| 49 | SenderCompID | Identitas pihak pengirim |
| 56 | TargetCompID | Identitas pihak penerima |
| 34 | MsgSeqNum | Nomor urut per sesi (dimulai dari 1) |
| 10 | Checksum | Jumlah semua byte pesan mod 256, diformat sebagai desimal 3 digit |

---

## Enum Tag

Nomor tag FIX dikirimkan sebagai integer ASCII di jaringan (misalnya `35`, `49`, `108`). Membaca literal numerik dalam kode mengharuskan menghafal spesifikasi FIX. `zix.Fix.Tag` adalah `enum(u16)` nonexhaustive yang memetakan nomor tag standar ke konstanta bernama, format jaringan tidak berubah.

```zig
pub const Tag = enum(u16) {
    MsgType      = 35,
    SenderCompID = 49,
    TargetCompID = 56,
    MsgSeqNum    = 34,
    HeartBtInt   = 108,
    // ... 55 tags total
    _,  // catch-all: any u16 is a valid Tag value
};
```

### Tag yang dicakup

Lapisan sesi: `BeginString` (8), `BodyLength` (9), `CheckSum` (10), `MsgSeqNum` (34), `MsgType` (35), `SenderCompID` (49), `SenderSubID` (50), `SendingTime` (52), `TargetCompID` (56), `TargetSubID` (57), `PossDupFlag` (43), `PossResend` (97), `EncryptMethod` (98), `HeartBtInt` (108), `TestReqID` (112), `OrigSendingTime` (122), `GapFillFlag` (123), `LastMsgSeqNumProcessed` (369).

Order dan eksekusi: `Account` (1), `AvgPx` (6), `ClOrdID` (11), `CumQty` (14), `Currency` (15), `ExecID` (17), `ExecTransType` (20), `HandlInst` (21), `LastPx` (31), `LastShares` (32), `OrderID` (37), `OrderQty` (38), `OrdStatus` (39), `OrdType` (40), `OrigClOrdID` (41), `Price` (44), `Side` (54), `StopPx` (99), `TimeInForce` (59), `TransactTime` (60), `ExecType` (150), `LeavesQty` (151).

Instrumen: `SecurityID` (48), `SecurityIDSource` (22), `Symbol` (55), `Text` (58), `ExDestination` (100), `SecurityType` (167), `MaturityMonthYear` (200), `SecurityExchange` (207), `TradeDate` (75).

Jumlah repeating group: `NoRelatedSym` (146), `NoMDEntries` (268), `NoPartyIDs` (453), `NoUnderlyings` (539), `NoLegs` (555).

### Cara penggunaan

Membaca field berdasarkan nama:

```zig
const msgtype  = zix.Fix.getField(fslice, .MsgType)      orelse return;
const sender   = zix.Fix.getField(fslice, .SenderCompID) orelse "";
const seq_str  = zix.Fix.getField(fslice, .MsgSeqNum)    orelse "0";
```

Membangun pesan dengan field bernama:

```zig
try client.sendMessage(io, "D", &[_]zix.Fix.BuildField{
    .{ .tag = .ClOrdID,  .value = "ORD-001" },
    .{ .tag = .Symbol,   .value = "AAPL" },
    .{ .tag = .Side,     .value = "1" },
    .{ .tag = .OrderQty, .value = "100" },
    .{ .tag = .OrdType,  .value = "2" },
    .{ .tag = .Price,    .value = "185.50" },
});
```

### Tag kustom dan ekstensi

Enum bersifat nonexhaustive (`_`). Semua `u16` adalah nilai `Tag` yang valid: gunakan `@enumFromInt` untuk tag yang tidak terdaftar:

```zig
const my_tag: zix.Fix.Tag = @enumFromInt(9999);
const extra = [_]zix.Fix.BuildField{
    .{ .tag = @enumFromInt(9001), .value = "custom-data" },
};
```

`parseFields` mengonversi integer jaringan ke `Tag` melalui `@enumFromInt` secara otomatis, tidak diperlukan konversi saat membaca field yang diterima.

### Pertimbangan

- Tipe backing adalah `u16`, sesuai dengan field `Field.tag` dan `BuildField.tag`. Tidak ada biaya runtime dibanding menyimpan `u16` mentah.
- Tag yang tidak dikenal yang diterima dari jaringan (`parseFields`) menjadi nilai enum nonexhaustive: keduanya dibandingkan dengan benar menggunakan `==` dan dicetak sebagai nilai integernya.
- Enum tidak memvalidasi nilai tag atau memberlakukan pembatasan versi FIX. Semua validasi semantik tetap menjadi tanggung jawab aplikasi.
- `getField` menerima `Tag`: meneruskan literal integer mentah secara langsung tidak lagi dapat dikompilasi. Gunakan konstanta bernama atau `@enumFromInt(n)`.

---

## Lapisan Sesi

`serveConn` mengimplementasikan lapisan sesi FIX secara otomatis. Tidak ada handler callback: semua logika sesi ada di dalam `serveConn`:

| MsgType (tag 35) | Tindakan server |
| :- | :- |
| `A` (Logon) | Merespons dengan Logon (`A`), CompID dibalik, seq=1 |
| `5` (Logout) | Merespons dengan Logout (`5`), kemudian menutup koneksi |
| `0` (Heartbeat) | Merespons dengan Heartbeat (`0`) |
| `1` (TestRequest) | Merespons dengan Heartbeat (`0`) |
| lainnya (routes non-kosong) | Dispatch ke `Route.handler` yang sesuai via `FixRouter`. Jika tidak ada rute yang cocok, pesan diabaikan |
| lainnya (routes kosong) | Echo pesan kembali tanpa perubahan (mode echo, backward-compatible) |

Checksum yang salah menutup koneksi tanpa memberikan respons.

---

## Konstanta MsgType

Nilai MsgType FIX (tag 35) adalah string ASCII, bukan integer. `zix.Fix.MsgType` adalah namespace struct berisi 44 konstanta string compile-time yang mencakup FIX 4.0-4.4. Gunakan konstanta ini sebagai pengganti string literal mentah untuk menghindari kesalahan ketik.

```zig
// Sesi
zix.Fix.MsgType.Heartbeat                   // "0"
zix.Fix.MsgType.TestRequest                 // "1"
zix.Fix.MsgType.ResendRequest               // "2"
zix.Fix.MsgType.Reject                      // "3"
zix.Fix.MsgType.SequenceReset               // "4"
zix.Fix.MsgType.Logout                      // "5"
zix.Fix.MsgType.Logon                       // "A"

// Aplikasi (satu karakter)
zix.Fix.MsgType.ExecutionReport             // "8"
zix.Fix.MsgType.OrderCancelReject           // "9"
zix.Fix.MsgType.IOIAcknowledgement          // "6"
zix.Fix.MsgType.IOI                         // "C"
zix.Fix.MsgType.NewOrderSingle              // "D"
zix.Fix.MsgType.NewOrderList                // "E"
zix.Fix.MsgType.OrderCancelRequest          // "F"
zix.Fix.MsgType.OrderCancelReplaceRequest   // "G"
zix.Fix.MsgType.OrderStatusRequest          // "H"
zix.Fix.MsgType.Allocation                  // "J"
// ... dan lainnya (Quote, MarketData*, Security*, TradingSession*, dll.)

// Aplikasi (dua karakter, FIX 4.3-4.4)
zix.Fix.MsgType.TradeCaptureReport          // "AE"
zix.Fix.MsgType.OrderMassStatusRequest      // "AF"
```

Penggunaan dalam tabel rute dan `sendMessage`:

```zig
&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle,    .handler = handleNewOrder },
    .{ .msg_type = zix.Fix.MsgType.OrderCancelRequest, .handler = handleCancel },
},

// di dalam handler:
res.sendMessage(zix.Fix.MsgType.ExecutionReport, &[_]zix.Fix.BuildField{ ... });

// di client:
try client.sendMessage(io, zix.Fix.MsgType.NewOrderSingle, &order_fields);
```

---

## Router dan Dispatch Pesan Aplikasi

Route dibungkus dalam `Fix.Router(&routes)` dan `.dispatch`-nya diteruskan ke `Fix.Server.init()` (ADR-063, mencerminkan engine lainnya). Pesan sesi (Logon/Logout/Heartbeat/TestRequest) selalu ditangani secara internal oleh `serveConn`. Hanya pesan aplikasi (lainnya) yang mencapai router.

```zig
const router = zix.Fix.Router(&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle,    .handler = handleNewOrder,   .timeout_ms = 500 },
    .{ .msg_type = zix.Fix.MsgType.OrderCancelRequest, .handler = handleCancel,     .timeout_ms = 500 },
});

var server = try zix.Fix.Server.init(
    router.dispatch,
    .{
        .io                    = process.io,
        .ip                    = "0.0.0.0",
        .port                  = 9500,
        .comp_id               = "BROKER",
        .dispatch_model        = .ASYNC,
        .conn_timeout_ms       = 60_000,
        .handler_timeout_ms    = 200,
    },
);
```

`Server.init` menerima `handler: ?HandlerFn`. Memberi `null` mengaktifkan mode echo (backward-compatible: semua pesan non-sesi di-echo).

### HandlerFn

```zig
fn handleNewOrder(req: *zix.Fix.Request, res: *zix.Fix.Response, ctx: *zix.Fix.Context) !void {
    if (ctx.isExpired()) return;
    const symbol = req.getField(.Symbol) orelse return;
    res.sendMessage(zix.Fix.MsgType.ExecutionReport, &[_]zix.Fix.BuildField{
        .{ .tag = .Symbol,    .value = symbol },
        .{ .tag = .OrdStatus, .value = "0" },
    });
}
```

### FixRequest / FixResponse / FixContext (trio ADR-063)

| Tipe | Anggota |
| :- | :- |
| `FixRequest` | `fields: []const Field`, `getField(tag) ?[]const u8` (view zero-copy atas field pesan yang diterima) |
| `FixResponse` | `sendMessage(msg_type, fields)`: bangun dan kirim respons FIX pada koneksi ini (CompID dibalik), independen dari `FixContext` sehingga handler bisa mengirim dari closure yang di-capture setelah context keluar dari scope |
| `FixContext` | `sender_comp_id`, `target_comp_id` (identitas sesi), `deadline_ns: ?u64` (deadline absolut, nanosecond CLOCK_REALTIME, paling ketat antara `handler_timeout_ms` / `Route.timeout_ms`, null = tanpa deadline), `withTimeout` / `setTimeout` / `withDeadline` / `isExpired()` / `timedOut()`, `io`, dan `allocator` stack-arena (`FixedBufferAllocator`, tanpa pemanggilan heap) |

### Override Deadline

```zig
ctx.deadline_ns = zix.Fix.wallClockNs() + 2 * std.time.ns_per_s; // perpanjang ke 2 detik
ctx.deadline_ns = null;                                            // nonaktifkan
// atau lewat helper: ctx.setTimeout(2_000); ctx.withDeadline(deadline_ns);
```

### FixRouter (comptime)

`FixRouter(routes)` menghasilkan fungsi `dispatch` comptime yang cocok persis dengan `HandlerFn`, di-unroll menggunakan `inline for` saat kompilasi, tanpa overhead runtime.

```zig
const r = zix.Fix.Router(&[_]zix.Fix.Route{
    .{ .msg_type = zix.Fix.MsgType.NewOrderSingle, .handler = handleNewOrder },
});
try r.dispatch(req, res, ctx);
```

`dispatch` membaca tipe pesan dari `req.getField(.MsgType)` sendiri, mencocokkannya dengan tabel route, memperketat `ctx.deadline_ns` dengan `Route.timeout_ms` bila diset, lalu memanggil `route.handler(req, res, ctx)`. Berikan `router.dispatch` ke `Server.init` untuk jalur server normal, panggil langsung hanya saat menjalankan `serveConn` secara manual. Memberi `null` ke `Server.init` melewati router sepenuhnya: semua pesan aplikasi di-echo.

---

## Kebijakan Error Handler

Handler mengembalikan `anyerror!void`, dan `res.sendMessage` mengembalikan error union, bukan `void`, jadi langkah build maupun tulis soketnya sama-sama bisa dilaporkan.

| Kondisi | Yang dikirim engine |
| :- | :- |
| handler mengembalikan error tanpa mengirim apa pun | Reject (`35=3`) dengan `RefSeqNum` (tag 45) dari pesan yang gagal dan `Text` (tag 58) `handler error` |
| handler mengembalikan error setelah mengirim pesan | tidak ada, pesan yang sudah dikirimnya berlaku sebagai jawaban |
| handler menangkap sendiri error itu | tidak ada, jawabannya milik handler |

`res.sendMessage` melaporkan dua kegagalan yang dulu tidak bisa dilihat handler:

- `error.ZixFixMessageTooLarge` saat pesan hasil build tidak muat di `MAX_MSG_SIZE`.
- `error.BrokenPipe` saat counterparty sudah tiada.

`try` adalah cara mencapai Reject di atas. Handler yang ingin menjawab dengan cara lain memakai catch:

```zig
fn handleNewOrder(req: *zix.Fix.Request, res: *zix.Fix.Response, ctx: *zix.Fix.Context) anyerror!void {
    // try: kegagalan di sini dijawab dengan Reject yang membawa RefSeqNum
    const filled = try matchOrder(req);

    // catch: jawabannya milik handler, engine tidak menambahkan apa pun
    res.sendMessage(zix.Fix.MsgType.ExecutionReport, filled.fields) catch {
        try res.sendMessage(zix.Fix.MsgType.OrderCancelReject, filled.reject_fields);
    };
}
```

Reject tidak pernah dikirim di atas pesan yang sudah dikirim handler: bagi counterparty itu terbaca sebagai dua jawaban yang saling bertentangan untuk satu pesan.

## Format Frame

FIX menggunakan framing berbasis delimiter (SOH = 0x01), bukan framing length-prefix. Receive loop mengumpulkan byte melalui `takeByte` sampai `findMessageEnd` mendeteksi pesan yang lengkap. Cara ini menghindari deadlock `readSliceShort` yang terjadi ketika buffer besar diteruskan tetapi pesan lebih pendek dari kapasitas buffer (deadlock buffer-lebih-besar-dari-pesan).

```
recv_buf:  [complete message][leftover bytes][free]
                                      ^
                                      shifted after each message
```

---

## Model Dispatch

Sama seperti tiga model di `zix.Http.Server`. Field-nya wajib tanpa default. ASYNC cocok untuk sesi FIX berumur panjang dan satu-satunya model portabel:

| Model | Accept thread | Catatan |
| :- | :- | :- |
| `.ASYNC` | 1 | Sesi berumur panjang, deployment FIX standar |
| `.EPOLL` | cpu_count (Linux-only) | Shared-nothing: satu SO_REUSEPORT listener dan satu epoll instance per worker. Ditolak di luar Linux. |
| `.URING` | cpu_count (Linux-only) | Worker io_uring shared-nothing yang menjalankan session processor resumable (`core.processFixRing`) per batch readable (ADR-037). Ditolak di luar Linux. |

---

## Siklus Hidup Server

```
Fix.Server.init(handler, config): validates port != 0, io taken from config
    -> .run(): dispatches via dispatch_model, blocks until error
Fix.Server.deinit(): no-op (resources released in run() via defer)
```

---

## Integrasi Logger

Ketika `config.logger` bernilai non-null:
- `system(.INFO, "fix", ...)` saat bind dan shutdown.
- `session(msg_type, sender, target, seq, state)` setelah setiap pesan diproses di dalam `serveConn`.

Lihat `docs/hld-logger-id.md` untuk detail format baris log.

---

## Contoh

| Berkas | Peran | Port |
| :- | :- | :- |
| `examples/fix_server.zig` | Server mode echo, model dispatch dipilih per target (`.URING` di Linux, `.ASYNC` di platform lain) | 9048 |
| `examples/fix_server_trading.zig` | Server `.ASYNC` dengan router: NewOrderSingle + OrderCancelRequest, JSON append, logger, timeout | 9500 |
| `examples/fix_client.zig` | Client high-level `FixClient` | 9500 |
| `examples/fix_client_raw.zig` | Client primitif core mentah | 9500 |
| `examples/fix_client_trading.zig` | Client trading: buy/cancel/sell/cancel flow | 9500 |

---

###### end of hld-fix
