"""Builds the real roads, rail and towns of the Grant County map.

Run (needs network): python3 tools/terrain/build_roads.py
Downloads OpenStreetMap-derived roads, rail and town limits from Overture
Maps (an open bucket on AWS) to tools/terrain/out/grant_in/ (git-ignored),
then writes into terrain/grant_in/:

  county.bin    64 x 64 lossless WebP, red = a north-south mile of county
                road, green = an east-west one, at (line, mile) wrapped to 64,
                the way CountyGrid and the ground shader read them. A mile
                has a road where a real road runs along that mile of section
                line. Past the map the old rule (a hash, 95%) fills in.
  county.json   the real names of those miles ("East 100 N").
  highways.json, highways.bin   the state roads, US 35 and I-69, as
                build_highways.py made them for Petersburg: the routes, and
                per channel the signed distance to their centre lines.
  places.json   Marion, Gas City and Jonesboro (the backdrop: real town
                limits, not playable) and the start towns, region metres.
  rail.json     the rail lines, for the rail hub.
  backdrop.bin  what the backdrop towns look like (BackdropView): their real
                building footprints as boxes and their streets, gzipped.

Real reference: Grant County's roads follow the Public Land Survey's
section lines, a road every mile, named by distance from the county's base
lines (East 100 N is a mile north of the east-west base line).
"""
import json, math, os, sys
import numpy as np
from PIL import Image

sys.argv = [sys.argv[0], "grant_in"]
sys.path.insert(0, os.path.dirname(__file__))
import build_region as R  # noqa: E402

OUT = R.OUT
DST = os.path.join(os.path.dirname(__file__), "..", "..", "terrain", R.REGION)
HALF = R.SIZE / 2
SECTION = 1608.0
RELEASE = "overturemaps-us-west-2/release/2026-10-21.0"
# The download box: the map plus a margin, lon/lat.
W, S, E, N = -86.00, 40.30, -85.33, 40.76

# 2020 Census.
BACKDROP = {"Marion": 28321, "Gas City": 6155, "Jonesboro": 1517}
SITES = [  # in the order new towns are offered them: nearest neighbors first
    ("Sweetser", 1074), ("Swayzee", 916), ("Converse", 1156),
    ("Fairmount", 2684), ("Upland", 3820), ("Van Buren", 787)]


def write_backdrop(backdrop, towns_poly):
    """Marion, Gas City and Jonesboro as they stand: every building's
    footprint (its smallest rotated rectangle) and height, and every street,
    from OpenStreetMap and Overture's building heights. Little-endian:
    "BKD1", u32 buildings, then per building 6 int16 (centre x, z metres;
    width, depth, height decimetres; angle centidegrees), u32 streets, then
    per street u8 class (0 lane, 1 street, 2 arterial), u16 points, int16
    x, z metres each. Gzipped."""
    import gzip, struct
    import pyarrow.parquet as pq
    import shapely
    from shapely.geometry import Polygon
    from shapely.prepared import prep
    area = prep(backdrop.buffer(30.0))
    rows = []
    for b in pq.read_table(f"{OUT}/buildings.parquet").to_pylist():
        g = shapely.from_wkb(b["geometry"])
        polys = [g] if g.geom_type == "Polygon" else list(getattr(g, "geoms", []))
        for p in polys:
            if p.geom_type != "Polygon":
                continue
            q = Polygon(xz(p.exterior.coords))
            if q.area < 12.0 or not area.contains(q.centroid):
                continue
            r = q.minimum_rotated_rectangle
            c = np.array(r.exterior.coords)[:4]
            e0, e1 = c[1] - c[0], c[2] - c[1]
            w, d = np.hypot(*e0), np.hypot(*e1)
            ang = math.degrees(math.atan2(e0[1], e0[0]))
            h = b["height"] or ((b["num_floors"] or 0) * 3.2) or (4.5 if q.area < 250 else 7.0)
            h = float(np.clip(h, 2.5, 60.0))
            cx, cz = r.centroid.coords[0]
            rows.append((round(cx), round(cz), round(w * 10), round(d * 10), round(h * 10), round(ang * 100)))
    streets = []
    klass = {"residential": 1, "living_street": 1, "unclassified": 1, "service": 0, "tertiary": 1,
             "secondary": 2, "primary": 2, "trunk": 2, "unknown": 1}
    for sg in pq.read_table(f"{OUT}/segments.parquet").to_pylist():
        if sg["subtype"] != "road" or sg["class"] not in klass:
            continue
        g = shapely.from_wkb(sg["geometry"])
        for ln in lines_of(g):
            from shapely.geometry import LineString
            l2 = LineString(xz(ln.coords))
            if not area.intersects(l2):
                continue
            l2 = l2.intersection(backdrop.buffer(30.0))
            for piece in lines_of(l2):
                piece = piece.simplify(2.0)
                if piece.length < 15.0:
                    continue
                streets.append((klass[sg["class"]], [(round(x), round(z)) for x, z in piece.coords]))
    out = bytearray(b"BKD1") + struct.pack("<I", len(rows))
    for r in rows:
        out += struct.pack("<6h", *r)
    out += struct.pack("<I", len(streets))
    for k, pts in streets:
        out += struct.pack("<BH", k, len(pts))
        for x, z in pts:
            out += struct.pack("<2h", x, z)
    open(f"{DST}/backdrop.bin", "wb").write(gzip.compress(bytes(out), 9))
    print("backdrop: %d buildings, %d streets, %d KB" % (len(rows), len(streets), os.path.getsize(f"{DST}/backdrop.bin") // 1024))


def download():
    import pyarrow.dataset as ds, pyarrow.fs as pfs, pyarrow.compute as pc, pyarrow.parquet as pq
    fs = pfs.S3FileSystem(anonymous=True, region="us-west-2")
    os.makedirs(OUT, exist_ok=True)
    for theme, typ, name, cols in [
            ("transportation", "segment", "segments", ["id", "subtype", "class", "names", "geometry", "routes"]),
            ("divisions", "division_area", "areas", ["id", "subtype", "class", "names", "geometry"]),
            ("buildings", "building", "buildings", ["id", "subtype", "class", "height", "num_floors", "geometry"])]:
        path = f"{OUT}/{name}.parquet"
        if os.path.exists(path):
            continue
        d = ds.dataset(f"{RELEASE}/theme={theme}/type={typ}/", filesystem=fs, format="parquet")
        f = ((pc.field("bbox", "xmin") < E) & (pc.field("bbox", "xmax") > W)
             & (pc.field("bbox", "ymin") < N) & (pc.field("bbox", "ymax") > S))
        pq.write_table(d.to_table(filter=f, columns=cols), path)
        print("downloaded", name)


def xz(coords):
    """lon/lat to region metres (x east, z south; 0 at R.CENTRE back from the middle)."""
    c = np.asarray(coords, dtype=np.float64)
    return np.stack([(c[:, 0] - R.LON0) * R.M_PER_DEG_LON + R.CENTRE[0],
                     -(c[:, 1] - R.LAT0) * R.M_PER_DEG_LAT + R.CENTRE[1]], -1)


def lines_of(geom):
    import shapely
    if geom.geom_type == "LineString":
        return [geom]
    if geom.geom_type == "MultiLineString":
        return list(geom.geoms)
    return [g for g in getattr(geom, "geoms", []) if g.geom_type == "LineString"]


def signed_name(name):
    """How the sign reads: "East 100 N" and "South 200 West" are signed
    "E 100 N" and "S 200 W" in Grant County; other names stay as they are."""
    w = name.split()
    d = {"North": "N", "South": "S", "East": "E", "West": "W"}
    if len(w) == 3 and w[0] in d and w[1].isdigit() and w[2] in list(d) + list(d.values()):
        return f"{d[w[0]]} {w[1]} {d.get(w[2], w[2])}"
    return name


def mix(a, b):
    """CountyGrid.mix: the same 32-bit hash."""
    h = ((a * 73856093) ^ (b * 19349663)) & 0xffffffff
    h ^= h >> 15
    h = (h * 0x2c1b3c6d) & 0xffffffff
    h ^= h >> 12
    h = (h * 0x297a2d39) & 0xffffffff
    h ^= h >> 15
    return h


def main():
    import pyarrow.parquet as pq
    import shapely
    from shapely.geometry import LineString, Polygon, MultiPolygon
    from shapely.ops import unary_union, linemerge
    download()

    # --- Towns ---------------------------------------------------------
    areas = pq.read_table(f"{OUT}/areas.parquet").to_pylist()
    towns = {}
    for a in areas:
        nm = (a["names"] or {}).get("primary")
        if a["subtype"] == "locality" and nm:
            g = shapely.from_wkb(a["geometry"])
            polys = [g] if g.geom_type == "Polygon" else list(getattr(g, "geoms", []))
            towns[nm] = unary_union([Polygon(xz(p.exterior.coords)) for p in polys if p.geom_type == "Polygon"])
    back = []
    for nm, pop in BACKDROP.items():
        g = towns[nm].buffer(0).simplify(25.0)
        parts = [g] if g.geom_type == "Polygon" else sorted(g.geoms, key=lambda p: -p.area)
        back.append({"name": nm, "pop": pop, "centre": [round(v, 1) for v in g.centroid.coords[0]],
                     "outlines": [[[round(x, 1), round(z, 1)] for x, z in p.exterior.coords[:-1]]
                                  for p in parts if p.area > 20000]})
    backdrop = unary_union([towns[nm] for nm in BACKDROP]).buffer(0)
    sites = []
    for nm, pop in SITES:
        c = towns[nm].centroid.coords[0]
        sites.append({"name": nm, "pop": pop, "centre": [round(c[0], 1), round(c[1], 1)]})
    places = {"backdrop": back, "sites": sites}

    # --- Roads -----------------------------------------------------------
    segs = pq.read_table(f"{OUT}/segments.parquet").to_pylist()
    rural = []   # [a, b, name] pieces of road, region metres
    rail = []
    hw = {}      # ref -> [LineString]
    order = {"US:I": 0, "US:US": 1, "US:IN": 2}
    for s in segs:
        g = shapely.from_wkb(s["geometry"])
        if s["subtype"] == "rail":
            for ln in lines_of(g):
                rail.append(xz(ln.coords))
            continue
        refs = sorted(((order[r["network"]], int(r["ref"]) if str(r["ref"]).isdigit() else 999, r["network"], r["ref"])
                       for r in (s["routes"] or []) if r.get("network") in order and r.get("ref")), key=lambda t: t[:2])
        if refs and s["class"] not in ("motorway_link", "trunk_link", "primary_link", "secondary_link"):
            key = (refs[0][2], refs[0][3])
            for ln in lines_of(g):
                hw.setdefault(key, []).append(LineString(xz(ln.coords)))
        if s["class"] in ("unclassified", "tertiary", "secondary", "primary", "residential", "unknown", "trunk"):
            name = (s["names"] or {}).get("primary") or ""
            for ln in lines_of(g):
                p = xz(ln.coords)
                for i in range(len(p) - 1):
                    rural.append((p[i], p[i + 1], name))

    # Miles of section line with a real road along them, leaving out the
    # ones a state road already runs down (it is painted as itself).
    hw_lines = unary_union([ln for ls in hw.values() for ln in ls])
    def on_highway(p0, axis):
        pts = [shapely.Point(*(p0 + axis * SECTION * f)) for f in (0.1, 0.3, 0.5, 0.7, 0.9)]
        return sum(1 for q in pts if hw_lines.distance(q) < TOL) >= 3
    A = np.array([r[0] for r in rural]); B = np.array([r[1] for r in rural])
    D = B - A; L = np.hypot(D[:, 0], D[:, 1]); keep = L > 1.0
    A, B, D, L = A[keep], B[keep], D[keep], L[keep]
    names = [r[2] for r, k in zip(rural, keep) if k]
    U = D / L[:, None]
    TOL = 200.0      # metres off the line a real road may run and still count
    COVER = 0.5      # share of the mile that must have one
    STEP = 50.0
    county = np.zeros((64, 64, 2), np.uint8)
    county_names = {}
    lines = range(-26, 38)  # 64 lines, the map's ~23 and the mirrored land past it
    inside = lambda v, k: -HALF + 400 < v - R.CENTRE[k] < HALF - 400
    fit = []
    for fam, ch in (("ns", 0), ("ew", 1)):
        axis = np.array([0.0, 1.0]) if fam == "ns" else np.array([1.0, 0.0])
        par = np.abs(U @ axis) > 0.94
        for line in lines:
            for seg in range(-26, 38):
                if fam == "ns":
                    p0 = np.array([line * SECTION, seg * SECTION])
                else:
                    p0 = np.array([seg * SECTION, line * SECTION])
                mid = p0 + axis * SECTION / 2
                ix, iy = line % 64, seg % 64
                if not (inside(mid[0], 0) and inside(mid[1], 1)):
                    key = line if fam == "ns" else line + (1 << 20)
                    has = (mix(key, seg) & 0xffff) / 65536.0 < 0.95
                    county[iy, ix, ch] = 255 if has else 0
                    continue
                if backdrop.distance(shapely.Point(*mid)) < SECTION * 0.3:
                    continue
                if on_highway(p0, axis):
                    continue
                ts = np.arange(STEP / 2, SECTION, STEP)
                pts = p0[None, :] + ts[:, None] * axis[None, :]
                lo = np.minimum(A, B) - TOL; hi = np.maximum(A, B) + TOL
                box = par & (hi[:, 0] > pts[:, 0].min()) & (lo[:, 0] < pts[:, 0].max()) \
                    & (hi[:, 1] > pts[:, 1].min()) & (lo[:, 1] < pts[:, 1].max())
                idx = np.nonzero(box)[0]
                if idx.size == 0:
                    continue
                a, u, l = A[idx], U[idx], L[idx]
                rel = pts[:, None, :] - a[None, :, :]
                t = np.clip((rel * u[None]).sum(-1), 0, l[None])
                q = a[None] + t[..., None] * u[None]
                d = np.hypot(*(pts[:, None, :] - q).transpose(2, 0, 1))
                best = d.argmin(1)
                ok = d[np.arange(len(pts)), best] < TOL
                if ok.mean() >= COVER:
                    county[iy, ix, ch] = 255
                    off = (q[np.arange(len(pts)), best] - pts)[ok]
                    fit.append(np.abs(off @ np.array([1.0, 0.0] if fam == "ns" else [0.0, 1.0])).mean())
                    votes = {}
                    for j in best[ok]:
                        nm = names[idx[j]]
                        if nm:
                            votes[nm] = votes.get(nm, 0) + 1
                    if votes:
                        county_names[f"{fam}:{line}:{seg}"] = signed_name(max(votes, key=votes.get))
    print("county miles on the map: %d; mean offset of the real road from the line %.0f m"
          % (len(fit), np.mean(fit)))

    # State roads, US 35 and I-69: one polyline per stretch, outside the backdrop.
    routes = []
    for (net, ref), ls in sorted(hw.items(), key=lambda kv: (order[kv[0][0]], int(kv[0][1]) if kv[0][1].isdigit() else 0)):
        merged = linemerge(unary_union(ls))
        merged = merged.difference(backdrop.buffer(60.0)).intersection(
            Polygon([(R.CENTRE[0] + x * HALF, R.CENTRE[1] + z * HALF) for x, z in ((-1, -1), (1, -1), (1, 1), (-1, 1))]))
        for ln in lines_of(merged):
            for piece in lines_of(linemerge(ln)) if ln.geom_type != "LineString" else [ln]:
                piece = piece.simplify(4.0)
                if piece.length < 400.0:
                    continue
                if net == "US:I":
                    name, short = f"Interstate {ref}", f"I-{ref}"
                elif net == "US:US":
                    name, short = f"U.S. Route {ref}", f"US {ref}"
                else:
                    name, short = f"State Road {ref}", f"SR {ref}"
                pts = np.array(piece.coords)
                routes.append({"name": name, "short": short, "limited": net == "US:I", "line": pts})
    # Channels: routes in one channel must stay apart (signed fields would
    # cancel between them), so colour the routes that come near each other.
    RANGE = 127.0
    n = len(routes)
    geo = [LineString(r["line"]) for r in routes]
    near = [[j for j in range(n) if j != i and geo[i].distance(geo[j]) < 2 * RANGE + 40] for i in range(n)]
    chan = [-1] * n
    for i in sorted(range(n), key=lambda i: -len(near[i])):
        used = [sum(1 for j in near[i] if chan[j] == c) for c in range(3)]
        chan[i] = int(np.argmin(used))
    clash = sum(1 for i in range(n) for j in near[i] if chan[i] == chan[j]) // 2
    print("routes", n, "channel clashes", clash)
    NF = 1024
    c = (np.arange(NF) + 0.5) * (R.SIZE / NF) - HALF
    X, Z = np.meshgrid(c + R.CENTRE[0], c + R.CENTRE[1])
    cx, cz = c + R.CENTRE[0], c + R.CENTRE[1]
    field = np.full((NF, NF, 3), RANGE)
    best = np.full((NF, NF, 3), np.inf)
    for r, ch in zip(routes, chan):
        line = r["line"]
        for i in range(len(line) - 1):
            a, b = line[i], line[i + 1]
            lo = np.minimum(a, b) - RANGE - 64
            hi = np.maximum(a, b) + RANGE + 64
            i0, i1 = np.searchsorted(cx, [lo[0], hi[0]])
            j0, j1 = np.searchsorted(cz, [lo[1], hi[1]])
            if i1 <= i0 or j1 <= j0:
                continue
            px, pz = X[j0:j1, i0:i1], Z[j0:j1, i0:i1]
            d = b - a
            L2 = d @ d
            if L2 < 1e-6:
                continue
            t = np.clip(((px - a[0]) * d[0] + (pz - a[1]) * d[1]) / L2, 0, 1)
            qx, qz = a[0] + t * d[0] - px, a[1] + t * d[1] - pz
            dist = np.sqrt(qx * qx + qz * qz)
            side = np.sign(d[0] * (pz - a[1]) - d[1] * (px - a[0]))
            end = ((t <= 0) & (i == 0)) | ((t >= 1) & (i == len(line) - 2))
            signed = np.where(end, dist, dist * np.where(side == 0, 1, side))
            win = best[j0:j1, i0:i1, ch]
            take = dist < win
            win[take] = dist[take]
            f = field[j0:j1, i0:i1, ch]
            f[take] = signed[take]

    os.makedirs(DST, exist_ok=True)
    Image.fromarray(np.dstack([county, np.zeros((64, 64, 1), np.uint8)]), "RGB").save(
        f"{DST}/county.bin", "WEBP", lossless=True)
    json.dump({"names": county_names}, open(f"{DST}/county.json", "w"), separators=(",", ":"))
    Image.fromarray(np.clip(np.round(field + 128.0), 1, 255).astype(np.uint8), "RGB").save(
        f"{DST}/highways.bin", "WEBP", lossless=True)
    json.dump({"range": RANGE, "routes": [{"name": r["name"], "short": r["short"], "limited": r["limited"],
               "pts": [[round(x, 1), round(z, 1)] for x, z in r["line"]]} for r in routes]},
              open(f"{DST}/highways.json", "w"), separators=(",", ":"))
    json.dump(places, open(f"{DST}/places.json", "w"), separators=(",", ":"))
    rails = []
    for p in rail:
        if np.all(np.abs(p - np.array(R.CENTRE)) > HALF + 2000):
            continue
        ln = LineString(p).simplify(5.0)
        if ln.length > 200:
            rails.append([[round(x, 1), round(z, 1)] for x, z in ln.coords])
    json.dump({"lines": rails}, open(f"{DST}/rail.json", "w"), separators=(",", ":"))
    print("routes:", sorted({r["short"] for r in routes}), "rail lines", len(rails))
    write_backdrop(backdrop, towns)
    print("sites:", [(s["name"], s["centre"]) for s in sites])


if __name__ == "__main__":
    main()
