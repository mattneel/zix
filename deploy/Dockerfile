# Build the demo with the Zig the repository pins, then ship only what runs.
FROM debian:bookworm-slim AS build
ARG ZIG_VERSION=0.16.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz
ENV PATH="/opt/zig:${PATH}"
WORKDIR /src
COPY . .
# The demo is the WebTransport example; the certificate and database come from the environment at runtime.
RUN zig build example-webtransport_tasks --prefix /out

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates certbot libnss3-tools \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/bin/zix-example-webtransport_tasks-x86_64-linux-debug /app/zix-demo
# The development certificate, so the machine runs before a domain exists; the entrypoint moves ZIX_CERT and
# ZIX_KEY to the ACME files once it has them.
COPY --from=build /src/examples/certs /app/examples/certs
COPY deploy/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
