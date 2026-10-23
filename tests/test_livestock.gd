extends SceneTree
## Livestock on farms (Brawn, 2026-10-23): a farm's leader picks a path
## (grain only, a beef herd on pasture, hog, dairy or turkey barns), big
## barns ask on the bell first (IDEM confined feeding), and a path that keeps
## losing is given up. Also the leader-check caches in Agency.
## Run: godot --headless -s tests/test_livestock.gd

var _fails := 0


func _init() -> void:
	_paths()
	_pasture()
	_barns_on_the_bell()
	_caches()
	print("ALL TESTS PASSED" if _fails == 0 else "%d TESTS FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Which paths are open, and what a leader makes of them.
func _paths() -> void:
	var flat := func(_c): return 0.0
	var soil := func(_c): return 0.85
	var f := _farm({"edu": 0.3, "caution": 0.5, "ambition": 0.5})
	var ids := func(opts: Array) -> Array: return opts.map(func(o): return o.id)
	var cut_off: Array = ids.call(Livestock.options(f, {"day": 0.0, "price": 1.0, "link": false, "mill": false,
		"fert": soil, "slope": flat}))
	_check(cut_off == ["none"], "good flat ground with no road out: grain only (%s)" % str(cut_off))
	var linked: Array = ids.call(Livestock.options(f, {"day": 0.0, "price": 1.0, "link": true, "mill": false,
		"fert": soil, "slope": flat}))
	_check("hogs" in linked and "turkeys" in linked and not "dairy" in linked,
		"a road out opens hog and turkey barns; a dairy needs a schooled leader (%s)" % str(linked))
	var school := _farm({"edu": 0.8, "caution": 0.5, "ambition": 0.5})
	_check("dairy" in ids.call(Livestock.options(school, {"day": 0.0, "price": 1.0, "link": true, "mill": false,
		"fert": soil, "slope": flat})), "a college-educated farmer can run a dairy")
	# A careful leader keeps to grain; a bold one builds barns.
	var careful := Agency.choose({"edu": 0.3, "caution": 1.0, "ambition": 0.0}, Livestock.options(f,
		{"day": 0.0, "price": 1.0, "link": true, "mill": false, "fert": soil, "slope": flat}))
	var bold := Agency.choose({"edu": 0.3, "caution": 0.0, "ambition": 1.0}, Livestock.options(f,
		{"day": 0.0, "price": 1.0, "link": true, "mill": true, "fert": soil, "slope": flat}))
	_check(careful.id == "none" and bold.id in Livestock.BARNS,
		"caution keeps to grain, ambition builds barns (%s / %s: %s)" % [careful.id, bold.id, bold.why])


## Steep or poor ground goes to a beef herd, and the crop plan pastures it.
func _pasture() -> void:
	var lead := {"edu": 0.5, "caution": 0.5, "ambition": 0.5}
	var f := _farm(lead)
	var soil := func(_c): return 0.85
	var steep := func(_c): return 0.14
	_check(Livestock.pasture_gain(f, soil, func(_c): return 0.0, 1.0, 0.0) == 0.0,
		"pasture never beats crops on good flat ground")
	_check(Livestock.pasture_gain(f, soil, steep, 1.0, 0.0) > 0.0, "it does on steep ground")
	_check(Livestock.pasture_gain(f, func(_c): return 0.3, func(_c): return 0.0, 1.0, 0.0) > 0.0,
		"and on poor ground, like reclaimed mine land")
	Livestock.stock(f).kind = "cattle"
	CropPlan.plan(f, {}, 1.0, 0.0, soil, steep)
	var crop: String = f.fields.values()[0].crop
	_check(crop == "pasture" and f.fields.values()[0].why.contains("herd"),
		"a cattle farm puts its steep forties in pasture (%s: %s)" % [crop, f.fields.values()[0].why])
	_check(Livestock.head(f) > 0, "and keeps a herd on it (%d cows)" % Livestock.head(f))
	var grain := _farm(lead)
	CropPlan.plan(grain, {}, 1.0, 0.0, soil, steep)
	_check(grain.fields.values()[0].crop != "pasture", "a farm with no herd never plants pasture")


## Hog barns past 600 head ask the town first; yes builds them, losses
## take them down again, and it all saves.
func _barns_on_the_bell() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.apply({"type": "paint_farmland", "points": [[-500, 20], [500, 20], [500, 600], [-500, 600]]})
	sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	var id: int = sim.farms.farms.keys()[0]
	var f: Dictionary = sim.farms.farms[id]
	f.barn = true
	f.leader = {"edu": 0.3, "caution": 0.0, "ambition": 1.0}
	for i in range(-8, 9):
		for j in range(0, 8):
			var c := Vector2i(i, j)
			if c != Vector2i.ZERO and not c in f.cells and sim.field_usable(Farms.cell_center(f, c), Farms.cell_corners(f, c)):
				f.cells.append(c)
	var cells_before: int = f.cells.size()
	var jobs_before := sim.farms.jobs()
	Livestock.stock(f).kind = "hogs"
	var homes := Livestock._homes(sim)
	Livestock._add_site(sim, id, f, "hogs", homes)
	var st: Dictionary = f.stock
	_check(not st.pending.is_empty(), "2,400 hogs is past IDEM's 600: the farm asks on the bell (%s)" % st.why)
	var req: Dictionary = sim.permits.requests.get(int(st.pending.get("req", -1)), {})
	_check(req.get("ask", "") == "cfo" and str(req.get("yes", "")).contains("job") and req.route.size() >= 3,
		"the ask says what a yes brings and shows the setback on the map")
	sim.apply({"type": "permit", "id": int(st.pending.req), "answer": "approve"})
	_check(Livestock.step(sim), "after a yes the barns go up")
	_check(Livestock.head(f) == 2400 and f.cells.size() == cells_before - 2,
		"2,400 hogs on two cells taken from the fields (%d, %d cells)" % [Livestock.head(f), f.cells.size()])
	_check(sim.farms.jobs() > jobs_before, "the barns hire")
	var mid := Livestock.site_center(f, Livestock.sites(f)[0])
	_check(sim.farms.farm_at(mid) == id and sim.farms.field_at(mid) == -1, "the barn pad belongs to the farm, not a field")
	_check(sim.farms.best_field(id, sim.field_usable) == Vector2i.MAX or not sim.farms.best_field(id, sim.field_usable) in Livestock.site_cells(f),
		"the farm never plants over its own barns")
	sim.pollution.rebuild(sim)
	_check(sim.pollution.sources.has("barns:%d" % id), "the barns show as a pollution source of their own")
	_check(Livestock.yearly(f, 0.0) > 0.0, "hog barns pay in an ordinary year ($%d)" % roundi(Livestock.yearly(f, 0.0)))
	sim.farms.demand = CropPlan.demand(sim)
	_check(sim.farms.demand.has("corn") and str(sim.farms.demand.corn[1]).contains("feed"), "barns make corn worth more nearby")

	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var bf: Dictionary = back.farms.farms[id]
	_check(Livestock.kind(bf) == "hogs" and Livestock.head(bf) == 2400, "the barns are saved")

	# Three losing years and the leader gives the barns up.
	st.loss = Balance.LIVESTOCK_LOSS_YEARS
	Livestock.retool(sim, id, f, "test")
	_check(Livestock.kind(f) == "" and f.cells.size() == cells_before and Livestock.sites(f).is_empty(),
		"giving up takes the barns down and the ground goes back to fields")

	# A no: the farm keeps to grain and waits.
	Livestock.stock(f).kind = "hogs"
	Livestock._add_site(sim, id, f, "hogs", homes)
	if not st.pending.is_empty():
		sim.apply({"type": "permit", "id": int(st.pending.req), "answer": "deny"})
		Livestock.step(sim)
	_check(Livestock.kind(f) == "" and int(st.wait) > sim.farms.year and Livestock.sites(f).is_empty(),
		"after a no the farm keeps to grain for a few years (%s)" % st.why)


## The leader checks reuse one measurement per tick and agree with a scan.
func _caches() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	sim.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	_check(Agency.education(sim) == Agency._education(sim), "the cached schooling matches a full count")
	_check(Agency._local(sim, Vector3(100, 0, 100), "farm") == 1 and Agency._local(sim, Vector3(9000, 0, 0), "farm") == 0,
		"farms within reach are counted from the buckets")
	sim.apply({"type": "place_farmhouse", "pos": [400, 60], "dir": [0, -1], "crop": "corn"})
	_check(Agency._local(sim, Vector3(100, 0, 100), "farm") == sim.farms.farms.size(),
		"a new farm starts the count over (%d)" % Agency._local(sim, Vector3(100, 0, 100), "farm"))


## A farm of four forties in a row, all corn last year.
func _farm(lead: Dictionary) -> Dictionary:
	var f := {"pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "crop": "corn", "cells": [], "leader": lead, "fields": {}}
	for fx in 4:
		for i in 10:
			for j in 10:
				f.cells.append(Vector2i(fx * 10 + i, j))
	return f


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS " + what)
	else:
		print("FAIL " + what)
		_fails += 1
