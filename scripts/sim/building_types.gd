class_name BuildingTypes
extends RefCounted
## What gets built on a zoned lot. The player zones street frontage for homes,
## shops or industry; each lot's owner then picks a building type from what is
## around it, the way a real developer would:
##   - shops with flats upstairs once a street side has become a Main Street
##   - row homes where land is dear (a built-up area), apartments in the
##     dense core and on avenues
##   - offices once the town has college graduates to hire (Education works
##     out how many office jobs they support; office buildings house them)
## Each type has its own growth path (stages), and some types turn into
## another at the top of theirs (a corner store gains flats upstairs once its
## street is a Main Street; a house in a pricey area makes way for row homes).
## Benchmarks: CS2's building levels, and real Midwestern towns (reality wins).
##
## A building: {"zone", "seed", "built", "cap", "occ", "type", "level",
## "units", "flats", "focc", "changed", "why"}. `cap`/`occ` are residents for
## homes and jobs for businesses. `flats`/`focc` are residents living above a
## shop. `units` is how many side-by-side homes a row takes.
## Everything here is deterministic (multiplayer copies must agree).

const RES := ZoneMap.Zone.RESIDENTIAL
const COM := ZoneMap.Zone.COMMERCIAL
const IND := ZoneMap.Zone.INDUSTRIAL

## Each stage: name, storeys, `cap` [min, max] (or `per_unit` for row homes),
## `flats` [min, max] above a shop, and `load` (power and water draw, in
## multiples of the zone's usual building).
const TYPES := {
	"house": {"zone": RES, "name": "House", "becomes": ["row_home"], "stages": [
		# A ranch, colonial or split-level (storeys 0: the seed picks).
		{"name": "Family home", "storeys": 0, "cap": [2, 4]},
		{"name": "Two-storey home", "storeys": 2, "cap": [4, 5]},
	]},
	# A real row-house lot is 6-8 m wide (20-25 ft).
	"row_home": {"zone": RES, "name": "Row homes", "unit_w": 7.5, "stages": [
		{"name": "Row homes", "storeys": 2, "per_unit": 3},
		{"name": "Three-storey row homes", "storeys": 3, "per_unit": 4},
	]},
	"apartments": {"zone": RES, "name": "Apartments", "stages": [
		{"name": "Walk-up apartments", "storeys": 2, "cap": [10, 14], "load": 4},
		{"name": "Three-storey apartments", "storeys": 3, "cap": [18, 24], "load": 7},
		{"name": "Mid-rise apartments", "storeys": 5, "cap": [36, 48], "load": 14},
	]},
	"shop": {"zone": COM, "name": "Shop", "becomes": ["mixed_use"], "stages": [
		{"name": "Corner store", "storeys": 1, "cap": [6, 10]},
		{"name": "Retail store", "storeys": 1, "cap": [11, 16]},
	]},
	"mixed_use": {"zone": COM, "name": "Shop with flats", "stages": [
		{"name": "Main Street block", "storeys": 2, "cap": [6, 10], "flats": [3, 5]},
		{"name": "Three-storey Main Street block", "storeys": 3, "cap": [8, 12], "flats": [8, 12], "load": 2},
		{"name": "Four-storey Main Street block", "storeys": 4, "cap": [10, 14], "flats": [14, 20], "load": 3},
	]},
	"office": {"zone": COM, "name": "Offices", "stages": [
		{"name": "Office building", "storeys": 3, "cap": [40, 50], "load": 3},
		{"name": "Five-storey offices", "storeys": 5, "cap": [80, 100], "load": 6},
		{"name": "Office tower", "storeys": 8, "cap": [140, 170], "load": 10},
	]},
	"factory": {"zone": IND, "name": "Factory", "stages": [
		{"name": "Factory", "storeys": 1, "cap": [18, 36]},
	]},
}

## What an owner builds when nothing nudges it elsewhere (and what buildings
## from older saves are).
const DEFAULT := {RES: "house", COM: "shop", IND: "factory"}


static func default_type(zone: int) -> String:
	return DEFAULT.get(zone, "house")


static func type_of(b: Dictionary) -> String:
	var t: String = b.get("type", "")
	return t if TYPES.has(t) else default_type(int(b.zone))


static func stage(b: Dictionary) -> Dictionary:
	var stages: Array = TYPES[type_of(b)].stages
	return stages[clampi(int(b.get("level", 0)), 0, stages.size() - 1)]


## "Main Street block", "Office tower", ...
static func name_of(b: Dictionary) -> String:
	return stage(b).name


static func storeys(b: Dictionary) -> int:
	return int(stage(b).storeys)


## Power and water draw, in multiples of the zone's usual building.
static func load_of(b: Dictionary) -> int:
	if type_of(b) == "row_home":
		return maxi(1, int(b.get("units", 1)))
	return int(stage(b).get("load", 1))


## How many row homes fit side by side on the lot.
static func row_units(sim, key: String) -> int:
	var w: float = sim.lots[key].get("width", 20.0) if sim.lots.has(key) else 20.0
	return maxi(2, floori(w / TYPES.row_home.unit_w))


## The building's numbers for a type and stage. Keeps its seed and age.
static func make(sim, key: String, b: Dictionary, type: String, level: int) -> Dictionary:
	var out := b.duplicate()
	var st: Dictionary = TYPES[type].stages[level]
	var r := absi(int(b.seed))
	out.type = type
	out.level = level
	out.units = 1
	if type == "row_home":
		out.units = row_units(sim, key)
		out.cap = out.units * int(st.per_unit)
	else:
		out.cap = _roll(st.cap, r)
	out.flats = _roll(st.flats, r / 7) if st.has("flats") else 0
	out.occ = mini(int(b.get("occ", 0)), out.cap) if int(b.zone) == RES else 0
	out.focc = mini(int(b.get("focc", 0)), out.flats)
	out.changed = int(b.get("changed", b.built))
	out.why = str(b.get("why", ""))
	return out


static func _roll(range_: Array, r: int) -> int:
	return int(range_[0]) + r % (int(range_[1]) - int(range_[0]) + 1)


# ------------------------------------------------------------- surroundings

## What an owner sees around a lot: how built-up it is, the road, whether
## its street side is a Main Street, how well-off the area is, and how many
## college graduates are free to fill office jobs.
static func context(sim, key: String) -> Dictionary:
	var lot: Dictionary = sim.lots[key]
	var p: Vector3 = lot.pos
	var density := 0
	for k in sim.buildings:
		if k != key and sim.lots.has(k) and sim.lots[k].pos.distance_to(p) <= Balance.CORE_RADIUS:
			density += 1
	var shops := 0
	for k in LotPlanner.block_face(sim, key):
		if k != key and sim.buildings.has(k) and int(sim.buildings[k].zone) == COM \
				and type_of(sim.buildings[k]) != "office":
			shops += 1
	var road: int = sim.network.segments[lot.seg].type if sim.network.segments.has(lot.seg) else 0
	return {
		"density": density,
		"shops": shops,
		"main_street": shops >= Balance.MAIN_STREET_SHOPS,
		"avenue": road == RoadStyle.Type.AVENUE or road == RoadStyle.Type.BOULEVARD,
		"wealth": sim.wealth_at(Vector2(p.x, p.z)),
		"graduates_free": graduates_free(sim),
	}


## Office jobs the town's college graduates support (scripts/sim/education.gd)
## that no office building holds yet.
static func graduates_free(sim) -> int:
	return sim.education.office_jobs() - office_jobs(sim)


## Jobs in office buildings across town (each needs a graduate).
static func office_jobs(sim) -> int:
	var n := 0
	for k in sim.buildings:
		if type_of(sim.buildings[k]) == "office":
			n += int(sim.buildings[k].cap)
	return n


# ----------------------------------------------------------------- choosing

## The type a new building on this lot takes, and why: [type, reason].
## Wealthier areas lean to detached houses and away from apartments.
static func pick(sim, key: String, zone: int, rng: RandomNumberGenerator) -> Array:
	var c := context(sim, key)
	var rich: float = c.wealth
	var dens := float(c.density)
	var weights := []  # [type, weight, why]
	match zone:
		RES:
			weights.append(["house", maxf(0.2, 1.0 - dens / 80.0) * (0.5 + rich), "Room for a house and yard"])
			if c.density >= Balance.ROW_HOME_DENSITY:
				weights.append(["row_home", clampf((dens - Balance.ROW_HOME_DENSITY) / 30.0 + 0.4, 0.0, 1.5)
					* (1.3 - rich), "Land is dear here, so homes share walls"])
			if c.density >= Balance.DENSE_CORE or c.avenue:
				var w := (0.8 if c.avenue else 0.0) + clampf((dens - Balance.DENSE_CORE) / 40.0, 0.0, 1.0)
				weights.append(["apartments", w * (1.3 - rich), "On an avenue" if c.avenue else "Close to the centre of town"])
		COM:
			if c.main_street:
				weights.append(["mixed_use", 1.5, "A busy Main Street: shop below, flats above"])
				weights.append(["shop", 0.3, "A shop on Main Street"])
			else:
				weights.append(["shop", 1.0, "A shop for the neighborhood"])
				weights.append(["mixed_use", 0.15, "Shop below, flats above"])
			if c.graduates_free >= int(TYPES.office.stages[0].cap[1]):
				weights.append(["office", 0.6 + dens / 50.0, "The town has college graduates to hire"])
		_:
			weights.append([default_type(zone), 1.0, ""])
	var total := 0.0
	for w in weights:
		total += w[1]
	var roll := rng.randf() * total
	for w in weights:
		roll -= w[1]
		if roll <= 0.0:
			return [w[0], w[2]]
	return [weights[-1][0], weights[-1][2]]


## Where a grown building can go next: [[type, level], ...]. Up its own path
## first; at the top, into another type when the area calls for it.
static func options(sim, key: String) -> Array:
	var b: Dictionary = sim.buildings[key]
	var t := type_of(b)
	var lvl := int(b.get("level", 0))
	var c := context(sim, key)
	var out := []
	if lvl + 1 < TYPES[t].stages.size() and _stage_ok(sim, b, t, lvl + 1, c):
		out.append([t, lvl + 1])
	for nt in TYPES[t].get("becomes", []):
		if _stage_ok(sim, b, nt, 0, c):
			out.append([nt, 0])
	return out


## Whether the area supports this stage.
static func _stage_ok(sim, b: Dictionary, type: String, level: int, c: Dictionary) -> bool:
	match [type, level]:
		["house", 1]: return true
		["row_home", 0]: return c.density >= Balance.ROW_HOME_DENSITY * 2 and c.wealth < 0.7
		["row_home", 1]: return c.density >= Balance.ROW_HOME_DENSITY + 15
		["apartments", 1]: return c.density >= Balance.DENSE_CORE + 10
		["apartments", 2]: return c.density >= Balance.DENSE_CORE * 3 or (c.avenue and c.density >= Balance.DENSE_CORE * 2)
		["shop", 1]: return true
		["mixed_use", 0]: return c.main_street
		["mixed_use", _]: return c.main_street and c.density >= Balance.DENSE_CORE * level
		["office", _]:
			var more := int(TYPES.office.stages[level].cap[1]) - (int(b.cap) if type_of(b) == "office" else 0)
			return c.graduates_free >= more
	return false


## How keen an owner is to build more, 0 (very) to 1 (content), from the
## building's seed: the same on every copy of the city.
static func ambition(b: Dictionary) -> float:
	return float((absi(int(b.seed)) / 13) % 100) / 100.0


## Whether a building is ready to grow: old enough, open, full, wanted, and
## its owner keen enough. Well-off areas have more owners who build on
## (about half at an average neighborhood, most in a thriving one).
static func ready(sim, key: String) -> bool:
	var b: Dictionary = sim.buildings[key]
	if sim.tick_count - int(b.get("changed", b.built)) < Balance.DEVELOP_AGE or not sim.utilities_ok(key):
		return false
	var p: Vector3 = sim.lots[key].pos
	if ambition(b) > Balance.DEVELOP_KEEN + Balance.DEVELOP_KEEN_WEALTH * sim.wealth_at(Vector2(p.x, p.z)):
		return false
	var z := int(b.zone)
	if z == RES:
		return int(b.occ) >= int(b.cap) and sim.demand[RES] > 0.2
	if int(b.get("flats", 0)) > 0 and int(b.focc) < int(b.flats):
		return false
	return sim.demand.get(z, 0.0) > 0.3
