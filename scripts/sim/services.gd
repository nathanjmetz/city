class_name Services
extends RefCounted
## City services, Cities: Skylines 2 style: power and water flow along the
## roads from a source, and safety, health and schools cover the homes within
## a real response distance by road.
##
## Sizes, prices and reach follow real US practice for a small town.

enum Kind { SUBSTATION, WATER_TOWER, FIRE, POLICE, CLINIC, SCHOOL, POWER_FEED, WELL, BUS_DEPOT, WATER_UTILITY, TAXI_COMPANY }

## Each kind: name, icon, footprint (width along the road x depth, metres),
## and its build cost, monthly upkeep and `reach` or `capacity` from Balance.
const KINDS := {
	# Ties the town to the regional grid (homes buy power from the utility).
	# A 20 MVA distribution substation carries about 13,000 homes.
	Kind.SUBSTATION: {"name": "Substation", "icon": "power", "size": Vector2(30, 30),
		"cost": Balance.SERVICES["substation"]["cost"], "upkeep": Balance.SERVICES["substation"]["upkeep"], "capacity": Balance.SERVICES["substation"]["capacity"], "utility": "power"},
	# Well, pump house and a 500,000 gallon elevated tank: about 1 million
	# gallons a day, at 300 gallons per household.
	Kind.WATER_TOWER: {"name": "Water tower", "icon": "water", "size": Vector2(30, 30),
		"cost": Balance.SERVICES["water_tower"]["cost"], "upkeep": Balance.SERVICES["water_tower"]["upkeep"], "capacity": Balance.SERVICES["water_tower"]["capacity"], "utility": "water"},
	# Starter utilities for a village: an overhead feed with pole transformers
	# from the regional utility, and a 150 gpm well with a pressure tank
	# (about 200,000 gallons a day).
	Kind.POWER_FEED: {"name": "Power line feed", "icon": "power", "size": Vector2(12, 12),
		"cost": Balance.SERVICES["power_feed"]["cost"], "upkeep": Balance.SERVICES["power_feed"]["upkeep"], "capacity": Balance.SERVICES["power_feed"]["capacity"], "utility": "power"},
	Kind.WELL: {"name": "Well and pump house", "icon": "water", "size": Vector2(20, 20),
		"cost": Balance.SERVICES["well"]["cost"], "upkeep": Balance.SERVICES["well"]["upkeep"], "capacity": Balance.SERVICES["well"]["capacity"], "utility": "water"},
	# The water and sewer utility (Brawn's hub with a manager): an office and
	# its first well. It pays its own way from water bills plus the city's
	# subsidy, so the city pays no upkeep for it (see WaterUtility).
	Kind.WATER_UTILITY: {"name": "Water and sewer utility", "icon": "water", "size": Vector2(30, 30),
		"cost": Balance.WATER_UTILITY["cost"], "upkeep": 0, "capacity": Balance.WATER_WORKS["well"]["capacity"], "utility": "water", "hub": true},
	# Two-bay station. ISO rates homes within 1.5 road miles of a station.
	Kind.FIRE: {"name": "Fire station", "icon": "fire", "size": Vector2(30, 36),
		"cost": Balance.SERVICES["fire"]["cost"], "upkeep": Balance.SERVICES["fire"]["upkeep"], "reach": Balance.SERVICES["fire"]["reach"]},
	# A small department's station, patrols covering about 2 road miles.
	Kind.POLICE: {"name": "Police station", "icon": "police", "size": Vector2(30, 36),
		"cost": Balance.SERVICES["police"]["cost"], "upkeep": Balance.SERVICES["police"]["upkeep"], "reach": Balance.SERVICES["police"]["reach"]},
	# Walk-in clinic; most Americans live within a few miles of one.
	Kind.CLINIC: {"name": "Clinic", "icon": "health", "size": Vector2(30, 30),
		"cost": Balance.SERVICES["clinic"]["cost"], "upkeep": Balance.SERVICES["clinic"]["upkeep"], "reach": Balance.SERVICES["clinic"]["reach"]},
	# Elementary school for about 400 pupils on a 2 acre site.
	Kind.SCHOOL: {"name": "Elementary school", "icon": "school", "size": Vector2(80, 100),
		"cost": Balance.SERVICES["school"]["cost"], "upkeep": Balance.SERVICES["school"]["upkeep"], "reach": Balance.SERVICES["school"]["reach"]},
	# A small-town bus garage: two maintenance bays, an office and a fenced
	# yard of bus stalls. It runs itself (BusNet) and grows into the land
	# next door; its monthly cost is the subsidy the player sets.
	Kind.BUS_DEPOT: {"name": "Bus depot", "icon": "bus", "size": Vector2(36, 44),
		"cost": Balance.SERVICES["bus_depot"]["cost"], "upkeep": Balance.SERVICES["bus_depot"]["upkeep"], "transit": true},
	# A cab company: a storefront dispatch office with a lot of cab stalls
	# behind it. Its owner runs it on fares (TaxiCo) and grows next door.
	Kind.TAXI_COMPANY: {"name": "Taxi company", "icon": "taxi", "size": Vector2(30, 34),
		"cost": Balance.SERVICES["taxi_company"]["cost"], "upkeep": Balance.SERVICES["taxi_company"]["upkeep"], "transit": true},
}
## Which kinds supply each utility.
const UTILITIES := {"power": [Kind.SUBSTATION, Kind.POWER_FEED], "water": [Kind.WATER_TOWER, Kind.WELL]}
## Kinds that cover homes by distance (the rest are utilities).
const COVERAGE := [Kind.FIRE, Kind.POLICE, Kind.CLINIC, Kind.SCHOOL]
## Water and sewer bills the city collects, per month.
const WATER_FEE := Balance.WATER_FEE
## How much each building draws, in homes-equivalent.
const LOAD := Balance.UTILITY_LOAD
## Gap kept between a service's front and the road's edge.
const SETBACK := 2.0


## The service buildings: id -> {kind, pos: Vector3 (centre), dir: Vector3
## (unit, from the building toward its road)}.
## Where the city sits in the shared region (set by CitySim).
var terrain_offset := Vector2.ZERO
var buildings := {}
## What each lot gets: lot key -> {"power": bool, "water": bool, Kind: bool...}
var served := {}
## Use of each utility: {"power": [used, capacity], "water": [used, capacity]}
var utility_use := {"power": [0, 0], "water": [0, 0]}
## Distance by road from the nearest service of each kind to every road node.
var reach_by_kind := {}
## The water and sewer utilities' managers, works and pipes.
var water := WaterUtility.new()
## Power companies' plants (Power.sources(), set by the city): more power
## sources, each feeding the lines from its yard gate.
var plants := []
## The town's Funding slider: a lean department costs less and covers less.
var policies: Policies
var _next_id := 1


## The Economy page area a service kind belongs to.
static func area_of(kind: int) -> String:
	return "utilities" if KINDS[kind].has("utility") else "public"


## Upkeep and reach (or capacity) multipliers for service `id` from Funding.
func funding(id: int, list: Array) -> float:
	if policies == null or not buildings.has(id):
		return 1.0
	return policies.pick(list, "funding", area_of(buildings[id].kind), "service:%d" % id)


## This service's monthly upkeep at its Funding.
func upkeep_of(id: int) -> int:
	return roundi(int(KINDS[buildings[id].kind].upkeep) * funding(id, Balance.POLICY_UPKEEP))


static func spec(kind: int) -> Dictionary:
	return KINDS[kind]


## The four corners of a service's footprint, on the ground. `size` is for
## hubs that have grown past their kind's first size.
static func corners(kind: int, pos: Vector3, dir: Vector3, size := Vector2.ZERO) -> Array:
	if size == Vector2.ZERO:
		size = KINDS[kind].size
	var side := Vector3(-dir.z, 0.0, dir.x)
	var out := []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(pos + side * size.x * 0.5 * s.x + dir * size.y * 0.5 * s.y)
	return out


## Where a service of this kind goes when placed beside the road nearest
## `hit`: [centre, dir toward the road, seg], or [] if no road is near.
static func site_near(network: RoadNetwork, kind: int, hit: Vector3) -> Array:
	var near := network.find_segment_near(hit, 80.0, 1.0)
	if near.is_empty() or not RoadStyle.TYPES[network.segments[near.seg].type].lots:
		return []
	var c := network.curve_of(near.seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
	tan.y = 0.0
	tan = tan.normalized()
	var normal := Vector3(-tan.z, 0.0, tan.x)
	var p: Vector3 = near.point
	if (hit - p).dot(normal) < 0.0:
		normal = -normal
	var depth: float = KINDS[kind].size.y
	var front := RoadStyle.right_of_way_half(network.segments[near.seg].type) + SETBACK
	return [Vector3(p.x, 0.0, p.z) + normal * (front + depth * 0.5), -normal, near.seg]


## Why a service can't go here, or "" if it can.
func site_problem(network: RoadNetwork, kind: int, pos: Vector3, dir: Vector3) -> String:
	var pts := corners(kind, pos, dir)
	var size: Vector2 = KINDS[kind].size
	if not Terrain.buildable(pos.x + terrain_offset.x, pos.z + terrain_offset.y, size.length() * 0.5):
		return "Can't build in the water or on a slope that steep."
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p.x, p.z))
	if road_clash(network, poly):
		return "Too close to a road."
	for id in buildings:
		var b: Dictionary = buildings[id]
		var other := PackedVector2Array()
		for p in corners(b.kind, b.pos, b.dir, size_of(b)):
			other.append(Vector2(p.x, p.z))
		if not Geometry2D.intersect_polygons(poly, other).is_empty():
			return "Overlaps the %s." % KINDS[b.kind].name.to_lower()
	for p in pts:
		if water.covers(buildings, p):
			return "Overlaps the water utility's yard."
	return ""


## True when a footprint (four corners) runs onto any road.
static func road_clash(network: RoadNetwork, poly: PackedVector2Array) -> bool:
	for id in network.segments:
		var hw := RoadStyle.right_of_way_half(network.segments[id].type)
		for p in network.sample_segment(id, 24):
			var q := Vector2(p.x, p.z)
			if Geometry2D.is_point_in_polygon(q, poly):
				return true
			for i in poly.size():
				if Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q) < hw - 0.5:
					return true
	return false


## A building's size now (a bus depot grows into the land next door).
static func size_of(b: Dictionary) -> Vector2:
	return b.get("size", KINDS[b.kind].size)


## The ground a service covers, as a polygon.
func footprint(id: int) -> PackedVector2Array:
	var b: Dictionary = buildings[id]
	var out := PackedVector2Array()
	for p in corners(b.kind, b.pos, b.dir, size_of(b)):
		out.append(Vector2(p.x, p.z))
	return out


func add(kind: int, pos: Vector3, dir: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	buildings[id] = {"kind": kind, "pos": pos, "dir": dir}
	return id


## The service whose footprint holds this point, or -1.
func at(p: Vector3) -> int:
	for id in buildings:
		var b: Dictionary = buildings[id]
		var poly := PackedVector2Array()
		for c in corners(b.kind, b.pos, b.dir, size_of(b)):
			poly.append(Vector2(c.x, c.z))
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
			return id
	return -1


## True when a point sits on any service's footprint or a water utility's
## yard (lots there are dropped).
func covers(p: Vector3) -> bool:
	return at(p) != -1 or water.covers(buildings, p)


func monthly_upkeep() -> int:
	var total := 0
	for id in buildings:
		total += upkeep_of(id) + int(buildings[id].get("subsidy", 0))
	return total + water.monthly_subsidy()


## Works out what every lot gets, from distances along the roads.
func update(network: RoadNetwork, lots: Dictionary, city_buildings: Dictionary) -> void:
	served.clear()
	reach_by_kind.clear()
	water.prune(buildings)
	water.refresh(network)
	var lengths := {}
	for id in network.segments:
		lengths[id] = RoadNetwork.polyline_length(network.sample_segment(id, 16))
	for kind in KINDS:
		var dist := {}
		for id in buildings:
			if buildings[id].kind == kind:
				_spread(network, lengths, buildings[id], dist, funding(id, Balance.POLICY_EFFECT))
		reach_by_kind[kind] = dist
	var plant_dist := {}
	for pl in plants:
		_spread_from(network, lengths, pl.front, plant_dist)
	var keys := lots.keys()
	keys.sort()
	# Utilities serve the nearest buildings first, up to their capacity.
	var by_dist := {"power": [], "water": []}
	# Lots on a utility's mains get their water from it: id -> [[dist, key]].
	var on_mains := {}
	for key in keys:
		var lot: Dictionary = lots[key]
		var s := {}
		for kind in COVERAGE:
			s[kind] = _lot_distance(network, lengths, reach_by_kind[kind], lot) <= KINDS[kind].reach
		served[key] = s
		var owner := water.main_owner(lot.seg)
		if owner != -1:
			s["water_linked"] = true
			if not on_mains.has(owner):
				on_mains[owner] = []
			on_mains[owner].append([lot.pos.distance_to(buildings[owner].pos), key, lot.seg])
		for u in ["power", "water"]:
			s[u] = false
			if u == "water" and owner != -1:
				continue
			var d := INF
			for kind in UTILITIES[u]:
				d = minf(d, _lot_distance(network, lengths, reach_by_kind[kind], lot))
			if u == "power":
				d = minf(d, _lot_distance(network, lengths, plant_dist, lot))
			# Joined to a source by road at all (before capacity is shared out).
			s[u + "_linked"] = d < INF
			if d < INF:
				by_dist[u].append([d, key])
	for u in ["power", "water"]:
		var cap := 0
		for id in buildings:
			if buildings[id].kind in UTILITIES[u]:
				cap += roundi(int(KINDS[buildings[id].kind].capacity) * funding(id, Balance.POLICY_EFFECT))
		if u == "power":
			for pl in plants:
				cap += int(pl.capacity)
		var used := 0
		by_dist[u].sort()
		for entry in by_dist[u]:
			var key: String = entry[1]
			var load := 1
			if city_buildings.has(key):
				load = LOAD[int(city_buildings[key].zone)] * BuildingTypes.load_of(city_buildings[key])
				if used + load > cap:
					continue
				used += load
			served[key][u] = used <= cap
		utility_use[u] = [used, cap]
	_serve_from_utilities(on_mains, city_buildings)


## Shares each utility's water (and sewer) among the lots on its pipes,
## nearest first, and adds up its bills.
func _serve_from_utilities(on_mains: Dictionary, city_buildings: Dictionary) -> void:
	for id in water.live:
		var l: Dictionary = water.live[id]
		var list: Array = on_mains.get(id, [])
		list.sort()
		var cap := water.water_capacity(id) + int(l.get("bought", 0))
		var scap := water.sewer_capacity(id)
		var used := 0
		var sused := 0
		var fees := 0.0
		var homes := 0
		var meters := (1.0 + (Balance.WATER_METER_GAIN if water.has_work(id, "meters") else 0.0)) * float(water.utilities[id].get("rate", 1.0))
		for entry in list:
			var key: String = entry[1]
			var s: Dictionary = served[key]
			s["water_by"] = id
			var load := 1
			if city_buildings.has(key):
				load = LOAD[int(city_buildings[key].zone)]
				if used + load > cap:
					continue
				used += load
			s["water"] = used <= cap
			var sewer := false
			if scap > 0 and l.sewers.has(entry[2]):
				if not city_buildings.has(key):
					sewer = true
				elif sused + load <= scap:
					sused += load
					sewer = true
			s["sewer"] = sewer
			if city_buildings.has(key):
				var z := int(city_buildings[key].zone)
				var fee: float = WATER_FEE[z] * (1.0 - Balance.WATER_SEWER_SHARE * (0.0 if sewer else 1.0))
				if z == ZoneMap.Zone.INDUSTRIAL and water.has_work(id, "industrial_main"):
					fee *= 1.0 + Balance.WATER_INDUSTRY_GAIN
				fees += fee * meters
				if z == ZoneMap.Zone.RESIDENTIAL:
					homes += 1
		l.homes_eq = used
		l.load = used
		l.sewer_load = sused
		l.fees = roundi(fees)
		l.homes = homes
		utility_use.water[0] += used
		utility_use.water[1] += cap


## True when the lot has power and water, so a building can grow there.
func has_utilities(key: String) -> bool:
	return served.has(key) and served[key].power and served[key].water


## Share of the four coverage services a lot gets, 0 to 1.
func coverage(key: String) -> float:
	if not served.has(key):
		return 0.0
	var n := 0
	for kind in COVERAGE:
		if served[key][kind]:
			n += 1
	return n / float(COVERAGE.size())


## Road distance from each service's front door to every node (Dijkstra).
## `effect` stretches its reach: distances are counted as d / effect, so a
## well-funded station covers farther than a lean one of the same kind.
func _spread(network: RoadNetwork, lengths: Dictionary, b: Dictionary, dist: Dictionary, effect := 1.0) -> void:
	_spread_from(network, lengths, b.pos + b.dir * size_of(b).y * 0.5, dist, effect)


func _spread_from(network: RoadNetwork, lengths: Dictionary, front: Vector3, dist: Dictionary, effect := 1.0) -> void:
	var near := network.find_segment_near(front, 80.0, 1.0)
	if near.is_empty():
		return
	var s: Dictionary = network.segments[near.seg]
	var l: float = lengths[near.seg]
	var frontier := {}
	var k := 1.0 / maxf(effect, 0.01)
	frontier[s.a] = near.t * l * k
	frontier[s.b] = (1.0 - near.t) * l * k
	var done := {}
	while not frontier.is_empty():
		var best := -1
		for n in frontier:
			if best == -1 or frontier[n] < frontier[best] or (frontier[n] == frontier[best] and n < best):
				best = n
		var d: float = frontier[best]
		frontier.erase(best)
		done[best] = true
		if not dist.has(best) or d < dist[best]:
			dist[best] = d
		elif dist[best] < d:
			continue
		for seg in network.segments_at(best):
			var sg: Dictionary = network.segments[seg]
			var other: int = sg.b if sg.a == best else sg.a
			var nd: float = d + lengths[seg] * k
			if done.has(other) or (dist.has(other) and dist[other] <= nd):
				continue
			if not frontier.has(other) or nd < frontier[other]:
				frontier[other] = nd


func _lot_distance(network: RoadNetwork, lengths: Dictionary, dist: Dictionary, lot: Dictionary) -> float:
	if not network.segments.has(lot.seg):
		return INF
	var s: Dictionary = network.segments[lot.seg]
	var l: float = lengths[lot.seg]
	var best := INF
	if dist.has(s.a):
		best = minf(best, dist[s.a] + lot.at_frac * l)
	if dist.has(s.b):
		best = minf(best, dist[s.b] + (1.0 - lot.at_frac) * l)
	return best


func to_dict() -> Dictionary:
	var out := {}
	for id in buildings:
		var b: Dictionary = buildings[id]
		out[str(id)] = [b.kind, b.pos.x, b.pos.z, b.dir.x, b.dir.z]
		if b.has("size") or b.has("subsidy"):
			out[str(id)].append_array([size_of(b).x, size_of(b).y, int(b.get("subsidy", 0))])
	return {"next_id": _next_id, "buildings": out, "water": water.to_dict()}


func from_dict(d: Dictionary) -> void:
	buildings.clear()
	for k in d.get("buildings", {}):
		var a: Array = d.buildings[k]
		buildings[int(k)] = {"kind": int(a[0]), "pos": Vector3(a[1], 0.0, a[2]),
			"dir": Vector3(a[3], 0.0, a[4]).normalized()}
		if a.size() >= 8:
			buildings[int(k)].size = Vector2(a[5], a[6])
			buildings[int(k)].subsidy = int(a[7])
	_next_id = int(d.get("next_id", 1))
	water.from_dict(d.get("water", {}))
