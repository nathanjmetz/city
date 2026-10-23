extends SceneTree
## Run: godot --headless -s tests/test_traffic.gd

func _init() -> void:
	# An L of streets with homes at one end and jobs at the other.
	var sim := _l_town()
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

	# The same commands give the same cars (needed for multiplayer).
	var a := _l_town()
	var b := _l_town()
	for i in 3000:
		a.tick()
		b.tick()
	_check(_fingerprint(a.traffic) == _fingerprint(b.traffic) and a.traffic.cars.size() > 0,
		"two copies drive exactly the same cars")

	# One-way: a single highway only drives the way it was drawn.
	var o := CitySim.new()
	o.apply({"type": "build_road", "start": [0, 0], "ctrl": [100, 0], "end": [200, 0], "road": RoadStyle.Type.HIGHWAY})
	o.tick()
	var lot_a := {"seg": o.network.segments.keys()[0], "at_frac": 0.8}
	var lot_b := {"seg": lot_a.seg, "at_frac": 0.2}
	_check(o.traffic._route(lot_b, lot_a).size() > 0, "can drive with the one-way")
	_check(o.traffic._route(lot_a, lot_b).is_empty(), "cannot drive against the one-way")

	# Lanes and lane arrows where two avenues cross.
	var x := CitySim.new()
	x.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": RoadStyle.Type.AVENUE})
	x.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200], "road": RoadStyle.Type.AVENUE})
	x.tick()
	var tx := x.traffic
	var centre := x.network.find_node_near(Vector3.ZERO, 1.0)
	var east_in := -1
	for wid in tx.ways_into(centre):
		if tx.ways[wid].pts[0].x < -100.0:
			east_in = wid
	_check(east_in != -1 and tx.ways[east_in].lanes == 2, "an avenue has two lanes each way")
	var lefts := []
	var rights := []
	for wo in tx._turns[east_in]:
		match tx._kind[Vector2i(east_in, wo)]:
			TrafficSim.Turn.LEFT: lefts = tx.lanes_for(east_in, wo)
			TrafficSim.Turn.RIGHT: rights = tx.lanes_for(east_in, wo)
	_check(lefts == [0] and rights == [1], "left lane turns left, right lane turns right (%s %s)" % [lefts, rights])
	_check(tx.junctions[centre].control == TrafficSim.Rule.SIGNAL, "two avenues crossing get traffic lights")
	var greens := 0
	for wid in tx.ways_into(centre):
		if tx.light(centre, wid) == TrafficSim.Light.GREEN:
			greens += 1
	_check(greens == 2, "lights give one road green at a time (%d green)" % greens)

	# Two streets crossing get an all-way stop; a street meeting an avenue
	# gets a stop sign on the street only.
	var s := CitySim.new()
	s.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
	s.apply({"type": "build_road", "start": [0, -200], "ctrl": [0, 0], "end": [0, 200]})
	s.apply({"type": "build_road", "start": [-200, 300], "ctrl": [0, 300], "end": [200, 300], "road": RoadStyle.Type.AVENUE})
	s.apply({"type": "build_road", "start": [0, 200], "ctrl": [0, 250], "end": [0, 300]})
	s.tick()
	var c0 := s.network.find_node_near(Vector3.ZERO, 1.0)
	var c1 := s.network.find_node_near(Vector3(0, 0, 300), 1.0)
	_check(s.traffic.junctions[c0].control == TrafficSim.Rule.ALL_STOP, "two streets get an all-way stop")
	var j1: Dictionary = s.traffic.junctions[c1]
	_check(j1.control == TrafficSim.Rule.PRIORITY and j1.major.size() == 2 and j1.sign == "stop",
		"a street meeting an avenue gets a stop sign")

	# The player can choose lights or signs, and the choice is saved.
	_check(s.apply({"type": "set_junction", "node": c0, "rule": TrafficSim.Rule.SIGNAL}), "set a junction to lights")
	_check(s.traffic.junctions[c0].control == TrafficSim.Rule.SIGNAL, "the junction now has lights")
	var saved := s.to_dict()
	var s2 := CitySim.new()
	s2.from_dict(JSON.parse_string(JSON.stringify(saved)))
	s2.tick()
	_check(s2.traffic.junctions[c0].control == TrafficSim.Rule.SIGNAL, "the choice survives saving")
	s.apply({"type": "set_junction", "node": c0, "rule": -1})
	_check(s.traffic.junctions[c0].control == TrafficSim.Rule.ALL_STOP, "auto puts the all-way stop back")

	# Busy crossroads: cars use both lanes, change lanes, and never share
	# the junction with a car whose path crosses theirs.
	var g := _crossroads()
	g.tick()
	var lots: Array = g.lots.keys()
	lots.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var changes := 0
	var clashes := 0
	var lanes_used := {}
	var last_lane := {}
	for i in 6000:
		if i % 8 == 0 and i < 4000:
			g.traffic.add_trip(g.lots[lots[rng.randi() % lots.size()]], g.lots[lots[rng.randi() % lots.size()]], rng)
		g.tick()
		for car in g.traffic.cars:
			if car.j == null:
				lanes_used[car.lane] = true
				if last_lane.has(car.id) and last_lane[car.id][0] == car.route[car.leg] \
						and last_lane[car.id][1] != car.lane:
					changes += 1
				last_lane[car.id] = [car.route[car.leg], car.lane]
		if i % 10 == 0:
			clashes += _clashes(g.traffic)
	_check(lanes_used.size() >= 2, "cars drive in more than one lane")
	_check(changes > 5, "cars change lanes (%d changes)" % changes)
	_check(clashes == 0, "no crossing paths inside a junction at once (%d)" % clashes)
	_check(g.traffic.gave_up < 5, "traffic keeps moving (%d gave up)" % g.traffic.gave_up)

	# Roundabout: cars go round counter-clockwise with the island on their
	# left, and cars coming in yield.
	var r := CitySim.new()
	r.economy.money = 1.0e9
	r.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": RoadStyle.Type.AVENUE})
	r.apply({"type": "build_roundabout", "center": [0, 0], "radius": 24, "road": RoadStyle.Type.AVENUE})
	r.tick()
	var ring_ok := true
	var ring_ways := 0
	var yields := 0
	for wid in r.traffic.ways:
		var w: Dictionary = r.traffic.ways[wid]
		if RoadStyle.is_ring(w.type):
			ring_ways += 1
			var mid: Vector3 = w.pts[w.pts.size() / 2]
			var sl := r.traffic.stop_line(wid)
			if sl.right.dot(Vector3(mid.x, 0, mid.z).normalized()) < 0.5:
				ring_ok = false
	for n in r.traffic.junctions:
		var jn: Dictionary = r.traffic.junctions[n]
		if jn.control == TrafficSim.Rule.PRIORITY and jn.sign == "yield":
			yields += 1
	_check(ring_ways > 0 and ring_ok, "roundabout traffic keeps the island on its left (%d ring ways)" % ring_ways)
	_check(yields == 2, "cars entering the roundabout yield (%d entries)" % yields)

	# Building a roundabout across busy roads doesn't wipe out the traffic.
	var e := _crossroads()
	e.economy.money = 1.0e9
	e.tick()
	var elots: Array = e.lots.keys()
	elots.sort()
	var erng := RandomNumberGenerator.new()
	erng.seed = 11
	for i in 1500:
		if i % 4 == 0:
			e.traffic.add_trip(e.lots[elots[erng.randi() % elots.size()]], e.lots[elots[erng.randi() % elots.size()]], erng)
		e.tick()
	var before := e.traffic.cars.size()
	e.apply({"type": "build_roundabout", "center": [200, 0], "radius": 24, "road": RoadStyle.Type.AVENUE})
	e.tick()
	elots = e.lots.keys()
	elots.sort()
	_check(e.traffic.cars.size() >= before * 0.8, "cars keep driving when a roundabout is built (%d of %d)" % [e.traffic.cars.size(), before])

	# Cars glide through junctions and roundabouts without snapping round.
	var jumps := 0
	var last := {}
	for i in 2000:
		if i % 6 == 0:
			e.traffic.add_trip(e.lots[elots[erng.randi() % elots.size()]], e.lots[elots[erng.randi() % elots.size()]], erng)
		e.tick()
		# A vehicle keeps its id for life, so only compare it with the tick
		# before if it was driving then too (not parked between trips).
		var now := {}
		for car in e.traffic.cars:
			var pose := e.traffic.car_pose(car)
			if last.has(car.id) and absf(last[car.id].signed_angle_to(pose[1], Vector3.UP)) > deg_to_rad(25.0):
				jumps += 1
			now[car.id] = pose[1]
		last = now
	_check(jumps == 0, "no car turns more than 25 degrees in a tenth of a second (%d)" % jumps)

	# A truck with a job: grain from a farm gate to a mill, reported on arrival,
	# and still delivered exactly once after a save and load mid-trip.
	var f := CitySim.new()
	f.economy.money = 1.0e9
	f.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0], "road": RoadStyle.Type.AVENUE})
	f.tick()
	var id := f.traffic.dispatch({"ref": "farm:1", "pos": [-380, 20]}, {"ref": "site:2", "pos": [380, -20]},
		"grain", {"good": "grain", "amount": 12})
	_check(id > 0, "a grain truck is sent")
	for i in 150:
		f.tick()
	var mid: Dictionary = JSON.parse_string(JSON.stringify(f.to_dict()))
	var f2 := CitySim.new()
	f2.from_dict(mid)
	var got := []
	for i in 1500:
		f2.tick()
		got += f2.traffic.arrivals
		f2.traffic.arrivals.clear()
	_check(got.size() == 1 and got[0].to == "site:2" and got[0].cargo.amount == 12 and got[0].purpose == "grain",
		"the grain arrives at the mill once, after a save and load (%s)" % [got])

	# A saved city with busy traffic loads and carries on exactly the same.
	# (Both copies load the same save, as every player joining a region does;
	# the road save rounds coordinates, so the original is not the reference.)
	var save_text := JSON.stringify(e.to_dict())
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(save_text))
	var copy2 := CitySim.new()
	copy2.from_dict(JSON.parse_string(save_text))
	# The copies' own lots: empty lots are re-platted on load from the
	# rounded roads, so their keys can differ from the original's.
	elots = copy.lots.keys()
	elots.sort()
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 5
	r2.seed = 5
	for i in 600:
		if i % 6 == 0:
			copy.traffic.add_trip(copy.lots[elots[r1.randi() % elots.size()]], copy.lots[elots[r1.randi() % elots.size()]], r1)
			copy2.traffic.add_trip(copy2.lots[elots[r2.randi() % elots.size()]], copy2.lots[elots[r2.randi() % elots.size()]], r2)
		copy.tick()
		copy2.tick()
	_check(copy.traffic.cars.size() > 10 and JSON.stringify(copy.traffic.to_dict()) == JSON.stringify(copy2.traffic.to_dict()),
		"loaded copies drive every car exactly the same (%d cars)" % copy.traffic.cars.size())

	# Loop 4: everyone is a named person; cars park in real spots, drivers walk
	# in, and no vehicle ever just disappears (CS2's parking and citizens).
	var people: Dictionary = sim.people.people
	_check(people.size() > 20, "every resident is a person (%d people)" % people.size())
	var place_names := {}
	for ref in sim.people.names:
		place_names[sim.people.names[ref]] = true
	_check(place_names.size() == sim.people.names.size() and place_names.size() > 10,
		"every place has its own name (%d)" % place_names.size())
	var vanished := 0
	var walked := 0
	var spot_kinds := {}
	var known := _vehicle_ids(t)
	for i in 3000:
		sim.tick()
		var now := _vehicle_ids(t)
		for vid in known:
			var was: Array = known[vid]
			if not now.has(vid) and was[0] != "edge" and not was[2] and (was[1] < 0 or people.has(was[1])):
				vanished += 1
		known = now
		walked = maxi(walked, t.walkers.size())
		if i % 100 == 0:
			for car in t.parked:
				var pl := t.place(car.at_place)
				if not pl.is_empty() and car.spot < pl.spots.size():
					spot_kinds[pl.spots[car.spot].kind] = true
	_check(vanished == 0, "no vehicle ever just disappears (%d did)" % vanished)
	_check(walked > 0, "people walk the sidewalks (up to %d at once)" % walked)
	_check(spot_kinds.has("drive") or spot_kinds.has("garage"), "cars park in driveways and garages (%s)" % [spot_kinds.keys()])

	# A truck from a factory unloads at a shop's lot, then drives home and parks.
	var shop := ""
	var works := ""
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.COMMERCIAL and shop == "":
			shop = key
		if sim.buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and works == "":
			works = key
	var trip := -1
	var truck := -1
	if shop != "" and works != "":
		var wl: Dictionary = sim.lots[works]
		var sl: Dictionary = sim.lots[shop]
		trip = t.dispatch({"ref": "lot:" + works, "pos": [wl.front.x, wl.front.z]},
			{"ref": "lot:" + shop, "pos": [sl.front.x, sl.front.z]}, "goods", {"good": "goods", "amount": 4})
	var arrived := false
	var home_again := false
	for i in 4000:
		sim.tick()
		for got_one in t.arrivals:
			if got_one.id == trip:
				arrived = true
				truck = got_one.get("vid", truck)
		if arrived:
			for car in t.parked:
				if car.id == truck and car.at_place == "lot:" + works and not car.get("pending", false) \
						and car.until < 0:
					home_again = true
		if home_again:
			break
	_check(trip >= 0 and arrived, "a delivery truck reaches the shop (trip %d)" % trip)
	_check(home_again, "and then drives back and parks at its own yard")

	# Click a vehicle: the panel says what it is, where from and to, and why.
	var info := {}
	for car in t.cars:
		var at: Vector3 = t.vehicle_centre(car, false)
		var sel := Inspect.pick(sim, at)
		if sel.get("type", "") == "vehicle":
			info = Inspect.describe(sim, sel)
			break
	var labels := []
	for row in info.get("rows", []):
		labels.append(row[0])
	_check(info.get("follow", false) and labels.has("From") and labels.has("To"),
		"clicking a vehicle shows where it's going (%s: %s)" % [info.get("title", "none"), info.get("status", "")])

	# Parked cars and people on foot load back exactly where they were.
	var save2 := JSON.stringify(sim.to_dict())
	var p1 := CitySim.new()
	p1.from_dict(JSON.parse_string(save2))
	var p2 := CitySim.new()
	p2.from_dict(JSON.parse_string(save2))
	for i in 300:
		p1.tick()
		p2.tick()
	_check(p1.traffic.parked.size() > 0 and JSON.stringify(p1.to_dict()) == JSON.stringify(p2.to_dict()),
		"parked cars, walkers and people load back exactly (%d parked)" % p1.traffic.parked.size())

	# A street closed to cars for a plaza: nobody drives in, people park
	# nearby, trucks deliver only when allowed, and it's saved.
	var pz := _crossroads()
	pz.economy.money = 1.0e9
	pz.tick()
	var west := -1
	var west_lot := ""
	var east_lot := ""
	var plots: Array = pz.lots.keys()
	plots.sort()
	for k in plots:
		var l: Dictionary = pz.lots[k]
		if l.pos.z > 5.0 and absf(l.pos.z) < 40.0 and l.pos.x < -60.0 and west_lot == "":
			west_lot = k
			west = int(l.seg)
		elif l.pos.z > 5.0 and absf(l.pos.z) < 40.0 and l.pos.x > 60.0 and east_lot == "":
			east_lot = k
	var prng := RandomNumberGenerator.new()
	prng.seed = 5
	pz.traffic.close_segment(west, true, "never")
	_check(west >= 0 and not pz.traffic.add_trip(pz.lots[east_lot], pz.lots[west_lot], prng),
		"no car drives onto a street closed to cars")
	_check(not pz.traffic.may_enter(west, true), "and no truck when deliveries are never allowed")
	pz.traffic.close_segment(west, true, "always")
	_check(pz.traffic.may_enter(west, true) and not pz.traffic.may_enter(west, false),
		"trucks may deliver when allowed, cars still may not")
	var pz2 := CitySim.new()
	pz2.from_dict(JSON.parse_string(JSON.stringify(pz.to_dict())))
	_check(pz2.traffic.closed.get(west, pz2.traffic.closed.get(str(west), "")) == "always", "a closed street stays closed after a load")
	pz.traffic.close_segment(west, false)
	_check(pz.traffic.add_trip(pz.lots[east_lot], pz.lots[west_lot], prng), "reopened, cars drive there again")

	# A railroad crossing with the gates down: cars stop at the line short of
	# the track and wait, and go on once the gates lift.
	var rx := _crossroads()
	rx.economy.money = 1.0e9
	for i in 900:
		rx.tick()
	var xseg := -1
	for sid in rx.network.segments:
		var cv: Array = rx.network.curve_of(sid)
		if absf(cv[0].z) < 1.0 and absf(cv[2].z) < 1.0 and minf(cv[0].x, cv[2].x) < -100.0:
			xseg = sid
	var xing := {"seg": xseg, "pos": Vector3(-200, 0, 0), "piece": -1, "s": 0.0, "closed": true}
	rx.rail.crossings.append(xing)
	var crossed := 0
	var waiting := 0
	var last_d := {}
	for i in 400:
		rx.tick()
		for car in rx.traffic.cars:
			if car.j != null or not rx.traffic._xings.has(car.route[car.leg]):
				continue
			var cs: float = rx.traffic._xings[car.route[car.leg]][0][0]
			var line := cs - TrafficSim.XING_STOP
			var key := Vector2i(car.id, car.route[car.leg])
			if car.d + car.v * car.v / (2.0 * TrafficSim.MAX_BRAKE) < line:
				last_d[key] = car.d  # could still stop for the gates
			elif last_d.has(key) and car.d > cs - 3.0:
				crossed += 1
				last_d.erase(key)
			if car.d < line + 1.5 and car.d > line - 8.0 and car.v < 0.3:
				waiting += 1
	_check(xseg >= 0 and crossed == 0, "no car drives onto a crossing with the gates down (%d did)" % crossed)
	_check(waiting > 0, "cars wait at the crossing line")
	xing.closed = false
	var went := 0
	for i in 300:
		rx.tick()
		for car in rx.traffic.cars:
			if car.j == null and rx.traffic._xings.has(car.route[car.leg]):
				var cs2: float = rx.traffic._xings[car.route[car.leg]][0][0]
				var key := Vector2i(car.id, car.route[car.leg])
				if last_d.has(key) and last_d[key] < cs2 - 3.0 and car.d > cs2 + 3.0:
					went += 1
					last_d.erase(key)
	_check(went > 0, "the gates lift and cars drive over the track (%d)" % went)

	# A walk on the trail: out along the sidewalk to where the trail crosses
	# the street, along it and back home.
	var tw := rx
	while tw.people.people.size() < 20 and tw.tick_count < 6000:
		tw.tick()
	tw.parks.trails.paths.append({"kind": "greenway", "pts": [[-200, -300], [-200, -100], [-200, 100], [-200, 300]]})
	var walker_pid := -1
	var pids: Array = tw.people.people.keys()
	pids.sort()
	for pid in pids:
		if tw.people.people[pid].at == "" and tw.traffic.stroll(pid):
			walker_pid = pid
			break
	_check(walker_pid != -1, "someone at home goes for a walk on the trail")
	if walker_pid != -1:
		var sw := tw.traffic.walker_of(walker_pid)
		var on_trail := false
		for q in sw.pts:
			on_trail = on_trail or (absf(q.x + 200.0) < 0.5 and absf(q.z) > 30.0)
		_check(on_trail and sw.pts[0].distance_to(sw.pts[sw.pts.size() - 1]) < 0.01 and sw.len > 800.0,
			"along the trail and back to the same door (%d m)" % roundi(sw.len))
		_check(not tw.traffic.stroll(walker_pid), "not twice at once")
		for i in int(sw.len / (TrafficSim.WALK_V * 0.85 * TrafficSim.DT)) + 5:
			tw.tick()
		_check(tw.people.people[walker_pid].at == "", "and home again after the walk")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _l_town() -> CitySim:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	sim.apply({"type": "build_road", "start": [300, 0], "ctrl": [300, 150], "end": [300, 300]})
	for x in range(-300, 0, 8):
		sim.apply({"type": "paint_zone", "center": [x, -15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	for z in range(20, 300, 8):
		sim.apply({"type": "paint_zone", "center": [315, z], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
		sim.apply({"type": "paint_zone", "center": [285, z], "radius": 10, "zone": ZoneMap.Zone.COMMERCIAL})
	return sim


## Every vehicle in town, by id: [where it's based ("edge" for ones passing
## through from out of town), its owner, whether it's being retired].
func _vehicle_ids(t: TrafficSim) -> Dictionary:
	var out := {}
	for list in [t.cars, t.parked, t._waiting]:
		for car in list:
			out[car.id] = [str(car.get("base", "")), int(car.get("owner", -1)), car.get("retire", false)]
	return out


## Two avenues crossing, homes on one, shops and factories on the other.
func _crossroads() -> CitySim:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [0, -400], "ctrl": [0, 0], "end": [0, 400], "road": RoadStyle.Type.AVENUE})
	for k in range(-380, 380, 8):
		if absi(k) < 40:
			continue
		var zx := ZoneMap.Zone.RESIDENTIAL
		var zz := ZoneMap.Zone.COMMERCIAL if k < 0 else ZoneMap.Zone.INDUSTRIAL
		sim.apply({"type": "paint_zone", "center": [k, -18], "radius": 10, "zone": zx})
		sim.apply({"type": "paint_zone", "center": [k, 18], "radius": 10, "zone": zx})
		sim.apply({"type": "paint_zone", "center": [-18, k], "radius": 10, "zone": zz})
		sim.apply({"type": "paint_zone", "center": [18, k], "radius": 10, "zone": zz})
	return sim


## Pairs of cars inside one junction on paths that cross.
func _clashes(t: TrafficSim) -> int:
	var by_node := {}
	for car in t.cars:
		if car.j != null:
			if not by_node.has(car.j.node):
				by_node[car.j.node] = []
			by_node[car.j.node].append(car)
	var bad := 0
	for n in by_node:
		var list: Array = by_node[n]
		for i in list.size():
			for k in range(i + 1, list.size()):
				var a: Dictionary = list[i].j
				var b: Dictionary = list[k].j
				if a.wo == b.wo and a.lo == b.lo:
					continue  # merging one after another is fine
				if t._conflicts(a, b):
					bad += 1
	return bad


## Cars on the same lane nearer than a car length (should never happen).
func _crowding(t: TrafficSim) -> int:
	var lanes := {}
	for car in t.cars:
		if car.j != null or car.lc_t < 1.0:
			continue
		var key = car.route[car.leg] * 8 + car.lane
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


func _fingerprint(t: TrafficSim) -> String:
	var parts := []
	for car in t.cars:
		parts.append("%d:%d:%d:%.3f" % [car.id, car.route[car.leg], car.lane, car.d])
	return ",".join(parts)


var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
