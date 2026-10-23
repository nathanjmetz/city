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
	_test_adopt()
	_test_meet()
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
	# A farm or company road heading for the county road comes out on it,
	# and the town takes over that mile, instead of a road of its own.
	var hub := CitySim.new()
	hub.apply({"type": "build_road", "start": [x + 120, z], "ctrl": [x + 60, z], "end": [x, z],
		"road": RoadStyle.Type.STREET})
	var far := Vector3(x + 200.0, 0.0, z + 300.0)
	var start := HubRoads.reach(hub, far, Vector3(-1, 0, 0), 400.0)
	_check(start != Vector3.INF and absf(start.x - x) < 0.5, "a hub's road reaches the county road (%s)" % str(start))
	if start != Vector3.INF:
		var plan := HubRoads.check(hub, [start, far], "farm:1")
		_check(plan.ok and not plan.permit, "it may build out to it (%s)" % plan.why)
		_check(not HubRoads.build(hub, plan.route).is_empty() and hub.county_joined.size() == 1,
			"building it joins the county mile to town")
	var lone := CitySim.new()
	_check(HubRoads.reach(lone, far, Vector3(-1, 0, 0), 400.0) == Vector3.INF,
		"a county road that meets no town road isn't a way into town")

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


## A road or a grid drawn onto a county road takes it over where it runs:
## the county road isn't moved, doubled or laid through the town's blocks.
func _test_adopt() -> void:
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
			for k in range(-12, 13):
				var q := cz + k * 60.0
				level = level and CountyGrid.clears(cx, q) and Terrain.water(cx + 300, q) < 0.05 \
					and Terrain.water(cx - 300, q) < 0.05
			if level:
				x = cx
				z = cz
				found = true
	_check(found, "found a long dry county road")
	if not found:
		return
	# A street drawn across it.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [x - 150, z], "ctrl": [x, z], "end": [x + 150, z],
		"road": RoadStyle.Type.STREET, "join": true})
	var gravel := _gravel(sim)
	_check(gravel.size() >= 2, "a street across a county road takes it over (%d pieces)" % gravel.size())
	var on_line := true
	for c in gravel:
		on_line = on_line and absf(c[0].x - x) < 0.5 and absf(c[2].x - x) < 0.5
	_check(on_line, "right where the county road ran, not moved")
	var meets := false
	for c in gravel:
		meets = meets or c[0].distance_to(Vector3(x, 0, z)) < 0.5 or c[2].distance_to(Vector3(x, 0, z)) < 0.5
	_check(meets, "and it meets the street there")
	# A grid laid across it: the county road runs on from its edges, but not
	# through its blocks.
	sim = CitySim.new()
	sim.apply({"type": "build_grid_shape", "points": [[x - 250, z - 250], [x + 250, z - 250], [x + 250, z + 250],
		[x - 250, z + 250]], "block": 100, "road": RoadStyle.Type.STREET, "join": true})
	gravel = _gravel(sim)
	var inside := 0
	var outside := 0
	for c in gravel:
		var mid: Vector3 = (c[0] + c[2]) * 0.5
		if absf(mid.z - z) < 249.0:
			inside += 1
		else:
			outside += 1
	_check(outside >= 2 and inside == 0, "a grid takes the county road on from its edges, not through its blocks (%d out, %d in)" % [outside, inside])
	# It stops short of zoned lots.
	sim = CitySim.new()
	sim.apply({"type": "paint_zone", "center": [x, z + 300], "radius": 30, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.apply({"type": "build_road", "start": [x - 150, z], "ctrl": [x, z], "end": [x + 150, z],
		"road": RoadStyle.Type.STREET, "join": true})
	var past := false
	for c in _gravel(sim):
		past = past or c[0].z > z + 265.0 or c[2].z > z + 265.0
	_check(not past, "and stops short of zoned lots")


## Roads drawn to a county road always meet it: at a crossing of two, just
## short of one, or at the edge of the town's land.
func _test_meet() -> void:
	var S := CountyGrid.SECTION
	var x := 0.0
	var z := 0.0
	var found := false
	for lx in range(-6, 6):
		for lz in range(-6, 6):
			if found or not (CountyGrid.has_mile(lx, lz) and CountyGrid.has_mile(lx, lz - 1)
					and CountyGrid.has_mile(lz + (1 << 20), lx) and CountyGrid.has_mile(lz + (1 << 20), lx - 1)):
				continue
			var dry := true
			for k in range(-10, 11):
				dry = dry and CountyGrid.clears(lx * S + k * 30, lz * S) and CountyGrid.clears(lx * S, lz * S + k * 30) \
					and CountyGrid.clears(lx * S, lz * S + 500 + k * 10)
			if dry:
				x = lx * S
				z = lz * S
				found = true
	_check(found, "found a dry crossing of two county roads")
	if not found:
		return
	# A road ending right at the crossing takes on all four roads out of it.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [x - 200, z - 200], "ctrl": [x - 100, z - 100], "end": [x, z],
		"road": RoadStyle.Type.STREET, "join": true})
	_check(sim.county_joined.size() == 4, "a road to a crossing of county roads takes on all four (%d)" % sim.county_joined.size())
	var corner := sim.network.find_node_near(Vector3(x, 0, z), 0.5)
	_check(corner != -1 and sim.network.segments_at(corner).size() == 5, "and they all meet there")
	# A road ending a few metres short is taken on to it.
	sim = CitySim.new()
	sim.apply({"type": "build_road", "start": [x - 200, z + 500], "ctrl": [x - 100, z + 500], "end": [x - 6, z + 500],
		"road": RoadStyle.Type.STREET, "join": true})
	var end := sim.network.find_node_near(Vector3(x - 6, 0, z + 500), 0.5)
	_check(end != -1 and sim.network.segments_at(end).size() == 2, "a road ending just short of a county road meets it")
	var on := sim.network.find_node_near(Vector3(x, 0, z + 500), 0.5)
	_check(on != -1 and sim.network.segments_at(on).size() == 3, "joining it on the line")
	# Only as far as the town's land, but right up to its edge.
	sim = CitySim.new()
	sim.land_check = func(pts: Array) -> String:
		for q in pts:
			if q.y > z + 700.0:
				return "Not your land."
		return ""
	sim.apply({"type": "build_road", "start": [x - 200, z + 500], "ctrl": [x - 100, z + 500], "end": [x, z + 500],
		"road": RoadStyle.Type.STREET, "join": true})
	var reach := -INF
	for c in _gravel(sim):
		reach = maxf(reach, maxf(c[0].z, c[2].z))
	_check(reach > z + 680.0 and reach <= z + 700.0, "the county road is taken up to the edge of the town's land (%d m)" % (reach - z - 500))


func _gravel(sim: CitySim) -> Array:
	var out := []
	for id in sim.network.segments:
		if sim.network.segments[id].type == RoadStyle.Type.GRAVEL:
			out.append(sim.network.curve_of(id))
	return out


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
