extends SceneTree
## House lots: yard trees stand clear of the house, and the traffic sim
## parks cars on the drive the art paints.
## Run: godot --headless -s tests/test_house_lots.gd


func _init() -> void:
	var lots := []
	for i in 160:
		lots.append({"width": [14.0, 16.5, 19.0, 21.0, 24.0][i % 5], "depth": [30.0, 36.0, 44.0][i % 3],
			"at": Vector2((i % 16) * 90.0, (i / 16) * 130.0)})

	# A shade tree's crown never passes through a wall (Brawn saw a maple
	# planted in a front window).
	var bad := []
	var trees := 0
	for i in lots.size():
		var b := HouseBuilder.new()
		b.rng = RandomNumberGenerator.new()
		b.rng.seed = i * 7919 + 13
		b._fit(lots[i])
		var built: Array = b._house(6.0, [0, 1, 2][i % 3])
		for t in built[2]:
			var p: Vector3 = t[0]
			if p.z <= 0.0:
				continue  # street trees, in the parkway
			trees += 1
			var need: float = TreeField.SPREAD[t[1]] * t[3] * 0.9
			if b._wall_gap(p) < need - 0.01:
				bad.append("lot %d: %s %.1f m from the house, crown %.1f m" % [i, TreeField.Species.keys()[t[1]], b._wall_gap(p), need])
	_check(trees > 100 and bad.is_empty(), "yard trees keep their crowns off the walls (%d trees) %s" % [trees, bad.slice(0, 3)])

	# The traffic sim lays a plan out without drawing it: the drive, garage
	# and door come out exactly as when the plan is drawn.
	var differ := []
	for i in lots.size():
		var seed := i * 104729 + 5
		HouseBuilder._plans.clear()
		HouseBuilder._infos.clear()
		var dry: Dictionary = HouseBuilder.plan_info(seed, lots[i], 0)
		HouseBuilder.build(seed, 6.0, lots[i], 0)
		HouseBuilder._infos.clear()
		var drawn: Dictionary = HouseBuilder.plan_info(seed, lots[i], 0)
		if str(dry) != str(drawn):
			differ.append("lot %d" % i)
	_check(differ.is_empty(), "a plan laid out without drawing matches the drawn one %s" % [differ.slice(0, 3)])

	# The car's garage and drive spots lie on the painted drive.
	var off := []
	for i in lots.size():
		var seed := i * 104729 + 5
		var built: Array = HouseBuilder.build(seed, 6.0, lots[i], 0)
		var lay := SiteLayout.house(seed, {"half": lots[i].width * 0.5, "depth": lots[i].depth, "art": lots[i]}, 0)
		for s in lay.spots:
			if s.kind == "drive" and not _on_drive(built[1], s.pos):
				off.append("lot %d at %s" % [i, s.pos])
		if not _on_drive(built[1], Vector2(lay.cut_x, -1.0)):
			off.append("lot %d curb cut at %.1f" % [i, lay.cut_x])
	_check(off.is_empty(), "cars use the drive the art paints %s" % [off.slice(0, 3)])

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## True when a spot lies on a concrete drive (yard alpha 0) in the flat mesh.
func _on_drive(flat: ArrayMesh, p: Vector2) -> bool:
	if flat.get_surface_count() == 0:
		return false
	var a := flat.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
	for i in range(0, v.size(), 3):
		if c[i].a > 0.01:
			continue
		var tri := PackedVector2Array([Vector2(v[i].x, v[i].z), Vector2(v[i + 1].x, v[i + 1].z), Vector2(v[i + 2].x, v[i + 2].z)])
		if Geometry2D.is_point_in_polygon(p, tri):
			return true
	return false


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
