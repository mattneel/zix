# Deployment WebTransport publik

Bagaimana endpoint HTTP/3 dan WebTransport milik zix dilayani di internet publik, dari browser, tanpa flag
browser dan tanpa peringatan sertifikat.

---

## Status

Sudah didemonstrasikan. Sebuah session WebTransport terbuka dari browser biasa terhadap hostname dengan
sertifikat dari otoritas publik, dengan TLS diterminasi oleh proses server itu sendiri.

---

## Tujuan

- Browser menjangkau endpoint ini tanpa memasang apa pun, tanpa `--origin-to-force-quic-on`, dan tanpa
  `--ignore-certificate-errors-spki-list`.
- Proses server memiliki session TLS dari awal sampai akhir.
- Satu origin melayani halaman dan session, yang disyaratkan WebTransport: URL sebuah session haruslah
  origin milik halamannya sendiri, karena browser tidak akan menemukan HTTP/3 untuk origin yang belum
  pernah menerima pemberitahuannya.

---

## Bentuk

```
browser
  |  HTTPS/1.1 lewat TCP    -> halaman      (eksternal 443, internal 9444)
  |  HTTP/3 lewat QUIC/UDP  -> session      (eksternal 443, internal 443)
  |
  v
edge platform (sebuah kabel, bukan terminator TLS)
  |
  v
proses zix: TLS diterminasi di sini, kedua listener pada satu origin
```

Dua transport pada satu hostname. Halaman tiba lewat TCP dan session lewat UDP, dan originnya sama untuk
keduanya. Halaman memberitahukan layanan HTTP/3 lewat `Alt-Svc` pada port yang dipakai browser untuk
terhubung, dan itulah yang memungkinkan browser yang belum pernah melihat endpoint ini memakai HTTP/3 untuk
sessionnya.

---

## Persyaratan platform

Ini berasal dari deployment di Fly.io dan dicatat karena masing-masingnya gagal dengan cara yang tidak
menyebutkan penyebabnya.

| Persyaratan | Apa yang rusak tanpanya |
| :- | :- |
| Service tidak membawa `handlers` | Edge menerminasi TLS dan mengeluarkan plaintext, sehingga handshake QUIC tidak pernah sampai ke proses. Service dengan daftar handler kosong adalah kabel passthrough. |
| Listener UDP mengikat port tempat datagram tiba | Port pada service UDP tidak ditulis ulang, hanya alamatnya. Service eksternal 443 ke internal 9444 mengantarkan datagram di 443, sehingga listener di 9444 menunggu trafik yang tidak mungkin datang. Service TCP memang menulis ulang port. |
| Listener UDP mengikat alamat UDP milik platform | Alamat yang harus diikat listener UDP bukanlah wildcard. Alamat sumber balasannya diambil dari alamat yang diikat, dan balasan dari alamat lain dibuang oleh edge. |
| Alamat IPv4 khusus | Alamat bersama tidak bisa membawa rute UDP. |
| Sertifikat diperoleh oleh mesinnya | Sertifikat yang dipegang edge tidak berguna: handshake-nya membutuhkan private key. |

Gejala dari aturan port itu perlu disebut sendiri: klien melaporkan `QUIC_NETWORK_IDLE_TIMEOUT` dengan
`num_undecryptable_packets: 0`, dan penangkapan paket yang difilter pada port internal tidak mencatat apa
pun sementara datagram jelas-jelas sedang dikirim.

---

## Sertifikat

Sertifikatnya diterbitkan untuk mesinnya, lewat challenge DNS-01, oleh klien ACME dengan plugin penyedia
DNS. DNS-01 alih-alih HTTP-01 karena tidak butuh port masuk: pada deployment yang seluruh desainnya adalah
TLS berakhir di dalamnya, port untuk challenge HTTP adalah permukaan kedua yang ada hanya untuk dipindai.

- Sertifikat dan key-nya tersimpan di volume mesin, sehingga restart memakainya kembali.
- Key dari klien ACME dikonversi ke bentuk yang diterima pembaca PEM server ini (SEC1, bukan PKCS#8).
- Perpanjangan berjalan di mesinnya.

### Rantai sertifikat disajikan utuh

Pembaca PEM mendekode setiap blok CERTIFICATE pada berkas, entitas akhir lebih dulu, dan pesan Certificate
pada TLS membawa tiap blok sebagai satu entri, sehingga klien menerima leaf beserta intermediate yang
merantainya ke otoritasnya. Itulah yang dibutuhkan klien ketat: klien yang belum memegang intermediate
melaporkan penerbit lokalnya tidak ditemukan lalu menolak koneksi. Entrypoint karena itu menyalin berkas
fullchain dari klien ACME, bukan menyederhanakannya menjadi satu sertifikat.

Satu rantai berukuran beberapa kilobyte, lebih besar daripada satu paket Handshake QUIC, jadi server memecah
handshake flight ke sebanyak paket yang diperlukan, masing-masing membawa CRYPTO frame pada offset yang
dipakai peer untuk menyusun ulang.

---

## Verifikasi

Setiap lapisan diperiksa sendiri-sendiri, karena kegagalan di satu lapisan terlihat seperti kegagalan di
lapisan berikutnya.

| Lapisan | Pemeriksaan | Harapan |
| :- | :- | :- |
| DNS | resolve hostname-nya | alamat khusus itu |
| TLS | minta halamannya tanpa mengabaikan verifikasi | sertifikat dari otoritas publik |
| Passthrough edge | minta halamannya lalu periksa penerbitnya | sertifikat aplikasinya, bukan milik edge |
| Listener | log prosesnya | dua listener: HTTP/3 pada port UDP yang diteruskan, HTTPS/1.1 pada port internal |
| Pengantaran UDP | penangkapan pada port yang diteruskan sambil mengirim | datagram tiba di mesinnya |
| Rantai | periksa sertifikat yang disajikan server | leaf beserta intermediate yang merantainya ke otoritasnya |
| Session | tekan kontrol session di halamannya | session terbuka, dilaporkan lewat HTTP/3 |
| Permintaan session | panel protokol di halamannya | dua koneksi yang dipisahkan: koneksi dokumennya sendiri, dan session lewat HTTP/3 dengan binding yang disepakati server; baris session adalah CONNECT yang diterima server, sampai ke token `:protocol`, path, dan authority |
| Penghitung | view state di halamannya | pesan yang diterima pada stream, patch yang menggerakkan view durable, dan revisi durable: balasan pengukuran adalah pesan, bukan patch |
| Laju | tekan tombol ukur di halamannya | round trip pada kedua kanal beserta batch asal tiap persentil, dan satu pertukaran 4 KiB yang dilabeli sebagai satu pertukaran |

---

## Bukan apa

- Bukan endpoint scale-to-zero. Fly.io tidak menyalakan mesin yang berhenti karena paket UDP masuk, sebab
  service UDP mengikat alamat UDP secara langsung dan tidak pernah melewati proxy yang memutuskan untuk
  menyalakan mesin. Endpoint yang berhenti harus dinyalakan oleh hal lain: permintaan ke service HTTP,
  atau panggilan API.
- Bukan deployment reverse-proxy umum. Passthrough-lah yang membuat QUIC bekerja, dan itu juga berarti
  platformnya tidak bisa memeriksa, merutekan, atau mengubah trafiknya.
