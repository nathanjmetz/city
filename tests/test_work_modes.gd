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

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
