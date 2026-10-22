extends SceneTree
## Run: godot --headless -s tests/test_airport.gd

var _fails := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 5_000_000
	sim.apply({"type": "build_road", "start": [-1500, 0], "ctrl": [0, 0], "end": [1500, 0]})
	var corr := RoadWins.corridors(sim.network, RoadWins.BUILDING_SLACK)
	# A runway across the road can't open; one beside it can.
	var across := Airports.from_cmd({"pos": [0, 0], "dir": [0, 1], "side": 1})
	_check(sim.airports.problem(sim, across, corr).begins_with("In the way"), "a road across the runway blocks it")
	var far := Airports.from_cmd({"pos": [0, -900], "dir": [1, 0], "side": 1})
	_check(sim.airports.problem(sim, far, corr).begins_with("Needs a road"), "needs a road near its hangars")
	var cmd := {"type": "place_airport", "pos": [0, -150], "dir": [1, 0], "side": 1}
	_check(sim.airports.problem(sim, Airports.from_cmd(cmd), corr) == "", "beside the road it can open")
	var money := sim.economy.money
	_check(sim.apply(cmd), "airport placed")
	_check(sim.economy.money == money - Balance.AIRPORT_COST, "the player paid for it")
	var id: int = sim.airports.sites.keys()[0]
	var a: Dictionary = sim.airports.sites[id]
	_check(not a.drive.is_empty(), "it has an access road")
	_check(Airports.runway_name(a) == "9/27", "an east-west runway is 9/27 (got %s)" % Airports.runway_name(a))
	# FAA sizes: 2,500 ft runway, protection zones off both ends.
	_check(absf(Airports.half_len(0) * 2.0 - 762.0) < 1.0, "grass strip is 2,500 ft")
	_check(sim.airports.covers(Vector3(Airports.half_len(0) + 200.0, 0, -150)), "protection zone past the runway end")
	_check(not sim.airports.owns(Vector3(Airports.half_len(0) + 200.0, 0, -150)), "but the airport doesn't own it")
	for key in sim.lots:
		_check(not sim.airports.covers(sim.lots[key].pos), "no lots on airport land")
	# A farm nearby brings a crop duster that sprays its fields in season.
	var fid := sim.farms.add_farm(Vector3(900, 0, 120), Vector3(0, 0, -1), "corn", [])
	for x in 6:
		for y in range(1, 5):
			sim.farms.farms[fid].cells.append(Vector2i(x, y))
	# A new city starts in May, crop dusting season.
	var flew := {}
	var sprayed := false
	for i in 60 * 24 * 4:
		sim.tick()
		for pid in sim.airports.planes:
			var p: Dictionary = sim.airports.planes[pid]
			if p.state == "flying":
				flew[p.flight.kind] = true
				sprayed = sprayed or p.flight.kind == "spray"
	_check(sim.airports.based(id, "duster").size() >= 1, "a crop duster is based there")
	_check(flew.has("arrive"), "planes fly in (%s)" % str(flew.keys()))
	_check(sprayed, "the duster went out to spray")
	# Flight paths start and end on the ground at the plane's spot.
	for pid in sim.airports.planes:
		var p: Dictionary = sim.airports.planes[pid]
		if p.state != "flying":
			continue
		var path := Airports.flight_path(a, p, p.flight)
		var pts: PackedVector3Array = path[0]
		if p.flight.kind != "depart":
			_check(pts[-1].distance_to(Airports.spot(a, p.spot)) < 0.1, "%s ends at its spot" % p.flight.kind)
		var pose := Airports.pose(a, p, path, sim.tick_count + 0.5)
		_check(pose.size() == 2, "a flying plane has a pose")
	# Saves round trip and copies stay in step.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.airports.sites.size() == 1 and copy.airports.planes.size() == sim.airports.planes.size(), "save keeps airports and planes")
	for i in 400:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.airports.to_dict()) == JSON.stringify(sim.airports.to_dict()), "copies fly the same planes")
	var info := sim.airports.describe(sim, id)
	_check(info.title.ends_with("Field") and info.rows.size() > 5, "selection panel describes it")
	# The road wins: a road across the strip closes it and pays it back.
	money = sim.economy.money
	sim.apply({"type": "build_road", "start": [0, -400], "ctrl": [0, -300], "end": [0, -130]})
	_check(sim.airports.sites.is_empty(), "a road across the runway closes the airport")
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
