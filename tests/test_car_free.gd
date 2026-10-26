extends SceneTree
## Car-free streets, like CS2's pedestrian streets (Nathan 2026-10-26: "i
## want all the same street and road options as CS2"). The player clicks a
## town street with the Car-free tool: it becomes a walking plaza, cars
## route around it, trucks still deliver at night, and a second click opens
## it to cars again.
## Run: godot --headless -s tests/test_car_free.gd

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	# A ladder: two long streets joined by three rungs, so there is a way
	# around any one rung.
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [200, 0], "end": [400, 0]})
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [200, -150], "end": [400, -150]})
	for x in [0, 200, 400]:
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, -75], "end": [x, -150]})
	sim.apply({"type": "build_road", "start": [600, 0], "ctrl": [600, -75], "end": [600, -150],
		"road": RoadStyle.Type.AVENUE})
	sim.tick()
	var rung: int = sim.network.find_segment_near(Vector3(200, 0, -75), 1.0).seg
	var avenue: int = sim.network.find_segment_near(Vector3(600, 0, -75), 1.0).seg

	_check(sim.car_free_problem(rung) == "", "a town street can be car-free (%s)" % sim.car_free_problem(rung))
	_check(sim.car_free_problem(avenue).begins_with("Only town streets"), "an avenue can't (%s)" % sim.car_free_problem(avenue))
	_check(not sim.apply({"type": "car_free", "seg": avenue, "on": true}), "the avenue stays open to cars")
	var cost := sim.car_free_cost(rung)
	_check(cost > 0, "pavers and benches cost money ($%d)" % cost)

	var money := sim.economy.money
	_check(sim.apply({"type": "car_free", "seg": rung, "on": true}), "the street is made car-free")
	_check(is_equal_approx(sim.economy.money, money - cost), "it cost what it said")
	_check(rung in sim.parks.trails.plazas, "it's drawn as a plaza")
	_check(not sim.traffic.may_enter(rung, false), "cars can't drive in")
	_check(sim.car_free_problem(rung) == "Already car-free.", "a second time it's already car-free")
	_check(not sim.apply({"type": "car_free", "seg": rung, "on": true}), "and isn't charged twice")
	sim.tick()
	# Cars from one long street to the other go round by another rung.
	var from := {"seg": sim.network.find_segment_near(Vector3(150, 0, 0), 1.0).seg, "at_frac": 0.5}
	var to := {"seg": sim.network.find_segment_near(Vector3(250, 0, -150), 1.0).seg, "at_frac": 0.5}
	var route: Array = sim.traffic._route(from, to).get("route", [])
	_check(route.size() > 0, "cars still get there")
	var uses := false
	for w in route:
		if sim.traffic.ways[int(w)].seg == rung:
			uses = true
	_check(not uses, "but not down the car-free street")

	# It survives a save.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(rung in copy.parks.trails.plazas and not copy.traffic.may_enter(rung, false), "still car-free after a load")

	# Open it again: no refund, cars come back.
	money = sim.economy.money
	_check(sim.apply({"type": "car_free", "seg": rung, "on": false}), "opened to cars again")
	_check(not rung in sim.parks.trails.plazas and sim.traffic.may_enter(rung, false), "cars may drive it again")
	_check(sim.economy.money == money, "opening it costs nothing")
	_check(not sim.apply({"type": "car_free", "seg": rung, "on": false}), "a street that's open can't be opened")

	# Not enough money: nothing happens.
	sim.economy.money = 10
	_check(not sim.apply({"type": "car_free", "seg": rung, "on": true}), "not without the money")
	_check(not rung in sim.parks.trails.plazas, "and the street stays open")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
