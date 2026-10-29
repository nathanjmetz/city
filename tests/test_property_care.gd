extends SceneTree
## Run: godot --headless -s tests/test_property_care.gd
## Every property responds to what the town gives it (PropertyCare):
## served well it improves, denied it declines, families leave and an unsafe
## vacant house comes down; the art shows it at no draw-call cost; and
## developers ask to build denser on the permit bell (Redevelopment).

var _failed := false
const MONTH := 24 * CitySim.TICKS_PER_HOUR


func _init() -> void:
	var sim := _town(21, RoadStyle.Type.STREET, 150)
	_check(sim.buildings.size() >= 20, "the test town grew (%d buildings)" % sim.buildings.size())

	# --- Served well, owners keep up and improve over a year or two.
	for i in 18:
		_care_month(sim)
	var tiers := _tiers(sim)
	print("  after 18 good months: ", tiers)
	_check(int(tiers.get(1, 0)) + int(tiers.get(2, 0)) > 0, "some owners improved their place")
	_check(int(tiers.get(-2, 0)) == 0, "nobody is derelict in a well-served town")
	var good_key := ""
	for k in _keys(sim):
		if sim.care.tier_of(k) >= 1:
			good_key = k
			break
	_check(good_key != "" and sim.care.land(good_key) > 1.0, "an improved place lifts its land value")

	# --- Cut the power and water for good: decline, families leave, upkeep stops.
	sim.require_utilities = true
	sim.services.served.clear()
	var homes_before := _residents(sim)
	for i in 12:
		_care_month(sim)
	tiers = _tiers(sim)
	print("  after 12 months without utilities: ", tiers, " residents ", homes_before, " -> ", _residents(sim))
	_check(int(tiers.get(-2, 0)) > sim.buildings.size() / 2, "most properties went derelict")
	_check(_residents(sim) < homes_before, "families moved out")
	var bad_key := ""
	for k in _keys(sim):
		if sim.care.tier_of(k) == -2:
			bad_key = k
			break
	_check(not sim.care.livable(bad_key), "nobody moves into a derelict building")
	_check(sim.care.land(bad_key) < 1.0, "and its land is worth less")
	_check(not BuildingTypes.ready(sim, bad_key), "a run-down owner doesn't build on")
	_check(str(sim.care.lacking.get(bad_key, "")) in ["Power", "Water"], "the inspector says what it needs most (%s)" % sim.care.lacking.get(bad_key, ""))
	var rows := sim.care.rows(sim, bad_key)
	_check(str(rows[0][1]).begins_with("Derelict"), "the inspector shows it: %s" % rows[0][1])

	# --- Services come back: they recover, slowly.
	sim.require_utilities = false
	for i in 8:
		_care_month(sim)
	tiers = _tiers(sim)
	print("  8 months after the utilities came back: ", tiers)
	_check(int(tiers.get(-2, 0)) < sim.buildings.size() / 2, "the neighbourhood recovers")

	# --- Cut off again and left vacant and unsafe long enough, they're ordered down.
	sim.require_utilities = true
	var n_before := sim.buildings.size()
	for i in Balance.CARE_UNSAFE_MONTHS + 14:
		_care_month(sim)
	print("  unsafe buildings ordered down: ", n_before - sim.buildings.size())
	_check(sim.buildings.size() < n_before, "vacant derelict buildings were ordered down")

	# --- A save carries the condition.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.care.cond.size() == sim.care.cond.size() and copy.care.tier == sim.care.tier, "conditions survive a save")

	# --- Art: condition shows, cheaply.
	_art()

	# --- Developers: houses to apartments, on the bell.
	var dev := _town(5, RoadStyle.Type.AVENUE, 300)
	_care_month(dev)
	dev.stats.population = 6000
	dev.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	dev.demand[ZoneMap.Zone.COMMERCIAL] = 1.0
	var faces := Redevelopment._faces(dev)
	for f in faces:
		if Redevelopment._arterial(dev, faces[f][0]):
			print("  arterial face ", f, " zone ", Redevelopment._zone(dev, faces[f][0]), " lots ", faces[f].size(),
				" types ", faces[f].map(func(k): return BuildingTypes.type_of(dev.buildings[k]) if dev.buildings.has(k) else "-"),
				" runs ", Redevelopment._runs(dev, faces[f], ["house"], 2, 10, LotPlanner.MAX_LOT.highway_shop).size())
	var plan := dev.redevelopment._plan_shopping(dev, faces)
	_check(not plan.is_empty(), "a developer finds a row of homes on the avenue for a shopping center")
	if not plan.is_empty():
		print("  shopping ask: ", plan.title, " / ", plan.yes)
		_check(dev.redevelopment.build(dev, {"kind": "shopping", "keys": plan.keys, "type": plan.type,
			"level": plan.level, "was": plan.was}), "a yes rezones and builds it")
		var site: String = plan.keys[0]
		_check(dev.zones.zone_at(dev.lots[site].zone_pt) == ZoneMap.Zone.COMMERCIAL, "the row is commercial now")
		_check(BuildingTypes.type_of(dev.buildings[site]) == "shopping_center", "a %s" % BuildingTypes.name_of(dev.buildings[site]))

	# A town of 6,000 on its own is too small a market for apartments; with
	# a bigger town nearby it isn't.
	dev.market.regional = 0
	_check(dev.redevelopment._plan_apartments(dev, Redevelopment._faces(dev)).is_empty(),
		"a lone town of 6,000 gets no apartment asks")
	dev.market.regional = 8000
	plan = dev.redevelopment._plan_apartments(dev, Redevelopment._faces(dev))
	_check(not plan.is_empty(), "a developer finds houses to buy for apartments")
	if not plan.is_empty():
		print("  apartments ask: ", plan.title, " / ", plan.yes)
		_check(dev.redevelopment._file(dev, plan), "and asks on the bell")
		var id := _ask_id(dev)
		_check(id > 0 and str(dev.permits.requests[id].yes).find("car trips") != -1, "the card counts the traffic and utilities it adds")
		var site: String = plan.keys[0]
		var gone: String = plan.keys[1]
		dev.apply({"type": "permit", "id": id, "answer": "approve"})
		dev.redevelopment.carry_out(dev)
		_check(dev.buildings.has(site) and BuildingTypes.type_of(dev.buildings[site]) == "apartments", "on a yes the apartments go up")
		_check(not dev.lots.has(gone), "on one assembled lot (%.0f m wide)" % dev.lots[site].width)
		_check(not dev.construction.is_done("lot:" + site, dev.tick_count), "with a crew building it")

	# Office parks: at a small city's edge, once the market is big enough.
	var op := _town(5, RoadStyle.Type.AVENUE, 300)
	_care_month(op)
	op.stats.population = 6000
	op.demand[ZoneMap.Zone.COMMERCIAL] = 1.0
	op.market.regional = 0
	_check(op.redevelopment._plan_officepark(op, Redevelopment._faces(op)).is_empty(), "a lone town of 6,000 gets no office park ask")
	op.market.regional = 8000
	plan = op.redevelopment._plan_officepark(op, Redevelopment._faces(op))
	print("  office park ask: ", plan.get("title", "(none)"), " / ", plan.get("yes", ""))
	if not plan.is_empty():
		_check(op.redevelopment.build(op, {"kind": "officepark", "keys": plan.keys, "type": plan.type,
			"level": plan.level, "was": plan.was}), "a yes rezones the run for an office park")
		var site: String = plan.keys[0]
		_check(BuildingTypes.type_of(op.buildings[site]) == "office_park" and int(op.buildings[site].level) == 0,
			"its first building goes up (%s)" % BuildingTypes.name_of(op.buildings[site]))
		var lay := SiteLayout.for_building(ZoneMap.Zone.COMMERCIAL, int(op.buildings[site].seed), op.lots[site], 2, "office_park", 0)
		_check(lay.spots.size() >= 20 and not lay.main_street, "with its own parking lot (%d stalls)" % lay.spots.size())
	else:
		_check(false, "a developer finds land on the avenue for an office park")
	_community()
	print("ALL TESTS PASSED" if not _failed else "SOME TESTS FAILED")
	quit(1 if _failed else 0)


## A neighborhood center buys the houses behind it for a discount store,
## once the market is a town of 20,000's.
func _community() -> void:
	var sim := CitySim.new()
	sim.city_seed = 9
	sim.simulate_traffic = false
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [-300, -80], "ctrl": [0, -80], "end": [300, -80]})
	for x in range(-290, 291, 10):
		for z in [-20, -35, -50, -62]:
			sim.apply({"type": "paint_zone", "center": [x, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 600:
		sim.tick()
	var empty: Array = sim.empty_zoned_lots()
	empty.sort()
	for key in empty:
		var b := {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": hash([9, key]), "built": sim.tick_count, "changed": sim.tick_count, "occ": 2}
		sim.buildings[key] = BuildingTypes.make(sim, key, b, "house", 0)
	for i in 600:
		sim.tick()
	sim.tick_count += 6 * MONTH
	_care_month(sim)
	sim.stats.population = 6000
	sim.demand[ZoneMap.Zone.COMMERCIAL] = 1.0
	sim.market.regional = 6000
	var plan := sim.redevelopment._plan_shopping(sim, Redevelopment._faces(sim))
	if plan.is_empty():
		_check(false, "a row of homes on the avenue for a shopping center")
		return
	sim.redevelopment.build(sim, {"kind": "shopping", "keys": plan.keys, "type": plan.type, "level": 1, "was": plan.was})
	var site: String = plan.keys[0]
	sim.tick_count += 6 * MONTH
	_check(sim.redevelopment._plan_community(sim, {}).is_empty(), "a town of 12,000's market gets no discount store")
	sim.market.regional = 16_000
	plan = sim.redevelopment._plan_community(sim, {})
	print("  community ask: ", plan.get("title", "(none)"), " / ", plan.get("why", ""), " / ", plan.get("yes", ""))
	if plan.is_empty():
		_check(false, "the center finds houses behind it to buy")
		return
	_check(plan.keys[0] == site and plan.keys.size() >= 2, "the center buys %d lots behind it" % (plan.keys.size() - 1))
	_check(sim.redevelopment.build(sim, {"kind": "community", "keys": plan.keys, "type": plan.type,
		"level": plan.level, "was": plan.was}), "a yes rezones and merges them")
	var b: Dictionary = sim.buildings[site]
	var lot: Dictionary = sim.lots[site]
	_check(BuildingTypes.type_of(b) == "shopping_center" and int(b.level) == 2,
		"a %s on %.0f m² (%.0f m deep)" % [BuildingTypes.name_of(b), lot.area, SiteLayout._fit(lot).depth])
	for k in plan.keys.slice(1):
		_check(not sim.lots.has(k), "lot %s is part of the site" % k)
	var lay := SiteLayout.for_building(ZoneMap.Zone.COMMERCIAL, int(b.seed), lot, 1, "shopping_center", 2)
	var aisles := {}
	for sp in lay.spots:
		aisles[sp.get("aisle", lay.aisle_z)] = true
	_check(lay.spots.size() >= 50 and aisles.size() >= 2, "its field has %d stalls off %d aisles" % [lay.spots.size(), aisles.size()])


func _art() -> void:
	var lot := {"width": 22.0, "depth": 45.0}
	var tris := {}
	var t0 := Time.get_ticks_usec()
	for c in [-2, -1, 0, 1, 2]:
		HouseBuilder.owner_care = c
		var built := HouseBuilder.build(4242, 6.0, lot, 1)
		tris[c] = [_tris(built[0]), built[0].get_surface_count(), _tris(built[1]), _pool(built[0])]
	HouseBuilder.owner_care = 0
	print("  house by care (tris, surfaces, ground tris): ", tris, "  %.1f ms each" % ((Time.get_ticks_usec() - t0) / 5000.0))
	# Trees give way to the pool and shed, so count the pool water itself.
	_check(tris[2][3] > 0 and tris[0][3] == 0 and tris[1][3] == 0, "a showpiece has a pool out back (%d pool vertices)" % tris[2][3])
	_check(tris[-2][0] > tris[0][0], "a derelict house has boards over its windows")
	_check(tris[-2][2] > tris[0][2], "and weeds in the yard")
	_check(tris[2][1] <= tris[0][1] and tris[-2][1] <= tris[0][1], "no extra draw calls either way")
	_check(tris[2][0] - tris[0][0] < 400, "add-ons stay low-poly (+%d triangles)" % (tris[2][0] - tris[0][0]))
	HouseBuilder.owner_care = -2
	var shop := DenseBuilder.build_retail(77, 6.0, {"width": 24.0, "depth": 40.0})
	HouseBuilder.owner_care = 0
	var shop0 := DenseBuilder.build_retail(77, 6.0, {"width": 24.0, "depth": 40.0})
	_check(_tris(shop[0]) > _tris(shop0[0]), "a derelict shop is boarded up too")


func _pool(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		for col in m.surface_get_arrays(s)[Mesh.ARRAY_COLOR] as PackedColorArray:
			if col.b > col.r + 0.3 and col.b > 0.55 and col.a > 0.99:
				n += 1
	return n


func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _town(seed: int, road: int, span: int) -> CitySim:
	var sim := CitySim.new()
	sim.city_seed = seed
	sim.simulate_traffic = false
	sim.apply({"type": "build_road", "start": [-span, 0], "ctrl": [0, 0], "end": [span, 0], "road": road})
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, -75], "end": [0, 0]})
	for x in range(-span, span + 1, 10):
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
		else:
			var b := {"zone": z, "seed": hash([seed, key]), "built": sim.tick_count, "changed": sim.tick_count, "occ": 2}
			sim.buildings[key] = BuildingTypes.make(sim, key, b, "house", 0)
	for i in 1200:
		sim.tick()
	sim.tick_count += 6 * MONTH  # everything is finished
	return sim


func _care_month(sim: CitySim) -> void:
	sim.tick_count += MONTH
	sim.care.start_month(sim)
	for i in PropertyCare.SLICES:
		sim.care.slice(sim, i)


func _tiers(sim: CitySim) -> Dictionary:
	var out := {}
	for k in sim.buildings:
		var t := sim.care.tier_of(k)
		out[t] = int(out.get(t, 0)) + 1
	return out


func _residents(sim: CitySim) -> int:
	var n := 0
	for k in sim.buildings:
		n += int(sim.buildings[k].get("occ", 0)) if int(sim.buildings[k].zone) == ZoneMap.Zone.RESIDENTIAL else 0
	return n


func _keys(sim: CitySim) -> Array:
	var keys := sim.buildings.keys()
	keys.sort()
	return keys


func _ask_id(sim: CitySim) -> int:
	for r in sim.permits.listed(Permits.State.OPEN):
		if str(r.get("ask", "")) == "redevelop":
			return int(r.id)
	return -1


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("  FAIL: ", what)
	else:
		print("PASS ", what)
