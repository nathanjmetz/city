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
