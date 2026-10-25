extends SceneTree
## Houses drawn the new way (BuildingView's rings; docs/scale-test-2026-10-25.md,
## "The new drawing style, measured"): the close-up detail lies on each
## house's own walls and roofs, squares near the camera are drawn in full
## and let go when it leaves, every house keeps its far version, and
## drawing never changes the town.
## Run: godot --headless -s tests/test_house_drawing.gd

var sim := CitySim.new()
var view: BuildingView
var cam := Camera3D.new()
var _frames := 0
var _failed := false
var _phase := 0
var _home := Vector3.ZERO
var _before := ""
var _wait := 0
var _gone := ""
var _redone := ""


func _initialize() -> void:
	_test_detail()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [560, 0], "c": [0, 420], "block": 140.0})
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.tick()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for key in sim.empty_zoned_lots():
		sim.buildings[key] = {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": rng.randi(), "built": 0, "cap": 3, "occ": 3}
	sim.buildings_changed.emit()
	_check(sim.buildings.size() > 40, "a neighbourhood of houses (%d)" % sim.buildings.size())
	for key in sim.buildings:
		_home = sim.lots[key].pos
		break
	_before = JSON.stringify(sim.to_dict())
	root.add_child(cam)
	cam.current = true
	_look(_home, 40.0)
	view = BuildingView.new()
	root.add_child(view)
	view.setup(sim)


func _look(at: Vector3, dist: float) -> void:
	at.y = Terrain.ground_y(at.x, at.z)
	cam.look_at_from_position(at + Vector3(0.0, dist * 0.45, dist * 0.9), at)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames > 3000:
		_check(false, "the view settles (phase %d)" % _phase)
		_end()
		return true
	if not view.idle():
		return false
	match _phase:
		0:
			var homes := view._recs.size()
			_check(homes == sim.buildings.size(), "every house is drawn (%d of %d)" % [homes, sim.buildings.size()])
			_check(view._far_sq.square_count() > 0, "with far versions (%d squares)" % view._far_sq.square_count())
			var reach := BuildingView._full_from()
			var near_ok := true
			for sq in view._batches:
				near_ok = near_ok and view._square_dist(sq) < reach + BuildingView.FULL_MARGIN
			_check(not view._batches.is_empty() and near_ok,
				"only squares near the camera are drawn in full (%d of %d)" % [view._batches.size(), view._by_sq.size()])
			var counts := view._near.instance_counts()
			_check(counts.get("board", 0) + counts.get("brick_inner", 0) > 0 and counts.get("shingle", 0) > 0,
				"houses near the camera are grown lap by lap and course by course %s" % counts)
			# Far off: the full drawings and the close-up detail are let go.
			_look(_home + Vector3(4000.0, 0.0, 0.0), 300.0)
			_phase = 1
			_wait = _frames
		1:
			if _frames - _wait < 10:
				return false
			_check(view._batches.is_empty(), "far from town, no square is kept in full (%d)" % view._batches.size())
			_check(view._near.grown_count() == 0, "and no close-up detail (%d)" % view._near.grown_count())
			_check(view._recs.size() == sim.buildings.size() and view._far_sq.square_count() > 0,
				"while every house keeps its far version")
			# Back again: drawn in full once more.
			_look(_home, 40.0)
			_phase = 2
			_wait = _frames
		2:
			if _frames - _wait < 10:
				return false
			_check(not view._batches.is_empty() and view._near.grown_count() > 0,
				"coming back, the squares and the detail return (%d, %d)" % [view._batches.size(), view._near.grown_count()])
			_check(JSON.stringify(sim.to_dict()) == _before, "drawing never changes the town")
			# A house torn down and one drawn anew, in a square kept in full.
			var near_keys := []
			for key in view._recs:
				if view._batches.has(view._recs[key].sq):
					near_keys.append(key)
			_gone = near_keys[0]
			_redone = near_keys[1]
			sim.buildings.erase(_gone)
			sim.buildings[_redone].level = int(sim.buildings[_redone].get("level", 0)) + 1
			sim.buildings_changed.emit()
			_phase = 3
			_wait = _frames
		3:
			if _frames - _wait < 10:
				return false
			var sq: Vector2i = view._recs[_redone].sq
			var batch: BatchSquare = view._batches[sq]
			_check(not view._recs.has(_gone) and view._recs[_redone].look[1] == sim.buildings[_redone].level and batch.merged.has(_redone) and batch.parts.is_empty(),
				"a house torn down leaves, one drawn anew is merged back, and the arrays are let go after")
			var all_in := true
			for key in view._by_sq.get(sq, {}):
				all_in = all_in and batch.merged.has(key)
			_check(all_in, "its neighbours are all still in the square's drawing")
			# A new house goes up on the empty lot, stage by stage.
			var lot: Dictionary = sim.lots[_gone]
			sim.construction.start("lot:" + _gone, "house", sim.tick_count, lot.front, -lot.normal, lot.to_curb)
			sim.buildings[_gone] = {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": 99, "built": sim.tick_count, "cap": 3, "occ": 0}
			sim.buildings_changed.emit()
			_phase = 4
			_wait = _frames
		4:
			if _frames - _wait < 10:
				return false
			var rec: Dictionary = view._recs.get(_gone, {})
			_check(not rec.is_empty() and rec.site != null and not view._batches[rec.sq].merged.has(_gone),
				"a house going up is drawn on its own, stage by stage")
			sim.tick_count += Construction.duration("house") + 10
			_phase = 5
			_wait = _frames
		5:
			# Its site looks at the clock four times a second.
			if _frames - _wait < 40:
				return false
			var rec: Dictionary = view._recs[_gone]
			_check(rec.site == null and view._batches[rec.sq].merged.has(_gone),
				"once it's done it joins its square's drawing")
			_end()
	return false


## The close-up pieces lie on the walls and roofs the builder drew.
func _test_detail() -> void:
	var found_brick := false
	var checked := 0
	for seed in range(1, 400):
		HouseBuilder.keep_arrays = true
		var built := HouseBuilder.build(seed * 7919, 4.0, {"width": 22.0, "depth": 40.0, "at": Vector2(seed * 61.0, 0.0)})
		HouseBuilder.keep_arrays = false
		var parts: Array = built[0].get_meta("parts")
		var has_brick := false
		for p in parts:
			has_brick = has_brick or (p[0] == "brick")
		if checked >= 3 and (found_brick or not has_brick):
			continue
		checked += 1
		var batch := BatchSquare.new(Vector2i.ZERO, 128.0)
		batch.set_building("h", Transform3D(Basis.IDENTITY, Vector3(64.0, 0.0, 64.0)), parts, [], [], [])
		var near := NearDetail.new()
		near.parts_of = func(_k): return [Vector2i.ZERO, batch.kind_parts("h", ["siding", "brick", "roof"])]
		near.index("h", Vector3(64.0, 0.0, 70.0))
		for i in 200:
			near.update(Vector3(64.0, 10.0, 40.0))
			if near.caught_up() and near.grown_count() == 1:
				break
		var counts := near.instance_counts()
		var on_walls := _on_faces(near, batch)
		_check(counts.get("board", 0) + counts.get("brick_inner", 0) + counts.get("brick_solo", 0) > 0 \
			and counts.get("shingle", 0) > 0 and on_walls, "house %d grown over its own walls and roof %s" % [seed, counts])
		if has_brick:
			found_brick = true
			var bricks := 0
			for k in counts:
				if String(k).begins_with("brick_"):
					bricks += counts[k]
			_check(bricks > 0 and counts.get("mortar", 0) > 0, "brick laid brick by brick, mortar behind (%d cells)" % bricks)
		near.free()
		batch.free()
		if checked >= 4:
			break
	_check(found_brick, "a brick house among them")


## Every piece starts on a wall or roof face of its kind (within 2 cm).
func _on_faces(near: NearDetail, batch: BatchSquare) -> bool:
	var planes := []
	for kp in batch.kind_parts("h", ["siding", "brick", "roof"]):
		var a: Array = kp[1]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx = a[Mesh.ARRAY_INDEX]
		var n_tri: int = (idx.size() if idx != null else v.size()) / 3
		for t in n_tri:
			var p0: Vector3 = v[idx[t * 3] if idx != null else t * 3]
			var p1: Vector3 = v[idx[t * 3 + 1] if idx != null else t * 3 + 1]
			var p2: Vector3 = v[idx[t * 3 + 2] if idx != null else t * 3 + 2]
			var n := (p1 - p0).cross(p2 - p0)
			if n.length_squared() > 1e-6:
				planes.append(Plane(n.normalized(), p0))
	# From the pieces' own records (a headless run's renderer keeps no
	# instance data).
	for key in near._grown:
		for kind in near._grown[key].bufs:
			var buf: PackedFloat32Array = near._grown[key].bufs[kind]
			for i in mini(buf.size() / 16, 200):
				var o := Vector3(buf[i * 16 + 3], buf[i * 16 + 7], buf[i * 16 + 11])
				var best := INF
				for pl: Plane in planes:
					best = minf(best, absf(pl.distance_to(o)))
				if best > 0.02:
					print("  %s piece %d is %.3f m off any face" % [kind, i, best])
					return false
	return true


func _end() -> void:
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
