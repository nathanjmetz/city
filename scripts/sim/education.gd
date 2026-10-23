class_name Education
extends RefCounted
## High schools, community colleges and universities, the way Brawn asked
## (2026-10-22): the player places one and sets its funding, and it hires a
## principal or president who runs it like a real institution trying to stay
## solvent. It fills its seats from the town (and, for a college or
## university, the region), saves, and buys the free land next to it for new
## buildings over the years. It never opens a second site: boxed in, it
## builds up instead. Graduates who stay make the town better educated,
## office and tech jobs open only for the graduates the town has, and the
## town's education shapes the leaders it hires (see leader_education()).
##
## Students are real trips: school buses in the morning and afternoon, and
## college students driving in. The numbers live in Balance.EDUCATION.

## One campus block: a 120 m square, about 3.6 acres (room for a football
## field with its bleachers). A full high school of 14 blocks covers about
## 50 acres, like a real consolidated Indiana high school.
const CELL := 120.0
## The most storeys a building block rises to when the campus is boxed in.
const MAX_LEVELS := 3
## Names and who runs it.
const KINDS := {
	"high_school": {"name": "High school", "head": "Principal", "icon": "school"},
	"college": {"name": "Community college", "head": "President", "icon": "school"},
	"university": {"name": "University", "head": "President", "icon": "school"},
}

## The development tree (Brawn 2026-10-22): every block a campus buys
## becomes one of these. Its head can only build what it is capable of and
## what the town and region around it call for, so two towns' universities
## grow up differently. Nodes follow the shared Agency shape ({id, name,
## requires, needs, effects, note}, see scripts/sim/agency.gd), plus `art`
## (how CampusBuilder draws it) and `repeat` (can be built more than once:
## a campus buys land block by block). Effects: `seats` (times the kind's
## block_seats), `rep` (reputation), `draw` (extra pull on students from the
## region), `jobs` (office, research or tech jobs it brings) and `stay`
## (extra share of graduates who settle here because local employers want
## what it teaches). `needs` takes any Agency condition (leader_edu,
## population, link, local:farm, local:<chain>, region_makes:<good>,
## region_buys:<good>, education) and these campus ones:
##   rep: reputation   enrolled: students   funding: the city's funding share
##   industry / shops: companies and factories, or shops, in town
##   clinic: a clinic in town
const TREE := {
	"high_school": [
		{"id": "classrooms", "name": "Classroom wing", "art": "hall", "repeat": true, "effects": {"seats": 1.0}},
		{"id": "gym", "name": "Gym", "art": "gym", "effects": {"seats": 0.3, "rep": 0.03}},
		{"id": "fields", "name": "Practice fields", "art": "fields", "effects": {"rep": 0.02}},
		{"id": "parking", "name": "Student parking", "art": "parking", "needs": {"enrolled": 400}, "effects": {"seats": 0.2}},
		{"id": "stadium", "name": "Football stadium", "art": "stadium", "requires": ["fields"],
			"needs": {"enrolled": 600}, "effects": {"rep": 0.05}},
		{"id": "arts", "name": "Fine arts wing", "art": "hall", "requires": ["classrooms"],
			"needs": {"leader_edu": 0.45, "funding": 1.0}, "effects": {"seats": 0.5, "rep": 0.04}},
		{"id": "ag_shop", "name": "FFA ag barn and shop", "art": "hall", "needs": {"local:farm": 2},
			"effects": {"seats": 0.4, "stay": 0.05}, "note": "farm kids learn to run the farm"},
		{"id": "career", "name": "Career center (welding, auto, building trades)", "art": "hall",
			"needs": {"industry": 3}, "effects": {"seats": 0.6, "stay": 0.05}},
		{"id": "area_career", "name": "Area career center", "art": "tech", "requires": ["career"],
			"needs": {"link": 1, "population": 4000}, "effects": {"seats": 0.5, "draw": 0.05, "stay": 0.05},
			"note": "shared with the districts around it, like Indiana's area career centers"},
		{"id": "natatorium", "name": "Natatorium", "art": "gym", "requires": ["gym"],
			"needs": {"population": 8000}, "effects": {"rep": 0.03}},
	],
	"college": [
		{"id": "classrooms", "name": "Classroom building", "art": "hall", "repeat": true, "effects": {"seats": 1.0}},
		{"id": "parking", "name": "Commuter parking", "art": "parking", "repeat": true, "effects": {"seats": 0.3}},
		{"id": "fields", "name": "Athletic fields", "art": "fields", "needs": {"enrolled": 800}, "effects": {"rep": 0.02}},
		{"id": "tech_center", "name": "Advanced manufacturing center", "art": "tech", "needs": {"industry": 3},
			"effects": {"seats": 0.7, "stay": 0.1, "jobs": 10}},
		{"id": "nursing", "name": "Nursing and health sciences", "art": "lab", "needs": {"clinic": 1},
			"effects": {"seats": 0.6, "stay": 0.1}},
		{"id": "ag_diesel", "name": "Ag and diesel tech", "art": "tech", "needs": {"local:farm": 2},
			"effects": {"seats": 0.5, "stay": 0.1}},
		{"id": "agribusiness", "name": "Agribusiness program", "art": "hall", "requires": ["classrooms"],
			"needs": {"region_makes:grain": 1, "link": 1}, "effects": {"seats": 0.4, "draw": 0.1, "stay": 0.05},
			"note": "a neighbouring farm town sends its students"},
		{"id": "business", "name": "Business and IT center", "art": "hall", "needs": {"shops": 15, "leader_edu": 0.5},
			"effects": {"seats": 0.6, "stay": 0.05, "jobs": 10}},
		{"id": "workforce", "name": "Workforce training center", "art": "tech", "requires": ["tech_center"],
			"needs": {"leader_edu": 0.55}, "effects": {"seats": 0.4, "jobs": 25}},
	],
	"university": [
		{"id": "hall", "name": "Academic hall", "art": "hall", "repeat": true, "effects": {"seats": 1.0}},
		{"id": "quad", "name": "Quad", "art": "quad", "repeat": true, "requires": ["hall"], "effects": {"rep": 0.02}},
		{"id": "library", "name": "Library", "art": "library", "requires": ["hall"], "effects": {"seats": 0.3, "rep": 0.06}},
		{"id": "parking", "name": "Parking", "art": "parking", "repeat": true, "needs": {"enrolled": 2000},
			"effects": {"seats": 0.2}},
		{"id": "dorm", "name": "Residence hall", "art": "dorm", "repeat": true, "needs": {"link": 1, "enrolled": 1800},
			"effects": {"seats": 0.8, "draw": 0.15}},
		{"id": "fields", "name": "Rec fields", "art": "fields", "needs": {"enrolled": 2000}, "effects": {"rep": 0.02}},
		{"id": "stadium", "name": "Football stadium", "art": "stadium", "requires": ["fields"],
			"needs": {"enrolled": 3500}, "effects": {"rep": 0.06, "draw": 0.2}},
		{"id": "ag_extension", "name": "College of Agriculture and extension office", "art": "hall",
			"needs": {"local:farm": 3}, "effects": {"seats": 0.6, "stay": 0.1, "jobs": 15, "draw": 0.05}},
		{"id": "engineering", "name": "College of Engineering", "art": "lab", "needs": {"industry": 3, "leader_edu": 0.75},
			"effects": {"seats": 0.8, "rep": 0.04, "stay": 0.1, "jobs": 10}},
		{"id": "business", "name": "School of Business", "art": "hall", "needs": {"shops": 20},
			"effects": {"seats": 0.8, "stay": 0.1, "jobs": 15}},
		{"id": "lab", "name": "Science research lab", "art": "lab", "needs": {"leader_edu": 0.8, "rep": 0.45},
			"effects": {"seats": 0.3, "rep": 0.06, "jobs": 30}},
		{"id": "research_park", "name": "Research park", "art": "tech", "requires": ["lab"],
			"needs": {"leader_edu": 0.85, "rep": 0.55}, "effects": {"rep": 0.05, "stay": 0.15, "jobs": 120}},
		{"id": "med_school", "name": "School of Medicine", "art": "lab",
			"needs": {"clinic": 1, "rep": 0.6, "population": 5000}, "effects": {"seats": 0.5, "rep": 0.08, "jobs": 60}},
		{"id": "arena", "name": "Basketball arena", "art": "gym", "requires": ["stadium"],
			"needs": {"enrolled": 6000}, "effects": {"rep": 0.04, "draw": 0.1}},
	],
}
## Conditions only a campus has (the rest go to Agency.holds).
const CAMPUS_NEEDS := ["rep", "enrolled", "funding", "industry", "shops", "clinic"]
## Arts drawn as a building, which can rise when the campus is boxed in.
const BUILDING_ARTS := ["hall", "lab", "tech", "library", "dorm", "gym"]

const FIRST := ["Linda", "James", "Karen", "Robert", "Susan", "Michael", "Deborah", "David", "Patricia",
	"Thomas", "Janet", "Gary", "Carol", "Steven", "Brenda", "Mark", "Diane", "Daniel", "Teresa", "Kevin"]
const LAST := ["Harmon", "Schroeder", "Whitfield", "Baker", "Lindqvist", "Hayes", "Kowalski", "Dunn",
	"Pruitt", "Albrecht", "Mercer", "Lutz", "Ostrander", "Brennan", "Yoder", "Graber", "Kessler", "Pike"]

## Campuses: id -> {kind, pos (centre of the first building's block), dir
## (unit, toward its road), blocks: [{c: Vector2i in its own frame, use,
## levels}], funding (index into Balance.EDUCATION_FUNDING_LEVELS), savings,
## applicants, enrolled, reputation, leader (Agency.leader plus a name:
## {name, edu, caution, ambition}), built and why (Agency), asking (its
## open land request to the player: {req, cell, use}), grads (everyone it
## has graduated), idle (why it isn't growing, not saved)}
var campuses := {}
## Graduates of the town's own schools who live and work here (people).
var locals := {"high_school": 0.0, "associate": 0.0, "degree": 0.0}
## Neighbors' towns in a shared region, for the student draw:
## {"population"}. The region client fills this in; a solo city has none,
## and only its own road out matters. (The tree reads neighbours through
## Agency: sim.trade.last_deals and sim.region.)
var region := {}
var _next_id := 1


static func spec(kind: String) -> Dictionary:
	return Balance.EDUCATION[kind]


static func _right(c: Dictionary) -> Vector3:
	return Vector3(-c.dir.z, 0.0, c.dir.x)


## Centre of a block (0,0 is the first building); +y runs away from the road.
static func block_center(c: Dictionary, cell: Vector2i) -> Vector3:
	var p: Vector3 = c.pos + _right(c) * (cell.x * CELL) - c.dir * (cell.y * CELL)
	return Vector3(p.x, 0.0, p.z)


static func block_corners(c: Dictionary, cell: Vector2i) -> PackedVector2Array:
	var mid := block_center(c, cell)
	var r: Vector3 = _right(c) * CELL * 0.5
	var b: Vector3 = -c.dir * CELL * 0.5
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * k.x + b * k.y
		out.append(Vector2(p.x, p.z))
	return out


## Where a campus goes when placed beside the road nearest `hit`: [centre,
## dir toward the road], or [] if no road is near.
static func site_near(network: RoadNetwork, hit: Vector3) -> Array:
	var near := network.find_segment_near(hit, 100.0, 1.0)
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
	var front := RoadStyle.right_of_way_half(network.segments[near.seg].type) + Services.SETBACK
	return [Vector3(p.x, 0.0, p.z) + normal * (front + CELL * 0.5), -normal]


## Why a campus can't go here, or "" if it can.
static func site_problem(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> String:
	if not KINDS.has(kind):
		return "Unknown campus."
	var probe := {"pos": pos, "dir": dir}
	var poly := block_corners(probe, Vector2i.ZERO)
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for p in _probe_points(pos, poly):
		if not sim.land_ok(p):
			return "Can't build in the water or on a slope that steep."
		if sim.banks.covers(p):
			return "That ground is a bank."
		if sim.education.covers(p):
			return "Too close to another campus. Campuses grow on their own, so give it room."
		if sim.telecom.covers(p):
			return "That ground belongs to the phone company."
		if sim.services.covers(p):
			return "Overlaps a service building."
		var owner := Capital.owner_of(sim, p)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if owner.begins_with("site:"):
			return "That ground belongs to a company."
		if sim.reserves.kind_at(p) != "":
			return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(p)]
		if sim.hubs.covers(p) or sim.warehouses.covers(p) or sim.parks.covers(p) or sim.mail.covers(p):
			return "Overlaps a landfill, cemetery, warehouse, park or the post office."
	return ""


static func _probe_points(mid: Vector3, poly: PackedVector2Array) -> Array:
	var pts := [mid]
	for q in poly:
		pts.append(mid.lerp(Vector3(q.x, 0.0, q.y), 0.85))
	for i in poly.size():
		var e := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
		pts.append(mid.lerp(Vector3(e.x, 0.0, e.y), 0.85))
	return pts


## Opens a campus and hires its head. `seed` makes the hire the same on
## every copy of the city.
func add(sim: CitySim, kind: String, pos: Vector3, dir: Vector3, seed: int, tick: int) -> int:
	var id := _next_id
	_next_id += 1
	campuses[id] = {"kind": kind, "pos": pos, "dir": dir, "blocks": [], "built": [], "why": "", "funding": 2,
		"savings": 0.0, "applicants": 0, "enrolled": 0, "reputation": Balance.EDUCATION_START_REPUTATION,
		"leader": hire(sim, kind, hash([seed, id, kind])), "grads": 0.0, "founded": tick, "idle": "",
		"cleared": [], "asking": {}}
	return id


## A new principal or president: an Agency leader (schooling follows the
## town's, caution and ambition are their own) with a name, and the degree
## the job calls for (a university always hires a doctorate).
static func hire(sim: CitySim, kind: String, seed: int) -> Dictionary:
	var l := Agency.leader(sim, seed)
	if kind == "university":
		l.edu = maxf(l.edu, 0.75)
	elif kind == "college":
		l.edu = maxf(l.edu, 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	l.name = "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
	return l


## "Dr. Linda Harmon" for a doctorate, else the plain name.
static func leader_name(l: Dictionary) -> String:
	return ("Dr. " if l.edu >= 0.7 else "") + str(l.name)


static func degree_name(edu: float) -> String:
	if edu >= 0.7:
		return "doctorate"
	if edu >= 0.4:
		return "master's degree"
	return "bachelor's degree"


## How the leader runs things, in a few words.
static func leader_style(l: Dictionary) -> String:
	var parts := []
	if l.caution >= 0.6:
		parts.append("cautious")
	elif l.caution <= 0.35:
		parts.append("bold")
	if l.ambition >= 0.6:
		parts.append("ambitious")
	elif l.ambition <= 0.35:
		parts.append("content")
	return ", ".join(parts) if not parts.is_empty() else "steady"


## Students it has room for: the first building plus every block, more for
## blocks built up.
static func seats(c: Dictionary) -> int:
	var b: Dictionary = spec(c.kind)
	var n: float = b.seats
	for blk in c.blocks:
		n += float(b.block_seats) * float(dev(c.kind, blk.use).get("effects", {}).get("seats", 0.0)) * int(blk.levels)
	return roundi(n)


## One development in the tree (empty if unknown, as in an older save).
static func dev(kind: String, use: String) -> Dictionary:
	for node in TREE[kind]:
		if node.id == use:
			return node
	return {}


## The sum of one effect (seats, rep, draw, jobs, stay) over a campus's
## blocks. Like Agency.effect, but a repeatable node counts once per block.
static func effect(c: Dictionary, what: String) -> float:
	var total := 0.0
	for blk in c.blocks:
		total += float(dev(c.kind, blk.use).get("effects", {}).get(what, 0.0))
	return total


## What the town offers, for the campus-only conditions (the rest, local
## and regional, are Agency's).
static func town_facts(sim: CitySim) -> Dictionary:
	var f := {"industry": sim.industry.sites.size(), "shops": 0, "clinic": 0}
	for key in sim.buildings:
		match int(sim.buildings[key].zone):
			ZoneMap.Zone.INDUSTRIAL: f.industry += 1
			ZoneMap.Zone.COMMERCIAL: f.shops += 1
	for id in sim.services.buildings:
		if sim.services.buildings[id].kind == Services.Kind.CLINIC:
			f.clinic += 1
	return f


## Why a development isn't open to this campus yet, or "" if it is.
static func locked_by(sim: CitySim, c: Dictionary, use: String, facts: Dictionary) -> String:
	var d := dev(c.kind, use)
	if d.is_empty():
		return "unknown"
	if use in c.get("built", []) and not d.get("repeat", false):
		return "built"
	for h in d.get("requires", []):
		if not h in c.get("built", []):
			return "needs a %s first" % dev(c.kind, h).name.to_lower()
	var n: Dictionary = d.get("needs", {})
	for cond in n:
		var v = n[cond]
		var ok: bool
		match cond:
			"rep": ok = c.reputation >= float(v)
			"enrolled": ok = c.enrolled >= int(v)
			"funding": ok = funding_share(c) >= float(v)
			"industry", "shops", "clinic": ok = int(facts.get(cond, 0)) >= int(v)
			_: ok = Agency.holds(sim, c, c.pos, c.savings, cond, v)
		if not ok:
			return _need_text(cond, v)
	return ""


## "needs a head with a doctorate" and so on, for the info panel.
static func _need_text(cond: String, v) -> String:
	match cond:
		"leader_edu": return "needs a head with a %s" % degree_name(float(v))
		"rep": return "needs a %d%% reputation" % roundi(float(v) * 100.0)
		"enrolled": return "needs %s students" % CitySim.money_text(int(v))
		"funding": return "needs full funding"
		"population": return "needs a town of %s" % CitySim.money_text(int(v))
		"industry": return "needs %d companies or factories in town" % int(v)
		"shops": return "needs %d shops in town" % int(v)
		"clinic": return "needs a clinic in town"
		"link": return "needs a road out to the region"
		"education": return "needs more of the town's homes near a school"
	if cond == "local:farm":
		return "needs %d farms nearby" % int(v)
	if cond.begins_with("local:"):
		return "needs a %s nearby" % cond.substr(6)
	if cond.begins_with("region_makes:"):
		return "needs a neighbouring town that sells %s" % cond.substr(13)
	if cond.begins_with("region_buys:"):
		return "needs a neighbouring town that buys %s" % cond.substr(12)
	return "needs " + cond


## Which open development its head builds next: room when it's full, and
## otherwise what fits their ambition and schooling. "" if nothing is open.
static func pick_next(sim: CitySim, c: Dictionary, facts: Dictionary, crowded: bool) -> String:
	var l: Dictionary = c.leader
	var count := {}
	for blk in c.blocks:
		count[blk.use] = count.get(blk.use, 0) + 1
	var best := ""
	var best_score := -INF
	for d in TREE[c.kind]:
		var use: String = d.id
		if locked_by(sim, c, use, facts) != "":
			continue
		var e: Dictionary = d.get("effects", {})
		var score: float = float(e.get("seats", 0.0)) * (2.0 if crowded else 0.3) \
			+ float(e.get("rep", 0.0)) * 20.0 * (0.5 + l.ambition) \
			+ float(e.get("draw", 0.0)) * 5.0 * l.ambition \
			+ float(e.get("jobs", 0.0)) / 30.0 * (0.5 + l.edu) \
			+ float(e.get("stay", 0.0)) * 6.0 \
			- 0.4 * count.get(use, 0)
		if not count.has(use):
			score += 1.0  # something new for the campus beats one more of the same
		if score > best_score + 0.0001 or (absf(score - best_score) <= 0.0001 and use < best):
			best_score = score
			best = use
	return best


## Records a new block's development: Agency's "built" list (each id once)
## and "why", which the info panel shows.
static func _record(c: Dictionary, use: String) -> void:
	_sync_built(c)
	var d := dev(c.kind, use)
	c.why = "%s %s built the %s%s." % [KINDS[c.kind].head, leader_name(c.leader), str(d.get("name", use)).to_lower(),
		(": " + str(d.note)) if d.has("note") else ""]


static func funding_share(c: Dictionary) -> float:
	return Balance.EDUCATION_FUNDING_LEVELS[clampi(int(c.funding), 0, Balance.EDUCATION_FUNDING_LEVELS.size() - 1)]


## What the city pays it a month.
static func monthly_funding(c: Dictionary) -> int:
	return roundi(spec(c.kind).funding * funding_share(c))


## Teaching quality, 0.75 at half funding to 1.25 at the most.
static func quality(c: Dictionary) -> float:
	return 0.5 + 0.5 * funding_share(c)


## Its books for a month at this enrollment: [income, costs]. Its head's
## schooling trims costs by up to a tenth; buildings cost a fixed share of
## the standard funding to keep up whatever the enrollment.
static func books(c: Dictionary, enrolled: int) -> Array:
	var b: Dictionary = spec(c.kind)
	var income: float = (float(b.aid) + float(b.tuition)) * enrolled / 12.0 + monthly_funding(c)
	var costs: float = float(b.spend) * enrolled / 12.0 * (1.0 - 0.1 * float(c.leader.edu)) \
		+ 0.5 * float(b.funding) * (1.0 + 0.15 * c.blocks.size())
	return [income, costs]


func monthly_upkeep() -> int:
	var total := 0
	for id in campuses:
		total += monthly_funding(campuses[id])
	return total


## Every campus takes its month: students apply and enroll, the books
## settle, some graduate, and its head decides whether to buy the next
## block of land (or build up, or sell when deep in debt).
func decide(sim: CitySim) -> bool:
	var changed := false
	var ids := campuses.keys()
	ids.sort()
	_apply_counts(sim)
	var corr := []
	var facts := town_facts(sim)
	var month_attrition := Balance.EDUCATION_ATTRITION / 12.0
	for k in locals:
		locals[k] *= 1.0 - month_attrition
	for id in ids:
		var c: Dictionary = campuses[id]
		var b: Dictionary = spec(c.kind)
		c.enrolled = mini(c.applicants, seats(c))
		var m := books(c, c.enrolled)
		c.savings += m[0] - m[1]
		var grads: float = c.enrolled * float(b.grad_rate) * minf(quality(c), 1.1) / float(b.years) / 12.0
		c.grads += grads
		var into: String = {"high_school": "high_school", "college": "associate", "university": "degree"}[c.kind]
		locals[into] += grads * minf(0.95, float(b.stay) + effect(c, "stay"))
		# Reputation follows funding, its head and how much campus it has.
		var target := 0.2 + 0.35 * (quality(c) - 0.75) / 0.5 + 0.25 * float(c.leader.edu) \
			+ 0.1 * minf(1.0, c.blocks.size() / 10.0) + effect(c, "rep")
		c.reputation += (target - c.reputation) * Balance.EDUCATION_REPUTATION_PULL
		var l: Dictionary = c.leader
		var idle := ""
		var crowded: bool = c.applicants > seats(c) * (1.0 + Balance.EDUCATION_CROWDING * (1.0 + l.caution - 2.0 * l.ambition))
		# The player's word to its head (the leader guide): "grow" builds out
		# whenever the money allows, "hold" buys nothing new.
		var stance: String = sim.permits.guidance("campus", id).stance
		if stance == "grow":
			crowded = true
		elif stance == "hold":
			crowded = false
		var down: float = float(b.block_cost) * Balance.EDUCATION_DOWN_PAYMENT * (1.0 + l.caution)
		if c.savings < -Balance.EDUCATION_SELL_DEBT * float(b.block_cost) and not c.blocks.is_empty():
			c.blocks.pop_back()
			_sync_built(c)
			c.savings += float(b.block_cost) * 0.5
			changed = true
		elif crowded and c.blocks.size() >= int(b.max_blocks):
			idle = "Full, and it already has all the campus it will ever need."
		elif crowded and c.savings < down:
			idle = "Full. Saving $%s for its next building." % CitySim.money_text(roundi(down - maxf(c.savings, 0.0)))
		elif crowded:
			if corr.is_empty():
				corr = RoadWins.corridors(sim.network, 2.0)
			var cell := _best_block(sim, id, c, corr)
			var use := pick_next(sim, c, facts, true)
			if cell != Vector2i.MAX and use != "":
				c.blocks.append({"c": cell, "use": use, "levels": 1})
				_record(c, use)
				c.savings -= float(b.block_cost)
				changed = true
			elif use != "" and l.ambition > l.caution and c.asking.is_empty() and _ask_for_land(sim, id, c, use, corr):
				# Boxed in by homes and shops: an ambitious head asks the
				# player to let it buy them out, as real campuses do.
				idle = "Full and boxed in. Asking you to let it buy the land next door."
				changed = true
			else:
				# Boxed in: build up instead (no second sites, ever).
				var up := -1
				for i in c.blocks.size():
					if dev(c.kind, c.blocks[i].use).get("art", "") in BUILDING_ARTS and c.blocks[i].levels < MAX_LEVELS \
							and (up == -1 or c.blocks[i].levels < c.blocks[up].levels):
						up = i
				if up != -1 and c.savings >= down * 0.6:
					c.blocks[up].levels += 1
					c.savings -= float(b.block_cost) * 0.6
					changed = true
				elif not c.asking.is_empty():
					idle = "Full and boxed in. Waiting on your answer about the land next door."
				else:
					idle = "Full and boxed in: no free land next to it, and nothing left to build up."
		changed = _carry_out(sim, id, c, corr) or changed
		if c.idle != idle:
			c.idle = idle
			changed = true
	var cap := float(sim.stats.workers)
	for k in locals:
		locals[k] = minf(locals[k], cap)
	return changed


## Who wants a seat at each campus: high-school-age teens from the homes
## nearest each high school, and adults from the homes nearest each college
## or university, plus students from the region for those (only once a road
## leads out to it).
func _apply_counts(sim: CitySim) -> void:
	var want := {}
	for id in campuses:
		want[id] = 0.0
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		var h: Dictionary = sim.buildings[key]
		if h.zone != ZoneMap.Zone.RESIDENTIAL or h.occ <= 0 or not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		var hs := _nearest(p, ["high_school"])
		if hs != -1:
			want[hs] += h.occ * Balance.EDUCATION_TEEN_SHARE
		var col := _nearest(p, ["college", "university"])
		if col != -1:
			want[col] += h.occ * Balance.EDUCATION_COLLEGE_SHARE
	var linked := not sim.region_links.is_empty()
	for id in campuses:
		var c: Dictionary = campuses[id]
		if linked and Balance.EDUCATION_REGION_DRAW.has(c.kind):
			# Neighbors' towns send students too, and dorms and a stadium pull more.
			var people := 1.0 + float(region.get("population", 0)) / 50_000.0
			want[id] += Balance.EDUCATION_REGION_DRAW[c.kind] * c.reputation * quality(c) * people \
				* (1.0 + effect(c, "draw"))
		c.applicants = roundi(want[id])


func _nearest(p: Vector3, kinds: Array) -> int:
	var best := -1
	var best_d := INF
	for id in campuses:
		if campuses[id].kind in kinds:
			var d: float = campuses[id].pos.distance_squared_to(p)
			if d < best_d - 0.01:
				best_d = d
				best = id
	return best


## The free block next to the campus that keeps it most compact, nearest
## its first building; Vector2i.MAX if none.
func _best_block(sim: CitySim, id: int, c: Dictionary, corr: Array) -> Vector2i:
	var best := Vector2i.MAX
	var best_score := -INF
	for cell in _frontier(c):
		if not usable(sim, id, c, cell, corr):
			continue
		var score := 2.0 * _neighbors(c, cell) - Vector2(cell).length()
		if score > best_score + 0.001:
			best_score = score
			best = cell
	return best


## True when a block is free to buy: no road, building, zoned or built lot,
## farm, company, reserve or other campus on it. Campuses buy only empty land
## (anything the player built or zoned stays theirs).
func usable(sim: CitySim, id: int, c: Dictionary, cell: Vector2i, corr: Array, lots_ok := false) -> bool:
	var poly := block_corners(c, cell)
	if RoadWins.hits(corr, poly):
		return false
	var mid := block_center(c, cell)
	for p in _probe_points(mid, poly):
		var other := at(p)
		if other != -1 and other != id:
			return false
		if not sim.land_ok(p) or sim.services.covers(p) or Capital.owner_of(sim, p) != "" \
				or sim.reserves.kind_at(p) != "" or sim.hubs.covers(p) \
				or sim.warehouses.covers(p) or sim.parks.covers(p) or sim.mail.covers(p) or sim.banks.covers(p) or sim.telecom.covers(p):
			return false
	if lots_ok:
		return true
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.NONE:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), poly) \
				or sim.lots[key].pos.distance_to(mid) < CELL * 0.5:
			return false
	return true


## Agency's "built": each development a campus has, once, in build order.
static func _sync_built(c: Dictionary) -> void:
	c.built = []
	for blk in c.blocks:
		if not blk.use in c.built:
			c.built.append(blk.use)


## Files a land-use request (Permits) for the block next door that only
## the player's homes and shops stand on. Returns true if it was filed.
func _ask_for_land(sim: CitySim, id: int, c: Dictionary, use: String, corr: Array) -> bool:
	if not sim.permits.can_file(sim, "campus", id):
		return false
	for cell in _frontier(c):
		if usable(sim, id, c, cell, corr) or not usable(sim, id, c, cell, corr, true):
			continue
		var outline := []
		for p in block_corners(c, cell):
			outline.append([p.x, p.y])
		var hits := sim.permits.check(sim, outline, 0.0, true)
		if not hits.roads.is_empty() or hits.buildings.is_empty():
			continue
		var homes := 0
		for h in hits.buildings:
			if h.what != "lot":
				outline = []
				break
			homes += 1
		if outline.is_empty():
			continue
		var name := str(dev(c.kind, use).get("name", use))
		var req := sim.permits.file(sim, {"hub": "campus", "hub_id": id, "leader": leader_name(c.leader),
			"title": "%s wants the block next door" % KINDS[c.kind].name,
			"why": "It is full and boxed in. It would buy out %d %s there for a %s." % [homes,
				"property" if homes == 1 else "properties", name.to_lower()],
			"change": "Homes and shops to campus", "area": outline,
			"per_m2": Balance.EDUCATION_LAND_PER_M2, "budget": maxi(roundi(c.savings), 0)})
		if req != -1:
			c.asking = {"req": req, "cell": cell, "use": use}
			return true
		return false
	return false


## Carries out an approved land request (the player may have reshaped it):
## buys out what stands there and builds the block, if the block's middle
## is still inside the land the player gave. Drops a request that was
## denied or shelved.
func _carry_out(sim: CitySim, id: int, c: Dictionary, corr: Array) -> bool:
	if c.asking.is_empty():
		return false
	var req: Dictionary = sim.permits.requests.get(int(c.asking.req), {})
	if req.is_empty() or req.state in [Permits.State.DENIED, Permits.State.SHELVED, Permits.State.WITHDRAWN, Permits.State.DONE]:
		c.asking = {}
		return true
	if req.state != Permits.State.APPROVED:
		return false
	var cell: Vector2i = c.asking.cell
	var mid := block_center(c, cell)
	var area := PackedVector2Array()
	for p in req.route:
		area.append(Vector2(p[0], p[1]))
	var b: Dictionary = spec(c.kind)
	if Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z), area) and usable(sim, id, c, cell, corr, true):
		c.blocks.append({"c": cell, "use": c.asking.use, "levels": 1})
		_record(c, c.asking.use)
		c.savings -= float(b.block_cost) + float(req.cost)
		# The homes and shops on it are bought out: their lots give way to
		# the campus at the next re-plat.
		sim._lots_dirty = true
	sim.permits.done(int(c.asking.req))
	c.asking = {}
	return true


static func _frontier(c: Dictionary) -> Array:
	var have := {Vector2i.ZERO: true}
	for blk in c.blocks:
		have[blk.c] = true
	var out := []
	var seen := {}
	for cell in c.get("cleared", []):
		seen[cell] = true  # the player cleared it for something else
	var keys := have.keys()
	keys.sort()
	for h in keys:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = h + d
			if not have.has(n) and not seen.has(n) and n.y >= 0:
				seen[n] = true
				out.append(n)
	return out


static func _neighbors(c: Dictionary, cell: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if cell + d == Vector2i.ZERO:
			n += 1
		for blk in c.blocks:
			if blk.c == cell + d:
				n += 1
	return n


## The campus with a block on this point, or -1.
func at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in campuses:
		var c: Dictionary = campuses[id]
		var d: Vector3 = p - c.pos
		var cell := Vector2i(roundi(d.dot(_right(c)) / CELL), roundi(-d.dot(c.dir) / CELL))
		if cell != Vector2i.ZERO:
			var found := false
			for blk in c.blocks:
				found = found or blk.c == cell
			if not found:
				continue
		if Geometry2D.is_point_in_polygon(q, block_corners(c, cell)):
			return id
	return -1


## The player clears one block (to make room for something else). Clearing
## the first building closes the campus. Returns true if anything went.
func remove_at(p: Vector3) -> bool:
	var id := at(p)
	if id == -1:
		return false
	var c: Dictionary = campuses[id]
	var d: Vector3 = p - c.pos
	var cell := Vector2i(roundi(d.dot(_right(c)) / CELL), roundi(-d.dot(c.dir) / CELL))
	if cell == Vector2i.ZERO:
		campuses.erase(id)
		return true
	for blk in c.blocks:
		if blk.c == cell:
			c.blocks.erase(blk)
			_sync_built(c)
			# Its head won't buy that block straight back.
			c.cleared.append(cell)
			return true
	return false


func covers(p: Vector3) -> bool:
	return not campuses.is_empty() and at(p) != -1


## Where its students and buses pull in: the middle of its road frontage.
static func front(c: Dictionary) -> Vector3:
	return c.pos + c.dir * (CELL * 0.5)


## Teachers and staff, plus the office and tech jobs the town's graduates
## bring.
func jobs() -> int:
	var n := office_jobs()
	for id in campuses:
		var c: Dictionary = campuses[id]
		n += 8 + c.enrolled / int(spec(c.kind).staff) + int(effect(c, "jobs"))
	return n


## Office and tech jobs: they open only for graduates the town has.
func office_jobs() -> int:
	return floori(locals.degree * Balance.EDUCATION_OFFICE_JOBS.degree
		+ locals.associate * Balance.EDUCATION_OFFICE_JOBS.associate)


## Share of the town's workers with a local college degree (an associate
## degree counts half).
func educated_share(workers: int) -> float:
	return clampf((locals.degree + 0.5 * locals.associate) / maxf(workers, 1.0), 0.0, 1.0)


## How educated the leaders the town can hire are, 0 to 1: 0.25 with no
## local graduates, rising to 1 when four in ten workers hold a local
## degree, as in a college town. Business, industry and transit leaders
## read this too (scripts/sim/agency.gd).
func leader_education(workers: int) -> float:
	return clampf(0.25 + 0.75 * educated_share(workers) / 0.4, 0.0, 1.0)


## The road wins: a road through a campus's first building closes it and
## pays the city back; a road through a block takes that block. Returns the
## money paid back.
func make_way(corr: Array) -> int:
	var back := 0
	var ids := campuses.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = campuses[id]
		if RoadWins.hits(corr, block_corners(c, Vector2i.ZERO)):
			back += int(spec(c.kind).cost)
			campuses.erase(id)
			continue
		for blk in c.blocks.duplicate():
			if RoadWins.hits(corr, block_corners(c, blk.c)):
				c.blocks.erase(blk)
		_sync_built(c)
	return back


## Sends today's students on real trips. On school days the buses leave
## their drivers' homes for the high school before 7 and take everyone home
## after 3 (in rural Indiana the driver keeps the bus at home); college and
## university students drive in for morning classes, some from out of
## town, and drive back out in the late afternoon.
func trips(sim: CitySim) -> void:
	if campuses.is_empty():
		return
	var t := sim.clock()
	if t.weekday == 0 or t.weekday == 6:
		return
	var minute: int = t.hour * 60 + t.minute
	if minute < 380 or minute > 1080:
		return
	var homes := []
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			homes.append(key)
	if homes.is_empty():
		return
	homes.sort()
	var ids := campuses.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = campuses[id]
		var at_school := {"ref": "campus:%d" % id, "pos": [front(c).x, front(c).z]}
		if c.kind == "high_school":
			var buses := clampi(ceili(c.enrolled / 55.0), 0, 10)
			for i in buses:
				var home: String = homes[absi(hash([id, i, "bus"])) % homes.size()]
				var there := {"ref": "home:" + home, "pos": [sim.lots[home].front.x, sim.lots[home].front.z]}
				if minute == 385 + i * 4:
					sim.traffic.dispatch(there, at_school, "school")
				elif minute == 900 + i * 4:
					sim.traffic.dispatch(at_school, there, "school")
			continue
		var cars := clampi(c.enrolled / 80, 0, 16)
		for i in cars:
			var there := {}
			# Region students come in on the county highway.
			if i % 3 == 2 and not sim.region_links.is_empty():
				var n: int = sim.region_links[i % sim.region_links.size()]
				if sim.network.nodes.has(n):
					there = {"ref": "edge", "pos": [sim.network.nodes[n].x, sim.network.nodes[n].z]}
			if there.is_empty():
				var home: String = homes[absi(hash([id, i, "student"])) % homes.size()]
				there = {"ref": "home:" + home, "pos": [sim.lots[home].front.x, sim.lots[home].front.z]}
			if minute == 455 + i * 2:
				sim.traffic.dispatch(there, at_school, "commute")
			elif minute == 990 + i * 3:
				sim.traffic.dispatch(at_school, there, "commute")


func to_dict() -> Dictionary:
	var out := {}
	for id in campuses:
		var c: Dictionary = campuses[id]
		var blocks := []
		for blk in c.blocks:
			blocks.append([blk.c.x, blk.c.y, blk.use, blk.levels])
		out[str(id)] = {"kind": c.kind, "pos": [c.pos.x, c.pos.z], "dir": [c.dir.x, c.dir.z], "blocks": blocks,
			"funding": c.funding, "savings": c.savings, "applicants": c.applicants, "enrolled": c.enrolled,
			"reputation": c.reputation, "leader": c.leader, "grads": c.grads, "founded": c.founded, "why": c.why,
			"asking": [] if c.asking.is_empty() else [c.asking.req, c.asking.cell.x, c.asking.cell.y, c.asking.use],
			"cleared": c.get("cleared", []).map(func(v): return [v.x, v.y])}
	return {"campuses": out, "locals": locals, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	campuses.clear()
	for k in d.get("campuses", {}):
		var s: Dictionary = d.campuses[k]
		var blocks := []
		for b in s.get("blocks", []):
			blocks.append({"c": Vector2i(int(b[0]), int(b[1])), "use": str(b[2]), "levels": int(b[3])})
		var l: Dictionary = s.get("leader", {})
		campuses[int(k)] = {"kind": str(s.kind), "pos": Vector3(s.pos[0], 0.0, s.pos[1]),
			"dir": Vector3(s.dir[0], 0.0, s.dir[1]).normalized(), "blocks": blocks,
			"funding": int(s.get("funding", 2)), "savings": float(s.get("savings", 0.0)),
			"applicants": int(s.get("applicants", 0)), "enrolled": int(s.get("enrolled", 0)),
			"reputation": float(s.get("reputation", Balance.EDUCATION_START_REPUTATION)),
			"leader": {"name": str(l.get("name", "Pat Lee")), "edu": float(l.get("edu", l.get("education", 0.5))),
				"caution": float(l.get("caution", 0.5)), "ambition": float(l.get("ambition", 0.5))},
			"grads": float(s.get("grads", 0.0)), "founded": int(s.get("founded", 0)), "idle": "",
			"cleared": s.get("cleared", []).map(func(v): return Vector2i(int(v[0]), int(v[1]))),
			"why": str(s.get("why", "")), "asking": {}}
		var ask: Array = s.get("asking", [])
		if ask.size() == 4:
			campuses[int(k)].asking = {"req": int(ask[0]), "cell": Vector2i(int(ask[1]), int(ask[2])), "use": str(ask[3])}
		_sync_built(campuses[int(k)])
	locals = {"high_school": 0.0, "associate": 0.0, "degree": 0.0}
	var l2: Dictionary = d.get("locals", {})
	for k in locals:
		locals[k] = float(l2.get(k, 0.0))
	_next_id = int(d.get("next_id", 1))
