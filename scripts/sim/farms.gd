class_name Farms
extends RefCounted
## Farmland, Cities: Skylines 2 style with one twist from Brawn: outline an
## area as farmland with nodes, place a farmhouse in it, and the farm buys
## the fields around it as it makes money (and sells them if it struggles).
##
## Soil never wears out: every spot keeps its own fertility forever.
## Prices follow Midwest figures: corn and soybeans, about $10,000 an acre.

const CELL := 40.0                 # one field cell: 40 m square, about 0.4 acre
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
## One crop price cycle, in game days (a game day settles a month: 4 years).
const PRICE_CYCLE_DAYS := 48.0
## Farms decide to buy or sell land this often, in ticks (6 game hours).
const DECIDE_EVERY := 360

## Painted farmland: Vector2i cell -> true.
var area := {}
## Farms: id -> {pos, dir, crop, cells: Array of Vector2i, loss_streak}
var farms := {}
var _next_id := 1
## Set by the city each time farms decide: the industrial property tax rate
## (percent) the land pays.
var tax_rate := 1.5
## Crop prices against normal (1.0). They rise and fall over the years like
## real commodity cycles, so farms grow in good years and sell in bad ones.
var price := 1.0


## How good the soil is at a point, about 0.45 to 1 (mostly good Midwest
## loam, with poorer patches). Fixed forever: soil never
## runs out.
static func fertility(cell: Vector2i) -> float:
	var f := 0.0
	var amp := 0.5
	var scale := 9.0
	for octave in 3:
		f += amp * _value_noise(Vector2(cell) / scale, octave)
		amp *= 0.5
		scale *= 0.5
	return clampf(0.45 + f * 0.7, 0.35, 1.0)


## Crop price on a given game day: up to 15% above or below normal.
static func price_on(day: float) -> float:
	return 1.0 + 0.15 * sin(TAU * day / PRICE_CYCLE_DAYS)


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


## Marks every cell whose centre is inside the outline as farmland (or clears
## it). Returns how many cells changed.
func paint_polygon(points: Array, on: bool) -> int:
	if points.size() < 3:
		return 0
	var poly := PackedVector2Array()
	var box := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p in points:
		poly.append(Vector2(p.x, p.z))
		box = box.expand(Vector2(p.x, p.z))
	if box.size.x * box.size.y > 4_000_000.0:  # 2 km square at most
		return 0
	var changed := 0
	for x in range(floori(box.position.x / CELL), ceili(box.end.x / CELL) + 1):
		for z in range(floori(box.position.y / CELL), ceili(box.end.y / CELL) + 1):
			var c := Vector2i(x, z)
			var mid := cell_center(c)
			if not Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z), poly):
				continue
			if on and not area.has(c):
				area[c] = true
				changed += 1
			elif not on and area.has(c):
				area.erase(c)
				changed += 1
				for id in farms:
					farms[id].cells.erase(c)
	return changed


func add_farm(pos: Vector3, dir: Vector3, crop: String) -> int:
	var id := _next_id
	_next_id += 1
	farms[id] = {"pos": pos, "dir": dir, "crop": crop, "cells": [], "loss_streak": 0}
	return id


## The farm whose farmhouse yard holds this point, or -1.
func farm_at(p: Vector3) -> int:
	for id in farms:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _yard(farms[id])):
			return id
	return -1


## True when a point is on a farmhouse yard (no lots there).
func covers(p: Vector3) -> bool:
	return farm_at(p) != -1


func owner_of(c: Vector2i) -> int:
	for id in farms:
		if c in farms[id].cells:
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
	var km := cell_center(c).distance_to(Vector3(f.pos.x, 0.0, f.pos.z)) / 1000.0
	var gross: float = GROSS_PER_ACRE[f.crop] * fertility(c) * price
	var tax := LAND_PER_ACRE * AG_ASSESSMENT * tax_rate / 100.0
	return (gross - COST_PER_ACRE[f.crop] - COST_PER_ACRE_PER_KM * km - tax) * ACRES_PER_CELL


## Every farm decides whether to buy the best field next to its land (if that
## field would pay and the farm is making money) or sell its worst one (if it
## keeps losing money). Farms finance land like real ones do, so profit, not
## cash in hand, decides.
func decide(usable: Callable) -> bool:
	var changed := false
	var ids := farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = farms[id]
		var profit := yearly_profit(id)
		var best := Vector2i.MAX
		var best_profit := 0.0
		if f.cells.size() < MAX_CELLS:
			for c in _frontier(f):
				if not usable.call(c) or owner_of(c) != -1:
					continue
				var p := field_profit(f, c)
				if p > best_profit or (p == best_profit and best != Vector2i.MAX and _less(c, best)):
					best = c
					best_profit = p
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


## Farmland next to the farm's fields (or around the farmhouse to start).
func _frontier(f: Dictionary) -> Array:
	var out := []
	var seen := {}
	var from: Array = f.cells.duplicate()
	if from.is_empty():
		var home := cell_of(f.pos)
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				from.append(home + Vector2i(dx, dz))
		for c in from:
			if area.has(c):
				out.append(c)
		return out
	for c in from:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if area.has(n) and not seen.has(n) and not n in f.cells:
				seen[n] = true
				out.append(n)
	return out


static func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


func _yard(f: Dictionary) -> PackedVector2Array:
	var side := Vector3(-f.dir.z, 0.0, f.dir.x)
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = f.pos + side * FARMHOUSE_SIZE.x * 0.5 * s.x + f.dir * FARMHOUSE_SIZE.y * 0.5 * s.y
		out.append(Vector2(p.x, p.z))
	return out


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
	var cells := []
	for c in area:
		cells.append([c.x, c.y])
	var fs := {}
	for id in farms:
		var f: Dictionary = farms[id]
		var owned := []
		for c in f.cells:
			owned.append([c.x, c.y])
		fs[str(id)] = {"pos": [f.pos.x, f.pos.z], "dir": [f.dir.x, f.dir.z], "crop": f.crop,
			"cells": owned, "loss": f.loss_streak}
	return {"area": cells, "farms": fs, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	area.clear()
	farms.clear()
	for c in d.get("area", []):
		area[Vector2i(int(c[0]), int(c[1]))] = true
	for k in d.get("farms", {}):
		var f: Dictionary = d.farms[k]
		var owned := []
		for c in f.cells:
			owned.append(Vector2i(int(c[0]), int(c[1])))
		farms[int(k)] = {"pos": Vector3(f.pos[0], 0.0, f.pos[1]),
			"dir": Vector3(f.dir[0], 0.0, f.dir[1]).normalized(), "crop": str(f.crop),
			"cells": owned, "loss_streak": int(f.get("loss", 0))}
	_next_id = int(d.get("next_id", 1))
