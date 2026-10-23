class_name CountyGrid
## County roads on the section lines of the Public Land Survey: a gravel road
## every mile, north-south and east-west, as across Pike County, Indiana
## (CR 100 N, 200 E and so on). Not every mile of line has one, and they
## stop at the water and on steep bluffs.
##
## Until a town joins one they are scenery: the ground shader paints them
## (TerrainView, county_road) and wild trees keep off them, so they cost the
## simulation nothing. The rule here and the shader's must stay the same.

## A mile of section line: four of the quarter-mile fields the ground shader
## draws (402 m), in region coordinates.
const SECTION := 1608.0
## Half the gravel roadway, metres (a 7 m, two-way county road).
const HALF_WIDTH := 3.5
## Half the cleared strip: the roadway, ditches and mowed verge.
const HALF_CLEAR := 8.0
## Share of the miles of section line that have a road.
const SHARE := 0.73
## No road where the land is steeper than this (bluffs above the river).
const MAX_SLOPE := 0.18


## A 32-bit integer hash, the same here and in the shader.
static func mix(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663)
	h &= 0xffffffff
	h ^= h >> 15
	h = (h * 0x2c1b3c6d) & 0xffffffff
	h ^= h >> 12
	h = (h * 0x297a2d39) & 0xffffffff
	h ^= h >> 15
	return h


## Whether mile `seg` (counted along the line) of section line `line` has a
## road. North-south lines are numbered by x; east-west lines are offset by
## 1 << 20 so the two families differ.
static func has_mile(line: int, seg: int) -> bool:
	return float(mix(line, seg) & 0xffff) / 65536.0 < SHARE


## The line and mile under a point along one axis: `across` is the
## coordinate across the line, `along` the one along it.
static func _line(across: float) -> int:
	return floori(across / SECTION + 0.5)


## How far a point (region coordinates) is from the nearest county road's
## centre line, or INF where none runs near. Ignores water and slope.
static func distance(x: float, z: float) -> float:
	var best := INF
	var ns := _line(x)
	if has_mile(ns, floori(z / SECTION)):
		best = absf(x - ns * SECTION)
	var ew := _line(z)
	if has_mile(ew + (1 << 20), floori(x / SECTION)):
		best = minf(best, absf(z - ew * SECTION))
	return best


## True where the cleared strip of a county road runs: the road itself, its
## ditches and verge, on dry land that isn't too steep. Region coordinates.
static func clears(x: float, z: float) -> bool:
	if distance(x, z) > HALF_CLEAR:
		return false
	return Terrain.water(x, z) < 0.1 and Terrain.slope(x, z) < MAX_SLOPE


## The mile of county road nearest a point (region coordinates), if one
## runs within `reach` metres: {key, a, b (its ends, Vector2), on (the
## point on it nearest p)}, or {} where none does.
static func mile_at(x: float, z: float, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	var ns := _line(x)
	var seg := floori(z / SECTION)
	if has_mile(ns, seg) and absf(x - ns * SECTION) <= best_d:
		best_d = absf(x - ns * SECTION)
		best = {"key": "ns:%d:%d" % [ns, seg], "a": Vector2(ns * SECTION, seg * SECTION),
			"b": Vector2(ns * SECTION, (seg + 1) * SECTION), "on": Vector2(ns * SECTION, z)}
	var ew := _line(z)
	seg = floori(x / SECTION)
	if has_mile(ew + (1 << 20), seg) and absf(z - ew * SECTION) <= best_d:
		best = {"key": "ew:%d:%d" % [ew, seg], "a": Vector2(seg * SECTION, ew * SECTION),
			"b": Vector2((seg + 1) * SECTION, ew * SECTION), "on": Vector2(x, ew * SECTION)}
	return best


## How far the road runs from `on` toward `to` (both on one mile) before
## the water or a bluff stops it, in steps of STEP metres.
static func run(on: Vector2, to: Vector2) -> Vector2:
	var length := on.distance_to(to)
	if length < 1.0:
		return on
	var dir := (to - on) / length
	var d := 0.0
	while d + STEP <= length:
		var q := on + dir * (d + STEP)
		if Terrain.water(q.x, q.y) >= 0.1 or Terrain.slope(q.x, q.y) >= MAX_SLOPE:
			# Stop short of the bank, at a turnaround.
			return on + dir * maxf(d - STEP, 0.0)
		d += STEP
	return to


## Sampling step when following a county road onto the land, metres.
const STEP := 10.0


## A county road's name, as Indiana counties number them: hundreds for each
## eighth of a mile from the county's base lines, N/S or E/W of them.
static func road_name(key: String) -> String:
	var parts := key.split(":")
	var n := int(parts[1])
	# A mile is 800 in the county numbering (100 per eighth of a mile).
	if parts[0] == "ns":
		return "County Road %d %s" % [absi(n) * 800, "E" if n >= 0 else "W"]
	return "County Road %d %s" % [absi(n) * 800, "S" if n >= 0 else "N"]
