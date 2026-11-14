# Free asset library

Real photo-scanned props, tiling photo surfaces and skies for the desktop app. Every asset is
**CC0 or CC-BY 4.0**: free for any use, forever, and allowed to sit in this public repo.
`fetch.py` refuses anything else.

## Why not Megascans

Quixel Megascans now live on Fab. They are free to download with an Epic account and may be used in
any engine, but under the **Fab Standard License**, which forbids redistributing the files "on a
standalone basis". This repo and the web preview are public, so committing or fetching Megascans here
would break that licence. Downloading also needs Brawn's Epic sign-in. So Megascans are not used.
Poly Haven covers most of the same ground (scans by the same kind of photogrammetry) as CC0.

Sources checked (2026-11-14): Poly Haven (CC0, reachable here, used). ambientCG (CC0; its API works but
its download host is blocked from the cloud sessions). Kenney (CC0, low-poly cartoon style: doesn't fit
the realistic art). Sketchfab CC0/CC-BY, Smithsonian 3D (CC0), OpenGameArt: blocked from the cloud
sessions. To use them, the environment's network allowlist needs their hosts.

## Use it in the game

```gdscript
var m := AssetLib.mesh("fire_hydrant", ["fire_hydrant*"], ["*aged"])  # one shared Mesh, with LODs
if m == null:
    m = _code_built_hydrant()            # ALWAYS keep the fallback: browser and fresh installs don't have it
var wall := AssetLib.material("red_brick")              # life-size tiling ORM material, UVs in metres
var barn := AssetLib.material("wood_peeling_paint_weathered", Color(0.75, 0.2, 0.15))  # tinted
var node := AssetLib.instance("wooden_picnic_table")    # a full scene copy
AssetLib.ids("models", "roads")                          # what a loop owns and has on this machine
```

### Props on a lot (builders)

Builders draw a building into one merged mesh, so a scan doesn't go in it. Note where it stands with
`PropLog.place(self, id, xf, parts, skip)` (xf in the builder's lot frame: x across, y up, -z to the
street). It returns true only while BuildingView (or the art gallery) collects and the scan is on
this machine; then BuildingView shows it through `PropField` (one MultiMesh per prop and 256 m
square, fading out past 420 m). On false, draw the code-built version, and keep that fallback off the
builder's `rng` so the building comes out the same either way (tests/test_prop_log.gd). Not for
house plans that HouseBuilder caches and re-places: those need the plan to carry them.

    if not PropLog.place(self, "standing_chalkboard_01", Transform3D(Basis().scaled(Vector3.ONE * 0.72), Vector3(x, 0, z))):
        _code_built_sandwich_board(x, z)

Many scans are kits or come clean and worn side by side: the catalog's `parts` note says which node
names to pick. Scans are heavy (often 10k-90k triangles): use them close up and in MultiMeshes, let
their LODs work, and keep code-built far versions.

## Fetch, look, add

```sh
python3 tools/assets/fetch.py                 # everything (~500 MB, a few minutes), or: fetch.py fire_hydrant red_brick
godot --headless --import
xvfb-run godot --rendering-driver opengl3 --resolution 800x600 -s tools/asset_shot.gd -- /tmp/tiles models roads
python3 tools/assets/sheet.py /tmp/tiles sheet.png 6
python3 tools/assets/search.py models bench --max-tris=60000   # find more on Poly Haven
```

To add one: put it in `catalog.json` with `loop`, `use` and `real` (the real Midwestern thing it
matches: the real-world rule), check it in the line-up beside the 1.75 m post, fetch, run
`tests/test_asset_lib.gd`, and commit `catalog.json`, `art/assets/index.json` and `CREDITS.md` (the
files themselves stay out of git). Rejected candidates and why are under `_rejected`.

## How it ships

The game's own pack leaves the art out so its updates stay small. On every push to main the Desktop
apps workflow packs only new or changed assets, one small pack per asset and platform
(`pack.gd`, `release.py`), and lists them in latest.json; the app downloads them in the background
and mounts them next launch (GameUpdater). Until then AssetLib returns null and the code-built
versions show.
