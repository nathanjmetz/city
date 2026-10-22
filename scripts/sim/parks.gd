class_name Parks
extends RefCounted
## Parks and landmarks.
##
## A park is a hub (Brawn's rule, 2026-10-22): the player places a lawn
## beside a road, and the park fills in by itself over the next couple of
## game years with paths, a playground, a pavilion, a court and a ball
## diamond. When it runs out of room it buys the free strip of land right
## next to it (never a second site), up to Balance.HUB_MAX_GROWTH times its
## first size. What it gets and how well kept it looks follow its
## neighborhood's tier: curated flowerbeds and a fountain where the area is
## thriving, a worn lawn where it is struggling.
##
## Landmarks are one per town: a courthouse square, the water tower with the
## town's name, a co-op grain elevator and the high school football field.
##
## Both lift land value (and so property tax) and happiness around them,
## fading with distance. Benchmarks: CS2's parks and signature buildings for
## the mechanics, real Midwestern towns for what fills in.

const KINDS := {
	"park": {"name": "Park", "icon": "park", "landmark": false},
	"courthouse": {"name": "Courthouse square", "icon": "courthouse", "landmark": true},
	"water_tower": {"name": "Town water tower", "icon": "water_landmark", "landmark": true},
	"grain_elevator": {"name": "Grain elevator", "icon": "elevator", "landmark": true},
	"football": {"name": "Football field", "icon": "football", "landmark": true},
}
## Every park gets its own name, like real Midwestern town parks.
const PARK_NAMES := ["Lincoln", "Riverside", "Memorial", "Oak Grove", "Maple", "Veterans", "Washington",
	"Sunnyside", "Kiwanis", "Rotary", "Heritage", "Willow Creek", "Pioneer", "Legion", "Garfield",
	"Hilltop", "Cedar", "Prairie", "Jaycee", "Elm Street", "Walnut", "Fairview", "Shady Lane",
	"Greenwood", "Burr Oak", "Cardinal", "Meadowbrook", "Founders", "Harmony", "Lakeview"]
const LANDMARK_NAMES := {"courthouse": "Courthouse Square", "water_tower": "Water tower",
	"grain_elevator": "Farmers Co-op Elevator", "football": "Memorial Field"}
## Gap kept between the front of a park and the road, like a service.
const SETBACK := 2.0
## Room kept between things inside a park, metres.
const FEATURE_GAP := 3.0
const DAYS_PER_DECIDE := Balance.PARK_DECIDE_EVERY / (24.0 * 60.0)

## id -> {kind, name, pos (centre), dir (unit, toward its road), size
## (width along the road x depth), start_area, built (tick), features:
## [{type, pos, size}], score (neighborhood, 0 to 1), tier, next_feature
## (tick), grew (strips bought)}.
var sites := {}
## Lift in land value and in happiness each building's lot gets.
var lot_value := {}
var lot_happy := {}
var _next_id := 1


static func size_of(kind: String) -> Vector2:
	return Balance.PARK_START_SIZE if kind == "park" else Balance.AMENITIES[kind].size


static func cost_of(kind: String) -> int:
	return int(Balance.AMENITIES[kind].cost)


## The four corners of a footprint on the ground.
static func corners(pos: Vector3, dir: Vector3, size: Vector2) -> PackedVector2Array:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * size.x * 0.5 * s.x + dir * size.y * 0.5 * s.y
		out.append(Vector2(p.x, p.z))
	return out


## Where a park or landmark goes when placed beside the road nearest `hit`:
## [centre, dir toward the road], or [] if no road is near.
static func site_near(network: RoadNetwork, kind: String, hit: Vector3) -> Array:
	var near := network.find_segment_near(hit, 90.0, 1.0)
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
	var front := RoadStyle.right_of_way_half(network.segments[near.seg].type) + SETBACK
	return [Vector3(p.x, 0.0, p.z) + normal * (front + size_of(kind).y * 0.5), -normal]


## Why this ground can't be taken, or "" if it can. `skip` is a site to
## leave out (the park that is growing).
func ground_problem(sim: CitySim, poly: PackedVector2Array, skip := -1) -> String:
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for id in sim.services.buildings:
		if not Geometry2D.intersect_polygons(poly, sim.services.footprint(id)).is_empty():
			return "Overlaps the %s." % Services.KINDS[sim.services.buildings[id].kind].name.to_lower()
	for id in sites:
		if id != skip and not Geometry2D.intersect_polygons(poly, footprint(id)).is_empty():
			return "Overlaps %s." % sites[id].name
	for key in sim.buildings:
		if sim.lots.has(key) and not Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			return "Buildings stand there."
	for p in _samples(poly):
		var q := Vector3(p.x, 0.0, p.y)
		if sim.farms.covers(q) or sim.farms.field_at(q) != -1:
			return "That ground is farmland."
		if sim.industry.covers(q):
			return "That ground belongs to a company."
		if sim.warehouses.covers(q):
			return "A warehouse stands there."
		if sim.hubs.covers(q):
			return "That ground is a landfill, recycling yard or cemetery."
		if sim.reserves.kind_at(q) != "":
			return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(q)]
	return ""


## Why a park or landmark can't go here, or "" if it can.
func site_problem(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> String:
	if not KINDS.has(kind):
		return "Unknown kind."
	if KINDS[kind].landmark and has_kind(kind):
		return "The town already has its %s (one per town)." % KINDS[kind].name.to_lower()
	return ground_problem(sim, corners(pos, dir, size_of(kind)))


func has_kind(kind: String) -> bool:
	for id in sites:
		if sites[id].kind == kind:
			return true
	return false


func add(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	var size := size_of(kind)
	var s := {"kind": kind, "name": _new_name(kind, id), "pos": pos, "dir": dir, "size": size,
		"start_area": size.x * size.y, "built": sim.tick_count, "features": [], "score": 0.5, "tier": -1,
		"next_feature": sim.tick_count + Balance.PARK_DECIDE_EVERY, "grew": 0}
	sites[id] = s
	var t := Neighborhood.target(sim, pos, lift_at(pos, "value", id))
	s.score = _quantize(t.score)
	s.tier = Neighborhood.tier_for(s.score, -1)
	return id


func _new_name(kind: String, id: int) -> String:
	if kind != "park":
		return LANDMARK_NAMES[kind]
	var used := {}
	for other in sites:
		used[sites[other].name] = true
	var start := absi(hash([id, "park"])) % PARK_NAMES.size()
	for round in 4:
		for i in PARK_NAMES.size():
			var n: String = ["", "North ", "South ", "East "][round] + PARK_NAMES[(start + i) % PARK_NAMES.size()] + " Park"
			if not used.has(n):
				return n
	return "Park %d" % id


func footprint(id: int) -> PackedVector2Array:
	var s: Dictionary = sites[id]
	return corners(s.pos, s.dir, s.size)


## The park or landmark whose ground holds this point, or -1.
func at(p: Vector3) -> int:
	for id in sites:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), footprint(id)):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1


func acres(id: int) -> float:
	var s: Dictionary = sites[id]
	return s.size.x * s.size.y / 4046.86


func monthly_upkeep() -> int:
	var total := 0.0
	for id in sites:
		total += site_upkeep(id)
	return roundi(total)


## A park costs more to keep the better kept it is.
func site_upkeep(id: int) -> float:
	var s: Dictionary = sites[id]
	if s.kind != "park":
		return float(Balance.AMENITIES[s.kind].upkeep)
	return acres(id) * Balance.PARK_UPKEEP_PER_ACRE * float(Neighborhood.TIERS[maxi(s.tier, 0)].upkeep)


func has_feature(id: int, type: String) -> bool:
	for f in sites[id].features:
		if f.type == type:
			return true
	return false


## The things this park's neighborhood tier calls for.
func wanted_features(id: int) -> Array:
	var out := []
	for f in Balance.PARK_FEATURES:
		if int(f.tier) <= maxi(sites[id].tier, 0):
			out.append(f)
	return out


## How strongly a site pulls on the land around it: a landmark fully; a park
## by how filled-in it is and how well kept (its tier's finish).
func quality(id: int) -> float:
	var s: Dictionary = sites[id]
	if s.kind != "park":
		return 1.0
	var want := wanted_features(id).size()
	var have := 0
	for f in wanted_features(id):
		if has_feature(id, f.type):
			have += 1
	return (0.4 + 0.6 * float(have) / maxf(want, 1.0)) * float(Neighborhood.TIERS[maxi(s.tier, 0)].finish)


## Distance from a point to a site's ground (0 inside).
func distance_to(id: int, p: Vector3) -> float:
	var s: Dictionary = sites[id]
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var d: Vector3 = p - s.pos
	var u := maxf(absf(d.dot(side)) - s.size.x * 0.5, 0.0)
	var v := maxf(absf(d.dot(s.dir)) - s.size.y * 0.5, 0.0)
	return Vector2(u, v).length()


## The lift every park and landmark gives at a point: "value" or "happy".
func lift_at(p: Vector3, effect: String, skip := -1) -> float:
	var total := 0.0
	for id in sites:
		if id == skip:
			continue
		var a: Dictionary = Balance.AMENITIES[sites[id].kind]
		var reach: float = a[effect + "_reach"]
		var d := distance_to(id, p)
		if d < reach:
			total += float(a[effect]) * quality(id) * (1.0 - d / reach)
	return minf(total, Balance.AMENITY_VALUE_CAP if effect == "value" else Balance.AMENITY_HAPPY_CAP)


## Works out the lift each building's lot gets (after stats update).
func update_effects(sim: CitySim) -> void:
	lot_value.clear()
	lot_happy.clear()
	if sites.is_empty():
		return
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		lot_value[key] = lift_at(p, "value")
		lot_happy[key] = lift_at(p, "happy")


## Average happiness lift across the town's homes, 0 to AMENITY_HAPPY_CAP.
func average_happiness(sim: CitySim) -> float:
	var total := 0.0
	var n := 0
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			total += float(lot_happy.get(key, 0.0))
			n += 1
	return 0.0 if n == 0 else total / n


## Every site follows its neighborhood, and parks fill in or grow. Returns
## true when anything visible changed.
func decide(sim: CitySim) -> bool:
	var changed := false
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sites[id]
		var t := Neighborhood.target(sim, s.pos, lift_at(s.pos, "value", id))
		if int(t.homes) > 0:
			s.score = _quantize(Neighborhood.follow(s.score, t.score, DAYS_PER_DECIDE))
		var tier := Neighborhood.tier_for(s.score, s.tier)
		if tier != s.tier:
			s.tier = tier
			changed = true
		if s.kind == "park" and sim.tick_count >= int(s.next_feature):
			if _fill_in(sim, id, int(t.residents)):
				s.next_feature = sim.tick_count + roundi(Balance.PARK_FEATURE_DAYS * 24.0 * 60.0)
				changed = true
	return changed


## Adds the next thing the park wants that fits, or buys land for it.
func _fill_in(sim: CitySim, id: int, residents: int) -> bool:
	var s: Dictionary = sites[id]
	for f in wanted_features(id):
		if has_feature(id, f.type):
			continue
		var spot = _find_spot(id, f.type, f.size)
		if spot != null:
			s.features.append({"type": f.type, "pos": spot, "size": f.size})
			return true
		# No room: buy the strip next door if people here use the park.
		if s.tier > 0 and residents >= Balance.PARK_GROW_MIN_RESIDENTS and _grow(sim, id):
			return true
	return false


## A free spot for a feature, in world space, or null. Each kind of thing
## has a usual place: the playground near the street, the ball diamond at
## the back, the fountain in the middle.
func _find_spot(id: int, type: String, size: Vector2):
	var s: Dictionary = sites[id]
	if size == Vector2.ZERO:
		return s.pos  # paths run through the whole park
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var hu: float = s.size.x * 0.5 - size.x * 0.5 - FEATURE_GAP
	var hv: float = s.size.y * 0.5 - size.y * 0.5 - FEATURE_GAP
	if hu < 0.0 or hv < 0.0:
		return null
	# Where it likes to be, as (along, back from the street) in -1..1.
	var like: Vector2 = {"playground": Vector2(-0.5, -0.6), "pavilion": Vector2(0.4, -0.1),
		"court": Vector2(0.8, 0.5), "ball_diamond": Vector2(0.0, 1.0), "flower_beds": Vector2(0.0, -1.0),
		"fountain": Vector2(0.0, 0.0)}.get(type, Vector2.ZERO)
	var best = null
	var best_d := INF
	var u := -hu
	while u <= hu + 0.01:
		var v := -hv
		while v <= hv + 0.01:
			# Local v grows away from the street (-dir).
			var p: Vector3 = s.pos + side * u - s.dir * v
			if _free(id, p, size):
				var d := Vector2(u - like.x * hu, v - like.y * hv).length()
				if d < best_d:
					best_d = d
					best = p
			v += 4.0
		u += 4.0
	return best


func _free(id: int, p: Vector3, size: Vector2) -> bool:
	var s: Dictionary = sites[id]
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	for f in s.features:
		if f.size == Vector2.ZERO:
			continue
		var d: Vector3 = p - f.pos
		if absf(d.dot(side)) < (size.x + f.size.x) * 0.5 + FEATURE_GAP \
				and absf(d.dot(s.dir)) < (size.y + f.size.y) * 0.5 + FEATURE_GAP:
			return false
	return true


## Buys a strip of free land on one side or the back, if the park is under
## its growth cap and the town can pay. Never a separate site.
func _grow(sim: CitySim, id: int) -> bool:
	var s: Dictionary = sites[id]
	var step := Balance.PARK_GROW_STEP
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var options := [
		["left", s.pos - side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		["right", s.pos + side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		["back", s.pos - s.dir * (s.size.y + step) * 0.5, Vector2(s.size.x, step)],
	]
	# Vary which way each park reaches first, so they don't all look alike.
	var first := absi(hash([id, int(s.grew)])) % options.size()
	for i in options.size():
		var o: Array = options[(first + i) % options.size()]
		var strip: Vector2 = o[2]
		var area: float = strip.x * strip.y
		if s.size.x * s.size.y + area > float(s.start_area) * Balance.HUB_MAX_GROWTH + 1.0:
			continue
		var cost := roundi(area / 4046.86 * Balance.PARK_LAND_PER_ACRE)
		if cost > sim.economy.money:
			return false
		if ground_problem(sim, corners(o[1], s.dir, strip), id) != "":
			continue
		sim.economy.money -= cost
		match o[0]:
			"left":
				s.pos -= side * step * 0.5
				s.size.x += step
			"right":
				s.pos += side * step * 0.5
				s.size.x += step
			"back":
				s.pos -= s.dir * step * 0.5
				s.size.y += step
		s.grew += 1
		return true
	return false


## Scores keep six decimals, so a saved city reloads to exactly the same
## numbers and every copy of the simulation stays in step.
static func _quantize(x: float) -> float:
	return float("%.6f" % x)


## True when a footprint (ground points) runs onto any park or landmark.
func overlaps(pts: Array) -> bool:
	var poly := PackedVector2Array(pts)
	for id in sites:
		if not Geometry2D.intersect_polygons(poly, footprint(id)).is_empty():
			return true
	return false


## The road wins (Brawn): a road built through a landmark bulldozes it and
## pays it back. A park gives up the strip the road runs through and keeps
## the bigger side; what stood on the lost ground fills in again later.
## Returns true when anything changed.
func road_wins(sim: CitySim, corr: Array) -> bool:
	var changed := false
	var ids := sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sites[id]
		if not RoadWins.hits(corr, footprint(id)):
			continue
		changed = true
		if s.kind != "park":
			sim.economy.money += cost_of(s.kind)
			sites.erase(id)
			continue
		var side := Vector3(-s.dir.z, 0.0, s.dir.x)
		var best := []
		var best_area := 0.0
		# Cut back from one side, 5 m at a time, keeping what the road misses.
		for cut in [[side, "x"], [-side, "x"], [s.dir, "y"], [-s.dir, "y"]]:
			var full: float = s.size.x if cut[1] == "x" else s.size.y
			var k := 5.0
			while full - k >= 20.0:
				var size: Vector2 = s.size - (Vector2(k, 0) if cut[1] == "x" else Vector2(0, k))
				var pos: Vector3 = s.pos - cut[0] * k * 0.5
				if not RoadWins.hits(corr, corners(pos, s.dir, size)):
					if size.x * size.y > best_area:
						best_area = size.x * size.y
						best = [pos, size]
					break
				k += 5.0
		if best.is_empty():
			sim.economy.money += Balance.PARK_COST
			sites.erase(id)
			continue
		s.pos = best[0]
		s.size = best[1]
		var keep := []
		for f in s.features:
			if f.size == Vector2.ZERO or (_inside(id, f.pos, f.size) and not RoadWins.hits(corr, corners(f.pos, s.dir, f.size))):
				keep.append(f)
		s.features = keep
	return changed


func _inside(id: int, p: Vector3, size: Vector2) -> bool:
	var s: Dictionary = sites[id]
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var d: Vector3 = p - s.pos
	return absf(d.dot(side)) + size.x * 0.5 <= s.size.x * 0.5 + 0.01 \
		and absf(d.dot(s.dir)) + size.y * 0.5 <= s.size.y * 0.5 + 0.01


## Points spread over a footprint, to test the ground under it.
static func _samples(poly: PackedVector2Array) -> Array:
	var out := Array(poly)
	var c := (poly[0] + poly[2]) * 0.5
	out.append(c)
	var a := poly[1] - poly[0]
	var b := poly[3] - poly[0]
	var na := maxi(1, int(a.length() / 12.0))
	var nb := maxi(1, int(b.length() / 12.0))
	for i in na + 1:
		for j in nb + 1:
			out.append(poly[0] + a * (float(i) / na) + b * (float(j) / nb))
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id in sites:
		var s: Dictionary = sites[id]
		var fs := []
		for f in s.features:
			fs.append([f.type, f.pos.x, f.pos.z, f.size.x, f.size.y])
		out[str(id)] = {"kind": s.kind, "name": s.name, "pos": [s.pos.x, s.pos.z], "dir": [s.dir.x, s.dir.z],
			"size": [s.size.x, s.size.y], "start_area": s.start_area, "built": s.built, "features": fs,
			"score": s.score, "tier": s.tier, "next_feature": s.next_feature, "grew": s.grew}
	return {"next_id": _next_id, "sites": out}


func from_dict(d: Dictionary) -> void:
	sites.clear()
	for k in d.get("sites", {}):
		var e: Dictionary = d.sites[k]
		if not KINDS.has(str(e.kind)):
			continue
		var fs := []
		for f in e.get("features", []):
			fs.append({"type": str(f[0]), "pos": Vector3(f[1], 0.0, f[2]), "size": Vector2(f[3], f[4])})
		sites[int(k)] = {"kind": str(e.kind), "name": str(e.name), "pos": Vector3(e.pos[0], 0.0, e.pos[1]),
			"dir": Vector3(e.dir[0], 0.0, e.dir[1]).normalized(), "size": Vector2(e.size[0], e.size[1]),
			"start_area": float(e.start_area), "built": int(e.built), "features": fs, "score": float(e.score),
			"tier": int(e.tier), "next_feature": int(e.next_feature), "grew": int(e.grew)}
	_next_id = int(d.get("next_id", 1))
