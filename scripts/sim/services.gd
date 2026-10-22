class_name Services
extends RefCounted
## City services, Cities: Skylines 2 style: power and water flow along the
## roads from a source, and safety, health and schools cover the homes within
## a real response distance by road.
##
## Sizes, prices and reach follow real US practice for a small town.

enum Kind { SUBSTATION, WATER_TOWER, FIRE, POLICE, CLINIC, SCHOOL }

## Each kind: name, icon, footprint (width along the road x depth, metres),
## build cost, monthly upkeep, and either `reach` (metres by road) or
## `capacity` (homes-equivalent it can serve).
const KINDS := {
	# Ties the town to the regional grid (homes buy power from the utility).
	# A 20 MVA distribution substation carries about 13,000 homes.
	Kind.SUBSTATION: {"name": "Substation", "icon": "power", "size": Vector2(30, 30),
		"cost": 900_000, "upkeep": 6_000, "capacity": 13_000, "utility": "power"},
	# Well, pump house and a 500,000 gallon elevated tank: about 1 million
	# gallons a day, at 300 gallons per household.
	Kind.WATER_TOWER: {"name": "Water tower", "icon": "water", "size": Vector2(30, 30),
		"cost": 2_000_000, "upkeep": 12_000, "capacity": 3_300, "utility": "water"},
	# Two-bay station. ISO rates homes within 1.5 road miles of a station.
	Kind.FIRE: {"name": "Fire station", "icon": "fire", "size": Vector2(30, 36),
		"cost": 2_500_000, "upkeep": 45_000, "reach": 2400.0},
	# A small department's station, patrols covering about 2 road miles.
	Kind.POLICE: {"name": "Police station", "icon": "police", "size": Vector2(30, 36),
		"cost": 1_800_000, "upkeep": 50_000, "reach": 3200.0},
	# Walk-in clinic; most Americans live within a few miles of one.
	Kind.CLINIC: {"name": "Clinic", "icon": "health", "size": Vector2(30, 30),
		"cost": 1_500_000, "upkeep": 35_000, "reach": 4800.0},
	# Elementary school for about 400 pupils on a 2 acre site.
	Kind.SCHOOL: {"name": "Elementary school", "icon": "school", "size": Vector2(80, 100),
		"cost": 9_000_000, "upkeep": 95_000, "reach": 3200.0},
}
## Kinds that cover homes by distance (the rest are utilities).
const COVERAGE := [Kind.FIRE, Kind.POLICE, Kind.CLINIC, Kind.SCHOOL]
## Water and sewer bills the city collects, per month.
const WATER_FEE := {ZoneMap.Zone.RESIDENTIAL: 45, ZoneMap.Zone.COMMERCIAL: 120, ZoneMap.Zone.INDUSTRIAL: 300}
## How much each building draws, in homes-equivalent.
const LOAD := {ZoneMap.Zone.RESIDENTIAL: 1, ZoneMap.Zone.COMMERCIAL: 4, ZoneMap.Zone.INDUSTRIAL: 12}
## Gap kept between a service's front and the road's edge.
const SETBACK := 2.0


## The service buildings: id -> {kind, pos: Vector3 (centre), dir: Vector3
## (unit, from the building toward its road)}.
var buildings := {}
## What each lot gets: lot key -> {"power": bool, "water": bool, Kind: bool...}
var served := {}
## Use of each utility: {"power": [used, capacity], "water": [used, capacity]}
var utility_use := {"power": [0, 0], "water": [0, 0]}
## Distance by road from the nearest service of each kind to every road node.
var reach_by_kind := {}
var _next_id := 1


static func spec(kind: int) -> Dictionary:
	return KINDS[kind]


## The four corners of a service's footprint, on the ground.
static func corners(kind: int, pos: Vector3, dir: Vector3) -> Array:
	var size: Vector2 = KINDS[kind].size
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
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p.x, p.z))
	# Clear of every road (sampled along each road, with its width).
	for id in network.segments:
		var hw := RoadStyle.right_of_way_half(network.segments[id].type)
		for p in network.sample_segment(id, 24):
			var q := Vector2(p.x, p.z)
			if Geometry2D.is_point_in_polygon(q, poly):
				return "Too close to a road."
			for i in 4:
				if Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % 4]).distance_to(q) < hw - 0.5:
					return "Too close to a road."
	for id in buildings:
		var b: Dictionary = buildings[id]
		var other := PackedVector2Array()
		for p in corners(b.kind, b.pos, b.dir):
			other.append(Vector2(p.x, p.z))
		if not Geometry2D.intersect_polygons(poly, other).is_empty():
			return "Overlaps the %s." % KINDS[b.kind].name.to_lower()
	return ""


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
		for c in corners(b.kind, b.pos, b.dir):
			poly.append(Vector2(c.x, c.z))
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
			return id
	return -1


## True when a point sits on any service's footprint (lots there are dropped).
func covers(p: Vector3) -> bool:
	return at(p) != -1


func monthly_upkeep() -> int:
	var total := 0
	for id in buildings:
		total += int(KINDS[buildings[id].kind].upkeep)
	return total


## Works out what every lot gets, from distances along the roads.
func update(network: RoadNetwork, lots: Dictionary, city_buildings: Dictionary) -> void:
	served.clear()
	reach_by_kind.clear()
	var lengths := {}
	for id in network.segments:
		lengths[id] = RoadNetwork.polyline_length(network.sample_segment(id, 16))
	for kind in KINDS:
		var dist := {}
		for id in buildings:
			if buildings[id].kind == kind:
				_spread(network, lengths, buildings[id], dist)
		reach_by_kind[kind] = dist
	var keys := lots.keys()
	keys.sort()
	# Utilities serve the nearest buildings first, up to their capacity.
	var by_dist := {"power": [], "water": []}
	for key in keys:
		var lot: Dictionary = lots[key]
		var s := {}
		for kind in COVERAGE:
			s[kind] = _lot_distance(network, lengths, reach_by_kind[kind], lot) <= KINDS[kind].reach
		served[key] = s
		for kind in [Kind.SUBSTATION, Kind.WATER_TOWER]:
			var d := _lot_distance(network, lengths, reach_by_kind[kind], lot)
			s[KINDS[kind].utility] = false
			if d < INF:
				by_dist[KINDS[kind].utility].append([d, key])
	for kind in [Kind.SUBSTATION, Kind.WATER_TOWER]:
		var u: String = KINDS[kind].utility
		var cap := 0
		for id in buildings:
			if buildings[id].kind == kind:
				cap += int(KINDS[kind].capacity)
		var used := 0
		by_dist[u].sort()
		for entry in by_dist[u]:
			var key: String = entry[1]
			var load := 1
			if city_buildings.has(key):
				load = LOAD[int(city_buildings[key].zone)]
				if used + load > cap:
					continue
				used += load
			served[key][u] = used <= cap
		utility_use[u] = [used, cap]


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
func _spread(network: RoadNetwork, lengths: Dictionary, b: Dictionary, dist: Dictionary) -> void:
	var near := network.find_segment_near(b.pos + b.dir * KINDS[b.kind].size.y * 0.5, 80.0, 1.0)
	if near.is_empty():
		return
	var s: Dictionary = network.segments[near.seg]
	var l: float = lengths[near.seg]
	var frontier := {}
	frontier[s.a] = near.t * l
	frontier[s.b] = (1.0 - near.t) * l
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
			var nd: float = d + lengths[seg]
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
	return {"next_id": _next_id, "buildings": out}


func from_dict(d: Dictionary) -> void:
	buildings.clear()
	for k in d.get("buildings", {}):
		var a: Array = d.buildings[k]
		buildings[int(k)] = {"kind": int(a[0]), "pos": Vector3(a[1], 0.0, a[2]),
			"dir": Vector3(a[3], 0.0, a[4]).normalized()}
	_next_id = int(d.get("next_id", 1))
