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
## Above all, only what the market supports (Market, Brawn 2026-10-24): the
## people within commuting reach, the town's and its neighbors'. A remote
## hamlet gets houses and a Main Street however dense its blocks are;
## apartments, row homes, offices and towers wait for the market to grow.
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
## `flats` [min, max] above a shop, `load` (power and water draw, in
## multiples of the zone's usual building) and, for towers, `plate`: the
## floor plate in m² (a high-rise's lifts, stairs and the offices or flats
## around them need about this much whatever the lot). Each type's `cover`
## is the share of its lot a floor covers, so its floor-area ratio is
## storeys × cover, or storeys × plate ÷ lot area for a tower: under the
## area's FAR a tower needs a big lot, so towers assemble lots (assemble()).
const TYPES := {
	"house": {"zone": RES, "name": "House", "becomes": ["row_home"], "cover": 0.25, "stages": [
		# A ranch, colonial or split-level (storeys 0: the seed picks).
		{"name": "Family home", "storeys": 0, "cap": [2, 4]},
		{"name": "Two-storey home", "storeys": 2, "cap": [4, 5]},
	]},
	# A real row-house lot is 6-8 m wide (20-25 ft).
	"row_home": {"zone": RES, "name": "Row homes", "unit_w": 7.5, "cover": 0.4, "stages": [
		{"name": "Row homes", "storeys": 2, "per_unit": 3},
		{"name": "Three-storey row homes", "storeys": 3, "per_unit": 4},
	]},
	"apartments": {"zone": RES, "name": "Apartments", "cover": 0.4, "stages": [
		{"name": "Walk-up apartments", "storeys": 2, "cap": [10, 14], "load": 4},
		{"name": "Three-storey apartments", "storeys": 3, "cap": [18, 24], "load": 7},
		{"name": "Mid-rise apartments", "storeys": 5, "cap": [36, 48], "load": 14},
		# 860-880 Lake Shore Drive: 26 storeys on plates of about 900 m².
		{"name": "High-rise apartments", "storeys": 12, "cap": [110, 140], "load": 40, "plate": 900.0},
		{"name": "Apartment tower", "storeys": 24, "cap": [220, 280], "load": 80, "plate": 900.0},
	]},
	"shop": {"zone": COM, "name": "Shop", "becomes": ["mixed_use"], "cover": 0.35, "stages": [
		{"name": "Corner store", "storeys": 1, "cap": [6, 10]},
		{"name": "Retail store", "storeys": 1, "cap": [11, 16]},
	]},
	"mixed_use": {"zone": COM, "name": "Shop with flats", "cover": 0.85, "stages": [
		{"name": "Main Street block", "storeys": 2, "cap": [6, 10], "flats": [3, 5]},
		{"name": "Three-storey Main Street block", "storeys": 3, "cap": [8, 12], "flats": [8, 12], "load": 2},
		{"name": "Four-storey Main Street block", "storeys": 4, "cap": [10, 14], "flats": [14, 20], "load": 3},
	]},
	# Plates: a postwar 16-storey slab about 1,200 m², a 30-storey downtown
	# tower about 1,400 (Salesforce Tower, Indianapolis: 48 storeys on
	# about 1,900).
	"office": {"zone": COM, "name": "Offices", "cover": 0.4, "stages": [
		{"name": "Office building", "storeys": 3, "cap": [40, 50], "load": 3},
		{"name": "Five-storey offices", "storeys": 5, "cap": [80, 100], "load": 6},
		# Eight storeys still fit one storefront lot (a 1920s bank tower).
		{"name": "Office tower", "storeys": 8, "cap": [140, 170], "load": 10},
		{"name": "Office high-rise", "storeys": 16, "cap": [300, 360], "load": 22, "plate": 1200.0},
		{"name": "Skyscraper", "storeys": 30, "cap": [600, 700], "load": 42, "plate": 1400.0},
	]},
	# Only a rezoning makes one (Redevelopment): a developer buys a row of
	# houses on a busy road. ICSC: a strip center under about 30,000 sq ft;
	# a neighborhood center with a grocery anchor, 30,000-125,000 sq ft.
	"shopping_center": {"zone": COM, "name": "Shopping center", "cover": 0.25, "stages": [
		{"name": "Strip shopping center", "storeys": 1, "cap": [25, 45], "load": 3},
		{"name": "Neighborhood shopping center", "storeys": 1, "cap": [80, 140], "load": 8},
	]},
	"factory": {"zone": IND, "name": "Factory", "cover": 0.5, "stages": [
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
	var c := {
		"density": density,
		"shops": shops,
		"main_street": shops >= Balance.MAIN_STREET_SHOPS,
		"avenue": road == RoadStyle.Type.AVENUE or road == RoadStyle.Type.BOULEVARD,
		"wealth": sim.wealth_at(Vector2(p.x, p.z)),
		"graduates_free": graduates_free(sim),
		"town": int(sim.stats.population),
		"market": sim.market.people(sim),
		"flats_vacant": Market.flats_vacancy(sim),
		"downtown": density >= Balance.DOWNTOWN_DENSITY,
	}
	var zone: int = sim.buildings[key].zone if sim.buildings.has(key) else sim.zones.zone_at(lot.zone_pt)
	c.far = far_limit(c, zone)
	return c


## The floor-area ratio zoning allows here (Balance.FAR_*): homes step up
## as the area fills in and the market grows; shops on a Main Street; and a
## city's downtown, by the city's size.
static func far_limit(c: Dictionary, zone: int) -> float:
	match zone:
		RES:
			var f: Array = Balance.FAR_HOMES
			if Market.supports(c.market, "apartments", 4) and c.downtown:
				return f[4]
			if Market.supports(c.market, "apartments", 3) and c.density >= Balance.DENSE_CORE * 3:
				return f[3]
			if (c.density >= Balance.DENSE_CORE or c.avenue) and Market.supports(c.market, "apartments"):
				return f[2]
			if c.density >= Balance.ROW_HOME_DENSITY and Market.supports(c.market, "row_home"):
				return f[1]
			return f[0]
		COM:
			if c.downtown:
				for i in range(Balance.DOWNTOWN_TOWNS.size() - 1, -1, -1):
					if c.town >= Balance.DOWNTOWN_TOWNS[i]:
						return Balance.FAR_DOWNTOWN[i]
			var f: Array = Balance.FAR_SHOPS
			if c.main_street and c.density >= Balance.DENSE_CORE * 2:
				return f[2]
			return f[1] if c.main_street else f[0]
	return Balance.FAR_INDUSTRY


## The floor-area ratio a type and stage makes on a lot of `area` m².
static func far_of(type: String, level: int, area: float) -> float:
	var st: Dictionary = TYPES[type].stages[level]
	if st.has("plate"):
		# A tower may cover its whole lot (the Loop's do), but not more.
		return float(st.storeys) * float(st.plate) / area if area >= float(st.plate) else INF
	return float(st.storeys) * float(TYPES[type].cover)


## The lot area (m²) a stage needs to stay within `far`, or INF if no lot
## is big enough (its floors already cover as much of the lot as they can).
static func area_for(type: String, level: int, far: float) -> float:
	var st: Dictionary = TYPES[type].stages[level]
	if st.has("plate"):
		return maxf(float(st.plate), float(st.storeys) * float(st.plate) / far)
	return 0.0 if float(st.storeys) * float(TYPES[type].cover) <= far else INF


## How far the market is along to a type's first stage (Market.ramp): 0
## where nobody would build it, 1 where it's as common as anywhere. New
## apartment buildings also wait while the town's flats stand empty.
static func market_for(c: Dictionary, type: String, level := 0) -> float:
	if type == "apartments" and c.flats_vacant >= Balance.MARKET_VACANCY:
		return 0.0
	return Market.ramp(c.market, type, level)


## Office jobs the town's college graduates support (scripts/sim/education.gd)
## that no office building holds yet.
static func graduates_free(sim) -> int:
	return sim.education.office_jobs() - office_jobs(sim)


## Jobs in office buildings across town (each needs a graduate).
static func office_jobs(sim) -> int:
	# As type_of: no zone's default is an office, so only a set type is one.
	var n := 0
	for b in sim.buildings.values():
		if b.get("type", "") == "office":
			n += int(b.cap)
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
			if c.density >= Balance.ROW_HOME_DENSITY and market_for(c, "row_home") > 0.0:
				weights.append(["row_home", clampf((dens - Balance.ROW_HOME_DENSITY) / 30.0 + 0.4, 0.0, 1.5)
					* (1.3 - rich) * market_for(c, "row_home"), "A big market, and land is dear here, so homes share walls"])
			if (c.density >= Balance.DENSE_CORE or c.avenue) and market_for(c, "apartments") > 0.0:
				var w := (0.8 if c.avenue else 0.0) + clampf((dens - Balance.DENSE_CORE) / 40.0, 0.0, 1.0)
				weights.append(["apartments", w * (1.3 - rich) * market_for(c, "apartments"),
					"On an avenue" if c.avenue else "Close to the centre of town"])
		COM:
			if c.main_street:
				weights.append(["mixed_use", 1.5, "A busy Main Street: shop below, flats above"])
				weights.append(["shop", 0.3, "A shop on Main Street"])
			else:
				weights.append(["shop", 1.0, "A shop for the neighborhood"])
				weights.append(["mixed_use", 0.15, "Shop below, flats above"])
			if c.graduates_free >= int(TYPES.office.stages[0].cap[1]) and market_for(c, "office") > 0.0:
				weights.append(["office", (0.6 + dens / 50.0) * market_for(c, "office"), "The town has college graduates to hire"])
		_:
			weights.append([default_type(zone), 1.0, ""])
	weights = weights.filter(func(w): return w[1] > 0.0)
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
	var area: float = sim.lots[key].area
	var out := []
	if lvl + 1 < TYPES[t].stages.size() and _stage_ok(sim, b, t, lvl + 1, c) \
			and far_of(t, lvl + 1, area) <= c.far:
		out.append([t, lvl + 1])
	for nt in TYPES[t].get("becomes", []):
		if _stage_ok(sim, b, nt, 0, c) and far_of(nt, 0, area) <= c.far:
			out.append([nt, 0])
	return out


# ----------------------------------------------------------------- assembly

## Lots whose centres are this close (metres) are looked at to buy.
const ASSEMBLE_REACH := 120.0


## A tower needs a bigger lot than one storefront: under the area's FAR,
## a 16-storey plate of 1,200 m² needs about 1,600 m² of lot at DX-12. So
## an owner whose next stage the area supports, but whose lot is too small
## for it, buys the lot next door and builds over both, the way downtown
## sites are assembled from old storefront lots. Only an empty lot, a
## vacant building, or (in a core zoned for towers, ASSEMBLE_FAR) a low
## building is bought; protected and charming old buildings are not.
## Returns the lot bought (now part of `key`'s lot), or "".
static func assemble(sim, key: String) -> String:
	var b: Dictionary = sim.buildings[key]
	var t := type_of(b)
	var lvl := int(b.get("level", 0)) + 1
	if lvl >= TYPES[t].stages.size() or not TYPES[t].stages[lvl].has("plate"):
		return ""
	var c := context(sim, key)
	if not _stage_ok(sim, b, t, lvl, c):
		return ""
	var need := area_for(t, lvl, c.far)
	var lot: Dictionary = sim.lots[key]
	if need == INF or need <= lot.area or need > LotPlanner.max_lot(int(b.zone), 0, c.far)[1]:
		return ""
	# Next door along the street, around the corner or behind.
	var near := []
	for k in sim.lots:
		if k != key and sim.lots[k].pos.distance_to(lot.pos) < ASSEMBLE_REACH:
			near.append(k)
	near.sort()
	var best := ""
	var best_rank := INF
	for k in near:
		if sim.zones.zone_at(sim.lots[k].zone_pt) != int(b.zone):
			continue
		var rank := _buy_rank(sim, k, c.far)
		if rank < best_rank and LotPlanner.can_merge(sim, key, k, c.far):
			best_rank = rank
			best = k
	if best == "":
		return ""
	return best if LotPlanner.merge_lots(sim, key, best, c.far) == key else ""


## How readily a lot is bought for a tower site: an empty lot first, then a
## vacant building, then a small low one. INF if it isn't for sale.
static func _buy_rank(sim, k: String, far: float) -> float:
	if not sim.buildings.has(k):
		return 0.0
	if sim.heritage.protected(k) or float(sim.heritage.charm.get(k, 0.0)) >= Balance.HERITAGE_DELAY_CHARM:
		return INF
	var o: Dictionary = sim.buildings[k]
	if int(o.get("occ", 0)) == 0 and int(o.get("focc", 0)) == 0:
		return 1.0
	if far >= Balance.ASSEMBLE_FAR and storeys(o) <= 3 and not TYPES[type_of(o)].stages[int(o.get("level", 0))].has("plate"):
		return 2.0 + float(o.cap) / 1000.0
	return INF


## Whether the area, and the market, support this stage.
static func _stage_ok(sim, b: Dictionary, type: String, level: int, c: Dictionary) -> bool:
	if not Market.supports(c.market, type, level):
		return false
	if type == "apartments" and c.flats_vacant >= Balance.MARKET_VACANCY:
		return false
	match [type, level]:
		["house", 1]: return true
		["row_home", 0]: return c.density >= Balance.ROW_HOME_DENSITY * 2 and c.wealth < 0.7
		["row_home", 1]: return c.density >= Balance.ROW_HOME_DENSITY + 15
		["apartments", 1]: return c.density >= Balance.DENSE_CORE + 10
		["apartments", 2]: return c.density >= Balance.DENSE_CORE * 3 or (c.avenue and c.density >= Balance.DENSE_CORE * 2)
		["apartments", 3]: return c.density >= Balance.DENSE_CORE * 3
		["apartments", 4]: return c.downtown
		["shop", 1]: return true
		["mixed_use", 0]: return c.main_street
		["mixed_use", _]: return c.main_street and c.density >= Balance.DENSE_CORE * level
		["office", _]:
			if level >= 3 and not c.downtown:
				return false
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
	# An owner letting the place run down doesn't build on (PropertyCare).
	if sim.care.tier_of(key) < 0:
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
