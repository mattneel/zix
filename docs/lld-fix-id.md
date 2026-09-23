# LLD: zix.Fix (internal)

Struktur data internal dan algoritma untuk implementasi sesi FIX 4.x.

---

## Struktur Data

### Field

```zig
pub const Field = struct {
    tag: Tag,
    value: []const u8, // zero-copy slice into the receive buffer
};
```

Zero-copy: `value` merupakan slice langsung ke dalam buffer penerimaan yang disediakan pemanggil. Buffer tidak boleh ditimpa selama fields masih digunakan.

### Buffer Penerimaan Pesan

`serveConn` mempertahankan dua stack buffer:

```
recv_buf: [MAX_MSG_SIZE * 2]u8    // 16 KB, mengakumulasi byte dari loop takeByte
recv_len: usize                   // jumlah byte yang saat ini ada di recv_buf
```

Setelah setiap pesan lengkap diproses, byte tersisa (pesan yang di-pipeline atau sebagian pesan berikutnya) digeser ke posisi depan:

```
recv_buf:  [complete message][leftover bytes][free]
            diproses dan dibuang   digeser ke recv_buf[0]
```

### Array fields

```zig
var fields: [MAX_FIELDS]Field = undefined;
```

Dialokasikan di stack dan digunakan ulang untuk setiap pesan dalam loop sesi. `MAX_FIELDS = 64` mencukupi untuk semua tipe pesan standar FIX 4.x.

---

## Algoritma serveConn

```
serveConn(stream, io, comp_id, opts):
    reader = stream.reader(io, &rd_buf)
    writer = stream.writer(io, &wr_buf)
    recv_len = 0

    loop:
        loop takeByte sampai findMessageEnd(recv_buf[0..recv_len]) mengembalikan indeks akhir
        raw = recv_buf[0..end]

        if not verifyChecksum(raw): return

        nf = parseFields(raw, &fields)
        fslice = fields[0..nf]

        msg_type = getField(fslice, .MsgType) or return
        sender   = getField(fslice, .SenderCompID) or return
        seq      = parseInt(getField(fslice, .MsgSeqNum) or "0")

        switch msg_type:
            "A" -> buildMessage(logon reply, sender/target swapped, seq=1)
                   writer.writeAll
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "Logon")
            "5" -> buildMessage(logout reply)
                   writer.writeAll
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "Logout")
                   return
            "0" -> buildMessage(heartbeat reply)
                   writer.writeAll
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "Heartbeat")
            "1" -> buildMessage(heartbeat reply dengan TestReqID di-echo)
                   writer.writeAll
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "TestRequest")
            _ (routes non-kosong, setelah Logon):
                   for route in opts.routes:
                       if msg_type == route.msg_type:
                           effective_ms = min(route.timeout_ms, opts.handler_timeout_ms) atau yang non-zero
                           ctx = FixContext{ sender_comp_id, target_comp_id=comp_id, deadline_ns, fd, &seq_out }
                           route.handler(fslice, &ctx)
                           logger.session(msg_type, sender, comp_id, seq, "dispatch")
                           break
                   (tidak ada rute yang cocok: diabaikan diam-diam)
            _ (routes kosong, mode echo):
                   saring field header sesi (BeginString, BodyLength, MsgType, SenderCompID,
                       TargetCompID, MsgSeqNum, SendingTime, CheckSum) dari fslice
                   buildMessage(out_buf, comp_id, peer, seq_out, msg_type, body_fields)
                   writer.writeAll(out_buf[0..n])
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "msg")

        geser byte tersisa: recv_buf[0..] = recv_buf[end..recv_len]
        recv_len -= end
```

---

## Algoritma buildMessage

Tag ditulis dalam urutan standar FIX:

1. `8=FIX.4.2\x01` (BeginString)
2. `9=` + placeholder (BodyLength, ditambal setelah body diketahui)
3. Body: `35=T\x01 49=sender\x01 56=target\x01 34=seq\x01 <extra fields>\x01`
4. Hitung BodyLength (semua byte mulai dari awal tag-35 hingga akhir SOH field body terakhir)
5. Tambal placeholder `9=` di output buffer
6. `10=CCC\x01` (checksum desimal 3 digit dari semua byte yang sudah ditulis)

Mengembalikan total byte yang ditulis ke dalam output buffer.

---

## Checksum

`computeChecksum(buf: []const u8) u8`:
- Menjumlahkan setiap byte dari `buf` sebagai u32 (tidak overflow untuk pesan hingga MAX_MSG_SIZE).
- Mengembalikan `@truncate(sum % 256)`.

`verifyChecksum(buf: []const u8) bool`:
- Mengekstrak nilai `10=NNN\x01` dari byte-byte di akhir pesan.
- Menghitung checksum atas semua byte hingga (tidak termasuk) tag `\x0110=`.
- Mengembalikan false jika field tag-10 cacat, tidak ada, atau nilainya tidak cocok.

---

## findMessageEnd

Pemindaian linear untuk pola `10=` yang diawali SOH:

```
for i in 0..buf.len-4:
    if buf[i] == SOH and buf[i+1]=='1' and buf[i+2]=='0' and buf[i+3]=='=':
        scan forward from i+4 for the closing SOH
        if found at index j: return j + 1
        else: return null   // pesan belum lengkap
return null
```

Prefiks SOH mencegah false positive di mana `10=` muncul di dalam nilai field. Mengembalikan indeks satu posisi setelah SOH penutup field checksum.

---

## Dispatch Model

`FixServer` menggunakan infrastruktur dispatch yang sama dengan `TcpServer`:

| Model | Fungsi entry | Dispatch koneksi |
| :- | :- | :- |
| `.ASYNC` | `runAsync` | Accept tunggal, `io.async(dispatchConn)` |
| `.EPOLL` | `epollWorkerEntry` (`dispatch/epoll.zig`, `runEpoll`) | Shared-nothing: satu SO_REUSEPORT listener plus satu instance epoll per worker (Linux-only, ditolak di luar Linux dengan `error.ZixDispatchModelUnsupported`) |
| `.URING` | `uringFixWorker` (`dispatch/uring.zig`, `runUring`) | Worker io_uring shared-nothing menjalankan `core.processFixRing` resumable per batch readable (Linux-only, ditolak di luar Linux dengan cara yang sama) |

`dispatchConn` memanggil `core.serveConn(task.stream, task.io, task.comp_id, task.opts)`.

---

###### end of lld-fix
