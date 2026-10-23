extends SceneTree
## Run: godot --headless -s tests/test_pollution.gd
## Pollution you can trace: smoke drifts downwind, noise fades with distance,
## dirty ground seeps downhill, every spot names its sources and their
## shares, land value and homes react, owners save for cleaner equipment,
## and the player's fixes (noise walls, helping pay) work.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	for x in range(-600, 601, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12,
			"zone": ZoneMap.Zone.INDUSTRIAL if x > 200 else ZoneMap.Zone.RESIDENTIAL})
	sim.simulate_traffic = false
	for i in 4000:
		sim.tick()
	var factories := 0
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.INDUSTRIAL:
			factories += 1
	_check(factories > 0, "factories grew (%d)" % factories)
	var pol := sim.pollution
	pol.rebuild(sim)
	var fref := ""
	for ref in pol.sources:
		if ref.begins_with("lot:"):
			fref = ref
			break
	_check(fref != "", "each factory is a pollution source")
	var f: Dictionary = pol.sources[fref]
	_check(f.name != "" and f.name != "Factory", "a factory has its own name (%s)" % f.name)

	# Smoke drifts with the wind: from the southwest toward the northeast.
	var w := Pollution.wind()
	_check(w.x > 0.6 and w.y < -0.6, "the wind blows toward the northeast (north is -z)")
	var down := pol.source_at(f, f.center + Vector3(w.x, 0, w.y) * 400.0).x
	var up := pol.source_at(f, f.center - Vector3(w.x, 0, w.y) * 400.0).x
	_check(down > 1.0 and down > up * 5.0, "smoke drifts downwind (%.2f downwind vs %.2f upwind)" % [down, up])

	# Noise from a point: about 6 dB quieter for each doubling of distance.
	var side := Vector3(-w.y, 0, w.x)
	var n50 := Pollution.db(pol.source_at(f, f.center + side * 50.0).y)
	var n100 := Pollution.db(pol.source_at(f, f.center + side * 100.0).y)
	_check(absf((n50 - n100) - 6.0) < 1.0, "noise drops about 6 dB per doubling (%.1f -> %.1f)" % [n50, n100])

	# A highway: about 77 dB beside it, 3 dB less per doubling (a line).
	sim.apply({"type": "build_road", "start": [-3000, 3000], "ctrl": [-2000, 3000], "end": [-1000, 3000], "road": RoadStyle.Type.HIGHWAY})
	pol.rebuild(sim)
	var href := ""
	for ref in pol.sources:
		if pol.sources[ref].kind == "highway":
			href = ref
	_check(href != "", "the highway is a pollution source")
	var h15: float = pol.sample(Vector3(-2000, 0, 3015)).noise
	var h60: float = pol.sample(Vector3(-2000, 0, 3060)).noise
	_check(absf(h15 - Balance.POLLUTION_SOURCES.highway.noise) < 2.5, "a highway is about %d dB beside it (%.1f)" % [
		roundi(Balance.POLLUTION_SOURCES.highway.noise), h15])
	_check(absf((h15 - h60) - 6.0) < 1.5, "highway noise drops about 3 dB per doubling (%.1f -> %.1f)" % [h15, h60])
	var by: Array = pol.sample(Vector3(-2000, 0, 3030)).by.noise
	_check(not by.is_empty() and by[0][0] == href and by[0][1] > 0.95, "the noise beside it is traced to the highway")

	# Any spot names its sources, with shares that add up.
	var spot: Vector3 = f.center + Vector3(w.x, 0, w.y) * 150.0
	var s := pol.sample(spot)
	var total := 0.0
	for e in s.by.smoke:
		total += e[1]
	_check(not s.by.smoke.is_empty() and absf(total - 1.0) < 0.001, "smoke shares add to 100%")
	var d := Inspect.describe(sim, {"type": "spot", "id": [spot.x, spot.z]})
	_check(d.title == "Pollution here" and d.rows.size() >= 2, "clicking a spot shows its pollution")
	var go := false
	for a in d.actions:
		go = go or (a.has("go") and a.go.type == "lot")
	_check(go, "a polluted spot has a Go to button for its source")

	# Homes near the factories are worth less, and say who's to blame.
	pol.rebuild(sim)
	pol.measure_lots(sim)
	var worst_key := ""
	var worst := 1.0
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			var lf := pol.lot_factor(sim, key)
			if lf < worst:
				worst = lf
				worst_key = key
	_check(worst < 0.97, "a home near the factories is worth less (%.3f)" % worst)
	var far_key := ""
	for key in sim.buildings:
		if sim.lots[key].pos.x < -500:
			far_key = key
	_check(far_key == "" or pol.lot_factor(sim, far_key) > 0.99, "a home far upwind is not")
	var home := Inspect.describe(sim, {"type": "lot", "id": worst_key})
	_check(home.rows.any(func(r): return r[0] in ["Smoke", "Noise", "Dirty ground"]), "a home lists its pollution")
	var named := false
	for p in home.problems:
		for ref in pol.sources:
			named = named or p.contains(pol.sources[ref].name)
	_check(named, "a hurt home names the source behind it")
	_check(not pol.hurts.is_empty(), "sources know how many homes they hurt")

	# A source panel says who it hurts and how to fix it.
	var fd := Inspect.describe(sim, f.select)
	_check(fd.title == f.name, "the factory panel uses its name")
	_check(fd.rows.any(func(r): return r[0] == "Homes it hurts"), "a source says how many homes it hurts")
	_check(fd.notes.size() >= 2, "a source lists ways to fix it (%d)" % fd.notes.size())
	_check(fd.actions.any(func(a): return a.has("cmd") and a.cmd.type == "fund_cleanup"), "you can help pay for cleaner equipment")

	# Helping pay buys the next equipment, and the smoke drops.
	var before := pol.source_at(pol.sources[fref], spot).x
	var money := sim.economy.money
	var cost := pol.help_cost(fref)
	_check(sim.apply({"type": "fund_cleanup", "ref": fref}), "help pay goes through")
	_check(sim.economy.money == money - cost, "helping costs what it said ($%d)" % cost)
	var after := pol.source_at(pol.sources[fref], spot).x
	_check(after < before * 0.6, "cleaner equipment cuts the smoke (%.2f -> %.2f)" % [before, after])

	# Owners save on their own, faster with a school nearby.
	var other := ""
	for ref in pol.sources:
		if ref.begins_with("lot:") and ref != fref:
			other = ref
	if other != "":
		var slow := pol.monthly_saving(sim, pol.sources[other])
		sim.services.add(Services.Kind.SCHOOL, Vector3(300, 0, -120), Vector3(0, 0, 1))
		var fast := pol.monthly_saving(sim, pol.sources[other])
		_check(fast > slow * 1.8, "an owner with a school nearby saves more ($%d vs $%d a month)" % [fast, slow])
		for day in 40:
			pol._daily(sim)
		_check(int(pol.owners.get(other, {}).get("level", 0)) >= 1, "an owner buys cleaner equipment on their own")

	# Homes wear down in pollution.
	for day in 20:
		pol._daily(sim)
	_check(pol.wear.get(worst_key, 0.0) > 0.05, "a polluted home wears down (%.2f)" % pol.wear.get(worst_key, 0.0))

	# Noise walls on the highway.
	var wall := pol.wall_cost(sim, href)
	_check(wall > 0, "noise walls have a price ($%d)" % wall)
	money = sim.economy.money
	_check(sim.apply({"type": "noise_wall", "ref": href}), "noise walls go up")
	_check(sim.economy.money == money - wall, "walls cost what they said")
	var walled: float = pol.sample(Vector3(-2000, 0, 3015)).noise
	_check(absf((h15 - walled) - Balance.NOISE_WALL_DB) < 0.5, "walls take %d dB off (%.1f -> %.1f)" % [
		roundi(Balance.NOISE_WALL_DB), h15, walled])
	_check(pol.wall_cost(sim, href) < 0, "a walled highway can't be walled again")

	# Other systems pollute through emit(): a power plant.
	pol.emit("plant:1", {"name": "Petersburg power plant", "kind": "power plant", "points": [Vector3(4000, 0, 4000)],
		"smoke": 20.0, "noise": 70.0, "ground": 0.2, "reach": 100.0, "fixes": ["Switch it to natural gas."]})
	pol.rebuild(sim)
	var ps := pol.sample(Vector3(4000, 0, 4000) + Vector3(w.x, 0, w.y) * 300.0)
	_check(not ps.by.smoke.is_empty() and ps.by.smoke[0][0] == "plant:1", "an emitted source shows up by name")
	pol.stop("plant:1")
	pol.rebuild(sim)
	_check(not pol.sources.has("plant:1"), "stop() removes it")

	# An old coal plant: traced by name, with its own fixes; scrubbers halve the smoke.
	var pid := sim.power.add_site(Vector3(-4000, 0, 4000), Vector3(0, 0, -1), [], 0.1, 7)
	var site: Dictionary = sim.power.sites[pid]
	site.plant = "coal"
	site.cells = [Vector2i(1, 0), Vector2i(-1, 0)]
	pol.rebuild(sim)
	var downwind := Vector3(-4000, 0, 4000) + Vector3(w.x, 0, w.y) * 300.0
	var cs := pol.sample(downwind)
	_check(not cs.by.smoke.is_empty() and cs.by.smoke[0][0] == "power:%d" % pid, "coal plant smoke is traced to the plant")
	var cd := Inspect.describe(sim, {"type": "spot", "id": [downwind.x, downwind.z]})
	_check(cd.problems.any(func(p): return p.contains("scrubbers")), "the fix for coal smoke names scrubbers (%.1f ug/m3)" % cs.smoke)
	var coal_smoke: float = cs.smoke
	site.built.append("scrubbers")
	pol.rebuild(sim)
	_check(absf(pol.sample(downwind).smoke - coal_smoke * 0.5) < 0.05 * coal_smoke, "scrubbers halve the smoke")
	site.plant = "solar"
	pol.rebuild(sim)
	_check(not pol.sources.has("power:%d" % pid), "a solar farm doesn't pollute")
	sim.power.sites.erase(pid)
	pol.rebuild(sim)

	# Dirty ground seeps downhill.
	pol.height = func(p: Vector3) -> float: return -p.x * 0.05
	pol.rebuild(sim)
	var g: Dictionary = pol.sources[fref]
	var downhill := pol.source_at(g, g.center + Vector3(120, 0, 0)).z
	var uphill := pol.source_at(g, g.center - Vector3(120, 0, 0)).z
	_check(downhill > uphill * 2.0, "dirty ground seeps downhill (%.3f vs %.3f)" % [downhill, uphill])
	pol.height = Callable()

	# Saves keep walls, owners, readings and wear.
	pol.rebuild(sim)
	pol.measure_lots(sim)
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.pollution.walls.size() == pol.walls.size(), "noise walls are saved")
	_check(copy.pollution.owners.size() == pol.owners.size(), "owners' plans are saved")
	_check(is_equal_approx(snappedf(copy.pollution.lot_factor(copy, worst_key), 0.001),
		snappedf(pol.lot_factor(sim, worst_key), 0.001)), "land value is the same after loading")
	_check(copy.pollution.sources.size() == pol.sources.size(), "sources are back right after loading")

	# Saved halfway through measuring: the copy finishes the same way.
	while sim.tick_count % Pollution.UPDATE_EVERY != 3:
		sim.tick()
	var mid := CitySim.new()
	mid.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for i in 12:
		sim.tick()
		mid.tick()
	_check(JSON.stringify(mid.pollution.to_dict()) == JSON.stringify(sim.pollution.to_dict()),
		"a save made mid-measure loads and stays in step")

	# Fast enough to run every game hour.
	var t0 := Time.get_ticks_usec()
	pol.rebuild(sim)
	pol.measure_lots(sim)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  hourly pollution update: %.1f ms for %d lots, %d sources" % [ms, sim.lots.size(), pol.sources.size()])
	_check(ms < 400.0, "hourly update is quick")

	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
