extends SceneTree
## Run: godot --headless -s tests/test_power.gd

var _fails := 0


func _init() -> void:
	var p := Power.new()
	# The leader's schooling decides the plant: short horizons buy old coal,
	# long ones build clean power. Look for an oil spot and a calm, open one.
	var oily := Vector3.INF
	var calm := Vector3.INF
	var windy := Vector3.INF
	for i in 6400:
		var at := Vector3((i % 80) * 200.0 - 8000.0, 0.0, (i / 80) * 200.0 - 8000.0)
		if Backdrop.inside(Vector2(at.x, at.z), 1000.0):
			continue
		if oily == Vector3.INF and p.gas(at) > 0.7 and p.reach_quality("hydro", at) < 0.3:
			oily = at
		if calm == Vector3.INF and p.gas(at) == 0.0 and p.reach_quality("wind", at) < 0.3 \
				and p.reach_quality("hydro", at) < 0.3 and Terrain.buildable(at.x, at.z, 250.0) \
				and Resources.at(Resources.Kind.FOREST, at) < 0.1:
			calm = at
		if windy == Vector3.INF and p.gas(at) == 0.0 and p.reach_quality("wind", at) > 0.85 \
				and p.reach_quality("hydro", at) < 0.3:
			windy = at
	_check(oily != Vector3.INF and calm != Vector3.INF and windy != Vector3.INF, "found test spots")
	var low := {"name": "Earl Riggs", "education": 0.15}
	var mid := {"name": "Deb Yoder", "education": 0.45}
	var high := {"name": "Lori Voss", "education": 0.85}
	_check(p.choose(low, calm)[0] == "coal", "a poorly schooled leader buys an old coal plant (%s)" % p.choose(low, calm)[0])
	_check(p.choose(high, calm)[0] == "solar", "an engineer builds solar on calm open ground (%s)" % p.choose(high, calm)[0])
	_check(p.choose(high, windy)[0] == "wind", "an engineer builds wind where it's windy (%s)" % p.choose(high, windy)[0])
	_check(p.choose(mid, oily)[0] == "gas", "a college-educated leader near oil builds gas (%s)" % p.choose(mid, oily)[0])
	_check(p.scores(high, calm)["hydro"] == -INF, "no river, no dam")
	p.river = func(_q): return 1.0
	_check(p.choose(high, calm)[0] == "hydro", "an engineer on the river builds a dam (%s)" % p.choose(high, calm)[0])
	for e in [0.1, 0.3, 0.4, 0.5, 0.6, 0.8]:
		print("  education %.1f: calm %s, oil %s, windy %s" % [e, p.choose({"name": "x", "education": e}, calm)[0],
			Power.new().choose({"name": "x", "education": e}, oily)[0], Power.new().choose({"name": "x", "education": e}, windy)[0]])

	# In a town: the plant powers homes with no substation, grows to cover
	# the load, and a coal plant's smoke lowers the land near it.
	var sim := CitySim.new()
	sim.require_utilities = true
	sim.economy.money = 50_000_000
	var o := calm
	sim.apply({"type": "build_road", "start": [o.x - 400, o.z], "ctrl": [o.x, o.z], "end": [o.x + 400, o.z]})
	sim.region_links.append(sim.network.find_node_near(Vector3(o.x + 400, 0, o.z), 1.0))
	var at := o + Vector3(200, 0, 60)
	var dir := Vector3(0, 0, -1)
	_check(sim.power_problem(at, dir) == "", "yard fits beside the road (%s)" % sim.power_problem(at, dir))
	_check(sim.apply({"type": "place_power", "pos": [at.x, at.z], "dir": [dir.x, dir.z]}), "place a power company")
	var id: int = sim.power.sites.keys()[0]
	var s: Dictionary = sim.power.sites[id]
	print("  leader: ", s.leader, " -> ", s.plant, ": ", s.reason)
	_check(s.cells.size() == 1, "the first unit goes up right away")
	_check(sim.services.utility_use.power[1] > 0, "the plant adds power capacity (%s)" % str(sim.services.utility_use.power))
	for x in range(-380, 120, 10):
		sim.apply({"type": "paint_zone", "center": [o.x + x, o.z - 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.apply({"type": "build_road", "start": [o.x - 400, o.z], "ctrl": [o.x - 400, o.z - 100], "end": [o.x - 400, o.z - 200]})
	var wells := sim.services.buildings.size()
	_check(wells == 0, "no substation or feed")
	var site := Services.site_near(sim.network, Services.Kind.WELL, o + Vector3(-300, 0, 30))
	sim.apply({"type": "place_service", "kind": Services.Kind.WELL, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var crewed := 0
	for i in 3000:
		sim.tick()
		crewed = maxi(crewed, sim.power.crews.size())
	var powered := 0
	for key in sim.buildings:
		if sim.services.served[key].power:
			powered += 1
	_check(crewed > 0, "a line crew drives out from the yard")
	_check(powered > 0, "homes grow on the company's power alone (%d)" % powered)
	print("  cells %d, capacity %d, sales %s, built %s" % [s.cells.size(), sim.power.capacity(id),
		str(sim.power.sales.get(id)), str(s.built)])
	if s.plant == "coal":
		var next_door: Vector3 = Power.cell_center(s, s.cells[0]) + s.dir * 150.0
		_check(sim.power_nuisance(next_door) < -0.05, "coal smoke lowers land value next door (%.2f)" % sim.power_nuisance(next_door))
		_check(sim.power_nuisance(next_door + Vector3(5000, 0, 0)) == 0.0, "but not far away")

	# Wild trees clear off the yard and every unit.
	sim.vegetation.update(sim)
	_check(sim.vegetation.is_occupied(Vegetation.cell_of(s.pos)), "trees don't grow in the yard")
	_check(sim.vegetation.is_occupied(Vegetation.cell_of(Power.cell_center(s, s.cells[-1]))), "or on its units")
	# A line to the neighbors follows the road out of town on wood poles.
	_check(sim.power.tie_route(sim.network, sim.region_links, s).is_empty(), "no line until the leader builds one")
	s.built.append("tie_line")
	var line: PackedVector3Array = sim.power.tie_route(sim.network, sim.region_links, s)
	var out_at: Vector3 = sim.network.nodes[sim.region_links[0]]
	_check(line.size() > 2 and line[0] == s.pos and Vector2(line[-1].x - out_at.x, line[-1].z - out_at.z).length() < 30.0,
		"the line runs from the yard to the road out of town (%d points)" % line.size())
	var spans := Power.poles(line)
	var longest := 0.0
	for i in range(1, spans.size()):
		longest = maxf(longest, spans[i].distance_to(spans[i - 1]))
	_check(spans.size() >= 4 and longest <= Balance.POWER_TIE_SPAN + 0.5, "poles about a span apart (%d, longest %.0f m)" % [spans.size(), longest])
	sim.power_changed.emit()
	sim.vegetation.update(sim)
	var sub := Power.substation(line)
	_check(sub.size() == 2 and Vector2(sub[0].x - out_at.x, sub[0].z - out_at.z).length() < 60.0, "a substation stands where the line meets the road out")
	var under := line[line.size() / 2]
	_check(sim.vegetation.is_occupied(Vegetation.cell_of(under)), "the corridor under the line is kept clear")
	if sub.size() == 2:
		_check(sim.vegetation.is_occupied(Vegetation.cell_of(sub[0])), "and the substation yard")
	s.built.erase("tie_line")
	sim.power_changed.emit()

	# A coal company's tree (Agency): nothing while it loses money;
	# scrubbers once it profits; a schooled leader near oil switches to gas.
	var t := CitySim.new()
	var tid := t.power.add_site(oily, Vector3(0, 0, -1), [], 0.1, 7)
	var ts: Dictionary = t.power.sites[tid]
	ts.plant = "coal"
	ts.cells = [Vector2i(0, 1)]
	ts.leader.edu = 0.35
	ts.leader.caution = 0.0
	ts.leader.ambition = 1.0
	t.power.sales[tid] = {"profit": -100_000.0}
	_check(not t.power.develop(t, tid, {"day": 1.0}), "a losing plant builds nothing")
	t.power.sales[tid] = {"profit": 1_000_000.0}
	t.power.develop(t, tid, {"day": 2.0})
	_check("scrubbers" in ts.built, "scrubbers once it makes money (%s)" % str(ts.built))
	ts.leader.edu = 0.6
	t.power.sales[tid] = {"profit": 3_000_000.0}
	for i in 3:
		t.power.develop(t, tid, {"day": 3.0 + i})
	_check(ts.plant == "gas" and "repower" in ts.built, "a schooled leader switches coal to gas near oil (%s %s)" % [ts.plant, str(ts.built)])
	var tie: Dictionary = Power.TREE.filter(func(n): return n.id == "tie_line")[0]
	_check(not Agency.open(t, ts, [tie], ts.pos, 3_000_000.0).size(), "line to a neighbor waits for a neighbor buying power")
	t.region_links.append(0)
	t.trade.last_deals = [{"good": "power", "amount": 100.0, "seller": "me", "buyer": "Bob", "price": 38.0}]
	_check(Agency.open(t, ts, [tie], ts.pos, 3_000_000.0).size() == 1, "and opens when one is")
	# A successor takes over when the term is up, better schooled with training.
	ts.built.append("training")
	var before: String = ts.leader.name
	t.power.develop(t, tid, {"day": 10.0 + Balance.POWER_LEADER_TERM_DAYS, "education": 0.5})
	_check(ts.hired > 10.0 and ts.leader.edu >= 0.5, "a better-schooled successor takes over (%s -> %s)" % [before, ts.leader.name])

	# Wind on farmland: a turbine may stand in a farmer's field, which stays
	# farmed; the wind company pays the farm a lease.
	var w := CitySim.new()
	var fid := w.farms.add_farm(windy, Vector3(0, 0, -1), "corn", [])
	var farm: Dictionary = w.farms.farms[fid]
	farm.cells = [Vector2i(0, 1)]
	var field_mid: Vector3 = Farms.cell_center(farm, Vector2i(0, 1))
	var before_lease := w.farms.field_profit(farm, Vector2i(0, 1))
	var wid := w.power.add_site(field_mid + Vector3(0, 0, -300), Vector3(0, 0, -1), [], 0.8, 3)
	var ws: Dictionary = w.power.sites[wid]
	ws.plant = "wind"
	_check(not w.field_usable(field_mid, Farms.cell_corners(farm, Vector2i(0, 1))) and w.pad_usable(field_mid, Farms.cell_corners(farm, Vector2i(0, 1))),
		"a turbine pad may go in a field where nothing else can")
	ws.pos = field_mid - ws.dir * -Power.spacing(ws)  # cell (0, 1) lands on the field
	ws.cells = [Vector2i(0, 1)]
	_check(Power.cell_center(ws, Vector2i(0, 1)).distance_to(field_mid) < 1.0, "the test turbine stands in the field")
	_check(w.power.leased(ws) == 1, "the company leases that ground")
	_check(is_equal_approx(w.farms.field_profit(farm, Vector2i(0, 1)) - before_lease, Balance.POWER_WIND_LEASE),
		"the farm earns the lease on top of its crop")
	_check(farm.cells.size() == 1, "and keeps farming the field")

	# Solar boxed in by cornfields asks the player (a land-use permit) to
	# lease farmland; once approved, the fields become panel rows and the
	# farm earns rent instead of a crop.
	var sol := CitySim.new()
	_no_county_roads(sol, calm)
	var sfid := sol.farms.add_farm(calm + Vector3(-1000, 0, 0), Vector3(0, 0, -1), "corn", [])
	var sf: Dictionary = sol.farms.farms[sfid]
	for fx in range(14, 37):
		for fy in range(-11, 12):
			sf.cells.append(Vector2i(fx, fy))
	var fields_before: int = sf.cells.size()
	var sid := sol.power.add_site(calm, Vector3(0, 0, -1), [], 0.8, 5)
	var ss: Dictionary = sol.power.sites[sid]
	ss.plant = "solar"
	ss.cells = [Vector2i(0, 1)]
	sol.power.decide(sol.field_usable, 1_000_000.0, false, {})
	_check(not ss.get("farm_want", []).is_empty(), "boxed in by fields, the solar company eyes the farmland (%d)" % ss.get("farm_want", []).size())
	_check(ss.cells.size() == 1, "but doesn't take it on its own")
	sol.power.farmland(sol, sid)
	var asked: Array = sol.permits.requests.values().filter(func(r): return r.hub == "power")
	_check(asked.size() == 1 and asked[0].change == "Farmland to solar panels", "it asks you first: %s" % (asked[0].title if asked.size() else "nothing"))
	if asked.size() == 1:
		sol.apply({"type": "permit", "id": asked[0].id, "answer": "approve"})
		sol.power.farmland(sol, sid)
		_check(ss.cells.size() > 1, "approved, panels go up on the leased fields (%d units)" % ss.cells.size())
		_check(sf.cells.size() < fields_before, "the farm gives those fields up (%d of %d left)" % [sf.cells.size(), fields_before])
		_check(sol.power.farm_rent(sfid) > 0.0, "and earns rent for them ($%d a year)" % roundi(sol.power.farm_rent(sfid)))
		var sol2 := CitySim.new()
		sol2.from_dict(JSON.parse_string(JSON.stringify(sol.to_dict())))
		_check(is_equal_approx(sol2.power.farm_rent(sfid), sol.power.farm_rent(sfid)), "a save keeps the leases")

	# A dam spans the river bank to bank, across the flow.
	var rp := Power.new()
	rp.river = func(q): return 1.0 if absf(q.z - 500.0) < 45.0 else 0.0
	var dspan: Array = rp.dam_span(Vector3(200, 0, 500))
	_check(dspan.size() == 2 and absf(dspan[0].x - dspan[1].x) < 1.0 and absf(dspan[0].distance_to(dspan[1]) - 84.0) < 13.0,
		"a dam runs across a 90 m river (%s)" % str(dspan))
	_check(rp.dam_span(Vector3(200, 0, 700)).is_empty(), "and only where there's a river")

	# Saves and copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.power.sites.size() == 1 and copy.power.sites[id].cells == s.cells, "save round trip keeps the plant")
	for i in 400:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.power.to_dict()) == JSON.stringify(sim.power.to_dict()), "copies stay in sync")
	print("power tests: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


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
		_fails += 1
		print("FAIL: " + what)
