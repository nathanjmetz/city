class_name HubRoads
extends RefCounted
## Roads that hubs build for themselves (Brawn, 2026-10-23): a hub with a
## leader grows only to a real size, then builds a road to reach more land.
## The road starts as part of the hub's own expansion, paid for by the hub,
## and from then on it is a normal public road in the city's network: the
## player can drive it, zone along it, upgrade it or remove it.
##
## Real reference: Indiana's county roads. Most rural roads in Pike County
## began as farm and mine roads on the land-survey lines and were taken over
## by the county; many are still gravel. So a hub's road goes in as gravel
## (RoadStyle.Type.GRAVEL) and the player can pave it like any other.
##
## Hubs never wreck what the player built: a road that would cross the
## player's roads (other than where it joins one), lots or buildings goes to
## the bell as a permit request instead (see Permits). Land saved for
## another use, water, steep banks and other hubs' land stop it outright.
##
## How a hub uses it:
##   var start := HubRoads.reach(sim, far_end, toward, max_len)  # where it joins the network
##   var plan := HubRoads.check(sim, [start, ..., far_end], "farm:3")
##   if plan.ok and not plan.permit: HubRoads.build(sim, plan.route)
##   elif plan.ok: file a permit with plan.route, build on approval

const TYPE := RoadStyle.Type.GRAVEL
## Pieces a long road is laid in (m), like the county highway.
const PIECE := 400.0
## How far apart points along a road are checked (m).
const STEP := 8.0
## Where a hub road meets an existing road, this much of it is the junction,
## not a crossing (m).
const JUNCTION := 12.0
## A road's end this near an existing road joins it (m).
const SNAP := 14.0


## Walks from `far_end` along `toward` (a flat unit vector) until it meets a
## public road, at most `max_len` metres. Returns the point on that road,
## or Vector3.INF if there's none.
##
## A county road on the section line (CountyGrid) that already meets the
## town's roads counts too: the hub joins that mile, the way a farm lane
## comes out on the county road, instead of laying its own beside it.
static func reach(sim, far_end: Vector3, toward: Vector3, max_len: float) -> Vector3:
	var d := Vector3(toward.x, 0.0, toward.z).normalized()
	var t := 0.0
	var tried := {}
	while t <= max_len:
		var p := far_end + d * t
		var hit: Dictionary = sim.network.find_segment_near(p, 5.0, 2.0)
		if not hit.is_empty():
			return hit.point
		var mile := _county(sim, p, tried)
		if not mile.is_empty():
			return Vector3(mile.on.x - sim.terrain_offset.x, 0.0, mile.on.y - sim.terrain_offset.y)
		t += 4.0
	return Vector3.INF


## The unjoined county mile under p (within 5 m) that touches the town's
## roads, or {}. `tried` remembers miles already looked at.
static func _county(sim, p: Vector3, tried: Dictionary) -> Dictionary:
	var o: Vector2 = sim.terrain_offset
	var mile := CountyGrid.mile_at(p.x + o.x, p.z + o.y, 5.0)
	if mile.is_empty() or sim.county_joined.has(mile.key):
		return {}
	if not tried.has(mile.key):
		tried[mile.key] = _county_meets_town(sim, mile)
	return mile if tried[mile.key] else {}


## True when the open stretch of a county mile meets a town road.
static func _county_meets_town(sim, mile: Dictionary) -> bool:
	var o: Vector2 = sim.terrain_offset
	var a: Vector2 = CountyGrid.run(mile.on, mile.a) - o
	var b: Vector2 = CountyGrid.run(mile.on, mile.b) - o
	var n := maxi(1, ceili(a.distance_to(b) / 16.0))
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		if not sim.network.find_segment_near(Vector3(q.x, 0.0, q.y), 10.0, 2.0).is_empty():
			return true
	return false


## The point on a public road within SNAP of p, or Vector3.INF.
static func on_road(sim, p: Vector3) -> Vector3:
	var hit: Dictionary = sim.network.find_segment_near(p, SNAP, 2.0)
	return Vector3.INF if hit.is_empty() else hit.point


## Can this hub build a road along `route` (Vector3 points, first one on an
## existing road)? Returns {ok, permit, hits, length, cost, why}: ok false
## means the land can't take a road at all; permit true means it crosses
## something of the player's and must be asked for.
static func check(sim, route: Array, self_ref: String) -> Dictionary:
	var out := {"ok": false, "permit": false, "hits": {}, "length": 0.0, "cost": 0, "route": route, "why": ""}
	if route.size() < 2:
		out.why = "nowhere to join the road network"
		return out
	var length := 0.0
	for i in range(1, route.size()):
		var a: Vector3 = route[i - 1]
		var b: Vector3 = route[i]
		if Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) < RoadNetwork.MIN_LENGTH:
			out.why = "too short"
			return out
		var c := [a, (a + b) * 0.5, b]
		var problem: String = sim.network.crossing_problem(c[0], c[1], c[2])
		if problem == "":
			problem = sim.land_problem([c])
		var saved: String = sim.reserves.crosses(RoadNetwork.sample_curve(c[0], c[1], c[2], 24))
		if problem == "" and saved != "" and saved != "farm":
			problem = "land saved for %s" % Reserves.KINDS[saved]
		if problem != "":
			out.why = problem
			return out
		out.cost += Economy.road_cost(c, TYPE)
		length += a.distance_to(b)
	out.length = length
	# The ground along it: no water or cliffs, and nobody else's land.
	var walked := 0.0
	for i in range(1, route.size()):
		var a: Vector3 = route[i - 1]
		var b: Vector3 = route[i]
		var n := maxi(1, ceili(a.distance_to(b) / STEP))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var along := walked + a.distance_to(b) * float(k) / n
			if along < JUNCTION or along > length - JUNCTION:
				continue
			if not sim.land_ok(p):
				out.why = "water or ground too steep for a road"
				return out
			var who: String = sim.land_owner(p)
			if who != "" and who != self_ref:
				out.why = "another business's land"
				return out
		walked += a.distance_to(b)
	# The player's roads, lots and buildings: ask first.
	var inner := _trimmed(route, JUNCTION, length)
	if inner.size() >= 2:
		var pts := []
		for p in inner:
			pts.append([p.x, p.z])
		out.hits = sim.permits.check(sim, pts, RoadStyle.right_of_way_half(TYPE) * 2.0)
		out.permit = Permits.needs(out.hits)
	out.ok = true
	return out


## Lays the road (the hub pays; the town's money is untouched) and returns
## the new segment ids. From here on it is a public road like any other.
static func build(sim, route: Array) -> Array:
	var money: int = sim.economy.money
	var before: Array = sim.network.segments.keys()
	# Starting on a county road: the town takes over that mile first (free,
	# the county hands it over), and the hub's road joins it.
	if not route.is_empty() and on_road(sim, route[0]) == Vector3.INF:
		sim._join_county(route[0])
	sim.network.begin_batch()
	for i in range(1, route.size()):
		var a: Vector3 = route[i - 1]
		var b: Vector3 = route[i]
		var n := maxi(1, ceili(a.distance_to(b) / PIECE))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			var q := a.lerp(b, float(k + 1) / n)
			sim.network.build_road(p, (p + q) * 0.5, q, TYPE)
	sim.network.end_batch()
	sim.economy.money = money
	return sim.network.segments.keys().filter(func(id): return not id in before)


## The route as [[x, z], ...] for a permit request.
static func flat(route: Array) -> Array:
	var out := []
	for p in route:
		out.append([p.x, p.z])
	return out


## A permit's route (maybe redrawn by the player) back to points, the first
## one snapped onto the road it joins.
static func from_flat(sim, pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append(Vector3(float(p[0]), 0.0, float(p[1])))
	if not out.is_empty():
		var start := on_road(sim, out[0])
		if start != Vector3.INF:
			out[0] = start
		var end := on_road(sim, out[-1])
		if end != Vector3.INF and out.size() >= 2 and end.distance_to(out[0]) > SNAP:
			out[-1] = end
	return out


## The part of a route more than `cut` metres from both ends.
static func _trimmed(route: Array, cut: float, length: float) -> Array:
	var out := []
	var walked := 0.0
	for i in range(1, route.size()):
		var a: Vector3 = route[i - 1]
		var b: Vector3 = route[i]
		var seg := a.distance_to(b)
		var t0 := clampf((cut - walked) / seg, 0.0, 1.0)
		var t1 := clampf((length - cut - walked) / seg, 0.0, 1.0)
		if t1 > t0:
			if out.is_empty() or out[-1].distance_to(a.lerp(b, t0)) > 0.01:
				out.append(a.lerp(b, t0))
			out.append(a.lerp(b, t1))
		walked += seg
	return out
