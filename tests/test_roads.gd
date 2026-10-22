extends SceneTree
## Run: godot --headless -s tests/test_roads.gd

func _init() -> void:
	var net := RoadNetwork.new()
	net.build_road(Vector3(-100, 0, 0), Vector3(0, 0, 0), Vector3(100, 0, 0))
	_check(net.segments.size() == 1, "one straight road")
	# A road crossing the middle makes a 4-way junction.
	net.build_road(Vector3(0, 0, -100), Vector3(0, 0, 0), Vector3(0, 0, 100))
	_check(net.segments.size() == 4, "crossing splits both roads (got %d)" % net.segments.size())
	_check(net.nodes.size() == 5, "five nodes (got %d)" % net.nodes.size())
	# Ending on an existing road makes a T junction.
	net.build_road(Vector3(50, 0, 80), Vector3(50, 0, 40), Vector3(50, 0, 0))
	_check(net.segments.size() == 6, "T junction (got %d)" % net.segments.size())
	# Save and load round trip.
	var copy := RoadNetwork.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(net.to_dict())))
	_check(copy.segments.size() == net.segments.size(), "save round trip")
	net.remove_segment(net.segments.keys()[0])
	_check(net.segments.size() == 5, "bulldoze")
	# Street corners (Junction): a crossroads gets four curb returns and its
	# roads stop short of it; a straight run through a node stays plain.
	var town := RoadNetwork.new()
	town.build_road(Vector3(-100, 0, 0), Vector3(0, 0, 0), Vector3(100, 0, 0))
	town.build_road(Vector3(0, 0, -100), Vector3(0, 0, 0), Vector3(0, 0, 100))
	town.build_road(Vector3(100, 0, 0), Vector3(150, 0, 0), Vector3(200, 0, 0))
	var plans := Junction.plan(town)
	var cross := town.find_node_near(Vector3.ZERO, 1.0)
	_check(plans.has(cross) and plans[cross].corners.filter(func(c): return c.fillet).size() == 4,
		"crossroads gets four curb returns")
	var trims: Array = plans.get(cross, {}).get("trim", {}).values()
	_check(not trims.is_empty() and trims.all(func(t): return t > 4.0 and t < 15.0), "roads stop at the corners (%s)" % [trims])
	_check(not plans.has(town.find_node_near(Vector3(100, 0, 0), 1.0)), "straight run stays plain")
	# A sharp Y still makes one clean outline.
	town.build_road(Vector3(-100, 0, 0), Vector3(-140, 0, 60), Vector3(-170, 0, 130))
	town.build_road(Vector3(-100, 0, 0), Vector3(-80, 0, 70), Vector3(-75, 0, 140))
	plans = Junction.plan(town)
	_check(plans.has(town.find_node_near(Vector3(-100, 0, 0), 1.0)), "sharp Y junction is shaped")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
