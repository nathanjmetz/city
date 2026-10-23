extends SceneTree
## Run: godot --headless -s tests/test_crops.gd
## Crop rotation (CropPlan) and the shared leader choice (Agency.choose).

var _failed := false


func _init() -> void:
	# The shared leader choice: the best weighted total wins and says why.
	var lead := {"edu": 0.5, "caution": 0.5, "ambition": 0.5}
	var pick := Agency.choose(lead, [
		{"id": "a", "name": "Plan A", "factors": {"money": [100.0, "pays more"], "risk": [-10.0, "costs less"]}},
		{"id": "b", "name": "Plan B", "factors": {"money": [60.0, "pays less"], "risk": [-5.0, "costs less"]}},
	])
	_check(pick.id == "a" and pick.why.contains("pays more") and pick.why.begins_with("Plan A over plan b"),
		"a leader picks the better option and says why (%s)" % pick.why)
	_check(Agency.weight({"edu": 1.0}, "future") > Agency.weight({"edu": 0.0}, "future"),
		"schooling makes a leader look further ahead")

	# One farm, four forties, average soil, flat ground, nobody buying extra.
	var flat := func(_c): return 0.0
	var soil := func(_c): return 0.85
	var f := _farm(lead)
	var history := {}
	for year in 8:
		CropPlan.plan(f, {}, 1.0, 0.0, soil, flat)
		for k in f.fields:
			if not history.has(k):
				history[k] = []
			history[k].append(f.fields[k].crop)
	var repeats := 0
	var corn_years := 0
	for k in history:
		for i in range(1, history[k].size()):
			repeats += 1 if history[k][i] == history[k][i - 1] and history[k][i] != "hay" else 0
		corn_years += history[k].count("corn")
	_check(repeats == 0, "fields rotate: no row crop two years running on flat, average ground (%s)" % str(history))
	_check(corn_years >= 10 and corn_years <= 20, "corn comes round every other year or so (%d of 32)" % corn_years)
	var mixed := false
	for year in 8:
		var crops := {}
		for k in history:
			crops[history[k][year]] = true
		mixed = mixed or crops.size() > 1
	_check(mixed, "a careful farmer splits the farm between crops in some years")
	var soy_field := ""
	for k in f.fields:
		if f.fields[k].crop == "corn" and f.fields[k].prev == "soybeans":
			soy_field = f.fields[k].why
	_check(soy_field.contains("Corn over") and (soy_field.contains("soybeans leave nitrogen") or soy_field.contains("pays")),
		"corn after soybeans says why: %s" % soy_field)

	# Steep ground goes to hay (NRCS highly erodible land).
	var hill := _farm(lead)
	CropPlan.plan(hill, {}, 1.0, 0.0, soil, func(_c): return 0.14)
	_check(hill.fields.values()[0].crop == "hay" and hill.fields.values()[0].why.contains("steep"),
		"steep fields are kept in hay (%s)" % hill.fields.values()[0].why)

	# A grain mill in town makes wheat (flour) worth growing after soybeans.
	var milled := _farm(lead)
	for k in milled.fields:
		milled.fields[k].crop = "soybeans"
	var mill_demand := {"wheat": [Balance.CROP_DEMAND.mill_wheat + 40.0, "the mill grinds soft red winter wheat for flour"]}
	CropPlan.plan(milled, mill_demand, 1.0, 0.0, soil, flat)
	var wheat := 0
	for k in milled.fields:
		wheat += 1 if milled.fields[k].crop == "wheat" else 0
	_check(wheat > 0, "a strong flour buyer gets wheat into the rotation (%d of 4 fields)" % wheat)

	# Cover crops: the college-educated farmer sows rye, the other doesn't.
	var school := _farm({"edu": 0.9, "caution": 0.5, "ambition": 0.5})
	var no_school := _farm({"edu": 0.2, "caution": 0.5, "ambition": 0.5})
	CropPlan.plan(school, {}, 1.0, 0.0, soil, flat)
	CropPlan.plan(no_school, {}, 1.0, 0.0, soil, flat)
	_check(school.fields.values()[0].cover and not no_school.fields.values()[0].cover,
		"educated farmers sow a rye cover crop, others leave stubble")
	_check(school.fields.values()[0].why.contains("cover crop"), "and Inspect says so")

	# Rotation pays: two years of corn after corn makes less than corn after soybeans.
	_check(CropPlan.net_per_acre("corn", "soybeans", 0.5, 1.0, 1.0) > CropPlan.net_per_acre("corn", "corn", 0.5, 1.0, 1.0) + 80.0,
		"corn after soybeans beats corn after corn by the rotation effect plus the nitrogen credit")

	# In a real town: a farm plans each January, the field shows its crop
	# and why in Inspect, and it's saved.
	var fm := CitySim.new()
	fm.economy.money = 10_000_000
	fm.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	fm.apply({"type": "paint_farmland", "points": [[-500, 20], [500, 20], [500, 600], [-500, 600]]})
	fm.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	var farm: Dictionary = fm.farms.farms.values()[0]
	var first_year := Seasons.year(fm.tick_count)
	while Seasons.year(fm.tick_count) < first_year + 2:
		fm.tick()
	_check(not farm.fields.is_empty() and int(farm.plan_year) == first_year + 2, "the farm planned its crops in January")
	var c: Vector2i = farm.cells[0]
	var at := Farms.cell_center(farm, c)
	var sel := Inspect.pick(fm, at)
	var d := Inspect.describe(fm, sel)
	var why := ""
	var this := ""
	for r in d.rows:
		if r[0] == "Why":
			why = r[1]
		if r[0] == "This field":
			this = r[1]
	_check(this.begins_with(CropPlan.crop_at(farm, c).capitalize()) and why.contains(" over "),
		"clicking a field shows its crop and why (%s: %s)" % [this, why])
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(fm.to_dict())))
	var bf: Dictionary = back.farms.farms.values()[0]
	_check(bf.fields.size() == farm.fields.size() and CropPlan.crop_at(bf, c) == CropPlan.crop_at(farm, c),
		"each field's crop is saved")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## A farm of four forties in a row, all corn last year.
func _farm(lead: Dictionary) -> Dictionary:
	var f := {"pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "crop": "corn", "cells": [], "leader": lead, "fields": {}}
	for fx in 4:
		for i in 10:
			for j in 10:
				f.cells.append(Vector2i(fx * 10 + i, j))
	return f


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
