extends SceneTree
## A park with a quiet dead-end street beside it asks the player (the
## permits bell) to have the town close the street; a no leaves it, a yes
## takes the street up and the park grows across it. A through street with
## no other way round is never asked for.

var failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	var site := Parks.site_near(sim.network, "park", Vector3(0, 0, 40))
	_check(sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}),
		"park placed")
	var pid: int = sim.parks.sites.keys()[0]
	var park: Dictionary = sim.parks.sites[pid]
	var dir: Vector3 = park.dir
	var pos: Vector3 = park.pos
	var side := Vector3(-dir.z, 0.0, dir.x)
	var back := -dir  # away from the main road
	var half: float = park.size.x * 0.5
	var row := RoadStyle.right_of_way_half(RoadStyle.Type.STREET)
	var off := half + row + 2.0
	var front: Vector3 = pos + dir * park.size.y * 0.5
	var rear: Vector3 = pos + back * (park.size.y * 0.5 + row + 3.0)
	# A dead-end street on one side, part way back.
	var a0 := front - side * off
	a0 = Vector3(a0.x, 0, 0.0)
	var a1: Vector3 = pos - side * off + back * park.size.y * 0.3
	_check(sim.apply({"type": "build_road", "start": [a0.x, a0.z], "ctrl": [(a0.x + a1.x) * 0.5, (a0.z + a1.z) * 0.5],
		"end": [a1.x, a1.z], "road": RoadStyle.Type.STREET}), "a dead-end street beside the park")
	# A through street on the other, joined to an avenue behind the park.
	var b0 := front + side * off
	b0 = Vector3(b0.x, 0, 0.0)
	var b1 := rear + side * off
	sim.apply({"type": "build_road", "start": [b0.x, b0.z], "ctrl": [(b0.x + b1.x) * 0.5, (b0.z + b1.z) * 0.5],
		"end": [b1.x, b1.z], "road": RoadStyle.Type.STREET})
	var c1 := rear - side * (off + 40.0)
	sim.apply({"type": "build_road", "start": [b1.x, b1.z], "ctrl": [(b1.x + c1.x) * 0.5, (b1.z + c1.z) * 0.5],
		"end": [c1.x, c1.z], "road": RoadStyle.Type.AVENUE})
	sim.tick()
	park = sim.parks.sites[pid]
	var size0: Vector2 = park.size
	var stub: int = sim.network.find_segment_near(park.pos - side * off, row).get("seg", -1)
	var through: int = sim.network.find_segment_near(park.pos + side * off, row).get("seg", -1)
	_check(stub != -1 and through != -1 and stub != through, "both side streets found (%d, %d)" % [stub, through])
	var step := Balance.PARK_GROW_STEP
	var right := Parks.corners(park.pos + side * (park.size.x + step) * 0.5, park.dir, Vector2(step, park.size.y))
	_check(sim.parks.closable_street(sim, pid, right) == -1, "a through street with no other way round can't be closed")
	var grew := sim.parks._grow(sim, pid, Vector2(park.size.x + 10.0, 0.0))
	var ask: Dictionary = park.get("ask", {})
	_check(not grew and int(ask.get("seg", -1)) == stub and sim.permits.state_of(int(ask.get("req", -1))) == Permits.State.OPEN,
		"boxed in, the park board asks to close the dead-end street (%s)" % str(ask))
	if ask.is_empty():
		_finish()
		return
	sim.apply({"type": "permit", "id": int(ask.req), "answer": "deny"})
	sim.parks._answer(sim, pid)
	_check(sim.network.segments.has(stub) and park.size == size0, "a no leaves the street and the park as they were")
	sim.tick_count += Permits.DENY_WAIT + 10
	sim.parks._grow(sim, pid, Vector2(park.size.x + 10.0, 0.0))
	ask = park.get("ask", {})
	_check(int(ask.get("seg", -1)) == stub, "it asks again after a while")
	if not ask.is_empty():
		var money := sim.economy.money
		sim.apply({"type": "permit", "id": int(ask.req), "answer": "approve"})
		sim.parks._answer(sim, pid)
		_check(not sim.network.segments.has(stub), "a yes takes the street up")
		_check(park.size.x > size0.x, "and the park grows across it (%.0f to %.0f m wide)" % [size0.x, park.size.x])
		_check(sim.economy.money < money, "the town paid for the strip")
		_check(sim.network.segments.has(through), "the through street stays")
	# A save keeps an open street ask.
	park.ask = {"req": 99, "side": "left", "seg": 7}
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(int(copy.parks.sites[pid].get("ask", {}).get("seg", -1)) == 7, "a save keeps the board's open street ask")
	_finish()


func _finish() -> void:
	print("ALL TESTS PASSED" if not failed else "SOME TESTS FAILED")
	quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	failed = failed or not ok
