extends SceneTree
## Run: godot --headless -s tests/test_sim.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	_check(sim.lots.size() >= 16, "lots along a 200 m road (got %d)" % sim.lots.size())
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		var d := absf(lot.pos.z)
		_check(d > RoadStyle.right_of_way_half() + 10.0, "lot %s sits back from the road" % key)
		break
	# Nothing grows until zoned.
	for i in 40:
		sim.tick()
	_check(sim.buildings.is_empty(), "no buildings without zones")
	# Zone the north side as homes, the south side as industry.
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	var zoned := sim.empty_zoned_lots().size()
	_check(zoned == sim.lots.size(), "every lot zoned (%d of %d)" % [zoned, sim.lots.size()])
	for i in 4000:
		sim.tick()
	_check(sim.count_buildings(ZoneMap.Zone.RESIDENTIAL) * 2 == sim.lots.size(),
		"homes grow on every home lot while there are jobs (%d of %d)" % [sim.count_buildings(ZoneMap.Zone.RESIDENTIAL), sim.lots.size() / 2])
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
	_check(m.economy.money == start - 200_000, "200 m street costs $200,000 (spent %d)" % (start - m.economy.money))
	var flat := [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(100, 0, 0)]
	var high := [Vector3(0, 7.5, 0), Vector3(50, 7.5, 0), Vector3(100, 7.5, 0)]
	_check(Economy.road_cost(high, 0) > Economy.road_cost(flat, 0) * 3, "bridges cost more")
	m.economy.money = 1000
	_check(not m.apply({"type": "build_road", "start": [-100, 50], "ctrl": [0, 50], "end": [100, 50]}),
		"can't build without the money")
	_check(m.road_problem([Vector3(-100, 0, 50), Vector3(0, 0, 50), Vector3(100, 0, 50)], 0).begins_with("Not enough money"),
		"says why")
	_check(m.upgrade_cost(m.network.segments.keys()[0], RoadStyle.Type.AVENUE) == 200_000, "upgrade pays the difference")
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
	_check(not fm.apply({"type": "place_farmhouse", "pos": [0, -200], "dir": [0, -1]}), "farmhouse needs farmland")
	_check(fm.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"}), "farmhouse placed")
	for i in Farms.DECIDE_EVERY * 40:
		fm.tick()
	var farm: Dictionary = fm.farms.farms.values()[0]
	var grown: int = farm.cells.size()
	_check(grown >= 10, "the farm buys fields as it makes money (%d fields)" % grown)
	var touches_road := false
	for c in farm.cells:
		touches_road = touches_road or absf(Farms.cell_center(c).z) < Farms.CELL * 0.5 + 4.0
	_check(not touches_road, "no fields on the road")
	_check(fm.economy.budget.income[ZoneMap.Zone.INDUSTRIAL] > 0, "farmland pays property tax")
	_check(Farms.fertility(Vector2i(3, 4)) == Farms.fertility(Vector2i(3, 4)), "soil never changes")
	var fcopy := CitySim.new()
	fcopy.from_dict(JSON.parse_string(JSON.stringify(fm.to_dict())))
	_check(fcopy.farms.farms.values()[0].cells.size() == grown, "farms saved")
	grown = farm.cells.size()
	fm.farms.price = 0.75  # a bad year for corn
	fm.farms.tax_rate = 3.0
	for i in 12:
		fm.farms.decide(fm.field_usable)
	_check(farm.cells.size() < grown, "a struggling farm sells fields (%d -> %d)" % [grown, farm.cells.size()])
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
