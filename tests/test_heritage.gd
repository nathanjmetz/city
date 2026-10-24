extends SceneTree
## Run: godot --headless -s tests/test_heritage.gd
## Earned nicknames, old buildings and historic districts,
## historic markers, leaders' asks on the bell, and the growth timelapse.

var _failed := false
const MONTH := 24 * CitySim.TICKS_PER_HOUR
const YEAR := 12 * MONTH


func _init() -> void:
	var sim := _town(11)
	_check(sim.buildings.size() >= 20, "the test town grew (%d buildings)" % sim.buildings.size())

	# --- Firsts get markers, and a timelapse record starts.
	_month(sim)
	var keys := sim.markers.markers.map(func(m): return m.key)
	for k in ["founded", "first_home", "first_store", "first_factory"]:
		_check(k in keys, "a marker for %s" % k)
	for m in sim.markers.markers:
		_check(str(m.title) != "" and str(m.text).find("{") == -1 or str(m.title) == "{town}",
			"marker words are filled in (%s: %s)" % [m.title, m.text])
	_check(HistoricMarkers.filled("{town}", "Lyons") == "Lyons", "the founding marker carries the town's name")
	var n_markers := sim.markers.markers.size()
	_month(sim)
	_check(sim.markers.markers.size() == n_markers, "each first is marked once")
	_check(sim.timelapse.at(Timelapse.month_of(sim.tick_count)).buildings.size() >= 20, "the timelapse has the buildings")
	_check(not sim.timelapse.at(Timelapse.month_of(sim.tick_count)).roads.is_empty(), "and the roads")

	# --- Culture follows the jobs, and a nickname is earned.
	sim.stats.population = 600
	for i in 3:
		_month(sim)
	_check(sim.culture.identity != "", "the town is known for something (%s)" % sim.culture.identity)
	_check(not sim.nicknames.current.is_empty(), "the town earned a nickname: %s" % sim.nicknames.current.get("text", "none"))
	var first_nick := str(sim.nicknames.current.get("text", ""))
	# The town changes under it (shops become offices, and the player keeps
	# saying yes to the bank): the nickname changes, and the old one is
	# remembered.
	var n := 0
	for k in sim.buildings.keys():
		var t := BuildingTypes.type_of(sim.buildings[k])
		if t == "factory" or (t in ["shop", "mixed_use"] and n % 4 != 3):
			sim.redevelop(k, "office", 0)
		n += 1
	for i in 40:
		sim.culture.nudge("office", Balance.CULTURE_YES_LEAN)
		_month(sim)
	_check(str(sim.nicknames.current.get("text", "")) != first_nick, "identity shifted: now %s" % sim.nicknames.current.get("text", ""))
	_check(not sim.nicknames.past.is_empty() and str(sim.nicknames.past[0].text) == first_nick, "and it remembers it was the %s" % first_nick)
	print("  nicknames: ", sim.nicknames.past.map(func(p): return p.text), " then ", sim.nicknames.current.get("text", ""))
	_check(sim.culture.pull("office") > 0.0, "an office town pulls offices forward (%.2f)" % sim.culture.pull("office"))

	# --- Old buildings: charm grows with age and a district becomes eligible.
	var key0: String = _any_shop(sim)
	_check(sim.heritage.charm.get(key0, 0.0) == 0.0, "a new building has no charm yet")
	_check(sim.land_factor(key0) == sim.hubs.lot_factor(sim, key0) * sim.pollution.lot_factor(sim, key0),
		"and no land value lift")
	sim.tick_count += Balance.HERITAGE_AGE_YEARS * YEAR
	_month(sim)
	_check(float(sim.heritage.charm.get(key0, 0.0)) > 0.0, "ten years on it has charm (%.2f)" % sim.heritage.charm.get(key0, 0.0))
	_check(sim.heritage.land(key0) > 1.0, "which lifts its land value (%.3f)" % sim.heritage.land(key0))
	_check(not sim.heritage.districts.is_empty(), "the old town is an eligible historic district")
	var did: int = sim.heritage.districts.keys()[0]
	var d: Dictionary = sim.heritage.districts[did]
	_check(str(d.name).ends_with("Historic District"), "named for its street: %s" % d.name)

	# The historical society asks on the bell, never as a pop-up.
	var req := int(d.req)
	_check(req > 0, "the historical society asks to protect it")
	if req > 0:
		var r: Dictionary = sim.permits.requests[req]
		_check(r.ask == "district" and str(r.yes) != "" and str(r.no) != "", "the card says what a yes and a no bring")
		_check(not sim.apply({"type": "permit", "id": req, "answer": "edit", "route": r.route}), "an ask can't be redrawn")
		sim.apply({"type": "permit", "id": req, "answer": "approve"})
		_hour(sim)
	_check(d.state == "protected", "approved, the district is protected")
	var inside := _member(sim, did)
	_check(sim.heritage.protected(inside), "its buildings are protected")
	_check(not sim.heritage.allow(sim, inside, "mixed_use", 0), "a protected building can't be rebuilt")
	_check(sim.heritage.land(inside) >= 1.0 + Balance.HERITAGE_DISTRICT_LIFT * 0.5, "land inside is worth more")
	_check(sim.heritage.monthly_cost() == Balance.HERITAGE_COMMISSION_MONTHLY, "the commission costs the town")
	_check(sim.heritage.tourism_demand() > 0.0, "visitors come to walk it")
	_check(sim.markers.seen.has("district:%d" % did), "a district plaque goes up")
	_check(not sim.heritage.rows(sim, inside).is_empty(), "the building panel tells its story")
	var acts := sim.heritage.actions(sim, inside)
	_check(acts.size() == 1 and acts[0].cmd.protect == false, "and offers to lift protection")

	# Lifting it from the panel is the player's word too.
	_check(sim.apply(acts[0].cmd), "protection can be lifted")
	_check(not sim.heritage.protected(inside), "then owners may rebuild again")

	# --- Demolition delay: a charming building outside a district asks first.
	sim.tick_count += 10 * YEAR
	_month(sim)
	var old_key := ""
	for k in sim.heritage.charm:
		if sim.heritage.charm[k] >= Balance.HERITAGE_DELAY_CHARM and not sim.heritage.protected(k) \
				and int(sim.buildings[k].zone) == ZoneMap.Zone.COMMERCIAL and BuildingTypes.type_of(sim.buildings[k]) != "office":
			old_key = k
			break
	_check(old_key != "", "a charming old shop stands unprotected")
	if old_key != "":
		_clear_bell(sim)
		var money: int = sim.economy.money
		_check(not sim.heritage.allow(sim, old_key, "office", 0), "its owner can't just tear it down")
		var ask := _ask_for(sim, "demolish")
		_check(ask > 0, "the owner asks on the bell")
		if ask > 0:
			sim.apply({"type": "permit", "id": ask, "answer": "deny"})
			_hour(sim)
			_check(sim.heritage.easements.has(old_key), "a no buys a preservation easement")
			_check(sim.economy.money < money, "which the town pays for")
			_check(sim.heritage.protected(old_key), "and it stays for good")
	# Another one, approved this time: it comes down for the new building.
	var other := ""
	for k in sim.heritage.charm:
		if k != old_key and sim.heritage.charm[k] >= Balance.HERITAGE_DELAY_CHARM and not sim.heritage.protected(k) \
				and BuildingTypes.type_of(sim.buildings[k]) == "shop":
			other = k
			break
	if other != "":
		_clear_bell(sim)
		sim.heritage.allow(sim, other, "office", 0)
		var ask := _ask_for(sim, "demolish")
		_check(ask > 0, "a second owner asks")
		sim.apply({"type": "permit", "id": ask, "answer": "approve"})
		_hour(sim)
		_check(BuildingTypes.type_of(sim.buildings[other]) == "office", "a yes and it's rebuilt")
		_check(Heritage.age_years(sim, sim.buildings[other]) < 0.1, "a new building's age starts again")

	# --- Leaders' asks: a fall festival on Main Street.
	_clear_bell(sim)
	while not Seasons.month(sim.tick_count) in Balance.ASK_FESTIVAL_MONTHS:
		sim.tick_count += MONTH
	var mixed := 0
	for k in sim.buildings:
		if BuildingTypes.type_of(sim.buildings[k]) == "mixed_use":
			mixed += 1
	if mixed < 3:
		for k in sim.buildings.keys():
			if int(sim.buildings[k].zone) == ZoneMap.Zone.COMMERCIAL and not sim.heritage.protected(k):
				sim.redevelop(k, "mixed_use", 0)
	var plan := sim.leaders._plan_festival(sim)
	_check(not plan.is_empty(), "Main Street merchants can ask for a festival")
	if not plan.is_empty():
		sim.leaders._file(sim, plan)
		var ask := _ask_for(sim, "festival")
		_check(ask > 0, "the festival ask is on the bell")
		var money: int = sim.economy.money
		var trade := float(sim.culture.shares.get("trade", 0.0))
		sim.apply({"type": "permit", "id": ask, "answer": "approve"})
		_hour(sim)
		_check(sim.economy.money == money - Balance.ASK_FESTIVAL_COST, "the town pays for it")
		_check(LeaderAsks.festival_demand(sim) > 0.0, "shops get a month's extra business")
		_check(float(sim.culture.shares.get("trade", 0.0)) > trade, "and the town leans toward its Main Street")

	# --- A farm asks to pave its gravel road.
	_clear_bell(sim)
	sim.apply({"type": "build_road", "start": [-100, 400], "ctrl": [0, 400], "end": [100, 400], "road": RoadStyle.Type.GRAVEL})
	var gseg := -1
	for seg in sim.network.segments:
		if sim.network.segments[seg].type == RoadStyle.Type.GRAVEL:
			gseg = seg
	var fid := sim.farms.add_farm(Vector3(0, 0, 500), Vector3(0, 0, -1), "corn", [Vector3(0, 0, 480), Vector3(0, 0, 404)])
	sim.farms.farms[fid].cells.append(Vector2i(1, 1))
	plan = sim.leaders._plan_pave(sim)
	_check(not plan.is_empty() and int(plan.do.seg) == gseg, "a farm on a gravel road asks to pave it")
	if not plan.is_empty():
		sim.leaders._file(sim, plan)
		var ask := _ask_for(sim, "pave")
		sim.apply({"type": "permit", "id": ask, "answer": "approve"})
		_hour(sim)
		_check(sim.network.segments[gseg].type == RoadStyle.Type.COUNTY, "approved, it's a paved county road")

	# --- A logging company asks for a tax break on a wood chip mill at its own
	# yard (Brawn: "somebody asked to build a chip plant ... I clicked yes and
	# nothing happened"). Yes builds it and the bell says so.
	_clear_bell(sim)
	sim.economy.money = 10_000_000
	var forest := _best(Industry.KINDS["forest"].resource)
	sim.apply({"type": "build_road", "start": [forest.x - 1800, forest.z], "ctrl": [forest.x, forest.z],
		"end": [forest.x + 1800, forest.z]})
	var site := -1
	for dx in [0, 200, -200, 400, -400]:
		if sim.apply({"type": "place_industry", "kind": "forest", "pos": [forest.x + dx, forest.z + 30], "dir": [0, -1]}):
			site = sim.industry.sites.keys()[-1]
			break
	_check(site >= 0, "a logging company opens in the woods")
	if site >= 0:
		var s: Dictionary = sim.industry.sites[site]
		s.built = ["log_yard", "replanting"]
		s.leader = {"edu": 0.5, "caution": 1.0, "ambition": 0.0}
		for cand in sim.industry._candidates(s):
			if s.pads.size() < 12 and sim.industry.pad_profit(s, cand) > 0.0:
				s.pads.append(cand)
		plan = sim.leaders._plan_abatement(sim)
		_check(not plan.is_empty() and str(plan.do.node) == "chip_plant",
			"with a log yard paid off, it asks for a chip mill (%s)" % str(plan.get("do", {})))
		if not plan.is_empty():
			_check(str(plan.title).contains("wood chip mill") and str(plan.why).contains("own yard")
				and str(plan.why).contains("no new land"), "the card says it's a wood chip mill at its own yard: %s" % plan.why)
			sim.leaders._file(sim, plan)
			var ask := _ask_for(sim, "abatement")
			_check(ask > 0, "the abatement ask is on the bell")
			sim.apply({"type": "permit", "id": ask, "answer": "approve"})
			_hour(sim)
			_check("chip_plant" in s.built, "approved, the chip mill is built")
			_check(str(s.why).contains("wood chip mill"), "the company says what it built (%s)" % s.why)
			_check(sim.permits.requests[ask].note == "Done.", "and the bell marks the ask done")
			_check(sim.permits.state_of(ask) == Permits.State.DONE, "the request is closed")

	# --- Saved and loaded, the story is the same.
	_month(sim)
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.nicknames.current == sim.nicknames.current, "the nickname is saved")
	_check(copy.nicknames.past.size() == sim.nicknames.past.size(), "and the old ones")
	_check(copy.markers.markers.size() == sim.markers.markers.size(), "markers are saved")
	_check(copy.heritage.districts.size() == sim.heritage.districts.size(), "districts are saved")
	_check(copy.heritage.easements == sim.heritage.easements, "easements are saved")
	_check(copy.heritage.land(old_key) == sim.heritage.land(old_key), "charm is worked out again after loading")
	var before: int = copy.timelapse.buildings.size()
	copy.town_month()
	_check(copy.timelapse.buildings.size() == before, "a loaded timelapse doesn't record standing buildings twice")
	var tl_roads: int = copy.timelapse.roads.size()
	copy.town_month()
	_check(copy.timelapse.roads.size() == tl_roads, "or roads")
	# The timelapse plays back from the start.
	_check(sim.timelapse.at(0).buildings.size() <= sim.timelapse.at(sim.timelapse.months - 1).buildings.size(),
		"the town grows across the timelapse")

	# --- Every copy of the city agrees (multiplayer).
	var a := _town(5)
	var b := _town(5)
	for i in 30:
		a.stats.population = 600
		b.stats.population = 600
		_month(a)
		_month(b)
	_check(JSON.stringify(a.nicknames.to_dict()) == JSON.stringify(b.nicknames.to_dict()), "two copies share a nickname")
	_check(JSON.stringify(a.markers.to_dict()) == JSON.stringify(b.markers.to_dict()), "and markers")

	# --- It costs next to nothing: a town month in the test town.
	var t0 := Time.get_ticks_usec()
	for i in 10:
		sim.town_month()
	print("  a town month takes %.2f ms" % ((Time.get_ticks_usec() - t0) / 10000.0))
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Homes, shops and factories along two streets.
func _town(seed: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	_clear_county(sim, Vector2.ZERO, 300.0)
	sim.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0]})
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, -75], "end": [0, 0]})
	for x in range(-150, 151, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12,
			"zone": ZoneMap.Zone.COMMERCIAL if x < 60 else ZoneMap.Zone.INDUSTRIAL})
	for i in 600:
		sim.tick()
	var empty: Array = sim.empty_zoned_lots()
	empty.sort()
	for key in empty:
		var z: int = sim.zones.zone_at(sim.lots[key].zone_pt)
		if z != ZoneMap.Zone.RESIDENTIAL:
			sim.found_business(key, z)
	for i in 1200:
		sim.tick()
	return sim


func _best(res: int) -> Vector3:
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-3000, 3001, 150):
		for z in range(-3000, 3001, 150):
			var v := Resources.at(res, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	return best


func _month(sim: CitySim) -> void:
	sim.tick_count += MONTH
	sim.permits.tick(sim)
	sim.culture.update(sim, sim.tick_count / MONTH)
	sim.town_month()


func _hour(sim: CitySim) -> void:
	sim.heritage.carry_out(sim)
	sim.leaders.carry_out(sim)


func _any_shop(sim: CitySim) -> String:
	var keys := sim.buildings.keys()
	keys.sort()
	for k in keys:
		if int(sim.buildings[k].zone) == ZoneMap.Zone.COMMERCIAL:
			return k
	return keys[0]


func _member(sim: CitySim, did: int) -> String:
	var keys := sim.heritage.district_of.keys()
	keys.sort()
	for k in keys:
		if sim.heritage.district_of[k] == did:
			return k
	return ""


func _ask_for(sim: CitySim, kind: String) -> int:
	for r in sim.permits.listed(Permits.State.OPEN):
		if str(r.get("ask", "")) == kind:
			return int(r.id)
	return -1


## Withdraws everything open so the next ask has room on the bell.
func _clear_bell(sim: CitySim) -> void:
	for r in sim.permits.listed(Permits.State.OPEN):
		sim.permits.withdraw(int(r.id))
	sim.permits.wait_until.clear()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)


## Bulldozes the county roads around `at` (town coordinates), for a test
## town laid out across the section lines with no county road in mind.
static func _clear_county(sim: CitySim, at: Vector2, reach: float) -> void:
	var o := sim.terrain_offset
	for x in range(int(at.x - reach), int(at.x + reach) + 1, 100):
		for z in range(int(at.y - reach), int(at.y + reach) + 1, 100):
			for mile in CountyGrid.miles_at(x + o.x, z + o.y, 60.0):
				sim.apply({"type": "remove_county", "key": mile.key})
