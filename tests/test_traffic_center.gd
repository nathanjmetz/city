extends SceneTree
## The Traffic Management Center (stage 4 of docs/spec-traffic-control.md;
## Nathan, 2026-10-25: "I could eventually build a traffic flow building
## ... and they would fine-tune all of that for me"). Its engineers count
## the cars at each light and give the busy way more green; a light the
## player timed stays the player's; the timing survives a save; and when
## the center goes, the lights go back.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


## Busy east-west, a trickle north-south, at both lights. A map edge lets
## a car out only every few seconds, so the east-west ones are set on the
## avenue in small bunches, 200 m before the first light.
func _drive(sim: CitySim, ticks: int) -> void:
	var t := sim.traffic
	for i in ticks:
		if i % 40 == 0:
			var before: int = t._waiting.size()
			for k in 4:
				t.dispatch({"ref": "edge", "pos": Vector3(-390, 0, 0)}, {"ref": "edge", "pos": Vector3(690, 0, 0)}, "commute", {}, "sedan")
			var fresh: Array = t._waiting.slice(before)
			t._waiting.resize(before)
			var k := 0
			for car in fresh:
				var lanes: Array = t.lanes_for(int(car.route[0]), int(car.route[1])) if car.route.size() >= 2 else []
				if lanes.is_empty():
					continue
				car.lane = lanes[k % lanes.size()]
				car.d = 200.0 - 12.0 * float(k / lanes.size())
				car.v = 12.0
				t.cars.append(car)
				k += 1
		if i % 60 == 30:
			t.dispatch({"ref": "edge", "pos": Vector3(0, 0, -290)}, {"ref": "edge", "pos": Vector3(0, 0, 290)}, "commute")
			t.dispatch({"ref": "edge", "pos": Vector3(300, 0, 290)}, {"ref": "edge", "pos": Vector3(300, 0, -290)}, "commute")
		sim.tick()


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	sim.charter.reached["city"] = 0  # a city: the center is open to build
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [150, 0], "end": [700, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [0, -300], "ctrl": [0, 0], "end": [0, 300], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [300, -300], "ctrl": [300, 0], "end": [300, 300], "road": RoadStyle.Type.AVENUE})
	sim.tick()
	var a := sim.network.find_node_near(Vector3.ZERO, 1.0)
	var b := sim.network.find_node_near(Vector3(300, 0, 0), 1.0)
	var standard: Array = sim.traffic.greens_at(a)
	var ew := -1
	for i in sim.traffic.junctions[a].phases.size():
		var wi: int = sim.traffic.junctions[a].phases[i].ways.keys()[0]
		if absf(sim.traffic.stop_line(wi).dir.x) > 0.7:
			ew = i
	_check(ew != -1 and standard.size() == 2, "two avenues crossing: an east-west and a north-south green (%s)" % [standard])
	_drive(sim, 400)
	_check(sim.traffic.tuned.is_empty() and sim.traffic.greens_at(a) == standard, "no center, no engineers: standard timing")
	# The player times light b by hand.
	sim.apply({"type": "set_green", "node": b, "phase": 0, "seconds": 40.0})
	var mine: Array = sim.traffic.greens_at(b)
	var site := Services.site_near(sim.network, Services.Kind.TRAFFIC_CENTER, Vector3(-200, 0, 40))
	var town := CitySim.new()
	_check(town.charter.locked(Services.Kind.TRAFFIC_CENTER) != "", "a small town can't build one yet (it comes with a city charter)")
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.TRAFFIC_CENTER, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a traffic management center is built")
	var tmc := sim.services.traffic_center()
	_check(sim.traffic.engineers, "its engineers start counting at once")
	sim.construction.sites.erase("svc:%d" % tmc)  # built and open (a test needn't wait the weeks)
	var other := Services.site_near(sim.network, Services.Kind.TRAFFIC_CENTER, Vector3(500, 0, -40))
	_check(sim.services.site_problem(sim.network, Services.Kind.TRAFFIC_CENTER, other[0], other[1]) != "", "one per town")
	_drive(sim, 1500)
	var g: Array = sim.traffic.greens_at(a)
	print("standard %s, tuned %s, counts %s" % [standard, g, sim.traffic.demand.get(a, {})])
	_check(sim.traffic.tuned.has(a), "the engineers retimed the busy light")
	_check(float(g[ew]) > float(standard[ew]) and float(g[1 - ew]) < float(standard[1 - ew]),
		"east-west, the busy way, gets more green; north-south less (%s from %s)" % [g, standard])
	_check(sim.traffic.retimed.has(a), "the light's panel can say when they retimed it")
	_check(not sim.traffic.tuned.has(b) and sim.traffic.greens_at(b) == mine, "the light the player timed stays the player's")
	# Copies agree after a save and load, through a retiming.
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	sim.tick()
	copy.tick()
	_check(copy.traffic.greens_at(a) == sim.traffic.greens_at(a) and copy.traffic.engineers, "the timing survives a save and load")
	for i in TrafficSim.RETUNE_EVERY + 10:
		sim.tick()
		copy.tick()
	_check(JSON.stringify(copy.traffic.engineers_to_dict()) == JSON.stringify(sim.traffic.engineers_to_dict())
		and copy.traffic.greens_at(a) == sim.traffic.greens_at(a), "and both copies retime alike")
	# The center goes: the lights go back at once, and a copy saved right
	# after agrees.
	_check(sim.apply({"type": "remove_service", "id": tmc}), "the center can be demolished")
	var after := CitySim.new()
	after.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	for i in TrafficSim.RETUNE_EVERY + 10:
		sim.tick()
		after.tick()
	_check(not after.traffic.engineers and after.traffic.tuned.is_empty() and after.traffic.greens_at(a) == standard,
		"a copy saved just after the demolition has standard timing too")
	_check(sim.traffic.tuned.is_empty() and sim.traffic.greens_at(a) == standard, "without it, standard timing comes back (%s)" % [sim.traffic.greens_at(a)])
	_check(sim.traffic.greens_at(b) == mine, "and the player's own timing stays")
	# A green wave the player links stays theirs at both ends.
	var w := CitySim.new()
	w.economy.money = 50_000_000
	w.charter.reached["city"] = 0
	w.apply({"type": "build_road", "start": [-400, 0], "ctrl": [150, 0], "end": [700, 0], "road": RoadStyle.Type.AVENUE})
	w.apply({"type": "build_road", "start": [0, -300], "ctrl": [0, 0], "end": [0, 300], "road": RoadStyle.Type.AVENUE})
	w.apply({"type": "build_road", "start": [300, -300], "ctrl": [300, 0], "end": [300, 300], "road": RoadStyle.Type.AVENUE})
	w.tick()
	var wa := w.network.find_node_near(Vector3.ZERO, 1.0)
	var wb := w.network.find_node_near(Vector3(300, 0, 0), 1.0)
	w.apply({"type": "link_wave", "from": wa, "to": wb, "v": 15.6})
	var ws := Services.site_near(w.network, Services.Kind.TRAFFIC_CENTER, Vector3(-200, 0, 40))
	w.apply({"type": "place_service", "kind": Services.Kind.TRAFFIC_CENTER, "pos": [ws[0].x, ws[0].z], "dir": [ws[1].x, ws[1].z]})
	w.construction.sites.erase("svc:%d" % w.services.traffic_center())
	var cyc: float = w.traffic.junctions[wa].cycle
	_drive(w, 1500)
	_check(not w.traffic.tuned.has(wa) and not w.traffic.tuned.has(wb)
		and is_equal_approx(w.traffic.junctions[wa].cycle, cyc) and is_equal_approx(w.traffic.junctions[wb].cycle, cyc),
		"a green wave keeps its timing at both lights (%.1f s, %.1f s)" % [w.traffic.junctions[wa].cycle, w.traffic.junctions[wb].cycle])
	print("traffic center: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
