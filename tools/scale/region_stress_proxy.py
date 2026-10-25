#!/usr/bin/env python3
"""A counting go-between for the shared-region stress test.

Every player connects to its own port here; this forwards everything to the
region server untouched and writes down, per player: how many bytes went each
way each second, what kinds of messages they were and how big, how long each
big message took to arrive, every connection (a second one is a reconnect),
and the time from a player's "hello" to the end of the region's "welcome" (how
long joining takes on the wire).

It only reads the WebSocket framing (not the game's own data), so it adds a
copy but no work the game would not do. Run by tools/scale/region_stress.sh.

  region_stress_proxy.py --names Bot1,Bot2 --base-port 9200 --target 9098 --out DIR

Stop it with SIGTERM or SIGINT: it writes DIR/net.json and DIR/net_msgs.jsonl.
"""
import argparse
import asyncio
import json
import os
import re
import signal
import time

T_RE = re.compile(rb'"t"\s*:\s*"([a-z_]+)"')
ID_RE = re.compile(rb'"id"\s*:\s*"([^"]{1,64})"')
PREFIX = 400


class Frames:
    """Reads WebSocket frames from one direction of a connection."""

    def __init__(self, on_message, on_bytes):
        self.on_message = on_message
        self.buf = bytearray()
        self.http_done = False
        self.state = "head"
        self.remaining = 0
        self.masked = False
        self.mask = b""
        self.opcode = 0
        self.fin = True
        self.prefix = bytearray()
        self.msg_first = None   # time the first bytes of the message arrived
        self.msg_size = 0
        self.msg_prefix = b""
        self.frame_first = None
        self.part = None        # a message coming in parts, so far

    def feed(self, data, now):
        if not self.http_done:
            self.buf += data
            i = self.buf.find(b"\r\n\r\n")
            if i < 0:
                return
            data = bytes(self.buf[i + 4:])
            self.buf = bytearray()
            self.http_done = True
            if not data:
                return
        self.buf += data
        while True:
            if self.state == "head":
                if len(self.buf) < 2:
                    return
                b0, b1 = self.buf[0], self.buf[1]
                n = b1 & 0x7F
                masked = bool(b1 & 0x80)
                need = 2 + (2 if n == 126 else 8 if n == 127 else 0) + (4 if masked else 0)
                if len(self.buf) < need:
                    return
                pos = 2
                if n == 126:
                    n = int.from_bytes(self.buf[2:4], "big")
                    pos = 4
                elif n == 127:
                    n = int.from_bytes(self.buf[2:10], "big")
                    pos = 10
                self.mask = bytes(self.buf[pos:pos + 4]) if masked else b""
                self.masked = masked
                self.fin = bool(b0 & 0x80)
                self.opcode = b0 & 0x0F
                self.remaining = n
                self.frame_len = n
                self.prefix = bytearray()
                self.frame_first = now
                del self.buf[:need]
                self.state = "payload"
            if self.state == "payload":
                take = min(len(self.buf), self.remaining)
                if take and len(self.prefix) < PREFIX:
                    want = PREFIX - len(self.prefix)
                    self.prefix += self.buf[:min(take, want)]
                del self.buf[:take]
                self.remaining -= take
                if self.remaining > 0:
                    return
                self.state = "head"
                self.frame_done(now)

    def frame_done(self, now):
        if self.opcode in (1, 2):
            self.msg_first = self.frame_first
            self.msg_size = 0
            pre = bytes(self.prefix)
            if self.masked and self.mask:
                pre = bytes(b ^ self.mask[i % 4] for i, b in enumerate(pre))
            self.msg_prefix = pre
        elif self.opcode != 0:
            return  # ping, pong, close
        self.msg_size += self.frame_len
        if self.fin:
            pre = self.msg_prefix
            # A big message comes as parts (scripts/net/net_link.gd): PART (1),
            # 1 if more follow, its whole size (u32), then the bytes. The
            # parts of one message come one after another; they count as one
            # message, from the first part's start to the last part's end.
            if len(pre) >= 6 and pre[0] == 1:
                if self.part is None:
                    t = T_RE.search(pre[6:])
                    i = ID_RE.search(pre[6:])
                    self.part = {"t": t.group(1).decode() if t else "?", "id": i.group(1).decode() if i else "",
                                 "first": self.msg_first, "size": 0}
                self.part["size"] += self.msg_size
                if pre[1] == 0:
                    p = self.part
                    self.part = None
                    self.on_message(p["t"], p["id"], p["size"], p["first"], now)
                return
            t = T_RE.search(pre)
            i = ID_RE.search(pre)
            self.on_message(t.group(1).decode() if t else "?", i.group(1).decode() if i else "",
                            self.msg_size, self.msg_first, now)


class Proxy:
    def __init__(self, names, base_port, target, out):
        self.names = names
        self.base_port = base_port
        self.target = target
        self.out = out
        self.t0 = time.time()
        self.bots = {n: {"connections": [], "up": {}, "down": {}, "bytes_up": 0, "bytes_down": 0,
                         "by_type": {}} for n in names}
        os.makedirs(out, exist_ok=True)
        self.msgs = open(os.path.join(out, "net_msgs.jsonl"), "w")

    def now(self):
        return time.time() - self.t0

    def count(self, name, direction, n):
        b = self.bots[name]
        sec = int(self.now())
        b[direction][sec] = b[direction].get(sec, 0) + n
        b["bytes_" + direction] += n

    def message(self, name, direction, conn, typ, ident, size, first, last):
        b = self.bots[name]
        key = "%s:%s" % (direction, typ)
        t = b["by_type"].setdefault(key, {"n": 0, "bytes": 0, "max": 0})
        t["n"] += 1
        t["bytes"] += size
        t["max"] = max(t["max"], size)
        if typ == "hello" and direction == "up":
            conn["hello_at"] = last
        if typ == "welcome" and direction == "down":
            conn["welcome_start"] = first
            conn["welcome_at"] = last
            conn["welcome_bytes"] = size
        if typ in ("reject", "waiting"):
            conn.setdefault("rejects", []).append(typ)
        # Small chatter is only counted; the rest is logged for sync lag.
        if typ in ("city", "welcome", "region", "telemetry", "apply") or size > 20000:
            self.msgs.write(json.dumps({"bot": name, "dir": direction, "type": typ, "id": ident, "bytes": size,
                                        "first": round(first, 3), "last": round(last, 3)}) + "\n")

    async def handle(self, name, reader, writer):
        conn = {"opened": round(self.now(), 3), "closed": None}
        self.bots[name]["connections"].append(conn)
        try:
            up_r, up_w = await asyncio.open_connection("127.0.0.1", self.target)
        except OSError as e:
            conn["error"] = str(e)
            writer.close()
            return
        up_frames = Frames(lambda *a: self.message(name, "up", conn, a[0], a[1], a[2], a[3] - self.t0, a[4] - self.t0), None)
        down_frames = Frames(lambda *a: self.message(name, "down", conn, a[0], a[1], a[2], a[3] - self.t0, a[4] - self.t0), None)

        async def pump(src, dst, frames, direction):
            try:
                while True:
                    data = await src.read(262144)
                    if not data:
                        break
                    now = time.time()
                    self.count(name, direction, len(data))
                    frames.feed(data, now)
                    dst.write(data)
                    await dst.drain()
            except (ConnectionError, OSError):
                pass
            finally:
                try:
                    dst.close()
                except OSError:
                    pass

        await asyncio.gather(pump(reader, up_w, up_frames, "up"), pump(up_r, writer, down_frames, "down"))
        conn["closed"] = round(self.now(), 3)

    async def run(self):
        servers = []
        for i, name in enumerate(self.names):
            servers.append(await asyncio.start_server(
                lambda r, w, name=name: self.handle(name, r, w), ["127.0.0.1", "::1"], self.base_port + i, limit=1 << 22))
        print("proxy up for %s on ports %d.." % (",".join(self.names), self.base_port), flush=True)
        stop = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, stop.set)
        await stop.wait()
        for s in servers:
            s.close()
        self.save()

    def save(self):
        self.msgs.close()
        end = int(self.now()) + 1
        out = {"seconds": end, "bots": {}}
        for name, b in self.bots.items():
            out["bots"][name] = {
                "connections": b["connections"], "bytes_up": b["bytes_up"], "bytes_down": b["bytes_down"],
                "by_type": b["by_type"],
                "per_sec_up": [b["up"].get(s, 0) for s in range(end)],
                "per_sec_down": [b["down"].get(s, 0) for s in range(end)],
            }
        with open(os.path.join(self.out, "net.json"), "w") as f:
            json.dump(out, f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--names", required=True)
    ap.add_argument("--base-port", type=int, default=9200)
    ap.add_argument("--target", type=int, default=9098)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    p = Proxy(a.names.split(","), a.base_port, a.target, a.out)
    asyncio.run(p.run())


if __name__ == "__main__":
    main()
