extends SceneTree
## Run: godot --headless -s tests/test_road_tools.gd

func _init() -> void:
	# A 3 x 2 block grid: 3 streets one way, 4 the other, all joined.
	var sim := CitySim.new()
	var changes := [0]
	sim.network.changed.connect(func(): changes[0] += 1)
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [360, 0], "c": [0, 164], "block": 120})
	_check(changes[0] == 1, "a grid is one change (got %d)" % changes[0])
	_check(sim.network.nodes.size() == 12, "grid junctions (got %d)" % sim.network.nodes.size())
	_check(sim.network.segments.size() == 17, "grid street pieces (got %d)" % sim.network.segments.size())
	_check(sim.lots.size() > 40, "grid has lots (got %d)" % sim.lots.size())
	# Lots back to back between streets don't clash.
	var rows := {}
	for key in sim.lots:
		if absf(sim.lots[key].normal.z) > 0.9:
			rows[snappedf(sim.lots[key].pos.z, 1.0)] = true
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
	var before: float = absf(w.lots.values()[0].pos.z)
	_check(w.apply({"type": "upgrade_road", "seg": seg, "road": RoadStyle.Type.BOULEVARD}), "upgrade to boulevard")
	var after: float = absf(w.lots.values()[0].pos.z)
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
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
