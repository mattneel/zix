# jzon

JSON dua arah, ditulis murni dengan Zig, hanya memakai standard library.

- Dua panggilan: `serialize` mengubah nilai bertipe menjadi teks JSON, `deserialize` mengubah teks JSON kembali menjadi nilai bertipe.
- Empat jalur tulis dan empat jalur baca. Semuanya menghasilkan byte yang sama dan membaca dokumen yang sama, jadi memilih salah satunya adalah keputusan biaya, bukan keputusan kebenaran.
- Serialize tidak mengalokasi apa pun. Pemanggil menyerahkan buffer, dan nilai yang tidak muat adalah `error.NoSpaceLeft`.
- Deserialize hanya mengalokasi apa yang ditunjuk hasilnya, dari allocator yang diserahkan, jadi satu reset arena membebaskan seluruh parse dalam satu langkah.
- String bisa di-borrow dari dokumennya, bukan disalin.
- Tipe field yang tidak punya bentuk JSON di jalur generated adalah compile error yang menyebut tipenya, bukan kegagalan runtime.
- Kompatibel dengan Zig 0.16 dan 0.17.

Untuk arsitektur lihat `hld-id.md`, untuk detail internal lihat `lld-id.md`, untuk biaya terukur lihat `benchmark-id.md`.

## Import

jzon ikut di dalam zix dan bisa dicapai dari sana:

```zig
const zix = @import("zix");

const len = try zix.jzon.serialize(&buf, order, .{});
```

Ia juga paket mandiri di bawah `src/jzon` dengan build file miliknya sendiri, jadi bisa dipakai berdiri sendiri. Tambahkan sebagai dependency path di `build.zig.zon`:

```zig
.dependencies = .{
    .jzon = .{ .path = "path/to/jzon" },
},
```

Pasang module-nya di `build.zig`:

```zig
const jzon = b.dependency("jzon", .{}).module("jzon");
exe.root_module.addImport("jzon", jzon);
```

## Mulai cepat

Satu record membawa kedua arah:

```zig
const Status = enum { PENDING, SHIPPED, CANCELLED };

const Line = struct {
    sku: []const u8,
    qty: u32,
    price_cents: i64,
};

const Order = struct {
    id: u64,
    customer: []const u8,
    status: Status,
    note: ?[]const u8 = null,
    tags: []const []const u8,
    lines: []const Line,
};
```

### Nilai menjadi teks JSON

```zig
var buf: [1024]u8 = undefined;

const len = try jzon.serialize(&buf, order, .{});
const json = buf[0..len];
```

Buffer itu milik pemanggil, jadi sebuah handler bisa merender langsung ke send buffer yang diberikan engine. Tidak ada yang dialokasi, dan satu-satunya kegagalan adalah `error.NoSpaceLeft`.

### Teks JSON kembali menjadi nilai

```zig
const order = try jzon.deserialize(Order, arena.allocator(), body, .{});
```

Semua yang ditunjuk `order` berasal dari allocator itu. Arena adalah pasangan alaminya untuk server: parse body permintaan ke dalamnya, jawab, lalu reset.

### Memilih jalur

```zig
const len = try jzon.serialize(&buf, order, .{ .strategy = .GENERATED });

const parsed = try jzon.deserialize(Order, arena.allocator(), body, .{
    .strategy = .GENERATED,
    .strings = .BORROW,
    .unknown = .SKIP,
});
```

Strategy adalah field comptime, jadi hanya jalur yang disebut yang ikut dikompilasi ke dalam binary.

## Strategy tulis

| Strategy | Yang dijalankan |
| :- | :- |
| `.STD` | `std.json.Stringify`, yang merender setiap bentuk yang dirender std |
| `.GENERATED_FMT` | dibangkitkan dari tipenya, integer lewat `std.fmt` |
| `.GENERATED` | dibangkitkan dari tipenya, digit integer ditulis langsung ke buffer |
| `.GENERATED_VECTOR` | seperti `.GENERATED`, dengan string dipindai satu vector lane sekaligus |

## Strategy baca

| Strategy | Yang dijalankan |
| :- | :- |
| `.STD` | refleksi `std.json`, yang mem-parse setiap bentuk yang di-parse std |
| `.SCANNER` | token dari `std.json.Scanner`, dengan dispatch field dibangkitkan dari tipenya |
| `.GENERATED` | dibangkitkan dari tipenya, di atas read cursor milik jzon, satu byte sekali jalan |
| `.GENERATED_VECTOR` | seperti `.GENERATED`, satu vector lane sekaligus |

`.GENERATED_VECTOR` tidak selalu yang tercepat, di kedua sisi. Ia membayar pada string panjang dan menjadi beban pada string pendek, itulah kenapa lebarnya tetap pilihan per call-site, bukan default. Lihat `benchmark-id.md` untuk hasil pengukurannya pada satu record.

## Options

`jzon.SerializeOptions`:

| Field | Default | Yang ditentukan |
| :- | :- | :- |
| `strategy` | `.STD` | jalur tulis mana yang berjalan |

`jzon.DeserializeOptions`:

| Field | Default | Yang ditentukan |
| :- | :- | :- |
| `strategy` | `.STD` | jalur baca mana yang berjalan |
| `strings` | `.COPY` | `.COPY` menyalin setiap string ke allocator, `.BORROW` mengarahkan string tanpa escape ke dokumennya, yang lalu harus hidup lebih lama dari nilainya |
| `unknown` | `.REJECT` | `.REJECT` gagal pada key yang tidak dideklarasikan tipenya, `.SKIP` melangkahi key beserta seluruh nilainya sedalam apa pun bersarangnya |

## Cakupan tipe

Jalur generated menerima: `bool`, integer lebar berapa pun bertanda maupun tidak, float lebar berapa pun, `[]const u8` sebagai string, slice dari tipe yang tercakup, optional dari tipe yang tercakup, enum exhaustive, dan struct yang seluruh fieldnya berupa itu.

Yang ditolak saat kompilasi, dengan menyebut tipenya: tuple, pointer non-slice, dan enum non-exhaustive. `.STD` tetap menerima bentuk apa pun yang diterima std, jadi field di luar himpunan itu adalah pilihan strategy, bukan tembok.

## Error

Proses render melaporkan `error.NoSpaceLeft` dan tidak ada yang lain.

Proses parse melaporkan satu set yang sama, jalur mana pun yang berjalan:

| Error | Artinya |
| :- | :- |
| `JzonUnknownField` | dokumen membawa key yang tidak dideklarasikan tipenya, di bawah `unknown = .REJECT` |
| `JzonMissingField` | dokumen meninggalkan field yang tidak mendeklarasikan default |
| `JzonUnknownEnumValue` | string yang tidak punya tag di enum-nya |
| `JzonTruncated` | dokumen berakhir lebih awal |
| `JzonUnexpected` | yang ada di sana bukan yang diminta tipenya: syntax error, nilai dengan bentuk salah, atau key yang sama dua kali |
| `JzonBadNumber` | teks angka yang tidak diizinkan grammar, atau nilai yang tidak muat di tipe integer sasaran |
| `JzonBadEscape` | escape sequence yang tidak dieja aturannya |
| `OutOfMemory` | allocator kehabisan |

Menukar strategy tidak pernah mengubah apa yang harus ditangani pemanggil. `lld-id.md` menyebut tiga tempat jalur yang dibangun dari tipenya menjawab berbeda dari `.STD`.

## Contoh

Enam, empat di paket ini dan dua di antaranya bench. Tidak ada yang berupa server, jadi masing-masing berjalan lalu selesai.

| Contoh | Yang ditunjukkan |
| :- | :- |
| [serialize](../../src/jzon/examples/serialize.zig) | sebuah nilai ke buffer tetap, setiap strategy tulis, dan apa yang dilaporkan buffer yang terlalu kecil |
| [deserialize](../../src/jzon/examples/deserialize.zig) | body permintaan menjadi nilai bertipe di atas arena, setiap strategy baca, reset di antara body |
| [strings](../../src/jzon/examples/strings.zig) | `.COPY` berhadapan dengan `.BORROW`, dan apa yang diminta borrow terhadap masa hidup dokumennya |
| [unknown_keys](../../src/jzon/examples/unknown_keys.zig) | `.REJECT` berhadapan dengan `.SKIP` pada dokumen yang membawa lebih dari yang dideklarasikan tipenya |
| [bench_serialize](../../src/jzon/examples/bench_serialize.zig) | biaya setiap strategy tulis per render, dibanding laju default |
| [bench_deserialize](../../src/jzon/examples/bench_deserialize.zig) | biaya setiap strategy baca per parse, pada dokumen minified dan dokumen yang ditata rapi |

Bangun dari paketnya:

```
zig build examples                 # semuanya
zig build example-serialize        # satu saja
```

Atau dari root repo dengan `zig build jzon-examples`. Binary-nya mendarat di `src/jzon/zig-out/bin` sebagai `jzon-example-<name>-<arch>-<os>-<optimize>`, dengan mode `debug` kecuali `-Doptimize` menentukan lain.

Dua contoh bench butuh `-Doptimize=ReleaseFast`. Build Debug mengukur safety check, bukan jalurnya.

Contoh ketujuh berupa server, jadi ia tinggal bersama contoh engine, bukan di paket ini: [`examples/http1_jzon.zig`](../../examples/http1_jzon.zig) membaca body JSON permintaan menjadi record di atas arena per-permintaan lalu menjawab dengan record yang dirender ke buffer stack, tanpa alokasi apa pun di jalur respons. Bangun dari root repo dengan `zig build example-http1_jzon`.

## Testing

Tiga tier, 440 test, tidak ada yang butuh instalasi apa pun:

```
zig build test-unit          # 113, test in-file di bawah src/
zig build test-behaviour     # 144, apa yang dilakukan tiap bagian saat diberi yang diminta
zig build test-edge          # 183, apa yang dilakukan tiap bagian saat diberi yang tidak diminta
zig build test-all           # ketiganya
```

Dari root repo langkah yang sama bernama `jzon-test-unit`, `jzon-test-behaviour`, `jzon-test-edge`, dan `jzon-test-all`. Batas per-test datang dari `-Ddriver-test-timeout=<durasi>`, karena build paket bersarang tidak pernah melihat `--test-timeout` milik induknya.

Setiap tier berjalan di kedua versi Zig yang didukung dan di ketujuh target CI.
