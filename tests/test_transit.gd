extends SceneTree
## Run: godot --headless -s tests/test_transit.gd

var _fails := 0


func _init() -> void:
	var sim := _town()
	_check(BusNet.bays_for(Services.KINDS[Services.Kind.BUS_DEPOT].size) >= 6, "a new depot's yard holds a small-town fleet (%d bays)" % BusNet.bays_for(Services.KINDS[Services.Kind.BUS_DEPOT].size))
	var site := Services.site_near(sim.network, Services.Kind.BUS_DEPOT, Vector3(-40, 0, 220))
	_check(not site.is_empty(), "a depot fits beside the street")
	var money := sim.economy.money
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.BUS_DEPOT, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "the depot can be placed")
	var id: int = sim.services.buildings.keys().filter(func(k): return sim.services.buildings[k].kind == Services.Kind.BUS_DEPOT)[0]
	_check(money - sim.economy.money == Services.KINDS[Services.Kind.BUS_DEPOT].cost, "it costs its build price")
	_check(sim.buses.depots.has(id), "the depot runs itself")
	_check(sim.buses._fleet(id) == 2, "it opens with two buses")
	# Stops: on the streets where people are, 2 to 3 blocks apart.
	var pts := []
	for sid in sim.buses.stops:
		pts.append(sim.buses.stops[sid].pt)
	_check(pts.size() >= 4, "it planned stops by itself (%d)" % pts.size())
	var closest := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			closest = minf(closest, Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[j].x, pts[j].z)))
	_check(closest >= Balance.BUS_STOP_SPACING - 0.1, "stops at least 300 m apart (closest %.0f m)" % closest)
	var routes: Array = sim.buses.routes[id]
	_check(routes.size() >= 1 and routes[0].stops.size() >= 2, "it planned a route (%d routes)" % routes.size())
	_check(routes[0].len > 100.0 and routes[0].pts.size() > 4, "the route follows the roads (%.0f m)" % routes[0].len)
	var hub: int = routes[0].stops[0]
	for r in routes:
		_check(r.stops[0] == hub, "every route starts at the same downtown transfer stop")
	# The city pays the subsidy through its services budget.
	sim.economy.update_budget(sim)
	var before: int = sim.economy.budget.services
	sim.apply({"type": "set_bus_subsidy", "id": id, "amount": 90_000})
	sim.economy.update_budget(sim)
	_check(sim.economy.budget.services - before == 90_000 - Balance.BUS_START_SUBSIDY, "the subsidy is part of the city's budget")
	# Buses leave the depot, drive real trips and stop at the curb.
	var drove := false
	var dwelt := false
	for i in 3000:
		sim.tick()
		for bid in sim.buses.buses:
			var bus: Dictionary = sim.buses.buses[bid]
			drove = drove or bus.state == "driving"
			dwelt = dwelt or bus.state == "dwell"
	_check(drove, "buses drove out on Traffic's roads")
	_check(dwelt, "buses stopped at stops to let people on and off")
	var in_traffic := 0
	for car in sim.traffic.cars:
		if sim.buses.trips.has(car.id):
			in_traffic += 1
			_check(car.kind == "city_bus", "a depot bus is a transit bus")
	for bid in sim.buses.buses:
		var bus: Dictionary = sim.buses.buses[bid]
		_check(bus.state != "driving" or sim.buses.trips.values().has(bid), "a driving bus has a trip, so it never vanishes")
	# A month settles: fares, grant, subsidy and costs.
	var dep: Dictionary = sim.buses.depots[id]
	_check(not dep.month.is_empty(), "a month's money settled")
	_check(dep.month.grant > 0 and dep.month.cost > 0, "the federal grant pays part of the costs (%s)" % str(dep.month))
	_check(dep.fare >= 0.0 and dep.fare <= Balance.BUS_FARE_BASE_MAX + Balance.BUS_FARE_RICH_EXTRA, "the depot set a fare its riders can bear ($%.2f)" % dep.fare)
	var d := sim.buses.describe(sim, id)
	_check(d.has("subsidy") and d.rows.size() >= 5, "the panel shows the depot and its subsidy")
	# Fares follow what riders earn: a poor area gets at most the base fare.
	sim.buses.depots[id].wealth = 0.0
	sim.buses.depots[id].education = 0.8
	sim.buses._set_fare(id, sim.services.buildings[id])
	_check(sim.buses.depots[id].fare <= Balance.BUS_FARE_BASE_MAX + 0.001, "a poor area's fare stays low ($%.2f)" % sim.buses.depots[id].fare)
	# An educated director with plenty of subsidy keeps fares down.
	sim.buses.depots[id].wealth = 1.0
	sim.services.buildings[id].subsidy = 900_000
	sim.buses._set_fare(id, sim.services.buildings[id])
	_check(sim.buses.depots[id].fare <= 0.001, "with the costs covered, an educated director runs fare-free ($%.2f)" % sim.buses.depots[id].fare)
	sim.buses.depots[id].education = 0.3
	sim.buses.depots[id].fare = 1.5
	sim.buses.depots[id].month = {"net": -10000, "cost": 50000}
	sim.buses._set_fare(id, sim.services.buildings[id])
	_check(is_equal_approx(sim.buses.depots[id].fare, 1.75), "a self-taught director raises the fare after a losing month ($%.2f)" % sim.buses.depots[id].fare)
	# The fleet follows need and money: a bus every half hour on each route,
	# no more; and with no money left it retires buses.
	sim.apply({"type": "set_bus_subsidy", "id": id, "amount": 600_000})
	sim.buses.depots[id].cash = 2_000_000
	for i in 3:
		sim.buses._decide(sim, id, false)
	_check(sim.buses._fleet(id) == sim.buses.depots[id].wanted, "it runs the buses its routes need (%d of %d)" % [sim.buses._fleet(id), sim.buses.depots[id].wanted])
	sim.buses.depots[id].wanted = 0
	sim.apply({"type": "set_bus_subsidy", "id": id, "amount": 0})
	sim.buses.depots[id].cash = -500_000
	var had := sim.buses._fleet(id)
	sim.buses._decide(sim, id, false)
	_check(sim.buses._fleet(id) < had, "broke and unsubsidised, it retires a bus")
	# A full yard buys the land next door, and only next door.
	var b: Dictionary = sim.services.buildings[id]
	for key in sim.buildings.keys():
		if sim.lots[key].pos.distance_to(b.pos) < 80.0:
			sim.buildings.erase(key)  # empty lots next door are for sale
	var size0: Vector2 = Services.size_of(b)
	var pos0: Vector3 = b.pos
	_check(sim.buses._grow(sim, id), "the depot can buy free land beside it")
	_check(Services.size_of(b).x * Services.size_of(b).y > size0.x * size0.y, "its site grew")
	_check(b.pos.distance_to(pos0) <= BusNet.GROW_STEP, "it grew in place, not to a second site")
	_check(BusNet.bays_for(Services.size_of(b)) > BusNet.bays_for(size0), "more land, more bays")
	# Save and load: same state, and two copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.buses.buses.size() == sim.buses.buses.size(), "buses saved")
	_check(copy.buses.stops.size() == sim.buses.stops.size(), "stops saved")
	_check(Services.size_of(copy.services.buildings[id]) == Services.size_of(b), "grown site saved")
	_check(int(copy.services.buildings[id].subsidy) == int(b.subsidy), "subsidy saved")
	var copy2 := CitySim.new()
	copy2.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for i in 200:
		copy.tick()
		copy2.tick()
	_check(JSON.stringify(copy.buses.to_dict()) == JSON.stringify(copy2.buses.to_dict()), "two copies run the buses the same")
	# Bulldozing the depot sells its parked buses.
	sim.apply({"type": "remove_service", "id": id})
	sim.tick()
	for bid in sim.buses.buses:
		_check(sim.buses.buses[bid].state == "driving", "only buses still on a trip remain after the depot goes")
	_schools()
	print("TESTS FAILED" if _fails > 0 else "ALL TESTS PASSED")
	quit(1 if _fails > 0 else 0)


## School buses: a school with pupils living far away keeps yellow buses and
## sends them out at the morning bell.
func _schools() -> void:
	var sim := _town()
	var site := Services.site_near(sim.network, Services.Kind.SCHOOL, Vector3(-900, 0, 40))
	_check(not site.is_empty(), "a school fits at the end of town")
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.SCHOOL, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "the school can be placed")
	sim.tick()
	sim.buses._plan(sim)
	var sid: int = sim.services.buildings.keys()[0]
	_check(sim.buses.schools.has(sid), "the school runs its own buses")
	_check(sim.buses.schools[sid].riders > 0, "pupils far from school ride (%d)" % sim.buses.schools[sid].riders)
	_check(sim.buses._school_buses(sid) >= 1, "it keeps enough buses (%d)" % sim.buses._school_buses(sid))
	# Wind the clock to a school morning, just before the bell run.
	var left := false
	for i in 4 * 1440:
		sim.tick()
		for bid in sim.buses.buses:
			left = left or sim.buses.buses[bid].state == "driving"
		if left:
			break
	_check(left, "school buses set off on their run at bell time")
	var t := sim.clock()
	_check(BusNet.school_day(t) and t.hour >= 6 and t.hour <= 16, "they run on school days (%s)" % str(t))


## A grid town with homes, shops and jobs already built (as if grown).
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = true
	for z in range(0, 801, 200):
		sim.apply({"type": "build_road", "start": [-1000, z], "ctrl": [0, z], "end": [1000, z]})
	for x in range(-1000, 1001, 250):
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 400], "end": [x, 800]})
	sim.economy.money = 50_000_000
	var keys := sim.lots.keys()
	keys.sort()
	var i := 0
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		var zone := ZoneMap.Zone.COMMERCIAL if absf(lot.pos.x) < 200.0 and i % 2 == 0 else ZoneMap.Zone.RESIDENTIAL
		sim.zones.paint(lot.zone_pt, 3.0, zone)
		var cap := CitySim.capacity(zone, i)
		sim.buildings[key] = {"zone": zone, "seed": i, "built": 0, "cap": cap, "occ": cap if zone == ZoneMap.Zone.RESIDENTIAL else 0}
		i += 1
	sim.update_stats()
	return sim


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		_fails += 1
		print("FAIL ", what)
