#!/usr/bin/env python3
"""Judges a soak run (tools/playtest/soak.sh): every player finished and is
still in the region, nobody lost the connection for good, the server holds
each town as its owner last had it, and every player sees every other town.

Run: python3 tools/playtest/soak_check.py OUT_DIR"""
import glob
import json
import os
import sys

out = sys.argv[1]
problems = []
bots = {}
for path in sorted(glob.glob(os.path.join(out, "*.json"))):
    name = os.path.basename(path)[:-5]
    if name == "region":
        continue
    with open(path) as f:
        bots[name] = json.load(f)

with open(os.path.join(out, "region.json")) as f:
    region = json.load(f)
server = {cid: len(c["city"].get("buildings", {})) for cid, c in region["cities"].items()}
names = {cid: c["name"] for cid, c in region["cities"].items()}

print("| player | ok | worst frame ms | freezes | drops | streets added | own buildings | server copy |")
print("|---|---|---|---|---|---|---|---|")
owners = {}
for name, r in bots.items():
    view = r.get("region", {})
    me = view.get("me", "")
    own = view.get("towns", {}).get(me, {}).get("buildings", -1)
    owners[me] = (name, own)
    net = view.get("net", {})
    total = r.get("total", {})
    print(f"| {name} | {r.get('ok')} | {total.get('max_ms')} | {total.get('freezes')} | "
          f"{net.get('disconnected', 0)} lost, {net.get('reconnected', 0)} back | {r.get('grown', 0)} | {own} | {server.get(me, 'missing')} |")
    if not r.get("ok"):
        problems.append(f"{name}: {r.get('error')}")
    if not view.get("joined"):
        problems.append(f"{name}: not in the region at the end")
    for why in net.get("failed", []):
        problems.append(f"{name}: {why}")
    if me and server.get(me, -1) != own:
        problems.append(f"{name}: has {own} buildings, the server's copy {server.get(me)}")
    if total.get("freezes", 0):
        problems.append(f"{name}: {total.get('freezes')} freezes over a second")

# Each player sees every other town, not far behind its owner.
for name, r in bots.items():
    towns = r.get("region", {}).get("towns", {})
    for cid, (owner, own) in owners.items():
        if owner == name or not cid:
            continue
        seen = towns.get(cid)
        if seen is None:
            problems.append(f"{name} doesn't see {owner}'s town")
        elif own > 0 and seen["buildings"] < own * 0.5:
            problems.append(f"{name} sees {owner}'s town with {seen['buildings']} of {own} buildings")
    for cid in server:
        if cid not in towns:
            problems.append(f"{name} doesn't see {names[cid]}")

print()
print("\n".join("- " + p for p in problems) if problems else "All good: everyone stayed in, every town synced.")
sys.exit(1 if problems else 0)
