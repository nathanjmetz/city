extends SceneTree
## Run: godot --headless -s tests/test_trails.gd

var _failed := false


func _init() -> void:
	# A street about half a kilometre up from the creek south of town.
	var sim := CitySim.new()
	sim.economy.money = 50_000_000.0
	sim.apply({"type": "build_road", "start": [-900, -300], "ctrl": [-300, -300], "end": [300, -300]})
	for x in range(-900, -549, 10):
		sim.apply({"type": "paint_zone", "center": [x, -325], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(-870, -569, 10):
		sim.apply({"type": "paint_zone", "center": [x, -275], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	_check(sim.stats.population > 0, "homes filled (%d people)" % sim.stats.population)

	# The trailhead, between the street and the creek.
	var site := Parks.site_near(sim.network, "trailhead", Vector3(-300, 0, -340))
	_check(not site.is_empty(), "a trailhead site beside the street")
	_check(sim.apply({"type": "place_park", "kind": "trailhead", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "trailhead placed")
	var t := sim.parks.trails
	_check(not t.hub.is_empty(), "the trailhead has a director")
	_check(str(t.hub.leader.get("name", "")).contains(" "), "the director has a name (%s)" % t.hub.leader.get("name", ""))
	var hid := int(t.hub.id)
	_check(not t.creek(sim).is_empty(), "it finds the creek")
	_check(t.problem(sim, "greenway") == "", "a greenway can start (%s)" % t.problem(sim, "greenway"))
	_check(t.problem(sim, "bike_lanes").begins_with("needs the creek greenway"), "bike lanes wait on the greenway")

	# The player says hold off: nothing gets built.
	sim.apply({"type": "guide", "hub": "trails", "hub_id": hid, "stance": "hold"})
	_check(t.problem(sim, "greenway") == "told to hold off", "hold off stops the director")
	sim.apply({"type": "guide", "hub": "trails", "hub_id": hid, "stance": "steady"})

	# A month: the greenway is built and starts along the bank.
	var money := sim.economy.money
	_month(sim)
	_check("greenway" in t.hub.built, "the director built the greenway (%s)" % str(t.hub.built))
	_check(sim.economy.money <= money - 600_000, "the town paid for it")
	_check(t.hub.why.contains("creek greenway"), "it says why (%s)" % t.hub.why)
	var g: Dictionary = t.paths[0]
	_check(g.kind == "greenway" and g.pts.size() >= 2, "a path was laid (%d points)" % g.pts.size())
	var first := t.length()
	_check(first > 0.0 and first <= Balance.TRAIL_GROW_MONTH + 900.0, "it grows a bit at a time (%.0f m)" % first)
	for k in 6:
		_month(sim)
	_check(t.length() > first or bool(g.get("done", false)), "it keeps growing along the bank (%.0f m)" % t.length())
	_check(t.length() <= Agency.effect(t.hub, Balance.TRAIL_TREE, "length+") + 900.0, "up to the mile it was built for")
	var dry := true
	var in_lot := false
	for p in g.pts:
		var q := Vector3(float(p[0]), 0, float(p[1]))
		if Terrain.is_water(q.x, q.z):
			dry = false
		for key in sim.buildings:
			if sim.lots.has(key) and Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), sim.lots[key].corners):
				in_lot = true
	_check(dry, "the path stays out of the water")
	_check(not in_lot, "the path never crosses anyone's lot")
	var mid: Array = g.pts[g.pts.size() / 2]
	var on := Vector3(float(mid[0]), 0, float(mid[1]))
	_check(t.on_path(on) and sim.parks.covers(on), "the trail's strip is kept clear")
	_check(sim.parks.site_upkeep(hid) > Balance.AMENITIES.trailhead.upkeep, "trails add to the upkeep")

	# Connector trails out to a park once the town is big enough.
	var ps := Parks.site_near(sim.network, "park", Vector3(100, 0, -340))
	_check(sim.apply({"type": "place_park", "kind": "park", "pos": [ps[0].x, ps[0].z], "dir": [ps[1].x, ps[1].z]}),
		"a park placed down the street (%s)" % sim.parks.site_problem(sim, "park", ps[0], ps[1]))
	_check(t.problem(sim, "connectors").begins_with("needs 1,000 people"), "connectors wait on the town (%s)" % t.problem(sim, "connectors"))
	sim.stats.population = 2_000
	_month(sim)
	_check("connectors" in t.hub.built, "connector trails built")
	_check(t.paths.any(func(p): return p.kind == "connector"), "a trail runs to the park")

	# Bike lanes go through the bell, then the street is restriped.
	sim.stats.population = 2_000
	for k in 3:
		_month(sim)
	_check("bike_lanes" in t.hub.built, "bike lanes are in the plan (%s)" % str(t.hub.built))
	_check(t.asked.size() == 1, "one street goes to the permit bell")
	var rid: int = t.asked.keys()[0]
	var seg: int = t.asked[rid]
	_check(sim.permits.requests[rid].hub == "trails", "the request is the trails director's")
	_check(sim.network.segments[seg].type == RoadStyle.Type.STREET, "nothing changes before you say yes")
	sim.apply({"type": "permit", "id": rid, "answer": "approve"})
	sim.parks.trails.decide(sim)
	_check(sim.network.segments[seg].type == RoadStyle.Type.STREET_BIKE, "approved: the street gets bike lanes")
	_check(seg in t.lanes and t.asked.is_empty(), "and the director moves on")

	# What trails do: homes near them are worth more, and short trips between
	# places near them often go on foot.
	var keys := []
	for key in sim.buildings:
		if sim.lots.has(key):
			keys.append(key)
	keys.sort()
	var la: Vector3 = sim.lots[keys[0]].pos
	var lb: Vector3 = sim.lots[keys[1]].pos
	t.paths.append({"kind": "connector", "pts": [[la.x, la.z + 40.0], [lb.x, lb.z + 40.0]], "park": -1})
	_check(t.lift(sim, keys[0], "value") > 0.0, "a home by the trail is worth more")
	sim.update_stats()
	_check(sim.parks.lot_value.get(keys[0], 0.0) > 0.0, "and the town counts it")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var walked := 0
	for i in 1000:
		if t.on_foot(sim, keys[0], keys[1], rng):
			walked += 1
	_check(walked > 50 and walked < 300, "some short trips go on foot or by bike (%d of 1000)" % walked)
	var far := CitySim.new()
	_check(not far.parks.trails.on_foot(far, "", "", rng), "no trails: every trip is by car")
	t.paths.pop_back()

	# A pedestrian plaza: cross streets make a downtown block, its shops fill
	# up, and the director asks the bell to close it to cars.
	sim.apply({"type": "build_road", "start": [-880, -250], "ctrl": [-880, -300], "end": [-880, -380]})
	sim.apply({"type": "build_road", "start": [-560, -250], "ctrl": [-560, -300], "end": [-560, -380]})
	for i in 3000:
		sim.tick()
	var on_block := {}
	for key in sim.buildings:
		if sim.lots.has(key):
			var sg := int(sim.lots[key].get("seg", -1))
			on_block[sg] = on_block.get(sg, []) + [key]
	var block := -1
	for sg in on_block:
		if block == -1 or on_block[sg].size() > on_block[block].size():
			block = sg
	_check(block != -1 and on_block[block].size() >= Balance.PLAZA_SHOPS,
		"a block with %d buildings on it" % (on_block[block].size() if block != -1 else 0))
	if block == -1 or on_block[block].size() < Balance.PLAZA_SHOPS:
		print("TESTS FAILED")
		quit(1)
		return
	_check(t.problem(sim, "plaza") != "", "no plaza before there's a busy downtown")
	for key in on_block[block]:
		sim.buildings[key].zone = ZoneMap.Zone.COMMERCIAL
	_check(t.plaza_block(sim) == block, "the shops' block is the busy one (%d)" % t.plaza_block(sim))
	sim.stats.population = 5_000
	# Say no to the next street's bike lanes: one ask at a time.
	for lrid in t.asked.keys():
		sim.apply({"type": "permit", "id": lrid, "answer": "deny"})
	sim.permits.wait_until.clear()  # (a no waits a while before the next ask)
	for k in 3:
		_month(sim)
	_check("plaza" in t.hub.built, "a plaza is in the plan (%s)" % str(t.hub.built))
	_check(t.asked_plaza.size() == 1, "the plaza goes to the permit bell")
	if t.asked_plaza.size() == 1:
		var prid: int = t.asked_plaza.keys()[0]
		_check(t.asked_plaza[prid] == block, "for the busy block")
		_check(not sim.traffic.closed.has(block), "the street stays open until you say yes")
		var before := sim.economy.money
		sim.apply({"type": "permit", "id": prid, "answer": "approve"})
		_month(sim)
		_check(block in t.plazas and t.asked_plaza.is_empty(), "approved: the block is a plaza")
		_check(sim.traffic.closed.has(block), "and closed to cars")
		_check(not sim.traffic.may_enter(block, false), "cars can't drive it")
		_check(sim.economy.money < before, "the town paid for the pavers")
		var shop: String = on_block[block][0]
		_check(t.lift(sim, shop, "value") > 0.0, "shops on the plaza are worth more")
		var art := ParkBuilder.plaza_mesh([{"pts": sim.network.sample_segment(block, 12), "w": 10.0}])
		_check(art[0].get_surface_count() > 0 and art[1].get_surface_count() > 0, "the plaza draws pavers and benches")

	# The panel, the save and the art.
	var info := JSON.stringify(Inspect.describe(sim, {"type": "park", "id": hid}))
	_check(info.contains("Parks and trails") and info.contains("Bike lanes") and info.contains("Plazas"),
		"the panel shows the director, lanes and plazas")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(JSON.stringify(copy.parks.to_dict()) == JSON.stringify(sim.parks.to_dict()), "save round trip keeps the trails")
	var art := ParkBuilder.build_site(sim.parks.sites[hid], 3, 6.0, "Test")
	_check(art[0].get_surface_count() > 0, "the trailhead has a kiosk and a toilet")
	var ribbon := ParkBuilder.trails_mesh(t.paths, func(_p): return false)
	_check(ribbon.get_surface_count() > 0, "the trails draw")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Runs the director's monthly turn now.
func _month(sim: CitySim) -> void:
	sim.parks.trails._month = -1
	sim.parks.trails.decide(sim)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)
