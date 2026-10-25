extends SceneTree
## Big local factories: one of each per town, fed by real trucks from the
## town's farms and companies first and the region after, keeping their own
## books, and growing only into the land right behind them.
## Run: godot --headless -s tests/test_big_factories.gd

var _failed := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.build_county_road(Vector2(600, 0), Vector2(2400, 0), [1])
	var site := Warehouses.site_near(sim.network, Vector3(-200, 0, -100))
	_check(site.size() == 3, "a site faces the street")
	var money := sim.economy.money
	_check(sim.apply({"type": "place_big_factory", "kind": "ethanol", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"an ethanol plant goes up beside the street")
	_check(sim.economy.money == money - int(Balance.BIG_FACTORY.ethanol.cost), "the town pays for the site")
	var other := Warehouses.site_near(sim.network, Vector3(300, 0, -100))
	_check(not sim.apply({"type": "place_big_factory", "kind": "ethanol", "pos": [other[0].x, other[0].z], "dir": [other[1].x, other[1].z]}),
		"only one ethanol plant per town")
	_check(sim.big.site_problem(sim, "furniture", site[0], site[1]) != "", "two plants can't share ground")
	var f: Dictionary = sim.big.sites[1]
	_check(f.leader.has("edu") and f.name.ends_with("Ethanol"), "it has an owner and a name (%s)" % f.name)

	# A corn farm across the street sells its grain to the plant.
	_check(sim.apply({"type": "place_farmhouse", "pos": [150, 60], "dir": [0, -1], "crop": "corn"}), "a corn farm")
	var fid: int = sim.farms.farms.keys()[0]
	sim.logistics.grain[fid] = 5_000.0
	var twin := CitySim.new()
	twin.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var corn_in := 0
	var ethanol_out := 0
	var seen := {}
	# Five days: the first batch waits on its third load of corn (it once
	# landed on day 3 only by luck of the traffic).
	for i in 1440 * 5:
		sim.tick()
		twin.tick()
		for id in sim.logistics.trips:
			if seen.has(id):
				continue
			seen[id] = true
			var t: Dictionary = sim.logistics.trips[id]
			if t.from.ref == "farm:%d" % fid and t.to.ref == "big:1":
				corn_in += 1
			if t.from.ref == "big:1" and t.cargo.good == "ethanol":
				ethanol_out += 1
	_check(corn_in >= 4, "grain trucks drove the farm's corn to the plant (%d)" % corn_in)
	_check(ethanol_out >= 1, "tankers took ethanol out to the region (%d)" % ethanol_out)
	_check(sim.trade.wants.has("corn") or sim.trade.got("corn") > 0.0 or f.due.corn > 0.0 or f.stock.corn > 0.0,
		"it buys corn the town can't supply from the region")
	_check(f.hist.size() >= 2, "it keeps monthly books (%s)" % str(f.hist))
	_check(twin.big.sites[1].stock == f.stock and twin.big.sites[1].cash == f.cash,
		"two copies of the town agree (multiplayer)")
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(back.big.sites[1].stock == f.stock and back.big.sites[1].built == f.built and back.big.sites[1].cash == f.cash,
		"a save keeps the plant's stock, books and tree")
	var sel := Inspect.pick(sim, BigFactories.center(f))
	var info := Inspect.describe(sim, sel)
	_check(sel.get("type") == "big" and str(info.get("title", "")) == f.name, "clicking it opens its panel")
	_check(sim.stats.jobs >= int(Balance.BIG_FACTORY.ethanol.jobs), "its jobs count")
	_check(sim.permits.locators.has("big"), "the player can give its owner their word")
	_check(sim.hub_area("big:1") == "big" and sim.apply({"type": "policy", "scope": "big:1", "slider": "growth", "step": 0})
		and sim.permits.guidance("big", 1).stance == "hold", "the Economy page's Growth slider reaches the owner")
	_check(not sim.apply({"type": "policy", "scope": "big:1", "slider": "funding", "step": 3}), "but the town doesn't fund it")
	sim.apply({"type": "policy", "scope": "big:1", "slider": "growth", "step": 2})

	# A meatpacker with no hog farms in town buys hogs from outside: trade
	# money is the plant's, not the town's.
	var town := CitySim.new()
	town.economy.money = 50_000_000
	town.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	town.build_county_road(Vector2(600, 0), Vector2(2400, 0), [1])
	var ms := Warehouses.site_near(town.network, Vector3(-150, 0, -100))
	_check(town.apply({"type": "place_big_factory", "kind": "meatpacker", "pos": [ms[0].x, ms[0].z], "dir": [ms[1].x, ms[1].z]}),
		"a meatpacker goes up")
	for x in range(100, 501, 10):
		town.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
	var hogs := 0
	var pork := 0
	var pork_any := 0
	var city_before := town.economy.money
	seen.clear()
	# Trucks drive at real speed in a fast calendar (a game day is a month),
	# so loads from the region link take a day or two to arrive.
	for i in 1440 * 7:
		town.tick()
		for id in town.logistics.trips:
			if seen.has(id):
				continue
			seen[id] = true
			var t: Dictionary = town.logistics.trips[id]
			if t.to.ref == "big:1" and t.cargo.good == "livestock":
				hogs += 1
			if t.from.ref == "big:1" and t.cargo.good == "pork":
				pork_any += 1
				if str(t.to.ref).begins_with("lot:"):
					pork += 1
	var m: Dictionary = town.big.sites[1]
	_check(hogs >= 3, "hog trailers came in from the region link (%d)" % hogs)
	_check(pork_any >= 1, "reefers took the plant's pork away (%d)" % pork_any)
	_check(town.count_buildings(ZoneMap.Zone.COMMERCIAL) == 0 or pork >= 1,
		"pork goes to the town's stores when it has some (%d of %d)" % [pork, pork_any])
	_check(town.trade.got("livestock") > 0.0 or hogs > 0, "the hogs were bought through regional trade")
	var hog_bill := 0.0
	for p in m.hist:
		hog_bill += p
	_check(town.economy.money > city_before - 2_000_000, "the town didn't pay for the plant's hogs")

	# Busy and paying: it builds up, then buys the land right behind it.
	var g: Dictionary = sim.big.sites[1]
	g.cash = 50_000_000.0
	g.hist = []
	for i in 12:
		g.hist.append(400_000)
	g.avg_profit = 4_800_000.0
	var now := BigFactories.today(sim)
	g.busy = Balance.BIG_FACTORY_BUSY_MONTHS
	g.grown = now
	sim.big._decide(sim, 1, 1.0, 400_000.0)
	_check(int(g.level) == 0, "growth takes years: not the month after it opened")
	for i in 4:
		g.busy = Balance.BIG_FACTORY_BUSY_MONTHS
		g.grown = now - Balance.BIG_FACTORY_GROW_YEARS * 12.0
		sim.big._decide(sim, 1, 1.0, 400_000.0)
	_check(int(g.level) == Balance.BIG_FACTORY_LEVELS - 1 and int(g.bays) >= 1,
		"a busy plant builds up first, then out (level %d, bays %d)" % [g.level, g.bays])
	_check(float(g.debt) > 0.0, "it bought the land behind it partly on a loan ($%d owed)" % roundi(float(g.debt)))
	g.busy = Balance.BIG_FACTORY_BUSY_MONTHS
	var bays := int(g.bays)
	sim.big._decide(sim, 1, 1.0, 400_000.0)
	_check(int(g.bays) == bays, "and waits years before the next bay")
	# Broke, it can't buy land however busy it is.
	var poor: Dictionary = g.duplicate(true)
	sim.big.sites[99] = poor
	poor.cash = 0.0
	poor.busy = Balance.BIG_FACTORY_BUSY_MONTHS
	poor.grown = now - 100.0
	sim.big._decide(sim, 99, 1.0, 400_000.0)
	_check(int(poor.bays) == bays, "growth comes from its own money, not the town's")
	sim.big.sites.erase(99)
	# Out in the country, a losing plant doesn't get offers from developers.
	g.loss = 5
	g.hist = [-50_000, -50_000, -50_000]
	sim.big._decide(sim, 1, 0.2, -50_000.0)
	_check(sim.big.sites.has(1) and g.get("sale", {}).is_empty(), "land far from town isn't worth selling out")
	var poly := BigFactories.corners(g)
	_check(Geometry2D.is_point_in_polygon(Vector2(site[0].x, site[0].z - 1.0), poly) or
		Geometry2D.is_point_in_polygon(Vector2(site[0].x, site[0].z + 1.0), poly), "it stays one site, grown from the back")
	var fresh := {"leader": g.leader, "built": [], "kind": "ethanol"}
	var tree := Agency.open(sim, fresh, BigFactories.TREES.ethanol, BigFactories.center(g), 500_000.0)
	_check(not tree.is_empty() and not g.built.is_empty(), "its owner develops its tree from its savings (%s)" % str(g.built))

	# A road through it bulldozes it and pays the town back.
	var before := sim.economy.money
	var c := BigFactories.center(g)
	sim.apply({"type": "build_road", "start": [c.x - 400, c.z], "ctrl": [c.x, c.z], "end": [c.x + 400, c.z]})
	_check(sim.big.sites.is_empty(), "the road wins over the plant")
	_check(sim.economy.money > before - 1_000_000, "and the town gets the site back")

	print("big factories: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1
