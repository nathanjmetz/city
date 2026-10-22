class_name Economy
extends RefCounted
## The city's money: what roads cost, what buildings pay in property tax,
## and the monthly budget.
##
## Prices follow real US figures. Like Cities: Skylines 2, the budget runs
## by the month and one game day settles one month, so a city grows at a
## playable pace while every amount stays real. Money is whole dollars so
## every copy of the simulation agrees to the cent.

const START_MONEY := 3_000_000
## Building a road, dollars per metre (about $1.6M a mile for a two-lane
## street and $9.7M a mile for a highway, in line with state DOT costs).
const BUILD_PER_M := {
	RoadStyle.Type.STREET: 1000, RoadStyle.Type.AVENUE: 2000,
	RoadStyle.Type.BOULEVARD: 3500, RoadStyle.Type.HIGHWAY: 6000, RoadStyle.Type.RAMP: 3000,
	RoadStyle.Type.RING: 2500, RoadStyle.Type.RING2: 4000,
}
## Road upkeep, dollars per lane-metre per month (about $10,000 a lane-mile
## a year, typical of US city budgets).
const UPKEEP_PER_LANE_M := 0.52
## A full-height bridge costs this many times more, a tunnel more still.
const BRIDGE_FACTOR := 4.0
const TUNNEL_FACTOR := 8.0
## Property tax, percent of value per year. Defaults are typical US rates.
const DEFAULT_TAX := {
	ZoneMap.Zone.RESIDENTIAL: 1.0, ZoneMap.Zone.COMMERCIAL: 1.5, ZoneMap.Zone.INDUSTRIAL: 1.5,
}
const TAX_MIN := 0.0
const TAX_MAX := 3.0
## Assessed value per resident a home holds, or per job a business offers.
const VALUE_PER_PLACE := {
	ZoneMap.Zone.RESIDENTIAL: 90_000, ZoneMap.Zone.COMMERCIAL: 150_000, ZoneMap.Zone.INDUSTRIAL: 100_000,
}

## Population milestones and the grant each one brings (like CS2's milestone
## rewards; in real life, state and federal community development grants).
const MILESTONES := [[100, 250_000], [250, 400_000], [500, 600_000], [1000, 1_000_000],
	[2500, 2_000_000], [5000, 3_500_000], [10000, 6_000_000], [25000, 10_000_000]]

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
