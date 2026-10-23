class_name Redevelopment
extends RefCounted
## Developers ask to build denser as the town grows (Brawn, 2026-10-23),
## always on the permit bell, because each one is a rezoning, and the
## player is the town that decides:
##   apartments  buy three or four houses side by side and put up a
##               three-storey apartment building (the "missing middle":
##               a walk-up on assembled 50 ft lots, rezoned from
##               single-family, e.g. Chicago RS-3 to RM-5)
##   highrise    a mid-rise apartment building buys the lots next door and
##               goes up 12 storeys (a planned development raising the FAR,
##               like 860-880 Lake Shore Drive's plates of about 900 m²)
##   shopping    buy a whole run of houses along a busy road, rezone it to
##               commercial and build a shopping center (ICSC: a strip or
##               convenience center under about 30,000 sq ft, a
##               neighborhood center with a grocery anchor up to about
##               125,000 sq ft on 3-5 acres)
## A real regional mall needs 40-100 acres, so it is farmland a developer
## asks for (TownCulture's land-use requests), not a city block.
##
## The player's job is the infrastructure: every card says what the project
## adds to the power and water the town has, and to the traffic on its
## street (ITE Trip Generation: about 6.7 car trips a day per walk-up
## apartment, about 37.75 per 1,000 sq ft of shopping center). Saying yes
## without building for it shows up as real problems: homes out of power or
## water, boil notices, gridlock, and then the neighbourhood running down
## (PropertyCare).
##
## Monthly, one ask at a time. Deterministic: sorted keys, seeded picks.

signal changed

const HUB := "developer"
const KINDS := ["apartments", "highrise", "shopping"]

## permit id -> {"kind", "keys", "type", "level", ...}
var asks := {}
## kind -> tick it was last asked
var last := {}
## Which month it is (for the window of street sides looked at).
var _month_no := 0


## Once a game month: maybe a developer asks.
func month(sim) -> void:
	for id in asks:
		if sim.permits.state_of(id) == Permits.State.OPEN:
			return  # one at a time
	_month_no = sim.tick_count / _month_ticks()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.city_seed, sim.tick_count, "redevelop"])
	if rng.randf() >= Balance.REDEV_CHANCE:
		return
	var faces := _faces(sim)
	var order := KINDS.duplicate()
	# Start from a different kind each month, so one doesn't crowd out the rest.
	var start := rng.randi() % order.size()
	for i in order.size():
		var kind: String = order[(start + i) % order.size()]
		if sim.tick_count - int(last.get(kind, -1_000_000_000)) < Balance.REDEV_COOLDOWN_MONTHS * _month_ticks():
			continue
		var plan: Dictionary = call("_plan_" + kind, sim, faces)
		if not plan.is_empty() and _file(sim, plan):
			return


static func _month_ticks() -> int:
	return 24 * CitySim.TICKS_PER_HOUR


func _file(sim, plan: Dictionary) -> bool:
	var hub_id := absi(hash([plan.kind, plan.keys[0]])) % 1_000_000
	if not sim.permits.can_file(sim, HUB, hub_id, true):
		return false
	var area := Heritage._outline(sim, plan.keys)
	if area.size() < 3:
		return false
	var req: int = sim.permits.file(sim, {"hub": HUB, "hub_id": hub_id, "leader": plan.leader,
		"title": plan.title, "why": plan.why, "area": area, "change": plan.change, "ask": "redevelop",
		"yes": plan.yes, "no": plan.no})
	if req <= 0:
		return false
	last[plan.kind] = sim.tick_count
	asks[req] = {"kind": plan.kind, "keys": plan.keys, "type": plan.type, "level": plan.level,
		"was": plan.was}
	changed.emit()
	return true


# --------------------------------------------------------------- the asks

## Three or four houses in a row, close in or on an avenue, in a town that
## needs homes.
func _plan_apartments(sim, faces: Dictionary) -> Dictionary:
	if int(sim.stats.population) < Balance.REDEV_APT_TOWN or float(sim.demand.get(ZoneMap.Zone.RESIDENTIAL, 0.0)) < Balance.REDEV_DEMAND:
		return {}
	var best := []
	var best_score := -INF
	for f in _sorted(faces):
		var face: Array = faces[f]
		if face.size() < 3 or _zone(sim, face[0]) != ZoneMap.Zone.RESIDENTIAL:
			continue
		var avenue := _arterial(sim, face[0])
		for run in _runs(sim, face, ["house"], 3, 4, LotPlanner.MAX_LOT.apartments):
			var dens := _density(sim, sim.lots[run[0]].pos)
			if dens < Balance.DENSE_CORE and not avenue:
				continue
			# Older, cheaper houses close in go first (the classic teardown).
			var score: float = float(dens) + (15.0 if avenue else 0.0) + (1.0 - _avg_cond(sim, run)) * 20.0 + run.size()
			if score > best_score:
				best_score = score
				best = run
	if best.is_empty():
		return {}
	var lvl := 1
	return _plan(sim, "apartments", best, "apartments", lvl,
		"Rezone %d houses for an apartment building" % best.size(),
		"Homes are short in town, and this block is close in. %d houses would make way for a three-storey walk-up." % best.size(),
		"Single-family homes to apartments")


## A mid-rise apartment building that wants to go up, in a city core.
func _plan_highrise(sim, faces: Dictionary) -> Dictionary:
	if int(sim.stats.population) < Balance.REDEV_HIGHRISE_TOWN or float(sim.demand.get(ZoneMap.Zone.RESIDENTIAL, 0.0)) < Balance.REDEV_DEMAND:
		return {}
	var far: float = Balance.REDEV_HIGHRISE_FAR
	var need := BuildingTypes.area_for("apartments", 3, far)
	for f in _sorted(faces):
		var face: Array = faces[f]
		for i in face.size():
			var key: String = face[i]
			var b: Dictionary = sim.buildings.get(key, {})
			if b.is_empty() or BuildingTypes.type_of(b) != "apartments" or int(b.get("level", 0)) != 2 \
					or sim.care.tier_of(key) < 0 or int(b.occ) < int(b.cap) or sim.heritage.protected(key):
				continue
			if _density(sim, sim.lots[key].pos) < Balance.DENSE_CORE * 3:
				continue
			# Buy along the street either side until the site is big enough.
			var keys := [key]
			var area: float = sim.lots[key].area
			var width: float = sim.lots[key].width
			var cap: Array = LotPlanner.MAX_LOT.downtown
			for j in [i + 1, i - 1, i + 2, i - 2]:
				if area >= need or j < 0 or j >= face.size():
					continue
				var k: String = face[j]
				if not _for_sale(sim, k, ["house", "row_home", ""]):
					continue
				if width + float(sim.lots[k].width) > cap[0] or area + float(sim.lots[k].area) > cap[1]:
					continue
				keys.append(k)
				area += float(sim.lots[k].area)
				width += float(sim.lots[k].width)
			if area < need:
				continue
			keys.sort_custom(func(a, c): return sim.lots[a].at_frac < sim.lots[c].at_frac)
			# The building itself stays the site's key (it keeps its tenants' place).
			keys.erase(key)
			keys.push_front(key)
			return _plan(sim, "highrise", keys, "apartments", 3,
				"Rezone for a 12-storey apartment tower",
				"%s is full and the core wants homes. With %s next door the site is big enough to go up." % [
					BuildingTypes.name_of(b), "the lot" if keys.size() == 2 else "%d lots" % (keys.size() - 1)],
				"Mid-rise to high-rise (planned development)")
	return {}


## A run of houses along a busy road in a town big enough to shop.
func _plan_shopping(sim, faces: Dictionary) -> Dictionary:
	if int(sim.stats.population) < Balance.REDEV_SHOP_TOWN or float(sim.demand.get(ZoneMap.Zone.COMMERCIAL, 0.0)) < Balance.REDEV_DEMAND:
		return {}
	var best := []
	var best_score := -INF
	for f in _sorted(faces):
		var face: Array = faces[f]
		if face.size() < Balance.REDEV_SHOP_LOTS or _zone(sim, face[0]) != ZoneMap.Zone.RESIDENTIAL or not _arterial(sim, face[0]):
			continue
		for run in _runs(sim, face, ["house"], Balance.REDEV_SHOP_LOTS, 10, LotPlanner.MAX_LOT.highway_shop):
			var score := float(run.size()) * 3.0 + (1.0 - _avg_cond(sim, run)) * 10.0
			if score > best_score:
				best_score = score
				best = run
	if best.is_empty():
		return {}
	var area := 0.0
	for k in best:
		area += float(sim.lots[k].area)
	var lvl := 1 if area >= Balance.REDEV_CENTER_AREA else 0
	return _plan(sim, "shopping", best, "shopping_center", lvl,
		"Rezone %d homes on %s for a shopping center" % [best.size(), _street(sim, best[0])],
		"Town has grown past what its shops can serve, and this is a busy road. A developer would buy the whole row.",
		"Homes to commercial (shopping center)")


## The card: what's built, and what it asks of the town's power, water
## and street.
func _plan(sim, kind: String, keys: Array, type: String, level: int, title: String, why: String, change: String) -> Dictionary:
	var st: Dictionary = BuildingTypes.TYPES[type].stages[level]
	var load := int(st.get("load", 1))
	var old_load := 0
	var households := 0
	var was := {}
	for k in keys:
		if sim.buildings.has(k):
			old_load += BuildingTypes.load_of(sim.buildings[k])
			households += 1 if int(sim.buildings[k].zone) == ZoneMap.Zone.RESIDENTIAL else 0
			was[k] = BuildingTypes.type_of(sim.buildings[k])
		else:
			was[k] = ""
	var more := load - old_load
	var street := _street(sim, keys[0])
	var trips := 0
	var what := ""
	if type == "apartments":
		var cap: Array = st.cap
		var units := int(cap[1]) / 2
		trips = roundi(units * Balance.REDEV_TRIPS_PER_FLAT)
		what = "about %d flats for %d to %d people" % [units, int(cap[0]), int(cap[1])]
	else:
		var area := 0.0
		for k in keys:
			area += float(sim.lots[k].area)
		var sqft := area * float(BuildingTypes.TYPES[type].cover) * 10.764
		trips = roundi(sqft / 1000.0 * Balance.REDEV_TRIPS_PER_KSQFT)
		what = "%s of about %s sq ft and %d to %d jobs" % [str(st.name).to_lower(), CitySim.money_text(roundi(sqft / 1000.0) * 1000),
			int(st.cap[0]), int(st.cap[1])]
	var strain := []
	for u in ["power", "water"]:
		var use: Array = sim.services.utility_use[u]
		if int(use[1]) > 0 and int(use[0]) + more > int(use[1]):
			strain.append("the town's %s is nearly full (%s of %s), so build more first or homes will lose it" % [
				u, CitySim.money_text(int(use[0])), CitySim.money_text(int(use[1]))])
	var flow := roundi(PropertyCare.street_score(sim, sim.lots[keys[0]]) * 100.0)
	var utilities := ("Power and water: +%d homes' worth." % more) if more > 0 else "Power and water: about the same."
	var yes := "%s replaces %s. %s About %d more car trips a day on %s (it moves at %d%% now)." % [
		what.left(1).to_upper() + what.substr(1), ("%d homes" % households) if households > 0 else "what's there", utilities,
		trips, street, flow]
	if not strain.is_empty():
		yes += " Careful: " + "; ".join(strain) + "."
	var who := "A developer"
	if kind == "highrise":
		var fam: Dictionary = sim.families.family_of("lot:" + str(keys[0]))
		if not fam.is_empty():
			who = str(fam.head)
	return {"kind": kind, "keys": keys, "type": type, "level": level, "leader": who, "title": title,
		"why": why, "change": change, "yes": yes, "no": "The houses stay as they are." if kind != "highrise" else "It stays mid-rise.",
		"was": was}


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
		if st == Permits.State.APPROVED:
			sim.permits.done(id)
			if build(sim, a) and a.kind == "shopping":
				sim.culture.nudge("trade", Balance.CULTURE_YES_LEAN)
		changed.emit()


## Assembles the site and starts the new building. False if things changed
## under the ask (a lot is gone or was rebuilt).
func build(sim, a: Dictionary) -> bool:
	var keys: Array = a.keys
	for k in keys:
		if not sim.lots.has(k) or (sim.buildings.has(k) and BuildingTypes.type_of(sim.buildings[k]) != str(a.was.get(k, ""))) \
				or (not sim.buildings.has(k) and str(a.was.get(k, "")) != ""):
			return false
	var type := str(a.type)
	var zone := int(BuildingTypes.TYPES[type].zone)
	var site: String = keys[0]
	var cap_kind: String = {"apartments": "apartments", "highrise": "downtown", "shopping": "highway_shop"}[str(a.kind)]
	if zone != _zone(sim, site):
		# The rezoning: the whole frontage of every lot changes zone.
		for k in keys:
			var lot: Dictionary = sim.lots[k]
			var w: float = lot.width
			var x := -w * 0.5 + 2.0
			while x <= w * 0.5 - 1.0:
				sim.zones.paint(lot.zone_pt + lot.dir * x, 3.0, zone)
				x += 3.0
		sim.zones_changed.emit()
	for k in keys.slice(1):
		if LotPlanner.merge_lots(sim, site, k, 0.0, cap_kind) != site:
			break
		sim.care.forget(k)
	var bseed: int = sim.buildings[site].seed if sim.buildings.has(site) else hash([sim.city_seed, site, "redevelop"])
	var b := {"zone": zone, "seed": bseed, "built": sim.tick_count, "changed": sim.tick_count, "occ": 0, "focc": 0}
	b = BuildingTypes.make(sim, site, b, type, int(a.level))
	b.fabric = sim.tick_count
	b.why = {"apartments": "The town rezoned these houses for apartments",
		"highrise": "The town approved a high-rise here", "shopping": "The town rezoned this row for shopping"}[str(a.kind)]
	sim.buildings[site] = b
	sim.care.forget(site)
	var lot: Dictionary = sim.lots[site]
	sim.construction.start("lot:" + site, CitySim.PROFILE_OF_ZONE[zone], sim.tick_count, lot.front, -lot.normal, lot.to_curb)
	sim.note_lots([site])
	sim.lots_changed.emit()
	sim.buildings_changed.emit()
	return true


# ---------------------------------------------------------------- helpers

## Every street side's lots in order along it: "seg:side" -> [keys].
static func _faces(sim) -> Dictionary:
	var faces := {}
	for k in sim.lots:
		var lot: Dictionary = sim.lots[k]
		var f := Vector2i(int(lot.seg), int(lot.side))
		if not faces.has(f):
			faces[f] = []
		faces[f].append([float(lot.at_frac), k])
	for f in faces:
		var list: Array = faces[f]
		list.sort()
		faces[f] = list.map(func(e): return e[1])
	return faces


## The street sides a developer looks at this month: a window of them,
## moving on each month, so a big town's month stays a few milliseconds.
func _sorted(faces: Dictionary) -> Array:
	var out := faces.keys()
	out.sort()
	if out.size() <= Balance.REDEV_FACES_PER_MONTH:
		return out
	var start := (_month_no * Balance.REDEV_FACES_PER_MONTH) % out.size()
	var win := out.slice(start, start + Balance.REDEV_FACES_PER_MONTH)
	if win.size() < Balance.REDEV_FACES_PER_MONTH:
		win.append_array(out.slice(0, Balance.REDEV_FACES_PER_MONTH - win.size()))
	return win


static func _zone(sim, key: String) -> int:
	return sim.zones.zone_at(sim.lots[key].zone_pt)


static func _arterial(sim, key: String) -> bool:
	var seg := int(sim.lots[key].seg)
	if not sim.network.segments.has(seg):
		return false
	var t: int = sim.network.segments[seg].type
	return RoadStyle.TYPES[t].lanes >= 4 or t in [RoadStyle.Type.COUNTY, RoadStyle.Type.STRIP,
		RoadStyle.Type.AVENUE, RoadStyle.Type.BOULEVARD]


static func _street(sim, key: String) -> String:
	var n: String = sim.streets.name_of(int(sim.lots[key].seg))
	return n if n != "" else "the street"


## Whether a developer can buy this lot: one of `types` ("" = empty), not
## going up, not protected or loved as an old building.
static func _for_sale(sim, k: String, types: Array) -> bool:
	if not sim.lots.has(k):
		return false
	if not sim.buildings.has(k):
		return "" in types and _zone(sim, k) != ZoneMap.Zone.NONE
	if not BuildingTypes.type_of(sim.buildings[k]) in types or not sim.construction.is_done("lot:" + k, sim.tick_count):
		return false
	return not sim.heritage.protected(k) and float(sim.heritage.charm.get(k, 0.0)) < Balance.HERITAGE_DELAY_CHARM


## Runs of `min_n` to `max_n` lots in a row on one street side that are
## all for sale, within a lot-size cap [frontage, area].
static func _runs(sim, face: Array, types: Array, min_n: int, max_n: int, cap: Array) -> Array:
	var out := []
	var i := 0
	while i < face.size():
		var run := []
		var w := 0.0
		var area := 0.0
		var j := i
		while j < face.size() and run.size() < max_n and _for_sale(sim, face[j], types):
			var lot: Dictionary = sim.lots[face[j]]
			if w + float(lot.width) > cap[0] or area + float(lot.area) > cap[1]:
				break
			run.append(face[j])
			w += float(lot.width)
			area += float(lot.area)
			j += 1
		if run.size() >= min_n:
			out.append(run)
			i = j
		else:
			i += 1
	return out


## About how many buildings stand within the core radius: whole cells of
## PropertyCare's grid whose middles are in reach (cheap enough to ask for
## every run of lots in a big town).
static func _density(sim, p: Vector3) -> int:
	var size := PropertyCare.NEAR_CELL
	var c := Vector2i(floori(p.x / size), floori(p.z / size))
	var r := ceili(Balance.CORE_RADIUS / size)
	var n := 0
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var cell := c + Vector2i(dx, dz)
			var mid := Vector2((cell.x + 0.5) * size, (cell.y + 0.5) * size)
			if mid.distance_to(Vector2(p.x, p.z)) <= Balance.CORE_RADIUS:
				n += int(sim.care._grid.get(cell, 0))
	return n


static func _avg_cond(sim, keys: Array) -> float:
	var t := 0.0
	for k in keys:
		t += sim.care.cond_of(k)
	return t / maxf(keys.size(), 1.0)


func to_dict() -> Dictionary:
	var as_ := {}
	for id in asks:
		as_[str(id)] = asks[id]
	return {"asks": as_, "last": last, "month_no": _month_no}


func from_dict(d: Dictionary) -> void:
	asks.clear()
	last.clear()
	for k in d.get("asks", {}):
		var a: Dictionary = d.asks[k]
		var was := {}
		for w in a.get("was", {}):
			was[str(w)] = str(a.was[w])
		asks[int(k)] = {"kind": str(a.kind), "keys": Array(a.keys).map(func(x): return str(x)),
			"type": str(a.type), "level": int(a.level), "was": was}
	for k in d.get("last", {}):
		last[str(k)] = int(d.last[k])
	_month_no = int(d.get("month_no", 0))
	changed.emit()
