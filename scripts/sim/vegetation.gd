class_name Vegetation
extends RefCounted
## Wild trees and brush, the way Brawn asked: there are no landscaping or
## brush tools. A new map is already covered in woodlots, fencerow trees and
## brush. Roads, buildings, farms and industry clear what they sit on ("the
## road wins"), and land that is cleared and then left empty grows back over
## real years: brush first, then young trees, then a woodlot again (numbers
## in Balance, WILD_*).
##
## Cheap and the same for everyone: the wild plants themselves are never
## stored. Each spot's plant comes from a hash of where it is, so the whole
## endless map costs nothing until the camera looks at it. All the city keeps
## is when each patch of land was last cleared, in 4 m cells, and only for
## land that was built on and then left.
## Benchmark: aerial photos of Pike County, Indiana, where woodlots, brushy
## fencerows and grown-over lots sit between the fields and houses.

signal changed(chunks: Array)

enum Kind { TREE, SHRUB }

## Size of a clearing record, metres.
const CELL := 4.0
## One possible tree every 9 m and one possible shrub every 6 m, each nudged
## at random within its square so no rows show.
const TREE_SPACING := 11.0
const SHRUB_SPACING := 7.0
## The view draws plants in chunks this big (matching TreeField's chunks).
const CHUNK := 256.0
const TICKS_PER_YEAR := 12 * 24 * 60  # 12 game days (one a month), 1 minute a tick

## Swappable natural cover: a Callable(p: Vector3) -> [tree share, brush share],
## each 0 to 1. The terrain thread plugs real land-cover data in here.
static var cover_source := Callable()

## Cell -> tick the land there was last cleared and left empty.
var cleared := {}
var _occupied := {}  # cell -> how many things stand on it
var _sources := {}  # what stands on the land (a road, a lot...) -> its cells
var _newest := {}  # chunk -> latest tick land in it was cleared
var _touched := {}  # chunks the city has ever built in (the rest is all wild)
var _dirty := true
var _dirty_tick := 0
var _sim: Object
var _hubs_version := -1


## Follows the city: anything built or removed marks the land for a re-check.
func watch(sim: Object) -> void:
	_sim = sim
	for sig in [sim.buildings_changed, sim.lots_changed, sim.farms_changed, sim.industry_changed, sim.warehouses_changed,
			sim.parks_changed, sim.network.changed]:
		sig.connect(_mark)


func _mark() -> void:
	if not _dirty:
		_dirty = true
		_dirty_tick = _sim.tick_count if _sim else 0


## Starts a new map: all wild again.
func reset() -> void:
	var touched := _chunks_of(cleared.keys() + _occupied.keys())
	cleared.clear()
	_occupied.clear()
	_sources.clear()
	_newest.clear()
	_touched.clear()
	_mark()
	if not touched.is_empty():
		changed.emit(touched)


## Re-checks what the city sits on, if anything changed. Land that was built
## on and isn't any more starts growing back from the moment it was cleared.
## Only things that were added or removed are looked at, so a big city stays
## cheap.
func update(sim: Object) -> void:
	# Landfills, recycling and cemeteries grow on their own, without a signal.
	if sim.hubs.version != _hubs_version:
		_hubs_version = sim.hubs.version
		_mark()
	if not _dirty:
		return
	_dirty = false
	var now := sources(sim)
	var touched := {}
	for key in _sources.keys():
		if now.has(key):
			continue
		for c in _sources[key]:
			_occupied[c] -= 1
			if _occupied[c] == 0:
				_occupied.erase(c)
				cleared[c] = _dirty_tick
				touched[c] = true
		_sources.erase(key)
	for key in now:
		if _sources.has(key):
			continue
		var cells: Array = now[key].call()
		_sources[key] = cells
		for c in cells:
			_occupied[c] = _occupied.get(c, 0) + 1
			cleared.erase(c)
			touched[c] = true
	if not touched.is_empty():
		var chunks := _chunks_of(touched.keys())
		for ch in chunks:
			_newest.erase(ch)
			_touched[ch] = true
		for c in touched:
			if cleared.has(c):
				var ch := _chunk_of_cell(c)
				_newest[ch] = maxi(_newest.get(ch, 0), cleared[c])
		changed.emit(chunks)


func is_occupied(c: Vector2i) -> bool:
	return _occupied.has(c)


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Everything the city has standing on the land, each under a key that
## changes when it moves, with a Callable that lists its cells: roads with
## their sidewalks and verges, built lots, service buildings, warehouses,
## parks, landfills and cemeteries, farmyards and fields, industry pads and
## lanes. Empty zoned lots keep their trees until something is built there.
static func sources(sim: Object) -> Dictionary:
	var out := {}
	var net: RoadNetwork = sim.network
	for id in net.segments:
		var c := net.curve_of(id)
		var reach := RoadStyle.right_of_way_half(net.segments[id].type) + 1.0
		var key := "r%d %s %s %s %.1f" % [id, c[0].snapped(Vector3.ONE * 0.1), c[1].snapped(Vector3.ONE * 0.1),
			c[2].snapped(Vector3.ONE * 0.1), reach]
		out[key] = func() -> Array:
			var n := maxi(2, int((c[0].distance_to(c[1]) + c[1].distance_to(c[2])) * 0.5))
			return _line_cells(RoadNetwork.sample_curve(c[0], c[1], c[2], n), reach)
	for key in sim.buildings:
		if sim.lots.has(key):
			var poly: PackedVector2Array = sim.lots[key].corners
			out["b%s %s" % [key, poly[0].snapped(Vector2.ONE * 0.1)]] = _poly_cells.bind(poly)
	for id in sim.services.buildings:
		out["s%d" % id] = _poly_cells.bind(sim.services.footprint(id))
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		out["fy%d" % id] = _poly_cells.bind(sim.farms._yard(f))
		out["fd%d %d" % [id, f.drive.size()]] = _line_cells.bind(PackedVector3Array(f.drive), Farms.DRIVE_WIDTH * 0.5 + 1.5)
		for cell in f.cells:
			out["fc%d %s" % [id, cell]] = _poly_cells.bind(Farms.cell_corners(f, cell))
	for id in sim.warehouses.buildings:
		var poly: PackedVector2Array = sim.warehouses.footprint(id)
		out["w%d %s" % [id, poly]] = _poly_cells.bind(poly)
	for id in sim.parks.sites:
		var poly: PackedVector2Array = sim.parks.footprint(id)
		out["p%d %s" % [id, poly]] = _poly_cells.bind(poly)
	for id in sim.hubs.hubs:
		var h: Dictionary = sim.hubs.hubs[id]
		for cell in h.cells:
			out["h%d %s %s" % [id, cell, h.pos]] = _poly_cells.bind(CivicHubs.cell_poly(h, cell))
	for id in sim.industry.sites:
		var s: Dictionary = sim.industry.sites[id]
		out["iy%d" % id] = _poly_cells.bind(sim.industry._yard(s))
		out["id%d %d" % [id, s.drive.size()]] = _line_cells.bind(PackedVector3Array(s.drive), Farms.DRIVE_WIDTH * 0.5 + 1.5)
		for pad in s.pads:
			out["ip%d %s" % [id, pad]] = _poly_cells.bind(Industry.pad_corners(s, pad))
	return out


static func _poly_cells(poly: PackedVector2Array) -> Array:
	var out := []
	if poly.size() < 3:
		return out
	var lo := poly[0]
	var hi := poly[0]
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for z in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, z + 0.5) * CELL, poly):
				out.append(Vector2i(x, z))
	return out


static func _line_cells(pts: PackedVector3Array, reach: float) -> Array:
	var seen := {}
	var r := reach + CELL * 0.5
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var lo := a.min(b) - Vector2(r, r)
		var hi := a.max(b) + Vector2(r, r)
		for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for z in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var m := Vector2(x + 0.5, z + 0.5) * CELL
				if Geometry2D.get_closest_point_to_segment(m, a, b).distance_to(m) <= reach:
					seen[Vector2i(x, z)] = true
	return seen.keys()


static func _chunk_of_cell(c: Vector2i) -> Vector2i:
	return Vector2i(floori(c.x * CELL / CHUNK), floori(c.y * CELL / CHUNK))


static func _chunks_of(cells: Array) -> Array:
	var seen := {}
	for c in cells:
		seen[_chunk_of_cell(c)] = true
	return seen.keys()


## True when this chunk holds land that is still growing back.
func growing_in(chunk: Vector2i, tick: int) -> bool:
	return _newest.has(chunk) and _newest[chunk] > tick - int(Balance.WILD_MATURE_YEARS * TICKS_PER_YEAR)


# --------------------------------------------------------------- the plants

## How wooded and how brushy the land is naturally at a point, 0 to 1 each:
## the forest deposits are the woodlots, and lighter groves, fencerows and
## lone trees are scattered through the open land in between.
static func natural_cover(p: Vector3) -> Array:
	if cover_source.is_valid():
		return cover_source.call(p)
	var wood := Resources.at(Resources.Kind.FOREST, p)
	var grove := smoothstep(0.55, 0.8, Resources.value_noise(Vector2(p.x, p.z) / 140.0, 911))
	var trees := clampf(0.025 + wood * 0.9 + grove * 0.22, 0.0, 0.95)
	# Brush is thickest along woodland edges, thin under a closed canopy.
	var brush := clampf(0.04 + 0.35 * 4.0 * trees * (1.0 - trees) + grove * 0.08, 0.0, 0.6)
	return [trees, brush]


## The wild plants in a square of land at a moment in time. Each is a
## Dictionary: pos, kind (Kind), species (TreeField.Species), size (1 is
## full grown) and tint. Far-off views can leave the brush out.
func plants_in(area: Rect2, tick: int, shrubs := true) -> Array:
	var out := []
	# Natural cover changes over hundreds of metres, so it is worked out on a
	# 16 m lattice and blended in between: much cheaper than per plant.
	var lattice := _cover_lattice(area)
	# Land the city never touched needs no checks against it.
	var built := false
	var m := CELL * 2.0
	for x in range(floori((area.position.x - m) / CHUNK), floori((area.end.x + m) / CHUNK) + 1):
		for z in range(floori((area.position.y - m) / CHUNK), floori((area.end.y + m) / CHUNK) + 1):
			built = built or _touched.has(Vector2i(x, z))
	_layer(out, area, tick, Kind.TREE, TREE_SPACING, 31, lattice, built)
	if shrubs:
		_layer(out, area, tick, Kind.SHRUB, SHRUB_SPACING, 57, lattice, built)
	return out


const LATTICE := 16.0


func _cover_lattice(area: Rect2) -> Dictionary:
	var lo := Vector2i(floori(area.position.x / LATTICE), floori(area.position.y / LATTICE))
	var hi := Vector2i(floori(area.end.x / LATTICE) + 1, floori(area.end.y / LATTICE) + 1)
	var grid := {}
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			grid[Vector2i(x, z)] = natural_cover(Vector3(x * LATTICE, 0.0, z * LATTICE))
	return grid


static func _blend(lattice: Dictionary, p: Vector3) -> Array:
	var f := Vector2(p.x, p.z) / LATTICE
	var i := Vector2i(floori(f.x), floori(f.y))
	var t := f - Vector2(i)
	var a: Array = lattice[i]
	var b: Array = lattice[i + Vector2i(1, 0)]
	var c: Array = lattice[i + Vector2i(0, 1)]
	var d: Array = lattice[i + Vector2i(1, 1)]
	return [lerpf(lerpf(a[0], b[0], t.x), lerpf(c[0], d[0], t.x), t.y),
		lerpf(lerpf(a[1], b[1], t.x), lerpf(c[1], d[1], t.x), t.y)]


func _layer(out: Array, area: Rect2, tick: int, kind: int, spacing: float, salt: int, lattice: Dictionary, built: bool) -> void:
	for ix in range(floori(area.position.x / spacing), floori(area.end.x / spacing) + 1):
		for iz in range(floori(area.position.y / spacing), floori(area.end.y / spacing) + 1):
			var i := Vector2i(ix, iz)
			var p := Vector3((ix + 0.15 + 0.7 * _h(i, salt)) * spacing, 0.0, (iz + 0.15 + 0.7 * _h(i, salt + 1)) * spacing)
			# Each spot belongs to exactly one area, so chunks never draw it twice.
			if not area.has_point(Vector2(p.x, p.z)):
				continue
			var plant := plant_at(p, i, kind, salt, tick, _blend(lattice, p), built)
			if not plant.is_empty():
				out.append(plant)


## The plant (or none) growing at one spot.
func plant_at(p: Vector3, i: Vector2i, kind: int, salt: int, tick: int, cover: Array, built := true) -> Dictionary:
	var c := cell_of(p)
	if built:
		# Trees keep their crowns clear of roads and roofs next door.
		var reach := 1 if kind == Kind.TREE else 0
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				if _occupied.has(c + Vector2i(dx, dz)):
					return {}
	var roll := _h(i, salt + 2)
	var size := 0.9 + 0.4 * _h(i, salt + 3)
	var regrown := built and cleared.has(c)
	if regrown:
		var years := float(tick - int(cleared[c])) / TICKS_PER_YEAR
		var grow := clampf((years - Balance.WILD_TREE_YEARS) / (Balance.WILD_MATURE_YEARS - Balance.WILD_TREE_YEARS), 0.0, 1.0)
		var brush_grow := clampf((years - Balance.WILD_BRUSH_YEARS) / Balance.WILD_BRUSH_YEARS, 0.0, 1.0)
		if kind == Kind.TREE:
			if roll >= maxf(cover[0], Balance.WILD_REGROW_TREES) or years < Balance.WILD_BRUSH_YEARS:
				return {}
			if years < Balance.WILD_TREE_YEARS:
				# A tree to be is still a thicket of suckers and seedlings.
				kind = Kind.SHRUB
				size *= 0.35 + 0.5 * brush_grow
			else:
				size *= lerpf(0.12, 1.0, grow)
		else:
			# Brush crowds a young lot, then thins in the shade of the trees.
			if roll >= lerpf(Balance.WILD_REGROW_BRUSH, cover[1], grow) or years < Balance.WILD_BRUSH_YEARS * 0.5:
				return {}
			size *= 0.3 + 0.7 * brush_grow
	elif roll >= (cover[0] if kind == Kind.TREE else cover[1]):
		return {}
	var pick := _h(i, salt + 4)
	var sp: int
	if kind == Kind.SHRUB:
		sp = TreeField.Species.CRABAPPLE
	elif regrown:
		# Pioneer trees: red cedar, black locust and box elder come first.
		sp = TreeField.Species.SPRUCE if pick < 0.3 else (TreeField.Species.LOCUST if pick < 0.65 \
			else (TreeField.Species.MAPLE if pick < 0.9 else TreeField.Species.OAK))
	else:
		# Southern Indiana woods: oak-hickory with maples, a few cedars.
		sp = TreeField.Species.OAK if pick < 0.4 else (TreeField.Species.MAPLE if pick < 0.75 \
			else (TreeField.Species.LOCUST if pick < 0.9 else TreeField.Species.SPRUCE))
	var tint: Color = TreeField.LEAF[sp]
	if kind == Kind.SHRUB:
		tint = Color("#4b5a22")  # sumac and dogwood: duller, yellower than yard trees
	var shade := _h(i, salt + 5)
	tint = tint.lightened(shade * 0.12) if shade < 0.5 else tint.darkened((shade - 0.5) * 0.25)
	return {"pos": p, "kind": kind, "species": sp, "size": size, "tint": tint}


static func _h(i: Vector2i, salt: int) -> float:
	return Resources.hash01(i, salt)


# ------------------------------------------------------------------ saving

## Only cleared land is saved, grouped by the tick it was cleared.
func to_dict() -> Dictionary:
	var by_tick := {}
	var cells := cleared.keys()
	cells.sort()
	for c in cells:
		var t := str(cleared[c])
		if not by_tick.has(t):
			by_tick[t] = []
		by_tick[t].append_array([c.x, c.y])
	return {"cleared": by_tick}


func from_dict(d: Dictionary) -> void:
	var touched := cleared.keys()
	cleared.clear()
	var by_tick: Dictionary = d.get("cleared", {})
	for t in by_tick:
		var flat: Array = by_tick[t]
		for k in range(0, flat.size() - 1, 2):
			cleared[Vector2i(int(flat[k]), int(flat[k + 1]))] = int(t)
	# What the loaded city stands on is worked out fresh, not saved.
	_occupied.clear()
	_sources.clear()
	_newest.clear()
	_touched.clear()
	for c in cleared:
		var ch := _chunk_of_cell(c)
		_newest[ch] = maxi(_newest.get(ch, 0), cleared[c])
		_touched[ch] = true
	_dirty = true
	touched.append_array(cleared.keys())
	changed.emit(_chunks_of(touched))
