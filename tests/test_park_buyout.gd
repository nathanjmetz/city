extends SceneTree
## A park hemmed in by homes asks the player (the permits bell) to buy the
## lots next door; a no leaves them, a yes clears them and the park grows.

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
	# A street behind the park too, so it can only grow sideways.
	var back: float = park.pos.z + park.size.y * 0.5 + 8.0
	sim.apply({"type": "build_road", "start": [-300, back], "ctrl": [0, back], "end": [300, back]})
	# Homes on every lot along the street beside it.
	var seg: int = sim.network.find_segment_near(Vector3(0, 0, 0), 5.0).seg
	for side in [-1, 1]:
		sim.apply({"type": "zone_frontage", "seg": seg, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	sim.tick()
	var homes := 0
	for key in sim.lots:
		sim.buildings[key] = {"zone": ZoneMap.Zone.RESIDENTIAL, "seed": 1, "built": 0, "cap": 3, "occ": 3}
		homes += 1
	_check(homes > 0, "homes along the street (%d)" % homes)
	var size0: Vector2 = park.size
	# Wider than it is: only the sides can give it room, and homes stand there.
	var grew := sim.parks._grow(sim, pid, Vector2(park.size.x + 10.0, 0.0))
	var ask: Dictionary = park.get("ask", {})
	_check(not grew and not ask.is_empty() and sim.permits.state_of(int(ask.req)) == Permits.State.OPEN,
		"hemmed in by homes, the park board asks to buy lots next door (%s)" % str(ask))
	if ask.is_empty():
		_finish()
		return
	sim.apply({"type": "permit", "id": int(ask.req), "answer": "deny"})
	sim.parks._answer(sim, pid)
	_check(park.size == size0 and sim.buildings.size() == homes, "a no leaves the homes and the park as they were")
	# Later, asked again: a yes clears the lots and the park grows.
	sim.tick_count += Permits.DENY_WAIT + 10
	sim.parks._grow(sim, pid, Vector2(park.size.x + 10.0, 0.0))
	ask = park.get("ask", {})
	_check(not ask.is_empty(), "it asks again after a while")
	if not ask.is_empty():
		var money := sim.economy.money
		sim.apply({"type": "permit", "id": int(ask.req), "answer": "approve"})
		sim.parks._answer(sim, pid)
		_check(sim.buildings.size() < homes, "a yes buys the homes out (%d of %d left)" % [sim.buildings.size(), homes])
		_check(park.size.x > size0.x, "and the park grows over them (%.0f to %.0f m wide)" % [size0.x, park.size.x])
		_check(sim.economy.money < money, "the town paid for the land")
	# A save keeps an open ask.
	park.ask = {"req": 99, "side": "left"}
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(int(copy.parks.sites[pid].get("ask", {}).get("req", -1)) == 99, "a save keeps the board's open ask")
	_finish()


func _finish() -> void:
	print("ALL TESTS PASSED" if not failed else "SOME TESTS FAILED")
	quit(1 if failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	failed = failed or not ok
