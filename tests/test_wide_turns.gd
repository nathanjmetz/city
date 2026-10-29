extends SceneTree
## Big trucks at town corners (Brawn, 2026-10-25: "semi trucks should take
## wide angles. other drives should stay back to give them room"). A
## tractor-trailer needs a 45 ft turning radius (AASHTO WB-67), a town
## corner gives it far less, so it swings out across the oncoming lane of
## the street it turns into while the cars there wait back; and a trailer
## still crossing a junction after its cab has left keeps the box closed.
## Run: godot --headless -s tests/test_wide_turns.gd
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## Two streets meeting in a square corner, no setback to turn in.
func _corner() -> CitySim:
	var sim := CitySim.new()
	sim.economy.money = 1.0e9
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [-150, 0], "end": [0, 0]})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 150], "end": [0, 300]})
	sim.tick()
	return sim


func _init() -> void:
	var sim := _corner()
	var t := sim.traffic
	# Eastbound turning south is a right turn (traffic keeps right).
	var semi := t.dispatch({"ref": "yard", "pos": [-280, 6]}, {"ref": "site", "pos": [-6, 280]}, "construction", {}, "flatbed")
	var pickup := t.dispatch({"ref": "yard2", "pos": [-200, 6]}, {"ref": "site2", "pos": [-6, 250]}, "construction", {}, "pickup")
	# A steady stream coming the other way up the street the semi turns into.
	var oncoming := []
	var semi_path := {}
	var pickup_path := {}
	var too_close := 0
	var last_d := {}
	var waited := 0
	var arrived := {}
	var saved := {}
	for i in 3000:
		if i < 1200 and i % 30 == 0:
			oncoming.append(t.dispatch({"ref": "h%d" % i, "pos": [6, 120]}, {"ref": "w%d" % i, "pos": [-260, -6]}, "commute", {}, "sedan"))
		sim.tick()
		for car in t.cars:
			if car.j == null or car.j.node < 0:
				continue
			if car.id == semi:
				semi_path = car.j
			elif car.id == pickup:
				pickup_path = car.j
		for car in t.cars:
			if car.id != semi or car.j == null or not car.j.has("sweep") or car.jd > car.j.len - TrafficSim.WIDE_BLEND:
				continue
			if saved.is_empty():
				saved = JSON.parse_string(JSON.stringify(sim.to_dict()))
			# While it swings, nobody oncoming moves into the swing, and the
			# cars there stop short of it.
			for o in t.cars:
				if not o.id in oncoming or o.j != null:
					continue
				var key: int = o.route[o.leg] * 8 + o.lane
				if not car.j.sweep.has(key):
					continue
				var hold: float = car.j.sweep[key]
				if o.d > hold + 0.5 and last_d.get(o.id, INF) <= hold + 0.5:
					too_close += 1
				if o.d > hold - 20.0 and o.d <= hold + 0.5:
					waited += 1
		for o in t.cars:
			if o.j == null:
				last_d[o.id] = o.d
		for a in t.arrivals:
			arrived[a.get("vid", -1)] = true
		t.arrivals.clear()
	_check(semi_path.has("sweep") and not semi_path.sweep.is_empty(),
		"the semi swings wide round the square corner (%s)" % [semi_path.get("sweep")])
	_check(not pickup_path.is_empty() and not pickup_path.has("sweep"), "a pickup takes the corner as usual")
	if semi_path.has("sweep"):
		# How far its path strays from the lane it turns into, and where it ends.
		var b: Dictionary = t.ways[semi_path.wo]
		var most := 0.0
		for p in semi_path.pts:
			var d: float = t._nearest_d(b, p)
			if d > b.s0 + 1.0:
				most = maxf(most, t._lane_point(b, semi_path.lo, d).distance_to(p))
		var end: Vector3 = semi_path.pts[semi_path.pts.size() - 1]
		_check(most > 2.5 and most < 4.5, "it swings about a lane over, into the oncoming lane (%.1f m)" % most)
		_check(end.distance_to(t._lane_point(b, semi_path.lo, semi_path.exit_d)) < 0.2, "and ends back in its own lane")
		var r := INF
		var pts: PackedVector3Array = semi_path.pts
		for k in range(1, pts.size() - 1):
			var a := Vector2(pts[k - 1].x, pts[k - 1].z)
			var m := Vector2(pts[k].x, pts[k].z)
			var c := Vector2(pts[k + 1].x, pts[k + 1].z)
			var cross := absf((m - a).cross(c - m))
			if cross > 0.001:
				r = minf(r, a.distance_to(m) * m.distance_to(c) * a.distance_to(c) / (2.0 * cross))
		_check(r > 6.0, "its tightest bend is a truck's, not a car's (radius %.1f m)" % r)
	_check(waited > 0, "oncoming drivers come up behind the swing and wait back (%d)" % waited)
	_check(too_close == 0, "no oncoming car drives into its swing (%d)" % too_close)
	_check(t.cars.is_empty() and t._waiting.is_empty(), "everyone gets where they were going (%d still out)" % t.cars.size())
	# The wide path is saved by name and found again on load.
	_check(not saved.is_empty(), "saved mid-turn")
	if not saved.is_empty():
		var copy := CitySim.new()
		copy.from_dict(saved)
		copy.tick()  # the roads are laid again first
		var again := false
		for car in copy.traffic.cars:
			if car.id == semi and car.j != null and car.j.has("sweep"):
				again = true
		_check(again, "the semi loads still on its wide turn")
		for i in 3000:
			copy.tick()
		_check(copy.traffic.cars.is_empty(), "and finishes it")

	# A crossroads: a semi crossing, cars on the cross street. None of them
	# starts across while the trailer is still in the box.
	var x := CitySim.new()
	x.economy.money = 1.0e9
	x.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	x.apply({"type": "build_road", "start": [0, -300], "ctrl": [0, 0], "end": [0, 300]})
	x.tick()
	var xt := x.traffic
	var big := xt.dispatch({"ref": "y", "pos": [-280, 6]}, {"ref": "s", "pos": [280, 6]}, "construction", {}, "semi")
	for n in 4:
		xt.dispatch({"ref": "n%d" % n, "pos": [6, 60 + n * 20]}, {"ref": "m%d" % n, "pos": [6, -250]}, "commute", {}, "sedan")
		xt.dispatch({"ref": "p%d" % n, "pos": [-6, -60 - n * 20]}, {"ref": "q%d" % n, "pos": [-6, 250]}, "commute", {}, "sedan")
	var tail_clash := 0
	var tails := 0
	for i in 3000:
		x.tick()
		for car in xt.cars:
			if car.id != big or car.j != null or car.get("pj") == null or car.d - car.len >= car.pj.exit_d:
				continue
			if car.pj.get("node", -1) < 0:
				continue
			tails += 1
			for o in xt.cars:
				if o.j != null and o.j.node == car.pj.node and xt._conflicts(o.j, car.pj):
					tail_clash += 1
	_check(tails > 0, "the semi's trailer trails through the box after its cab (%d ticks)" % tails)
	_check(tail_clash == 0, "no one drives into the trailer (%d)" % tail_clash)
	_check(xt.cars.is_empty(), "all through")

	print("wide turns: %s" % ("all ok" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
