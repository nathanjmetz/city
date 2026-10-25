class_name RoadWear
extends RefCounted
## How each kind of road wears and gets repaired, from small facts: the
## road's type (its surface and how much traffic and how many trucks a road
## like it carries), when it was paved or last resurfaced (StreetAge, read
## only), and the date. Nothing new is saved: every player in a region sees
## the same cracks, patches and paint on the same day.
##
## The numbers and where they come from: docs/roads-age.md. The shaders in
## RoadSurface read the constants below, so each number lives here once.

## Surfaces drawn by RoadSurface. Dirt lanes and brick keep their own looks.
enum Kind { ASPHALT, CHIP, GRAVEL, CONCRETE, DIRT, BRICK }

# --- Asphalt ---------------------------------------------------------------
## Sun oxidises the binder: jet black to charcoal grey in about 3 to 5 years
## (the e-folding time, in years, of the black-to-grey fade).
const OXIDISE_YEARS := 1.8
## Crack sealing: first about 3.5 to 5 years after paving, then every 4 years
## (FHWA pavement preservation; INDOT: sealing keeps water out), until about
## year 17, when a street waits for its overlay.
const SEAL_FIRST := 3.5
const SEAL_SPREAD := 1.5
const SEAL_EVERY := 4.0
const SEAL_LAST := 3.0  # seals after the first
## Fresh sealant is glossy black; it dulls over about this many years.
const SEAL_DULL := 0.45
## Thermal (transverse) cracks: the first from about year 3, one every 9 m by
## about year 21 (cold-climate thermal cracking spacing).
const THERMAL_FROM := 3.0
const THERMAL_SPREAD := 18.0
const THERMAL_EVERY := 9.0
## Fatigue (alligator) cracking in the wheel paths: from about year 10 on
## the heaviest truck routes, about year 22 on quiet streets.
const FATIGUE_LATE := 24.0
const FATIGUE_SPAN := 14.0
## Potholes: open in February and March (freeze-thaw), cold patched within
## 2 to 4 weeks, hot patched once the asphalt plants open (mid May to
## September; hot mix needs about 40-50 F).
const HOLE_FROM := 5.0
const HOLE_SPAN := 22.0
const HOLE_SHARE := 0.70  # of 5 m wheel-path stretches, over a street's life, on a heavy truck route
const HOT_PATCH_AT := 0.37  # fraction of the year: mid May
const HOT_PATCH_SPREAD := 0.30

# --- Paint -------------------------------------------------------------------
## Waterborne paint lasts about a year (one winter of plows and salt); INDOT
## repaints at least yearly, April to October. Towns: every 1 to 2 years.
const PAINT_FROM := 0.42  # early June
const PAINT_SPREAD := 0.25
const PAINT_YEARLY := 0.6  # share of stretches repainted every year (the rest every other year)

# --- Chip seal ---------------------------------------------------------------
## County chip seal: redone every 5 to 7 years in July (INDOT: one adds 3 to 5
## years; counties stretch it).
const CHIP_EVERY := 5.0
const CHIP_SPREAD := 2.0
const CHIP_MONTH := 0.55

# --- Concrete ----------------------------------------------------------------
## Jointed plain concrete: transverse joints every 15 ft (INDOT Design Manual
## ch. 52 after JTRP-2011/20), longitudinal joints at the lane lines.
const SLAB := 4.572

## Typical traffic for each road type: [average daily traffic, share of
## trucks]. Rough INDOT functional-class figures (local streets a few hundred
## to 1,500 a day, collectors a few thousand, arterials 10,000 to 25,000,
## rural I-69 about 30,000 with a quarter trucks, gravel county roads under
## 100). The game has no stored count per road, so the road's class stands in.
const TRAFFIC := {
	RoadStyle.Type.STREET: [800, 0.03],
	RoadStyle.Type.AVENUE: [6000, 0.05],
	RoadStyle.Type.BOULEVARD: [18000, 0.06],
	RoadStyle.Type.HIGHWAY: [30000, 0.25],
	RoadStyle.Type.RAMP: [6000, 0.20],
	RoadStyle.Type.RING: [4000, 0.04],
	RoadStyle.Type.RING2: [9000, 0.05],
	RoadStyle.Type.STREET_NARROW: [500, 0.03],
	RoadStyle.Type.STREET_BIKE: [1200, 0.03],
	RoadStyle.Type.STREET_ONEWAY: [4000, 0.04],
	RoadStyle.Type.MAIN_STREET: [5000, 0.04],
	RoadStyle.Type.ALLEY: [100, 0.08],
	RoadStyle.Type.GRAVEL: [60, 0.15],
	RoadStyle.Type.COUNTY: [800, 0.10],
	RoadStyle.Type.AVENUE_TURN: [9000, 0.05],
	RoadStyle.Type.AVENUE_BIKE: [6000, 0.05],
	RoadStyle.Type.AVENUE_DIVIDED: [12000, 0.05],
	RoadStyle.Type.AVENUE_ONEWAY: [6000, 0.04],
	RoadStyle.Type.STRIP: [20000, 0.07],
	RoadStyle.Type.PARKWAY: [12000, 0.03],
	RoadStyle.Type.FREEWAY2: [25000, 0.25],
	RoadStyle.Type.FREEWAY4: [45000, 0.20],
	RoadStyle.Type.DIVIDED_HWY: [12000, 0.15],
	RoadStyle.Type.STATE_HWY: [5000, 0.12],
	RoadStyle.Type.RAMP2: [10000, 0.18],
	RoadStyle.Type.AVENUE_BUS: [7000, 0.08],
	RoadStyle.Type.DIRT: [15, 0.10],
	RoadStyle.Type.CHIP_SEAL: [250, 0.12],
	RoadStyle.Type.STREET_ONEWAY1: [1500, 0.03],
	RoadStyle.Type.BRICK: [1000, 0.02],
	RoadStyle.Type.STREET_DIVIDED: [2500, 0.03],
}

## Interstate mainline is jointed concrete; the rest of the asphalt types
## stay asphalt, alleys are concrete (RoadStyle).
const CONCRETE_TYPES := [RoadStyle.Type.HIGHWAY, RoadStyle.Type.FREEWAY2, RoadStyle.Type.FREEWAY4]


static func kind(type: int) -> int:
	if type in CONCRETE_TYPES:
		return Kind.CONCRETE
	match RoadStyle.TYPES[type].get("surface", "asphalt"):
		"chip seal": return Kind.CHIP
		"gravel": return Kind.GRAVEL
		"concrete": return Kind.CONCRETE
		"dirt": return Kind.DIRT
		"brick": return Kind.BRICK
	return Kind.ASPHALT


## Average daily traffic, 0 (a field lane) to 1 (a busy interstate).
static func traffic(type: int) -> float:
	var t: Array = TRAFFIC.get(type, [800, 0.05])
	return clampf(log(1.0 + float(t[0])) / log(1.0 + 40000.0), 0.0, 1.0)


## Truck loading (what wears out the wheel paths), 0 to 1.
static func fatigue(type: int) -> float:
	var t: Array = TRAFFIC.get(type, [800, 0.05])
	return clampf(log(1.0 + float(t[0]) * float(t[1])) / log(1.0 + 8000.0), 0.0, 1.0)


## Where the wheels run on this road, across its paved strip (metres from
## the centre line): {start: the first lane's centre, width: each lane's,
## count: lanes on a side (two-way) or in all (one-way), mirror: two-way}.
static func lanes(type: int) -> Dictionary:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw: float = spec.width * 0.5
	var n: int = spec.lanes
	if RoadStyle.is_freeway(type):
		return {"start": -hw + 1.2 + 1.8, "width": 3.6, "count": n, "mirror": false}
	if spec.oneway:
		return {"start": -n * 1.8 + 1.8, "width": 3.6, "count": n, "mirror": false}
	var per_side := maxi(n / 2, 1)
	var inner: float = spec.median * 0.5
	if RoadStyle.raised_median(type):
		inner += RoadStyle.CURB_WIDTH
	var w := minf(3.6, (hw - inner) / per_side)
	return {"start": inner + w * 0.5, "width": w, "count": per_side, "mirror": true}


## Narrow country roads crumble at the edge where trucks run off the paving.
static func breaks_at_edge(type: int) -> bool:
	return type == RoadStyle.Type.COUNTY or type == RoadStyle.Type.CHIP_SEAL


## A date in years (Seasons.months / 12) packed into two bytes, 1/256 year
## steps, from 64 years before the first year to 192 after.
static func pack_years(years: float) -> int:
	return clampi(roundi((years + 64.0) * 256.0), 0, 65535)


static func unpack_years(v: int) -> float:
	return float(v) / 256.0 - 64.0


## The wear map: each StreetAge square's paving date, for the shaders.
## Returns {image, rect: Vector4(first x, first z, across, down)}, or {}
## when nothing is paved yet. At most `limit` squares a side.
static func map_image(paved: Dictionary, limit := 1024) -> Dictionary:
	if paved.is_empty():
		return {}
	var x0 := 1 << 30
	var z0 := 1 << 30
	var x1 := -(1 << 30)
	var z1 := -(1 << 30)
	for k in paved:
		x0 = mini(x0, k.x)
		z0 = mini(z0, k.y)
		x1 = maxi(x1, k.x)
		z1 = maxi(z1, k.y)
	# A huge region keeps the squares around the middle.
	var w := mini(x1 - x0 + 1, limit)
	var h := mini(z1 - z0 + 1, limit)
	x0 = maxi(x0, (x0 + x1) / 2 - limit / 2) if x1 - x0 + 1 > limit else x0
	z0 = maxi(z0, (z0 + z1) / 2 - limit / 2) if z1 - z0 + 1 > limit else z0
	# One square of margin all round: StreetAge notes the squares a street's
	# centre line runs through, but a wide road (or one along a square's
	# edge) spills into the next. An unnoted square next to noted ones takes
	# the newest of them.
	x0 -= 1
	z0 -= 1
	w = mini(w + 2, limit)
	h = mini(h + 2, limit)
	var vals := PackedInt32Array()
	vals.resize(w * h)
	vals.fill(-1)
	var noted := PackedInt32Array()
	for k in paved:
		var x: int = k.x - x0
		var z: int = k.y - z0
		if x < 0 or z < 0 or x >= w or z >= h:
			continue
		vals[z * w + x] = pack_years(Seasons.months(int(paved[k])) / 12.0)
		noted.append(z * w + x)
	var spill := {}  # unnoted square -> the newest noted one beside it
	for i in noted:
		var x := i % w
		var z := i / w
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var nx: int = x + dx
				var nz: int = z + dz
				if nx >= 0 and nz >= 0 and nx < w and nz < h and vals[nz * w + nx] < 0:
					spill[nz * w + nx] = maxi(spill.get(nz * w + nx, -1), vals[i])
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in noted:
		spill[i] = vals[i]
	for i in spill:
		var v: int = spill[i]
		data[i * 4] = v >> 8
		data[i * 4 + 1] = v & 255
		data[i * 4 + 3] = 255
	return {"image": Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data),
		"rect": Vector4(x0, z0, w, h)}

