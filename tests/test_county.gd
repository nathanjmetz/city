extends SceneTree
## County roads on the section-line mile grid (CountyGrid).

var _failed := 0


func _init() -> void:
	# Grant County's real roads: on the map, the miles where the county has
	# one (about half of them squared onto the game's exact mile grid), with
	# their real names; past it, where the land mirrors, nearly every mile.
	var have := 0
	var named := 0
	for line in range(-6, 16):
		for seg in range(-8, 14):
			if CountyGrid.has_mile(line, seg):
				have += 1
				named += 1 if CountyGrid.real_name("ns:%d:%d" % [line, seg]) != "" else 0
	var share := have / 484.0
	_check(share > 0.35 and share < 0.9, "the real county roads are on the map (%.2f of the miles)" % share)
	_check(named > have * 0.8, "with their real names (%d of %d)" % [named, have])
	var streets := CitySim.new().streets
	var real_key := ""
	for k in CountyGrid._names:
		real_key = k
		break
	_check(real_key != "" and streets.grid_name(real_key) == CountyGrid.real_name(real_key),
		"a real county road keeps its real name (%s), courthouse or not" % CountyGrid.real_name(real_key))
	have = 0
	for line in range(40, 50):
		for seg in range(40, 50):
			have += 1 if CountyGrid.has_mile(line, seg) else 0
	_check(have > 85, "past the map, nearly every mile has one (%d of 100)" % have)
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
	_test_overlay()
	_test_through_zoning()
	_test_grid_over_joined()
	_test_kept_clear()
	_test_stub()
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
			# and the field a farm road crosses to it, further down
			for k in 11:
				var f := Vector2(cx + 20.0 * k, cz + 300.0)
				level = level and Terrain.water(f.x, f.y) < 0.05 and Terrain.slope(f.x, f.y) < 0.06
			if level:
				x = cx
				z = cz
				found = true
	_check(found, "found a county road to join")
	if not found:
		return
	var real_names: Dictionary = CountyGrid._names
	CountyGrid._names = {}
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

	# Founding the county seat: county roads without a real name (past the
	# map; real ones are tested in _init) are renamed from its courthouse.
	var key: String = sim.county_joined.keys()[0]
	var before := sim.streets.grid_name(key)
	_check(sim.streets.courthouse == Vector2.INF and _named(sim, before), "before a courthouse: %s" % before)
	sim.parks.sites[999] = {"kind": "courthouse", "pos": Vector3(x + 2.0 * CountyGrid.SECTION + 100.0, 0, z)}
	_check(sim.streets.seat(sim), "the courthouse renames the county roads")
	_check(_named_end(sim, " 200 W"), "two miles west of the courthouse is 200 W, signed the Grant County way (N 200 W)")
	sim.parks.sites[999].pos = Vector3(x + 50.0, 0, z)
	sim.streets.seat(sim)
	sim.parks.sites.erase(999)  # a stand-in courthouse, not a full park site
	_check(_named_end(sim, " 00 EW"), "the road through the courthouse's own line is 00 EW")
	CountyGrid._names = real_names
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


## A road drawn along a road already there takes its place instead of
## being laid on top of it.
func _test_overlay() -> void:
	var x := 0.0
	var z := 0.0
	var found := false
	for line in range(-6, 6):
		for seg in range(-6, 6):
			if found or not CountyGrid.has_mile(line, seg):
				continue
			var cx := line * CountyGrid.SECTION
			var cz := (seg + 0.3) * CountyGrid.SECTION
			var dry := true
			for k in range(-4, 16):
				dry = dry and CountyGrid.clears(cx, cz + k * 50.0) and Terrain.water(cx - 150, cz) < 0.05
			if dry:
				x = cx
				z = cz
				found = true
	_check(found, "found a dry county road to draw along")
	if not found:
		return
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [x - 150, z], "ctrl": [x - 75, z], "end": [x, z],
		"road": RoadStyle.Type.STREET, "join": true})
	_check(not _gravel(sim).is_empty(), "the county road is joined first")
	var money := sim.economy.money
	var ok := sim.apply({"type": "build_road", "start": [x, z + 50], "ctrl": [x, z + 300], "end": [x, z + 550],
		"road": RoadStyle.Type.STREET, "join": true})
	_check(ok, "a street drawn along the county road is accepted")
	var length := 0.0
	var gravel_left := false
	for id in sim.network.segments:
		var c := sim.network.curve_of(id)
		var mid: Vector3 = (c[0] + c[2]) * 0.5
		if absf(mid.x - x) < 2.0 and mid.z > z + 50 and mid.z < z + 550:
			length += c[0].distance_to(c[2])
			gravel_left = gravel_left or int(sim.network.segments[id].type) == RoadStyle.Type.GRAVEL
	_check(absf(length - 500.0) < 10.0, "it isn't laid on top of the county road (%d m of road along 500 m)" % length)
	_check(not gravel_left, "that stretch becomes the street")
	_check(money - sim.economy.money <= Economy.road_cost([Vector3(x, 0, z + 50), Vector3(x, 0, z + 300),
		Vector3(x, 0, z + 550)], RoadStyle.Type.STREET), "and costs no more than a new street")
	# A street drawn over a street and on past its end just carries on.
	sim = CitySim.new()
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0], "road": RoadStyle.Type.STREET})
	sim.apply({"type": "build_road", "start": [100, 0], "ctrl": [200, 0], "end": [300, 0], "road": RoadStyle.Type.STREET})
	length = 0.0
	for id in sim.network.segments:
		var c := sim.network.curve_of(id)
		length += c[0].distance_to(c[2])
	_check(absf(length - 300.0) < 5.0, "a street drawn over a street and on past it isn't doubled (%d m)" % length)
	_check(sim.network.segments.size() <= 3, "and is one run of road (%d pieces)" % sim.network.segments.size())


## Brawn (2026-10-24): a county road joined out in the country stopped
## short of the town's street where that street's frontage was zoned, so it
## never met it. It goes through the zoned strip to the street.
func _test_through_zoning() -> void:
	var S := CountyGrid.SECTION
	var x := 0.0
	var z := 0.0
	var found := false
	for line in range(-6, 6):
		for seg in range(-6, 6):
			if found or not CountyGrid.has_mile(line, seg):
				continue
			var cx := line * S
			var cz := (seg + 0.5) * S
			var dry := true
			for k in range(-12, 13):
				dry = dry and CountyGrid.clears(cx, cz + k * 30.0) and Terrain.slope(cx + 150.0, cz + k * 30.0) < 0.06 \
					and Terrain.water(cx + 150.0, cz + k * 30.0) < 0.05
			if dry:
				x = cx
				z = cz
				found = true
	_check(found, "found a dry mile for a town street to cross")
	if not found:
		return
	var sim := CitySim.new()
	var z0 := z - 300.0
	sim.apply({"type": "build_road", "start": [x - 300, z0], "ctrl": [x, z0], "end": [x + 300, z0],
		"road": RoadStyle.Type.STREET})
	for id in sim.network.segments:
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	_check(sim.zones.zone_at(Vector3(x, 0, z0 + 15.0)) != ZoneMap.Zone.NONE, "the street's frontage is zoned over the line")
	sim.apply({"type": "build_road", "start": [x + 200, z + 300], "ctrl": [x + 100, z + 300], "end": [x, z + 300],
		"road": RoadStyle.Type.STREET, "join": true})
	var meet := sim.network.find_node_near(Vector3(x, 0, z0), 1.0)
	var gravel_there := false
	if meet != -1:
		for id in sim.network.segments_at(meet):
			gravel_there = gravel_there or sim.network.segments[id].type == RoadStyle.Type.GRAVEL
	_check(gravel_there, "the joined county road runs through the zoned frontage and meets the street")



## Brawn (2026-10-24): lots keep off a county road, joined or not, as
## fields do (test_farm_roads).
func _test_kept_clear() -> void:
	var S := CountyGrid.SECTION
	var x := 0.0
	var z := 0.0
	var found := false
	for line in range(-6, 6):
		for seg in range(-6, 6):
			if found or not CountyGrid.has_mile(line, seg):
				continue
			var cx := line * S
			var cz := (seg + 0.5) * S
			var dry := true
			for k in range(-12, 13):
				for dx in [-150.0, 150.0]:
					dry = dry and CountyGrid.clears(cx, cz + k * 30.0) and Terrain.slope(cx + dx, cz + k * 30.0) < 0.06 \
						and Terrain.water(cx + dx, cz + k * 30.0) < 0.05
			if dry:
				x = cx
				z = cz
				found = true
	_check(found, "found a dry mile to build beside")
	if not found:
		return
	var sim := CitySim.new()
	# A street crossing the line (not joined), zoned both sides: no lot
	# lies across the county road's gravel.
	sim.apply({"type": "build_road", "start": [x - 300, z], "ctrl": [x, z], "end": [x + 300, z],
		"road": RoadStyle.Type.STREET})
	for id in sim.network.segments:
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim._refresh()
	var over := 0
	for key in sim.lots:
		var lo := INF
		var hi := -INF
		for c in sim.lots[key].corners:
			lo = minf(lo, c.x)
			hi = maxf(hi, c.x)
		if hi > x - CountyGrid.HALF_WIDTH and lo < x + CountyGrid.HALF_WIDTH:
			over += 1
	_check(sim.lots.size() > 10 and over == 0, "no lot is platted across it (%d lots, %d across)" % [sim.lots.size(), over])



## Brawn (2026-10-24): joined county road that had stopped at a farm lane
## ended in round pads, with the painted road carrying on past. A stub on
## the line is taken on along it.
func _test_stub() -> void:
	var S := CountyGrid.SECTION
	var x := 0.0
	var z := 0.0
	var found := false
	for line in range(-6, 6):
		for seg in range(-6, 6):
			if found or not CountyGrid.has_mile(line, seg):
				continue
			var cx := line * S
			var cz := (seg + 0.5) * S
			var dry := true
			for k in range(-25, 26):
				dry = dry and CountyGrid.clears(cx, cz + k * 30.0)
			if dry:
				x = cx
				z = cz
				found = true
	_check(found, "found a dry mile for a stub")
	if not found:
		return
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [x - 300, z], "ctrl": [x - 150, z], "end": [x, z], "road": RoadStyle.Type.STREET})
	sim.network.build_road(Vector3(x, 0, z - 100), Vector3(x, 0, z - 50), Vector3(x, 0, z), RoadStyle.Type.GRAVEL)
	sim.network.build_road(Vector3(x, 0, z), Vector3(x, 0, z + 50), Vector3(x, 0, z + 100), RoadStyle.Type.GRAVEL)
	var before := 0.0
	for c in _gravel(sim):
		before += c[0].distance_to(c[2])
	_check(sim._extend_county_ends(), "the stub on the line is taken on")
	var after := 0.0
	var lo := INF
	var hi := -INF
	for c in _gravel(sim):
		after += c[0].distance_to(c[2])
		for q in [c[0], c[2]]:
			if absf(q.x - x) < 1.0:
				lo = minf(lo, q.z)
				hi = maxf(hi, q.z)
	_check(after > before + 1000.0 and lo < z - 700.0 and hi > z + 700.0,
		"out along the mile both ways (%d m, was %d m; %d..%d)" % [after, before, lo - z, hi - z])
	_check(not sim._extend_county_ends(), "and once is enough")


## Brawn (2026-10-24): a grid whose side lies on a county road the town
## had already joined laid its street over the gravel, leaving a doubled
## stretch, a turnaround bulb and a broken edge street. The grid side takes
## the gravel over in place.
func _test_grid_over_joined() -> void:
	var S := CountyGrid.SECTION
	var x := 0.0
	var z := 0.0
	var found := false
	for line in range(-6, 6):
		for seg in range(-6, 6):
			if found or not CountyGrid.has_mile(line, seg):
				continue
			var ok := true
			for k in range(-12, 13):
				ok = ok and CountyGrid.clears(line * S, (seg + 0.5) * S + k * 30.0) \
					and Terrain.slope(line * S - 200.0, (seg + 0.5) * S + k * 30.0) < 0.06
			if ok:
				x = line * S
				z = (seg + 0.5) * S
				found = true
	_check(found, "found a dry mile for a grid beside it")
	if not found:
		return
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [x - 200, z + 400], "ctrl": [x - 100, z + 400], "end": [x, z + 400],
		"road": RoadStyle.Type.STREET, "join": true})
	sim.apply({"type": "build_grid", "a": [x - 357, z - 200], "b": [x + 3, z - 200], "c": [x - 357, z + 40],
		"block": 120.0, "join": true})
	var ids := sim.network.segments.keys()
	var doubled := 0
	for i in ids.size():
		var ci: Array = sim.network.curve_of(ids[i])
		var mid: Vector3 = (ci[0] + ci[2]) * 0.5
		if absf(mid.x - x) > 15.0 or mid.z < z - 300.0 or mid.z > z + 100.0 or ci[0].distance_to(ci[2]) < 10.0:
			continue
		for j in ids.size():
			if i == j:
				continue
			var cj: Array = sim.network.curve_of(ids[j])
			if Geometry3D.get_closest_point_to_segment(mid, cj[0], cj[2]).distance_to(mid) < 4.0:
				doubled += 1
	var dead := 0
	for n in sim.network.nodes:
		var p: Vector3 = sim.network.nodes[n]
		if absf(p.x - x) < 30.0 and p.z > z - 300.0 and p.z < z + 100.0 and sim.network.segments_at(n).size() == 1:
			dead += 1
	_check(doubled == 0 and dead == 0,
		"a grid side on joined gravel takes it over: no doubled road (%d), no dead ends (%d)" % [doubled, dead])


func _gravel(sim: CitySim) -> Array:
	var out := []
	for id in sim.network.segments:
		if sim.network.segments[id].type == RoadStyle.Type.GRAVEL:
			out.append(sim.network.curve_of(id))
	return out


func _named_end(sim: CitySim, tail: String) -> bool:
	for id in sim.network.segments:
		if sim.streets.name_of(id).ends_with(tail) and sim.streets.name_of(id).length() <= tail.length() + 2:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
