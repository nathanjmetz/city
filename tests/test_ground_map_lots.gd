extends SceneTree
## Run: godot --headless -s tests/test_ground_map_lots.gd
## The ground map, step 3, lots and buildings (docs/spec-ground-map.md;
## Nathan, 2026-10-29: "They run right underneath the buildings."):
##   - _lot_blocked asks the ground map first, and answers exactly as asking
##     every system does: for every lot of both test towns and the big one,
##     the lots moved about, after a road is built and the sites filed
##     again, and after the sites' map packs itself (an item with no boxes,
##     filed as no claim, never takes another's place);
##   - lots don't share ground (but for the few KNOWN), built twice or
##     saved and loaded the same;
##   - a lot check with nothing changed hands back the very lots.

const Audit := preload("res://tools/overlap_audit.gd")
## Pairs of lots each town still has sharing ground: a corner more than
## half a metre in, left as the planner cut it (tests/test_overlaps.gd).
const SHARED := {"small": 1, "county_small": 1}

var _failed := false


func _initialize() -> void:
	for name in ["small", "county_small"]:
		var sim := Audit.town(name)
		_check_blocked(name, sim, true)
		_check_overlaps(name, sim)
		if name == "small":
			_check_refile(sim)
			_check_same(sim)
			_check_stable(sim)
	_check_blocked("perf_big", Audit.town("perf_big"), true)
	_check_compaction()
	quit(1 if _failed else 0)


## The ground map's answer is every system's answer, for every lot (and,
## with `moved`, three moved copies of each).
func _check_blocked(town: String, sim: CitySim, moved: bool) -> void:
	GroundMap.of(sim).file_sites(LotGround.items(sim))
	var r := _compare(sim, moved)
	_check(r[2].is_empty() and r[1] > 0, "%s: the ground map's lot check answers as every system does (%d asked, %d kept off) %s" % [
		town, r[0], r[1], r[2]])


## [asked, kept off, the first lots where the two answers differ].
static func _compare(sim: CitySim, moved: bool) -> Array:
	var asked := 0
	var blocked := 0
	var differ := []
	var keys := sim.lots.keys()
	keys.sort()
	var shifts := [Vector3.ZERO, Vector3(15.0, 0.0, 0.0), Vector3(0.0, 0.0, -20.0), Vector3(-40.0, 0.0, 35.0)] if moved else [Vector3.ZERO]
	for key in keys:
		for shift in shifts:
			var lot: Dictionary = sim.lots[key].duplicate()
			var poly := PackedVector2Array()
			for q in lot.corners:
				poly.append(q + Vector2(shift.x, shift.z))
			lot.corners = poly
			for f in ["pos", "front", "zone_pt"]:
				lot[f] = lot[f] + shift
			sim._sites_filed = true
			var fast := sim._lot_blocked(lot)
			sim._sites_filed = false
			var full := sim._lot_blocked(lot)
			asked += 1
			if full:
				blocked += 1
			if fast != full and differ.size() < 3:
				differ.append("%s %s" % [key, shift])
	return [asked, blocked, differ]


## A road built through the middle of town, the town run on, the sites filed
## again as the next lot check does: the same answers.
func _check_refile(sim: CitySim) -> void:
	sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [-60.0, 110.0], "dir": [0.0, 1.0]})
	sim.apply({"type": "build_road", "start": [-150.0, 35.0], "ctrl": [0.0, 45.0], "end": [150.0, 35.0]})
	for i in 20:
		sim.tick()
	GroundMap.of(sim).file_sites(LotGround.items(sim))
	var r := _compare(sim, true)
	_check(r[2].is_empty(), "after a new road, a fire station and 20 ticks, filed again: the same answers (%d asked) %s" % [r[0], r[2]])


## The sites' map packed after a thousand refilings, an item with no boxes
## among them: every site still answers, none freed in its place.
func _check_compaction() -> void:
	var g := GroundMap.new()
	var items := {"reserves": [hash([]), []], "a": [1, [Rect2(0.0, 0.0, 10.0, 10.0)]], "b": [2, [Rect2(100.0, 0.0, 10.0, 10.0)]],
		"water:1": [3, []]}
	g.file_sites(items)
	var packed := false
	for i in 1200:
		# "c" changes every time: taken back and filed again.
		items["c"] = [100 + i, [Rect2(200.0, 0.0, 10.0, 10.0)]]
		var before := g._sites._owner.size()
		g.file_sites(items)
		packed = packed or g._sites._owner.size() < before
	var ok := g.sites_near(Rect2(2.0, 2.0, 1.0, 1.0)) and g.sites_near(Rect2(102.0, 2.0, 1.0, 1.0)) \
		and g.sites_near(Rect2(202.0, 2.0, 1.0, 1.0)) and not g.sites_near(Rect2(50.0, 50.0, 1.0, 1.0))
	# Changing the empty items takes nothing else with it.
	items["reserves"] = [hash(["painted"]), []]
	items["water:1"] = [hash(["more"]), []]
	g.file_sites(items)
	ok = ok and g.sites_near(Rect2(2.0, 2.0, 1.0, 1.0)) and g.sites_near(Rect2(102.0, 2.0, 1.0, 1.0)) \
		and g.sites_near(Rect2(202.0, 2.0, 1.0, 1.0))
	_check(packed and ok and int(g._site_by["reserves"][1]) == -1,
		"the sites' map packs itself after 1,200 refilings and an item with no boxes never frees another's claim")


## Lots don't share ground but for the few known.
func _check_overlaps(town: String, sim: CitySim) -> void:
	var pairs := _overlaps(sim)
	_check(pairs.size() <= int(SHARED[town]), "%s: of its %d lots, %d pairs share ground (at most %d) %s" % [town, sim.lots.size(),
		pairs.size(), int(SHARED[town]), pairs.slice(0, 3)])


static func _overlaps(sim: CitySim) -> Array:
	var keys := sim.lots.keys()
	keys.sort()
	var out := []
	for i in keys.size():
		var a: Dictionary = sim.lots[keys[i]]
		for j in range(i + 1, keys.size()):
			var b: Dictionary = sim.lots[keys[j]]
			if a.pos.distance_to(b.pos) < 90.0 and GroundMap.overlap(a.corners, b.corners)[0] >= GroundMap.MIN_AREA["lot|lot*other"]:
				out.append([keys[i], keys[j]])
	return out


## The same lots built twice and after a save and load.
func _check_same(sim: CitySim) -> void:
	var town := Audit.town("small")
	var again := Audit.town("small")
	_check(_lots_sig(again) == _lots_sig(town), "the same town built twice has the same lots (%d)" % town.lots.size())
	var copy := CitySim.new()
	copy.county_rail = true
	copy.from_dict(JSON.parse_string(JSON.stringify(town.to_dict())))
	copy.county_trains.tick(copy)
	for i in 3:
		copy.tick()
	_check(_lots_sig(copy) == _lots_sig(town) and _overlaps(copy).size() <= int(SHARED.small),
		"saved, loaded and run a little, the same lots (%d)" % copy.lots.size())


static func _lots_sig(sim: CitySim) -> int:
	var keys := sim.lots.keys()
	keys.sort()
	return hash(keys.map(func(k): return [k, sim.lots[k].corners]))


## A check with nothing changed hands back the very lots.
func _check_stable(sim: CitySim) -> void:
	var trimmed := 0
	for key in sim._lot_trims:
		if not is_same(sim._lot_trims[key][0], sim._lot_trims[key][2]):
			trimmed += 1
	var before := {}
	for k in sim.lots:
		before[k] = sim.lots[k]
	sim._lots_dirty = true
	sim._refresh()
	var same := true
	for k in before:
		same = same and sim.lots.has(k) and is_same(sim.lots[k], before[k])
	_check(same and sim.lots.size() == before.size(), "a lot check with nothing changed keeps every lot as it was (%d trimmed off a neighbour)" % trimmed)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
