extends SceneTree
## Run: godot --headless -s tests/test_engineer.gd
## The city engineer (CityEngineer): counts rush-hour traffic, then brings
## the worst problem to the bell with fixes to pick from: a hub road used as
## a shortcut, a jammed two-lane road, a busy alley. The town pays for what
## it approves, and a save keeps the counts and the open proposal.

var _failed := false


func _init() -> void:
	# --- A farm lane that's become a shortcut.
	var sim := _town()
	sim.stats.population = 3000
	var lane: Array = HubRoads.build(sim, [Vector3(300, 0, 0), Vector3(300, 0, 300), Vector3(600, 0, 300)], "farm:1")
	_check(lane.size() >= 2, "a farm lane joins the roads (%d pieces)" % lane.size())
	# A rush-hour count: one car passing through, one on farm business.
	sim.traffic.cars.append({"id": 9001, "route": [lane[0] * 2], "leg": 0, "from_ref": "lot:1", "to_ref": "lot:2"})
	sim.traffic.cars.append({"id": 9002, "route": [lane[0] * 2], "leg": 0, "from_ref": "farm:1", "to_ref": "lot:2"})
	sim.engineer.count(sim)
	_check(sim.engineer.counts.get(lane[0], []) == [1, 0, 1], "the count sees one car with no business on the lane (%s)" % [sim.engineer.counts.get(lane[0], [])])
	sim.traffic.cars.clear()
	sim.engineer.counts[lane[0]] = [4, 0, 6]
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	_check(sim.engineer.pending.size() == 1, "the engineer asks")
	var id: int = sim.engineer.pending.keys()[0] if not sim.engineer.pending.is_empty() else -1
	var req: Dictionary = sim.permits.requests.get(id, {})
	print("  ", req.get("title", ""), " | ", req.get("why", ""))
	_check(req.get("options", []).size() == 2, "two fixes: pave it or local traffic only")
	# A save keeps the open proposal.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.engineer.pending.has(id), "a save keeps the proposal")
	var money: int = sim.economy.money
	_check(sim.apply({"type": "permit", "id": id, "answer": "approve", "pick": 1}), "the player picks local traffic only")
	sim.engineer.carry_out(sim)
	_check(lane.all(func(s): return sim.traffic.closed.has(s)), "the lane is closed to through cars")
	_check(not sim.traffic.may_enter(lane[0], false) and sim.traffic.may_enter(lane[0], true), "the farm's trucks may still use it")
	_check(money - sim.economy.money == Balance.ENGINEER_SIGN_COST, "the town pays for the signs")

	# --- A jammed two-lane road, in a city.
	sim = _town()
	sim.stats.population = 12000
	var segs: Array = sim.network.segments.keys()
	segs.sort()
	for seg in segs:
		if int(sim.network.segments[seg].type) == RoadStyle.Type.STREET:
			sim.engineer.counts[seg] = [4, 4, 0]
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	id = sim.engineer.pending.keys()[0] if not sim.engineer.pending.is_empty() else -1
	req = sim.permits.requests.get(id, {})
	print("  ", req.get("title", ""), " | ", req.get("why", ""))
	var opts: Array = req.get("options", [])
	_check(opts.size() == 2 and int(opts[0].to) == RoadStyle.Type.AVENUE, "widen to four lanes or add a turn lane")
	_check(opts.size() == 2 and int(opts[0].cost) > int(opts[1].cost) and int(opts[1].cost) > 0, "four lanes cost more than a turn lane")
	_check(opts.size() == 2 and opts[0].segs.size() >= 2, "the whole jammed stretch is one job (%d pieces)" % (opts[0].segs.size() if opts.size() else 0))
	money = sim.economy.money
	sim.apply({"type": "permit", "id": id, "answer": "approve", "pick": 0})
	sim.engineer.carry_out(sim)
	_check(Array(opts[0].segs).all(func(s): return int(sim.network.segments[int(s)].type) == RoadStyle.Type.AVENUE), "the road is widened")
	_check(money - sim.economy.money == int(opts[0].cost), "the town pays for it ($%s)" % CitySim.money_text(int(opts[0].cost)))

	# --- Below city size, no widening yet.
	sim = _town()
	sim.stats.population = 3000
	for seg in sim.network.segments:
		sim.engineer.counts[seg] = [4, 4, 0]
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	_check(sim.engineer.pending.is_empty(), "a town too small has no engineer for widening")

	# --- A busy alley.
	sim = _town()
	sim.stats.population = 12000
	sim.apply({"type": "build_road", "start": [0, 60], "ctrl": [100, 60], "end": [200, 60], "road": RoadStyle.Type.ALLEY})
	for seg in sim.network.segments:
		if int(sim.network.segments[seg].type) == RoadStyle.Type.ALLEY:
			sim.engineer.counts[seg] = [4, 0, 0]
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	id = sim.engineer.pending.keys()[0] if not sim.engineer.pending.is_empty() else -1
	req = sim.permits.requests.get(id, {})
	_check(str(req.get("change", "")) == "Alley to street", "a busy alley becomes a street proposal")
	sim.apply({"type": "permit", "id": id, "answer": "approve", "pick": 0})
	sim.engineer.carry_out(sim)
	var alleys := 0
	for seg in sim.network.segments:
		if int(sim.network.segments[seg].type) == RoadStyle.Type.ALLEY:
			alleys += 1
	_check(alleys == 0, "the alley is paved into a street")

	# --- A neighborhood with one road in.
	sim = _town()
	sim.stats.population = 2500
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -100], "end": [0, -200]})
	sim.apply({"type": "build_road", "start": [-150, -200], "ctrl": [0, -200], "end": [150, -200]})
	var cross := -1
	for seg in sim.network.segments:
		var sg: Dictionary = sim.network.segments[seg]
		if absf(sim.network.nodes[sg.a].z + 200.0) < 1.0 and absf(sim.network.nodes[sg.b].z + 200.0) < 1.0:
			cross = seg
	for i in 20:
		sim.lots["t%d" % i] = {"seg": cross}
		sim.buildings["t%d" % i] = {"zone": ZoneMap.Zone.RESIDENTIAL, "type": "row_home", "units": 1}
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	_check(sim.engineer.pending.is_empty(), "20 homes on one road in is fine")
	for i in range(20, 31):
		sim.lots["t%d" % i] = {"seg": cross}
		sim.buildings["t%d" % i] = {"zone": ZoneMap.Zone.RESIDENTIAL, "type": "row_home", "units": 1}
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	id = sim.engineer.pending.keys()[0] if not sim.engineer.pending.is_empty() else -1
	req = sim.permits.requests.get(id, {})
	_check(str(req.get("change", "")) == "Second way in" and str(req.why).begins_with("31 homes"), "31 homes with one road in: a second way in (%s)" % req.get("title", ""))
	for i in 31:
		sim.lots.erase("t%d" % i)
		sim.buildings.erase("t%d" % i)
	var segs_before := sim.network.segments.size()
	money = sim.economy.money
	sim.apply({"type": "permit", "id": id, "answer": "approve", "pick": 0})
	sim.engineer.carry_out(sim)
	_check(sim.network.segments.size() > segs_before and money - sim.economy.money == int(req.options[0].cost), "the new street is built and paid for ($%s)" % CitySim.money_text(int(req.options[0].cost)))
	var saved := CitySim.new()
	saved.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(saved.engineer.asked.size() == sim.engineer.asked.size() and not saved.engineer.asked.is_empty(), "a save remembers what it brought up")
	sim.engineer.asked.clear()
	for i in 31:
		sim.lots["t%d" % i] = {"seg": cross}
		sim.buildings["t%d" % i] = {"zone": ZoneMap.Zone.RESIDENTIAL, "type": "row_home", "units": 1}
	sim.engineer.samples = 4
	sim.engineer.month(sim)
	_check(sim.engineer.pending.is_empty(), "with two ways in, nothing more to ask")

	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)


## A street with a crossroads, and money to spend.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	sim.apply({"type": "build_road", "start": [300, 0], "ctrl": [450, 0], "end": [600, 0]})
	sim.apply({"type": "build_road", "start": [600, 0], "ctrl": [600, 150], "end": [600, 300]})
	return sim


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true
