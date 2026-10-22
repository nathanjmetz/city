extends SceneTree
## Run: godot --headless -s tests/test_sim.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	_check(sim.lots.is_empty(), "no lots until the street is zoned (got %d)" % sim.lots.size())
	# Nothing grows until zoned.
	for i in 40:
		sim.tick()
	_check(sim.buildings.is_empty(), "no buildings without zones")
	# Zone the north side as homes, the south side as industry.
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	_check(sim.lots.size() >= 10, "lots along a 200 m road once zoned (got %d)" % sim.lots.size())
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		var d := absf(lot.pos.z)
		_check(d > RoadStyle.right_of_way_half() + 10.0, "lot %s sits back from the road" % key)
		break
	var zoned := sim.empty_zoned_lots().size()
	_check(zoned == sim.lots.size(), "every lot zoned (%d of %d)" % [zoned, sim.lots.size()])
	var home_lots := 0
	for key in sim.lots:
		if sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.RESIDENTIAL:
			home_lots += 1
	for i in 4000:
		sim.tick()
	_check(sim.count_buildings(ZoneMap.Zone.RESIDENTIAL) == home_lots,
		"homes grow on every home lot while there are jobs (%d of %d)" % [sim.count_buildings(ZoneMap.Zone.RESIDENTIAL), home_lots])
	_check(sim.stats.population > 0 and sim.stats.employed > 0,
		"people moved in and found jobs (%s)" % str(sim.stats))
	_check(sim.count_buildings(ZoneMap.Zone.RESIDENTIAL) > 0 and sim.count_buildings(ZoneMap.Zone.INDUSTRIAL) > 0,
		"both zone types grew")
	# Dezoning removes buildings.
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.NONE})
	_check(sim.count_buildings(ZoneMap.Zone.INDUSTRIAL) == 0, "dezoning removes industry")
	# Same commands give the same city (needed for multiplayer).
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.buildings.size() == sim.buildings.size(), "save round trip keeps buildings")
	_check(copy.zones.cells.size() == sim.zones.cells.size(), "save round trip keeps zones")
	for i in 20:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim.to_dict()), "copies stay in sync")
	# A crossing road removes the lots it runs through.
	sim.apply({"type": "build_road", "start": [0, -100], "ctrl": [0, 0], "end": [0, 100]})
	for key in sim.buildings:
		_check(absf(sim.lots[key].pos.x) > 5.0, "no building left on the new road")
	# Demand: homes alone stall once people need work; jobs bring them back.
	var d := CitySim.new()
	d.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in range(-300, 301, 10):
		d.apply({"type": "paint_zone", "center": [x, -15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 6000:
		d.tick()
	var stalled: int = d.stats.population
	_check(d.demand[ZoneMap.Zone.RESIDENTIAL] < 0.2, "no jobs: demand for homes drops (%.2f)" % d.demand[ZoneMap.Zone.RESIDENTIAL])
	_check(d.demand[ZoneMap.Zone.INDUSTRIAL] > 0.3, "jobless people want industry (%.2f)" % d.demand[ZoneMap.Zone.INDUSTRIAL])
	for x in range(-300, 301, 10):
		d.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in 6000:
		d.tick()
	_check(d.stats.population > stalled, "jobs bring more people (%d -> %d)" % [stalled, d.stats.population])
	_check(CitySim.new().clock().weekday == 1 and CitySim.new().clock().hour == 6, "clock starts Monday 6 AM")
	# Money: roads cost real prices, taxes come in, upkeep goes out.
	var m := CitySim.new()
	var start: int = m.economy.money
	m.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	var street_cost := 200 * int(Economy.BUILD_PER_M[RoadStyle.Type.STREET])
	_check(m.economy.money == start - street_cost, "200 m street costs its price (spent %d)" % (start - m.economy.money))
	var flat := [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(100, 0, 0)]
	var high := [Vector3(0, 7.5, 0), Vector3(50, 7.5, 0), Vector3(100, 7.5, 0)]
	_check(Economy.road_cost(high, 0) > Economy.road_cost(flat, 0) * 3, "bridges cost more")
	m.economy.money = 1000
	_check(not m.apply({"type": "build_road", "start": [-100, 50], "ctrl": [0, 50], "end": [100, 50]}),
		"can't build without the money")
	_check(m.road_problem([Vector3(-100, 0, 50), Vector3(0, 0, 50), Vector3(100, 0, 50)], 0).begins_with("Not enough money"),
		"says why")
	_check(m.upgrade_cost(m.network.segments.keys()[0], RoadStyle.Type.AVENUE) == 200 * int(
		Economy.BUILD_PER_M[RoadStyle.Type.AVENUE] - Economy.BUILD_PER_M[RoadStyle.Type.STREET]), "upgrade pays the difference")
	_check(d.economy.budget.income[ZoneMap.Zone.RESIDENTIAL] > 0 and d.economy.budget.upkeep > 0,
		"budget has taxes and upkeep (%s)" % str(d.economy.budget))
	var before: int = d.economy.money
	for i in 1440:
		d.tick()
	_check(d.economy.money > before, "a growing town earns money over a day (%d -> %d)" % [before, d.economy.money])
	var r0: float = d.demand[ZoneMap.Zone.INDUSTRIAL]
	d.apply({"type": "set_tax", "zone": ZoneMap.Zone.INDUSTRIAL, "rate": 3.0})
	_check(d.demand[ZoneMap.Zone.INDUSTRIAL] < r0 or r0 == 0.0, "higher taxes cut demand")
	var saved := CitySim.new()
	saved.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	_check(saved.economy.money == d.economy.money and saved.economy.tax[ZoneMap.Zone.INDUSTRIAL] == 3.0,
		"money and taxes saved")
	# Services: power and water flow along roads; nothing grows without them.
	var u := CitySim.new()
	u.require_utilities = true
	u.economy.money = 50_000_000
	u.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in range(-300, 301, 10):
		u.apply({"type": "paint_zone", "center": [x, -15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		u.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in 400:
		u.tick()
	_check(u.buildings.is_empty(), "no power or water: nothing grows")
	var site := Services.site_near(u.network, Services.Kind.SUBSTATION, Vector3(-280, 0, 40))
	_check(not site.is_empty(), "substation finds a road to face")
	var lots_before := u.lots.size()
	_check(u.apply({"type": "place_service", "kind": Services.Kind.SUBSTATION,
		"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}), "substation placed")
	_check(u.lots.size() < lots_before, "lots under it are cleared")
	_check(not u.apply({"type": "place_service", "kind": Services.Kind.WATER_TOWER,
		"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}), "can't stack services")
	_check(not u.apply({"type": "place_service", "kind": Services.Kind.WATER_TOWER,
		"pos": [0, 2], "dir": [0, 1]}), "can't build on a road")
	var w := Services.site_near(u.network, Services.Kind.WATER_TOWER, Vector3(-240, 0, 40))
	_check(u.apply({"type": "place_service", "kind": Services.Kind.WATER_TOWER,
		"pos": [w[0].x, w[0].z], "dir": [w[1].x, w[1].z]}), "water tower placed")
	for i in 3000:
		u.tick()
	_check(u.count_buildings(ZoneMap.Zone.RESIDENTIAL) > 10 and u.stats.population > 0,
		"with power and water the town grows (%d homes)" % u.count_buildings(ZoneMap.Zone.RESIDENTIAL))
	_check(u.economy.budget.services == 18_000 and u.economy.budget.fees > 0, "utilities cost upkeep and earn water bills")
	var f := Services.site_near(u.network, Services.Kind.FIRE, Vector3(0, 0, 60))
	var cov0 := u.service_coverage()
	u.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [f[0].x, f[0].z], "dir": [f[1].x, f[1].z]})
	u.update_stats()
	_check(u.service_coverage() > cov0, "a fire station covers homes (%.2f -> %.2f)" % [cov0, u.service_coverage()])
	var us := CitySim.new()
	us.from_dict(JSON.parse_string(JSON.stringify(u.to_dict())))
	_check(us.services.buildings.size() == 3, "services saved")
	u.apply({"type": "remove_service", "id": 1})
	_check(u.services.buildings.size() == 2, "services can be removed")
	# A new game can afford a start: village utilities, a few streets, grants.
	var ng := CitySim.new()
	ng.require_utilities = true
	ng.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for entry in [[Services.Kind.POWER_FEED, Vector3(-280, 0, 30)], [Services.Kind.WELL, Vector3(-250, 0, 30)]]:
		var st := Services.site_near(ng.network, entry[0], entry[1])
		_check(ng.apply({"type": "place_service", "kind": entry[0], "pos": [st[0].x, st[0].z], "dir": [st[1].x, st[1].z]}),
			"starter utility placed")
	for x in range(-300, 301, 10):
		ng.apply({"type": "paint_zone", "center": [x, -15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		ng.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
	_check(ng.economy.money > 1_500_000, "still money left to build ($%d)" % ng.economy.money)
	for i in 6000:
		ng.tick()
	_check(ng.stats.population >= 50, "the village grows (%d people)" % ng.stats.population)
	var before_grant: int = ng.economy.money
	_check(ng.economy.reach_milestones(260) == 650_000 and ng.economy.money == before_grant + 650_000
		and ng.economy.reach_milestones(260) == 0, "milestone grants paid once each")
	# Farms: outline farmland, place a farmhouse, watch it buy fields.
	var fm := CitySim.new()
	fm.economy.money = 10_000_000
	fm.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	_check(fm.apply({"type": "paint_farmland", "points": [[-500, 20], [500, 20], [500, 600], [-500, 600]]}),
		"farmland outlined with nodes")
	_check(fm.apply({"type": "paint_reserve", "kind": "oil", "points": [[-500, -20], [500, -20], [500, -400], [-500, -400]]}),
		"land reserved for oil")
	_check(not fm.apply({"type": "place_farmhouse", "pos": [0, -200], "dir": [0, 1]}), "no farmhouse on oil land")
	_check(not fm.apply({"type": "build_road", "start": [0, -100], "ctrl": [0, -200], "end": [0, -300]}),
		"no roads across reserved land")
	fm.apply({"type": "paint_zone", "center": [0, -60], "radius": 20, "zone": ZoneMap.Zone.RESIDENTIAL})
	_check(fm.zones.zone_at(Vector3(0, 0, -60)) == ZoneMap.Zone.NONE, "no zoning on reserved land")
	var oil_seen := 0.0
	for k in 400:
		var v := Resources.at(Resources.Kind.OIL, Vector3(k * 97.0, 0, k * 61.0))
		_check(v >= 0.0 and v <= 1.0, "resource levels stay 0 to 1") if k == 0 else null
		oil_seen = maxf(oil_seen, v)
	_check(oil_seen > 0.5, "oil turns up somewhere on the map")
	_check(fm.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"}), "farmhouse placed")
	_check(not fm.apply({"type": "place_farmhouse", "pos": [0, 560], "dir": [0, -1]}), "farmhouse needs a road near")
	var farm: Dictionary = fm.farms.farms.values()[0]
	_check(farm.drive.size() >= 2 and absf(farm.drive[-1].z) < 1.0, "a farm lane runs out to the road")
	fm.farms.decide(fm.field_usable)
	_check(farm.barn and farm.cells.is_empty(), "the barn goes up before any fields")
	fm.farms.decide(fm.field_usable)
	_check(farm.cells.size() == 1 and absi(farm.cells[0].x) + absi(farm.cells[0].y) == 1,
		"the first field is next to the farmyard (%s)" % [farm.cells])
	for i in Farms.DECIDE_EVERY * 40:
		fm.tick()
	var grown: int = farm.cells.size()
	_check(grown >= 10, "the farm buys fields as it makes money (%d fields)" % grown)
	var touches_road := false
	for c in farm.cells:
		touches_road = touches_road or absf(Farms.cell_center(farm, c).z) < Farms.CELL * 0.5 + 4.0
	_check(not touches_road, "no fields on the road")
	_check(fm.economy.budget.income[ZoneMap.Zone.INDUSTRIAL] > 0, "farmland pays property tax")
	_check(Farms.fertility_at(Vector3(130, 0, 170)) == Farms.fertility_at(Vector3(130, 0, 170)), "soil never changes")
	# A farm on a diagonal road lays its fields out square to that road.
	var diag := CitySim.new()
	diag.economy.money = 10_000_000
	diag.apply({"type": "build_road", "start": [-400, -400], "ctrl": [0, 0], "end": [400, 400]})
	diag.apply({"type": "paint_farmland", "points": [[-300, -200], [200, 300], [400, 100], [-100, -400]]})
	var dir := Vector3(-1, 0, 1).normalized()
	_check(diag.apply({"type": "place_farmhouse", "pos": [60, 0], "dir": [dir.x, dir.z]}), "farmhouse on a diagonal road")
	for i in 20:
		diag.farms.decide(diag.field_usable)
	var dfarm: Dictionary = diag.farms.farms.values()[0]
	var corners := Farms.cell_corners(dfarm, dfarm.cells[0])
	var edge := (corners[1] - corners[0]).normalized()
	_check(dfarm.cells.size() >= 5 and absf(absf(edge.dot(Vector2(1, 1).normalized())) - 1.0) < 0.01,
		"fields run square to the road, not the world grid")
	var fcopy := CitySim.new()
	fcopy.from_dict(JSON.parse_string(JSON.stringify(fm.to_dict())))
	_check(fcopy.farms.farms.values()[0].cells.size() == grown, "farms saved")
	grown = farm.cells.size()
	fm.farms.price = 0.75  # a bad year for corn
	fm.farms.tax_rate = 3.0
	for i in 12:
		fm.farms.decide(fm.field_usable)
	_check(farm.cells.size() < grown, "a struggling farm sells fields (%d -> %d)" % [grown, farm.cells.size()])
	# Brawn's case: a well but no power. The warning names what's missing,
	# and clicking the well or a lot explains it.
	var ws := CitySim.new()
	ws.require_utilities = true
	ws.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	ws.apply({"type": "paint_zone", "center": [0, 20], "radius": 40, "zone": ZoneMap.Zone.RESIDENTIAL})
	ws.economy.money = 400_000
	_check(ws.utility_problem().begins_with("No power: build a Power line feed"), "warning names power first: " + ws.utility_problem())
	var well_site := Services.site_near(ws.network, Services.Kind.WELL, Vector3(120, 0, -30))
	ws.apply({"type": "place_service", "kind": Services.Kind.WELL, "pos": [well_site[0].x, well_site[0].z],
		"dir": [well_site[1].x, well_site[1].z]})
	for i in 50:
		ws.tick()
	var why := ws.utility_problem()
	_check(why.begins_with("No power") and why.contains("need $"), "without power the warning says so and the money short: " + why)
	var well := Inspect.pick(ws, well_site[0])
	_check(well.get("type") == "service", "clicking the well selects it")
	var wd := Inspect.describe(ws, well)
	_check(wd.title == "Well and pump house" and wd.status.begins_with("Working") and not wd.ok
		and str(wd.problems).contains("no power"), "the well's panel: working, but the town lacks power (%s)" % str(wd))
	var lot_key: String = ws.empty_zoned_lots()[0] if not ws.empty_zoned_lots().is_empty() else ""
	var some_lot := ""
	for key in ws.lots:
		if ws.zones.zone_at(ws.lots[key].zone_pt) != ZoneMap.Zone.NONE:
			some_lot = key
			break
	var ld := Inspect.describe(ws, Inspect.pick(ws, ws.lots[some_lot].pos))
	_check(ld.get("title") == "Empty lot" and str(ld.problems).contains("No power") and not str(ld.problems).contains("No water"),
		"a zoned lot says it lacks power, not water (%s)" % str(ld))
	_check(lot_key == "", "nothing can grow without power")
	ws.economy.money = 400_000
	var feed := Services.site_near(ws.network, Services.Kind.POWER_FEED, Vector3(-120, 0, -30))
	ws.apply({"type": "place_service", "kind": Services.Kind.POWER_FEED, "pos": [feed[0].x, feed[0].z],
		"dir": [feed[1].x, feed[1].z]})
	for i in 50:
		ws.tick()
	_check(ws.utility_problem() == "", "power and water: no warning")
	# The Critic's case: power reaches one street, water another, so no lot
	# has both. The warning has to say so.
	var split := CitySim.new()
	split.require_utilities = true
	split.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	split.apply({"type": "build_road", "start": [-200, 300], "ctrl": [0, 300], "end": [200, 300]})
	split.apply({"type": "paint_zone", "center": [0, 20], "radius": 40, "zone": ZoneMap.Zone.RESIDENTIAL})
	split.apply({"type": "paint_zone", "center": [0, 320], "radius": 40, "zone": ZoneMap.Zone.RESIDENTIAL})
	split.economy.money = 1_000_000
	for entry in [[Services.Kind.POWER_FEED, Vector3(150, 0, -30)], [Services.Kind.WELL, Vector3(150, 0, 270)]]:
		var spot := Services.site_near(split.network, entry[0], entry[1])
		split.apply({"type": "place_service", "kind": entry[0], "pos": [spot[0].x, spot[0].z], "dir": [spot[1].x, spot[1].z]})
	for i in 50:
		split.tick()
	_check(split.utility_problem().contains("no power: their streets aren't joined by road to a power line")
		and split.utility_problem().contains("no water: their streets aren't joined by road to a water source"),
		"split networks: each utility's cause is named: " + split.utility_problem())
	_check(split.utility_summary().length() < 40, "the top-bar chip stays short: " + split.utility_summary())
	var rd := Inspect.describe(ws, Inspect.pick(ws, Vector3(60, 0, 0)))
	_check(rd.get("title") == "Street" and rd.ok, "clicking a road shows the street")
	_check(Inspect.pick(ws, Vector3(0, 0, -900)).is_empty(), "clicking open ground selects nothing")
	# Resource industry (Brawn's model): a company's pads spread where the
	# resource is, and every load leaves on a real truck.
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-2000, 2001, 100):
		for z in range(-2000, 2001, 100):
			var v := Resources.at(Resources.Kind.OIL, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	var oil := CitySim.new()
	oil.economy.money = 50_000_000
	oil.apply({"type": "build_road", "start": [best.x - 400, best.z - 60], "ctrl": [best.x, best.z - 60], "end": [best.x + 400, best.z - 60]})
	oil.build_county_road(Vector2(best.x + 400, best.z - 60), Vector2(best.x + 2000, best.z - 60), [1])
	_check(oil.region_links.size() == 1 and oil.is_link_segment(oil.network.segments_at(oil.region_links[0])[0])
		and not oil.apply({"type": "remove_road", "seg": oil.network.segments_at(oil.region_links[0])[0]}),
		"the county highway's way out can't be bulldozed")
	var stub := CitySim.new()
	stub.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	_check(stub.logistics._edge(stub).is_empty(), "a dead-end street isn't a way out of town")
	var old_save := stub.to_dict()
	old_save.erase("links")
	var upgraded := CitySim.new()
	upgraded.from_dict(JSON.parse_string(JSON.stringify(old_save)))
	_check(upgraded.region_links.size() == 1 and absf(upgraded.network.nodes[upgraded.region_links[0]].x) > 2100.0,
		"an older town gets a county highway out to the region")
	_check(oil.industry_problem("oil", best + Vector3(0, 0, 900), Vector3(0, 0, -1)).begins_with("Needs a road")
		or oil.industry_problem("oil", best + Vector3(0, 0, 900), Vector3(0, 0, -1)).begins_with("No crude"),
		"a company needs a road and the resource nearby")
	var dry := Vector3.ZERO
	for x in range(-2000, 2001, 100):
		if Resources.at(Resources.Kind.OIL, Vector3(x, 0, best.z)) < 0.05 and oil.industry_reach("oil", Vector3(x, 0, best.z + 20)) < Industry.MIN_RICHNESS:
			dry = Vector3(x, 0, best.z + 20)
			break
	if dry != Vector3.ZERO:
		oil.apply({"type": "build_road", "start": [dry.x - 100, dry.z - 80], "ctrl": [dry.x, dry.z - 80], "end": [dry.x + 100, dry.z - 80]})
		_check(oil.industry_problem("oil", dry, Vector3(0, 0, -1)).begins_with("No crude oil"), "no oil company where there's no oil")
	_check(oil.apply({"type": "place_industry", "kind": "oil", "pos": [best.x, best.z + 20], "dir": [0, -1]}), "an oil company opens on the oil field")
	var twin := CitySim.new()
	twin.from_dict(JSON.parse_string(JSON.stringify(oil.to_dict())))
	for i in 1440 * 3:
		oil.tick()
		twin.tick()
	var co: Dictionary = oil.industry.sites[1]
	_check(co.pads.size() >= 3, "its pads spread over three days (%d)" % co.pads.size())
	var rich := true
	for c in co.pads:
		rich = rich and Industry.richness(co, c) >= Industry.MIN_RICHNESS
	_check(rich, "every pad sits on oil")
	_check(oil.logistics.delivered > 0 and oil.logistics.exported > 0, "tankers drove crude out to the highway (%d delivered)" % oil.logistics.delivered)
	var tankers := 0
	for car in oil.traffic.cars:
		if car.get("purpose", "") == "fuel":
			tankers += 1
	_check(tankers > 0 or not oil.logistics.trips.is_empty(), "crude rides in tankers")
	_check(twin.industry.sites[1].pads == co.pads and twin.logistics.delivered == oil.logistics.delivered,
		"two copies grow the same oil field (multiplayer)")
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(oil.to_dict())))
	_check(back.industry.sites[1].pads.size() == co.pads.size() and back.logistics.trips.size() == oil.logistics.trips.size(),
		"save keeps the company and its trucks")
	_check(oil.factory_chain(co.pos + Vector3(600, 0, 0)) == "refinery"
		and oil.factory_chain(co.pos + Vector3(40000, 0, 0)) == "general",
		"factories near the oil field make plastics; far from any industry they're general")
	oil.buildings["test"] = {"zone": ZoneMap.Zone.INDUSTRIAL, "seed": 1, "built": 0, "cap": 10, "occ": 0, "chain": "metal"}
	_check(Logistics.input_of(oil, "test") == "ore", "a metal works buys ore")
	oil.buildings.erase("test")
	var oil_sel := Inspect.pick(oil, co.pos)
	_check(oil_sel.get("type") == "industry" and Inspect.describe(oil, oil_sel).title == "Oil company", "clicking the company opens its panel")
	_check(oil.stats.jobs >= Balance.INDUSTRY["oil"]["jobs_hq"], "the company's jobs count")
	# Critic round 7: a company whose yard isn't on the deposit itself still
	# finds the rich ground within reach for its first pad.
	var edge_spot := Vector3.INF
	for r in [240.0, 280.0, 320.0]:
		for i in 16:
			var p: Vector3 = best + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * r
			var probe := {"kind": "oil", "pos": p, "dir": Vector3(0, 0, -1)}
			var poor := true
			for c in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				poor = poor and Industry.richness(probe, c) < Industry.MIN_RICHNESS
			if poor and edge_spot == Vector3.INF:
				edge_spot = p
	_check(edge_spot != Vector3.INF, "found a spot off the deposit's edge")
	if edge_spot != Vector3.INF:
		var off := Industry.new()
		off.add_site("oil", edge_spot, Vector3(0, 0, -1), [])
		off.decide(func(_m, _c): return true)
		_check(off.sites[1].pads.size() == 1 and off.sites[1].get("idle", "") == "",
			"a company beside the deposit opens its first pad on it (%d)" % off.sites[1].pads.size())
	# Somewhere on the real map with no oil anywhere in a company's reach.
	var no_oil := Vector3.INF
	for k in 400:
		var p := Vector3(-16000.0 + (k % 20) * 1600.0, 0, -16000.0 + (k / 20) * 1600.0)
		var probe := {"kind": "oil", "pos": p, "dir": Vector3(0, 0, -1)}
		var empty := true
		for y in range(-Industry.SEED_REACH, Industry.SEED_REACH + 1):
			for x in range(-Industry.SEED_REACH, Industry.SEED_REACH + 1):
				empty = empty and Industry.richness(probe, Vector2i(x, y)) < Industry.MIN_RICHNESS
		if empty:
			no_oil = p
			break
	_check(no_oil != Vector3.INF, "the map has land with no oil")
	var none := Industry.new()
	none.add_site("oil", no_oil, Vector3(0, 0, -1), [])
	none.decide(func(_m, _c): return true)
	_check(none.sites[1].pads.is_empty() and str(none.sites[1].get("idle", "")).begins_with("No crude oil"),
		"a company with no oil around says why")
	# The road wins (Brawn): a road through the fields trims them to its edge.
	var rw := CitySim.new()
	rw.from_dict(JSON.parse_string(JSON.stringify(fm.to_dict())))
	var rw_farm: Dictionary = rw.farms.farms[1]
	var cut_z: float = rw_farm.pos.z + Farms.CELL * 2.3
	var cells_before: int = rw_farm.cells.size()
	rw.apply({"type": "paint_reserve", "kind": "", "points": [[-600, 10], [600, 10], [600, 700], [-600, 700]]})
	_check(rw.apply({"type": "build_road", "start": [-900, cut_z], "ctrl": [0, cut_z], "end": [900, cut_z]}),
		"a road can go through a farm's fields")
	var on_road := false
	for c in rw_farm.cells:
		for poly in rw.farms.trim.get(1, {}).get(c, [Farms.cell_corners(rw_farm, c)]):
			for q in poly:
				on_road = on_road or absf(q.y - cut_z) < RoadStyle.right_of_way_half(0) + 0.5
	_check(rw.farms.farms.has(1) and not on_road and not rw.farms.trim.get(1, {}).is_empty(),
		"the fields stop at the road's edge (%d of %d cells left, %d trimmed)" % [rw_farm.cells.size(), cells_before, rw.farms.trim.get(1, {}).size()])
	var twin_farm := CitySim.new()
	twin_farm.from_dict(JSON.parse_string(JSON.stringify(rw.to_dict())))
	_check(twin_farm.farms.trim.get(1, {}).size() == rw.farms.trim.get(1, {}).size(), "a reload trims the same fields")
	var cash: int = rw.economy.money
	rw.apply({"type": "build_road", "start": [-300, rw_farm.pos.z], "ctrl": [0, rw_farm.pos.z], "end": [300, rw_farm.pos.z]})
	_check(not rw.farms.farms.has(1) and rw.economy.money > cash, "a road through the farmyard bulldozes it and pays it back")
	# Old saves (roads only) come back zoned as homes.
	var old := CitySim.new()
	old.from_dict({"version": 1, "next_id": 4, "nodes": {"1": [-100, 0], "2": [100, 0]},
		"segments": {"3": [1, 2, 0, 0]}})
	_check(old.empty_zoned_lots().size() == old.lots.size() and old.lots.size() > 0, "old saves get zoned")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	elif not what.begins_with("lot ") and not what.begins_with("no building left"):
		print("PASS " + what)
