extends SceneTree
## Freight trains on the county's real railroads (CountyTrains): through
## runs from one county line to another, real consists, fleets that never
## meet on single track, and gates where the town's roads cross.
## Run: godot --headless -s tests/test_county_trains.gd


func _init() -> void:
	var cs := CountyTrains.corridors()
	_check(cs.size() >= 2, "the county's main lines make through runs (%d)" % cs.size())
	_check(cs.all(func(c): return _edge(c.pts[0]) and _edge(c.pts[c.pts.size() - 1]) and c.length >= CountyTrains.MIN_CORRIDOR),
		"each runs from one county line to another")

	# One train, followed the whole way: it comes in at the county line, runs
	# at track speed and leaves at the far one.
	var seed := CountyTrains.SEED
	var first: Dictionary = {}
	var t := 0
	var L: float = cs[0].length
	while first.is_empty() and t < 400_000:
		for tr in CountyTrains.trains_at(t, seed):
			if tr.corridor == 0 and (tr.s < 100.0 if tr.dir > 0 else tr.s > L - 100.0):
				first = tr
				break
		t += 50
	_check(not first.is_empty(), "a train comes in at the county line")
	var seen := []
	var gone := false
	while not gone:
		var here: Array = CountyTrains.trains_at(t, seed).filter(func(x): return x.id == first.id)
		if here.is_empty():
			gone = true
		else:
			seen.append(float(here[0].s))
		t += 50
	var moved_ok := true
	for i in range(1, seen.size()):
		moved_ok = moved_ok and absf(absf(seen[i] - seen[i - 1]) - CountyTrains.SPEED * 5.0) < 0.5
	_check(seen.size() > 10 and moved_ok, "it runs at 40 mph the whole way (%d looks)" % seen.size())
	var end: float = seen[-1] if first.dir > 0 else L - seen[-1]
	_check(end > L, "and only drops off the list once its last car is past the county line (%.0f of %.0f m)" % [end, L])
	_check(first.consist.size() >= CountyTrains.CARS.x + 2 and first.consist[0][0] in ["gp38", "sd40"]
		and first.consist.slice(3).all(func(c): return c[1] != ""), "two or three diesels ahead of loaded cars (%s train, %d cars)" % [
		first.kind, first.consist.size()])

	# Single track: on any line, every train runs the same way, a train apart.
	var meets := 0
	var close := 0
	var kinds := {}
	for tick in range(0, 400_000, 997):
		var by := {}
		for tr in CountyTrains.trains_at(tick, seed):
			kinds[tr.kind] = true
			if not by.has(tr.corridor):
				by[tr.corridor] = []
			by[tr.corridor].append(tr)
		for ci in by:
			var list: Array = by[ci]
			for a in list:
				for b in list:
					if a.id == b.id:
						continue
					if a.dir != b.dir:
						meets += 1
					elif absf(float(a.s) - float(b.s)) < CountyTrains._max_len():
						close += 1
	_check(meets == 0, "no two trains ever meet on a line")
	_check(close == 0, "trains a fleet apart never run into each other")
	_check(kinds.size() >= 3, "grain, tank, stone and manifest trains (%s)" % str(kinds.keys()))

	# A town road across the line gets gates that close for a train.
	var c0: Dictionary = cs[0]
	var mid := CountyTrains._at(c0, 9000.0)
	var dir := (CountyTrains._at(c0, 9010.0) - CountyTrains._at(c0, 8990.0)).normalized()
	var across := Vector2(-dir.y, dir.x)
	var sim := CitySim.new()
	sim.county_rail = true
	sim.terrain_offset = mid
	sim.economy.money = 10_000_000
	var a := -across * 150.0
	var b := across * 150.0
	sim.apply({"type": "build_road", "start": [a.x, a.y], "ctrl": [0, 0], "end": [b.x, b.y]})
	sim.county_trains.tick(sim)
	var xs: Array = sim.county_trains.crossings
	_check(xs.size() == 1 and int(xs[0].corridor) == 0 and absf(float(xs[0].s) - 9000.0) < 5.0,
		"the town's road crosses the line once (%s)" % str(xs.map(func(x): return [x.corridor, int(x.s)])))
	if xs.size() == 1:
		var closed_at := -1
		var open_after := -1
		for tick in range(0, 300_000, 20):
			sim.tick_count = tick
			sim.county_trains.tick(sim)
			if xs[0].closed and closed_at == -1:
				closed_at = tick
				# Where's the train: about 25 s (450 m) out.
				var near := INF
				for tr in CountyTrains.trains_at(tick, seed):
					if tr.corridor == 0:
						near = minf(near, absf(float(tr.s) - 9000.0))
				_check(near > CountyTrains.SPEED * (CountyTrains.GATE_WARNING - 2.0) and near < CountyTrains.SPEED * (CountyTrains.GATE_WARNING + 2.0),
					"the gates come down about 25 seconds before the train (%.0f m out)" % near)
			elif closed_at != -1 and not xs[0].closed:
				open_after = tick
				break
		_check(closed_at != -1 and open_after != -1, "and go up once it has passed")
		sim.tick_count = closed_at
		sim.county_trains.tick(sim)
		sim.traffic._sim = sim
		sim.traffic._rebuild()
		sim.traffic._find_xings()
		_check(not sim.traffic._xings.is_empty(), "traffic stops at the county line's gates")

	_horns(cs)
	_interchange(seed)
	_town_interchange(cs)
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Through freights blow long, long, short, long for every grade crossing
## on the line, out in the country too.
func _horns(cs: Array) -> void:
	var sim := CitySim.new()
	sim.county_rail = true
	var rs := RailSounds.new()
	rs.sim = sim
	var xs := rs._xings_on(0)
	_check(xs.size() >= 10, "the line crosses the county's roads at grade (%d crossings on %.0f km)" % [xs.size(), cs[0].length / 1000.0])
	# Stand by a crossing and wait for a train.
	var x0: float = xs[xs.size() / 2]
	var p := CountyTrains._at(cs[0], x0)
	var ear := Vector3(p.x - Terrain.view_origin.x, 0.0, p.y - Terrain.view_origin.y)
	var blew := -1.0
	for tick in range(0, 300_000, 10):
		sim.tick_count = tick
		rs._watch_county(ear)
		for key in rs._blow:
			var b: Dictionary = rs._blow[key]
			if float(b.reached) > 0.0:
				blew = float(b.reached)
		if blew > 0.0:
			break
	_check(blew > 0.0, "a passing train blows its horn for crossings near you")
	_check(blew <= RailSounds.HORN_LEAD + 0.5 and blew >= RailSounds.HORN_LEAD - 1.5,
		"starting about %d s before the engine is on the crossing (%.1f s)" % [int(RailSounds.HORN_LEAD), blew])
	_check(rs._county.size() >= 1, "and its diesels can be heard")
	rs.free()


## A town's cars left beside the line ride out on the next through freight.
func _interchange(seed: int) -> void:
	var ct := CountyTrains.new()
	var c0: Dictionary = CountyTrains.corridors()[0]
	var s0 := 20000.0
	var at := CountyTrains._at(c0, s0)
	var cars := [["covered", "grain"], ["covered", "grain"], ["hopper", "ore"]]
	_check(ct.hand_off(100, at + Vector2(3, 3), 7, cars), "a town leaves three cars at its interchange")
	_check(not ct.hand_off(100, Vector2(-1e6, -1e6), 7, cars), "but not where no county line runs")
	var taken := -1
	var tid := 0
	var stood := 0
	for tick in range(100, 400_000):
		var trains := ct.now(tick)
		ct._pick_up(tick, trains)
		if taken == -1 and not ct.stops.is_empty():
			taken = tick
			tid = ct.stops.keys()[0]
		if taken != -1:
			for t in trains:
				if t.id == tid and t.get("stopped", false):
					stood += 1
					if stood == 1:
						_check(absf(float(t.s) - float(ct.stops[tid].s)) < 2.0, "it stops with its head at the interchange")
		if taken != -1 and ct.handoffs.is_empty():
			break
	_check(taken != -1, "the next through freight to come by stops for them")
	_check(stood == CountyTrains.STOP, "it stands %d ticks to couple them on (%d)" % [CountyTrains.STOP, stood])
	_check(ct.handoffs.is_empty(), "the cars leave the interchange with it")
	var after := {}
	for tick in range(taken, taken + 400_000, 50):
		for t in ct.now(tick):
			if t.id == tid:
				after = t
		if not after.is_empty() and after.consist.size() > 0 and after.consist.slice(-3) == cars:
			break
	_check(not after.is_empty() and after.consist.slice(-3) == cars, "and they ride on the back of its train")
	# Saved and loaded, the timetable is the same.
	var back := CountyTrains.new()
	back.from_dict(JSON.parse_string(JSON.stringify(ct.to_dict())))
	var same := true
	for tick in range(taken, taken + 60_000, 997):
		if str(ct.now(tick)) != str(back.now(tick)):
			same = false
	_check(same, "a saved stop loads the same")
	# Stopping never brings two trains together.
	var meets := 0
	for tick in range(taken - 20_000, taken + 80_000, 25):
		var list := ct.now(tick).filter(func(t): return t.corridor == 0)
		for x in list:
			for y in list:
				if x.id != y.id and (x.dir != y.dir or absf(float(x.s) - float(y.s)) < CountyTrains._max_len()):
					meets += 1
	_check(meets == 0, "a train standing at an interchange never meets or crowds another")


## A town near the line builds its main line to an interchange track beside
## it, and its local freight leaves its cars there and comes back.
func _town_interchange(cs: Array) -> void:
	# Somewhere 1.5 km off the line with dry, level ground for a yard.
	var sim: CitySim
	var placed := false
	for s0 in [26000.0, 12000.0, 30000.0, 16000.0, 6000.0, 22000.0, 34000.0]:
		for side in [1.0, -1.0]:
			var c0: Dictionary = cs[0]
			var mid := CountyTrains._at(c0, s0)
			var dir := (CountyTrains._at(c0, s0 + 10.0) - CountyTrains._at(c0, s0 - 10.0)).normalized()
			var across: Vector2 = Vector2(-dir.y, dir.x) * float(side)
			sim = CitySim.new()
			sim.simulate_traffic = false
			sim.county_rail = true
			sim.terrain_offset = mid + across * 1500.0
			sim.economy.money = 5_000_000
			# A county road through town, along the line.
			var a := dir * -2000.0
			var b := dir * 2000.0
			sim.apply({"type": "build_county_road", "a": [a.x, a.y], "b": [b.x, b.y], "links": [0, 1]})
			var site := Rail.site_near(sim.network, Vector3(-across.x, 0, -across.y) * 60.0)
			if site.is_empty() or sim.rail.site_problem(sim, site[0], site[1], site[2]) != "":
				continue
			placed = sim.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z], "axis": [site[2].x, site[2].z]})
			if placed:
				break
		if placed:
			break
	_check(placed, "a depot opens 1.5 km from the county line")
	if not placed:
		return
	var d: Dictionary = sim.rail.depots.values()[0]
	for i in Balance.RAIL_DECIDE_EVERY + 1:
		sim.tick()
	var reqs := sim.rail.open_requests()
	_check(reqs.size() == 1 and sim.rail.lines[reqs[0]].target.get("county", false),
		"its main line goes to an interchange with the county line (%s)" % d.why)
	if reqs.is_empty():
		return
	var l: Dictionary = sim.rail.lines[reqs[0]]
	sim.apply({"type": "permit", "id": l.permit, "answer": "approve"})
	for i in 24 * 60 * 10:
		sim.tick()
		if l.state == "open":
			break
	_check(l.state == "open", "it opens")
	var rp: int = l.pieces[-1]
	var pc: Dictionary = sim.rail.pieces[rp]
	var off := sim.terrain_offset
	var worst := 0.0
	var pts: Array = pc.pts
	for i in range(pts.size() / 2, pts.size()):
		var n := CountyTrains.nearest(Vector2(pts[i].x, pts[i].z) + off)
		worst = maxf(worst, absf(float(n.dist) - Rail.INTERCHANGE_GAP))
	_check(pc.get("county", false) and worst < 0.5,
		"the interchange track runs beside the county's main, 4.6 m between centres (off by %.2f m)" % worst)
	# The local freight brings five loaded hoppers out.
	var tid: int = d.freight_train
	var t: Dictionary = sim.rail.trains[tid]
	t.legs = ["region"]
	t.consist = ["gp38", "hopper", "hopper", "hopper", "hopper", "hopper"]
	t.cars = 5
	t.cargo = "ore"
	t.state = "ready"
	for i in 24 * 60 * 2:
		sim.tick()
		if not sim.county_trains.handoffs.is_empty():
			break
	_check(sim.county_trains.handoffs.size() == 1 and sim.county_trains.handoffs[0].cars.size() == 5,
		"the local freight leaves its five cars at the interchange")
	_check(int(d.get("delivered", 0)) == 5, "and the railroad is paid for them")
	_check(t.state != "away" and t.consist == ["gp38"] and t.legs == ["yard"], "its engine heads back, not off the map")
	for i in 24 * 60 * 2:
		sim.tick()
		if t.state == "parked" or t.purpose == "Waiting for work":
			break
	_check(t.purpose == "Waiting for work", "and gets back to the yard (%s)" % t.purpose)


func _edge(p: Vector2) -> bool:
	var lo := Terrain.CENTRE - Vector2.ONE * Terrain.SIZE * 0.5
	var hi := lo + Vector2.ONE * Terrain.SIZE
	return p.x - lo.x < 40.0 or hi.x - p.x < 40.0 or p.y - lo.y < 40.0 or hi.y - p.y < 40.0


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
