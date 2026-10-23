extends SceneTree
## Oil and timber companies grow to a real size and then build a road
## (Brawn, 2026-10-23): once a company has worked out its lease, it leases
## the next tract and lays a gravel lease road (or logging road) to it from
## the nearest public road, which joins the town's network.
## Run: godot --headless -s tests/test_industry_roads.gd

var _fails := 0


func _init() -> void:
	for kind in ["oil", "forest"]:
		_lease_road(kind)
	_quarry_never()
	_grows_from_profit()
	_field_drilled_out()
	_done()


func _best(res: int) -> Vector3:
	var best := Vector3.ZERO
	var best_v := 0.0
	for x in range(-3000, 3001, 150):
		for z in range(-3000, 3001, 150):
			var v := Resources.at(res, Vector3(x, 0, z))
			if v > best_v:
				best_v = v
				best = Vector3(x, 0, z)
	return best


func _company(sim: CitySim, kind: String) -> int:
	var best := _best(Industry.KINDS[kind].resource)
	sim.apply({"type": "build_road", "start": [best.x - 1800, best.z], "ctrl": [best.x, best.z],
		"end": [best.x + 1800, best.z]})
	for dx in [0, 200, -200, 400, -400]:
		if sim.apply({"type": "place_industry", "kind": kind, "pos": [best.x + dx, best.z + 30], "dir": [0, -1]}):
			return sim.industry.sites.keys()[-1]
	return -1


## Opens every pad that pays and is free on its lease, as years of growth would.
func _work_out(sim: CitySim, id: int) -> void:
	var s: Dictionary = sim.industry.sites[id]
	s.erase("regrow")
	for _k in 400:
		var c := Vector2i.MAX
		for cand in sim.industry._candidates(s):
			if Industry.richness(s, cand) >= Industry.MIN_RICHNESS and sim.industry.pad_profit(s, cand) > 0.0 \
					and sim.industry._free(id, s, cand, sim.field_usable):
				c = cand
				break
		if c == Vector2i.MAX:
			return
		s.pads.append(c)
		if s.kind == "forest":
			# Cut and resting: the whole woods has been through a cycle.
			s.pads.erase(c)
			if not s.has("regrow"):
				s.regrow = {}
			s.regrow[c] = sim.industry.day
	if s.kind == "forest":
		s.pads.append(s.regrow.keys()[0])
		s.regrow.erase(s.pads[0])


func _lease_road(kind: String) -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 50_000_000
	var id := _company(sim, kind)
	_check(id != -1, "%s: a company is placed" % kind)
	if id == -1:
		return
	var ind := sim.industry
	ind.price = 4.0
	ind.day = 1.0
	var s: Dictionary = ind.sites[id]
	s.pads.append(Vector2i(0, 2))
	_check(not ind.wants_road(id, sim.field_usable), "%s: a new company doesn't want a road" % kind)
	_work_out(sim, id)
	_check(ind.wants_road(id, sim.field_usable),
		"%s: worked out and paying, it wants new ground (%d pads, $%d a year)" % [kind, s.pads.size(), ind.yearly_profit(id)])
	var segs := sim.network.segments.size()
	var money := sim.economy.money
	var built := sim._industry_road(id)
	_check(built, "%s: it builds a lease road: %s" % [kind, s.get("why", "")])
	if not built:
		print("  next tract: %s, wait %s" % [str(ind.next_lease(id, sim.field_usable)), str(s.get("road_wait", 0))])
		return
	_check(sim.network.segments.size() > segs, "%s: the road is in the city's network" % kind)
	_check(sim.economy.money == money, "%s: the company pays for it, not the town" % kind)
	var gravel := false
	for seg in sim.network.segments.values():
		gravel = gravel or seg.type == RoadStyle.Type.GRAVEL
	_check(gravel, "%s: it starts as a gravel road" % kind)
	_check(s.leases.size() == 1 and s.leases[0].length() > Balance.LEASE_REACH_CELLS * 0.75,
		"%s: the new tract lies past its first lease (%s)" % [kind, str(s.leases)])
	sim._refresh()
	var past := false
	for c in ind._candidates(s):
		if c.length() > Balance.LEASE_REACH_CELLS and Industry.richness(s, c) >= Industry.MIN_RICHNESS \
				and ind._free(id, s, c, sim.field_usable):
			past = true
	_check(past, "%s: it can open pads on the new tract" % kind)
	var copy := Industry.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(ind.to_dict())))
	_check(copy.sites[id].leases == s.leases, "%s: its tracts survive a save" % kind)


## A company grows from its own money (Brawn, 2026-10-23): its startup
## cash opens its first pads, then it grows only as fast as it keeps
## profit, and dearer ground near town costs it more.
func _grows_from_profit() -> void:
	var best := _best(Resources.Kind.OIL)
	var ind := Industry.new()
	var id := ind.add_site("oil", best, Vector3(0, 0, -1), [])
	var s: Dictionary = ind.sites[id]
	var any := func(_m, _c): return true
	var unlimited := Industry.new()
	var uid := unlimited.add_site("oil", best, Vector3(0, 0, -1), [])
	unlimited.sites[uid].cash = 1.0e12
	for i in 40:
		unlimited.decide(any)
	ind.day = 1.0
	for i in 40:
		ind.decide(any)
	var first: int = s.pads.size()
	_check(first >= 1 and first < unlimited.sites[uid].pads.size(),
		"startup cash opens its first wells, not the whole field (%d of %d)" % [first, unlimited.sites[uid].pads.size()])
	_check(float(s.cash) >= 0.0, "it never spends more than it has ($%d)" % s.cash)
	# A month later: hardly any more saved, so no new wells.
	ind.day = 2.0
	ind.decide(any)
	_check(s.pads.size() <= first + 1, "a month's profit doesn't drill another field")
	# Years of kept profit pay for more.
	for m in 120:
		ind.day = 2.0 + m
		ind.decide(any)
	_check(s.pads.size() > first, "over ten years it drills more from what it kept (%d wells)" % s.pads.size())
	# Ground by a growing town costs a quarry more to take on.
	var q := Industry.new()
	var qid := q.add_site("ore", Vector3.ZERO, Vector3(0, 0, -1), [])
	var cheap := q.pad_price(q.sites[qid], Vector2i(0, 1))
	q.land_price_of = func(_p): return Balance.CAPITAL_LAND_PER_ACRE * 3.0
	_check(q.pad_price(q.sites[qid], Vector2i(0, 1)) > cheap, "a bench by town costs more than one out in the country")
	var copy := Industry.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(ind.to_dict())))
	_check(is_equal_approx(float(copy.sites[id].cash), float(s.cash)), "its money survives a save")


## An oil field is drilled out from the tank battery, offset by offset, and
## each new well gets a lease road branching back to the main road (Brawn,
## 2026-10-23: like someone is laying it out).
func _field_drilled_out() -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	var id := _company(sim, "oil")
	if id == -1:
		return
	var ind := sim.industry
	ind.price = 2.0
	var s: Dictionary = ind.sites[id]
	s.cash = 50_000_000.0
	var roads := sim.network.segments.size()
	for i in 30:
		ind.day = 1.0 + i
		ind.decide(sim.field_usable)
	_check(s.pads.size() >= 3, "it drills several wells (%d)" % s.pads.size())
	var joined := true
	for c in s.pads:
		var near: bool = maxi(absi(c.x), absi(c.y)) <= Balance.OIL_OFFSET_CELLS
		for o in s.pads:
			if o != c and maxi(absi(o.x - c.x), absi(o.y - c.y)) <= Balance.OIL_OFFSET_CELLS:
				near = true
		joined = joined and near
	_check(joined, "every well is an offset to another, none a mile off (%s)" % str(s.pads))
	var reached := true
	for c in s.pads:
		reached = reached and not sim.network.find_segment_near(Industry.pad_center(s, c), Industry.PAD * 0.9, 2.0).is_empty()
	_check(reached, "every well has a road to it")
	_check(sim.network.segments.size() > roads, "the company laid lease roads (%d pieces)" % (sim.network.segments.size() - roads))


## A quarry widens from its plant; it never leases far ground.
func _quarry_never() -> void:
	var ind := Industry.new()
	var id := ind.add_site("ore", Vector3.ZERO, Vector3(0, 0, -1), [])
	ind.sites[id].pads = [Vector2i(0, 1)]
	_check(not ind.wants_road(id, func(_m, _c): return false), "a quarry doesn't build lease roads")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _done() -> void:
	print("ALL TESTS PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(0 if _fails == 0 else 1)
