class_name Heritage
extends RefCounted
## Old buildings gain charm (Brawn, 2026-10-23), so the player chooses
## between protecting a historic block and letting it redevelop.
##
## Real references, adapted for a game where a decade passes in an evening:
##   - National Register of Historic Places: a building is "historic" at 50
##     years (here Balance.HERITAGE_AGE_YEARS game years), and a district is a
##     group of buildings most of which contribute to its character.
##   - Indiana's local historic districts (IC 36-7-11): the town council
##     designates a district and a preservation commission reviews changes
##     (a Certificate of Appropriateness); owners can't tear down or add on.
##   - The federal historic rehabilitation tax credit: owners in a district
##     restore instead of replace, so charm grows faster there.
##   - Demolition delay (Bloomington and other Indiana towns): a surveyed
##     building outside a district can't come down without notice; the town
##     can buy a preservation easement (Indiana Landmarks holds hundreds).
##
## How it plays:
##   - Every building ages from when it went up (or was last rebuilt as a
##     different type: "fabric"). Charm grows with age and the kind of
##     building, and lifts land value (and so property tax).
##   - Once a corner of town is mostly historic, it is an eligible district.
##     The county historical society asks on the bell to protect it. Yes:
##     nothing there is torn down or built up, land is worth more, visitors
##     come (shop demand), the commission costs a little each month, and a
##     marker goes up. No: owners rebuild as the town grows. The player can
##     protect or lift protection any time from a building's panel.
##   - An owner who wants to tear down a charming building outside a
##     district asks first (demolition delay). Yes: it comes down for the
##     bigger building. No: the town buys an easement and it stays for good.
## Answers lean the town: protecting leans it toward its history, which can
## earn a "Historic" nickname (TownNickname); letting a block go leans its
## reputation (TownCulture) toward the trade that replaces it.
##
## Monthly and O(buildings). Charm, lift and district membership are worked
## out again after a load, so only districts, easements and asks are saved.

signal changed

const TICKS_PER_YEAR := 12 * 24 * CitySim.TICKS_PER_HOUR
## The historical society's asks on the bell, and owners' demolition asks.
const HUB := "heritage"
const OWNER := "owner"

## id -> {"id", "name", "cells": [[i, j], ...], "state": "eligible" |
## "protected", "since": tick it was protected (-1), "declined": tick of the
## last no (-1), "req": open permit id (-1)}.
var districts := {}
var next_id := 1
## lot key -> calendar year the town bought a preservation easement on it.
var easements := {}
## permit id -> what it was for: {"kind": "district", "district"} or
## {"kind": "demolish", "key", "type", "level", "cost"}.
var asks := {}
## Worked out monthly (not saved): lot key -> charm 0..1, -> land factor,
## -> district id.
var charm := {}
var lift := {}
var district_of := {}
## The historical society's president (named once, saved).
var president := ""
var _computed := false


# ------------------------------------------------------------------- ages

## Game years since a building's fabric went up.
static func age_years(sim, b: Dictionary) -> float:
	return float(sim.tick_count - int(b.get("fabric", b.built))) / TICKS_PER_YEAR


## True when a building is old enough to count toward a district.
static func is_historic(sim, b: Dictionary) -> bool:
	return age_years(sim, b) >= Balance.HERITAGE_AGE_YEARS


## Charm 0..1 from age and kind; more where it is protected.
static func charm_for(sim, b: Dictionary, protected: bool) -> float:
	var age := age_years(sim, b)
	var ramp := clampf((age - Balance.HERITAGE_CHARM_FROM_YEARS)
		/ float(Balance.HERITAGE_FULL_YEARS - Balance.HERITAGE_CHARM_FROM_YEARS), 0.0, 1.0)
	var w := float(Balance.HERITAGE_TYPE_WEIGHT.get(BuildingTypes.type_of(b), 0.5))
	return clampf(ramp * w * (Balance.HERITAGE_PROTECTED_CHARM if protected else 1.0), 0.0, 1.0)


# ---------------------------------------------------------------- monthly

## Once a game month: districts and the society's asks. Charm and land
## value follow an hour later (month_charm), so neither hour carries both.
func month(sim) -> void:
	_districts(sim)
	_ask_districts(sim)
	changed.emit()


func month_charm(sim) -> void:
	_charm(sim)
	changed.emit()


## Recomputes after a load (charm and districts aren't saved).
func ensure(sim) -> void:
	if not _computed:
		_districts(sim)
		_charm(sim)


## Finds the town's historic districts: squares that are mostly historic,
## joined where they touch. Protected districts keep their boundary (it was
## set by ordinance); eligible ones follow the town. One pass over the
## buildings; nothing here depends on the order they're visited in.
func _districts(sim) -> void:
	_computed = true
	var held := {}  # cell -> protected district id
	for id in districts:
		if districts[id].state == "protected":
			for c in districts[id].cells:
				held[Vector2i(int(c[0]), int(c[1]))] = id
	var count := {}  # cell -> [buildings, historic]
	var cell_of := {}  # key -> cell, outside protected districts
	district_of.clear()
	var oldest: int = sim.tick_count - Balance.HERITAGE_AGE_YEARS * TICKS_PER_YEAR
	var inv := 1.0 / Balance.HERITAGE_CELL
	var lots: Dictionary = sim.lots
	for key in sim.buildings:
		var lot = lots.get(key)
		if lot == null:
			continue
		var p: Vector3 = lot.pos
		var c := Vector2i(floori(p.x * inv), floori(p.z * inv))
		var h = held.get(c)
		if h != null:
			district_of[key] = h
			continue
		cell_of[key] = c
		var n = count.get(c)
		if n == null:
			n = [0, 0]
			count[c] = n
		n[0] += 1
		var b: Dictionary = sim.buildings[key]
		if int(b.get("fabric", b.built)) <= oldest:
			n[1] += 1
	var ok := {}
	for c in count:
		if int(count[c][1]) >= Balance.HERITAGE_DISTRICT_MIN \
				and float(count[c][1]) >= Balance.HERITAGE_DISTRICT_SHARE * float(count[c][0]):
			ok[c] = true
	# Join touching squares, in a fixed order so every copy agrees.
	var cells := ok.keys()
	cells.sort()
	var groups := []
	var seen := {}
	for c in cells:
		if seen.has(c):
			continue
		var group := []
		var todo := [c]
		seen[c] = true
		while not todo.is_empty():
			var q: Vector2i = todo.pop_back()
			group.append(q)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if ok.has(q + d) and not seen.has(q + d):
					seen[q + d] = true
					todo.append(q + d)
		group.sort()
		groups.append(group)
	# Keep the id, name and history of an eligible district the new group
	# overlaps most; drop the ones that are gone (their open asks too).
	var old := {}
	for id in districts:
		if districts[id].state == "eligible":
			old[id] = true
	var ids := old.keys()
	ids.sort()
	var owner := {}  # cell -> district id
	for group in groups:
		var in_group := {}
		for c in group:
			in_group[c] = true
		var best := -1
		var best_n := 0
		for id in ids:
			if not old.has(id):
				continue
			var n := 0
			for c in districts[id].cells:
				if in_group.has(Vector2i(int(c[0]), int(c[1]))):
					n += 1
			if n > best_n:
				best_n = n
				best = id
		if best == -1:
			best = next_id
			next_id += 1
			districts[best] = {"id": best, "name": "", "cells": [], "state": "eligible", "since": -1,
				"declined": -1, "req": -1}
		else:
			old.erase(best)
		districts[best].cells = group.map(func(c): return [c.x, c.y])
		for c in group:
			owner[c] = best
	if not owner.is_empty():
		for key in cell_of:
			var id = owner.get(cell_of[key])
			if id != null:
				district_of[key] = id
	for id in old:
		var req := int(districts[id].req)
		if req != -1:
			sim.permits.withdraw(req)
			asks.erase(req)
		districts.erase(id)
	for id in districts:
		if str(districts[id].name) == "":
			districts[id].name = _name_for(sim, id)


## "Main Street Historic District": the street most of its buildings face.
func _name_for(sim, id: int) -> String:
	var streets := {}
	for key in district_of:
		if district_of[key] == id and sim.lots.has(key):
			var s: String = sim.streets.name_of(int(sim.lots[key].seg))
			if s != "":
				streets[s] = int(streets.get(s, 0)) + 1
	var order := streets.keys()
	order.sort_custom(func(a, b): return streets[a] > streets[b] or (streets[a] == streets[b] and a < b))
	var taken := {}
	for other in districts:
		taken[str(districts[other].name)] = true
	for s in order + ["Old Town"]:
		var n := "%s Historic District" % s
		if not taken.has(n):
			return n
	return "Historic District No. %d" % id


## Charm and the land value it lifts, for every building (charm_for,
## inlined: this runs over every building in town).
func _charm(sim) -> void:
	charm.clear()
	lift.clear()
	var kept_ids := {}
	for id in districts:
		if districts[id].state == "protected":
			kept_ids[id] = true
	var now: int = sim.tick_count
	var from := float(Balance.HERITAGE_CHARM_FROM_YEARS)
	var span := float(Balance.HERITAGE_FULL_YEARS - Balance.HERITAGE_CHARM_FROM_YEARS)
	var first := now - Balance.HERITAGE_CHARM_FROM_YEARS * TICKS_PER_YEAR
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		var built := int(b.get("fabric", b.built))
		var inside: bool = not kept_ids.is_empty() and kept_ids.has(district_of.get(key, -1))
		if built >= first and not inside:
			continue  # too new for any charm
		var ramp := clampf((float(now - built) / TICKS_PER_YEAR - from) / span, 0.0, 1.0)
		var w := float(Balance.HERITAGE_TYPE_WEIGHT.get(BuildingTypes.type_of(b), 0.5))
		var kept := inside or easements.has(key)
		var c := clampf(ramp * w * (Balance.HERITAGE_PROTECTED_CHARM if kept else 1.0), 0.0, 1.0)
		if c <= 0.0 and not inside:
			continue
		charm[key] = snappedf(c, 0.001)
		if inside:
			lift[key] = 1.0 + Balance.HERITAGE_DISTRICT_LIFT * (0.5 + 0.5 * c)
		elif c > 0.0:
			lift[key] = 1.0 + Balance.HERITAGE_LAND_LIFT * c


# ------------------------------------------------------------- what it does

## Land value factor from charm (CitySim.land_factor).
func land(key: String) -> float:
	return float(lift.get(key, 1.0))


func protected(key: String) -> bool:
	return easements.has(key) or (district_of.has(key) and districts.has(district_of[key])
		and districts[district_of[key]].state == "protected")


## Buildings inside protected districts.
func protected_count() -> int:
	var n := 0
	for key in district_of:
		if districts.has(district_of[key]) and districts[district_of[key]].state == "protected":
			n += 1
	return n


## What the preservation commission costs the town a month.
func monthly_cost() -> int:
	var n := 0
	for id in districts:
		if districts[id].state == "protected":
			n += 1
	return n * Balance.HERITAGE_COMMISSION_MONTHLY


## Shop demand from visitors who come to walk the old districts.
func tourism_demand() -> float:
	var sizes := {}
	for key in district_of:
		var id: int = district_of[key]
		if districts.has(id) and districts[id].state == "protected":
			sizes[id] = int(sizes.get(id, 0)) + 1
	var d := 0.0
	for id in sizes:
		d += Balance.HERITAGE_TOURISM_DEMAND * minf(1.0, float(sizes[id]) / Balance.HERITAGE_TOURISM_FULL)
	return d


## Whether an owner may rebuild this building as `type` (CitySim, before
## redevelop). Protected buildings stay as they are. A charming one that
## would be torn down for another type asks the town first.
func allow(sim, key: String, type: String, level: int) -> bool:
	if protected(key):
		return false
	var b: Dictionary = sim.buildings[key]
	if type == BuildingTypes.type_of(b) or float(charm.get(key, 0.0)) < Balance.HERITAGE_DELAY_CHARM:
		return true
	for id in asks:
		if str(asks[id].get("key", "")) == key:
			return false  # already asked
	var hub_id := _owner_id(key)
	if not sim.permits.can_file(sim, OWNER, hub_id, true):
		return false
	var ref := "lot:" + key
	var name: String = sim.families.name_of(ref)
	if name == "":
		name = Families.home_name(b) if int(b.zone) == ZoneMap.Zone.RESIDENTIAL else "old " + BuildingTypes.name_of(b).to_lower()
	var fam: Dictionary = sim.families.family_of(ref)
	var who := str(fam.head) if not fam.is_empty() else "The owner"
	var built := Families.calendar(Seasons.year(int(b.get("fabric", b.built)) + sim.calendar_offset))
	var new_stage: Dictionary = BuildingTypes.TYPES[type].stages[level]
	var gain := ""
	var st_cap: Array = new_stage.get("cap", [0, 0])
	if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
		gain = "room for more families"
	elif new_stage.has("flats"):
		gain = "shops below and flats above"
	elif not st_cap.is_empty() and int(st_cap[1]) > int(b.cap):
		gain = "up to %d jobs" % int(st_cap[1])
	var cost := easement_cost(b)
	var area := []
	for p in sim.lots[key].corners:
		area.append([p.x, p.y])
	var req: int = sim.permits.file(sim, {"hub": OWNER, "hub_id": hub_id, "leader": who,
		"title": "Tear down %s (built %d) for a %s" % [name, built, str(new_stage.name).to_lower()],
		"why": "It's one of the town's old buildings, so it can't come down without a word to the town.",
		"area": area, "change": "Old building replaced", "ask": "demolish",
		"yes": "It comes down for a %s%s. Its charm is gone for good." % [str(new_stage.name).to_lower(),
			(", " + gain) if gain != "" else ""],
		"no": "The town buys a preservation easement for $%s, and it stays as it is for good." % CitySim.money_text(cost)})
	if req > 0:
		asks[req] = {"kind": "demolish", "key": key, "type": type, "level": level, "cost": cost}
	return false


## What a preservation easement on this building costs the town.
static func easement_cost(b: Dictionary) -> int:
	return Balance.HERITAGE_EASEMENT_BASE + Balance.HERITAGE_EASEMENT_PER_STOREY * maxi(1, BuildingTypes.storeys(b))


## A stable number for an owner's lot on the bell (Permits wants an int).
static func _owner_id(key: String) -> int:
	return absi(hash(["owner", key])) % 1_000_000_000


## The society asks about one eligible district at a time.
func _ask_districts(sim) -> void:
	for id in districts:
		if int(districts[id].req) != -1:
			return
	var ids := districts.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = districts[id]
		if d.state != "eligible":
			continue
		if int(d.declined) != -1 and sim.tick_count - int(d.declined) < Balance.HERITAGE_REASK_YEARS * TICKS_PER_YEAR:
			continue
		if not sim.permits.can_file(sim, HUB, id, true):
			continue
		var members := []
		var old := 0
		for key in district_of:
			if district_of[key] == id:
				members.append(key)
				if is_historic(sim, sim.buildings[key]):
					old += 1
		var hull := _outline(sim, members)
		if hull.size() < 3:
			continue
		if president == "":
			president = "%s %s" % [Names.FIRST_NEW[absi(hash([sim.city_seed, "society"])) % Names.FIRST_NEW.size()],
				Names.surname(hash([sim.city_seed, "society"]))]
		var req: int = sim.permits.file(sim, {"hub": HUB, "hub_id": id,
			"leader": "%s, %s Historical Society" % [president, TownNickname.COUNTY],
			"title": "Protect the %s" % d.name,
			"why": "%d of its buildings date from the town's early years and still stand together." % old,
			"area": hull, "change": "Local historic district", "ask": "district",
			"yes": "Nothing there is torn down or built up. Land there is worth up to %d%% more, visitors come to walk it, and the commission costs $%s a day." % [
				roundi(Balance.HERITAGE_DISTRICT_LIFT * 100.0), CitySim.money_text(Balance.HERITAGE_COMMISSION_MONTHLY)],
			"no": "Owners may rebuild as the town grows. The society may ask again in %d years." % Balance.HERITAGE_REASK_YEARS})
		if req > 0:
			d.req = req
			asks[req] = {"kind": "district", "district": id}
			return


## The outline around some lots: the hull of their corners.
static func _outline(sim, keys: Array) -> Array:
	var pts := PackedVector2Array()
	for key in keys:
		if sim.lots.has(key):
			pts.append_array(sim.lots[key].corners)
	if pts.size() < 3:
		return []
	var hull := Geometry2D.convex_hull(pts)
	var out := []
	for i in hull.size() - 1:  # the hull repeats its first point
		out.append([hull[i].x, hull[i].y])
	return out


## Carries out the player's answers (CitySim, every game hour).
func carry_out(sim) -> void:
	if asks.is_empty():
		return
	var ids := asks.keys()
	ids.sort()
	for id in ids:
		var a: Dictionary = asks[id]
		var st: int = sim.permits.state_of(id)
		if st == Permits.State.OPEN or st == Permits.State.SHELVED:
			continue
		asks.erase(id)
		match str(a.kind):
			"district":
				var did := int(a.district)
				if not districts.has(did):
					continue
				districts[did].req = -1
				if st == Permits.State.APPROVED:
					set_protected(sim, did, true)
					sim.permits.done(id)
				elif st == Permits.State.DENIED:
					districts[did].declined = sim.tick_count
					sim.culture.nudge("trade", Balance.CULTURE_NO_LEAN)
			"demolish":
				var key := str(a.key)
				if st == Permits.State.APPROVED:
					sim.permits.done(id)
					if sim.buildings.has(key) and not protected(key):
						sim.redevelop(key, str(a.type), int(a.level))
						charm.erase(key)
						lift.erase(key)
						sim.culture.nudge(_axis_of(str(a.type)), Balance.CULTURE_YES_LEAN)
				elif st == Permits.State.DENIED and sim.buildings.has(key):
					sim.economy.money -= int(a.cost)
					easements[key] = Families.calendar(Seasons.year(sim.calendar_tick()))
					sim.nicknames.lean_historic(Balance.NICKNAME_HISTORIC_LEAN)
		changed.emit()


static func _axis_of(type: String) -> String:
	match type:
		"office": return "office"
		"shop", "mixed_use": return "trade"
		"factory": return "manufacturing"
	return "trade"


## Protects a district, or lifts its protection (the player's word, from the
## bell or a building's panel: CitySim.apply {"type": "heritage", "district",
## "protect"}).
func set_protected(sim, id: int, on: bool) -> bool:
	if not districts.has(id):
		return false
	var d: Dictionary = districts[id]
	if (d.state == "protected") == on:
		return false
	d.state = "protected" if on else "eligible"
	d.since = sim.tick_count if on else -1
	if on:
		if int(d.req) != -1:
			sim.permits.withdraw(int(d.req))
			asks.erase(int(d.req))
			d.req = -1
		sim.nicknames.lean_historic(Balance.NICKNAME_HISTORIC_LEAN)
		sim.markers.district(sim, d, _outline(sim, _members(id)))
	else:
		# Lifting it is a no to the society, for now.
		d.declined = sim.tick_count
		sim.culture.nudge("trade", Balance.CULTURE_NO_LEAN)
	_districts(sim)
	_charm(sim)
	changed.emit()
	return true


func _members(id: int) -> Array:
	var out := []
	for key in district_of:
		if district_of[key] == id:
			out.append(key)
	out.sort()
	return out


# ---------------------------------------------------------------- panels

## Rows for a building's info panel.
func rows(sim, key: String) -> Array:
	var b: Dictionary = sim.buildings[key]
	var out := []
	var year := Families.calendar(Seasons.year(int(b.get("fabric", b.built)) + sim.calendar_offset))
	out.append(["Built", ("%d, historic" % year) if is_historic(sim, b) else str(year)])
	var c := float(charm.get(key, 0.0))
	if c > 0.0:
		out.append(["Charm", "%d%%" % roundi(c * 100.0)])
	if district_of.has(key) and districts.has(district_of[key]):
		var d: Dictionary = districts[district_of[key]]
		out.append(["Historic district", "%s (%s)" % [d.name,
			"protected since %d" % Families.calendar(Seasons.year(int(d.since) + sim.calendar_offset)) if d.state == "protected"
			else "eligible, not protected"]])
	if easements.has(key):
		out.append(["Preservation easement", "Since %d" % int(easements[key])])
	return out


## Buttons for a building's info panel: protect its district or lift it.
func actions(_sim, key: String) -> Array:
	if not district_of.has(key) or not districts.has(district_of[key]):
		return []
	var d: Dictionary = districts[district_of[key]]
	if d.state == "protected":
		return [{"label": "Lift protection from the %s" % d.name,
			"cmd": {"type": "heritage", "district": int(d.id), "protect": false}}]
	return [{"label": "Protect the %s" % d.name, "cmd": {"type": "heritage", "district": int(d.id), "protect": true}}]


## Districts for the Town panel, protected first.
func listed() -> Array:
	var ids := districts.keys()
	ids.sort()
	var out := []
	for id in ids:
		var n := 0
		for key in district_of:
			if district_of[key] == id:
				n += 1
		out.append({"id": id, "name": districts[id].name, "state": districts[id].state, "buildings": n,
			"since": int(districts[id].since)})
	out.sort_custom(func(a, b): return a.state == "protected" and b.state != "protected")
	return out


# ------------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	var ds := []
	var ids := districts.keys()
	ids.sort()
	for id in ids:
		ds.append(districts[id])
	var as_ := {}
	for id in asks:
		as_[str(id)] = asks[id]
	return {"districts": ds, "next": next_id, "easements": easements, "asks": as_, "president": president}


func from_dict(d: Dictionary) -> void:
	districts.clear()
	easements.clear()
	asks.clear()
	charm.clear()
	lift.clear()
	district_of.clear()
	_computed = false
	for x in d.get("districts", []):
		districts[int(x.id)] = {"id": int(x.id), "name": str(x.name),
			"cells": x.cells.map(func(c): return [int(c[0]), int(c[1])]), "state": str(x.state),
			"since": int(x.since), "declined": int(x.declined), "req": int(x.req)}
	next_id = int(d.get("next", 1))
	for k in d.get("easements", {}):
		easements[str(k)] = int(d.easements[k])
	for k in d.get("asks", {}):
		var a: Dictionary = d.asks[k]
		var out := {"kind": str(a.kind)}
		if out.kind == "district":
			out.district = int(a.district)
		else:
			out.merge({"key": str(a.key), "type": str(a.type), "level": int(a.level), "cost": int(a.cost)})
		asks[int(k)] = out
	president = str(d.get("president", ""))
	changed.emit()
