class_name LeaderAsks
extends RefCounted
## Leaders ask the town for things, and every answer costs something
## (Brawn, 2026-10-23). They come on the permit bell, never as a pop-up, at
## most one new one a month, and an unanswered one is shelved like any other.
## Each card says what happens on a yes and on a no.
##
## This is how culture and community show up in play. Which leaders ask
## follows the town's culture (TownCulture.pull): a farm town hears from
## farmers, a market town from merchants. Each answer leans it in turn, so the
## player steers what the town becomes one answer at a time; that is the
## CORE PILLAR, a town that can change identity, with the player in control.
##
## The asks, each after a real thing a town council or board of works hears:
##   abatement  A company asks for an Indiana property tax abatement
##              (IC 6-1.1-12.1, an Economic Revitalization Area) to build its
##              next step now. Yes: it builds and hires; the town forgoes part
##              of the new taxes for a few years. No: it saves up instead.
##   pave       A farm family asks the town to pave the gravel road its grain
##              trucks use (the county posts spring weight limits on gravel;
##              Indiana's Community Crossings grants pay most of the cost).
##   signal     The bank president (or a Main Street owner) asks for a
##              stoplight at a busy four-way stop: a traffic signal warrant
##              (MUTCD chapter 4C). Yes: the town pays; the main road flows,
##              side streets wait for green.
##   festival   Main Street merchants ask to close the street for the fall
##              festival (a special event permit). Yes: the town pays police
##              and cleanup; shops do a month's extra business.
## Farmland turned into an office park or a shopping strip, Brawn's example
## of a town changing identity, is asked by a land developer (TownCulture).
## Heritage asks (protect a district, tear down an old building) live in
## Heritage and work the same way.
##
## Monthly; the checks are small (O(roads + hubs)). Deterministic: the pick
## uses a seed from the city and the month.

signal changed

const HUB := "town"
## The trade (TownCulture sector) each ask speaks for; an abatement speaks
## for the company's own trade.
const AXIS := {"abatement": "mining", "pave": "farm", "signal": "trade", "festival": "trade"}
const TICKS_PER_MONTH := 24 * CitySim.TICKS_PER_HOUR

## permit id -> {"kind", ...what to do on a yes}
var asks := {}
## kind -> tick it was last asked
var last := {}
## Tax abatements in force: [{"who", "monthly", "until"}]
var abatements := []
## The tick a festival lifts shop demand until.
var festival_until := -1


## Once a game month: maybe one leader asks for something.
func month(sim) -> void:
	_expire(sim)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, sim.tick_count, "asks"])
	if rng.randf() >= Balance.ASK_CHANCE:
		return
	var options := []
	for kind in ["abatement", "pave", "signal", "festival"]:
		if sim.tick_count - int(last.get(kind, -1_000_000_000)) < int(Balance.ASK_COOLDOWN[kind]) * TICKS_PER_MONTH:
			continue
		var plan: Dictionary = call("_plan_" + kind, sim)
		if plan.is_empty():
			continue
		# The town's own kind of leaders speak up more.
		plan.weight = 1.2 + sim.culture.pull(_sector(sim, kind, plan.get("do", {})))
		options.append(plan)
	if options.is_empty():
		return
	var total := 0.0
	for o in options:
		total += float(o.weight)
	var roll := rng.randf() * total
	var pick: Dictionary = options[-1]
	for o in options:
		roll -= float(o.weight)
		if roll <= 0.0:
			pick = o
			break
	_file(sim, pick)


func _file(sim, plan: Dictionary) -> void:
	var kind := str(plan.kind)
	var hub_id := int(plan.get("hub_id", absi(hash([kind, sim.tick_count])) % 1_000_000))
	if not sim.permits.can_file(sim, HUB, hub_id, true):
		return
	var req: int = sim.permits.file(sim, {"hub": HUB, "hub_id": hub_id, "leader": plan.leader,
		"title": plan.title, "why": plan.why, "area": plan.area, "change": plan.get("change", ""), "ask": kind,
		"yes": plan.yes, "no": plan.no})
	if req <= 0:
		return
	last[kind] = sim.tick_count
	asks[req] = plan.do
	asks[req].kind = kind
	changed.emit()


# ---------------------------------------------------------------- the asks

## A company with a next step it can't yet pay for.
func _plan_abatement(sim) -> Dictionary:
	var ids: Array = sim.industry.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sim.industry.sites[id]
		var profit: float = sim.industry.yearly_profit(id)
		if profit <= 0.0 or not Agency.TREES.has(s.kind):
			continue
		var lead: Dictionary = s.get("leader", {"caution": 0.5, "ambition": 0.5})
		var budget := profit * (2.0 + 3.0 * float(lead.ambition)) - profit * float(lead.caution)
		var want := {}
		for node in Agency.open(sim, s, Agency.TREES[s.kind], s.pos, profit):
			if float(node.cost) > budget and (want.is_empty() or float(node.cost) < float(want.cost)):
				want = node
		if want.is_empty():
			continue
		var ref := "site:%d" % id
		var company: String = sim.families.name_of(ref)
		if company == "":
			company = "the " + str(Industry.KINDS[s.kind].name).to_lower()
		var fam: Dictionary = sim.families.family_of(ref)
		var monthly := roundi(float(want.cost) * Balance.ASK_ABATE_RATE / 12.0)
		var jobs := int(want.get("effects", {}).get("jobs+", 0))
		return {"kind": "abatement", "hub_id": id,
			"leader": "%s, %s" % [fam.head, company] if not fam.is_empty() else company.capitalize(),
			"title": "A tax abatement for a %s" % str(want.name).to_lower(),
			"why": "%s would build a %s%s now if the new investment's taxes phase in over %d years." % [
				company.capitalize(), str(want.name).to_lower(), (" (%s)" % want.note) if want.has("note") else "",
				Balance.ASK_ABATE_YEARS],
			"area": _square(s.pos, 60.0),
			"yes": "They build it now%s. The town forgoes about $%s a month for %d years." % [
				(" and hire %d" % jobs) if jobs > 0 else "", CitySim.money_text(monthly), Balance.ASK_ABATE_YEARS],
			"no": "They wait until they can pay for it themselves.",
			"do": {"site": id, "node": str(want.id), "monthly": monthly}}
	return {}


## A farm whose trucks use a gravel road.
func _plan_pave(sim) -> Dictionary:
	var gravel := []
	for seg in sim.network.segments:
		if int(sim.network.segments[seg].type) == RoadStyle.Type.GRAVEL:
			gravel.append(seg)
	if gravel.is_empty():
		return {}
	gravel.sort()
	var ids: Array = sim.farms.farms.keys()
	ids.sort_custom(func(a, b): return sim.farms.farms[a].cells.size() > sim.farms.farms[b].cells.size() \
		or (sim.farms.farms[a].cells.size() == sim.farms.farms[b].cells.size() and a < b))
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		var end: Vector3 = f.drive[-1] if not f.drive.is_empty() else f.pos
		for seg in gravel:
			var pts: PackedVector3Array = sim.network.sample_segment(seg)
			var near := false
			for p in pts:
				if p.distance_to(end) < 60.0:
					near = true
					break
			if not near:
				continue
			var length := 0.0
			for i in range(1, pts.size()):
				length += pts[i].distance_to(pts[i - 1])
			var cost := roundi(length * Balance.ASK_PAVE_PER_M)
			var ref := "farm:%d" % id
			var farm: String = sim.families.name_of(ref)
			var fam: Dictionary = sim.families.family_of(ref)
			var street: String = sim.streets.name_of(seg)
			if street == "":
				street = "the gravel road"
			return {"kind": "pave", "hub_id": 100000 + seg,
				"leader": ("%s, %s" % [fam.head, farm]) if not fam.is_empty() else "A farmer on %s" % street,
				"title": "Pave %s" % street,
				"why": "Grain trucks rut the gravel every spring thaw, and the county posts weight limits on it.",
				"area": _corridor(pts, 10.0), "change": "Gravel to paved county road",
				"yes": "The town pays its share, $%s (a Community Crossings grant pays the rest). Trucks run faster and safer." % CitySim.money_text(cost),
				"no": "It stays gravel.",
				"do": {"seg": seg, "cost": cost}}
	return {}


## A four-way stop on a main road, near a bank or a family business.
func _plan_signal(sim) -> Dictionary:
	if int(sim.stats.get("population", 0)) < 400:
		return {}
	var nodes: Array = sim.traffic.junctions.keys()
	nodes.sort()
	for n in nodes:
		var j: Dictionary = sim.traffic.junctions[n]
		if int(j.get("control", -1)) != TrafficSim.Rule.ALL_STOP or not sim.network.nodes.has(n):
			continue
		var segs: Array = sim.network.segments_at(n)
		if segs.size() < 3:
			continue
		var main := false
		var names := []
		for seg in segs:
			var t: int = sim.network.segments[seg].type
			if t == RoadStyle.Type.MAIN_STREET or RoadStyle.TYPES[t].lanes >= 4:
				main = true
			var nm: String = sim.streets.name_of(seg)
			if nm != "" and not nm in names:
				names.append(nm)
		if not main:
			continue
		var at: Vector3 = sim.network.nodes[n]
		var who := _leader_near(sim, at)
		if who == "":
			continue
		var corner := "this corner" if names.size() < 2 else "%s and %s" % [names[0], names[1]]
		return {"kind": "signal", "hub_id": 200000 + n,
			"leader": who, "title": "A stoplight at %s" % corner,
			"why": "Cars back up at the four-way stop at rush hour. It meets the signal warrant.",
			"area": _square(at, 18.0), "change": "Four-way stop to traffic signal",
			"yes": "The town pays $%s. The main road keeps moving; side streets wait for green." % CitySim.money_text(Balance.ASK_SIGNAL_COST),
			"no": "It stays a four-way stop.",
			"do": {"node": n, "cost": Balance.ASK_SIGNAL_COST}}
	return {}


## A bank president or a family business owner near a point.
static func _leader_near(sim, at: Vector3) -> String:
	var ids: Array = sim.banks.banks.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.banks.banks[id]
		if b.pos.distance_to(at) < 500.0:
			return "%s, %s" % [b.leader.get("name", "The president"), b.name]
	var refs: Array = sim.families.owned.keys()
	refs.sort()
	for ref in refs:
		var key := str(ref).substr(4)
		if str(ref).begins_with("lot:") and sim.lots.has(key) and sim.lots[key].pos.distance_to(at) < 300.0:
			return "%s, %s" % [sim.families.family_of(ref).head, sim.families.name_of(ref)]
	return ""


## Fall festival on Main Street.
func _plan_festival(sim) -> Dictionary:
	if not Seasons.month(sim.tick_count) in Balance.ASK_FESTIVAL_MONTHS:
		return {}
	var best := -1
	var shops := 0
	var count := {}
	for key in sim.buildings:
		if BuildingTypes.type_of(sim.buildings[key]) == "mixed_use" and sim.lots.has(key):
			var seg := int(sim.lots[key].seg)
			count[seg] = int(count.get(seg, 0)) + 1
	var segs := count.keys()
	segs.sort()
	for seg in segs:
		if sim.network.segments.has(seg) and int(count[seg]) > shops:
			shops = int(count[seg])
			best = seg
	if best == -1 or shops < 3:
		return {}
	var street: String = sim.streets.name_of(best)
	if street == "":
		street = "Main Street"
	var who := ""
	var refs: Array = sim.families.owned.keys()
	refs.sort()
	for ref in refs:
		var key := str(ref).substr(4)
		if str(ref).begins_with("lot:") and sim.lots.has(key) and int(sim.lots[key].seg) == best:
			who = "%s, for the %s merchants" % [sim.families.family_of(ref).head, street]
			break
	if who == "":
		who = "The %s merchants" % street
	return {"kind": "festival", "hub_id": 300000 + Seasons.year(sim.tick_count),
		"leader": who, "title": "Close %s for the fall festival" % street,
		"why": "A weekend of booths, a parade and music brings the whole county downtown.",
		"area": _corridor(sim.network.sample_segment(best), 14.0), "change": "Street closed for a weekend",
		"yes": "The town pays $%s for police, barricades and cleanup. Shops do a month's extra business." % CitySim.money_text(Balance.ASK_FESTIVAL_COST),
		"no": "No festival this year.",
		"do": {"cost": Balance.ASK_FESTIVAL_COST}}


# ------------------------------------------------------------ the answers

## Carries out the player's answers (CitySim, every game hour).
func carry_out(sim) -> void:
	if asks.is_empty():
		return
	var ids := asks.keys()
	ids.sort()
	for id in ids:
		var st: int = sim.permits.state_of(id)
		if st == Permits.State.OPEN or st == Permits.State.SHELVED:
			continue
		var a: Dictionary = asks[id]
		asks.erase(id)
		var kind := str(a.kind)
		if st == Permits.State.APPROVED:
			sim.permits.done(id)
			if _yes(sim, a):
				sim.culture.nudge(_sector(sim, kind, a), Balance.CULTURE_YES_LEAN)
		changed.emit()


## The trade an ask speaks for: an abatement's is its company's.
static func _sector(sim, kind: String, a: Dictionary) -> String:
	if kind == "abatement" and sim.industry.sites.has(int(a.get("site", -1))):
		return TownCulture.sector_of_kind(str(sim.industry.sites[int(a.site)].kind))
	return AXIS[kind]


func _yes(sim, a: Dictionary) -> bool:
	match str(a.kind):
		"abatement":
			var s: Dictionary = sim.industry.sites.get(int(a.site), {})
			if s.is_empty() or str(a.node) in s.get("built", []):
				return false
			if not s.has("built"):
				s.built = []
			s.built.append(str(a.node))
			var node := {}
			for n in Agency.TREES[s.kind]:
				if n.id == str(a.node):
					node = n
			s.why = "Built %s with a tax abatement from the town." % str(node.get("name", "it")).to_lower()
			abatements.append({"who": "site:%d" % int(a.site), "monthly": int(a.monthly),
				"until": sim.tick_count + Balance.ASK_ABATE_YEARS * 12 * TICKS_PER_MONTH})
			sim.industry_changed.emit()
		"pave":
			if not sim.network.segments.has(int(a.seg)) or int(sim.network.segments[int(a.seg)].type) != RoadStyle.Type.GRAVEL:
				return false
			sim.network.set_type(int(a.seg), RoadStyle.Type.COUNTY)
			sim.economy.money -= int(a.cost)
		"signal":
			if not sim.traffic.set_rule(int(a.node), TrafficSim.Rule.SIGNAL):
				return false
			sim.economy.money -= int(a.cost)
		"festival":
			sim.economy.money -= int(a.cost)
			festival_until = sim.tick_count + TICKS_PER_MONTH
	return true


## Drops abatements that have run their course.
func _expire(sim) -> void:
	abatements = abatements.filter(func(x): return int(x.until) > sim.tick_count)


## What abatements cost the town a month (taxes it forgoes).
func monthly_cost() -> int:
	var n := 0
	for x in abatements:
		n += int(x.monthly)
	return n


## Shop demand from a festival this month.
static func festival_demand(sim) -> float:
	return Balance.ASK_FESTIVAL_DEMAND if sim.tick_count < int(sim.leaders.festival_until) else 0.0


# --------------------------------------------------------------- outlines

static func _square(at: Vector3, half: float) -> Array:
	return [[at.x - half, at.z - half], [at.x + half, at.z - half], [at.x + half, at.z + half], [at.x - half, at.z + half]]


## A band `half` metres either side of a road's line.
static func _corridor(pts: PackedVector3Array, half: float) -> Array:
	var line := PackedVector2Array()
	for p in pts:
		line.append(Vector2(p.x, p.z))
	var polys := Geometry2D.offset_polyline(line, half, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	var out := []
	if polys.is_empty():
		return out
	# Keep it to a handful of corners for the bell's map.
	var poly: PackedVector2Array = polys[0]
	var step := maxi(1, poly.size() / 16)
	for i in range(0, poly.size(), step):
		out.append([snappedf(poly[i].x, 0.01), snappedf(poly[i].y, 0.01)])
	return out


func to_dict() -> Dictionary:
	var as_ := {}
	for id in asks:
		as_[str(id)] = asks[id]
	return {"asks": as_, "last": last, "abatements": abatements, "festival": festival_until}


func from_dict(d: Dictionary) -> void:
	asks.clear()
	last.clear()
	abatements.clear()
	festival_until = int(d.get("festival", -1))
	for k in d.get("asks", {}):
		var a: Dictionary = d.asks[k]
		var out := {}
		for f in a:
			var v = a[f]
			out[f] = int(v) if v is float and f != "kind" else v
		asks[int(k)] = out
	for k in d.get("last", {}):
		last[str(k)] = int(d.last[k])
	for x in d.get("abatements", []):
		abatements.append({"who": str(x.who), "monthly": int(x.monthly), "until": int(x.until)})
	changed.emit()
