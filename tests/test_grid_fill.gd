extends SceneTree
## Run: godot --headless -s tests/test_grid_fill.gd
## The smart grid: any shape, fitted to the roads already there, no overlaps.

var failed := false


func _init() -> void:
	# A plain rectangle on empty land is a normal grid with no loose ends.
	var a := CitySim.new()
	_check(a.apply({"type": "build_grid_shape", "points": [[0, 0], [360, 0], [360, 246], [0, 246]], "block": 120}),
		"rectangle grid built")
	_check(_dead_ends(a.network) == 0, "rectangle has no dead ends (got %d)" % _dead_ends(a.network))
	_check(_overlaps(a.network) == "", "rectangle has no overlaps " + _overlaps(a.network))

	# Brawn's case: a second grid dropped over the first, a few metres off
	# and turned slightly. Nothing may run on top of or beside the old roads.
	var b := CitySim.new()
	b.apply({"type": "build_grid_shape", "points": [[0, 0], [360, 0], [360, 246], [0, 246]], "block": 120})
	var before := b.network.segments.size()
	var turn := deg_to_rad(2.0)
	var pts := []
	for p in [Vector2(5, 6), Vector2(520, 6), Vector2(520, 330), Vector2(5, 330)]:
		pts.append([p.x * cos(turn) - p.y * sin(turn), p.x * sin(turn) + p.y * cos(turn)])
	_check(b.apply({"type": "build_grid_shape", "points": pts, "block": 120}), "overlapping grid built")
	_check(b.network.segments.size() > before, "it added new streets")
	_check(_overlaps(b.network) == "", "no road runs on or beside another " + _overlaps(b.network))

	# A side drawn right along an old road reuses it and joins it.
	var c := CitySim.new()
	c.apply({"type": "build_road", "start": [-100, 0], "ctrl": [100, 0], "end": [300, 0]})
	c.apply({"type": "build_grid_shape", "points": [[0, 0], [200, 0], [200, 164], [0, 164]], "block": 100})
	var on_road := 0
	for id in c.network.segments:
		var cv := c.network.curve_of(id)
		if absf(cv[0].z) < 0.5 and absf(cv[2].z) < 0.5:
			on_road += 1
	_check(on_road == 4, "old road split into 4 pieces, not doubled (got %d)" % on_road)
	_check(_overlaps(c.network) == "", "no doubled road " + _overlaps(c.network))
	_check(_dead_ends(c.network) == 2, "only the old road's own two ends are dead ends (got %d)" % _dead_ends(c.network))

	# Brawn's case: a side street off the county road, then a grid dragged up
	# along it past its end. The street is reused and carried straight on to
	# the grid's corner, with no gap and no loose ends.
	var k := CitySim.new()
	k.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0]})
	k.apply({"type": "build_road", "start": [200, 0], "ctrl": [200, -125], "end": [200, -250]})
	k.apply({"type": "build_grid_shape", "points": [[200, 0], [200, -300], [-160, -300], [-160, 0]], "block": 120})
	var along := 0.0
	for id in k.network.segments:
		var cv := k.network.curve_of(id)
		if absf(cv[0].x - 200) < 0.5 and absf(cv[2].x - 200) < 0.5:
			along += absf(cv[2].z - cv[0].z)
	_check(absf(along - 300.0) < 1.0, "street along the side runs the full 300 m (got %.0f)" % along)
	_check(_dead_ends(k.network) == 2, "only the county road's ends are loose (got %d)" % _dead_ends(k.network))
	_check(_overlaps(k.network) == "", "street extended: no overlaps " + _overlaps(k.network))

	# An odd, concave shape: everything stays inside it and joins up.
	var d := CitySim.new()
	var shape := [[0, 0], [300, -40], [340, 180], [160, 120], [120, 300], [-20, 220]]
	_check(d.apply({"type": "build_grid_shape", "points": shape, "block": 90}), "odd shape built")
	var poly := PackedVector2Array()
	for p in shape:
		poly.append(Vector2(p[0], p[1]))
	var outside := 0
	for id in d.network.segments:
		for p in d.network.sample_segment(id, 4):
			var q := Vector2(p.x, p.z)
			if not Geometry2D.is_point_in_polygon(q, poly) and _dist_to(q, poly) > 1.0:
				outside += 1
	_check(outside == 0, "odd shape: streets stay inside (got %d points out)" % outside)
	_check(d.network.segments.size() > 10, "odd shape: filled with streets (got %d)" % d.network.segments.size())
	_check(_dead_ends(d.network) == 0, "odd shape: no dead ends (got %d)" % _dead_ends(d.network))
	_check(_overlaps(d.network) == "", "odd shape: no overlaps " + _overlaps(d.network))

	# An old road straight through the middle gets proper junctions.
	var e := CitySim.new()
	e.apply({"type": "build_road", "start": [-50, 100], "ctrl": [150, 100], "end": [350, 100]})
	e.apply({"type": "build_grid_shape", "points": [[0, 0], [300, 0], [300, 246], [0, 246]], "block": 100})
	var fours := 0
	for n in e.network.nodes:
		if e.network.segments_at(n).size() == 4:
			fours += 1
	_check(fours >= 2, "crossing old road makes 4-way junctions (got %d)" % fours)
	_check(_overlaps(e.network) == "", "crossing old road: no overlaps " + _overlaps(e.network))

	# The same command gives the same streets on every copy of the game.
	var x := CitySim.new()
	var y := CitySim.new()
	for s in [x, y]:
		s.apply({"type": "build_road", "start": [-30, 40], "ctrl": [100, 60], "end": [250, 20]})
		s.apply({"type": "build_grid_shape", "points": shape, "block": 90})
	_check(JSON.stringify(x.network.to_dict()) == JSON.stringify(y.network.to_dict()), "same result on every copy")

	# Rectangle mode: a side dragged a few degrees off a diagonal county road
	# snaps exactly parallel, and the depth keeps every corner square.
	var r := CitySim.new()
	r.apply({"type": "build_road", "start": [-300, -200], "ctrl": [0, 0], "end": [300, 200]})
	var t := RoadTool.new()
	t.sim = r
	t.network = r.network
	t.mode = RoadTool.Mode.GRID
	var a0 := Vector3(0, 0, 30)
	t._points.append(a0)
	var road := atan2(200.0, 300.0)
	var off := road + deg_to_rad(6.0)
	var b0 := t._grid_corner(a0 + Vector3(cos(off), 0, sin(off)) * 300.0)
	_check(absf(angle_difference(atan2(b0.z - a0.z, b0.x - a0.x), road)) < 0.0001, "rectangle side snaps parallel to the road")
	t._points.append(b0)
	var rect := t._rect(t._grid_corner(b0 + Vector3(-40, 0, 170)))
	_check(absf((rect[1] - rect[0]).normalized().dot((rect[2] - rect[1]).normalized())) < 0.0001, "rectangle corners are square")
	t.free()

	# Every size preset plans a clean grid quickly, from a farm section
	# down to a city block, with the long side and the short side kept.
	for pr in GridFill.PRESETS:
		var g := CitySim.new()
		g.economy.money = 100000000
		var w: float = pr.block * 2.0
		var h: float = pr.across * 2.0
		var t0 := Time.get_ticks_msec()
		g.apply({"type": "build_grid_shape", "points": [[0, 0], [w, 0], [w, h], [0, h]],
			"block": pr.block, "across": pr.across})
		var ms := Time.get_ticks_msec() - t0
		_check(g.network.segments.size() >= 8 and _dead_ends(g.network) == 0 and ms < 3000,
			"%s preset: %d streets, %d dead ends, %d ms" % [pr.name, g.network.segments.size(), _dead_ends(g.network), ms])

	print("ALL TESTS PASSED" if not failed else "TESTS FAILED")
	quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed = true


func _dead_ends(net: RoadNetwork) -> int:
	var n := 0
	for id in net.nodes:
		if net.segments_at(id).size() == 1:
			n += 1
	return n


## "" if no two roads that don't share a junction come closer than their
## sidewalks allow; otherwise where they do.
func _overlaps(net: RoadNetwork) -> String:
	var ids := net.segments.keys()
	for i in ids.size():
		var si: Dictionary = net.segments[ids[i]]
		var pi := net.sample_segment(ids[i], 16)
		for j in range(i + 1, ids.size()):
			var sj: Dictionary = net.segments[ids[j]]
			var room := RoadStyle.right_of_way_half(si.type) + RoadStyle.right_of_way_half(sj.type)
			var shared := []
			for n in [si.a, si.b]:
				if n == sj.a or n == sj.b:
					shared.append(net.nodes[n])
			var pj := net.sample_segment(ids[j], 16)
			for p in pi:
				var near_shared := false
				for q in shared:
					if p.distance_to(q) < room * 1.5:
						near_shared = true
				if near_shared:
					continue
				for k in pj.size() - 1:
					var c := Geometry3D.get_closest_point_to_segment(p, pj[k], pj[k + 1])
					if c.distance_to(p) < room - 0.5:
						var near_q := false
						for q in shared:
							if c.distance_to(q) < room * 1.5:
								near_q = true
						if not near_q:
							return "(at %.0f, %.0f)" % [p.x, p.z]
	return ""


func _dist_to(q: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q))
	return best
