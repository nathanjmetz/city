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

	# Three clicks off a diagonal county road: a first side clicked close to
	# the road's direction lines up exactly; Shift on the third click makes
	# a rectangle with square corners, without it a triangle.
	var r := CitySim.new()
	r.apply({"type": "build_road", "start": [-300, -200], "ctrl": [0, 0], "end": [300, 200]})
	var t := RoadTool.new()
	t.sim = r
	t.network = r.network
	t.mode = RoadTool.Mode.GRID
	t.grid_exact = false
	var a0 := Vector3(0, 0, 30)
	var road := atan2(200.0, 300.0)
	for quarter in 4:
		var ang := road + quarter * PI * 0.5 + deg_to_rad(3.0)
		var rect := _three_clicks(t, a0, a0 + Vector3(cos(ang), 0, sin(ang)) * 250.0, a0 + Vector3(-60, 0, 170), true)
		var side := atan2(rect[1].z - rect[0].z, rect[1].x - rect[0].x)
		_check(absf(sin(2.0 * angle_difference(side, road))) < 0.0001, "first side %d lines up with the road" % quarter)
		_check(absf((rect[1] - rect[0]).normalized().dot((rect[2] - rect[1]).normalized())) < 0.0001,
			"Shift makes square corners (%d)" % quarter)
	var tri := _three_clicks(t, a0, a0 + Vector3(250, 0, 0), a0 + Vector3(90, 0, 200), false)
	_check(tri.size() == 3 and tri[2].distance_to(a0 + Vector3(90, 0, 200)) < 0.01, "third click without Shift: a triangle")
	t.free()

	# Brawn: keep clicking points for any shape, then Enter builds it.
	var pg := CitySim.new()
	pg.economy.money = 100000000
	var tp := RoadTool.new()
	tp.sim = pg
	tp.network = pg.network
	tp.mode = RoadTool.Mode.GRID
	tp.grid_exact = false
	tp.set_grid_preset(5)
	for corner in [Vector3(0, 0, 0), Vector3(400, 0, 0), Vector3(520, 0, 260), Vector3(260, 0, 420), Vector3(-60, 0, 300)]:
		tp._points.append(corner)
	tp._finish_grid()
	_check(tp._points.is_empty() and pg.network.segments.size() > 10, "five clicked points and Enter build a grid (%d streets)" % pg.network.segments.size())
	# Every point snaps onto a road under the cursor, zoomed out too.
	var sn := CitySim.new()
	sn.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0]})
	tp.sim = sn
	tp.network = sn.network
	tp._px = 0.1
	var near := tp._snapped(Vector3(50, 0, 9))
	_check(tp._snap_kind == "segment" and absf(near.z) < 0.01, "close up, a point 30 ft off the road snaps onto it")
	tp._px = 2.0
	near = tp._snapped(Vector3(50, 0, 24))
	_check(tp._snap_kind == "segment" and absf(near.z) < 0.01, "zoomed out, the snap reaches 14 pixels")
	tp._px = 0.1
	tp._snapped(Vector3(50, 0, 24))
	_check(tp._snap_kind == "free", "close up, a point 80 ft away stays free")
	tp.free()

	# Brawn's street: a first side clicked just past a street's end stops
	# exactly on it.
	var q := CitySim.new()
	q.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0]})
	q.apply({"type": "build_road", "start": [200, 0], "ctrl": [200, -125], "end": [200, -250]})
	var tq := RoadTool.new()
	tq.sim = q
	tq.network = q.network
	tq.mode = RoadTool.Mode.GRID
	tq.grid_exact = false
	tq._points.append(Vector3(200, 0, 0))
	var bq := tq._side_end(Vector3(203, 0, -255))
	_check(bq.distance_to(Vector3(200, 0, -250)) < 0.01, "first side stops on the street's end (got %s)" % str(bq))
	tq.free()

	# Brawn's junction: county roads bend and cross at odd angles, with an
	# old street running off the bend on a diagonal. A grid laid from the
	# bend along the road to the junction leaves no sharp wedges or shallow
	# strips against the old roads.
	var jn := CitySim.new()
	jn.economy.money = 100000000
	for rd in [[[-800, 80], [-300, 120]], [[-300, 120], [0, 0]], [[0, 0], [700, -320]], [[40, -700], [0, 0]],
			[[0, 0], [-60, 700]], [[-300, 120], [-33, 380]]]:
		jn.apply({"type": "build_road", "start": rd[0], "ctrl": [(rd[0][0] + rd[1][0]) * 0.5, (rd[0][1] + rd[1][1]) * 0.5], "end": rd[1]})
	var old_segs := jn.network.segments.keys()
	var tj := RoadTool.new()
	tj.sim = jn
	tj.network = jn.network
	tj.mode = RoadTool.Mode.GRID
	tj.grid_exact = false
	var bend := Vector3(-300, 0, 120)
	var to_junction := atan2(-120.0, 300.0) + deg_to_rad(3.0)
	var rj := _three_clicks(tj, bend, bend + Vector3(cos(to_junction), 0, sin(to_junction)) * 148.6, Vector3(-20, 0, 420), true)
	_check(absf(sin(tj._guide_angle - atan2(-120.0, 300.0))) < 0.001, "first side along the road to the junction")
	tj.free()
	var pts_j := []
	for corner in rj:
		pts_j.append([corner.x, corner.z])
	_check(jn.apply({"type": "build_grid_shape", "points": pts_j, "block": 120, "across": 82}), "junction grid built")
	var sharp := 0
	var strips := 0
	for id in jn.network.segments:
		if id in old_segs:
			continue
		var sg: Dictionary = jn.network.segments[id]
		for n in [sg.a, sg.b]:
			var mine := _leaving(jn.network, id, n)
			for other in jn.network.segments_at(n):
				var od := _leaving(jn.network, other, n)
				if other != id and mine.dot(od) > 0.0 and absf(mine.cross(od)) < 0.5:
					sharp += 1
		var cv := jn.network.curve_of(id)
		if Vector2(cv[2].x - cv[0].x, cv[2].z - cv[0].z).length() < 41.0:
			strips += 1
	_check(sharp == 0, "junction grid: no streets meet under 30 degrees (got %d)" % sharp)
	_check(strips == 0, "junction grid: no shallow strips (got %d)" % strips)
	_check(_overlaps(jn.network) == "", "junction grid: no overlaps " + _overlaps(jn.network))

	# Exact: a section grid's first side clicked at 1.6 miles stops at one
	# whole mile and says how far the next mile is; every block is a mile.
	var ex := CitySim.new()
	ex.economy.money = 1000000000
	var te := RoadTool.new()
	te.sim = ex
	te.network = ex.network
	te.mode = RoadTool.Mode.GRID
	te.set_grid_preset(0)
	te._points.append(Vector3.ZERO)
	var be := te._side_end(Vector3(2575, 0, 4))
	_check(be.distance_to(Vector3(1608, 0, 0)) < 0.01, "exact: a 1.6 mi side stops at one whole section (got %s)" % str(be))
	_check(te._exact_next.contains("0.4 mi more"), "exact: says 0.4 mi to the next section (got %s)" % te._exact_next)
	var re := _three_clicks(te, Vector3.ZERO, Vector3(2575, 0, 4), Vector3(1700, 0, 1300), true)
	_check(re[2].distance_to(Vector3(1608, 0, 1608)) < 0.01, "exact: the rectangle is one whole section (got %s)" % str(re))
	re = _three_clicks(te, Vector3.ZERO, Vector3(-3300, 0, 0), Vector3(-3216, 0, 3250), true)
	_check(re[2].distance_to(Vector3(-3216, 0, 3216)) < 0.01, "exact: 2 x 2 sections laid up and left (got %s)" % str(re))
	var pts_e := []
	for corner in re:
		pts_e.append([corner.x, corner.z])
	_check(ex.apply({"type": "build_grid_shape", "points": pts_e, "block": 1608, "across": 1608, "fit": te._fit()}),
		"exact: grid built")
	var odd_len := 0
	for id in ex.network.segments:
		var cv := ex.network.curve_of(id)
		if absf(cv[0].distance_to(cv[2]) - 1608.0) > 0.5:
			odd_len += 1
	_check(odd_len == 0 and ex.network.segments.size() == 12, "exact: 12 streets, each a mile (got %d, %d off)" % [ex.network.segments.size(), odd_len])
	# Exact triangle: section lines a whole mile apart, cut by the long side.
	var tr := CitySim.new()
	tr.economy.money = 1000000000
	var tri_e := _three_clicks(te, Vector3.ZERO, Vector3(3300, 0, 0), Vector3(0, 0, 3216), false)
	var pts_t := []
	for corner in tri_e:
		pts_t.append([corner.x, corner.z])
	_check(tr.apply({"type": "build_grid_shape", "points": pts_t, "block": 1608, "across": 1608, "fit": te._fit()}),
		"exact triangle built")
	var on_mile := false
	for id in tr.network.segments:
		var cv := tr.network.curve_of(id)
		if absf(cv[0].x - 1608.0) < 0.5 and absf(cv[2].x - 1608.0) < 0.5:
			on_mile = true
	_check(on_mile, "exact triangle: a street on the one-mile line")
	# A mile grid across a county highway keeps the streets that cross it:
	# a strip 700 m deep is plenty for lots, unlike a sliver by a town block.
	var hwy := CitySim.new()
	hwy.economy.money = 1000000000
	hwy.apply({"type": "build_road", "start": [-2000, 0], "ctrl": [0, 0], "end": [2000, 0]})
	var crossing := GridFill.plan(hwy.network, [Vector3(-1300, 0, -700), Vector3(1275, 0, -700), Vector3(1275, 0, 590),
		Vector3(-1300, 0, 590)], 1608.0, 0, 0, 1608.0, GridFill.FIT_AT_MOST)
	_check(crossing.size() == 10, "mile grid over a highway keeps its cross streets (got %d)" % crossing.size())
	# Adaptive: the same clicks flex the blocks to fit, never over a mile.
	te.set_grid_exact(false)
	var ra := _three_clicks(te, Vector3.ZERO, Vector3(2575, 0, 4), Vector3(2575, 0, 1300), true)
	_check(ra[2].distance_to(Vector3(2575, 0, 1300)) < 0.01, "adaptive: the rectangle follows the clicks (got %s)" % str(ra))
	var ad := CitySim.new()
	ad.economy.money = 1000000000
	var pts_a := []
	for corner in ra:
		pts_a.append([corner.x, corner.z])
	ad.apply({"type": "build_grid_shape", "points": pts_a, "block": 1608, "across": 1608, "fit": te._fit()})
	var longest := 0.0
	for id in ad.network.segments:
		var cv := ad.network.curve_of(id)
		longest = maxf(longest, cv[0].distance_to(cv[2]))
	_check(longest <= 1608.5 and ad.network.segments.size() > 4, "adaptive: no block over a mile (longest %.0f m)" % longest)
	te.free()

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


## The way segment `id` leaves node `n`.
## The shape three clicks make: the first corner `a`, the first side
## toward `b`, then the third point toward `c` (`square` = Shift held).
func _three_clicks(tool: RoadTool, a: Vector3, b: Vector3, c: Vector3, square: bool) -> Array:
	tool._points.clear()
	tool._points.append(a)
	tool._points.append(tool._side_end(b))
	tool._square = false
	return tool._pending_shape(tool._square_off(c) if square else c)


func _leaving(net: RoadNetwork, id: int, n: int) -> Vector2:
	var c := net.curve_of(id)
	var t := 0.0 if net.segments[id].a == n else 1.0
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
	return Vector2(tan.x, tan.z).normalized() * (1.0 if t == 0.0 else -1.0)


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
