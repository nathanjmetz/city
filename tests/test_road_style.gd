extends SceneTree
## A street keeps one style along its length (Brawn, 2026-10-23): a stretch
## of country road between two stretches of town street gets curbs too, a
## side street joining doesn't break the run, and a street that had curbs
## keeps them while lots are replanned.
## Run: godot --headless -s tests/test_road_style.gd

var _fails := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	# One straight street in three pieces, with a side street at a joint.
	for x in [-900, -300, 300]:
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x + 300, 0], "end": [x + 600, 0]})
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-300, -150], "end": [-300, -300]})
	# Homes zoned along the two outer pieces only.
	for x in range(-880, -620, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(620, 880, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var view := RoadView.new()
	view.network = sim.network
	view.sim = sim
	var mid := sim.network.find_segment_near(Vector3(0, 0, 0), 2.0)
	var side := sim.network.find_segment_near(Vector3(-300, 0, -200), 2.0)
	_check(not mid.is_empty() and not side.is_empty(), "the street and side street are built")
	if mid.is_empty():
		_done()
		return
	var rural := view._rural_segments()
	_check(not rural.has(int(mid.seg)), "the stretch between two town stretches is a town street too")
	_check(rural.has(int(side.seg)), "an empty side street out of town stays a country road")
	# The homes' zoning is taken off for a moment (as when lots replan):
	# the street keeps its curbs.
	for x in range(-880, -620, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.NONE})
	for x in range(620, 880, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.NONE})
	rural = view._rural_segments()
	_check(not rural.has(int(mid.seg)), "a street keeps its curbs while lots are replanned")
	view.free()
	_done()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
