#!/usr/bin/env python3
"""Samples the CPU time and memory of the processes a stress run started, and
the machine's load, every few seconds.

  region_stress_monitor.py --pids server=123,Bot1=456 --every 2 --out DIR/procs.jsonl

CPU is the process's cumulative CPU seconds (so a rate between two samples is
exact, and 100% means one full core); memory is resident memory in MB.
Stops when every process has ended, or on SIGINT/SIGTERM.
"""
import argparse
import json
import os
import signal
import subprocess
import time

running = True


def stop(*_):
    global running
    running = False


def cpu_seconds(text: str) -> float:
    # [[dd-]hh:]mm:ss.cc
    days = 0
    if "-" in text:
        d, text = text.split("-", 1)
        days = int(d)
    parts = [float(p) for p in text.split(":")]
    s = 0.0
    for p in parts:
        s = s * 60 + p
    return s + days * 86400


def sample(pids: dict) -> dict:
    out = {}
    if not pids:
        return out
    res = subprocess.run(["ps", "-o", "pid=,rss=,cputime=", "-p", ",".join(str(p) for p in pids.values())],
                         capture_output=True, text=True)
    by_pid = {}
    for line in res.stdout.splitlines():
        f = line.split()
        if len(f) >= 3:
            by_pid[int(f[0])] = (int(f[1]) / 1024.0, cpu_seconds(f[2]))
    for name, pid in pids.items():
        if pid in by_pid:
            out[name] = {"rss_mb": round(by_pid[pid][0], 1), "cpu_s": round(by_pid[pid][1], 2)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pids", required=True, help="name=pid,name=pid")
    ap.add_argument("--every", type=float, default=2.0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    pids = {}
    for item in a.pids.split(","):
        n, p = item.split("=")
        pids[n] = int(p)
    t0 = time.time()
    with open(a.out, "w") as f:
        while running:
            s = sample(pids)
            if not s:
                break
            f.write(json.dumps({"t": round(time.time() - t0, 2), "load": round(os.getloadavg()[0], 2), "procs": s}) + "\n")
            f.flush()
            time.sleep(a.every)


if __name__ == "__main__":
    main()
