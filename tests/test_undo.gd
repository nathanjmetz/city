extends SceneTree
## Run: godot --headless -s tests/test_undo.gd
## Undo the last build (Ctrl+Z): roads, a crossing that split a road, and a
## placed building come back out with a full refund.

func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	var segs := sim.network.segments.size()
	var money := sim.economy.money

	# A crossing street splits the first one; undo puts the first one back whole.
	_check(sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, 0], "end": [0, 150]}), "a crossing street is built")
	_check(sim.network.segments.size() > segs + 1, "it split the first street (%d segments)" % sim.network.segments.size())
	_check(sim.economy.money < money, "it cost money")
	_check(not sim.undo.last(sim).is_empty(), "it can be undone")
	_check(sim.apply({"type": "undo"}), "undo goes through")
	_check(sim.network.segments.size() == segs, "the first street is whole again (%d)" % sim.network.segments.size())
	_check(sim.economy.money == money, "a full refund ($%d)" % (sim.economy.money - money))

	# Two roads, two undos, back to the start.
	sim.apply({"type": "build_road", "start": [-200, 100], "ctrl": [0, 100], "end": [200, 100]})
	sim.apply({"type": "build_road", "start": [-200, -100], "ctrl": [0, -100], "end": [200, -100]})
	_check(sim.apply({"type": "undo"}) and sim.apply({"type": "undo"}), "two undos in a row")
	_check(sim.network.segments.size() == segs and sim.economy.money == money, "both roads gone, money back")
	_check(sim.apply({"type": "undo"}) and sim.network.segments.is_empty(), "a third undo takes the first street too")
	_check(not sim.apply({"type": "undo"}), "nothing left to undo")
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	money = sim.economy.money

	# A placed fire station comes back out.
	var site := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(-120, 0, 30))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a fire station is placed")
	_check(sim.services.buildings.size() == 1, "it stands")
	_check(sim.apply({"type": "undo"}), "undo the fire station")
	_check(sim.services.buildings.is_empty() and sim.economy.money == money, "gone, money back")

	# Something changed the roads since: that undo is stale and is dropped.
	sim.apply({"type": "build_road", "start": [-200, 60], "ctrl": [0, 60], "end": [200, 60]})
	sim.network.remove_segment(sim.network.segments.keys().back())
	_check(sim.undo.last(sim).is_empty(), "an undo after the roads changed some other way is dropped")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
