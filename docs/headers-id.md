# Header Respons: Konfigurasi & Keamanan

## Tujuan

Setiap respons HTTP di zix dapat membawa header kustom yang ditambahkan melalui `res.addHeader(name, value)`. Jumlah header yang diizinkan dalam satu respons dikendalikan oleh `HttpServerConfig.max_response_headers`, yang menerima nilai `zix.Http.HeaderSize`.

Backing buffer dialokasikan via arena per request dengan ukuran tepat sesuai cap yang dikonfigurasi: tidak ada memori yang terbuang, tidak ada batas palsu. `addHeader()` mengembalikan `error.ZixTooManyHeaders` begitu cap tercapai.

---

## Tier Header

| Varian | Cap | Kapan digunakan |
| :- | :- | :- |
| `.MINIMAL` | 16 | **Default.** API sederhana, layanan internal, handler polos tanpa proxy. Footprint arena per-respons paling ketat |
| `.COMMON` | 32 | Sebagian besar aplikasi web di balik satu proxy atau load balancer |
| `.LARGE` | 64 | Stack CDN + proxy, layanan yang mengemisi banyak header CORS, cache, atau forwarding |
| `.EXTRA_LARGE` | 128 | Deployment k8s, service mesh (Envoy/Linkerd), rantai header yang padat |
| `.{ .CUSTOM = N }` | N | Cap non-standar yang ditetapkan secara eksplisit |

Atur sekali saja di `HttpServerConfig`:

```zig
var server = zix.Http.Server.init(handler, .{
    // ...
    .max_response_headers = .LARGE,              // 64 headers
    // .max_response_headers = .{ .CUSTOM = 48 }, // cap eksplisit
});
```

---

## Memilih Tier

**Mulai dengan `.MINIMAL` (16), nilai default.** Hitung header yang benar-benar ditambahkan handler terberat di produksi, lalu bulatkan ke tier berikutnya hanya jika melebihinya. Jangan over-provisioning karena cap yang lebih besar berarti footprint arena per-respons yang lebih besar dan batas yang lebih sulit dianalisis saat diserang.

Perkiraan jumlah header berdasarkan deployment:

- Layanan polos: 2-6 (`Content-Type`, `Content-Length`, `Connection`, `Date` dikirim otomatis, header kustom seperti `X-Request-ID` berasal dari `addHeader()`)
- Dengan CORS: +4-6 (`Access-Control-*`, `Vary`, `Access-Control-Max-Age`)
- Dengan caching: +3-4 (`Cache-Control`, `ETag`, `Last-Modified`, `Expires`)
- Di balik k8s ingress: +5-10 (forwarding, tracing, `X-Forwarded-*`, `X-Envoy-*`)

Jika mencapai 16 header dalam operasi normal, pindah ke `.COMMON`. Jika mencapai 32, pindah ke `.LARGE`. Jika mencapai 64, pindah ke `.EXTRA_LARGE`. Jangan langsung menggunakan `.CUSTOM` kecuali ada alasan yang sudah dihitung.

---

## Keamanan

### Injeksi Header

`addHeader()` menolak `name` atau `value` yang mengandung `\r` (CR) atau `\n` (LF):

```
error.ZixInvalidHeaderName   (CR atau LF ditemukan di nama header)
error.ZixInvalidHeaderValue  (CR atau LF ditemukan di nilai header)
```

**Jangan pernah meneruskan data yang dikontrol pengguna langsung ke `addHeader()` tanpa sanitasi.** Meski sudah ada penjaga CR/LF, nilai header yang mengandung `:` atau menyerupai header lain dapat membingungkan proxy upstream. Jika nilai berasal dari request body, query param, atau path segment, validasi terlebih dahulu sebelum digunakan.

### Flooding Header (cap sebagai batas DoS)

Cap bukan sekadar batas kegunaan: ini adalah **langkah pertahanan berlapis**. Handler yang salah konfigurasi atau terkompromi yang terus memanggil `addHeader()` dibatasi oleh `max_response_headers`, bukan oleh memori. Dengan `.MINIMAL` (16), overhead per-respons dalam kasus terburuk adalah:

```
16 headers x (name_ptr + value_ptr) = 16 x 32 bytes = 512 bytes (arena)
```

Dengan `.EXTRA_LARGE` (128), naik menjadi sekitar 4 KB. Keduanya terbatas dan dialokasikan via arena. Jangan menetapkan `.{ .CUSTOM = N }` ke angka besar secara spekulatif karena hanya memperlebar footprint tanpa manfaat yang sepadan.

### Header yang Terlihat oleh Client

Ingat bahwa setiap header yang ditambahkan terlihat oleh client (dan proxy mana pun di antara server dan client). Hindari membocorkan:

- Nama host atau IP internal di echo `X-Forwarded-*`
- Stack trace atau metadata build di debug header
- Token sesi atau token internal di nilai header mana pun

---

## Masalah Modifikasi saat Runtime

Memodifikasi atau menambahkan header selama fase respons dikendalikan ketat untuk menjaga performa dan integritas protokol.

1. **Pelanggaran Protokol (Timing)**: HTTP/1.1 mengharuskan status line dan semua header dikirim sebelum body. Jika `res.send()` sudah mulai mengirimkan data, menambahkan header baru secara fisik sudah terlambat.
2. **Kapasitas Buffer**: Fungsi `send()` menyimpan header sementara di stack buffer berukuran 4096 byte. Set header yang sangat besar atau modifikasi saat runtime yang mendorong total blok header melewati 4 KB akan menghasilkan `error.ZixBufferTooSmall`.
3. **Keamanan Thread**: Di lingkungan multi-threaded, memodifikasi header sementara `send()` memproses buffer dapat menyebabkan race condition dan korupsi data.
4. **Perlindungan Injeksi**: Modifikasi saat runtime yang menggunakan data eksternal tetap harus menghormati penjaga injeksi CR/LF untuk mencegah celah keamanan.

---

## Penanganan Error di Handler

`addHeader()` mengembalikan `!void`. Propagasikan atau tangani secara eksplisit:

```zig
// Propagasi: muncul sebagai 500 jika server menangkapnya
try res.addHeader("X-Foo", "bar");

// Tangani secara eksplisit: beri client error yang bermakna
res.addHeader("X-Foo", "bar") catch |err| switch (err) {
    error.ZixTooManyHeaders    => { res.setStatus(.INTERNAL_SERVER_ERROR); try res.sendJson("{\"error\":\"too many headers\"}"); return; },
    error.ZixInvalidHeaderName => { res.setStatus(.BAD_REQUEST);           try res.sendJson("{\"error\":\"invalid header name\"}"); return; },
    error.ZixInvalidHeaderValue => { res.setStatus(.BAD_REQUEST);          try res.sendJson("{\"error\":\"invalid header value\"}"); return; },
    else                    => return err,
};
```

Lihat `examples/http_xtra_headers.zig` dan `examples/http1_xtra_headers.zig` untuk demonstrasi cap, jalur overflow, dan penjaga injeksi yang berfungsi.

---

## Nilai Custom > 128

`.{ .CUSTOM = N }` dengan N > 128 didukung penuh: backing buffer dialokasikan via arena tepat sebesar N slot per request. Meski demikian, jika benar-benar membutuhkan lebih dari 128 header kustom per respons, pertimbangkan ulang desainnya. Respons HTTP tipikal membawa 5-20 header, dan 128 sudah merupakan batas atas yang ekstrem.

---

###### end of headers.md
