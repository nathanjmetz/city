class_name SmartZoning
extends RefCounted
## Smart paint's planner: which street sides around a spot to zone, and how,
## the way a town planner lays out a neighborhood (never over zoning that's
## already there):
## - The area: one street (followed straight through its crossings), or a
##   neighborhood of streets reached within a walk of the spot, bounded by
##   the busy roads around it (Clarence Perry's neighborhood unit, 1929: about
##   a quarter mile across, arterials on the edges, not through it).
## - Shops front the busy roads (corridor commercial on avenues and county
##   highways) and cluster on the corners of the neighborhood's main crossing
##   (the corner store and the neighborhood center).
## - Industry goes beside industry that's already zoned, or by the highway
##   ramps, never in among the homes.
## - Homes take the quiet local streets.
## Only the zones the player ticked are used.

enum Scope { STREET, SMALL, EXTENDED }
const SCOPE_NAMES := ["Street", "Neighborhood", "Extended"]
## How far along the streets a neighborhood reaches from the spot (path
## length): about two blocks, and Perry's quarter mile.
const REACH := [0.0, 220.0, 420.0]
## Shops at the main crossing: about two shop lots from each corner.
const CORNER_SHOPS := 45.0
## Industry joins industry already zoned within this distance.
const NEAR_INDUSTRY := 150.0
## A street carries on through a crossing within this turn.
const STRAIGHT := deg_to_rad(30.0)


## The plan: [{seg, side, zone, span: [from, to] or []}], each street side
## once (corner shop spans plus the rest as homes), and a few words on why.
static func plan(sim: CitySim, seg: int, scope: int, kinds: Dictionary) -> Dictionary:
	var out := {"parts": [], "why": []}
	if not sim.network.segments.has(seg) or kinds.is_empty():
		return out
	var segs := _street(sim, seg) if scope == Scope.STREET else _neighborhood(sim, seg, REACH[scope])
	var center := _main_crossing(sim, segs) if scope != Scope.STREET else -1
	var why := {}
	segs.sort()
	for id in segs:
		var t: int = sim.network.segments[id].type
		if not _zonable(t):
			continue
		for side in [-1, 1]:
			var s := sim.planner.side_survey(sim.network, id, side)
			if s.is_empty() or LotPlanner._zoned(s, sim.zones):
				continue
			var z := _pick(kinds, _want(sim, id, s))
			if z == ZoneMap.Zone.NONE:
				continue
			# The main crossing's corners get a couple of shops each.
			var near_a: bool = center >= 0 and sim.network.segments[id].a == center
			var near_b: bool = center >= 0 and sim.network.segments[id].b == center
			var corner: bool = z != ZoneMap.Zone.COMMERCIAL and kinds.get(ZoneMap.Zone.COMMERCIAL, false) and (near_a or near_b)
			if corner and s.len <= CORNER_SHOPS * 1.5:
				# A short block by the crossing: shops all along it.
				out.parts.append({"seg": id, "side": side, "zone": ZoneMap.Zone.COMMERCIAL, "span": []})
				why["corner"] = true
				why[ZoneMap.Zone.COMMERCIAL] = true
				continue
			if corner:
				var a0: float = 0.0 if near_a else s.len - CORNER_SHOPS
				var a1: float = CORNER_SHOPS if near_a else s.len
				out.parts.append({"seg": id, "side": side, "zone": ZoneMap.Zone.COMMERCIAL, "span": [a0, a1]})
				out.parts.append({"seg": id, "side": side, "zone": z,
					"span": [a1, s.len] if near_a else [0.0, a0]})
				why["corner"] = true
				why[ZoneMap.Zone.COMMERCIAL] = true
			else:
				out.parts.append({"seg": id, "side": side, "zone": z, "span": []})
				if z == ZoneMap.Zone.COMMERCIAL:
					why["busy"] = true
			why[z] = true
	if why.has("busy"):
		out.why.append("shops on the busy roads")
	if why.has("corner"):
		out.why.append("corner shops at the main crossing")
	if why.has(ZoneMap.Zone.INDUSTRIAL):
		out.why.append("industry beside industry or the highway")
	if why.has(ZoneMap.Zone.RESIDENTIAL):
		out.why.append("homes on the quiet streets")
	return out


## What planning practice wants on a street side, before the ticked zones.
static func _want(sim: CitySim, id: int, s: Dictionary) -> int:
	var t: int = sim.network.segments[id].type
	var mid: Vector2 = s.fronts[s.fronts.size() / 2][1]
	if _near_industry(sim, mid) or _by_highway(sim, id):
		return ZoneMap.Zone.INDUSTRIAL
	if busy(t):
		return ZoneMap.Zone.COMMERCIAL
	return ZoneMap.Zone.RESIDENTIAL


## The ticked zone nearest what's wanted: homes and shops stand in for each
## other; industry only goes where it's wanted or where nothing else is ticked.
static func _pick(kinds: Dictionary, want: int) -> int:
	if kinds.get(want, false):
		return want
	var order := {
		ZoneMap.Zone.RESIDENTIAL: [ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL],
		ZoneMap.Zone.COMMERCIAL: [ZoneMap.Zone.RESIDENTIAL, ZoneMap.Zone.INDUSTRIAL],
		ZoneMap.Zone.INDUSTRIAL: [ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.RESIDENTIAL],
	}
	for z in order[want]:
		if kinds.get(z, false):
			return z
	return ZoneMap.Zone.NONE


## A road busy enough for shops and to bound a neighborhood: four lanes or
## more, or a county highway at 45 mph or faster.
static func busy(type: int) -> bool:
	var spec: Dictionary = RoadStyle.TYPES[type]
	return spec.get("lanes", 2) >= 4 or spec.get("mph", 25) >= 45


static func _zonable(type: int) -> bool:
	var spec: Dictionary = RoadStyle.TYPES[type]
	return spec.lots and spec.get("surface", "asphalt") != "gravel"


static func _near_industry(sim: CitySim, p: Vector2) -> bool:
	var step := 30.0
	var n := int(NEAR_INDUSTRY / step)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var off := Vector2(i, j) * step
			if off.length() <= NEAR_INDUSTRY and sim.zones.zone_at(Vector3(p.x + off.x, 0.0, p.y + off.y)) == ZoneMap.Zone.INDUSTRIAL:
				return true
	return false


## Whether the street meets a highway ramp or highway at either end.
static func _by_highway(sim: CitySim, id: int) -> bool:
	var sg: Dictionary = sim.network.segments[id]
	for node in [sg.a, sg.b]:
		for o in sim.network.segments_at(node):
			var spec: Dictionary = RoadStyle.TYPES[sim.network.segments[o].type]
			if not spec.lots and spec.get("mph", 25) >= 35:
				return true
	return false


## The street through seg: on through each crossing to the road that carries
## straight on (within 30°), both ways.
static func _street(sim: CitySim, seg: int) -> Array:
	var out := [seg]
	var seen := {seg: true}
	for from_b in [true, false]:
		var cur := seg
		var at_b: bool = from_b
		for guard in 200:
			var sg: Dictionary = sim.network.segments[cur]
			var node: int = sg.b if at_b else sg.a
			var dir := _dir_out(sim, cur, not at_b)  # heading into the node
			var best := -1
			var best_turn := STRAIGHT
			for o in sim.network.segments_at(node):
				if seen.has(o) or not _zonable(sim.network.segments[o].type):
					continue
				var od := _dir_out(sim, o, sim.network.segments[o].a == node)
				var turn := absf(dir.angle_to(od))
				if turn < best_turn:
					best_turn = turn
					best = o
			if best < 0:
				break
			seen[best] = true
			out.append(best)
			at_b = sim.network.segments[best].a == node
			cur = best
	return out


## The road's heading leaving its a end (from_a) or its b end, flat.
static func _dir_out(sim: CitySim, id: int, from_a: bool) -> Vector2:
	var c := sim.network.curve_of(id)
	var p: Vector3 = c[0] if from_a else c[2]
	var q: Vector3 = c[1]
	if q.distance_to(p) < 0.5:
		q = c[2] if from_a else c[0]
	var d := Vector2(q.x - p.x, q.z - p.z).normalized()
	return d if from_a else -d


## Streets reached from seg within reach along the network, not through busy
## roads (they bound the neighborhood; their near frontage joins it).
static func _neighborhood(sim: CitySim, seg: int, reach: float) -> Array:
	var net := sim.network
	var dist := {}
	var open := []  # [distance, node]
	var sg: Dictionary = net.segments[seg]
	var half := _length(sim, seg) * 0.5
	for node in [sg.a, sg.b]:
		dist[node] = half
		open.append([half, node])
	var segs := {seg: true}
	while not open.is_empty():
		open.sort_custom(func(x, y): return x[0] < y[0])
		var cur: Array = open.pop_front()
		if cur[0] > dist.get(cur[1], INF):
			continue
		for o in net.segments_at(cur[1]):
			var t: int = net.segments[o].type
			if not _zonable(t):
				continue
			segs[o] = true
			if busy(t) and not busy(sg.type):
				continue
			var other: int = net.segments[o].b if net.segments[o].a == cur[1] else net.segments[o].a
			var d: float = cur[0] + _length(sim, o)
			if d <= reach and d < dist.get(other, INF):
				dist[other] = d
				open.append([d, other])
	return segs.keys()


static func _length(sim: CitySim, id: int) -> float:
	var sg: Dictionary = sim.network.segments[id]
	return (sim.network.nodes[sg.a] as Vector3).distance_to(sim.network.nodes[sg.b])


## The neighborhood's main crossing: the busiest four-way (or three-way)
## junction nearest its middle, inside it.
static func _main_crossing(sim: CitySim, segs: Array) -> int:
	var count := {}
	var mid := Vector3.ZERO
	for id in segs:
		var sg: Dictionary = sim.network.segments[id]
		for node in [sg.a, sg.b]:
			count[node] = count.get(node, 0) + 1
			mid += sim.network.nodes[node]
	if count.is_empty():
		return -1
	mid /= float(segs.size() * 2)
	var best := -1
	var best_score := -INF
	var nodes := count.keys()
	nodes.sort()
	for node in nodes:
		var here: Array = sim.network.segments_at(node)
		if here.size() < 3:
			continue
		var rank := 0
		for o in here:
			rank += 2 if busy(sim.network.segments[o].type) else 0
		var score: float = here.size() * 10.0 + rank * 10.0 - (sim.network.nodes[node] as Vector3).distance_to(mid) * 0.1
		if score > best_score:
			best_score = score
			best = node
	return best
