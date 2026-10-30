extends SceneTree
## Run: godot --headless -s tests/test_state_layer.gd
## The state layer's yard props (docs/spec-state-layer.md, step 1): the
## same town always gets the same items in the same spots; as a lot slips
## further, items only come (in the same order) and stay put; decline items
## only on run-down and derelict lots, improvements only on improved and
## showpiece ones; who lives there changes nothing; Medium draws them to
## 100 m, High and up to 150 m, Low and the browser none; and in the drawn
## town, the props stand near the camera, and their whole footprint (the
## car's loose wheel, the couch's mattress) keeps off the building, the
## drive, the front walk as the house drew it (straight or across to the
## drive), the public sidewalk, a shop's entrance drive and aisles, every
## spot a car parks in, every tree's trunk, and the ground under a home's
## grown yard trees' crowns (#935), its own and its neighbours'.

var _failed := false
var sim: CitySim
var view: BuildingView
var state: StateView
var _frames := 0
var _phase := 0
var _at := 0
var _key := ""
var _saved := {}
var _counts := [0, 0]


func _initialize() -> void:
	# The same town twice, set to the look round's mixed tiers.
	var a := _town()
	var b := _town()
	var ia := _all_items(a)
	var ib := _all_items(b)
	_check(ia.size() > 50, "the test town has lots with props (%d)" % ia.size())
	_check(JSON.stringify(ia) == JSON.stringify(ib), "two copies of the same town get the same items in the same spots")
	_check(JSON.stringify(_all_items(a)) == JSON.stringify(ia), "and the same town asked again gets them again")
	var by := {}
	for key in ia:
		for it in ia[key]:
			by[it.item] = int(by.get(it.item, 0)) + 1
	for name in LotState.ITEMS:
		_check(int(by.get(name, 0)) > 0, "%s shows somewhere in the town (%d)" % [name, int(by.get(name, 0))])
	# Every item in the whole town (the house's own plan read from its
	# builder, so both front walks it might have drawn) keeps clear.
	var clash := _clashes(a, ia)
	for what in clash:
		_check(clash[what] == 0, "across the town, no item on the %s (%d)" % [what, clash[what]])
	# Tiers: decline items only below kept up, improvements only above.
	var decline := ["car_blocks", "cans", "couch", "dumpster", "lease"]
	var wrong := 0
	for key in ia:
		var t := a.care.tier_of(key)
		for it in ia[key]:
			if it.item in decline and t >= 0 and not (it.item == "cans" and _piled(a, key)):
				wrong += 1
			if not it.item in decline and t <= 0:
				wrong += 1
	_check(wrong == 0, "decline items only on run-down lots, improvements only on kept-up ones (%d wrong)" % wrong)
	# As a lot slips, items only come, in the same order, and stay put; as
	# it recovers, they go the same way.
	var grew_ok := true
	var stayed := true
	var n_homes := 0
	for key in a.buildings:
		if LotState.kind_of(a.buildings[key]) != "home" or not a.lots.has(key):
			continue
		n_homes += 1
		if n_homes > 60:
			break
		var y := LotState.yard_of(a, key)
		var bs := int(a.buildings[key].seed)
		var had := []
		for k in 40:
			var c := 0.37 - k * 0.37 / 39.0
			var t := -1 if c >= Balance.CARE_TIERS[0] else -2
			var now := LotState.items(a.city_seed, key, bs, t, c, y)
			for it in had:
				if not now.any(func(n): return n.item == it.item and n.at == it.at):
					stayed = false
			if now.size() < had.size():
				grew_ok = false
			had = now
	_check(grew_ok, "as a home slips, its items only come, never go")
	_check(stayed, "and each stays where it first stood")
	# Who lives there changes nothing: only the town's service sets condition.
	var key0 := ""
	for key in ia:
		if LotState.kind_of(a.buildings[key]) == "home" and not ia[key].is_empty():
			key0 = key
			break
	var was := JSON.stringify(_lot_items(a, key0))
	a.buildings[key0].occ = 0
	a.buildings[key0]["family"] = 12345
	_check(JSON.stringify(_lot_items(a, key0)) == was, "a home's props don't change with who lives there")
	# How far they're drawn, by tier, and never in the browser.
	var reach := []
	for t in 5:
		reach.append(float(GraphicsQuality.budget_for(t).get("state_m", -1.0)))
	_check(reach == [0.0, 100.0, 150.0, 150.0, 150.0], "Low none, Medium 100 m, High and up 150 m (%s)" % [reach])
	_check(float(GraphicsQuality.budget_for(GraphicsQuality.CINEMATIC, true).state_m) == 0.0
		and StateView.reach_for(true, 150.0) == 0.0, "the browser draws none")
	_check(float(GraphicsQuality.INACTIVE.get("state_m", 0.0)) == 0.0, "nor does a headless run unless a test asks")
	# Every prop is a real size: the meshes' triangles stay in the budget.
	var tris := 0
	for kind in StateView.KINDS:
		tris += StateMeshes.triangles(kind)
	_check(tris < 6000, "all eight props together are %d triangles" % tris)
	# The drawn town: the buildings' view and the state view, a camera over
	# a run-down square.
	sim = _town("small")
	GraphicsQuality.budget = GraphicsQuality.INACTIVE.duplicate()
	GraphicsQuality.budget["state_m"] = 150.0
	view = BuildingView.new()
	root.add_child(view)
	view.setup(sim)
	state = StateView.new()
	state.setup(sim, view)
	root.add_child(state)
	var cam := Camera3D.new()
	root.add_child(cam)
	var spot := Vector3.ZERO
	for key in sim.buildings:
		if sim.lots.has(key) and sim.care.tier_of(key) == -1 and LotState.kind_of(sim.buildings[key]) == "home":
			spot = sim.lots[key].pos
			break
	spot.y = Terrain.base_y(spot.x, spot.z)
	var from := spot + Vector3(0, 35, 25)
	cam.transform = Transform3D(Basis.looking_at(spot - from), from)
	cam.current = true


func _process(_d: float) -> bool:
	if sim == null:
		return true
	_frames += 1
	if _frames < 30 or ((not view.idle() or not state.idle()) and _frames < 3000):
		return false
	if _phase > 0:
		return _refiling()
	var counts := state.counts()
	var total := 0
	for k in counts:
		total += int(counts[k])
	_check(total > 5, "props are drawn near the camera (%s)" % [counts])
	_check(state.reach == 150.0, "the state view reaches 150 m when the tier asks for it")
	var eye: Vector3 = root.get_viewport().get_camera_3d().global_position
	var far := 0
	var hits := {"building": 0, "drive": 0, "walk": 0, "sidewalk": 0, "parking": 0, "tree trunk": 0, "yard tree crown": 0}
	# Every tree the buildings view planted, in the world: [where, crown reach
	# at the oldest a grown yard comes in (a street tree: -1)].
	var all_trees := []
	for k in view._planted:
		for t in view.trees_of(k):
			var reach := -1.0
			if float(t[3]) >= 0.0:
				reach = TreeField.SPREAD[int(t[1])] * float(t[2]) * minf(float(t[3]), TreeKinds.size_at(int(t[1]), 56.0))
			all_trees.append([t[0], reach])
	var walks := {"straight": 0, "across": 0}
	var checked := 0
	for key in state._lots:
		var lot: Dictionary = sim.lots[key]
		var b: Dictionary = sim.buildings[key]
		var inv := SiteLayout.frame(lot).affine_inverse()
		var tc := float(lot.get("to_curb", 2.0))
		var walk1 := -tc + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
		var sidewalk := Rect2(-100.0, walk1 - RoadStyle.SIDEWALK_WIDTH, 200.0, RoadStyle.SIDEWALK_WIDTH)
		# Where things must stay clear, from the drawing and the traffic's
		# own parking layout (not from LotState).
		var drives := []
		var walk := Rect2()
		var plan := view.plan_of(key)
		if not plan.is_empty():
			var dw := float(plan.drive_w)
			drives.append(Rect2(float(plan.drive_x) - dw * 0.5, -tc, dw, maxf(float(plan.get("garage_z", 6.0)), 6.0) + tc))
			walk = plan.walk
			walks["straight" if walk.position.y < 0.0 else "across"] += 1
		var lay := SiteLayout.for_lot(sim, key)
		var cars := []
		for sp in lay.spots:
			var at: Vector2 = sp.pos
			cars.append(Rect2(at - Vector2(1.0, 2.45), Vector2(2.0, 4.9)))
		if plan.is_empty() and not lay.main_street and not lay.spots.is_empty():
			drives.append(Rect2(float(lay.cut_x) - 3.0, -tc, 6.0, float(lay.aisle_z) + tc))
		for pr in state._lots[key].props:
			var x: Transform3D = pr[1]
			if x.origin.distance_to(eye) > 170.0:
				far += 1
			if pr[0] in ["lease", "flag"]:
				continue
			checked += 1
			# The prop's whole mesh, laid flat in the lot's frame.
			var box := StateMeshes.of(pr[0]).get_aabb()
			var foot := Rect2()
			for k in 4:
				var c := inv * (x * Vector3(box.position.x + (box.size.x if k & 1 else 0.0), 0.0,
					box.position.z + (box.size.z if k & 2 else 0.0)))
				foot = Rect2(Vector2(c.x, c.z), Vector2.ZERO) if k == 0 else foot.expand(Vector2(c.x, c.z))
			foot = foot.grow(-0.02)
			for m: Rect2 in view.masses_of(key):
				if m.intersects(foot):
					hits.building += 1
			for d: Rect2 in drives:
				if d.intersects(foot):
					hits.drive += 1
			if walk.has_area() and walk.intersects(foot):
				hits.walk += 1
			if sidewalk.intersects(foot) and not (pr[0] == "planters" and lay.main_street):
				hits.sidewalk += 1
			for c: Rect2 in cars:
				if c.intersects(foot):
					hits.parking += 1
			for t: Array in all_trees:
				var q := inv * (t[0] as Vector3)
				var at := Vector2(q.x, q.z)
				var d := at.distance_to(at.clamp(foot.position, foot.end))
				if d < 0.3:
					hits["tree trunk"] += 1
				if float(t[1]) > 0.0 and d < float(t[1]):
					hits["yard tree crown"] += 1
	_check(far == 0, "every prop is near the camera (%d far)" % far)
	_check(checked > 10, "props on the ground checked (%d)" % checked)
	_check(all_trees.filter(func(t): return float(t[1]) > 0.0).size() > 10, "grown yard trees among them (%d)"
		% all_trees.filter(func(t): return float(t[1]) > 0.0).size())
	_check(walks.straight > 0 and walks.across > 0, "both kinds of front walk are among the homes checked (%s)" % [walks])
	for what in hits:
		_check(hits[what] == 0, "no prop's footprint on the %s (%d)" % [what, hits[what]])
	_check(state.place_ms_max() < 8.0, "placing takes a few ms at most in any frame (%.1f ms, headless)" % state.place_ms_max())
	# Re-filing: a building torn down and one put up are filed one lot at a
	# time; a change that adds or removes none files nothing.
	for k in state._filed:
		_key = k
		break
	_saved = sim.buildings[_key].duplicate()
	_counts = [state.filed_count, state.dropped_count]
	sim.buildings_changed.emit()
	_phase = 1
	_at = _frames
	return false
	return true


## The re-filing phases, once the town is drawn and still again.
func _refiling() -> bool:
	if _frames - _at < 5:
		return false
	match _phase:
		1:
			_check(state.filed_count == _counts[0] and state.dropped_count == _counts[1],
				"a change that adds or removes no building files nothing (%d filed, %d dropped)"
				% [state.filed_count - _counts[0], state.dropped_count - _counts[1]])
			sim.buildings.erase(_key)
			sim.buildings_changed.emit()
		2:
			_check(state.dropped_count == _counts[1] + 1 and state.filed_count == _counts[0] and not state._filed.has(_key),
				"a building torn down drops only its lot (%d dropped, %d filed)"
				% [state.dropped_count - _counts[1], state.filed_count - _counts[0]])
			sim.buildings[_key] = _saved
			sim.buildings_changed.emit()
		3:
			_check(state.filed_count == _counts[0] + 1 and state._filed.has(_key),
				"a new building files only its own lot (%d filed)" % (state.filed_count - _counts[0]))
			print("FAILED" if _failed else "ALL PASSED")
			quit(1 if _failed else 0)
			return true
	_phase += 1
	_at = _frames
	return false


## Items over what must stay clear, from the builders' own plans and the
## traffic's parking layout: {what: count}.
func _clashes(s: CitySim, all: Dictionary) -> Dictionary:
	var hits := {"drive": 0, "walk": 0, "sidewalk": 0, "parking": 0}
	for key in all:
		var lot: Dictionary = s.lots[key]
		var b: Dictionary = s.buildings[key]
		var tc := float(lot.get("to_curb", 2.0))
		var walk1 := -tc + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
		var clear := {"sidewalk": [Rect2(-100.0, walk1 - RoadStyle.SIDEWALK_WIDTH, 200.0, RoadStyle.SIDEWALK_WIDTH)],
			"drive": [], "walk": [], "parking": []}
		var lay := SiteLayout.for_lot(s, key)
		for sp in lay.spots:
			var at: Vector2 = sp.pos
			clear.parking.append(Rect2(at - Vector2(1.0, 2.45), Vector2(2.0, 4.9)))
		if BuildingTypes.type_of(b) == "house":
			var r := RandomNumberGenerator.new()
			r.seed = int(b.seed)
			var fit := SiteLayout._fit(lot)
			var h := HouseBuilder.plan_info(r.randi(), fit.art, BuildingTypes.storeys(b))
			var dx := float(h.drive_x)
			var dw := float(h.drive_w)
			clear.drive.append(Rect2(dx - dw * 0.5, -tc, dw, maxf(float(h.get("garage_z", 6.0)), 6.0) + tc))
			var dr := float(h.door_x)
			var wz := float(h.walk_z)
			clear.walk.append(Rect2(dr - 0.6, -0.3, 1.2, wz + 0.3))
			clear.walk.append(Rect2(minf(dr, dx) - 0.6, wz - 1.2, absf(dr - dx) + 0.6, 1.2))
		for it in all[key]:
			if it.item in ["lease", "flag"]:
				continue
			var foot := LotState.footprint(it.item, it.at, it.yaw).grow(-0.02)
			for what in clear:
				if what == "sidewalk" and it.item == "planters":
					continue  # a Main Street shop's planters stand on the walk at its wall
				for r: Rect2 in clear[what]:
					if r.intersects(foot):
						hits[what] += 1
	return hits


## PerfTown at the look round's mixed tiers, with trash piled on one street.
func _town(size := "small") -> CitySim:
	var s := CitySim.new()
	PerfTown.build(s, size)
	var at: Array = Balance.CARE_TIERS
	var bands := [at[0] * 0.5, (at[0] + at[1]) * 0.5, (at[1] + at[2]) * 0.5, (at[2] + at[3]) * 0.5, (at[3] + 1.0) * 0.5]
	var keys := s.buildings.keys()
	keys.sort()
	for key in keys:
		if not s.lots.has(key):
			continue
		var p: Vector3 = s.lots[key].pos
		var t: int = [-2, -1, 0, 1, 2][posmod(floori(p.x / 80.0) * 2 + floori(p.z / 80.0) * 3, 5)]
		s.care.cond[key] = bands[t + 2]
		s.care.tier[key] = t
	var segs := s.network.segments.keys()
	segs.sort()
	s.hubs.trash[segs[segs.size() / 2]] = Balance.GARBAGE_PILE_LB * 2.0
	return s


func _piled(s: CitySim, key: String) -> bool:
	return float(s.hubs.trash.get(int(s.lots[key].seg), 0.0)) >= Balance.GARBAGE_PILE_LB


func _lot_items(s: CitySim, key: String) -> Array:
	var b: Dictionary = s.buildings[key]
	return LotState.items(s.city_seed, key, int(b.seed), s.care.tier_of(key), s.care.cond_of(key),
		LotState.yard_of(s, key), _piled(s, key))


## key -> its items, for every lot with any.
func _all_items(s: CitySim) -> Dictionary:
	var out := {}
	var keys := s.buildings.keys()
	keys.sort()
	for key in keys:
		if not s.lots.has(key) or LotState.kind_of(s.buildings[key]) == "":
			continue
		var it := _lot_items(s, key)
		if not it.is_empty():
			out[key] = it
	return out


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
