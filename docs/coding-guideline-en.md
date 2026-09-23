## Zix Coding Guideline

How code is written in zix, derived from the existing implementation. This is the house style for `src/`, `tests/`, `examples/`, and the build files. Each rule names a real place in the tree so the convention can be checked against live code, not just asserted.

The guiding principle behind every rule below: code reads like the code already around it. Match the surrounding file's naming, comment density, and idiom before introducing a new one.

---

## 1. Source layout

Each subsystem is one Zig file-as-struct namespace, exported once from `src/lib.zig`. A subsystem's public type module is `PascalCase.zig` (`Tcp.zig`, `Udp.zig`, `Http1.zig`, `Channel.zig`), and it only re-exports that domain's surface:

```zig
//! zix tcp

pub const Server = @import("server.zig").Server;
pub const Client = @import("client.zig").TcpClient;
pub const HandlerFn = @import("server.zig").HandlerFn;
pub const DispatchModel = @import("config.zig").DispatchModel;
pub const ServerConfig = @import("config.zig").TcpServerConfig;
```

> Give each subsystem one namespace type (`zix.Http1`, `zix.Grpc`, ...). Put implementation in lowercase files (`server.zig`, `config.zig`, `client.zig`) and re-export only the public names from the `PascalCase.zig` aggregator.

The lowercase implementation files carry the logic, the PascalCase file is the door. `lib.zig` is the single root: it lists each subsystem (`pub const Tcp = @import("tcp/Tcp.zig");`) and groups loose helpers under a namespace struct (`pub const utils = struct { ... }`).

> A subsystem becomes public only when it has a line in `src/lib.zig`. Nothing reaches `zix.*` by accident.

**Test discovery is not recursive.** Every new `src/` file that has tests MUST get its own `std.testing.refAllDecls(@import("..."))` line in the `lib.zig` unit-test block, grouped under its engine comment. Miss it and the file's tests silently never run while unit-test still exits 0.

```zig
test "zix: unit test" {
    // # zix.Http
    std.testing.refAllDecls(@import("tcp/http/router.zig"));
    std.testing.refAllDecls(@import("tcp/http/response.zig"));
    // ... one line per file with tests
}
```

> After adding a `src/` file with tests, add its `refAllDecls` line in `src/lib.zig` in the same change. No exceptions.

---

## 2. Naming

| Kind | Rule | Example |
| :- | :- | :- |
| Public type module file | `PascalCase.zig` | `Http1.zig`, `Channel.zig` |
| Implementation file | `lowercase.zig` | `server.zig`, `config.zig` |
| Type / struct / enum | `PascalCase` | `TcpServerConfig`, `DispatchModel`, `RespSink` |
| Function | `camelCase` | `serveDispatch`, `frameRespond`, `uringUnavailableReason` |
| Field / variable / const binding | `snake_case` | `dispatch_model`, `max_recv_buf`, `worker_stack_size_bytes` (use `_var` if it meant for private usage) |
| Domain / public / config enum value | `UPPER_CASE` | `ASYNC`, `EPOLL`, `URING` |
| Error | `error.<Product><Domain><Condition>` | `error.ZixPortNotConfigured`, `error.ZixHttp1ListenFailed` (see section 9) |
| Comptime version constants | `UPPER_CASE` | `ZIG_SEMVER.MAJOR` |

Enums that model a public, domain, or config choice are `UPPER_CASE` (`DispatchModel`, content type, status, logger level). The narrow exceptions kept in-tree are internal control-flow enums (`keep_alive` / `close` style outcomes) and protocol-mirroring values (WebSocket `text` / `binary` opcodes that mirror the wire name). When in doubt, `UPPER_CASE`.

**Use a short name only when it clearly represents its purpose.** The test is whether a reader who has not seen the file understands it, not the character count. Clear short forms are fine: `conn`, `cfg`, `ctx`, `fd`, `io`, `str`. A name that does not carry its purpose must be spelled out: `handler` not `h`, `stream` not `s`, `worker` not `w`, `paths` not `p`, `cache` not `c`.

One-character names are reserved for two cases: `i` / `n` loop and count idioms, and crypto / modular-arithmetic notation that mirrors the math (`p`, `q`, `d`, `n`, `m` in `rsa.zig`, `montgomery.zig`, `ff.zig`). A single-character function parameter is otherwise not allowed, spell it out.

> Name for the reader who has not seen the file. If a short name needs a comment to be understood, it is the wrong name.

---

## 3. File anatomy

Files follow a fixed top-to-bottom shape:

```zig
//! zix tcp config

const std = @import("std");
const Logger = @import("../logger/logger.zig").Logger;

// --------------------------------------------------------- //

/// Connection dispatch model. ...
pub const DispatchModel = enum(u8) { ... };

// --------------------------------------------------------- //

/// TCP stream server configuration. ...
pub const TcpServerConfig = struct { ... };

// --------------------------------------------------------- //
// --------------------------------------------------------- //

test "zix tcp: TcpServerConfig, default field values" { ... }
```

1. **Module doc comment** `//! zix <subsystem>` on line 1, a short lowercase identity (`//! zix udp namespace aggregator`, `//! zix logger`). The one branded exception in `src/lib.zig` (`//! Zero sIX; 06;`) is intentional, never change it.
2. **Imports** with `const std = @import("std");` first, then project imports.
3. **Comment spacer** `// --------------------------------------------------------- //` separates major declarations.
4. **Declarations**, each preceded by its doc comment.
5. **Tests** at the bottom, fronted by a double comment spacer (two spacer lines), which is the one place a double spacer is allowed.

> Keep the order: header, imports, spacer-separated decls, then a double-spacer and the tests.

A comment spacer is a visual rule and separator. When the code gets longer, this grouping can act as a hint that it is already too large and can be refactored for maintainability. A leading spacer followed by a label line is the allowed form:

```zig
// --------------------------------------------------------- //
// Public surface re-exported from the dispatch helpers.

pub const HandlerFn = common.HandlerFn;
```

---

## 4. Doc comments

Public declarations carry a `///` doc comment. Use the label set with a `:` after the subject, never the verb form, never `;` as a prose separator:

- `Note:` (title case, not `NOTE:`)
- `Param:` with entries `name - type (description)`, a single space around the `-`, no column-aligning padding
- `Return:` (not `Returns`), entries are `-` bulleted outcome lines, never a bare type line
- `Usage:` only when non-obvious to a junior dev, and the code sample is wrapped in a ```zig fence

```zig
/// THE ONLY SOURCE OF TRUTH for Zig SEMVER for zix source code.
///
/// Note:
/// - Do not create in other place!
pub const ZIG_SEMVER = struct { ... };
```

Config fields each get a one-line `///` that states the unit, the default, and what 0 or null means:

```zig
/// Socket receive timeout per accepted connection in milliseconds (SO_RCVTIMEO). 0 = disabled.
recv_timeout_ms: u32 = 0,
/// Optional logger. When non-null, ... Caller owns. Must outlive the server.
logger: ?*Logger = null,
```

> Do not pad two-to-four spaces after a label `:`. The exception is a multi-line `Note:` bullet whose continuation lines align under the text. Write `Return:` outcomes as `-` bullets.

---

## 5. Code formatting (blank line between phases)

Run `zig fmt .` before any commit. Beyond formatting, distinct phases of a function body are separated by one blank line for readability, even without a comment. The phase boundaries:

| Boundary | Blank line before |
| :- | :- |
| Guard / early return -> main logic | the first non-guard statement |
| Preparation / build -> send / write / commit | the first write or commit |
| Computation -> return | the `return` (especially a multi-line struct literal) |
| `defer x.deinit()` -> main execution | the first real statement |

```zig
pub fn init(config: TcpServerConfig) !Self {
    if (config.port == 0) return error.ZixPortNotConfigured;

    return .{ .config = config };
}
```

```zig
var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
defer threaded.deinit();

const cfg = TcpServerConfig{ .io = threaded.io(), .ip = "127.0.0.1", .port = 9300 };
```

Exceptions where no blank line is needed: a mutex guard (`defer unlock` directly above its critical section) and same-phase setup chains (`defer free(x)` above the loop that uses `x`).

> After writing a function body, scan every line for a phase boundary. A guard's closing `}` and a single-line `if (...) return ...;` are each followed by a blank line. The last computation before a `return` is preceded by one.

---

## 6. Configuration: flat, no builder

Every config is one flat struct in `*/config.zig`. No nested sub-configs, no fluent builder. Required fields (`io`, `ip`, `port`) have no default and come first, every other field carries an explicit default:

```zig
pub const TcpServerConfig = struct {
    io: std.Io,            // required, caller-provided, must outlive the server
    ip: []const u8,        // required
    port: u16,             // required, must be non-zero
    dispatch_model: DispatchModel,  // required
    kernel_backlog: u31 = 4096,
    max_recv_buf: usize = 4096,
    // ...
};
```

A new tunable is a new top-level field, not a builder method or a nested object. When a field is genuinely cross-engine, it is added across all engine configs for consistency. A field scoped to one capability (for example the response-cache or compression knobs) is added only to the engine configs that have that capability, matching the existing footprint rather than all 8.

> Add a top-level field. Give it an explicit default and a one-line doc stating unit and the meaning of 0 / null.

---

## 7. Public type shape (lifecycle)

A server type is specialized over its comptime handler so `run` takes no handler argument, matching the `zix.Http1` / `zix.Grpc` shape. Every type uses `const Self = @This();` and the `init` / `deinit` / `run` lifecycle:

```zig
fn TcpServerImpl(comptime handler: HandlerFn) type {
    return struct {
        config: TcpServerConfig,

        const Self = @This();

        pub fn init(config: TcpServerConfig) !Self {
            if (config.port == 0) return error.ZixPortNotConfigured;

            return .{ .config = config };
        }

        pub fn deinit(_: *Self) void {}

        /// Listen and serve. Selects the concurrency model from config.dispatch_model.
        pub fn run(self: *const Self) !void {
            return serveDispatch(self.config, handler);
        }
    };
}
```

- `init` validates required fields first and returns an error (`error.ZixPortNotConfigured`) rather than panicking.
- `deinit` always exists even when empty (`pub fn deinit(_: *Self) void {}`), so callers can `defer server.deinit()` uniformly.
- `io` is always caller-provided through config and must outlive the server. Zix does not own the event loop.

> Bake the handler into the type at comptime. Validate in `init`, free in `deinit`, serve in `run`. Keep the trio even when one is a no-op.

---

## 8. Dispatch model and platform support

Concurrency is one `DispatchModel` enum (`ASYNC`, `EPOLL`, `URING`), each model in its own file under `dispatch/` (ADR-043), selected by a thin `switch` in the server. `.ASYNC = 0` is the zero value so a zero-init config gets a sane default, and it is the only model available on every platform.

Two different mismatches, handled two different ways (ADR-065):

- **A model the target OS cannot run** (`.EPOLL` / `.URING` off Linux) is a config error. `run()` logs which model was rejected and returns `error.ZixDispatchModelUnsupported`. It never downgrades: a caller that asked for a per-core loop and silently got something else has no way to tell.
- **A model the host cannot use right now** (io_uring unavailable on Linux, commonly the `RLIMIT_MEMLOCK` cap) is a capability gap. `.URING` folds to the EPOLL loop and logs the reason, so the server does not vanish right after binding.

The platform check is one shared predicate, consulted before the server binds anything:

```zig
if (!dispatch_support.isSupported(cfg.dispatch_model)) {
    common.logSystem(cfg, "{s} dispatch is Linux-only, use .ASYNC on this platform.", .{dispatch_support.rejectedName(cfg.dispatch_model)});

    return error.ZixDispatchModelUnsupported;
}
```

The `switch` arms keep their comptime OS gate as well, because the Linux-only loops only compile on Linux:

```zig
.EPOLL => if (comptime builtin.target.os.tag == .linux)
    epoll_model.runEpoll(cfg, handler)
else
    error.ZixDispatchModelUnsupported,
```

> Prefer comptime gating for a build-time fact (`comptime builtin.target.os.tag`), a runtime probe only for a host-time fact (memlock, ring availability). Always log the reason. Never let the server silently disappear after binding, and never let it silently serve a model the caller did not ask for.

> A model zix keeps is a model zix can maintain. `.POOL` and `.MIXED` were dropped in ADR-065 for exactly that reason, and `.KQUEUE` / `.IOCP` stay reserved names until each has a maintainer.

The same guard applies to any hand-rolled Linux-only fast path added purely for performance, not just the dispatch model (for example a `wallClockNs` / `nowUs` helper calling `std.os.linux.clock_gettime` directly instead of going through `std.posix.system`). The Linux branch (`comptime builtin.target.os.tag == .linux`, covers both x86_64-linux and aarch64-linux identically) is the primary, guarded platform: keep it byte-identical to what is already proven, and add every other platform as its own separate branch next to it, never folded into one shared implementation.

---

## 9. Error handling

An error has two jobs, and they are not the same job. The error VALUE is what the caller branches on. The log LINE is what the reader debugs from. A name alone cannot say which file, which port, or which field failed, so the rules below cover both halves.

### 9.1 Naming

- An error name is PascalCase on `error.` and reads `<Product><Domain><Condition>`: `error.ZixPortNotConfigured`, `error.ZixHttp1ListenFailed`, `error.ZixTlsCertFileNotFound`.
- The product prefix is whoever owns the file, not the repository. `Zix` in the engine tree, `Zixer` under `src/zixer`, and a standalone package keeps its own name: `Jzon`, `Postgrez`, `Rediz`, `Prometheuz`.
- A std error that is re-raised unchanged keeps the name std gave it: `OutOfMemory`, `WriteFailed`, `ReadFailed`, `EndOfStream`, `BrokenPipe`, `NoSpaceLeft`, `Overflow`, `Unexpected`. std propagates the unprefixed name through the same function, so prefixing only the local raise site would leave two names for one condition in the same error set.
- A name that a caller outside the package can receive is unique to the CONDITION, not just to the subsystem: `error.ZixHttp1RequestLineTruncated`, not a shared `error.ZixTruncated`. Reuse an existing name only when it is the same condition, never because it is close enough.
- A sans-I/O parser may share a narrow name inside its own error set, because that value is mapped to a domain error before any reader sees it.
- Never put `@src().file` or `@src().line` in the message. They point at the zix source, not at the reader's config. A name that is unique to the condition already locates the raise.

### 9.2 A log line, an error value, or both

Two questions settle it: can a caller act on it, and does the reader already know the subject.

| Situation | Emit | Why |
| :- | :- | :- |
| Sans-I/O parser or internal helper, the caller already holds the input | error value only | the caller has the subject, and a log line here would fire per packet |
| No error union to return into: `void` function, spawned worker thread, accept loop | log line only | nothing can branch on it, so the line IS the report |
| Public entry point holding a value the reader configured: path, port, dir, url | both | the value lets the caller branch, the line carries the subject the name cannot |

```zig
const cert_pem = std.Io.Dir.cwd().readFileAlloc(io, config.cert_path, allocator, .limited(CERT_MAX_BYTES)) catch |err| {
    logSystem(config, .ERROR, "tls cert read failed: {s} ({})", .{ config.cert_path, err });

    return switch (err) {
        error.FileNotFound => error.ZixTlsCertFileNotFound,
        error.AccessDenied => error.ZixTlsCertFileUnreadable,
        else => error.ZixTlsCertFileReadFailed,
    };
};
```

Two failures this rules out:

- Logging and swallowing where the function CAN return an error. That hides a failure the caller was able to handle.
- Returning a bare name at a config boundary. `error.ZixTlsCertFileNotFound` on its own still does not say which file, so the path goes in the line.

### 9.3 Shape

- Validate inputs at the boundary (`init`) and return the error early as a guard, with a blank line after.
- Use `errdefer` to unwind a partial construction, `defer` for unconditional cleanup.
- Do not collapse several causes into one name. Switch on the cause when the causes call for different fixes: not-found, permission denied and is-a-directory are three different reader actions.

> Return a named error, do not panic on a recoverable condition. Name the condition, name the subject in the line, and never make the reader guess which of the two halves is missing.

---

## 10. Memory and allocators

There is no single "preferred" allocator. The allocator is chosen by the data's lifetime and ownership, and arena is the exception, not the default. In the live tree the general-purpose thread-safe allocator is the dominant one, arena shows up only where a genuine bulk-reset point exists, and the bounded hot-path table has its own custom allocator.

| Allocator | When | Where in tree |
| :- | :- | :- |
| `std.heap.smp_allocator` (general-purpose, thread-safe) | the default for long-lived and shared state: connection and stream maps, worker thread arrays, HPACK tables, per-connection state. Use it whenever the data has no clean single reset point or is touched from more than one thread | every `dispatch/` and `core.zig` |
| `std.heap.ArenaAllocator` | only when the lifetime is a true scope with one bulk reset and a single owner: the response-cache backing, the `zix.Http` per-connection arena | `utils/response_cache.zig`, `tcp/http/server.zig` |
| Demand-paged slab (custom contiguous) | the bounded hot-path connection table, one `mmap` carved per worker, no per-accept heap call, an empty slot is just `buf.len == 0` | `multiplexers/slab.zig` |
| `std.heap.page_allocator` | page-granular buffers handed to the kernel (the provided-buffer ring) | `tcp/http1/dispatch/uring.zig` |
| `std.testing.allocator` | tests only, it also catches leaks | every test block |

Arena is the wrong choice, use `smp_allocator`, when any of these hold:

- The data is shared across worker threads. Arena is not thread-safe.
- The lifetime has no single reset point, for example a connection or stream that lives indefinitely and frees objects individually (the idle-conn pool reuses, it does not bulk-reset).
- Objects are reclaimed one at a time rather than all at once.

So "prefer arena if applicable" turns on "if applicable": in a shared-nothing, long-lived-connection, thread-per-core server that is the minority of allocation sites, which is why `smp_allocator` dominates the tree and the slab carries the hot path.

A buffer-owning type frees in `deinit`. Anything caller-provided (`io`, `logger`) is borrowed, documented as "caller owns, must outlive", and never freed by zix.

> Pick the allocator from the data's lifetime and ownership. Default to `smp_allocator` for shared or long-lived state, reach for arena only at a true single-owner bulk-reset scope, and use the slab for the bounded hot-path table. Do not force arena where the lifetime does not fit it.

---

## 11. Tests

Tests live at the bottom of the file they cover (Zig discovers them through `refAllDecls`). The name carries the domain prefix of the surface under test: `test "zix <domain>: <subject>, <case>"` (`zix tcp:`, `zix http1:`, `zix grpc:`, `zix tls:`, `zix channel:`), and driver tests use the driver name (`postgrez auth:`, `rediz protocol:`):

```zig
test "zix tcp: TcpServerConfig, default field values" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();

    const cfg = TcpServerConfig{ .io = threaded.io(), .ip = "127.0.0.1", .port = 9300 };
    try std.testing.expectEqualStrings("127.0.0.1", cfg.ip);
    try std.testing.expectEqual(@as(u16, 9300), cfg.port);
}
```

After implementing any new function, field, or behavior, add the tests covering it in the same change (unit, behaviour, edge, and integration when applicable). A file is not done, and the next file is not started, until the new code has tests.

> Co-locate tests with the code. Name them `zix <domain>: subject, case`. New behavior ships with its tests, never after.

When a test only makes sense on one platform (e.g. an EPOLL/URING dispatch model that is Linux-only), wrap the skip in an explicit block instead of a bare guard line, so the platform split reads as two distinct regions. The block names its reason with `std.log.info` and then returns plainly. Do not use `return error.SkipZigTest`: it reports the test outside the pass count, which reads as a hole in the run rather than a decision the code made.

```zig
test "zix grpc: dual listener, EPOLL serves h2c on port" {
    if (builtin.os.tag != .linux) {
        // windows / other-platform region: EPOLL/URING dispatch models are
        // Linux-only, nothing is spawned here, nothing to retry or clean up.
        std.log.info("EPOLL/URING is Linux-only, test skipped", .{});
        return;
    }

    // linux region: real server + retry + timeout
    ...
}
```

If the linux region spawns a background server to test against, retry the connect with a fixed attempt count (a hard ceiling, not an unbounded loop). Only add explicit shutdown/deinit for that server if the engine actually exposes a stop path: do not fake cleanup on a thread that can never return.

---

## 12. Comments and prose (in code and docs)

These apply to `//`, `///`, `//!`, and every markdown doc:

- A single `-` is allowed as a definer after a `:` subject or inside `()` (`Support: en - English, id - Bahasa`), and in a `name - type` param entry. It is not allowed as a free-floating clause separator.
- Diagrams are mermaid, not text-art.
- Directory trees use plain ASCII with the `|___` connector and `/`-prefixed directory entries, never Unicode box-drawing.

> Before moving on from any comment or doc block, scan each sentence for an em-dash or a `;` used as a separator and restructure it.

---

## 13. Zig version gating

Zix supports two Zig versions through one comptime source of truth, `zix.ZIG_SEMVER` (ADR-044). Version-specific branches are gated at comptime so only the active branch compiles, the inactive one is never type-checked into the binary:

```zig
if (comptime ZIG_SEMVER.MINOR == 16) {
    // 0.16 std.Io path
} else {
    // 0.17 std.Io path
}
```

`ZIG_SEMVER` is declared once in `src/lib.zig` and nowhere else. The build script keeps its own build-only copy.

> Gate a version difference at comptime against `ZIG_SEMVER`. Do not branch on the version at runtime, and do not redeclare the constant.

---

## 14. Commits and documentation

- Run `zig fmt .` before composing a commit message.
- One commit per file. Closely related, inseparable files in one new directory may share a single commit.
- Documentation comes in an `-en.md` / `-id.md` pair. When translating to Indonesian, keep the English technical term wherever a forced translation would drift from the established meaning (shared-nothing, slab, dispatch, hot path, throughput, comptime, and similar).

> Commit per file with a meaningful message after `zig fmt .`. Keep docs bilingual, and keep technical terms in English inside other languages translation.

---

## 15. File read/write on unix and Windows

Every file operation goes through `std.Io.Dir.cwd()` (`createFile`, `readFileAlloc`, `deleteFile`). When the sub_path is absolute the dir handle is ignored, so this one call shape serves both relative and absolute paths. Do not reach for the `*Absolute` variants (`deleteFileAbsolute`, `openFileAbsolute`): they only accept an absolute path, which forces the call site to split into two shapes the moment a platform needs a relative one.

Never hardcode a unix-style absolute path (`/tmp/...`) in code that Windows will open, write, or bind. Windows resolves `/tmp/...` against the current drive (for example `D:\tmp\...`), and when that directory does not exist the operation fails with NTSTATUS OBJECT_PATH_NOT_FOUND (surfacing as `error.FileNotFound` on file ops, or `error.Unexpected` on a socket bind). The idiom is a cwd-relative path, no platform branch needed since it resolves the same way everywhere:

```zig
const cert_path = "tmp/zix_rsa_integration_cert.pem";

try writeFile(io, cert_path, cert_pem);
defer std.Io.Dir.cwd().deleteFile(io, cert_path) catch {};
```

The same rule covers unix domain socket paths handed to `std.Io.net.UnixAddress`: Windows supports AF_UNIX, but the bind resolves the path exactly like a file open, so a `/tmp/...` socket path fails there too. This also means a UDS server must clean up its socket file through `cwd().deleteFile`, never `deleteFileAbsolute`, since a relative path fails that function's own absolute-path assert.

Production paths follow the caller: `Tls.Context.init` reads `cert_path` / `key_path` through `cwd().readFileAlloc`, so a config may carry either shape and the right one is the deployment's concern, not zix's.

> Route every file op through `std.Io.Dir.cwd()` and let the path decide relative vs absolute. Never hardcode `/tmp` for anything Windows touches: use a cwd-relative path everywhere instead.
