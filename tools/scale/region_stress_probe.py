#!/usr/bin/env python3
"""Asks the region server a harmless question every couple of seconds and
times the answer, so a server that is busy (saving, unpacking a big town,
sending a welcome) shows up as a slow answer.

The question is a hello from a game too old to join: the server answers
"reject" at once and changes nothing. The time covers opening the connection,
the WebSocket handshake and the answer, all of which the server only does
between its own frames, so it is the longest the server was away from the
network.

  region_stress_probe.py --port 9098 --seconds 1500 --out DIR/probe.json
"""
import argparse
import asyncio
import base64
import json
import os
import signal
import struct
import time


def masked_text(payload: bytes) -> bytes:
    key = os.urandom(4)
    n = len(payload)
    head = bytes([0x81])
    if n < 126:
        head += bytes([0x80 | n])
    elif n < 65536:
        head += bytes([0x80 | 126]) + struct.pack(">H", n)
    else:
        head += bytes([0x80 | 127]) + struct.pack(">Q", n)
    return head + key + bytes(b ^ key[i % 4] for i, b in enumerate(payload))


async def ask(port: int, timeout: float):
    t0 = time.time()
    r, w = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", port), timeout)
    try:
        key = base64.b64encode(os.urandom(16)).decode()
        w.write(("GET /STRESS HTTP/1.1\r\nHost: localhost:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                 "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (port, key)).encode())
        await w.drain()
        await asyncio.wait_for(r.readuntil(b"\r\n\r\n"), timeout)
        t1 = time.time()
        w.write(masked_text(json.dumps({"t": "hello", "v": 1, "min": 1, "name": "probe"}).encode()))
        await w.drain()
        head = await asyncio.wait_for(r.readexactly(2), timeout)
        n = head[1] & 0x7F
        if n == 126:
            n = struct.unpack(">H", await r.readexactly(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", await r.readexactly(8))[0]
        await asyncio.wait_for(r.readexactly(n), timeout)
        t2 = time.time()
        return {"connect_ms": (t1 - t0) * 1000.0, "answer_ms": (t2 - t1) * 1000.0, "total_ms": (t2 - t0) * 1000.0}
    finally:
        w.close()


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9098)
    ap.add_argument("--seconds", type=float, default=600)
    ap.add_argument("--every", type=float, default=2.0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    t_start = time.time()
    samples = []
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    while time.time() - t_start < a.seconds and not stop.is_set():
        at = time.time() - t_start
        try:
            s = await ask(a.port, 60.0)
            s["at"] = round(at, 2)
            s["ok"] = True
        except Exception as e:  # noqa: BLE001 - any failure is a data point
            s = {"at": round(at, 2), "ok": False, "error": repr(e), "total_ms": (time.time() - t_start - at) * 1000.0}
        samples.append(s)
        try:
            await asyncio.wait_for(stop.wait(), a.every)
        except asyncio.TimeoutError:
            pass
        # Write as we go: the run may be cut short.
        if len(samples) % 10 == 0:
            with open(a.out, "w") as f:
                json.dump(samples, f)
    with open(a.out, "w") as f:
        json.dump(samples, f)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
