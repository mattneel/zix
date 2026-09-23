# Migration Guide

## For callers upgrading from 0.4.x:

1. **Set `dispatch_model` explicitly** in every server config (no default)
2. **Update `Server.init` calls**:
   - `zix.Http.Server.init(4096, &routes, cfg)` -> `zix.Http.Server.init(zix.Http.Router(&routes).dispatch, cfg)`
   - `const S = zix.Http3.Http3(handler); try S.init(cfg)` -> `zix.Http3.Server.init(handler, cfg)`
   - Remove `try` from `zix.Http2`/`zix.Grpc`/`zix.Http` init (validation moved to `run()`)
3. **Update `HandlerFn` signatures** to `fn(req: *Request, res: *Response, ctx: *Context) anyerror!void`
4. **Rename response helpers** per ADR-059 taxonomy:
   - `write*` -> `send*`; `*FD` for fd-taking variants
5. **Update error names** to prefixed forms: `error.PortNotConfigured` -> `error.ZixPortNotConfigured`
6. **HTTP method parsing**: `codeFromString` is now exact case-sensitive, lowercase methods -> 501
7. **Content lookups**: `enumFromString` -> `typeFromString`, returns `?Type` (no `.NA`)
8. **Remove `.POOL`/`.MIXED` references**, use `.ASYNC`, `.EPOLL`, or `.URING`
9. **`pool_size` removed**, use `workers` for thread/worker count
10. **`max_gzip_out`** -> `compression_max_out`
