extends SceneTree
## Run: godot --headless -s tests/test_traffic.gd

func _init() -> void:
	# An L of streets with homes at one end and jobs at the other.
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	sim.apply({"type": "build_road", "start": [300, 0], "ctrl": [300, 150], "end": [300, 300]})
	for x in range(-300, 0, 8):
		sim.apply({"type": "paint_zone", "center": [x, -15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	for z in range(20, 300, 8):
		sim.apply({"type": "paint_zone", "center": [315, z], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
		sim.apply({"type": "paint_zone", "center": [285, z], "radius": 10, "zone": ZoneMap.Zone.COMMERCIAL})
	var t := sim.traffic
	var most := 0
	var finished := 0
	var seen := {}
	var too_close := 0
	for i in 12000:
		sim.tick()
		most = maxi(most, t.cars.size())
		var now := {}
		for car in t.cars:
			now[car.id] = true
		for id in seen:
			if not now.has(id):
				finished += 1
		seen = now
		if i % 50 == 0:
			too_close += _crowding(t)
	_check(most > 3, "cars on the road (most at once %d, pop %d)" % [most, sim.stats.population])
	_check(finished > 3, "cars finish their trips (%d)" % finished)
	_check(too_close == 0, "cars keep their distance (%d too close)" % too_close)

	# One-way: a single highway loop only drives the way it was drawn.
	var o := CitySim.new()
	o.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0], "road": RoadStyle.Type.HIGHWAY})
	o.tick()
	var lot_a := {"seg": o.network.segments.keys()[0], "at_frac": 0.8}
	var lot_b := {"seg": lot_a.seg, "at_frac": 0.2}
	_check(o.traffic._route(lot_b, lot_a).size() > 0, "can drive with the one-way")
	_check(o.traffic._route(lot_a, lot_b).is_empty(), "cannot drive against the one-way")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Cars on the same lane nearer than a car length (should never happen).
func _crowding(t: TrafficSim) -> int:
	var lanes := {}
	for car in t.cars:
		var key = TrafficSim._lane_key(car.route[car.leg])
		if not lanes.has(key):
			lanes[key] = []
		lanes[key].append(car.d)
	var bad := 0
	for key in lanes:
		var ds: Array = lanes[key]
		ds.sort()
		for i in range(1, ds.size()):
			if ds[i] - ds[i - 1] < 4.0:
				bad += 1
	return bad

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
