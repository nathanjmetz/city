#!/usr/bin/env python3
"""Joins everything a stress run (tools/scale/region_stress.sh) wrote into
OUT/region_stress.json and a short plain summary (OUT/summary.md, also printed).

Run: python3 tools/scale/region_stress_report.py OUT_DIR
"""
import glob
import json
import re
import os
import sys

out = sys.argv[1]


def load(name, default=None):
    path = os.path.join(out, name)
    if not os.path.exists(path):
        return default
    try:
        with open(path) as f:
            return json.load(f)
    except (ValueError, OSError):
        return default


def lines(name):
    path = os.path.join(out, name)
    rows = []
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
    return rows


def alive(rows):
    """Samples taken while the process still existed (ps reports zeros after)."""
    out = []
    for r in rows:
        procs = {k: v for k, v in r["procs"].items() if v.get("rss_mb", 0) > 0}
        if procs:
            out.append({"t": r["t"], "load": r["load"], "procs": procs})
    return out


def pct(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(len(s) - 1, int(len(s) * p / 100.0))]


def stats(values, nd=1):
    if not values:
        return {"n": 0}
    return {"n": len(values), "mean": round(sum(values) / len(values), nd), "p50": round(pct(values, 50), nd),
            "p95": round(pct(values, 95), nd), "p99": round(pct(values, 99), nd), "max": round(max(values), nd)}


roster = load("roster.json", [])
net = load("net.json", {"bots": {}, "seconds": 0})
probe = load("probe.json", [])
duration = float(open(os.path.join(out, "duration_s.txt")).read()) if os.path.exists(os.path.join(out, "duration_s.txt")) else 0.0
city_of = {p["name"]: p["city"] for p in roster if p["city"]}
name_of_city = {v: k for k, v in city_of.items()}
late_names = [p["name"] for p in roster if not p["city"]]
first_names = [p["name"] for p in roster if p["city"]]

result = {"roster": roster, "duration_s": duration}

# ---- Who was in, and when (seconds on the proxy's clock) ----
joined_at = {}
left_at = {}
for name, b in net["bots"].items():
    ws = [c.get("welcome_at") for c in b["connections"] if c.get("welcome_at") is not None]
    if ws:
        joined_at[name] = min(ws)
    cs = [c["closed"] for c in b["connections"] if c.get("closed") is not None]
    if cs:
        left_at[name] = max(cs)
steady_from = max([joined_at[n] for n in first_names if n in joined_at] or [0]) + 30
steady_to = min([left_at[n] for n in first_names if n in left_at] or [net.get("seconds", 0)]) - 5
if steady_to <= steady_from:
    steady_from, steady_to = 0, net.get("seconds", 0)
result["steady_window_s"] = [round(steady_from, 1), round(steady_to, 1)]

# ---- Server CPU and memory ----
server = alive(lines("procs-server.jsonl"))
cpu = []
for a, b in zip(server, server[1:]):
    dt = b["t"] - a["t"]
    if dt > 0 and "server" in a["procs"] and "server" in b["procs"]:
        cpu.append((b["t"], 100.0 * (b["procs"]["server"]["cpu_s"] - a["procs"]["server"]["cpu_s"]) / dt))
# The proxy clock and the monitor clock start a few seconds apart; the
# monitor starts first, so shift by the offset (the proxy starts ~2 s later).
cpu_all = [c for _, c in cpu]
cpu_steady = [c for t, c in cpu if steady_from <= t <= steady_to]
rss = [(s["t"], s["procs"]["server"]["rss_mb"]) for s in server if "server" in s["procs"]]
result["server"] = {
    "cpu_percent_of_one_core": {"whole_run": stats(cpu_all), "steady": stats(cpu_steady)},
    "cpu_busy_seconds_over_90pct": sum(1 for c in cpu_all if c >= 90) * 2,
    "memory_mb": {"start": rss[0][1] if rss else 0, "end": rss[-1][1] if rss else 0, "peak": max([r for _, r in rss] or [0])},
    "memory_series": [[round(t), r] for t, r in rss[::15]],
    "cpu_series": [[round(t), round(c)] for t, c in cpu[::15]],
}

# ---- Bytes ----
bots_net = {}
tot_up = [0] * (int(net.get("seconds", 0)) + 1)
tot_down = [0] * (int(net.get("seconds", 0)) + 1)
for name, b in net["bots"].items():
    up, down = b["per_sec_up"], b["per_sec_down"]
    for i, v in enumerate(up):
        tot_up[i] += v
    for i, v in enumerate(down):
        tot_down[i] += v
    win = lambda arr: arr[int(steady_from):int(steady_to)]  # noqa: E731
    bots_net[name] = {
        "sent_to_server_mb": round(b["bytes_up"] / 1e6, 2), "received_from_server_mb": round(b["bytes_down"] / 1e6, 2),
        "steady_up_kb_per_s": round(sum(win(up)) / max(1, len(win(up))) / 1024.0, 1),
        "steady_down_kb_per_s": round(sum(win(down)) / max(1, len(win(down))) / 1024.0, 1),
        "peak_up_kb_per_s": round(max(up or [0]) / 1024.0, 1), "peak_down_kb_per_s": round(max(down or [0]) / 1024.0, 1),
        "connections": len(b["connections"]),
    }
w_up, w_down = tot_up[int(steady_from):int(steady_to)], tot_down[int(steady_from):int(steady_to)]
result["bytes"] = {
    "per_player": bots_net,
    "total_into_server": {"total_mb": round(sum(tot_up) / 1e6, 1), "steady_kb_per_s": round(sum(w_up) / max(1, len(w_up)) / 1024.0, 1),
                          "peak_kb_per_s": round(max(tot_up or [0]) / 1024.0, 1)},
    "total_out_of_server": {"total_mb": round(sum(tot_down) / 1e6, 1), "steady_kb_per_s": round(sum(w_down) / max(1, len(w_down)) / 1024.0, 1),
                            "peak_kb_per_s": round(max(tot_down or [0]) / 1024.0, 1)},
}
types = {}
for name, b in net["bots"].items():
    for key, t in b["by_type"].items():
        a = types.setdefault(key, {"n": 0, "mb": 0.0, "max_mb": 0.0})
        a["n"] += t["n"]
        a["mb"] += t["bytes"] / 1e6
        a["max_mb"] = max(a["max_mb"], t["max"] / 1e6)
result["bytes"]["by_message"] = {k: {"n": v["n"], "mb": round(v["mb"], 2), "biggest_mb": round(v["max_mb"], 2)}
                                 for k, v in sorted(types.items(), key=lambda kv: -kv[1]["mb"])}

# ---- Joining: hello to the end of the welcome ----
joins = []
for name, b in net["bots"].items():
    for i, c in enumerate(b["connections"]):
        if c.get("welcome_at") is not None and c.get("hello_at") is not None:
            joins.append({"player": name, "connection": i + 1, "late": name in late_names or i > 0,
                          "welcome_mb": round(c.get("welcome_bytes", 0) / 1e6, 2),
                          "hello_to_welcome_s": round(c["welcome_at"] - c["hello_at"], 2),
                          "welcome_arrival_s": round(c["welcome_at"] - c.get("welcome_start", c["welcome_at"]), 2),
                          "at_s": round(c["welcome_at"], 1)})
bots = {}
for path in sorted(glob.glob(os.path.join(out, "*.json"))):
    name = os.path.basename(path)[:-5]
    if name in [p["name"] for p in roster]:
        with open(path) as f:
            bots[name] = json.load(f)
for j in joins:
    r = bots.get(j["player"], {})
    for s in r.get("steps", []):
        if s.get("step") == "load":
            j["bot_load_s"] = s["seconds"]
result["joins"] = joins

# ---- Sync lag: owner's postcard going in, neighbor's copy coming out ----
msgs = lines("net_msgs.jsonl")
ups = {}
downs = {}
for m in msgs:
    if m["type"] != "city":
        continue
    if m["dir"] == "up":
        ups.setdefault(m["bot"], []).append(m)
    else:
        downs.setdefault((m["bot"], m["id"]), []).append(m)
lags = []
per_pair = {}
for (receiver, cid), arr in downs.items():
    owner = name_of_city.get(cid)
    if not owner or owner == receiver or owner not in ups:
        continue
    joined = joined_at.get(receiver, 0)
    queue = [u for u in ups[owner] if u["last"] >= joined - 1]
    k = 0
    for d in arr:
        if d["last"] < joined:
            continue
        # the latest upstream copy that had fully arrived when this went out
        while k + 1 < len(queue) and queue[k + 1]["last"] <= d["first"] + 0.001:
            k += 1
        if k < len(queue) and queue[k]["last"] <= d["last"]:
            lag = d["last"] - queue[k]["last"]
            lags.append(lag)
            per_pair.setdefault("%s->%s" % (owner, receiver), []).append(lag)
            k += 1
        if k >= len(queue):
            break
result["sync_lag_wire_s"] = {"all": stats(lags, 2),
                             "worst_pairs": sorted(({"pair": p, "max_s": round(max(v), 2), "p50_s": round(pct(v, 50), 2)}
                                                    for p, v in per_pair.items()), key=lambda x: -x["max_s"])[:5]}
# What each player ends up seeing of every neighbor, against the owner's own count.
seen = []
for name, r in bots.items():
    view = r.get("region", {})
    towns = view.get("towns", {})
    for cid, t in towns.items():
        owner = name_of_city.get(cid)
        if not owner or owner == name or owner not in bots:
            continue
        own = bots[owner].get("region", {}).get("towns", {}).get(cid, {}).get("buildings", 0)
        seen.append({"viewer": name, "owner": owner, "owner_buildings": own, "seen_buildings": t.get("buildings", 0),
                     "behind": own - t.get("buildings", 0)})
result["on_screen_at_end"] = {"pairs": len(seen), "behind": stats([s["behind"] for s in seen], 0),
                              "worst": sorted(seen, key=lambda s: -s["behind"])[:5]}

# ---- Is the server keeping up? ----
ok = [p["total_ms"] for p in probe if p.get("ok")]
bad = [p for p in probe if not p.get("ok")]
stalls = sorted(probe, key=lambda p: -p["total_ms"])[:8]
result["server_answer_ms"] = {"stats": stats(ok, 0), "failed": len(bad), "over_1s": sum(1 for v in ok if v > 1000),
                              "over_5s": sum(1 for v in ok if v > 5000), "samples": len(probe),
                              "worst": [{"at_s": s["at"], "ms": round(s["total_ms"])} for s in stalls]}

# ---- Each bot ----
bot_rows = {}
for name, r in bots.items():
    total = r.get("total", {})
    view = r.get("region", {})
    netv = view.get("net", {})
    procs = alive(lines("procs-%s.jsonl" % name))
    cpu_avg = 0.0
    have = [x for x in procs if name in x["procs"]]
    if len(have) > 1:
        cpu_avg = 100.0 * (have[-1]["procs"][name]["cpu_s"] - have[0]["procs"][name]["cpu_s"]) / max(1e-6, have[-1]["t"] - have[0]["t"])
    rss_peak = max([x["procs"][name]["rss_mb"] for x in procs if name in x["procs"]] or [0])
    steps = {s["step"]: s for s in r.get("steps", [])}
    run = steps.get("run", {})
    bot_rows[name] = {"ok": r.get("ok"), "error": r.get("error"), "people": r.get("population"), "buildings": r.get("buildings"),
                      "frame_p50_ms": run.get("p50_ms"), "frame_p95_ms": run.get("p95_ms"), "frame_p99_ms": run.get("p99_ms"),
                      "frame_max_ms": total.get("max_ms"), "hitches_over_100ms": total.get("hitches"), "freezes_over_1s": total.get("freezes"),
                      "frames": total.get("frames"), "dropped": netv.get("disconnected", 0), "reconnected": netv.get("reconnected", 0),
                      "failed": netv.get("failed", []), "memory_peak_mb": r.get("memory_peak_mb"), "rss_peak_mb": rss_peak, "cpu_percent_of_one_core": round(cpu_avg),
                      "city_lines_hitch_s": round(r.get("hitch_causes", {}).get("frame.city_lines", 0) / 1000.0), "run_s": run.get("seconds"), "hitch_causes_ms": {k: round(v) for k, v in sorted(r.get("hitch_causes", {}).items(), key=lambda kv: -kv[1])[:4]},
                      "worst_freezes": sorted(r.get("freezes", []), key=lambda f: -f["ms"])[:3],
                      "grown": r.get("grown"), "load_s": steps.get("load", {}).get("seconds"), "actions": r.get("actions", {})}
result["bots"] = bot_rows
result["reconnects"] = {n: b["connections"] for n, b in bots_net.items() if b["connections"] > 1}

# Server log: anything odd.
server_log = []
path = os.path.join(out, "server.log")
if os.path.exists(path):
    with open(path, errors="replace") as f:
        server_log = [l.strip() for l in f if ("ERROR" in l or "Turned away" in l or "Couldn't" in l or "Wrong PIN" in l) and "version 1," not in l]
result["server_log_problems"] = server_log[:20]
# The server's own loop: any step over 100 ms is logged as "Slow step: X took N ms".
slow = []
if os.path.exists(path):
    with open(path, errors="replace") as f:
        for l in f:
            m = re.search(r"Slow step: (\S+) took (\d+) ms", l)
            if m:
                slow.append((m.group(1), int(m.group(2))))
by_step = {}
for step, ms in slow:
    by_step.setdefault(step, []).append(ms)
result["server_slow_steps"] = {"count": len(slow), "max_ms": max([ms for _, ms in slow] or [0]),
                               "by_step": {k: {"n": len(v), "max_ms": max(v)} for k, v in by_step.items()}}
# The most the city lines added to any frame that went over 100 ms, per bot
# (a frame under 100 ms isn't a hitch, so isn't kept).
for name, r in bot_rows.items():
    raw = load(name + ".json", {}) or {}
    worst = 0.0
    for fr in raw.get("freezes", []):
        worst = max(worst, float(fr.get("stages", {}).get("frame.city_lines", 0.0)))
    r["city_lines_worst_in_a_hitch_ms"] = round(worst, 1)

with open(os.path.join(out, "region_stress.json"), "w") as f:
    json.dump(result, f, indent=1)

# ---- Plain summary ----
S = []
S.append("Run: %d players with towns (%s people in the biggest), %d late joiners, %.0f s. Steady window %s s."
         % (len(first_names), max([b["people"] or 0 for b in bot_rows.values()] or [0]), len(late_names), duration, result["steady_window_s"]))
S.append("")
sv = result["server"]
S.append("Server CPU (one core = 100): steady mean %s, p95 %s, max %s. Seconds pinned over 90: %s. Memory %d MB at start, %d at end, %d peak."
         % (sv["cpu_percent_of_one_core"]["steady"].get("mean"), sv["cpu_percent_of_one_core"]["steady"].get("p95"),
            sv["cpu_percent_of_one_core"]["whole_run"].get("max"), sv["cpu_busy_seconds_over_90pct"],
            sv["memory_mb"]["start"], sv["memory_mb"]["end"], sv["memory_mb"]["peak"]))
b = result["bytes"]
S.append("Bytes: server takes in %s KB/s steady (peak %s), sends out %s KB/s steady (peak %s). Whole run: %s MB in, %s MB out."
         % (b["total_into_server"]["steady_kb_per_s"], b["total_into_server"]["peak_kb_per_s"], b["total_out_of_server"]["steady_kb_per_s"],
            b["total_out_of_server"]["peak_kb_per_s"], b["total_into_server"]["total_mb"], b["total_out_of_server"]["total_mb"]))
S.append("Server answer time (probe): %s ms; failed %d; over 1 s: %d; over 5 s: %d of %d."
         % (result["server_answer_ms"]["stats"], result["server_answer_ms"]["failed"], result["server_answer_ms"]["over_1s"],
            result["server_answer_ms"]["over_5s"], result["server_answer_ms"]["samples"]))
S.append("Sync lag on the wire (owner's copy in, neighbor's copy out): %s s." % result["sync_lag_wire_s"]["all"])
S.append("Neighbors' towns on screen at the end: behind by %s buildings." % result["on_screen_at_end"]["behind"])
ss = result["server_slow_steps"]
S.append("Server loop steps over 100 ms: %d (worst %d ms) %s." % (ss["count"], ss["max_ms"], ss["by_step"]))
S.append("City lines in frames over 100 ms (most in any one, per bot): %s ms."
         % {n: r["city_lines_worst_in_a_hitch_ms"] for n, r in bot_rows.items()})
S.append("")
S.append("| player | people | p50 ms | p95 ms | worst ms | freezes >1 s | hitches >100 ms | dropped/back | KB/s up | KB/s down | CPU % | peak RSS MB |")
S.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
for name, r in bot_rows.items():
    n = bots_net.get(name, {})
    S.append("| %s | %s | %s | %s | %s | %s | %s | %s/%s | %s | %s | %s | %s |" % (
        name, r["people"], r["frame_p50_ms"], r["frame_p95_ms"], r["frame_max_ms"], r["freezes_over_1s"], r["hitches_over_100ms"],
        r["dropped"], r["reconnected"], n.get("steady_up_kb_per_s"), n.get("steady_down_kb_per_s"), r["cpu_percent_of_one_core"], r["rss_peak_mb"]))
S.append("")
S.append("| joiner | late | welcome MB | hello to welcome s | bot's load s |")
S.append("|---|---|---|---|---|")
for j in joins:
    S.append("| %s | %s | %s | %s | %s |" % (j["player"], "yes" if j["late"] else "", j["welcome_mb"], j["hello_to_welcome_s"], j.get("bot_load_s", "")))
S.append("")
problems = []
for n, r in bot_rows.items():
    if not r["ok"]:
        problems.append("%s: %s" % (n, r["error"]))
    if r["failed"]:
        problems.append("%s: %s" % (n, r["failed"]))
if result["reconnects"]:
    problems.append("second connections: %s" % result["reconnects"])
problems += sorted(set(result["server_log_problems"]))
S.append("Problems: " + ("; ".join(problems) if problems else "none"))
text = "\n".join(S)
with open(os.path.join(out, "summary.md"), "w") as f:
    f.write(text + "\n")
print(text)
