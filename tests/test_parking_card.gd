extends SceneTree
## Hovering a parking lot shows its card (Game critic round 28): stalls and
## upkeep, not a service's road reach.
## Run: godot --headless -s tests/test_parking_card.gd

var _fails := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	var shown := 0
	for kind in Services.PARKING:
		if not sim.apply({"type": "place_service", "kind": kind, "pos": [0, 40], "dir": [0, -1]}):
			continue
		var id: int = sim.services.buildings.keys()[-1]
		var card := Inspect._service(sim, id)
		var stalls := false
		for r in card.rows:
			stalls = stalls or r[0] == "Stalls"
		_check(stalls, "%s's card lists its stalls" % card.title)
		shown += 1
		sim.apply({"type": "remove_service", "id": id})
	_check(shown >= 3, "parking lots are placed and described (%d)" % shown)
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)
