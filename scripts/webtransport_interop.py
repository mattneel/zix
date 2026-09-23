"""Independent WebTransport over HTTP/3 client (aioquic), used as an interop harness.

Drives one session against a zix WebTransport server and fails unless application data
actually moves in both directions:

  1. QUIC handshake with ALPN h3, max_datagram_frame_size advertised
  2. extended CONNECT with :protocol webtransport on <path>, expecting 2xx
  3. a client bidirectional WebTransport stream: payload out, the echo back
  4. an HTTP/3 datagram: payload out, the echo back
  5. the server-opened unidirectional stream (its banner, with a FIN)

Every step prints the bytes it saw, so a failure names the direction that broke.

Usage: python3 webtransport_interop.py <host> <port> <path>
Exit 0 on success, 1 otherwise.
"""

import asyncio
import json
import ssl
import sys

from aioquic.asyncio.client import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import (
    DatagramReceived,
    HeadersReceived,
    WebTransportStreamDataReceived,
)
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.events import QuicEvent, StreamDataReceived
from aioquic.quic.logger import QuicLogger

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 9089
PATH = sys.argv[3] if len(sys.argv) > 3 else "/echo"

# The CONNECT request stream: the client's first bidirectional stream (id 0).
CONNECT_STREAM_ID = 0
# Distinctive payloads, so a stray echo from another client cannot be mistaken for ours.
STREAM_PAYLOAD = b"interop-stream-payload-0123456789"
DATAGRAM_PAYLOAD = b"interop-datagram-0123456789"
BANNER_PREFIX = b"zix webtransport echo"


def frame_summary(frame: dict) -> str:
    kind = frame.get("frame_type", "?")
    if kind == "stream":
        return f"stream(id={frame.get('stream_id')},len={frame.get('length')},off={frame.get('offset')},fin={frame.get('fin')})"

    return str(kind)


class Client(QuicConnectionProtocol):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.http = H3Connection(self._quic, enable_webtransport=True)
        self.connect_status = None
        self.stream_echo = bytearray()
        self.datagrams = bytearray()
        self.server_streams = []  # (stream_id, data, ended)
        self.wt_stream_id = None  # the bidirectional data stream, once opened
        self.sent_frames = []  # every frame this client put on the wire
        self.events = asyncio.Queue()

    def quic_event_received(self, event: QuicEvent) -> None:
        name = getattr(event, "event_type", type(event).__name__)
        if name == "packet_sent":
            for frame in getattr(getattr(event, "packet", None), "frames", []) or []:
                self.sent_frames.append(frame)
        # The echo on the bidirectional stream is read from the raw stream bytes: aioquic's HTTP/3
        # layer only classifies incoming stream data as WebTransport when the peer re-sends the 0x41
        # stream header, which the draft forbids on the server's direction of a client-initiated
        # stream (draft-ietf-webtrans-http3-16 4.3), so a conformant echo never reaches its
        # WebTransport event.
        if isinstance(event, StreamDataReceived) and self.wt_stream_id is not None:
            if event.stream_id == self.wt_stream_id:
                self.stream_echo += event.data
        for http_event in self.http.handle_event(event):
            self.events.put_nowait(http_event)
            if isinstance(http_event, HeadersReceived) and http_event.stream_id == CONNECT_STREAM_ID:
                for name_b, value in http_event.headers:
                    if name_b == b":status":
                        self.connect_status = value.decode()
            elif isinstance(http_event, WebTransportStreamDataReceived):
                if http_event.stream_id != CONNECT_STREAM_ID and http_event.stream_id % 4 in (2, 3):
                    self.server_streams.append((http_event.stream_id, bytes(http_event.data), http_event.stream_ended))
                elif http_event.stream_id != CONNECT_STREAM_ID:
                    self.stream_echo += http_event.data
            elif isinstance(http_event, DatagramReceived):
                self.datagrams += http_event.data

    def sent_frames_from_logger(self, logger: QuicLogger) -> list:
        frames = []
        for trace in logger.to_dict().get("traces", []):
            for entry in trace.get("events", []):
                if entry.get("name") not in ("transport:packet_sent", "quic:packet_sent"):
                    continue
                for frame in entry.get("data", {}).get("frames", []):
                    frames.append(frame)

        return frames

    async def wait_for(self, predicate, timeout: float) -> bool:
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            if predicate():
                return True
            await asyncio.sleep(0.02)

        return predicate()

    def describe_sent(self) -> str:
        return ", ".join(frame_summary(f) for f in self.sent_frames) if self.sent_frames else "(nothing)"


async def main() -> int:
    failures = []

    configuration = QuicConfiguration(
        alpn_protocols=["h3"],
        is_client=True,
        max_datagram_frame_size=1200,
        idle_timeout=30.0,
    )
    configuration.verify_mode = ssl.CERT_NONE
    quic_logger = QuicLogger()
    configuration.quic_logger = quic_logger

    async with connect(HOST, PORT, configuration=configuration, create_protocol=Client) as client:
        await client.wait_connected()
        print("1. handshake: connected")

        client.http.send_headers(
            stream_id=CONNECT_STREAM_ID,
            headers=[
                (b":method", b"CONNECT"),
                (b":protocol", b"webtransport"),
                (b":scheme", b"https"),
                (b":authority", f"{HOST}:{PORT}".encode()),
                (b":path", PATH.encode()),
            ],
        )
        client.transmit()

        if not await client.wait_for(lambda: client.connect_status is not None, 10):
            print("2. CONNECT: no response")
            print(f"   frames sent: {client.describe_sent()}")
            return 1

        print(f"2. CONNECT: {client.connect_status}")
        if not client.connect_status.startswith("2"):
            failures.append(f"CONNECT answered {client.connect_status}")

        # 3. A bidirectional WebTransport stream, echoed.
        stream_id = client.http.create_webtransport_stream(CONNECT_STREAM_ID, is_unidirectional=False)
        client.wt_stream_id = stream_id
        client._quic.send_stream_data(stream_id, STREAM_PAYLOAD, end_stream=False)
        client.transmit()
        print(f"3. stream {stream_id}: sent {len(STREAM_PAYLOAD)} bytes")

        got = await client.wait_for(lambda: len(client.stream_echo) >= len(STREAM_PAYLOAD), 10)
        print(f"   stream {stream_id}: received {bytes(client.stream_echo)!r}")
        if not got or bytes(client.stream_echo) != STREAM_PAYLOAD:
            failures.append(f"stream echo mismatch: {bytes(client.stream_echo)!r}")

        # 4. A datagram, echoed.
        client.http.send_datagram(CONNECT_STREAM_ID, DATAGRAM_PAYLOAD)
        client.transmit()
        print(f"4. datagram: sent {len(DATAGRAM_PAYLOAD)} bytes")

        got = await client.wait_for(lambda: len(client.datagrams) >= len(DATAGRAM_PAYLOAD), 10)
        print(f"   datagram: received {bytes(client.datagrams)!r}")
        if not got or bytes(client.datagrams) != DATAGRAM_PAYLOAD:
            failures.append(f"datagram echo mismatch: {bytes(client.datagrams)!r}")

        # 5. The server-opened unidirectional stream.
        got = await client.wait_for(lambda: len(client.server_streams) > 0, 10)
        if not got:
            failures.append("no server-opened unidirectional stream")
        else:
            stream_id, data, ended = client.server_streams[0]
            print(f"5. server stream {stream_id}: {len(data)} bytes, fin={ended}, {data[:40]!r}")
            if not data.startswith(BANNER_PREFIX):
                failures.append(f"unexpected banner: {data!r}")
            if not ended:
                failures.append("banner stream did not end (no FIN)")

        print("   frames this client sent:")
        for frame in client.sent_frames_from_logger(quic_logger):
            print(f"     {frame_summary(frame)}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")

        return 1

    print("PASS: session, stream echo, datagram echo, server-opened stream")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
