extends SceneTree
## Run: godot --headless -s tests/test_tourism.gd

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000.0
	sim.build_county_road(Vector2(-1200, 0), Vector2(1200, 0), [0, 1])
	for x in range(-500, 501, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim.tick()
	_check(sim.stats.population > 40, "homes filled (%d people)" % sim.stats.population)

	# The fairgrounds: a venue with a fair board, placed like any landmark.
	sim.economy.money = 20_000_000.0
	var site := Parks.site_near(sim.network, "fairgrounds", Vector3(0, 0, 40))
	_check(not site.is_empty(), "a fairgrounds site beside the road")
	_check(sim.apply({"type": "place_park", "kind": "fairgrounds", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "fairgrounds placed")
	var fid := -1
	for id in sim.parks.sites:
		if sim.parks.sites[id].kind == "fairgrounds":
			fid = id
	_check(fid != -1, "the fairgrounds is a site")
	_check(not sim.apply({"type": "place_park", "kind": "motel", "pos": [100, 40], "dir": [0, -1]}),
		"a motel can't be placed by hand")
	sim.tick()
	_check(sim.parks.tourism.venues.has(fid), "the fairgrounds has a fair board")
	var v: Dictionary = sim.parks.tourism.venues[fid]
	_check(str(v.leader.get("name", "")).contains(" "), "the fair board has a named leader (%s)" % v.leader.get("name", ""))

	# The grandstand goes up first: no fair while it's being built.
	var ref := "park:%d" % fid
	_check(sim.construction.sites.has(ref), "the fairgrounds goes up in stages")
	sim.parks.tourism._crowd(sim, fid, 7, 9)
	_check(v.crowd.is_empty(), "no fair while it's being built")
	# (Building done; the game would get there in about a month.)
	sim.construction.sites.erase(ref)

	# Run to the fair in July: it opens at 9, people come and go by car.
	var trips0: int = sim.traffic._next_id
	var saw_crowd := false
	while Seasons.month(sim.tick_count) != 8:
		sim.tick()
		if not v.crowd.is_empty():
			saw_crowd = true
	_check(saw_crowd, "the county fair was on in July")
	_check(v.crowd.is_empty(), "the fair closed afterwards")
	_check(v.visitors > 0.0, "people came to the fair (%d)" % v.visitors)
	_check(v.outside > 0.0, "some came from out of town (%d)" % v.outside)
	_check(v.visitors <= Balance.VENUES.fairgrounds.seats + 1, "no more than the grounds hold")
	_check(v.gate > 0.0 and v.savings > 0.0, "the gate money went to the fair board (%.0f)" % v.savings)
	var trips: int = sim.traffic._next_id - trips0
	var most := Balance.TOURISM_MAX_CARS_HOUR * 14 * 2
	_check(trips > 0, "fairgoers drove there (%d trips)" % trips)
	_check(trips < most + 400, "only a sample of cars drives (%d)" % trips)

	# Nothing opens for a few hundred visitors a year.
	_check(not sim.parks.has_kind("gas_station"), "no gas station yet for %d visitors" % v.outside)

	# A big draw: businesses open for visitors one at a time, near the venue.
	v.outside_last = 20_000.0
	var tax0 := sim.parks.tourism.monthly_tax()
	_check(tax0 > 0.0, "visitors' spending is taxed (%.0f a month)" % tax0)
	var jobs0 := Tourism.jobs(sim)
	for k in 4:
		sim.parks.tourism._monthly(sim, 9)
	for b in Balance.TOURISM_BUSINESSES:
		_check(sim.parks.has_kind(b.kind), "a %s opened for the visitors" % b.kind)
	_check(Tourism.jobs(sim) > jobs0, "the businesses hire (%d jobs)" % Tourism.jobs(sim))
	_check(Tourism.taxable_value(sim) > 0.0, "the businesses pay property tax")
	for id in sim.parks.sites:
		var s: Dictionary = sim.parks.sites[id]
		if Tourism.business(s.kind).is_empty():
			continue
		_check(s.pos.distance_to(sim.parks.sites[fid].pos) < Balance.TOURISM_BUSINESS_REACH + 200.0,
			"the %s is near the fairgrounds" % s.kind)
		_check(str(s.name) != "" and not str(s.name).begins_with("The "), "the %s has a name (%s)" % [s.kind, s.name])
		var poly := sim.parks.footprint(id)
		for key in sim.lots:
			_check(not Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), poly),
				"no lot under the %s" % s.kind)
	_check(sim.parks.tourism.venues.size() == 1, "businesses aren't venues")

	# The fair board builds its tree from the gate money.
	v.savings = 5_000_000.0
	v.profit = 1_000_000.0
	for k in 12:
		sim.parks.tourism._monthly(sim, 3)
	_check(v.built.has("midway"), "the board hired a carnival midway (%s)" % str(v.built))
	_check(not v.built.has("show_barns"), "no 4-H barns without farms nearby")
	_check(v.why.begins_with("The fair board built"), "it says why (%s)" % v.why)
	var with_tree := sim.parks.tourism.attendance(sim, fid, Balance.VENUES.fairgrounds.events[0])
	_check(with_tree.visitors > 0, "the fair still draws after building")

	# Football: Friday nights in the fall, with the boosters.
	site = Parks.site_near(sim.network, "football", Vector3(-350, 0, 40))
	if not site.is_empty() and sim.apply({"type": "place_park", "kind": "football", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}):
		sim.tick()
		var fb := -1
		for id in sim.parks.tourism.venues:
			if sim.parks.tourism.venues[id].kind == "football":
				fb = id
		_check(fb != -1, "the football field is a venue")
		_check(not sim.parks.tourism.event_in(fb, 10).is_empty(), "football is on in October")
		_check(sim.parks.tourism.event_in(fb, 2).is_empty(), "no football in February")
	else:
		_check(false, "football field placed (%s)" % ("no site" if site.is_empty() else
			sim.parks.site_problem(sim, "football", site[0], site[1])))

	# The info panel and the save.
	var info := Inspect.describe(sim, {"type": "park", "id": fid})
	var text := JSON.stringify(info)
	_check(text.contains("Fair board"), "the panel names the fair board")
	_check(text.contains("Visitors this year"), "the panel counts visitors")
	var d := sim.to_dict()
	var again := CitySim.new()
	again.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(JSON.stringify(again.parks.to_dict()) == JSON.stringify(sim.parks.to_dict()), "save round trip keeps venues")
	_check(again.parks.tourism.venues.size() == sim.parks.tourism.venues.size(), "venues survive a save")

	# The art builds for every kind.
	for id in sim.parks.sites:
		var s: Dictionary = sim.parks.sites[id].duplicate()
		var vv: Dictionary = sim.parks.tourism.venues.get(id, {})
		s["venue_built"] = vv.get("built", [])
		s["event_on"] = true
		var art := ParkBuilder.build_site(s, 7, 6.0, "Test")
		_check(art[0].get_surface_count() > 0, "the %s has a building" % s.kind)

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)
