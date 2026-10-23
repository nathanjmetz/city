class_name PropertyCare
extends RefCounted
## Every property's owner looks after it as well as what the town gives it
## allows (Brawn, 2026-10-23): a home with power, clean water, a sewer,
## schools and police nearby, a street that moves, jobs in town and good
## neighbours gets a new roof, a deck, a shed and one day a pool; one denied
## those for too long fades, its yard goes to weeds, its family moves out
## and its windows are boarded. Shops, offices, apartments and factories
## too. Upgrades come slowly and decline faster, as they do in real towns.
##
## Real references:
##   - Owners spend on improvements as their home's value and the area
##     rise (Harvard Joint Center for Housing Studies, "Improving America's
##     Housing"), and defer upkeep once rents or values fall below its cost.
##   - Filtering: housing ages and passes down the income ladder unless it
##     is kept up (urban economics; Rosenthal 2014, "Are Private Markets and
##     Filtering a Viable Source of Low-Income Housing?").
##   - Blight spreads: a vacant, boarded house lowers the homes around it
##     (Econsult/Temple University, Philadelphia vacant property study 2010:
##     homes within 150 ft of one sold for about $7,600 less), so a
##     neighbourhood's own condition is one of its needs.
##   - A vacant house left unsafe long enough is ordered down under the
##     state's unsafe building law (Indiana Code 36-7-9).
##
## Each property has a condition from 0 (derelict) to 1 (showpiece) and a
## tier the art draws: -2 derelict, -1 run-down, 0 kept, 1 improved,
## 2 showpiece. Once a game month (a day), one slice of the town at a time,
## each owner weighs what it gets (needs()) and moves toward it.
## Deterministic: no random draws, sorted keys, so every copy agrees.

const TIER_NAMES := {-2: "Derelict", -1: "Run-down", 0: "Kept up", 1: "Improved", 2: "Showpiece"}
## What a property looks like at each tier, in plain words for the inspector.
const TIER_LOOKS := {
	-2: "boarded windows, weeds and peeling paint",
	-1: "faded paint and a weedy yard",
	0: "",
	1: "fresh paint and a new roof%s",
	2: "a pool and a privacy fence%s",
}
## The month runs in a slice of town every half game hour, so no tick
## carries much; the neighbourhood grid is rebuilt on a tick of its own.
const SLICES := 48
const NEAR_CELL := 80.0

## lot key -> condition, 0 to 1
var cond := {}
## lot key -> tier, -2 to 2 (what the art draws)
var tier := {}
## lot key -> the tick it became derelict (unsafe building clock)
var derelict_since := {}
## lot key -> the need it lacks most, for the inspector
var lacking := {}
## Neighbourhood grid of buildings, and each cell's average condition with
## the cells around it, rebuilt at the month's first slice.
var _grid := {}
var _cell_avg := {}
## Buildings whose tier changed this slice (BuildingView redraws them).
var changed_keys := []
## Funding by area, read once per slice.
var _fund := {}


## A new building starts kept up, the way new construction looks.
func cond_of(key: String) -> float:
	return float(cond.get(key, Balance.CARE_START))


func tier_of(key: String) -> int:
	return int(tier.get(key, 0))


## Whether a family will move into it (nobody moves into a derelict house).
func livable(key: String) -> bool:
	return tier_of(key) > -2


## The land value factor its own upkeep gives the lot (1.0 = no change).
func land(key: String) -> float:
	return float(Balance.CARE_LAND[tier_of(key) + 2])


## Forgets a property (it was torn down or merged into another lot).
func forget(key: String) -> void:
	cond.erase(key)
	tier.erase(key)
	derelict_since.erase(key)
	lacking.erase(key)


## Runs one slice of the month (CitySim calls it every half game hour).
## Returns true when some building's look changed.
func slice(sim, i: int) -> bool:
	changed_keys = []
	_fund = {}
	var keys := []
	for key in sim.buildings:
		if key.hash() % SLICES == i and sim.lots.has(key):
			keys.append(key)
	keys.sort()
	var demolish := []
	for key in keys:
		if not sim.construction.is_done("lot:" + key, sim.tick_count):
			continue
		var n := needs(sim, key)
		var target := float(n.target)
		lacking[key] = str(n.lacking)
		var c := cond_of(key)
		c = clampf(c + clampf((target - c) * Balance.CARE_PULL, -Balance.CARE_DOWN, Balance.CARE_UP), 0.0, 1.0)
		cond[key] = snappedf(c, 0.0001)
		var t := _tier_for(c, tier_of(key))
		if t != tier_of(key) and changed_keys.size() < Balance.CARE_REDRAWS_PER_SLICE:
			tier[key] = t
			changed_keys.append(key)
			if t == -2:
				derelict_since[key] = sim.tick_count
			else:
				derelict_since.erase(key)
		_occupancy(sim, key)
		if derelict_since.has(key) and _vacant(sim.buildings[key]) \
				and sim.tick_count - int(derelict_since[key]) >= Balance.CARE_UNSAFE_MONTHS * 24 * CitySim.TICKS_PER_HOUR \
				and not sim.heritage.protected(key):
			demolish.append(key)
	for key in demolish:
		# Ordered down as unsafe; the lot waits for a new owner.
		sim.buildings.erase(key)
		forget(key)
		changed_keys.append(key)
	return not changed_keys.is_empty()


## What the owner gets, each 0 to 1 with a weight, and where that leaves
## the property: {"target", "lacking", "parts": {name: [score, weight]}}.
func needs(sim, key: String) -> Dictionary:
	var b: Dictionary = sim.buildings[key]
	var lot: Dictionary = sim.lots[key]
	var z := int(b.zone)
	var s: Dictionary = sim.services.served.get(key, {})
	var pop := int(sim.stats.get("population", 0))
	var parts := {}
	# Tests and the balance harness can run a town without utilities.
	var has_power: bool = s.get("power", false) or not sim.require_utilities
	var has_water: bool = s.get("water", false) or not sim.require_utilities
	parts["Power"] = [1.0 if has_power else 0.0, 1.0]
	parts["Water"] = [1.0 if has_water else 0.0, 1.0]
	parts["Safe tap water"] = [0.0 if sim.services.water.boils(s) else 1.0, 1.0]
	# Septic tanks do for houses on a village's big lots; past a small town,
	# and for anything bigger than a house, people expect sewers.
	var sewer_w := 0.0
	if not sim.services.water.utilities.is_empty():
		sewer_w = 0.6 if BuildingTypes.type_of(b) != "house" else clampf(float(pop - 2000) / 8000.0, 0.0, 0.6)
	parts["Sewer"] = [1.0 if s.get("sewer", false) else 0.0, sewer_w]
	# Past village size people want fire, police, a clinic and a school
	# nearby (the same point demand starts asking for them).
	var svc_w := clampf(float(pop - 300) / 700.0, 0.0, 1.0) * (1.5 if z == ZoneMap.Zone.RESIDENTIAL else 0.8)
	parts["Schools, police, fire and a clinic"] = [Services.coverage_of(s) if not s.is_empty() else 0.0, svc_w]
	parts["A street that moves"] = [street_score(sim, lot), 1.0 if z == ZoneMap.Zone.RESIDENTIAL else 1.3]
	parts["Land value"] = [clampf(0.55 + (base_land(sim, key) - 1.0) * 2.5, 0.0, 1.0), 1.0]
	var jobs := 1.0
	if z == ZoneMap.Zone.RESIDENTIAL:
		jobs = float(sim.stats.employed) / maxf(float(sim.stats.workers), 1.0) if int(sim.stats.workers) > 0 else 1.0
		parts["Jobs in town"] = [clampf((jobs - 0.75) / 0.2, 0.0, 1.0), 1.0]
		parts["Lived in"] = [1.0 if int(b.get("occ", 0)) > 0 or int(b.cap) == 0 else 0.0, 0.8]
	elif z == ZoneMap.Zone.COMMERCIAL:
		parts["Customers"] = [clampf(0.35 + float(sim.demand.get(z, 0.0)), 0.0, 1.0), 1.0]
	else:
		parts["Workers"] = [clampf(float(sim.stats.workers) / maxf(float(sim.stats.jobs), 1.0), 0.0, 1.0), 1.0]
	parts["Kept-up neighbours"] = [_near(lot.pos, key), 1.0]
	var area: String = Economy.ZONE_AREA.get(z, "homes")
	if not _fund.has(area):
		_fund[area] = sim.policies.pick(Balance.POLICY_LAND_VALUE, "funding", area)
	var fund: float = _fund[area]
	parts["Town upkeep (Funding)"] = [clampf(0.5 + (fund - 1.0) * 10.0, 0.0, 1.0), 0.6]
	var total := 0.0
	var weight := 0.0
	var worst := ""
	var worst_gap := 0.05
	for name in parts:
		var p: Array = parts[name]
		total += float(p[0]) * float(p[1])
		weight += float(p[1])
		var gap := (1.0 - float(p[0])) * float(p[1])
		if gap > worst_gap:
			worst_gap = gap
			worst = name
	var target := total / maxf(weight, 0.001)
	# Some owners keep their place nicer than others (the same on every copy).
	target += (0.5 - BuildingTypes.ambition(b)) * Balance.CARE_OWNER_SPREAD
	# Without power or water nobody can keep a building up.
	if not has_power or not has_water:
		target = minf(target, Balance.CARE_NO_UTILITY)
	return {"target": clampf(target, 0.0, 1.0), "lacking": worst, "parts": parts}


## How freely traffic moves on the lot's street, 0 (gridlock) to 1.
static func street_score(sim, lot: Dictionary) -> float:
	if not sim.simulate_traffic:
		return 1.0
	var seg := int(lot.seg)
	var sp := minf(sim.traffic.way_speed(seg * 2), sim.traffic.way_speed(seg * 2 + 1))
	return clampf((sp - 0.25) / 0.5, 0.0, 1.0)


## The land factor without this lot's own upkeep (that would feed back).
static func base_land(sim, key: String) -> float:
	return sim.hubs.lot_factor(sim, key) * sim.pollution.lot_factor(sim, key) * sim.heritage.land(key)


## A tier for a condition, sticking to the old one near the line between
## them so a property doesn't flicker back and forth.
static func _tier_for(c: float, was: int) -> int:
	var at: Array = Balance.CARE_TIERS
	var t := -2
	for i in at.size():
		if c >= float(at[i]):
			t = i - 1
	if t == was:
		return t
	var line: float = at[mini(t, was) + 2]
	return t if absf(c - line) >= Balance.CARE_STICKY else was


static func _vacant(b: Dictionary) -> bool:
	return int(b.get("occ", 0)) == 0 and int(b.get("focc", 0)) == 0


## Families leave a derelict building, a few households a month.
func _occupancy(sim, key: String) -> void:
	if tier_of(key) > -2:
		return
	var b: Dictionary = sim.buildings[key]
	var leave := maxi(1, int(b.cap) / 4)
	if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
		b.occ = maxi(0, int(b.occ) - leave)
	b.focc = maxi(0, int(b.get("focc", 0)) - maxi(1, int(b.get("flats", 0)) / 4))


## The month's start: forget torn-down buildings and rebuild the
## neighbourhood grid (CitySim, on a tick of its own before slice 0).
func start_month(sim) -> void:
	for k in cond.keys():
		if not sim.buildings.has(k):
			forget(k)
	_build_grid(sim)


func _build_grid(sim) -> void:
	_grid = {}
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var p: Vector3 = sim.lots[key].pos
		var c := Vector2i(floori(p.x / NEAR_CELL), floori(p.z / NEAR_CELL))
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append([p, key])
	_cell_avg = {}
	var sums := {}
	for c in _grid:
		var t := 0.0
		for e in _grid[c]:
			t += cond_of(e[1])
		sums[c] = [t, _grid[c].size()]
	for c in _grid:
		var t := 0.0
		var n := 0
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var s: Array = sums.get(c + Vector2i(dx, dz), [0.0, 0])
				t += float(s[0])
				n += int(s[1])
		_cell_avg[c] = [t, n]


## Average condition of the buildings around a point (its 80 m cell and
## the eight around it, as they stood at the start of the month; the lot
## itself left out), or neutral when it stands alone.
func _near(p: Vector3, key: String) -> float:
	var c := Vector2i(floori(p.x / NEAR_CELL), floori(p.z / NEAR_CELL))
	var s: Array = _cell_avg.get(c, [0.0, 0])
	var total: float = float(s[0])
	var n: int = int(s[1])
	if n > 0 and cond.has(key):
		total -= cond_of(key)
		n -= 1
	if n == 0:
		return 0.7
	# Condition 0.6 and up reads as a fine street.
	return clampf(total / n / 0.7, 0.0, 1.0)


## Rows for the inspector: how it looks, and what it needs most.
func rows(sim, key: String) -> Array:
	if not sim.buildings.has(key):
		return []
	var t := tier_of(key)
	var look: String = TIER_LOOKS[t]
	if t >= 1:
		var house := BuildingTypes.type_of(sim.buildings[key]) == "house"
		look = look % ((", a deck and a shed" if t == 1 else "") if house else "")
		if not house:
			look = "fresh paint and a clean front"
	var out := [["Condition", TIER_NAMES[t] + ((": " + look) if look != "" else "")]]
	var l := str(lacking.get(key, ""))
	if l != "":
		out.append(["Needs most", l])
	return out


func to_dict() -> Dictionary:
	return {"cond": cond, "tier": tier, "derelict": derelict_since, "lacking": lacking}


func from_dict(d: Dictionary) -> void:
	cond = {}
	tier = {}
	derelict_since = {}
	lacking = {}
	_grid = {}
	for k in d.get("cond", {}):
		cond[str(k)] = float(d.cond[k])
	for k in d.get("tier", {}):
		tier[str(k)] = int(d.tier[k])
	for k in d.get("derelict", {}):
		derelict_since[str(k)] = int(d.derelict[k])
	for k in d.get("lacking", {}):
		lacking[str(k)] = str(d.lacking[k])
