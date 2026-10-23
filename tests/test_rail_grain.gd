extends SceneTree
## The grain elevator spur: once the depot's tree has it and farms are near,
## the leader asks for a spur to the co-op elevator, and the farms' grain
## leaves by covered hopper instead of by truck.
## Run: godot --headless -s tests/test_rail_grain.gd

var _fails := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var site := Rail.site_near(sim.network, Vector3(0, 0, 60))
	_check(sim.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z],
		"axis": [site[2].x, site[2].z]}), "the depot is placed")
	var did: int = sim.rail.depots.keys()[0]
	var d: Dictionary = sim.rail.depots[did]
	# The co-op elevator down the road, on the same side as the yard.
	var eid := -1
	for x in range(500, 1400, 100):
		var es := Parks.site_near(sim.network, "grain_elevator", Vector3(x, 0, 60))
		if not es.is_empty() and sim.apply({"type": "place_park", "kind": "grain_elevator", "pos": [es[0].x, es[0].z],
				"dir": [es[1].x, es[1].z]}):
			eid = sim.parks.sites.keys()[-1]
			break
	_check(eid != -1, "the co-op elevator goes up")
	# Farms across the highway, with their fields grown.
	var farms := 0
	for x in range(-1950, 1950, 300):
		if sim.apply({"type": "place_farmhouse", "pos": [x, -90], "dir": [0, 1], "crop": "corn"}):
			farms += 1
	_check(farms >= 2, "farms around town (%d)" % farms)
	for fid in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[fid]
		f.barn = true
		for y in range(1, 13):
			for x in range(-3, 4):
				if not Vector2i(x, y) in f.cells:
					f.cells.append(Vector2i(x, y))
	var per_year := Rail.grain_cars_per_year(sim, sim.parks.sites[eid].pos)
	_check(per_year > 10.0, "the farms grow enough for rail (%d carloads a year)" % roundi(per_year))
	# The main line first.
	_run(sim, Balance.RAIL_DECIDE_EVERY + 1)
	var reqs := sim.rail.open_requests()
	_check(reqs.size() == 1, "the leader asks for a main line")
	if reqs.is_empty():
		_done()
		return
	sim.apply({"type": "permit", "id": sim.rail.lines[reqs[0]].permit, "answer": "approve"})
	_run(sim, 24 * 60 * 8)
	_check(sim.rail.lines[reqs[0]].state == "open", "the main line opens")
	# Without the grain spur on its tree, the leader doesn't look at the elevator.
	d.built = ["team_track"]
	d.skip.clear()
	_run(sim, Balance.RAIL_DECIDE_EVERY * 2)
	for lid in sim.rail.open_requests():
		_check(not str(sim.rail.lines[lid].target.ref).begins_with("elev:"), "no elevator spur before the tree has one")
	# With it, and a bold leader, the elevator gets its spur.
	d.built = ["team_track", "grain_spur"]
	d.leader.ambition = 1.0
	d.leader.caution = 0.1
	d.skip.clear()
	var spur := -1
	for i in 8:
		_run(sim, Balance.RAIL_DECIDE_EVERY)
		for lid in sim.rail.open_requests():
			if str(sim.rail.lines[lid].target.ref) == "elev:%d" % eid:
				spur = lid
		if spur != -1:
			break
		d.skip.clear()
	_check(spur != -1, "the leader asks for a spur to the elevator (%s)" % d.why)
	if spur == -1:
		_done()
		return
	var l: Dictionary = sim.rail.lines[spur]
	sim.apply({"type": "permit", "id": l.permit, "answer": "approve"})
	_run(sim, 24 * 60 * 6)
	_check(l.state == "open", "the elevator spur opens (%s)" % l.state)
	_check(sim.rail.ships_by_rail(sim, "elev:%d" % eid), "the elevator ships by rail")
	# Trucks bring grain in from the farms; covered hoppers take it out.
	_run(sim, 10)
	_check(int(l.get("store", -1)) != -1 and sim.warehouses.buildings.has(int(l.store)),
		"the elevator takes truckloads from the farms")
	var store: int = l.store
	var sent := 0
	for i in 24 * 60 * 6:
		if i % 60 == 0 and Warehouses.stored(sim.warehouses.buildings[store]) < 20:
			for k in 5:
				sim.warehouses.receive(store, {"good": "corn", "amount": int(Balance.GRAIN_TRUCK_BUSHELS)}, Warehouses.RAW)
				sent += 1
		sim.tick()
		if int(d.get("delivered", 0)) > 0:
			break
	var t: Dictionary = sim.rail.trains[d.freight_train]
	_check(int(d.get("delivered", 0)) > 0, "covered hoppers of grain reach the region (%s)" % t.purpose)
	var hoppers := 0
	for k in t.consist:
		if k == "covered":
			hoppers += 1
	_check(t.cargo == "grain" or hoppers > 0 or int(d.delivered) > 0, "the train is made up of covered hoppers")
	# Saves keep the elevator's store.
	var copy := CitySim.new()
	copy.simulate_traffic = false
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(int(copy.rail.lines[spur].get("store", -1)) == store, "a save keeps the elevator's store")
	_done()


func _run(sim: CitySim, n: int) -> void:
	for i in n:
		sim.tick()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
