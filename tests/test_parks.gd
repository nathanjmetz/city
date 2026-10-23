extends SceneTree
## Run: godot --headless -s tests/test_parks.gd

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in range(-300, 301, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(-300, -119, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in 6000:
		sim.tick()
	_check(sim.stats.population > 40, "homes filled (%d people)" % sim.stats.population)

	# Placing a park on the open south side.
	var money := sim.economy.money
	var site := Parks.site_near(sim.network, "park", Vector3(0, 0, 40))
	_check(not site.is_empty(), "a park site beside the road")
	_check(sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"park placed")
	_check(sim.economy.money == money - Balance.PARK_COST, "park paid for")
	var pid: int = sim.parks.sites.keys()[0]
	var park: Dictionary = sim.parks.sites[pid]
	_check(park.name.ends_with(" Park"), "the park has a name (%s)" % park.name)
	_check(park.tier >= 0, "the park knows its neighborhood tier (%d)" % park.tier)
	for key in sim.lots:
		_check(not sim.parks.covers(sim.lots[key].pos), "no lot left on the park")
	# Not on top of homes, and not twice in the same place.
	var on_homes := Parks.site_near(sim.network, "park", Vector3(0, 0, -40))
	_check(sim.parks.site_problem(sim, "park", on_homes[0], on_homes[1]) != "", "a park can't go on top of homes")
	_check(not sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"two parks can't overlap")

	# Landmarks are one per town.
	var lm := Parks.site_near(sim.network, "water_tower", Vector3(200, 0, 40))
	_check(sim.apply({"type": "place_park", "kind": "water_tower", "pos": [lm[0].x, lm[0].z], "dir": [lm[1].x, lm[1].z]}),
		"water tower placed")
	var lm2 := Parks.site_near(sim.network, "water_tower", Vector3(-200, 0, 40))
	_check(not sim.apply({"type": "place_park", "kind": "water_tower", "pos": [lm2[0].x, lm2[0].z], "dir": [lm2[1].x, lm2[1].z]}),
		"only one water tower landmark per town")

	# The park fills in over time, in order, and grows only next to itself.
	var area0: float = park.size.x * park.size.y
	var poly0 := sim.parks.footprint(pid)
	for i in 1440 * 24:
		sim.tick()
	var types: Array = park.features.map(func(f): return f.type)
	_check(types.size() >= 3 and types[0] == "paths" and types[1] == "playground",
		"park filled in with paths, then a playground (%s)" % str(types))
	_check(park.size.x * park.size.y > area0, "the park bought land next door to fit more (%.0f -> %.0f m2)" % [area0, park.size.x * park.size.y])
	_check(park.size.x * park.size.y <= area0 * Balance.HUB_MAX_GROWTH + 1.0, "growth stays under the hub cap")
	var poly1 := sim.parks.footprint(pid)
	_check(not Geometry2D.intersect_polygons(poly0, poly1).is_empty() and Geometry2D.is_point_in_polygon(
		(poly0[0] + poly0[2]) * 0.5, poly1), "it grew around where it started (no second site)")
	for f in park.features:
		if f.size != Vector2.ZERO:
			for c in Parks.corners(f.pos, park.dir, f.size):
				_check(Geometry2D.is_point_in_polygon(c, poly1.duplicate()) or _near_poly(c, poly1), "%s sits inside the park" % f.type)
	_check(Services.road_clash(sim.network, poly1) == false, "a growing park never runs onto a road")

	# Homes near the park are worth more and pay more tax; people like it.
	var near_key := ""
	var far_key := ""
	for key in sim.buildings:
		var d := sim.parks.distance_to(pid, sim.lots[key].pos)
		if d < 60.0 and near_key == "":
			near_key = key
		if d > 400.0 and sim.parks.distance_to(2, sim.lots[key].pos) > 600.0 and far_key == "":
			far_key = key
	_check(near_key != "" and sim.parks.lot_value.get(near_key, 0.0) > 0.03,
		"a home by the park gets a land value lift (%.3f)" % sim.parks.lot_value.get(near_key, 0.0))
	_check(far_key == "" or sim.parks.lot_value.get(far_key, 0.0) < sim.parks.lot_value.get(near_key, 0.0),
		"the lift fades with distance")
	var b: Dictionary = sim.buildings[near_key]
	_check(sim.economy.building_tax(b, 1.0, sim.parks.lot_value[near_key]) > sim.economy.building_tax(b, 1.0),
		"its property tax rises with the lift")
	_check(sim.parks.average_happiness(sim) > 0.0, "parks make residents happier (%.3f)" % sim.parks.average_happiness(sim))
	_check(sim.economy.budget.services >= sim.parks.monthly_upkeep(), "park upkeep is in the budget")
	_check(Inspect.pick(sim, park.pos).get("type", "") == "park", "clicking a park selects it")
	_check(Inspect.describe(sim, {"type": "park", "id": pid}).title == park.name, "the park describes itself")

	# Saves and copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(JSON.stringify(copy.parks.to_dict()) == JSON.stringify(sim.parks.to_dict()), "save round trip keeps parks")
	for i in 2000:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.parks.to_dict()) == JSON.stringify(sim.parks.to_dict()), "copies stay in sync")

	# Neighborhood character moves slowly and doesn't flicker.
	_check(Neighborhood.tier_for(0.82, -1) == 3 and Neighborhood.tier_for(0.1, -1) == 0, "scores map to tiers")
	_check(Neighborhood.tier_for(0.57, 1) == 1, "a tier only rises once past the line by the margin")
	_check(Neighborhood.tier_for(0.52, 2) == 2, "and only drops once below it by the margin")
	var up := Neighborhood.follow(0.2, 0.8, Balance.HOOD_HALF_LIFE_DAYS)
	var down := Neighborhood.follow(0.8, 0.2, Balance.HOOD_HALF_LIFE_DAYS)
	_check(absf(up - 0.5) < 0.001, "half the gap closes in a half-life (%.3f)" % up)
	_check(0.8 - down > up - 0.2, "decline is faster than improvement")

	# A struggling neighborhood's park stays plain: no court, no fountain.
	var s := CitySim.new()
	s.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	var ss := Parks.site_near(s.network, "park", Vector3(0, 0, 40))
	s.apply({"type": "place_park", "kind": "park", "pos": [ss[0].x, ss[0].z], "dir": [ss[1].x, ss[1].z]})
	var sp: Dictionary = s.parks.sites.values()[0]
	sp.score = 0.05
	sp.tier = 0
	for i in 1440 * 20:
		s.tick()
	var st: Array = sp.features.map(func(f): return f.type)
	_check("playground" in st and not "court" in st and not "fountain" in st,
		"a struggling park gets the basics only (%s)" % str(st))
	_check(sp.size == Balance.PARK_START_SIZE, "a struggling park doesn't buy land")

	# The road wins: a street through the park cuts it back, and one through
	# a landmark bulldozes it and pays it back.
	var before: Vector2 = sp.size
	var cx: float = sp.pos.x + sp.size.x * 0.25
	s.apply({"type": "build_road", "start": [cx, 0], "ctrl": [cx, 60], "end": [cx, 140]})
	_check(not s.parks.sites.is_empty() and sp.size.x < before.x, "a road cuts a park back (%s -> %s)" % [before, sp.size])
	_check(not RoadWins.hits(RoadWins.corridors(s.network, RoadWins.BUILDING_SLACK), s.parks.footprint(s.parks.sites.keys()[0])),
		"nothing of the park is left on the road")
	var tw := Parks.site_near(s.network, "football", Vector3(-80, 0, -60))
	s.economy.money = 20_000_000
	var m0 := s.economy.money
	_check(s.apply({"type": "place_park", "kind": "football", "pos": [tw[0].x, tw[0].z], "dir": [tw[1].x, tw[1].z]}), "football field placed")
	var fx: float = tw[0].x
	s.apply({"type": "build_road", "start": [fx, -20], "ctrl": [fx, -80], "end": [fx, -160]})
	_check(not s.parks.has_kind("football"), "a road through a landmark bulldozes it")
	_check(s.economy.money > m0 - Parks.cost_of("football"), "and pays it back")
	# Removing it frees the ground.
	s.apply({"type": "remove_park", "id": s.parks.sites.keys()[0]})
	_check(s.parks.sites.is_empty(), "park removed")
	_tree()
	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	_park_sizes()
	quit(1 if _failed else 0)


## The size row: each NRPA class places at its own acreage, cost and reach.
func _park_sizes() -> void:
	var reach := []
	for i in Balance.PARK_SIZES.size():
		var ps: Dictionary = Balance.PARK_SIZES[i]
		var sim := CitySim.new()
		sim.economy.money = 10_000_000
		sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
		var site := Parks.site_near(sim.network, "park", Vector3(0, 0, 40), i)
		var money := sim.economy.money
		_check(sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z],
			"dir": [site[1].x, site[1].z], "size": i}), "%s park placed" % ps.name)
		var pid: int = sim.parks.sites.keys()[0]
		_check(sim.economy.money == money - int(ps.cost), "%s park paid for" % ps.name)
		_check(absf(sim.parks.acres(pid) - ps.size.x * ps.size.y / 4046.86) < 0.01, "%s park is %.1f acres" % [ps.name, sim.parks.acres(pid)])
		reach.append(sim.parks.reach_of(pid))
		var copy := CitySim.new()
		copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
		_check(int(copy.parks.sites[pid].get("class", -1)) == i, "%s park's size saved" % ps.name)
	_check(reach[0] < reach[1] and reach[1] < reach[2], "bigger parks draw from further off")
	var acres: Array = Balance.PARK_SIZES.map(func(ps): return ps.size.x * ps.size.y / 4046.86)
	_check(acres[0] < 1.0 and absf(acres[1] - 5.0) < 0.3 and absf(acres[2] - 20.0) < 0.5,
		"sizes follow NRPA: under an acre, about 5, about 20 (%s)" % str(acres))


func _near_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	for i in poly.size():
		if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < 0.01:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


## The park development tree: what each step waits on, the board building
## and paying for it, and the player's word to the board.
func _tree() -> void:
	var t := CitySim.new()
	t.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
	var ps := Parks.site_near(t.network, "park", Vector3(0, 0, 40))
	t.economy.money = 50_000_000
	t.apply({"type": "place_park", "kind": "park", "pos": [ps[0].x, ps[0].z], "dir": [ps[1].x, ps[1].z]})
	var tid: int = t.parks.sites.keys()[0]
	var pk: Dictionary = t.parks.sites[tid]
	_check(str(pk.leader.name) != "", "the park board has a chair (%s)" % pk.leader.name)
	pk.tier = 3
	pk.score = 0.9
	for type in ["paths", "playground", "pavilion", "ball_diamond"]:
		pk.features.append({"type": type, "pos": pk.pos, "size": Vector2.ZERO})
	t.stats.population = 3_000
	_check(t.parks.tree_problem(t, tid, "all_abilities").begins_with("needs the splash pad"),
		"a step waits on the one before it (%s)" % t.parks.tree_problem(t, tid, "all_abilities"))
	_check(t.parks.tree_problem(t, tid, "splash_pad") == "needs town water", "a splash pad needs town water")
	_check(t.parks.tree_problem(t, tid, "field_lights") == "needs town power", "field lights need power")
	for e in [[Services.Kind.WATER_TOWER, -300.0], [Services.Kind.SUBSTATION, 300.0]]:
		var site := Services.site_near(t.network, e[0], Vector3(e[1], 0, -40))
		t.apply({"type": "place_service", "kind": e[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	_check(t.parks.tree_problem(t, tid, "splash_pad") == "", "with water, the splash pad is next")
	_check(t.parks.tree_problem(t, tid, "youth_complex").begins_with("needs the field lights"), "the complex waits on lights")
	var up0 := t.parks.site_upkeep(tid)
	var m0 := t.economy.money
	var hold := t.apply({"type": "guide", "hub": "park", "hub_id": tid, "stance": "hold", "grant": 0})
	_check(hold and t.parks.tree_problem(t, tid, "splash_pad") == "told to hold off", "told to hold off, the board waits")
	for i in 4:
		t.parks._fill_in(t, tid, 100)
	_check(not t.parks.has_feature(tid, "splash_pad"), "and builds nothing from its tree")
	t.apply({"type": "guide", "hub": "park", "hub_id": tid, "stance": "steady", "grant": 0})
	for i in 40:
		t.stats.population = 3_000
		t.parks._fill_in(t, tid, 100)
	for key in ["splash_pad", "field_lights", "bandstand", "walking_loop", "pool"]:
		_check(t.parks.has_feature(tid, key), "the board added the %s" % key)
	_check(t.parks.tree_problem(t, tid, "youth_complex").contains("school"), "the youth complex needs a school nearby")
	_check(t.economy.money < m0 - Parks.node("pool").cost, "the board paid for what it built")
	_check(t.parks.site_upkeep(tid) > up0, "and it costs more to keep up")
	_check(t.parks.tree_lift(tid, "happy") > 0.1, "tree items make the park pull harder (%.2f)" % t.parks.tree_lift(tid, "happy"))
	var d := Inspect.describe(t, {"type": "park", "id": tid})
	var labels: Array = d.rows.map(func(r): return r[0])
	_check("Play" in labels and "Sports" in labels and "Park board" in labels, "the info panel shows the tree (%s)" % str(labels))
	_check(HubSliders.takes(t, {"type": "park", "id": tid}), "the player can guide the park board")
	for f in pk.features:
		if f.size != Vector2.ZERO:
			_check(t.parks._inside(tid, f.pos, f.size), "%s fits inside the park" % f.type)
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	_check(JSON.stringify(copy.parks.to_dict()) == JSON.stringify(t.parks.to_dict()), "save keeps the tree and board")
	var art := ParkBuilder.build_site(pk, 7, 8.0, "Petersburg")
	_check((art[0] as ArrayMesh).get_surface_count() > 0, "the tree items build their art")
