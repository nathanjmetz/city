extends SceneTree
## Run: godot --headless -s tests/test_road_variants.gd
## The road variants in each road menu: sizes that add up, every one
## buildable, drawable, drivable and saved by its number.

func _init() -> void:
	# Saves store types by number: the original seven never move.
	_check(RoadStyle.Type.STREET == 0 and RoadStyle.Type.RAMP == 4 and RoadStyle.Type.RING2 == 6, "old type numbers kept")
	_check(RoadStyle.TYPES.size() == RoadStyle.Type.size(), "one spec per type")
	for g in RoadStyle.GROUPS:
		var v := RoadStyle.variants(g)
		_check(v[0] == g and v.size() >= 2, "%s menu starts with itself and has variants %s" % [RoadStyle.TYPES[g].name, v])

	var mats := {}
	for key in ["asphalt", "curb", "walk", "median", "yellow", "white", "gravel", "concrete"]:
		mats[key] = StandardMaterial3D.new()
	var line := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -60), Vector3(0, 0, -120)])
	for t in RoadStyle.TYPES.size():
		var spec: Dictionary = RoadStyle.TYPES[t]
		_check(Economy.BUILD_PER_M.has(t), "%s has a price" % spec.name)
		if RoadStyle.is_ring(t):
			continue
		# Every lane, bike lane and parking lane fits between the curbs.
		var offs := TrafficSim.lane_offsets(t, false)
		var lane: float = TrafficSim.LANE_W if spec.get("surface", "asphalt") == "asphalt" else spec.width * 0.5
		var outer := 0.0
		for o in offs:
			outer = maxf(outer, absf(o) + lane * 0.5)
		if spec.get("bike", false):
			outer += RoadStyle.BIKE_WIDTH
		outer += RoadStyle.parking_width(t)
		_check(outer <= RoadStyle.half_width(t) + 0.15, "%s: lanes fit its %.1f m (need %.1f each side)" % [
			spec.name, spec.width, outer])
		var expect: int = spec.lanes if spec.oneway else spec.lanes / 2
		_check(offs.size() == expect, "%s: %d lanes each way" % [spec.name, expect])
		_check(RoadMesh.street(line, t, mats).get_surface_count() > 0, "%s draws" % spec.name)

	# Each variant builds, drives and survives a save.
	var sim := CitySim.new()
	sim.economy.money = 1e9
	var x := 0.0
	for t in RoadStyle.TYPES.size():
		if RoadStyle.is_ring(t) or t <= RoadStyle.Type.RAMP:
			continue
		_check(sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, -150], "end": [x, -300], "road": t}),
			"build a %s" % RoadStyle.TYPES[t].name)
		x += 120.0
	sim.tick()
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var types := []
	for id in copy.network.segments:
		types.append(copy.network.segments[id].type)
	types.sort()
	_check(types == range(RoadStyle.Type.STREET_NARROW, RoadStyle.TYPES.size()), "every variant saved by number")

	# A downtown one-way street drives only the way it was drawn, with
	# both lanes going that way.
	var o := CitySim.new()
	o.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0], "road": RoadStyle.Type.STREET_ONEWAY})
	o.tick()
	var a := {"seg": o.network.segments.keys()[0], "at_frac": 0.8}
	var b := {"seg": a.seg, "at_frac": 0.2}
	_check(o.traffic._route(b, a).size() > 0 and o.traffic._route(a, b).is_empty(), "one-way street drives one way")
	_check(TrafficSim.lane_offsets(RoadStyle.Type.STREET_ONEWAY, true) == PackedFloat32Array([-1.8, 1.8]),
		"one-way street lanes are centred between the parking lanes")
	_check(RoadStyle.TYPES[RoadStyle.Type.STREET_ONEWAY].lots, "homes and shops can face a one-way street")

	# A center turn lane is painted, so the through lanes sit right beside it.
	_check(TrafficSim.lane_offsets(RoadStyle.Type.AVENUE_TURN, false) == PackedFloat32Array([3.6]),
		"turn lane avenue: through lane beside the 12 ft turn lane")

	# A 2-lane ramp off a 2-lane freeway gets the full interchange drawing.
	var net := RoadNetwork.new()
	net.build_road(Vector3(-300, 0, 0), Vector3(-150, 0, 0), Vector3(0, 0, 0), RoadStyle.Type.FREEWAY2)
	net.build_road(Vector3(0, 0, 0), Vector3(150, 0, 0), Vector3(300, 0, 0), RoadStyle.Type.FREEWAY2)
	net.build_road(Vector3(0, 0, 0), Vector3(100, 0, 10), Vector3(200, 0, 60), RoadStyle.Type.RAMP2)
	var merges := RampMerge.merges(net)
	_check(merges.size() == 1 and RampMerge.ramp_cut(merges[0]) > 0.0, "2-lane ramp merges with a 2-lane freeway")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
