# jzon

JSON in both directions, written in pure Zig, standard library only.

- Two calls: `serialize` turns a typed value into JSON text, `deserialize` turns JSON text back into a typed value.
- Four write paths and four read paths. Every one of them produces the same bytes and reads the same documents, so picking one is a cost decision and never a correctness one.
- Serialize allocates nothing. The caller hands over a buffer, and a value that does not fit is `error.NoSpaceLeft`.
- Deserialize allocates only what the result points at, out of the allocator handed in, so an arena reset frees a whole parse in one step.
- Strings can be borrowed from the document instead of copied.
- A field type a generated path has no JSON form for is a compile error naming the type, never a runtime failure.
- Builds on Zig 0.16 and 0.17.

For the architecture see `hld-en.md`, for the internals see `lld-en.md`, for measured cost see `benchmark-en.md`.

## Import

jzon ships inside zix and is reachable from it:

```zig
const zix = @import("zix");

const len = try zix.jzon.serialize(&buf, order, .{});
```

It is also a standalone package under `src/jzon` with its own build files, so it can be depended on by itself. Add it as a path dependency in your `build.zig.zon`:

```zig
.dependencies = .{
    .jzon = .{ .path = "path/to/jzon" },
},
```

Wire the module in `build.zig`:

```zig
const jzon = b.dependency("jzon", .{}).module("jzon");
exe.root_module.addImport("jzon", jzon);
```

## Quickstart

One record carries both directions:

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

### A value into JSON text

```zig
var buf: [1024]u8 = undefined;

const len = try jzon.serialize(&buf, order, .{});
const json = buf[0..len];
```

The buffer belongs to the caller, so a handler can render straight into the send buffer an engine hands it. Nothing is allocated, and the only failure is `error.NoSpaceLeft`.

### JSON text back into a value

```zig
const order = try jzon.deserialize(Order, arena.allocator(), body, .{});
```

Everything `order` points at comes from that allocator. An arena is the natural fit for a server: parse the request body into it, answer, reset it.

### Picking a path

```zig
const len = try jzon.serialize(&buf, order, .{ .strategy = .GENERATED });

const parsed = try jzon.deserialize(Order, arena.allocator(), body, .{
    .strategy = .GENERATED,
    .strings = .BORROW,
    .unknown = .SKIP,
});
```

The strategy is a comptime field, so only the path named is compiled into the binary.

## Write strategies

| Strategy | What it runs |
| :- | :- |
| `.STD` | `std.json.Stringify`, which renders every shape std renders |
| `.GENERATED_FMT` | generated from the type, integers through `std.fmt` |
| `.GENERATED` | generated from the type, integer digits written straight into the buffer |
| `.GENERATED_VECTOR` | as `.GENERATED`, with strings scanned one vector lane at a time |

## Read strategies

| Strategy | What it runs |
| :- | :- |
| `.STD` | `std.json` reflection, which parses every shape std parses |
| `.SCANNER` | tokens from `std.json.Scanner`, with the field dispatch generated from the type |
| `.GENERATED` | generated from the type, over jzon's own read cursor, one byte at a time |
| `.GENERATED_VECTOR` | as `.GENERATED`, one vector lane at a time |

`.GENERATED_VECTOR` is not always the quickest, on either side. It pays on long strings and costs on short ones, which is why the width stays a call-site choice rather than a default. See `benchmark-en.md` for what it measures on one record.

## Options

`jzon.SerializeOptions`:

| Field | Default | What it decides |
| :- | :- | :- |
| `strategy` | `.STD` | which write path runs |

`jzon.DeserializeOptions`:

| Field | Default | What it decides |
| :- | :- | :- |
| `strategy` | `.STD` | which read path runs |
| `strings` | `.COPY` | `.COPY` copies every string into the allocator, `.BORROW` points a string with no escape at the document, which then has to outlive the value |
| `unknown` | `.REJECT` | `.REJECT` fails on a key the type does not declare, `.SKIP` steps over the key and its whole value however deep it nests |

## Type coverage

The generated paths take: `bool`, any integer width signed or unsigned, any float width, `[]const u8` as a string, a slice of any covered type, an optional of any covered type, an exhaustive enum, and a struct whose fields are all of those.

They refuse at compile time, naming the type: a tuple, a non-slice pointer, and a non-exhaustive enum. `.STD` still takes any shape std takes, so a field outside the covered set is a strategy choice rather than a wall.

## Errors

A render reports `error.NoSpaceLeft` and nothing else.

A parse reports one set whichever path ran:

| Error | What it means |
| :- | :- |
| `JzonUnknownField` | the document carries a key the type does not declare, under `unknown = .REJECT` |
| `JzonMissingField` | the document left out a field that declares no default |
| `JzonUnknownEnumValue` | a string the enum has no tag for |
| `JzonTruncated` | the document ended early |
| `JzonUnexpected` | what is there is not what the type wants: a syntax error, a value of the wrong shape, or the same key twice |
| `JzonBadNumber` | number text the grammar does not allow, or a value the target integer type cannot hold |
| `JzonBadEscape` | an escape sequence the rules do not spell |
| `OutOfMemory` | the allocator ran out |

Swapping a strategy never changes what a caller has to handle. `lld-en.md` lists the three places a path built from the type answers differently from `.STD`.

## Examples

Six, four in this package and two of them benches. None is a server, so each runs and exits.

| Example | What it shows |
| :- | :- |
| [serialize](../../src/jzon/examples/serialize.zig) | a value into a fixed buffer, every write strategy, and what a buffer too small reports |
| [deserialize](../../src/jzon/examples/deserialize.zig) | a request body into a typed value on an arena, every read strategy, reset between bodies |
| [strings](../../src/jzon/examples/strings.zig) | `.COPY` against `.BORROW`, and what borrowing asks of the document's lifetime |
| [unknown_keys](../../src/jzon/examples/unknown_keys.zig) | `.REJECT` against `.SKIP` on a document carrying more than the type declares |
| [bench_serialize](../../src/jzon/examples/bench_serialize.zig) | what each write strategy costs per render, against the default's rate |
| [bench_deserialize](../../src/jzon/examples/bench_deserialize.zig) | what each read strategy costs per parse, on a minified document and a laid-out one |

Build them from the package:

```
zig build examples                 # all of them
zig build example-serialize        # one of them
```

Or from the repo root with `zig build jzon-examples`. The binaries land in `src/jzon/zig-out/bin` as `jzon-example-<name>-<arch>-<os>-<optimize>`, where the mode is `debug` unless `-Doptimize` says otherwise.

The two bench examples want `-Doptimize=ReleaseFast`. A Debug build measures the safety checks rather than the paths.

A seventh example is a server, so it lives with the engine examples rather than in this package: [`examples/http1_jzon.zig`](../../examples/http1_jzon.zig) reads a JSON request body into a record on the per-request arena and answers with a record rendered into a stack buffer, nothing allocated on the response path. Build it from the repo root with `zig build example-http1_jzon`.

## Testing

Three tiers, 440 tests, none of them needing anything installed:

```
zig build test-unit          # 113, the in-file tests under src/
zig build test-behaviour     # 144, what each piece does when handed what it wants
zig build test-edge          # 183, what each piece does when handed what it does not
zig build test-all           # all three
```

From the repo root the same steps are `jzon-test-unit`, `jzon-test-behaviour`, `jzon-test-edge`, and `jzon-test-all`. The per-test bound comes from `-Ddriver-test-timeout=<duration>`, because a nested package build never sees the parent's `--test-timeout`.

Every tier runs on both supported Zig versions and on all seven CI targets.
