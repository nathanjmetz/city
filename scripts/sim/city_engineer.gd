class_name CityEngineer
extends RefCounted
## The city engineer (Brawn, 2026-10-23: "very late in the game ... a
## request to turn an alley into a road or to turn a road into a 6 lane
## road. This would be proposed by a civil engineer."). Once the town is
## big enough to hire one, the engineer counts rush-hour traffic like a real
## traffic count and brings the worst problem to the bell, one at a time,
## each with a ghost, an argument for why and what it costs:
## - a two-lane road jammed at rush hour: widen it to four lanes, or add a
##   centre turn lane;
## - an alley carrying through traffic: pave it into a street;
## - a hub's own road (a farm lane, an oil company's lease road) that has
##   become a shortcut for everyone else (Brawn: "the tension between the
##   will of hub leaders and the mayor is where the game sings"): pave it
##   as a public street, or make it local traffic only.
## The town pays for what it approves.
##
## Real: a city engineer's capital improvement plan, triggered by traffic
## counts. Highway Capacity Manual: an urban street at under 40% of its
## free-flow speed is level of service E or F; a two-lane road carries up
## to about 15,000 cars a day, a three-lane (centre turn lane) about
## 20,000, four lanes about 30,000 to 35,000. Gravel lease roads are
## private haul roads; counties post them "local traffic only" or pave them
## when the public starts using them.
##
## A few counts at rush hour (cars already on the roads) and one look a
## month: no per-frame work.

signal changed

const HUB := "engineer"
const TWO_LANE := [RoadStyle.Type.STREET, RoadStyle.Type.STREET_NARROW, RoadStyle.Type.COUNTY, RoadStyle.Type.MAIN_STREET,
	RoadStyle.Type.STREET_BIKE]

## This month's counts: segment -> [rush-hour samples with cars, slow
## samples, through cars on a hub's road]. Saved (the month's answer
## depends on them).
var counts := {}
## Rush-hour counts taken this month.
var samples := 0
## Open proposals: permit id -> true.
var pending := {}


## A rush-hour count (CitySim, at the top of each rush hour): every car on
## the roads, where it is, and whether it has any business on a hub road.
func count(sim) -> void:
	if int(sim.stats.population) < Balance.ENGINEER_CUT_MIN_POP:
		return
	samples += 1
	var t: TrafficSim = sim.traffic
	var seen := {}
	for list in [t.cars, t.flowing]:
		for car in list:
			if not car.has("route") or not car.has("leg"):
				continue
			var route: Array = car.route
			var leg := int(car.leg)
			if leg < 0 or leg >= route.size():
				continue
			var seg := int(route[leg]) >> 1
			var s: Dictionary = sim.network.segments.get(seg, {})
			if s.is_empty():
				continue
			var c: Array = counts.get(seg, [0, 0, 0])
			if not seen.has(seg):
				seen[seg] = true
				c[0] += 1
				if minf(t.way_speed(seg * 2), t.way_speed(seg * 2 + 1)) < Balance.ENGINEER_SLOW_SHARE:
					c[1] += 1
			var by := str(s.get("built_by", ""))
			if by != "" and str(car.get("from_ref", "")).get_slice("@", 0) != by \
					and str(car.get("to_ref", "")).get_slice("@", 0) != by:
				c[2] += 1
			counts[seg] = c


## Once a month: the worst problem found goes to the bell, then the counts
## start over.
func month(sim) -> void:
	var found := _worst(sim)
	counts = {}
	samples = 0
	if found.is_empty() or not pending.is_empty():
		return
	if not sim.permits.can_file(sim, HUB, 1):
		return
	var seed := hash([sim.city_seed, sim.tick_count, HUB])
	var surname := Names.surname(seed)
	var id: int = sim.permits.file(sim, {"hub": HUB, "hub_id": 1, "leader": "City engineer " + Names.person(seed, surname),
		"title": found.title, "why": found.why, "change": found.change, "area": found.options[0].outline,
		"options": found.options})
	if id > 0:
		pending[id] = true
		changed.emit()


## Carries out approved proposals (CitySim, every game hour). True when
## roads changed.
func carry_out(sim) -> bool:
	var did := false
	var ids := pending.keys()
	ids.sort()
	for id in ids:
		var st: int = sim.permits.state_of(id)
		if st == Permits.State.OPEN or st == Permits.State.SHELVED:
			continue
		if st != Permits.State.APPROVED:
			pending.erase(id)
			changed.emit()
			continue
		var req: Dictionary = sim.permits.requests[id]
		var o: Dictionary = req.options[clampi(int(req.get("pick", 0)), 0, req.options.size() - 1)]
		var cost := _cost_now(sim, o)
		if cost > int(sim.economy.money):
			req.note = "Waiting until the town has $%s." % CitySim.money_text(cost)
			continue
		var segs: Array = Array(o.segs).map(func(x): return int(x))
		match str(o.fix):
			"upgrade":
				for seg in segs:
					sim.network.set_type(seg, int(o.to))
			"local":
				for seg in segs:
					if sim.network.segments.has(seg):
						sim.traffic.close_segment(seg, true, "always")
		sim.economy.money -= cost
		pending.erase(id)
		sim.permits.done(id)
		did = true
		changed.emit()
	return did


## What an option costs the town today (roads may have changed since).
static func _cost_now(sim, o: Dictionary) -> int:
	if str(o.fix) == "local":
		return Balance.ENGINEER_SIGN_COST
	var cost := 0
	for seg in o.segs:
		cost += maxi(0, sim.upgrade_cost(int(seg), int(o.to)))
	return cost


# --------------------------------------------------------------- finding

## The worst problem in this month's counts: {title, why, change, options}
## or {}. A hub road used as a shortcut first (it's the one nobody else
## will notice), then the most jammed road, then a busy alley.
func _worst(sim) -> Dictionary:
	if samples <= 0:
		return {}
	var pop := int(sim.stats.population)
	var ids := counts.keys()
	ids.sort()
	# Shortcuts through a hub's road.
	var by_hub := {}
	for seg in ids:
		var s: Dictionary = sim.network.segments.get(seg, {})
		var by := str(s.get("built_by", ""))
		if by != "" and int(counts[seg][2]) > 0:
			by_hub[by] = int(by_hub.get(by, 0)) + int(counts[seg][2])
	var hubs := by_hub.keys()
	hubs.sort()
	var best_hub := ""
	for h in hubs:
		if int(by_hub[h]) >= Balance.ENGINEER_CUT_CARS and (best_hub == "" or int(by_hub[h]) > int(by_hub[best_hub])):
			best_hub = h
	if best_hub != "":
		return _shortcut(sim, best_hub, int(by_hub[best_hub]))
	if pop < Balance.ENGINEER_MIN_POP:
		return {}
	# The most jammed two-lane road.
	var worst := -1
	for seg in ids:
		var c: Array = counts[seg]
		var s: Dictionary = sim.network.segments.get(seg, {})
		if s.is_empty() or not int(s.type) in TWO_LANE or str(s.get("built_by", "")) != "":
			continue
		if float(c[1]) / samples >= Balance.ENGINEER_JAMMED and (worst == -1 or int(c[1]) > int(counts[worst][1])):
			worst = seg
	if worst != -1:
		return _widen(sim, worst)
	# An alley used as a street.
	for seg in ids:
		var s: Dictionary = sim.network.segments.get(seg, {})
		if not s.is_empty() and int(s.type) == RoadStyle.Type.ALLEY and float(counts[seg][0]) / samples >= Balance.ENGINEER_ALLEY_BUSY:
			return _alley(sim, seg)
	return {}


func _shortcut(sim, by: String, cars: int) -> Dictionary:
	var segs := []
	for seg in sim.network.segments:
		if str(sim.network.segments[seg].get("built_by", "")) == by and not sim.traffic.closed.has(seg):
			segs.append(seg)
	segs.sort()
	if segs.is_empty():
		return {}
	var whose: String = sim.families.name_of(by)
	var what := "farm lane" if by.begins_with("farm:") else "lease road"
	var owner := "the farm" if by.begins_with("farm:") else "the company"
	var road := ("%s's gravel %s" % [whose, what]) if whose != "" else "the gravel %s" % what
	var pave := _option(sim, "A", "Pave it as a town street", segs, "upgrade", RoadStyle.Type.STREET)
	pave.lines = ["The town takes it over: a paved street anyone may use, built for the traffic it already carries.",
		"$%s a year more to keep up" % CitySim.money_text(pave.upkeep)]
	var local := _option(sim, "B", "Local traffic only", segs, "local", -1)
	local.cost = Balance.ENGINEER_SIGN_COST
	local.lines = ["Signs and a gate arm: %s's trucks only. Through drivers go back to the town's roads." % (whose if whose != "" else owner),
		"Cheap, but that traffic lands on your other roads."]
	return {"title": ("%s's %s has become a shortcut" % [whose, what]) if whose != "" else "A %s has become a shortcut" % what,
		"why": "At rush hour I counted %d cars on %s with no business there. It was built for %s's own trucks, not through traffic, and the neighbors are noticing the dust and the speed." % [
			cars, road, owner],
		"change": "Fix a shortcut", "options": [pave, local]}


func _widen(sim, seg: int) -> Dictionary:
	var run := _run(sim, seg, func(s): return int(counts.get(s, [0, 0, 0])[1]) > 0)
	var name: String = sim.streets.name_of(seg)
	var road := name if name != "" else "this road"
	var four := _option(sim, "A", "Widen to four lanes", run, "upgrade", RoadStyle.Type.AVENUE)
	four.lines = ["Carries about 30,000 cars a day instead of 15,000.", "$%s a year more to keep up, and more to resurface later" % CitySim.money_text(four.upkeep)]
	var turn := _option(sim, "B", "Add a centre turn lane", run, "upgrade", RoadStyle.Type.AVENUE_TURN)
	turn.lines = ["Left turns wait in the middle: about 20,000 cars a day. Cheaper, less room taken.",
		"$%s a year more to keep up" % CitySim.money_text(turn.upkeep)]
	return {"title": "Widen %s" % road,
		"why": "At rush hour %s crawls at under %d%% of its speed limit (level of service E or F). A two-lane road carries about 15,000 cars a day. Here are two ways to give it room." % [
			road, roundi(Balance.ENGINEER_SLOW_SHARE * 100)],
		"change": "Widen a road", "options": [four, turn]}


func _alley(sim, seg: int) -> Dictionary:
	var run := _run(sim, seg, func(s): return int(sim.network.segments[s].type) == RoadStyle.Type.ALLEY and counts.has(s))
	var street := _option(sim, "A", "Pave it into a street", run, "upgrade", RoadStyle.Type.STREET_NARROW)
	street.lines = ["A narrow street, with room for the traffic and curbs for the yards.",
		"$%s a year more to keep up" % CitySim.money_text(street.upkeep)]
	return {"title": "Turn a busy alley into a street",
		"why": "Drivers are using this alley as a street at rush hour. Alleys are built for garbage trucks and garages, not through traffic.",
		"change": "Alley to street", "options": [street]}


## The road pieces joined to `seg` end to end, of the same kind, that pass
## `keep` (up to ENGINEER_RUN pieces): the stretch to fix as one job.
func _run(sim, seg: int, keep: Callable) -> Array:
	var type := int(sim.network.segments[seg].type)
	var out := [seg]
	var queue := [seg]
	while not queue.is_empty() and out.size() < Balance.ENGINEER_RUN:
		var s: Dictionary = sim.network.segments[queue.pop_front()]
		for n in [s.a, s.b]:
			for other in sim.network.segments_at(n):
				if out.has(other) or int(sim.network.segments[other].type) != type or not keep.call(other):
					continue
				out.append(other)
				queue.append(other)
	out.sort()
	return out


## An option for the card: its streets as a ghost, its outline, the cost
## to the town and the upkeep it adds.
func _option(sim, letter: String, name: String, segs: Array, fix: String, to: int) -> Dictionary:
	var lines := []
	var pts := PackedVector2Array()
	var upkeep := 0.0
	var cost := 0
	for seg in segs:
		var c: Array = sim.network.curve_of(seg)
		lines.append([[snappedf(c[0].x, 0.01), snappedf(c[0].z, 0.01)], [snappedf(c[2].x, 0.01), snappedf(c[2].z, 0.01)]])
		for p in [c[0], c[1], c[2]]:
			pts.append(Vector2(p.x, p.z))
		if to >= 0:
			cost += maxi(0, sim.upgrade_cost(seg, to))
			upkeep += Economy.road_upkeep(c, to) - Economy.road_upkeep(c, int(sim.network.segments[seg].type))
	var hull := Geometry2D.convex_hull(pts)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	var outline := []
	if hull.size() >= 4:
		var grown := Geometry2D.offset_polygon(hull, 12.0)
		for p in (grown[0] if not grown.is_empty() else hull):
			outline.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	else:
		box = box.grow(12.0)
		for p in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
			outline.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return {"letter": letter, "name": name, "fix": fix, "to": to, "segs": segs, "streets": lines, "ghost": [],
		"outline": outline, "cost": cost, "upkeep": roundi(maxf(upkeep, 0.0) * 12.0), "lines": []}


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var c := {}
	for seg in counts:
		c[str(seg)] = counts[seg]
	return {"counts": c, "samples": samples, "pending": pending.keys()}


func from_dict(d: Dictionary) -> void:
	counts.clear()
	pending.clear()
	var c: Dictionary = d.get("counts", {})
	for k in c:
		counts[int(k)] = Array(c[k]).map(func(x): return int(x))
	samples = int(d.get("samples", 0))
	for id in d.get("pending", []):
		pending[int(id)] = true
	changed.emit()
