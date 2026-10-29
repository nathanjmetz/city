#!/usr/bin/env python3
"""Fetches the desktop app's real-life textures from Poly Haven (CC0).

Reads tools/textures/list.json ({"<poly haven id>": {"res": "2k", "use": "..."}})
and writes art/pbr/<id>/albedo.jpg and normal.jpg (OpenGL normals), then
art/pbr/SOURCES.md with each texture's author, real size and use. The Web
export leaves art/pbr out, so the browser download doesn't grow.
Run: python3 tools/textures/fetch.py
"""
import json, os, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UA = {"User-Agent": "neighbors-city-builder (github.com/nathanjmetz/city)"}
MAPS = {"Diffuse": "albedo", "nor_gl": "normal"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def main():
    with open(os.path.join(ROOT, "tools/textures/list.json")) as f:
        wanted = json.load(f)
    base = os.path.join(ROOT, "art/pbr")
    rows = []
    for aid, spec in sorted(wanted.items()):
        res = spec.get("res", "2k")
        files = json.loads(get("https://api.polyhaven.com/files/" + aid))
        info = json.loads(get("https://api.polyhaven.com/info/" + aid))
        dest = os.path.join(base, aid)
        os.makedirs(dest, exist_ok=True)
        for key, name in MAPS.items():
            path = os.path.join(dest, name + ".jpg")
            if not os.path.exists(path):
                with open(path, "wb") as f:
                    f.write(get(files[key][res]["jpg"]["url"]))
        size = info.get("dimensions", [0, 0])
        rows.append("- `%s` (%s, %.1f x %.1f m): %s. https://polyhaven.com/a/%s by %s" % (
            aid, res, size[0] / 1000.0, size[1] / 1000.0, spec.get("use", ""), aid,
            ", ".join(info.get("authors", {}).keys())))
        print("ok", aid)
    with open(os.path.join(base, "SOURCES.md"), "w") as f:
        f.write("# Real-life textures (desktop app only)\n\n")
        f.write("From Poly Haven (https://polyhaven.com), CC0 1.0 Universal (public domain): free for any use,\n")
        f.write("no credit required, credited here anyway. Fetched by `tools/textures/fetch.py` from\n")
        f.write("`tools/textures/list.json`. The Web export leaves `art/pbr/` out.\n\n")
        f.write("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
