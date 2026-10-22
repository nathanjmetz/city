class_name Balance
extends RefCounted
## Every gameplay number in one place: money, prices, upkeep, taxes, grants,
## growth pace and yields. Tune the game here; the simulation scripts only
## read these values.
##
## Amounts are whole US dollars. One game day settles one month of budget,
## so "a month" below is one game day. Each value notes the real-world
## figure it follows, so a change can stay grounded in reality.

# --- Money -------------------------------------------------------------------

## Cash a new city starts with.
const START_MONEY := 3_000_000

## Difficulty, picked when a city starts: cash to start with, and how much
## income (taxes and water bills), upkeep (roads and services) and milestone
## grants are scaled. Normal is real prices; Easy and Hard bend the budget the
## way Cities: Skylines' hard mode does, without changing what things cost.
const DIFFICULTIES := {
	"easy": {"name": "Easy", "start": 5_000_000, "income": 1.25, "upkeep": 0.8, "grants": 1.5},
	"normal": {"name": "Normal", "start": 3_000_000, "income": 1.0, "upkeep": 1.0, "grants": 1.0},
	"hard": {"name": "Hard", "start": 1_500_000, "income": 0.85, "upkeep": 1.25, "grants": 0.75},
}

## Population milestones and the grant each one brings (like CS2's milestone
## rewards; in real life, state and federal community development grants).
const MILESTONES := [[100, 250_000], [250, 400_000], [500, 600_000], [1000, 1_000_000],
	[2500, 2_000_000], [5000, 3_500_000], [10000, 6_000_000], [25000, 10_000_000]]

# --- Roads -------------------------------------------------------------------

## Building a road: what the city pays, dollars per metre. A full new
## two-lane street costs about $1,000 a metre ($1.6M a mile, state DOT
## figures), but in US towns developers build most local streets and hand
## them to the city, and state and federal aid pays most of a highway. So the
## city's share is about a fifth (CS2 likewise prices a starter grid at a
## small slice of the opening funds).
## (Tuned 2026-10-22: at full price a starter street cost $16,000 a home and
## took five game years to pay back; CS2 pays back a first neighborhood in
## minutes.)
const ROAD_BUILD_PER_M := {
	RoadStyle.Type.STREET: 200, RoadStyle.Type.AVENUE: 450,
	RoadStyle.Type.BOULEVARD: 800, RoadStyle.Type.HIGHWAY: 1200, RoadStyle.Type.RAMP: 700,
	RoadStyle.Type.RING: 550, RoadStyle.Type.RING2: 900,
}
## Road upkeep, dollars per lane-metre per month (about $10,000 a lane-mile
## a year, typical of US city budgets).
const ROAD_UPKEEP_PER_LANE_M := 0.52
## A full-height bridge costs this many times more, a tunnel more still.
const BRIDGE_FACTOR := 4.0
const TUNNEL_FACTOR := 8.0

# --- Taxes and property ------------------------------------------------------

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

# --- Services ----------------------------------------------------------------

## Build cost, monthly upkeep, and either `capacity` (homes-equivalent a
## utility serves) or `reach` (metres by road a service covers).
const SERVICES := {
	# Ties the town to the regional grid. A 20 MVA distribution substation
	# carries about 13,000 homes.
	"substation": {"cost": 900_000, "upkeep": 6_000, "capacity": 13_000},
	# Well, pump house and a 500,000 gallon elevated tank: about 1 million
	# gallons a day, at 300 gallons per household.
	"water_tower": {"cost": 2_000_000, "upkeep": 12_000, "capacity": 3_300},
	# Starter power: an overhead feed with pole transformers from the utility.
	"power_feed": {"cost": 120_000, "upkeep": 1_000, "capacity": 400},
	# Starter water: a 150 gpm well with a pressure tank (~200,000 gallons a day).
	"well": {"cost": 300_000, "upkeep": 3_000, "capacity": 650},
	# Two-bay station. ISO rates homes within 1.5 road miles of a station.
	"fire": {"cost": 2_500_000, "upkeep": 45_000, "reach": 2400.0},
	# A small department's station, patrols covering about 2 road miles.
	"police": {"cost": 1_800_000, "upkeep": 50_000, "reach": 3200.0},
	# Walk-in clinic; most Americans live within a few miles of one.
	"clinic": {"cost": 1_500_000, "upkeep": 35_000, "reach": 4800.0},
	# Elementary school for about 400 pupils on a 2 acre site.
	"school": {"cost": 9_000_000, "upkeep": 95_000, "reach": 3200.0},
	# A small-town bus garage with two starter 40 ft buses. FTA Section 5339
	# pays 80% of transit capital, so this is the city's 20% share. It has no
	# fixed upkeep: the player sets a monthly subsidy instead (BusNet).
	"bus_depot": {"cost": 1_400_000, "upkeep": 0},
}
## Water and sewer bills the city collects, per building per month. The
## average US household pays about $100 a month for water and sewer
## together (AWWA/EPA surveys); businesses and plants use far more.
const WATER_FEE := {ZoneMap.Zone.RESIDENTIAL: 100, ZoneMap.Zone.COMMERCIAL: 250, ZoneMap.Zone.INDUSTRIAL: 600}
## How much power and water each building draws, in homes-equivalent.
const UTILITY_LOAD := {ZoneMap.Zone.RESIDENTIAL: 1, ZoneMap.Zone.COMMERCIAL: 4, ZoneMap.Zone.INDUSTRIAL: 12}

# --- Growth ------------------------------------------------------------------

## A new building can start every this many ticks (10 ticks = 1 real second).
const GROW_EVERY := 4
## People move in and stats update every this many ticks.
const MOVE_EVERY := 10
## Share of residents who work (US labour force is about half of everyone).
const WORKER_SHARE := 0.5

# --- Farms -------------------------------------------------------------------

const FARMHOUSE_COST := 350_000
## Iowa farmland is about $11,000 an acre.
const FARM_LAND_PER_ACRE := 10_000
## Farmland is taxed on what it produces, not its sale price (US "use value"
## assessment), roughly a quarter of market value.
const FARM_AG_ASSESSMENT := 0.25
## Yearly gross per acre at full fertility: corn about 180 bu x $4.50.
const FARM_GROSS_PER_ACRE := {"corn": 810.0, "soybeans": 600.0}
## Yearly cost per acre (seed, fuel, fertiliser, machinery; USDA operating
## costs with the land owned). Soybeans need no nitrogen, so they cost less.
const FARM_COST_PER_ACRE := {"corn": 420.0, "soybeans": 280.0}
## Extra yearly cost per acre for each km a field lies from the farmhouse.
const FARM_COST_PER_ACRE_PER_KM := 260.0
## Jobs: the farm family (2) plus a hired hand per this many cells (~40 acres).
const FARM_CELLS_PER_WORKER := 100
const FARM_MAX_CELLS := 400
## Dollars a year a field is preferred per neighbouring field of the same farm.
const FARM_COMPACT_BONUS := 25.0
## Dollars a year a field is preferred on land reserved for farming.
const FARM_RESERVE_BONUS := 40.0
## One crop price cycle, in game days (a game day settles a month: 4 years).
const FARM_PRICE_CYCLE_DAYS := 48.0
## Farms decide to buy or sell land this often, in ticks (6 game hours).
const FARM_DECIDE_EVERY := 360

# --- Resource industry -------------------------------------------------------

## Each kind of company: what the player pays to open its main building, and
## per pad (a well pad, pit or logging stand) at full richness: truck loads a
## month, dollars a load, yearly running cost and jobs.
## Oil: a Midwest pad of two pumpjacks makes about 200 barrels a month, one
## tanker load, about $14,000 at $70 a barrel.
## Ore: a pit fills about three 20 t dump trucks a month, ~$2,500 a load.
## Forest: a logging stand cuts about 1.5 log-truck loads a month, ~$1,800 each.
const INDUSTRY := {
	"oil": {"cost": 600_000, "loads": 1.0, "price": 14_000.0, "pad_cost": 50_000.0, "jobs_hq": 12, "jobs_pad": 1},
	"ore": {"cost": 500_000, "loads": 3.0, "price": 2_500.0, "pad_cost": 25_000.0, "jobs_hq": 15, "jobs_pad": 3},
	"forest": {"cost": 300_000, "loads": 1.5, "price": 1_800.0, "pad_cost": 9_000.0, "jobs_hq": 8, "jobs_pad": 2},
}
## Hauling from a pad to the main building, dollars a year per km.
const INDUSTRY_HAUL_PER_KM := 6_000.0
## Assessed value of each pad, for the city's industrial property tax.
const INDUSTRY_PAD_VALUE := 250_000.0
## Dollars a year a pad is preferred per neighbouring pad, or on reserved land.
const INDUSTRY_COMPACT_BONUS := 4_000.0
const INDUSTRY_RESERVE_BONUS := 6_000.0
## Pads go only where the deposit is at least this rich (0 to 1).
const INDUSTRY_MIN_RICHNESS := 0.25
## Loads a company stores before it stops producing (no truck got out).
const INDUSTRY_STOCK_CAP := 12.0
## Companies decide to open or close a pad this often, in ticks (6 game hours).
const INDUSTRY_DECIDE_EVERY := 360

# --- Freight -----------------------------------------------------------------

## Grain a farm ships: bushels an acre a year at full fertility (USDA Iowa
## yields), and one hopper semi's load.
const FARM_BUSHELS_PER_ACRE := {"corn": 180.0, "soybeans": 55.0}
const GRAIN_TRUCK_BUSHELS := 1_000.0
## A factory ships one load of goods to the shops for this many loads in.
const FACTORY_LOADS_PER_GOODS := 2.0

# --- Neighborhood character --------------------------------------------------
# Brawn's rule (2026-10-22): neighborhoods grow a culture of their own, and
# anything that fills in by itself (parks, trees, shopfronts, upkeep) matches
# how well the neighborhood is doing.

## How a neighborhood's wealth score (0 to 1) is made up. Land value is the
## biggest part, as in real assessments; the rest is how well it is served
## and whether its people have work.
const HOOD_WEALTH_WEIGHTS := {"land_value": 0.4, "services": 0.25, "employment": 0.2, "occupancy": 0.15}
## Wealth tiers, lowest first: the score a neighborhood needs to reach each
## one, and how lavish the things that fill in there are (1.0 = a plain,
## well-kept town standard). A thriving area gets a curated park with
## flowerbeds and a fountain; a struggling one a worn lawn and a rusty swing.
const HOOD_TIERS := [
	{"key": "struggling", "name": "Struggling", "min": 0.0, "finish": 0.6, "upkeep": 0.6},
	{"key": "working", "name": "Working class", "min": 0.3, "finish": 0.85, "upkeep": 0.85},
	{"key": "comfortable", "name": "Comfortable", "min": 0.55, "finish": 1.0, "upkeep": 1.0},
	{"key": "thriving", "name": "Thriving", "min": 0.8, "finish": 1.4, "upkeep": 1.3},
]
## A neighborhood moves up or down a tier only once its score passes the
## line by this much, so it doesn't flicker back and forth.
const HOOD_TIER_MARGIN := 0.05
## How slowly character follows the numbers: half the gap between the score a
## neighborhood has and the one its conditions call for closes in this many
## game days (a game day is a month, so about a year; real neighborhoods
## change over years, and at 1x a year is about half an hour of play).
const HOOD_HALF_LIFE_DAYS := 12.0
## Declining is faster than improving (disinvestment shows sooner than
## gentrification does): the half-life is multiplied by this on the way down.
const HOOD_DECLINE_SPEED := 0.75
## How far apart homes can be and still count as one neighborhood, metres
## (about a quarter-mile walk, the usual US planning radius).
const HOOD_RADIUS := 400.0

# --- Hubs, waste and cemeteries -----------------------------------------------
# Brawn's rules (2026-10-22): a hub never opens a second location. It grows
# only into free land directly next to what it already has. Landfills and
# cemeteries never fill up (CS1 and CS2 players modded that away), but they
# change the land around them.

## A hub's new piece must touch its current footprint, within this gap in
## metres (room for a fence or a service lane, never a separate site).
const HUB_ADJACENT_GAP := 10.0
## A hub's footprint can grow to at most this many times its first building's.
const HUB_MAX_GROWTH := 6.0

## Waste and burial sites: build cost, monthly upkeep, and how they change
## nearby land value. `value` is the change right next door (-0.15 = 15%
## lower), fading to nothing at `reach` metres. Real studies find homes next
## to a large landfill sell for roughly 10-15% less, fading over about half a
## mile; recycling plants have a much smaller effect, and enclosed ones none.
## A cemetery is open green space and a place of meaning, so it lifts the
## area around it a little.
const WASTE_SITES := {
	"landfill": {"cost": 1_500_000, "upkeep": 20_000, "value": -0.15, "reach": 800.0},
	# Recycling replaces a landfill and can be upgraded twice: a drop-off
	# yard, then a sorting plant, then an enclosed materials recovery plant.
	# Sold materials offset part of the upkeep (`sales`, dollars a month).
	"recycling_1": {"cost": 2_500_000, "upkeep": 25_000, "sales": 8_000, "value": -0.06, "reach": 400.0},
	"recycling_2": {"cost": 2_000_000, "upkeep": 32_000, "sales": 18_000, "value": -0.03, "reach": 250.0},
	"recycling_3": {"cost": 4_000_000, "upkeep": 40_000, "sales": 32_000, "value": 0.0, "reach": 0.0},
	"cemetery": {"cost": 800_000, "upkeep": 8_000, "value": 0.05, "reach": 300.0},
}
## Upgrade costs are what you pay to step up from the level below; going
## from landfill to recycling_1 also clears the landfill's effect over this
## many game days (the old mound is capped and grassed over).
const LANDFILL_RECOVERY_DAYS := 24.0


# --- Buses -------------------------------------------------------------------
# Brawn's rule (2026-10-22): the player places a bus depot and gives it land
# and a monthly subsidy; the depot plans its own stops, routes, fleet and fare
# and tries to stay in business. Benchmark: CS2 buses, with line drawing
# replaced by the depot's own planning. Numbers are real US transit figures
# (FTA National Transit Database, TCRP reports).

## Stops: the depot keeps them at least this far apart, metres (TCRP Report
## 19 suggests 750 to 1,300 ft in suburbs; Brawn: "about every 2 to 3 blocks").
const BUS_STOP_SPACING := 300.0
## How far people walk to a stop, metres (the US planning quarter mile).
const BUS_WALK := 400.0
## People (residents plus 0.8 per job) a stop's walk must reach to be worth it.
const BUS_STOP_MIN_PEOPLE := 80.0
## A small-town route visits about this many stops before it's split in two.
const BUS_STOPS_PER_ROUTE := 12
const BUS_MAX_ROUTES := 8
## Average speed with stops, km/h (US local buses: about 12 mph).
const BUS_AVG_KMH := 19.0
## Every 30 minutes is the small-town US standard the depot aims for.
const BUS_TARGET_HEADWAY_MIN := 30.0
## Service day, hours (6 am to 7 pm, typical of a small US system).
const BUS_SERVICE_HOURS := 13.0
## A 40 ft bus: 40 seats, about 60 with standees.
const BUS_CAPACITY := 60
## Operating cost per bus per hour of service (NTD: about $120 for small
## urban systems), so one bus for a month of 30 service days:
const BUS_MONTHLY_COST := 120 * 13 * 30
## A new 40 ft diesel bus costs about $550,000; FTA pays 80%.
const BUS_PRICE_LOCAL := 110_000
## What a retired bus fetches at auction.
const BUS_RESALE := 15_000
## FTA Section 5307/5311 operating aid: up to half of the net operating
## deficit (cost minus fares).
const BUS_GRANT_SHARE := 0.5
## Transit's share of trips in a small US city with half-hourly buses at a
## $1.50 fare and a middle income (ACS: 1 to 2%; poorer areas ride more).
const BUS_BASE_SHARE := 0.02
## Riders change by this power of the fare and of the frequency (TCRP Report
## 95: fare elasticity about -0.4, service elasticity about +0.5).
const BUS_FARE_ELASTICITY := -0.4
const BUS_SERVICE_ELASTICITY := 0.5
## The highest fare a depot thinks its riders will bear: this plus up to
## BUS_FARE_RICH_EXTRA in the best-off neighborhoods (US fares: $0.50-$3).
const BUS_FARE_BASE_MAX := 1.0
const BUS_FARE_RICH_EXTRA := 2.0
## A new depot starts at a typical small-town fare and monthly subsidy.
const BUS_START_FARE := 1.25
const BUS_START_SUBSIDY := 40_000
const BUS_SUBSIDY_MAX := 1_000_000
## Brawn (2026-10-22): no penny-pinching. The player picks a broad funding
## level; each is a monthly subsidy (Standard runs about two buses).
const BUS_FUNDING_LEVELS := [["None", 0], ["Lean", 20_000], ["Standard", 40_000], ["Generous", 80_000],
	["Lavish", 160_000]]
## The depot buys land next door at about $50,000 an acre (Midwest town
## edge), dollars per square metre.
const BUS_LAND_PER_M2 := 12.0

## School buses (Type C, 72 elementary pupils, 3 to a seat). Districts bus
## pupils who live farther than about a mile by road; 0.8 mile straight-line
## stands in for that. About 8% of people are of elementary age.
const SCHOOL_BUS_LOAD := 66
const SCHOOL_BUS_MAX := 8
const SCHOOL_WALK := 1300.0
const SCHOOL_PUPIL_SHARE := 0.08
## Bell times: buses leave the school this long before the morning bell and
## right after the afternoon bell (8:00 am and 3:00 pm), in game minutes.
const SCHOOL_MORNING_RUN := 6 * 60 + 40
const SCHOOL_AFTERNOON_RUN := 15 * 60 + 5
