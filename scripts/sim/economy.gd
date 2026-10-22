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

var money := START_MONEY
## How many milestones the city has reached.
var milestone := 0
var tax := DEFAULT_TAX.duplicate()
## This month's budget, per month: {"income": {zone: $}, "upkeep": $}.
var budget := {"income": {}, "upkeep": 0, "fees": 0, "services": 0}


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
func building_tax(b: Dictionary, staffed: float) -> float:
	var z := int(b.zone)
	var value: float = VALUE_PER_PLACE[z] * b.cap
	var used := staffed
	if z == ZoneMap.Zone.RESIDENTIAL:
		used = float(b.occ) / maxf(b.cap, 1.0)
	return value * (0.5 + 0.5 * used) * tax[z] / 100.0


## Works out this month's budget from the buildings and roads.
func update_budget(sim: CitySim) -> void:
	var income := {}
	for z in DEFAULT_TAX:
		income[z] = 0.0
	var staffed := float(sim.stats.employed) / maxf(sim.stats.jobs, 1.0)
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) != ZoneMap.Zone.RESIDENTIAL and not sim.utilities_ok(key):
			continue  # a business with no power or water is closed
		income[int(b.zone)] += building_tax(b, staffed) / 12.0
	# Farmland pays property tax at the industrial rate.
	income[ZoneMap.Zone.INDUSTRIAL] += sim.farms.total_acres() * Farms.LAND_PER_ACRE * Farms.AG_ASSESSMENT \
		* tax[ZoneMap.Zone.INDUSTRIAL] / 100.0 / 12.0
	var upkeep := 0.0
	for id in sim.network.segments:
		upkeep += road_upkeep(sim.network.curve_of(id), sim.network.segments[id].type)
	for z in income:
		income[z] = roundi(income[z])
	# Water and sewer bills from every building on the water system.
	var fees := 0
	for key in sim.buildings:
		if sim.services.served.has(key) and sim.services.served[key].get("water", false):
			fees += int(Services.WATER_FEE[int(sim.buildings[key].zone)])
	budget = {"income": income, "upkeep": roundi(upkeep), "fees": fees,
		"services": sim.services.monthly_upkeep()}


func monthly_net() -> int:
	var total := -int(budget.upkeep) - int(budget.services) + int(budget.fees)
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
		paid += int(MILESTONES[milestone][1])
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


func to_dict() -> Dictionary:
	var t := {}
	for z in tax:
		t[str(z)] = tax[z]
	return {"money": money, "tax": t, "milestone": milestone}


func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", START_MONEY))
	milestone = int(d.get("milestone", 0))
	tax = DEFAULT_TAX.duplicate()
	var t: Dictionary = d.get("tax", {})
	for z in t:
		tax[int(z)] = float(t[z])
