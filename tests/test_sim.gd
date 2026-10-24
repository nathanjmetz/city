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
	var owed := 0
	for i in range(ng.economy.milestone, Economy.MILESTONES.size()):
		if Economy.MILESTONES[i][0] <= 260:
			owed += Economy.MILESTONES[i][1]
	_check(owed > 0 and ng.economy.reach_milestones(260) == owed and ng.economy.money == before_grant + owed
		and ng.economy.reach_milestones(260) == 0, "milestone grants paid once each")
	# Farms: outline farmland, place a farmhouse, watch it buy fields.
	var fm := CitySim.new()
	fm.economy.money = 10_000_000
	_no_county_roads(fm, Vector3.ZERO)
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
	# The critic's woods (round 19): 35% fertile, no field would ever pay.
	var woods := CitySim.new()
	_check(woods.farms.start_profit(Vector3(300, 0, -120), Vector3(0, 0, 1)) <= 0.0
		and fm.farms.start_profit(Vector3(0, 0, 60), Vector3(0, 0, -1)) > 0.0,
		"a farmstead only goes where a field would pay")
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
	_no_county_roads(diag, Vector3.ZERO)
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
	# Farmers ride out a bad spell, then cut back after a season of losses.
	for i in Balance.FARM_SELL_LOOKS + 12:
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
	_check(ws.utility_problem().contains("still going in"), "while the line crew works, the warning says so: " + ws.utility_problem())
	# Power lines and wells supply nothing till their crews finish.
	for i in maxi(Construction.duration("power_feed"), Construction.duration("well")):
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
	for i in Construction.duration("well") + 20:
		split.tick()
	_check(split.utility_problem().contains("no power: their streets aren't joined by road to a power line")
		and split.utility_problem().contains("no water: their streets aren't joined by road to a water source"),
		"split networks: each utility's cause is named: " + split.utility_problem())
	_check(split.utility_summary().length() < 40, "the top-bar chip stays short: " + split.utility_summary())
	var rd := Inspect.describe(ws, Inspect.pick(ws, Vector3(60, 0, 0)))
	_check(rd.get("kind") == "Street" and str(rd.get("title")).ends_with("Street") and rd.ok, "clicking a road shows the street and its name: %s" % rd.get("title"))
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
	var ind_id: int = oil.industry.sites.keys()[0]
	_check(not oil.construction.state("ind:%d" % ind_id, oil.tick_count).is_empty(),
		"the company's main building goes up in stages")
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
	# Hub agency (Brawn): the company's leader builds up its own tree.
	_check(not co.get("leader", {}).is_empty() and "tank_battery" in co.get("built", []),
		"the oil company's owner builds a tank battery (%s)" % [co.get("built", [])])
	_check(twin.industry.sites[1].get("built", []) == co.built, "both copies develop the same way")
	_check(not Agency.holds(oil, co, co.pos, 1.0e6, "region_buys:crude oil", 1), "no neighbours buy crude yet")
	oil.region = {"neighbors": [{"name": "Winslow", "imports": {"crude oil": 3}}]}
	_check(Agency.holds(oil, co, co.pos, 1.0e6, "region_buys:crude oil", 1), "a neighbouring town that buys crude opens the terminal path")
	oil.region = {}
	var dev_rows: Array = Inspect.describe(oil, {"type": "industry", "id": 1}).rows
	_check(str(dev_rows).contains("Could build next"), "the company panel shows its development tree")
	_check(oil.factory_chain(co.pos + Vector3(600, 0, 0)) == "refinery"
		and oil.factory_chain(co.pos + Vector3(40000, 0, 0)) == "general",
		"factories near the oil field make plastics; far from any industry they're general")
	oil.buildings["test"] = {"zone": ZoneMap.Zone.INDUSTRIAL, "seed": 1, "built": 0, "cap": 10, "occ": 0, "chain": "metal"}
	_check(Logistics.input_of(oil, "test") == "ore", "a metal works buys ore")
	oil.buildings.erase("test")
	var oil_sel := Inspect.pick(oil, co.pos)
	_check(oil_sel.get("type") == "industry" and Inspect.describe(oil, oil_sel).kind == "Oil company"
		and Inspect.describe(oil, oil_sel).title == oil.families.name_of("site:%d" % oil_sel.id), "clicking the company opens its panel, under its own name")
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
	_real_layouts()
	_town_culture()
	_clear_keeps_links()
	_identity_shift()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

## Industry spreads like the real thing: spaced oil pads, one quarry,
## timber cut in rotation.
## A town's character follows its jobs (location quotients) and pulls its
## own trade forward.
func _town_culture() -> void:
	var sim := CitySim.new()
	var res: int = Industry.KINDS["ore"].resource
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-1500, 1501, 100):
		for z in range(-1500, 1501, 100):
			var v := Resources.at(res, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	_no_county_roads(sim, best)
	sim.apply({"type": "build_road", "start": [best.x - 600, best.z - 260], "ctrl": [best.x, best.z - 260], "end": [best.x + 600, best.z - 260]})
	sim.apply({"type": "place_industry", "kind": "ore", "pos": [best.x, best.z - 180], "dir": [0, -1]})
	var id: int = sim.industry.sites.keys()[0]
	var plain := sim.industry.buy_margin(id)
	for i in 1440 * 4:
		sim.tick()
	_check(sim.culture.identity == "mining" and sim.culture.title() == "Coal and oil town",
		"a town of coal miners is a coal town (%s, LQ %.0f)" % [sim.culture.identity, sim.culture.lq("mining")])
	_check(sim.culture.pull("mining") > 0.5 and sim.culture.pull("office") < 0.0, "its own trade pulls, others drag")
	_check(sim.industry.buy_margin(id) < plain, "a coal town's mine opens new cuts on thinner margins")
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(back.culture.identity == "mining" and is_equal_approx(back.culture.lq("mining"), sim.culture.lq("mining")),
		"the town's character is saved")


## A rising trade with no land left asks to rezone farm ground along a
## road, and only does it once the player approves.
func _identity_shift() -> void:
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	# Homes across the road: the farm is at the edge of town.
	for x in range(-300, 301, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in Farms.DECIDE_EVERY * 40:
		sim.tick()
	var farm: Dictionary = sim.farms.farms.values()[0]
	var fields: int = farm.cells.size()
	# Offices are rising fast and every commercial lot is taken.
	for k in TownCulture.SECTORS:
		sim.culture.shares[k] = 0.1
		sim.culture.now[k] = 0.1
	sim.culture.now["office"] = 0.3
	sim.demand[ZoneMap.Zone.COMMERCIAL] = 0.9
	sim.culture.develop(sim)
	var asked: Array = sim.permits.listed(Permits.State.OPEN).filter(func(r): return r.hub == TownCulture.HUB)
	_check(asked.size() == 1 and asked[0].change == "Farmland to offices" and asked[0].shape == "area",
		"a rising office trade asks to rezone farm ground (%s)" % [asked.map(func(r): return r.change)])
	var zoned: int = sim.zones.cells.size()
	_check(farm.cells.size() == fields and sim.zones.cells.size() == zoned, "nothing changes before the player says yes")
	if asked.is_empty():
		return
	sim.apply({"type": "permit", "id": asked[0].id, "answer": "approve"})
	sim.culture.develop(sim)
	_check(farm.cells.size() < fields and sim.zones.cells.size() > zoned,
		"approved: the fields along the road are sold and zoned (%d of %d fields left)" % [farm.cells.size(), fields])
	_check(sim.zones.cells.values().count(ZoneMap.Zone.COMMERCIAL) == sim.zones.cells.size() - zoned, "zoned for offices")
	# Out in the country, with no town beside it, no developer comes.
	var country := CitySim.new()
	country.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	country.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	for i in Farms.DECIDE_EVERY * 10:
		country.tick()
	_check(TownCulture._farm_frontage(country).is_empty(), "a farm out in the country isn't the edge of town")
	_check(not sim.buildings.is_empty(), "homes went up across the road (%d)" % sim.buildings.size())


## Starting over keeps the county highway out to the region, and gives a
## crossroads to begin from (Brawn, 2026-10-23).
func _clear_keeps_links() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 200]})
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, -100], "end": [-300, -200]})
	sim.apply({"type": "clear"})
	_check(sim.region_links.size() == 2, "starting over keeps both ways out to the region (%d)" % sim.region_links.size())
	var far_ok := sim.network.find_node_near(Vector3(-2000, 0, 0), 2.0) != -1 and sim.network.find_node_near(Vector3(2000, 0, 0), 2.0) != -1
	_check(far_ok and sim.network.find_segment_near(Vector3(-300, 0, 0), 2.0).size() > 0, "the county highway runs right through")
	var hub := sim.network.find_node_near(Vector3.ZERO, 60.0)
	_check(hub != -1 and sim.network.segments_at(hub).size() == 4, "with a crossroads to start the town from")
	_check(sim.network.find_segment_near(Vector3(-300, 0, -150), 5.0).is_empty(), "the player's own roads are gone")


func _real_layouts() -> void:
	var any := func(_mid, _corners): return true
	for kind in ["oil", "ore", "forest"]:
		var res: int = Industry.KINDS[kind].resource
		var best := Vector3.ZERO
		var best_v := 0.0
		for x in range(-3000, 3001, 150):
			for z in range(-3000, 3001, 150):
				var v := Resources.at(res, Vector3(x, 0, z))
				if v > best_v:
					best_v = v
					best = Vector3(x, 0, z)
		var ind := Industry.new()
		ind.price = 3.0  # rich enough that every good cell pays
		var id := ind.add_site(kind, best, Vector3(0, 0, -1), [])
		for i in 40:
			ind.day = i * 1.5
			ind.decide(any)
		var pads: Array = ind.sites[id].pads
		if kind == "oil":
			var spaced := pads.size() >= 2
			for a in pads:
				for b in pads:
					if a != b and maxi(absi(a.x - b.x), absi(a.y - b.y)) < Balance.OIL_SPACING_CELLS:
						spaced = false
			_check(spaced, "oil pads keep their well spacing (%d pads)" % pads.size())
		elif kind == "ore":
			var joined := pads.size() >= 3
			for c in pads:
				var touches: bool = c.length_squared() == 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					touches = touches or (c + d) in pads
				joined = joined and touches
			_check(joined, "the quarry grows as one pit (%d benches)" % pads.size())
			var way := signi(pads[0].y)
			var one_way: bool = way != 0
			for c in pads:
				one_way = one_way and c.y * way >= pads[0].y * way
			_check(one_way, "the strip mine advances one way, away from its plant")
			# A county road one cell east of the yard: the pit never jumps it.
			var walled := Industry.new()
			walled.price = 3.0
			var rx := best.x + 1.5 * Industry.PAD
			walled.road_between = func(a: Vector3, b: Vector3): return (a.x - rx) * (b.x - rx) < 0.0
			var wid := walled.add_site(kind, best, Vector3(0, 0, -1), [])
			for i in 40:
				walled.decide(any)
			var stays: bool = walled.sites[wid].pads.size() >= 3
			for c in walled.sites[wid].pads:
				stays = stays and c.x <= 1
			_check(stays, "the strip mine stays on its own side of the road")
		else:
			_check(pads.size() <= Balance.FOREST_ACTIVE_UNITS and not ind.sites[id].get("regrow", {}).is_empty(),
				"timber is cut a few units at a time and left to regrow (%d cutting, %d resting)"
				% [pads.size(), ind.sites[id].get("regrow", {}).size()])
			var back := Industry.new()
			back.from_dict(JSON.parse_string(JSON.stringify(ind.to_dict())))
			_check(back.sites[id].regrow.size() == ind.sites[id].regrow.size(), "resting units are saved")


## No county roads cross this test's ground (as if the player bulldozed the
## miles near p): fields and pads keep off painted county roads.
func _no_county_roads(sim: CitySim, p: Vector3) -> void:
	var sec := CountyGrid.SECTION
	var cx := floori((p.x + sim.terrain_offset.x) / sec)
	var cz := floori((p.z + sim.terrain_offset.y) / sec)
	for k in range(-3, 5):
		for seg in range(-3, 4):
			sim.county_removed["ns:%d:%d" % [cx + k, cz + seg]] = true
			sim.county_removed["ew:%d:%d" % [cz + k, cx + seg]] = true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	elif not what.begins_with("lot ") and not what.begins_with("no building left"):
		print("PASS " + what)
