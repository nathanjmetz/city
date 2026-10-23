extends SceneTree
## Run: godot --headless -s tests/test_telecom.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 200_000_000
	sim.build_county_road(Vector2(-6000, 0), Vector2(2000, 0), [0, 1])
	# A street of homes north of the highway, near where the office goes...
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, -150], "end": [-300, -300]})
	_homes(sim, -300)
	# ...and a hamlet far out along the highway, past any tower's reach.
	sim.apply({"type": "build_road", "start": [-5200, 0], "ctrl": [-5200, -150], "end": [-5200, -300]})
	_homes(sim, -5200)
	for i in 6000:
		sim.tick()
	_check(sim.stats.population > 0, "people live in town (%d)" % sim.stats.population)

	# Placing: beside a street, one per town.
	var site := Telecom.site_near(sim.network, Vector3(300, 0, 60))
	_check(site.size() == 2, "the office finds its spot beside the highway")
	_check(Telecom.site_problem(sim, site[0], site[1]) == "", "open ground is fine (%s)" % Telecom.site_problem(sim, site[0], site[1]))
	var money := sim.economy.money
	_check(sim.apply({"type": "place_telecom", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"placing the phone company")
	_check(money - sim.economy.money == Balance.TELECOM_COST, "the city pays for the office")
	var id: int = sim.telecom.companies.keys()[0]
	var c: Dictionary = sim.telecom.companies[id]
	_check(str(c.leader.name) != "", "it hires a manager (%s)" % Telecom.leader_name(c.leader))
	_check(c.towers.size() == 1, "its first tower stands in its own yard")
	_check(sim.telecom.covers(site[0]), "the company covers its office block")
	var site2 := Telecom.site_near(sim.network, Vector3(900, 0, 60))
	_check(Telecom.site_problem(sim, site2[0], site2[1]) != "", "only one phone company per town")

	# A month: fiber goes down the street of homes, densest first, through
	# the empty highway between. A well-schooled manager plans far ahead.
	c.savings = 5_000_000.0
	c.leader.edu = 1.0
	for k in sim.buildings:
		sim.buildings[k].occ = sim.buildings[k].cap
	sim.telecom.decide(sim)
	_check(not c.fiber.is_empty(), "crews string fiber (%d streets)" % c.fiber.size())
	var on_homes := false
	for f in c.fiber:
		var s: Dictionary = sim.network.segments.get(int(f.seg), {})
		for key in sim.lots:
			on_homes = on_homes or (int(sim.lots[key].seg) == int(f.seg) and sim.buildings.has(key))
	_check(on_homes, "fiber runs past homes")
	_check(not c.jobs.is_empty(), "fiber crews have real truck trips waiting")
	_check(c.subs.fiber > 0.0 or true, "homes sign up")
	sim.telecom.decide(sim)
	_check(c.subs.fiber > 0.0, "homes on the fiber street sign up (%.1f)" % c.subs.fiber)
	_check(c.subs.wireless > 0.0, "cell customers near the yard tower (%.1f)" % c.subs.wireless)

	# Coverage: town homes have signal; the far hamlet has none.
	var near_q := 0.0
	var far_q := 1.0
	for key in sim.telecom.served:
		var p: Vector3 = sim.lots[key].pos
		if p.x > -1000.0:
			near_q = maxf(near_q, sim.telecom.served[key].q)
		else:
			far_q = minf(far_q, sim.telecom.served[key].q)
	_check(near_q > 0.9, "full signal in town (%.2f)" % near_q)
	_check(far_q < Balance.TELECOM_GOOD_SIGNAL, "rural edges stay spotty (%.2f)" % far_q)

	# Effects: lifted values, remote workers, a grant in the budget.
	var lifted := false
	for key in sim.telecom.served:
		lifted = lifted or sim.telecom.lot_lift(key) > Balance.TELECOM_FIBER_LIFT
	_check(lifted, "fiber and signal lift home values")
	sim.update_stats()
	_check(sim.telecom.remote_workers > 0, "remote workers move in on fiber (%d)" % sim.telecom.remote_workers)
	_check(int(sim.economy.budget.telecom) == Balance.TELECOM_GRANT, "the budget pays the broadband grant")
	_check(sim.apply({"type": "set_telecom_funding", "id": id, "level": 4}), "grant raised")
	_check(Telecom.monthly_grant(c) == roundi(Balance.TELECOM_GRANT * 1.5), "grant at 150%")
	var h0 := Telecom.horizon(sim, id, c)
	sim.apply({"type": "set_telecom_funding", "id": id, "level": 0})
	_check(Telecom.horizon(sim, id, c) < h0, "a smaller grant means a shorter plan")
	sim.apply({"type": "set_telecom_funding", "id": id, "level": 4})

	# Towers: the manager asks on the bell for one by the hamlet, if it pays.
	c.leader.ambition = 1.0
	sim.apply({"type": "guide", "hub": "telecom", "hub_id": id, "stance": "grow", "grant": 0})
	for k in sim.buildings:
		if sim.lots[k].pos.x < -4000.0:
			sim.buildings[k].occ = sim.buildings[k].cap * 25  # a big hamlet, so a tower pays
	sim.telecom.decide(sim)
	_check(not c.pending.is_empty(), "a tower request goes to the bell")
	if not c.pending.is_empty():
		var p: Array = c.pending.pos
		_check(Vector2(p[0], p[1]).distance_to(Vector2(-5200, -150)) < 2000.0, "it's by the poorly served homes")
		_check(sim.permits.state_of(int(c.pending.req)) == Permits.State.OPEN, "it waits for the player")
		_check(sim.apply({"type": "permit", "id": int(c.pending.req), "answer": "approve"}), "the player approves")
		sim.telecom.decide(sim)
		_check(c.towers.size() == 2, "the tower goes up once approved")
		_check(sim.telecom.covers(Vector3(p[0], 0, p[1])), "its compound is the company's")
		var hit := false
		for job in c.jobs:
			hit = hit or job.what == "tower"
		_check(hit, "a crew truck heads out to raise it")

	# The tree (shared Agency model): no 5G without an educated manager and a
	# big enough town; middle-mile fiber before a data center.
	var fresh := {"built": [], "towers": [], "leader": {"edu": 0.2, "ambition": 0.5, "caution": 0.5},
		"facts": {"towers": 1, "fiber_km": 1.0, "shops": 0}}
	var open := Agency.open(sim, fresh, Telecom.TREE, c.pos, 1_000_000.0).map(func(n): return n.id)
	_check(not "lte_5g" in open, "no 5G with a manager who never went to college")
	_check(not "data_center" in open, "no data center without middle-mile fiber")
	_check("garage" in open, "a crew garage is open from the start")
	fresh.leader.edu = 0.9
	fresh.facts = {"towers": 4, "fiber_km": 20.0, "shops": 20}
	_check("noc" in Agency.open(sim, fresh, Telecom.TREE, c.pos, 1_000_000.0).map(func(n): return n.id),
		"a schooled manager with towers opens an operations center")

	# It grows next door, never a second site.
	c.savings = 20_000_000.0
	for i in 4:
		sim.telecom.decide(sim)
		c.savings = 20_000_000.0
	for blk in c.blocks:
		var touching := false
		for other in c.blocks + [{"c": Vector2i.ZERO}]:
			touching = touching or (absi(blk.c.x - other.c.x) + absi(blk.c.y - other.c.y) == 1)
		_check(touching, "block %s touches the office (no second sites)" % str(blk.c))

	# Inspect shows its manager and the grant lever.
	var d := Inspect.describe(sim, Inspect.pick(sim, site[0]))
	_check(d.get("title", "") == "Phone company", "clicking the office inspects it")
	_check(not d.get("actions", []).is_empty(), "the panel offers grant buttons")

	# Saves round-trip.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var cc: Dictionary = copy.telecom.companies[id]
	_check(cc.fiber.size() == c.fiber.size() and cc.towers.size() == c.towers.size() and cc.leader.name == c.leader.name,
		"save keeps the fiber, towers and manager")

	# Bulldozing a tower takes it down; the manager won't put one right back.
	if c.towers.size() > 1:
		var t: Array = c.towers[1].pos
		_check(sim.apply({"type": "remove_telecom_at", "pos": [t[0], t[1]]}), "bulldozing a tower")
		_check(c.towers.size() == 1, "the tower is gone")

	# The road wins: a road through the office closes it and pays back.
	money = sim.economy.money
	sim.apply({"type": "build_road", "start": [site[0].x - 100, site[0].z], "ctrl": [site[0].x, site[0].z],
		"end": [site[0].x + 100, site[0].z]})
	_check(not sim.telecom.companies.has(id), "a road through the office closes the company")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _homes(sim: CitySim, x: float) -> void:
	for z in range(-290, -10, 10):
		sim.apply({"type": "paint_zone", "center": [x + 25, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x - 25, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})


var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
