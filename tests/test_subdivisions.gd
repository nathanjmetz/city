extends SceneTree
## Run: godot --headless -s tests/test_subdivisions.gd
## Home builders (Subdivisions): once the town is big enough and out of
## home lots, a builder asks on the bell with a choice of sites, each with a
## ghost, a cost and what a yes means. The player picks one; the builder
## lays the first phase's streets (two entrances, at its own cost) and zones
## them for homes; the next phase opens once most of the last has sold.

var _failed := false
const MONTH := 24 * CitySim.TICKS_PER_HOUR


func _init() -> void:
	var sim := _town(7)
	_check(Subdivisions._free_homes(sim) < Balance.SUBDIV_FREE_LOTS, "the test town has no home lots left (%d)" % Subdivisions._free_homes(sim))

	# --- Too small: no builder comes.
	sim.stats.population = 100
	_ask(sim)
	_check(sim.subdivisions.pending.is_empty(), "a hamlet gets no builder")

	# --- Big enough and out of lots: a builder asks, with a choice of sites.
	sim.stats.population = 2500
	sim.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	sim.subdivisions.month(sim)
	_check(not sim.subdivisions.scout.is_empty(), "a builder starts scouting for land")
	# A save in the middle of scouting carries on the same way.
	var mid := CitySim.new()
	mid.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	# (The test set these by hand; a real town works them out the same.)
	mid.stats.population = sim.stats.population
	mid.demand = sim.demand.duplicate()
	var worst := 0.0
	for h in 48:
		var t0 := Time.get_ticks_usec()
		sim.subdivisions.hour(sim)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		mid.subdivisions.hour(mid)
	print("  the slowest hour of scouting took %.1f ms" % worst)
	var a := JSON.stringify(mid.permits.to_dict())
	var b := JSON.stringify(sim.permits.to_dict())
	if a != b:
		for i in a.length():
			if a[i] != b[i]:
				print("  differs at: ", a.substr(maxi(0, i - 200), 300), "\n  vs ", b.substr(maxi(0, i - 200), 300))
				break
	_check(a == b, "a town loaded mid-scout asks the same thing")
	_check(sim.subdivisions.pending.size() == 1, "a builder asked")
	if sim.subdivisions.pending.is_empty():
		_finish()
		return
	var id: int = sim.subdivisions.pending.keys()[0]
	var req: Dictionary = sim.permits.requests[id]
	var opts: Array = req.options
	print("  ", req.title, " | sites: ", opts.size(), " | ", req.why)
	_check(opts.size() >= 2, "it offers at least two sites (%d)" % opts.size())
	for o in opts:
		print("    %s %s: %d homes, %s acres, builder spends $%s, upkeep $%s/yr, taxes $%s/yr, water %d%%" % [
			o.letter, o.name, o.homes, o.effects.acres, CitySim.money_text(o.cost), CitySim.money_text(o.effects.upkeep),
			CitySim.money_text(o.effects.taxes), o.effects.water])
		_check(int(o.homes) > 30 and not o.ghost.is_empty() and not o.streets.is_empty(), "site %s has a ghost of its homes and streets" % o.letter)
		_check(int(o.effects.kids) > 0 and int(o.effects.trips) > int(o.homes), "site %s says what a yes means" % o.letter)
	var other_site: Dictionary = opts[0]
	for i in range(1, opts.size()):
		_check(Vector2(opts[i].o[0], opts[i].o[1]).distance_to(Vector2(other_site.o[0], other_site.o[1])) >= Balance.SUBDIV_SITE_APART - 0.1,
			"the sites are apart")
	_check(req.state == Permits.State.OPEN, "it waits on the bell")
	_check(not sim.permits.answer(sim, {"id": id, "answer": "edit", "route": req.route}), "a choice of sites can't be redrawn")

	# --- Determinism: a second copy of the same town asks the same thing.
	var twin := _town(7)
	twin.stats.population = 2500
	twin.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	_ask(twin)
	var twin_req: Dictionary = twin.permits.requests.get(twin.subdivisions.pending.keys()[0] if not twin.subdivisions.pending.is_empty() else -1, {})
	_check(JSON.stringify(twin_req.get("options", [])) == JSON.stringify(opts), "every copy of the town gets the same sites")

	# --- The player picks the last site.
	var pick := opts.size() - 1
	var money: int = sim.economy.money
	var roads_before: int = sim.network.segments.size()
	_check(sim.apply({"type": "permit", "id": id, "answer": "approve", "pick": pick}), "approving a site works")
	_check(sim.permits.requests[id].route == Permits._route(opts[pick].outline), "the approved site is the one picked")
	sim.subdivisions.carry_out(sim)
	_check(sim.subdivisions.active.size() == 1, "the subdivision started")
	var made: int = sim.network.segments.size() - roads_before
	_check(made >= 3, "the builder laid the first phase's streets (%d new pieces)" % made)
	_check(sim.economy.money == money, "the builder paid for the streets, not the town")
	var sid: int = sim.subdivisions.active.keys()[0]
	var site: Dictionary = sim.subdivisions.active[sid].site
	var entrances := 0
	for s in [-1.0, 1.0]:
		var e := Subdivisions.local(site, s * (Balance.SUBDIV_WIDTH * 0.5 - Balance.SUBDIV_SPINE_IN), -float(site.hw))
		if not sim.network.find_segment_near(e, 3.0).is_empty():
			entrances += 1
	_check(entrances == 2, "two ways in from the start (fire code)")
	for i in 30:
		sim.tick()
	var fill := sim.subdivisions.sold(sim, sid)
	print("  phase 1 lots: ", fill)
	_check(fill.y >= 10, "the new streets were platted into home lots (%d)" % fill.y)

	# --- Phase 2 waits for the first to sell.
	sim.tick_count += Balance.SUBDIV_PHASE_MIN_MONTHS * MONTH
	sim.subdivisions.month(sim)
	_check(int(sim.subdivisions.active[sid].phase) == 1, "the next phase waits until the first has sold")
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.RESIDENTIAL:
			sim.buildings[key] = BuildingTypes.make(sim, key, {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": hash(key), "built": sim.tick_count,
				"changed": sim.tick_count, "occ": 2}, "house", 0)
	sim.subdivisions.month(sim)
	_check(int(sim.subdivisions.active[sid].phase) == 2, "once it has sold, the next phase opens")

	# --- A save keeps it.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.subdivisions.active.size() == 1 and int(copy.subdivisions.active[sid].phase) == 2, "a save keeps the subdivision")
	_check(JSON.stringify(copy.subdivisions.to_dict()) == JSON.stringify(sim.subdivisions.to_dict()), "the loaded copy matches")
	_finish()


## A month's check, then a game day of scouting.
func _ask(sim: CitySim) -> void:
	sim.subdivisions.month(sim)
	for h in 48:
		sim.subdivisions.hour(sim)


## A town on a long avenue, every home lot taken, with open land around it.
func _town(seed: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-1400, 0], "ctrl": [-700, 0], "end": [0, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [700, 0], "end": [1400, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -100], "end": [0, -200]})
	for x in range(-150, 151, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 600:
		sim.tick()
	for key in sim.empty_zoned_lots():
		var b := {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": hash([seed, key]), "built": sim.tick_count, "changed": sim.tick_count, "occ": 2}
		sim.buildings[key] = BuildingTypes.make(sim, key, b, "house", 0)
	sim.tick_count += 6 * MONTH
	return sim


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _finish() -> void:
	print("SOME TESTS FAILED" if _failed else "ALL TESTS PASSED")
	quit(1 if _failed else 0)
