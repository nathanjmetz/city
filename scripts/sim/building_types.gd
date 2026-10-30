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
	"house": {"zone": RES, "name": "House", "becomes": ["duplex", "row_home"], "cover": 0.25, "stages": [
		# A ranch, colonial or split-level (storeys 0: the seed picks).
		{"name": "Family home", "storeys": 0, "cap": [2, 4]},
		{"name": "Two-storey home", "storeys": 2, "cap": [4, 5]},
		# The owner builds on out back: a family room, sunroom or a
		# two-storey rear wing (NAHB: additions are about a third of
		# remodeling jobs on Midwestern homes over 30 years old).
		{"name": "Home with addition", "storeys": 2, "cap": [5, 6]},
		# A backyard cottage for a grown child, a parent or a renter: the
		# accessory dwelling unit Indianapolis (2023), Fort Wayne and
		# Bloomington now allow on any single-family lot, a one-storey
		# cottage of 400-800 sq ft behind the house.
		{"name": "Home with backyard cottage", "storeys": 2, "cap": [6, 8]},
		# A landlord cuts the house into an up and a down flat (or three),
		# the outside stair to the upstairs door, as countless older homes
		# in Marion, Muncie and Indianapolis were from the 1940s on.
		{"name": "House cut into flats", "storeys": 2, "cap": [7, 10]},
	]},
	# A two-family house: a postwar side-by-side ranch duplex, a recent
	# two-storey one, or on prewar streets an up-and-down two-family
	# (Milwaukee's duplex flats, Indianapolis's doubles), and then a
	# fourplex (four flats in two storeys, a stair hall in the middle).
	# Census ACS: 2-4 unit buildings are 5-8% of homes in Indiana towns of
	# 2,500-10,000, a few in smaller ones.
	"duplex": {"zone": RES, "name": "Duplex", "becomes": ["row_home", "apartments"], "cover": 0.3, "stages": [
		{"name": "Duplex", "storeys": 0, "cap": [4, 7]},
		{"name": "Fourplex", "storeys": 2, "cap": [8, 11], "load": 2},
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
	"mixed_use": {"zone": COM, "name": "Shop with flats", "becomes": ["commercial_block"], "cover": 0.85, "stages": [
		{"name": "Main Street block", "storeys": 2, "cap": [6, 10], "flats": [3, 5]},
		{"name": "Three-storey Main Street block", "storeys": 3, "cap": [8, 12], "flats": [8, 12], "load": 2},
		{"name": "Four-storey Main Street block", "storeys": 4, "cap": [10, 14], "flats": [14, 20], "load": 3},
	]},
	# A storefront owner buys out the shop next door and builds across both
	# lots: one front of three to five bays over the shops, flats or a lodge
	# hall upstairs, its name and year in the parapet (the 1880s-1910s
	# Italianate and Romanesque blocks on Indiana's courthouse squares:
	# Wabash, Huntington, Marion, 50-100 ft fronts). `min_width`: the lot
	# frontage it needs (m), bought up along the street (assemble()).
	"commercial_block": {"zone": COM, "name": "Commercial block", "cover": 0.85, "stages": [
		{"name": "Commercial block", "storeys": 3, "cap": [16, 24], "flats": [8, 14], "load": 3, "min_width": 24.0},
		{"name": "Four-storey commercial block", "storeys": 4, "cap": [22, 30], "flats": [14, 22], "load": 4, "min_width": 24.0},
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
		# A community center: a discount store joins the grocer (ICSC 125,000-
		# 400,000 sq ft on 10-30 acres; scaled down, as the game's blocks
		# are). It needs about 1.6 acres, a whole block's depth from the
		# road: the center buys the houses behind it (Redevelopment) or
		# commercial lots next door.
		# Discount stores staffed about 1 job per 400-500 sq ft.
		{"name": "Community shopping center", "storeys": 1, "cap": [170, 240], "load": 12, "lot": 6500.0},
		# A power center: three or more "category killer" boxes (home
		# improvement, electronics, sporting goods) beside the discount
		# store, few small shops, and pads along the road (ICSC 250,000-
		# 600,000 sq ft on 25-80 acres; Marion's Baldwin Avenue, Fort Wayne's
		# Apple Glen, scaled down like the community center). About 3 acres:
		# it buys more of the block behind it.
		{"name": "Power center", "storeys": 1, "cap": [320, 440], "load": 20, "lot": 12000.0},
	]},
	# Only a rezoning makes one (Redevelopment): a developer buys a run of
	# lots on a busy road at the edge of town and builds it in phases, as
	# Indiana's small-city office parks were (one low building, a second,
	# then a third and the pond). Jobs at about 300 sq ft of office each
	# (NAIOP/ULI suburban office densities): a 20,000 sq ft building holds
	# about 60.
	"office_park": {"zone": COM, "name": "Office park", "cover": 0.2, "stages": [
		{"name": "Office park, first building", "storeys": 2, "cap": [50, 70], "load": 3},
		{"name": "Office park, second building", "storeys": 2, "cap": [100, 140], "load": 5},
		{"name": "Office park, built out", "storeys": 3, "cap": [190, 250], "load": 9, "lot": 5000.0},
		# A company that did well here builds its headquarters on the park
		# (Cummins in Columbus, Lincoln Financial and Steel Dynamics in Fort
		# Wayne): a six-storey glass building beside the low ones, on land
		# bought next door. 150,000 sq ft at about 300 sq ft a job. Its
		# 450-odd spaces (ITE: about 4 per 1,000 sq ft) take a five-level
		# deck and a field of rows out front: about 4.5 acres in all.
		{"name": "Corporate campus", "storeys": 6, "cap": [400, 500], "load": 16, "lot": 18000.0},
	]},
	# Only a rezoning makes one (Redevelopment): a hotel chain buys a run of
	# lots on a busy road (Marion's Hampton Inn and Holiday Inn Express by
	# I-69). A highway hotel of about 90 rooms, then, in a metro's market, a
	# full-service hotel of about 220 with a ballroom (Muncie's, Kokomo's).
	# AHLA staffing: about 0.25 jobs a room limited-service, 0.5-0.6 full.
	# The roadside motel is Tourism's (a Parks site), not this.
	"hotel": {"zone": COM, "name": "Hotel", "cover": 0.25, "stages": [
		{"name": "Highway hotel", "storeys": 4, "cap": [20, 30], "load": 14, "rooms": 90, "lot": 4500.0},
		{"name": "Full-service hotel", "storeys": 8, "cap": [110, 140], "load": 36, "rooms": 220, "lot": 14000.0},
	]},
	# A small plant that does well buys the empty parcel next door and adds
	# a wing and more truck docks, the way Indiana's small-town plants grew
	# (a 10,000 sq ft shop to a 40,000-80,000 sq ft plant). "lot" is the
	# land (m²) each stage needs. Jobs at about 500-700 sq ft of plant each
	# (ULI/NAIOP employment densities for light manufacturing): ~1.5 acres
	# for a 30-60 job plant, ~3 acres for 70-110 (the most one 60 m deep
	# industrial frontage holds, 200 m along the street) (Census County Business
	# Patterns: most Indiana manufacturing plants have 20-99 workers).
	"factory": {"zone": IND, "name": "Factory", "cover": 0.5, "stages": [
		{"name": "Factory", "storeys": 1, "cap": [18, 36]},
		{"name": "Factory with an addition", "storeys": 1, "cap": [32, 60], "lot": 6000.0},
		{"name": "Plant", "storeys": 1, "cap": [70, 110], "lot": 12000.0},
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
	# A house going up decides once which side its drive goes (a corner
	# house's away from the corner), and keeps it as it grows; one begun
	# before the rule came in keeps the drive it was built with.
	if type == "house" and not out.has("drive") and sim is CitySim and int(out.get("built", 0)) >= int(sim.curb_drives_from):
		out.drive = SiteLayout.decide_drive(sim, key)
	# Grown a stage on the same lot: some owners add floors on top of the
	# building they have ("added_from": its storeys before), the rest
	# rebuild (Balance.ADD_ON_PERCENT). Anything else is a new building.
	var was := int(b.get("level", 0))
	if type != type_of(b) or level < was or st.has("plate") or st.has("lot"):
		out.erase("added_from")
	elif level == was + 1:
		out.erase("added_from")
		if type in Balance.ADD_ON_TYPES and absi(hash([int(b.seed), level, "add on"])) % 100 < Balance.ADD_ON_PERCENT:
			out.added_from = int(TYPES[type].stages[was].storeys)
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
			# Zoning stays as it is; what's built on it waits on the market.
			if c.density >= Balance.DENSE_CORE or c.avenue:
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
	if st.has("lot") and area < float(st.lot):
		return INF
	return float(st.storeys) * float(TYPES[type].cover)


## The lot area (m²) a stage needs to stay within `far`, or INF if no lot
## is big enough (its floors already cover as much of the lot as they can).
static func area_for(type: String, level: int, far: float) -> float:
	var st: Dictionary = TYPES[type].stages[level]
	if st.has("plate"):
		return maxf(float(st.plate), float(st.storeys) * float(st.plate) / far)
	if st.has("lot"):
		return float(st.lot) if float(st.storeys) * float(TYPES[type].cover) <= far else INF
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
			if c.density >= Balance.DUPLEX_DENSITY and market_for(c, "duplex") > 0.0:
				weights.append(["duplex", Balance.DUPLEX_PICK * (1.2 - rich) * market_for(c, "duplex"),
					"Close to town, a house built for two families"])
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
	var wide: float = sim.lots[key].get("width", 0.0)
	if lvl + 1 < TYPES[t].stages.size() and _stage_ok(sim, b, t, lvl + 1, c) \
			and far_of(t, lvl + 1, area) <= c.far and wide >= float(TYPES[t].stages[lvl + 1].get("min_width", 0.0)):
		out.append([t, lvl + 1])
	for nt in TYPES[t].get("becomes", []):
		if _stage_ok(sim, b, nt, 0, c) and far_of(nt, 0, area) <= c.far \
				and wide >= float(TYPES[nt].stages[0].get("min_width", 0.0)):
			out.append([nt, 0])
	return out


## The stage an owner would build next that needs a wider frontage than
## its lot has (a commercial block over two storefronts): [type, level],
## or [] if none the area supports.
static func wider_stage(sim, key: String) -> Array:
	var b: Dictionary = sim.buildings[key]
	var t := type_of(b)
	var lvl := int(b.get("level", 0))
	var c := context(sim, key)
	var wide: float = sim.lots[key].get("width", 0.0)
	var cands := []
	if lvl + 1 < TYPES[t].stages.size():
		cands.append([t, lvl + 1])
	for nt in TYPES[t].get("becomes", []):
		cands.append([nt, 0])
	for o in cands:
		var st: Dictionary = TYPES[o[0]].stages[o[1]]
		if st.has("min_width") and wide < float(st.min_width) and _stage_ok(sim, b, o[0], o[1], c) \
				and far_of(o[0], o[1], sim.lots[key].area) <= c.far:
			return o
	return []


## Whether an owner here sets out to buy the lot next door this time (its
## own dice): about one in three keen owners whose next stage needs a wider
## lot, so most still grow in place.
static func wants_site(sim, key: String) -> bool:
	var roll := float(absi(hash([key, sim.tick_count, "site"])) % 1000) / 1000.0
	return roll < Balance.ASSEMBLE_MAIN_CHANCE and not wider_stage(sim, key).is_empty()


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
	if not wider_stage(sim, key).is_empty():
		return _assemble_front(sim, key)
	var b: Dictionary = sim.buildings[key]
	var t := type_of(b)
	var lvl := int(b.get("level", 0)) + 1
	if lvl >= TYPES[t].stages.size() or not (TYPES[t].stages[lvl].has("plate") or TYPES[t].stages[lvl].has("lot")):
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


## A storefront owner buys the lot next door along its own street side, so
## the block it builds has one front across both: an empty lot first, then
## a vacant building, then a one-storey shop (bought out, as Main Street
## owners did). Protected and charming old buildings are not for sale.
## Returns the lot bought (now part of `key`'s lot), or "".
static func _assemble_front(sim, key: String) -> String:
	var lot: Dictionary = sim.lots[key]
	var c := context(sim, key)
	var near := []
	for k in sim.lots:
		var o: Dictionary = sim.lots[k]
		if k != key and o.seg == lot.seg and o.side == lot.side and o.pos.distance_to(lot.pos) < ASSEMBLE_REACH:
			near.append(k)
	near.sort()
	var best := ""
	var best_rank := INF
	for k in near:
		var rank := _front_rank(sim, k)
		if rank < best_rank and LotPlanner.can_merge(sim, key, k, c.far):
			best_rank = rank
			best = k
	if best == "":
		return ""
	return best if LotPlanner.merge_lots(sim, key, best, c.far) == key else ""


static func _front_rank(sim, k: String) -> float:
	if not sim.buildings.has(k):
		return 0.0
	if sim.heritage.protected(k) or float(sim.heritage.charm.get(k, 0.0)) >= Balance.HERITAGE_DELAY_CHARM:
		return INF
	var o: Dictionary = sim.buildings[k]
	if int(o.zone) != COM:
		return INF
	if int(o.get("occ", 0)) == 0 and int(o.get("focc", 0)) == 0:
		return 1.0
	if type_of(o) == "shop":
		return 2.0 + float(o.cap) / 1000.0
	return INF


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
		["house", 2]: return c.wealth >= Balance.ADDITION_WEALTH
		["house", 3]: return c.density >= Balance.DUPLEX_DENSITY and c.wealth >= Balance.ADDITION_WEALTH
		# Conversions come where owners move out and landlords buy in.
		["house", 4]: return c.density >= Balance.DUPLEX_DENSITY and c.wealth < 0.6
		["duplex", 0]: return c.density >= Balance.DUPLEX_DENSITY and c.wealth < 0.75
		["duplex", 1]: return c.density >= Balance.ROW_HOME_DENSITY
		["row_home", 0]: return c.density >= Balance.ROW_HOME_DENSITY * 2 and c.wealth < 0.7
		["row_home", 1]: return c.density >= Balance.ROW_HOME_DENSITY + 15
		["apartments", 1]: return c.density >= Balance.DENSE_CORE + 10
		["apartments", 2]: return c.density >= Balance.DENSE_CORE * 3 or (c.avenue and c.density >= Balance.DENSE_CORE * 2)
		["apartments", 3]: return c.density >= Balance.DENSE_CORE * 3
		["apartments", 4]: return c.downtown
		["shop", 1]: return true
		["mixed_use", 0]: return c.main_street
		["commercial_block", 0]: return c.main_street and c.density >= Balance.DENSE_CORE * 2
		["commercial_block", 1]: return c.main_street and c.density >= Balance.DENSE_CORE * 3
		["mixed_use", _]: return c.main_street and c.density >= Balance.DENSE_CORE * level
		["office_park", _]:
			var more := int(TYPES.office_park.stages[level].cap[1]) - int(b.cap)
			return c.graduates_free >= more
		["office", _]:
			if level >= 3 and not c.downtown:
				return false
			var more := int(TYPES.office.stages[level].cap[1]) - (int(b.cap) if type_of(b) == "office" else 0)
			return c.graduates_free >= more
		["hotel", _]: return c.avenue or c.density < Balance.DENSE_CORE  # on a busy road or out at the edge
		["factory", _]:
			# Hiring needs people to hire: the town's workers not yet in a
			# job here or in Marion.
			var more := int(TYPES.factory.stages[level].cap[1]) - int(b.cap)
			return int(sim.stats.workers) - int(sim.stats.employed) - int(sim.stats.get("commuting", 0)) >= more
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
