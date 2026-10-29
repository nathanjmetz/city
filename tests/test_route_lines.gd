extends SceneTree
## Run: godot --headless -s tests/test_route_lines.gd
## Show routes (Brawn's pick, Cities: Skylines' route view): select a road,
## a place or a vehicle and the trips using it are drawn on their streets,
## ahead to where they're going and back to where they set off.

func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-150, 0], "end": [0, 0]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 150], "end": [0, 300]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [150, 0], "end": [300, 0]})
	var t := sim.traffic
	var vid := t.dispatch({"ref": "yard", "pos": [-280, 12]}, {"ref": "site", "pos": [12, 280]}, "construction", {}, "pickup")
	_check(vid != -1, "a pickup is sent across town")
	var car := {}
	for i in 3000:
		sim.tick()
		var f := t.find_vehicle(vid)
		if f.get("state", "") == "driving" and f.car.j == null and int(f.car.route[f.car.leg]) / 2 != _seg_of(sim, Vector3(-150, 0, 0)):
			car = f.car
			break
	_check(not car.is_empty(), "it drives round the corner")
	if car.is_empty():
		quit(1)
		return
	var runs := t.trip_runs(car)
	_check(not runs.ahead.is_empty(), "the route ahead is known (%d ways)" % runs.ahead.size())
	_check(not runs.came.is_empty(), "the way it came is planned from where it set off (%d ways)" % runs.came.size())
	var first := t.way_line(int(runs.came[0][0]), float(runs.came[0][1]), float(runs.came[0][2]))
	_check(first.size() >= 2 and first[0].x < -200.0, "the way it came starts back at the yard (x %.0f)" % first[0].x)
	var last: Array = runs.ahead[runs.ahead.size() - 1]
	var end := t.way_line(int(last[0]), float(last[1]), float(last[2]))
	_check(end[end.size() - 1].z > 200.0, "the route ahead ends by the site (z %.0f)" % end[end.size() - 1].z)

	var on_road := RouteLines.trips(sim, {"type": "road", "id": int(car.route[car.leg]) / 2})
	_check(on_road.has(car), "selecting the road it's on shows its trip")
	var other := _seg_of(sim, Vector3(150, 0, 0))
	_check(not RouteLines.trips(sim, {"type": "road", "id": other}).has(car), "a road it never takes doesn't")
	_check(RouteLines.trips(sim, {"type": "vehicle", "id": vid}) == [car], "selecting the vehicle shows its own trip")
	car.to_ref = "svc:7@2"
	_check(RouteLines.trips(sim, {"type": "service", "id": 7}).has(car), "selecting where it's going shows its trip")
	_check(not RouteLines.trips(sim, {"type": "service", "id": 8}).has(car), "another place doesn't")
	_check(RouteLines.colour(car) == RouteLines.CAR, "a pickup is drawn as a car")

	var lines := RouteLines.new()
	lines.sim = sim
	lines.show_for({"type": "vehicle", "id": vid})
	_check(lines._mesh.get_surface_count() == 1, "its route is drawn")
	# A street the trip came along taken away (a park vacating it, say):
	# the lines carry on from what's left, nothing breaks.
	var came_seg := int(runs.came[0][0]) / 2
	sim.apply({"type": "remove_road", "seg": came_seg})
	lines.show_for({"type": "vehicle", "id": vid})
	_check(not sim.network.segments.has(came_seg) and int(lines._came.get(vid, [[0, "", -1]])[0][2]) == sim.network.revision,
		"a road removed under the route: the way it came is planned again")
	lines.show_for({})
	_check(lines._mesh.get_surface_count() == 0, "clearing the selection clears the lines")
	lines.free()
	quit(1 if _failed else 0)


func _seg_of(sim: CitySim, p: Vector3) -> int:
	return int(RoadIndex.segment_near(sim.network, p, 20.0, 4.0).get("seg", -1))


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
