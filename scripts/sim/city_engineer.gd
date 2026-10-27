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
## - a neighborhood with only one road in and more than 30 homes: a new
##   street to give it a second way in, well apart from the first.
## The town pays for what it approves.
##
## Real: a city engineer's capital improvement plan, triggered by traffic
## counts. Highway Capacity Manual: an urban street at under 40% of its
## free-flow speed is level of service E or F; a two-lane road carries up
## to about 15,000 cars a day, a three-lane (centre turn lane) about
## 20,000, four lanes about 30,000 to 35,000. The fire code asks for two
## separate ways in once a development passes 30 homes, apart by at least
## half its width, so one blocked road can't cut it off (International Fire
## Code D107; subdivision rules make builders stub streets to the next
## parcel for the same reason). Gravel lease roads are
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
## One-way-in neighborhoods already brought up: the road in -> tick. Saved.
var asked := {}
## The road network's bridges (not saved: from the roads), and the
## network revision they were worked out for.
var _graph := {}
var _rev := -1


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
			"link":
				var a := Vector3(float(o.link[0][0]), float(o.link[0][1]), float(o.link[0][2]))
				var b := Vector3(float(o.link[1][0]), float(o.link[1][1]), float(o.link[1][2]))
				if not sim.subdivisions._line_clear(sim, a, b):
					req.note = "Something is in the way now."
					pending.erase(id)
					sim.permits.done(id)
					changed.emit()
					continue
				var money: int = sim.economy.money
				sim.network.build_road(a, (a + b) * 0.5, b, RoadStyle.Type.STREET)
				sim.economy.money = money
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
	if str(o.fix) == "link":
		return int(o.cost)
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
	# A neighborhood one blocked road away from being cut off comes first.
	var cut_off := _one_way(sim)
	if not cut_off.is_empty():
		return cut_off
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
		"$%s more every 12 days to keep up" % CitySim.money_text(pave.upkeep)]
	var local := _option(sim, "B", "Local traffic only", segs, "local", -1)
	local.cost = Balance.ENGINEER_SIGN_COST
	local.lines = ["Signs and a gate arm: %s's trucks only. Through drivers go back to the town's roads." % (whose if whose != "" else owner),
		"Cheap, but that traffic lands on your other roads."]
	return {"title": ("%s's %s has become a shortcut" % [whose, what]) if whose != "" else "%s has become a shortcut" % Words.a_first(what),
		"why": "At rush hour I counted %d cars on %s with no business there. It was built for %s's own trucks, not through traffic, and the neighbors are noticing the dust and the speed." % [
			cars, road, owner],
		"change": "Fix a shortcut", "options": [pave, local]}


func _widen(sim, seg: int) -> Dictionary:
	var run := _run(sim, seg, func(s): return int(counts.get(s, [0, 0, 0])[1]) > 0)
	var name: String = sim.streets.name_of(seg)
	var road := name if name != "" else "this road"
	var four := _option(sim, "A", "Widen to four lanes", run, "upgrade", RoadStyle.Type.AVENUE)
	four.lines = ["Carries about 30,000 cars a day instead of 15,000.", "$%s more every 12 days to keep up, and more to resurface later" % CitySim.money_text(four.upkeep)]
	var turn := _option(sim, "B", "Add a centre turn lane", run, "upgrade", RoadStyle.Type.AVENUE_TURN)
	turn.lines = ["Left turns wait in the middle: about 20,000 cars a day. Cheaper, less room taken.",
		"$%s more every 12 days to keep up" % CitySim.money_text(turn.upkeep)]
	return {"title": "Widen %s" % road,
		"why": "At rush hour %s crawls at under %d%% of its speed limit (level of service E or F). A two-lane road carries about 15,000 cars a day. Here are two ways to give it room." % [
			road, roundi(Balance.ENGINEER_SLOW_SHARE * 100)],
		"change": "Widen a road", "options": [four, turn]}


func _alley(sim, seg: int) -> Dictionary:
	var run := _run(sim, seg, func(s): return int(sim.network.segments[s].type) == RoadStyle.Type.ALLEY and counts.has(s))
	var street := _option(sim, "A", "Pave it into a street", run, "upgrade", RoadStyle.Type.STREET_NARROW)
	street.lines = ["A narrow street, with room for the traffic and curbs for the yards.",
		"$%s more every 12 days to keep up" % CitySim.money_text(street.upkeep)]
	return {"title": "Turn a busy alley into a street",
		"why": "Drivers are using this alley as a street at rush hour. Alleys are built for garbage trucks and garages, not through traffic.",
		"change": "Alley to street", "options": [street]}


## The biggest neighborhood with only one road in (a road whose removal
## cuts it off) and more than ENGINEER_ONE_WAY_HOMES homes, with a new
## street to give it a second way in; {} when there's none or no room.
func _one_way(sim) -> Dictionary:
	var net = sim.network
	var homes_at := {}  # node -> homes on the streets that start there
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue
		var seg := int(sim.lots[key].seg)
		if net.segments.has(seg):
			var a := int(net.segments[seg].a)
			homes_at[a] = int(homes_at.get(a, 0)) + BuildingTypes.load_of(b)
	# Homes on the far side of each road whose removal splits the network,
	# summed up the depth-first walk's tree.
	var g := _bridges(net)
	var index: Dictionary = g.index
	var disc: PackedInt32Array = g.disc
	var size: PackedInt32Array = g.size
	var comp: PackedInt32Array = g.comp
	var comp_n: Dictionary = g.comp_n
	var up: PackedInt32Array = g.up
	var sub := PackedInt32Array()
	sub.resize(disc.size())
	for node in homes_at:
		if index.has(node):
			sub[index[node]] += int(homes_at[node])
	for k in g.order:
		if up[k] >= 0:
			sub[up[k]] += sub[k]
	var found: Array = g.found
	var ids: Array = g.ids
	# The biggest cut-off side not already brought up.
	var best := []
	var best_h := Balance.ENGINEER_ONE_WAY_HOMES
	for f in found:
		var seg := int(f[0])
		if str(net.segments[seg].get("built_by", "")) != "":
			continue
		if asked.has(seg) and int(sim.tick_count) - int(asked[seg]) < Balance.ENGINEER_REASK_YEARS * 12 * 1440:
			continue
		var v: int = index[int(f[1])]
		var inside := size[v] * 2 <= int(comp_n[comp[v]])
		var h := sub[v] if inside else sub[comp[v]] - sub[v]
		if h > best_h:
			best_h = h
			best = [seg, v, inside]
	if best.is_empty():
		return {}
	var seg := int(best[0])
	var v := int(best[1])
	var lo := disc[v]
	var hi := lo + size[v]
	var pocket_of := func(node: int) -> bool:
		var k: int = index.get(node, -1)
		return k >= 0 and comp[k] == comp[v] and ((disc[k] >= lo and disc[k] < hi) == bool(best[2]))
	var s0: Dictionary = net.segments[seg]
	var door: Vector3 = net.nodes[int(s0.b) if pocket_of.call(int(s0.a)) else int(s0.a)]
	var gate: Vector3 = net.nodes[int(s0.a) if pocket_of.call(int(s0.a)) else int(s0.b)]
	# The shortest clear street from the pocket to a public road outside it,
	# well apart from the road in.
	var cell := Balance.ENGINEER_LINK_MAX
	var outside := {}
	var inside_ids := []
	for n in ids:
		if comp[index[n]] != comp[v]:
			continue
		if pocket_of.call(n):
			inside_ids.append(n)
			continue
		var np: Vector3 = net.nodes[n]
		var k := Vector2i(floori(np.x / cell), floori(np.z / cell))
		if not outside.has(k):
			outside[k] = []
		outside[k].append(n)
	var pairs := []
	for p in inside_ids:
		var pp: Vector3 = net.nodes[p]
		var near := []
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				near.append_array(outside.get(Vector2i(floori(pp.x / cell) + dx, floori(pp.z / cell) + dz), []))
		for q in near:
			var qp: Vector3 = net.nodes[q]
			var d := pp.distance_to(qp)
			if d < Balance.ENGINEER_LINK_MIN or d > Balance.ENGINEER_LINK_MAX or qp.distance_to(door) < Balance.ENGINEER_LINK_APART \
					or pp.distance_to(gate) < Balance.ENGINEER_LINK_APART * 0.5:
				continue
			var public := false
			for o in net.segments_at(q):
				if str(net.segments[o].get("built_by", "")) == "" and int(net.segments[o].type) != RoadStyle.Type.ALLEY:
					public = true
			if public:
				pairs.append([d, p, q])
	pairs.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and (x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]))))
	var tries := 0
	for pr in pairs:
		tries += 1
		if tries > Balance.ENGINEER_LINK_TRIES:
			break
		var a: Vector3 = net.nodes[int(pr[1])]
		var b: Vector3 = net.nodes[int(pr[2])]
		if not sim.subdivisions._line_clear(sim, a, b):
			continue
		asked[seg] = int(sim.tick_count)
		var c := [a, (a + b) * 0.5, b]
		var cost := Economy.road_cost(c, RoadStyle.Type.STREET)
		var o := {"letter": "A", "name": "Build a second way in", "fix": "link", "to": -1, "segs": [],
			"link": [[snappedf(a.x, 0.01), snappedf(a.y, 0.01), snappedf(a.z, 0.01)], [snappedf(b.x, 0.01), snappedf(b.y, 0.01), snappedf(b.z, 0.01)]],
			"streets": [[[snappedf(a.x, 0.01), snappedf(a.z, 0.01)], [snappedf(b.x, 0.01), snappedf(b.z, 0.01)]]], "ghost": [],
			"cost": cost, "upkeep": roundi(Economy.road_upkeep(c, RoadStyle.Type.STREET) * 12.0), "lines": []}
		var box := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(20.0)
		o.outline = []
		for q in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
			o.outline.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
		o.lines = ["$%s more every 12 days to keep up" % CitySim.money_text(o.upkeep)]
		var name: String = sim.streets.name_of(seg)
		return {"title": "A second way into %s" % ("the neighborhood off " + name if name != "" else "a neighborhood"),
			"why": "%d homes have only one road in. If it's blocked, fire trucks and ambulances can't get through." % best_h,
			"change": "Second way in", "options": [o]}
	asked[seg] = int(sim.tick_count)  # no room for one: don't look again for a while
	return {}


## The roads whose removal splits the network (bridges, by Tarjan's
## depth-first walk), worked out again only when the roads change:
## {disc, size, comp, comp_n, up, order (children before parents), found:
## [[seg, the node on its far side]], ids}.
func _bridges(net) -> Dictionary:
	if int(net.revision) == _rev and not _graph.is_empty():
		return _graph
	# Junctions numbered 0..n-1, each with its roads as [road, other end].
	var ids: Array = net.nodes.keys()
	ids.sort()
	var count := ids.size()
	var index := {}
	for k in count:
		index[ids[k]] = k
	var adj := []
	adj.resize(count)
	for k in count:
		adj[k] = PackedInt32Array()
	var seg_ids: Array = net.segments.keys()
	seg_ids.sort()
	for seg in seg_ids:
		var sg: Dictionary = net.segments[seg]
		var a: int = index.get(sg.a, -1)
		var b: int = index.get(sg.b, -1)
		if a < 0 or b < 0 or a == b:
			continue
		adj[a].append_array([seg, b])
		adj[b].append_array([seg, a])
	var disc := PackedInt32Array()
	disc.resize(count)
	disc.fill(-1)
	var low := PackedInt32Array()
	low.resize(count)
	var size := PackedInt32Array()
	size.resize(count)
	var comp := PackedInt32Array()
	comp.resize(count)
	var up := PackedInt32Array()
	up.resize(count)
	up.fill(-1)
	var via := PackedInt32Array()
	via.resize(count)
	var at := PackedInt32Array()
	at.resize(count)
	var comp_n := {}
	var order := PackedInt32Array()
	var found := []
	var t := 0
	var stack := PackedInt32Array()
	for root in count:
		if disc[root] >= 0:
			continue
		disc[root] = t
		low[root] = t
		t += 1
		var start := t - 1
		via[root] = -1
		stack.append(root)
		while not stack.is_empty():
			var n: int = stack[stack.size() - 1]
			var edges: PackedInt32Array = adj[n]
			if at[n] < edges.size():
				var seg: int = edges[at[n]]
				var m: int = edges[at[n] + 1]
				at[n] += 2
				if seg == via[n]:
					continue
				if disc[m] >= 0:
					low[n] = mini(low[n], disc[m])
				else:
					disc[m] = t
					low[m] = t
					t += 1
					via[m] = seg
					up[m] = n
					stack.append(m)
				continue
			stack.resize(stack.size() - 1)
			size[n] += 1
			comp[n] = root
			order.append(n)
			var p: int = up[n]
			if p >= 0:
				low[p] = mini(low[p], low[n])
				size[p] += size[n]
				if low[n] > disc[p]:
					found.append([via[n], ids[n]])
		comp_n[root] = t - start
	_rev = int(net.revision)
	_graph = {"index": index, "ids": ids, "disc": disc, "size": size, "comp": comp, "comp_n": comp_n, "up": up,
		"order": order, "found": found}
	return _graph


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
	var a := {}
	for seg in asked:
		a[str(seg)] = asked[seg]
	return {"counts": c, "samples": samples, "pending": pending.keys(), "asked": a}


func from_dict(d: Dictionary) -> void:
	counts.clear()
	pending.clear()
	asked.clear()
	var a: Dictionary = d.get("asked", {})
	for k in a:
		asked[int(k)] = int(a[k])
	var c: Dictionary = d.get("counts", {})
	for k in c:
		counts[int(k)] = Array(c[k]).map(func(x): return int(x))
	samples = int(d.get("samples", 0))
	for id in d.get("pending", []):
		pending[int(id)] = true
	changed.emit()
