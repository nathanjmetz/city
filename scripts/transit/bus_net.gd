class_name BusNet
extends RefCounted
## Buses, run by the depots themselves (Brawn's rule, 2026-10-22). The player
## places a bus depot and decides only two things: how much land it has and
## how much the city pays it each month. The depot does the rest, the way a
## real small-town transit agency does:
##   - it puts stops where enough people live or work within a quarter-mile
##     walk, at least 300 m apart (2 to 3 blocks),
##   - it runs "pulse" routes, the usual US small-town layout: loops out from
##     a downtown transfer stop and back, re-planned as the town grows,
##   - it buys buses up to what its yard holds and its money pays for, aiming
##     for a bus every 30 minutes,
##   - it sets its own fare from its costs and what its riders earn, and
##   - when its yard is full and it can afford more, it buys the land next
##     door (only next door: a hub never opens a second site).
## Its director (an Agency leader) is more or less educated depending on how
## much the town has put into schools, and that changes how it decides (see
## `_set_fare`). The director also works through the depot's development
## tree (TREE, below) with the depot's own money: shelters, a transfer
## center, cleaner buses, park-and-ride, dial-a-ride, a school bus contract
## and coaches to the neighboring towns, each opening up only when the town
## and region around it call for it.
##
## Buses are real vehicles on Traffic's trips: they drive stop to stop, wait at
## the curb while people get on and off, and park in their bay at the depot.
## Schools run their own yellow buses at bell times, parked at the school.
##
## Ridership and money are worked out at real-world rates (people a day,
## dollars a month); the buses on screen carry each trip's share of that.
## Benchmark: Cities: Skylines 2 buses, with line drawing replaced by the
## depot's own planning.

## Ticks between re-plans of stops and routes (half a game day).
const PLAN_EVERY := 720
## Ticks between the director's decisions; money settles then too. A game
## day is a month of budget, as everywhere in the game.
const DECIDE_EVERY := 24 * CitySim.TICKS_PER_HOUR
## The director revisits the fare once a quarter.
const FARE_EVERY_DAYS := 3
## Ticks a bus waits at a stop: 15 s, plus 2 s a boarding (Traffic's clock
## runs a tenth of a second a tick).
const DWELL_TICKS := 150
const DWELL_PER_RIDER := 20
## Ticks between buses leaving the depot, so they spread along the route.
const LAUNCH_GAP := 250
## How long a bus waits before trying again when no road leads on.
const BUS_COACH_AWAY_TICKS := Balance.BUS_COACH_AWAY
const RETRY_TICKS := 300
## Hard cap on stops in town (keeps planning fast on the web).
const MAX_STOPS := 160
## Demand is pooled in squares this size, metres, before stops are scored.
const CELL := 50.0
const SAMPLE_STEP := 40.0
## Where the curb is, from a stop's point on the road's centre line.
const CURB_EXTRA := 0.6
## Yard layout: 40 ft buses in 4.5 m stalls, 14 m deep, off a 7 m aisle.
const STALL_W := 4.5
const STALL_D := 14.0
const AISLE := 7.0
## The garage and office across the front of the depot site, metres deep.
const GARAGE_D := 16.0
## A depot buys land in strips this wide.
const GROW_STEP := AISLE + STALL_D

## The depot's development tree, in Agency's format. Besides Agency's
## conditions, a node can need "neighbors" (neighboring towns that trade
## with this one) or "school" (elementary schools in town); BusNet checks
## those itself. Costs come from the depot's own cash. Effects:
##   riders*  more people ride; cost*  cheaper to run (negative);
##   riders+  riders a day outside the buses (dial-a-ride vans);
##   income+  dollars a month from a contract; coach* more coach riders.
const TREE := [
	{"id": "shelters", "name": "Shelters and benches", "cost": 60_000, "needs": {},
		"effects": {"riders*": 0.04}, "note": "people wait out of the weather at the busy stops"},
	{"id": "transfer_center", "name": "Downtown transfer center", "cost": 900_000, "requires": ["shelters"],
		"needs": {"population": 2500}, "effects": {"riders*": 0.08},
		"note": "every route meets downtown under one roof"},
	{"id": "cng", "name": "Natural gas buses", "cost": 400_000, "requires": ["shelters"],
		"needs": {"leader_edu": 0.55, "education": 0.4}, "effects": {"cost*": -0.12},
		"note": "cheaper fuel and cleaner air"},
	{"id": "electric", "name": "Electric buses and chargers", "cost": 1_500_000, "requires": ["cng"],
		"needs": {"leader_edu": 0.75, "profit": 200_000}, "effects": {"cost*": -0.12},
		"note": "quiet, and cheaper to run per mile"},
	{"id": "park_ride", "name": "Park-and-ride lot", "cost": 700_000, "requires": ["transfer_center"],
		"needs": {"population": 5000, "link": 1}, "effects": {"riders*": 0.08},
		"note": "commuters leave their cars at the edge of town"},
	{"id": "dial_a_ride", "name": "Dial-a-ride vans", "cost": 250_000, "needs": {"population": 1500},
		"effects": {"riders+": 30.0}, "note": "door-to-door rides for seniors and riders with disabilities (ADA paratransit)"},
	{"id": "school_contract", "name": "School bus contract", "cost": 150_000,
		"needs": {"education": 0.3, "school": 1}, "effects": {"income+": 12_000.0},
		"note": "the school district pays the depot to keep its buses"},
	{"id": "intercity", "name": "Intercity coach", "cost": 600_000,
		"needs": {"link": 1, "neighbors": 1, "population": 1500}, "effects": {"coach*": 0.0},
		"note": "a coach runs to the neighboring towns along the county highway"},
	{"id": "regional", "name": "Shared regional routes", "cost": 1_200_000, "requires": ["intercity"],
		"needs": {"neighbors": 2, "leader_edu": 0.5}, "effects": {"coach*": 0.5, "riders*": 0.03},
		"note": "timed transfers with the neighbors' buses"},
]

var depots := {}  # service id -> depot state (see _new_depot)
var stops := {}   # stop id -> {pt, dir, side, pos, name, people, res, jobs, depot, riders}
var routes := {}  # depot id -> [{stops: [ids], len, cycle_min, buses, headway_min, riders, pts}]
var buses := {}   # bus id -> {depot, kind, state, route, stop, at, dir, load, until, bay}
var schools := {} # school service id -> {riders, pickups: [Vector3], runs: [[Vector3]]}
var trips := {}   # traffic trip id -> bus id
## Bumped whenever stops or routes change, so views know to redraw.
var version := 0
var _next_stop := 1
var _next_bus := 1
var _next_launch := {}  # depot id -> tick


# --- The city's side ----------------------------------------------------------

## A depot was just built: it gets its starting subsidy and two buses.
func on_placed(sim: CitySim, id: int) -> void:
	var b: Dictionary = sim.services.buildings[id]
	b.size = Services.KINDS[b.kind].size
	b.subsidy = Balance.BUS_START_SUBSIDY
	depots[id] = _new_depot()
	depots[id].leader = Agency.leader(sim, hash([id, "bus_depot"]))
	for i in 2:
		_add_bus(sim, id, "city_bus")
	_plan(sim)
	_decide(sim, id, false)


## Player commands that belong to the buses. Returns true if anything changed.
func apply(sim: CitySim, cmd: Dictionary) -> bool:
	match cmd.get("type", ""):
		"set_bus_subsidy":
			var id := int(cmd.get("id", -1))
			if not depots.has(id) or not sim.services.buildings.has(id):
				return false
			var amount := clampi(int(cmd.get("amount", 0)), 0, Balance.BUS_SUBSIDY_MAX)
			sim.services.buildings[id].subsidy = amount
			_note(id, "The city now pays $%s a month." % CitySim.money_text(amount))
			return true
	return false


## Steps every bus. Returns the ids of depots that bought land this tick, so
## the city can clear lots and zoning under them.
func tick(sim: CitySim) -> Array:
	if not sim.permits.locators.has("bus_depot"):
		# Lets the player guide the depot's director from its panel.
		sim.permits.locators["bus_depot"] = func(s: CitySim, id: int) -> Vector2:
			var b: Dictionary = s.services.buildings.get(id, {})
			return Vector2(b.pos.x, b.pos.z) if not b.is_empty() else Vector2.ZERO
	_sync(sim)
	_arrivals(sim)
	var grown := []
	if depots.is_empty() and schools.is_empty() and buses.is_empty():
		return grown
	if sim.tick_count % PLAN_EVERY == 0:
		_plan(sim)
	if sim.tick_count % DECIDE_EVERY == 0:
		var ids := depots.keys()
		ids.sort()
		for id in ids:
			if _decide(sim, id, true):
				grown.append(id)
	_school_bells(sim)
	_drive(sim)
	return grown


## Depots and schools come and go with their buildings.
func _sync(sim: CitySim) -> void:
	var changed := false
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if b.kind == Services.Kind.BUS_DEPOT and not depots.has(id):
			# Built before the depot ran itself (or on another copy): set it up.
			if not b.has("subsidy"):
				b.size = Services.KINDS[b.kind].size
				b.subsidy = Balance.BUS_START_SUBSIDY
			depots[id] = _new_depot()
			depots[id].leader = Agency.leader(sim, hash([id, "bus_depot"]))
			changed = true
		elif b.kind == Services.Kind.SCHOOL and not schools.has(id):
			schools[id] = {"riders": 0, "pickups": [], "runs": []}
			changed = true
	for id in depots.keys():
		if not sim.services.buildings.has(id):
			depots.erase(id)
			routes.erase(id)
			changed = true
	for id in schools.keys():
		if not sim.services.buildings.has(id):
			schools.erase(id)
			changed = true
	# A bulldozed depot or school sells its buses: parked ones go at once,
	# those on the road finish their trip first.
	for bid in buses.keys():
		var bus: Dictionary = buses[bid]
		if not sim.services.buildings.has(bus.depot) and bus.state != "driving":
			_drop(sim, bid)
			changed = true
	if changed:
		_plan(sim)


func _new_depot() -> Dictionary:
	return {"cash": 0, "fare": Balance.BUS_START_FARE, "fare_day": -99, "wanted": 2, "target": 2,
		"riders": 0, "month": {}, "log": [], "wealth": 0.5, "education": 0.5,
		"leader": {"edu": 0.5, "caution": 0.5, "ambition": 0.5}, "built": [], "why": "", "strip": []}


# --- Stops and routes ---------------------------------------------------------

## Re-plans stops for the whole town and routes for each depot.
func _plan(sim: CitySim) -> void:
	version += 1
	var cells := _demand_cells(sim)
	_plan_stops(sim, cells)
	var g := _graph(sim.network)
	var ids := depots.keys()
	ids.sort()
	for id in ids:
		_plan_routes(sim, id, g)
	_plan_schools(sim)


## People within a walk of each 50 m square: residents, and the workers who
## come in to jobs there (0.8 a job: not every job is filled every day).
func _demand_cells(sim: CitySim) -> Dictionary:
	var cells := {}
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var b: Dictionary = sim.buildings[key]
		var p: Vector3 = sim.lots[key].pos
		var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not cells.has(c):
			cells[c] = Vector2.ZERO
		if b.zone == ZoneMap.Zone.RESIDENTIAL:
			cells[c].x += b.occ
		else:
			cells[c].y += b.cap * 0.8
	return cells


## {res, jobs} within a quarter-mile walk of a point.
static func _near(cells: Dictionary, p: Vector3) -> Vector2:
	var r := ceili(Balance.BUS_WALK / CELL)
	var c0 := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var out := Vector2.ZERO
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var c := c0 + Vector2i(dx, dz)
			if not cells.has(c):
				continue
			var mid := Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)
			if mid.distance_to(Vector2(p.x, p.z)) <= Balance.BUS_WALK:
				out += cells[c]
	return out


func _plan_stops(sim: CitySim, cells: Dictionary) -> void:
	var net := sim.network
	var kept := []
	var ids := stops.keys()
	ids.sort()
	# Stops stay put while enough people still use them (so routes don't
	# jump around), and follow the road if it's rebuilt under them.
	for id in ids:
		var s: Dictionary = stops[id]
		var near := net.find_segment_near(s.pt, 15.0)
		if near.is_empty() or not _bus_road(sim, near.seg) or depots.is_empty():
			stops.erase(id)
			continue
		_place_stop(sim, s, near)
		var n := _near(cells, s.pt)
		if n.x + n.y < Balance.BUS_STOP_MIN_PEOPLE * 0.6:
			stops.erase(id)
			continue
		s.res = n.x
		s.jobs = n.y
		kept.append(s.pt)
	if depots.is_empty():
		return
	# New stops: the busiest points on the bus roads, 2 to 3 blocks apart.
	var cands := []
	var segs := net.segments.keys()
	segs.sort()
	for seg in segs:
		if not _bus_road(sim, seg):
			continue
		var pts := net.sample_segment(seg, 16)
		var length := RoadNetwork.polyline_length(pts)
		var n := maxi(1, int(length / SAMPLE_STEP))
		var c := net.curve_of(seg)
		for i in n:
			var t := (i + 0.5) / n
			var p := RoadNetwork.bezier(c[0], c[1], c[2], t)
			var d := _near(cells, p)
			if d.x + d.y >= Balance.BUS_STOP_MIN_PEOPLE:
				cands.append([d.x + d.y, seg, t, p])
	cands.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and (a[1] < b[1] or a[1] == b[1] and a[2] < b[2])))
	for cand in cands:
		if stops.size() >= MAX_STOPS:
			break
		var p: Vector3 = cand[3]
		var clear := true
		for q in kept:
			if Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) < Balance.BUS_STOP_SPACING:
				clear = false
				break
		if not clear:
			continue
		var s := {"id": _next_stop, "pt": p, "name": "Stop %d" % _next_stop, "riders": 0.0, "depot": -1}
		_next_stop += 1
		_place_stop(sim, s, {"seg": cand[1], "t": cand[2]})
		var d := _near(cells, p)
		s.res = d.x
		s.jobs = d.y
		stops[s.id] = s
		kept.append(p)


## Buses run on streets, avenues and boulevards (never highways or ramps),
## and not out along the county highway to the region.
func _bus_road(sim: CitySim, seg: int) -> bool:
	var s: Dictionary = sim.network.segments[seg]
	return RoadStyle.TYPES[s.type].lots and not RoadStyle.is_ring(s.type) and not sim.is_link_segment(seg)


## Fixes a stop to its road: the point on the centre line, the road's
## direction there, and the curb on the side with more people.
func _place_stop(sim: CitySim, s: Dictionary, near: Dictionary) -> void:
	var c := sim.network.curve_of(near.seg)
	var t: float = near.t
	var p := RoadNetwork.bezier(c[0], c[1], c[2], t)
	var dir := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var normal := Vector3(-dir.z, 0.0, dir.x)
	if not s.has("side"):
		s.side = 1.0
		var best := -1.0
		for side in [1.0, -1.0]:
			var count := 0
			for key in sim.buildings:
				if sim.lots.has(key):
					var q: Vector3 = sim.lots[key].pos
					if q.distance_to(p) < 120.0 and (q - p).dot(normal) * side > 0.0:
						count += 1
			if count > best:
				best = count
				s.side = side
	s.seg = near.seg
	s.t = t
	s.pt = p
	s.dir = dir
	var hw := RoadStyle.half_width(sim.network.segments[near.seg].type)
	s.pos = p + normal * s.side * (hw + CURB_EXTRA)


## Pulse routes for one depot: from the busiest downtown stop (the transfer
## point) out through one slice of town and back.
func _plan_routes(sim: CitySim, id: int, g: Dictionary) -> void:
	var b: Dictionary = sim.services.buildings[id]
	var gate := _gate(b)
	var mine := []
	var sids := stops.keys()
	sids.sort()
	for sid in sids:
		var s: Dictionary = stops[sid]
		# Each stop belongs to the nearest depot.
		var best := -1
		var best_d := INF
		var dids := depots.keys()
		dids.sort()
		for did in dids:
			var d := _gate(sim.services.buildings[did]).distance_to(s.pt)
			if d < best_d:
				best_d = d
				best = did
		if best == id and not _path(sim.network, g, _spot(sim.network, gate), s).is_empty():
			s.depot = id
			mine.append(s)
	var out := []
	var old: Array = routes.get(id, [])
	if mine.is_empty():
		routes[id] = out
		return
	var hub: Dictionary = mine[0]
	for s in mine:
		if s.jobs > hub.jobs or s.jobs == hub.jobs and s.res > hub.res:
			hub = s
	var others := mine.filter(func(s): return s != hub)
	var dep: Dictionary = depots[id]
	var n := clampi(ceili(others.size() / float(Balance.BUS_STOPS_PER_ROUTE)), 1, Balance.BUS_MAX_ROUTES)
	# Never more routes than buses the director means to run.
	n = mini(n, maxi(1, int(dep.target)))
	# Slices of town by direction from the hub, each with about as many stops.
	var hp: Vector3 = hub.pt
	others.sort_custom(func(a, c):
		var aa := atan2(a.pt.z - hp.z, a.pt.x - hp.x)
		var ca := atan2(c.pt.z - hp.z, c.pt.x - hp.x)
		return aa < ca or aa == ca and a.id < c.id)
	# Start the slices at the widest gap between neighbouring stops, so no
	# route straddles the seam.
	if others.size() > 2:
		var gap := -1.0
		var at := 0
		for i in others.size():
			var a1 := atan2(others[i].pt.z - hp.z, others[i].pt.x - hp.x)
			var a0 := atan2(others[i - 1].pt.z - hp.z, others[i - 1].pt.x - hp.x)
			var d := fposmod(a1 - a0, TAU)
			if d > gap:
				gap = d
				at = i
		others = others.slice(at) + others.slice(0, at)
	for r in n:
		var part := others.slice(roundi(r * others.size() / float(n)), roundi((r + 1) * others.size() / float(n)))
		# Nearest stop next, out from the hub; the bus loops back to the hub.
		var order := [hub]
		var left := part.duplicate()
		while not left.is_empty():
			var last: Dictionary = order[-1]
			var k := 0
			for i in left.size():
				if left[i].pt.distance_to(last.pt) < left[k].pt.distance_to(last.pt):
					k = i
			order.append(left[k])
			left.remove_at(k)
		var route := {"stops": [], "len": 0.0, "pts": PackedVector3Array(), "buses": 0,
			"headway_min": INF, "riders": 0.0, "cycle_min": 0.0}
		for s in order:
			route.stops.append(s.id)
		_measure(sim.network, g, route)
		if route.stops.size() >= 2 or others.is_empty():
			out.append(route)
	# Keep the bus counts the routes had (the director re-shares them at the
	# month's end).
	for i in mini(out.size(), old.size()):
		out[i].buses = old[i].buses
	routes[id] = out
	_share_buses(id)


## Length, round-trip time and the line to draw for a route, along the roads
## the buses will really take. Stops no road reaches are left out.
func _measure(net: RoadNetwork, g: Dictionary, route: Dictionary) -> void:
	var ids: Array = route.stops
	var kept := [ids[0]]
	for i in range(1, ids.size()):
		if not _path(net, g, stops[kept[-1]], stops[ids[i]]).is_empty():
			kept.append(ids[i])
	route.stops = kept
	var pts := PackedVector3Array()
	var length := 0.0
	if kept.size() >= 2:
		for i in kept.size():
			var leg := _path(net, g, stops[kept[i]], stops[kept[(i + 1) % kept.size()]])
			if leg.is_empty():
				continue
			length += leg.len
			pts.append_array(leg.pts)
	route.len = length
	route.pts = pts
	route.cycle_min = length / (Balance.BUS_AVG_KMH * 1000.0 / 60.0)


## Spreads the depot's buses over its routes: the routes needing most
## buses for a half-hourly service get theirs first.
func _share_buses(id: int) -> void:
	var list: Array = routes.get(id, [])
	if list.is_empty():
		return
	var fleet := 0
	for bid in buses:
		if buses[bid].depot == id and buses[bid].kind == "city_bus" and not buses[bid].get("retire", false):
			fleet += 1
	var want := []
	for r in list:
		r.buses = 0
		want.append(maxi(1, ceili(r.cycle_min / Balance.BUS_TARGET_HEADWAY_MIN)))
	var left := fleet
	# One each first, busiest routes first, then the rest by need.
	var order := range(list.size())
	order.sort_custom(func(a, b): return _route_people(list[a]) > _route_people(list[b]))
	for i in order:
		if left > 0:
			list[i].buses = 1
			left -= 1
	while left > 0:
		var best := -1
		for i in order:
			if list[i].buses < want[i] * 2 and (best == -1 or float(list[i].buses) / want[i] < float(list[best].buses) / want[best]):
				best = i
		if best == -1:
			break
		list[best].buses += 1
		left -= 1
	for r in list:
		r.headway_min = r.cycle_min / r.buses if r.buses > 0 else INF
	# Each bus learns its route.
	var by_route := []
	for r in list.size():
		by_route.append(list[r].buses)
	var bids := buses.keys()
	bids.sort()
	for bid in bids:
		var bus: Dictionary = buses[bid]
		if bus.depot != id or bus.kind != "city_bus" or bus.get("retire", false):
			continue
		var r := 0
		while r < by_route.size() and by_route[r] <= 0:
			r += 1
		if r < by_route.size():
			by_route[r] -= 1
			bus.route = r
		else:
			bus.route = -1


func _route_people(r: Dictionary) -> float:
	var n := 0.0
	for sid in r.stops:
		if stops.has(sid):
			n += stops[sid].res + stops[sid].jobs
	return n


# --- Road graph -----------------------------------------------------------------

## node -> [[other node, seg, length, from a to b]] for the roads buses may
## drive (one-way roads only the right way).
func _graph(net: RoadNetwork) -> Dictionary:
	var adj := {}
	var lens := {}
	var segs := net.segments.keys()
	segs.sort()
	for seg in segs:
		var s: Dictionary = net.segments[seg]
		var length := RoadNetwork.polyline_length(net.sample_segment(seg, 16))
		lens[seg] = length
		# Routes lean onto avenues with bus lanes, where buses run faster.
		var cost := length * (Balance.BUS_LANE_ROUTE_COST if RoadStyle.bus_lane(int(s.type)) >= 0 else 1.0)
		if not adj.has(s.a):
			adj[s.a] = []
		if not adj.has(s.b):
			adj[s.b] = []
		adj[s.a].append([s.b, seg, cost, true])
		if not net.is_oneway(seg):
			adj[s.b].append([s.a, seg, cost, false])
	return {"adj": adj, "len": lens}


## A place on the road for routing: {seg, t}.
static func _spot(net: RoadNetwork, p: Vector3) -> Dictionary:
	var near := net.find_segment_near(p, 80.0)
	if near.is_empty():
		return {}
	return {"seg": near.seg, "t": near.t, "pt": near.point}


## The shortest drive from one road spot to another: {len, pts}, or {}.
func _path(net: RoadNetwork, g: Dictionary, from: Dictionary, to: Dictionary) -> Dictionary:
	if from.is_empty() or to.is_empty() or not net.segments.has(from.seg) or not net.segments.has(to.seg):
		return {}
	var lens: Dictionary = g.len
	var fs: Dictionary = net.segments[from.seg]
	var ts: Dictionary = net.segments[to.seg]
	var fl: float = lens[from.seg]
	var tl: float = lens[to.seg]
	# Straight along one road.
	if from.seg == to.seg and (to.t >= from.t or not net.is_oneway(from.seg)):
		return {"len": absf(to.t - from.t) * fl, "pts": _part(net, from.seg, from.t, to.t)}
	var dist := {}
	var prev := {}
	var heap := []
	# Out of the start road either way it may go.
	dist[fs.b] = (1.0 - from.t) * fl
	prev[fs.b] = [-1, from.seg, true]
	_push(heap, [dist[fs.b], fs.b])
	if not net.is_oneway(from.seg):
		dist[fs.a] = from.t * fl
		prev[fs.a] = [-1, from.seg, false]
		_push(heap, [dist[fs.a], fs.a])
	var best := INF
	var end := -1
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var d: float = top[0]
		var n: int = top[1]
		if d > dist.get(n, INF) or d >= best:
			continue
		# Into the goal road from this node.
		if n == ts.a and d + to.t * tl < best:
			best = d + to.t * tl
			end = n
		if n == ts.b and not net.is_oneway(to.seg) and d + (1.0 - to.t) * tl < best:
			best = d + (1.0 - to.t) * tl
			end = n
		for e in g.adj.get(n, []):
			var nd: float = d + e[2]
			if nd < dist.get(e[0], INF):
				dist[e[0]] = nd
				prev[e[0]] = [n, e[1], e[3]]
				_push(heap, [nd, e[0]])
	if end == -1:
		return {}
	# Back from the goal to the start.
	var legs := []
	var n := end
	while true:
		var p: Array = prev[n]
		legs.push_front(p)
		if p[0] == -1:
			break
		n = p[0]
	var pts := PackedVector3Array()
	var first: Array = legs[0]
	pts.append_array(_part(net, from.seg, from.t, 1.0 if first[2] else 0.0))
	# The real distance driven (the search weighs bus-lane roads lighter).
	var length: float = ((1.0 - from.t) if first[2] else from.t) * fl
	for i in range(1, legs.size()):
		var l: Array = legs[i]
		pts.append_array(_part(net, l[1], 0.0 if l[2] else 1.0, 1.0 if l[2] else 0.0))
		length += float(lens[l[1]])
	pts.append_array(_part(net, to.seg, 0.0 if end == ts.a else 1.0, to.t))
	length += (to.t if end == ts.a else 1.0 - to.t) * tl
	return {"len": length, "pts": pts}


## Points along a road from t0 to t1 (either way).
static func _part(net: RoadNetwork, seg: int, t0: float, t1: float) -> PackedVector3Array:
	var c := net.curve_of(seg)
	var n := maxi(2, ceili(absf(t1 - t0) * 12.0) + 1)
	var out := PackedVector3Array()
	for i in n:
		out.append(RoadNetwork.bezier(c[0], c[1], c[2], lerpf(t0, t1, i / float(n - 1))))
	return out


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p][0] <= item[0]:
			break
		heap[i] = heap[p]
		i = p
	heap[i] = item


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var c := i * 2 + 1
		if c >= n:
			break
		if c + 1 < n and heap[c + 1][0] < heap[c][0]:
			c += 1
		if heap[c][0] >= last[0]:
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top


# --- The director's month --------------------------------------------------------

## Settles the month's money and makes the depot's decisions. `settle` is
## false the day it opens. Returns true if it bought land.
func _decide(sim: CitySim, id: int, settle: bool) -> bool:
	var dep: Dictionary = depots[id]
	var b: Dictionary = sim.services.buildings[id]
	var list: Array = routes.get(id, [])
	dep.education = float(dep.leader.edu)
	dep.wealth = _wealth(sim, id)
	var stance: String = sim.permits.guidance("bus_depot", id).stance
	var fleet := _fleet(id)
	var riders := _ridership(id, dep.fare)
	dep.riders = roundi(riders)
	if settle:
		var in_service := 0
		for r in list:
			in_service += r.buses
		var cost := roundi(in_service * Balance.BUS_MONTHLY_COST * Agency.effect(dep, TREE, "cost*"))
		var fares := roundi(riders * 30.0 * dep.fare)
		# The coach to the neighbors pays its own way (or doesn't).
		var coach := coach_riders(sim, id) if _has_coach(id) else 0
		fares += roundi(coach * 30.0 * Balance.BUS_COACH_FARE)
		if _has_coach(id):
			cost += Balance.BUS_COACH_MONTHLY
		var grant := roundi(Balance.BUS_GRANT_SHARE * maxf(0.0, cost - fares))
		var subsidy := int(b.get("subsidy", 0))
		var contract := roundi(Agency.effect(dep, TREE, "income+"))
		dep.cash += fares + grant + subsidy + contract - cost
		dep.month = {"riders": dep.riders, "fares": fares, "grant": grant, "subsidy": subsidy, "cost": cost,
			"contract": contract, "coach": coach, "net": fares + grant + subsidy + contract - cost}
	# How many buses a bus every half hour on every route takes, plus one
	# where the busiest trip would be crowded.
	var wanted := 0
	for r in list:
		var w := maxi(1, ceili(r.cycle_min / Balance.BUS_TARGET_HEADWAY_MIN))
		var per_trip := _per_trip(r, dep.fare, Balance.BUS_TARGET_HEADWAY_MIN)
		if per_trip > 0.85 * Balance.BUS_CAPACITY:
			w += 1
		wanted += w
	# How many the money carries: the city's subsidy and the federal grant
	# against what each bus costs beyond the fares it brings in.
	var per_bus_fares: float = riders * 30.0 * dep.fare / maxf(fleet, 1.0)
	var net_cost: float = Balance.BUS_MONTHLY_COST * Agency.effect(dep, TREE, "cost*") - per_bus_fares
	var afford := 99 if net_cost <= 0.0 else floori(int(b.get("subsidy", 0)) / (1.0 - Balance.BUS_GRANT_SHARE) / net_cost)
	# A more educated director projects ahead and keeps less idle cash; a
	# less educated one waits until the money is in the bank.
	var reserve := roundi(Balance.BUS_MONTHLY_COST * (0.5 + float(dep.leader.caution) - 0.5 * dep.education))
	var bays := bays_for(Services.size_of(b))
	dep.wanted = wanted
	dep.target = mini(mini(wanted, afford), bays)
	var bought_land := false
	if fleet < dep.target and dep.cash >= Balance.BUS_PRICE_LOCAL + reserve:
		dep.cash -= Balance.BUS_PRICE_LOCAL
		_add_bus(sim, id, "city_bus")
		_note(id, "Bought a bus: %d on the road now." % (fleet + 1))
	elif fleet > dep.target and (fleet > afford and dep.cash < 0 or fleet > bays):
		if _retire_one(id):
			dep.cash += Balance.BUS_RESALE
			_note(id, "Retired a bus: the money no longer covers %d." % fleet)
	elif stance != "hold" and fleet >= bays - (1 if stance == "grow" else 0) \
			and (mini(wanted, afford) > bays or stance == "grow"):
		# The yard is full (or the player said grow): buy the land next door.
		var cost := _grow_cost(b)
		if dep.cash >= cost + reserve:
			var got := _grow(sim, id)
			if got == "ok":
				dep.cash -= cost
				bought_land = true
				_note(id, "Bought the land next door for more bus bays.")
			elif got == "built":
				_ask_for_land(sim, id, cost)
	# Land the player said yes to: buy out what stands there and move in.
	for req in sim.permits.approved("bus_depot", id):
		if _take_strip(sim, id, req):
			dep.cash -= int(req.cost)
			bought_land = true
			_note(id, "Bought the homes next door, as you approved, for more bus bays.")
		sim.permits.done(req.id)
	# The development tree, from the depot's own money.
	if _has_coach_built(dep) and not _has_coach(id):
		_add_bus(sim, id, "coach")
	var profit: float = float(dep.month.get("net", 0)) * 12.0
	var node := Agency.develop(sim, dep, _open_tree(sim, id), _gate(b), profit)
	if not node.is_empty():
		dep.cash -= int(node.cost)
		_note(id, str(dep.why))
	var day := sim.tick_count / DECIDE_EVERY
	if day - int(dep.fare_day) >= FARE_EVERY_DAYS:
		_set_fare(id, b)
		dep.fare_day = day
	_share_buses(id)
	version += 1
	return bought_land


## The fare. Both kinds of director keep it within what riders here can
## pay. An educated director knows riders leave as fares rise (TCRP: -0.4)
## and picks the lowest fare that keeps the depot in business; a less
## educated one nudges the fare up after a losing month and down after a
## good one.
func _set_fare(id: int, b: Dictionary) -> void:
	var dep: Dictionary = depots[id]
	var top := snappedf(Balance.BUS_FARE_BASE_MAX + Balance.BUS_FARE_RICH_EXTRA * dep.wealth, 0.25)
	var bottom := 0.0 if dep.education >= 0.6 else 0.5
	var old: float = dep.fare
	var fare := old
	if dep.education >= 0.5:
		var cost: float = mini(dep.target, _fleet(id)) * Balance.BUS_MONTHLY_COST
		fare = top
		var f := bottom
		while f <= top + 0.001:
			var fares := _ridership(id, f) * 30.0 * f
			var gap := cost - fares
			if fares + Balance.BUS_GRANT_SHARE * maxf(0.0, gap) + int(b.get("subsidy", 0)) >= cost:
				fare = f
				break
			f += 0.25
	elif not dep.month.is_empty():
		if dep.month.net < 0:
			fare = old + 0.25
		elif dep.month.net > 0.2 * maxf(dep.month.cost, 1.0):
			fare = old - 0.25
	fare = clampf(snappedf(fare, 0.25), bottom, top)
	if not is_equal_approx(fare, old):
		dep.fare = fare
		var why := "to cover its costs" if fare > old else "since the money allows it"
		_note(id, "%s the fare to $%.2f %s." % ["Raised" if fare > old else "Lowered", fare, why])


## Daily boardings on the depot's network at a fare, from who lives and
## works by each stop, how often the bus comes and what it costs.
func _ridership(id: int, fare: float) -> float:
	var total := 0.0
	for r in routes.get(id, []):
		for sid in r.stops:
			if stops.has(sid):
				stops[sid].riders = 0.0
	for r in routes.get(id, []):
		if r.buses <= 0:
			continue
		var day := 0.0
		for sid in r.stops:
			var n := _stop_riders(sid, fare, r.headway_min, id)
			day += n
			if stops.has(sid):
				stops[sid].riders += n
		r.riders = day
		total += day
	if depots.has(id):
		total += Agency.effect(depots[id], TREE, "riders+")
	return total


## Daily boardings at one stop on one route.
func _stop_riders(sid: int, fare: float, headway: float, id: int) -> float:
	if not stops.has(sid) or headway == INF:
		return 0.0
	var s: Dictionary = stops[sid]
	var dep: Dictionary = depots.get(id, {})
	var wealth: float = dep.get("wealth", 0.5)
	var share := Balance.BUS_BASE_SHARE
	share *= pow(maxf(fare, 0.25) / 1.5, Balance.BUS_FARE_ELASTICITY)
	share *= clampf(pow(Balance.BUS_TARGET_HEADWAY_MIN / headway, Balance.BUS_SERVICE_ELASTICITY), 0.3, 1.6)
	# Households with less money ride more (ACS commuting by income).
	share *= 1.6 - 1.2 * wealth
	if not dep.is_empty():
		share *= Agency.effect(dep, TREE, "riders*")
	var on_routes := 0
	for r in routes.get(id, []):
		if sid in r.stops:
			on_routes += 1
	return share * (s.res + s.jobs) / maxf(on_routes, 1.0)


## Riders on the busiest stretch of one trip of a route.
func _per_trip(r: Dictionary, fare: float, headway: float) -> float:
	var day := 0.0
	for sid in r.stops:
		day += _stop_riders(sid, fare, headway, stops[sid].depot if stops.has(sid) else -1)
	# A trip carries its share of the day's riders; the busiest hour has
	# about twice the average hour's riders and about half are aboard at once.
	return day * headway / (Balance.BUS_SERVICE_HOURS * 60.0)


## How well off the depot's riders are, 0 to 1, from the things the
## neighborhood wealth score is made of (Balance.HOOD_WEALTH_WEIGHTS):
## services, work and full homes. Land value isn't simulated yet, so its
## share follows the services.
func _wealth(sim: CitySim, id: int) -> float:
	var w: Dictionary = Balance.HOOD_WEALTH_WEIGHTS
	var employment := float(sim.stats.employed) / maxf(sim.stats.workers, 1.0)
	var cover := 0.0
	var occ := 0.0
	var n := 0
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if b.zone != ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		var mine := false
		for r in routes.get(id, []):
			for sid in r.stops:
				if stops.has(sid) and stops[sid].pt.distance_to(p) <= Balance.BUS_WALK:
					mine = true
					break
			if mine:
				break
		if not mine:
			continue
		n += 1
		cover += sim.services.coverage(key)
		occ += float(b.occ) / maxf(b.cap, 1.0)
	if n == 0:
		return 0.5
	cover /= n
	occ /= n
	return clampf((w.land_value + w.services) * cover + w.employment * employment + w.occupancy * occ, 0.0, 1.0)


func _fleet(id: int) -> int:
	var n := 0
	for bid in buses:
		if buses[bid].depot == id and buses[bid].kind == "city_bus" and not buses[bid].get("retire", false):
			n += 1
	return n


func _note(id: int, text: String) -> void:
	if not depots.has(id):
		return
	var log: Array = depots[id].log
	log.append(text)
	while log.size() > 4:
		log.pop_front()


# --- The yard -----------------------------------------------------------------

## Bus stalls in a depot of this size, in the site's local frame (centre at
## the origin, -z toward the road): [position of the stall's front end,
## facing]. Rows of stalls behind the garage, each nosed onto its aisle.
static func bay_slots(size: Vector2) -> Array:
	var out := []
	var per_row := int((size.x - 2.0) / STALL_W)
	var z := -size.y * 0.5 + GARAGE_D
	while z + AISLE + STALL_D <= size.y * 0.5 - 0.5:
		for i in per_row:
			var x := -size.x * 0.5 + 1.0 + (i + 0.5) * STALL_W
			out.append([Vector3(x, 0.0, z + AISLE + 0.6), Vector3(0, 0, -1)])
		z += AISLE + STALL_D
	return out


static func bays_for(size: Vector2) -> int:
	return bay_slots(size).size()


## Where the depot's driveway meets the street.
static func _gate(b: Dictionary) -> Vector3:
	return b.pos + b.dir * (Services.size_of(b).y * 0.5 + Services.SETBACK)


## A bus parked in its bay, in world space: [front of the bus, facing].
func bay_pose(sim: CitySim, bus: Dictionary) -> Array:
	var b: Dictionary = sim.services.buildings.get(bus.depot, {})
	if b.is_empty():
		return [bus.at, bus.dir]
	var frame := Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos)
	if b.kind == Services.Kind.SCHOOL:
		# Along the school's side, past the bus loop.
		var size := Services.size_of(b)
		var p := Vector3(size.x * 0.5 - 3.0, 0.0, -size.y * 0.5 + 34.0 + bus.bay * 4.0)
		return [frame * p, frame.basis * Vector3(0, 0, -1)]
	var slots := bay_slots(Services.size_of(b))
	if slots.is_empty():
		return [_gate(b), -b.dir]
	var slot: Array = slots[bus.bay % slots.size()]
	return [frame * slot[0], frame.basis * slot[1]]


func _cost_per_m2() -> float:
	return Balance.BUS_LAND_PER_M2


func _grow_cost(b: Dictionary) -> int:
	return roundi(GROW_STEP * Services.size_of(b).x * _cost_per_m2())


## Buys a strip of land directly behind the depot, or beside it once it's
## as deep as it gets: only free land (no road, building, farm, company or
## land saved for something else), never more than Balance.HUB_MAX_GROWTH
## times the first site.
func _grow(sim: CitySim, id: int) -> String:
	var b: Dictionary = sim.services.buildings[id]
	var size := Services.size_of(b)
	var first: Vector2 = Services.KINDS[b.kind].size
	if (size.x + GROW_STEP) * size.y > first.x * first.y * Balance.HUB_MAX_GROWTH \
			and size.x * (size.y + GROW_STEP) > first.x * first.y * Balance.HUB_MAX_GROWTH:
		return "no"
	var side := Vector3(-b.dir.z, 0.0, b.dir.x)
	var tries := [[Vector2(0, GROW_STEP), -b.dir * GROW_STEP * 0.5],
		[Vector2(GROW_STEP, 0), side * GROW_STEP * 0.5], [Vector2(GROW_STEP, 0), -side * GROW_STEP * 0.5]]
	if size.y >= size.x * 2.0:
		tries = [tries[1], tries[2], tries[0]]  # deep enough: go sideways first
	var built := []
	for t in tries:
		var new_size: Vector2 = size + t[0]
		if new_size.x * new_size.y > first.x * first.y * Balance.HUB_MAX_GROWTH:
			continue
		var pos: Vector3 = b.pos + t[1]
		var why := land_free(sim, id, pos, b.dir, new_size)
		if why == "":
			b.pos = pos
			b.size = new_size
			return "ok"
		if why == "built" and built.is_empty():
			built = [pos, new_size]
	# Only homes or shops stand in the way: the director may ask to buy them.
	if not built.is_empty():
		depots[id].strip = [[built[0].x, built[0].z], [built[1].x, built[1].y]]
		return "built"
	return "no"


## "" when the land is free, "built" when only homes or businesses stand on
## it (the player can let the depot buy them), else "no".
static func land_free(sim: CitySim, id: int, pos: Vector3, dir: Vector3, size: Vector2) -> String:
	var poly := PackedVector2Array()
	for p in Services.corners(Services.Kind.BUS_DEPOT, pos, dir, size):
		poly.append(Vector2(p.x, p.z))
	if Services.road_clash(sim.network, poly):
		return "no"
	var off: Vector2 = sim.services.terrain_offset
	if not Terrain.buildable(pos.x + off.x, pos.z + off.y, size.length() * 0.5):
		return "no"  # water or a steep slope
	for oid in sim.services.buildings:
		if oid != id and not Geometry2D.intersect_polygons(poly, sim.services.footprint(oid)).is_empty():
			return "no"
	for i in 9:
		var t := Vector2((i % 3) / 2.0, (i / 3) / 2.0)
		var q: Vector2 = poly[0].lerp(poly[1], t.x).lerp(poly[3].lerp(poly[2], t.x), t.y)
		var p := Vector3(q.x, 0.0, q.y)
		if sim.farms.covers(p) or sim.farms.field_at(p) != -1 or sim.industry.covers(p) or sim.reserves.kind_at(p) != "":
			return "no"
	# Homes and businesses already built aren't the depot's to take; empty
	# lots are.
	for key in sim.buildings:
		if sim.lots.has(key) and Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), poly):
			return "built"
	return ""


## The homes or shops behind the depot are in the way: ask the player, through
## a land permit, to let the depot buy them out (Permits never forces it).
func _ask_for_land(sim: CitySim, id: int, cost: int) -> void:
	var dep: Dictionary = depots[id]
	if dep.strip.is_empty() or not sim.permits.can_file(sim, "bus_depot", id):
		return
	var b: Dictionary = sim.services.buildings[id]
	var pos := Vector3(dep.strip[0][0], 0.0, dep.strip[0][1])
	var size := Vector2(dep.strip[1][0], dep.strip[1][1])
	var area := []
	for p in Services.corners(Services.Kind.BUS_DEPOT, pos, b.dir, size):
		area.append([p.x, p.z])
	var hits := sim.permits.check(sim, area, 0.0, true)
	var homes := 0
	for h in hits.get("buildings", []):
		if h.what == "lot":
			homes += 1
	sim.permits.file(sim, {"hub": "bus_depot", "hub_id": id, "leader": "The transit director",
		"title": "Buy %d building%s next to the bus depot" % [homes, "" if homes == 1 else "s"],
		"why": "The bus yard is full; more bays let the depot run the buses the town needs.",
		"area": area, "change": "Homes and shops to bus yard", "per_m2": roundi(Balance.BUS_LAND_PER_M2 * 6.0),
		"base": cost, "budget": int(dep.cash)})


## Carries out an approved land permit: the buildings on the strip are bought
## and cleared, and the yard grows over them.
func _take_strip(sim: CitySim, id: int, req: Dictionary) -> bool:
	var dep: Dictionary = depots[id]
	var b: Dictionary = sim.services.buildings.get(id, {})
	if b.is_empty() or dep.strip.is_empty():
		return false
	var pos := Vector3(dep.strip[0][0], 0.0, dep.strip[0][1])
	var size := Vector2(dep.strip[1][0], dep.strip[1][1])
	var outline := PackedVector2Array()
	for p in req.route:
		outline.append(Vector2(float(p[0]), float(p[1])))
	for key in sim.buildings.keys():
		if sim.lots.has(key) and Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), outline):
			sim.buildings.erase(key)
	dep.strip = []
	if land_free(sim, id, pos, b.dir, size) != "":
		return false  # the player trimmed the area: not enough land to grow
	b.pos = pos
	b.size = size
	sim.buildings_changed.emit()
	return true


## The tree nodes whose BusNet-only needs hold, with those needs taken out
## so Agency checks the rest.
func _open_tree(sim: CitySim, id: int) -> Array:
	var out := []
	var schools_in_town := 0
	for sid in sim.services.buildings:
		if sim.services.buildings[sid].kind == Services.Kind.SCHOOL:
			schools_in_town += 1
	var near := neighbors(sim)
	for node in TREE:
		var needs: Dictionary = node.get("needs", {}).duplicate()
		var ok := true
		if needs.has("neighbors"):
			ok = ok and near >= int(needs.neighbors)
			needs.erase("neighbors")
		if needs.has("school"):
			ok = ok and schools_in_town >= int(needs.school)
			needs.erase("school")
		if ok:
			var n: Dictionary = node.duplicate()
			n.needs = needs
			out.append(n)
	return out


## Neighboring towns this one trades with (last month's deals, plus what the
## region server reports). Solo towns have none.
static func neighbors(sim: CitySim) -> int:
	var towns := {}
	for d in sim.trade.last_deals:
		for side in ["buyer", "seller"]:
			var t := str(d.get(side, "outside"))
			if t != "outside" and t != "me" and t != "":
				towns[t] = true
	for town in sim.region.get("neighbors", []):
		towns[str(town.get("name", ""))] = true
	return towns.size()


func _has_coach_built(dep: Dictionary) -> bool:
	return "intercity" in dep.get("built", [])


func _has_coach(id: int) -> bool:
	for bid in buses:
		if buses[bid].depot == id and buses[bid].kind == "coach":
			return true
	return false


## People a day riding the coach to and from the neighboring towns.
func coach_riders(sim: CitySim, id: int) -> int:
	if not depots.has(id):
		return 0
	var share := Balance.BUS_COACH_DAILY_SHARE * Agency.effect(depots[id], TREE, "coach*")
	return roundi(sim.stats.population * share * neighbors(sim))


## Where the county highway leaves for the region (the coach's far end).
static func _link_pos(sim: CitySim) -> Vector3:
	for n in sim.region_links:
		if sim.network.nodes.has(n):
			return sim.network.nodes[n]
	return Vector3.INF





# --- Buses on the road ----------------------------------------------------------

func _add_bus(sim: CitySim, home: int, kind: String) -> int:
	var used := {}
	for bid in buses:
		if buses[bid].depot == home:
			used[buses[bid].bay] = true
	var bay := 0
	while used.has(bay):
		bay += 1
	var id := _next_bus
	_next_bus += 1
	var bus := {"id": id, "depot": home, "kind": kind, "state": "parked", "route": -1, "stop": -1,
		"target": -1, "load": 0, "until": 0, "bay": bay, "at": Vector3.ZERO, "dir": Vector3.FORWARD, "run": []}
	buses[id] = bus
	var pose := bay_pose(sim, bus)
	bus.at = pose[0]
	bus.dir = pose[1]
	return id


## A bus leaves the city's books, and its vehicle leaves the road if it's
## parked somewhere (one still driving finishes its trip first).
func _drop(sim: CitySim, bid: int) -> void:
	var bus: Dictionary = buses.get(bid, {})
	if int(bus.get("vid", -1)) != -1 and bus.get("state", "") != "driving":
		sim.traffic.retire_vehicle(int(bus.vid))
	buses.erase(bid)


func _retire_one(id: int) -> bool:
	var bids := buses.keys()
	bids.sort()
	bids.reverse()
	for bid in bids:
		var bus: Dictionary = buses[bid]
		if bus.depot == id and bus.kind == "city_bus" and not bus.get("retire", false):
			bus.retire = true
			bus.route = -1
			return true
	return false


## Picks up Traffic's reports for our buses and leaves the rest alone.
func _arrivals(sim: CitySim) -> void:
	if trips.is_empty():
		return
	for list in [sim.traffic.arrivals, sim.traffic.failed]:
		var ok: bool = list == sim.traffic.arrivals
		var i := 0
		while i < list.size():
			var a: Dictionary = list[i]
			var tid := int(a.get("trip", a.get("id", -1)))
			if not trips.has(tid):
				i += 1
				continue
			var bid: int = trips[tid]
			trips.erase(tid)
			list.remove_at(i)
			if buses.has(bid):
				if a.has("vid"):
					buses[bid].vid = int(a.vid)
				_arrived(sim, buses[bid], ok)


func _arrived(sim: CitySim, bus: Dictionary, ok: bool) -> void:
	if not ok:
		# No way through: wait where it is and try the next stop later.
		bus.state = "wait"
		bus.stop = bus.target
		bus.until = sim.tick_count + RETRY_TICKS
		return
	if bus.target == -1:
		# Home: in through the garage and into its bay (off the road).
		_off_road(sim, bus)
		if bus.get("retire", false) or not sim.services.buildings.has(bus.depot):
			_drop(sim, bus.id)
			return
		var pose := bay_pose(sim, bus)
		bus.at = pose[0]
		bus.dir = pose[1]
		bus.state = "parked"
		bus.load = 0
		if bus.kind == "coach":
			bus.until = sim.tick_count + BUS_COACH_AWAY_TICKS
		return
	if bus.target == -2:
		# Off the map edge to the neighboring towns; back after the layover.
		_off_road(sim, bus)
		bus.at = _link_pos(sim)
		bus.load = 0
		bus.state = "away"
		bus.until = sim.tick_count + BUS_COACH_AWAY_TICKS
		return
	bus.stop = bus.target
	var riders := 0
	if bus.kind == "school_bus":
		var stop_at: Vector3 = bus.run[bus.target] if bus.target < bus.run.size() else bus.at
		bus.at = stop_at
		var s: Dictionary = schools.get(bus.depot, {})
		var each := ceili(float(s.get("riders", 0)) / maxf(_school_buses(bus.depot) * maxf(bus.run.size(), 1), 1.0))
		if bus.get("morning", true):
			riders = mini(each, Balance.SCHOOL_BUS_LOAD - bus.load)
			bus.load += riders
		else:
			riders = mini(each, bus.load)
			bus.load -= riders
		bus.state = "dwell"
		bus.until = sim.tick_count + DWELL_TICKS + DWELL_PER_RIDER * riders
		return
	if not stops.has(bus.target):
		bus.state = "wait"
		bus.until = sim.tick_count + 1
		return
	var s: Dictionary = stops[bus.target]
	bus.at = s.pos
	riders = _board(bus, s)
	bus.state = "dwell"
	bus.until = sim.tick_count + DWELL_TICKS + DWELL_PER_RIDER * riders


## People getting off and on at a stop: off by the share of the route's
## destinations here, on by this stop's riders per trip.
func _board(bus: Dictionary, s: Dictionary) -> int:
	var list: Array = routes.get(bus.depot, [])
	if bus.route < 0 or bus.route >= list.size():
		var off: int = bus.load
		bus.load = 0
		return off
	var r: Dictionary = list[bus.route]
	var people := maxf(_route_people(r), 1.0)
	var off: int = roundi(bus.load * clampf((s.res + s.jobs) * 2.0 / people, 0.0, 1.0))
	if r.stops.size() > 0 and r.stops[0] == s.id:
		off = roundi(bus.load * 0.7)  # the transfer stop downtown
	bus.load -= off
	var dep: Dictionary = depots.get(bus.depot, {})
	var on := roundi(_stop_riders(s.id, dep.get("fare", 1.5), r.headway_min, bus.depot) * r.headway_min \
		/ (Balance.BUS_SERVICE_HOURS * 60.0))
	on = clampi(on, 0, Balance.BUS_CAPACITY - bus.load)
	bus.load += on
	return off + on


## Sends parked and waiting buses on their way.
func _drive(sim: CitySim) -> void:
	var bids := buses.keys()
	bids.sort()
	for bid in bids:
		if not buses.has(bid):
			continue
		var bus: Dictionary = buses[bid]
		if bus.state == "driving" or sim.tick_count < int(bus.until):
			continue
		if bus.kind == "school_bus":
			_school_next(sim, bus)
			continue
		if bus.kind == "coach":
			_coach_next(sim, bus)
			continue
		var list: Array = routes.get(bus.depot, [])
		var on_route: bool = bus.route >= 0 and bus.route < list.size() and list[bus.route].stops.size() >= 2
		if bus.state == "parked":
			if not on_route or sim.tick_count < int(_next_launch.get(bus.depot, 0)):
				continue
			var first: int = list[bus.route].stops[0]
			if _send(sim, bus, first):
				_next_launch[bus.depot] = sim.tick_count + LAUNCH_GAP
			continue
		# At a stop (or stuck): on to the next stop, or home if off duty.
		if not on_route or not sim.services.buildings.has(bus.depot):
			_send(sim, bus, -1)
			continue
		var ids: Array = list[bus.route].stops
		var i := ids.find(bus.stop)
		_send(sim, bus, ids[(i + 1) % ids.size()] if i != -1 else ids[0])


## The coach: out to the county highway's region link, a layover in the
## neighboring towns, then home to its bay until the next run.
func _coach_next(sim: CitySim, bus: Dictionary) -> void:
	if bus.state == "parked":
		if bus.get("retire", false) or not _has_coach_built(depots.get(bus.depot, {})):
			_drop(sim, bus.id)
			return
		bus.load = mini(ceili(coach_riders(sim, bus.depot) / 2.0), Balance.BUS_COACH_SEATS)
		if not _send(sim, bus, -2):
			bus.load = 0
		return
	if bus.state == "away":
		bus.load = mini(ceili(coach_riders(sim, bus.depot) / 2.0), Balance.BUS_COACH_SEATS)
	_send(sim, bus, -1)


## Puts a bus on the road to a stop (-1: home to its depot). False if no
## road leads there yet; it tries again later.
func _send(sim: CitySim, bus: Dictionary, target: int) -> bool:
	var to := Vector3.ZERO
	if target == -1:
		var b: Dictionary = sim.services.buildings.get(bus.depot, {})
		if b.is_empty():
			_drop(sim, bus.id)
			return false
		to = _gate(b)
	elif target == -2:
		to = _link_pos(sim)
		if to == Vector3.INF:
			bus.until = sim.tick_count + RETRY_TICKS
			return false
	elif bus.kind == "school_bus":
		to = bus.run[target]
	else:
		to = stops[target].pos
	var from: Vector3 = bus.at
	if bus.state == "parked":
		from = _gate(sim.services.buildings[bus.depot])
	var purpose := "school" if bus.kind == "school_bus" else "transit"
	var kind: String = bus.kind if bus.kind == "school_bus" or bus.kind == "coach" else "city_bus"
	var cargo := {"riders": bus.load, "bus": bus.id}
	var dest := {"ref": "edge" if target == -2 else "bus:%d" % bus.id, "pos": [to.x, to.z]}
	var tid := -1
	if bus.state == "away":
		# Back in off the county highway from the neighboring towns.
		var link := _link_pos(sim)
		tid = sim.traffic.dispatch({"ref": "edge", "pos": [link.x, link.z]}, dest, purpose, cargo, kind)
	else:
		tid = leg(sim.traffic, bus, "bus:%d" % bus.id, from, dest, purpose, cargo, kind)
	if tid == -1:
		bus.until = sim.tick_count + RETRY_TICKS
		if bus.state != "parked":
			bus.state = "wait"
			bus.stop = target
		return false
	trips[tid] = bus.id
	bus.target = target
	bus.state = "driving"
	return true


## One traffic vehicle per bus (or cab) for its whole run: put on the road
## at `from` when it pulls out of its yard, sent stop to stop with
## TrafficSim.move (so it parks at each stop, no trip back), and taken off
## the road again when it pulls into its yard (_off_road). Returns the trip
## id, or -1 if it can't go yet.
static func leg(traffic: TrafficSim, v: Dictionary, ref: String, from: Vector3, to: Dictionary,
		purpose: String, cargo: Dictionary, kind: String) -> int:
	var fresh := int(v.get("vid", -1)) == -1
	if fresh:
		var at := traffic.register({"ref": ref, "pos": [from.x, from.z]})
		if at == "":
			return -1
		var vid := traffic.new_vehicle(kind, at, -1, at)
		if vid == -1:
			return -1
		v.vid = vid
	var tid := traffic.move(int(v.vid), to, purpose, cargo)
	if tid == -1 and fresh:
		traffic.retire_vehicle(int(v.vid))
		v.vid = -1
	return tid


## Into the garage (or off the map edge): its vehicle leaves the road.
func _off_road(sim: CitySim, bus: Dictionary) -> void:
	if int(bus.get("vid", -1)) != -1:
		sim.traffic.retire_vehicle(int(bus.vid))
		bus.vid = -1


# --- School buses -----------------------------------------------------------------

func _school_buses(id: int) -> int:
	var n := 0
	for bid in buses:
		if buses[bid].depot == id and buses[bid].kind == "school_bus":
			n += 1
	return n


## Who rides to each school, where the bus picks them up, and how many
## buses the school keeps (one per 66 pupils, parked at the school).
func _plan_schools(sim: CitySim) -> void:
	var ids := schools.keys()
	ids.sort()
	if ids.is_empty():
		return
	var homes := {}  # school id -> [[pos, pupils]]
	for sid in ids:
		homes[sid] = []
	for key in sim.buildings:
		var h: Dictionary = sim.buildings[key]
		if h.zone != ZoneMap.Zone.RESIDENTIAL or h.occ <= 0 or not sim.lots.has(key):
			continue
		if not sim.services.served.get(key, {}).get(Services.Kind.SCHOOL, false):
			continue
		var p: Vector3 = sim.lots[key].front
		var best := -1
		for sid in ids:
			if best == -1 or sim.services.buildings[sid].pos.distance_to(p) < sim.services.buildings[best].pos.distance_to(p):
				best = sid
		if sim.services.buildings[best].pos.distance_to(p) > Balance.SCHOOL_WALK:
			homes[best].append([p, h.occ * Balance.SCHOOL_PUPIL_SHARE])
	for sid in ids:
		var school: Dictionary = schools[sid]
		var b: Dictionary = sim.services.buildings[sid]
		var pupils := 0.0
		var picks := []  # [pos, pupils]
		var list: Array = homes[sid]
		list.sort_custom(func(a, c): return a[0].x < c[0].x or a[0].x == c[0].x and a[0].z < c[0].z)
		for h in list:
			pupils += h[1]
			var joined := false
			for pk in picks:
				if pk[0].distance_to(h[0]) < 200.0:
					pk[1] += h[1]
					joined = true
					break
			if not joined:
				picks.append([h[0], h[1]])
		school.riders = roundi(pupils)
		var need := clampi(ceili(pupils / Balance.SCHOOL_BUS_LOAD), 0, Balance.SCHOOL_BUS_MAX)
		while _school_buses(sid) < need:
			_add_bus(sim, sid, "school_bus")
		# Buses no longer needed are sold once they're home.
		var have := _school_buses(sid)
		var bids := buses.keys()
		bids.sort()
		bids.reverse()
		for bid in bids:
			if have <= need:
				break
			if buses[bid].depot == sid and buses[bid].kind == "school_bus" and buses[bid].state == "parked":
				_drop(sim, bid)
				have -= 1
		# Each bus takes a slice of the pickups around the school.
		var center: Vector3 = b.pos
		picks.sort_custom(func(a, c): return atan2(a[0].z - center.z, a[0].x - center.x) < atan2(c[0].z - center.z, c[0].x - center.x))
		school.pickups = picks.map(func(pk): return pk[0])
		school.runs = []
		var n := maxi(have, 1)
		for i in n:
			var part: Array = school.pickups.slice(roundi(i * picks.size() / float(n)), roundi((i + 1) * picks.size() / float(n)))
			# Farthest pickup first, then nearest next, ending at the school.
			part.sort_custom(func(a, c): return a.distance_to(center) > c.distance_to(center))
			var run := []
			var left := part.duplicate()
			while not left.is_empty():
				var k := 0
				if not run.is_empty():
					for j in left.size():
						if left[j].distance_to(run[-1]) < left[k].distance_to(run[-1]):
							k = j
				run.append(left[k])
				left.remove_at(k)
			school.runs.append(run)


## School days: weekdays outside the summer break (June and July; the
## game's months follow Seasons).
static func school_day(t: Dictionary) -> bool:
	if t.weekday == 0 or t.weekday == 6:
		return false
	return t.month != 6 and t.month != 7


## At the bell times, every school bus at home sets off on its run: in the
## morning out to its farthest pickup and back to school, in the afternoon
## the other way round.
func _school_bells(sim: CitySim) -> void:
	if schools.is_empty():
		return
	var t := sim.clock()
	var minute: int = t.hour * 60 + t.minute
	if minute != Balance.SCHOOL_MORNING_RUN and minute != Balance.SCHOOL_AFTERNOON_RUN or not school_day(t):
		return
	var morning := minute == Balance.SCHOOL_MORNING_RUN
	var bids := buses.keys()
	bids.sort()
	var slot := {}
	for bid in bids:
		var bus: Dictionary = buses[bid]
		if bus.kind != "school_bus" or bus.state != "parked" or not schools.has(bus.depot):
			continue
		var runs: Array = schools[bus.depot].runs
		var i: int = slot.get(bus.depot, 0)
		slot[bus.depot] = i + 1
		if i >= runs.size() or runs[i].is_empty():
			continue
		var run: Array = runs[i].duplicate()
		if not morning:
			run.reverse()
		bus.run = run
		bus.morning = morning
		bus.load = 0 if morning else mini(Balance.SCHOOL_BUS_LOAD,
			ceili(float(schools[bus.depot].riders) / maxf(runs.size(), 1.0)))
		bus.state = "dwell"
		bus.stop = -1
		bus.until = sim.tick_count + i * 30  # buses leave one after another
		bus.from_school = true


func _school_next(sim: CitySim, bus: Dictionary) -> void:
	if bus.state == "parked":
		return
	if bus.get("from_school", false):
		# Pulling out of the school lot.
		bus.from_school = false
		var b: Dictionary = sim.services.buildings.get(bus.depot, {})
		if b.is_empty():
			_drop(sim, bus.id)
			return
		bus.at = _gate(b)
		if bus.run.is_empty():
			bus.state = "parked"
			return
		_send(sim, bus, 0)
		return
	var next: int = bus.stop + 1
	if next >= bus.run.size():
		_send(sim, bus, -1)
	else:
		_send(sim, bus, next)


# --- What the panels show ---------------------------------------------------------

## Buses that aren't on Traffic's roads right now (in a bay, at a stop):
## [kind, front of the bus, facing, load, drawn by Traffic (parked on the road)].
func standing(sim: CitySim) -> Array:
	var out := []
	var bids := buses.keys()
	bids.sort()
	for bid in bids:
		var bus: Dictionary = buses[bid]
		if bus.state == "driving" or bus.state == "away":
			continue
		var on_road := int(bus.get("vid", -1)) != -1  # Traffic draws it where it's parked
		var dir: Vector3 = bus.dir
		if bus.state == "parked":
			var pose := bay_pose(sim, bus)
			out.append([bus.kind, pose[0], pose[1], 0])
			continue
		if bus.kind == "city_bus" and stops.has(bus.stop):
			var s: Dictionary = stops[bus.stop]
			# Pulled in at the curb, facing the way traffic on that side goes.
			dir = s.dir * (-s.side)
			out.append([bus.kind, s.pos + dir * 6.0, dir, bus.load, on_road])
		else:
			out.append([bus.kind, bus.at, dir if dir.length() > 0.5 else Vector3.FORWARD, bus.load, on_road])
	return out


## The panel for a depot: Inspect's format.
func describe(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
	var k: Dictionary = Services.KINDS[b.kind]
	var dep: Dictionary = depots.get(id, _new_depot())
	var list: Array = routes.get(id, [])
	var rows := []
	var problems := []
	var running := 0
	var nstops := 0
	var headway := INF
	for r in list:
		if r.buses > 0:
			running += 1
			headway = minf(headway, r.headway_min)
		nstops += r.stops.size()
	var fleet := _fleet(id)
	var bays := bays_for(Services.size_of(b))
	rows.append(["Buses", "%d of %d bays" % [fleet, bays]])
	rows.append(["Routes", "%d running, %d stops" % [running, nstops]])
	if headway < INF:
		rows.append(["A bus every", "%d minutes" % roundi(headway)])
	rows.append(["Riders", "%s a day" % CitySim.money_text(int(dep.riders))])
	rows.append(["Fare", "$%.2f (set by the depot)" % dep.fare])
	# Set by the depot's Funding slider (Economy page).
	rows.append(["City funding", "$%s / month" % CitySim.money_text(int(b.get("subsidy", 0)))])
	var m: Dictionary = dep.month
	if not m.is_empty():
		rows.append(["Fares", "$%s / month" % CitySim.money_text(int(m.fares))])
		rows.append(["Federal grant", "$%s / month" % CitySim.money_text(int(m.grant))])
		rows.append(["Running costs", "$%s / month" % CitySim.money_text(int(m.cost))])
	rows.append(["Depot's cash", ("-$%s" if dep.cash < 0 else "$%s") % CitySim.money_text(absi(int(dep.cash)))])
	rows.append(["Director", "%s, riders %s" % [_education_words(dep.education), _wealth_words(dep.wealth)]])
	if _has_coach(id):
		rows.append(["Coach riders", "%d a day to %d neighboring town%s" % [coach_riders(sim, id), neighbors(sim),
			"" if neighbors(sim) == 1 else "s"]])
	var profit: float = float(dep.month.get("net", 0)) * 12.0
	rows.append_array(Inspect._development(sim, dep, _open_tree(sim, id), _gate(b), profit))
	var linked := not sim.network.find_segment_near(_gate(b), 80.0, 1.0).is_empty()
	var status := ""
	if not linked:
		problems.append("Not beside a road, so its buses can't get out.")
		status = "Not running"
	elif list.is_empty() or nstops == 0:
		problems.append("No stops yet: buses go where at least %d people live or work within a quarter mile." % int(Balance.BUS_STOP_MIN_PEOPLE))
		status = "Waiting for riders"
	elif fleet == 0:
		status = "Saving up for its first bus"
	else:
		status = "Running %d route%s" % [running, "" if running == 1 else "s"]
	if dep.target < dep.wanted and int(b.get("subsidy", 0)) / (1.0 - Balance.BUS_GRANT_SHARE) < dep.wanted * Balance.BUS_MONTHLY_COST * 0.5 and nstops > 0:
		problems.append("The subsidy covers %d of the %d buses a bus every half hour needs." % [dep.target, dep.wanted])
	if mini(dep.wanted, dep.target) >= bays and dep.wanted > bays:
		problems.append("The yard is full: it will buy the land next door when it's free and it can afford it.")
	return {"title": k.name, "kind": "Transit", "icon": k.icon, "ok": linked and problems.is_empty() and fleet > 0,
		"status": status, "rows": rows, "problems": problems, "log": dep.log.duplicate()}


static func _education_words(e: float) -> String:
	if e >= 0.75:
		return "college-educated"
	if e >= 0.5:
		return "well-schooled"
	return "self-taught"


static func _wealth_words(w: float) -> String:
	for i in range(Balance.HOOD_TIERS.size() - 1, -1, -1):
		if w >= Balance.HOOD_TIERS[i].min:
			return str(Balance.HOOD_TIERS[i].name).to_lower()
	return "working class"


## The panel for a school's buses (added to the school's own rows).
func school_rows(id: int) -> Array:
	if not schools.has(id):
		return []
	return [["Pupils by bus", str(schools[id].riders)], ["School buses", str(_school_buses(id))]]


# --- Saving -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {"next_stop": _next_stop, "next_bus": _next_bus, "stops": [], "buses": [], "depots": {},
		"trips": {}, "launch": {}}
	var ids := stops.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = stops[id]
		d.stops.append([id, s.pt.x, s.pt.z, s.side])
	ids = buses.keys()
	ids.sort()
	for id in ids:
		var bus: Dictionary = buses[id]
		var run := []
		for p in bus.run:
			run.append([p.x, p.z])
		d.buses.append({"id": id, "depot": bus.depot, "kind": bus.kind, "state": bus.state, "route": bus.route,
			"stop": bus.stop, "target": bus.target, "load": bus.load, "until": bus.until, "bay": bus.bay,
			"at": [bus.at.x, bus.at.z], "dir": [bus.dir.x, bus.dir.z], "run": run,
			"retire": bus.get("retire", false), "morning": bus.get("morning", true),
			"from_school": bus.get("from_school", false), "vid": bus.get("vid", -1)})
	for id in depots:
		var dep: Dictionary = depots[id]
		d.depots[str(id)] = {"cash": dep.cash, "fare": dep.fare, "fare_day": dep.fare_day, "wanted": dep.wanted,
			"target": dep.target, "riders": dep.riders, "month": dep.month, "log": dep.log,
			"leader": dep.leader, "built": dep.built, "why": dep.why, "strip": dep.strip}
	for tid in trips:
		d.trips[str(tid)] = trips[tid]
	for id in _next_launch:
		d.launch[str(id)] = _next_launch[id]
	return d


## Loads a saved state. The city's roads and buildings must be loaded first;
## routes are planned again from the stops.
func from_dict(sim: CitySim, d: Dictionary) -> void:
	_next_stop = int(d.get("next_stop", 1))
	_next_bus = int(d.get("next_bus", 1))
	stops.clear()
	for a in d.get("stops", []):
		var s := {"id": int(a[0]), "pt": Vector3(a[1], 0.0, a[2]), "side": float(a[3]), "name": "Stop %d" % int(a[0]),
			"riders": 0.0, "depot": -1, "res": 0.0, "jobs": 0.0}
		var near := sim.network.find_segment_near(s.pt, 15.0)
		if near.is_empty():
			continue
		_place_stop(sim, s, near)
		stops[s.id] = s
	buses.clear()
	for a in d.get("buses", []):
		var run := []
		for p in a.get("run", []):
			run.append(Vector3(p[0], 0.0, p[1]))
		buses[int(a.id)] = {"id": int(a.id), "depot": int(a.depot), "kind": str(a.kind), "state": str(a.state),
			"route": int(a.route), "stop": int(a.stop), "target": int(a.target), "load": int(a.load),
			"until": int(a.until), "bay": int(a.bay), "at": Vector3(a.at[0], 0.0, a.at[1]),
			"dir": Vector3(a.dir[0], 0.0, a.dir[1]), "run": run, "retire": bool(a.get("retire", false)),
			"morning": bool(a.get("morning", true)), "from_school": bool(a.get("from_school", false)),
			"vid": int(a.get("vid", -1))}
	depots.clear()
	for k in d.get("depots", {}):
		var dep := _new_depot()
		var v: Dictionary = d.depots[k]
		for f in ["cash", "riders", "wanted", "target", "fare_day"]:
			dep[f] = int(v.get(f, dep[f]))
		dep.fare = float(v.get("fare", dep.fare))
		dep.month = v.get("month", {})
		dep.log = v.get("log", [])
		dep.leader = v.get("leader", Agency.leader(sim, hash([int(k), "bus_depot"])))
		dep.built = v.get("built", [])
		dep.why = str(v.get("why", ""))
		dep.strip = v.get("strip", [])
		depots[int(k)] = dep
	trips.clear()
	for k in d.get("trips", {}):
		trips[int(k)] = int(d.trips[k])
	_next_launch.clear()
	for k in d.get("launch", {}):
		_next_launch[int(k)] = int(d.launch[k])
	schools.clear()
	_sync(sim)
	_plan(sim)
	# Bus route numbers were saved; keep them as planned.
	for id in depots:
		_ridership(id, depots[id].fare)
