extends SceneTree
## A logging company's woods give way to the town: a street and homes built
## through them clear the trees off the road and the lots (Brawn built a
## neighborhood in a forestry company's woods and the trees stayed).
## Run: godot --headless -s tests/test_forestry_woods.gd

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.require_utilities = false
	var id := _company(sim)
	_check(id >= 0, "a logging company opens in the woods")
	if id < 0:
		_done()
		return
	var s: Dictionary = sim.industry.sites[id]
	# A few years of logging: stands open, with woods around them.
	for i in 3000:
		sim.tick()
	var view := IndustryView.new()
	root.add_child(view)
	view.setup(sim)
	var key := "site:%d" % id
	# A street through the woods it keeps around its stands, homes on both
	# sides (the company's own stands and yard aren't the town's to zone).
	var count: int = view._trees._trees.get(key, []).size()
	var mid := Vector3.ZERO
	var side := Vector3(s.dir.z, 0.0, -s.dir.x).normalized()
	# The street runs through the most of its woods it can while staying
	# clear of the mill's yard (a road through that would buy it out).
	var most := -1
	var best_side := side
	for c in s.pads + [Vector2i.ZERO]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			var at := Industry.pad_center(s, n)
			if n in s.pads or n == Vector2i.ZERO:
				continue
			for way in [side, Vector3(-side.z, 0.0, side.x)]:
				var p0 := Vector2(at.x, at.z) - Vector2(way.x, way.z) * 150.0
				var p1 := Vector2(at.x, at.z) + Vector2(way.x, way.z) * 150.0
				var hq := Vector2(s.pos.x, s.pos.z)
				if Geometry2D.get_closest_point_to_segment(hq, p0, p1).distance_to(hq) < Industry.HQ_SIZE.length() + 30.0:
					continue
				var k := 0
				for t in view._trees._trees.get(key, []):
					var o := Vector2(t[0].origin.x, t[0].origin.z)
					if Geometry2D.get_closest_point_to_segment(o, p0, p1).distance_to(o) < 60.0:
						k += 1
				if k > most:
					most = k
					mid = at
					best_side = way
	side = best_side
	var a := mid - side * 150.0
	var b := mid + side * 150.0
	var near := 0
	for t in view._trees._trees.get(key, []):
		var o: Vector3 = t[0].origin
		if Geometry2D.get_closest_point_to_segment(Vector2(o.x, o.z), Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(Vector2(o.x, o.z)) < 60.0:
			near += 1
	_check(count > 100 and near > 15, "its woods are drawn (%d trees, %d where the street will go)" % [count, near])
	var stands: Array = s.pads.duplicate()
	var resting = s.get("regrow")
	sim.apply({"type": "build_road", "start": [a.x, a.z], "ctrl": [mid.x, mid.z], "end": [b.x, b.z]})
	var across := Vector3(-side.z, 0, side.x)
	for t in range(-140, 141, 10):
		for d in [-30.0, 30.0]:
			var p: Vector3 = mid + side * t + across * d
			sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": 18, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	# The same stands as before (the company cuts and moves on over the years,
	# which is not what this looks at).
	s.pads = stands
	if resting != null:
		s.regrow = resting
	sim.vegetation.update(sim)
	view._redraw_cleared()
	var homes := 0
	var bad := []
	var trees: Array = view._trees._trees.get(key, [])
	for k in sim.buildings:
		if not sim.lots.has(k):
			continue
		homes += 1
		var poly: PackedVector2Array = sim.lots[k].corners
		for t in trees:
			var o: Vector3 = t[0].origin
			if Geometry2D.is_point_in_polygon(Vector2(o.x, o.z), poly):
				bad.append("tree on lot %s" % k)
				break
	for t in trees:
		var o: Vector3 = t[0].origin
		var on_road := Geometry2D.get_closest_point_to_segment(Vector2(o.x, o.z), Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(Vector2(o.x, o.z))
		if on_road < 8.0:
			bad.append("tree in the street at %s" % o)
			break
	_check(homes >= 6 and bad.is_empty(), "the street and its %d homes are cleared of the company's trees %s" % [homes, bad.slice(0, 3)])
	var rest := 0
	for t in trees:
		var o: Vector3 = t[0].origin
		if Geometry2D.get_closest_point_to_segment(Vector2(o.x, o.z), Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(Vector2(o.x, o.z)) > 70.0:
			rest += 1
	# Most of the woods off the street still stand (Grant County woodlots are small).
	_check(rest > 30 and rest >= (count - near) * 0.75, "the rest of its woods stand (%d trees away from the street, of %d)" % [rest, count - near])
	view.free()
	_done()


func _company(sim: CitySim) -> int:
	var best := Vector3.ZERO
	var best_v := 0.0
	# The biggest woods near town (Grant County's are mostly small woodlots).
	for x in range(-4000, 4001, 150):
		for z in range(-4000, 4001, 150):
			var v := 0.0
			for dx in [-300, 0, 300]:
				for dz in [-300, 0, 300]:
					v += Resources.at(Resources.Kind.FOREST, Vector3(x + dx, 0, z + dz))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	sim.apply({"type": "build_road", "start": [best.x - 1800, best.z], "ctrl": [best.x, best.z], "end": [best.x + 1800, best.z]})
	for dx in [0, 200, -200, 400, -400]:
		if sim.apply({"type": "place_industry", "kind": "forest", "pos": [best.x + dx, best.z + 30], "dir": [0, -1]}):
			return sim.industry.sites.keys()[-1]
	return -1


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)


func _done() -> void:
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
