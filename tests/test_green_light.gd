extends SceneTree
## Run: godot --headless -s tests/test_green_light.gd
## Drivers use a green light the way real ones do (docs/traffic-rules.md).
## Nathan, 2026-10-25: "only three cars got through and all three of them
## hesitated when they got to the line there was no sense of urgency or
## desire to move traffic along."
## A queue of 20 cars a lane waits on red at two avenues crossing; each
## green is measured: cars through, the first car's start, the gap between
## cars crossing the line, their speed through the junction, and whether
## any slowed at the line with nothing in its way. Then an all-way stop's
## rate, and where cars stop at a town street meeting the highway.

var failed := false


func _init() -> void:
	var g := green_run(RoadStyle.Type.AVENUE, RoadStyle.Type.AVENUE)
	print("GREEN %s" % JSON.stringify(g))
	_check(g.per30 >= 12.0, "at least 12 cars a lane through 30 s of green (%.1f)" % g.per30)
	_check(g.start <= 2.0, "the first car moves within 2 s of green (%.1f s)" % g.start)
	_check(g.headway <= 2.3, "about 2 s between cars crossing the line (%.2f s)" % g.headway)
	_check(g.hesitate == 0, "nobody slows or stops at the line on green (%d did)" % g.hesitate)
	_check(g.top >= 0.85 * g.limit, "up to the limit through the junction (%.1f of %.1f m/s)" % [g.top, g.limit])
	_check(g.ripple_ok, "the queue starts in a ripple (%s s)" % str(g.ripple))
	var s := stop_run()
	print("ALLSTOP %s" % JSON.stringify(s))
	_check(s.per_car >= 3.5 and s.per_car <= 5.5, "an all-way stop takes 4 to 5 s a car (%.1f s)" % s.per_car)
	var b := bar_run()
	print("BAR %s" % JSON.stringify(b))
	_check(b.behind >= 0.0 and b.behind <= 2.0,
		"a car stops at the painted line where a street meets the highway (%.1f m behind it)" % b.behind)
	quit(1 if failed else 0)


## Puts `n` cars a lane, nose to tail, in every lane of `wi` that goes on to
## the way straight across, each headed off the far edge.
static func _queue(sim: CitySim, wi: int, from: Vector2, to: Vector2, n: int) -> Array:
	var t := sim.traffic
	var placed := []
	var w: Dictionary = t.ways[wi]
	var lanes := []
	for k in n * 2:
		t.dispatch({"ref": "edge", "pos": [from.x, from.y]}, {"ref": "edge", "pos": [to.x, to.y]}, "commute", {}, "sedan")
	var pool: Array = t._waiting.duplicate() + t.cars.duplicate()
	t._waiting.clear()
	t.cars.clear()
	pool = pool.filter(func(c): return c.route.size() >= 2 and c.route[0] == wi)
	lanes = t.lanes_for(wi, pool[0].route[1]) if not pool.is_empty() else []
	var at := {}
	for lane in lanes:
		at[lane] = w.s1 - 1.0
	var k := 0
	for car in pool:
		var lane: int = lanes[k % lanes.size()]
		if placed.filter(func(c): return c.lane == lane).size() >= n:
			k += 1
			continue
		car.lane = lane
		car.d = at[lane]
		car.v = 0.0
		at[lane] -= car.len + TrafficSim.JAM_GAP
		t.cars.append(car)
		placed.append(car)
		k += 1
	return placed


static func _node_at(net: RoadNetwork, p: Vector3) -> int:
	for n in net.nodes:
		if net.nodes[n].distance_to(p) < 1.0:
			return n
	return -1


static func _way_in(t: TrafficSim, node: int, dir: Vector3) -> int:
	for wid in t.ways_into(node):
		if t.stop_line(wid).dir.dot(dir) > 0.9:
			return wid
	return -1


## Two roads crossing at lights; 20 cars a lane queue from the west on red.
static func green_run(ew: int, ns: int) -> Dictionary:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0], "road": ew})
	sim.apply({"type": "build_road", "start": [0, -600], "ctrl": [0, 0], "end": [0, 600], "road": ns})
	var t := sim.traffic
	sim.tick()
	var node := _node_at(sim.network, Vector3.ZERO)
	t.set_rule(node, TrafficSim.Rule.SIGNAL)
	sim.tick()
	var wi := _way_in(t, node, Vector3.RIGHT)
	var mine := _queue(sim, wi, Vector2(-590, 0), Vector2(590, 0), 20)
	var limit: float = t.way_speed(wi)
	# Wait for red, then for the green after it.
	var was := t.light(node, wi)
	var greens := []
	var cross := {}   # car id -> [time, lane]
	var top := 0.0
	var peak := {}    # car id -> fastest so far on the approach
	var dip := {}     # car id -> slowest after reaching 2 m/s, before the line
	var moved := {}   # car id -> when it first moved
	var hesitate := 0
	var hes_ids := []
	for i in 2400:
		sim.tick()
		var st := t.light(node, wi)
		if st == TrafficSim.Light.GREEN and was == TrafficSim.Light.RED:
			greens.append(t.time)
		was = st
		if greens.is_empty():
			continue
		for car in mine:
			if not t.cars.has(car):
				continue
			if not moved.has(car.id) and car.v > 0.5:
				moved[car.id] = t.time
			if car.j != null:
				if car.j.node == node and not cross.has(car.id):
					cross[car.id] = [t.time, car.j.li]
				if car.j.node == node:
					top = maxf(top, car.v)
				continue
			if cross.has(car.id):
				if car.d - t.ways[car.route[car.leg]].s0 < 40.0:
					top = maxf(top, car.v)
				continue
			if car.route[car.leg] != wi:
				continue
			var ds: float = t.ways[wi].s1 - car.d
			peak[car.id] = maxf(peak.get(car.id, 0.0), car.v)
			# Slowing near the line on green with nobody close ahead.
			if st == TrafficSim.Light.GREEN and ds < 30.0 and peak[car.id] > 2.0 and car.a < -0.5 \
					and _clear_ahead(t, car) and not hes_ids.has(car.id):
				hes_ids.append(car.id)
				hesitate += 1
		if greens.size() >= 2 and t.time > greens[1] + 2.0:
			break
	var g0: float = greens[0] if not greens.is_empty() else 0.0
	var by_lane := {}
	for id in cross:
		var c: Array = cross[id]
		if c[0] >= g0 and c[0] <= g0 + 30.0:
			if not by_lane.has(c[1]):
				by_lane[c[1]] = []
			by_lane[c[1]].append(c[0])
	var counts := []
	var heads := []
	for lane in by_lane:
		var ts: Array = by_lane[lane]
		ts.sort()
		counts.append(ts.size())
		for k in range(3, ts.size()):
			heads.append(ts[k] - ts[k - 1])
	var first := INF
	var starts := []
	for car in mine:
		if moved.has(car.id) and moved[car.id] >= g0:
			first = minf(first, moved[car.id] - g0)
	# The ripple: when each of the first six in the first lane moved.
	var lane0: Array = mine.filter(func(c): return c.lane == mine[0].lane)
	for k in mini(6, lane0.size()):
		starts.append(snappedf(moved.get(lane0[k].id, INF) - g0, 0.1))
	var ripple_ok := starts.size() == 6
	for k in range(1, starts.size()):
		var gap: float = starts[k] - starts[k - 1]
		if gap < 0.3 or gap > 2.0:
			ripple_ok = false
	var green_len := _green_len(t, node, wi)
	var span := minf(30.0, green_len)
	var lo := 99
	for c in counts:
		lo = mini(lo, c)
	var hw := 0.0
	for h in heads:
		hw += h
	return {"counts": counts, "green": snappedf(green_len, 0.1), "per30": snappedf(lo * 30.0 / span, 0.1) if not counts.is_empty() else 0.0,
		"start": snappedf(first, 0.1), "headway": snappedf(hw / maxf(heads.size(), 1), 0.01) if not heads.is_empty() else 99.0,
		"top": snappedf(top, 0.1), "limit": snappedf(limit, 0.1), "hesitate": hesitate, "ripple": starts, "ripple_ok": ripple_ok}


static func _green_len(t: TrafficSim, node: int, wi: int) -> float:
	var j: Dictionary = t.junctions[node]
	var start := 0.0
	for ph in j.phases:
		if ph.ways.has(wi):
			return ph.g_end - start
		start = ph.end
	return 0.0


static func _clear_ahead(t: TrafficSim, car: Dictionary) -> bool:
	for o in t.cars:
		if o.id == car.id or o.j != null or o.route[o.leg] != car.route[car.leg] or o.lane != car.lane:
			continue
		if o.d > car.d and o.d - o.len - car.d < 25.0:
			return false
	for o in t.cars:
		if o.j != null and o.id != car.id and o.j.wi == car.route[car.leg] and o.j.li == car.lane and o.jd < o.j.len * 0.5:
			return false
	return true


## Two country roads at an all-way stop, ten cars queued from the west and
## ten from the south: seconds per car through.
static func stop_run() -> Dictionary:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0], "road": RoadStyle.Type.COUNTY})
	sim.apply({"type": "build_road", "start": [0, -400], "ctrl": [0, 0], "end": [0, 400], "road": RoadStyle.Type.COUNTY})
	var t := sim.traffic
	sim.tick()
	var node := _node_at(sim.network, Vector3.ZERO)
	t.set_rule(node, TrafficSim.Rule.ALL_STOP)
	sim.tick()
	var mine := _queue(sim, _way_in(t, node, Vector3.RIGHT), Vector2(-390, 0), Vector2(390, 0), 10)
	mine += _queue(sim, _way_in(t, node, Vector3.BACK), Vector2(0, -390), Vector2(0, 390), 10)
	var times := []
	var seen := {}
	var t0 := t.time
	for i in 3000:
		sim.tick()
		for car in mine:
			if car.j != null and car.j.node == node and not seen.has(car.id):
				seen[car.id] = true
				times.append(t.time)
		if seen.size() >= mine.size():
			break
	times.sort()
	var per := 99.0
	if times.size() >= 6:
		per = (times[times.size() - 1] - times[2]) / float(times.size() - 3)
	return {"through": times.size(), "of": mine.size(), "per_car": snappedf(per, 0.01), "first": snappedf(times[0] - t0 if not times.is_empty() else 99.0, 0.1)}


## A town street meeting the state highway, stop sign on the street: how far
## behind the painted line the first car stops.
static func bar_run() -> Dictionary:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": RoadStyle.Type.STATE_HWY})
	sim.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, -100], "end": [0, 0], "road": RoadStyle.Type.STREET})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, 100], "end": [0, 200], "road": RoadStyle.Type.STREET})
	var t := sim.traffic
	sim.tick()
	var node := _node_at(sim.network, Vector3.ZERO)
	var wi := _way_in(t, node, Vector3.BACK)
	var mine := _queue(sim, wi, Vector2(0, -190), Vector2(0, 190), 1)
	var plans := Junction.plan(sim.network)
	var j: Dictionary = plans.get(node, {})
	var bar := INF
	for arm in j.get("arms", []):
		if arm.seg == t.ways[wi].seg:
			bar = JunctionMarks.country_near(j, arm) + JunctionMarks.BAR
	if not j.get("country", false) and not j.get("unmarked", false):
		var back := JunctionMarks.stop_back(j, t.ways[wi].seg)
		if back > 0.0:
			bar = back
	# Start the car back up the street and let it roll up to the line.
	mine[0].d = t.ways[wi].s1 - 60.0
	var rest := -1.0
	for i in 600:
		sim.tick()
		# Stopped as the stop sign counts it (TrafficSim: under 1 m/s within
		# 4 m of the line), at the slowest point.
		if mine[0].j == null and mine[0].v < 1.0 and t.ways[wi].s1 - mine[0].d < 10.0:
			var low: float = mine[0].v
			rest = t.ways[wi].len - mine[0].d  # nose to the junction's centre
			for k in 300:
				if mine[0].j != null:
					break
				sim.tick()
				if mine[0].v > low:
					break
				low = mine[0].v
				rest = t.ways[wi].len - mine[0].d  # nose to the junction's centre
			break
	return {"bar": snappedf(bar, 0.1), "nose": snappedf(rest, 0.1), "behind": snappedf(rest - bar, 0.1),
		"country": j.get("country", false), "unmarked": j.get("unmarked", false)}


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed = true
