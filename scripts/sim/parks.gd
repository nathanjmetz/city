class_name Parks
extends RefCounted
## Parks and landmarks.
##
## A park is a hub (Brawn's rule, 2026-10-22): the player places a lawn
## beside a road, and the park fills in by itself over the next couple of
## game years with paths, a playground, a pavilion, a court and a ball
## diamond. When it runs out of room it buys the free strip of land right
## next to it (never a second site), up to Balance.HUB_MAX_GROWTH times its
## first size. Boxed in by roads, it fills the rest of its block up to the
## sidewalk with lawn, walks and shade trees (Nathan, 2026-10-26: "when a hub
## with leader is "trapped" inside a road area, it should nicely fill in
## that area up to the edge (sidewalk) so that it looks like its using its
## space well."): edge pieces, below. What it gets and how well kept it
## looks follow its neighborhood's tier: curated flowerbeds and a fountain
## where the area is thriving, a worn lawn where it is struggling.
##
## Past the basics, each park has a development tree (Balance.PARK_TREE, in
## the shared Agency format): a park board, with a chair of its own, adds a splash pad, field lights, a
## youth sports complex, a bandstand, a pond or a pool when the park, its
## neighborhood, the town and the region can support them. The player's
## word to the board (the leader guide) speeds it up or holds it off.
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
	"fairgrounds": {"name": "County fairgrounds", "icon": "fairgrounds", "landmark": true},
	# Where the town's trails start; its director grows them (Trails).
	"trailhead": {"name": "Trailhead", "icon": "trailhead", "landmark": true},
	# Opened by themselves for visitors (Tourism), never placed by the player.
	"gas_station": {"name": "Gas station", "icon": "car", "landmark": false, "auto": true},
	"diner": {"name": "Diner", "icon": "shops", "landmark": false, "auto": true},
	"motel": {"name": "Motel", "icon": "homes", "landmark": false, "auto": true},
}
## Every park gets its own name, like real Midwestern town parks.
const PARK_NAMES := ["Lincoln", "Riverside", "Memorial", "Oak Grove", "Maple", "Veterans", "Washington",
	"Sunnyside", "Kiwanis", "Rotary", "Heritage", "Willow Creek", "Pioneer", "Legion", "Garfield",
	"Hilltop", "Cedar", "Prairie", "Jaycee", "Elm Street", "Walnut", "Fairview", "Shady Lane",
	"Greenwood", "Burr Oak", "Cardinal", "Meadowbrook", "Founders", "Harmony", "Lakeview"]
const LANDMARK_NAMES := {"courthouse": "Courthouse Square", "water_tower": "Water tower",
	"grain_elevator": "Farmers Co-op Elevator", "football": "Memorial Field", "fairgrounds": "County Fairgrounds", "trailhead": "Trailhead",
	"gas_station": "Gas station", "diner": "Diner", "motel": "Motel"}
## What the basics are called, for the info panel.
const FEATURE_NAMES := {"paths": "paths", "playground": "playground", "pavilion": "picnic pavilion",
	"court": "basketball court", "ball_diamond": "ball diamond", "flower_beds": "flower beds",
	"fountain": "fountain"}
## Gap kept between the front of a park and the road, like a service.
const SETBACK := 2.0
## Room kept between things inside a park, metres.
const FEATURE_GAP := 3.0
const DAYS_PER_DECIDE := Balance.PARK_DECIDE_EVERY / (24.0 * 60.0)
## The edge pieces round a park, as (across, back): its left and right sides,
## its back, then the two back corners (each filled once a side next to it
## is). Each is a growth strip's worth of land (Balance.PARK_GROW_STEP).
const EDGE_PIECES := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]
## An edge piece is kept only when it's at least this wide on average (m) and
## this big (m2): thinner, it's just the grass verge.
const EDGE_MIN_WIDTH := 1.0
const EDGE_MIN_AREA := 12.0
## How often (park rounds) a park looks at its edge pieces: one round in four,
## so a big town's parks take turns.
const EDGE_EVERY := 4

## id -> {kind, name, pos (centre), dir (unit, toward its road), size
## (width along the road x depth), start_area, founded (tick), features:
## [{type, pos, size}], score (neighborhood, 0 to 1), tier, next_feature
## (tick), grew (strips bought), leader (the park board's chair: Agency.leader
## plus a name), why (what the board did last), edge}. Tree items sit in
## `features` like the basics; `built` (for Agency) is their types.
## `edge` holds a park's edge pieces: piece -> outline cut back to the road,
## in the park's own frame (x along the road, z back from it, from its
## centre; CivicHubs.to_world), as CivicHubs keeps a hub's. They count as its
## land (at, covers, overlaps) but not for upkeep, lift or features.
var sites := {}
## Lift in land value and in happiness each building's lot gets.
var lot_value := {}
var lot_happy := {}
## The town's sliders: Funding sets upkeep and how much a site lifts the
## land around it, Growth how soon a park buys more land (see Policies).
var policies: Policies
var _next_id := 1
var _effects_key := []
var _effects_lots := {}
static var _nodes := {}
## The fairgrounds and football field as event venues, and the visitors
## they bring (see Tourism).
var tourism := Tourism.new()
var trails := Trails.new()


## A Balance list's value for site `id`'s step of a slider.
func policy(id: int, slider: String, list: Array) -> float:
	if policies == null:
		return float(list[Policies.STANDARD])
	return policies.pick(list, slider, "parks", "park:%d" % id)


## First ground for a kind; a park's comes from its size class
## (Balance.PARK_SIZES), landmarks have one real size each.
static func size_of(kind: String, size_class := 0) -> Vector2:
	return park_size(size_class).size if kind == "park" else Balance.AMENITIES[kind].size


## One of Balance.PARK_SIZES, clamped to the list.
static func park_size(size_class: int) -> Dictionary:
	return Balance.PARK_SIZES[clampi(size_class, 0, Balance.PARK_SIZES.size() - 1)]


## How a site's building goes up (Construction.PROFILES), or "" for a park
## or trailhead, which are laid out rather than built.
static func profile_of(kind: String) -> String:
	if kind in ["park", "trailhead"]:
		return ""
	return "shop" if KINDS.get(kind, {}).get("auto", false) else "civic"


static func cost_of(kind: String, size_class := 0) -> int:
	return int(park_size(size_class).cost) if kind == "park" else int(Balance.AMENITIES[kind].cost)


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
static func site_near(network: RoadNetwork, kind: String, hit: Vector3, size_class := 0) -> Array:
	var near := RoadIndex.segment_near(network, hit, 90.0, 1.0)
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
	return [Vector3(p.x, 0.0, p.z) + normal * (front + size_of(kind, size_class).y * 0.5), -normal]


## Why this ground can't be taken, or "" if it can. `skip` is a site to
## leave out (the park that is growing).
## With `homes_ok`, homes and shops on the ground don't count (land the
## player could let a park buy).
func ground_problem(sim: CitySim, poly: PackedVector2Array, skip := -1, homes_ok := false) -> String:
	for q in poly:
		if not sim.land_ok(Vector3(q.x, 0.0, q.y)):
			return "Can't build in the water or on a slope that steep."
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for id in sim.services.buildings:
		if not Geometry2D.intersect_polygons(poly, sim.services.footprint(id)).is_empty():
			return "Overlaps the %s." % Services.KINDS[sim.services.buildings[id].kind].name.to_lower()
	for id in sites:
		if id != skip and _poly_hits(poly, land_polys(id)):
			return "Overlaps %s." % sites[id].name
	for key in sim.buildings:
		if not homes_ok and sim.lots.has(key) and not Geometry2D.intersect_polygons(poly, sim.lots[key].corners).is_empty():
			return "Buildings stand there."
	for p in _samples(poly):
		var q := Vector3(p.x, 0.0, p.y)
		var owner := Capital.owner_of(sim, q)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if owner.begins_with("site:"):
			return "That ground belongs to a company."
		if sim.warehouses.covers(q):
			return "A warehouse stands there."
		if sim.hubs.covers(q):
			return "That ground is a landfill, recycling yard or cemetery."
		if sim.mail.covers(q):
			return "That ground is the post office."
		if sim.education.covers(q):
			return "That ground is a campus."
		if sim.telecom.covers(q):
			return "That ground belongs to the phone company."
		if sim.banks.covers(q):
			return "That ground is a bank."
		if sim.reserves.kind_at(q) != "":
			return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(q)]
	return ""


## Why a park or landmark can't go here, or "" if it can.
func site_problem(sim: CitySim, kind: String, pos: Vector3, dir: Vector3, size_class := 0) -> String:
	if not KINDS.has(kind):
		return "Unknown kind."
	if KINDS[kind].get("auto", false):
		return "That opens by itself when visitors come."
	if KINDS[kind].landmark and has_kind(kind):
		return "The town already has its %s (one per town)." % KINDS[kind].name.to_lower()
	return ground_problem(sim, corners(pos, dir, size_of(kind, size_class)))


func has_kind(kind: String) -> bool:
	for id in sites:
		if sites[id].kind == kind:
			return true
	return false


func add(sim: CitySim, kind: String, pos: Vector3, dir: Vector3, size_class := 0) -> int:
	var id := _next_id
	_next_id += 1
	var size := size_of(kind, size_class)
	var s := {"kind": kind, "name": _new_name(kind, id), "pos": pos, "dir": dir, "size": size,
		"class": clampi(size_class, 0, Balance.PARK_SIZES.size() - 1) if kind == "park" else 0,
		"start_area": size.x * size.y, "founded": sim.tick_count, "features": [], "score": 0.5, "tier": -1,
		"next_feature": sim.tick_count + Balance.PARK_DECIDE_EVERY, "grew": 0,
		"leader": _hire(sim, hash([sim.city_seed, id, kind])), "why": "", "edge": {}}
	sites[id] = s
	_sign_up(sim)
	var t := Neighborhood.target(sim, pos, lift_at(pos, "value", id))
	s.score = _quantize(t.score)
	s.tier = Neighborhood.tier_for(s.score, -1)
	if Parks.profile_of(kind) != "":
		# Its building goes up like any other (Construction).
		sim.construction.start("park:%d" % id, Parks.profile_of(kind), sim.tick_count, pos, dir,
			SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH)
	if Tourism.is_venue(kind):
		tourism.sync(sim)
	if kind == "trailhead":
		trails.sync(sim)
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


## All the ground a site holds, as outlines (x, z): its footprint, then
## each edge piece.
func land_polys(id: int) -> Array:
	var out := [footprint(id)]
	for c in sites[id].get("edge", {}):
		out.append(edge_poly(id, c))
	return out


## Edge piece `c`'s outline on the ground (x, z).
func edge_poly(id: int, c: Vector2i) -> PackedVector2Array:
	var s: Dictionary = sites[id]
	var out := PackedVector2Array()
	for q in s.get("edge", {}).get(c, PackedVector2Array()):
		out.append(CivicHubs.to_world(s, q))
	return out


static func _in_box(q: Vector2, poly: PackedVector2Array) -> bool:
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	return q.x >= lo.x and q.y >= lo.y and q.x <= hi.x and q.y <= hi.y


## What a site's land is laid out from (to tell when it changed).
func land_sig(id: int) -> int:
	var s: Dictionary = sites[id]
	return hash([s.pos, s.dir, s.size, s.get("edge", {})])


## The park or landmark whose ground holds this point, or -1.
func at(p: Vector3) -> int:
	for id in sites:
		# Quick out: past its corners and a growth strip (its edge pieces' reach).
		var s: Dictionary = sites[id]
		var dx: float = p.x - s.pos.x
		var dz: float = p.z - s.pos.z
		var r: float = (s.size.length() * 0.5 + Balance.PARK_GROW_STEP * 1.5)
		if dx * dx + dz * dz > r * r:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), footprint(id)):
			return id
		var edge: Dictionary = sites[id].get("edge", {})
		if not edge.is_empty():
			var l := CivicHubs.to_local(sites[id], Vector2(p.x, p.z))
			for c in edge:
				# Its box first: Godot's point-in-polygon can say yes for a
				# point well outside an outline with corners in a line.
				if _in_box(l, edge[c]) and Geometry2D.is_point_in_polygon(l, edge[c]):
					return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1 or trails.on_path(p)


func acres(id: int) -> float:
	var s: Dictionary = sites[id]
	return s.size.x * s.size.y / 4046.86


## Acres of all a site's land, its edge pieces too (the info panel; upkeep
## goes by acres).
func land_acres(id: int) -> float:
	var a := acres(id) * 4046.86
	for c in sites[id].get("edge", {}):
		a += CivicHubs.area(sites[id].edge[c])
	return a / 4046.86


func monthly_upkeep() -> int:
	var total := 0.0
	for id in sites:
		total += site_upkeep(id)
	return roundi(total)


## A park costs more to keep the better kept it is.
func site_upkeep(id: int) -> float:
	var s: Dictionary = sites[id]
	var funding := policy(id, "funding", Balance.POLICY_UPKEEP)
	if s.kind == "trailhead":
		return (float(Balance.AMENITIES[s.kind].upkeep) + trails.upkeep()) * funding
	if s.kind != "park":
		return float(Balance.AMENITIES[s.kind].upkeep) * funding
	var tree := tree_effect(id, "upkeep+")
	return (acres(id) * Balance.PARK_UPKEEP_PER_ACRE + tree) * float(Neighborhood.TIERS[maxi(s.tier, 0)].upkeep) * funding


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
	var funding := policy(id, "funding", Balance.POLICY_EFFECT)
	if s.kind != "park":
		return funding
	var want := wanted_features(id).size()
	var have := 0
	for f in wanted_features(id):
		if has_feature(id, f.type):
			have += 1
	return (0.4 + 0.6 * float(have) / maxf(want, 1.0)) * float(Neighborhood.TIERS[maxi(s.tier, 0)].finish) * funding


## What a park's tree items add to its pull ("value" or "happy"), kept as
## well as its neighborhood keeps things.
func tree_lift(id: int, effect: String) -> float:
	return tree_effect(id, effect + "+") * float(Neighborhood.TIERS[maxi(sites[id].tier, 0)].finish)


## The sum of one tree effect over what a park has (Agency.effect).
func tree_effect(id: int, key: String) -> float:
	var s: Dictionary = sites[id]
	s.built = s.features.map(func(f): return f.type)
	return Agency.effect(s, Balance.PARK_TREE, key)


## One node of the park tree by id ({} if none).
static func node(key: String) -> Dictionary:
	if _nodes.is_empty():
		for n in Balance.PARK_TREE:
			_nodes[n.id] = n
	return _nodes.get(key, {})


## Distance from a point to a site's ground (0 inside).
func distance_to(id: int, p: Vector3) -> float:
	var s: Dictionary = sites[id]
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var d: Vector3 = p - s.pos
	var u := maxf(absf(d.dot(side)) - s.size.x * 0.5, 0.0)
	var v := maxf(absf(d.dot(s.dir)) - s.size.y * 0.5, 0.0)
	return Vector2(u, v).length()


## How far past a pocket park's reach this site's pull goes (a community
## park draws from further off than a tot lot).
func reach_of(id: int) -> float:
	var s: Dictionary = sites[id]
	return float(park_size(int(s.get("class", 0))).reach) if s.kind == "park" else 1.0


## The lift every park and landmark gives at a point: "value" or "happy".
func lift_at(p: Vector3, effect: String, skip := -1) -> float:
	var total := 0.0
	for id in sites:
		if id == skip:
			continue
		var a: Dictionary = Balance.AMENITIES[sites[id].kind]
		var reach: float = a[effect + "_reach"] * reach_of(id)
		var d := distance_to(id, p)
		if d < reach:
			total += (float(a[effect]) * quality(id) + tree_lift(id, effect)) * (1.0 - d / reach)
	return minf(total, Balance.AMENITY_VALUE_CAP if effect == "value" else Balance.AMENITY_HAPPY_CAP)


## Works out the lift each building's lot gets (after stats update).
var _lift_of := []  # [the parks' places, coefs] the rows were worked out for
var _lift_rows := {}  # lot key -> [lot, its pos, value, happy]


func update_effects(sim: CitySim) -> void:
	# Each site's full-strength lift, worked out once (quality and its tree
	# are the same for every lot). The lots' lifts only change when these,
	# the parks, the trails, the lots or the buildings do.
	var coefs := {}
	for id in sites:
		var a: Dictionary = Balance.AMENITIES[sites[id].kind]
		var q := quality(id)
		var r := reach_of(id)
		coefs[id] = [float(a.value) * q + tree_lift(id, "value"), float(a.value_reach) * r,
			float(a.happy) * q + tree_lift(id, "happy"), float(a.happy_reach) * r]
	var sig := [sites.hash(), coefs, sim.buildings.size(), sim.lots.size(), trails.paths.size(), trails.lanes.size()]
	if sig == _effects_key and is_same(sim.lots, _effects_lots):
		return
	_effects_key = sig
	_effects_lots = sim.lots
	# A lot's lift only depends on where it is, the parks (their lifts) and
	# the trails: with no trails or plazas (trails.lift reads nothing then),
	# a lot that hasn't moved since keeps the lift it was given.
	# (A lot's lift reads each park's lift numbers, coefs, and where it is.)
	var shape := []
	for id in sites:
		shape.append([id, sites[id].pos, sites[id].dir, sites[id].size])
	var keep := trails.paths.is_empty() and trails.plazas.is_empty() and _lift_of == [shape, coefs]
	var was := _lift_rows if keep else {}
	_lift_of = [shape, coefs]
	_lift_rows = {}
	lot_value.clear()
	lot_happy.clear()
	if sites.is_empty() and trails.paths.is_empty():
		return
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var lot: Dictionary = sim.lots[key]
		var row: Array = was.get(key, [])
		if not row.is_empty() and is_same(row[0], lot) and row[1] == lot.pos:
			lot_value[key] = row[2]
			lot_happy[key] = row[3]
			_lift_rows[key] = row
			continue
		var p: Vector3 = sim.lots[key].pos
		var value := 0.0
		var happy := 0.0
		for id in coefs:
			var c: Array = coefs[id]
			var d := distance_to(id, p)
			if d < c[1]:
				value += c[0] * (1.0 - d / c[1])
			if d < c[3]:
				happy += c[2] * (1.0 - d / c[3])
		# As lift_at, plus homes along a trail are worth a little more, too.
		lot_value[key] = minf(minf(value, Balance.AMENITY_VALUE_CAP) + trails.lift(sim, key, "value"), Balance.AMENITY_VALUE_CAP)
		lot_happy[key] = minf(minf(happy, Balance.AMENITY_HAPPY_CAP) + trails.lift(sim, key, "happy"), Balance.AMENITY_HAPPY_CAP)
		_lift_rows[key] = [lot, lot.pos, lot_value[key], lot_happy[key]]


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
	_sign_up(sim)
	tourism.sync(sim)
	var changed := trails.decide(sim)
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
		# Boxed in by roads: lawn up to the sidewalk (unless told to hold),
		# looked at every EDGE_EVERY rounds, a few parks a round (by id).
		if s.kind == "park" and (sim.tick_count / Balance.PARK_DECIDE_EVERY + id) % EDGE_EVERY == 0 \
				and sim.permits.guidance("park", id).stance != "hold" and _take_edges(sim, id):
			changed = true
	return changed


## Park boards take the player's word too (grow, your call, hold off).
static func _sign_up(sim: CitySim) -> void:
	if not sim.permits.locators.has("park"):
		sim.permits.locators["park"] = func(s2: CitySim, id: int) -> Vector2:
			var p: Vector3 = s2.parks.sites.get(id, {"pos": Vector3.ZERO}).pos
			return Vector2(p.x, p.z)


## Adds the next thing the park wants that fits, or buys land for it.
func _fill_in(sim: CitySim, id: int, residents: int) -> bool:
	var s: Dictionary = sites[id]
	if not s.get("ask", {}).is_empty():
		return _answer(sim, id)
	for f in wanted_features(id):
		if has_feature(id, f.type):
			continue
		var spot = _find_spot(id, f.type, f.size)
		if spot != null:
			s.features.append({"type": f.type, "pos": spot, "size": f.size})
			return true
		# No room: buy the strip next door if people here use the park.
		var need := Balance.PARK_GROW_MIN_RESIDENTS * policy(id, "growth", Balance.POLICY_PARK_RESIDENTS)
		if s.tier > 0 and residents >= need and _grow(sim, id, f.size):
			return true
	# Then the next thing from its tree that it can support and afford.
	if sim.permits.guidance("park", id).stance == "hold":
		return false
	for t in Balance.PARK_TREE:
		var key: String = t.id
		if tree_problem(sim, id, key) != "":
			continue
		var spot = _find_spot(id, key, t.size)
		if spot != null:
			sim.economy.money -= int(t.cost)
			s.features.append({"type": key, "pos": spot, "size": t.size})
			s.why = "The park board added %s%s." % [str(t.name).to_lower(), (": " + str(t.note)) if t.has("note") else ""]
			return true
		# Big things bring their own land: the park buys what they need.
		var need := Balance.PARK_GROW_MIN_RESIDENTS * policy(id, "growth", Balance.POLICY_PARK_RESIDENTS)
		if residents >= need and _grow(sim, id, t.size, t.size.x * t.size.y):
			return true
	return false


## Why the park board can't add `key` from its tree yet, in a few plain
## words, or "" if it can (it then still needs room, which it buys).
func tree_problem(sim: CitySim, id: int, key: String) -> String:
	var s: Dictionary = sites[id]
	var t := node(key)
	if s.kind != "park" or t.is_empty():
		return "not for this site"
	if has_feature(id, key):
		return "built"
	var n: Dictionary = t.get("needs", {})
	for r in t.get("requires", []):
		if not has_feature(id, r):
			return "needs the %s first" % str(node(r).get("name", FEATURE_NAMES.get(r, r))).to_lower()
	if n.has("tier") and maxi(s.tier, 0) < int(n.tier):
		return "needs %s neighborhood" % Words.a(str(Neighborhood.TIERS[int(n.tier)].name).to_lower())
	if n.has("population") and not Agency.holds(sim, s, s.pos, 0.0, "population", n.population):
		return "needs %s people in town" % CitySim.money_text(int(n.population))
	if n.has("water") and not _has_service(sim, [Services.Kind.WATER_TOWER, Services.Kind.WELL]):
		return "needs town water"
	if n.has("power") and not _has_service(sim, [Services.Kind.SUBSTATION, Services.Kind.POWER_FEED]):
		return "needs town power"
	if n.has("school") and not _school_near(sim, s.pos, float(n.school)):
		return "needs a school within %.0f mi" % (float(n.school) / 1609.0)
	if n.has("forest") and _forest_near(id) < float(n.forest) and not _water_near(id):
		return "needs woods or a creek next to the park"
	if n.has("link") and not Agency.holds(sim, s, s.pos, 0.0, "link", n.link):
		return "needs a county road out to neighbor towns"
	var g: Dictionary = sim.permits.guidance("park", id)
	if g.stance == "hold":
		return "told to hold off"
	var keep := Balance.PARK_TREE_RESERVE * (0.5 + float(s.leader.caution)) * (0.5 if g.stance == "grow" else 1.0)
	if sim.economy.money < int(t.cost) + roundi(keep):
		return "saving up ($%s)" % CitySim.money_text(int(t.cost))
	return ""


## Each tree branch as [branch, what it has, the next step and what it
## waits on], for the info panel.
func tree_status(sim: CitySim, id: int) -> Array:
	var out := []
	var by_branch := {}
	for t in Balance.PARK_TREE:
		var b: String = t.branch
		if not by_branch.has(b):
			by_branch[b] = [[], ""]
			out.append(b)
		if has_feature(id, t.id):
			by_branch[b][0].append(str(t.name).to_lower())
		elif by_branch[b][1] == "":
			var why := tree_problem(sim, id, t.id)
			by_branch[b][1] = "%s %s" % [t.name, "(planned)" if why == "" else "(%s)" % why]
	var rows := []
	for b in out:
		var have: Array = by_branch[b][0]
		var text := ", ".join(have).capitalize() if not have.is_empty() else ""
		if by_branch[b][1] != "":
			text += ("; next: " if text != "" else "Next: ") + by_branch[b][1]
		rows.append([b, text])
	return rows


static func _has_service(sim: CitySim, kinds: Array) -> bool:
	for sid in sim.services.buildings:
		if sim.services.buildings[sid].kind in kinds:
			return true
	return false


static func _school_near(sim: CitySim, p: Vector3, reach: float) -> bool:
	for sid in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[sid]
		if b.kind == Services.Kind.SCHOOL and b.pos.distance_to(p) <= reach:
			return true
	for cid in sim.education.campuses:
		var c: Dictionary = sim.education.campuses[cid]
		if c.kind == "high_school" and c.pos.distance_to(p) <= reach:
			return true
	return false


## True when a river or creek runs within 40 m of the park.
func _water_near(id: int) -> bool:
	var s: Dictionary = sites[id]
	for p in corners(s.pos, s.dir, s.size + Vector2(80, 80)) + corners(s.pos, s.dir, s.size + Vector2(80, 0)) \
			+ corners(s.pos, s.dir, s.size + Vector2(0, 80)):
		if Terrain.is_water(p.x, p.y):
			return true
	return false


## The most woods (0 to 1) on the land just around the park.
func _forest_near(id: int) -> float:
	var s: Dictionary = sites[id]
	var best := 0.0
	for p in corners(s.pos, s.dir, s.size + Vector2(80, 80)):
		best = maxf(best, Resources.at(Resources.Kind.FOREST, Vector3(p.x, 0.0, p.y)))
	return best


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
		"fountain": Vector2(0.0, 0.0), "splash_pad": Vector2(-0.8, -0.3), "all_abilities": Vector2(-0.7, 0.2),
		"youth_complex": Vector2(0.0, 1.0), "tournament": Vector2(1.0, -1.0), "bandstand": Vector2(0.3, 0.2),
		"pond": Vector2(-1.0, 1.0), "pool": Vector2(1.0, -0.6), "aquatic_center": Vector2(1.0, 0.4),
		# Courts in a block toward the back, the dog park and the garden off
		# in a far corner, the memorial and the skaters near the street (seen,
		# so watched), the amphitheatre's lawn at the back.
		"pickleball": Vector2(0.8, 0.2), "tennis": Vector2(0.9, 0.8), "volleyball": Vector2(-0.3, 0.6),
		"dog_park": Vector2(-0.9, 0.8), "skate_park": Vector2(0.6, -0.6), "shelter_house": Vector2(0.2, -0.3),
		"amphitheater": Vector2(0.0, 0.9), "veterans_memorial": Vector2(0.0, -0.9),
		"community_garden": Vector2(-0.8, 1.0)}.get(type, Vector2.ZERO)
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
## `need` is the size of what it wants room for, so it grows the way that
## fits it; `extra` is land a tree item brings on top of the growth cap.
func _grow(sim: CitySim, id: int, need := Vector2.ZERO, extra := 0.0) -> bool:
	var s: Dictionary = sites[id]
	var step := Balance.PARK_GROW_STEP
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var cap := minf(float(s.start_area) * Balance.HUB_MAX_GROWTH,
		float(park_size(int(s.get("class", 0))).max_acres) * 4046.86) + extra
	for f in s.features:
		var t := node(f.type)
		if not t.is_empty():
			cap += t.size.x * t.size.y
	var options := [
		["left", s.pos - side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		["right", s.pos + side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		["back", s.pos - s.dir * (s.size.y + step) * 0.5, Vector2(s.size.x, step)],
	]
	# Vary which way each park reaches first, so they don't all look alike,
	# but widen for something wide and deepen for something deep.
	var first := absi(hash([id, int(s.grew)])) % options.size()
	var order := []
	for i in options.size():
		order.append(options[(first + i) % options.size()])
	var wide: bool = need.x + FEATURE_GAP * 2.0 > s.size.x
	var deep: bool = need.y + FEATURE_GAP * 2.0 > s.size.y
	if deep and not wide:
		order.sort_custom(func(a, b): return a[0] == "back" and b[0] != "back")
	elif wide and not deep:
		order.sort_custom(func(a, b): return a[0] != "back" and b[0] == "back")
	var homes := []
	var street := []
	for o in order:
		var strip: Vector2 = o[2]
		var area: float = strip.x * strip.y
		if s.size.x * s.size.y + area > cap + 1.0:
			continue
		var cost := roundi(area / 4046.86 * Balance.PARK_LAND_PER_ACRE)
		if cost > sim.economy.money:
			return false
		var why := ground_problem(sim, corners(o[1], s.dir, strip), id)
		if why == "Buildings stand there." and homes.is_empty() and _homes_only(sim, corners(o[1], s.dir, strip), id):
			homes = [o[0], o[1], strip, cost]
		if why == "Too close to a road." and street.is_empty():
			var seg := closable_street(sim, id, corners(o[1], s.dir, strip))
			if seg != -1:
				street = [o[0], o[1], strip, cost, seg]
		if why != "":
			continue
		_take(sim, id, o[0], cost)
		return true
	# Only homes or shops stand on the land it needs: the park board asks
	# the player (the permits bell) to let it buy them, as real park boards
	# buy the houses next door and tear them down to grow a park.
	if not homes.is_empty():
		_ask(sim, id, homes)
	elif not street.is_empty():
		_ask_street(sim, id, street)
	return false


## The one quiet street in the way of a park's next strip that the town
## could close and give to the park, or -1: the way Indiana towns vacate a
## street to a park that owns both sides (IC 36-7-3-12, an ordinance after
## a hearing; the land goes to the owners on either side). Only a plain
## local street or alley (Balance.PARK_CLOSABLE_STREETS) no longer than a
## block, with no home, shop or service on it, that the town can still get
## round once it is gone: a dead end, or both ends still joined by other
## streets.
func closable_street(sim: CitySim, id: int, poly: PackedVector2Array) -> int:
	var net := sim.network
	var hits := []
	for seg in net.segments:
		if Services._clashes(poly, net.sample_segment(seg, RoadIndex.SAMPLES), RoadStyle.right_of_way_half(net.segments[seg].type)):
			hits.append(seg)
			if hits.size() > 1:
				return -1
	if hits.size() != 1:
		return -1
	var seg: int = hits[0]
	var road: Dictionary = net.segments[seg]
	if int(road.type) not in Balance.PARK_CLOSABLE_STREETS or sim.is_link_segment(seg):
		return -1
	var pts := net.sample_segment(seg, RoadIndex.SAMPLES)
	var length := 0.0
	for i in pts.size() - 1:
		length += pts[i].distance_to(pts[i + 1])
	if length > Balance.PARK_CLOSE_MAX_M:
		return -1
	# Nothing else lives on it: no building on a lot facing it, no service
	# or other park beside it.
	for key in sim.buildings:
		if sim.lots.has(key) and int(sim.lots[key].get("seg", -1)) == seg:
			return -1
	var band := PackedVector2Array()
	for p in pts:
		band.append(Vector2(p.x, p.z))
	var reach := RoadStyle.right_of_way_half(road.type) + 6.0
	for b in sim.services.buildings:
		for q in sim.services.footprint(b):
			if _near_line(q, band, reach):
				return -1
	for other in sites:
		if other != id:
			for q in footprint(other):
				if _near_line(q, band, reach):
					return -1
	# The town can still get round: a dead end, or another way between its ends.
	if net.segments_at(road.a).size() == 1 or net.segments_at(road.b).size() == 1:
		return seg
	return seg if _joined_without(net, road.a, road.b, seg) else -1


static func _near_line(q: Vector2, line: PackedVector2Array, d: float) -> bool:
	for i in line.size() - 1:
		if Geometry2D.get_closest_point_to_segment(q, line[i], line[i + 1]).distance_to(q) < d:
			return true
	return false


## True when nodes a and b are joined by streets other than `skip`.
static func _joined_without(net: RoadNetwork, a: int, b: int, skip: int) -> bool:
	var seen := {a: true}
	var todo := [a]
	while not todo.is_empty():
		var n: int = todo.pop_back()
		for seg in net.segments_at(n):
			if seg == skip:
				continue
			var r: Dictionary = net.segments[seg]
			var m: int = r.b if r.a == n else r.a
			if m == b:
				return true
			if not seen.has(m):
				seen[m] = true
				todo.append(m)
	return false


## Files the park board's request to have the town close the street beside
## it and give the park the land.
func _ask_street(sim: CitySim, id: int, street: Array) -> void:
	var s: Dictionary = sites[id]
	if not sim.permits.can_file(sim, "park", id):
		return
	var area := []
	for q in corners(street[1], s.dir, street[2]):
		area.append([q.x, q.y])
	var req: int = sim.permits.file(sim, {"hub": "park", "hub_id": id, "leader": str(s.leader.get("name", "The park board")),
		"title": "Close the street beside %s" % s.name,
		"why": "The park fills both sides of a quiet street; the board asks the town to close it and join the park across it.",
		"area": area, "change": "Street to park", "base": int(street[3]), "budget": maxi(0, int(sim.economy.money))})
	if req != -1:
		s.ask = {"req": req, "side": street[0], "seg": int(street[4])}
		s.why = "The park board asked the town to close the street beside it."


## Grows the park one strip to `which` side, paying `cost`.
func _take(sim: CitySim, id: int, which: String, cost: int) -> void:
	var s: Dictionary = sites[id]
	var step := Balance.PARK_GROW_STEP
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	sim.economy.money -= cost
	match which:
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
	# Edge pieces were cut to the old outline: they go, and come back
	# fitted to the new one wherever a road still boxes it in.
	if not s.get("edge", {}).is_empty():
		s.edge = {}
		_take_edges(sim, id)


## True when what stands on `poly` is only homes or shops (and the strip is
## otherwise fine): ground the player can let the park buy.
func _homes_only(sim: CitySim, poly: PackedVector2Array, id: int) -> bool:
	return ground_problem(sim, poly, id, true) == ""


## Files the park board's request to buy the homes on a strip.
func _ask(sim: CitySim, id: int, homes: Array) -> void:
	var s: Dictionary = sites[id]
	if not sim.permits.can_file(sim, "park", id):
		return
	var area := []
	for q in corners(homes[1], s.dir, homes[2]):
		area.append([q.x, q.y])
	var n := 0
	for h in sim.permits.check(sim, area, 0.0, true).get("buildings", []):
		if h.what == "lot":
			n += 1
	var req: int = sim.permits.file(sim, {"hub": "park", "hub_id": id, "leader": str(s.leader.get("name", "The park board")),
		"title": "Buy %d lot%s next to %s" % [n, "" if n == 1 else "s", s.name],
		"why": "People here fill the park; the board wants the lots next door to make it bigger.",
		"area": area, "change": "Homes to park", "per_m2": roundi(Balance.PARK_HOME_PER_M2),
		"base": int(homes[3]), "budget": maxi(0, int(sim.economy.money))})
	if req != -1:
		s.ask = {"req": req, "side": homes[0]}
		s.why = "The park board asked to buy the homes next door."


## The player's answer: on a yes the homes on the land they agreed to are
## bought and cleared and the park grows over them.
func _answer(sim: CitySim, id: int) -> bool:
	var s: Dictionary = sites[id]
	var state: int = sim.permits.state_of(int(s.ask.req))
	if state == Permits.State.OPEN:
		return false
	var which := str(s.ask.side)
	var req_id := int(s.ask.req)
	var seg := int(s.ask.get("seg", -1))
	s.ask = {}
	if state != Permits.State.APPROVED:
		if state == Permits.State.DENIED:
			s.why = "Was told no on the %s." % ("street beside it" if seg != -1 else "homes next door")
		return false
	var outline := PackedVector2Array()
	for p in sim.permits.requests[req_id].route:
		outline.append(Vector2(float(p[0]), float(p[1])))
	if seg != -1:
		return _close_street(sim, id, req_id, which, seg)
	var price := 0.0
	for key in sim.buildings.keys():
		if sim.parcel_under(key, outline):
			sim.buildings.erase(key)
			price += Balance.PARK_HOME_PER_M2 * _poly_area(sim.lots[key].corners)
	sim.permits.done(req_id)
	var step := Balance.PARK_GROW_STEP
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var to: Array = {"left": [s.pos - side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		"right": [s.pos + side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		"back": [s.pos - s.dir * (s.size.y + step) * 0.5, Vector2(s.size.x, step)]}[which]
	sim.mark_lots_dirty()
	if ground_problem(sim, corners(to[0], s.dir, to[1]), id) != "":
		s.why = "The land agreed to wasn't enough to grow the park."
		return true
	_take(sim, id, which, roundi(price))
	s.why = "The park board bought the homes next door and grew the park."
	return true


## A yes on closing the street: the town takes it up (if nothing has moved
## onto it since), and the park grows across where it ran.
func _close_street(sim: CitySim, id: int, req_id: int, which: String, seg: int) -> bool:
	var s: Dictionary = sites[id]
	sim.permits.done(req_id)
	var step := Balance.PARK_GROW_STEP
	var side := Vector3(-s.dir.z, 0.0, s.dir.x)
	var to: Array = {"left": [s.pos - side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		"right": [s.pos + side * (s.size.x + step) * 0.5, Vector2(step, s.size.y)],
		"back": [s.pos - s.dir * (s.size.y + step) * 0.5, Vector2(s.size.x, step)]}[which]
	var poly := corners(to[0], s.dir, to[1])
	if closable_street(sim, id, poly) != seg:
		s.why = "The street beside it changed; the park board let the closing drop."
		return true
	# Part of the simulation, so every copy of the town takes it up on the
	# same tick (not a player command); lots and traffic catch up as after
	# any road change.
	var keep := sim.network.snapshot()
	var closures := sim.street_closures()
	sim.network.remove_segment(seg)
	if ground_problem(sim, poly, id) != "":
		# Something else still stands in the way: the street goes back, a
		# plaza or car-free street with it (second reviewer 2026-10-29).
		sim.network.restore(keep)
		sim.put_back_closures(closures)
		s.why = "Closing the street wasn't enough to grow the park."
		return true
	_take(sim, id, which, roundi(to[1].x * to[1].y / 4046.86 * Balance.PARK_LAND_PER_ACRE))
	s.why = "The town closed the street and the park grew across it."
	return true


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5


## Scores keep six decimals, so a saved city reloads to exactly the same
## numbers and every copy of the simulation stays in step.
static func _quantize(x: float) -> float:
	return float("%.6f" % x)


## True when a footprint (ground points) runs onto any park or landmark.
func overlaps(pts: Array) -> bool:
	var poly := PackedVector2Array(pts)
	for id in sites:
		if _poly_hits(poly, land_polys(id)):
			return true
	return false


static func _poly_hits(poly: PackedVector2Array, polys: Array) -> bool:
	for q in polys:
		if not Geometry2D.intersect_polygons(poly, q).is_empty():
			return true
	return false


# --- Edge pieces ------------------------------------------------------------------
# A park boxed in by roads fills the rest of its block up to the sidewalk:
# where a growth strip beside it or behind it runs into a road, it takes
# the strip cut back to the road's right of way plus the SETBACK its front
# keeps (CivicHubs' cut, the same as a hub's): lawn with walks and trees,
# never a playground or a field. Only free ground: never a zoned or built
# lot, another owner's land, water or a reserve. It's the town's verge up to
# the road already, so it costs nothing and adds no upkeep. Roads still
# win: a road built later cuts the pieces back, or takes them (road_wins).

## Takes every edge piece that fits round park `id`, and fits one a road
## had cut back out to the roads again once that road is gone. True when
## any changed.
func _take_edges(sim: CitySim, id: int) -> bool:
	var s: Dictionary = sites[id]
	if s.kind != "park":
		return false
	if not s.has("edge"):
		s.edge = {}
	var took := false
	for c in EDGE_PIECES:
		if s.edge.has(c):
			# Cut back by a road since gone: it fits out to the roads again.
			# The cut alone first (cheap), the ground check only if it'd grow.
			var keep: Dictionary = s.edge
			s.edge = keep.duplicate()
			s.edge.erase(c)
			var fresh := _edge_shape(sim, id, c, PackedVector2Array(), false)
			if not fresh.is_empty() and CivicHubs.area(fresh) > CivicHubs.area(keep[c]) + 1.0:
				fresh = _edge_shape(sim, id, c)
			else:
				fresh = PackedVector2Array()
			s.edge = keep
			if not fresh.is_empty() and CivicHubs.area(fresh) > CivicHubs.area(keep[c]) + 1.0:
				keep[c] = fresh
				took = true
			continue
		var shape := _edge_shape(sim, id, c)
		if not shape.is_empty():
			s.edge[c] = shape
			took = true
	return took


## Edge piece `c` of park `id` as a whole strip, in its frame (x across, z
## back, from its centre).
func _edge_rect(id: int, c: Vector2i) -> PackedVector2Array:
	var s: Dictionary = sites[id]
	var step := Balance.PARK_GROW_STEP
	var hx: float = s.size.x * 0.5
	var hz: float = s.size.y * 0.5
	var x0: float = [-hx - step, -hx, hx][c.x + 1]
	var x1: float = [-hx, hx, hx + step][c.x + 1]
	var z0: float = -hz if c.y == 0 else hz
	var z1: float = hz if c.y == 0 else hz + step
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## Piece `c` of park `id` cut back to the roads, in its frame, if what's left
## is big enough, runs along its land (the park, or for a corner a piece
## next to it) and is free; else empty. `from` is an edge piece's outline
## (x, z) to cut back again: land it already holds, so only its size and
## touch are checked. `check` false skips the ground check (a quick look).
func _edge_shape(sim: CitySim, id: int, c: Vector2i, from := PackedVector2Array(), check := true) -> PackedVector2Array:
	var s: Dictionary = sites[id]
	var rect := _edge_rect(id, c)
	var whole := PackedVector2Array()
	for q in rect:
		whole.append(CivicHubs.to_world(s, q))
	# Cut a few centimetres wider than the roads need, so the outline kept in
	# EDGE_SNAP steps never pokes back over them.
	var parts := CivicHubs._cut_by_roads(sim.network, whole if from.is_empty() else from, CivicHubs.EDGE_SNAP * 3.0)
	if from.is_empty():
		parts = _cut_by_zones(sim, _cut_by_lots(sim, parts))
	var best := PackedVector2Array()
	var best_a := 0.0
	for part in parts:
		var a := CivicHubs.area(part)
		if a > best_a + 0.01 and _edge_touches(id, c, part):
			best = part
			best_a = a
	var full := CivicHubs.area(rect)
	var long: float = s.size.y if c.y == 0 else (s.size.x if c.x == 0 else Balance.PARK_GROW_STEP)
	# Not cut at all: no road boxes it in there (growing takes whole strips).
	if best.is_empty() or best_a < maxf(EDGE_MIN_AREA, long * EDGE_MIN_WIDTH) \
			or (from.is_empty() and best_a > full - 1.0):
		return PackedVector2Array()
	var local := PackedVector2Array()
	for q in best:
		var l := CivicHubs.to_local(s, q)
		l = Vector2(snappedf(l.x, CivicHubs.EDGE_SNAP), snappedf(l.y, CivicHubs.EDGE_SNAP))
		if local.is_empty() or l.distance_to(local[-1]) > 0.05:
			local.append(l)
	if local.size() > 1 and local[0].distance_to(local[-1]) <= 0.05:
		local.remove_at(local.size() - 1)
	# Corners in a straight line (where a cut ran along the strip) go.
	local = CivicHubs.drop_collinear(local)
	if local.size() < 3:
		return PackedVector2Array()
	if from.is_empty() and check:
		var world := PackedVector2Array()
		for l in local:
			world.append(CivicHubs.to_world(s, l))
		if _edge_problem(sim, id, world) != "":
			return PackedVector2Array()
	return local


## `parts` (outlines, x, z) less every zoned or built lot running onto them
## (and half a metre round it), less any part a lot sits wholly inside (it
## would leave a hole).
static func _cut_by_lots(sim: CitySim, parts: Array) -> Array:
	if parts.is_empty():
		return parts
	var box := Rect2(parts[0][0], Vector2.ZERO)
	for part in parts:
		for q in part:
			box = box.expand(q)
	var keys := sim.lots_near(box.grow(1.0))
	keys.sort()
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		if not sim.buildings.has(key) and sim.zones.zone_at(lot.zone_pt) == ZoneMap.Zone.NONE:
			continue
		for grown in Geometry2D.offset_polygon(lot.corners, 0.5):
			var next := []
			for part in parts:
				var inside := true
				for q in grown:
					if not Geometry2D.is_point_in_polygon(q, part):
						inside = false
						break
				if inside:
					continue  # that part goes (it would have a hole); the rest stay
				next.append_array(Geometry2D.clip_polygons(part, grown))
			parts = next
	return parts


## `parts` (outlines, x, z) less every zoned cell on them, painted but not
## yet a lot (ZoneMap.CELL squares, a row's run of them at a time), less
## any part one sits wholly inside (it would leave a hole).
static func _cut_by_zones(sim: CitySim, parts: Array) -> Array:
	if parts.is_empty() or sim.zones.cells.is_empty():
		return parts
	var box := Rect2(parts[0][0], Vector2.ZERO)
	for part in parts:
		for q in part:
			box = box.expand(q)
	var k := ZoneMap.CELL
	var lo := Vector2i(floori(box.position.x / k), floori(box.position.y / k))
	var hi := Vector2i(floori(box.end.x / k), floori(box.end.y / k))
	for y in range(lo.y, hi.y + 1):
		var x := lo.x
		while x <= hi.x:
			if not sim.zones.cells.has(Vector2i(x, y)):
				x += 1
				continue
			var x0 := x
			while x <= hi.x and sim.zones.cells.has(Vector2i(x, y)):
				x += 1
			var run := PackedVector2Array([Vector2(x0 * k, y * k), Vector2(x * k, y * k),
				Vector2(x * k, (y + 1) * k), Vector2(x0 * k, (y + 1) * k)])
			var next := []
			for part in parts:
				var inside := true
				for q in run:
					if not Geometry2D.is_point_in_polygon(q, part):
						inside = false
						break
				if inside:
					continue  # that part goes (it would have a hole); the rest stay
				next.append_array(Geometry2D.clip_polygons(part, run))
			parts = next
	return parts


## True when `part` (x, z) runs along the land next to piece `c` for a good
## stretch (4 m): the park itself for a side or the back, the side or back
## piece next to it for a corner.
func _edge_touches(id: int, c: Vector2i, part: PackedVector2Array) -> bool:
	var next := []
	if c.x == 0 or c.y == 0:
		next.append(footprint(id))
	else:
		for n in [Vector2i(c.x, 0), Vector2i(0, 1)]:
			if sites[id].edge.has(n):
				next.append(edge_poly(id, n))
	for other in next:
		var touch := 0.0
		for grown in Geometry2D.offset_polygon(other, 0.5):
			for q in Geometry2D.intersect_polygons(part, grown):
				touch += CivicHubs.area(q)
		if touch >= 2.0:
			return true
	return false


## Why ground `world` (an edge piece's outline, x, z) can't be park `id`'s,
## or "": the hubs' checks (water, reserves, other owners, zoned or built
## lots), less the road one (it's already cut back), and no other park's
## land or zoned lot running onto it at all.
func _edge_problem(sim: CitySim, id: int, world: PackedVector2Array) -> String:
	var p := sim.hubs._ground_problem(sim, world, CivicHubs._inner_pts(world, 4.0), -1, true, false)
	if p != "":
		return p
	for other in sites:
		if other != id and _poly_hits(world, land_polys(other)):
			return "Overlaps %s." % sites[other].name
	# No zoned or built lot running onto it, nor zoning not yet a lot.
	return BlockEdges.zoned_problem(sim, world)


## Roads win over edge pieces too: each is cut back to the roads as they
## are now (or goes, if too little is left), and a corner left with no
## piece next to it goes. True when anything changed.
func _prune_edges(sim: CitySim, id: int) -> bool:
	var s: Dictionary = sites[id]
	var changed := false
	# Sides and the back first, so a corner is checked against what's left.
	for c in EDGE_PIECES:
		if not s.edge.has(c):
			continue
		var now := edge_poly(id, c)
		var parts := CivicHubs._cut_by_roads(sim.network, now)
		var left := 0.0
		for part in parts:
			left = maxf(left, CivicHubs.area(part))
		if left >= CivicHubs.area(now) - 0.5 and _edge_touches(id, c, now):
			continue
		changed = true
		var shape := _edge_shape(sim, id, c, now) if left > 0.0 else PackedVector2Array()
		if shape.is_empty():
			s.edge.erase(c)
		else:
			s.edge[c] = shape
	return changed


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
			sim.economy.money += cost_of(s.kind, int(s.get("class", 0)))
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
		# Its edge pieces were cut to the old outline: they come back fitted
		# to the new one if it's still boxed in.
		s.edge = {}
	# A road by a park's edge pieces cuts them back (the corridors here
	# leave the sidewalk gap out, so this goes by the roads themselves).
	for id in ids:
		if sites.has(id) and not sites[id].get("edge", {}).is_empty() and _prune_edges(sim, id):
			changed = true
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
			"size": [s.size.x, s.size.y], "class": s.get("class", 0), "start_area": s.start_area, "founded": s.founded, "features": fs,
			"score": s.score, "tier": s.tier, "next_feature": s.next_feature, "grew": s.grew,
			"leader": s.leader, "why": s.why}
		if not s.get("ask", {}).is_empty():
			out[str(id)].ask = s.ask
		if not s.get("edge", {}).is_empty():
			out[str(id)].edge = CivicHubs.edge_to_save(s.edge)
	return {"next_id": _next_id, "sites": out, "tourism": tourism.to_dict(), "trails": trails.to_dict()}


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
			"class": int(e.get("class", 0)),
			"start_area": float(e.start_area), "founded": int(e.get("founded", e.get("built", 0))), "features": fs, "score": float(e.score),
			"tier": int(e.tier), "next_feature": int(e.next_feature), "grew": int(e.grew),
			"leader": _leader(e.get("leader", {})), "why": str(e.get("why", "")),
			"edge": CivicHubs.edge_from_save(e.get("edge", [])), "ask": Dictionary(e.get("ask", {}))}
	_next_id = int(d.get("next_id", 1))
	tourism.from_dict(d.get("tourism", {}))
	trails.from_dict(d.get("trails", {}))


## A park board chair: an Agency leader with a name of their own.
static func _hire(sim: CitySim, seed: int) -> Dictionary:
	var l := Agency.leader(sim, seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	l.name = "%s %s" % [Education.FIRST[rng.randi() % Education.FIRST.size()], Education.LAST[rng.randi() % Education.LAST.size()]]
	return l


static func _leader(l: Dictionary) -> Dictionary:
	return {"name": str(l.get("name", "Pat Lee")), "edu": float(l.get("edu", 0.5)),
		"caution": float(l.get("caution", 0.5)), "ambition": float(l.get("ambition", 0.5))}
