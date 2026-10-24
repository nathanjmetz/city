class_name CountyGrid
## County roads on the section lines of the Public Land Survey: a gravel road
## on the miles of line where Grant County, Indiana has one (East 100 N, South
## 200 W and so on), from its real roads (tools/terrain/build_roads.py, table
## county.bin). The game's lines are an exact mile apart; the real ones wander
## a little (about 80 m on average), so each real road is squared onto the
## nearest line. They stop at the water and on steep bluffs.
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
## Trees stand back this far from the middle of the road, so their crowns
## don't close over it (the right of way is mowed, 33 ft each side).
const TREE_CLEAR := 12.0
## Share of the miles of section line that have a road, past the real map
## (where the land mirrors): build_roads.py fills those in by this rule.
const SHARE := 0.95
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
	_load()
	var ew := line >= (1 << 19)
	if ew:
		line -= 1 << 20
	return _miles[(posmod(seg, TABLE) * TABLE + posmod(line, TABLE)) * 3 + (1 if ew else 0)] > 127


## The table of miles (county.bin): TABLE x TABLE, red for north-south,
## green for east-west, at (line, mile) wrapped. The ground shader reads the
## same table (texture()).
const TABLE := 64
static var _miles := PackedByteArray()
static var _names := {}
static var _tex: ImageTexture


static func _load() -> void:
	if not _miles.is_empty():
		return
	var img := Image.new()
	if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(Terrain.DIR + "county.bin")) != OK:
		push_error("CountyGrid: can't read county.bin")
		_miles.resize(TABLE * TABLE * 3)
		return
	img.convert(Image.FORMAT_RGB8)
	_miles = img.get_data()
	_tex = ImageTexture.create_from_image(img)
	var json = JSON.parse_string(FileAccess.get_file_as_string(Terrain.DIR + "county.json"))
	if typeof(json) == TYPE_DICTIONARY:
		_names = json.get("names", {})


## The real name of a mile ("E 100 N"), or "" where it has none.
static func real_name(key: String) -> String:
	_load()
	return str(_names.get(key, ""))


## The table of miles for the ground shader.
static func texture() -> Texture2D:
	_load()
	return _tex


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
static func clears(x: float, z: float, half := HALF_CLEAR) -> bool:
	if distance(x, z) > half:
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


## Every mile of county road within `reach` metres of a point (region
## coordinates), as mile_at gives them: at a crossing, all four.
static func miles_at(x: float, z: float, reach: float) -> Array:
	var out := []
	var ns := _line(x)
	if absf(x - ns * SECTION) <= reach:
		for seg in range(floori((z - reach) / SECTION), floori((z + reach) / SECTION) + 1):
			if has_mile(ns, seg):
				out.append(mile_of("ns:%d:%d" % [ns, seg], x, z))
	var ew := _line(z)
	if absf(z - ew * SECTION) <= reach:
		for seg in range(floori((x - reach) / SECTION), floori((x + reach) / SECTION) + 1):
			if has_mile(ew + (1 << 20), seg):
				out.append(mile_of("ew:%d:%d" % [ew, seg], x, z))
	return out


## The mile with this key, as mile_at gives it, `on` its nearest point to
## (x, z) (region coordinates).
static func mile_of(key: String, x: float, z: float) -> Dictionary:
	var parts := key.split(":")
	var line := int(parts[1])
	var seg := int(parts[2])
	if parts[0] == "ns":
		return {"key": key, "a": Vector2(line * SECTION, seg * SECTION), "b": Vector2(line * SECTION, (seg + 1) * SECTION),
			"on": Vector2(line * SECTION, clampf(z, seg * SECTION, (seg + 1) * SECTION))}
	return {"key": key, "a": Vector2(seg * SECTION, line * SECTION), "b": Vector2((seg + 1) * SECTION, line * SECTION),
		"on": Vector2(clampf(x, seg * SECTION, (seg + 1) * SECTION), line * SECTION)}


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


## A county road's name, as Indiana counties number them: 100 for each mile
## from the county's base lines (CR 300 N is three miles north), N/S or E/W
## of them. Its real name when it has one ("East 100 N"). Once a town has a
## courthouse, Streets.grid_name counts from it.
static func road_name(key: String) -> String:
	_load()
	if _names.has(key):
		return str(_names[key])
	var parts := key.split(":")
	var n := int(parts[1])
	if parts[0] == "ns":
		return "County Road %d %s" % [absi(n) * 100, "E" if n >= 0 else "W"]
	return "County Road %d %s" % [absi(n) * 100, "S" if n >= 0 else "N"]


## True for a mile key as mile_at makes them ("ns:3:-2", "ew:0:5").
static func valid_key(key: String) -> bool:
	var parts := key.split(":")
	return parts.size() == 3 and parts[0] in ["ns", "ew"] and parts[1].is_valid_int() and parts[2].is_valid_int()


## Size of the table of miles the ground shader hides (HIDDEN x HIDDEN,
## wrapping): the ones bulldozed.
const HIDDEN := 64


## That table as a texture: red for north-south miles, green for east-west,
## at (line, mile) wrapped to HIDDEN.
static func hidden_texture(keys: Array) -> ImageTexture:
	var img := Image.create(HIDDEN, HIDDEN, false, Image.FORMAT_RG8)
	for key in keys:
		if not valid_key(key):
			continue
		var parts: PackedStringArray = key.split(":")
		var x := posmod(int(parts[1]), HIDDEN)
		var y := posmod(int(parts[2]), HIDDEN)
		var c := img.get_pixel(x, y)
		if parts[0] == "ns":
			c.r = 1.0
		else:
			c.g = 1.0
		img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
