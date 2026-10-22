class_name Farms
extends RefCounted
## Farmland, Cities: Skylines 2 style with one twist from Brawn: outline an
## area as farmland with nodes, place a farmhouse in it, and the farm buys
## the fields around it as it makes money (and sells them if it struggles).
##
## No world grid: each farm lays its fields out square to its own farmhouse
## (which faces its road), the way Midwest fields follow the road they're
## on, and they're drawn clipped to the painted outline. A new farm puts up
## its barn first, then plants the fields next to the farmyard and works
## outward. Every farmhouse gets a winding gravel lane out to its road.
##
## Soil never wears out: every spot keeps its own fertility forever.
## Prices follow Midwest figures: corn and soybeans, about $10,000 an acre.

const CELL := 40.0                 # one field cell: 40 m square, about 0.4 acre
## The longest farm lane a farmhouse can have out to its road.
const MAX_DRIVE := 250.0
const DRIVE_WIDTH := 4.0           # a one-lane gravel farm lane
const ACRES_PER_CELL := CELL * CELL / 4046.86
const FARMHOUSE_SIZE := Vector2(36, 40)  # house, barn and silo yard
const FARMHOUSE_COST := 350_000
const LAND_PER_ACRE := 10_000      # Iowa farmland is about $11,000 an acre
## Farmland is taxed on what it produces, not its sale price (US "use value"
## assessment), roughly a quarter of market value.
const AG_ASSESSMENT := 0.25
## Yearly gross per acre at full fertility: corn about 180 bu x $4.50.
const GROSS_PER_ACRE := {"corn": 810.0, "soybeans": 600.0}
## Yearly cost per acre (seed, fuel, fertiliser, machinery), plus more the
## farther a field is from the farmhouse (driving the combine out to it).
## USDA operating costs per acre (land already owned): soybeans need no
## nitrogen, so they cost less to grow.
const COST_PER_ACRE := {"corn": 420.0, "soybeans": 280.0}
const COST_PER_ACRE_PER_KM := 260.0
## Jobs: the farm family (2) plus a hired hand per this many cells (~40 acres).
const CELLS_PER_WORKER := 100
const MAX_CELLS := 400
## How much a field next to more of the farm's own land is preferred, in
## dollars a year per neighbouring field.
const COMPACT_BONUS := 25.0
## One crop price cycle, in game days (a game day settles a month: 4 years).
const PRICE_CYCLE_DAYS := 48.0
## Farms decide to buy or sell land this often, in ticks (6 game hours).
const DECIDE_EVERY := 360

## Painted farmland: outlines in the order they were drawn, each
## {points: PackedVector2Array, on: bool}. Later outlines win.
var area: Array = []
## Farms: id -> {pos, dir, crop, cells: Array of Vector2i in the farm's own
## frame, loss_streak, barn: bool, drive: Array of Vector3}
var farms := {}
var _next_id := 1
## Set by the city each time farms decide: the industrial property tax rate
## (percent) the land pays.
var tax_rate := 1.5
## Crop prices against normal (1.0). They rise and fall over the years like
## real commodity cycles, so farms grow in good years and sell in bad ones.
var price := 1.0


## How good the soil is at a point, about 0.45 to 1 (mostly good Midwest
## loam, with poorer patches). Fixed forever: soil never runs out.
static func fertility_at(p: Vector3) -> float:
	var f := 0.0
	var amp := 0.5
	var scale := 9.0
	for octave in 3:
		f += amp * _value_noise(Vector2(p.x, p.z) / CELL / scale, octave)
		amp *= 0.5
		scale *= 0.5
	return clampf(0.45 + f * 0.7, 0.35, 1.0)


## Crop price on a given game day: up to 15% above or below normal.
static func price_on(day: float) -> float:
	return 1.0 + 0.15 * sin(TAU * day / PRICE_CYCLE_DAYS)


## The farm's right-hand direction, with its farmhouse facing the road.
static func _right(f: Dictionary) -> Vector3:
	return Vector3(-f.dir.z, 0.0, f.dir.x)


## Centre of field cell c of farm f: cell (0, 0) is the farmyard, j counts
## back from the road and i to the right.
static func cell_center(f: Dictionary, c: Vector2i) -> Vector3:
	var p: Vector3 = f.pos + _right(f) * (c.x * CELL) - f.dir * (c.y * CELL)
	return Vector3(p.x, 0.0, p.z)


## The four corners of a field cell, on the ground plane.
static func cell_corners(f: Dictionary, c: Vector2i) -> PackedVector2Array:
	var mid := cell_center(f, c)
	var r: Vector3 = _right(f) * CELL * 0.5
	var b: Vector3 = -f.dir * CELL * 0.5
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * s.x + b * s.y
		out.append(Vector2(p.x, p.z))
	return out


## True when a point is inside the painted farmland.
func is_farmland(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	var on := false
	for a in area:
		if Geometry2D.is_point_in_polygon(q, a.points):
			on = a.on
	return on


## Adds an outline as farmland (or takes it back out). Fields left outside
## the farmland are given up. Returns true if it was a usable outline.
func paint_polygon(points: Array, on: bool) -> bool:
	if points.size() < 3:
		return false
	var poly := PackedVector2Array()
	var box := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p in points:
		poly.append(Vector2(p.x, p.z))
		box = box.expand(Vector2(p.x, p.z))
	if box.size.x * box.size.y > 4_000_000.0 or absf(_area_of(poly)) < 100.0:  # 2 km square at most
		return false
	area.append({"points": poly, "on": on})
	if not on:
		for id in farms:
			var f: Dictionary = farms[id]
			f.cells = f.cells.filter(func(c): return is_farmland(cell_center(f, c)))
	return true


func add_farm(pos: Vector3, dir: Vector3, crop: String, drive: Array) -> int:
	var id := _next_id
	_next_id += 1
	farms[id] = {"pos": pos, "dir": dir, "crop": crop, "cells": [], "loss_streak": 0,
		"barn": false, "drive": drive}
	return id


## A winding gravel lane from the farmhouse's front door out to a point on
## its road: a gentle S-bend, different for every farm.
static func make_drive(pos: Vector3, dir: Vector3, road: Vector3) -> Array:
	var start := pos + dir * (FARMHOUSE_SIZE.y * 0.5)
	start.y = 0.0
	var end := Vector3(road.x, 0.0, road.z)
	var span := end - start
	var side := Vector3(-span.z, 0.0, span.x).normalized()
	var bend := (_hash01(Vector2i(roundi(pos.x), roundi(pos.z)), 7) * 2.0 - 1.0)
	bend = signf(bend) * (0.5 + absf(bend) * 0.5) * span.length() * 0.16
	var p1 := start + span / 3.0 + side * bend
	var p2 := start + span * 2.0 / 3.0 - side * bend * 0.8
	var out := []
	var n := maxi(6, int(span.length() / 8.0))
	for k in n + 1:
		var t := float(k) / n
		var u := 1.0 - t
		out.append(start * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + end * t * t * t)
	return out


## The farm whose farmhouse yard or lane holds this point, or -1.
func farm_at(p: Vector3) -> int:
	for id in farms:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _yard(farms[id])):
			return id
		if _near_drive(farms[id], p, DRIVE_WIDTH * 0.5 + 2.0):
			return id
	return -1


## True when a point is on a farmyard or farm lane (no lots there).
func covers(p: Vector3) -> bool:
	return farm_at(p) != -1


## The farm whose field holds this point, or -1.
func field_at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in farms:
		var f: Dictionary = farms[id]
		var local := _local(f, p)
		var c := Vector2i(roundi(local.x / CELL), roundi(local.y / CELL))
		if c in f.cells and Geometry2D.is_point_in_polygon(q, cell_corners(f, c)):
			return id
	return -1


## Acres farmed in the whole town.
func total_acres() -> float:
	var n := 0
	for id in farms:
		n += farms[id].cells.size()
	return n * ACRES_PER_CELL


func jobs() -> int:
	var total := 0
	for id in farms:
		total += 2 + farms[id].cells.size() / CELLS_PER_WORKER
	return total


## A farm's yearly profit from its fields as they stand.
func yearly_profit(id: int) -> float:
	var f: Dictionary = farms[id]
	var total := 0.0
	for c in f.cells:
		total += field_profit(f, c)
	return total


## One field's yearly profit: what it grows, less farming costs and the
## property tax on the land. A family with modern machinery works a farm
## this size, so it doesn't wait on hired hands.
func field_profit(f: Dictionary, c: Vector2i) -> float:
	var mid := cell_center(f, c)
	var km := mid.distance_to(Vector3(f.pos.x, 0.0, f.pos.z)) / 1000.0
	var gross: float = GROSS_PER_ACRE[f.crop] * fertility_at(mid) * price
	var tax := LAND_PER_ACRE * AG_ASSESSMENT * tax_rate / 100.0
	return (gross - COST_PER_ACRE[f.crop] - COST_PER_ACRE_PER_KM * km - tax) * ACRES_PER_CELL


## Every farm takes its next step. A new farm puts up its barn first. Then
## it buys the best field next to its land (if that field would pay and the
## farm is making money) or sells its worst one (if it keeps losing money).
## Farms finance land like real ones do, so profit, not cash in hand,
## decides. `usable(centre, corners)` says if the city leaves the ground
## free (no road, lot or building).
func decide(usable: Callable) -> bool:
	var changed := false
	var ids := farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = farms[id]
		if not f.barn:
			f.barn = true
			changed = true
			continue
		var profit := yearly_profit(id)
		var best := Vector2i.MAX
		var best_profit := 0.0
		if f.cells.size() < MAX_CELLS:
			for c in _frontier(f):
				if not _free(id, f, c, usable):
					continue
				var p := field_profit(f, c)
				if p <= 0.0:
					continue
				# Farmers square off their fields: land that rounds out what
				# they already work beats a slightly richer odd corner.
				var score := p + COMPACT_BONUS * _owned_neighbors(f, c)
				if score > best_profit or (score == best_profit and best != Vector2i.MAX and _less(c, best)):
					best = c
					best_profit = score
		var worst := Vector2i.MAX
		for c in f.cells:
			if worst == Vector2i.MAX or field_profit(f, c) < field_profit(f, worst):
				worst = c
		if worst != Vector2i.MAX and field_profit(f, worst) < 0.0:
			# A field that loses money twice running is sold off.
			f.loss_streak += 1
			if f.loss_streak >= 2:
				f.cells.erase(worst)
				f.loss_streak = 0
				changed = true
		elif best != Vector2i.MAX and (f.cells.is_empty() or profit >= 0.0):
			f.cells.append(best)
			f.loss_streak = 0
			changed = true
	return changed


## Can farm `id` plant cell c: farmland, clear of its lane, other farms and
## anything the city has built?
func _free(id: int, f: Dictionary, c: Vector2i, usable: Callable) -> bool:
	var mid := cell_center(f, c)
	if not is_farmland(mid):
		return false
	var corners := cell_corners(f, c)
	if _drive_crosses(f, corners):
		return false
	for other in farms:
		if other == id:
			continue
		var o: Dictionary = farms[other]
		if o.pos.distance_to(mid) > CELL * (sqrt(float(o.cells.size())) * 2.0 + 4.0) + MAX_DRIVE:
			continue
		var inset := PackedVector2Array()
		for p in corners:
			inset.append(Vector2(mid.x, mid.z).lerp(p, 0.8))
		inset.append(Vector2(mid.x, mid.z))
		for q in inset:
			var pt := Vector3(q.x, 0.0, q.y)
			if field_at(pt) == other or farm_at(pt) == other:
				return false
	return usable.call(mid, corners)


## Cells next to the farm's fields, or next to the farmyard to start, so
## the fields always spread out from the farmhouse.
func _frontier(f: Dictionary) -> Array:
	var out := []
	var seen := {Vector2i.ZERO: true}
	for c in f.cells:
		seen[c] = true
	var from: Array = f.cells.duplicate()
	from.append(Vector2i.ZERO)
	for c in from:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n):
				seen[n] = true
				out.append(n)
	return out


static func _owned_neighbors(f: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if (c + d) in f.cells or c + d == Vector2i.ZERO:
			n += 1
	return n


static func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## A point in the farm's own frame: x to the right, y back from the road.
static func _local(f: Dictionary, p: Vector3) -> Vector2:
	var d: Vector3 = p - f.pos
	return Vector2(d.dot(_right(f)), -d.dot(f.dir))


func _yard(f: Dictionary) -> PackedVector2Array:
	var side := _right(f)
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = f.pos + side * FARMHOUSE_SIZE.x * 0.5 * s.x + f.dir * FARMHOUSE_SIZE.y * 0.5 * s.y
		out.append(Vector2(p.x, p.z))
	return out


static func _near_drive(f: Dictionary, p: Vector3, reach: float) -> bool:
	var drive: Array = f.drive
	var q := Vector2(p.x, p.z)
	for i in drive.size() - 1:
		var a := Vector2(drive[i].x, drive[i].z)
		var b := Vector2(drive[i + 1].x, drive[i + 1].z)
		if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < reach:
			return true
	return false


## True when the farm's lane runs through (or right beside) a field cell.
static func _drive_crosses(f: Dictionary, corners: PackedVector2Array) -> bool:
	var grown := PackedVector2Array()
	var mid := (corners[0] + corners[2]) * 0.5
	for p in corners:
		grown.append(mid + (p - mid) * (1.0 + (DRIVE_WIDTH + 2.0) / CELL))
	var drive: Array = f.drive
	for i in drive.size():
		if Geometry2D.is_point_in_polygon(Vector2(drive[i].x, drive[i].z), grown):
			return true
	return false


static func _area_of(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5


## Smooth random value at a point, the same every time.
static func _value_noise(p: Vector2, octave: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash01(i, octave)
	var b := _hash01(i + Vector2i(1, 0), octave)
	var c := _hash01(i + Vector2i(0, 1), octave)
	var d := _hash01(i + Vector2i(1, 1), octave)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _hash01(i: Vector2i, salt: int) -> float:
	var h := (i.x * 374761393 + i.y * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10006.0


func to_dict() -> Dictionary:
	var outlines := []
	for a in area:
		var pts := []
		for p in a.points:
			pts.append([p.x, p.y])
		outlines.append({"points": pts, "on": a.on})
	var fs := {}
	for id in farms:
		var f: Dictionary = farms[id]
		var owned := []
		for c in f.cells:
			owned.append([c.x, c.y])
		var lane := []
		for p in f.drive:
			lane.append([p.x, p.z])
		fs[str(id)] = {"pos": [f.pos.x, f.pos.z], "dir": [f.dir.x, f.dir.z], "crop": f.crop,
			"cells": owned, "loss": f.loss_streak, "barn": f.barn, "drive": lane, "frame": 2}
	return {"outlines": outlines, "farms": fs, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	area.clear()
	farms.clear()
	for a in d.get("outlines", []):
		var poly := PackedVector2Array()
		for p in a.points:
			poly.append(Vector2(p[0], p[1]))
		area.append({"points": poly, "on": bool(a.on)})
	# Older saves painted farmland in 40 m world squares.
	for c in d.get("area", []):
		var x := float(c[0]) * CELL
		var z := float(c[1]) * CELL
		area.append({"points": PackedVector2Array([Vector2(x, z), Vector2(x + CELL, z),
			Vector2(x + CELL, z + CELL), Vector2(x, z + CELL)]), "on": true})
	for k in d.get("farms", {}):
		var f: Dictionary = d.farms[k]
		var owned := []
		# Fields from before farms had their own frame start over.
		if int(f.get("frame", 1)) == 2:
			for c in f.cells:
				owned.append(Vector2i(int(c[0]), int(c[1])))
		var lane := []
		for p in f.get("drive", []):
			lane.append(Vector3(p[0], 0.0, p[1]))
		farms[int(k)] = {"pos": Vector3(f.pos[0], 0.0, f.pos[1]),
			"dir": Vector3(f.dir[0], 0.0, f.dir[1]).normalized(), "crop": str(f.crop),
			"cells": owned, "loss_streak": int(f.get("loss", 0)), "barn": bool(f.get("barn", true)),
			"drive": lane}
	_next_id = int(d.get("next_id", 1))
