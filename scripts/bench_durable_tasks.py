#!/usr/bin/env python3
"""Benchmark for the durable CreateTask slice: the workload the slice exists to serve.

What it measures, per request:
  submit  -> the `accepted` reply on the reliable stream   (the commit: validate, authorize, one
                                                            transaction for the task and its job)
  submit  -> the `task_completed` patch on the same stream  (the whole durable path: the worker leased
                                                            the job, ran it, committed the completion and
                                                            its outbox row, the dispatcher published it,
                                                            and the view's poll collected it)

The second number is the one the milestone is about: it is the latency a page sees between asking for
something durable and seeing it done. It includes two poll intervals, so it is an upper bound on the
server's own work: `--poll-ms 0` measures the path with the client polling as fast as the socket allows.

Usage:
  python3 scripts/bench_durable_tasks.py [--host H] [--port P] [--requests N] [--poll-ms MS]
                                         [--principal WHO] [--tenant T] [--path /tasks] [--json]

Needs aioquic (the same dependency the interop harness uses) and a running
`zig build example-webtransport_tasks` server.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import ssl
import statistics
import sys
import time

from aioquic.asyncio.client import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.events import StreamDataReceived

CONNECT_STREAM_ID = 0


class View(QuicConnectionProtocol):
    """One authorized view: a subscription stream, and the patches the server writes back on it."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.http = H3Connection(self._quic, enable_webtransport=True)
        self.status: str | None = None
        self.view_stream: int | None = None
        self.lines: asyncio.Queue = asyncio.Queue()
        self._buffer = b""

    def quic_event_received(self, event):
        for http_event in self.http.handle_event(event):
            if isinstance(http_event, HeadersReceived) and http_event.stream_id == CONNECT_STREAM_ID:
                for name, value in http_event.headers:
                    if name == b":status":
                        self.status = value.decode()
        if isinstance(event, StreamDataReceived) and self.view_stream is not None:
            if event.stream_id != self.view_stream:
                return
            self._buffer += event.data
            while b"\n" in self._buffer:
                line, self._buffer = self._buffer.split(b"\n", 1)
                if line.strip():
                    self.lines.put_nowait(json.loads(line))

    async def next_line(self, timeout: float):
        return await asyncio.wait_for(self.lines.get(), timeout)

    async def open(self, host: str, port: int, path: str, principal: str, tenant: str):
        self.http.send_headers(
            CONNECT_STREAM_ID,
            [
                (b":method", b"CONNECT"),
                (b":protocol", b"webtransport"),
                (b":scheme", b"https"),
                (b":authority", f"{host}:{port}".encode()),
                (b":path", path.encode()),
            ],
        )
        self.transmit()

        deadline = time.monotonic() + 10
        while self.status is None:
            if time.monotonic() > deadline:
                raise TimeoutError("no CONNECT response")
            await asyncio.sleep(0.02)
        if not self.status.startswith("2"):
            raise RuntimeError(f"CONNECT answered {self.status}")

        stream = await self._new_stream()
        self.view_stream = stream
        await self._send(stream, {"kind": "subscribe", "principal": principal, "tenant": tenant})

        # The subscription answers with the committed state, which is also the resync path.
        snapshot = await self.next_line(10)
        if snapshot.get("kind") != "snapshot":
            raise RuntimeError(f"expected a snapshot, got {snapshot}")

        return snapshot

    async def _new_stream(self) -> int:
        stream_id = self.http.create_webtransport_stream(CONNECT_STREAM_ID, is_unidirectional=False)
        self.transmit()

        return stream_id

    async def _send(self, stream_id: int, command: dict):
        payload = json.dumps(command).encode() + b"\n"
        self._quic.send_stream_data(stream_id, payload, end_stream=False)
        self.transmit()

    async def create_task(self, stream_id: int, key: str, title: str, principal: str, tenant: str) -> float:
        """Submit one task and wait for its completion patch. Returns (commit, completion) latencies."""
        started = time.monotonic()
        await self._send(stream_id, {
            "kind": "create_task",
            "idempotency_key": key,
            "title": title,
            "principal": principal,
            "tenant": tenant,
        })

        accepted_at = None
        while accepted_at is None:
            line = await self.next_line(10)
            if line.get("kind") == "accepted" and line.get("task_id") is not None:
                accepted_at = time.monotonic()

        while True:
            line = await self.next_line(20)
            if line.get("kind") == "task_completed" and line.get("rev") is not None:
                return accepted_at - started, time.monotonic() - started

    async def poll(self, stream_id: int):
        await self._send(stream_id, {"kind": "poll"})


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))

    return ordered[index]


async def run(args) -> int:
    configuration = QuicConfiguration(
        alpn_protocols=["h3"],
        is_client=True,
        max_datagram_frame_size=1200,
        idle_timeout=60.0,
    )
    configuration.verify_mode = ssl.CERT_NONE

    commits: list[float] = []
    completions: list[float] = []

    async with connect(args.host, args.port, configuration=configuration, create_protocol=View) as view:
        await view.wait_connected()
        snapshot = await view.open(args.host, args.port, args.path, args.principal, args.tenant)
        print(f"subscribed as {args.principal} @ {args.tenant}: rev {snapshot.get('rev')}, "
              f"{len(snapshot.get('tasks', []))} task(s) already committed")

        run_tag = f"bench-{int(time.time() * 1000)}"
        poll_task = asyncio.create_task(poll_forever(view, view.view_stream, args.poll_ms))

        started = time.monotonic()
        for index in range(args.requests):
            if args.verbose:
                print(f"  request {index} ...", file=sys.stderr, flush=True)
            key = f"{run_tag}-{index}"
            commit, completion = await view.create_task(view.view_stream, key, f"bench task {index}", args.principal, args.tenant)
            commits.append(commit * 1000)
            completions.append(completion * 1000)
        elapsed = time.monotonic() - started

        poll_task.cancel()

    report(args, commits, completions, elapsed)

    return 0


async def poll_forever(view: View, stream_id: int, poll_ms: float):
    """The view's own clock: the server can only write from a callback, so the client polls for patches."""
    while True:
        await view.poll(stream_id)
        await asyncio.sleep(poll_ms / 1000.0)


def report(args, commits: list[float], completions: list[float], elapsed: float):
    def line(name: str, values: list[float]) -> str:
        return (f"  {name:12s} n={len(values):3d}  mean={statistics.fmean(values):7.1f}ms  "
                f"p50={percentile(values, 0.50):7.1f}ms  p90={percentile(values, 0.90):7.1f}ms  "
                f"p99={percentile(values, 0.99):7.1f}ms  max={max(values):7.1f}ms")

    print(f"\ndurable CreateTask, {args.requests} requests through "
          f"{args.host}:{args.port}{args.path}, poll every {args.poll_ms:g}ms")
    print(line("commit", commits))
    print(line("end-to-end", completions))
    print(f"  throughput  {args.requests / elapsed:.1f} tasks/s ({elapsed:.2f}s wall, one session, sequential)")

    if args.json:
        print(json.dumps({
            "requests": args.requests,
            "poll_ms": args.poll_ms,
            "commit_ms": {"mean": statistics.fmean(commits), "p50": percentile(commits, 0.50), "p99": percentile(commits, 0.99)},
            "end_to_end_ms": {"mean": statistics.fmean(completions), "p50": percentile(completions, 0.50), "p99": percentile(completions, 0.99), "max": max(completions)},
            "throughput_per_s": args.requests / elapsed,
        }))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9444)
    parser.add_argument("--path", default="/tasks")
    parser.add_argument("--requests", type=int, default=25)
    parser.add_argument("--poll-ms", type=float, default=10.0)
    parser.add_argument("--principal", default="alice@acme")
    parser.add_argument("--tenant", default="acme")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--verbose", action="store_true", help="print per-request progress to stderr")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    sys.exit(main())
