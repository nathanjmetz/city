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
