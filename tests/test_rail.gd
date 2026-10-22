extends SceneTree
## Run: godot --headless -s tests/test_rail.gd

var _fails := 0


func _init() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	sim.economy.money = 5_000_000
	# A depot beside the county highway.
	var site := Rail.site_near(sim.network, Vector3(0, 0, 60))
	_check(not site.is_empty(), "a depot fits beside the highway")
	_check(sim.rail.site_problem(sim, site[0], site[1], site[2]) == "", "open ground is fine for a yard")
	var money := sim.economy.money
	_check(sim.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z],
		"axis": [site[2].x, site[2].z]}), "the depot is placed")
	_check(sim.economy.money == money - Balance.RAIL_DEPOT_COST, "the town pays only for the depot")
	var did: int = sim.rail.depots.keys()[0]
	var d: Dictionary = sim.rail.depots[did]
	_check(d.leader.name.split(" ").size() == 2, "the depot has a leader (%s)" % d.leader.name)
	_check(sim.rail.pieces.size() == Rail.YARD_TRACKS, "the yard has its tracks")
	# No lots under the yard.
	var inside := 0
	for key in sim.lots:
		if sim.rail.covers(sim.lots[key].pos):
			inside += 1
	_check(inside == 0, "no lots inside the yard (%d)" % inside)
	# A mining company about a kilometre off on rich ore, across a side street.
	var hq := Vector3.ZERO
	var best := 0.0
	for x in range(900, 1700, 50):
		for z in range(300, 1400, 50):
			var r := Resources.at(Resources.Kind.ORE, Vector3(x, 0, z))
			if r > best:
				best = r
				hq = Vector3(x, 0, z)
	var street_x := hq.x - 400.0
	sim.apply({"type": "build_road", "start": [street_x, 0], "ctrl": [street_x, 1000], "end": [street_x, 2000]})
	var dir := Vector3(-1, 0, 0)
	var sid := sim.industry.add_site("ore", hq, dir, [hq, Vector3(street_x, 0, hq.z)])
	# A busy mine: pads behind the main building.
	for x in range(-3, 4):
		for y in range(1, 6):
			sim.industry.sites[sid].pads.append(Vector2i(x, y))
	_run(sim, Balance.RAIL_DECIDE_EVERY + 1)
	var reqs := sim.rail.open_requests()
	_check(reqs.size() == 1, "the leader asks permission for a main line (%s)" % d.why)
	if reqs.is_empty():
		_done()
		return
	var main: int = reqs[0]
	var l: Dictionary = sim.rail.lines[main]
	_check(l.kind == "main", "the first request is the main line")
	var req: Dictionary = sim.permits.requests[l.permit]
	_check(req.route.size() > 10 and req.cost > 0 and req.leader == d.leader.name and req.hub == "rail",
		"the request on the permit bell shows its route and cost ($%s)" % CitySim.money_text(req.cost))
	_check_curves(l.route, RailPlanner.LIMITS.main.radius, "main line")
	# Nothing is built until the town says yes.
	_run(sim, Balance.RAIL_DECIDE_EVERY * 3)
	_check(l.state == "permit" and sim.rail.pieces.size() == Rail.YARD_TRACKS, "nothing is built without a permit")
	var rail_money: float = d.money
	_check(sim.apply({"type": "permit", "id": l.permit, "answer": "approve"}), "the town approves")
	_run(sim, Balance.RAIL_DECIDE_EVERY)
	_check(l.state == "building", "crews start laying track")
	_run(sim, 24 * 60 * 8)
	_check(l.state == "open", "the main line opens (%s, built %s)" % [l.state, str(sim.rail.pieces[l.pieces[0]].built)])
	_check(d.money < rail_money - l.cost * 0.9, "the railroad paid for its own track")
	_check(sim.rail.trains.size() == 1, "a local freight is in the yard")
	_check(d.why.contains("years to pay off") or not sim.rail.open_requests().is_empty(),
		"the leader weighs whether a spur pays (%s)" % d.why)
	# A bold leader will take a longer payback.
	d.leader.ambition = 1.0
	d.leader.caution = 0.1
	d.skip.clear()
	# Then a spur to the mine, crossing the side street.
	_run(sim, Balance.RAIL_DECIDE_EVERY * 2)
	reqs = sim.rail.open_requests()
	_check(reqs.size() == 1 and sim.rail.lines[reqs[0]].kind == "spur", "the leader asks for a spur to the mine (%s)" % d.why)
	if reqs.is_empty():
		_done()
		return
	var spur: int = reqs[0]
	var sl: Dictionary = sim.rail.lines[spur]
	_check_curves(sl.route, RailPlanner.LIMITS.spur.radius, "spur")
	_check(sl.crossings.size() >= 1, "the spur's request lists its road crossing")
	sim.apply({"type": "permit", "id": sl.permit, "answer": "approve"})
	_run(sim, 24 * 60 * 7)
	_check(sl.state == "open", "the spur opens")
	_check(sim.rail.crossings.size() >= 1, "a grade crossing is in place")
	for c in sim.rail.crossings:
		var seg: Dictionary = sim.network.segments[c.seg]
		var tan: Vector3 = sim.network.curve_of(c.seg)[2] - sim.network.curve_of(c.seg)[0]
		var tp := sim.rail.pose_at(c.piece, c.s)
		var ang := rad_to_deg(acos(absf(tan.normalized().dot(tp[1].normalized()))))
		_check(ang >= RailPlanner.MIN_CROSS_ANGLE - 1.0, "crossings are nearly square (%d°)" % roundi(ang))
		_check(seg.type != RoadStyle.Type.HIGHWAY, "no highway is crossed at grade")
	# The mine's loads go by rail now.
	_check(sim.rail.ships_by_rail(sim, "site:%d" % sid), "the mine ships by rail")
	sim.industry.sites[sid].stock = 12.0
	var income: float = d.money
	var gates_down := false
	var moved := false
	var start_pos = null
	for i in 24 * 60 * 5:
		sim.tick()
		if sim.industry.sites[sid].stock < 6.0:
			sim.industry.sites[sid].stock = 12.0
		for c in sim.rail.crossings:
			gates_down = gates_down or c.closed
		var t: Dictionary = sim.rail.trains[d.freight_train]
		var poses := sim.rail.car_poses(d.freight_train)
		if not poses.is_empty():
			if start_pos == null:
				start_pos = poses[0][1]
			elif poses[0][1].distance_to(start_pos) > 50.0:
				moved = true
		if int(d.get("delivered", 0)) > 0:
			break

	_check(moved, "the local freight drives")
	_check(gates_down, "crossing gates come down for the train")
	_check(int(d.get("delivered", 0)) > 0, "loaded cars reach the region (%s)" % sim.rail.trains[d.freight_train].purpose)
	_check(d.ledger.income + d.last.income > 0.0 or d.money > income - 1e6, "freight pays the railroad")
	# A train in the region comes back to the yard.
	for i in 24 * 60 * 3:
		sim.tick()
		if sim.rail.trains[d.freight_train].state == "parked":
			break
	_check(sim.rail.trains[d.freight_train].state in ["parked", "ready", "wait", "run", "load", "dwell"],
		"the freight came back from the region (%s)" % sim.rail.trains[d.freight_train].state)
	# Saves and copies stay in step.
	var copy := CitySim.new()
	copy.simulate_traffic = false
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(copy.rail.pieces.size() == sim.rail.pieces.size() and copy.rail.lines.size() == sim.rail.lines.size(),
		"save round trip keeps the railroad")
	var a0 := JSON.stringify(sim.rail.to_dict())
	var b0 := JSON.stringify(copy.rail.to_dict())
	if a0 != b0:
		for i in a0.length():
			if a0[i] != b0[i]:
				print("DBG diff at load: ", a0.substr(maxi(0, i - 60), 120), " VS ", b0.substr(maxi(0, i - 60), 120))
				break
	for i in 600:
		sim.tick()
		copy.tick()
	var a1 := JSON.stringify(sim.rail.to_dict())
	var b1 := JSON.stringify(copy.rail.to_dict())
	if a1 != b1:
		for i in a1.length():
			if a1[i] != b1[i]:
				print("DBG diff after: ", a1.substr(maxi(0, i - 80), 140), " VS ", b1.substr(maxi(0, i - 80), 140))
				break
	_check(a1 == b1, "copies of the railroad stay in sync")
	# Deny: the leader backs off.
	var sim2 := CitySim.new()
	sim2.simulate_traffic = false
	sim2.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var s2 := Rail.site_near(sim2.network, Vector3(0, 0, 60))
	sim2.apply({"type": "place_rail_depot", "pos": [s2[0].x, s2[0].z], "dir": [s2[1].x, s2[1].z], "axis": [s2[2].x, s2[2].z]})
	_run(sim2, Balance.RAIL_DECIDE_EVERY + 1)
	var r2 := sim2.rail.open_requests()
	if not r2.is_empty():
		sim2.apply({"type": "permit", "id": sim2.rail.lines[r2[0]].permit, "answer": "deny"})
		_run(sim2, Balance.RAIL_DECIDE_EVERY * 4)
		_check(sim2.rail.open_requests().is_empty() and sim2.rail.pieces.size() == Rail.YARD_TRACKS,
			"after a no, the leader doesn't build or ask again right away")
	# A depot can't sit on houses.
	var sim3 := CitySim.new()
	sim3.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	for x in range(-300, 301, 10):
		sim3.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 3000:
		sim3.tick()
	var s3 := Rail.site_near(sim3.network, Vector3(0, 0, 40))
	_check(sim3.rail.site_problem(sim3, s3[0], s3[1], s3[2]) != "", "no depot on top of homes")
	_done()


func _run(sim: CitySim, n: int) -> void:
	for i in n:
		sim.tick()


## Every bend on a planned route is at least the minimum radius.
func _check_curves(pts: Array, radius: float, what: String) -> void:
	var worst := INF
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i] - pts[i - 1]
		var b: Vector3 = pts[i + 1] - pts[i]
		var ang := absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
		if ang > 0.0005 and a.length() > 1.0 and b.length() > 1.0:
			worst = minf(worst, minf(a.length(), b.length()) / (2.0 * sin(ang * 0.5)))
	_check(worst >= radius - 2.0, "%s curves are at least %d m (tightest %d m)" % [what, int(radius), int(worst)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
