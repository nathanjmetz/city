extends SceneTree
## Work modes per hub (Brawn's pick #17): the hub's leader picks how it
## runs. A plant whose orders back up adds a second shift (more batches,
## more jobs, night pay), and lets the night crew go when those batches stop
## selling; an ethanol plant already runs around the clock.
## Run: godot --headless -s tests/test_work_modes.gd


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	var site := Warehouses.site_near(sim.network, Vector3(-200, 0, -100))
	_check(sim.apply({"type": "place_big_factory", "kind": "furniture", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a furniture maker goes up")
	var f: Dictionary = sim.big.sites[1]
	f.leader = {"edu": 0.5, "caution": 0.5, "ambition": 0.5}
	var day: float = sim.big.day_capacity(f)
	var jobs: int = sim.big.jobs_at(f)
	var cost: float = sim.big.batch_cost(f)
	_check(int(f.get("shifts", 1)) == 1 and is_equal_approx(sim.big.capacity(f), day), "it starts on a day shift")

	# Half busy: no night shift.
	f.last = {"made": day * 0.5, "util": 0.5}
	sim.big._shifts(sim, f, 0.5, "")
	_check(int(f.get("shifts", 1)) == 1, "half busy, it stays on one shift")

	# Orders back up but nobody in town is looking for work.
	sim.stats = {"population": 300, "workers": 150, "employed": 150, "jobs": 150, "commuting": 0, "homes_free": 0}
	f.last = {"made": day, "util": 1.0}
	sim.big._shifts(sim, f, 1.0, "")
	_check(int(f.get("shifts", 1)) == 1, "with nobody to hire, it stays on one shift")

	# Orders back up, and the town has people looking for work.
	sim.stats = {"population": 3000, "workers": 1500, "employed": 1000, "jobs": 1000, "commuting": 0, "homes_free": 0}
	f.last = {"made": day, "util": 1.0}
	sim.big._shifts(sim, f, 1.0, "")
	_check(int(f.shifts) == 2, "busy, the owner adds a second shift (%s)" % str(f.why))
	_check(str(f.why).begins_with("A second shift over one shift"), "and says why")
	_check(sim.big.capacity(f) > day * 1.8, "it makes more (%.1f -> %.1f batches)" % [day, sim.big.capacity(f)])
	_check(sim.big.jobs_at(f) > jobs * 1.8, "and hires a night crew (%d -> %d jobs)" % [jobs, sim.big.jobs_at(f)])
	_check(sim.big.batch_cost(f) > cost, "the night shift's work costs a differential more")
	_check(BigFactoryInfo.describe(sim, 1).rows.any(func(r): return r[0] == "Shifts" and r[1] == "Day and night"),
		"its panel says it runs day and night")

	# The player's hold keeps it from adding one, never from dropping one.
	var g := f.duplicate(true)
	g.shifts = 1
	sim.big._shifts(sim, g, 1.0, "hold")
	_check(int(g.shifts) == 1, "on hold it doesn't add a shift")

	# Steady at what the night shift adds: it keeps it.
	f.last = {"made": day * 1.6, "util": 0.86}
	sim.big._shifts(sim, f, 0.86, "")
	_check(int(f.shifts) == 2, "selling the night batches, it keeps both shifts")
	# The night batches stop selling: it lets them go.
	f.last = {"made": day * 0.8, "util": 0.43}
	sim.big._shifts(sim, f, 0.43, "")
	_check(int(f.shifts) == 1 and is_equal_approx(sim.big.capacity(f), day), "orders fall off, back to one shift (%s)" % str(f.why))

	# An ethanol plant runs around the clock already.
	var other := Warehouses.site_near(sim.network, Vector3(300, 0, -100))
	_check(sim.apply({"type": "place_big_factory", "kind": "ethanol", "pos": [other[0].x, other[0].z],
		"dir": [other[1].x, other[1].z]}), "an ethanol plant")
	var e: Dictionary = sim.big.sites[2]
	e.last = {"made": sim.big.day_capacity(e), "util": 1.0}
	sim.big._shifts(sim, e, 1.0, "")
	_check(int(e.get("shifts", 1)) == 1, "the ethanol plant has no shift to add")

	f.shifts = 2
	var back := BigFactories.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sim.big.to_dict())))
	_check(int(back.sites[1].shifts) == 2 and int(back.sites[2].shifts) == 1, "shifts are saved")

	_tillage()
	_hours()

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Farms: each January the leader picks how to work the ground.
func _tillage() -> void:
	var avg := {"edu": 0.5, "caution": 0.5, "ambition": 0.5}
	var flat := _farm(avg, "chisel")
	_check(_pick(flat, 0.0) == "beans_no_till", "a flat corn-and-bean farm no-tills its soybeans (%s)" % str(flat.get("till_why", "")))
	var steep := _farm(avg, "chisel")
	_check(_pick(steep, 0.12) == "no_till", "on steep ground it no-tills everything to keep the soil (%s)" % str(steep.get("till_why", "")))
	var hay := _farm(avg, "chisel", "hay")
	_check(_pick(hay, 0.0) == "chisel" and not hay.has("till_why"), "an all-hay farm has nothing to till")
	# What it costs and pays: no-till saves passes, corn yields a little less.
	var conv := CropPlan.net_per_acre("soybeans", "corn", 0.5, 0.8, 1.0)
	_check(CropPlan.net_per_acre("soybeans", "corn", 0.5, 0.8, 1.0, 1.0, "no_till") > conv + 20.0,
		"no-till soybeans skip about $24 of tillage")
	_check(CropPlan.net_per_acre("corn", "soybeans", 0.5, 0.8, 1.0, 1.0, "no_till")
		< CropPlan.net_per_acre("corn", "soybeans", 0.5, 0.8, 1.0), "no-till corn on dark ground nets less")
	_check(CropPlan.next_health(0.5, "corn", "soybeans", false, "no_till") > CropPlan.next_health(0.5, "corn", "soybeans", false),
		"no-till builds the soil")
	# The farm's look follows the pick.
	_check(CropCalendar.farm_practice(7, {"till": "no_till"}) == CropCalendar.NO_TILL
		and CropCalendar.farm_practice(7, {"till": "chisel"}) == CropCalendar.CHISEL, "the fields are drawn the way it tills")

	# In a town: the January plan sets it, the panel says it, and it's saved.
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_county_road", "a": [-700, 0], "b": [700, 0], "links": [0, 1]})
	sim.apply({"type": "place_farmhouse", "pos": [0, -90], "dir": [0, 1], "crop": "corn"})
	var id: int = sim.farms.farms.keys()[0]
	var f: Dictionary = sim.farms.farms[id]
	f.cells = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)]
	f.barn = true
	f.plan_year = sim.farms.year - 1
	sim.farms.decide(func(_c, _p): return true)
	_check(Balance.TILLAGE.has(str(f.get("till", ""))), "the January plan picks its tillage (%s)" % str(f.get("till", "")))
	var at := Farms.cell_center(f, f.cells[0])
	var rows: Array = Inspect.describe(sim, {"type": "farm", "id": id, "at": [at.x, at.z]}).rows
	_check(rows.any(func(r): return r[0] == "Tillage" and r[1].begins_with(Balance.TILLAGE[f.till].name)),
		"its panel says how it tills")
	var back := Farms.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sim.farms.to_dict())))
	_check(str(back.farms[id].get("till", "")) == str(f.till), "the farm's tillage is saved")


## Shops: each January the owner weighs staying open until 9.
func _hours() -> void:
	var sim := CitySim.new()
	sim.stats = {"population": 2000, "workers": 1000, "employed": 450, "jobs": 450, "commuting": 50, "homes_free": 0}
	var fams: Families = sim.families
	var shops := {"grocery": "g", "florist": "f", "restaurant": "r", "law": "l", "grocery2": "g2"}
	for what in shops:
		sim.buildings[shops[what]] = {"cap": 10, "zone": ZoneMap.Zone.COMMERCIAL}
		var fam := fams._new_family(sim, "Miller", "Miller", "serif", hash(what), 2030)
		fam.caution = 0.5
		fam.ambition = 0.5
		fams.families[fam.id] = fam
		fams.next_id += 1
		fams._own("lot:" + shops[what], fam.id, what.trim_suffix("2"), what, 2030)
	fams._set_hours(sim, "lot:g")
	fams._set_hours(sim, "lot:f")
	_check(fams.owned["lot:g"].late, "the grocery stays open until 9 (%s)" % fams.owned["lot:g"].hours_why)
	_check(not fams.owned["lot:f"].late, "the florist closes at 6 (%s)" % fams.owned["lot:f"].hours_why)
	_check(fams.open_at("lot:g", 19) and not fams.open_at("lot:g", 21) and not fams.open_at("lot:f", 19)
		and fams.open_at("lot:f", 10), "after six only the late shops are open")
	_check(fams.open_at("lot:r", 20) and not fams.open_at("lot:l", 19), "the diner is open for supper, the law office isn't")
	_check(fams._draw(sim, "lot:g") > 10 * Balance.FAMILY_PER_JOB or not sim.utilities_ok("g"),
		"the evening's sales go to the owners")
	# A second grocery shares the town's evening shoppers.
	fams._set_hours(sim, "lot:g2")
	_check(float(fams.owned["lot:g2"].get("late_net", 0)) < float(fams.owned["lot:g"].late_net),
		"a second grocery splits the evening trade")
	sim.stats = {"population": 2000, "workers": 1000, "employed": 0, "jobs": 0, "commuting": 0, "homes_free": 0}
	fams._set_hours(sim, "lot:g")
	_check(not fams.owned["lot:g"].late, "with nobody working days, the evening isn't worth it")
	_check(fams.rows(sim, "lot:f").any(func(r): return r[0] == "Hours" and r[1].begins_with("9 am to 6 pm")),
		"the shop's panel shows its hours")
	var back := Families.new()
	back.from_dict(JSON.parse_string(JSON.stringify(fams.to_dict())))
	_check(back.open_at("lot:g2", 19) == fams.open_at("lot:g2", 19) and back.owned["lot:f"].has("late"), "hours are saved")


func _farm(lead: Dictionary, till: String, crop := "") -> Dictionary:
	var f := {"leader": lead, "till": till, "crop": "corn", "fields": {}, "cells": []}
	for i in 4:
		var c := Vector2i(i * 40, 0)
		f.cells.append(c)
		var grow := crop if crop != "" else ("corn" if i % 2 == 0 else "soybeans")
		f.fields[CropPlan.field_of(c)] = {"crop": grow, "prev": "soybeans" if grow == "corn" else "corn", "years": 1,
			"health": 0.5, "cover": false, "cover_prev": false, "why": ""}
	return f


func _pick(f: Dictionary, slope: float) -> String:
	var cells_of := {}
	for c in f.cells:
		cells_of[CropPlan.field_of(c)] = [c]
	var keys := cells_of.keys()
	keys.sort()
	return CropPlan.plan_till(f, f.leader, cells_of, keys, 1.0, func(_c): return 0.8, func(_c): return slope)


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
