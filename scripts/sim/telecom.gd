class_name Telecom
extends RefCounted
## The town's phone company, the way Brawn green-lit it (2026-10-22, Best of
## CS #17): the player places its central office once and sets the city's
## broadband grant, and from then on its general manager runs it like a real
## rural telephone co-op trying to stay in business.
##   - Fiber goes down the streets that pay back first, which are the
##     densest. Crews string it from the office outward, street by street,
##     and every job is a real truck trip.
##   - Cell towers go up where too many households get one bar or none, or
##     where a tower is overloaded. The first stands in the office's own
##     yard. Every other one is a zoning request on the permit bell, as at a
##     real county board of zoning appeals, and the player can say no.
##   - The office grows only into the land right next to it, never a second
##     site, picking from a development tree its manager's schooling and the
##     town around it unlock. Boxed in by roads, it fills the rest of its
##     block up to the sidewalk with lawn and a fenced gravel yard, never
##     another building (Nathan, 2026-10-26: "when a hub with leader is
##     "trapped" inside a road area, it should nicely fill in that area up
##     to the edge (sidewalk) so that it looks like its using its space
##     well."): edge pieces, BlockEdges.
## Coverage draws people, remote workers and offices, and fiber lifts home
## values. Rural edges stay spotty unless the grant pays to reach them.
## Numbers live in Balance (TELECOM_*). Benchmark: CS2's telecom (network
## quality drives offices) and real Indiana co-ops.

## One block of the office's land: a 40 m square (about 0.4 acre), enough
## for a garage bay or a cable yard.
const CELL := 40.0
## The most storeys a building block rises to when the office is boxed in.
const MAX_LEVELS := 2
## Real tower types in the rural Midwest. `height` (m), `radius` the reach
## of its signal (m, a 700 MHz LTE macro site), `capacity` households one
## site serves well (three sectors), and `cost` to build with radios.
const TOWERS := {
	"monopole": {"name": "150-ft monopole", "height": 45.7, "radius": 4_000.0, "capacity": 1_500, "cost": 300_000},
	"lattice": {"name": "300-ft lattice tower", "height": 91.4, "radius": 7_000.0, "capacity": 1_500, "cost": 420_000},
	"monopine": {"name": "120-ft monopine (a tower dressed as a pine)", "height": 36.6, "radius": 3_200.0,
		"capacity": 1_500, "cost": 380_000},
}
## Signal is full out to this share of a tower's radius, then fades to none.
const FULL_SIGNAL := 0.35

## The development tree, on the shared Agency model: its manager picks the
## next node on a monthly cadence from the company's own money. Nodes with
## `land` take the next free block next to the office (the value says how
## TelecomBuilder draws it); the rest are upgrades to the network. Effects:
## "crews*" (fiber crews), "fiber_cost*" (what fiber costs), "take*" (more
## households sign up), "capacity*" (households per tower), "offices*"
## (office demand on fiber streets), "fixed*" and "stealth*" (fixed wireless
## for farms, stealth towers near homes), "jobs+". Conditions are Agency's,
## plus the company's own facts: hub:towers, hub:fiber_km, hub:shops.
const TREE := [
	{"id": "garage", "name": "Line crew garage", "cost": 450_000, "needs": {}, "effects": {"crews*": 1.0},
		"land": "garage", "note": "a second crew strings fiber twice as fast"},
	{"id": "cable_yard", "name": "Cable and reel yard", "cost": 450_000, "needs": {"hub:fiber_km": 3},
		"effects": {"fiber_cost*": -0.15}, "land": "yard", "note": "buys fiber and poles by the truckload"},
	{"id": "store", "name": "Phone store and payment window", "cost": 450_000, "needs": {"hub:shops": 8},
		"effects": {"take*": 0.12}, "land": "store", "note": "more households sign up"},
	{"id": "garage_2", "name": "Second crew garage", "cost": 450_000, "requires": ["garage"],
		"needs": {"hub:fiber_km": 8}, "effects": {"crews*": 1.0}, "land": "garage"},
	{"id": "noc", "name": "Network operations center", "cost": 450_000, "needs": {"leader_edu": 0.5, "hub:towers": 3},
		"effects": {"capacity*": 0.15, "jobs+": 20}, "land": "office", "note": "watches every tower and tunes it"},
	{"id": "lte_5g", "name": "5G radios on every tower", "cost": 400_000,
		"needs": {"leader_edu": 0.55, "population": 3_000}, "effects": {"capacity*": 1.5}},
	{"id": "small_cells", "name": "Small cells on downtown streetlights", "cost": 600_000, "requires": ["lte_5g"],
		"needs": {"leader_edu": 0.7, "population": 6_000}, "effects": {"capacity*": 0.5}},
	{"id": "fixed_wireless", "name": "Fixed wireless internet for farms", "cost": 250_000,
		"needs": {"local:farm": 3, "hub:towers": 2}, "effects": {"fixed*": 0.5},
		"note": "farms past the fiber get internet off the towers"},
	{"id": "stealth", "name": "Stealth towers near homes", "cost": 100_000,
		"needs": {"leader_edu": 0.5, "population": 4_000}, "effects": {"stealth*": 0.2},
		"note": "new towers near homes go up dressed as pines"},
	{"id": "middle_mile", "name": "Middle-mile fiber to the region", "cost": 1_200_000,
		"needs": {"link": 1, "hub:fiber_km": 5}, "effects": {"offices*": 0.05}},
	{"id": "data_center", "name": "Data center", "cost": 450_000, "requires": ["middle_mile"],
		"needs": {"leader_edu": 0.7, "hub:fiber_km": 15}, "effects": {"offices*": 0.1, "jobs+": 25}, "land": "data"},
]
const BUILDING_ARTS := ["garage", "office", "data", "store"]
const FIRST := ["Linda", "James", "Karen", "Robert", "Susan", "Michael", "Deborah", "David", "Patricia",
	"Thomas", "Janet", "Gary", "Carol", "Steven", "Brenda", "Mark", "Diane", "Daniel", "Teresa", "Kevin"]
const LAST := ["Harmon", "Schroeder", "Whitfield", "Baker", "Lindqvist", "Hayes", "Kowalski", "Dunn",
	"Pruitt", "Albrecht", "Mercer", "Lutz", "Ostrander", "Brennan", "Yoder", "Graber", "Kessler", "Pike"]

## Companies (a town has one): id -> {pos (centre of the office block), dir
## (toward its road), blocks [{c, use, levels}], built [tree node ids], towers
## [{pos: [x, z], kind, built}], fiber [{seg, pts: [[x, z], ...]}], funding
## (index into Balance.TELECOM_FUNDING_LEVELS), savings, leader (Agency's,
## plus a name), why (its last move), facts (for the tree, not saved), subs
## {fiber, business, fixed, wireless}, pending {req, pos, kind} (a tower
## waiting on the bell), refused (sites the player turned down), jobs
## (truck trips waiting for the morning), founded, cleared, idle (not saved),
## edge (its edge pieces up to the sidewalk: block -> outline, BlockEdges)}
var companies := {}
var _next_id := 1
## Per building key: {fiber: bool, q: cell signal 0..1}. Rebuilt by
## refresh() when stale; never saved.
var served := {}
var remote_workers := 0
## Average signal per household, and the share of businesses on fiber.
var town_signal := 0.0
var business_fiber := 0.0
var _load := {}  # "id:index" -> share of its households a tower serves well
var _dirty := true


static func _right(c: Dictionary) -> Vector3:
	return Vector3(-c.dir.z, 0.0, c.dir.x)


## Centre of a block (0,0 is the office); +y runs away from the road.
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


## The fenced compound around a tower.
static func compound(pos: Vector2) -> PackedVector2Array:
	var h := Balance.TELECOM_COMPOUND * 0.5
	return PackedVector2Array([pos + Vector2(-h, -h), pos + Vector2(h, -h), pos + Vector2(h, h), pos + Vector2(-h, h)])


## The office's own tower stands in its back yard, behind the building.
static func yard_tower(c: Dictionary) -> Vector2:
	var p: Vector3 = c.pos - c.dir * (CELL * 0.5 - Balance.TELECOM_COMPOUND * 0.5 - 0.5) + _right(c) * 9.0
	return Vector2(p.x, p.z)


## Where the office goes beside the road nearest `hit`: [centre, dir toward
## the road], or [] if no road is near.
static func site_near(network: RoadNetwork, hit: Vector3) -> Array:
	var near := RoadIndex.segment_near(network, hit, 60.0, 1.0)
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


## Why the office can't go here, or "" if it can.
static func site_problem(sim: CitySim, pos: Vector3, dir: Vector3) -> String:
	if not sim.telecom.companies.is_empty():
		return "The town already has its phone company. It grows on its own."
	var probe := {"pos": pos, "dir": dir}
	var poly := block_corners(probe, Vector2i.ZERO)
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for p in _probe_points(pos, poly):
		var why := ground_problem(sim, p)
		if why != "":
			return why
	return ""


## What else stands on a point, or "".
static func ground_problem(sim: CitySim, p: Vector3) -> String:
	if not sim.land_ok(p):
		return "Can't build in the water or on a slope that steep."
	if sim.services.covers(p):
		return "Overlaps a service building."
	var owner := Capital.owner_of(sim, p)
	if owner.begins_with("farm:"):
		return "That ground is farmland."
	if owner.begins_with("site:"):
		return "That ground belongs to a company."
	if sim.reserves.kind_at(p) != "":
		return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(p)]
	if sim.education.covers(p):
		return "That ground is a campus."
	if sim.hubs.covers(p) or sim.warehouses.covers(p) or sim.parks.covers(p) or sim.mail.covers(p):
		return "Overlaps a landfill, cemetery, warehouse, park or post office."
	if sim.banks.covers(p):
		return "That ground is a bank."
	return ""


static func _probe_points(mid: Vector3, poly: PackedVector2Array) -> Array:
	var pts := [mid]
	for q in poly:
		pts.append(mid.lerp(Vector3(q.x, 0.0, q.y), 0.85))
	for i in poly.size():
		var e := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
		pts.append(mid.lerp(Vector3(e.x, 0.0, e.y), 0.85))
	return pts


## Opens the company and hires its manager; its first tower goes up in the
## office's own yard.
func add(sim: CitySim, pos: Vector3, dir: Vector3, seed: int, tick: int) -> int:
	var id := _next_id
	_next_id += 1
	var lead := Agency.leader(sim, hash([seed, id, "telecom"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, id, "telecom", "name"])
	lead.name = "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
	var c := {"pos": pos, "dir": dir, "blocks": [], "built": [], "why": "", "towers": [], "fiber": [], "funding": 2,
		"savings": 0.0, "leader": lead,
		"subs": {"fiber": 0.0, "business": 0.0, "fixed": 0.0, "wireless": 0.0}, "pending": {}, "refused": [],
		"jobs": [], "founded": tick, "cleared": [], "idle": "", "edge": {}}
	var yt := yard_tower(c)
	c.towers.append({"pos": [yt.x, yt.y], "kind": "monopole", "built": tick})
	companies[id] = c
	_dirty = true
	return id


static func dev(id: String) -> Dictionary:
	for node in TREE:
		if node.id == id:
			return node
	return {}


## One effect over what the company has built (Agency's rules: "*" keys
## come back as a multiplier, the rest as a sum).
static func effect(c: Dictionary, key: String) -> float:
	return Agency.effect(c, TREE, key)


static func has(c: Dictionary, id: String) -> bool:
	return id in c.built


## "Linda Harmon", how they were schooled, and how they run things.
static func leader_name(l: Dictionary) -> String:
	return str(l.get("name", "The manager"))


static func leader_style(l: Dictionary) -> String:
	var school := "college degree" if float(l.edu) >= 0.6 else ("some college" if float(l.edu) >= 0.4 else "high school")
	var style := "careful" if float(l.caution) > 0.6 else ("ambitious" if float(l.ambition) > 0.6 else "steady")
	return "%s, %s" % [school, style]


static func funding_share(c: Dictionary) -> float:
	var levels: Array = Balance.TELECOM_FUNDING_LEVELS
	return levels[clampi(int(c.funding), 0, levels.size() - 1)]


## What the city pays it a month (the broadband grant).
static func monthly_grant(c: Dictionary) -> int:
	return roundi(Balance.TELECOM_GRANT * funding_share(c))


func monthly_upkeep() -> int:
	var total := 0
	for id in companies:
		total += monthly_grant(companies[id])
	return total


static func fiber_m(c: Dictionary) -> float:
	var m := 0.0
	for f in c.fiber:
		m += _poly_len(f.pts)
	return m


static func _poly_len(pts: Array) -> float:
	var m := 0.0
	for i in range(1, pts.size()):
		m += Vector2(pts[i][0], pts[i][1]).distance_to(Vector2(pts[i - 1][0], pts[i - 1][1]))
	return m


static func crews(c: Dictionary) -> int:
	var n := roundi(effect(c, "crews*"))
	for blk in c.blocks:
		if dev(blk.use).get("effects", {}).has("crews*"):
			n += int(blk.levels) - 1  # a garage built up holds another crew
	return n


## Households a tower serves well.
static func tower_capacity(c: Dictionary, t: Dictionary) -> float:
	return float(TOWERS[t.kind].capacity) * effect(c, "capacity*")


## Signal from one tower at a point, 0 to 1.
static func signal_of(t: Dictionary, p: Vector2) -> float:
	var r: float = TOWERS[t.kind].radius
	var d := p.distance_to(Vector2(t.pos[0], t.pos[1]))
	return 1.0 - smoothstep(r * FULL_SIGNAL, r, d)


## Cell service at a point, 0 to 1: the best tower's signal, less when that
## tower has more households than it can serve.
func signal_at(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var best := 0.0
	for id in companies:
		var c: Dictionary = companies[id]
		for i in c.towers.size():
			best = maxf(best, signal_of(c.towers[i], q) * float(_load.get("%d:%d" % [id, i], 1.0)))
	return best


## The planning horizon in years: longer for a schooled manager, a bigger
## grant and the player's "grow", shorter for a cautious one.
static func horizon(sim: CitySim, id: int, c: Dictionary) -> float:
	var l: Dictionary = c.leader
	var h: float = (Balance.TELECOM_HORIZON + Balance.TELECOM_HORIZON_EDU * float(l.edu)) \
		* (0.5 + 0.5 * funding_share(c)) * (0.8 + 0.4 * float(l.ambition)) / (0.8 + 0.4 * float(l.caution))
	if sim.permits.guidance("telecom", id).stance == "grow":
		h *= 1.4
	return h


## The company's own facts its tree reads (as hub:<fact>).
static func facts_of(sim: CitySim, c: Dictionary) -> Dictionary:
	var f := {"towers": c.towers.size(), "fiber_km": fiber_m(c) / 1000.0, "shops": 0}
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.COMMERCIAL:
			f.shops += 1
	return f


## Its yearly profit at this month's books.
static func yearly_profit(c: Dictionary) -> float:
	var m := books(c)
	return (m[0] - m[1]) * 12.0


# ------------------------------------------------------------- coverage

## Recounts who has fiber and cell service, if anything changed.
func refresh(sim: CitySim) -> void:
	if not _dirty:
		return
	_dirty = false
	served.clear()
	_load.clear()
	remote_workers = 0
	town_signal = 0.0
	business_fiber = 0.0
	if companies.is_empty():
		return
	var fiber_segs := {}
	for id in companies:
		for f in companies[id].fiber:
			fiber_segs[int(f.seg)] = true
	var keys := sim.buildings.keys()
	keys.sort()
	# Each household rides its strongest tower; a tower with more than it
	# can serve gives everyone on it a weaker signal.
	var users := {}
	var best := {}
	for key in keys:
		if not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		var q := Vector2(p.x, p.z)
		var top := 0.0
		var on := ""
		for id in companies:
			var c: Dictionary = companies[id]
			for i in c.towers.size():
				var s := signal_of(c.towers[i], q)
				if s > top + 0.0001:
					top = s
					on = "%d:%d" % [id, i]
		best[key] = [top, on]
		if on != "":
			users[on] = users.get(on, 0.0) + _households(sim.buildings[key]) * top
	for id in companies:
		var c: Dictionary = companies[id]
		for i in c.towers.size():
			var k := "%d:%d" % [id, i]
			_load[k] = clampf(tower_capacity(c, c.towers[i]) / maxf(users.get(k, 0.0), 1.0), 0.0, 1.0)
	var hh_total := 0.0
	var sig_total := 0.0
	var remote := 0.0
	var biz := 0
	var biz_fiber := 0
	for key in keys:
		if not best.has(key):
			continue
		var b: Dictionary = sim.buildings[key]
		var q: float = best[key][0] * float(_load.get(best[key][1], 1.0))
		var fib := fiber_segs.has(int(sim.lots[key].get("seg", -1)))
		served[key] = {"fiber": fib, "q": q}
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			var hh := _households(b)
			hh_total += hh
			sig_total += hh * q
			var share := Balance.TELECOM_REMOTE_SHARE if fib \
				else (Balance.TELECOM_REMOTE_CELL if q >= Balance.TELECOM_GOOD_SIGNAL else 0.0)
			remote += int(b.occ) * Balance.WORKER_SHARE * share
		else:
			biz += 1
			if fib:
				biz_fiber += 1
	remote_workers = floori(remote)
	town_signal = sig_total / hh_total if hh_total > 0.0 else 0.0
	business_fiber = float(biz_fiber) / biz if biz > 0 else 0.0


func mark_dirty() -> void:
	_dirty = true


static func _households(b: Dictionary) -> float:
	if int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
		return 0.0
	return float(b.occ) / Balance.TELECOM_PEOPLE_PER_HOUSEHOLD


## How much fiber and cell service lift a lot's value (0.04 = 4%).
func lot_lift(key: String) -> float:
	var s: Dictionary = served.get(key, {})
	if s.is_empty():
		return 0.0
	return (Balance.TELECOM_FIBER_LIFT if s.fiber else 0.0) + Balance.TELECOM_CELL_LIFT * float(s.q)


## The same lift for a point (for neighborhoods): fiber within a street of
## it, and the cell signal there.
func lift_at(sim: CitySim, p: Vector3) -> float:
	if companies.is_empty():
		return 0.0
	var near := RoadIndex.segment_near(sim.network, p, 60.0) if not sim.network.segments.is_empty() else {}
	var fib := false
	if not near.is_empty():
		for id in companies:
			for f in companies[id].fiber:
				fib = fib or int(f.seg) == int(near.seg)
	return (Balance.TELECOM_FIBER_LIFT if fib else 0.0) + Balance.TELECOM_CELL_LIFT * signal_at(p)


## Staff, plus remote workers (their jobs come with them) and the jobs its
## operations center and data center bring.
func jobs() -> int:
	var n := remote_workers
	for id in companies:
		var c: Dictionary = companies[id]
		n += 10 + c.towers.size() / 2 + int(fiber_m(c) / 2000.0) + int(effect(c, "jobs+")) \
			+ int((float(c.subs.fiber) + float(c.subs.wireless)) / 500.0)
	return n


## Extra demand for shops and offices from fiber on business streets.
func office_demand() -> float:
	var boost := 1.0
	for id in companies:
		boost += (effect(companies[id], "offices*") - 1.0) * 5.0
	return Balance.TELECOM_OFFICE_DEMAND * business_fiber * boost


## Assessed value of towers and fiber, for property tax.
func taxable_value() -> float:
	var v := 0.0
	for id in companies:
		var c: Dictionary = companies[id]
		v += c.towers.size() * Balance.TELECOM_TOWER_VALUE + fiber_m(c) * Balance.TELECOM_FIBER_VALUE_M
	return v


# ------------------------------------------------------------- the month

## A month's bills and costs for a company: [income, costs].
static func books(c: Dictionary) -> Array:
	var s: Dictionary = c.subs
	var income: float = float(s.fiber) * Balance.TELECOM_FIBER_ARPU + float(s.business) * Balance.TELECOM_BUSINESS_ARPU \
		+ float(s.fixed) * Balance.TELECOM_FIXED_ARPU + float(s.wireless) * Balance.TELECOM_WIRELESS_ARPU \
		+ monthly_grant(c)
	var costs: float = c.towers.size() * Balance.TELECOM_TOWER_MONTH \
		+ fiber_m(c) * Balance.TELECOM_FIBER_UPKEEP_M / 12.0 \
		+ Balance.TELECOM_OVERHEAD * (1.0 + 0.15 * c.blocks.size()) * (1.0 - 0.1 * float(c.leader.edu))
	return [income, costs]


## Every company takes its month: subscribers settle, the books close, and
## its manager strings fiber, puts up (or asks for) a tower and buys what
## the tree opens next. Returns true if anything on the map changed.
func decide(sim: CitySim) -> bool:
	var changed := false
	var ids := companies.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = companies[id]
		changed = _repair_fiber(sim, c) or changed
	_dirty = true
	refresh(sim)
	var corr := []
	for id in ids:
		var c: Dictionary = companies[id]
		var before := float(c.subs.fiber)
		_count_subs(sim, c)
		var new_installs := maxi(0, roundi(float(c.subs.fiber) - before))
		var m := books(c)
		c.savings += m[0] - m[1]
		var stance: String = sim.permits.guidance("telecom", id).stance
		var idle := ""
		if c.savings < -Balance.TELECOM_MAX_DEBT * 1.5 and not c.blocks.is_empty():
			# Deep in debt: it sells its newest block of land (and edge
			# pieces only that block held up).
			c.blocks.pop_back()
			c.savings += Balance.TELECOM_BLOCK_COST * 0.5
			BlockEdges.prune(sim, c, CELL)
			changed = true
		elif stance == "hold":
			idle = "Holding off, as you asked. It keeps what it has running."
		else:
			var h := horizon(sim, id, c)
			var built := _string_fiber(sim, id, c, h)
			if built > 0:
				changed = true
			if corr.is_empty():
				corr = RoadWins.corridors(sim.network, 2.0)
			var tw := _towers_step(sim, id, c, h, corr)
			changed = tw or changed
			# The tree, on the shared Agency model, paid from its own savings.
			c.facts = facts_of(sim, c)
			var profit := minf(yearly_profit(c), c.savings)
			if profit > 0.0:
				var node := Agency.develop(sim, c, TREE, c.pos, profit)
				if not node.is_empty():
					var art: String = node.get("land", "")
					if art != "" and not _buy_block(sim, id, c, node.id, corr):
						# Boxed in: no free land next door, so it waits.
						c.built.erase(node.id)
						c.why = ""
						idle = "Boxed in: no free land next to the office for %s." % Words.a(Words.mid(str(node.name)))
					else:
						c.savings -= float(node.cost)
						changed = true
						_dirty = true
			if built == 0 and not tw and idle == "" and c.pending.is_empty():
				idle = "No street or tower pays back yet in its %d-year plan." % roundi(h)
			# Boxed in by roads: lawn and a fenced yard up to the sidewalk.
			if BlockEdges.due(sim.tick_count, Balance.TELECOM_DECIDE_EVERY, id) and take_edges(sim, id):
				changed = true
		# Morning jobs: fiber and tower crews are queued by the builds;
		# install vans go to new subscribers.
		for i in mini(new_installs, 4):
			var home := _random_home(sim, hash([id, sim.tick_count, i]))
			if home != "":
				c.jobs.append({"to": [sim.lots[home].front.x, sim.lots[home].front.z], "what": "install"})
		if c.jobs.size() > 24:
			c.jobs = c.jobs.slice(c.jobs.size() - 24)
		if c.idle != idle:
			c.idle = idle
			changed = true
	if changed:
		_dirty = true
	return changed


func _count_subs(sim: CitySim, c: Dictionary) -> void:
	var take := Balance.TELECOM_FIBER_TAKE * effect(c, "take*")
	var s := {"fiber": 0.0, "business": 0.0, "fixed": 0.0, "wireless": 0.0}
	var fixed := has(c, "fixed_wireless")
	for key in served:
		if not sim.buildings.has(key):
			continue
		var b: Dictionary = sim.buildings[key]
		var sv: Dictionary = served[key]
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			var hh := _households(b)
			s.wireless += hh * float(sv.q)
			if sv.fiber:
				s.fiber += hh * take
			elif fixed and float(sv.q) >= 0.3:
				s.fixed += hh * Balance.TELECOM_FIXED_TAKE
		elif sv.fiber:
			s.business += Balance.TELECOM_BUSINESS_TAKE
	c.subs = s


## Roads can be split or rebuilt; fiber follows the street it was strung on.
func _repair_fiber(sim: CitySim, c: Dictionary) -> bool:
	var keep := []
	var lost := []
	for f in c.fiber:
		if sim.network.segments.has(int(f.seg)) and _same_street(sim, int(f.seg), f.pts):
			keep.append(f)
		else:
			lost.append(f)
	if lost.is_empty():
		return false
	var have := {}
	for f in keep:
		have[int(f.seg)] = true
	var ids := sim.network.segments.keys()
	ids.sort()
	for seg in ids:
		if have.has(seg):
			continue
		var pts := _seg_pts(sim, seg)
		var mid: Array = pts[pts.size() / 2]
		for f in lost:
			if _near_line(Vector2(mid[0], mid[1]), f.pts, 3.0):
				keep.append({"seg": seg, "pts": pts})
				have[seg] = true
				break
	c.fiber = keep
	return true


func _same_street(sim: CitySim, seg: int, pts: Array) -> bool:
	var now := _seg_pts(sim, seg)
	return now.size() == pts.size() and Vector2(now[0][0], now[0][1]).distance_to(Vector2(pts[0][0], pts[0][1])) < 0.5 \
		and Vector2(now[-1][0], now[-1][1]).distance_to(Vector2(pts[-1][0], pts[-1][1])) < 0.5


static func _near_line(p: Vector2, pts: Array, tol: float) -> bool:
	for i in range(1, pts.size()):
		var a := Vector2(pts[i - 1][0], pts[i - 1][1])
		var b := Vector2(pts[i][0], pts[i][1])
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= tol:
			return true
	return false


static func _seg_pts(sim: CitySim, seg: int) -> Array:
	var out := []
	for p in sim.network.sample_segment(seg):
		out.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
	return out


## Strings fiber down the streets next to what it has, best payback first,
## as far as its crews get in a month. Returns the metres strung.
func _string_fiber(sim: CitySim, id: int, c: Dictionary, h: float) -> float:
	if sim.network.segments.is_empty():
		return 0.0
	# Households and businesses along each street.
	var along := {}
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var seg := int(sim.lots[key].get("seg", -1))
		var b: Dictionary = sim.buildings[key]
		var a: Array = along.get(seg, [0.0, 0])
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			a[0] += _households(b)
		else:
			a[1] += 1
		along[seg] = a
	var have := {}
	var nodes := {}
	for f in c.fiber:
		have[int(f.seg)] = true
		var s: Dictionary = sim.network.segments.get(int(f.seg), {})
		if not s.is_empty():
			nodes[int(s.a)] = true
			nodes[int(s.b)] = true
	if have.is_empty():
		var near := RoadIndex.segment_near(sim.network, c.pos + c.dir * (CELL * 0.5), 120.0)
		if near.is_empty():
			return 0.0
		nodes[int(sim.network.segments[near.seg].a)] = true
		nodes[int(sim.network.segments[near.seg].b)] = true
	var take := Balance.TELECOM_FIBER_TAKE * effect(c, "take*")
	var per_m := Balance.TELECOM_FIBER_PER_M * effect(c, "fiber_cost*")
	var room := crews(c) * Balance.TELECOM_FIBER_M_PER_CREW
	if sim.permits.guidance("telecom", id).stance == "grow":
		room *= 1.25
	var strung := 0.0
	var ids := sim.network.segments.keys()
	ids.sort()
	var cap := -Balance.TELECOM_MAX_DEBT * (1.0 - 0.5 * float(c.leader.caution))
	# Each street: [pts, monthly revenue less upkeep, cost to string it].
	var info := {}
	var at_node := {}
	for seg in ids:
		var s: Dictionary = sim.network.segments[seg]
		for n in [int(s.a), int(s.b)]:
			if not at_node.has(n):
				at_node[n] = []
			at_node[n].append(seg)
		if have.has(seg):
			continue
		var a: Array = along.get(seg, [0.0, 0])
		var pts := _seg_pts(sim, seg)
		var len := _poly_len(pts)
		info[seg] = [pts, a[0] * take * Balance.TELECOM_FIBER_ARPU
			+ a[1] * Balance.TELECOM_BUSINESS_TAKE * Balance.TELECOM_BUSINESS_ARPU
			- len * Balance.TELECOM_FIBER_UPKEEP_M / 12.0,
			len * per_m + a[0] * take * Balance.TELECOM_FIBER_DROP, a[0] > 0.0 or a[1] > 0]
	for _round in 12:
		# Cheapest way out from the network to every corner (Dijkstra), so a
		# dense street a few blocks off is reached through the streets between.
		var dist := {}
		var via := {}
		var open := []
		for n in nodes:
			dist[n] = 0.0
			open.append(n)
		while not open.is_empty():
			var bi := 0
			for k in range(1, open.size()):
				if dist[open[k]] < dist[open[bi]] or (dist[open[k]] == dist[open[bi]] and open[k] < open[bi]):
					bi = k
			var n: int = open[bi]
			open.remove_at(bi)
			if dist[n] > room * per_m * 2.0:
				continue
			for seg in at_node.get(n, []):
				if not info.has(seg):
					continue
				var s: Dictionary = sim.network.segments[seg]
				var o: int = int(s.b) if int(s.a) == n else int(s.a)
				var d: float = dist[n] + float(info[seg][2])
				if d < float(dist.get(o, INF)) - 0.001:
					if not dist.has(o):
						open.append(o)
					dist[o] = d
					via[o] = [seg, n]
		var best := []
		var best_ratio := 1.0
		for seg in info:
			if not info[seg][3]:
				continue
			var s: Dictionary = sim.network.segments[seg]
			var from: int = int(s.a) if float(dist.get(int(s.a), INF)) <= float(dist.get(int(s.b), INF)) else int(s.b)
			if not dist.has(from):
				continue
			var path := [seg]
			var n := from
			while via.has(n) and not nodes.has(n):
				path.append(via[n][0])
				n = via[n][1]
			var month := 0.0
			var cost := 0.0
			for q in path:
				month += float(info[q][1])
				cost += float(info[q][2])
			var ratio := month * 12.0 * h / maxf(cost, 1.0)
			if ratio > best_ratio + 0.0001 or (absf(ratio - best_ratio) <= 0.0001 and not best.is_empty() and seg < best[0]):
				best_ratio = ratio
				best = path
		if best.is_empty() or strung >= room:
			break
		var total := 0.0
		for q in best:
			total += float(info[q][2])
		if c.savings - total < cap:
			break
		best.reverse()  # from the network outward, the way crews work
		for q in best:
			var pts: Array = info[q][0]
			c.fiber.append({"seg": q, "pts": pts})
			c.savings -= float(info[q][2])
			have[q] = true
			var s2: Dictionary = sim.network.segments[q]
			nodes[int(s2.a)] = true
			nodes[int(s2.b)] = true
			strung += _poly_len(pts)
			c.jobs.append({"to": pts[pts.size() / 2], "what": "fiber"})
			info.erase(q)
	return strung


## Puts up an approved tower, or files the next one where it would pay.
func _towers_step(sim: CitySim, id: int, c: Dictionary, h: float, corr: Array) -> bool:
	if not c.pending.is_empty():
		var st := sim.permits.state_of(int(c.pending.req))
		if st == Permits.State.APPROVED:
			# The player may have dragged the compound somewhere else.
			var p: Array = c.pending.pos
			var outline: Array = sim.permits.requests[int(c.pending.req)].route
			if outline.size() >= 3:
				var mid := Vector2.ZERO
				for q in outline:
					mid += Vector2(q[0], q[1])
				mid /= outline.size()
				p = [snappedf(mid.x, 0.01), snappedf(mid.y, 0.01)]
			var kind: String = c.pending.kind
			var cost := float(TOWERS[kind].cost)
			if tower_problem(sim, id, Vector2(p[0], p[1]), corr) == "":
				c.towers.append({"pos": p, "kind": kind, "built": sim.tick_count})
				c.savings -= cost
				c.jobs.append({"to": p, "what": "tower"})
				sim.permits.done(int(c.pending.req))
				c.pending = {}
				_dirty = true
				return true
			sim.permits.withdraw(int(c.pending.req))
			c.pending = {}
		elif st in [Permits.State.OPEN, Permits.State.SHELVED]:
			return false
		else:
			if st == Permits.State.DENIED:
				c.refused.append(c.pending.pos)
			c.pending = {}
	if not sim.permits.can_file(sim, "telecom", id):
		return false
	var plan := best_tower(sim, id, c, h, corr)
	if plan.is_empty():
		return false
	var cap := -Balance.TELECOM_MAX_DEBT * (1.0 - 0.5 * float(c.leader.caution))
	if c.savings - float(TOWERS[plan.kind].cost) < cap:
		return false
	var p2: Vector2 = plan.pos
	# A cell site is a land-use change, as at a real county board of zoning
	# appeals: the player sees the compound's outline and can move it.
	var area := []
	for q in compound(p2):
		area.append([q.x, q.y])
	var req := sim.permits.file(sim, {"hub": "telecom", "hub_id": id, "leader": leader_name(c.leader),
		"title": "New %s" % TOWERS[plan.kind].name, "change": "Open land to a cell tower site",
		"why": "About %d households near here get one bar or none. This tower would fix that, and pays for itself in about %d years." \
			% [roundi(plan.poor), maxi(1, roundi(plan.payback))],
		"area": area, "base": int(TOWERS[plan.kind].cost), "per_m2": 0, "budget": int(TOWERS[plan.kind].cost)})
	if req == -1:
		return false
	c.pending = {"req": req, "pos": [p2.x, p2.y], "kind": plan.kind}
	return true


## The tower that would pay back best, or {}: {pos, kind, poor, payback}.
func best_tower(sim: CitySim, id: int, c: Dictionary, h: float, corr: Array) -> Dictionary:
	# Households that get poor service, with how much they're missing.
	var poor := []
	var keys := served.keys()
	keys.sort()
	for key in keys:
		if not sim.buildings.has(key) or int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL:
			continue
		var hh := _households(sim.buildings[key])
		var q: float = served[key].q
		if hh > 0.0 and q < Balance.TELECOM_GOOD_SIGNAL:
			var p: Vector3 = sim.lots[key].pos
			poor.append([Vector2(p.x, p.z), hh, q])
	if poor.is_empty():
		return {}
	var step := maxi(1, poor.size() / 160)
	var best := {}
	var best_ratio := 1.0
	for i in range(0, poor.size(), step):
		var center: Vector2 = poor[i][0]
		var dense := 0.0
		for e in poor:
			if e[0].distance_to(center) < 1_500.0:
				dense += e[1]
		var kind := "monopole" if dense > 300.0 else "lattice"
		var site := _tower_site(sim, id, c, center, corr)
		if site == Vector2.INF:
			continue
		if kind == "monopole" and has(c, "stealth") and _homes_within(sim, site, 250.0):
			kind = "monopine"
		var t := {"pos": [site.x, site.y], "kind": kind}
		var gain := 0.0
		var count := 0.0
		for e in poor:
			var s := signal_of(t, e[0])
			if s > e[2]:
				gain += e[1] * (s - e[2])
				count += e[1]
		gain = minf(gain, float(TOWERS[kind].capacity) * effect(c, "capacity*"))
		var month := gain * Balance.TELECOM_WIRELESS_ARPU - Balance.TELECOM_TOWER_MONTH
		var cost := float(TOWERS[kind].cost)
		var ratio := month * 12.0 * h / cost
		if ratio > best_ratio + 0.0001:
			best_ratio = ratio
			best = {"pos": site, "kind": kind, "poor": count, "payback": cost / maxf(month * 12.0, 1.0)}
	return best


func _homes_within(sim: CitySim, p: Vector2, r: float) -> bool:
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			var q: Vector3 = sim.lots[key].pos
			if Vector2(q.x, q.z).distance_to(p) < r:
				return true
	return false


## A free spot for a tower near `center`: open, unzoned ground near a road,
## away from other towers and from spots the player turned down.
func _tower_site(sim: CitySim, id: int, c: Dictionary, center: Vector2, corr: Array) -> Vector2:
	for ring in [0.0, 60.0, 120.0, 200.0, 300.0, 420.0]:
		var n := 1 if ring == 0.0 else 8
		for k in n:
			var a := TAU * k / n
			var p: Vector2 = (center + Vector2(cos(a), sin(a)) * float(ring)).snapped(Vector2(0.01, 0.01))
			if tower_problem(sim, id, p, corr) == "":
				return p
	return Vector2.INF


## Why a tower can't stand here, or "".
func tower_problem(sim: CitySim, id: int, p: Vector2, corr: Array) -> String:
	var poly := compound(p)
	if RoadWins.hits(corr, poly):
		return "On a road."
	if RoadIndex.segment_near(sim.network, Vector3(p.x, 0.0, p.y), Balance.TELECOM_TOWER_ROAD).is_empty():
		return "No road near for its drive."
	for oid in companies:
		for t in companies[oid].towers:
			if Vector2(t.pos[0], t.pos[1]).distance_to(p) < Balance.TELECOM_TOWER_SPACING:
				return "Too close to another tower."
	for r in companies[id].refused:
		if Vector2(r[0], r[1]).distance_to(p) < 300.0:
			return "You turned a tower down here."
	var mid := Vector3(p.x, 0.0, p.y)
	for q in _probe_points(mid, poly):
		if ground_problem(sim, q) != "" or at(q) != -1:
			return "Something stands there."
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if not sim.buildings.has(key) and sim.zones.zone_at(lot.zone_pt) == ZoneMap.Zone.NONE:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(lot.pos.x, lot.pos.z), poly) \
				or Vector2(lot.pos.x, lot.pos.z).distance_to(p) < Balance.TELECOM_COMPOUND:
			return "A lot is there."
	return ""


## Buys the free block next to the office that keeps it most compact.
func _buy_block(sim: CitySim, id: int, c: Dictionary, use: String, corr: Array) -> bool:
	if c.blocks.size() >= Balance.TELECOM_MAX_BLOCKS:
		return _build_up(c, use)
	var best := Vector2i.MAX
	var best_score := -INF
	for cell in _frontier(c):
		if not usable(sim, id, c, cell, corr):
			continue
		var score := 2.0 * _neighbors(c, cell) - Vector2(cell).length()
		if score > best_score + 0.001:
			best_score = score
			best = cell
	if best == Vector2i.MAX:
		return _build_up(c, use)
	c.blocks.append({"c": best, "use": use, "levels": 1})
	# An edge piece a road has since let go of becomes a whole block.
	c.get("edge", {}).erase(best)
	return true


## Boxed in: a building block of the same use rises a storey instead.
static func _build_up(c: Dictionary, use: String) -> bool:
	if not dev(use).get("land", "") in BUILDING_ARTS:
		return false
	for blk in c.blocks:
		if blk.use == use and int(blk.levels) < MAX_LEVELS:
			blk.levels += 1
			return true
	return false


## True when a block is free to buy: empty land nobody else holds, not
## zoned or built on, and no road.
func usable(sim: CitySim, id: int, c: Dictionary, cell: Vector2i, corr: Array) -> bool:
	var poly := block_corners(c, cell)
	if RoadWins.hits(corr, poly):
		return false
	var mid := block_center(c, cell)
	for p in _probe_points(mid, poly):
		var other := at(p)
		if (other != -1 and other != id) or ground_problem(sim, p) != "":
			return false
	for t in c.towers:
		if Geometry2D.intersect_polygons(poly, compound(Vector2(t.pos[0], t.pos[1]))).size() > 0:
			return false
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.NONE:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(sim.lots[key].pos.x, sim.lots[key].pos.z), poly) \
				or sim.lots[key].pos.distance_to(mid) < CELL * 0.5:
			return false
	return true


static func _frontier(c: Dictionary) -> Array:
	var have := {Vector2i.ZERO: true}
	for blk in c.blocks:
		have[blk.c] = true
	var out := []
	var seen := {}
	for cell in c.get("cleared", []):
		seen[cell] = true
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


static func _cell_of(c: Dictionary, p: Vector3) -> Vector2i:
	var d: Vector3 = p - c.pos
	return Vector2i(roundi(d.dot(_right(c)) / CELL), roundi(-d.dot(c.dir) / CELL))


## The company with its office, a block, an edge piece or a tower on this
## point, or -1.
func at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in companies:
		var c: Dictionary = companies[id]
		var cell := _cell_of(c, p)
		var found := cell == Vector2i.ZERO
		for blk in c.blocks:
			found = found or blk.c == cell
		if found and Geometry2D.is_point_in_polygon(q, block_corners(c, cell)):
			return id
		if not found and c.edge.has(cell) and BlockEdges.on_edge(c, CELL, p):
			return id
		if tower_at(id, q) != -1:
			return id
	return -1


## The index of a company's tower whose compound holds `q`, or -1.
func tower_at(id: int, q: Vector2) -> int:
	var c: Dictionary = companies[id]
	for i in c.towers.size():
		var t: Vector2 = Vector2(c.towers[i].pos[0], c.towers[i].pos[1])
		if absf(q.x - t.x) <= Balance.TELECOM_COMPOUND * 0.5 and absf(q.y - t.y) <= Balance.TELECOM_COMPOUND * 0.5:
			return i
	return -1


func covers(p: Vector3) -> bool:
	return not companies.is_empty() and at(p) != -1


## All the ground the office holds, as outlines (x, z): its own block, each
## block it bought, then each edge piece (not its towers).
static func land_polys(c: Dictionary) -> Array:
	var out := [block_corners(c, Vector2i.ZERO)]
	for blk in c.blocks:
		out.append(block_corners(c, blk.c))
	return out + BlockEdges.edge_polys(c, CELL)


## Takes the edge pieces that fit round company `id`'s office, up to the
## sidewalk.
func take_edges(sim: CitySim, id: int) -> bool:
	var c: Dictionary = companies[id]
	# Its own towers' fenced yards (the office's pokes a metre past its
	# block) stay as they are: the pieces are cut round them.
	var towers := func(parts: Array) -> Array:
		for t in c.towers:
			parts = BlockEdges.cut_out(parts, compound(Vector2(t.pos[0], t.pos[1])))
		return parts
	return BlockEdges.take(sim, c, CELL, func(world: PackedVector2Array) -> String:
		for t in c.towers:
			for q in Geometry2D.intersect_polygons(world, compound(Vector2(t.pos[0], t.pos[1]))):
				if CivicHubs.area(q) > 0.5:
					return "A tower stands there."
		return BlockEdges.ground_problem(sim, world, CELL * 0.2), towers)


## Edge pieces cut back to the roads as they are now, and any no longer
## joined to the office's blocks gone (after a road, or a block cleared).
func prune_edges(sim: CitySim) -> bool:
	var changed := false
	var ids := companies.keys()
	ids.sort()
	for id in ids:
		changed = BlockEdges.prune(sim, companies[id], CELL) or changed
	return changed


## The player clears what stands here: a tower, a block, or (the office
## itself) the whole company. Returns true if anything went.
func remove_at(p: Vector3) -> bool:
	var id := at(p)
	if id == -1:
		return false
	var c: Dictionary = companies[id]
	var ti := tower_at(id, Vector2(p.x, p.z))
	if ti != -1:
		var t: Dictionary = c.towers[ti]
		c.towers.remove_at(ti)
		# Its manager won't put one straight back.
		c.refused.append(t.pos)
		_dirty = true
		return true
	# An edge piece: it goes, and its manager won't take it straight back.
	if BlockEdges.clear_at(c, CELL, p):
		return true
	var cell := _cell_of(c, p)
	if cell == Vector2i.ZERO:
		companies.erase(id)
		_dirty = true
		return true
	for blk in c.blocks:
		if blk.c == cell:
			c.blocks.erase(blk)
			c.cleared.append(cell)
			return true
	return false


## The road wins: a road through the office closes the company and pays the
## city back; through a block or a tower's compound, that goes.
func make_way(corr: Array) -> int:
	var back := 0
	var ids := companies.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = companies[id]
		if RoadWins.hits(corr, block_corners(c, Vector2i.ZERO)):
			back += Balance.TELECOM_COST
			companies.erase(id)
			continue
		for blk in c.blocks.duplicate():
			if RoadWins.hits(corr, block_corners(c, blk.c)):
				c.blocks.erase(blk)
		for t in c.towers.duplicate():
			if RoadWins.hits(corr, compound(Vector2(t.pos[0], t.pos[1]))):
				c.towers.erase(t)
	_dirty = true
	return back


## Where its trucks pull out: the middle of the office's road frontage.
static func front(c: Dictionary) -> Vector3:
	return c.pos + c.dir * (CELL * 0.5)


func _random_home(sim: CitySim, h: int) -> String:
	var homes := []
	for key in served:
		if served[key].fiber and sim.buildings.has(key) and int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			homes.append(key)
	if homes.is_empty():
		return ""
	homes.sort()
	return homes[absi(h) % homes.size()]


## Weekday mornings the crews head out to the day's jobs (fiber to string,
## a tower to raise, a new subscriber to hook up) and come back to the
## garage in the afternoon. Real trips through the traffic simulation.
func trips(sim: CitySim) -> void:
	if companies.is_empty():
		return
	var t := sim.clock()
	if t.weekday == 0 or t.weekday == 6:
		return
	var minute: int = t.hour * 60 + t.minute
	if minute < 420 or minute > 1000:
		return
	var ids := companies.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = companies[id]
		var base := {"ref": "telecom:%d" % id, "pos": [front(c).x, front(c).z]}
		var n := mini(c.jobs.size(), 8)
		for i in n:
			var job: Dictionary = c.jobs[i]
			var there := {"ref": "job", "pos": job.to}
			if minute == 425 + i * 5:
				sim.traffic.dispatch(base, there, "telecom", {"what": job.what})
			elif minute == 935 + i * 5:
				sim.traffic.dispatch(there, base, "telecom")
		if minute == 935 + n * 5 + 1 and n > 0:
			c.jobs = c.jobs.slice(n)


func to_dict() -> Dictionary:
	var out := {}
	for id in companies:
		var c: Dictionary = companies[id]
		var blocks := []
		for blk in c.blocks:
			blocks.append([blk.c.x, blk.c.y, blk.use, blk.levels])
		out[str(id)] = {"pos": [c.pos.x, c.pos.z], "dir": [c.dir.x, c.dir.z], "blocks": blocks,
			"built": c.built, "why": c.why, "towers": c.towers, "fiber": c.fiber, "funding": c.funding,
			"savings": c.savings, "leader": c.leader, "subs": c.subs, "pending": c.pending,
			"refused": c.refused, "jobs": c.jobs, "founded": c.founded,
			"cleared": c.cleared.map(func(v): return [v.x, v.y])}
		if not c.get("edge", {}).is_empty():
			out[str(id)].edge = CivicHubs.edge_to_save(c.edge)
	return {"companies": out, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	companies.clear()
	for k in d.get("companies", {}):
		var s: Dictionary = d.companies[k]
		var blocks := []
		for b in s.get("blocks", []):
			blocks.append({"c": Vector2i(int(b[0]), int(b[1])), "use": str(b[2]), "levels": int(b[3])})
		var l: Dictionary = s.get("leader", {})
		var towers := []
		for t in s.get("towers", []):
			if TOWERS.has(str(t.kind)):
				towers.append({"pos": [float(t.pos[0]), float(t.pos[1])], "kind": str(t.kind), "built": int(t.get("built", 0))})
		var fiber := []
		for f in s.get("fiber", []):
			fiber.append({"seg": int(f.seg), "pts": f.pts.map(func(p): return [float(p[0]), float(p[1])])})
		var subs: Dictionary = s.get("subs", {})
		var pend: Dictionary = s.get("pending", {})
		companies[int(k)] = {"pos": Vector3(s.pos[0], 0.0, s.pos[1]),
			"dir": BlockEdges.unit(Vector3(s.dir[0], 0.0, s.dir[1])), "blocks": blocks,
			"built": s.get("built", []).map(func(u): return str(u)), "why": str(s.get("why", "")), "towers": towers,
			"fiber": fiber,
			"funding": int(s.get("funding", 2)), "savings": float(s.get("savings", 0.0)),
			"leader": {"name": str(l.get("name", "Pat Lee")), "edu": float(l.get("edu", 0.5)),
				"caution": float(l.get("caution", 0.5)), "ambition": float(l.get("ambition", 0.5))},
			"subs": {"fiber": float(subs.get("fiber", 0.0)), "business": float(subs.get("business", 0.0)),
				"fixed": float(subs.get("fixed", 0.0)), "wireless": float(subs.get("wireless", 0.0))},
			"pending": {} if pend.is_empty() else {"req": int(pend.req), "pos": [float(pend.pos[0]), float(pend.pos[1])],
				"kind": str(pend.kind)},
			"refused": s.get("refused", []).map(func(p): return [float(p[0]), float(p[1])]),
			"jobs": s.get("jobs", []).map(func(j): return {"to": [float(j.to[0]), float(j.to[1])], "what": str(j.what)}),
			"founded": int(s.get("founded", 0)), "idle": "",
			"cleared": s.get("cleared", []).map(func(v): return Vector2i(int(v[0]), int(v[1]))),
			"edge": BlockEdges.from_save(s.get("edge", []), blocks)}
	_next_id = int(d.get("next_id", 1))
	_dirty = true
