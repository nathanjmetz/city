extends SceneTree
## Run: godot --headless -s tests/test_ambient_people.gd
## AmbientLife's people on the street: the school's crossing guard on the
## corner by the doors, riders waiting at a bus stop, and porch sitters in
## the seated pose, and people standing about who shift their weight.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.charter.reached.merge({"town": 0, "city": 0})
	for z in [0, 200]:
		sim.apply({"type": "build_road", "start": [-300, z], "ctrl": [0, z], "end": [300, z]})
	for x in [-250, 0, 250]:
		sim.apply({"type": "build_road", "start": [x, -200], "ctrl": [x, 100], "end": [x, 400]})
	sim.economy.money = 50_000_000
	var site := Services.site_near(sim.network, Services.Kind.SCHOOL, Vector3(-125, 0, 40))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.SCHOOL, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a school is placed")
	var al := AmbientLife.new()
	al.setup(sim, StandardMaterial3D.new())
	var id: int = sim.services.buildings.keys()[0]
	var spot := al._guard_spot(id, sim.services.buildings[id])
	_check(not spot.is_empty(), "the school has a crossing guard's corner")
	if not spot.is_empty():
		var off := sim.network.find_segment_near(spot.at, 50.0)
		var hw := RoadStyle.half_width(sim.network.segments[off.seg].type)
		_check(float(off.dist) > hw, "the guard waits off the road (%.1f m from the centre line)" % float(off.dist))
		var mid: Vector3 = spot.at + spot.face * float(spot.reach)
		_check(sim.network.find_segment_near(mid, 50.0).dist < 1.0, "and walks out to the middle of the street")
		var people := []
		var props := {"paddle": [], "paddle_pole": []}
		al._guard_scene(people, props, {"spot": spot, "seed": 3})
		_check(people.size() == 1 and props.paddle.size() == 1, "one guard with a STOP paddle")
	# A bus stop with riders: they wait there, standing or on the bench.
	var st := {"pos": Vector3(-100, 0, 6), "dir": Vector3(1, 0, 0), "side": 1.0}
	var waiting := []
	al._stop_scene(waiting, {"stop": st, "n": 4, "seed": 9, "shelter": true})
	_check(waiting.size() == 4, "four riders wait at the stop")
	var seated := 0
	for p in waiting:
		if int((p[1] as Color).a) & WalkerView.SEATED:
			seated += 1
		_check((p[0] as Transform3D).origin.distance_to(Terrain.stand(st.pos)) < 8.0, "each by the stop")
	_check(seated == 3, "three on the shelter's bench (%d)" % seated)
	# Standing about they shift their weight; talking, they talk with their
	# hands; sitting or walking, neither.
	for p in waiting:
		var bits := int((p[1] as Color).a)
		_check(bool(bits & WalkerView.STANDING) != bool(bits & WalkerView.SEATED) and not bits & WalkerView.TALKING,
			"a rider %s" % ("sits still" if bits & WalkerView.SEATED else "shifts their weight"))
	# Most riders standing at the stop are on their phones.
	var crowd := []
	al._stop_scene(crowd, {"stop": st, "n": 6, "seed": 21, "shelter": false})
	var phones := crowd.filter(func(p): return int((p[1] as Color).a) & WalkerView.PHONE).size()
	_check(phones >= 2 and phones < 6, "most riders standing wait looking at their phones (%d of 6)" % phones)
	var two := []
	al._person(two, Vector3.ZERO, Vector3.FORWARD, 5, -1.0, 1.0, false, 0.0, WalkerView.TALKING)
	al._person(two, Vector3(3, 0, 0), Vector3.FORWARD, 6, 2.5)
	_check(int((two[0][1] as Color).a) & WalkerView.TALKING, "neighbours talking talk with their hands")
	_check(not int((two[1][1] as Color).a) & (WalkerView.STANDING | WalkerView.TALKING), "someone walking neither")
	al.free()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
