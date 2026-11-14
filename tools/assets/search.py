#!/usr/bin/env python3
"""Searches the free CC0 libraries for assets to add to tools/assets/catalog.json.

Run: python3 tools/assets/search.py <models|textures|hdris> [word ...] [--max-tris=N]
Prints id, name, real size (metres: wide x tall x deep for models), triangles and
categories, already-in-catalog marked with *. Poly Haven only for now (every
other free library is blocked from this container or isn't CC0/CC-BY).
Before adding one, check it against a real Midwestern version (the real-world rule):
note that reference in the catalog's "real" field.
"""
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UA = {"User-Agent": "neighbors-city-builder (github.com/nathanjmetz/city)"}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    kind = args[0] if args else "models"
    words = [w.lower() for w in args[1:]]
    max_tris = 0
    for a in sys.argv[1:]:
        if a.startswith("--max-tris="):
            max_tris = int(a.split("=")[1])
    t = {"models": "models", "textures": "textures", "hdris": "hdris"}[kind]
    req = urllib.request.Request("https://api.polyhaven.com/assets?t=" + t, headers=UA)
    assets = json.loads(urllib.request.urlopen(req, timeout=60).read())
    with open(os.path.join(ROOT, "tools/assets/catalog.json")) as f:
        have = json.load(f).get(kind, {})
    for aid, a in sorted(assets.items()):
        text = " ".join([aid, a.get("name", "")] + a.get("tags", []) + a.get("categories", [])).lower()
        if words and not any(w in text for w in words):
            continue
        tris = a.get("polycount", 0)
        if max_tris and tris > max_tris:
            continue
        d = a.get("dimensions", [0, 0, 0])
        size = "%.2fx%.2fx%.2f" % (d[0] / 1e3, d[2] / 1e3, d[1] / 1e3) if len(d) == 3 else "%.1fx%.1f" % (d[0] / 1e3, d[1] / 1e3) if d else ""
        cats = ",".join(c for c in a.get("categories", []) if not c.startswith("collection"))
        print("%s %-36s %-16s %8s  %s" % ("*" if aid in have else " ", aid, size, tris or "", cats))


if __name__ == "__main__":
    main()
