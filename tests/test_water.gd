extends SceneTree
## Run: godot --headless -s tests/test_water.gd
## The water and sewer utility hub: its manager lays mains toward zoned lots,
## climbs the development tree, and lets problems pile up when starved.

var _failed := false


func _init() -> void:
	var sim := _town()
	var w := sim.services.water
	_check(w.utilities.size() == 1, "placing the utility hires a manager")
	var id: int = w.utilities.keys()[0]
	var u: Dictionary = w.utilities[id]
	_check(str(u.name).contains(" ") and w.has_work(id, "well"), "the manager has a name and the first well (%s)" % u.name)
	_check(w.live[id].mains.size() >= 1, "a main runs under the utility's own street")
	# Only lots on its mains get water; the rest wait for pipe.
	var piped := 0
	var dry := 0
	for key in sim.lots:
		var s: Dictionary = sim.services.served[key]
		if s.get("water_by", -1) == id:
			piped += 1
		elif sim.zones.zone_at(sim.lots[key].zone_pt) != ZoneMap.Zone.NONE and not s.get("water", false):
			dry += 1
	_check(piped > 0 and dry > 0, "lots on its main have water, others wait (%d piped, %d dry)" % [piped, dry])
	for i in 20000:
		sim.tick()
	var l: Dictionary = w.live[id]
	_check(l.mains.size() > 3, "the manager lays mains along more streets (%d segments)" % l.mains.size())
	_check(sim.count_buildings(ZoneMap.Zone.RESIDENTIAL) > 40, "homes grow on piped streets (%d)" % sim.count_buildings(ZoneMap.Zone.RESIDENTIAL))
	_check(w.has_work(id, "lagoon") or w.has_work(id, "plant"), "a growing town gets a sewage lagoon")
	_check(l.sewers.size() > 0, "sewers follow the mains")
	_check(int(l.fees) > 0 and sim.economy.budget.fees == 0, "the utility collects the water bills, not the city ($%d)" % l.fees)
	_check(sim.economy.budget.services >= int(u.subsidy), "the city pays the subsidy")
	var d := Inspect.describe(sim, Inspect.pick(sim, sim.services.buildings[id].pos))
	_check(d.kind == "Utility hub" and d.has("tree") and d.rows.any(func(r): return r[0] == "City subsidy"),
		"its panel shows the tree and the subsidy")
	# The subsidy is the utility's Funding slider on the Economy page.
	_check(sim.apply({"type": "policy", "scope": "water:%d" % id, "slider": "funding", "step": 3})
		and int(u.subsidy) == Balance.POLICY_WATER_SUBSIDY[3], "Well funded raises the subsidy ($%d)" % int(u.subsidy))
	_check(sim.apply({"type": "set_water_subsidy", "id": id, "amount": 24_000}) and int(u.subsidy) == 24_000
		and sim.policies.step("funding", "water", "water:%d" % id) == 4, "an exact subsidy shows as the nearest step")
	# Every yard piece touches the yard (no second sites).
	var cells := {Vector2i.ZERO: true}
	for wk in u.works:
		if wk[1].x > -99:
			cells[wk[1]] = true
	var joined := true
	for c in cells:
		if c != Vector2i.ZERO and not (cells.has(c + Vector2i(1, 0)) or cells.has(c - Vector2i(1, 0)) or cells.has(c - Vector2i(0, 1))):
			joined = false
	_check(joined, "the yard grows only into land next to it (%s)" % str(cells.keys()))
	# Save and load, then two copies stay in step (multiplayer).
	var copy := CitySim.new()
	copy.require_utilities = true
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.services.water.utilities.size() == 1 and copy.services.water.live[id].mains.size() == l.mains.size(),
		"a save keeps the manager and the pipes")
	for i in 1500:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.to_dict().services) == JSON.stringify(sim.to_dict().services)
		and JSON.stringify(copy.to_dict().buildings) == JSON.stringify(sim.to_dict().buildings), "copies of the utility stay in sync")

	# Educated and funded: a clean, modern plant. Starved and unschooled:
	# boil orders and a smelly lagoon.
	var good := _town()
	var gid: int = good.services.water.utilities.keys()[0]
	good.services.water.utilities[gid].leader.edu = 0.95
	good.apply({"type": "set_water_subsidy", "id": gid, "amount": 40_000})
	var bad := _town()
	var bid: int = bad.services.water.utilities.keys()[0]
	bad.apply({"type": "set_water_subsidy", "id": bid, "amount": 0})
	bad.services.water.utilities[bid].cash = 0.0
	for i in 20000:
		good.tick()
		good.services.water.utilities[gid].leader.edu = 0.95  # as if the town had great schools
		bad.tick()
		bad.services.water.utilities[bid].leader.edu = 0.0
	var gu: Dictionary = good.services.water.utilities[gid]
	var bu: Dictionary = bad.services.water.utilities[bid]
	_check(gu.cond > 0.85 and not gu.boil, "a funded, educated manager keeps things in repair (%.2f)" % gu.cond)
	_check(good.services.water.count_work(gid, "well") + int(good.services.water.has_work(gid, "meters")) > 1,
		"the educated manager climbs the tree (%s)" % str(gu.works))
	_check(bu.cond < gu.cond - 0.2, "a starved manager lets condition slide (%.2f vs %.2f)" % [bu.cond, gu.cond])
	_check(not bad.services.water.has_work(bid, "meters"), "an unschooled manager can't take on smart meters")
	var locked := ""
	for entry in bad.services.water.options(bad, bid):
		if entry[0] == "meters":
			locked = entry[1]
	_check(locked.contains("schooled"), "the panel says why a step is locked (%s)" % locked)
	# A smelly plant lowers land value right next to it.
	bu.odor = 0.8
	var plant := Vector3.INF
	for wk in bu.works:
		if wk[0] in ["lagoon", "plant"]:
			plant = WaterUtility.cell_center(bad.services.buildings[bid], wk[1])
	if plant == Vector3.INF:
		bu.works.append(["lagoon", Vector2i(0, 1)])
		plant = WaterUtility.cell_center(bad.services.buildings[bid], Vector2i(0, 1))
	_check(bad.services.water.land_value_factor(bad.services.buildings, plant) < 0.9
		and bad.services.water.land_value_factor(bad.services.buildings, plant + Vector3(2000, 0, 0)) == 1.0,
		"the smell lowers land value nearby only")
	bu.boil = true
	bad.update_stats()
	_check(bad.services.water.boil_share(bad) > 0.0, "a boil-water notice reaches the homes")

	# Three quarters full and broke: the superintendent asks the town to pay
	# for the next well. Yes builds it now.
	var ask := _town()
	var aid: int = ask.services.water.utilities.keys()[0]
	var au: Dictionary = ask.services.water.utilities[aid]
	for i in 3000:
		ask.tick()
	au.cash = -1_000_000_000.0
	ask.services.water.live[aid].load = ask.services.water.water_capacity(aid) / 2
	_check(ask.leaders._plan_water(ask).is_empty(), "no ask while the system has room")
	ask.services.water.live[aid].load = ask.services.water.water_capacity(aid)
	var plan: Dictionary = ask.leaders._plan_water(ask)
	_check(not plan.is_empty() and str(plan.title).begins_with("Pay for a new"), "a full system with no money asks the town (%s)" % plan.get("title", ""))
	var wells := ask.services.water.count_work(aid, "well") + ask.services.water.count_work(aid, "tower") + ask.services.water.count_work(aid, "intake")
	ask.leaders.month(ask)
	var rid := -1
	for r in ask.permits.requests:
		if str(ask.permits.requests[r].get("ask", "")) == "water":
			rid = r
	_check(rid != -1, "the ask comes on the bell ahead of the others")
	var before := int(ask.economy.money)
	ask.apply({"type": "permit", "id": rid, "answer": "approve"})
	ask.leaders.carry_out(ask)
	var after := ask.services.water.count_work(aid, "well") + ask.services.water.count_work(aid, "tower") + ask.services.water.count_work(aid, "intake")
	_check(after == wells + 1 and int(ask.economy.money) < before, "a yes builds it and the town pays ($%d)" % (before - int(ask.economy.money)))
	ask.services.water.live[aid].load = ask.services.water.water_capacity(aid)
	_check(not ask.leaders._cooled(ask, "water"), "it doesn't ask again right away")
	au.cash = 1_000_000_000.0
	_check(ask.leaders._plan_water(ask).is_empty(), "a utility with the money builds it itself")

	# Removing the utility drops its manager.
	sim.apply({"type": "remove_service", "id": id})
	sim.update_stats()
	_check(w.utilities.is_empty(), "bulldozing the utility ends it")
	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


## A small grid of streets, zoned for homes and some industry, with power and
## a water utility at one corner.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.charter.reached["town"] = 0  # sewers are a town's (IC 36-9-23)
	sim.require_utilities = true
	sim.economy.money = 50_000_000
	for z in [0, 200, 400]:
		sim.apply({"type": "build_road", "start": [-400, z], "ctrl": [0, z], "end": [400, z]})
	for x in [-400, 0, 400]:
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 200], "end": [x, 400]})
	for x in range(-380, 381, 40):
		for z in [20, 180, 220, 380]:
			sim.apply({"type": "paint_zone", "center": [x, z], "radius": 25, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, -20], "radius": 25, "zone": ZoneMap.Zone.INDUSTRIAL})
	var feed := Services.site_near(sim.network, Services.Kind.SUBSTATION, Vector3(150, 0, 205))
	sim.apply({"type": "place_service", "kind": Services.Kind.SUBSTATION, "pos": [feed[0].x, feed[0].z], "dir": [feed[1].x, feed[1].z]})
	var site := Services.site_near(sim.network, Services.Kind.WATER_UTILITY, Vector3(300, 0, -40))
	sim.apply({"type": "place_service", "kind": Services.Kind.WATER_UTILITY, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	sim.update_stats()
	return sim


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
