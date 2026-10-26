extends SceneTree
## Run: godot --headless -s tests/test_boxed_edges_fuzz.gd
## The review's random towns for PR #608 that went wrong, kept as fixed
## seeds: a bank, a campus and the phone company boxed in by jittered and
## curved streets, zoning painted at random, roads built and taken up while
## they grow. Their edge pieces (BlockEdges) must stay joined to their
## blocks on the near side of every street (seeds 110 and 121: a refit
## used to jump across the back street and a reload then dropped four
## pieces), never run onto anyone else's land (seed 138: a phone company
## piece lay 13 m2 over a bank's block), never over a road, and a reloaded
## copy must keep them exactly.
var _fails := 0
var _rng := RandomNumberGenerator.new()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _road(sim: CitySim, a: Array, b: Array) -> void:
	var off: float = _rng.randf_range(-30, 30) if _rng.randf() < 0.3 else 0.0
	sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5 + off, (a[1] + b[1]) * 0.5 + off], "end": b})


static func _box(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	return box


func _town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 500_000_000
	sim.simulate_traffic = false
	return sim


## One campus in a jittered ring of streets (seeds 110, 121).
func _campus_ring(seed: int) -> CitySim:
	_rng.seed = seed
	var sim := _town()
	var row := 10.0
	var cell: float = Education.CELL
	var side := _rng.randf_range(8, 70.0)
	var side2 := _rng.randf_range(8, 70.0)
	var back := _rng.randf_range(10, 90.0)
	var w := -(cell * 0.5 + side + row)
	var e := cell * 0.5 + side2 + row
	var bz := -(row + cell + back + row)
	var pts := []
	for q in [[w, 0.0], [e, 0.0], [e, bz], [w, bz]]:
		pts.append([q[0] + _rng.randf_range(-6, 6), q[1] + _rng.randf_range(-6, 6)])
	for i in 4:
		_road(sim, pts[i], pts[(i + 1) % 4])
	var s := Education.site_near(sim.network, Vector3(0, 0, -20))
	if s.size() != 2 or not sim.apply({"type": "place_campus", "kind": "high_school", "pos": [s[0].x, s[0].z],
			"dir": [s[1].x, s[1].z]}):
		return null
	for k in _rng.randi_range(0, 8):
		sim.apply({"type": "paint_zone", "center": [_rng.randf_range(w, e), _rng.randf_range(bz, 0)],
			"radius": _rng.randf_range(6, 25), "zone": _rng.randi_range(1, 3)})
	for i in 1440 * 10:
		sim.tick()
	for k in _rng.randi_range(0, 2):
		_road(sim, [_rng.randf_range(w, e), _rng.randf_range(bz, 0)], [_rng.randf_range(w, e), _rng.randf_range(bz, 0)])
	if _rng.randf() < 0.4:
		var ks: Array = sim.network.segments.keys()
		sim.apply({"type": "remove_road", "seg": ks[_rng.randi_range(0, ks.size() - 1)]})
	for i in 1440 * 9:
		sim.tick()
	return sim


## A jittered grid of streets with a bank, the phone company, a campus and a
## landfill dropped in at random (seed 138).
func _grid_town(seed: int) -> CitySim:
	_rng.seed = seed
	var sim := _town()
	var cs := 130.0 + _rng.randf() * 60.0
	var nx := 4
	var ny := 4
	for i in nx + 1:
		for j in ny:
			var a := [i * cs + _rng.randf_range(-12, 12), -j * cs + _rng.randf_range(-12, 12)]
			var b := [i * cs + _rng.randf_range(-12, 12), -(j + 1) * cs + _rng.randf_range(-12, 12)]
			if _rng.randf() < 0.9:
				_road(sim, a, b)
	for j in ny + 1:
		for i in nx:
			var a := [i * cs + _rng.randf_range(-12, 12), -j * cs + _rng.randf_range(-12, 12)]
			var b := [(i + 1) * cs + _rng.randf_range(-12, 12), -j * cs + _rng.randf_range(-12, 12)]
			if _rng.randf() < 0.9:
				_road(sim, a, b)
	for k in _rng.randi_range(0, 3):
		_road(sim, [_rng.randf_range(0, nx * cs), -_rng.randf_range(0, ny * cs)],
			[_rng.randf_range(0, nx * cs), -_rng.randf_range(0, ny * cs)])
	for kind in ["bank", "telecom", "campus", "landfill"]:
		var hit := Vector3(_rng.randf_range(20, nx * cs - 20), 0, -_rng.randf_range(20, ny * cs - 20))
		match kind:
			"bank":
				var s := Banks.site_near(sim.network, hit)
				if s.size() == 2:
					sim.apply({"type": "place_bank", "kind": "community", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
			"telecom":
				var s := Telecom.site_near(sim.network, hit)
				if s.size() == 2:
					sim.apply({"type": "place_telecom", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
			"campus":
				var s := Education.site_near(sim.network, hit)
				if s.size() == 2:
					sim.apply({"type": "place_campus", "kind": "high_school" if _rng.randi_range(0, 1) == 0 else "college",
						"pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
			"landfill":
				var s := CivicHubs.site_near(sim.network, hit)
				if s.size() == 2:
					sim.apply({"type": "place_hub", "kind": "landfill", "pos": [s[0].x, s[0].z], "dir": [s[1].x, s[1].z]})
	for k in _rng.randi_range(0, 12):
		sim.apply({"type": "paint_zone", "center": [_rng.randf_range(0, nx * cs), -_rng.randf_range(0, ny * cs)],
			"radius": _rng.randf_range(6, 25), "zone": _rng.randi_range(1, 3)})
	for i in 1440 * 4:
		sim.tick()
	for k in _rng.randi_range(1, 3):
		_road(sim, [_rng.randf_range(0, nx * cs), -_rng.randf_range(0, ny * cs)],
			[_rng.randf_range(0, nx * cs), -_rng.randf_range(0, ny * cs)])
	if _rng.randf() < 0.5:
		var ks: Array = sim.network.segments.keys()
		for k in 2:
			sim.apply({"type": "remove_road", "seg": ks[_rng.randi_range(0, ks.size() - 1)]})
	for i in 1440 * 6:
		sim.tick()
	return sim


func _init() -> void:
	for seed in [110, 121]:
		var sim := _campus_ring(seed)
		_check(sim != null, "seed %d: the campus goes in" % seed)
		if sim != null:
			_checks(sim, seed)
	_checks(_grid_town(138), 138)
	print("boxed edges, the review's towns: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)


func _checks(sim: CitySim, seed: int) -> void:
	var sets := {"bank": [sim.banks.banks, Banks.CELL, Banks], "telecom": [sim.telecom.companies, Telecom.CELL, Telecom],
		"campus": [sim.education.campuses, Education.CELL, Education]}
	var pieces := 0
	var land := []  # [owner, poly, is_edge]
	for kind in sets:
		for id in sets[kind][0]:
			var b: Dictionary = sets[kind][0][id]
			var cell: float = sets[kind][1]
			var own: Array = sets[kind][2].land_polys(b)
			var edges := BlockEdges.edge_polys(b, cell)
			pieces += edges.size()
			for i in own.size():
				land.append(["%s%d" % [kind, id], own[i], i >= own.size() - edges.size()])
			# Joined to its blocks, as prune sees it.
			var h := BlockEdges.view(b, cell)
			_check(CivicHubs.joined_edges(h).size() == b.edge.size(),
				"seed %d: every %s edge piece is joined to its blocks (%d)" % [seed, kind, b.edge.size()])
			var over := 0.0
			for poly in edges:
				for band in CivicHubs._road_bands(sim.network, _box(poly), 0.0):
					for q in Geometry2D.intersect_polygons(poly, band):
						over = maxf(over, CivicHubs.area(q))
			_check(over < 0.05, "seed %d: no %s edge piece runs onto a road's right of way and gap (%.3f m2)" %
				[seed, kind, over])
	for id in sim.hubs.hubs:
		for poly in CivicHubs.land_polys(sim.hubs.hubs[id]):
			land.append(["landfill%d" % id, poly, false])
	# No edge piece on anyone else's land (or another of its own pieces).
	var worst := 0.0
	var where := ""
	for i in land.size():
		for j in range(i + 1, land.size()):
			if not (land[i][2] or land[j][2]):
				continue
			for q in Geometry2D.intersect_polygons(land[i][1], land[j][1]):
				if CivicHubs.area(q) > worst:
					worst = CivicHubs.area(q)
					where = "%s / %s" % [land[i][0], land[j][0]]
	_check(worst <= 1.0, "seed %d: no edge piece on other land (%d pieces, worst %.1f m2 %s)" % [seed, pieces, worst, where])
	# A reloaded copy keeps every piece exactly and saves byte for byte the same.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var same := true
	for kind in sets:
		for id in sets[kind][0]:
			var theirs: Dictionary = {"bank": copy.banks.banks, "telecom": copy.telecom.companies,
				"campus": copy.education.campuses}[kind].get(id, {})
			same = same and not theirs.is_empty() and theirs.edge == sets[kind][0][id].edge
	_check(same, "seed %d: a reloaded copy keeps every edge piece" % seed)
	for o in [["banks", sim.banks, copy.banks], ["phone company", sim.telecom, copy.telecom],
			["campuses", sim.education, copy.education]]:
		_check(JSON.stringify(o[1].to_dict()) == JSON.stringify(o[2].to_dict()),
			"seed %d: the %s save byte for byte the same after a reload" % [seed, o[0]])
