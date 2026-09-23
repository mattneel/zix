# LLD: zix.Fix (internal)

Internal data structures and algorithms for the FIX 4.x session implementation.

---

## Data Structures

### Field

```zig
pub const Field = struct {
    tag: Tag,
    value: []const u8, // zero-copy slice into the receive buffer
};
```

Zero-copy: `value` slices directly into the caller-supplied receive buffer. The buffer must not be overwritten while fields are in use.

### Message Receive Buffer

`serveConn` maintains two stack buffers:

```
recv_buf: [MAX_MSG_SIZE * 2]u8    // 16 KB, accumulates bytes from takeByte loop
recv_len: usize                   // bytes currently in recv_buf
```

After each complete message is processed, leftover bytes (pipelined messages or partial next message) are shifted to the front:

```
recv_buf:  [complete message][leftover bytes][free]
            processed and discarded   shifted to recv_buf[0]
```

### fields Array

```zig
var fields: [MAX_FIELDS]Field = undefined;
```

Stack-allocated, reused for every message in the session loop. `MAX_FIELDS = 64` is sufficient for all standard FIX 4.x message types.

---

## serveConn Algorithm

```
serveConn(stream, io, comp_id, opts):
    reader = stream.reader(io, &rd_buf)
    writer = stream.writer(io, &wr_buf)
    recv_len = 0

    loop:
        takeByte loop until findMessageEnd(recv_buf[0..recv_len]) returns end index
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
            "1" -> buildMessage(heartbeat reply with TestReqID echoed)
                   writer.writeAll
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "TestRequest")
            _ (routes non-empty, after Logon):
                   for route in opts.routes:
                       if msg_type == route.msg_type:
                           effective_ms = min(route.timeout_ms, opts.handler_timeout_ms) or whichever is non-zero
                           ctx = FixContext{ sender_comp_id, target_comp_id=comp_id, deadline_ns, fd, &seq_out }
                           route.handler(fslice, &ctx)
                           logger.session(msg_type, sender, comp_id, seq, "dispatch")
                           break
                   (no matching route: silently ignored)
            _ (routes empty, echo mode):
                   strip session header fields (BeginString, BodyLength, MsgType, SenderCompID,
                       TargetCompID, MsgSeqNum, SendingTime, CheckSum) from fslice
                   buildMessage(out_buf, comp_id, peer, seq_out, msg_type, body_fields)
                   writer.writeAll(out_buf[0..n])
                   writer.flush
                   logger.session(msg_type, sender, comp_id, seq, "msg")

        shift leftover bytes: recv_buf[0..] = recv_buf[end..recv_len]
        recv_len -= end
```

---

## buildMessage Algorithm

Tags are written in standard FIX order:

1. `8=FIX.4.2\x01` (BeginString)
2. `9=` + placeholder (BodyLength, patched after body is known)
3. Body: `35=T\x01 49=sender\x01 56=target\x01 34=seq\x01 <extra fields>\x01`
4. Compute BodyLength (all bytes from start of tag-35 to end of last body field SOH)
5. Patch the `9=` placeholder in the output buffer
6. `10=CCC\x01` (3-digit decimal checksum of all bytes written so far)

Returns total bytes written into the output buffer.

---

## Checksum

`computeChecksum(buf: []const u8) u8`:
- Sums every byte of `buf` as u32 (no overflow for messages up to MAX_MSG_SIZE).
- Returns `@truncate(sum % 256)`.

`verifyChecksum(buf: []const u8) bool`:
- Extracts the `10=NNN\x01` value from the trailing bytes.
- Computes checksum over all bytes up to (not including) the `\x0110=` tag.
- Returns false if the tag-10 field is malformed, missing, or the value does not match.

---

## findMessageEnd

Linear scan for the SOH-prefixed `10=` pattern:

```
for i in 0..buf.len-4:
    if buf[i] == SOH and buf[i+1]=='1' and buf[i+2]=='0' and buf[i+3]=='=':
        scan forward from i+4 for the closing SOH
        if found at index j: return j + 1
        else: return null   // message not yet complete
return null
```

The SOH prefix guards against false positives where `10=` appears inside a field value. Returns the index one past the closing SOH of the checksum field.

---

## Dispatch Models

`FixServer` uses the same dispatch infrastructure as `TcpServer`:

| Model | Entry function | Connection dispatch |
| :- | :- | :- |
| `.ASYNC` | `runAsync` | Single accept, `io.async(dispatchConn)` |
| `.EPOLL` | `epollWorkerEntry` (`dispatch/epoll.zig`, `runEpoll`) | Shared-nothing: one SO_REUSEPORT listener plus one epoll instance per worker (Linux-only, rejected off Linux with `error.ZixDispatchModelUnsupported`) |
| `.URING` | `uringFixWorker` (`dispatch/uring.zig`, `runUring`) | Shared-nothing io_uring workers running the resumable `core.processFixRing` per readable batch (Linux-only, rejected off Linux the same way) |

`dispatchConn` calls `core.serveConn(task.stream, task.io, task.comp_id, task.opts)`.

---

###### end of lld-fix
