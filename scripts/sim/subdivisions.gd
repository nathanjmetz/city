class_name Subdivisions
extends RefCounted
## Home builders come to town (Brawn, 2026-10-23: "as you get to a certain
## size, land developers come to the city"). When the town needs homes and
## its zoned lots have run out, a builder asks on the permit bell to build
## a subdivision. The card shows two or three farms at the edge of town the
## builder holds options on, each as a ghost of the finished neighborhood,
## with what a yes means for the town. The player picks one, or says no.
##
## Real process (Indiana): a builder takes purchase options on several farms,
## brings a primary plat to the plan commission, and buys the one that's
## approved. It builds the streets and pipes at its own cost, a phase at a
## time (20 to 60 lots), and dedicates them to the town, which maintains
## them from then on (Strong Towns: the town inherits the upkeep). The next
## phase opens once most of the last one has sold; small Midwest markets
## absorb a few home sales a month, so a big subdivision takes years.
## A subdivision of SUBDIV_PARK_HOMES homes or more sets aside a pocket park
## halfway through, at the builder's cost, as Indiana subdivision rules ask
## (park land dedication, or a fee in lieu); the town keeps it up after.
## Layout: a ladder of streets off the road, with two entrances from the
## start, because the fire code asks for two separate access roads once a
## development passes 30 homes (International Fire Code, Appendix D107).
##
## The houses themselves are the town's ordinary growth: the builder zones
## the new street fronts for homes and the lots fill with demand. So it adds
## no new per-frame work: a monthly check, and the card's ghost only while
## the card is open.

signal changed

const HUB := "subdivision"
const TYPE := RoadStyle.Type.STREET

## Open proposals: permit id -> true (the sites live on the permit).
var pending := {}
## Subdivisions being built: id -> {"site": Dictionary, "phase": int (phases
## built), "opened": tick of the last phase, "builder": String, "name": String,
## "needs": what the last phase needed (ProjectNeeds.check), "extra": $ the
## builder has paid for shortages so far, "slow": how much longer the
## current phase is taking (0 on time, 1 twice as long)}.
var active := {}
var next_id := 1
## The last search for land, for checking: what stopped each candidate.
## Not saved.
var last_search := {}
## Scouting for land in progress, a little each hour ({} when not): which
## roads, how far along, the sites found so far. Saved, so a loaded copy
## of the town scouts on the same way.
var scout := {}
## scout.built as a set of squares (not saved: rebuilt from it).
var _built := {}


## Once a game month: build the next phase where the last one has sold, and
## maybe ask for a new subdivision.
func month(sim) -> bool:
	var did := _phases(sim)
	if scout.is_empty() and _can_ask(sim):
		scout_start(sim, int(_tier(sim).phases))
	return did


## Every game hour: scout a few more roads; when done, ask with what was
## found (if the town still needs it).
func hour(sim) -> void:
	if scout.is_empty():
		return
	scout_step(sim, Balance.SUBDIV_SEGS_PER_HOUR)
	if scout.get("done", false):
		var out: Array = scout.out
		scout = {}
		if not out.is_empty() and _can_ask(sim):
			_ask(sim, out)


## Carries out the player's answers (CitySim, every game hour). True when
## roads or zones changed.
func carry_out(sim) -> bool:
	if pending.is_empty():
		return false
	var did := false
	var ids := pending.keys()
	ids.sort()
	for id in ids:
		var st: int = sim.permits.state_of(id)
		if st == Permits.State.OPEN or st == Permits.State.SHELVED:
			continue
		pending.erase(id)
		if st != Permits.State.APPROVED:
			changed.emit()
			continue
		var req: Dictionary = sim.permits.requests[id]
		var opts: Array = req.get("options", [])
		var pick := clampi(int(req.get("pick", 0)), 0, maxi(opts.size() - 1, 0))
		sim.permits.done(id)
		if opts.is_empty():
			continue
		var site: Dictionary = opts[pick]
		var sid := next_id
		next_id += 1
		active[sid] = {"site": site, "phase": 0, "opened": int(sim.tick_count), "builder": str(req.leader),
			"name": str(site.get("name", "Subdivision")), "needs": {}, "extra": 0, "slow": 0.0}
		_buy_land(sim, site)
		# In winter or under a hookup moratorium the first phase waits too
		# (the monthly check starts it).
		if _ready(sim, sid) and not _build_phase(sim, sid):
			active.erase(sid)
		did = true
		changed.emit()
	return did


# ------------------------------------------------------------ the asking

## A builder only comes when the town is big enough, wants homes and has
## no empty lots left for them, and there isn't one already asking.
func _can_ask(sim) -> bool:
	if _tier(sim).is_empty():
		return false
	if float(sim.demand.get(ZoneMap.Zone.RESIDENTIAL, 0.0)) < Balance.SUBDIV_DEMAND:
		return false
	if not pending.is_empty() or _building() >= Balance.SUBDIV_MAX_ACTIVE:
		return false
	if not sim.permits.can_file(sim, HUB, 1):
		return false
	return _free_homes(sim) < Balance.SUBDIV_FREE_LOTS


## The builder that comes at this size: {"min", "phases", "who"}, or {}.
## Builders size up the market (Market), so a new town beside a city draws
## a regional developer early.
static func _tier(sim) -> Dictionary:
	var best := {}
	for t in Balance.SUBDIV_TIERS:
		if sim.market.people(sim) >= int(t[0]):
			best = {"min": int(t[0]), "phases": int(t[1]), "who": str(t[2])}
	return best


## Subdivisions with phases still to build.
func _building() -> int:
	var n := 0
	for id in active:
		if int(active[id].phase) < int(active[id].site.phases):
			n += 1
	return n


## Empty lots zoned for homes.
static func _free_homes(sim) -> int:
	var n := 0
	for key in sim.lots:
		if not sim.buildings.has(key) and sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.RESIDENTIAL:
			n += 1
	return n


func _ask(sim, sites: Array) -> void:
	var tier := _tier(sim)
	if sites.is_empty():
		return
	var seed := hash([sim.city_seed, sim.tick_count, HUB])
	var surname := Names.surname(seed)
	var company := "%s Homes" % surname
	var letters := ["A", "B", "C"]
	for i in sites.size():
		sites[i].name = "%s %s" % [_place_name(seed + i), ["Estates", "Meadows", "Crossing", "Farms", "Ridge"][absi(seed + i) % 5]]
		sites[i].letter = letters[i]
		sites[i].needs = ProjectNeeds.check(sim, _per_phase(sites[i]))
	var homes := int(sites[0].homes)
	var free := _free_homes(sim)
	var why := "The town needs homes and %s. %s holds options on %s at the edge of town. Pick the one you want built, or say no." % [
		"no empty home lots are left" if free == 0 else "only %d empty home lot%s left" % [free, " is" if free == 1 else "s are"],
		company, "%d pieces of land" % sites.size() if sites.size() > 1 else "a piece of land"]
	var id: int = sim.permits.file(sim, {"hub": HUB, "hub_id": 1, "leader": Names.person(seed, surname),
		"title": "%s wants to build about %d homes" % [company, homes], "why": why,
		"change": "Farmland to homes", "area": sites[0].outline, "options": sites, "who": str(tier.who)})
	if id > 0:
		pending[id] = true
		changed.emit()


## A short place name for the subdivision, from the land's old owners.
static func _place_name(seed: int) -> String:
	return ["Willow", "Oak", "Hickory", "Prairie", "Sycamore", "Cedar", "Walnut", "Maple", "Quail", "Heron",
		"Creekside", "Orchard"][absi(seed) % 12]


# ---------------------------------------------------------- finding land

## Up to three sites for a subdivision of `phases` rows of homes, best
## first: open or farm land at the edge of town, fronting a paved road,
## at least SUBDIV_SITE_APART apart so the choice is a real one. All at
## once, for tests and tools; the game scouts a little each hour instead
## (scout_start, scout_step).
func find_sites(sim, phases: int) -> Array:
	scout_start(sim, phases)
	while not scout.is_empty() and not scout.get("done", false):
		scout_step(sim, 1_000_000)
	var out: Array = scout.get("out", [])
	scout = {}
	return out


## Starts scouting for land: the roads it will look along (a big town's
## roads a window at a time, moving on each month, the way a builder scouts
## one side of town and then another).
func scout_start(sim, phases: int) -> void:
	var ids: Array = sim.network.segments.keys()
	ids.sort()
	if ids.size() > Balance.SUBDIV_SEGS_PER_MONTH:
		var start: int = (int(sim.tick_count) / _month_ticks() * Balance.SUBDIV_SEGS_PER_MONTH) % ids.size()
		ids = (ids + ids).slice(start, start + Balance.SUBDIV_SEGS_PER_MONTH)
	var c := _centre(sim)
	# Where the town is built, on 100 m squares (saved with the scouting,
	# so it's the same town all month).
	var built := {}
	for key in sim.buildings:
		var lot: Dictionary = sim.lots.get(key, {})
		if not lot.is_empty():
			built[_cell(lot.pos, 100.0)] = true
	var cells := built.keys()
	cells.sort()
	var flat := []
	for k in cells:
		flat.append(k.x)
		flat.append(k.y)
	scout = {"phases": phases, "ids": ids, "i": 0, "tries": 0, "found": [], "out": [], "j": 0, "done": false,
		"centre": [snappedf(c.x, 0.01), snappedf(c.y, 0.01)], "built": flat}
	_built = built
	last_search = {}


## Scouts along up to `n` more roads; once every road is looked at, checks
## the best sites one at a time against everything of yours. Each call is
## a small, fixed piece of work, and where it got to is saved.
func scout_step(sim, n: int) -> void:
	if scout.is_empty() or scout.done:
		return
	var phases := int(scout.phases)
	var depth := float(phases) * Balance.SUBDIV_ROW + 5.0
	var ids: Array = scout.ids
	var found: Array = scout.found
	if int(scout.i) < ids.size() and int(scout.tries) <= Balance.SUBDIV_MAX_TRIES:
		# Up to n roads, or until this hour's share of sites is looked at.
		var stop := int(scout.tries) + Balance.SUBDIV_TRIES_PER_HOUR
		var k := 0
		while k < n and int(scout.i) < ids.size() and (int(scout.tries) < stop or n >= 1_000_000):
			var seg := int(ids[int(scout.i)])
			scout.i = int(scout.i) + 1
			k += 1
			if sim.network.segments.has(seg) and _frontage(int(sim.network.segments[seg].get("type", 0))) and _edge(sim, seg):
				_scout_road(sim, seg, depth, _road_grid(sim, [seg], depth))
		return
	# Every road looked at: the best sites, nearest the middle of town first.
	if int(scout.j) == 0:
		found.sort_custom(func(a, b): return float(a.score) > float(b.score) or (float(a.score) == float(b.score) and int(a.seg) < int(b.seg)))
	var out: Array = scout.out
	while int(scout.j) < found.size() and out.size() < 3:
		var s: Dictionary = found[int(scout.j)]
		scout.j = int(scout.j) + 1
		if _too_close(out, s):
			continue
		var site := s.duplicate(true)
		site.erase("score")
		_lay_out(sim, site)
		# (Lots and buildings stand on zoning, which fronts a road, so the
		# road check in _clear has already kept sites off anything of yours.)
		if _entrances_ok(sim, site):
			out.append(site)
		if n < 1_000_000:
			return  # one full check an hour
	scout.done = true


## Looks along one road, both sides, for a site at the edge of town.
func _scout_road(sim, seg: int, depth: float, roads: Dictionary) -> void:
	var type := int(sim.network.segments[seg].get("type", 0))
	var found: Array = scout.found
	var centre := Vector2(float(scout.centre[0]), float(scout.centre[1]))
	# A site can front a road that's in pieces (junctions split it): each
	# piece is looked at along its length, and the entrances only have to
	# meet a road.
	var c: Array = sim.network.curve_of(seg)
	var len := Vector2(c[0].x, c[0].z).distance_to(Vector2(c[2].x, c[2].z))
	var hw: float = RoadStyle.right_of_way_half(type)
	var steps := maxi(1, roundi(len / Balance.SUBDIV_SITE_STEP))
	for i in steps:
		var t0 := (i + 0.5) / steps
		var p: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], t0)
		# The edge of town: homes or shops within about 200 m (Indiana lets a
		# town annex only land that touches it, IC 36-4-3-13).
		if not _near(_built, p, 2):
			continue
		var ahead: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], minf(t0 + 0.02, 1.0)) - RoadNetwork.bezier(c[0], c[1], c[2], maxf(t0 - 0.02, 0.0))
		var tan := Vector2(ahead.x, ahead.z).normalized()
		if tan == Vector2.ZERO:
			continue
		for side in [-1.0, 1.0]:
			var nrm: Vector2 = Vector2(-tan.y, tan.x) * float(side)
			var site := {"o": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)], "t": [snappedf(tan.x, 0.0001), snappedf(tan.y, 0.0001)],
				"n": [snappedf(nrm.x, 0.0001), snappedf(nrm.y, 0.0001)], "hw": snappedf(hw, 0.01), "seg": seg, "phases": int(scout.phases)}
			if _too_close(found, site):
				continue
			# The middle of the site must be open country, or it isn't the
			# edge of town: most points along town roads stop here, cheaply.
			var mid := local(site, 0.0, depth * 0.5)
			if _near(_built, mid, 0) or sim.zones.zone_at(mid) != ZoneMap.Zone.NONE:
				continue
			# The town's land use plan: never homes on land it plans for
			# something else; land it plans for homes is looked at first.
			var plan: String = sim.land_plan.kind_at(mid)
			if plan != "" and plan != "homes":
				last_search["planned for " + plan] = int(last_search.get("planned for " + plan, 0)) + 1
				continue
			scout.tries = int(scout.tries) + 1
			if int(scout.tries) > Balance.SUBDIV_MAX_TRIES:
				return
			var why := _clear(sim, site, depth, roads)
			if why != "":
				last_search[why] = int(last_search.get(why, 0)) + 1
				continue
			site.score = snappedf(-Vector2(p.x, p.z).distance_to(centre), 0.01)
			if plan == "homes":
				site.planned = true
				site.score = float(site.score) + Balance.PLAN_FIRST_M
			found.append(site)


## Roads homes can be reached from: not a freeway or its ramps, an alley,
## or a gravel farm road.
static func _frontage(type: int) -> bool:
	return not type in [RoadStyle.Type.HIGHWAY, RoadStyle.Type.RAMP, RoadStyle.Type.RAMP2, RoadStyle.Type.FREEWAY2,
		RoadStyle.Type.FREEWAY4, RoadStyle.Type.ALLEY, RoadStyle.Type.GRAVEL]


## True when some of a road is at the edge of town (built land within
## about 200 m, but open land beside it): roads deep in town or far out in
## the country are passed over before anything dearer is worked out.
func _edge(sim, seg: int) -> bool:
	var c: Array = sim.network.curve_of(seg)
	var near := false
	var open := false
	for t in [0.0, 0.5, 1.0]:
		var p: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], t)
		near = near or _near(_built, p, 2)
		open = open or not _near(_built, p, 0)
	return near and open


## The middle of town: the middle of its road junctions.
static func _centre(sim) -> Vector2:
	var centre := Vector2.ZERO
	for id in sim.network.nodes:
		var q: Vector3 = sim.network.nodes[id]
		centre += Vector2(q.x, q.z)
	return centre / maxf(sim.network.nodes.size(), 1.0)


## Every road's right of way (plus 3 m) near these roads' sites, as points
## 20 m apart on a 25 m grid: cell -> [[point, reach], ...]. Only roads that
## come within a site's reach of them are sampled (a quick box test first).
func _road_grid(sim, segs: Array, depth: float) -> Dictionary:
	var area := Rect2()
	var first := true
	for seg in segs:
		if not sim.network.segments.has(seg):
			continue
		var c: Array = sim.network.curve_of(seg)
		var box := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)).expand(Vector2(c[2].x, c[2].z))
		area = box if first else area.merge(box)
		first = false
	var out := {}
	if first:
		return out
	area = area.grow(depth + 60.0)
	for seg in sim.network.segments:
		var c: Array = sim.network.curve_of(seg)
		var box := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)).expand(Vector2(c[2].x, c[2].z))
		if not box.intersects(area):
			continue
		var len := Vector2(c[0].x, c[0].z).distance_to(Vector2(c[2].x, c[2].z))
		var keep := RoadStyle.right_of_way_half(int(sim.network.segments[seg].get("type", 0))) + 3.0
		for q in sim.network.sample_segment(seg, clampi(int(len / 20.0), 2, 120)):
			var k := _cell(q, 25.0)
			if not out.has(k):
				out[k] = []
			out[k].append([Vector2(q.x, q.z), keep])
	return out


func _too_close(list: Array, site: Dictionary) -> bool:
	var o := Vector2(site.o[0], site.o[1])
	for s in list:
		if o.distance_to(Vector2(s.o[0], s.o[1])) < Balance.SUBDIV_SITE_APART:
			return true
	return false


## "" when every point of the site is buildable ground with no zoning,
## lot, road (inside any road's right of way, the one it fronts included),
## business or hub on it; otherwise what's in the way.
func _clear(sim, site: Dictionary, depth: float, roads: Dictionary) -> String:
	var half := Balance.SUBDIV_WIDTH * 0.5
	var step := 50.0
	# Corners and middle first: most candidates fail there.
	var order := [[0.0, depth * 0.5], [-half, depth], [half, depth], [-half, 4.0], [half, 4.0]]
	var u := -half
	while u <= half + 0.01:
		var v := 4.0
		while v <= depth + 0.01:
			order.append([u, v])
			v += step
		u += step
	var o := Vector2(float(site.o[0]), float(site.o[1]))
	var n := Vector2(float(site.n[0]), float(site.n[1]))
	var hw := float(site.hw)
	# The cheap checks for every point first, the dearer ones after.
	for uv in order:
		var p := local(site, uv[0], uv[1])
		var k := _cell(p, 25.0)
		# (Zoning always fronts a road, so the road check below finds it too.)
		if sim.zones.zone_at(p) != ZoneMap.Zone.NONE:
			return "built or zoned"
		# Points are 50 m apart (and a road's points 20), so a road anywhere near one is a road
		# through the site, unless it's on the far side of the site's own
		# edge (the road it fronts).
		var flat := Vector2(p.x, p.z)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for r in roads.get(k + Vector2i(dx, dz), []):
					if flat.distance_to(r[0]) < float(r[1]) + 28.0 and (r[0] - o).dot(n) - hw > -1.0:
						return "a road"
	for uv in order:
		var p := local(site, uv[0], uv[1])
		if fmod(absf(float(uv[0])) + float(uv[1]) - 4.0, 100.0) > 0.01 and uv[1] != depth * 0.5:
			continue  # the ground and who owns it, every 100 m
		if not sim.land_ok(p):
			return "water or steep"
		if sim.reserves.kind_at(p) != "":
			return "reserved"
		var who: String = sim.land_owner(p)
		if who != "" and (not who.begins_with("farm:") or sim.farms.farm_at(p) != -1):
			return "someone's land"
	return ""


## Both entrances meet the road (the one the site fronts, maybe in pieces).
func _entrances_ok(sim, site: Dictionary) -> bool:
	for s in [-1.0, 1.0]:
		var e := local(site, s * (Balance.SUBDIV_WIDTH * 0.5 - Balance.SUBDIV_SPINE_IN), -float(site.hw))
		if sim.network.find_segment_near(e, 6.0, 4.0).is_empty():
			return false
	return true


## A point at (u along the road, v back from the edge of its right of way).
static func local(site: Dictionary, u: float, v: float) -> Vector3:
	var o := Vector2(float(site.o[0]), float(site.o[1]))
	var t := Vector2(float(site.t[0]), float(site.t[1]))
	var n := Vector2(float(site.n[0]), float(site.n[1]))
	var p := o + t * u + n * (float(site.hw) + v)
	return Vector3(p.x, 0.0, p.y)


## Where the cross street of row k runs (metres back from the road).
static func row_v(k: int) -> float:
	return Balance.SUBDIV_FIRST_ROW + Balance.SUBDIV_ROW * k


## The streets of phase k: [[a, b], ...] as Vector3 (entrance or spine
## pieces first, then the cross street). Every phase but the last leaves
## its spines running on a little past the cross street, a "stub street"
## the next phase continues from, as real plats do, so no lot is laid
## across the way on.
static func streets(site: Dictionary, k: int) -> Array:
	var spine := Balance.SUBDIV_WIDTH * 0.5 - Balance.SUBDIV_SPINE_IN
	var out := []
	var v0 := -float(site.hw) if k == 0 else row_v(k - 1) + Balance.SUBDIV_STUB
	var v1 := row_v(k) + (Balance.SUBDIV_STUB if k < int(site.phases) - 1 else 0.0)
	for s in [-1.0, 1.0]:
		out.append([local(site, s * spine, v0), local(site, s * spine, v1)])
	out.append([local(site, -spine, row_v(k)), local(site, spine, row_v(k))])
	return out


## Fills in the site's outline, the ghost of its finished homes and streets,
## its cost and what a yes means for the town.
func _lay_out(sim, site: Dictionary) -> void:
	var phases := int(site.phases)
	var half := Balance.SUBDIV_WIDTH * 0.5
	var depth := float(phases) * Balance.SUBDIV_ROW + 5.0
	site.outline = []
	for uv in [[-half, 1.0], [half, 1.0], [half, depth], [-half, depth]]:
		var p := local(site, uv[0], uv[1])
		site.outline.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
	var lines := []
	var cost := 0
	var street_m := 0.0
	for k in phases:
		for l in streets(site, k):
			lines.append([[snappedf(l[0].x, 0.01), snappedf(l[0].z, 0.01)], [snappedf(l[1].x, 0.01), snappedf(l[1].z, 0.01)]])
			cost += Economy.road_cost([l[0], (l[0] + l[1]) * 0.5, l[1]], TYPE)
			street_m += l[0].distance_to(l[1])
	site.streets = lines
	# The homes: both sides of every cross street, and the outer side of the
	# spines, a lot every SUBDIV_LOT_W, set back from the sidewalk.
	var ghost := []
	var back := RoadStyle.right_of_way_half(TYPE) + Balance.SUBDIV_SETBACK + 5.0
	var spine := half - Balance.SUBDIV_SPINE_IN
	var ang := atan2(float(site.t[1]), float(site.t[0]))
	for k in phases:
		var u := -spine + back + 4.0
		while u <= spine - back - 4.0:
			for s in [-1.0, 1.0]:
				var p := local(site, u, row_v(k) + s * back)
				ghost.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01), snappedf(ang, 0.001), 12.0, 10.0, 6.0 + float(absi(hash([u, k, s])) % 3)])
			u += Balance.SUBDIV_LOT_W
		var v := (0.0 if k == 0 else row_v(k - 1)) + back + 6.0
		while v <= row_v(k) + Balance.SUBDIV_ROW * 0.5 - 8.0 and v <= depth - 8.0:
			for s in [-1.0, 1.0]:
				var p := local(site, s * (spine + back), v)
				ghost.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01), snappedf(ang + PI * 0.5, 0.001), 12.0, 10.0, 6.0])
			v += Balance.SUBDIV_LOT_W
	site.ghost = ghost
	var homes := ghost.size()
	site.homes = homes
	var acres := Balance.SUBDIV_WIDTH * depth / 4046.86
	site.cost = cost + roundi(Balance.SUBDIV_WIDTH * depth * Balance.CULTURE_FARMLAND_PER_M2)
	site.effects = effects_of(sim, homes, street_m)
	site.effects.acres = snappedf(acres, 0.1)
	site.effects.years = snappedf(float(phases) * _phase_months(site) / 12.0, 0.5)


## What adding `homes` homes and `street_m` metres of street means for the
## town, for the card ("This yes means"). Real ratios: about 2.5 people a
## household (US Census), about 0.6 school-age children per new single-
## family home (pupil yield studies), and about 9.4 car trips a day per
## house, about 1 of them at rush hour (ITE Trip Generation, code 210).
static func effects_of(sim, homes: int, street_m: float) -> Dictionary:
	var people := roundi(homes * Balance.SUBDIV_PEOPLE_PER_HOME)
	var water: Array = sim.services.utility_use.get("water", [0, 0])
	var power: Array = sim.services.utility_use.get("power", [0, 0])
	var load := homes * int(Balance.UTILITY_LOAD[ZoneMap.Zone.RESIDENTIAL])
	var tax := float(sim.economy.tax.get(ZoneMap.Zone.RESIDENTIAL, 1.0))
	return {
		"homes": homes,
		"people": people,
		"kids": roundi(homes * Balance.SUBDIV_KIDS_PER_HOME),
		"trips": roundi(homes * Balance.SUBDIV_TRIPS_PER_HOME),
		"peak": roundi(homes * Balance.SUBDIV_PEAK_PER_HOME),
		"water": _pct(int(water[0]) + load, int(water[1])),
		"power": _pct(int(power[0]) + load, int(power[1])),
		"upkeep": roundi(street_m * RoadStyle.TYPES[TYPE].lanes * Balance.ROAD_UPKEEP_PER_LANE_M * 12.0),
		# ...and resurfacing them when they wear out (StreetAge).
		"repave": StreetAge.repave_cost(street_m * RoadStyle.TYPES[TYPE].lanes, TYPE),
		"taxes": roundi(people * Balance.VALUE_PER_PLACE[ZoneMap.Zone.RESIDENTIAL] * tax / 100.0),
	}


## Use as a percentage of capacity, or -1 when there's none.
static func _pct(used: int, cap: int) -> int:
	return -1 if cap <= 0 else roundi(100.0 * used / cap)


# ------------------------------------------------------------- building

## The builder buys the farm ground the whole site covers.
func _buy_land(sim, site: Dictionary) -> void:
	var poly := PackedVector2Array()
	for p in site.outline:
		poly.append(Vector2(float(p[0]), float(p[1])))
	var ids: Array = sim.farms.farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		var keep := []
		for c in f.cells:
			if Geometry2D.intersect_polygons(poly, Farms.cell_corners(f, c)).is_empty():
				keep.append(c)
		f.cells = keep


## Builds the next phase's streets (at the builder's cost) and zones their
## fronts for homes. False if the land is no longer clear for them.
func _build_phase(sim, sid: int) -> bool:
	var a: Dictionary = active[sid]
	var site: Dictionary = a.site
	var k := int(a.phase)
	var lines := streets(site, k)
	# Anything of yours in the way now? (Your roads, or zoning, which is
	# where lots and buildings stand.) The ends meet the builder's own streets.
	for l in lines:
		if not _line_clear(sim, l[0], l[1]):
			return false
	var money: int = sim.economy.money
	var before: Array = sim.network.segments.keys()
	if k == 0:
		for l in lines.slice(0, 2):
			if HubRoads.on_road(sim, l[0]) == Vector3.INF:
				sim._join_county(l[0])
	sim.network.begin_batch()
	for l in lines:
		sim.network.build_road(l[0], (l[0] + l[1]) * 0.5, l[1], TYPE)
	sim.network.end_batch()
	sim.economy.money = money
	var made: Array = sim.network.segments.keys().filter(func(id): return not id in before)
	sim.zone_new_streets(made, ZoneMap.Zone.RESIDENTIAL)
	if k == int(site.phases) / 2 and int(site.homes) >= Balance.SUBDIV_PARK_HOMES and not a.has("park"):
		_dedicate_park(sim, a, k)
	a.phase = k + 1
	a.opened = int(sim.tick_count)
	return true


## The builder's park: a pocket park on phase k's cross street, in the
## middle, on whichever side is clear.
func _dedicate_park(sim, a: Dictionary, k: int) -> void:
	for side in [1.0, -1.0]:
		var spot := Parks.site_near(sim.network, "park", local(a.site, 0.0, row_v(k) + side * 30.0))
		if spot.is_empty() or sim.parks.site_problem(sim, "park", spot[0], spot[1]) != "":
			continue
		var pid: int = sim.parks.add(sim, "park", spot[0], spot[1])
		sim._clear_zones_under(sim.parks.footprint(pid))
		sim._lots_dirty = true
		sim.parks_changed.emit()
		a.park = pid
		return


## True when a new street from a to b crosses no road and no zoning and
## stays on buildable ground, away from its ends (where it joins).
func _line_clear(sim, a: Vector3, b: Vector3) -> bool:
	var box := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(30.0)
	var near := []
	for seg in sim.network.segments:
		var c: Array = sim.network.curve_of(seg)
		if Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)).expand(Vector2(c[2].x, c[2].z)).intersects(box):
			var keep := RoadStyle.half_width(int(sim.network.segments[seg].get("type", 0))) + RoadStyle.half_width(TYPE)
			for q in sim.network.sample_segment(seg, 24):
				near.append([Vector2(q.x, q.z), keep])
	var length := a.distance_to(b)
	var d := HubRoads.JUNCTION
	while d <= length - HubRoads.JUNCTION:
		var p := a.lerp(b, d / length)
		if not sim.land_ok(p) or sim.zones.zone_at(p) != ZoneMap.Zone.NONE:
			return false
		for r in near:
			if Vector2(p.x, p.z).distance_to(r[0]) < float(r[1]):
				return false
		d += 6.0
	return true


## A phase opens once most of the last one has sold, and not before
## SUBDIV_PHASE_MIN_MONTHS have passed.
func _phases(sim) -> bool:
	var did := false
	var ids := active.keys()
	ids.sort()
	for sid in ids:
		var a: Dictionary = active[sid]
		if int(a.phase) >= int(a.site.phases):
			continue
		if int(a.phase) > 0:
			# Shortages on the last phase make it take longer.
			var wait := roundi(_phase_months(a.site) * (1.0 + float(a.get("slow", 0.0))) * _month_ticks())
			if int(sim.tick_count) - int(a.opened) < wait:
				continue
			var fill := sold(sim, sid)
			if fill.y <= 0 or float(fill.x) / fill.y < Balance.SUBDIV_NEXT_PHASE_FILL:
				continue
		if not _ready(sim, sid):
			changed.emit()
			continue
		if _build_phase(sim, sid):
			did = true
		else:
			# Something of yours is in the way: the builder stops here.
			a.site.phases = int(a.phase)
		changed.emit()
	return did


## Asks the other leaders what the next phase needs and records it. False
## when it has to wait (winter, or water or power full); otherwise the
## builder pays for any shortage and the phase will take longer.
func _ready(sim, sid: int) -> bool:
	var a: Dictionary = active[sid]
	var needs := ProjectNeeds.check(sim, _per_phase(a.site))
	a.needs = needs
	if needs.hold:
		return false
	a.extra = int(a.get("extra", 0)) + int(needs.extra)
	a.slow = float(needs.slow)
	return true


## Months a phase takes at least: less inside the town's land use plan,
## where the plan commission approves each section plat as routine.
static func _phase_months(site: Dictionary) -> float:
	return Balance.SUBDIV_PHASE_MIN_MONTHS * (Balance.PLAN_FASTER if bool(site.get("planned", false)) else 1.0)


## Homes in one phase of a site.
static func _per_phase(site: Dictionary) -> int:
	return int(site.homes) / maxi(int(site.phases), 1)


## (homes built, lots) in a subdivision's built phases so far.
func sold(sim, sid: int) -> Vector2i:
	var a: Dictionary = active[sid]
	var site: Dictionary = a.site
	var half := Balance.SUBDIV_WIDTH * 0.5 + 5.0
	var depth := row_v(int(a.phase) - 1) + Balance.SUBDIV_ROW * 0.5
	var o := Vector2(float(site.o[0]), float(site.o[1]))
	var t := Vector2(float(site.t[0]), float(site.t[1]))
	var n := Vector2(float(site.n[0]), float(site.n[1]))
	var built := 0
	var total := 0
	for key in sim.lots:
		var p: Vector3 = sim.lots[key].pos
		var d := Vector2(p.x, p.z) - o
		var u := d.dot(t)
		var v := d.dot(n) - float(site.hw)
		if absf(u) <= half and v >= 0.0 and v <= depth:
			total += 1
			if sim.buildings.has(key):
				built += 1
	return Vector2i(built, total)


static func _month_ticks() -> int:
	return 24 * CitySim.TICKS_PER_HOUR


static func _cell(p: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.z / size))


static func _near(grid: Dictionary, p: Vector3, r: int) -> bool:
	var c := _cell(p, 100.0)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if grid.has(c + Vector2i(dx, dz)):
				return true
	return false


## True when there's zoning (so lots, homes and shops) within r × 100 m of
## p, looked at on a 25 m pattern around it (r 0 is the 25 m around p).
static func _zoned_near(sim, p: Vector3, r: int) -> bool:
	var reach := 12.5 if r == 0 else r * 100.0
	var step := 12.5 if r == 0 else 50.0
	var x := -reach
	while x <= reach + 0.01:
		var z := -reach
		while z <= reach + 0.01:
			if sim.zones.zone_at(p + Vector3(x, 0.0, z)) != ZoneMap.Zone.NONE:
				return true
			z += step
		x += step
	return false


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var act := {}
	for id in active:
		act[str(id)] = active[id]
	return {"next": next_id, "pending": pending.keys(), "active": act, "scout": scout}


func from_dict(d: Dictionary) -> void:
	pending.clear()
	active.clear()
	next_id = int(d.get("next", 1))
	scout = {}
	var sc: Dictionary = d.get("scout", {})
	if not sc.is_empty():
		scout = {"phases": int(sc.phases), "ids": Array(sc.ids).map(func(x): return int(x)), "i": int(sc.i),
			"tries": int(sc.tries), "j": int(sc.j), "done": bool(sc.done), "centre": [float(sc.centre[0]), float(sc.centre[1])],
			"found": Array(sc.found).map(func(x): return site_from(x)), "out": Array(sc.out).map(func(x): return site_from(x)),
			"built": Array(sc.built).map(func(x): return int(x))}
	_built = {}
	if not scout.is_empty():
		var b: Array = scout.built
		for i in range(0, b.size() - 1, 2):
			_built[Vector2i(b[i], b[i + 1])] = true
	for id in d.get("pending", []):
		pending[int(id)] = true
	for k in d.get("active", {}):
		var a: Dictionary = d.active[k]
		active[int(k)] = {"site": site_from(a.site), "phase": int(a.phase), "opened": int(a.opened),
			"builder": str(a.get("builder", "")), "name": str(a.get("name", "")),
			"needs": ProjectNeeds.from_dict(a.get("needs", {})), "extra": int(a.get("extra", 0)), "slow": float(a.get("slow", 0.0))}
		if a.has("park"):
			active[int(k)].park = int(a.park)
	changed.emit()


## A site back from a save, with whole numbers whole again.
static func site_from(s: Dictionary) -> Dictionary:
	var out := s.duplicate(true)
	for k in ["seg", "phases", "homes", "cost"]:
		if out.has(k):
			out[k] = int(out[k])
	if out.has("effects"):
		for k in out.effects:
			if not k in ["acres", "years"]:
				out.effects[k] = int(out.effects[k])
	if out.has("needs"):
		out.needs = ProjectNeeds.from_dict(out.needs)
	return out
