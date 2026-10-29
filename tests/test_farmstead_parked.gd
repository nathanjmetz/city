extends SceneTree
## Run: godot --headless -s tests/test_farmstead_parked.gd
## What stands in a county farmstead's yard by the month (FarmsteadParked):
## the pickup always, machines out from spring to fall, the combine and the
## grain trailer at harvest, all on the gravel and clear of the buildings;
## and the farmhouse's propane tank.

var _failed := false


func _init() -> void:
	var grain := []
	var homes := 0
	for seed in 3000:
		var p := FarmsteadPlan.grow(Vector2(500.0 + seed * 41.0, 900.0), true, 0.0, seed % 256)
		if p.kind == "grain" and grain.size() < 12:
			grain.append(p)
		if p.kind == "home" and homes < 6:
			homes += 1
			var v := FarmsteadParked.of(p, 7)
			_check(v.size() <= 1, "a country home has its own car or truck, no machines")
	var combines := 0
	for p in grain:
		var jan := FarmsteadParked.of(p, 1)
		var oct := FarmsteadParked.of(p, 10)
		var jul := FarmsteadParked.of(p, 7)
		var kinds := oct.map(func(v): return v.kind)
		_check(jan.all(func(v): return v.kind not in ["tractor", "tractor_wagon", "combine", "grain_truck"]),
			"in January the machines are in the sheds")
		if p.parts.any(func(q): return q.kind == "shed" or q.kind == "quonset"):
			if "combine" in kinds:
				combines += 1
			_check(jul.any(func(v): return v.kind == "tractor"), "a tractor out in July")
		_check(FarmsteadParked.of(p, 10) == oct, "the same yard every time")
		for v in oct:
			var at: Vector2 = v.at
			if v.kind != "pickup" and not str(v.kind).begins_with("pickup") and v.kind != "suv":
				_check(p.gravel.any(func(r: Rect2): return r.grow(1.0).has_point(at)), "the %s stands on the gravel" % v.kind)
			var foot := FarmsteadParked.footprint(v.kind, at, v.yaw)
			for q in p.parts:
				_check(not FarmsteadPlan._extent(q).intersects(foot), "the %s isn't parked in a %s" % [v.kind, q.kind])
	_check(combines >= grain.size() / 2, "at harvest most grain farms have the combine out (%d of %d)" % [combines, grain.size()])
	# The farmhouse's propane tank is drawn (the last step).
	var p: Dictionary = grain[0]
	var b2 := FarmBuilder.county(p)
	for i in b2.steps():
		b2.step(i)
	_check(b2.steps() == p.parts.size() + 3, "one more step for the yard's small things")
	var node := Node3D.new()
	FarmsteadParked.add_to(node, p, 10, func(_q): return 0.0)
	_check(node.get_child_count() >= 3, "the machines are drawn (%d kinds)" % node.get_child_count())
	node.free()
	print("FAIL" if _failed else "PASS", " test_farmstead_parked")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
