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
	_check(share > 0.9 and share < 0.99, "nearly every mile of section line has a county road (%.2f)" % share)
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
	_test_join()
	_test_remove()
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


## Drawing a road onto a county road out in the country joins that mile.
func _test_join() -> void:
	# A north-south mile on dry, level land near the middle of the map.
	var x := 0.0
	var z := 0.0
	var found := false
	for line in range(-6, 6):
		for seg in range(-6, 6):
			if found or not CountyGrid.has_mile(line, seg):
				continue
			var cx := line * CountyGrid.SECTION
			var cz := (seg + 0.5) * CountyGrid.SECTION
			var level := true
			for k in range(-3, 4):
				var q := cz + k * 60.0
				level = level and Terrain.water(cx + 120, q) < 0.05 and Terrain.slope(cx + 120, q) < 0.06 \
					and CountyGrid.clears(cx, q)
			if level:
				x = cx
				z = cz
				found = true
	_check(found, "found a county road to join")
	if not found:
		return
	var sim := CitySim.new()
	var money := sim.economy.money
	var ok := sim.apply({"type": "build_road", "start": [x + 120, z], "ctrl": [x + 60, z], "end": [x, z],
		"road": RoadStyle.Type.STREET})
	_check(ok, "a street can be drawn up to the county road")
	_check(sim.county_joined.is_empty(), "building a road alone never joins one (the road tool asks)")
	sim.apply({"type": "join_county", "at": [x, z]})
	_check(sim.county_joined.size() == 1, "the street joins the county road's mile to town")
	var gravel := 0.0
	for id in sim.network.segments:
		if sim.network.segments[id].type == RoadStyle.Type.GRAVEL:
			var c: Array = sim.network.curve_of(id)
			gravel += c[0].distance_to(c[2])
			_check(absf(c[0].x - x) < 0.5 and absf(c[2].x - x) < 0.5, "the joined road runs down the section line")
	_check(gravel > 300.0, "the joined mile is a gravel road of the town's own (%d m)" % gravel)
	var street_cost := Economy.road_cost([Vector3(x + 120, 0, z), Vector3(x + 60, 0, z), Vector3(x, 0, z)],
		RoadStyle.Type.STREET)
	_check(absf(money - street_cost - sim.economy.money) < 1.0, "the county hands its road over free")
	var segs := sim.network.segments.size()
	sim.apply({"type": "join_county", "at": [x, z + 10.0]})
	_check(sim.network.segments.size() == segs, "a mile is only joined once")
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	_check(copy.county_joined.size() == 1, "joined county roads are saved")

	# Founding the county seat: county roads are renamed from its courthouse.
	var key: String = sim.county_joined.keys()[0]
	var before := sim.streets.grid_name(key)
	_check(sim.streets.courthouse == Vector2.INF and _named(sim, before), "before a courthouse: %s" % before)
	sim.parks.sites[999] = {"kind": "courthouse", "pos": Vector3(x + 2.0 * CountyGrid.SECTION + 100.0, 0, z)}
	_check(sim.streets.seat(sim), "the courthouse renames the county roads")
	_check(_named(sim, "County Road 200 W"), "two miles west of the courthouse is County Road 200 W")
	sim.parks.sites[999].pos = Vector3(x + 50.0, 0, z)
	sim.streets.seat(sim)
	sim.parks.sites.erase(999)  # a stand-in courthouse, not a full park site
	_check(_named(sim, "Meridian Road"), "the road through the courthouse's own line is Meridian Road")
	var saved := CitySim.new()
	saved.from_dict(sim.to_dict())
	_check(saved.streets.courthouse.is_equal_approx(sim.streets.courthouse), "the county seat is saved")


func _named(sim: CitySim, name: String) -> bool:
	for id in sim.network.segments:
		if sim.streets.name_of(id) == name:
			return true
	return false


## Bulldozing a scenery mile takes it off the map for good.
func _test_remove() -> void:
	var sim := CitySim.new()
	var heard := [0]
	sim.county_changed.connect(func() -> void: heard[0] += 1)
	_check(not sim.apply({"type": "remove_county", "key": "nonsense"}), "only real county miles can be bulldozed")
	_check(sim.apply({"type": "remove_county", "key": "ns:-3:2"}), "a county mile can be bulldozed")
	_check(heard[0] == 1, "the ground hears a mile was bulldozed")
	_check(not sim.apply({"type": "remove_county", "key": "ns:-3:2"}), "a mile is only bulldozed once")
	_check(not sim.apply({"type": "join_county", "at": [-3 * CountyGrid.SECTION, 2.5 * CountyGrid.SECTION]}),
		"a bulldozed mile can't be joined")
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	_check(copy.county_removed.has("ns:-3:2"), "bulldozed county roads are saved")
	sim.apply({"type": "clear"})
	_check(sim.county_removed.is_empty() and heard[0] == 2, "starting over brings the county roads back")
	var img := CountyGrid.hidden_texture(["ns:-3:2", "ew:5:70"]).get_image()
	_check(img.get_pixel(61, 2).r > 0.5 and img.get_pixel(61, 2).g < 0.5, "the ground hides the bulldozed north-south mile")
	_check(img.get_pixel(5, 6).g > 0.5 and img.get_pixel(5, 6).r < 0.5, "and an east-west one, wrapped")
	_check(img.get_pixel(0, 0).r < 0.5, "and leaves the rest")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
