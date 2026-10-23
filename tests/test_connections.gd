extends SceneTree
## Run: godot --headless -s tests/test_connections.gd
## A selected home links to where its people work, and a workplace to where
## its staff live (ConnectionLines).

func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	for x in range(-200, 201, 8):
		sim.apply({"type": "paint_zone", "center": [x, -22], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 22], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in 4000:
		sim.tick()
	var home := ""
	var work := ""
	for p in sim.people.people.values():
		if p.job.begins_with("lot:") and sim.lots.has(p.home) and sim.lots.has(p.job.substr(4)):
			home = p.home
			work = p.job.substr(4)
			break
	_check(home != "", "someone lives and works in town")
	if home != "":
		var from_home := ConnectionLines.ends(sim, {"type": "lot", "id": home})
		_check(not from_home.is_empty(), "a home links to where its people work (%d)" % from_home.size())
		_check(from_home.any(func(v): return v.is_equal_approx(sim.lots[work].pos)), "including that job")
		var from_work := ConnectionLines.ends(sim, {"type": "lot", "id": work})
		_check(from_work.any(func(v): return v.is_equal_approx(sim.lots[home].pos)), "a workplace links back to that home")
		_check(from_work.size() <= ConnectionLines.MAX_LINES, "never more than %d arcs" % ConnectionLines.MAX_LINES)
	_check(ConnectionLines.ends(sim, {"type": "road", "id": 1}).is_empty(), "a road has no arcs")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
