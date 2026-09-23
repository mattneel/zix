# LLD: zix.Logger (internal)

Struktur data internal dan algoritma untuk implementasi logger.

---

## Struktur Data

```zig
pub const Logger = struct {
    config: Config,
    allocator: std.mem.Allocator,
    locked: std.atomic.Value(bool),   // spinlock

    file_fd: std.posix.fd_t,          // -1 when no file is open
    current_date: [10]u8,             // "YYYY-MM-DD" of currently open file
    file_seq: u32,                    // sequence counter for file rotation
    line_count: u64,                  // lines written to current file
    file_suspended: bool,             // true after unrecoverable file I/O error

    file_sink: Sink,                  // dua buffer 64 KB untuk berkas log (kosong jika save_path == "")
    console_sink: Sink,               // dua buffer 64 KB untuk console (kosong jika console == .OFF)
    flusher: Flusher,                 // thread latar belakang yang memiliki setiap penulisan
    flusher_unavailable: bool,        // true saat thread gagal dijalankan, drain berjalan inline
};

pub const Sink = struct {
    bufs: [2][]u8,                    // producer mengisi satu, flush thread menulis yang lain
    active: u1,                       // buffer yang diisi producer
    fill: usize,                      // byte di dalam bufs[active]
    pending: usize,                   // byte di bufs[active ^ 1] menunggu ditulis, 0 = tidak ada
    stalls: u64,                      // berapa kali producer menunggu karena kedua buffer terpakai
    lines: u64,                       // record yang ditambahkan
    writes: u64,                      // batch yang sudah ditulis keluar
};
```

---

## Alur Penulisan

Semua metode log mengikuti pola yang sama:

1. Turunkan level (disediakan pemanggil untuk `system()`, dihitung untuk yang lain).
2. Periksa `consoleActive(level)` dan `fileActive(level)`: keluar lebih awal jika keduanya tidak aktif.
3. Format `line` ke dalam stack buffer 4096 byte melalui `std.fmt.bufPrint`.
4. `spinLock()`.
5. Jika console aktif: `rawWrite(STDERR_FILENO, line + "\n")`.
6. Jika file aktif: `ensureFileLocked(&ts.date)` lalu `writeLineLocked(line)`.
7. `spinUnlock()`.

Semua pemformatan terjadi sebelum lock diperoleh. Waktu tahan lock sebanding dengan `memcpy` ke dalam write buffer, biasanya beberapa ratus nanodetik.

---

## rawWrite

Syscall POSIX `write` langsung dalam retry loop hingga semua byte terkirim atau error dikembalikan:

```zig
fn rawWrite(fd: std.posix.fd_t, data: []const u8) ?std.posix.E {
    var rem = data;
    while (rem.len > 0) {
        const rc = std.posix.system.write(fd, rem.ptr, rem.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => { rem = rem[@intCast(rc)..]; },
            else => return,
        }
    }
}
```

Tidak ada `std.Io`: aman dari OS thread manapun termasuk thread yang di-spawn melalui `std.Thread.spawn`. Ini disengaja: `std.debug.print` melewati `std.Options.debug_io` (sebuah global singleton) dan bersaing dengan IPC test runner di background thread. `rawWrite` ke STDERR_FILENO tidak memiliki global state semacam itu.

---

## Spinlock

CAS loop pada `locked: std.atomic.Value(bool)`:
- Lock: `cmpxchgWeak(false, true, .acquire, .monotonic)`, mencoba ulang dengan `spinLoopHint()` saat gagal.
- Unlock: `store(false, .release)`.
- `spinLoopHint()` dipetakan ke `pause`/`yield` pada x86/ARM.

Spinlock benar di bawah konkurensi tinggi karena lock hanya dipegang untuk satu `memcpy` ke buffer aktif dan tidak lebih. Lock tidak pernah dipegang melintasi syscall: flush thread melepasnya sebelum menulis dan mengambilnya kembali setelahnya, sehingga disk yang lambat tidak dapat menahan producer.

---

## Write Buffer

Dialokasikan oleh `init()` per destinasi yang aktif, dua buffer masing-masing (`write_buf_size`, 64 KB secara default, dinaikkan agar memuat satu record utuh bila disetel lebih kecil).

`appendLocked(sink, kind, line)`:
1. `sink.tryAppend(line)`: `@memcpy` record dan `'\n'` penutup ke `bufs[active]` bila masih muat, lalu kembali.
2. Tidak muat dan `pending != 0`: flush thread masih memegang buffer satunya. Hitung satu stall dan tunggu, dengan lock dilepas selama menunggu.
3. `sink.swap()`: serahkan `bufs[active]` sebagai `pending` dan mulai mengisi buffer yang lain.
4. Ulangi append, yang sekarang muat.

Producer tidak pernah mengeluarkan syscall. Penulisan terjadi di dua tempat:

- `pumpSinkLocked` di flush thread, yang melepas lock selama penulisan. Ini jalur normalnya.
- `drainSinkLocked` di thread pemanggil, dengan lock dipegang sepanjang penulisan. Ini jalur sinkronnya.

Jalur sinkron berjalan pada:
- Record `ERROR`, sehingga crash tidak menelan record yang menjelaskan crash itu.
- Pergantian tanggal atau rotasi urut (di dalam `ensureFileLocked`), yang butuh descriptor untuk dirinya sendiri.
- Pemanggilan eksplisit `logger.flush()`.
- `logger.deinit()`, setelah flush thread dihentikan dan di-join.

Flush thread tidur 20 us antar pass selama sebuah burst mungkin masih berjalan, memanjang ke 2 ms setelah 64 pass tanpa pekerjaan. Aliran record yang tipis tetap ditulis paling lambat setiap 2 ms, dan itulah yang membatasi laju syscall untuk logger yang tidak pernah memenuhi buffer.

---

## Algoritma Rotasi

`ensureFileLocked(date: *const [10]u8)` dipanggil sebelum setiap penulisan ke berkas:

```
if file_suspended: return

if file_fd < 0:
    open initial file for *date*
    return

if date changed:
    flush + close
    reset seq=0, line_count=0
    open new file in new date directory
    return

if line_count >= max_lines:
    if seq >= 999_999:
        flush + close
        file_suspended = true
        rawWrite(STDERR, warning)
        return
    flush + close
    seq += 1, line_count = 0
    open new file (same date directory)
```

Path berkas: `<save_path>/<YYYY-MM-DD>/<save_file>-<NNNNNN>.log` (nomor urut 6 digit dengan zero-padding).

Direktori tanggal dibuat dengan `mkdirat` di setiap pembukaan berkas. `mkdirat` bersifat idempoten: "sudah ada" bukan error di level system call.

---

## Timestamp

`getTimestamp()` memanggil `clock_gettime(.REALTIME)` melalui `std.os.linux.clock_gettime` (syscall langsung). Field kalender dihitung menggunakan `std.time.epoch`. Output:
- `date`: `"YYYY-MM-DD"` (10 byte, stack)
- `time`: `"HH:MM:SS.mmm"` (12 byte, stack)

Milidetik berasal dari `nsec / 1_000_000`. Tidak ada alokasi, tidak ada `std.Io`.

---

## consoleActive / fileActive

```zig
fn consoleActive(self, level) bool:
    .OFF           -> false
    .DEBUG_ONLY    -> comptime mode == .Debug and level >= console_min_level
    .ALWAYS        -> level >= console_min_level

fn fileActive(self, level) bool:
    save_path.len > 0
    and not file_suspended
    and level >= save_min_level
```

Keduanya diperiksa sebelum pemformatan apapun untuk memotong pemanggilan no-op dengan biaya nol.

---

###### end of lld-logger
