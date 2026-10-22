extends SceneTree
## Run: godot --headless -s tests/test_sim.gd

func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	_check(sim.lots.size() >= 16, "lots along a 200 m road (got %d)" % sim.lots.size())
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		var d := absf(lot.pos.z)
		_check(d > RoadStyle.right_of_way_half() + 10.0, "lot %s sits back from the road" % key)
		break
	# Nothing grows until zoned.
	for i in 40:
		sim.tick()
	_check(sim.buildings.is_empty(), "no buildings without zones")
	# Zone the north side as homes, the south side as industry.
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	var zoned := sim.empty_zoned_lots().size()
	_check(zoned == sim.lots.size(), "every lot zoned (%d of %d)" % [zoned, sim.lots.size()])
	for i in 400:
		sim.tick()
	_check(sim.buildings.size() == sim.lots.size(), "buildings grow on every zoned lot")
	_check(sim.count_buildings(ZoneMap.Zone.RESIDENTIAL) > 0 and sim.count_buildings(ZoneMap.Zone.INDUSTRIAL) > 0,
		"both zone types grew")
	# Dezoning removes buildings.
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.NONE})
	_check(sim.count_buildings(ZoneMap.Zone.INDUSTRIAL) == 0, "dezoning removes industry")
	# Same commands give the same city (needed for multiplayer).
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.buildings.size() == sim.buildings.size(), "save round trip keeps buildings")
	_check(copy.zones.cells.size() == sim.zones.cells.size(), "save round trip keeps zones")
	for i in 20:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.to_dict()) == JSON.stringify(sim.to_dict()), "copies stay in sync")
	# A crossing road removes the lots it runs through.
	sim.apply({"type": "build_road", "start": [0, -100], "ctrl": [0, 0], "end": [0, 100]})
	for key in sim.buildings:
		_check(absf(sim.lots[key].pos.x) > 5.0, "no building left on the new road")
	# Old saves (roads only) come back zoned as homes.
	var old := CitySim.new()
	old.from_dict({"version": 1, "next_id": 4, "nodes": {"1": [-100, 0], "2": [100, 0]},
		"segments": {"3": [1, 2, 0, 0]}})
	_check(old.empty_zoned_lots().size() == old.lots.size() and old.lots.size() > 0, "old saves get zoned")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	elif not what.begins_with("lot ") and not what.begins_with("no building left"):
		print("PASS " + what)
