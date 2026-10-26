extends SceneTree
## Run: godot --headless -s tests/test_boxed_parks.gd
## A park boxed in by roads fills its block up to the sidewalk with lawn,
## walks and trees (Nathan, 2026-10-26: "when a hub with leader is
## "trapped" inside a road area, it should nicely fill in that area up to
## the edge (sidewalk) so that it looks like its using its space well."):
## edge pieces cut back to the roads, never over them, never on zoned or
## built lots, kept by a save byte for byte, and cut back again by a road
## built later.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## How far a point is from the nearest road's right of way plus the gap the
## park keeps (negative: over it).
func _clear_of_roads(sim: CitySim, p: Vector2) -> float:
	var best := INF
	for id in sim.network.segments:
		var w := RoadStyle.right_of_way_half(sim.network.segments[id].type) + Parks.SETBACK
		var pts := sim.network.sample_segment(id, 64)
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - w)
	return best


## Four streets round a block `w` metres across and `d` deep, its front
## street along z = 0.
func _ring(sim: CitySim, w: int, d: int) -> void:
	var x := w / 2
	for r in [[[-x, 0], [x, 0]], [[x, 0], [x, -d]], [[x, -d], [-x, -d]], [[-x, -d], [-x, 0]]]:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})


func _no_edge_over_roads(sim: CitySim, pid: int) -> bool:
	for c in sim.parks.sites[pid].edge:
		var poly := sim.parks.edge_poly(pid, c)
		if Services.road_clash(sim.network, poly):
			return false
		for q in poly:
			if _clear_of_roads(sim, q) < -0.05:
				return false
	return true


func _edge_area(s: Dictionary) -> float:
	var a := 0.0
	for c in s.edge:
		a += CivicHubs.area(s.edge[c])
	return a


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	_ring(sim, 110, 80)
	_check(sim.network.segments.size() == 4, "a block ringed by four streets (%d)" % sim.network.segments.size())
	var row := RoadStyle.right_of_way_half(sim.network.segments.values()[0].type) + Parks.SETBACK
	var site := Parks.site_near(sim.network, "park", Vector3(0, 0, -30))
	_check(sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"a park goes in on the block's front street")
	var pid: int = sim.parks.sites.keys()[0]
	var s: Dictionary = sim.parks.sites[pid]
	_check(s.edge.is_empty(), "a new park has no edge pieces")
	var size0: Vector2 = s.size
	# Houses zoned along the inside of the east street.
	for z in range(-15, -66, -10):
		sim.apply({"type": "paint_zone", "center": [47, z], "radius": 9, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 400:
		sim.tick()
	var zoned := []
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if lot.pos.x > 30.0 and lot.pos.z < -5.0 and lot.pos.z > -75.0 \
				and (sim.buildings.has(key) or sim.zones.zone_at(lot.zone_pt) != ZoneMap.Zone.NONE):
			zoned.append(key)
	_check(not zoned.is_empty(), "lots zoned along the east street (%d)" % zoned.size())

	# The park board's rounds: it fills in, and takes its edge pieces.
	for i in 3000:
		sim.tick()
	_check(s.size == size0, "boxed in, it never bought a whole strip (%s)" % s.size)
	# The park faces +z: its own right (+x along its road) runs west.
	var w_piece := Vector2i(1, 0)
	_check(s.edge.has(w_piece) and s.edge.has(Vector2i(0, 1)),
		"it took edge pieces up to the west and back streets (%s)" % str(s.edge.keys()))
	_check(_no_edge_over_roads(sim, pid), "no edge piece reaches over a street's sidewalk and the gap")
	var nearest := INF
	for c in s.edge:
		for q in sim.parks.edge_poly(pid, c):
			nearest = minf(nearest, _clear_of_roads(sim, q))
	_check(nearest < 0.5, "edge pieces reach right up to the sidewalk gap (%.2f m)" % nearest)
	# The west side, the back and the back corner are the park's up to the sidewalk.
	var west := -55.0 + row + 1.0
	for z in [-15.0, -40.0]:
		_check(sim.parks.covers(Vector3(west, 0, z)), "land by the west sidewalk at z %d is the park's" % z)
	_check(sim.parks.covers(Vector3(0, 0, -80.0 + row + 1.0)), "land by the back street's sidewalk is the park's")
	_check(sim.parks.covers(Vector3(west, 0, -80.0 + row + 1.0)), "and the back corner")
	_check(not sim.parks.covers(Vector3(west - 3.0, 0, -40.0)), "the sidewalk itself is not")
	# Nothing taken from the zoned and built lots, and no lot left on its land.
	var taken := false
	for key in zoned:
		var lot: Dictionary = sim.lots.get(key, {})
		if lot.is_empty():
			continue
		for p in [lot.pos, lot.front, lot.zone_pt]:
			taken = taken or sim.parks.covers(p)
		for c in s.edge:
			for q in Geometry2D.intersect_polygons(sim.parks.edge_poly(pid, c), lot.corners):
				taken = taken or CivicHubs.area(q) > 1.0
	_check(not taken, "no zoned or built lot was taken")
	var under := false
	for key in sim.lots:
		under = under or sim.parks.covers(sim.lots[key].pos)
	_check(not under, "no lot is left on the park's land")
	# Lawn and walks only: the playground and the rest stay on the park itself.
	var off := false
	for f in s.features:
		if f.size != Vector2.ZERO:
			off = off or not sim.parks._inside(pid, f.pos, f.size)
	_check(not s.features.is_empty() and not off, "every playground, court and field is on the park itself (%d)" % s.features.size())
	_check(sim.parks.land_acres(pid) > sim.parks.acres(pid), "the panel's acres count the edge land (%.2f > %.2f)" %
		[sim.parks.land_acres(pid), sim.parks.acres(pid)])
	var upkeep := sim.parks.site_upkeep(pid)
	var kept: Dictionary = s.edge.duplicate()
	s.edge = {}
	_check(is_equal_approx(sim.parks.site_upkeep(pid), upkeep), "edge pieces don't change the upkeep")
	s.edge = kept
	# Something else can't take its edge land.
	var inside := CivicHubs._inner_pts(sim.parks.edge_poly(pid, w_piece), 4.0)
	_check(not inside.is_empty() and sim.parks.at(inside[0]) == pid, "its edge land is its own")
	_check(sim.hubs._ground_problem(sim, sim.parks.edge_poly(pid, w_piece), inside, -1, true, false) != "",
		"a landfill or post office can't take it")
	_check(sim.parks.overlaps(Array(sim.parks.edge_poly(pid, w_piece))), "nor a service building")

	# Save, load: byte for byte the same, and the copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var cs: Dictionary = copy.parks.sites[pid]
	_check(cs.edge == s.edge, "a save keeps every edge piece exactly")
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim.to_dict()), "a loaded copy saves byte for byte the same")
	for i in 800:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.parks.to_dict()) == JSON.stringify(sim.parks.to_dict()), "copies stay in step")
	# An older save, without edge pieces, still loads.
	var old := sim.to_dict()
	for k in old.parks.sites:
		old.parks.sites[k].erase("edge")
	var aged := CitySim.new()
	aged.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(aged.parks.sites[pid].edge.is_empty() and aged.parks.sites[pid].size == s.size,
		"an older save loads with no edge pieces")
	_check(not JSON.stringify(aged.parks.to_dict()).contains("\"edge\""), "and saves the old way until it takes some")

	# Roads win: a short lane in from the west street cuts the west piece back.
	var before := _edge_area(s)
	var shapes: Dictionary = s.edge.duplicate()
	var size1: Vector2 = s.size
	var end := -size1.x * 0.5 - row - 3.0
	sim.apply({"type": "build_road", "start": [-55, -25], "ctrl": [(-55 + end) * 0.5, -25], "end": [end, -25]})
	sim.tick()
	_check(sim.network.segments.size() > 4, "the lane is built")
	_check(sim.parks.sites.has(pid) and s.size == size1, "the park itself is untouched")
	_check(_edge_area(s) < before, "the lane took edge land (%.0f -> %.0f m2)" % [before, _edge_area(s)])
	_check(_no_edge_over_roads(sim, pid), "nothing left of the edge pieces is on or by the lane")
	_check(not sim.parks.covers(Vector3(end - 2.0, 0, -25.0)), "the lane's ground is not the park's")
	var cut := 0
	for c in s.edge:
		if shapes.has(c) and shapes[c] != s.edge[c]:
			cut += 1
	_check(cut > 0 and s.edge.has(Vector2i(0, 1)), "edge pieces cut back, the rest stay (%d cut)" % cut)
	var copy2 := CitySim.new()
	copy2.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(JSON.stringify(copy2.to_dict()) == JSON.stringify(sim.to_dict()), "the cut-back town saves byte for byte the same")
	copy2.tick()
	_check(copy2.parks.sites[pid].edge == s.edge, "the cut-back edge pieces survive a save")

	# Its drawing fills the edge pieces: more lawn, more trees.
	var bare := s.duplicate()
	bare.edge = {}
	var built := ParkBuilder.build_site(s, 7, 6.0, "Town")
	var plain := ParkBuilder.build_site(bare, 7, 6.0, "Town")
	var verts := func(m: ArrayMesh) -> int:
		return 0 if m.get_surface_count() == 0 else m.surface_get_array_len(0)
	_check(verts.call(built[4]) > verts.call(plain[4]), "the edge pieces are drawn as lawn")
	_check(built[2].size() > plain[2].size(), "with shade trees (%d -> %d)" % [plain[2].size(), built[2].size()])
	var out := false
	for t in built[2]:
		var q := CivicHubs.to_world(s, Vector2(t[0].x, t[0].z))
		out = out or not sim.parks.covers(Vector3(q.x, 0, q.y))
	_check(not out, "every tree stands on the park's land")
	# Its walks and things lie on its land, or on the way out to the sidewalk.
	var far := 0.0
	var flat: ArrayMesh = built[1]
	for i in flat.get_surface_count():
		for v in flat.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			var q := CivicHubs.to_world(s, Vector2(v.x, v.z))
			far = maxf(far, -_clear_of_roads(sim, q))
	_check(far < 6.5, "no walk runs further out than the sidewalk (%.1f m past the gap)" % far)
	print("boxed parks: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
