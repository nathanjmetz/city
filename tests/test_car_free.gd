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
	_second_reader()
	quit(1 if _failed else 0)


## Cases the second reader found (2026-10-26).
func _second_reader() -> void:
	# A road joining a car-free street mid-block: both pieces stay car-free.
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0]})
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [100, -150], "end": [200, -150]})
	sim.apply({"type": "build_road", "start": [100, 0], "ctrl": [100, -75], "end": [100, -150]})
	sim.tick()
	var rung: int = sim.network.find_segment_near(Vector3(100, 0, -75), 1.0).seg
	sim.apply({"type": "car_free", "seg": rung, "on": true})
	var money_before := sim.economy.money
	sim.apply({"type": "build_road", "start": [100, -75], "ctrl": [150, -75], "end": [200, -75]})
	var top: int = sim.network.find_segment_near(Vector3(100, 0, -30), 1.0).seg
	var bottom: int = sim.network.find_segment_near(Vector3(100, 0, -120), 1.0).seg
	_check(top != rung and bottom != rung and top != bottom, "the joining road cut the car-free street in two")
	_check(top in sim.parks.trails.plazas and bottom in sim.parks.trails.plazas and not rung in sim.parks.trails.plazas,
		"both pieces are still a plaza")
	_check(not sim.traffic.may_enter(top, false) and not sim.traffic.may_enter(bottom, false), "and both are still car-free")
	_check(not sim.traffic.closed.has(rung), "nothing left on the old piece's id")
	# Undo the joining road: the street is whole and car-free again.
	_check(sim.apply({"type": "undo"}), "the joining road is undone")
	_check(sim.network.segments.has(rung) and rung in sim.parks.trails.plazas and not sim.traffic.may_enter(rung, false),
		"the street is whole and car-free again")
	_check(not sim.traffic.closed.has(top) and not top in sim.parks.trails.plazas, "and the pieces' ids are cleared")
	_check(is_equal_approx(sim.economy.money, money_before),
		"undo gives back the road's cost only, not the old plaza's pavers ($%d, was $%d)" % [sim.economy.money, money_before])

	# Build a street, make it car-free, undo the street: the next road
	# built (which gets the same id) is open to cars.
	var u := CitySim.new()
	u.economy.money = 10_000_000
	u.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0]})
	u.apply({"type": "build_road", "start": [0, -100], "ctrl": [100, -100], "end": [200, -100]})
	var seg: int = u.network.find_segment_near(Vector3(100, 0, -100), 1.0).seg
	u.apply({"type": "car_free", "seg": seg, "on": true})
	var paid := u.economy.money
	var pavers := 0
	_check(u.apply({"type": "undo"}), "the car-free street is undone")
	pavers = int(u.economy.money - paid)
	_check(not u.network.segments.has(seg), "the street is gone")
	_check(not u.traffic.closed.has(seg) and not seg in u.parks.trails.plazas, "and so is its closure")
	_check(pavers > u.car_free_cost(-1) and pavers >= 30000, "the pavers come back with the road's refund ($%d)" % pavers)
	u.apply({"type": "build_road", "start": [0, -100], "ctrl": [100, -100], "end": [200, -100]})
	var again: int = u.network.find_segment_near(Vector3(100, 0, -100), 1.0).seg
	_check(u.traffic.may_enter(again, false) and not again in u.parks.trails.plazas,
		"the next road built there is open to cars (id %d, was %d)" % [again, seg])

	# Move It: a car-free dead end dragged across a street is rebuilt to
	# meet it, and stays car-free.
	var m := CitySim.new()
	m.economy.money = 10_000_000
	m.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	m.apply({"type": "build_road", "start": [0, 200], "ctrl": [0, 150], "end": [0, 100]})
	m.apply({"type": "build_road", "start": [-100, 200], "ctrl": [0, 200], "end": [100, 200]})
	var spur: int = m.network.find_segment_near(Vector3(0, 0, 150), 1.0).seg
	_check(m.apply({"type": "car_free", "seg": spur, "on": true}), "a dead-end street made car-free")
	var end_node := m.network.find_node_near(Vector3(0, 0, 100), 1.0)
	_check(m.apply(MoveIt.command([{"type": "node", "id": end_node}], Vector3(0, 0, 100), Vector3(0, 0, -140))),
		"its end drags across the street")
	var pieces := [m.network.find_segment_near(Vector3(0, 0, 100), 1.0).seg, m.network.find_segment_near(Vector3(0, 0, -20), 1.0).seg]
	var all_closed := true
	for piece in pieces:
		if m.traffic.may_enter(int(piece), false) or not int(piece) in m.parks.trails.plazas:
			all_closed = false
	_check(all_closed, "moved and rebuilt, it's still car-free (pieces %s)" % [pieces])

	# Bridges and tunnels stay open to cars.
	var b := CitySim.new()
	b.economy.money = 10_000_000
	b.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -60], "end": [0, -120, 7.5]})
	b.apply({"type": "build_road", "start": [0, -120, 7.5], "ctrl": [0, -180, 7.5], "end": [0, -240, 7.5]})
	var deck: int = b.network.find_segment_near(Vector3(0, 7.5, -180), 1.0).seg
	_check(b.car_free_problem(deck) == "Bridges and tunnels can't be car-free.", "a bridge can't be car-free (%s)" % b.car_free_problem(deck))
	_check(not b.apply({"type": "car_free", "seg": deck, "on": true}), "and the command says no")


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
