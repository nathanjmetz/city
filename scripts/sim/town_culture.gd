class_name TownCulture
extends RefCounted
## What kind of town this is, and where it's heading (Brawn's core idea,
## 2026-10-22: hub leaders plus a culture that drifts let a town change
## identity over the years, a coal town turning into a college town, say,
## always through permits the player approves).
##
## Measured the way economic developers do it: an economic-base analysis
## of where the town's jobs are, by sector, as location quotients (LQ = the
## town's share of jobs in a sector over the US share). A sector with an LQ
## of 1.25 or more is one the town specialises in and "exports"; the
## strongest one names the town: Petersburg, Indiana is a coal town, Jasper
## a furniture-mill town, Bloomington a college town.
##
## Culture follows the jobs slowly (a half-life of years), so a town keeps
## its character for a while after the work changes, as real towns do. A
## sector the town is known for pulls its leaders forward: skilled workers,
## suppliers and lenders who know the trade are already here (Marshall's
## agglomeration economies), so they'll buy land on thinner margins. A
## sector the town has drifted away from finds it harder.
## Plain data, updated once a game day in the tick, so every copy agrees.

signal changed

## Sectors, with the US share of jobs in each (BLS Current Employment
## Statistics and QCEW, 2023, rounded) and what a town that specialises in
## it is called.
const SECTORS := {
	"farm": {"us": 0.015, "name": "Farm town"},
	"mining": {"us": 0.004, "name": "Gravel and gas town"},
	"timber": {"us": 0.005, "name": "Timber town"},
	"manufacturing": {"us": 0.083, "name": "Mill town"},
	"trade": {"us": 0.21, "name": "Market town"},
	"office": {"us": 0.22, "name": "Banking and office center"},
	"campus": {"us": 0.16, "name": "College and hospital town"},
	"transport": {"us": 0.045, "name": "Railroad and power town"},
}

## How a town changes identity on the ground: when a trade is rising and
## its zoned land has run out, a local developer buys the farm ground along
## a road at the edge of town and asks to rezone it, like the office parks
## and industrial parks built on corn ground around real Midwest towns
## (Carmel and Fishers, Indiana; Jasper's industrial park). The player
## approves, denies or drags the boundary on the permit bell.
## sector -> [zone it needs, the change on the permit, what gets built].
const CONVERTS := {
	"office": [ZoneMap.Zone.COMMERCIAL, "Farmland to offices", "an office park"],
	"trade": [ZoneMap.Zone.COMMERCIAL, "Farmland to shops", "a shopping strip"],
	"manufacturing": [ZoneMap.Zone.INDUSTRIAL, "Farmland to an industrial park", "an industrial park"],
}
## The permit bell's name for the developer.
const HUB := "developer"

var shares := {}       # sector -> smoothed share of the town's jobs (0..1)
var now := {}          # sector -> share of the town's jobs today (not saved)
var identity := ""     # the sector the town is known for ("" while too small)
var since := 0         # game day the town took on its identity
var _day := -1


## The town's jobs by sector, right now.
static func jobs_by_sector(sim) -> Dictionary:
	var out := {}
	for k in SECTORS:
		out[k] = 0
	out.farm = sim.farms.jobs()
	for id in sim.industry.sites:
		var s: Dictionary = sim.industry.sites[id]
		var k: Dictionary = Balance.INDUSTRY[s.kind]
		out["timber" if s.kind == "forest" else "mining"] += int(k.jobs_hq) + int(k.jobs_pad) * s.pads.size()
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		match int(b.zone):
			ZoneMap.Zone.INDUSTRIAL:
				out.manufacturing += int(b.cap)
			ZoneMap.Zone.COMMERCIAL:
				if BuildingTypes.type_of(b) == "office":
					out.office += int(b.cap)
				else:
					out.trade += int(b.cap)
	out.manufacturing += sim.warehouses.jobs()
	out.office += sim.banks.jobs() + sim.telecom.jobs()
	out.campus += sim.education.jobs() + sim.healthcare.jobs(sim)
	out.transport += sim.power.jobs() + sim.rail.jobs()
	return out


## Once a game day: culture drifts toward where the jobs are.
func update(sim, day: int) -> void:
	if day == _day:
		return
	var steps := 1 if _day < 0 else day - _day
	_day = day
	var jobs := jobs_by_sector(sim)
	var total := 0
	for k in jobs:
		total += int(jobs[k])
	if total < Balance.CULTURE_MIN_JOBS:
		return
	# Half the gap closes in CULTURE_HALF_LIFE_DAYS; a brand-new town takes
	# its first character straight from its jobs.
	var keep := pow(0.5, float(steps) / Balance.CULTURE_HALF_LIFE_DAYS) if not shares.is_empty() else 0.0
	for k in SECTORS:
		now[k] = float(jobs[k]) / total
		shares[k] = float(shares.get(k, now[k])) * keep + now[k] * (1.0 - keep)
	var best := ""
	var best_lq := Balance.CULTURE_SPECIALISED_LQ
	for k in SECTORS:
		var q := lq(k)
		# A known identity holds until another sector clearly passes it.
		if k == identity:
			q += Balance.CULTURE_HOLD_LQ
		if q > best_lq:
			best_lq = q
			best = k
	if best != identity:
		identity = best
		since = day
		changed.emit()


## Location quotient: how much more of the town works in `sector` than the
## US does (1.0 = the national mix). 1.0 until the town has a culture.
func lq(sector: String) -> float:
	if shares.is_empty() or not SECTORS.has(sector):
		return 1.0
	return float(shares[sector]) / float(SECTORS[sector].us)


## How strongly the town pulls this sector forward, -1 (drifted away) to
## +1 (what the town is known for). LQs are compared on a log scale, as a
## town with 4x the US share is as specialised as one with a quarter of it
## is lacking.
func pull(sector: String) -> float:
	return clampf(log(maxf(lq(sector), 0.01)) / log(Balance.CULTURE_FULL_PULL_LQ), -1.0, 1.0)


## How fast a sector is rising: today's share of jobs over the share the
## town is known for, less one (0.2 = a fifth more than its reputation).
func momentum(sector: String) -> float:
	if not now.has(sector) or float(shares.get(sector, 0.0)) <= 0.0:
		return 0.0
	return float(now[sector]) / float(shares[sector]) - 1.0


## Once a game day, after update(): a developer carries out an approved
## rezoning, or, when a rising trade has run out of zoned land, asks for
## the farm ground it needs. True if the town changed.
func develop(sim) -> bool:
	var did := false
	for req in sim.permits.approved(HUB, 1):
		_rezone(sim, req)
		sim.permits.done(int(req.id))
		did = true
	if shares.is_empty() or not sim.permits.can_file(sim, HUB, 1):
		return did
	var best := ""
	var best_score := 0.0
	for k in CONVERTS:
		var zone: int = CONVERTS[k][0]
		var score := pull(k) + momentum(k)
		if score <= Balance.CULTURE_DEVELOP_SCORE or sim.demand.get(zone, 0.0) < Balance.CULTURE_DEVELOP_DEMAND \
				or _free_lots(sim, zone) >= Balance.CULTURE_DEVELOP_FREE_LOTS:
			continue
		if score > best_score:
			best_score = score
			best = k
	if best == "":
		return did
	var site := _farm_frontage(sim)
	if site.is_empty():
		return did
	var outline: Array = site.outline
	var area := 0.0
	var poly := PackedVector2Array()
	for p in outline:
		poly.append(Vector2(p[0], p[1]))
	area = absf(_area(poly))
	var farm: Dictionary = sim.farms.farms[int(site.farm)]
	var owner: String = sim.families.name_of("farm:%d" % int(site.farm))
	var why := "%s is %s now, and there's no %s land left to build on. %s along %s is for sale." % [
		"Town" if identity == "" else "The town", _known_as(best), ZoneMap.NAMES[CONVERTS[best][0]].to_lower(),
		owner if owner != "" else "A %s farm" % str(farm.crop), site.road]
	sim.permits.file(sim, {"hub": HUB, "hub_id": 1, "leader": Names.person(hash([since, site.farm]), Names.surname(hash(site.farm))),
		"title": "A developer wants to build %s" % CONVERTS[best][2], "why": why,
		"change": CONVERTS[best][1], "area": outline, "per_m2": Balance.CULTURE_FARMLAND_PER_M2,
		"base": roundi(area * Balance.CULTURE_FARMLAND_PER_M2), "sector": best})
	return did


## How the permit says what the town is turning into.
func _known_as(sector: String) -> String:
	if sector == identity:
		return "known for its %s" % ("offices" if sector == "office" else "shops" if sector == "trade" else "factories")
	return "growing %s fast" % ("offices" if sector == "office" else "shops" if sector == "trade" else "factories")


## Zoned lots of this zone with nothing built on them yet.
static func _free_lots(sim, zone: int) -> int:
	var n := 0
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == zone:
			n += 1
	return n


## The best run of farm field along a road at the edge of town:
## {farm, outline [[x, z], ...], road}, or {} when there's none. The
## outline is a strip one deep lot back from the road.
##
## Real rules (Brawn: towns grow the way real towns do): a developer buys
## the farm next to town, not one out in the country, because Indiana only
## lets a town annex land that touches it (IC 36-4-3-13 asks for an eighth
## of the boundary) and water and sewer lines run out from the town's edge.
## Shops and offices front a paved through road, never a gravel farm road
## or a freeway (no driveways on a limited-access road), and a project goes
## in one phase at a time, about a quarter mile of frontage.
static func _farm_frontage(sim) -> Dictionary:
	var centre := Vector3.ZERO
	var n := 0
	# The built-up town on a 100 m grid, to tell the edge of town.
	var built := {}
	for key in sim.buildings:
		if sim.lots.has(key):
			var p: Vector3 = sim.lots[key].pos
			centre += p
			n += 1
			built[Vector2i(floori(p.x / 100.0), floori(p.z / 100.0))] = true
	if n == 0:
		return {}
	centre /= n
	# Farm fields on the same grid, so only roads beside a field are looked
	# at closely (finding the field under a point is the slow part).
	var fields := {}
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		for c in f.cells:
			var q := Farms.cell_center(f, c)
			fields[Vector2i(floori(q.x / 100.0), floori(q.z / 100.0))] = true
	if fields.is_empty():
		return {}
	var by_town := func(p: Vector3) -> bool:
		return _near(built, p, 1)
	var by_field := func(p: Vector3, r: int) -> bool:
		return _near(fields, p, r)
	var best := {}
	var best_score := -INF
	var ids: Array = sim.network.segments.keys()
	ids.sort()
	for seg in ids:
		var type := int(sim.network.segments[seg].get("type", 0))
		# Nothing fronts a freeway or its ramps, an alley or a gravel farm road.
		if type in [RoadStyle.Type.HIGHWAY, RoadStyle.Type.RAMP, RoadStyle.Type.RAMP2, RoadStyle.Type.FREEWAY2,
				RoadStyle.Type.FREEWAY4, RoadStyle.Type.ALLEY, RoadStyle.Type.GRAVEL]:
			continue
		var rough: PackedVector3Array = sim.network.sample_segment(seg, 8)
		var near_town := false
		var near_field := false
		for q in rough:
			near_town = near_town or _near(built, q, 2)
			near_field = near_field or by_field.call(q, 2)
		if not (near_town and near_field):
			continue
		var length := 0.0
		for i in range(1, rough.size()):
			length += rough[i].distance_to(rough[i - 1])
		var pts: PackedVector3Array = sim.network.sample_segment(seg, clampi(int(length / 10.0), 8, 200))
		var hw: float = RoadStyle.right_of_way_half(type)
		for side in [-1.0, 1.0]:
			var run := []
			var farm := -1
			for i in pts.size():
				var a: Vector3 = pts[maxi(i - 1, 0)]
				var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
				var t := (b - a)
				t.y = 0.0
				var nrm: Vector3 = Vector3(-t.z, 0.0, t.x).normalized() * side
				var probe: Vector3 = pts[i] + nrm * (hw + Balance.CULTURE_FRONTAGE_DEPTH * 0.75)
				var f: int = sim.farms.field_at(probe) if by_field.call(probe, 1) else -1
				var ok: bool = f != -1 and (farm == -1 or f == farm) and sim.zones.zone_at(probe) == ZoneMap.Zone.NONE
				if ok:
					farm = f
					run.append([pts[i], nrm])
				if (not ok or i == pts.size() - 1) and not run.is_empty():
					run = _phase(run, by_town)
					var span := 0.0 if run.is_empty() else (run[-1][0] as Vector3).distance_to(run[0][0])
					if span >= Balance.CULTURE_FRONTAGE_MIN:
						var mid: Vector3 = run[run.size() / 2][0]
						# The nearest the middle of town, on the busiest road.
						var through := 0.0 if type in [RoadStyle.Type.STREET, RoadStyle.Type.STREET_NARROW,
							RoadStyle.Type.STREET_BIKE, RoadStyle.Type.STREET_ONEWAY] else 150.0
						var score := span * 0.25 + through - mid.distance_to(centre)
						if score > best_score:
							best_score = score
							var inner := []
							var outer := []
							for r in run:
								var p: Vector3 = r[0] + r[1] * (hw + 1.0)
								var q: Vector3 = r[0] + r[1] * (hw + 1.0 + Balance.CULTURE_FRONTAGE_DEPTH)
								inner.append([snappedf(p.x, 0.1), snappedf(p.z, 0.1)])
								outer.append([snappedf(q.x, 0.1), snappedf(q.z, 0.1)])
							outer.reverse()
							var sname: String = sim.streets.name_of(seg)
							best = {"farm": farm, "outline": inner + outer, "road": sname if sname != "" else "the road"}
					run = []
					farm = f if f != -1 and sim.zones.zone_at(probe) == ZoneMap.Zone.NONE else -1
					if farm != -1:
						run.append([pts[i], nrm])
	return best


## True when a grid square within r squares of p is in `grid` (100 m squares).
static func _near(grid: Dictionary, p: Vector3, r: int) -> bool:
	var c := Vector2i(floori(p.x / 100.0), floori(p.z / 100.0))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if grid.has(c + Vector2i(dx, dz)):
				return true
	return false


## The part of a run of frontage a developer would take: it starts where
## the run touches the built-up town and reaches one phase
## (CULTURE_FRONTAGE_MAX) along the road. Empty when it doesn't touch town.
static func _phase(run: Array, by_town: Callable) -> Array:
	var k := -1
	for i in run.size():
		if by_town.call(run[i][0]):
			k = i
			break
	if k == -1:
		return []
	var lo := k
	var hi := k
	var span := 0.0
	while span < Balance.CULTURE_FRONTAGE_MAX and (lo > 0 or hi < run.size() - 1):
		# Grow along the road on whichever side keeps it closest to town.
		if hi < run.size() - 1 and (lo == 0 or by_town.call(run[hi + 1][0]) or not by_town.call(run[lo - 1][0])):
			hi += 1
		else:
			lo -= 1
		span = (run[hi][0] as Vector3).distance_to(run[lo][0])
	return run.slice(lo, hi + 1)


## Carries out an approved rezoning: the farm sells every field the outline
## touches, and the land is zoned for the trade that asked.
func _rezone(sim, req: Dictionary) -> void:
	var poly := PackedVector2Array()
	for p in req.route:
		poly.append(Vector2(p[0], p[1]))
	if poly.size() < 3:
		return
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var sector := ""
	for k in CONVERTS:
		if CONVERTS[k][1] == str(req.change):
			sector = k
	if sector == "":
		return
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var keep := []
		for c in f.cells:
			if Geometry2D.intersect_polygons(poly, Farms.cell_corners(f, c)).is_empty():
				keep.append(c)
		f.cells = keep
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var zone: int = CONVERTS[sector][0]
	var cell := ZoneMap.CELL
	for x in range(floori(lo.x / cell), ceili(hi.x / cell) + 1):
		for y in range(floori(lo.y / cell), ceili(hi.y / cell) + 1):
			if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) * cell, (y + 0.5) * cell), poly):
				sim.zones.cells[Vector2i(x, y)] = zone
	sim.zones.revision += 1
	sim.zones.dirty.append(Rect2(lo - Vector2.ONE * cell, hi - lo + Vector2.ONE * cell * 2.0))


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## What the town is called, e.g. "Gravel and gas town" ("" while too small).
func title() -> String:
	return SECTORS[identity].name if identity != "" else ""


## A player's answer to a leader on the bell leans the town's reputation
## (LeaderAsks, Heritage): say yes to the merchants and it is a little more
## a market town. It fades as the reputation follows the jobs again.
func nudge(sector: String, amount: float) -> void:
	if shares.is_empty() or not shares.has(sector):
		return
	shares[sector] = maxf(0.0, float(shares[sector]) + amount)
	var total := 0.0
	for k in shares:
		total += float(shares[k])
	for k in shares:
		shares[k] = float(shares[k]) / total
	changed.emit()


## The sector a resource company works in.
static func sector_of_kind(kind: String) -> String:
	return "timber" if kind == "forest" else "mining"


func to_dict() -> Dictionary:
	return {"shares": shares.duplicate(), "identity": identity, "since": since, "day": _day}


func from_dict(d: Dictionary) -> void:
	shares.clear()
	var s: Dictionary = d.get("shares", {})
	for k in s:
		if SECTORS.has(k):
			shares[k] = float(s[k])
	identity = str(d.get("identity", ""))
	if not SECTORS.has(identity):
		identity = ""
	since = int(d.get("since", 0))
	_day = int(d.get("day", -1))
