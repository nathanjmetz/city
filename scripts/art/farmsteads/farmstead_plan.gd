class_name FarmsteadPlan
extends RefCounted
## What one county farmstead is, grown from a few small facts, and where
## everything on it stands. The facts are its place, which way it faces its
## road, whether the land cover shows a farm or a country home, and an
## 8-bit seed (all from terrain/grant_in/farmsteads.bin). From them, by
## rules from real east-central Indiana farmsteads (docs/farmsteads.md):
##   - its kind: a working grain farm, a hog farm, a dairy, a farmstead
##     whose land is rented out to a neighbour ("retired"), or a country home
##   - how much land it farms (sized to Grant County's 2022 farm census)
##   - when it was settled, and when its house and barn were built, so the
##     house is an I-house, a gabled-ell farmhouse, a foursquare, a ranch or
##     a newer two-storey by era, and the barn a bank barn or a gambrel
##   - the barn's paint and how well it is kept (weathered, sagging, fallen)
##   - grain bins sized to what the farm grows, a dryer and leg on the big
##     ones, pole-barn machine sheds, an unused stave silo or old windmill
##     now and then, a windbreak on the north and west, a gravel drive and
##     lane, a yard light on a pole and a mailbox at the road.
## Nothing here is saved or simulated, and it is the same on every computer
## (a seeded generator, no clock), so every player in a region sees the same
## farm. The far drawing (FarmsteadFar) and the close-up (FarmsteadNear) are
## both grown from the same plan, so one hands over to the other unseen.
##
## Local frame (metres): x along the road, z away from it (+z is behind
## the house), y up. z = 0 is the farmhouse's front wall; the road runs at
## z = -lane. `side` (+1 or -1) is the side the drive and the work yard are on.

## Feet to metres.
const FT := 0.3048
## Shares of the county's farmsteads by kind (data kind 1). Grant County had
## 457 farms in 2022 (USDA census), against about 1,700 farmsteads the land
## cover shows on this map: most old farmsteads now rent their land to a
## neighbour, and their bins and barns stand, little used.
const FARM_KINDS := [["grain", 0.37], ["retired", 0.54], ["hog", 0.08], ["dairy", 0.01]]
## House types by era, for the farmhouse: [type, from year, to year, share].
## I-houses 1840-1890, gabled-ell farmhouses 1870-1910, foursquares
## 1900-1930, ranches 1950-1980, two-storey builder homes 1990-2020.
const FARM_HOUSES := [["i_house", 1845, 1890, 0.32], ["farmhouse", 1870, 1910, 0.16], ["foursquare", 1900, 1930, 0.17],
	["ranch", 1950, 1980, 0.25], ["colonial", 1990, 2020, 0.10]]
## A country home on a few acres, mostly built since the war.
const HOME_HOUSES := [["farmhouse", 1880, 1910, 0.10], ["i_house", 1850, 1890, 0.06], ["foursquare", 1905, 1930, 0.06],
	["ranch", 1950, 1985, 0.50], ["colonial", 1990, 2020, 0.28]]
## Barn paint: red (iron-oxide paint), white, and bare boards gone grey.
const BARN_RED := [Color("#7d2a20"), Color("#8a2f22"), Color("#6f2620"), Color("#933a2a")]
const BARN_WHITE := Color("#e6e3da")
const BARN_GREY := [Color("#7d776c"), Color("#6e675d"), Color("#867f73")]
## Pole-barn steel colours (tan, white, grey, light stone, green, red,
## brown) and galvalume or coloured roofs.
const SHED_WALLS := [Color("#c9b99a"), Color("#e4e2dc"), Color("#a9aba8"), Color("#d6cdb8"), Color("#4f6b4a"),
	Color("#8a2f25"), Color("#7a6250"), Color("#c9b99a")]
const SHED_ROOFS := [Color("#a9adae"), Color("#9ea2a3"), Color("#5a5c5e"), Color("#7d2f25"), Color("#3f5a3e")]
const GALV := Color("#b9bdbe")
const OLD_GALV := Color("#8f8e86")
const STAVE := Color("#bdb7aa")
## The yard light: an old mercury-vapour lamp (blue-white), a sodium one
## (orange) or an LED (white).
const LAMPS := [Color(0.80, 0.90, 1.0), Color(1.0, 0.62, 0.28), Color(1.0, 0.95, 0.88)]
## The windbreak's conifers, by TreeField kind name, a fixed list (see _windbreak).
const WINDBREAK_TREES := ["SPRUCE", "RED_CEDAR"]
## How far over the ground the lawn and the gravel lie, far and near alike.
const LAWN_LIFT := 0.15
const GRAVEL_LIFT := 0.25

## Plans kept for reuse, oldest first (a Dictionary keeps its insertion order).
static var _cache := {}
const CACHE_MAX := 512
## Plans the close-ups are using right now (key -> true): never evicted.
static var pinned := {}
## Farmsteads not drawn (the town has built over them, or they stand in
## water): key -> true. Crops and wild trees ignore them (covers, solids_in).
static var hidden := {}
## The farthest any part of a farmstead's grounds (the lawn out to the
## windbreak) or its buildings lies from its anchor, metres; a test checks
## every plan stays inside it, so the searches below can skip far places.
const REACH := 260.0


## The key a plan is kept under, and pinned and hidden by.
static func key_of(p: Dictionary) -> Vector3i:
	return Vector3i(int(p.at.x), int(p.at.y), p.seed)


## The plan for a farmstead (region metres `at`, facing angle toward its
## road, `farm` true where the land cover shows a farm), kept for reuse.
## Past CACHE_MAX the oldest unused plans go, never one a close-up is using.
static func of(at: Vector2, farm: bool, facing: float, seed: int) -> Dictionary:
	var key := Vector3i(int(at.x), int(at.y), seed)
	if _cache.has(key):
		var hit: Dictionary = _cache[key]
		# Most recently used goes last.
		_cache.erase(key)
		_cache[key] = hit
		return hit
	var p := grow(at, farm, facing, seed)
	_cache[key] = p
	if _cache.size() > CACHE_MAX:
		var drop := []
		for k in _cache:
			if _cache.size() - drop.size() <= CACHE_MAX * 3 / 4:
				break
			if not pinned.has(k):
				drop.append(k)
		for k in drop:
			_cache.erase(k)
	return p


static func grow(at: Vector2, farm: bool, facing: float, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	# The same on every computer and engine version (hash() is the engine's
	# own and may change), and the hash the crops use.
	rng.seed = CropCalendar.hash32(int(at.x), int(at.y), seed * 7919 + 13)
	var p := {"at": at, "facing": facing, "seed": seed, "side": 1.0 if seed & 1 else -1.0,
		"parts": [], "trees": [], "gravel": [], "light": {}, "acres": 0, "windbreak": ""}
	p.kind = _kind(rng) if farm else "home"
	p.founded = rng.randi_range(1835, 1880)
	p.lane = _lane(at, facing)
	match p.kind:
		"grain": p.acres = _acres(rng)
		"hog", "dairy": p.acres = int(_acres(rng) * 0.7)
	_house(p, rng)
	if p.kind == "home":
		_home_yard(p, rng)
	else:
		_farm_yard(p, rng)
	_drive(p, rng)
	_shade_trees(p, rng)
	_windbreak(p, rng)
	# None out in a pond or the river: a windbreak row reaches 30 m past the
	# yard, and on a bank it ran on into the water. Left out after every
	# roll, so the rest of the plan is the same.
	p.trees = p.trees.filter(func(t): return not under_water(to_region(p, t[0])))
	# The farmstead's grounds: the yard and the grass out to its windbreak.
	var g: Rect2 = p.extent
	for t in p.trees:
		g = g.expand(t[0])
	p.grounds = g.grow(3.0)
	return p


## A tree kind by name from the trees code (TreeField), or `fallback`
## where that kind isn't drawn yet.
static func species(name: String, fallback: int) -> int:
	var kinds: Dictionary = TreeField.Species
	return kinds.get(name, fallback)


static func _kind(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	for k in FARM_KINDS:
		r -= k[1]
		if r <= 0.0:
			return k[0]
	return "grain"


## Acres a working farm runs: Grant County's 2022 census spread (half under
## about 180 acres among all farms, 41 of 457 at 1,000 acres or more); a
## farm that keeps a farmstead and bins runs more than the average.
static func _acres(rng: RandomNumberGenerator) -> int:
	return int(pow(10.0, lerpf(2.1, 3.55, pow(rng.randf(), 1.15))))


## How far the farmhouse sits back from its road, metres: the data faces
## each place toward the nearest section-line road or state road.
static func _lane(at: Vector2, facing: float) -> float:
	var f := Vector2(cos(facing), sin(facing))
	var d := INF
	if absf(f.x) > 0.95:
		d = absf(roundf(at.x / CountyGrid.SECTION) * CountyGrid.SECTION - at.x)
	elif absf(f.y) > 0.95:
		d = absf(roundf(at.y / CountyGrid.SECTION) * CountyGrid.SECTION - at.y)
	else:
		d = Highways.distance(at.x, at.y)
	if not is_finite(d) or d > 420.0:
		d = 30.0
	return clampf(d, 24.0, 420.0)


static func _pick_era(rng: RandomNumberGenerator, table: Array) -> Array:
	var r := rng.randf()
	for t in table:
		r -= t[3]
		if r <= 0.0:
			return t
	return table[-1]


## The house: its type by when it was built, a footprint the far drawing
## uses (the close-up grows the real plan of that type), and whether it
## stands empty (farms consolidate; about one old farmhouse in twelve).
static func _house(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var t: Array = _pick_era(rng, HOME_HOUSES if p.kind == "home" else FARM_HOUSES)
	var year := rng.randi_range(t[1], t[2])
	var kind: String = t[0]
	var h := {"type": kind, "year": year, "era": "prewar" if year < 1940 else ("postwar" if year < 1985 else "recent")}
	# Footprints from the house builder's own plans (HouseBuilder).
	match kind:
		"i_house": h.merge({"w": 12.0, "d": 5.8, "eave": 6.3, "rise": 2.0, "ell": Vector2(5.0, 6.2), "ridge_x": true})
		"farmhouse": h.merge({"w": 13.0, "d": 9.0, "eave": 6.1, "rise": 2.9, "ell": Vector2.ZERO, "ridge_x": false})
		"foursquare": h.merge({"w": 9.0, "d": 9.0, "eave": 6.4, "rise": 3.0, "ell": Vector2.ZERO, "hip": true})
		"ranch": h.merge({"w": 17.0, "d": 9.0, "eave": 2.9, "rise": 1.8, "ell": Vector2.ZERO, "ridge_x": true})
		_: h.merge({"w": 16.0, "d": 10.0, "eave": 6.0, "rise": 2.4, "ell": Vector2.ZERO, "ridge_x": true})
	var old := year < 1940
	h.wall = Color("#f1efe8") if old and rng.randf() < 0.7 else \
		[Color("#e9e6da"), Color("#d8d2c2"), Color("#c9c3b3"), Color("#9aa3a8"), Color("#b8a98c"), Color("#7d8a74")][rng.randi() % 6]
	h.roof = [Color("#5c5c5e"), Color("#6e6d6a"), Color("#76665a"), Color("#7a7874"), Color("#9a9fa2")][rng.randi() % 5]
	h.vacant = p.kind != "home" and old and rng.randf() < 0.09
	h.x = -p.side * 3.0
	p.house = h
	p.old = old


## The work yard of a farm: barn, bins, sheds, silo, windmill, hog barns.
static func _farm_yard(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var s: float = p.side
	var kind: String = p.kind
	var parts: Array = p.parts
	var acres: int = p.acres
	# The barn: most old farmsteads kept theirs; some modern grain farms
	# pulled it down. Bank barns (built into a bank, a ramp up to the loft)
	# 1850-1910, gambrel-roofed hay barns 1900-1950.
	var barn_year := rng.randi_range(maxi(p.founded + 10, 1855), 1945)
	var has_barn := kind == "dairy" or rng.randf() < (0.62 if kind == "grain" else 0.82)
	var upkeep := rng.randf()
	if kind == "dairy":
		upkeep = 0.9
	var barn := {}
	if has_barn:
		var gambrel := barn_year >= 1905 or rng.randf() < 0.15
		var w := (rng.randf_range(36.0, 42.0) if gambrel else rng.randf_range(36.0, 44.0)) * FT
		var l := (rng.randf_range(60.0, 90.0) if gambrel else rng.randf_range(50.0, 80.0)) * FT
		if kind == "dairy":
			l = rng.randf_range(90.0, 120.0) * FT
		var r := rng.randf()
		var paint: Color = BARN_RED[rng.randi() % BARN_RED.size()] if r < 0.6 else (BARN_WHITE if r < 0.78 else BARN_GREY[rng.randi() % 3])
		# Upkeep: kept (painted, roof sound), weathered (paint faded, roof
		# rusting), sagging (ridge bowed, walls leaning), fallen in.
		var cond := "kept" if upkeep > 0.42 else ("weathered" if upkeep > 0.14 else ("sagging" if upkeep > 0.045 else "fallen"))
		barn = {"kind": "barn", "style": "gambrel" if gambrel else "bank", "year": barn_year, "paint": paint, "cond": cond,
			"w": w, "l": l, "eave": (rng.randf_range(16.0, 20.0) if gambrel else rng.randf_range(18.0, 22.0)) * FT,
			"pos": Vector2(-s * (6.0 + w * 0.5), 26.0 + l * 0.5), "yaw": 0.0, "lean": rng.randf_range(-1.0, 1.0)}
		parts.append(barn)
	# A concrete stave silo (1910s-1960s) by the barn's end, from when the
	# farm fed cattle; most stand unused now, some lost their domes.
	var silo_odds := 1.0 if kind == "dairy" else (0.4 if has_barn else 0.0)
	if rng.randf() < silo_odds:
		var n := 2 if kind == "dairy" and rng.randf() < 0.7 else 1
		for i in n:
			var r := rng.randf_range(12.0, 16.0) * FT * 0.5
			var used := kind == "dairy"
			var at := Vector2(barn.pos.x + s * (barn.w * 0.5 + r + 0.6), barn.pos.y + barn.l * 0.5 - r - 1.0 - i * (2.0 * r + 1.5)) \
				if has_barn else Vector2(-s * 10.0, 30.0)
			parts.append({"kind": "silo", "pos": at, "r": r, "h": rng.randf_range(36.0, 60.0) * FT,
				"dome": used or rng.randf() < 0.45, "used": used, "harvestore": used and i == 1 and rng.randf() < 0.5})
	# Grain bins: storage for part of a year's crop (corn about 180 bu an
	# acre and soybeans 55 in Grant County, half and half), in round steel
	# bins of 0.628 x D^2 x H bushels (D and H in feet). A rented-out
	# farmstead keeps one to three old, small bins.
	var bins := []
	if kind == "retired":
		var n := rng.randi_range(0, 3) if rng.randf() < 0.75 else 0
		for i in n:
			bins.append(rng.randf_range(18.0, 24.0))
	else:
		var need := acres * 118.0 * rng.randf_range(0.35, 0.8)
		var have := 0.0
		while have < need and bins.size() < 9:
			var d := 18.0 + 3.0 * float(rng.randi_range(0, 2) + int(clampf(need / 25000.0, 0.0, 6.0)))
			d = minf(d, 48.0)
			bins.append(d)
			have += 0.628 * d * d * _bin_eave(d)
	bins.sort()
	bins.reverse()
	# Bins stand in a row of up to four along the yard, the next row
	# behind, a walkway's gap apart (a compact site the auger and leg reach).
	var bin_parts := []
	var bz := 28.0
	var row_r := 0.0
	var x := s * 14.0
	for i in bins.size():
		var r: float = bins[i] * FT * 0.5
		if i > 0 and i % 4 == 0:
			bz += row_r * 2.0 + 3.0
			x = s * 14.0
			row_r = 0.0
		row_r = maxf(row_r, r)
		x += s * r
		var b := {"kind": "bin", "pos": Vector2(x, bz + r), "r": r, "h": _bin_eave(bins[i]) * FT,
			"col": GALV if p.kind != "retired" else OLD_GALV}
		bin_parts.append(b)
		parts.append(b)
		x += s * (r + 2.4)
	var bins_end := bz + row_r * 2.0
	# A dryer and a bucket elevator leg on the bigger grain farms, spouts
	# running down to each bin.
	if p.kind == "grain" and bin_parts.size() >= 3 and acres >= 700:
		var first: Dictionary = bin_parts[0]
		var leg := Vector2(first.pos.x - s * (first.r + 3.0), first.pos.y - first.r - 4.0)
		var tallest := 0.0
		for b in bin_parts:
			tallest = maxf(tallest, b.h + b.r * 0.45)
		parts.append({"kind": "dryer", "pos": leg, "h": tallest + rng.randf_range(8.0, 14.0), "bins": bin_parts,
			"dryer_at": leg + Vector2(-s * 5.0, 1.0)})
	# Pole-barn machine sheds (post-frame, since the 1960s): one or two on a
	# small farm, more on a big one; 40 x 60 ft to 60 x 120 ft.
	var n_sheds := 0
	match kind:
		"grain": n_sheds = clampi(1 + int(acres / 700.0) + (1 if rng.randf() < 0.3 else 0), 1, 4)
		"hog", "dairy": n_sheds = rng.randi_range(1, 2)
		"retired": n_sheds = 1 if rng.randf() < 0.55 else 0
	var sx := -s * 4.0
	var shed_z := maxf(26.0 + barn.get("l", 14.0), bins_end) + 10.0
	for i in n_sheds:
		var big := clampf(acres / 2000.0, 0.0, 1.0)
		var w := rng.randf_range(40.0, 50.0 + big * 20.0) * FT
		var l := rng.randf_range(60.0, 80.0 + big * 60.0) * FT
		var year := rng.randi_range(1965, 2022)
		var quonset := year < 1975 and rng.randf() < 0.35
		sx += s * l * 0.5
		parts.append({"kind": "quonset" if quonset else "shed", "pos": Vector2(sx, shed_z + w * 0.5), "w": w, "l": l,
			"eave": rng.randf_range(14.0, 18.0 + big * 4.0) * FT, "year": year,
			"wall": SHED_WALLS[rng.randi() % SHED_WALLS.size()], "roof": SHED_ROOFS[rng.randi() % SHED_ROOFS.size()]})
		sx += s * (l * 0.5 + 6.0)
	# Hog farms: two tunnel-ventilated finishing barns (41 x 204 ft, 1,200
	# head each) behind the yard, with bulk feed bins at their ends.
	if kind == "hog":
		var hz := shed_z + 28.0
		var n := rng.randi_range(1, 2)
		for i in n:
			var c := Vector2(s * 20.0, hz + i * 22.0)
			parts.append({"kind": "hog_barn", "pos": c, "w": 41.0 * FT, "l": 204.0 * FT})
			parts.append({"kind": "feed_bin", "pos": c + Vector2(-s * (102.0 * FT + 3.0), 0.0), "r": 1.5, "h": 5.5})
	if kind == "dairy":
		parts.append({"kind": "milk_house", "pos": Vector2(barn.pos.x + s * (barn.w * 0.5 + 3.5), barn.pos.y - barn.l * 0.5 + 3.0),
			"w": 6.0, "l": 5.0})
	# An old windmill tower by the house well: 8 ft wheel on a 30-40 ft
	# four-legged steel tower. A few remain, some with blades missing.
	if p.old and rng.randf() < 0.1:
		parts.append({"kind": "windmill", "pos": Vector2(-s * 13.0, 15.0), "h": rng.randf_range(28.0, 40.0) * FT,
			"wheel": (8.0 if rng.randf() < 0.75 else 10.0) * FT, "yaw": rng.randf() * TAU, "broken": rng.randf() < 0.4})
	# The yard: crushed limestone between the house and the buildings.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for part in parts:
		var e := _extent(part)
		lo = Vector2(minf(lo.x, e.position.x), minf(lo.y, e.position.y))
		hi = Vector2(maxf(hi.x, e.end.x), maxf(hi.y, e.end.y))
	if parts.is_empty():
		lo = Vector2(-10, 20)
		hi = Vector2(10, 40)
	# Gravel aprons in front of the buildings, joined into one work yard.
	var y0 := 18.0
	var y1 := maxf(minf(hi.y, shed_z + 2.0), y0 + 12.0)
	p.gravel.append(Rect2(Vector2(minf(lo.x, -6.0) + 2.0, y0), Vector2(maxf(hi.x, 6.0) - minf(lo.x, -6.0) - 4.0, y1 - y0)))
	_yard_light(p, rng, Vector2(s * 9.0, 22.0), 0.92)
	p.extent = Rect2(lo, hi - lo).expand(Vector2(-12, -6)).expand(Vector2(12, 0))


## A country home: a detached garage or a pole building behind, now and
## then an old barn from when it was a farm.
static func _home_yard(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var s: float = p.side
	var h: Dictionary = p.house
	var parts: Array = p.parts
	var r := rng.randf()
	if r < 0.45:
		parts.append({"kind": "shed", "pos": Vector2(s * 9.0, h.d + 9.0), "w": 7.0, "l": 7.5, "eave": 2.7, "year": h.year,
			"wall": h.wall, "roof": h.roof, "garage": true})
	elif r < 0.8:
		var w := rng.randf_range(30.0, 40.0) * FT
		var l := rng.randf_range(40.0, 60.0) * FT
		parts.append({"kind": "shed", "pos": Vector2(s * (6.0 + l * 0.5), h.d + 10.0 + w * 0.5), "w": w, "l": l,
			"eave": rng.randf_range(10.0, 14.0) * FT, "year": rng.randi_range(1975, 2022),
			"wall": SHED_WALLS[rng.randi() % SHED_WALLS.size()], "roof": SHED_ROOFS[rng.randi() % SHED_ROOFS.size()]})
	if rng.randf() < 0.12:
		var w := 34.0 * FT
		var l := rng.randf_range(40.0, 60.0) * FT
		var paint: Color = BARN_RED[rng.randi() % 4] if rng.randf() < 0.55 else BARN_GREY[rng.randi() % 3]
		parts.append({"kind": "barn", "style": "bank" if rng.randf() < 0.5 else "gambrel", "year": rng.randi_range(1880, 1940),
			"paint": paint, "cond": "weathered" if rng.randf() < 0.6 else "sagging", "w": w, "l": l, "eave": 16.0 * FT,
			"pos": Vector2(-s * (8.0 + w * 0.5), h.d + 18.0 + l * 0.5), "yaw": 0.0, "lean": rng.randf_range(-1.0, 1.0)})
	var depth := 30.0
	for part in parts:
		depth = maxf(depth, _extent(part).end.y + 4.0)
	_yard_light(p, rng, Vector2(s * 7.0, h.d + 4.0), 0.55)
	p.extent = Rect2(Vector2(-18.0, -4.0), Vector2(36.0, depth))


static func _yard_light(p: Dictionary, rng: RandomNumberGenerator, at: Vector2, odds: float) -> void:
	if rng.randf() >= odds:
		return
	var r := rng.randf()
	var lamp: Color = LAMPS[0] if r < 0.3 else (LAMPS[1] if r < 0.55 else LAMPS[2])
	p.light = {"pos": at, "h": 7.6, "col": lamp}


## Eave height (ft) of a bin of diameter `d` ft: rings of 32-44 in, more
## rings on wider bins (18 ft bins about 16 ft high, 48 ft bins 32-40 ft).
static func _bin_eave(d: float) -> float:
	return clampf(8.0 + d * 0.6, 16.0, 38.0)


## The gravel lane from the road and the drive past the house to the yard.
static func _drive(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var s: float = p.side
	var x: float = s * (p.house.w * 0.5 + 2.5) + p.house.x
	var half := 12.0 * FT * 0.5
	var lane: float = p.lane
	p.drive_x = x
	p.gravel.append(Rect2(Vector2(x - half, -lane + 3.0), Vector2(half * 2.0, lane - 3.0 + (20.0 if p.kind != "home" else p.house.d + 3.0))))
	# The mailbox: on the drive's right as the carrier drives up, the box
	# about 42 in high, its front 6 to 8 in back from the road's edge.
	p.mailbox = Vector2(x + s * 2.2, -lane + 4.5)


static func _extent(part: Dictionary) -> Rect2:
	var c: Vector2 = part.pos
	match part.kind:
		"bin", "silo", "feed_bin":
			return Rect2(c - Vector2.ONE * part.r, Vector2.ONE * part.r * 2.0)
		"windmill":
			return Rect2(c - Vector2(2, 2), Vector2(4, 4))
		"dryer":
			return Rect2(c - Vector2(7, 3), Vector2(14, 6))
		"barn":
			return Rect2(c - Vector2(part.w, part.l) * 0.5 - Vector2(0, 4), Vector2(part.w, part.l + 4.0))
		"milk_house":
			return Rect2(c - Vector2(part.w, part.l) * 0.5, Vector2(part.w, part.l))
	# Sheds and long barns run along x.
	return Rect2(c - Vector2(part.l, part.w) * 0.5, Vector2(part.l, part.w))


## Shade trees by the house: old farmsteads have big maples (sugar and
## silver), oaks and a black walnut or two; new homes have young ones.
static func _shade_trees(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var h: Dictionary = p.house
	var n := rng.randi_range(3, 7) if p.old else rng.randi_range(2, 4)
	var age: float = 2026.0 - float(h.year)
	# Kept clear of the house, the drive and every building by the crown's
	# reach, as arborists plant shade trees (about 20 ft out from a wall).
	var keep := [Rect2(h.x - h.w * 0.5, -3.0, h.w, h.d + 9.0), Rect2(p.drive_x - 3.0, -p.lane, 6.0, p.lane + 40.0)]
	for part in p.parts:
		keep.append(_extent(part))
	keep.append_array(p.gravel)
	for i in n:
		var a := rng.randf() * TAU
		var size := 0.0
		var r := rng.randf()
		var at := Vector2(h.x, h.d * 0.5) + Vector2(cos(a), sin(a)) * Vector2(h.w * 0.5 + rng.randf_range(10.0, 18.0), h.d * 0.5 + rng.randf_range(10.0, 18.0))
		var years := clampf(age * rng.randf_range(0.5, 1.0), 8.0, 110.0)
		size = clampf(0.45 + years / 70.0, 0.5, 1.3)
		var clear := true
		for k: Rect2 in keep:
			if k.grow(6.5 * size).has_point(at):
				clear = false
		if not clear:
			continue
		var sp: int
		if r < 0.35:
			sp = TreeField.Species.MAPLE
		elif r < 0.55:
			sp = species("SILVER_MAPLE", TreeField.Species.MAPLE)
		elif r < 0.75:
			sp = TreeField.Species.OAK
		elif r < 0.88:
			sp = species("WALNUT", TreeField.Species.OAK)
		else:
			sp = TreeField.Species.SPRUCE
		p.trees.append([at, sp, size, years])


## The windbreak: rows of conifers on the farmstead's north and west sides
## (the winter wind's), set back 65-100 ft from what it shelters (2 to 5
## times its height, NRCS practice 380), trees 8-16 ft apart in a row and
## rows 12-20 ft apart (Purdue FNR-189 and its county notes). Most were
## planted 1940-1980; a gap where a tree died now and then.
static func _windbreak(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var odds := 0.8 if p.kind != "home" else 0.4
	if rng.randf() >= odds:
		return
	var rows := 1 if p.kind == "home" else rng.randi_range(1, 3)
	var planted := rng.randi_range(1940, 1985) if p.kind != "home" else rng.randi_range(maxi(1950, p.house.year), 2015)
	var years := clampf(2026.0 - planted, 8.0, 90.0)
	var size := clampf(0.4 + years / 60.0, 0.45, 1.35)
	# One roll from a fixed list, so the pick (and the rest of this farmstead's
	# rolls) never depend on which kinds the trees code has drawn yet. Until
	# the trees code has a red cedar, it is drawn as a spruce.
	var wb_name: String = WINDBREAK_TREES[rng.randi() % WINDBREAK_TREES.size()]
	p.windbreak = wb_name
	var sp: int = species(wb_name, TreeField.Species.SPRUCE)
	var e: Rect2 = p.extent
	var f := Vector2(cos(p.facing), sin(p.facing))  # toward the road (local -z)
	# Local axes in region terms: +z is away from the road, +x along it.
	var ax := Vector2(-f.y, f.x)
	var az := -f
	var gap := rng.randf_range(20.0, 30.0)
	var step := rng.randf_range(8.0, 14.0) * FT * 1.6
	# Each side of the extent whose outward normal points north (-z region)
	# or west (-x region) gets the rows, except the one facing the road.
	# Each side of the yard that faces the north-west (the winter wind's
	# quarter) gets the rows. On the road side they stand between the road
	# and the house, the lane passing through a gap.
	var nw := Vector2(-1, -1).normalized()
	var sides := [[Vector2(0, 1), az], [Vector2(-1, 0), -ax], [Vector2(1, 0), ax], [Vector2(0, -1), -az]]
	for sd in sides:
		var n_local: Vector2 = sd[0]
		var n_world: Vector2 = sd[1]
		if n_world.dot(nw) < 0.3:
			continue
		for row in rows:
			var off := gap + row * rng.randf_range(12.0, 20.0) * FT
			var a: Vector2
			var b: Vector2
			if n_local.y > 0.5:
				a = Vector2(e.position.x - gap, e.end.y + off)
				b = Vector2(e.end.x + gap, e.end.y + off)
			elif n_local.y < -0.5:
				var z := e.position.y - off * 0.6
				if z < -p.lane + 12.0:
					continue
				a = Vector2(e.position.x - gap, z)
				b = Vector2(e.end.x + gap, z)
			elif n_local.x < -0.5:
				a = Vector2(e.position.x - off, e.position.y + 10.0)
				b = Vector2(e.position.x - off, e.end.y + gap)
			else:
				a = Vector2(e.end.x + off, e.position.y + 10.0)
				b = Vector2(e.end.x + off, e.end.y + gap)
			var len := a.distance_to(b)
			var k := 0.0
			while k <= len:
				var q := a.lerp(b, k / len)
				k += step
				if absf(q.x - p.drive_x) < 7.0 and n_local.y < -0.5:
					continue  # the lane's gap
				if rng.randf() > 0.08:
					var jitter := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
					p.trees.append([q + jitter, sp, size * rng.randf_range(0.85, 1.1), years, true])


## Places from farmsteads.bin by 256 m square: [at, farm, facing, seed].
static var _bins := {}
## 256 m square -> the places whose grounds can reach into it (no plans grown).
static var _near_sq := {}
## Place key -> its grounds for crops: [at, facing, Rect2 local], or null where
## it stands in water. Grown one place at a time, the first time a crop asks
## about ground within reach of it.
static var _yards := {}
## Place key -> its solid ground (see _solid), kept: about a kilobyte each.
static var _solids := {}


## Loads the places from farmsteads.bin, once (no plans grown).
static func load_places() -> void:
	if not _bins.is_empty():
		return
	_bins[Vector2i(1 << 20, 0)] = []  # loaded, even if the file is missing
	var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
	if data.size() >= 8 and data.slice(0, 4).get_string_from_ascii() == "FST1":
		for i in data.decode_u32(4):
			var at := 8 + i * 7
			var q := off_rail(Vector2(data.decode_s16(at), data.decode_s16(at + 2)))
			var b := Vector2i(floori(q.x / 256.0), floori(q.y / 256.0))
			if not _bins.has(b):
				_bins[b] = []
			_bins[b].append([q, data.decode_u8(at + 4) == 1, data.decode_u8(at + 5) / 256.0 * TAU, data.decode_u8(at + 6)])


## A farmstead's place moved back from a county railroad (CountyRail, where
## it is drawn) to RAIL_BACK metres off the track: the land cover's 10 m
## pixels put a few houses on the right of way itself, and real farmhouses
## stand back past its 100 ft and the fence.
const RAIL_BACK := 45.0
static func off_rail(q: Vector2) -> Vector2:
	if not CountyRail.drawn():
		return q
	# Again, where moving off one track brings it near another (a junction).
	for k in 4:
		var n := CountyRail.near(q.x, q.y, RAIL_BACK - 0.5)
		if n.is_empty():
			return q
		var away: Vector2 = q - n.on
		if away.length() < 0.5:
			var r: Dictionary = CountyRail.all()[n.route]
			var t: Vector2 = (r.pts[n.seg + 1] - r.pts[n.seg]).normalized()
			away = Vector2(-t.y, t.x)
		q = n.on + away.normalized() * RAIL_BACK
	# Hemmed in between tracks: the nearest clear spot round about.
	if not CountyRail.near(q.x, q.y, RAIL_BACK - 0.5).is_empty():
		for ring in range(1, 6):
			for k in 8:
				var c := q + Vector2.from_angle(k * TAU / 8.0) * RAIL_BACK * ring
				if CountyRail.near(c.x, c.y, RAIL_BACK - 0.5).is_empty():
					return c
	return q


## The places whose grounds can reach into a 256 m square.
static func _places_near(sq: Vector2i) -> Array:
	if not _near_sq.has(sq):
		if _near_sq.size() > 4096:
			_near_sq.clear()
		var box := Rect2(Vector2(sq) * 256.0, Vector2(256.0, 256.0)).grow(REACH)
		var list := []
		var n := ceili(REACH / 256.0)
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				for pl in _bins.get(sq + Vector2i(dx, dz), []):
					if box.has_point(pl[0]):
						list.append(pl)
		_near_sq[sq] = list
	return _near_sq[sq]


## True where a county farmstead's yard and lawn lie (region metres), so
## crops (CropPlants) keep off it. Only farmsteads that are drawn count: not
## one in water, nor one the town has built over. A plan is grown the first
## time a crop asks about ground within reach of its farmstead, one at a
## time, never the squares' worth at once.
static func covers(r: Vector2) -> bool:
	load_places()
	for pl in _places_near(Vector2i(floori(r.x / 256.0), floori(r.y / 256.0))):
		var at: Vector2 = pl[0]
		if absf(r.x - at.x) > REACH or absf(r.y - at.y) > REACH:
			continue
		var key := Vector3i(int(at.x), int(at.y), pl[3])
		if hidden.has(key):
			continue
		if not _yards.has(key):
			if _yards.size() > 4096:
				_yards.clear()
			var p := of(at, pl[1], pl[2], pl[3])
			_yards[key] = null if wet(p) else [p.at, p.facing, (p.grounds as Rect2).grow(4.0)]
		var y: Variant = _yards[key]
		if y == null:
			continue
		var f := Vector2(cos(y[1]), sin(y[1]))
		var d: Vector2 = r - y[0]
		if (y[2] as Rect2).has_point(Vector2(d.dot(Vector2(-f.y, f.x)), -d.dot(f))):
			return true
	return false


## The farmsteads whose buildings, gravel, house or lawn stand in a region
## rectangle (WildView asks once per chunk, then on_solid for each tree):
## [anchor, facing, Array of local Rect2, reach]. Loads the places, but
## grows plans only for farmsteads within reach of the rectangle.
static func solids_in(box: Rect2) -> Array:
	load_places()
	var out := []
	var reach := box.size.length() * 0.5 + REACH
	var b0 := Vector2i(floori((box.position.x - REACH) / 256.0), floori((box.position.y - REACH) / 256.0))
	var b1 := Vector2i(floori((box.end.x + REACH) / 256.0), floori((box.end.y + REACH) / 256.0))
	for bx in range(b0.x, b1.x + 1):
		for bz in range(b0.y, b1.y + 1):
			for pl in _bins.get(Vector2i(bx, bz), []):
				if (pl[0] as Vector2).distance_to(box.get_center()) > reach:
					continue
				var key := Vector3i(int(pl[0].x), int(pl[0].y), pl[3])
				if hidden.has(key):
					continue
				if not _solids.has(key):
					if _solids.size() > 2048:
						_solids.clear()
					var p := of(pl[0], pl[1], pl[2], pl[3])
					_solids[key] = [] if wet(p) else _solid(p)
				if not _solids[key].is_empty():
					out.append(_solids[key])
	return out


## A farmstead's solid ground for on_solid: [anchor, facing, local rects, reach]:
## the house, every building, the gravel (the lane only near the yard) and the
## mown lawn out to the windbreak.
static func _solid(p: Dictionary) -> Array:
	var rects := [Rect2(p.house.x - p.house.w * 0.5, -4.0, p.house.w, p.house.d + 8.0).grow(4.0), (p.grounds as Rect2).grow(1.0)]
	for part in p.parts:
		rects.append(_extent(part).grow(4.0))
	for g: Rect2 in p.gravel:
		# The lane only near the yard (woods along a lane can stay).
		rects.append(g.intersection(Rect2(-1000.0, -10.0, 2000.0, 2000.0)).grow(2.0))
	var reach := 0.0
	for rect: Rect2 in rects:
		for c in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			reach = maxf(reach, c.length())
	return [p.at, p.facing, rects, reach]


## True where a tree would stand on a farmstead's buildings, gravel or lawn
## (region metres; `solids` from solids_in).
static func on_solid(solids: Array, r: Vector2) -> bool:
	for s in solids:
		var d: Vector2 = r - s[0]
		if d.length_squared() > s[3] * s[3]:
			continue
		var f := Vector2(cos(s[1]), sin(s[1]))
		var q := Vector2(d.dot(Vector2(-f.y, f.x)), -d.dot(f))
		for rect: Rect2 in s[2]:
			if rect.has_point(q):
				return true
	return false


## How a tree stands at a local point: the turn and the tint, the same for
## the far stand-in and the close-up tree so they match at the handover.
static func tree_turn(at: Vector2) -> float:
	return fposmod(at.x * 1.7 + at.y * 0.9, TAU)


static func tree_tint(leaf: Color, at: Vector2, amount := 0.08) -> Color:
	return leaf.lightened(fposmod(at.x * 0.37 + at.y * 0.13, 1.0) * amount - amount * 0.375)


## True where the yard would reach into a lake or river: the land cover
## marks a few farmsteads right on the water, and those are left out.
static func wet(p: Dictionary) -> bool:
	var e: Rect2 = p.extent
	for q in [e.position, e.end, Vector2(e.position.x, e.end.y), Vector2(e.end.x, e.position.y), e.get_center()]:
		var r := to_region(p, q)
		if Terrain.water(r.x, r.y) > 0.3:
			return true
	return false


## True where region point `r` lies under a pond's or the river's level
## (TerrainView draws its water sheet there).
static func under_water(r: Vector2) -> bool:
	return Terrain.water(r.x, r.y) > 0.02 and Terrain.height(r.x, r.y) < Terrain.water_level(r.x, r.y) + 0.15


## A local point (x along the road, z back from it) in region metres.
static func to_region(p: Dictionary, q: Vector2) -> Vector2:
	var f := Vector2(cos(p.facing), sin(p.facing))
	return p.at + Vector2(-f.y, f.x) * q.x - f * q.y


## The farmstead's frame in view coordinates: its origin at the anchor on
## the ground (y = `base`), local -z toward the road.
static func frame(p: Dictionary, origin: Vector2, base: float) -> Transform3D:
	var f := Vector2(cos(p.facing), sin(p.facing))
	var z := Vector3(-f.x, 0.0, -f.y)
	var x := Vector3.UP.cross(z)
	var at: Vector2 = p.at - origin
	return Transform3D(Basis(x, Vector3.UP, z), Vector3(at.x, base, at.y))
