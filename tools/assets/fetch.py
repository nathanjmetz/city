#!/usr/bin/env python3
"""Fetches the free asset library: photo-scanned models, PBR textures and skies.

Reads tools/assets/catalog.json and writes, for the desktop app only:
  art/assets/models/<id>/<id>.gltf (+ .bin, textures/)  scanned props, in metres
  art/assets/pbr/<id>/albedo.jpg, normal.jpg, arm.jpg   tiling surfaces (arm = AO, rough, metal)
  art/assets/hdri/<id>.hdr                              skies for reflections and ambient light
  art/assets/index.json                                 what the game reads (AssetLib)
  art/assets/CREDITS.md                                 every asset's author, licence and link

LICENCE GATE: only licences that are free for any use, forever, and allow the
files to sit in this public repo are accepted: CC0-1.0 (public domain) and
CC-BY-4.0 (free, credit required; the credit goes in CREDITS.md and the game's
credits). Anything else -- Fab/Megascans Standard License, "free for personal
use", CC-BY-NC, CC-BY-ND, editorial, royalty-free-with-purchase -- is refused,
because the repo and web preview are public and those licences forbid
standalone redistribution or cost money.

Sources:
  "polyhaven"  api.polyhaven.com (always CC0)
  "url"        any direct file list; the entry must name "licence", "author" and "page"
  "scan"       a vehicle photo scan (Sketchfab, CC-BY): the unmodified download sits on
               the vehicle-scans-raw release as "raw" (a zip); it is cleaned here by
               tools/vehicles/bake_vehicle.py (Blender as a Python module, installed on
               first use) to "length" metres, front/back flipped when "flip" is true

Run: python3 tools/assets/fetch.py [id ...]     (no ids = everything in the catalog)
     python3 tools/assets/fetch.py --check      (licence/credit check only, no downloads)
The Web export leaves art/assets out, so the browser download doesn't grow.
"""
import hashlib, json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "tools/assets/catalog.json")
OUT = os.path.join(ROOT, "art/assets")
UA = {"User-Agent": "neighbors-city-builder (github.com/nathanjmetz/city)"}
ALLOWED = {
    "CC0-1.0": "CC0 1.0 Universal (public domain), https://creativecommons.org/publicdomain/zero/1.0/",
    "CC-BY-4.0": "Creative Commons Attribution 4.0, https://creativecommons.org/licenses/by/4.0/",
}
SOURCE_LICENCE = {"polyhaven": "CC0-1.0"}
# Poly Haven texture maps we keep, by their API key -> our file name.
TEX_MAPS = {"Diffuse": "albedo", "nor_gl": "normal", "arm": "arm"}
MAX_MB = 95.0  # GitHub refuses files over 100 MB
KINDS = ("models", "textures", "hdris")


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
        return r.read()


def get_json(url):
    return json.loads(get(url))


def save(url, path, md5=None):
    """Downloads url to path unless it's already there with the right md5."""
    if os.path.exists(path) and (md5 is None or _md5(path) == md5):
        return os.path.getsize(path)
    data = get(url)
    if md5 and hashlib.md5(data).hexdigest() != md5:
        raise RuntimeError("checksum mismatch for " + url)
    if len(data) / 1e6 > MAX_MB:
        raise RuntimeError("%s is %.0f MB, over the %d MB GitHub limit: pick a lower res" % (url, len(data) / 1e6, MAX_MB))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


def _md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def licence_of(spec):
    src = spec.get("src", "polyhaven")
    lic = SOURCE_LICENCE.get(src, spec.get("licence", ""))
    if lic not in ALLOWED:
        raise SystemExit("REFUSED %s: licence %r is not free for any use in a public repo (allowed: %s)"
                         % (spec.get("_id"), lic or "missing", ", ".join(ALLOWED)))
    if src != "polyhaven":
        for k in ("author", "page"):
            if not spec.get(k):
                raise SystemExit("REFUSED %s: a %s asset needs %r for its credit" % (spec.get("_id"), src, k))
    return lic


def fetch_polyhaven(kind, aid, spec):
    info = get_json("https://api.polyhaven.com/info/" + aid)
    files = get_json("https://api.polyhaven.com/files/" + aid)
    res = spec.get("res", {"models": "1k", "textures": "2k", "hdris": "2k"}[kind])
    total = 0
    entry = {"author": ", ".join(info.get("authors", {}).keys()), "page": "https://polyhaven.com/a/" + aid,
             "name": info.get("name", aid)}
    if kind == "models":
        g = files["gltf"][res]["gltf"]
        dest = os.path.join(OUT, "models", aid)
        total += save(g["url"], os.path.join(dest, aid + ".gltf"), g.get("md5"))
        for rel, f in g.get("include", {}).items():
            total += save(f["url"], os.path.join(dest, rel), f.get("md5"))
        d = info.get("dimensions", [0, 0, 0])  # mm, Blender axes: x wide, y deep, z up
        entry.update(path="res://art/assets/models/%s/%s.gltf" % (aid, aid),
                     size_m=[round(d[0] / 1000.0, 3), round(d[2] / 1000.0, 3), round(d[1] / 1000.0, 3)],
                     tris=info.get("polycount", 0))
    elif kind == "textures":
        dest = os.path.join(OUT, "pbr", aid)
        for key, name in TEX_MAPS.items():
            f = files[key][res]["jpg"]
            total += save(f["url"], os.path.join(dest, name + ".jpg"), f.get("md5"))
        write_texture_imports(dest)
        d = info.get("dimensions", [0, 0])
        entry.update(dir="res://art/assets/pbr/" + aid, size_m=[round(d[0] / 1000.0, 2), round(d[1] / 1000.0, 2)])
    else:
        f = files["hdri"][res]["hdr"]
        total += save(f["url"], os.path.join(OUT, "hdri", aid + ".hdr"), f.get("md5"))
        entry.update(path="res://art/assets/hdri/%s.hdr" % aid)
    return entry, total


def write_texture_imports(dest):
    """VRAM-compressed with mipmaps (they tile on big surfaces); normals flagged as normal maps.
    Godot fills in the rest of each .import on its first import."""
    for name in ("albedo", "normal", "arm"):
        path = os.path.join(dest, name + ".jpg.import")
        if os.path.exists(path) or not os.path.exists(os.path.join(dest, name + ".jpg")):
            continue
        with open(path, "w") as f:
            f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                    "compress/mode=2\ncompress/normal_map=%d\nmipmaps/generate=true\n" % (1 if name == "normal" else 2))


def fetch_url(kind, aid, spec):
    total = 0
    sub = {"models": "models", "textures": "pbr", "hdris": "hdri"}[kind]
    for f in spec["files"]:  # [{"url": ..., "path": "<relative to the asset's folder>", "md5"?: ...}]
        total += save(f["url"], os.path.join(OUT, sub, aid, f["path"]), f.get("md5"))
    entry = {"author": spec["author"], "page": spec["page"], "name": spec.get("name", aid)}
    if kind == "models":
        entry.update(path="res://art/assets/models/%s/%s" % (aid, spec["main"]), size_m=spec.get("size_m", [0, 0, 0]),
                     tris=spec.get("tris", 0))
    elif kind == "textures":
        entry.update(dir="res://art/assets/pbr/" + aid, size_m=spec.get("size_m", [1, 1]))
    else:
        entry.update(path="res://art/assets/hdri/%s/%s" % (aid, spec["main"]))
    return entry, total


RAW_URL = "https://github.com/nathanjmetz/city/releases/download/vehicle-scans-raw/"


def _bpy_python():
    """A Python that can import bpy (Blender as a module): BPY_PATH, or a
    one-time pip install into ~/.cache/bpyenv (about 1 GB)."""
    import subprocess
    path = os.environ.get("BPY_PATH") or os.path.expanduser("~/.cache/bpyenv")
    env = dict(os.environ, PYTHONPATH=path)
    if subprocess.run([sys.executable, "-P", "-c", "import bpy"], env=env, capture_output=True).returncode != 0:
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--target", path, "bpy"], check=True)
    return env


def fetch_scan(kind, aid, spec):
    import subprocess, tempfile, zipfile
    dest = os.path.join(OUT, "models", aid)
    out = os.path.join(dest, aid + ".glb")
    stamp = os.path.join(dest, "bake.json")
    want = json.dumps({k: spec.get(k) for k in ("raw", "raw_url", "length", "flip")}, sort_keys=True)
    if not (os.path.exists(out) and os.path.exists(stamp) and open(stamp).read() == want):
        with tempfile.TemporaryDirectory() as tmp:
            z = os.path.join(tmp, "raw.zip")
            with open(z, "wb") as f:
                f.write(get(spec.get("raw_url") or RAW_URL + spec["raw"]))
            with zipfile.ZipFile(z) as zf:
                zf.extractall(os.path.join(tmp, "x"))
            scene = None
            for r, _, fs in os.walk(os.path.join(tmp, "x")):
                for n in fs:
                    if n.endswith((".gltf", ".glb")) and scene is None:
                        scene = os.path.join(r, n)
            if scene is None:
                raise RuntimeError("no glTF in " + spec["raw"])
            os.makedirs(dest, exist_ok=True)
            cmd = [sys.executable, "-P", os.path.join(ROOT, "tools/vehicles/bake_vehicle.py"), scene, out,
                   str(spec["length"])] + (["flip"] if spec.get("flip") else [])
            subprocess.run(cmd, env=_bpy_python(), check=True, stdout=subprocess.DEVNULL)
        with open(stamp, "w") as f:
            f.write(want)
    entry = {"author": spec["author"], "page": spec["page"], "name": spec.get("name", aid),
             "path": "res://art/assets/models/%s/%s.glb" % (aid, aid), "size_m": spec.get("size_m", [0, 0, 0]),
             "tris": spec.get("tris", 0)}
    return entry, os.path.getsize(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv
    with open(CATALOG) as f:
        catalog = json.load(f)
    index_path = os.path.join(OUT, "index.json")
    index = {k: {} for k in KINDS}
    if os.path.exists(index_path):
        with open(index_path) as f:
            index.update(json.load(f))
    for kind in KINDS:
        for aid, spec in sorted(catalog.get(kind, {}).items()):
            spec["_id"] = aid
            lic = licence_of(spec)
            if check_only or (args and aid not in args):
                continue
            src = spec.get("src", "polyhaven")
            entry, total = {"polyhaven": fetch_polyhaven, "scan": fetch_scan}.get(src, fetch_url)(kind, aid, spec)
            entry.update(licence=lic, source=src, loop=spec.get("loop", ""), use=spec.get("use", ""),
                         real=spec.get("real", ""))
            index[kind][aid] = entry
            print("ok %-9s %-34s %6.1f MB" % (kind, aid, total / 1e6))
    if check_only:
        print("licences ok:", sum(len(catalog.get(k, {})) for k in KINDS), "assets")
        return
    # Drop index rows that left the catalog.
    for kind in KINDS:
        for aid in list(index[kind]):
            if aid not in catalog.get(kind, {}):
                del index[kind][aid]
    os.makedirs(OUT, exist_ok=True)
    with open(index_path, "w") as f:
        json.dump(index, f, indent=1, sort_keys=True)
    write_credits(index)


def write_credits(index):
    lines = ["# Free asset library: credits (desktop app only)", "",
             "Every asset here is free for any use, now and later. Fetched by `tools/assets/fetch.py` from",
             "`tools/assets/catalog.json`, which refuses any licence that isn't CC0 or CC-BY 4.0. The Web export",
             "leaves `art/assets/` out. Licences:", ""]
    for k, v in ALLOWED.items():
        lines.append("- %s: %s" % (k, v))
    titles = {"models": "Models", "textures": "Surfaces (PBR textures)", "hdris": "Skies (HDRIs)"}
    for kind in KINDS:
        if not index[kind]:
            continue
        lines += ["", "## " + titles[kind], ""]
        for aid, e in sorted(index[kind].items()):
            lines.append("- `%s` %s by %s, %s, %s. Used for: %s" % (
                aid, e.get("name", aid), e.get("author", "?"), e.get("licence"), e.get("page"), e.get("use", "")))
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
