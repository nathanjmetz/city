extends SceneTree
## Run: godot --headless -s tests/test_rail_right_of_way.gd
## The county's real railroads come first, as in a real town (Nathan,
## 2026-10-29: "railroad tracks running right through the city like
## they're just a part of the ground. They run right underneath the
## buildings."): lots and public buildings keep off the right of way
## (CountyRail.ROW_HALF), roads keep back from the track or cross it nearly
## square, grid streets stop short of it, and an older save with a building
## on the track loads and simply loses that lot.

var _failed := false


func _init() -> void:
	# A town grown on the county main line (as tools/overlap_audit.gd "county").
	var c: Dictionary = CountyTrains.corridors()[0]
	var sim := CitySim.new()
	sim.county_rail = true
	sim.terrain_offset = CountyTrains._at(c, 9000.0)
	PerfTown.build(sim, "small")
	var o := sim.terrain_offset
	var on := 0
	for key in sim.lots:
		var reg := PackedVector2Array()
		for q in sim.lots[key].corners:
			reg.append(q + o)
		if CountyRail.poly_distance(reg, CountyRail.ROW_HALF) < CountyRail.ROW_HALF - CitySim.RAIL_LOT_SLACK - 0.01:
			on += 1
	_check(on == 0, "no lot reaches onto the railroad's right of way (%d do)" % on)
	_check(sim.buildings.size() > 200, "the town still grows round it (%d buildings)" % sim.buildings.size())
	_check(sim.county_trains.crossings.size() >= 4, "its streets cross the track at grade crossings (%d)" % sim.county_trains.crossings.size())

	# The same town plans the same with the browser's lighter track drawing
	# and the desktop's (Nathan, 2026-10-29: the browser gets the rail too,
	# so a town plans the same everywhere, as shared regions need).
	_check(CountyRail.drawn(), "the railroads are part of the town on every platform")
	var plans := []
	for light in [0, 1]:
		CountyRail.force_light = light
		var t2 := CitySim.new()
		t2.county_rail = true
		t2.terrain_offset = sim.terrain_offset
		PerfTown.build(t2, "small")
		var lots2 := {}
		for key in t2.lots:
			lots2[key] = t2.lots[key].corners
		plans.append([lots2, t2.buildings.keys(), t2.county_trains.crossings.map(func(x): return [x.seg, x.pos]),
			t2._rail_sites().keys(), CountyRail.light()])
	CountyRail.force_light = -1
	_check(plans[0][4] != plans[1][4], "(the test draws it both ways)")
	_check(plans[0][0] == plans[1][0], "the lots are the same with and without the desktop's track drawing (%d, %d)" % [plans[0][0].size(), plans[1][0].size()])
	_check(plans[0][1] == plans[1][1] and plans[0][2] == plans[1][2] and plans[0][3] == plans[1][3],
		"and so are the buildings, the grade crossings and the right of way")

	# Roads in open country on the same line.
	var at := CountyTrains._at(c, 14000.0)
	var n := CountyRail.near(at.x, at.y, 30.0)
	_check(not n.is_empty(), "the track is found where the town sits")
	var r: Dictionary = CountyRail.all()[n.route]
	var t: Vector2 = (r.pts[n.seg + 1] - r.pts[n.seg]).normalized()
	var off: Vector2 = n.on - Vector2(400.0, 0.0)  # the track 400 m east of the town's middle
	var p := Vector2(400.0, 0.0)
	var across := Vector2(-t.y, t.x)
	var hw := RoadStyle.half_width(0)
	var square := _road(p - across * 100.0, p + across * 100.0)
	_check(CountyRail.road_problem(square, hw, off) == "", "a street may cross the track square on")
	var along := _road(p + across * 8.0 - t * 100.0, p + across * 8.0 + t * 100.0)
	var why := CountyRail.road_problem(along, hw, off)
	_check("Keep the street" in why, "a street running along the track is refused, with a hint (%s)" % why)
	var far := _road(p + across * 30.0 - t * 100.0, p + across * 30.0 + t * 100.0)
	_check(CountyRail.road_problem(far, hw, off) == "", "a street beside the track, past its fence, is fine")
	var slant := t.rotated(deg_to_rad(20.0))
	var shallow := _road(p - slant * 150.0, p + slant * 150.0)
	why = CountyRail.road_problem(shallow, hw, off)
	_check("crosses the railroad at 20" in why, "a street crossing the track at 20 degrees is refused (%s)" % why)
	# The simulation refuses it too, not just the tool.
	var town := CitySim.new()
	town.county_rail = true
	town.terrain_offset = off
	town.economy.money = 900_000_000
	var before := town.network.segments.size()
	town.apply({"type": "build_road", "start": [along[0].x, along[0].z], "ctrl": [along[1].x, along[1].z], "end": [along[2].x, along[2].z]})
	_check(town.network.segments.size() == before, "the simulation won't build a street along the track")
	_check("railroad" in town.road_problem(along, 0), "and says why")
	# A grid street crossing too shallow stops short of the track each side.
	var lines := CountyRail.trim_lines([shallow, square], hw, off)
	var kept_square := false
	var pieces := 0
	for l in lines:
		if l == square:
			kept_square = true
			continue
		pieces += 1
		for q in [l[0], l[2]]:
			var d := CountyRail.distance(q.x + off.x, q.z + off.y, 40.0)
			_check(d >= hw + CountyRail.ROAD_GAP - 0.5, "a trimmed grid street ends clear of the track (%.1f m)" % d)
	_check(kept_square and pieces == 2, "a grid keeps the square crossing and stops the slanting street short (%d pieces)" % pieces)
	# No public building on the right of way.
	var site := Vector3(p.x, 0.0, p.y)
	var dir := Vector3(across.x, 0.0, across.y)
	why = town.services.site_problem(town.network, Services.Kind.FIRE, site, dir)
	_check("right of way" in why, "a fire station on the track is refused (%s)" % why)
	_check("right of way" in town.warehouse_problem("small", site, dir) or not Warehouses.KINDS.has("small"),
		"so is a warehouse")

	# An older save, grown before the rule (here: with the rule off), with
	# homes and shops on the track: it loads and runs, and at its first full
	# lot check those lots go, like lots a new road runs through (Nathan,
	# 2026-10-29: the towns saved so far are test towns).
	var old := CitySim.new()
	old.terrain_offset = o
	PerfTown.build(old, "small")
	var was := _on_row(old)
	_check(was > 0, "the old town has buildings on the right of way (%d)" % was)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(old.to_dict()))
	var copy := CitySim.new()
	copy.county_rail = true
	copy.terrain_offset = o
	copy.from_dict(saved)
	copy.terrain_offset = o
	copy._lots_dirty = true
	for i in 3:
		copy.tick()
	_check(_on_row(copy) == 0, "after loading it with the railroads on, none are left (%d)" % _on_row(copy))
	_check(copy.buildings.size() > 150, "and the rest of the town stands (%d of %d buildings)" % [copy.buildings.size(), old.buildings.size()])
	quit(1 if _failed else 0)


## Buildings whose lot reaches onto the right of way.
static func _on_row(sim: CitySim) -> int:
	var n := 0
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var reg := PackedVector2Array()
		for q in sim.lots[key].corners:
			reg.append(q + sim.terrain_offset)
		if CountyRail.poly_distance(reg, CountyRail.ROW_HALF) < CountyRail.ROW_HALF - CitySim.RAIL_LOT_SLACK - 0.01:
			n += 1
	return n


static func _road(a: Vector2, b: Vector2) -> Array:
	return [Vector3(a.x, 0.0, a.y), Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5), Vector3(b.x, 0.0, b.y)]


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
