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

## id -> {kind, name, pos (centre), dir (unit, toward its road), size
## (width along the road x depth), start_area, founded (tick), features:
## [{type, pos, size}], score (neighborhood, 0 to 1), tier, next_feature
## (tick), grew (strips bought), leader (the park board's chair: Agency.leader
## plus a name), why (what the board did last)}. Tree items sit in
## `features` like the basics; `built` (for Agency) is their types.
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
func ground_problem(sim: CitySim, poly: PackedVector2Array, skip := -1) -> String:
	for q in poly:
		if not sim.land_ok(Vector3(q.x, 0.0, q.y)):
			return "Can't build in the water or on a slope that steep."
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
		"leader": _hire(sim, hash([sim.city_seed, id, kind])), "why": ""}
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


## The park or landmark whose ground holds this point, or -1.
func at(p: Vector3) -> int:
	for id in sites:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), footprint(id)):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1 or trails.on_path(p)


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
	lot_value.clear()
	lot_happy.clear()
	if sites.is_empty() and trails.paths.is_empty():
		return
	for key in sim.buildings:
		if not sim.lots.has(key):
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
		return "needs a %s neighborhood" % str(Neighborhood.TIERS[int(n.tier)].name).to_lower()
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
		"pond": Vector2(-1.0, 1.0), "pool": Vector2(1.0, -0.6), "aquatic_center": Vector2(1.0, 0.4)}.get(type, Vector2.ZERO)
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
	for o in order:
		var strip: Vector2 = o[2]
		var area: float = strip.x * strip.y
		if s.size.x * s.size.y + area > cap + 1.0:
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
			"leader": _leader(e.get("leader", {})), "why": str(e.get("why", ""))}
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
