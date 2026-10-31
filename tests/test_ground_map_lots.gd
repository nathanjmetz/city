extends SceneTree
## Run: godot --headless -s tests/test_ground_map_lots.gd
## The ground map, step 3, lots and buildings (docs/spec-ground-map.md;
## Nathan, 2026-10-29: "They run right underneath the buildings."):
##   - _lot_blocked asks the ground map first, and answers exactly as asking
##     every system does, for every lot of both test towns and the lots
##     moved about;
##   - no two lots share ground, built twice or saved and loaded the same;
##   - a lot trimmed off its neighbour stays the same Dictionary from one
##     lot check to the next when nothing changed.

const Audit := preload("res://tools/overlap_audit.gd")

var _failed := false


func _initialize() -> void:
	for name in ["small", "county_small"]:
		var sim := Audit.town(name)
		_check_blocked(name, sim)
		_check_overlaps(name, sim)
		if name == "small":
			_check_same(sim)
			_check_stable(sim)
	quit(1 if _failed else 0)


## The ground map's answer is every system's answer.
func _check_blocked(town: String, sim: CitySim) -> void:
	GroundMap.of(sim).file_sites(LotGround.items(sim))
	var asked := 0
	var blocked := 0
	var differ := []
	var keys := sim.lots.keys()
	keys.sort()
	for key in keys:
		for shift in [Vector3.ZERO, Vector3(15.0, 0.0, 0.0), Vector3(0.0, 0.0, -20.0), Vector3(-40.0, 0.0, 35.0)]:
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
	_check(differ.is_empty() and blocked > 0, "%s: the ground map's lot check answers as every system does (%d asked, %d kept off) %s" % [
		town, asked, blocked, differ])


## No two lots share more than a sliver of ground.
func _check_overlaps(town: String, sim: CitySim) -> void:
	var pairs := _overlaps(sim)
	_check(pairs.is_empty(), "%s: no two of its %d lots share ground %s" % [town, sim.lots.size(), pairs.slice(0, 3)])


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
	var again := Audit.town("small")
	_check(_lots_sig(again) == _lots_sig(sim), "the same town built twice has the same lots (%d)" % sim.lots.size())
	var copy := CitySim.new()
	copy.county_rail = true
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.county_trains.tick(copy)
	for i in 3:
		copy.tick()
	_check(_lots_sig(copy) == _lots_sig(sim) and _overlaps(copy).is_empty(),
		"saved, loaded and run a little, the same lots, none sharing ground (%d)" % copy.lots.size())


static func _lots_sig(sim: CitySim) -> int:
	var keys := sim.lots.keys()
	keys.sort()
	return hash(keys.map(func(k): return [k, sim.lots[k].corners]))


## A check with nothing changed hands back the very lots.
func _check_stable(sim: CitySim) -> void:
	var trimmed := 0
	for key in sim._lot_trims:
		if sim._lot_trims[key][2] != null:
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
