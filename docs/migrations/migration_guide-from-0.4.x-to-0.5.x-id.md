# Panduan Migrasi

## Untuk pengguna yang meningkat dari 0.4.x:

1. **Atur `dispatch_model` secara eksplisit** di setiap konfigurasi server (tanpa nilai default)
2. **Perbarui pemanggilan `Server.init`**:
   - `zix.Http.Server.init(4096, &routes, cfg)` -> `zix.Http.Server.init(zix.Http.Router(&routes).dispatch, cfg)`
   - `const S = zix.Http3.Http3(handler); try S.init(cfg)` -> `zix.Http3.Server.init(handler, cfg)`
   - Hapus `try` dari inisialisasi `zix.Http2`/`zix.Grpc`/`zix.Http` (validasi dipindahkan ke `run()`)
3. **Perbarui tanda tangan `HandlerFn`** menjadi `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void`
4. **Ganti nama helper respons** sesuai taksonomi ADR-059:
   - `write*` -> `send*`; tambahkan `*FD` untuk varian yang menerima fd
5. **Perbarui nama error** ke bentuk berprefiks: `error.PortNotConfigured` -> `error.ZixPortNotConfigured`
6. **Penguraian metode HTTP**: `codeFromString` sekarang bersifat case-sensitive eksak, metode huruf kecil -> 501
7. **Pencarian tipe konten**: `enumFromString` -> `typeFromString`, mengembalikan `?Type` (tanpa `.NA`)
8. **Hapus referensi `.POOL`/`.MIXED`**, gunakan `.ASYNC`, `.EPOLL`, atau `.URING`
9. **`pool_size` dihapus**, gunakan `workers` untuk jumlah thread/worker
10. **`max_gzip_out`** -> `compression_max_out`
