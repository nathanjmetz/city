extends SceneTree
## Run: godot --headless -s tests/test_state_layer.gd
## The state layer's yard props (docs/spec-state-layer.md, step 1): the
## same town always gets the same items in the same spots; as a lot slips
## further, items only come (in the same order) and stay put; decline items
## only on run-down and derelict lots, improvements only on improved and
## showpiece ones; who lives there changes nothing; Medium draws them to
## 100 m, High and up to 150 m, Low and the browser none; and in the drawn
## town, the props stand near the camera, never inside a building.

var _failed := false
var sim: CitySim
var view: BuildingView
var state: StateView
var _frames := 0


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
	_check(float(GraphicsQuality.INACTIVE.state_m) == 0.0, "nor does a headless run unless a test asks")
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
	var counts := state.counts()
	var total := 0
	for k in counts:
		total += int(counts[k])
	_check(total > 5, "props are drawn near the camera (%s)" % [counts])
	_check(state.reach == 150.0, "the state view reaches 150 m when the tier asks for it")
	var eye: Vector3 = root.get_viewport().get_camera_3d().global_position
	var far := 0
	var inside := 0
	for key in state._lots:
		var lot: Dictionary = sim.lots[key]
		var inv := SiteLayout.frame(lot).affine_inverse()
		var masses := view.masses_of(key)
		for pr in state._lots[key].props:
			var x: Transform3D = pr[1]
			if x.origin.distance_to(eye) > 170.0:
				far += 1
			if pr[0] in ["lease", "flag"]:
				continue
			var q := inv * x.origin
			for m: Rect2 in masses:
				if m.has_point(Vector2(q.x, q.z)):
					inside += 1
	_check(far == 0, "every prop is near the camera (%d far)" % far)
	_check(inside == 0, "no prop stands inside its building (%d)" % inside)
	_check(state.place_ms_max() < 8.0, "placing takes a few ms at most in any frame (%.1f ms, headless)" % state.place_ms_max())
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)
	return true


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
