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
	for i in 4000:
		var at := Vector3((i % 64) * 157.0, 0.0, (i / 64) * 157.0)
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
	print("  leader: ", s.leader, " -> ", s.plant, ": ", s.why)
	_check(s.cells.size() == 1, "the first unit goes up right away")
	_check(sim.services.utility_use.power[1] > 0, "the plant adds power capacity (%s)" % str(sim.services.utility_use.power))
	for x in range(-380, 120, 10):
		sim.apply({"type": "paint_zone", "center": [o.x + x, o.z - 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.apply({"type": "build_road", "start": [o.x - 400, o.z], "ctrl": [o.x - 400, o.z - 100], "end": [o.x - 400, o.z - 200]})
	var wells := sim.services.buildings.size()
	_check(wells == 0, "no substation or feed")
	var site := Services.site_near(sim.network, Services.Kind.WELL, o + Vector3(-300, 0, 30))
	sim.apply({"type": "place_service", "kind": Services.Kind.WELL, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	for i in 3000:
		sim.tick()
	var powered := 0
	for key in sim.buildings:
		if sim.services.served[key].power:
			powered += 1
	_check(powered > 0, "homes grow on the company's power alone (%d)" % powered)
	print("  cells %d, capacity %d, sales %s, savings %d, upgrades %s" % [s.cells.size(), sim.power.capacity(id),
		str(sim.power.sales.get(id)), int(s.savings), str(s.upgrades)])
	if s.plant == "coal":
		_check(sim.power.land_value_effect(Power.cell_center(s, s.cells[0])) < -0.1, "coal smoke lowers land value next door")
		_check(sim.power.land_value_effect(Power.cell_center(s, s.cells[0]) + Vector3(3000, 0, 0)) == 0.0, "but not far away")

	# A coal company's tree: scrubbers with money; a schooled successor with
	# oil nearby switches to gas.
	var t := Power.new()
	var tid := t.add_site(oily, Vector3(0, 0, -1), [], 0.1, 7)
	var ts: Dictionary = t.sites[tid]
	ts.plant = "coal"
	ts.cells = [Vector2i(0, 1)]
	ts.savings = 0.0
	_check(not t.grow_tree(tid, {"day": 1.0}), "no money, no add-ons")
	ts.savings = 3_000_000.0
	ts.leader.education = 0.35
	t.grow_tree(tid, {"day": 2.0})
	_check("scrubbers" in ts.upgrades, "scrubbers once it can afford them")
	ts.savings = 10_000_000.0
	ts.leader.education = 0.6
	t.grow_tree(tid, {"day": 3.0})
	_check(ts.plant == "gas" and "repower" in ts.upgrades, "a schooled leader switches coal to gas near oil (%s)" % ts.plant)
	_check(t.unlock_problem(tid, "tie_line", {}) != "", "line to a neighbor waits for a neighbor short of power")
	_check(t.unlock_problem(tid, "tie_line", {"neighbor_short": 500.0}) == "", "and unlocks when one is")
	# A successor takes over when the term is up, better schooled with training.
	ts.upgrades.append("training")
	var before: String = ts.leader.name
	t.grow_tree(tid, {"day": 3.0 + Balance.POWER_LEADER_TERM_DAYS, "education": 0.5})
	_check(ts.hired > 3.0, "a successor takes over (%s -> %s)" % [before, ts.leader.name])

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


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + what)
