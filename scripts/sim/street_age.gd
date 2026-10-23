class_name StreetAge
extends RefCounted
## Streets wear out (Brawn's mayor play, D1; the Strong Towns "enemy" in
## design/enemy-and-long-hours.md). Every paved street is resurfaced about
## STREET_LIFE_YEARS after it was built or last resurfaced, and the town
## pays for it then: a street a builder hands over is free today and a bill
## in 25 years. Towns that grew fast meet the whole bill at once, as real
## towns do when a boom's streets all come due together.
##
## Real: an asphalt street lasts about 20 to 30 years before it needs a mill
## and overlay (FHWA pavement life studies); Indiana towns pay about $25 to
## $35 a square yard for it (INDOT unit prices), about $130 a lane-metre.
##
## Ages are kept on a coarse grid (STREET_AGE_CELL), so a street split by a
## new junction keeps its age. Worked out once a month, a sum over the
## streets; the forecast for the Economy page comes from the same pass.

## Grid square -> tick its streets were built or last resurfaced.
var paved := {}
## Resurfacing paid in the last 12 months, month by month (newest last).
var paid: Array = []
## What comes due in each of the next STREET_FORECAST_YEARS years
## (not saved: worked out each month).
var forecast: Array = []
## Each street's lane-metres and the squares it runs through (not saved:
## from its shape).
var _lane_m := {}
var _cells := {}
var _rev := -1


## Once a game month: notes new streets, resurfaces the ones that are due
## and bills the town, and works out what comes due next. Returns what was
## paid.
func month(sim) -> int:
	var now := int(sim.tick_count)
	var life := _life_ticks()
	var fresh: bool = paved.is_empty()
	if _rev != int(sim.network.revision):
		_rev = int(sim.network.revision)
		var live := {}
		var ids: Array = sim.network.segments.keys()
		ids.sort()
		for id in ids:
			live[id] = true
			if _lane_m.has(id):
				continue
			_measure(sim, id)
			# Every square along a new street takes its age, unless an older
			# street was there (one split by a new junction keeps its age).
			# Every street in an older save was built over the years before.
			_note(id, now, fresh and now > 2 * _year_ticks() / 12)
		for id in _lane_m.keys():
			if not live.has(id):
				_lane_m.erase(id)
				_cells.erase(id)
	var years := Balance.STREET_FORECAST_YEARS
	forecast = []
	forecast.resize(years)
	forecast.fill(0)
	var due := 0
	var done := {}
	var redone := []
	var ids: Array = sim.network.segments.keys()
	ids.sort()
	for id in ids:
		var cost := repave_cost(float(_lane_m.get(id, 0.0)), int(sim.network.segments[id].type))
		if cost <= 0:
			continue
		var k := cell_of(sim, id)
		var age := now - int(paved.get(k, now))
		if age >= life or done.has(k):
			due += cost
			done[k] = true
			redone.append(id)
			continue
		var y := (life - age) / _year_ticks()
		if y < years:
			forecast[y] += cost
	for id in redone:
		for k in _cells[id]:
			paved[k] = now
	paid.append(due)
	if paid.size() > 12:
		paid = paid.slice(paid.size() - 12)
	return due


## Roads the county built (the highway a town starts on and its links to
## the region): built over the years before, so their ages are spread and
## they don't all come due the same month.
func note_old(sim, ids: Array) -> void:
	for id in ids:
		if sim.network.segments.has(id):
			_measure(sim, id)
			_note(id, int(sim.tick_count), true)


func _note(id: int, now: int, old: bool) -> void:
	for k in _cells[id]:
		if not paved.has(k):
			paved[k] = now - (absi(hash([k.x, k.y])) % _life_ticks() if old else 0)


## Resurfacing paid over the last year.
func paid_this_year() -> int:
	var n := 0
	for v in paid:
		n += int(v)
	return n


## The grid square a street's age is kept in (by its middle).
static func cell_of(sim, id: int) -> Vector2i:
	var s: Dictionary = sim.network.segments[id]
	var a: Vector3 = sim.network.nodes[s.a]
	var b: Vector3 = sim.network.nodes[s.b]
	var m: Vector3 = (a + b) * 0.25 + s.ctrl * 0.5
	return Vector2i(floori(m.x / Balance.STREET_AGE_CELL), floori(m.z / Balance.STREET_AGE_CELL))


## What resurfacing `lane_m` lane-metres of this kind of road costs (gravel
## is regraded from upkeep, not resurfaced).
static func repave_cost(lane_m: float, type: int) -> int:
	if type == RoadStyle.Type.GRAVEL:
		return 0
	return roundi(lane_m * Balance.STREET_REPAVE_PER_LANE_M)


## A street's lane-metres and the squares it runs through, its middle first.
func _measure(sim, id: int) -> void:
	var c: Array = sim.network.curve_of(id)
	var pts := RoadNetwork.sample_curve(c[0], c[1], c[2], 8)
	var m := RoadNetwork.polyline_length(pts)
	_lane_m[id] = m * float(RoadStyle.TYPES[int(sim.network.segments[id].type)].lanes)
	var cells := [cell_of(sim, id)]
	var n := maxi(2, ceili(m / (Balance.STREET_AGE_CELL * 0.5)))
	for i in n + 1:
		var p: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], float(i) / n)
		var k := Vector2i(floori(p.x / Balance.STREET_AGE_CELL), floori(p.z / Balance.STREET_AGE_CELL))
		if not k in cells:
			cells.append(k)
	_cells[id] = cells


static func _year_ticks() -> int:
	return 12 * 24 * CitySim.TICKS_PER_HOUR


static func _life_ticks() -> int:
	return Balance.STREET_LIFE_YEARS * _year_ticks()


func to_dict() -> Dictionary:
	var keys := paved.keys()
	keys.sort()
	var flat := []
	for k in keys:
		flat.append_array([k.x, k.y, paved[k]])
	return {"paved": flat, "paid": paid}


func from_dict(d: Dictionary) -> void:
	paved.clear()
	_lane_m.clear()
	_cells.clear()
	_rev = -1
	forecast = []
	var flat: Array = d.get("paved", [])
	for i in range(0, flat.size() - 2, 3):
		paved[Vector2i(int(flat[i]), int(flat[i + 1]))] = int(flat[i + 2])
	paid = Array(d.get("paid", [])).map(func(x): return int(x))
