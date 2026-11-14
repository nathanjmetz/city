#!/usr/bin/env python3
"""Keeps the desktop release's art packs in step with tools/assets/catalog.json (CI only).

Each asset in the free library ships as its own pack per platform, named
a-<platform>-<id>-<key>.pck on the "desktop" release, where key changes only when
the asset's catalog entry, the engine or the pack format changes. So a CI run
builds and uploads only new or changed assets, and an app downloads only those
(GameUpdater). assets.json on the release lists every pack with its sha256.

  release.py plan OLD_ASSETS_JSON RELEASE_NAMES_JSON
      prints the ids whose packs must be built (space-separated, maybe empty)
  release.py finish OLD_ASSETS_JSON RELEASE_NAMES_JSON PACK_DIR OUT_DIR
      moves the packs built into PACK_DIR/<platform>/<id>.pck to OUT_DIR/art/<name>,
      writes OUT_DIR/assets.json ({"macos": [...], "windows": [...]}, each
      {"id", "name", "url", "sha256", "size"}) and OUT_DIR/stale.txt (release
      packs no longer listed, to delete once latest.json points past them)
"""
import hashlib, json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLATFORMS = ("macos", "windows")
PACK_FORMAT = "1"  # bump when tools/assets/pack.gd changes what goes in a pack
URL = "https://github.com/%s/releases/download/desktop/" % os.environ.get("GITHUB_REPOSITORY", "nathanjmetz/city")


def wanted():
    """{(platform, id): name} for every asset in the catalog."""
    with open(os.path.join(ROOT, "tools/assets/catalog.json")) as f:
        cat = json.load(f)
    engine = os.environ.get("GODOT_VERSION", "")
    out = {}
    for kind in ("models", "textures", "hdris"):
        for aid, spec in cat.get(kind, {}).items():
            key = hashlib.sha256((json.dumps(spec, sort_keys=True) + engine + PACK_FORMAT).encode()).hexdigest()[:10]
            for p in PLATFORMS:
                out[(p, aid)] = "a-%s-%s-%s.pck" % (p, aid, key)
    return out


def _load(path, empty):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return empty


def _known(old, names):
    """Packs already on the release with a known sha256: {name: entry}."""
    have = set(names)
    out = {}
    for p in PLATFORMS:
        for e in old.get(p, []):
            if e.get("name") in have and e.get("sha256"):
                out[e["name"]] = e
    return out


def plan(old_path, names_path):
    known = _known(_load(old_path, {}), _load(names_path, []))
    need = sorted({aid for (p, aid), name in wanted().items() if name not in known})
    print(" ".join(need))


def finish(old_path, names_path, pack_dir, out_dir):
    names = _load(names_path, [])
    known = _known(_load(old_path, {}), names)
    os.makedirs(os.path.join(out_dir, "art"), exist_ok=True)
    manifest = {p: [] for p in PLATFORMS}
    for (p, aid), name in sorted(wanted().items()):
        if name in known:
            e = dict(known[name])
        else:
            src = os.path.join(pack_dir, p, aid + ".pck")
            if not os.path.exists(src):
                print("missing pack, leaving it out:", p, aid)
                continue
            dst = os.path.join(out_dir, "art", name)
            shutil.move(src, dst)
            with open(dst, "rb") as f:
                data = f.read()
            e = {"name": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
        e.update(id=aid, name=name, url=URL + name)
        manifest[p].append(e)
    with open(os.path.join(out_dir, "assets.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    keep = {e["name"] for p in PLATFORMS for e in manifest[p]}
    with open(os.path.join(out_dir, "stale.txt"), "w") as f:
        f.write("\n".join(n for n in names if n.startswith("a-") and n.endswith(".pck") and n not in keep))
    print("art packs: %d listed, %d new" % (len(keep), len(os.listdir(os.path.join(out_dir, "art")))))


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "plan":
        plan(*sys.argv[2:4])
    else:
        finish(*sys.argv[2:6])
