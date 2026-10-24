"""Builds the state highways across the region map (SR 57, SR 61, SR 56).

Run: python3 tools/terrain/build_highways.py
Writes terrain/white_river_in/highways.json (the routes, region metres) and
highways.bin (lossless WebP): per route channel, the signed distance to its
centre line, which the ground shader paints and the game samples.

The routes follow INDOT's state highways around Petersburg, Pike County,
traced from waypoints at the towns and river crossings they pass (Oakland
City, Petersburg, the White River bridge, Monroe City, Washington, Winslow,
Otwell). They are close to the real roads, not surveyed. I-69 is left out:
it's a regional project the towns build together.
"""
import json, math, os
import numpy as np
from PIL import Image

LON0, LAT0 = -87.2844, 38.5038
SIZE = 32768.0
N = 1024                    # samples across: 32 m each
RANGE = 127.0               # metres of signed distance kept either side
M_PER_DEG_LAT = 111_132.954 - 559.822 * math.cos(2 * math.radians(LAT0))
M_PER_DEG_LON = 111_412.84 * math.cos(math.radians(LAT0))
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "terrain", "white_river_in")

# Waypoints as (lat, lon) at towns, or "px" points on the 2048-sample land
# cover map (16 m each) where its built-up channel shows the road itself.
# Channel 0..2: routes that share a channel never come near each other.
ROUTES = [
    # Oakland City, north through Petersburg, then north-east past the power
    # plant, over the White River, to Washington.
    {"name": "State Road 57", "short": "SR 57", "channel": 0, "pts": [
        (38.300, -87.358), (38.338, -87.345), (38.380, -87.328), (38.420, -87.310), (38.455, -87.292),
        ("px", 1056, 1100), ("px", 1080, 1060), ("px", 1130, 1010), ("px", 1190, 965),
        ("px", 1235, 925), ("px", 1280, 882), ("px", 1360, 822), ("px", 1392, 740), ("px", 1389, 668),
        ("px", 1440, 530), ("px", 1484, 403), ("px", 1569, 201), ("px", 1622, 106), (38.6595, -87.1725),
        (38.700, -87.150)]},
    # North from Petersburg over the White River, then north-west through
    # Monroe City toward Vincennes.
    {"name": "State Road 61", "short": "SR 61", "from_main": True, "channel": 1, "pts": [
        ("px", 1052, 1104), ("px", 1010, 1072), ("px", 990, 1000), ("px", 988, 960), ("px", 985, 832),
        ("px", 965, 720), ("px", 940, 662), ("px", 850, 552), ("px", 760, 442), (38.6145, -87.3540),
        (38.640, -87.375), (38.690, -87.410)]},
    # South-east from Petersburg to Winslow and on toward Lynnville.
    {"name": "State Road 61", "short": "SR 61", "from_main": True, "channel": 1, "pts": [
        ("px", 1052, 1100), ("px", 1070, 1130), ("px", 1090, 1180), ("px", 1130, 1280), ("px", 1170, 1360),
        ("px", 1205, 1440), ("px", 1290, 1640), ("px", 1360, 1820), (38.340, -87.190),
        (38.300, -87.175)]},
    # East from Petersburg to Otwell and on toward Jasper.
    {"name": "State Road 56", "short": "SR 56", "from_main": True, "channel": 2, "pts": [
        ("px", 1050, 1098), ("px", 1080, 1105), ("px", 1160, 1118), ("px", 1260, 1132), ("px", 1400, 1150),
        ("px", 1560, 1190), ("px", 1700, 1250), ("px", 1850, 1300), (38.4545, -87.0925), (38.450, -87.040)]},
]


def nearest(line, p):
    """The point on a polyline nearest p."""
    best, out = np.inf, line[0]
    for a, b in zip(line[:-1], line[1:]):
        d = b - a
        t = np.clip((p - a) @ d / max(d @ d, 1e-9), 0, 1)
        q = a + t * d
        if np.linalg.norm(q - p) < best:
            best, out = np.linalg.norm(q - p), q
    return out


def point(q):
    if q[0] == "px":
        return ((q[1] + 0.5) * 16.0 - SIZE / 2, (q[2] + 0.5) * 16.0 - SIZE / 2)
    return to_xz(*q)


def to_xz(lat, lon):
    return ((lon - LON0) * M_PER_DEG_LON, -(lat - LAT0) * M_PER_DEG_LAT)


def smooth(pts, step=20.0):
    """Catmull-Rom through the waypoints, every `step` metres or so."""
    p = [np.array(q) for q in pts]
    p = [p[0] * 2 - p[1]] + p + [p[-1] * 2 - p[-2]]
    out = []
    for i in range(1, len(p) - 2):
        a, b, c, d = p[i - 1], p[i], p[i + 1], p[i + 2]
        n = max(2, int(np.linalg.norm(c - b) / step))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                              + (-a + 3 * b - 3 * c + d) * t * t * t))
    out.append(p[-2])
    return np.array(out)


def main():
    c = (np.arange(N) + 0.5) * (SIZE / N) - SIZE / 2
    X, Z = np.meshgrid(c, c)
    field = np.full((N, N, 3), RANGE, dtype=np.float64)
    best = np.full((N, N, 3), np.inf)
    routes = []
    main_line = None
    for r in ROUTES:
        way = [point(q) for q in r["pts"]]
        if main_line is not None and r.get("from_main"):
            # It starts on SR 57 itself, as SR 61 and SR 56 leave it in
            # Petersburg: one road, not a spur ending beside it.
            way[0] = tuple(nearest(main_line, np.array(way[0])))
        line = smooth(way)
        if main_line is None:
            main_line = line
        routes.append({"name": r["name"], "short": r["short"], "pts": [[round(x, 1), round(z, 1)] for x, z in line]})
        ch = r["channel"]
        for i in range(len(line) - 1):
            a, b = line[i], line[i + 1]
            lo = np.minimum(a, b) - RANGE - 64
            hi = np.maximum(a, b) + RANGE + 64
            i0, i1 = np.searchsorted(c, [lo[0], hi[0]])
            j0, j1 = np.searchsorted(c, [lo[1], hi[1]])
            if i1 <= i0 or j1 <= j0:
                continue
            px, pz = X[j0:j1, i0:i1], Z[j0:j1, i0:i1]
            d = b - a
            L2 = d @ d
            t = np.clip(((px - a[0]) * d[0] + (pz - a[1]) * d[1]) / L2, 0, 1)
            qx, qz = a[0] + t * d[0] - px, a[1] + t * d[1] - pz
            dist = np.sqrt(qx * qx + qz * qz)
            # Signed by side, so it blends straight across the line; past
            # the ends it stays positive (no road), so nothing runs on.
            side = np.sign(d[0] * (pz - a[1]) - d[1] * (px - a[0]))
            end = ((t <= 0) & (i == 0)) | ((t >= 1) & (i == len(line) - 2))
            signed = np.where(end, dist, dist * np.where(side == 0, 1, side))
            win = best[j0:j1, i0:i1, ch]
            take = dist < win
            win[take] = dist[take]
            f = field[j0:j1, i0:i1, ch]
            f[take] = signed[take]
    img = np.clip(np.round(field + 128.0), 1, 255).astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(img, "RGB").save(os.path.join(OUT, "highways.bin"), "WEBP", lossless=True)
    with open(os.path.join(OUT, "highways.json"), "w") as f:
        json.dump({"range": RANGE, "routes": routes}, f, separators=(",", ":"))
    print("routes", [(r["short"], len(r["pts"])) for r in routes])


if __name__ == "__main__":
    main()
