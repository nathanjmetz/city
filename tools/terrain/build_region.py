"""Builds the game's real-world terrain from free public data.

Run once (needs network): python3 tools/terrain/build_region.py [region]
Downloads to tools/terrain/out/<region>/ (git-ignored), then writes the
game's layers to terrain/<region>/. Add `derive` to redo only the second step
from the cached downloads. The region is "grant_in" (the game's map) unless
named; "white_river_in" is the old Petersburg map, kept so it can be rebuilt.


Sources (see terrain/LICENSES.md):
  - Elevation: USGS 3D Elevation Program (3DEP) 1/3 arc-second DEM (~10 m),
    public domain, from the USGS National Map bucket on AWS.
  - Land cover: ESA WorldCover 10 m 2021 v200, CC BY 4.0.

The map is a square of SIZE metres on a local flat projection centred on
(LON0, LAT0): x runs east, z runs south (north is -z), 1 unit = 1 metre.
"""
import os
os.environ["CURL_CA_BUNDLE"] = os.environ.get("CURL_CA_BUNDLE", "/root/.ccr/ca-bundle.crt")
os.environ["GDAL_CURL_CA_BUNDLE"] = os.environ["CURL_CA_BUNDLE"]
if os.environ.get("HTTPS_PROXY"):
    os.environ["GDAL_HTTP_PROXY"] = os.environ["HTTPS_PROXY"]
os.environ["GDAL_DISABLE_READDIR_ON_OPEN"] = "EMPTY_DIR"
import json, math, sys
import numpy as np
from PIL import Image
import rasterio
from rasterio.windows import from_bounds
from scipy import ndimage

REGIONS = {
    # Grant County, Indiana, around Marion: Converse to Upland, La Fontaine
    # to Fairmount. The centre is moved onto a crossing of the county's
    # section-line roads, so the game's mile grid (CountyGrid) lies over the
    # real one; build_roads.py prints how well it fits.
    # Region (0, 0), where the first town starts, is Sweetser's crossroads,
    # five miles west and three north of the centre: `centre` is where the
    # map's middle lies in region metres.
    "grant_in": {"name": "Grant County, Indiana", "lon0": -85.67319, "lat0": 40.52273, "cell": 18.0,
                 "centre": [8040.0, 4824.0]},
    "white_river_in": {"name": "White River valley, near Petersburg, Indiana", "lon0": -87.2844, "lat0": 38.5038,
                       "cell": 16.0, "centre": [0.0, 0.0]},
}
REGION = next((a for a in sys.argv[1:] if a in REGIONS), "grant_in")
NAME = REGIONS[REGION]["name"]
LON0, LAT0 = REGIONS[REGION]["lon0"], REGIONS[REGION]["lat0"]
N = 2048          # samples across
CELL = REGIONS[REGION]["cell"]  # metres per sample
CENTRE = REGIONS[REGION]["centre"]
SIZE = N * CELL   # 36 864 m (Grant County), 32 768 m (Petersburg)
OUT = os.path.join(os.path.dirname(__file__), "out", REGION)

M_PER_DEG_LAT = 111_132.954 - 559.822 * math.cos(2 * math.radians(LAT0))
M_PER_DEG_LON = 111_412.84 * math.cos(math.radians(LAT0))


def grid_lonlat(n=N, cell=CELL):
    c = (np.arange(n) + 0.5) * cell - SIZE / 2
    x, z = np.meshgrid(c, c)
    return LON0 + x / M_PER_DEG_LON, LAT0 - z / M_PER_DEG_LAT


def bounds(pad=0.01):
    lon, lat = grid_lonlat(2, SIZE)
    return lon.min() - pad - 0.25, lat.min() - pad - 0.25, lon.max() + pad + 0.25, lat.max() + pad + 0.25


def sample(path, lon, lat, order=1, band=1):
    """Reads a window of a (cloud) raster and samples it at lon/lat."""
    with rasterio.open(path) as ds:
        x0, y0, x1, y1 = lon.min() - 0.005, lat.min() - 0.005, lon.max() + 0.005, lat.max() + 0.005
        w = from_bounds(x0, y0, x1, y1, ds.transform).round_offsets().round_lengths()
        a = ds.read(band, window=w)
        t = ds.window_transform(w)
    col = (lon - t.c) / t.a - 0.5
    row = (lat - t.f) / t.e - 0.5
    return a, row, col


def main():
    os.makedirs(OUT, exist_ok=True)
    lon, lat = grid_lonlat()
    tile = f"n{math.ceil(lat.max()):02d}w{-math.floor(lon.min()):03d}"
    assert tile == f"n{math.ceil(lat.min()):02d}w{-math.floor(lon.max()):03d}", "map spans two DEM tiles"
    dem_url = f"/vsicurl/https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/{tile}/USGS_13_{tile}.tif"
    print("elevation", dem_url)
    a, row, col = sample(dem_url, lon, lat)
    a = a.astype(np.float32)
    height = ndimage.map_coordinates(a, [row, col], order=1, mode="nearest").astype(np.float32)

    # Land cover, area-averaged to one sample: each sample counts 4x4 sub-points.
    wc_lat = math.floor(lat.min() / 3) * 3
    wc_lon = math.floor(lon.min() / 3) * 3
    wc_url = (f"/vsicurl/https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/"
              f"ESA_WorldCover_10m_2021_v200_N{wc_lat:02d}W{-wc_lon:03d}_Map.tif")
    print("land cover", wc_url)
    sub = 4
    flon, flat = grid_lonlat(N * sub, CELL / sub)
    cls, row, col = sample(wc_url, flon, flat)
    c = cls[np.clip(np.rint(row).astype(int), 0, cls.shape[0] - 1), np.clip(np.rint(col).astype(int), 0, cls.shape[1] - 1)]
    def frac(*codes):
        m = np.isin(c, codes).astype(np.float32)
        return m.reshape(N, sub, N, sub).mean(axis=(1, 3))
    tree = frac(10, 20)       # tree cover, shrubland
    water = frac(80)          # permanent water
    wet = frac(90)            # herbaceous wetland
    crop = frac(40)
    built = frac(50)
    bare = frac(60)           # bare ground: strip mines (Pike County), gravel pits
    grass = frac(30)

    np.save(f"{OUT}/height.npy", height)
    np.savez_compressed(f"{OUT}/cover.npz", tree=tree, water=water, wet=wet, crop=crop, built=built, bare=bare, grass=grass)
    print("height", height.min(), height.max(), "water", water.mean(), "tree", tree.mean(), "crop", crop.mean(), "bare", bare.mean())




# ---------------------------------------------------------------------------
# Derived layers: what the game reads. Everything below is computed only from
# the two downloaded layers above, so it is reproducible.

def smooth01(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def value_noise(n, cell_px, seed):
    """Smooth random field, 0..1, features about cell_px samples across."""
    rng = np.random.default_rng(seed)
    g = rng.random((n // cell_px + 3, n // cell_px + 3)).astype(np.float32)
    return np.clip(ndimage.zoom(g, cell_px, order=3)[:n, :n], 0, 1)


def _pike_underground(h, water, is_water, big, upland, floodplain, slope, c):
    # Ore: coal. Pike County sits on the Illinois Basin's Pennsylvanian coal
    # beds, mined from the surface across its uplands; the river valleys are
    # filled with sand and silt over it. So coal lies under the uplands, and is
    # surest where the land already shows strip mining: bare spoil and the
    # many small pit lakes up in the hills.
    pits = ndimage.gaussian_filter((is_water & ~big).astype(np.float32) * upland, 8)
    mines = ndimage.gaussian_filter(c["bare"], 6)
    ore = upland * (0.2 + 0.8 * value_noise(N, 60, 11)) * 0.85 + 14 * pits + 8 * mines
    ore = smooth01(0.48, 0.8, ore) * (1 - smooth01(0.3, 0.6, water))

    # Oil: the Illinois Basin deepens to the south-west across Pike County, and
    # its oil pools sit in small, scattered structures. Pools here are placed
    # in clusters that grow more common toward the south-west. (Approximate:
    # replace with Indiana Geological and Water Survey well records when that
    # host is reachable.)
    yy, xx = np.mgrid[0:N, 0:N] / N
    basin = 0.35 + 0.65 * smooth01(0.0, 1.0, (yy + (1 - xx)) * 0.7)
    pools = value_noise(N, 45, 23) * 0.7 + value_noise(N, 15, 29) * 0.3
    oil = smooth01(0.6, 0.75, pools * (0.45 + 0.5 * basin)) * (1 - smooth01(0.3, 0.6, water))
    return ore, oil


def _grant_underground(h, water, is_water, big, upland, floodplain, slope, c):
    # Ore: sand, gravel and stone. Grant County has no coal; what is dug here
    # is glacial outwash sand and gravel in the river valleys (the pits and
    # pit ponds along the Mississinewa below Marion and Gas City) and the
    # Silurian limestone under thin till on the valley sides. So ore lies
    # along the valleys, richest where the land already shows pits: bare
    # ground and small ponds in the bottoms.
    near = ndimage.gaussian_filter(big.astype(np.float32), 40) * 8
    pits = ndimage.gaussian_filter((is_water & ~big).astype(np.float32) * (1 - upland), 6)
    dug = ndimage.gaussian_filter(c["bare"], 5)
    # Smaller valley-train outwash lies along the creeks cut into the till
    # plain (Walnut, Back, Pipe and Deer creeks), dug in pockets by small
    # county pits.
    creek = smooth01(1.0, 4.0, ndimage.gaussian_filter(h, 40) - h)
    pockets = smooth01(0.45, 0.7, value_noise(N, 30, 13))
    ore = np.clip(near, 0, 1) * (0.25 + 0.75 * value_noise(N, 50, 11)) * 0.8 + 12 * pits + 8 * dug \
        + 0.9 * creek * pockets
    ore = smooth01(0.5, 0.8, ore) * (1 - smooth01(0.3, 0.6, water))

    # Oil: the Trenton field. Grant County sits on the Ordovician Trenton
    # limestone, the gas and oil field of Indiana's 1887-1900s gas boom (Gas
    # City is named for it); the gas lay under almost the whole county, with
    # oil pools to the east toward Blackford and Wells counties. Pools here
    # are spread county-wide, a little more common to the east. (Approximate:
    # Indiana Geological and Water Survey well records would make it exact.)
    yy, xx = np.mgrid[0:N, 0:N] / N
    field = 0.55 + 0.45 * smooth01(0.0, 1.0, xx)
    pools = value_noise(N, 45, 23) * 0.7 + value_noise(N, 15, 29) * 0.3
    oil = smooth01(0.6, 0.75, pools * (0.45 + 0.5 * field)) * (1 - smooth01(0.3, 0.6, water))
    return ore, oil


def derive():
    h = np.load(f"{OUT}/height.npy")
    c = dict(np.load(f"{OUT}/cover.npz"))
    water = ndimage.gaussian_filter(c["water"], 0.6)
    water = np.where(c["water"] > 0.5, np.maximum(water, c["water"]), water)
    is_water = water > 0.5

    # Water surface: the DEM is hydro-flattened, so over water it already is the
    # water level. Carry the nearest water level a little past the shore so the
    # water surface is defined where it meets the bank.
    idx = ndimage.distance_transform_edt(~is_water, return_distances=False, return_indices=True)
    wlevel = h[idx[0], idx[1]]
    wlevel = ndimage.gaussian_filter(wlevel, 1.0)
    # Riverbeds: deeper toward the middle of wide water, a few metres at most.
    inside = ndimage.distance_transform_edt(is_water) * CELL
    depth = np.minimum(1.2 + inside * 0.06, 4.0) * smooth01(0.25, 0.75, water)
    ground = np.where(water > 0.02, np.minimum(h, wlevel - depth), h).astype(np.float32)
    ground = np.where(water > 0.02, ndimage.gaussian_filter(ground, 0.7), ground)
    # Keep dry land dry: banks never sink below the water next to them.
    ground = np.where(water < 0.25, np.maximum(ground, wlevel + 0.15 - 2.0 * smooth01(0.0, 0.25, water)), ground)
    ground = np.where(water < 0.02, h, ground).astype(np.float32)

    # Base level for roads and buildings: gently smoothed ground (cut and
    # fill), lifted over water into bridge decks with 7 m (23 ft) of clearance
    # and ramps no steeper than about 6%.
    base = ndimage.gaussian_filter(h, 1.5)
    deck = np.where(water > 0.35, wlevel + 7.0, -1e9)
    reach = 7  # cells: ~110 m of ramp at 6%
    for _ in range(reach):
        deck = np.maximum(deck, ndimage.grey_dilation(deck, size=3) - 7.0 / reach * 1.0)
    base = np.maximum(base, ndimage.gaussian_filter(np.maximum(deck, base), 1.0)).astype(np.float32)

    # Slope, rise over run, of the real ground.
    gz, gx = np.gradient(h, CELL)
    slope = np.hypot(gx, gz)

    # Height above the nearest big water (rivers): low = floodplain.
    if REGION == "grant_in":
        # The Mississinewa is only 2 or 3 samples wide, so an opening would
        # erase it: keep every body of water bigger than a pond instead.
        lab, n = ndimage.label(is_water)
        sizes = ndimage.sum(np.ones_like(lab), lab, range(n + 1))
        big = sizes[lab] >= 150
        big[lab == 0] = False
    else:
        big = ndimage.binary_opening(is_water, iterations=2)
    bidx = ndimage.distance_transform_edt(~big, return_distances=False, return_indices=True)
    above_river = h - wlevel[bidx[0], bidx[1]]
    floodplain = 1.0 - smooth01(2.0, 9.0, above_river)
    upland = smooth01(8.0, 25.0, above_river)

    # Fertility: farmed land on gentle slopes is good soil; alluvial river
    # bottoms are the richest (Indiana's prime farmland); steep wooded hills,
    # strip mines and wet ground are poor. USDA land capability classes are
    # set mostly by exactly these: slope, erosion, wetness and flooding.
    fert = 0.42 + 0.25 * ndimage.gaussian_filter(c["crop"], 3) + 0.3 * floodplain * (1 - water)
    fert -= 0.6 * smooth01(0.02, 0.12, ndimage.gaussian_filter(slope, 1.5))
    fert -= 0.4 * ndimage.gaussian_filter(c["bare"], 2) + 0.25 * ndimage.gaussian_filter(c["wet"], 2)
    # Standing woods aren't farmland: on the flat till plain the woodlots
    # that were never cleared are mostly the wet, poorly drained ground, and
    # clearing one costs more than the land would earn for years.
    fert -= 0.8 * smooth01(0.3, 0.8, ndimage.gaussian_filter(c["tree"], 1.5))
    fert += 0.08 * (value_noise(N, 24, 7) - 0.5)
    fert = np.clip(np.where(water > 0.5, 0, fert), 0, 1)

    # Forest: real tree cover.
    forest = np.clip(ndimage.gaussian_filter(c["tree"], 1.2) * 1.15, 0, 1)

    ore, oil = (_grant_underground if REGION == "grant_in" else _pike_underground)(
        h, water, is_water, big, upland, floodplain, slope, c)

    dst = os.path.join(os.path.dirname(__file__), "..", "..", "terrain", REGION)
    os.makedirs(dst, exist_ok=True)

    def png(name, arr, mode):
        # Lossless WebP bytes under a .bin name, so Godot ships them as-is and
        # doesn't import them as textures (about 30% smaller than PNG). WebP
        # has no grey-plus-alpha mode, so LA layers go in as RGBA with
        # R = G = B; Terrain packs them back. `exact` keeps RGB under zero alpha.
        img = Image.fromarray(arr, mode)
        if mode == "LA":
            l, a = img.split()
            img = Image.merge("RGBA", (l, l, l, a))
        img.save(f"{dst}/{name}.bin", "WEBP", lossless=True, method=6, exact=True)

    def heights(a):
        """Heights in decimetres above sea level, split high byte / low byte."""
        q = np.clip(np.rint(a.astype(np.float64) * 10), 0, 65535).astype(np.uint16)
        return np.stack([(q >> 8).astype(np.uint8), (q & 255).astype(np.uint8)], -1)

    def u8(a):
        return np.clip(np.rint(a * 255), 0, 255).astype(np.uint8)
    png("ground", heights(ground), "LA")
    png("base", heights(base[::2, ::2]), "LA")
    png("wlevel", heights(wlevel[::2, ::2]), "LA")
    png("cover", np.stack([u8(c["tree"]), u8(water), u8(c["crop"]),
                           u8(c["bare"])], -1), "RGBA")
    def pool4(a):
        # Land cover layers: each 72 m sample the mean of the 4x4 it covers,
        # so a small woodlot is not missed or blown up.
        return a.reshape(N // 4, 4, N // 4, 4).mean(axis=(1, 3))
    png("resources", np.stack([u8(pool4(fert)), u8(oil[::4, ::4]), u8(ore[::4, ::4]), u8(pool4(forest))], -1), "RGBA")
    json.dump({"region": REGION, "name": NAME, "lon0": LON0, "lat0": LAT0, "size_m": SIZE, "centre": CENTRE,
               "layers": {"ground": [N, "dm LA"], "base": [N // 2, "dm LA"], "wlevel": [N // 2, "dm LA"],
                          "cover": [N, "tree water crop bare"], "resources": [N // 4, "fertility oil ore forest"]}},
              open(f"{dst}/region.json", "w"), indent=1)
    print("ground", ground.min(), ground.max(), "base", base.min(), base.max())
    print("fert mean", fert.mean(), "oil>0.5", (oil > 0.5).mean(), "ore>0.5", (ore > 0.5).mean())
    return h, ground, base, water, fert, oil, ore, forest, slope


if __name__ == "__main__":
    if "derive" not in sys.argv:
        main()
    derive()
