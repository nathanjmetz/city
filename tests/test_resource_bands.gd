extends SceneTree
## Run: godot --headless -s tests/test_resource_bands.gd
## Resource views: soil and deposits show in flat steps with a line where
## the ground starts to pay, and farms and companies read the same land the
## view draws, even in a region town far from the map's origin.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	var line := InfoView.threshold(Resources.Kind.FERTILITY, sim)
	_check(line > 0.35 and line < 0.9, "the farmable line sits inside the soil range (%.2f)" % line)
	var best := -INF
	for crop in CropPlan.CROPS:
		best = maxf(best, CropPlan.net_per_acre(crop, "", 0.5, line + 0.05, sim.farms.price))
	_check(best > 0.0, "soil just above the line pays")
	# 20 points of fertility is never the same colour above the line.
	var a := InfoView.band_color(InfoView.Mode.FERTILITY, line + 0.02, line)
	var b := InfoView.band_color(InfoView.Mode.FERTILITY, line + 0.22, line)
	_check(a != b, "20 points apart reads as two colours")
	_check(InfoView.band(line - 0.01, line) == -1, "below the line is greyed out")
	_check(InfoView.band(1.0, line) == InfoView.BANDS - 1, "the best soil is the top step")
	_check(InfoView.band_color(InfoView.Mode.FERTILITY, 0.0, line).a == 0.0, "water stays clear")
	var ore := InfoView.band_color(InfoView.Mode.ORE, Industry.MIN_RICHNESS - 0.01, Industry.MIN_RICHNESS)
	_check(ore == InfoView.RAMPS[InfoView.Mode.ORE][0], "thin ore is grey")
	# A region town reads the land under it, not the map's origin, and a
	# neighbour's copy loading does not move it.
	var mine := CitySim.new()
	mine.terrain_offset = Vector2(9000, -6000)
	Resources.pin(mine.terrain_offset)
	var other := CitySim.new()
	other.terrain_offset = Vector2(-20000, 4000)
	var p := Vector3(130, 0, 270)
	_check(is_equal_approx(Farms.fertility_at(p), Resources.at(Resources.Kind.FERTILITY, p, Vector2(9000, -6000))),
		"farms read the soil the view draws")
	_check(is_equal_approx(Resources.at(Resources.Kind.ORE, p), Resources.at(Resources.Kind.ORE, p, Vector2(9000, -6000))),
		"companies read the ore the view draws")
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
