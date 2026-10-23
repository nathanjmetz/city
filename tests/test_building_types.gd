extends SceneTree
## Run: godot --headless -s tests/test_building_types.gd
## Building types: each lot's owner picks what to build from its
## surroundings (Main Street, a dense core, graduates), and each type grows
## along its own path.

var failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [360, 0], "c": [360, 240], "block": 120.0})
	var segs := sim.network.segments.keys()
	segs.sort()
	for id in segs:
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	# A long street apart from the grid, one side zoned for shops.
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [200, -150], "end": [400, -150]})
	var main: int = sim.network.find_segment_near(Vector3(200, 0, -150), 5.0).seg
	sim.apply({"type": "zone_frontage", "seg": main, "side": 1, "zone": ZoneMap.Zone.COMMERCIAL})
	sim.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
	for i in 400:
		sim.tick()
	_check(sim.buildings.size() > 5, "homes grew (%d)" % sim.buildings.size())
	var typed := true
	sim.buildings.clear()
	for i in 400:
		sim.tick()
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		typed = typed and BuildingTypes.TYPES.has(b.get("type", "")) and b.has("level")
	_check(typed, "every new building has a type and a stage")

	# Out in the open, owners build houses; in a built-up core, row homes
	# and apartments too.
	var key := ""
	for k in sim.buildings:
		if sim.buildings[k].zone == ZoneMap.Zone.RESIDENTIAL:
			key = k
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sparse := _picks(sim, key, ZoneMap.Zone.RESIDENTIAL, rng)
	_check(sparse.keys() == ["house"], "a quiet street gets houses (%s)" % str(sparse))
	var crowd := _crowd(sim, key, 70)
	# A small town's crowded core: mostly houses, a few walk-ups, no rows
	# (real small Midwestern towns).
	var small := _picks(sim, key, ZoneMap.Zone.RESIDENTIAL, rng)
	_check(not small.has("row_home") and small.get("house", 0) > small.get("apartments", 0),
		"a small town's core stays mostly houses, no row homes (%s)" % str(small))
	var people: int = sim.stats.population
	sim.stats.population = 150_000
	var dense := _picks(sim, key, ZoneMap.Zone.RESIDENTIAL, rng)
	_check(dense.has("row_home") and dense.has("apartments"), "a big city's dense core gets row homes and apartments (%s)" % str(dense))
	sim.stats.population = people
	var row := BuildingTypes.make(sim, key, sim.buildings[key], "row_home", 0)
	var units: int = row.units
	_check(units == maxi(2, floori(sim.lots[key].width / 7.5)) and row.cap == units * 3,
		"row homes split the lot into narrow homes (%d on %.1f m)" % [units, sim.lots[key].width])
	for k in crowd:
		sim.buildings.erase(k)

	# Shops: a Main Street gets shops with flats upstairs.
	var shop_lot := ""
	for k in sim.lots:
		if sim.zones.zone_at(sim.lots[k].zone_pt) == ZoneMap.Zone.COMMERCIAL:
			shop_lot = k
	var face := LotPlanner.block_face(sim, shop_lot)
	for k in face:
		sim.buildings.erase(k)
	_check(face.size() >= 4, "a block face to make a Main Street on (%d lots)" % face.size())
	var c0 := BuildingTypes.context(sim, face[0])
	_check(not c0.main_street, "one street side is not a Main Street yet")
	for i in [1, 2]:
		sim.buildings[face[i]] = BuildingTypes.make(sim, face[i],
			{"zone": ZoneMap.Zone.COMMERCIAL, "seed": i, "built": 0, "occ": 0}, "shop", 0)
	_check(BuildingTypes.context(sim, face[0]).main_street, "two shops along it make a Main Street")
	var shops := _picks(sim, face[0], ZoneMap.Zone.COMMERCIAL, rng)
	_check(shops.get("mixed_use", 0) > shops.get("shop", 0), "Main Street lots mostly get flats upstairs (%s)" % str(shops))
	sim.buildings[face[0]] = BuildingTypes.make(sim, face[0],
		{"zone": ZoneMap.Zone.COMMERCIAL, "seed": 9, "built": 0, "occ": 0}, "shop", 0)
	var opts := BuildingTypes.options(sim, face[1])
	_check(opts.any(func(o): return o[0] == "mixed_use"),
		"a corner store on Main Street can add flats upstairs (%s)" % str(opts))

	# Offices only open while there are college graduates to hire.
	sim.education.locals.degree = 0.0
	var none := _picks(sim, face[3], ZoneMap.Zone.COMMERCIAL, rng)
	_check(not none.has("office"), "no graduates, no offices (%s)" % str(none))
	sim.education.locals.degree = 400.0
	var some := _picks(sim, face[3], ZoneMap.Zone.COMMERCIAL, rng)
	_check(some.has("office"), "graduates bring offices (%s)" % str(some))

	# Flats over a shop fill with residents and count as homes.
	sim.education.locals.degree = 0.0
	sim.buildings[face[3]] = BuildingTypes.make(sim, face[3],
		{"zone": ZoneMap.Zone.COMMERCIAL, "seed": 3, "built": 0, "occ": 0}, "mixed_use", 0)
	var flats: int = sim.buildings[face[3]].flats
	_check(flats >= 3, "a Main Street block has flats (%d)" % flats)
	for i in 400:
		sim.tick()
	_check(int(sim.buildings[face[3]].focc) > 0, "people move into the flats (%d of %d)" % [sim.buildings[face[3]].focc, flats])

	# Growing up the path: a house adds a storey, keeping its family.
	var home := ""
	for k in sim.buildings:
		if BuildingTypes.type_of(sim.buildings[k]) == "house":
			home = k
			break
	sim.redevelop(home, "house", 1)
	_check(BuildingTypes.storeys(sim.buildings[home]) == 2 and sim.buildings[home].cap >= 4,
		"a house grows into a two-storey home (cap %d)" % sim.buildings[home].cap)

	# Saves keep type, stage and flats; copies stay in step. (This test put
	# buildings in by hand, so re-plat the lots first, as a load does.)
	sim._lots_dirty = true
	sim.tick()
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	copy.simulate_traffic = false
	_check(copy.buildings[face[3]].type == "mixed_use" and copy.buildings[home].level == 1
		and copy.buildings[face[3]].flats == flats, "save keeps building types and stages")
	for i in 2000:
		sim.tick()
		copy.tick()
	var da := copy.to_dict()
	var db := sim.to_dict()
	var diff := []
	for k in da:
		if JSON.stringify(da[k]) != JSON.stringify(db.get(k)):
			diff.append(k)
	_check(diff.is_empty(), "copies stay in sync %s" % str(diff))


	# Old saves: buildings without a type are the plain type of their zone.
	var old := sim.to_dict()
	for k in old.buildings:
		for f in ["type", "level", "units", "flats", "focc", "changed", "why"]:
			old.buildings[k].erase(f)
	var loaded := CitySim.new()
	loaded.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(loaded.buildings[face[3]].type == "shop" and loaded.buildings[home].type == "house",
		"old saves load as houses, shops and factories")

	# Over time, full buildings move up their paths on their own.
	var grow := CitySim.new()
	grow.simulate_traffic = false
	grow.apply({"type": "build_grid", "a": [0, 0], "b": [240, 0], "c": [240, 120], "block": 120.0})
	var gsegs := grow.network.segments.keys()
	gsegs.sort()
	for id in gsegs:
		for side in [-1, 1]:
			grow.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	# Jobs, so people keep coming.
	grow.apply({"type": "build_road", "start": [0, -150], "ctrl": [200, -150], "end": [400, -150]})
	var works: int = grow.network.find_segment_near(Vector3(200, 0, -150), 5.0).seg
	grow.apply({"type": "zone_frontage", "seg": works, "side": 1, "zone": ZoneMap.Zone.INDUSTRIAL})
	grow.apply({"type": "zone_frontage", "seg": works, "side": -1, "zone": ZoneMap.Zone.COMMERCIAL})
	for i in Balance.DEVELOP_AGE + 3000:
		grow.demand[ZoneMap.Zone.RESIDENTIAL] = 1.0
		grow.tick()
	var grown := 0
	for k in grow.buildings:
		grown += int(grow.buildings[k].level)
	_check(grown > 0, "buildings grow along their paths over time (%d stages up)" % grown)
	_test_far()
	print("ALL TESTS PASSED" if not failed else "TESTS FAILED")
	quit(1 if failed else 0)


## Zoning's floor-area ratio caps how big a building gets; a tower needs
## a bigger lot than a storefront, so its owner buys the lot next door.
func _test_far() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.apply({"type": "build_grid", "a": [0, 0], "b": [360, 0], "c": [360, 240], "block": 120.0})
	# The middle street of the grid is the shopping street.
	var main := -1
	var best := INF
	for id in sim.network.segments:
		var pts: PackedVector3Array = sim.network.sample_segment(id, 2)
		var d: float = pts[1].distance_to(Vector3(180, 0, 120))
		if d < best:
			best = d
			main = id
	sim.apply({"type": "zone_frontage", "seg": main, "side": 1, "zone": ZoneMap.Zone.COMMERCIAL})
	var segs := sim.network.segments.keys()
	segs.sort()
	for id in segs:
		if id != main:
			for side in [-1, 1]:
				sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.tick()
	var shop_lot := ""
	for k in sim.lots:
		if sim.zones.zone_at(sim.lots[k].zone_pt) == ZoneMap.Zone.COMMERCIAL:
			shop_lot = k
	var face := LotPlanner.block_face(sim, shop_lot)
	var home := ""
	for k in sim.lots:
		if sim.zones.zone_at(sim.lots[k].zone_pt) == ZoneMap.Zone.RESIDENTIAL:
			home = k
			break
	_check(is_equal_approx(BuildingTypes.context(sim, home).far, Balance.FAR_HOMES[0]),
		"a quiet street of homes is zoned for houses (FAR %.1f)" % BuildingTypes.context(sim, home).far)
	var key: String = face[1]
	var crowd := _crowd(sim, key, 80)
	for k in face:
		sim.buildings.erase(k)
	sim.stats.population = 3_000
	var c := BuildingTypes.context(sim, key)
	_check(c.far <= Balance.FAR_SHOPS[2], "a small town's busy blocks stay low (FAR %.1f)" % c.far)
	sim.stats.population = 60_000
	sim.education.locals.degree = 20_000.0
	c = BuildingTypes.context(sim, key)
	_check(c.downtown and is_equal_approx(c.far, Balance.FAR_DOWNTOWN[1]), "a city's core is zoned for towers (FAR %.1f, %d nearby, %d lots)" % [c.far, c.density, sim.lots.size()])
	sim.buildings[key] = BuildingTypes.make(sim, key,
		{"zone": ZoneMap.Zone.COMMERCIAL, "seed": 5, "built": 0, "occ": 0}, "office", 2)
	var area: float = sim.lots[key].area
	_check(BuildingTypes.far_of("office", 3, area) > c.far and not BuildingTypes.options(sim, key).has(["office", 3]),
		"a high-rise doesn't fit one storefront lot (%.0f m², FAR %.1f)" % [area, BuildingTypes.far_of("office", 3, area)])
	# Next door: a charming old shop, which isn't for sale, and a vacant one.
	var at := face.find(key)
	sim.buildings[face[at - 1]] = BuildingTypes.make(sim, face[at - 1],
		{"zone": ZoneMap.Zone.COMMERCIAL, "seed": 6, "built": 0, "occ": 4}, "shop", 0)
	sim.heritage.charm[face[at - 1]] = 1.0
	var bought := BuildingTypes.assemble(sim, key)
	_check(bought == face[at + 1] and not sim.lots.has(bought) and sim.lots[key].area > area + 200.0,
		"the owner buys the empty lot next door, not the charming old shop (%s, %.0f m²)" % [bought, sim.lots[key].area])
	for i in 4:
		if BuildingTypes.options(sim, key).has(["office", 3]):
			break
		BuildingTypes.assemble(sim, key)
	_check(BuildingTypes.options(sim, key).has(["office", 3]) and sim.lots.has(face[at - 1]),
		"on the assembled site the high-rise fits (%.0f m²)" % sim.lots[key].area)
	sim.redevelop(key, "office", 3)
	_check(BuildingTypes.storeys(sim.buildings[key]) == 16, "and it goes up 16 storeys")
	# A small town has no tower core: nobody assembles a site there.
	sim.stats.population = 3_000
	_check(BuildingTypes.assemble(sim, key) == "", "no tower sites outside a city's core")
	for k in crowd:
		sim.buildings.erase(k)


## How often each type comes up for a lot, over many owners.
func _picks(sim: CitySim, key: String, zone: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for i in 200:
		var t: String = BuildingTypes.pick(sim, key, zone, rng)[0]
		out[t] = out.get(t, 0) + 1
	return out


## Puts n stand-in buildings near a lot (on other lots), for density.
func _crowd(sim: CitySim, key: String, n: int) -> Array:
	var added := []
	var keys := []
	for k in sim.lots:
		keys.append([sim.lots[k].pos.distance_to(sim.lots[key].pos), k])
	keys.sort()
	for e in keys:
		var k: String = e[1]
		if added.size() >= n:
			break
		if k != key and not sim.buildings.has(k):
			sim.buildings[k] = {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": 1, "built": 0, "cap": 3, "occ": 3}
			added.append(k)
	return added


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	failed = failed or not ok
