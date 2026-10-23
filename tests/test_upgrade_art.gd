extends SceneTree
## Every upgrade a leader builds shows on the ground (Brawn 2026-10-23: an
## oil company's leader was "adding things" and nothing changed at its
## yard). Draws each company and farmstead with and without each step of its
## development tree and checks the drawing changes; then lets a real oil
## company build and checks its add-ons take free ground beside the yard.
## Run: godot --headless -s tests/test_upgrade_art.gd

var _failed := false


func _init() -> void:
	for kind in Agency.TREES:
		var none := _verts(kind, [], {})
		var missing := []
		for node in Agency.TREES[kind]:
			var built := _with_requires(Agency.TREES[kind], node.id)
			var before := _verts(kind, built.filter(func(n): return n != node.id), _spots(kind, built.filter(func(n): return n != node.id)))
			var after := _verts(kind, built, _spots(kind, built))
			if after <= before:
				missing.append(node.id)
		_check(missing.is_empty(), "every %s upgrade draws something (%d steps, base %d vertices)%s" % [
			kind, Agency.TREES[kind].size(), none, "" if missing.is_empty() else ": missing " + str(missing)])
	for kind in Industry.ADDONS:
		var bad := []
		for node in Industry.ADDONS[kind]:
			var size: Array = Industry.ADDONS[kind][node][0]
			for at in Industry.ADDONS[kind][node][1]:
				var r := Rect2(at[0] - size[0] * 0.5, at[1] - size[1] * 0.5, size[0], size[1])
				if not Rect2(-40.5, -40.5, 81, 81).encloses(r):
					bad.append(node)
		_check(bad.is_empty(), "%s add-ons stay inside the main building's own 80 m cell %s" % [kind, bad])
	_oil_company()
	_done()


## A node and everything it needs before it, in tree order.
func _with_requires(tree: Array, id: String) -> Array:
	var want := {id: true}
	var grew := true
	while grew:
		grew = false
		for n in tree:
			if want.has(n.id):
				for r in n.get("requires", []):
					if not want.has(r):
						want[r] = true
						grew = true
	var out := []
	for n in tree:
		if want.has(n.id):
			out.append(n.id)
	return out


## Add-ons at their first spots that don't overlap.
func _spots(kind: String, built: Array) -> Dictionary:
	var s := {"kind": kind, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "addons": {}}
	var ind := Industry.new()
	ind.sites[1] = s
	for n in built:
		ind.place_addon(1, n, func(_p): return true)
	return s.addons


func _verts(kind: String, built: Array, addons: Dictionary) -> int:
	var parts: Array
	match kind:
		"farm": parts = FarmBuilder.build_farmstead(7, 1, built)
		"forest": parts = ForestryBuilder.mill(7, Industry.HQ_SIZE, built, addons)
		_: parts = IndustryBuilder.build_hq(kind, 7, built, addons)
	var n := 0
	for k in 2:
		var mesh: ArrayMesh = parts[k]
		for i in mesh.get_surface_count():
			n += mesh.surface_get_array_len(i)
	return n


func _oil_company() -> void:
	var sim := CitySim.new()
	sim.require_utilities = false
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-3000, 3001, 150):
		for z in range(-3000, 3001, 150):
			var v := Resources.at(Resources.Kind.OIL, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	sim.apply({"type": "build_road", "start": [best.x - 1800, best.z], "ctrl": [best.x, best.z], "end": [best.x + 1800, best.z]})
	var id := -1
	for dx in [0, 200, -200, 400, -400]:
		if sim.apply({"type": "place_industry", "kind": "oil", "pos": [best.x + dx, best.z + 30], "dir": [0, -1]}):
			id = sim.industry.sites.keys()[-1]
			break
	_check(id >= 0, "an oil company opens")
	if id < 0:
		return
	var s: Dictionary = sim.industry.sites[id]
	# Its leader has built up the whole tree (as an old save has, from before
	# add-ons took ground): the next round finds each one its ground.
	s.built = Agency.TREES.oil.map(func(n): return n.id)
	sim._develop_hubs()
	var built: Array = s.get("built", [])
	var placed: Dictionary = s.get("addons", {})
	var want := []
	for n in built:
		if Industry.ADDONS.oil.has(n):
			want.append(n)
	_check(built.size() >= 3 and want.size() >= 1, "the leader builds up its tree %s" % [built])
	var all_placed := true
	for n in want:
		all_placed = all_placed and placed.has(n)
	_check(all_placed, "each add-on it built has ground beside the yard %s" % [placed])
	var held := true
	for n in placed:
		var c := Industry.addon_rect(s, n).get_center()
		var p: Vector3 = s.pos + Vector3(-s.dir.z, 0, s.dir.x) * c.x - s.dir * c.y
		held = held and sim.industry.site_at(p) == id
	_check(held, "the company holds the ground its add-ons stand on")
	# A copy loaded from a save draws the same add-ons in the same places.
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	_check(copy.industry.sites[id].get("addons", {}) == placed, "add-ons survive a save")


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)


func _done() -> void:
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
