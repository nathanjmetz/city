extends SceneTree
## County roads on the section-line mile grid (CountyGrid).

var _failed := 0


func _init() -> void:
	# About three miles of line in four have a road.
	var have := 0
	for line in range(-20, 20):
		for seg in range(-20, 20):
			if CountyGrid.has_mile(line, seg):
				have += 1
	var share := have / 1600.0
	_check(share > 0.65 and share < 0.8, "most miles of section line have a county road (%.2f)" % share)
	_check(CountyGrid.mix(3, -7) == CountyGrid.mix(3, -7) and CountyGrid.mix(3, -7) != CountyGrid.mix(-7, 3),
		"the road layout is the same on every computer")
	_check(CountyGrid.mix(-123456, 98765) >= 0 and CountyGrid.mix(-123456, 98765) <= 0xffffffff,
		"the hash stays in 32 bits, as the shader's does")
	# Find a mile with a road, and check its line is where the grid says.
	var found := false
	for line in range(0, 40):
		if CountyGrid.has_mile(line, 0):
			var x := line * CountyGrid.SECTION
			_check(CountyGrid.distance(x + 2.0, 800.0) <= 2.0 + 0.001, "a county road runs down its section line")
			found = true
			break
	_check(found, "some north-south line has a road in its first mile")
	# Nowhere is a road more than half a mile from a section line.
	_check(CountyGrid.distance(CountyGrid.SECTION * 0.5, CountyGrid.SECTION * 0.5) >= CountyGrid.SECTION * 0.49,
		"no county road through the middle of a section")
	# Trees keep off a road on dry, level land, but not off the water.
	var dry := false
	for line in range(-10, 10):
		for seg in range(-10, 10):
			if dry or not CountyGrid.has_mile(line, seg):
				continue
			var x := line * CountyGrid.SECTION
			var z := (seg + 0.5) * CountyGrid.SECTION
			if Terrain.water(x, z) < 0.05 and Terrain.slope(x, z) < 0.05:
				_check(CountyGrid.clears(x, z) and not CountyGrid.clears(x + 30.0, z),
					"the road and its verge are cleared of trees, the field beside it isn't")
				dry = true
	_check(dry, "found a county road on dry level land")
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
