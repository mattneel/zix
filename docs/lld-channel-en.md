# LLD: zix.Channel

Internal implementation details. For design rationale see [`docs/hld-channel-en.md`](hld-channel-en.md) and ADR-017.

---

## Source Layout

```
src/channel/
    channel.zig   // Channel(comptime T: type) generic implementation
    Channel.zig   // namespace aggregator
```

---

## Data Structure

Ring buffer backed by a heap-allocated `[]T` slice. All state lives in the `Channel(T)` struct returned by `init()`.

```
buf: []T          // heap-allocated ring, length = capacity
head: usize       // index of the next item to read
count: usize      // number of items currently in the buffer
closed: bool      // set by close(), no new sends after this point
mutex: std.Io.Mutex
not_empty: std.Io.Condition
not_full:  std.Io.Condition
allocator: std.mem.Allocator
```

Ring arithmetic:
- Write (tail) index: `(head + count) % buf.len`
- Advance head on recv: `head = (head + 1) % buf.len`

---

## Locking Primitive

`std.Io.Mutex` + `std.Io.Condition` (fiber-aware). Required so Channel can be used from `io.concurrent()` handler tasks as well as plain OS threads.

`std.Thread.Mutex` was evaluated and rejected because it blocks the OS thread rather than yielding to the scheduler, incompatible with fiber-based concurrency.

---

## send()

```
lock mutex
while count == buf.len:
    if closed: unlock + return error.ZixClosed
    not_full.waitUncancelable(io, &mutex)
if closed: unlock + return error.ZixClosed
buf[(head + count) % buf.len] = value
count += 1
unlock
not_empty.signal(io)
```

---

## recv()

```
lock mutex
while count == 0:
    if closed: unlock + return error.ZixClosed
    not_empty.waitUncancelable(io, &mutex)
value = buf[head]
head = (head + 1) % buf.len
count -= 1
unlock
not_full.signal(io)
return value
```

---

## close()

```
lock mutex
closed = true
unlock
not_empty.broadcast(io)   // unblock all waiting recvs
not_full.broadcast(io)    // unblock all waiting sends
```

---

## Memory

`init()` calls `allocator.alloc(T, capacity)`. `deinit()` calls `allocator.free(buf)`. No other heap allocations.

---

###### end of lld-channel
