extends SceneTree
## Run: godot --headless -s tests/test_road_tools.gd

func _init() -> void:
	# Brawn (CS2): drawing a road lines it up with nearby junctions and road
	# ends, along their roads or square to them, with dotted lines; and shows
	# the angle it makes with the road it starts on.
	var al := CitySim.new()
	al.apply({"type": "build_road", "start": [0, 0], "ctrl": [50, 0], "end": [100, 0]})
	al.apply({"type": "build_road", "start": [200, 100], "ctrl": [200, 200], "end": [200, 300]})
	var at := RoadTool.new()
	at.sim = al
	at.network = al.network
	at.mode = RoadTool.Mode.STRAIGHT
	at._px = 1.0
	var none := Vector3(INF, 0, INF)
	var q := at._align(Vector3(150, 0, 4), none)
	_check(q.distance_to(Vector3(150, 0, 0)) < 0.01 and at._align_lines.size() == 1, "a point lines up straight on from a road end")
	q = at._align(Vector3(203, 0, 5), none)
	_check(q.distance_to(Vector3(200, 0, 0)) < 0.01 and at._align_lines.size() == 2, "where two guide lines cross, it snaps to the crossing")
	q = at._align(Vector3(150, 0, 60), none)
	_check(q.distance_to(Vector3(150, 0, 60)) < 0.01 and at._align_lines.is_empty(), "far from every guide it stays free")
	q = at._align(Vector3(150, 0, -6), Vector3(150, 0, -100), PI * 0.5)
	_check(q.distance_to(Vector3(150, 0, 0)) < 0.01, "along a fixed direction it slides to where a guide crosses")
	# Brawn: a guide only helps from the nearest junction or straight on down
	# a road into open ground, never through another road.
	var bl := CitySim.new()
	bl.apply({"type": "build_road", "start": [0, 0], "ctrl": [50, 0], "end": [100, 0]})
	bl.apply({"type": "build_road", "start": [150, -100], "ctrl": [150, 0], "end": [150, 100]})
	var bt := RoadTool.new()
	bt.sim = bl
	bt.network = bl.network
	bt.mode = RoadTool.Mode.STRAIGHT
	bt._px = 1.0
	q = bt._align(Vector3(120, 0, 3), none)
	_check(q.distance_to(Vector3(120, 0, 0)) < 0.01, "straight on from a road end, before the next road")
	q = bt._align(Vector3(220, 0, 3), none)
	_check(q.distance_to(Vector3(220, 0, 3)) < 0.01 and bt._align_lines.is_empty(), "no guide through another road (got %s)" % q)
	q = bt._align(Vector3(50, 0, 3), none)
	_check(q.distance_to(Vector3(50, 0, 3)) < 0.01, "no guide back along the road itself (got %s)" % q)
	q = bt._align(Vector3(153, 0, 160), none)
	_check(q.distance_to(Vector3(150, 0, 160)) < 0.01, "down the centreline into the field (got %s)" % q)
	bt.free()
	# Brawn: a grid's third corner dragged onto a road squares onto it, so
	# the far side runs along that road; in the open it lines up with a
	# junction straight on from a road.
	var gs := CitySim.new()
	gs.apply({"type": "build_road", "start": [-100, 200], "ctrl": [150, 200], "end": [400, 200]})
	gs.apply({"type": "build_road", "start": [300, -200], "ctrl": [300, -150], "end": [300, -100]})
	var gt := RoadTool.new()
	gt.sim = gs
	gt.network = gs.network
	gt.mode = RoadTool.Mode.GRID
	gt._px = 1.0
	gt.grid_exact = false
	gt._points = [Vector3(0, 0, 0), Vector3(200, 0, 0)]
	q = gt._grid_corner(gt._snapped(Vector3(214, 0, 201)))
	_check(q.distance_to(Vector3(200, 0, 200)) < 0.01, "a grid corner on a road squares onto it (got %s)" % q)
	gt._points = [Vector3(0, 0, -300), Vector3(200, 0, -300)]
	q = gt._grid_corner(gt._snapped(Vector3(204, 0, -100)))
	_check(absf(q.x - 200.0) < 0.01 and absf(q.z + 100.0) < 0.01, "square side lines up with a road end (got %s)" % q)
	_check(not gt._align_lines.is_empty(), "with a dotted line to that junction")
	gt.free()
	# Brawn: the grid's first corner snaps onto a county road crossing.
	var cs := CitySim.new()
	var ct := RoadTool.new()
	ct.sim = cs
	ct.network = cs.network
	ct.mode = RoadTool.Mode.GRID
	ct._px = 1.0
	var co := cs.terrain_offset
	var found := Vector2(INF, INF)
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var cc0 := (Vector2(roundf(co.x / CountyGrid.SECTION) + ix, roundf(co.y / CountyGrid.SECTION) + iz)) * CountyGrid.SECTION - co
			if found.x == INF and ct._county_crossing(Vector3(cc0.x + 6, 0, cc0.y - 5), 15.0).x != INF:
				found = cc0
	_check(found.x != INF, "a county crossing near town")
	q = ct._snapped(Vector3(found.x + 6, 0, found.y - 5))
	_check(Vector2(q.x, q.z).distance_to(found) < 0.01 and ct._snap_kind == "county", "a click by a county crossing lands on it (got %s)" % q)
	ct._points = [Vector3(0, 0, 0), Vector3(200, 0, 0)]
	ct._grid_angles(Vector3(200, 0, 150))
	_check(ct._angle_labels[0].visible and ct._angle_labels[0].text == "90°", "a grid corner shows its angle (got %s)" % ct._angle_labels[0].text)
	ct._points.append(Vector3(200, 0, 150))
	ct._grid_angles(Vector3(0, 0, 150))
	_check(ct._angle_labels[1].visible and ct._angle_labels[1].text == "90°", "and where it closes to the first (got %s)" % ct._angle_labels[1].text)
	for l in ct._angle_labels:
		l.free()
	ct.free()
	var c30 := Vector3(50, 0, 0) + Vector3(cos(deg_to_rad(30.0)), 0, sin(deg_to_rad(30.0))) * 80.0
	at._show_angles([Vector3(50, 0, 0), Vector3(50, 0, 0).lerp(c30, 0.5), c30])
	_check(at._angle_labels[0].text == "30° sharp", "a 30° crossing reads sharp (got %s)" % at._angle_labels[0].text)
	at._show_angles([Vector3(50, 0, 0), Vector3(50, 0, 40), Vector3(50, 0, 80)])
	_check(at._angle_labels[0].text == "90°", "a square crossing reads 90° (got %s)" % at._angle_labels[0].text)
	at._show_angles([Vector3(100, 0, 0), Vector3(150, 0, 0), Vector3(200, 0, 0)])
	_check(at._angle_labels[0].text == "180°", "straight on from a road end reads 180° (got %s)" % at._angle_labels[0].text)
	for l in at._angle_labels:
		l.free()
	at.free()

	# A 3 x 2 block grid: 3 streets one way, 4 the other, all joined.
	var sim := CitySim.new()
	var changes := [0]
	sim.network.changed.connect(func(): changes[0] += 1)
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [360, 0], "c": [0, 164], "block": 120})
	_check(changes[0] == 1, "a grid is one change (got %d)" % changes[0])
	_check(sim.network.nodes.size() == 12, "grid junctions (got %d)" % sim.network.nodes.size())
	_check(sim.network.segments.size() == 17, "grid street pieces (got %d)" % sim.network.segments.size())
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	_check(sim.lots.size() > 40, "grid has lots (got %d)" % sim.lots.size())
	# Lots back to back between streets don't clash.
	var rows := {}
	for key in sim.lots:
		if absf(sim.lots[key].normal.z) > 0.9:
			rows["%d %d" % [roundi(sim.lots[key].road.z), signi(roundi(sim.lots[key].normal.z))]] = true
	_check(rows.size() == 6, "lots on both sides of all 3 streets (got %s)" % str(rows.keys()))

	# A roundabout on a crossroads joins all four roads and clears the middle.
	var r := CitySim.new()
	r.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	r.apply({"type": "build_road", "start": [0, -100], "ctrl": [0, 0], "end": [0, 100]})
	r.apply({"type": "build_roundabout", "center": [0, 0], "radius": 20})
	var inside := 0
	for id in r.network.segments:
		var c := r.network.curve_of(id)
		if RoadNetwork.bezier(c[0], c[1], c[2], 0.5).length() < 18.0:
			inside += 1
	_check(inside == 0, "nothing left inside the ring")
	var joined := 0
	for n in r.network.nodes:
		if r.network.segments_at(n).size() == 3:
			joined += 1
	_check(joined == 4, "four roads meet the ring (got %d)" % joined)
	var ring_ok := true
	for id in r.network.segments:
		for p in r.network.sample_segment(id, 8):
			var d := p.length()
			if d < 25.0 and absf(d - 20.0) > 0.2:
				ring_ok = false
	_check(ring_ok, "ring is round")
	# Real curve rules: a gentle U-turn is fine, a hairpin tighter than a truck can turn is not.
	var u := CitySim.new()
	_check(u.apply({"type": "build_road", "start": [0, 0], "ctrl": [40, 30], "end": [0, 60]}), "gentle bend allowed")
	_check(not u.apply({"type": "build_road", "start": [100, 0], "ctrl": [140, 3], "end": [100, 6]}), "hairpin refused")
	# Road types: an upgrade widens the road and pushes its lots back.
	var w := CitySim.new()
	w.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	var seg: int = w.network.segments.keys()[0]
	w.apply({"type": "zone_frontage", "seg": seg, "side": 1, "zone": ZoneMap.Zone.RESIDENTIAL, "both": true})
	var before: float = absf(w.lots.values()[0].front.z)
	_check(w.apply({"type": "upgrade_road", "seg": seg, "road": RoadStyle.Type.BOULEVARD}), "upgrade to boulevard")
	var after: float = absf(w.lots.values()[0].front.z)
	_check(is_equal_approx(after - before, RoadStyle.half_width(2) - RoadStyle.half_width(0)),
		"lots move back by the extra width (%.1f -> %.1f)" % [before, after])
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	_check(back.network.segments.values()[0].type == RoadStyle.Type.BOULEVARD, "road type saved")
	# A crossing street keeps its own type on both halves.
	w.apply({"type": "build_road", "start": [0, -100], "ctrl": [0, 0], "end": [0, 100], "road": 1})
	var avenues := 0
	for id in w.network.segments:
		if w.network.segments[id].type == 1:
			avenues += 1
	_check(avenues == 2, "split avenue keeps its type (got %d)" % avenues)
	# Parallel: the offset of a curve stays the same distance away.
	var curve := [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(80, 0, 40)]
	var off := RoadShapes.offset(curve, 30.0)
	var a := RoadNetwork.sample_curve(curve[0], curve[1], curve[2], 16)
	var b := RoadNetwork.sample_curve(off[0], off[1], off[2], 16)
	var worst := 0.0
	for p in b:
		var best := INF
		for i in a.size() - 1:
			best = minf(best, Geometry3D.get_closest_point_to_segment(p, a[i], a[i + 1]).distance_to(p))
		worst = maxf(worst, absf(best - 30.0))
	_check(worst < 2.0, "parallel road stays about 30 m away (off by %.2f m)" % worst)
	# Roundabouts: a one-way ring turning counter-clockwise seen from above.
	var rb := CitySim.new()
	rb.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	rb.apply({"type": "build_roundabout", "center": [0, 0], "radius": 20})
	var rings := 0
	var ccw := true
	for id in rb.network.segments:
		var sg: Dictionary = rb.network.segments[id]
		if sg.type == RoadStyle.Type.RING:
			rings += 1
			var c := rb.network.curve_of(id)
			# Seen from above (x east, z south), counter-clockwise means the
			# centre sits to the driver's left: cross product y > 0.
			var fwd: Vector3 = c[2] - c[0]
			var to_centre: Vector3 = -c[0]
			ccw = ccw and fwd.cross(to_centre).y > 0.0 and rb.network.is_oneway(id)
		else:
			_check(not RoadStyle.is_ring(sg.type), "approach roads keep their type")
	_check(rings >= 8, "street roundabout is a one-lane ring (%d arcs)" % rings)
	_check(ccw, "ring is one-way, counter-clockwise from above")
	var rb2 := RoadNetwork.new()
	rb2.from_dict(JSON.parse_string(JSON.stringify(rb.network.to_dict())))
	_check(rb2.is_oneway(rb2.segments.keys()[rb2.segments.size() - 1]) == rb.network.is_oneway(rb.network.segments.keys()[rb.network.segments.size() - 1]),
		"one-way flag saved")
	var big := CitySim.new()
	big.apply({"type": "build_roundabout", "center": [0, 0], "radius": 14, "road": RoadStyle.Type.AVENUE})
	var c0: Array = big.network.curve_of(big.network.segments.keys()[0])
	_check(big.network.segments.values()[0].type == RoadStyle.Type.RING2 and absf(c0[0].length() - RoadShapes.radius_for_icd(150.0 / 3.28084, RoadStyle.Type.RING2)) < 0.5,
		"avenue roundabout is two lanes, at least 150 ft across (FHWA)")
	# The size row: each real FHWA size builds at its own diameter and lanes.
	for size in RoadShapes.ROUNDABOUT_SIZES:
		var ring := RoadShapes.ring_for_lanes(int(size.lanes))
		var rs := CitySim.new()
		rs.apply({"type": "build_roundabout", "center": [0, 0], "lanes": size.lanes,
			"radius": RoadShapes.radius_for_icd(float(size.icd) / 3.28084, ring)})
		var first: Dictionary = rs.network.segments.values()[0]
		var r0: float = rs.network.curve_of(rs.network.segments.keys()[0])[0].length()
		_check(first.type == ring and absf(RoadShapes.icd_of(r0, ring) * 3.28084 - float(size.icd)) < 2.0,
			"%s roundabout is %d ft across with %d lane(s)" % [size.name, size.icd, size.lanes])
		_check(RoadShapes.is_mini(r0, ring) == (float(size.icd) <= 90.0), "%s: mini only at 90 ft or less" % size.name)
	var one := CitySim.new()
	one.apply({"type": "build_roundabout", "center": [0, 0], "lanes": 1, "radius": 200})
	_check(RoadShapes.icd_of(one.network.curve_of(one.network.segments.keys()[0])[0].length(), RoadStyle.Type.RING) * 3.28084 < 181.0,
		"a one-lane roundabout tops out at 180 ft (NCHRP 672)")
	_check(not rb.apply({"type": "upgrade_road", "seg": rb.network.segments.keys()[0], "road": RoadStyle.Type.RING}),
		"no upgrading to ring types")
	# Old saves: two-way rings become real roundabouts on load.
	var old_save := rb.to_dict()
	for k in old_save.roads.segments:
		var arr: Array = old_save.roads.segments[k]
		if RoadStyle.is_ring(int(arr[4])):
			arr[4] = RoadStyle.Type.STREET
			arr.resize(6)
			var a0 = arr[0]
			arr[0] = arr[1]
			arr[1] = a0
	var migrated := CitySim.new()
	migrated.from_dict(JSON.parse_string(JSON.stringify(old_save)))
	var ok_rings := 0
	for id in migrated.network.segments:
		var sg: Dictionary = migrated.network.segments[id]
		if RoadStyle.is_ring(sg.type):
			var c := migrated.network.curve_of(id)
			if (c[2] - c[0]).cross(-c[0]).y > 0.0 and migrated.network.is_oneway(id):
				ok_rings += 1
	_check(ok_rings >= 8, "old saves get real roundabouts (%d arcs)" % ok_rings)
	var circ := RoadShapes.arc_circle(RoadShapes.roundabout(Vector3(5, 0, 7), 30.0)[3])
	_check(circ[0].distance_to(Vector3(5, 0, 7)) < 0.5 and absf(circ[1] - 30.0) < 0.5, "arc circle found")
	# Bridges: a road 7.5 m up passes over without a junction.
	var o := CitySim.new()
	o.economy.money = 100_000_000  # this test is about road rules, not money
	o.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": 3})
	_check(o.lots.is_empty(), "no lots along a highway")
	# Ramps up at the AASHTO 8% max grade: 7.5 m needs ~94 m.
	_check(not o.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, -125], "end": [0, -100, 7.5], "road": 1}),
		"too steep refused")
	_check(o.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, -125], "end": [0, -50, 7.5], "road": 1}),
		"ramp up at a legal grade")
	_check(o.apply({"type": "build_road", "start": [0, -50, 7.5], "ctrl": [0, 0, 7.5], "end": [0, 50, 7.5], "road": 1}),
		"overpass built")
	var crossings := 0
	for n in o.network.nodes:
		if o.network.segments_at(n).size() > 2:
			crossings += 1
	_check(crossings == 0, "overpass makes no junction (got %d)" % crossings)
	_check(not o.apply({"type": "build_road", "start": [50, -50, 3], "ctrl": [50, 0, 3], "end": [50, 50, 3]}),
		"too low to pass over refused")
	var o2 := CitySim.new()
	o2.from_dict(JSON.parse_string(JSON.stringify(o.to_dict())))
	var high := 0
	for n in o2.network.nodes:
		if o2.network.nodes[n].y > 7.0:
			high += 1
	_check(high == 2, "heights saved (got %d)" % high)
	_check(RoadStyle.safe_speed_mph(46.0) >= 20 and RoadStyle.safe_speed_mph(46.0) <= 30, "a 150 ft loop ramp is a ~25 mph curve")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
