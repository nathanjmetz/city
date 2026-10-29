extends SceneTree
## Local materials (Brawn's pick #12): a job site's concrete comes from the
## town's own quarry on a real truck, the quarry is paid, and the truck goes
## back to the quarry; a town without one still gets it off the highway.
## Run: godot --headless -s tests/test_local_supply.gd


func _init() -> void:
	var sim := _town()
	var edge := _concrete_from(sim)
	# (From the highway it may not make the pour in time at all: then none comes.)
	_check(edge == "edge" or edge == "", "with no quarry the new homes' concrete comes off the highway (%s)" % edge)

	sim = _town()
	# A sand and gravel company just across the street, its drive meeting it.
	var qid := sim.industry.add_site("ore", Vector3(30, 0, -80), Vector3(0, 0, 1),
		[Vector3(30, 0, -60), Vector3(30, 0, -6)])
	var src := LocalSupply.source(sim, "ready-mix concrete", Vector3.ZERO)
	_check(src.get("ref", "") == "site:%d" % qid, "the quarry is the town's ready-mix source (%s)" % str(src))
	_check(LocalSupply.source(sim, "hot-mix asphalt", Vector3.ZERO).get("ref", "") == "site:%d" % qid
		and LocalSupply.source(sim, "crushed stone", Vector3.ZERO).get("ref", "") == "site:%d" % qid,
		"and its asphalt and crushed stone")
	_check(LocalSupply.source(sim, "ready-mix concrete", Vector3(30 + 30_000, 0, 0)).is_empty(),
		"ready-mix doesn't go farther than a 90-minute haul")
	_check(LocalSupply.source(sim, "building crew", Vector3.ZERO).is_empty(), "a crew isn't a material")
	_check(LocalSupply.source(sim, "posts and trusses", Vector3.ZERO).is_empty(),
		"no sawmill in town: lumber still comes from outside")
	var cash0 := float(sim.industry.sites[qid].cash)
	# A home going up orders a truck of ready-mix (with all the time it
	# needs: in play a pour waits for no one, so only a near plant makes it).
	for i in 60:
		sim.tick()
	var ref := ""
	for r in sim.construction.sites:
		if not sim.construction.is_done(r, sim.tick_count):
			ref = r
			break
	sim.construction._budget = 4
	sim.construction._deliver(sim, ref, sim.construction.sites[ref], "concrete_mixer", "ready-mix concrete",
		sim.tick_count + 100_000)
	var from := ""
	for id in sim.construction.trips:
		var t: Dictionary = sim.construction.trips[id]
		if t.ref == ref and t.cargo == "ready-mix concrete":
			from = str(t.get("src", {}).get("ref", "edge"))
	_check(from == "site:%d" % qid, "the concrete truck comes from the quarry (%s)" % from)
	# Let it arrive and unload.
	var arrived := false
	var went_back := false
	for i in 4000:
		sim.tick()
		for p in sim.construction.sites.get(ref, {}).get("parked", []):
			if p.cargo == "ready-mix concrete":
				arrived = true
				sim.construction._budget = 4
				sim.construction._leave(sim, ref, "delivery")
		for id in sim.construction.trips:
			var t: Dictionary = sim.construction.trips[id]
			if not t.inbound and t.kind == "concrete_mixer":
				went_back = true
		if went_back:
			break
	_check(arrived and int(sim.construction.local_loads.get("ready-mix concrete", 0)) >= 1,
		"the load counts as local (%s)" % str(sim.construction.local_loads))
	_check(float(sim.industry.sites[qid].cash) >= cash0 + Balance.LOCAL_SUPPLY_PRICE["ready-mix concrete"] - 0.5,
		"the quarry is paid for it (%d -> %d)" % [cash0, sim.industry.sites[qid].cash])
	_check(went_back and LocalSupply.home(sim, {"ref": "site:%d" % qid}).get("ref", "") == "site:%d" % qid,
		"the empty mixer drives back to the quarry")
	# Saved and loaded, the tally stays.
	var c2 := Construction.new()
	c2.from_dict(JSON.parse_string(JSON.stringify(sim.construction.to_dict())))
	_check(c2.local_loads == sim.construction.local_loads, "the local tally is saved")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _town() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_county_road", "a": [-60, 0], "b": [-60, -100], "links": [1]})
	sim.apply({"type": "build_road", "start": [-60, 0], "ctrl": [100, 0], "end": [260, 0]})
	# A street of new homes, with no builder's yard in town: each one's
	# concrete truck comes from a supplier.
	for x in range(-40, 241, 10):
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	return sim


## Where the first new home's concrete set out from ("" if none came).
func _concrete_from(sim: CitySim) -> String:
	for i in 3000:
		sim.tick()
		for id in sim.construction.trips:
			var t: Dictionary = sim.construction.trips[id]
			if t.inbound and t.cargo == "ready-mix concrete":
				return str(t.get("src", {}).get("ref", "edge"))
	return ""


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
