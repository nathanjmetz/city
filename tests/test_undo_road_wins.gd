extends SceneTree
## Run: godot --headless -s tests/test_undo_road_wins.gd
## The road wins (a new street bulldozes what's in its way and pays it back),
## and undo puts it all back (critic 2026-10-27: a street drawn through the
## water tower, then Ctrl+Z, took the street away but not the tower, and
## the town emptied without water). Each kind of thing the road wins can
## take comes back with its id, place and state, and the money ends where
## it was before the street.

var _failed := false


func _init() -> void:
	_water_tower()
	_water_utility()
	_farm()
	_farm_fields()
	_industry()
	_warehouse()
	_big_factory()
	_parks()
	_power()
	_campus()
	_telecom()
	_bank()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## A town with one street east-west through the middle.
func _town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 200_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	return sim


## A street east-west through `at`, then undo. Checks that the thing `id` in
## `store` was taken and paid back, and comes back whole: the same id, kind,
## place and state, with the money where it was before the street.
func _through(sim: CitySim, what: String, store: Callable, id: int, at: Vector3, half := 150.0) -> void:
	_check(store.call().has(id), "%s: it stands" % what)
	var was: Dictionary = store.call()[id].duplicate(true)
	var money := sim.economy.money
	_check(sim.apply({"type": "build_road", "start": [at.x - half, at.z], "ctrl": [at.x, at.z], "end": [at.x + half, at.z]}),
		"%s: a street through it" % what)
	_check(not store.call().has(id), "%s: the road wins and bulldozes it" % what)
	_check(sim.apply({"type": "undo"}), "%s: undo goes through" % what)
	var now: Dictionary = store.call().get(id, {})
	_check(not now.is_empty() and str(now.get("kind")) == str(was.get("kind")) and now.pos == was.pos and now.dir == was.dir,
		"%s: back with the same id, kind and place" % what)
	_check(_same(now, was), "%s: back as it was" % what)
	_check(sim.economy.money == money, "%s: the money is where it was before the street ($%d off)" % [what, sim.economy.money - money])


## The fields of a record that the town keeps the same (Dictionary equality,
## ignoring keys the town only adds to draw it).
func _same(a: Dictionary, b: Dictionary) -> bool:
	for k in b:
		if k in ["changed"]:
			continue
		if not a.has(k) or a[k] != b[k]:
			print("  differs: %s: %s -> %s" % [k, str(b[k]).left(120), str(a.get(k)).left(120)])
			return false
	return true


func _water_tower() -> void:
	var sim := _town()
	for x in range(-500, 501, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := Services.site_near(sim.network, Services.Kind.WATER_TOWER, Vector3(0, 0, 40))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.WATER_TOWER, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "water tower: placed")
	var id: int = sim.services.buildings.keys()[0]
	sim.construction.sites.erase("svc:%d" % id)  # built
	for i in 20:
		sim.tick()
	var cap: int = sim.services.utility_use.water[1]
	_check(cap > 0, "water tower: it supplies water (%d)" % cap)
	_through(sim, "water tower", func(): return sim.services.buildings, id, site[0])
	for i in 20:
		sim.tick()
	_check(sim.services.utility_use.water[1] == cap, "water tower: it supplies water again (%d of %d)" % [sim.services.utility_use.water[1], cap])
	var served := 0
	for key in sim.services.served:
		if sim.services.served[key].get("water", false):
			served += 1
	_check(served > 0, "water tower: homes have water again (%d lots)" % served)


func _water_utility() -> void:
	var sim := _town()
	var site := Services.site_near(sim.network, Services.Kind.WATER_UTILITY, Vector3(0, 0, 40))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.WATER_UTILITY, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "water utility: placed")
	var id: int = sim.services.buildings.keys()[0]
	var u: Dictionary = sim.services.water.utilities[id].duplicate(true)
	_through(sim, "water utility", func(): return sim.services.buildings, id, site[0])
	_check(sim.services.water.utilities.has(id) and sim.services.water.utilities[id].name == u.name
		and sim.services.water.utilities[id].mains.size() == u.mains.size(),
		"water utility: its manager and mains are back (%s)" % str(sim.services.water.utilities.get(id, {}).get("name")))
	_check(sim.construction.sites.has("svc:%d" % id), "water utility: it's still going up where it was")


func _farm() -> void:
	var sim := _town()
	_check(sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"}), "farm: placed")
	var id: int = sim.farms.farms.keys()[0]
	var f: Dictionary = sim.farms.farms[id]
	var owner := sim.families.name_of("farm:%d" % id)
	var build: Dictionary = sim.construction.sites.get("farm:%d" % id, {}).duplicate(true)
	_through(sim, "farm", func(): return sim.farms.farms, id, f.pos, 300.0)
	_check(sim.families.name_of("farm:%d" % id) == owner, "farm: the same family runs it (%s)" % owner)
	_check(not build.is_empty() and sim.construction.sites.get("farm:%d" % id, {}).get("start") == build.start,
		"farm: its farmhouse is still going up where it was")


## A street through a farm's fields, not its yard: the fields cut back to the
## road come back whole.
func _farm_fields() -> void:
	var sim := _town()
	sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	var id: int = sim.farms.farms.keys()[0]
	var f: Dictionary = sim.farms.farms[id]
	for i in 40:
		if f.cells.size() >= 8:
			break
		sim.farms.decide(sim.field_usable)
	# The field farthest out to one side: a street north-south through it
	# misses the yard.
	var far: Vector3 = f.pos
	for c in f.cells:
		var p := Farms.cell_center(f, c)
		if absf(p.x - f.pos.x) > absf(far.x - f.pos.x):
			far = p
	_check(absf(far.x - f.pos.x) > 80.0, "farm fields: fields grow away from the yard (%d cells)" % f.cells.size())
	var was: Dictionary = f.duplicate(true)
	var money := sim.economy.money
	# A boulevard down the middle of a field leaves too little of it to farm.
	sim.apply({"type": "build_road", "start": [far.x, far.z - 400], "ctrl": [far.x, far.z], "end": [far.x, far.z + 400],
		"road": RoadStyle.Type.BOULEVARD})
	f = sim.farms.farms.get(id, {})
	_check(not f.is_empty() and f.cells.size() < was.cells.size(), "farm fields: the road takes some (%d of %d cells left)"
		% [f.get("cells", []).size(), was.cells.size()])
	_check(sim.apply({"type": "undo"}), "farm fields: undo goes through")
	f = sim.farms.farms.get(id, {})
	_check(not f.is_empty() and f.cells == was.cells and not sim.farms.trim.has(id), "farm fields: they come back whole (%d of %d cells)"
		% [f.get("cells", []).size(), was.cells.size()])
	_check(sim.economy.money == money, "farm fields: the money is where it was")


func _industry() -> void:
	var best := Vector3.ZERO
	var rich := -1.0
	for x in range(-3000, 3001, 150):
		for z in range(-3000, 3001, 150):
			if not Backdrop.inside(Vector2(x, z), 1500.0) and Resources.at(Resources.Kind.OIL, Vector3(x, 0, z)) > rich:
				rich = Resources.at(Resources.Kind.OIL, Vector3(x, 0, z))
				best = Vector3(x, 0, z)
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 200_000_000
	sim.apply({"type": "build_road", "start": [best.x - 1800, best.z], "ctrl": [best.x, best.z], "end": [best.x + 1800, best.z]})
	var id := -1
	for dx in [0, 200, -200, 400, -400]:
		if sim.apply({"type": "place_industry", "kind": "oil", "pos": [best.x + dx, best.z + 30], "dir": [0, -1]}):
			id = sim.industry.sites.keys()[-1]
			break
	_check(id != -1, "oil company: placed")
	if id == -1:
		return
	var owner := sim.families.name_of("site:%d" % id)
	_through(sim, "oil company", func(): return sim.industry.sites, id, sim.industry.sites[id].pos)
	_check(sim.families.name_of("site:%d" % id) == owner, "oil company: the same family runs it (%s)" % owner)


func _warehouse() -> void:
	var sim := _town()
	var site := Warehouses.site_near(sim.network, Vector3(100, 0, 60))
	_check(sim.apply({"type": "place_warehouse", "kind": "small", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"warehouse: placed")
	var id: int = sim.warehouses.buildings.keys()[0]
	_through(sim, "warehouse", func(): return sim.warehouses.buildings, id, Warehouses.center(sim.warehouses.buildings[id]))


func _big_factory() -> void:
	var sim := _town()
	var site := Warehouses.site_near(sim.network, Vector3(-200, 0, -100))
	_check(sim.apply({"type": "place_big_factory", "kind": "ethanol", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"ethanol plant: placed")
	var id: int = sim.big.sites.keys()[0]
	_through(sim, "ethanol plant", func(): return sim.big.sites, id, BigFactories.center(sim.big.sites[id]), 400.0)


## A landmark is bulldozed; a park is only cut back, and grows back whole.
func _parks() -> void:
	var sim := _town()
	var tw := Parks.site_near(sim.network, "football", Vector3(-200, 0, -60))
	_check(sim.apply({"type": "place_park", "kind": "football", "pos": [tw[0].x, tw[0].z], "dir": [tw[1].x, tw[1].z]}),
		"football field: placed")
	var fid: int = sim.parks.sites.keys()[0]
	_through(sim, "football field", func(): return sim.parks.sites, fid, tw[0])
	var site := Parks.site_near(sim.network, "park", Vector3(200, 0, 40))
	_check(sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"park: placed")
	var pid: int = sim.parks.sites.keys()[-1]
	var was: Dictionary = sim.parks.sites[pid].duplicate(true)
	var money := sim.economy.money
	var cx: float = was.pos.x + was.size.x * 0.25
	sim.apply({"type": "build_road", "start": [cx, 0], "ctrl": [cx, 60], "end": [cx, 140]})
	_check(sim.parks.sites.has(pid) and sim.parks.sites[pid].size.x < was.size.x, "park: a street cuts it back")
	_check(sim.apply({"type": "undo"}), "park: undo goes through")
	_check(sim.parks.sites.has(pid) and _same(sim.parks.sites[pid], was), "park: it comes back whole (%s)"
		% str(sim.parks.sites.get(pid, {}).get("size")))
	_check(sim.economy.money == money, "park: the money is where it was")


func _power() -> void:
	var sim := _town()
	var at := Vector3(200, 0, 60)
	var dir := Vector3(0, 0, -1)
	_check(sim.apply({"type": "place_power", "pos": [at.x, at.z], "dir": [dir.x, dir.z]}), "power company: placed")
	var id: int = sim.power.sites.keys()[0]
	_through(sim, "power company", func(): return sim.power.sites, id, sim.power.sites[id].pos)


func _campus() -> void:
	var sim := _town()
	var site := Education.site_near(sim.network, Vector3(300, 0, 90))
	_check(sim.apply({"type": "place_campus", "kind": "high_school", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"high school: placed")
	var id: int = sim.education.campuses.keys()[0]
	_through(sim, "high school", func(): return sim.education.campuses, id, site[0])


func _telecom() -> void:
	var sim := _town()
	var site := Telecom.site_near(sim.network, Vector3(300, 0, 60))
	_check(sim.apply({"type": "place_telecom", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"phone company: placed")
	var id: int = sim.telecom.companies.keys()[0]
	_through(sim, "phone company", func(): return sim.telecom.companies, id, site[0], 100.0)


func _bank() -> void:
	var sim := _town()
	var site := Banks.site_near(sim.network, Vector3(300, 0, 40))
	_check(sim.apply({"type": "place_bank", "kind": "community", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"bank: placed")
	var id: int = sim.banks.banks.keys()[0]
	_through(sim, "bank", func(): return sim.banks.banks, id, Banks.block_center(sim.banks.banks[id], Vector2i.ZERO), 80.0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
