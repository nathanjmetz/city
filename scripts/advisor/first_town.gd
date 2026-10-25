class_name FirstTown
extends RefCounted
## The guided first town (Brawn, 2026-10-23): instead of a vague welcome, the
## game says the plan up front and walks a new player through it in the
## order a real subdivision goes in: streets are platted, the electric co-op
## runs a line and energizes it, a well is drilled and tested, the lots are
## zoned, and builders put up the first houses. Every wait says what the
## crew is doing and shows how far along it is, so it never feels like
## nothing's happening.
##
## Pure logic: which step the town is on follows from the town itself, so a
## player who skips ahead, reloads or builds things in another order lands
## on the right step. FirstTownTour draws it.
##
## Benchmarks: Cities: Skylines 2's tutorial (a docked card per step, the
## button to press lit up), Frostpunk's and Anno 1800's guided openings (one
## goal at a time, the camera taken to it), and Mini Motorways' pulsing
## hints. Not a wall of text: one short line per step.

## The steps, in order. "wait" steps follow a crew; the rest wait on the
## player. "goal" is the line shown in the plan up front.
const STEPS := [
	{"id": "plan", "title": "Let's build your first neighborhood"},
	{"id": "streets", "title": "Lay out a few streets", "goal": "Lay out a few streets"},
	{"id": "yard", "title": "Pick your builder's yard", "goal": "Pick your builder's yard"},
	{"id": "power", "title": "Bring in power", "goal": "Bring in power"},
	{"id": "power_wait", "title": "The line crew's at work", "wait": true},
	{"id": "water", "title": "Bring in water", "goal": "Drill a well for water"},
	{"id": "water_wait", "title": "The driller's at work", "wait": true},
	{"id": "homes", "title": "Zone some homes", "goal": "Zone some homes"},
	{"id": "builders", "title": "Builders are on the way", "wait": true, "goal": "Welcome your first neighbors"},
	{"id": "done", "title": "Welcome to town!"},
]
## A grid this many street crossings deep counts as laid out.
const JUNCTIONS := 4
## The grid the tour suggests: two Midwest town-plat blocks each way
## (GridFill "Town": 400 x 300 ft).
const GRID_PRESET := 5
const BLOCKS := 2


static func index_of(id: String) -> int:
	for i in STEPS.size():
		if STEPS[i].id == id:
			return i
	return -1


## The goals listed in the plan up front.
static func plan() -> Array:
	return STEPS.filter(func(s): return s.has("goal")).map(func(s): return s.goal)


## The first step the town hasn't finished (never "plan", which is the
## player's to dismiss).
static func current(sim: CitySim) -> String:
	if not has_streets(sim):
		return "streets"
	if sim.services.yard() == -1:
		return "yard"
	if utility_placed(sim, "power").is_empty():
		return "power"
	if not utility_on(sim, "power"):
		return "power_wait"
	if utility_placed(sim, "water").is_empty():
		return "water"
	if not utility_on(sim, "water"):
		return "water_wait"
	if not has_homes_zoned(sim):
		return "homes"
	if int(sim.stats.population) <= 0:
		return "builders"
	return "done"


## Street crossings in town (nodes where three or more roads meet).
static func junctions(sim: CitySim) -> int:
	var n := 0
	for id in sim.network.nodes:
		if sim.network.segments_at(id).size() >= 3:
			n += 1
	return n


static func has_streets(sim: CitySim) -> bool:
	return junctions(sim) >= JUNCTIONS


## Service ids supplying a utility, built or going up, oldest first.
static func utility_placed(sim: CitySim, u: String) -> Array:
	var out := []
	var ids := sim.services.buildings.keys()
	ids.sort()
	for id in ids:
		var kind: int = sim.services.buildings[id].kind
		if kind in Services.UTILITIES[u] or (u == "water" and kind == Services.Kind.WATER_UTILITY):
			out.append(id)
	# A power company's yard brings power too, once its plant runs.
	if u == "power" and not sim.power.sites.is_empty():
		out.append(-1)
	return out


## True once one of them is up and running.
static func utility_on(sim: CitySim, u: String) -> bool:
	for id in utility_placed(sim, u):
		if id == -1:
			if not sim.services.plants.is_empty():
				return true
		elif not sim.services.offline.has(id):
			return true
	return false


static func has_homes_zoned(sim: CitySim) -> bool:
	for c in sim.zones.cells:
		if int(sim.zones.cells[c]) == ZoneMap.Zone.RESIDENTIAL:
			return true
	return false


## What the crew on a wait step is doing: {ref, pos, words, total (0-1)},
## or {} when there's nothing going up to show.
static func crew(sim: CitySim, step: String) -> Dictionary:
	match step:
		"power_wait", "water_wait":
			var u := "power" if step == "power_wait" else "water"
			for id in utility_placed(sim, u):
				if id == -1:
					continue
				var st := sim.construction.state("svc:%d" % id, sim.tick_count)
				if not st.is_empty():
					return {"ref": "svc:%d" % id, "pos": sim.services.buildings[id].pos, "words": st.words,
						"total": float(st.total)}
		"builders":
			# The house furthest along.
			var best := {}
			var keys := sim.buildings.keys()
			keys.sort()
			for key in keys:
				if int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
					continue
				var st := sim.construction.state("lot:" + key, sim.tick_count)
				if not st.is_empty() and float(st.total) > float(best.get("total", -1.0)):
					var lot: Dictionary = sim.lots[key]
					best = {"ref": "lot:" + key, "pos": lot.front + lot.normal * 10.0, "words": st.words,
						"total": float(st.total)}
			return best
	return {}


## Where the tour suggests the first grid: [corner, opposite corner], two
## town blocks each way off the end of the road in from the highway, on dry
## land clear of other roads. [] if nowhere fits.
static func grid_spot(sim: CitySim) -> Array:
	var p: Dictionary = GridFill.PRESETS[GRID_PRESET]
	var w: float = p.block * BLOCKS
	var d: float = p.across * BLOCKS
	var anchors := []
	# Dead ends first (the starter road's end), nearest the middle of town.
	var centre := Vector3(sim.streets.main_at.x, 0.0, sim.streets.main_at.y)
	var ends := []
	for id in sim.network.nodes:
		if sim.network.segments_at(id).size() == 1 and not id in sim.region_links:
			ends.append(sim.network.nodes[id])
	ends.sort_custom(func(a, b): return a.distance_to(centre) < b.distance_to(centre))
	anchors.append_array(ends)
	anchors.append(centre + Vector3(0, 0, 40))
	for a in anchors:
		for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var b: Vector3 = a + Vector3(dir.x * w, 0.0, dir.y * d)
			if _clear(sim, a, b):
				return [a, b]
	return []


## Dry land, with no road but the anchor's own running through the inside.
static func _clear(sim: CitySim, a: Vector3, b: Vector3) -> bool:
	for i in 5:
		for j in 5:
			var p := Vector3(lerpf(a.x, b.x, (i + 0.5) / 5.0), 0.0, lerpf(a.z, b.z, (j + 0.5) / 5.0))
			if Terrain.is_water(p.x + sim.terrain_offset.x, p.z + sim.terrain_offset.y):
				return false
			if i > 0 and j > 0 and not sim.network.find_segment_near(p, 25.0, 1.0).is_empty():
				return false
	return true


## A good spot for the builder's yard: beside a street near where the
## streets come in from the highway, so its trucks reach the new blocks.
## Vector3.INF when there's none.
static func yard_spot(sim: CitySim, aim := Vector3.INF) -> Vector3:
	if aim == Vector3.INF:
		aim = Vector3(sim.streets.main_at.x, 0.0, sim.streets.main_at.y)
	for r in [0.0, 40.0, 80.0, 140.0, 220.0]:
		for a in 8:
			var p: Vector3 = aim + Vector3(cos(a * TAU / 8.0), 0.0, sin(a * TAU / 8.0)) * r
			var site := Services.site_near(sim.network, Services.Kind.BUILDER_YARD, p)
			if not site.is_empty() and sim.services.site_problem(sim.network, Services.Kind.BUILDER_YARD, site[0], site[1]) == "":
				return site[0]
	return Vector3.INF


## A good spot beside one of the new streets for a utility (where the
## service tool would put it, and allowed there): along the streets at the
## crossing nearest `aim` (the grid's middle; once the power line is in, its
## spot is taken, so the well goes on the next).
## Vector3.INF when there's none.
static func site_spot(sim: CitySim, u: String, aim := Vector3.INF) -> Vector3:
	var kind: int = Services.Kind.POWER_FEED if u == "power" else Services.Kind.WELL
	if aim == Vector3.INF:
		aim = Vector3(sim.streets.main_at.x, 0.0, sim.streets.main_at.y)
	var crossings := []
	for id in sim.network.nodes:
		if sim.network.segments_at(id).size() >= 3:
			crossings.append(id)
	crossings.sort_custom(func(a, b): return sim.network.nodes[a].distance_to(aim) < sim.network.nodes[b].distance_to(aim))
	for node in crossings.slice(0, 3):
		var segs: Array = sim.network.segments_at(node)
		segs.sort()
		for seg in segs:
			var pts: PackedVector3Array = sim.network.sample_segment(seg, 8)
			var m := pts.size() / 2
			var along: Vector3 = (pts[m + 1] - pts[m - 1]).normalized()
			for side in [1.0, -1.0]:
				var probe: Vector3 = pts[m] + Vector3.UP.cross(along).normalized() * side * 20.0
				var site := Services.site_near(sim.network, kind, probe)
				if site.is_empty() or sim.services.site_problem(sim.network, kind, site[0], site[1]) != "":
					continue
				return site[0]
	return Vector3.INF
