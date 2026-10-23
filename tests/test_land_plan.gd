extends SceneTree
## Run: godot --headless -s tests/test_land_plan.gd
## The future land use map (LandPlan): outlined areas, later ones winning,
## erasing cuts them back, and a save keeps it.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	_check(not sim.apply({"type": "paint_plan", "points": [[0, 0], [100, 0], [100, 100]], "kind": "parking"}), "an unknown kind is refused")
	_check(not sim.apply({"type": "paint_plan", "points": [[0, 0], [100, 0], [100, 100]], "kind": ""}), "nothing to erase on an empty plan")
	_check(sim.apply({"type": "paint_plan", "points": [[0, 0], [1000, 0], [1000, 1000], [0, 1000]], "kind": "homes"}), "an area for homes")
	_check(sim.land_plan.kind_at(Vector3(500, 0, 500)) == "homes", "inside it is planned for homes")
	_check(sim.land_plan.kind_at(Vector3(1500, 0, 500)) == "", "outside it there's no plan")
	# Shops along one edge: cut out of the homes area.
	sim.apply({"type": "paint_plan", "points": [[800, -100], [1100, -100], [1100, 1100], [800, 1100]], "kind": "shops"})
	_check(sim.land_plan.kind_at(Vector3(900, 0, 500)) == "shops", "a later area wins")
	_check(sim.land_plan.outlines.size() == 2, "the older area was cut back, not stacked (%d pieces)" % sim.land_plan.outlines.size())
	# Erase a strip across the middle: the homes area splits in two.
	sim.apply({"type": "paint_plan", "points": [[-50, 450], [850, 450], [850, 550], [-50, 550]], "kind": ""})
	_check(sim.land_plan.kind_at(Vector3(400, 0, 500)) == "", "erased land has no plan")
	_check(sim.land_plan.kind_at(Vector3(400, 0, 200)) == "homes" and sim.land_plan.kind_at(Vector3(400, 0, 800)) == "homes",
		"the rest stays planned")
	# Erase a hole in the middle of one piece.
	sim.apply({"type": "paint_plan", "points": [[300, 100], [400, 100], [400, 200], [300, 200]], "kind": ""})
	_check(sim.land_plan.kind_at(Vector3(350, 0, 150)) == "", "a hole erases too")
	_check(sim.land_plan.kind_at(Vector3(100, 0, 100)) == "homes", "around the hole is still homes")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for p in [Vector3(350, 0, 150), Vector3(100, 0, 100), Vector3(900, 0, 500), Vector3(400, 0, 500)]:
		_check(copy.land_plan.kind_at(p) == sim.land_plan.kind_at(p), "a save keeps the plan at %s" % p)
	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true
