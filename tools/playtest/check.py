#!/usr/bin/env python3
"""Checks play-through results (scripts/perf/playtest.gd) against budgets.

Writes a Markdown table (for the CI run's summary page) and exits 1 when a
run breaks a hard budget: a freeze long enough to look like a crash, memory
that would sink an 8 GB Mac, or a run that never finished. Softer targets
are shown as warnings, so the table says how far the game is from smooth.

Run: python3 tools/playtest/check.py budgets.json result.json [result.json ...]
"""
import json
import sys


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        return {"ok": False, "error": f"no result ({e})"}


def check(name, r, b):
    """[(level, text)] for one run; level is "fail", "warn" or "ok"."""
    out = []
    if not r.get("ok"):
        return [("fail", f"didn't finish: {r.get('error', '?')}")]
    actions = r.get("actions", {})
    for a in ("road", "grid", "join_county"):
        if actions.get(a) is False:
            out.append(("fail", f"the {a} step was refused"))
    play = [s for s in r.get("steps", []) if s.get("step") != "load"]
    worst = max((s.get("max_ms", 0) for s in play), default=0)
    worst_step = next((s["step"] for s in play if s.get("max_ms", 0) == worst), "")
    hitches = sum(s.get("hitches", 0) for s in play)
    seconds = sum(s.get("seconds", 0) for s in play) or 1
    per_min = hitches * 60.0 / seconds
    load = next((s for s in r.get("steps", []) if s.get("step") == "load"), {})
    mem = r.get("memory_peak_mb", 0)
    checks = [
        ("worst frame while playing", worst, "ms", b["freeze_fail_ms"], b["freeze_target_ms"], f" ({worst_step})"),
        ("hitches (frames over 100 ms) a minute", per_min, "", b["hitches_fail_per_min"], b["hitches_target_per_min"], ""),
        ("opening the town", load.get("seconds", 0), "s", b["load_fail_s"], b["load_target_s"], ""),
        ("memory at its peak", mem, "MB", b["memory_fail_mb"], b["memory_target_mb"], ""),
    ]
    for label, value, unit, fail, target, extra in checks:
        text = f"{label}: {value:,.0f} {unit}{extra} (target {target:,} {unit}, limit {fail:,} {unit})"
        out.append(("fail" if value > fail else "warn" if value > target else "ok", text))
    causes = sorted(r.get("hitch_causes", {}).items(), key=lambda kv: -kv[1])[:4]
    if causes:
        out.append(("info", "hitch time by cause: " + ", ".join(f"{k} {v / 1000:,.1f} s" for k, v in causes)))
    # The stages behind the worst freezes, so the table points at a culprit.
    for f in sorted(r.get("freezes", []), key=lambda f: -f["ms"])[:3]:
        if f.get("step") == "load":
            continue
        stages = ", ".join(f"{k} {v:,.0f}" for k, v in sorted(f["stages"].items(), key=lambda kv: -kv[1])[:3])
        out.append(("info", f"freeze {f['ms']:,.0f} ms in {f['step']}: {stages or 'no timed stage'}"))
    return out


def main():
    budgets = load(sys.argv[1])
    failed = False
    lines = ["### Play-through check", ""]
    for path in sys.argv[2:]:
        r = load(path)
        kind = path.rsplit("/", 1)[-1].removesuffix(".json")
        b = budgets.get(kind, budgets["default"])
        rows = check(kind, r, b)
        mark = "❌" if any(l == "fail" for l, _ in rows) else "⚠️" if any(l == "warn" for l, _ in rows) else "✅"
        lines.append(f"**{mark} {kind}**: population {r.get('population', 0)}, "
                     f"{r.get('total', {}).get('frames', 0)} frames, median {r.get('total', {}).get('p50_ms', 0)} ms")
        icon = {"fail": "❌", "warn": "⚠️", "ok": "✅", "info": "·"}
        lines += [f"- {icon[l]} {t}" for l, t in rows]
        lines.append("")
        failed |= any(l == "fail" for l, _ in rows)
    print("\n".join(lines))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
