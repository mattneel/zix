# Referensi Konfigurasi zix

Arti dari setiap field konfigurasi zix yang dapat diatur, dan bagaimana mengubahnya memengaruhi proses yang berjalan. Mencakup engine server dan TLS context, plus komponen bersama (Logger) yang dilampirkan engine mana pun lewat pointer. Satu bagian per config. Setiap field mencantumkan default, apa yang diatur, dan trade-off penyetelannya.

Dokumen ini diindeks berdasarkan field konfigurasi: satu bagian per struct config, setiap field dengan default-nya dan apa yang ditegakkan sumbernya.

Catatan: server melampirkan Logger lewat field `logger` (pointer). Knob sizing milik Logger berada sekali di config Logger (lihat bagian Logger), bukan di setiap config server.

## Cara membaca kolom

Sebuah sel dibiarkan kosong saat tidak berlaku (handle wajib seperti `io` tidak punya trade-off penyetelan).

| kolom | arti |
| :- | :- |
| field | nama field pada struct konfigurasi |
| default | nilai yang dipakai saat field tidak diisi |
| fungsi | apa yang dilakukan field |
| dampak performa | di mana posisinya (hot path, per koneksi, per worker, startup) dan metrik apa yang digerakkan |
| cara menyetel | arah perubahan untuk suatu tujuan |
| jika lebih kecil | konsekuensi nilai yang lebih kecil |
| jika lebih besar | konsekuensi nilai yang lebih besar |
| konsekuensi salah atur | risiko utama bila salah dikonfigurasi |

## Dispatch model (dipakai bersama oleh semua engine keluarga TCP)

`dispatch_model` memilih keseluruhan strategi concurrency. Field ini wajib: setel secara eksplisit, tidak ada default. Nilai:

| nilai | arti |
| :- | :- |
| `.ASYNC` | satu accept thread, satu `io.async()` per koneksi. Terbaik untuk latency rendah pada jumlah koneksi sedang. |
| `.EPOLL` | shared-nothing: tiap worker memiliki satu listener SO_REUSEPORT plus satu instance epoll. Terbaik untuk jumlah koneksi sangat tinggi. Khusus Linux, di luar Linux `run()` mengembalikan `error.ZixDispatchModelUnsupported`. |
| `.URING` | io_uring shared-nothing: topologi per-core yang sama dengan `.EPOLL`, berbasis completion sehingga sebagian besar syscall di-batch. Khusus Linux, memeriksa ring saat startup lalu melipat ke `.EPOLL` saat io_uring tidak tersedia. |

## HTTP/1 (`Http1ServerConfig`)

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, harus non-zero | | | | | nol tidak divalidasi: bind ke port ephemeral pilihan kernel |
| dispatch_model | wajib | model concurrency (lihat tabel di atas) | menentukan keseluruhan strategi | `.EPOLL`/`.URING` untuk jumlah koneksi tinggi di Linux | | | model salah membatasi throughput, di luar Linux hanya `.ASYNC` yang jalan |
| kernel_backlog | 1024 | TCP listen backlog sebelum accept() | kedalaman antrian accept kernel | naikkan saat lonjakan koneksi | koneksi baru dibuang saat lonjakan | lebih banyak memori kernel untuk antrian | terlalu kecil membuang koneksi saat spike |
| workers | 0 | jumlah accept thread, 0 = cpu_count | paralelisme antar core | biarkan 0 (otomatis), atau patok jumlahnya | lebih sedikit core dipakai | oversubscription dan context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack worker thread untuk handler thread .EPOLL/.URING | RSS per thread (demand-paged) | naikkan untuk handler dalam atau local stack besar, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biaya rendah sampai kedalamannya dipakai |
| worker_stack_compress_bytes | 2097152 | stack worker saat compression aktif, diterapkan sebagai floor: stack efektif = max(worker_stack_size_bytes, ini) | RSS per thread pada .EPOLL/.URING dengan compression | naikkan bila handler yang mengompres butuh lebih | flate (sekitar 230 KB pada frame handler) dapat overflow stack kecil | RSS terbuang per worker | tanpa efek saat compression off |
| busy_poll_us | 50 | spin window SO_BUSY_POLL dalam mikrodetik untuk koneksi yang diterima (.EPOLL) | hot, kernel busy-spin sebelum menidurkan worker | naikkan untuk memangkas tail latency saat beban, 0 untuk hemat CPU idle | spin lebih pendek, lebih banyak wakeup idle-sleep, tail latency lebih tinggi | core spin 100% saat idle | no-op tanpa dukungan SO_BUSY_POLL kernel |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): koneksi baru masuk ke listener index = CPU penerima mod workers alih-alih hash 4-tuple | penempatan koneksi (per SYN, tanpa biaya hot-path) | aktifkan pada host multi-core agar koneksi dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| max_recv_buf | 6144 | read buffer per koneksi pada semua dispatch model (slot .EPOLL / .URING, pasangan pool-thread .ASYNC), membatasi head dan slice body yang dilihat handler | memori per koneksi dan ukuran request maksimum | naikkan untuk header request besar | request besar ditolak | lebih banyak memori per koneksi | terlalu kecil menolak request besar yang valid |
| large_body_rcvbuf | 0 | SO_RCVBUF diterapkan hanya pada jalur body besar (body lebih besar dari read buffer, yaitu upload), 0 memakai default kernel | kecepatan ingest upload dan memori per koneksi saat body besar berjalan | naikkan untuk ingest upload lebih cepat | upload ingest lebih lambat (window default kernel yang sempit) | lebih banyak memori saat body besar (256 KiB menargetkan sekitar 256 MiB resident pada 256c) | hanya jalur upload yang menyentuhnya, cell request kecil tidak terpengaruh |
| max_request_body | 8388608 | body request terbesar yang diambil engine: Content-Length yang dideklarasikan melewatinya ditolak dengan 413 sebelum body dibaca atau di-drain, 0 menghapus cek | satu compare per request ber-body, tidak ada di jalur GET panas | turunkan untuk membatasi upload, 0 untuk mempercayai panjang yang dideklarasikan | upload besar yang sah ditolak dengan 413 | klien bisa membuat worker mengonsumsi lebih banyak byte per request | chunked tidak mendeklarasikan panjang di muka, jadi dibatasi body buffer (413 melewatinya) |
| ws_recv_buf | 0 | buffer receive per koneksi WebSocket, 0 jatuh ke max_recv_buf | memori per koneksi WS dan kedalaman burst pipelined WS | naikkan di atas max_recv_buf untuk menampung burst pipelined lebih dalam | lebih banyak compact dan re-read untuk WS | lebih banyak memori per koneksi WS | .EPOLL menentukan ukuran buffer recv, .URING menentukan ukuran buffer frame-accumulation dan scratch unmask, 0 memakai ulang max_recv_buf |
| uring_send_buf_size | 16384 | buffer send per koneksi untuk dispatch model .URING (sisi send, max_recv_buf untuk recv) | memori per koneksi pada .URING | naikkan untuk respons tunggal lebih besar, turunkan untuk memperkecil memori per koneksi | lebih banyak pertumbuhan buffer pada respons besar | lebih banyak memori per koneksi | tanpa efek pada dispatch model lain |
| uring_idle_pool_floor | 8 | floor slot idle warm per worker pada .URING (juga jumlah stride yang di-pretouch saat startup) | memori warm vs first-touch fault pada koneksi baru | naikkan untuk menjaga lebih banyak slot warm saat churn, turunkan untuk memperkecil memori idle | lebih banyak page fault setelah periode sepi | lebih banyak slot idle tetap resident | warm cap adalah clamp(live_count, floor, ceiling), tanpa efek pada model lain |
| uring_idle_pool_ceiling | 256 | ceiling absolut slot idle warm per worker pada .URING, menjaga warm set di bawah live_count pada konkurensi tinggi | memori resident pada jumlah koneksi tinggi | naikkan untuk menjaga lebih banyak warm bagi reconnect, turunkan untuk memperkecil resident set saat churn | lebih banyak page fault pada reconnect saat konkurensi tinggi | lebih banyak slot tertutup tetap resident (tekanan cache dan TLB) | perbaikan untuk regresi koneksi tinggi saat warm set mengikuti live_count, tanpa efek pada model lain |
| process_queue_len | 0 (off) | FIFO ring per worker (.URING) yang mem-park re-arm recv atau send saat submission queue penuh dan mencoba ulang pada loop pass berikutnya alih-alih menutup koneksi, 0 menonaktifkan fitur | slab per worker, hanya referensi (fd + generation), aktif hanya saat SQ penuh saat burst | atur sekitar puncak koneksi bersamaan per worker agar burst SQ-penuh mem-park alih-alih membuang koneksi | ring penuh lebih cepat saat burst, entry terbaru ditolak dan koneksi itu jatuh ke jalur close | lebih banyak slab tercadang per worker (jumlah entry kali beberapa byte) | tanpa efek pada dispatch model lain, nilai jauh di atas puncak koneksi per worker hanya mencadangkan slab yang menjadi resident seiring waktu tanpa manfaat |
| max_response_headers | `.MINIMAL` (16) | header respons custom maksimum (kapasitas addHeader, ADR-062) | memori per respons, dialokasikan lazy pada addHeader pertama | naikkan tier untuk banyak header custom | header ekstra tidak bisa diset | lebih banyak memori per respons | request yang tidak menambah header tidak membayar apa pun |
| conn_timeout_ms | 0 | penjaga umur koneksi (ms), 0 = nonaktif (ADR-062) | eviction timer latar pada `.ASYNC` | atur untuk meng-evict koneksi berumur panjang pada model blocking | koneksi diputus lebih cepat | koneksi berumur lebih panjang | no-op terdokumentasi pada `.EPOLL`/`.URING` (event loop-nya memiliki umur koneksi) |
| handler_timeout_ms | 0 | budget eksekusi per handler (ms), 0 = nonaktif | deadline kooperatif | atur untuk membatasi handler lambat | handler dihentikan lebih cepat | handler lambat berjalan lebih lama | handler harus cek isExpired() agar berlaku |
| send_date_header | true | sertakan header Date di setiap respons (RFC 7231) | 37 byte per respons | biarkan on untuk kepatuhan, off untuk memperkecil respons | | | off menghilangkan header standar |
| public_dir | "" | direktori root untuk serve file statis, kosong menonaktifkan | I/O disk saat hit statis | atur untuk melayani file statis pada route yang tidak match handler | | | non-empty divalidasi saat run(), direktori yang tidak ada menghasilkan error.ZixPublicDirNotFound |
| public_dir_upload | "u" | subdirektori upload di bawah public_dir, path deklaratif yang ditulis handler upload secara konvensi | | atur path upload | | | relatif terhadap public_dir, engine tidak auto-wire upload |
| public_dir_cache_ttl_ms | 0 | berapa lama file static yang sudah di-resolve tetap di-cache (ms), 0 = tidak pernah di-cache (ADR-064) | satu descriptor terbuka per varian cache, bukan open plus stat per request | atur di atas 0 agar file static tetap terbuka dan header 200-nya sudah dirender | setiap request membuka dan membaca ulang file | file yang diedit di disk butuh sampai satu window untuk terlihat | 0 sama persis dengan perilaku sebelum ADR-064 |
| public_dir_cache_max_entries | 256 | jumlah slot cache static, satu slot per file plus sibling .br dan .gz-nya | descriptor dan tabel slot demand-paged | naikkan untuk public_dir yang lebih besar | file di luar tabel disajikan tanpa cache | lebih banyak descriptor ditahan | dibulatkan turun ke pangkat dua, di-clamp terhadap budget descriptor proses |
| compress | false | aktifkan kompresi respons gzip/deflate/brotli dengan negosiasi Accept-Encoding | CPU vs ukuran body, hanya untung lewat jaringan nyata | aktifkan saat melayani lewat jaringan, matikan untuk benchmark loopback | | | pada benchmark loopback ini murni biaya CPU |
| compression_min_size | 256 | ukuran body minimum (byte) sebelum kompresi dicoba | pemeriksaan per respons | naikkan agar tidak mengompres body kecil | body kecil dikompres dengan untung kecil | body lebih besar dikirim tanpa kompresi | terlalu kecil memboroskan CPU pada body kecil |
| compression_max_out | 262144 | byte output terkompresi maksimum untuk semua coding | batas per respons terkompresi | naikkan untuk mengompres body lebih besar | body lebih besar dikirim tanpa kompresi | lebih banyak CPU dan memori sebelum menyerah | body di atas ini dikirim tanpa kompresi |
| response_cache | false | aktifkan cache respons per worker (ADR-036) | memori untuk respons yang di-cache | aktifkan untuk respons panas yang berulang | | | off membuat API cache jadi no-op |
| cache_max_entries | 256 | jumlah slot cache, dibulatkan turun ke pangkat dua | memori per worker = entries * value_bytes | naikkan untuk lebih banyak key yang di-cache | lebih sedikit key di-cache, lebih banyak miss | lebih banyak memori per worker | per worker, dikali jumlah worker |
| cache_max_value_bytes | 16384 | batas respons per slot, respons lebih besar melewati cache | memori per slot | naikkan untuk meng-cache respons lebih besar | respons besar melewati cache | lebih banyak memori per worker | tetap ramping, cache untung di atas beberapa KiB |
| cache_ttl_ms | 1000 | kesegaran cache default (ms) | hit rate cache vs kebasian | naikkan untuk hit rate lebih tinggi, turunkan untuk data lebih segar | entri kedaluwarsa lebih cepat, lebih banyak miss | respons lebih basi disajikan | terlalu tinggi menyajikan data basi |
| cache_max_total_bytes | 0 | batas opsional memori cache per worker, 0 = tanpa batas | membatasi total memori cache | atur untuk membatasi RAM cache | jumlah entri efektif dikurangi agar muat | memakai penuh entries * value_bytes | 0 menonaktifkan batas |
| tls | null | TLS context untuk https (opt-in), null = cleartext | mengaktifkan TLS, band performa tersendiri | pasang context untuk melayani https | | | null melayani cleartext |
| tls_port | 0 | port bind https pendamping untuk dual listener (ADR-060) | satu worker fleet melayani cleartext + TLS | isi bersama tls untuk melayani keduanya dari satu server | 0 mempertahankan perilaku single-listener | | butuh tls diisi, harus beda dari port |
| logger | null | logger opsional untuk baris lifecycle | | pasang untuk logging server | | | access logging per request adalah tugas handler |

## HTTP/2 (`Http2ServerConfig`)

h2c cleartext secara default, h2-over-TLS saat `tls` diisi.

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nilai nol ditolak |
| dispatch_model | wajib | model concurrency | menentukan strategi | `.EPOLL`/`.URING` di Linux untuk skala | | | `.URING` melipat ke `.EPOLL` saat io_uring tidak tersedia, di luar Linux hanya `.ASYNC` yang jalan |
| kernel_backlog | 1024 | TCP listen backlog | antrian accept kernel | naikkan saat lonjakan koneksi | koneksi dibuang saat lonjakan | lebih banyak memori kernel | terlalu kecil membuang koneksi |
| workers | 0 | jumlah accept thread, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core dipakai | context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack worker thread untuk handler thread .EPOLL/.URING dan TLS | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biaya rendah sampai kedalamannya dipakai |
| busy_poll_us | 0 | spin window SO_BUSY_POLL dalam mikrodetik untuk koneksi yang diterima (.EPOLL / .URING) | hot, kernel busy-spin sebelum menidurkan worker | set ke mis. 50 untuk memangkas tail latency saat beban | spin lebih pendek, lebih banyak wakeup idle-sleep | core spin 100% saat idle | 0 membiarkannya tidak diset, no-op tanpa dukungan SO_BUSY_POLL kernel |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): koneksi baru masuk ke listener index = CPU penerima mod workers alih-alih hash 4-tuple | penempatan koneksi (per SYN, tanpa biaya hot-path) | aktifkan pada host multi-core agar koneksi dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| max_recv_buf | 32768 | floor buffer read per koneksi (.EPOLL / .URING mux) | buffer read per koneksi, hot | naikkan untuk memangkas read() dan compaction untuk frame besar | lebih banyak read dan compaction untuk frame besar | lebih banyak memori per koneksi | reader = max(ini, satu frame maksimum) |
| tls_write_buf_initial_bytes | 16384 | kapasitas awal buffer TLS pending-write per koneksi (tumbuh sesuai kebutuhan) | per koneksi, jalur TLS | naikkan untuk menghindari realokasi dini pada respons besar | lebih banyak realokasi pada respons besar | lebih banyak memori idle per koneksi TLS | minor, hanya amortisasi |
| max_streams | 128 | stream konkuren maksimum per koneksi (SETTINGS_MAX_CONCURRENT_STREAMS yang diiklankan) | tabel pointer slot per koneksi, slot stream di-pool per worker | naikkan untuk klien yang sangat multipleks | klien kena REFUSED_STREAM lebih cepat | array pointer lebih lebar, concurrency iklan lebih tinggi | terlalu kecil menyerialkan klien multipleks |
| max_frame_size | 16384 | setting MAX_FRAME_SIZE yang diiklankan ke klien (byte) | byte per frame DATA | naikkan untuk mengirim frame lebih besar | lebih banyak frame per respons | buffer per frame lebih besar | dibatasi rentang spesifikasi HTTP/2 |
| max_header_scratch | 4096 | scratch decode HPACK per stream | buffer per stream, di-pool berdasarkan concurrency | naikkan untuk set header besar | blok header besar ditolak | lebih banyak memori per stream konkuren | terlalu kecil menolak header valid |
| max_body | 16384 | body request maksimum yang di-buffer per stream (byte), lebih besar dipotong | buffer per stream, di-pool berdasarkan concurrency | naikkan untuk body request lebih besar | body di atas ini dipotong | lebih banyak memori per stream konkuren | terlalu besar memboroskan memori pool saat concurrency puncak |
| response_cache | false | aktifkan cache respons per worker (ADR-036), opt-in via serveCached/sendCached | memori cache | aktifkan untuk respons panas yang berulang | | | off membuat API cache jadi send biasa |
| cache_max_entries | 256 | jumlah slot cache (pangkat dua) | memori per worker | naikkan untuk lebih banyak key | lebih banyak miss | lebih banyak memori | dikali jumlah worker |
| cache_max_value_bytes | 16384 | batas respons per slot | memori per slot | naikkan untuk respons cache lebih besar | respons besar melewati cache | lebih banyak memori | tetap ramping |
| cache_ttl_ms | 1000 | kesegaran cache default (ms) | hit rate vs kebasian | naikkan untuk hit rate, turunkan untuk kesegaran | kedaluwarsa lebih cepat, lebih banyak miss | data lebih basi | terlalu tinggi menyajikan data basi |
| cache_max_total_bytes | 0 | batas memori cache per worker, 0 = tanpa batas | membatasi memori cache | atur untuk membatasi RAM cache | jumlah entri dikurangi agar muat | penuh entries * value_bytes | 0 menonaktifkan batas |
| public_dir | "" | direktori root untuk penyajian file static, kosong menonaktifkannya (ADR-064) | I/O disk saat hit static | atur untuk menyajikan file static bagi route yang tidak cocok handler | | | Range (RFC 7233) disajikan, 206 atau 416, header multi-range dijawab range pertama |
| public_dir_cache_ttl_ms | 0 | berapa lama file static yang sudah di-resolve tetap di-cache (ms), 0 = tidak pernah di-cache | satu descriptor terbuka per varian cache, bukan open plus stat per request | atur di atas 0 agar file static tetap terbuka dan sibling-nya sudah di-resolve | setiap request membuka dan membaca ulang file | file yang diedit di disk butuh sampai satu window untuk terlihat | berbagi tabel proses dengan engine lain |
| public_dir_cache_max_entries | 256 | jumlah slot cache static, satu slot per file plus sibling .br dan .gz-nya | descriptor dan tabel slot demand-paged | naikkan untuk public_dir yang lebih besar | file di luar tabel disajikan tanpa cache | lebih banyak descriptor ditahan | dibulatkan turun ke pangkat dua, di-clamp terhadap budget descriptor proses |
| tls | null | TLS context untuk h2-over-TLS (ALPN h2), null = h2c | mengaktifkan TLS | pasang context dengan ALPN h2 | | | browser butuh ALPN h2 untuk HTTP/2 over TLS |
| tls_port | 0 | port bind h2-over-TLS pendamping untuk dual listener (ADR-060) | satu worker fleet melayani h2c + h2-over-TLS | isi bersama tls untuk melayani keduanya dari satu server | 0 mempertahankan perilaku single-listener | | butuh tls diisi, harus beda dari port |
| logger | null | logger opsional untuk baris lifecycle | | pasang untuk logging | | | logging per request adalah tugas handler |

## gRPC (`GrpcServerConfig`)

gRPC di atas HTTP/2. h2c cleartext secara default, h2-over-TLS saat `tls` diisi.

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nilai nol ditolak |
| dispatch_model | wajib | model concurrency | menentukan strategi | `.EPOLL`/`.URING` di Linux untuk skala | | | di luar Linux hanya `.ASYNC` yang jalan |
| kernel_backlog | 1024 | TCP listen backlog | antrian accept kernel | naikkan saat lonjakan | koneksi dibuang | lebih banyak memori kernel | terlalu kecil membuang koneksi |
| workers | 0 | jumlah accept thread, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core | context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack worker thread untuk handler thread .EPOLL/.URING dan TLS | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biaya rendah sampai kedalamannya dipakai |
| busy_poll_us | 0 | spin window SO_BUSY_POLL dalam mikrodetik untuk koneksi yang diterima (.EPOLL / .URING) | hot, kernel busy-spin sebelum menidurkan worker | set ke mis. 50 untuk memangkas tail latency saat beban | spin lebih pendek, lebih banyak wakeup idle-sleep | core spin 100% saat idle | 0 membiarkannya tidak diset, no-op tanpa dukungan SO_BUSY_POLL kernel |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): koneksi baru masuk ke listener index = CPU penerima mod workers alih-alih hash 4-tuple | penempatan koneksi (per SYN, tanpa biaya hot-path) | aktifkan pada host multi-core agar koneksi dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| max_recv_buf | 65536 | floor buffer read per koneksi (.EPOLL / .URING) | buffer read per koneksi, hot | naikkan untuk memangkas read() dan compaction untuk frame besar | lebih banyak read dan compaction untuk frame besar | lebih banyak memori per koneksi | reader = max(ini, satu frame maksimum) |
| tls_write_buf_initial_bytes | 16384 | kapasitas awal buffer TLS pending-write per koneksi (tumbuh sesuai kebutuhan) | per koneksi, jalur TLS | naikkan untuk menghindari realokasi dini pada balasan besar | lebih banyak realokasi pada balasan besar | lebih banyak memori idle per koneksi TLS | minor, hanya amortisasi |
| max_streams | 128 | stream h2 konkuren maksimum per koneksi (SETTINGS_MAX_CONCURRENT_STREAMS yang diiklankan) | tabel pointer slot per koneksi, slot stream di-pool per worker | naikkan untuk klien yang sangat multipleks | klien kena REFUSED_STREAM lebih cepat | array pointer lebih lebar, concurrency iklan lebih tinggi | terlalu kecil menyerialkan klien multipleks |
| max_frame_size | 16384 | setting MAX_FRAME_SIZE yang diiklankan ke klien (byte) | byte per frame DATA | naikkan untuk frame lebih besar | lebih banyak frame per pesan | buffer per frame lebih besar | dibatasi rentang spesifikasi HTTP/2 |
| max_header_scratch | 4096 | scratch decode HPACK per stream | buffer per stream, di-pool berdasarkan concurrency | naikkan untuk set header besar | blok header besar ditolak | lebih banyak memori per stream konkuren | terlalu kecil menolak header valid |
| max_body | 16384 | body request maksimum yang di-buffer per stream (byte), lebih besar dipotong | buffer per stream, di-pool berdasarkan concurrency | naikkan untuk pesan lebih besar | pesan di atas ini dipotong | lebih banyak memori per stream konkuren | terlalu besar memboroskan memori pool saat concurrency puncak |
| handler_timeout_ms | 0 | batas timeout handler global (ms), 0 = nonaktif | deadline kooperatif | atur untuk membatasi handler lambat | handler diputus lebih cepat | handler lambat berjalan lebih lama | Route.timeout_ms dan header grpc-timeout memperketatnya |
| compress | false | kompresi gzip frame DATA untuk klien yang mengiklankan grpc-accept-encoding: gzip | CPU vs ukuran pesan | aktifkan lewat jaringan | | | murni biaya CPU pada loopback |
| response_cache | false | aktifkan cache respons unary per worker | memori cache | aktifkan untuk respons unary panas | | | off membuat API cache jadi send biasa |
| cache_max_entries | 256 | jumlah slot cache (pangkat dua) | memori per worker | naikkan untuk lebih banyak key | lebih banyak miss | lebih banyak memori | dikali jumlah worker |
| cache_max_value_bytes | 16384 | batas pesan respons per slot | memori per slot | naikkan untuk pesan cache lebih besar | pesan besar melewati cache | lebih banyak memori | tetap ramping |
| cache_ttl_ms | 1000 | kesegaran cache default (ms) | hit rate vs kebasian | naikkan untuk hit rate, turunkan untuk kesegaran | kedaluwarsa lebih cepat, lebih banyak miss | data lebih basi | terlalu tinggi menyajikan data basi |
| cache_max_total_bytes | 0 | batas memori cache per worker, 0 = tanpa batas | membatasi memori cache | atur untuk membatasi RAM cache | jumlah entri dikurangi agar muat | penuh entries * value_bytes | 0 menonaktifkan batas |
| tls | null | TLS context untuk gRPC over TLS (ALPN h2), null = h2c | mengaktifkan TLS | pasang context dengan ALPN h2 | | | gRPC jalan di HTTP/2, butuh ALPN h2 over TLS |
| tls_port | 0 | port bind gRPC-over-TLS pendamping untuk dual listener (ADR-060) | satu worker fleet melayani h2c + TLS | isi bersama tls untuk melayani keduanya dari satu server | 0 mempertahankan perilaku single-listener | | butuh tls diisi, harus beda dari port |
| logger | null | logger opsional, lifecycle plus per-rpc | | pasang untuk logging | | | |

## HTTP (engine konvenien, `HttpServerConfig`)

Jalur serba-lengkap. Set field compression dan cache yang sama dengan HTTP/1, plus knob arena dan tier header.

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nol tidak divalidasi: bind ke port ephemeral pilihan kernel |
| dispatch_model | wajib | model concurrency | menentukan strategi | `.EPOLL`/`.URING` di Linux untuk skala | | | di luar Linux hanya `.ASYNC` yang jalan |
| kernel_backlog | 1024 | TCP listen backlog | antrian accept kernel | naikkan saat lonjakan | koneksi dibuang | lebih banyak memori kernel | terlalu kecil membuang koneksi |
| workers | 0 | jumlah accept thread, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core | context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack worker thread untuk handler thread .EPOLL/.URING | RSS per thread (demand-paged) | naikkan untuk handler dalam atau local stack besar, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biaya rendah sampai kedalamannya dipakai |
| worker_stack_compress_bytes | 2097152 | stack worker saat compression aktif, diterapkan sebagai floor: stack efektif = max(worker_stack_size_bytes, ini) | RSS per thread pada .EPOLL/.URING dengan compression | naikkan bila handler yang mengompres butuh lebih | flate (sekitar 230 KB pada frame handler) dapat overflow stack kecil | RSS terbuang per worker | tanpa efek saat compression off |
| busy_poll_us | 50 | spin window SO_BUSY_POLL dalam mikrodetik untuk koneksi yang diterima (.EPOLL) | hot, kernel busy-spin sebelum menidurkan worker | naikkan untuk memangkas tail latency saat beban, 0 untuk hemat CPU idle | spin lebih pendek, lebih banyak wakeup idle-sleep, tail latency lebih tinggi | core spin 100% saat idle | no-op tanpa dukungan SO_BUSY_POLL kernel |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): koneksi baru masuk ke listener index = CPU penerima mod workers alih-alih hash 4-tuple | penempatan koneksi (per SYN, tanpa biaya hot-path) | aktifkan pada host multi-core agar koneksi dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| max_recv_buf | 6144 | buffer read per request, request terlalu besar dapat 431 | memori per koneksi dan ukuran request maksimum | naikkan untuk request besar | request ditolak dengan 431 | lebih banyak memori per koneksi | terlalu kecil menolak request valid |
| large_body_rcvbuf | 0 | SO_RCVBUF diterapkan hanya saat membaca body request besar (upload), 0 memakai default kernel | kecepatan ingest upload dan memori per koneksi saat body besar berjalan | naikkan untuk ingest upload lebih cepat | upload ingest lebih lambat (window default kernel yang sempit) | lebih banyak memori saat body besar (256 KiB menargetkan sekitar 256 MiB resident pada 256c) | hanya jalur upload yang menyentuhnya, handler request kecil tidak terpengaruh |
| body_read_timeout_ms | 30000 | maks ms Request.body() menunggu segmen berikutnya dari body multi-segmen pada fd non-blocking .EPOLL / .URING | hanya jalur upload, membatasi klien yang macet | turunkan untuk membuang uploader macet lebih cepat | upload dari klien lambat diputus lebih cepat | klien macet menahan worker lebih lama | jalur GET panas tidak punya body dan tidak pernah menunggu di sini |
| max_request_body | 8388608 | body request terbesar yang diambil body(), dihitung dari yang benar-benar tiba: panjang yang dideklarasikan melewatinya ditolak dengan 413 sebelum alokasi, body chunked berhenti di byte yang melintasinya (413) | membatasi alokasi body per request dan waktu socket | turunkan untuk membatasi upload, 0 untuk mempercayai panjang yang dideklarasikan | upload besar yang sah ditolak dengan 413 | alokasi per request bisa lebih besar | 0 hanya menghapus cek Content-Length, body chunked tetap punya plafon internal |
| uring_send_buf_size | 16384 | buffer send per koneksi untuk dispatch model .URING (max_recv_buf untuk recv) | memori per koneksi pada .URING | naikkan untuk respons lebih besar, turunkan untuk memperkecil memori per koneksi | lebih banyak pertumbuhan buffer pada respons besar | lebih banyak memori per koneksi | tanpa efek pada dispatch model lain |
| uring_idle_pool_floor | 8 | floor warm idle-connection pool per worker pada .URING | memori warm-pool vs hit allocator pada koneksi baru | naikkan untuk menjaga lebih banyak koneksi warm saat churn bursty, turunkan untuk memperkecil memori idle | lebih banyak hit allocator setelah periode sepi | lebih banyak koneksi idle tetap resident | tanpa efek pada dispatch model lain |
| uring_idle_pool_ceiling | 256 | ceiling absolut warm idle-pool per worker pada .URING (ADR-062) | memori resident pada jumlah koneksi tinggi | naikkan untuk menjaga lebih banyak warm bagi reconnect, turunkan untuk memperkecil resident set | lebih banyak hit allocator pada reconnect | lebih banyak koneksi tertutup tetap resident | menjepit antara floor dan ceiling seperti zix.Http1 |
| process_queue_len | 0 (off) | FIFO ring per worker (.URING) yang mem-park re-arm recv atau send saat submission queue penuh dan mencoba ulang pada loop pass berikutnya alih-alih menutup koneksi, 0 menonaktifkan fitur | slab per worker, hanya referensi (fd + generation), aktif hanya saat SQ penuh saat burst | atur sekitar puncak koneksi bersamaan per worker agar burst SQ-penuh mem-park alih-alih membuang koneksi | ring penuh lebih cepat saat burst, entry terbaru ditolak dan koneksi itu jatuh ke jalur close | lebih banyak slab tercadang per worker (jumlah entry kali beberapa byte) | tanpa efek pada dispatch model lain, mengikuti zix.Http1 |
| max_allocator_size | 4096 | kapasitas arena awal per koneksi, tumbuh bila terlampaui | memori per koneksi, realokasi | naikkan untuk menghindari pertumbuhan arena dini | lebih banyak event pertumbuhan arena | lebih banyak memori idle per koneksi | tetap tumbuh otomatis | 
| max_request_headers | `.LARGE` | header request maksimum, di atas tier ditolak 431 | penyimpanan parse | naikkan tier untuk klien dengan banyak header | request padat header ditolak | lebih banyak penyimpanan parse | nilai custom di atas 64 dibatasi ke 64 |
| max_response_headers | `.MINIMAL` (16) | header respons custom maksimum, dialokasikan arena seukuran ini | memori per respons | naikkan tier untuk banyak header custom | header ekstra tidak bisa diset | lebih banyak memori per respons | dialokasikan persis per request |
| conn_timeout_ms | 0 | penjaga umur koneksi (ms), 0 = nonaktif | eviction oleh timer latar | atur untuk meng-evict koneksi berumur panjang | koneksi diputus lebih cepat | koneksi berumur lebih panjang | sebaiknya >= handler_timeout_ms |
| handler_timeout_ms | 0 | budget per handler (ms), 0 = nonaktif | deadline kooperatif | atur untuk membatasi handler lambat | handler diputus lebih cepat | handler lambat berjalan lebih lama | handler harus cek ctx.isExpired() |
| send_date_header | true | sertakan header Date pada setiap respons (RFC 7231, ADR-062) | 37 byte per respons | biarkan on untuk kepatuhan, off untuk memperkecil respons | | | off membuang header standar |
| public_dir | "" | direktori root untuk serve file statis, kosong menonaktifkan | I/O disk saat hit statis | atur untuk melayani file statis | | | kosong menonaktifkan serve statis |
| public_dir_upload | "u" | subdirektori upload di bawah public_dir untuk upload multipart | | atur path upload | | | relatif terhadap public_dir |
| public_dir_cache_ttl_ms | 0 | berapa lama file static yang sudah di-resolve tetap di-cache (ms), 0 = tidak pernah di-cache (ADR-064) | satu descriptor terbuka per varian cache, bukan open plus stat per request | atur di atas 0 agar file static tetap terbuka dan header 200-nya sudah dirender | setiap request membuka dan membaca ulang file | file yang diedit di disk butuh sampai satu window untuk terlihat | berbagi tabel proses dengan engine lain |
| public_dir_cache_max_entries | 256 | jumlah slot cache static, satu slot per file plus sibling .br dan .gz-nya | descriptor dan tabel slot demand-paged | naikkan untuk public_dir yang lebih besar | file di luar tabel disajikan tanpa cache | lebih banyak descriptor ditahan | dibulatkan turun ke pangkat dua, di-clamp terhadap budget descriptor proses |
| compress | false | aktifkan gzip/deflate/brotli dengan Accept-Encoding | CPU vs ukuran body | aktifkan lewat jaringan | | | murni biaya CPU pada loopback |
| compression_min_size | 256 | ukuran body minimum sebelum kompresi | pemeriksaan per respons | naikkan agar melewati body kecil | body kecil dikompres | body lebih besar melewati kompresi | terlalu kecil memboroskan CPU |
| compression_max_out | 262144 | byte output terkompresi maksimum | batas per respons | naikkan untuk body lebih besar | body lebih besar tanpa kompresi | lebih banyak CPU sebelum menyerah | di atas ini dikirim tanpa kompresi |
| response_cache | false | aktifkan cache respons per worker | memori cache | aktifkan untuk respons panas | | | off membuat API cache jadi send biasa |
| cache_max_entries | 256 | jumlah slot cache (pangkat dua) | memori per worker | naikkan untuk lebih banyak key | lebih banyak miss | lebih banyak memori | dikali jumlah worker |
| cache_max_value_bytes | 16384 | batas respons per slot | memori per slot | naikkan untuk respons cache lebih besar | respons besar melewati cache | lebih banyak memori | tetap ramping |
| cache_ttl_ms | 1000 | kesegaran cache default (ms) | hit rate vs kebasian | naikkan untuk hit rate, turunkan untuk kesegaran | kedaluwarsa lebih cepat, lebih banyak miss | data lebih basi | terlalu tinggi menyajikan data basi |
| cache_max_total_bytes | 0 | batas memori cache per worker, 0 = tanpa batas | membatasi memori cache | atur untuk membatasi RAM cache | jumlah entri dikurangi agar muat | penuh entries * value_bytes | 0 menonaktifkan batas |
| tls | null | TLS context untuk https (opt-in, ADR-053), null = cleartext | mengaktifkan TLS, band performa tersendiri | pasang context untuk melayani https | | | null melayani cleartext |
| tls_port | 0 | port bind https pendamping untuk dual listener (ADR-060) | satu worker fleet melayani cleartext + TLS | isi bersama tls untuk melayani keduanya dari satu server | 0 mempertahankan perilaku single-listener | | butuh tls diisi, harus beda dari port |
| logger | null | logger opsional, engine menulis satu record [component:access] per respons | | pasang untuk access logging | | | menyuntikkan ctx.logger untuk handler |

## TCP (`TcpServerConfig`)

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nilai nol ditolak |
| dispatch_model | wajib | model concurrency | menentukan strategi | `.EPOLL`/`.URING` di Linux untuk skala | | | di luar Linux hanya `.ASYNC` yang jalan |
| kernel_backlog | 4096 | TCP listen backlog | antrian accept kernel | naikkan saat lonjakan | koneksi dibuang | lebih banyak memori kernel | terlalu kecil membuang koneksi |
| workers | 0 | jumlah accept thread, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core | context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack worker thread untuk handler thread .EPOLL/.URING | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biaya rendah sampai kedalamannya dipakai |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): koneksi baru masuk ke listener index = CPU penerima mod workers alih-alih hash 4-tuple | penempatan koneksi (per SYN, tanpa biaya hot-path) | aktifkan pada host multi-core agar koneksi dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| max_recv_buf | 4096 | byte payload maksimum per frame, terlalu besar menutup koneksi | memori per koneksi dan frame maksimum | naikkan untuk frame lebih besar | frame besar menutup koneksi | lebih banyak memori per koneksi | terlalu kecil menutup frame besar yang valid |
| uring_send_buf_size | 65536 | buffer send per koneksi untuk model framed .URING (max_recv_buf untuk recv) | memori per koneksi pada .URING | naikkan untuk frame lebih besar, turunkan untuk memperkecil memori per koneksi | lebih banyak pertumbuhan buffer pada frame besar | lebih banyak memori per koneksi | tanpa efek pada dispatch model lain |
| uring_max_conns_per_worker | 65536 | koneksi konkuren maksimum yang dilacak satu worker .URING (slab terindeks fd) | slab per worker, demand-paged | naikkan untuk concurrency sangat tinggi, turunkan untuk memperkecil slab | koneksi ditolak melewati cap | slab awal lebih besar (demand-paged) | hanya model .URING |
| recv_timeout_ms | 0 | timeout receive socket per koneksi (SO_RCVTIMEO), 0 = nonaktif | memblok recv melewati ini | atur untuk membuang peer yang macet | peer dibuang lebih cepat | peer lambat ditoleransi lebih lama | 0 menunggu tanpa batas |
| send_timeout_ms | 0 | timeout send socket per koneksi (SO_SNDTIMEO), 0 = nonaktif | memblok send melewati ini | atur untuk membuang konsumen lambat | konsumen dibuang lebih cepat | konsumen lambat ditoleransi lebih lama | 0 menunggu tanpa batas |
| logger | null | logger opsional, lifecycle plus penutupan per koneksi | | pasang untuk logging | | | |

## UDP (`UdpServerConfig`)

Jalur messaging bertipe menjalankan satu loop receive async. Knob batch dan worker berlaku untuk jalur raw-bytes (`zix.Udp.Raw`, ADR-049).

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| allocator | wajib | allocator backing, harus general-purpose | | | | | ArenaAllocator membuat snapshot broadcast bocor |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, harus non-zero | | | | | nilai nol ditolak pada init |
| allow_args | false | saat true, init membaca `--ip` / `--port` dari args yang diberikan | startup saja | set true untuk override ip dan port saat runtime | | | args diabaikan saat false |
| dispatch_model | wajib | concurrency jalur raw, EPOLL/URING jalankan worker per-core | menentukan strategi | `.EPOLL`/`.URING` untuk jalur raw pada skala | | | jalur bertipe melipat model non-ASYNC ke satu loop |
| workers | 0 | jumlah worker untuk model per-core, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core | context-switching | hanya untuk EPOLL/URING |
| worker_stack_size_bytes | 524288 | stack thread worker untuk worker raw per-core (.EPOLL / .URING) | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biayanya rendah sampai kedalamannya terpakai |
| busy_poll_us | 0 | spin window SO_BUSY_POLL dalam mikrodetik untuk socket worker raw per-core (.EPOLL / .URING) | wake-up latency recvmmsg | set ke mis. 50 untuk memangkas wake-up latency saat beban | spin lebih pendek, lebih banyak wakeup idle-sleep | core spin saat idle | 0 membiarkannya tidak diset, no-op tanpa dukungan SO_BUSY_POLL kernel |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): socket index = CPU penerima mod workers per paket alih-alih hash 4-tuple | penempatan paket (di kernel, tanpa biaya hot-path) | aktifkan pada host multi-core agar datagram dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| reuse_address | false | set SO_REUSEADDR + SO_REUSEPORT untuk bind multi-worker | mengaktifkan load-balancing kernel | aktifkan untuk worker per-core | | | wajib untuk berbagi port multi-worker |
| recv_batch | 32 | datagram diterima per syscall recvmmsg (jalur raw) | syscall per batch | naikkan untuk memangkas syscall saat beban | lebih banyak syscall per datagram | buffer batch lebih besar | terlalu kecil kehilangan manfaat batching |
| send_batch | 32 | balasan digabung per flush sendmmsg (jalur raw) | syscall per flush | naikkan untuk memangkas syscall saat beban | lebih banyak syscall flush | buffer batch lebih besar | terlalu kecil kehilangan manfaat batching |
| max_recv_buf | 1500 | ukuran datagram maksimum, buffer receive per slot (jalur raw) | memori per slot | samakan dengan MTU jalur | datagram lebih besar terpotong | lebih banyak memori per slot | 1500 adalah MTU Ethernet umum |
| gso_enabled | false | UDP GSO (UDP_SEGMENT): gabungkan balasan ke tujuan yang sama berturut-turut jadi satu sendmsg per grup | syscall jalur send | aktifkan saat balasan membludak ke satu peer (flight multi-packet) | | lebih sedikit syscall send, CPU lebih rendah | diprobe saat startup, off pada kernel di bawah 4.18, hanya membantu batch multi-packet ke peer yang sama |
| endianness | `.LITTLE` | kontrak endianness wire dengan klien (typed server merelay byte mentah tanpa decode, klien yang menerapkannya pada setiap send dan receive) | konversi per paket di sisi klien | `.LITTLE` untuk klien lintas bahasa, `.BIG` untuk network order | | | harus sama antara klien dan server |
| conn_timeout_ms | 5000 | ms hening sebelum klien dianggap terputus | pelacakan liveness | turunkan untuk deteksi putus lebih cepat | klien dibuang lebih cepat | klien mati menggantung | terlalu kecil membuang klien lambat tapi hidup |
| poll_timeout_ms | 2000 | interval poll receive (ms), menentukan frekuensi cek putus | frekuensi wakeup | turunkan untuk cek lebih responsif | wakeup lebih sering | deteksi putus lebih lambat | menukar CPU dengan responsivitas |
| auto_ack | false | kirim byte ACK 0x06 saat terima sukses | satu send tambahan per paket | aktifkan untuk umpan balik at-least-once | | | menambah trafik balasan |
| error_report | false | kirim byte NACK 0x15 saat paket cacat atau kebesaran | satu send tambahan saat error | aktifkan untuk umpan balik error | | | menambah trafik balasan |
| auto_echo | false | echo paket yang diterima apa adanya | satu send tambahan per paket | aktifkan untuk perilaku echo | | | menambah trafik balasan |
| broadcast | false | relay paket yang diterima ke semua klien terhubung | satu send per klien terhubung | aktifkan untuk fan-out | | | biaya per paket naik seiring jumlah klien |
| logger | null | logger opsional, lifecycle plus per datagram | | pasang untuk logging | | | |

## HTTP/3 (`Http3ServerConfig`)

QUIC di atas UDP. Membutuhkan TLS 1.3 context (tidak ada mode cleartext).

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| allocator | wajib | allocator backing, general-purpose | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nilai nol ditolak |
| dispatch_model | wajib | concurrency: .EPOLL adalah epoll readiness loop, .URING io_uring completion loop, masing-masing satu worker SO_REUSEPORT per core | menentukan strategi | `.EPOLL`/`.URING` untuk skala multicore | | | ASYNC jalankan satu worker dengan demux CID, EPOLL/URING satu per core. .URING melipat ke .EPOLL saat io_uring tidak tersedia |
| workers | 0 | jumlah worker untuk model per-core, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core | context-switching | hanya untuk EPOLL/URING |
| worker_stack_size_bytes | 524288 | stack thread worker untuk worker per-core (.EPOLL / .URING) | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biayanya rendah sampai kedalamannya terpakai |
| busy_poll_us | 0 | spin window SO_BUSY_POLL dalam mikrodetik untuk socket worker per-core (.EPOLL / .URING) | wake-up latency recvmmsg | set ke mis. 50 untuk memangkas wake-up latency saat beban | spin lebih pendek, lebih banyak wakeup idle-sleep | core spin saat idle | 0 membiarkannya tidak diset, no-op tanpa dukungan SO_BUSY_POLL kernel |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): socket index = CPU penerima mod workers per paket alih-alih hash 4-tuple | penempatan paket (di kernel) | biarkan false pada jalur QUIC | | | steering CPU per paket merusak flow affinity QUIC (paket satu flow mendarat di worker berbeda dan kehilangan state koneksi), terukur sebagai keruntuhan throughput. No-op bila kernel tidak punya opsi ini (pra-4.5) |
| recv_batch | 32 | datagram diterima per syscall recvmmsg | syscall per batch | naikkan untuk memangkas syscall | lebih banyak syscall | buffer lebih besar | terlalu kecil kehilangan batching |
| send_batch | 32 | paket digabung per flush sendmmsg | syscall per flush | naikkan untuk memangkas syscall | lebih banyak flush | buffer lebih besar | terlalu kecil kehilangan batching |
| max_recv_buf | 1500 | ukuran datagram maksimum, buffer receive per slot | memori per slot | samakan dengan MTU jalur | datagram terpotong | lebih banyak memori | 1500 adalah MTU Ethernet umum |
| socket_rcvbuf | 4194304 | SO_RCVBUF yang diminta per socket UDP per-core, menampung burst yang tiba di antara batch recvmmsg | packet loss pada run yang syscall-bound (loss jadi retransmit) | biarkan tinggi, turunkan hanya untuk memangkas memori pada deployment kecil | lebih banyak datagram drop saat burst, lebih banyak retransmit | lebih banyak memori socket kernel per worker | dibatasi net.core.rmem_max (dan digandakan internal), 0 membiarkan default kernel |
| socket_sndbuf | 4194304 | SO_SNDBUF yang diminta per socket UDP per-core, agar flight send GSO tidak dicekik | throttling send saat flight besar | biarkan tinggi, turunkan hanya untuk memangkas memori | flight send besar tersendat pada buffer kecil | lebih banyak memori socket kernel per worker | dibatasi net.core.wmem_max, 0 membiarkan default kernel |
| gso_enabled | true | UDP GSO (UDP_SEGMENT): gabungkan flight respons multi-packet ke satu peer jadi satu sendmsg | syscall jalur send, hot | biarkan on, matikan hanya untuk A/B atau pada kernel terbatas | | lebih sedikit syscall send, CPU lebih rendah dan throughput lebih tinggi | diprobe saat startup, fallback ke sendmmsg biasa pada kernel di bawah 4.18 |
| cid_len | 8 | panjang connection ID terbitan server (byte, RFC 9000) | penanganan CID per paket | biarkan 8, panjang tetap memungkinkan steering per-core | lebih pendek, lebih sedikit CID berbeda | overhead CID per paket lebih besar | memungkinkan steering CID per-core di masa depan |
| max_idle_ms | 30000 | timeout idle koneksi (ms, RFC 9000 10.1) | liveness | turunkan untuk merebut kembali koneksi idle lebih cepat | koneksi idle ditutup lebih cepat | koneksi idle menggantung | terlalu kecil menutup koneksi lambat tapi hidup |
| max_streams | 128 | stream request konkuren maksimum (RFC 9000 4.6) | state stream per koneksi | naikkan untuk klien yang sangat multipleks | klien terblokir lebih cepat | lebih banyak state per koneksi | terlalu kecil menyerialkan klien multipleks |
| max_datagram_size | 1200 | ukuran wire yang ditargetkan untuk satu datagram respons 1-RTT, ukuran efektif adalah min(nilai ini, client max_udp_payload_size, ceiling 16 KiB) | sizing paket dan cwnd, hot | naikkan (mis. 8192) hanya di mana path MTU diketahui besar (loopback, jumbo LAN): lebih sedikit paket per respons, jadi lebih sedikit kerja per-paket header/AEAD/ack (dinding static-h3) | paket lebih kecil, lebih banyak kerja per-paket | lebih sedikit paket, lebih sedikit kerja per-paket, tapi nilai di atas path MTU nyata memicu fragmentasi di WAN | tidak pernah mengirim melebihi batas yang diiklankan klien, juga basis cwnd awal, 1200 adalah minimum QUIC |
| max_stream_chunk | 0 (derive) | batas eksplisit byte payload STREAM-frame per paket 1-RTT, 0 menurunkannya dari ukuran datagram | byte per paket, hot | biarkan 0 supaya menaikkan max_datagram_size otomatis melebarkan paket | nilai non-zero kecil memaksa lebih banyak paket per respons | nilai non-zero besar mendekati ukuran datagram | 0 berarti ukuran datagram dikurangi ruang frame dan tag |
| max_inflight_packets | 128 | paket respons in flight per koneksi sebelum menunggu ack (batas congestion window dan kedalaman ring loss-detection) | throughput respons multi-paket, hot | naikkan untuk throughput per-koneksi lebih tinggi pada respons besar | burst kirim lebih kecil, lebih ramah ke receive buffer klien yang terbatas, throughput per-koneksi lebih rendah | window lebih besar, respons besar mengalir dalam lebih sedikit ronde ACK-clocked, pembukuan kirim lebih banyak | dibatasi ke kapasitas ring saat kompilasi (128 paket, connection.zig max_sent_ranges), melewatinya perlu itu dinaikkan dan rebuild |
| initial_window_packets | 32 | congestion window awal dalam paket, seberapa banyak respons keluar sebelum ack pertama (RFC 9002 7.2) | latency first-flight, hot | naikkan pada path low-loss supaya respons perlu lebih sedikit ronde ACK-clocked | burst pertama lebih kecil, lebih banyak ronde untuk respons besar | burst pertama lebih besar, lebih sedikit ronde, risiko loss dan bufferbloat di jaringan lossy nyata | burst pertama efektif adalah min dari nilai ini, max_inflight_packets, dan kapasitas ring |
| max_pending_request_streams | 16 | request stream yang dirakit satu worker sekaligus, hanya request yang dipecah client antar paket yang memakai slot | memori worker: nilai ini * max_request_stream_bytes * 9/8 per worker | naikkan bila banyak client mengunggah bersamaan, 0 mematikan penahanan untuk server yang route-nya tidak menerima body | lonjakan upload bersamaan lebih cepat dijawab 503 | lebih banyak memori ditahan per worker | request yang tiba utuh dalam satu paket (setiap GET yang conforming) tidak pernah menyentuh pool, jadi ini tidak membebani jalur GET |
| max_request_stream_bytes | 8192 | byte yang boleh dipegang satu request stream terakit, body request terbesar yang bisa diberikan utuh ke handler | memori worker, lihat baris di atas | naikkan ke upload terbesar yang diterima route | body melewatinya diantar terpotong, bodyComplete() false | lebih banyak memori ditahan per worker | dinaikkan ke 1024 bila diset lebih kecil, body terpotong tetap melaporkan apa yang benar-benar tiba lewat bodyReceived() |
| public_dir | "" | direktori root untuk penyajian file static, kosong menonaktifkannya (ADR-064) | satu snapshot di memori per file yang disajikan | atur untuk menyajikan file static bagi route yang tidak cocok handler | | | hanya 200 file utuh, Range tidak disajikan di atas HTTP/3, dan tidak berfungsi kecuali public_dir_cache_ttl_ms diatur |
| public_dir_cache_ttl_ms | 0 | berapa lama file static yang sudah di-resolve tetap di-cache (ms), 0 = penyajian static MATI di engine ini | menahan setiap file yang disajikan di memori | atur di atas 0 agar penyajian static aktif sama sekali | | file yang diedit di disk butuh sampai satu window untuk terlihat | BERBEDA dari engine lain, 0 menonaktifkan penyajian static sepenuhnya: body respons HTTP/3 hidup lebih lama dari handler-nya, jadi file hanya bisa disajikan dari cache |
| public_dir_cache_max_entries | 256 | jumlah slot cache static, satu slot per file plus sibling .br dan .gz-nya | descriptor, plus satu snapshot per file yang disajikan engine ini | naikkan untuk public_dir yang lebih besar | file di luar tabel tidak disajikan di sini | lebih banyak memori ditahan | dibulatkan turun ke pangkat dua, di-clamp terhadap budget descriptor proses, dan setiap snapshot dibatasi 8 MiB |
| tls | null (wajib) | TLS 1.3 context: cert, key, ALPN, QUIC butuh TLS 1.3 | mengaktifkan QUIC | pasang TLS 1.3 context | | | null ditolak, QUIC tidak punya mode cleartext |
| logger | null | logger opsional untuk baris lifecycle | | pasang untuk logging | | | |

## WebRTC (`WebrtcServerConfig`)

ICE-lite, DTLS 1.2, data channel SCTP, forwarding media SRTP opsional, semuanya di satu port UDP. Butuh TLS context yang kuncinya ECDSA P-256 (tidak ada mode cleartext).

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| allocator | wajib | allocator penopang, general-purpose | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nilai nol ditolak saat run() |
| dispatch_model | wajib | concurrency: .ASYNC satu worker portable, .EPOLL dan .URING satu worker SO_REUSEPORT per core | menentukan strategi | `.EPOLL`/`.URING` di Linux untuk skala multicore | | | di luar Linux hanya `.ASYNC` yang jalan. Tidak ada knob steering CPU: satu peer adalah 4-tuple-nya dan steering akan memecah sesi |
| workers | 0 | jumlah worker untuk model per-core, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core terpakai | context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack thread worker untuk model per-core | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | diabaikan oleh `.ASYNC` |
| max_recv_buf | 1500 | ukuran datagram maksimum, buffer penerima per slot | memori per slot | samakan dengan MTU path | datagram terpotong | lebih banyak memori | 1500 adalah MTU Ethernet umum |
| socket_rcvbuf | 1048576 | SO_RCVBUF yang diminta dalam byte | datagram hilang saat burst | biarkan besar, turunkan hanya untuk memangkas memori | lebih banyak kehilangan saat burst | lebih banyak memori socket kernel | 0 memakai default kernel |
| socket_sndbuf | 1048576 | SO_SNDBUF yang diminta dalam byte | pengiriman tertahan saat flight besar | biarkan besar, turunkan hanya untuk memangkas memori | flight tertahan pada buffer kecil | lebih banyak memori socket kernel | 0 memakai default kernel |
| ice_ufrag | "" (wajib) | ufrag agent ini, paruh pertama USERNAME yang dibawa setiap check | | isi, lalu publikasikan nilai yang sama di SDP answer | | | kosong ditolak saat run() |
| ice_password | "" (wajib) | password agent ini, kunci yang dipakai memverifikasi setiap check | | isi, lalu publikasikan nilai yang sama di SDP answer | | | kosong ditolak saat run(), dan inilah satu-satunya gerbang yang nyata |
| peer_ice_ufrag | "" | ufrag peer, paruh kedua USERNAME tersebut | | isi bila signalling sudah memberi tahu ufrag peer | | | kosong berarti check ditolak dengan 401 sampai diketahui. Diabaikan bila accept_any_peer_ice_ufrag menyala |
| accept_any_peer_ice_ufrag | false | menerima check apa pun sebutan peer, menyisakan ice_password sebagai satu-satunya gerbang | | set true untuk client browser mana pun | | | browser menarik ufrag baru per peer connection, jadi tanpa ini setiap check ditolak. Mati secara default supaya server yang menyebut satu peer tetap menolak yang lain |
| tls | null (wajib) | TLS context: certificate dan kunci yang menandatangani ServerKeyExchange | mengaktifkan DTLS | pasang context yang kuncinya ECDSA P-256 | | | null ditolak saat run(), begitu juga kunci yang bukan ECDSA P-256 (satu-satunya suite DTLS 1.2 di sini adalah ECDHE-ECDSA, RFC 5289) |
| max_handshake_fragment | 1024 | badan fragment handshake terbesar yang dikeluarkan server ini | jumlah record per flight | turunkan bila MTU path kecil | lebih banyak fragment per flight | record bisa melampaui MTU path lalu dibuang | diukur supaya satu record muat di MTU path |
| carry_media | false | apakah server ini meneruskan audio dan video antar peer-nya | mengaktifkan jalur SRTP dan buffer-nya | set true untuk server forwarding | | buffer media dialokasikan per peer | mati berarti tidak ada kunci diekspor dan RTP dibuang di tempat ia dirutekan. SDP answer punya switch terpisah, nyalakan keduanya |
| path_max_bytes | 1200 | paket SCTP terbesar yang muat di path, overhead DTLS sudah dikurangi | jumlah fragment per pesan | naikkan hanya bila MTU path diketahui besar | lebih banyak fragment per pesan | paket bisa melampaui MTU path | 1200 sesuai default WebRTC yang konservatif |
| outbound_streams | 128 | berapa stream keluar yang diminta association | state per association | naikkan untuk banyak channel bersamaan | lebih sedikit channel tersedia | lebih banyak state per association | dinegosiasikan turun ke yang ditawarkan peer |
| inbound_streams | 128 | berapa stream masuk yang diterima association | state per association | naikkan untuk banyak channel bersamaan | peer dibatasi lebih awal | lebih banyak state per association | |
| max_channels | 64 | berapa channel yang boleh terbuka pada satu peer, dihitung dari kedua sisi | registry per peer | naikkan untuk peer dengan banyak channel | open ditolak lebih awal | lebih banyak memori per peer | |
| max_peers | 64 | berapa peer yang dipegang satu worker sekaligus | memori per worker | naikkan untuk room lebih besar | peer baru dibuang lebih awal | lebih banyak memori per worker | dihitung PER WORKER, jadi N worker menampung sampai N * max_peers. Datagram dari peer baru di atas batas dibuang, yang terbaca oleh peer itu sebagai check yang tidak dijawab |
| peer_idle_ms | 30000 | berapa lama peer boleh tanpa datagram sebelum dilepas | kecepatan reklamasi | turunkan untuk reklamasi lebih cepat | peer hidup tapi diam ikut dilepas | peer mati bertahan lebih lama | menangani kasus browser menutup tab tanpa shutdown yang rapi |
| tick_interval_ms | 250 | seberapa sering engine melihat peer-nya saat tidak ada datagram datang | CPU saat idle, dan batas bawah keterlambatan retransmit | turunkan untuk timer lebih ketat, naikkan untuk menenangkan server idle | lebih banyak bangun di server idle | retransmit atau pelepasan idle bisa terlambat sebesar ini | waktu tunggu diturunkan dari deadline dan dibatasi nilai ini, jadi ini juga biaya server yang sepenuhnya sunyi |
| logger | null | logger opsional untuk baris lifecycle | | pasang untuk logging | | | engine bisu tanpa logger, dan itu default yang keliru untuk demo browser |

## FIX (`FixServerConfig`)

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| ip | wajib | alamat bind | | | | | |
| port | wajib | port bind, non-zero | | | | | nilai nol ditolak |
| comp_id | wajib | SenderCompID server (tag 49) | | | | | wajib untuk sesi FIX |
| dispatch_model | wajib | model concurrency | menentukan strategi | `.EPOLL`/`.URING` di Linux untuk skala | | | di luar Linux hanya `.ASYNC` yang jalan |
| kernel_backlog | 1024 | TCP listen backlog | antrian accept kernel | naikkan saat lonjakan | koneksi dibuang | lebih banyak memori kernel | terlalu kecil membuang koneksi |
| workers | 0 | worker accept/event-loop, 0 = cpu_count | paralelisme | biarkan 0 (otomatis) | lebih sedikit core | context-switching | diabaikan oleh `.ASYNC` |
| worker_stack_size_bytes | 524288 | stack worker thread untuk handler thread .EPOLL dan .URING | RSS per thread (demand-paged) | naikkan untuk handler dalam, turunkan untuk memangkas RSS | stack overflow pada handler dalam | RSS terbuang per worker | biaya rendah sampai kedalamannya dipakai |
| reuseport_cbpf | false | steering SO_ATTACH_REUSEPORT_CBPF (.EPOLL / .URING): koneksi baru masuk ke listener index = CPU penerima mod workers alih-alih hash 4-tuple | penempatan koneksi (per SYN, tanpa biaya hot-path) | aktifkan pada host multi-core agar koneksi dilayani pada core yang menerimanya | | | no-op bila kernel tidak punya opsi ini (pra-4.5) |
| uring_send_buf_size | 65536 | buffer send per koneksi untuk dispatch model .URING | memori per koneksi pada .URING | naikkan untuk balasan lebih besar, turunkan untuk memperkecil memori per koneksi | lebih banyak pertumbuhan buffer pada balasan besar | lebih banyak memori per koneksi | tanpa efek pada dispatch model lain |
| uring_max_conns_per_worker | 65536 | koneksi konkuren maksimum yang dilacak satu worker .URING (slab terindeks fd) | slab per worker, demand-paged | naikkan untuk concurrency sangat tinggi, turunkan untuk memperkecil slab | koneksi ditolak melewati cap | slab awal lebih besar (demand-paged) | hanya model .URING |
| default_heartbeat_secs | 30 | HeartBtInt default (detik) yang dikirim di respons Logon saat klien tidak mengisi tag 108 | bukan perf, liveness sesi | naikkan untuk mengurangi trafik heartbeat, turunkan untuk deteksi dead-peer lebih cepat | lebih banyak pesan heartbeat | deteksi sesi mati lebih lambat | hanya dipakai saat klien tidak mengisi tag 108 |
| heartbeat_timeout_ms | 0 | ms sebelum mengirim TestRequest, lalu Logout bila tak ada balasan, 0 = nonaktif | liveness sesi | turunkan untuk deteksi sesi mati lebih cepat | lebih banyak trafik heartbeat, deteksi lebih cepat | lebih lambat mendeteksi sesi mati | hanya berlaku setelah Logon |
| conn_timeout_ms | 0 | tutup idle (ms) saat heartbeat off, 0 = nonaktif | liveness sesi | atur saat tidak memakai heartbeat | koneksi ditutup lebih cepat | sesi idle menggantung | tidak mengirim TestRequest sebelum menutup |
| handler_timeout_ms | 0 | budget handler per pesan (ms), 0 = nonaktif | deadline kooperatif | atur untuk membatasi handler lambat | handler diputus lebih cepat | handler lambat berjalan lebih lama | Route.timeout_ms per-route menimpa ini |
| logger | null | logger opsional, lifecycle plus session() per pesan | | pasang untuk logging | | | |

## UDS (`UdsServerConfig`)

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| io | wajib | backend std.Io | | | | | |
| allocator | wajib | allocator backing | | | | | |
| path | wajib | path filesystem untuk file socket (maks 107 byte) | | | | | di-unlink sebelum bind dan saat keluar |
| kernel_backlog | 128 | listen backlog sebelum accept() | antrian accept kernel | naikkan saat lonjakan | koneksi dibuang | lebih banyak memori kernel | terlalu kecil membuang koneksi |
| max_recv_buf | 4096 | byte payload maksimum per frame, terlalu besar menutup koneksi | memori per koneksi dan frame maksimum | naikkan untuk frame lebih besar | frame besar menutup koneksi | lebih banyak memori per koneksi | terlalu kecil menutup frame besar yang valid |
| recv_timeout_ms | 0 | timeout receive socket (SO_RCVTIMEO), 0 = nonaktif | memblok recv melewati ini | atur untuk membuang peer macet | peer dibuang lebih cepat | peer lambat ditoleransi | 0 menunggu tanpa batas |
| send_timeout_ms | 0 | timeout send socket (SO_SNDTIMEO), 0 = nonaktif | memblok send melewati ini | atur untuk membuang konsumen lambat | konsumen dibuang lebih cepat | konsumen lambat ditoleransi | 0 menunggu tanpa batas |
| logger | null | logger opsional untuk baris lifecycle | | pasang untuk logging | | | |

## TLS context (`Tls.Context.Config`)

Policy TLS sisi server, divalidasi sekali saat init. Pasang `Tls.Context` yang sudah dibangun lewat pointer ke field `tls` sebuah engine. Mengosongkan field opsional menghasilkan default aman (forward secrecy, AEAD, ECDHE-only).

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| cert_path | wajib | path PEM ke sertifikat end-entity (ECDSA P-256, Ed25519, atau RSA) | load startup | | | | wajib |
| key_path | wajib | path PEM ke private key yang cocok dengan cert_path | load startup | | | | wajib, harus cocok dengan cert |
| alpn | kosong | protokol ALPN yang ditawarkan, urutan preferensi server | handshake | set `.{ .HTTP_1_1 }` untuk Http1, `.{ .H2 }` untuk Http2 | | | browser butuh ALPN h2 untuk HTTP/2 over TLS |
| min_version | `.TLS_1_2` | batas bawah versi, rentang valid TLS 1.2 sampai 1.3 | kompatibilitas handshake | naikkan ke `.TLS_1_3` untuk mewajibkan 1.3 | | | 1.0/1.1 tidak pernah ditawarkan (RFC 8996) |
| max_version | `.TLS_1_3` | batas atas versi | handshake | turunkan hanya untuk interop lawas | | | batas atas 1.2 menolak 1.3 |
| curves | set ECDHE default | curve ECDHE urutan preferensi | pertukaran kunci handshake | atur ulang untuk kompatibilitas klien | | | nilai tak didukung (P384, MLKEM768) ditolak saat init |
| ciphers | set AEAD default | cipher suite AEAD urutan preferensi, 1.3 dan 1.2 | handshake | atur ulang untuk kompatibilitas klien | | | nilai tak didukung (AES_256, CHACHA20, suite RSA apa pun) ditolak saat init |
| prefer_server_ciphers | true | utamakan urutan cipher server di atas klien | seleksi handshake | biarkan on untuk seleksi yang dapat diprediksi | | | dengan set suite tunggal pilihannya identik |
| hsts_max_age_s | 0 | HSTS max-age dalam detik (RFC 6797), 0 = off | satu header respons | set untuk mengaktifkan Strict-Transport-Security | | | nilai panjang mengunci klien ke https |

## Logger (`Logger.Config`)

Bangun satu Logger dengan config ini dan lampirkan lewat pointer ke field `logger` engine mana pun. Sebagian besar sizing Logger bersifat compile-time. Satu knob runtime adalah buffer write file.

| field | default | fungsi | dampak performa | cara menyetel | jika lebih kecil | jika lebih besar | konsekuensi salah atur |
| :- | :- | :- | :- | :- | :- | :- | :- |
| console | `.OFF` | mode output console | | set untuk mengaktifkan output console | | | |
| console_min_level | `.INFO` | level minimum untuk output console | | naikkan untuk membungkam console | | | |
| console_fd | `null` | descriptor tujuan record console, null berarti stderr | | set untuk mengirim output console ke tempat lain | | | descriptor dimiliki pemanggil dan harus tetap terbuka selama logger hidup |
| save_path | "" | direktori untuk file log, kosong menonaktifkan file logging | I/O disk saat diisi | set untuk mengaktifkan file logging | | | direktori harus sudah ada |
| save_file | "log" | nama dasar file log | | set nama dasar file | | | |
| save_min_level | `.INFO` | level minimum untuk output file | | naikkan untuk menulis lebih sedikit baris ke file | | | |
| max_lines | 1000000 | baris per file sebelum rotasi ke nomor urut berikutnya | frekuensi rotasi | naikkan untuk file lebih sedikit dan besar | rotasi lebih sering | file lebih besar | |
| write_buf_size | 65536 | ukuran buffer write file (byte), membatch baris log per write() ke disk | batching write() log | naikkan untuk memangkas syscall disk, turunkan untuk membatasi memori | flush lebih sering | window kehilangan ter-buffer lebih besar saat crash | minor |

## Catatan

- Field wajib (`io`, `ip`, `port`, `allocator`, `path`, `comp_id`, `cert_path`, `key_path`, `ice_ufrag`, `ice_password`) tidak punya default dan harus diisi. Port nol ditolak saat init oleh `zix.Tcp` / `zix.Udp` / `zix.Fix` (dan client-nya), dan saat `run()` oleh `zix.Http2` / `zix.Grpc` / `zix.Http3` / `zix.Webrtc`. `zix.Http1` dan `zix.Http` tidak memvalidasinya (port 0 bind ke port ephemeral pilihan kernel).
- `io`, `logger`, dan `tls` dimiliki pemanggil: dilewatkan lewat handle atau pointer dan harus hidup lebih lama dari server.
- `.EPOLL` dan `.URING` khusus Linux. Di luar Linux `run()` mengembalikan `error.ZixDispatchModelUnsupported`, jadi pilih `.ASYNC` di sana. Jalur TLS mengikuti model: `.EPOLL` / `.URING` terminasi di worker tls_mux yang multiplexed, `.ASYNC` di tls_serve.
- Fitur compression dan response-cache aktif hanya pada `.EPOLL` dan `.URING` (shared-nothing, satu pemilik per worker).
