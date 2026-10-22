extends SceneTree
## Run: godot --headless -s tests/test_hubs.gd
## Landfills, recycling and cemeteries: they never fill up, change the land
## value around them, grow only into land right next to them, and every load
## of trash rides a real garbage truck.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
	for x in range(-400, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	# A landfill on the far end of the road, beside the street.
	var site := CivicHubs.site_near(sim.network, Vector3(300, 0, -60))
	_check(not site.is_empty(), "a landfill finds a spot beside the street")
	var money := sim.economy.money
	_check(sim.apply({"type": "place_hub", "kind": "landfill", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "landfill placed")
	_check(sim.economy.money == money - int(Balance.WASTE_SITES.landfill.cost), "landfill costs its price")
	_check(sim.hubs.hubs.size() == 1, "one hub")
	var lid: int = sim.hubs.hubs.keys()[0]
	var h: Dictionary = sim.hubs.hubs[lid]
	_check(not sim.apply({"type": "place_hub", "kind": "landfill", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a second hub can't go on top of the first")
	_check(not sim.apply({"type": "place_hub", "kind": "recycling_3", "pos": [-300, -200], "dir": [0, 1]}),
		"the big recycling plants come only as upgrades")
	# Land value: lower right next door, normal far away.
	var next_door := CivicHubs.cell_center(h, Vector2i(2, 0)) + CivicHubs.right(h) * 10.0
	var near_f := sim.hubs.value_factor(next_door)
	_check(near_f < 0.9 and near_f >= 0.84, "land next to a landfill is worth less (%.3f)" % near_f)
	_check(is_equal_approx(sim.hubs.value_factor(Vector3(-2000, 0, 0)), 1.0), "land far away is unchanged")
	for p in [h.pos - h.dir * 30.0]:
		_check(sim.hubs.covers(p), "the landfill covers its own land")
	for key in sim.lots:
		_check(not sim.hubs.covers(sim.lots[key].pos), "no lot left on the landfill's land")
	# Grow the town, and watch garbage trucks run.
	var saw_truck := false
	var saw_stop := false
	for i in 9000:
		sim.tick()
		if not sim.hubs.trips.is_empty():
			saw_truck = true
			for t in sim.hubs.trips:
				saw_stop = saw_stop or sim.hubs.trips[t].stops > 0
	_check(sim.stats.population > 50, "people moved in (%d)" % sim.stats.population)
	_check(saw_truck, "garbage trucks went out")
	_check(saw_stop, "trucks went from street to street")
	_check(h.received > 0.0, "trash reached the landfill (%.0f lb)" % h.received)
	for t in sim.hubs.trips:
		var car_ids := sim.traffic.cars.map(func(c): return c.id)
		var waiting: bool = sim.hubs.trips[t].seg == -1 or sim.hubs.claimed.has(sim.hubs.trips[t].seg)
		_check(t in car_ids or waiting, "each truck trip is a real vehicle")
	_check(sim.hubs.trucks_out(lid) <= sim.hubs.trucks(lid), "never more trucks out than the landfill has")
	# Never fills up: a landfill that has taken in a mountain still takes more.
	h.received = 1e12
	for i in 600:
		sim.tick()
	_check(sim.hubs.hubs.has(lid) and sim.hubs.trucks(lid) > 0, "a landfill never fills up")
	_check(CivicHubs.mound_height(h) <= 24.0, "the mound tops out at a real height")
	# A busy landfill grows into land right next to it, never a second site.
	var before: int = h.cells.size()
	for round in 40:
		h.want = 10
		h.short = 10
		sim.hubs._decide(sim)
	_check(h.cells.size() > before, "a busy landfill grows (%d -> %d pieces)" % [before, h.cells.size()])
	_check(h.cells.size() <= int(CivicHubs.BASE.size() * Balance.HUB_MAX_GROWTH), "growth stops at its limit")
	_check(CivicHubs._connected(h.cells).size() == h.cells.size(), "every piece touches the rest: one site")
	for c in h.cells:
		_check(c.y >= 0, "it never grows toward the road in front")
		_check(not Services.road_clash(sim.network, CivicHubs.cell_poly(h, c, 1.0)), "no piece on a road")
	# Roads win: a road through the landfill cuts it back to one piece.
	var pieces: int = h.cells.size()
	var cut := CivicHubs.cell_center(h, Vector2i(0, 2))
	var along := CivicHubs.right(h) * 400.0
	sim.apply({"type": "build_road", "start": [cut.x - along.x, cut.z - along.z], "ctrl": [cut.x, cut.z],
		"end": [cut.x + along.x, cut.z + along.z]})
	sim.tick()
	if sim.hubs.hubs.has(lid):
		_check(h.cells.size() < pieces, "a road through the landfill takes its land (%d -> %d)" % [pieces, h.cells.size()])
		_check(CivicHubs._connected(h.cells).size() == h.cells.size(), "what's left is still one site")
	# Recycling replaces the landfill; the old mound fades over time.
	money = sim.economy.money
	_check(sim.apply({"type": "upgrade_hub", "id": lid}), "landfill upgraded to recycling")
	_check(h.kind == "recycling_1" and sim.economy.money == money - int(Balance.WASTE_SITES.recycling_1.cost),
		"upgrade costs the recycling yard's price")
	var scarred := sim.hubs.value_factor(next_door)
	_check(scarred < 1.0, "the old landfill still weighs on the area at first (%.3f)" % scarred)
	h.scar = 0.0
	var healed := sim.hubs.value_factor(next_door)
	_check(healed > scarred, "once capped, recycling hurts land value less (%.3f)" % healed)
	_check(sim.apply({"type": "upgrade_hub", "id": lid}) and sim.apply({"type": "upgrade_hub", "id": lid}),
		"recycling upgrades twice")
	_check(h.kind == "recycling_3" and not sim.apply({"type": "upgrade_hub", "id": lid}), "and no further")
	_check(is_equal_approx(sim.hubs.value_factor(next_door), 1.0), "an enclosed recovery plant leaves land value alone")
	# A cemetery lifts the area around it and grows with the town.
	var cs := CivicHubs.site_near(sim.network, Vector3(-300, 0, -120))
	_check(not cs.is_empty() and sim.apply({"type": "place_hub", "kind": "cemetery", "pos": [cs[0].x, cs[0].z],
		"dir": [cs[1].x, cs[1].z]}), "cemetery placed")
	var cid: int = sim.hubs.hubs.keys().max()
	var cem: Dictionary = sim.hubs.hubs[cid]
	var lift := sim.hubs.value_factor(cem.pos + CivicHubs.right(cem) * 70.0)
	_check(lift > 1.0, "land next to a cemetery is worth a little more (%.3f)" % lift)
	sim.stats.population = Balance.CEMETERY_PEOPLE_PER_PIECE * 3
	var cb: int = cem.cells.size()
	sim.hubs._decide(sim)
	_check(cem.cells.size() == cb + 1, "a cemetery grows one piece at a time with the town")
	# Inspect and the budget know about them.
	_check(Inspect.pick(sim, cem.pos - cem.dir * 20.0).get("type", "") == "hub", "clicking a hub selects it")
	var d := Inspect.describe(sim, {"type": "hub", "id": lid})
	_check(d.get("title", "") == "Materials recovery plant", "the panel names it")
	_check(sim.hubs.monthly_cost() > 0, "hubs cost upkeep")
	# Save, load and stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.hubs.hubs.size() == sim.hubs.hubs.size(), "save keeps the hubs")
	_check(copy.hubs.hubs[cid].cells == cem.cells, "save keeps a hub's land")
	for i in 60:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.hubs.to_dict()) == JSON.stringify(sim.hubs.to_dict()), "copies stay in step")
	_check(sim.apply({"type": "remove_hub", "id": cid}) and not sim.hubs.hubs.has(cid), "a hub can be demolished")
	# Without any waste site, trash piles up and the panel says so, until
	# the town pays someone else (a neighbor, or a hauler from outside) to
	# take it away.
	var bare := CitySim.new()
	bare.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-200, 201, 10):
		bare.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		bare.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	bare.simulate_traffic = false
	for i in 6000:
		bare.tick()
	var any_key: String = bare.buildings.keys()[0]
	bare.hubs.trash[bare.lots[any_key].seg] = Balance.GARBAGE_PILE_LB * 2.0
	_check(bare.hubs.lot_problem(bare, any_key).contains("Build a landfill"),
		"with no landfill, trash piles up and says what to build")
	for i in 3000:
		bare.tick()
	_check(bare.hubs.lot_problem(bare, any_key) == "", "a town with no landfill pays to have its trash hauled away")
	# The development tree: options unlock from the town and its surroundings.
	var dev := CitySim.new()
	dev.economy.money = 50_000_000
	dev.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0]})
	var ds := CivicHubs.site_near(dev.network, Vector3(0, 0, -60))
	dev.apply({"type": "place_hub", "kind": "landfill", "pos": [ds[0].x, ds[0].z], "dir": [ds[1].x, ds[1].z]})
	var did: int = dev.hubs.hubs.keys()[0]
	var dh: Dictionary = dev.hubs.hubs[did]
	_check(dev.hubs.dev_problem(dev, did, "gas_plant").begins_with("needs a bigger site"), "a small landfill can't run a gas plant")
	_check(not dev.apply({"type": "develop_hub", "id": did, "dev": "gas_plant"}), "locked options can't be built")
	_check(dev.hubs.dev_problem(dev, did, "compost").contains("farm"), "compost needs farms to sell to")
	_check(dev.hubs.dev_problem(dev, did, "chapel") == "not for this site", "a landfill has no chapel")
	for i in 10:
		dh.want = 4
		dh.short = 4
		dev.hubs._decide(dev)
	dh.received = 2000.0 * 30_000
	money = dev.economy.money
	_check(dev.apply({"type": "develop_hub", "id": did, "dev": "gas_plant"}), "a big landfill adds a gas plant")
	_check(dev.economy.money == money - int(Balance.HUB_DEVELOPMENTS.gas_plant.cost), "the gas plant costs its price")
	for i in 1440 * 2:
		dev.tick()
	_check(dev.trade.sold("power") > 0.0, "the gas plant sells power (%.0f MWh)" % dev.trade.sold("power"))
	var tp := dev.hubs.dev_problem(dev, did, "transfer")
	_check(tp.contains("neighbor") if dev.region_links.is_empty() else tp == "",
		"taking a neighbor's trash needs a road out to neighbors (%s)" % tp)
	_check(dev.apply({"type": "upgrade_hub", "id": did}) and "gas_plant" in dh.dev,
		"a capped landfill keeps its gas plant under recycling")
	_check("scrap_yard" in CivicHubs.dev_options(dh) and "gas_plant" in CivicHubs.dev_options(dh),
		"recycling on an old landfill offers both trees")
	var info := HubInfo.describe(dev, did)
	_check(info.actions.any(func(a): return str(a.label).begins_with("Scrap metal yard: needs")),
		"the panel says what a locked option needs")
	var cem_site := CivicHubs.site_near(dev.network, Vector3(0, 0, 80))
	dev.apply({"type": "place_hub", "kind": "cemetery", "pos": [cem_site[0].x, cem_site[0].z], "dir": [cem_site[1].x, cem_site[1].z]})
	var cmid: int = dev.hubs.hubs.keys().max()
	var ch: Dictionary = dev.hubs.hubs[cmid]
	var spot: Vector3 = ch.pos + CivicHubs.right(ch) * 80.0
	var plain := dev.hubs.value_factor(spot)
	dev.stats.population = 500
	_check(dev.apply({"type": "develop_hub", "id": cmid, "dev": "chapel"}), "a cemetery adds a chapel")
	_check(dev.hubs.value_factor(spot) > plain, "the chapel lifts land value more")
	_check(dev.hubs.dev_problem(dev, cmid, "garden") == "" and dev.hubs.dev_problem(dev, cmid, "veterans").contains("residents"),
		"the garden follows the chapel; the veterans memorial waits for a bigger town")
	var round := CitySim.new()
	round.from_dict(JSON.parse_string(JSON.stringify(dev.to_dict())))
	_check(round.hubs.hubs[cmid].dev == ["chapel"], "save keeps a hub's developments")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	elif not what.begins_with("no lot left") and not what.begins_with("it never grows") \
			and not what.begins_with("no piece") and not what.begins_with("each truck"):
		print("PASS " + what)
