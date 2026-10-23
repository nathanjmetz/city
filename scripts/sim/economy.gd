class_name Economy
extends RefCounted
## The city's money: what roads cost, what buildings pay in property tax,
## and the monthly budget.
##
## Prices follow real US figures. Like Cities: Skylines 2, the budget runs
## by the month and one game day settles one month, so a city grows at a
## playable pace while every amount stays real. Money is whole dollars so
## every copy of the simulation agrees to the cent.

## The numbers live in Balance, where the tuning happens.
const START_MONEY := Balance.START_MONEY
const BUILD_PER_M := Balance.ROAD_BUILD_PER_M
const UPKEEP_PER_LANE_M := Balance.ROAD_UPKEEP_PER_LANE_M
const BRIDGE_FACTOR := Balance.BRIDGE_FACTOR
const TUNNEL_FACTOR := Balance.TUNNEL_FACTOR
const DEFAULT_TAX := Balance.DEFAULT_TAX
const TAX_MIN := Balance.TAX_MIN
const TAX_MAX := Balance.TAX_MAX
const VALUE_PER_PLACE := Balance.VALUE_PER_PLACE
const MILESTONES := Balance.MILESTONES
const DIFFICULTIES := Balance.DIFFICULTIES

var money := START_MONEY
## "easy", "normal" or "hard": scales start money, income, upkeep and grants.
var difficulty := "normal"
## How many milestones the city has reached.
var milestone := 0
var tax := DEFAULT_TAX.duplicate()
## This month's budget, per month: {"income": {zone: $}, "upkeep": $, ...}.
## "care" is the town's spending on homes, shops and factories from their
## Funding sliders and "support" its aid to farms and companies (both
## negative when Lean saves or collects money).
var budget := {"income": {}, "upkeep": 0, "fees": 0, "services": 0, "education": 0, "care": 0, "support": 0, "telecom": 0}

## Each zone's area on the Economy page.
const ZONE_AREA := {ZoneMap.Zone.RESIDENTIAL: "homes", ZoneMap.Zone.COMMERCIAL: "shops",
	ZoneMap.Zone.INDUSTRIAL: "factories"}


## What it costs to build a road along this curve.
static func road_cost(c: Array, type: int) -> int:
	var m := RoadNetwork.polyline_length(RoadNetwork.sample_curve(c[0], c[1], c[2]))
	return roundi(m * BUILD_PER_M[type] * height_factor(c))


## Monthly upkeep of a road along this curve.
static func road_upkeep(c: Array, type: int) -> float:
	var m := RoadNetwork.polyline_length(RoadNetwork.sample_curve(c[0], c[1], c[2]))
	return m * RoadStyle.TYPES[type].lanes * UPKEEP_PER_LANE_M * height_factor(c)


## Bridges and tunnels cost more the higher or deeper they run.
static func height_factor(c: Array) -> float:
	var y: float = (c[0].y + c[1].y + c[2].y) / 3.0
	var depth := clampf(absf(y) / RoadNetwork.CLEARANCE, 0.0, 1.0)
	return 1.0 + depth * ((BRIDGE_FACTOR if y > 0.0 else TUNNEL_FACTOR) - 1.0)


## A building's yearly property tax: its value, less while it sits part
## empty, times the zone's rate.
## `lift` is how much nearby parks and landmarks raise its value (0.1 = 10%).
func building_tax(b: Dictionary, staffed: float, lift := 0.0) -> float:
	var z := int(b.zone)
	var value: float = VALUE_PER_PLACE[z] * b.cap * (1.0 + lift)
	var used := staffed
	if z == ZoneMap.Zone.RESIDENTIAL:
		used = float(b.occ) / maxf(b.cap, 1.0)
	var flats := float(b.get("flats", 0))
	# Flats above a shop are assessed like homes, at the shop's rate.
	var homes: float = VALUE_PER_PLACE[ZoneMap.Zone.RESIDENTIAL] * flats * (0.5 + 0.5 * float(b.get("focc", 0)) / maxf(flats, 1.0))
	return (value * (0.5 + 0.5 * used) + homes) * tax[z] / 100.0


var _roads_rev := []
var _roads_upkeep := 0.0


## Works out this month's budget from the buildings and roads.
func update_budget(sim: CitySim) -> void:
	_finish_budget(sim, _slice_sums(sim, -1))


## In a running town the buildings' taxes are added up a sixth at a time
## through the hour (sim.tick, every MOVE_EVERY ticks), so no one tick pays
## for all of them; the budget is set on the hour (slice 0). Which slice a
## building is in, and the running sums, don't depend on when the game was
## loaded, so a loaded copy comes out the same.
const SLICES := 6
var _acc := {}  # running sums for this hour: {income, care, fees, done}


func budget_step(sim: CitySim, slice: int) -> void:
	if _acc.is_empty():
		_acc = _slice_sums(sim, -2)
	_add(_acc, _slice_sums(sim, slice))
	_acc.done.append(slice)
	if slice != 0:
		return
	# A town just started or loaded mid-hour fills in what it missed.
	for s in range(1, SLICES):
		if not s in _acc.done:
			_add(_acc, _slice_sums(sim, s))
	var sums := _acc
	_acc = {}
	_finish_budget(sim, sums)


static func _add(into: Dictionary, sums: Dictionary) -> void:
	for z in sums.income:
		into.income[z] += sums.income[z]
	into.care += sums.care
	into.fees += sums.fees


## Taxes, care and water fees of the buildings in one slice (-1: all of
## them, -2: none, for an empty running sum).
func _slice_sums(sim: CitySim, slice: int) -> Dictionary:
	var income := {}
	for z in DEFAULT_TAX:
		income[z] = 0.0
	var out := {"income": income, "care": 0.0, "fees": 0, "done": []}
	if slice == -2:
		return out
	var staffed := float(sim.stats.employed) / maxf(sim.stats.jobs, 1.0)
	var care := 0.0
	var fees := 0
	# The sliders are per area, so each is read once rather than per building.
	var care_of := {}
	var land_of := {}
	for key in sim.buildings:
		if slice >= 0 and key.hash() % SLICES != slice:
			continue
		var b: Dictionary = sim.buildings[key]
		# Water and sewer bills from every building on the water system;
		# water utilities collect their own bills (see WaterUtility).
		var s: Dictionary = sim.services.served.get(key, {})
		if s.get("water", false) and s.get("water_by", -1) == -1:
			fees += int(Services.WATER_FEE[int(b.zone)])
		var area: String = ZONE_AREA.get(int(b.zone), "homes")
		if not care_of.has(area):
			care_of[area] = sim.policies.pick(Balance.POLICY_CARE_PER_BUILDING, "funding", area)
			land_of[area] = sim.policies.pick(Balance.POLICY_LAND_VALUE, "funding", area)
		care += float(care_of[area])
		if int(b.zone) != ZoneMap.Zone.RESIDENTIAL and not sim.utilities_ok(key):
			continue  # a business with no power or water is closed
		# Land near a landfill is worth less, near a cemetery a little more,
		# and parks and landmarks lift it. Good mail service lifts it a little
		# too, and so do well-kept streets (Funding) and fiber and cell service;
		# a smelly sewer plant and pollution lower it.
		var tax_due := building_tax(b, staffed, sim.parks.lot_value.get(key, 0.0) + sim.telecom.lot_lift(key)) * sim.land_factor(key) \
			* sim.mail.lot_factor(sim, key) * float(land_of[area]) / 12.0
		if sim.lots.has(key):
			tax_due *= sim.services.water.land_value_factor(sim.services.buildings, sim.lots[key].pos)
		income[int(b.zone)] += tax_due
	out.care = care
	out.fees = fees
	return out


func _finish_budget(sim: CitySim, sums: Dictionary) -> void:
	var income: Dictionary = sums.income
	var care: float = sums.care
	var fees: int = sums.fees
	# Farmland pays property tax at the industrial rate.
	income[ZoneMap.Zone.INDUSTRIAL] += sim.farms.total_acres() * Farms.LAND_PER_ACRE * Farms.AG_ASSESSMENT \
		* tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	# Resource companies pay property tax on their main buildings and pads.
	income[ZoneMap.Zone.INDUSTRIAL] += sim.industry.taxable_value() * tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	# So do warehouses.
	income[ZoneMap.Zone.INDUSTRIAL] += sim.warehouses.taxable_value() * tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	income[ZoneMap.Zone.INDUSTRIAL] += sim.power.taxable_value() * tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	# And the big local factories.
	income[ZoneMap.Zone.INDUSTRIAL] += sim.big.taxable_value() * tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	# Bank buildings pay commercial property tax too.
	income[ZoneMap.Zone.COMMERCIAL] += sim.banks.taxable_value() * tax[ZoneMap.Zone.COMMERCIAL] / 100.0 / 12.0
	# Visitors to the fair and the games: what they spend is taxed, and the
	# businesses that opened for them pay property tax.
	income[ZoneMap.Zone.COMMERCIAL] += Tourism.taxable_value(sim) * tax[ZoneMap.Zone.COMMERCIAL] / 100.0 / 12.0 \
		+ sim.parks.tourism.monthly_tax()
	# Offices that opened for the town's graduates pay commercial property tax
	# (campuses themselves are tax-exempt, as in real life). Office buildings
	# pay their own tax, so only the jobs not yet in one count here.
	income[ZoneMap.Zone.COMMERCIAL] += maxi(0, sim.education.office_jobs() - BuildingTypes.office_jobs(sim)) \
		* Balance.EDUCATION_OFFICE_VALUE \
		* tax[ZoneMap.Zone.COMMERCIAL] / 100.0 / 12.0
	# The phone company pays property tax on its towers and fiber.
	income[ZoneMap.Zone.COMMERCIAL] += sim.telecom.taxable_value() * tax[ZoneMap.Zone.COMMERCIAL] / 100.0 / 12.0
	# And airports.
	income[ZoneMap.Zone.INDUSTRIAL] += sim.airports.taxable_value() * tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	# Road upkeep only changes with the roads.
	if _roads_rev != [sim.network.get_instance_id(), sim.network.revision]:
		_roads_rev = [sim.network.get_instance_id(), sim.network.revision]
		_roads_upkeep = 0.0
		for id in sim.network.segments:
			_roads_upkeep += road_upkeep(sim.network.curve_of(id), sim.network.segments[id].type)
	var upkeep := _roads_upkeep
	for z in income:
		income[z] = roundi(income[z])
	var d: Dictionary = DIFFICULTIES[difficulty]
	for z in income:
		income[z] = roundi(income[z] * d.income)
	var support := (sim.farms.yearly_support() + sim.industry.yearly_support()) / 12.0
	budget = {"income": income, "upkeep": roundi(upkeep * d.upkeep), "fees": roundi(fees * d.income),
		"services": roundi((sim.services.monthly_upkeep() + sim.hubs.monthly_cost() + sim.parks.monthly_upkeep()
			+ sim.mail.monthly_cost() + sim.heritage.monthly_cost()) * d.upkeep + sim.leaders.monthly_cost()),
		"education": roundi(sim.education.monthly_upkeep() * d.upkeep),
		"care": roundi(care * d.upkeep), "support": roundi(support),
		"telecom": roundi(sim.telecom.monthly_upkeep() * d.upkeep),
		# Service deals with neighbor towns: fees in as host, out as served.
		"deals": sim.interlocal.monthly_net(),
		# The region's projects: air visitors' spending and co-op capital credits.
		"region": sim.regional.monthly_income(sim)}


func monthly_net() -> int:
	var total := -int(budget.upkeep) - int(budget.services) - int(budget.get("education", 0)) + int(budget.fees) \
		- int(budget.get("care", 0)) - int(budget.get("support", 0)) - int(budget.get("telecom", 0)) + int(budget.get("deals", 0)) + int(budget.get("region", 0))
	for z in budget.income:
		total += int(budget.income[z])
	return total


## Lower taxes than usual make a zone more wanted, higher ones less.
func demand_shift(zone: int) -> float:
	return -0.3 * (tax[zone] - DEFAULT_TAX[zone]) / DEFAULT_TAX[zone]


## Pays any grants the population has earned. Returns the total paid.
func reach_milestones(population: int) -> int:
	var paid := 0
	while milestone < MILESTONES.size() and population >= MILESTONES[milestone][0]:
		paid += roundi(MILESTONES[milestone][1] * DIFFICULTIES[difficulty].grants)
		milestone += 1
	money += paid
	return paid


func set_tax(zone: int, rate: float) -> bool:
	if not tax.has(zone):
		return false
	rate = snappedf(clampf(rate, TAX_MIN, TAX_MAX), 0.1)
	if is_equal_approx(tax[zone], rate):
		return false
	tax[zone] = rate
	return true


## Cash a new city starts with on this difficulty.
static func start_money(diff: String) -> int:
	return int(DIFFICULTIES.get(diff, DIFFICULTIES.normal).start)


## Picks the difficulty. A city that hasn't started yet gets its start money.
func set_difficulty(diff: String, fresh: bool) -> bool:
	if not DIFFICULTIES.has(diff) or diff == difficulty and not fresh:
		return false
	difficulty = diff
	if fresh:
		money = start_money(diff)
	return true


func to_dict() -> Dictionary:
	var t := {}
	for z in tax:
		t[str(z)] = tax[z]
	var out := {"money": money, "tax": t, "milestone": milestone, "difficulty": difficulty}
	if not _acc.is_empty():
		var inc := {}
		for z in _acc.income:
			inc[str(z)] = _acc.income[z]
		out.acc = {"income": inc, "care": _acc.care, "fees": _acc.fees, "done": _acc.done}
	return out


func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", START_MONEY))
	milestone = int(d.get("milestone", 0))
	difficulty = str(d.get("difficulty", "normal"))
	if not DIFFICULTIES.has(difficulty):
		difficulty = "normal"
	_acc = {}
	if d.has("acc"):
		var a: Dictionary = d.acc
		var inc := {}
		for z in a.income:
			inc[int(z)] = float(a.income[z])
		_acc = {"income": inc, "care": float(a.care), "fees": int(a.fees), "done": Array(a.done).map(func(x): return int(x))}
	tax = DEFAULT_TAX.duplicate()
	var t: Dictionary = d.get("tax", {})
	for z in t:
		tax[int(z)] = float(t[z])
