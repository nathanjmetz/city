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

# --- Power companies ----------------------------------------------------------
# Brawn's hub-with-a-leader model (Best of CS pitch #6). A plant is built
# unit by unit; each unit's numbers below. `homes` is the average output in
# homes-equivalent at full quality (EIA: a US home uses about 10,500 kWh a
# year). `capex` is what one unit costs to build, `opex` its fuel and upkeep
# per MWh, `value`/`reach` how much it lowers land value next door and how
# far that fades out (like WASTE_SITES), `smoke_weight` how much an educated
# leader minds that, and `firm` whether it runs day and night.
## Solar: a 0.3 MW block of panels on an 80 m cell (~1.6 acres), 22% capacity
## factor, $1,100/kW. Wind: one 2.8 MW turbine at 38%, $1,300/kW, a
## turbine every 240 m with the farm going on around its 40 m pad. Gas: one
## 9 MW reciprocating engine run at 70%, $1,000/kW, burning the oil field's
## own gas. Coal: an old 30 MW unit bought used and refitted, 48% (the
## Petersburg, Indiana plant's story in miniature). Hydro: a 3 MW
## run-of-river bay retrofitted into an old mill dam, $2,000/kW.
## `carbon` is tonnes of CO2 per MWh, which educated leaders price in.
const POWER_PLANTS := {
	"coal": {"name": "Old coal plant", "unit": "boiler unit", "homes": 12_000.0, "capex": 4_000_000,
		"opex": 46.0, "firm": true, "value": -0.2, "reach": 1200.0, "smoke_weight": 1500.0, "carbon": 1.0,
		"jobs": 30, "max_cells": 2, "spacing": 80.0, "footprint": 80.0},
	"gas": {"name": "Gas plant", "unit": "engine", "homes": 5_250.0, "capex": 9_000_000,
		"opex": 40.0, "firm": true, "value": -0.04, "reach": 300.0, "smoke_weight": 600.0, "carbon": 0.45,
		"jobs": 6, "max_cells": 4, "spacing": 80.0, "footprint": 80.0},
	"solar": {"name": "Solar farm", "unit": "block of panels", "homes": 55.0, "capex": 330_000,
		"opex": 8.0, "firm": false, "value": 0.0, "reach": 0.0, "smoke_weight": 0.0, "carbon": 0.0,
		"jobs": 0.15, "max_cells": 48, "spacing": 80.0, "footprint": 80.0},
	"wind": {"name": "Wind farm", "unit": "turbine", "homes": 885.0, "capex": 3_640_000,
		"opex": 12.0, "firm": false, "value": 0.0, "reach": 0.0, "smoke_weight": 0.0, "carbon": 0.0,
		"jobs": 0.5, "max_cells": 16, "spacing": 240.0, "footprint": 40.0},
	"hydro": {"name": "River dam", "unit": "dam bay", "homes": 830.0, "capex": 6_000_000,
		"opex": 10.0, "firm": true, "value": 0.0, "reach": 0.0, "smoke_weight": 0.0, "carbon": 0.0,
		"jobs": 3, "max_cells": 4, "spacing": 80.0, "footprint": 80.0},
}
## Which plant wins a tie, cleanest first.
const POWER_PLANT_ORDER := ["hydro", "wind", "solar", "gas", "coal"]
## What the player pays for the yard (switchyard and control building), its
## assessed value, and the jobs there.
const POWER_YARD_COST := 1_200_000
const POWER_YARD_VALUE := 1_200_000.0
const POWER_YARD_JOBS := 6.0
const POWER_MWH_PER_HOME := 10.5
## Dollars per MWh: selling to the town's utility, and wholesale to the
## region (MISO prices run about $30-45), and the gas price with the field's
## own gas right there.
const POWER_TOWN_PRICE := 55.0
const POWER_EXPORT_PRICE := 38.0
const POWER_GAS_LOCAL_OPEX := 24.0
## Extra a plant that runs day and night is worth per MWh (capacity payments).
const POWER_FIRM_BONUS := 6.0
## Dollars per tonne of CO2 a leader with an engineering degree prices in
## for the risk of carbon rules over the plant's life (scaled by education).
const POWER_CARBON_PRICE := 20.0
## Years a leader plans ahead, from no schooling to an engineering degree.
const POWER_HORIZON_MIN := 3.0
const POWER_HORIZON_MAX := 25.0
## How far a leader's education can stray from the town's.
const POWER_LEADER_SPREAD := 0.1
## A unit goes only where wind, sun or river is at least this good.
const POWER_MIN_QUALITY := 0.3
const POWER_LOAN_YEARS := 20.0
## Yearly profit above which a company is "doing well".
const POWER_THRIVING_PROFIT := 250_000.0
## Land value never drops more than this from power plants.
const POWER_SMOKE_FLOOR := -0.3
## A house is this much less likely to go up per point of land value lost.
const POWER_SMOKE_GROWTH := 2.0
## Companies decide to add or mothball a unit this often, in ticks.
const POWER_DECIDE_EVERY := 360
## The town's schooling (0 to 1) with no school, and what a school
## covering every home adds. About a third of rural Midwest adults hold a
## college degree.
const TOWN_EDUCATION_BASE := 0.25
const TOWN_EDUCATION_SCHOOLS := 0.5
## Factories this close to a coal or gas plant can buy its steam, metres.
const POWER_STEAM_REACH := 600.0
## Steam sales and blade-yard work, dollars a year.
const POWER_STEAM_SALES := 300_000.0
const POWER_BLADE_YARD_SALES := 200_000.0
## Leaders retire and a successor takes over this often, in game days.
const POWER_LEADER_TERM_DAYS := 120.0
## A training center lifts a successor's education by this much.
const POWER_TRAINING_LIFT := 0.15

# --- Freight -----------------------------------------------------------------

## Grain a farm ships: bushels an acre a year at full fertility (USDA Iowa
## yields), and one hopper semi's load.
const FARM_BUSHELS_PER_ACRE := {"corn": 180.0, "soybeans": 55.0}
const GRAIN_TRUCK_BUSHELS := 1_000.0
## A factory ships one load of goods to the shops for this many loads in.
const FACTORY_LOADS_PER_GOODS := 2.0
## Factories in the industrial zone follow the town's industry (Brawn): each
## one that moves in works whatever is produced most nearby. "input" is the
## cargo it buys (grain covers corn and soybeans); "general" works materials
## shipped in from the region when nothing local is near.
const FACTORY_CHAINS := {
	"mill": {"name": "Grain mill", "input": "grain", "makes": "flour and feed"},
	"sawmill": {"name": "Sawmill", "input": "logs", "makes": "lumber"},
	"refinery": {"name": "Plastics plant", "input": "crude oil", "makes": "plastics"},
	"metal": {"name": "Metal works", "input": "ore", "makes": "steel parts"},
	"general": {"name": "Factory", "input": "materials", "makes": "goods"},
}
## How far a new factory looks for local supply, in metres, and how much
## nearby output it needs before it follows that chain (loads a month).
const FACTORY_CHAIN_REACH := 3000.0
const FACTORY_CHAIN_MIN := 0.5

# --- Warehouses ----------------------------------------------------------------
# Brawn (2026-10-22): warehouses in many real sizes, like Cities: Skylines'
# storage buildings. They take loads nobody needs yet and send them on when a
# factory or shop wants them. Every load still rides a real truck.

## Each size when first built: building width along the road and depth
## (metres), the truck court in front, dock doors, what the player pays, jobs
## and assessed value. Sizes follow US industrial real estate: a 10,000 sq ft
## flex building, a 32,000 sq ft bulk warehouse, a 100,000 sq ft regional
## warehouse and a 270,000 sq ft distribution center. Truck courts run
## 18-40 m (60-130 ft), enough for a 53 ft trailer to back in. About one
## dock door per 10,000 sq ft, and one job per 2,500 sq ft.
const WAREHOUSE := {
	"small": {"w": 30.0, "d": 30.0, "court": 18.0, "docks": 3, "cost": 300_000, "jobs": 4, "value": 900_000.0},
	"medium": {"w": 50.0, "d": 60.0, "court": 28.0, "docks": 6, "cost": 800_000, "jobs": 13, "value": 2_800_000.0},
	"large": {"w": 90.0, "d": 100.0, "court": 36.0, "docks": 12, "cost": 1_800_000, "jobs": 40, "value": 8_500_000.0},
	"dc": {"w": 140.0, "d": 180.0, "court": 40.0, "docks": 26, "cost": 4_000_000, "jobs": 100, "value": 24_000_000.0},
}
## Floor area one stored truckload takes, m² (26 pallets racked three high
## with aisles), at the first clear height.
const WAREHOUSE_M2_PER_LOAD := 40.0
## Clear heights a warehouse builds up through before it buys land: 24, 32
## and 40 ft. Taller racks hold more on the same floor.
const WAREHOUSE_HEIGHTS := [7.3, 9.8, 12.2]
## A back extension adds one structural bay this deep (50 ft column spacing).
const WAREHOUSE_BAY := 15.0
## Full this much at two decisions in a row, it builds up or out; nearly
## empty and idle this many decisions in a row, it gives back a bay.
const WAREHOUSE_BUSY := 0.8
const WAREHOUSE_IDLE := 0.05
const WAREHOUSE_IDLE_STREAK := 8
## Warehouses decide to grow this often, in ticks (6 game hours).
const WAREHOUSE_DECIDE_EVERY := 360
## What a warehouse earns per truckload it handles: a real 3PL charges
## handling in and out plus monthly storage, about $150 to $350 a load.
const WAREHOUSE_FEE := 250.0
## Running a warehouse per m2 of floor a year (power, insurance, upkeep;
## real US distribution space runs about $3 to $6 a square foot).
const WAREHOUSE_UPKEEP_M2 := 4.0
## A regional DC offers neighbouring towns up to this many loads a month.
const WAREHOUSE_REGIONAL_LOADS := 8
## Online orders a fulfillment center packs, per person in town a month:
## Americans get about 5 parcels a month; a local center fills about a
## tenth of them (the rest come in on the mail truck).
const WAREHOUSE_PARCELS_PER_PERSON := 0.5
## Parcels in a trailer from the fulfillment center to the post office
## (a 53 ft trailer holds about 1,000 to 2,000 parcels).
const WAREHOUSE_PARCEL_TRUCK := 1200

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
## Intercity coach to the neighboring towns (a development-tree option):
## a one-way fare like rural intercity lines (FTA 5311(f)), its running cost
## a month (about $90 an hour, 10 hours a day), and the share of townspeople
## who take a trip to a neighboring town on a given day, per neighbor.
const BUS_COACH_FARE := 15.0
const BUS_COACH_MONTHLY := 90 * 10 * 30
const BUS_COACH_DAILY_SHARE := 0.0015
## Game ticks a coach spends in the neighboring town before coming back.
const BUS_COACH_AWAY := 600
## Seats on a 45-foot motorcoach (MCI J4500).
const BUS_COACH_SEATS := 56
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
# --- Wild trees and brush ----------------------------------------------------

## Cleared land left alone grows back the way an abandoned lot in southern
## Indiana does (old-field succession, USDA Forest Service): grass and weeds
## the first season, brush (sumac, dogwood, blackberry) in a year or two,
## pioneer trees (eastern red cedar, box elder, black locust) poking through
## after a few years, and a young woodlot as tall as its neighbours in about
## twenty. Years are game years: a game day is a month, so a year is 12 game
## days (about half an hour at 1x, like the budget).
const WILD_BRUSH_YEARS := 1.5
const WILD_TREE_YEARS := 4.0
const WILD_MATURE_YEARS := 20.0
## Share of spots on an abandoned lot that end up as trees (most of an
## untended Midwest lot is woods after twenty years), and as brush while the
## trees are still young.
const WILD_REGROW_TREES := 0.5
const WILD_REGROW_BRUSH := 0.45
## Trash, which garbage trucks carry to a landfill or recycling centre. A
## game day here is a real day for trash (a month would bury a small town):
## Americans throw out about 4.9 lb a person a day (EPA), and a business
## about 2 lb per job.
const GARBAGE_LB_PER_RESIDENT := 4.9
const GARBAGE_LB_PER_JOB := 2.0
## A rear-loader garbage truck carries about 10 tons when full.
const GARBAGE_TRUCK_LB := 20_000.0
## A street is worth a stop once this much trash is out at the curb (about a
## week of trash for six or seven homes), and a truck makes at most this many
## stops before it heads back.
const GARBAGE_STOP_LB := 600.0
const GARBAGE_STOPS_PER_RUN := 6
## Trash left out past this much on a street lowers its land value by
## GARBAGE_PILE_VALUE (-0.05 = 5% lower) until a truck comes.
const GARBAGE_PILE_LB := 2_500.0
const GARBAGE_PILE_VALUE := -0.05
## Trucks each waste site keeps, plus one more for every two pieces of land
## it has grown into.
const HUB_TRUCKS := {"landfill": 3, "recycling_1": 2, "recycling_2": 3, "recycling_3": 4}
## Each piece of land a hub grows into adds this share of its base upkeep.
const HUB_PIECE_UPKEEP := 0.15
## Hubs decide whether to grow this often, in ticks (6 game hours). A waste
## site grows when its trucks were all out on at least this share of the
## rounds it wanted to send one; it gives land back after this many quiet
## decisions in a row.
const HUB_DECIDE_EVERY := 360
const HUB_GROW_BUSY_SHARE := 0.5
const HUB_SHRINK_QUIET := 8
## A cemetery takes one more piece of land for every this many residents.
const CEMETERY_PEOPLE_PER_PIECE := 1_200

# --- Region and trade ----------------------------------------------------------

## Price of a unit of each traded good or service, in dollars. Hubs add their
## goods here (power in MWh, water in thousand gallons, garbage in tons...).
const TRADE_PRICE := {
	# Wholesale power from landfill gas, per MWh.
	"power": 60.0,
	# Taking a town's trash, per ton: the US average landfill tipping fee.
	"garbage": 55.0,
	# Baled scrap metal and finished compost, per ton.
	"scrap": 180.0,
	"compost": 25.0,
	# Wholesale water between towns, per thousand gallons (Indiana wholesale
	# rates run about $2.50 to $4).
	"water": 3.0,
	# A truckload of general merchandise from a regional DC: the
	# distributor's margin on it.
	"goods": 2500.0,
}
## Price for a good with no entry above.
const TRADE_PRICE_DEFAULT := 100.0
## What no neighbor covers is bought from the outside world at this many
## times the price...
const TRADE_IMPORT_MARKUP := 1.5
## ...and what no neighbor buys is sold to it for this share of the price.
## Trading with a neighbor is the better deal for both towns.
const TRADE_EXPORT_SHARE := 0.6

# --- Parks and landmarks -------------------------------------------------------
# Brawn's rules (2026-10-22): a park is a hub. You place it and it fills in by
# itself over time (paths, a playground, a pavilion, a ball diamond), growing
# only into free land right next to it, and how well kept it is follows the
# neighborhood's tier. Landmarks are one-of-a-kind town buildings that lift
# land value and happiness around them.

## A new park: its first piece of ground (width along the road x depth,
## metres; about 0.7 acre, a US "mini park") and what the city pays for it.
const PARK_START_SIZE := Vector2(60, 50)
const PARK_COST := 250_000
## Town land a park buys when it grows, dollars an acre (Midwestern town
## land outside downtown).
const PARK_LAND_PER_ACRE := 15_000
## Each growth step adds a strip this deep along one side, metres.
const PARK_GROW_STEP := 20.0
## Upkeep per acre per month: US parks departments spend about $7,000 an
## acre a year (NRPA Park Metrics median), scaled by the tier's `upkeep`.
const PARK_UPKEEP_PER_ACRE := 600
## A park adds one thing (a path, a playground...) at most this often, in
## game days (a day is a month: a park fills in over a couple of years).
const PARK_FEATURE_DAYS := 2.0
## A park only buys more land while at least this many people live within
## the neighborhood radius (someone has to use it), and never in a
## struggling neighborhood.
const PARK_GROW_MIN_RESIDENTS := 30
## Parks and landmarks decide what to do this often, in ticks (6 game hours).
const PARK_DECIDE_EVERY := 360
## What a park fills in with, in order, and the space each needs (width x
## depth, metres). `tier` is the lowest neighborhood tier that gets it
## (0 struggling .. 3 thriving). Real references: a Little League field
## with 200 ft fences, a 30 x 40 ft picnic shelter, a half basketball court.
const PARK_FEATURES := [
	{"type": "paths", "size": Vector2.ZERO, "tier": 0},
	{"type": "playground", "size": Vector2(18, 14), "tier": 0},
	{"type": "pavilion", "size": Vector2(14, 11), "tier": 0},
	{"type": "court", "size": Vector2(16, 15), "tier": 1},
	{"type": "ball_diamond", "size": Vector2(70, 64), "tier": 0},
	{"type": "flower_beds", "size": Vector2(12, 8), "tier": 2},
	{"type": "fountain", "size": Vector2(10, 10), "tier": 3},
]

## Amenities: build cost, monthly upkeep, and their pull on the land around.
## `value` is the lift in land value right next door (0.10 = 10% higher),
## fading to nothing at `value_reach` metres; `happy` likewise for how much
## nearby residents like living there. Real studies (Crompton, 2005) find
## homes beside a neighborhood park sell for about 8-20% more, fading over
## 500-2,000 ft. A park's pull also scales with how filled-in and kept it is.
## Landmarks are one per town, like the signature buildings in CS2.
const AMENITIES := {
	"park": {"cost": PARK_COST, "upkeep": 0, "value": 0.10, "value_reach": 300.0, "happy": 0.10, "happy_reach": 600.0},
	# An Indiana county seat's courthouse on a full block of lawn, with
	# diagonal walks and a war memorial (about 300 ft square).
	"courthouse": {"cost": 6_000_000, "upkeep": 30_000, "size": Vector2(90, 90),
		"value": 0.12, "value_reach": 600.0, "happy": 0.15, "happy_reach": 900.0},
	# The town's old multi-leg water tower, painted with the town name. It
	# is a symbol, so it is seen and felt far away.
	"water_tower": {"cost": 900_000, "upkeep": 4_000, "size": Vector2(30, 30),
		"value": 0.04, "value_reach": 500.0, "happy": 0.10, "happy_reach": 1500.0},
	# A farmers' co-op grain elevator: concrete silos and a headhouse.
	"grain_elevator": {"cost": 2_500_000, "upkeep": 6_000, "size": Vector2(56, 40),
		"value": 0.03, "value_reach": 400.0, "happy": 0.06, "happy_reach": 1200.0},
	# The high school football field: a 120 yd field, bleachers, a press box
	# and lights (Friday nights are a small-town institution).
	"football": {"cost": 4_000_000, "upkeep": 15_000, "size": Vector2(140, 84),
		"value": 0.06, "value_reach": 600.0, "happy": 0.12, "happy_reach": 1600.0},
}
## Most land value and happiness a home can get from parks and landmarks
## together.
const AMENITY_VALUE_CAP := 0.25
const AMENITY_HAPPY_CAP := 0.4
## How much the town's average amenity happiness raises demand for homes.
const AMENITY_DEMAND := 0.3
## In the neighborhood score, land value counts as this plus the amenity
## lift times AMENITY_LAND_SCALE (0 to 1), until a land value model lands.
const HOOD_LAND_BASE := 0.5
const AMENITY_LAND_SCALE := 2.5
# --- Hub development trees -------------------------------------------------------
# Brawn (2026-10-22): every hub has a thick tree of buildings and options. Its
# leader unlocks them from what the town can do (money, schools, size) and
# what is around it, in town and in neighboring towns. A capped landfill
# under a recycling centre keeps the landfill tree (it still makes gas).
## Development trees for landfills, recycling and cemeteries, in the shared
## Agency format (see agency.gd): the hub's leader picks what to build next
## on its own. `upkeep` is extra dollars a month. Needs starting "site_"
## are about the hub itself (CivicHubs checks them): site_pieces (land),
## site_tons (trash in the mound), site_level (recycling plant level),
## site_forest (woods next to it). Effects: power, compost, scrap and garbage
## are what it sells a month (MWh or tons), "sales*" lifts materials sold,
## value/reach lift land value nearby, grow lets the hub grow further.
const HUB_TREES := {
	"landfill": [
		# Landfill gas to electricity: an engine plant burning the methane a
		# big, old landfill gives off.
		{"id": "gas_plant", "name": "Landfill gas plant", "cost": 2_200_000, "upkeep": 9_000,
			"needs": {"site_pieces": 10, "site_tons": 20_000}, "effects": {"power": 700.0},
			"note": "sells power to the neighbors or the grid"},
		# Yard waste and food scraps turned into compost for nearby farms.
		{"id": "compost", "name": "Compost yard", "cost": 400_000, "upkeep": 4_000,
			"needs": {"local:farm": 1}, "effects": {"compost": 300.0}, "note": "farms nearby buy the compost"},
		# A transfer station takes in a neighbor town's trash for a fee.
		{"id": "transfer", "name": "Transfer station", "cost": 900_000, "upkeep": 7_000,
			"needs": {"link": 1, "region_buys:garbage": 1}, "effects": {"garbage": 600.0},
			"note": "a neighbor town pays to send its trash here"},
	],
	"recycling": [
		# Scrap metal yard: crushes and bales metal for the metal works.
		{"id": "scrap_yard", "name": "Scrap metal yard", "cost": 600_000, "upkeep": 5_000,
			"needs": {"local:metal": 1}, "effects": {"scrap": 60.0}, "note": "the metal works nearby buys scrap"},
		# Extra sorting lines need trained workers.
		{"id": "glass_line", "name": "Glass sorting line", "cost": 700_000, "upkeep": 4_000,
			"needs": {"site_level": 2, "education": 0.3}, "effects": {"sales*": 0.35}},
		{"id": "ewaste", "name": "Electronics recycling", "cost": 1_200_000, "upkeep": 6_000,
			"requires": ["glass_line"], "needs": {"site_level": 3, "education": 0.5, "population": 2_000},
			"effects": {"sales*": 0.5}},
		# Sorting a neighbor town's recycling for a fee.
		{"id": "regional_mrf", "name": "Regional sorting contract", "cost": 500_000, "upkeep": 3_000,
			"needs": {"site_level": 3, "link": 1, "region_buys:garbage": 1}, "effects": {"garbage": 900.0}},
	],
	"cemetery": [
		{"id": "chapel", "name": "Chapel", "cost": 350_000, "upkeep": 2_000,
			"needs": {"population": 300}, "effects": {"value": 0.02, "reach": 100.0}},
		{"id": "garden", "name": "Memorial garden", "cost": 250_000, "upkeep": 2_500,
			"requires": ["chapel"], "needs": {}, "effects": {"value": 0.02, "reach": 50.0}},
		{"id": "veterans", "name": "Veterans memorial", "cost": 300_000, "upkeep": 1_000,
			"needs": {"population": 3_000}, "effects": {"value": 0.02, "reach": 150.0}},
		# Natural burial in the woods next door: room to grow half again as
		# far, under trees instead of lawn.
		{"id": "woods", "name": "Natural burial woods", "cost": 200_000, "upkeep": 1_500,
			"needs": {"site_forest": 0.3}, "effects": {"grow": 0.5}},
	],
}
## The town funds its landfills, recycling and cemeteries: their leaders plan
## projects against this many years of the hub's upkeep (Agency's "profit").
const HUB_PLAN_YEARS := 3.0
## Every waste site has room for this much of a neighbor's trash a month
## (tons) before any transfer station, so towns without one can trade.
const GARBAGE_BASE_TAKE_TONS := 150.0
## A town with no landfill or recycling of its own pays a neighbor to take its
## trash, if one will (otherwise it piles up).
const GARBAGE_TONS_PER_RESIDENT_MONTH := 0.07
# --- Schools and universities -------------------------------------------------
# Brawn's model (2026-10-22): the player places a high school, community
# college or university and sets its funding. Its principal or president
# runs it like a real institution trying to stay solvent: it fills its
# seats, saves, and buys the free land next to it for new buildings, never
# a second site. Graduates who stay make the town better educated, and
# office and tech jobs open only for the graduates the town has.

## Each kind of campus. `cost` is what the player pays for the first
## building; `funding` is the city's standard monthly contribution (the
## player can set it from half to one and a half times). Per student a
## year: `aid` (state money, which follows the student), `tuition` and
## `spend` (what teaching a student costs). `seats` the first building
## holds and `block_seats` each campus block adds (a block is a CELL
## square of campus), `block_cost` what buying and building one costs, and
## `max_blocks` the most it will ever own (real campus acreage). `years` to
## graduate, `grad_rate` of those who finish, and `stay` the share of
## graduates who settle in town. `staff` is students per job.
## Real figures: an Indiana high school costs about $30,000 a seat to build
## and $10,000 a student a year to run, mostly paid by the state; Ivy Tech
## community college tuition is about $4,500 a year and about a third
## finish; a regional state university charges about $10,000 in-state and
## graduates about 60% in six years.
const EDUCATION := {
	"high_school": {"cost": 14_000_000, "funding": 60_000, "aid": 8_500.0, "tuition": 0.0, "spend": 8_000.0,
		"seats": 500, "block_seats": 250, "block_cost": 2_500_000, "max_blocks": 14,
		"years": 4, "grad_rate": 0.88, "stay": 0.6, "staff": 14},
	"college": {"cost": 9_000_000, "funding": 40_000, "aid": 4_000.0, "tuition": 4_500.0, "spend": 8_000.0,
		"seats": 600, "block_seats": 400, "block_cost": 3_500_000, "max_blocks": 12,
		"years": 2, "grad_rate": 0.35, "stay": 0.75, "staff": 18},
	"university": {"cost": 35_000_000, "funding": 120_000, "aid": 6_000.0, "tuition": 10_500.0, "spend": 15_500.0,
		"seats": 1_500, "block_seats": 900, "block_cost": 9_000_000, "max_blocks": 40,
		"years": 4, "grad_rate": 0.6, "stay": 0.3, "staff": 9},
}
## Funding levels the player can pick, as a share of the standard funding.
const EDUCATION_FUNDING_LEVELS := [0.5, 0.75, 1.0, 1.25, 1.5]
## Share of the town who are high-school age (US: about 5.3% are 14 to 17).
const EDUCATION_TEEN_SHARE := 0.053
## Share of the town who would take community college classes (about 2.5%
## of a US county's people are enrolled at one).
const EDUCATION_COLLEGE_SHARE := 0.025
## Students a college or university draws from the county and region beyond
## the town, at full reputation.
const EDUCATION_REGION_DRAW := {"college": 400, "university": 6_000}
## Reputation (0 to 1) a new university starts with, and how much of the gap
## to where funding and its president would take it closes each month.
const EDUCATION_START_REPUTATION := 0.3
const EDUCATION_REPUTATION_PULL := 0.02
## Graduates who stay leave town or retire at this share a year.
const EDUCATION_ATTRITION := 0.03
## Office and tech jobs each local graduate supports: a bachelor's degree
## brings one; an associate degree about half a job (the rest take the jobs
## that were already there).
const EDUCATION_OFFICE_JOBS := {"degree": 1.0, "associate": 0.5}
## Assessed value of an office job, for the city's commercial property tax.
const EDUCATION_OFFICE_VALUE := 150_000
## A president buys the next block only while applicants outnumber the seats
## by more than this share (an ambitious one sooner, a cautious one later),
## and only with a down payment saved: this share of the block's cost, plus
## up to as much again for a cautious president. The rest is borrowed (a
## bond) and paid back from the yearly surplus before the next purchase.
const EDUCATION_CROWDING := 0.05
const EDUCATION_DOWN_PAYMENT := 0.3
## A campus whose debt passes this many block costs sells its newest block.
const EDUCATION_SELL_DEBT := 1.5
## Campuses decide once a game day (a month).
const EDUCATION_DECIDE_EVERY := 1440
## What a campus pays per square metre to buy out the homes and shops next
## door (land plus the houses on it): a 120 m block of small-town Indiana
## homes, about a dozen at $120k-150k, comes to roughly $1.5M.
const EDUCATION_LAND_PER_M2 := 100

# --- Post office and mail --------------------------------------------------------
# Best of CS pitch #10, green-lit by Brawn (2026-10-22): a post office hub
# whose postmaster plans the routes, real carrier trips, a sorting center
# that grows next door, and a development tree (see Mail.TREE).

## A small-town post office (about 4,000 sq ft on 0.6 acre) and what the city
## pays a month to keep it open. Each piece of land it grows adds
## HUB_PIECE_UPKEEP of this.
const MAIL_COST := 1_200_000
const MAIL_UPKEEP := 14_000
## The city's funding levels, the player's lever: what goes to the postmaster
## a month on top of postage, to spend on the development tree.
const MAIL_FUNDING := [
	{"name": "Postage only", "monthly": 0},
	{"name": "Basic", "monthly": 6_000},
	{"name": "Generous", "monthly": 15_000},
	{"name": "Lavish", "monthly": 30_000},
]
## USPS handles about 116 billion pieces a year to 167 million delivery
## points over about 300 delivery days: 2.3 pieces a household a day.
## Businesses get several times that, and about 3 parcels a day each.
const MAIL_PIECES_PER_HOME := 2.3
const MAIL_PIECES_PER_BUSINESS := 9.0
const MAIL_PARCELS_PER_BUSINESS := 3.0
## Delivery days in a month, and what the postmaster keeps per piece after
## running costs (USPS takes in about 68 cents a piece; most goes to wages).
const MAIL_DAYS_PER_MONTH := 26.0
const MAIL_MARGIN_PER_PIECE := 0.04
## Neighbouring towns' postage a regional hub keeps, dollars a person a month.
const MAIL_REGIONAL_PER_PERSON := 0.15
## A neighbouring town whose size the region doesn't report counts as this
## many people (small towns around Petersburg, Indiana).
const MAIL_OFFLINE_TOWN_POP := 1_800
## A city carrier route is about 500 delivery points; a carrier's day also
## tops out at this many streets. A parcel van makes this many business
## stops and carries this many parcels.
const MAIL_POINTS_PER_ROUTE := 500
const MAIL_STOPS_PER_ROUTE := 30
const MAIL_VAN_STOPS := 25
const MAIL_VAN_PARCELS := 150
## Carrier trucks and jeeps, and parcel vans, an office starts with. Each
## piece of fleet lot it grows holds two more carriers.
const MAIL_CARRIERS := 2
const MAIL_VANS := 1
## A street with fewer homes than one per this many metres is a rural route
## (right-hand-drive jeeps and roadside boxes).
const MAIL_RURAL_SPACING := 40.0
## When the mail truck comes in from the region, when carriers and vans go
## out (after the mail is cased), and when the outgoing truck leaves. Hours.
const MAIL_FREIGHT_IN_HOUR := 5
const MAIL_ROUNDS_HOUR := 9
const MAIL_FREIGHT_OUT_HOUR := 17
## A street counts as served while its mail came within this many ticks
## (two days, so Sundays don't count against it).
const MAIL_SERVED_TICKS := 2 * 24 * 60
## Good mail makes a place a little better: land value on served streets
## (homes +2%, shops +4%, factories +3%), and demand for homes and shops
## (times the share served).
const MAIL_VALUE := {ZoneMap.Zone.RESIDENTIAL: 0.02, ZoneMap.Zone.COMMERCIAL: 0.04, ZoneMap.Zone.INDUSTRIAL: 0.03}
const MAIL_DEMAND_HOMES := 0.04
const MAIL_DEMAND_SHOPS := 0.06
## A neighbour's regional sorting hub speeds your mail too.
const MAIL_REGION_HUB_VALUE := 0.01
## What the tree's nodes do.
const MAIL_PO_BOX_VALUE := 0.005
const MAIL_PASSPORT_VALUE := 0.005
const MAIL_LOCKER_VALUE := 0.01
const MAIL_BUSINESS_MAIL_VALUE := 0.02
const MAIL_MURAL_VALUE := 0.03
const MAIL_MURAL_REACH := 300.0
const MAIL_CLUSTER_BOOST := 1.3
const MAIL_ELECTRIC_SAVING := 0.15
## A regional hub runs one more truck each way for each neighbouring town,
## up to this many.
const MAIL_REGIONAL_TRUCKS := 4
## The development tree's numbers: cost (from the postmaster's fund), land
## (pieces next door), days to build (game days), weight (how much it does,
## which Agency weighs against cost by the postmaster's temperament), and
## gates: population, pieces (of mail a day), shops, factories, towns and
## region_pop (neighbours), link (a road out to the region), education and
## ambition (the postmaster's own), town_school (share of homes near a
## school, Agency's "education"). Agency spends up to a few years' income.
const MAIL_TREE := {
	"po_boxes": {"cost": 40_000, "land": 0, "days": 1, "weight": 1, "population": 600},
	"passports": {"cost": 25_000, "land": 0, "days": 1, "weight": 2, "population": 1_500, "education": 0.5},
	"kiosk": {"cost": 60_000, "land": 0, "days": 1, "weight": 2, "population": 2_500, "town_school": 0.5},
	"mural": {"cost": 80_000, "land": 0, "days": 2, "weight": 1, "population": 1_200, "ambition": 0.4},
	"cluster_boxes": {"cost": 120_000, "land": 0, "days": 2, "weight": 3, "population": 3_000},
	"more_vans": {"cost": 180_000, "land": 1, "days": 1, "weight": 3, "shops": 15, "vans": 2},
	"electric_fleet": {"cost": 300_000, "land": 0, "days": 2, "weight": 2, "education": 0.6, "ambition": 0.6,
		"population": 2_000},
	"parcel_lockers": {"cost": 90_000, "land": 0, "days": 1, "weight": 2, "shops": 25},
	"business_mail": {"cost": 150_000, "land": 1, "days": 2, "weight": 2, "factories": 8},
	"parcel_depot": {"cost": 400_000, "land": 2, "days": 3, "weight": 4, "shops": 40, "vans": 3},
	"parcel_ground_hub": {"cost": 1_400_000, "land": 4, "days": 4, "weight": 5, "shops": 60, "vans": 6,
		"region_pop": 15_000},
	"sorting_room": {"cost": 250_000, "land": 1, "days": 2, "weight": 4, "pieces": 3_000},
	"sorting_center": {"cost": 900_000, "land": 3, "days": 4, "weight": 6, "pieces": 10_000},
	"regional_hub": {"cost": 1_600_000, "land": 4, "days": 5, "weight": 7, "towns": 2, "region_pop": 6_000, "link": 1,
		"education": 0.45},
	"rail_mail": {"cost": 900_000, "land": 1, "days": 3, "weight": 3},
	"air_mail": {"cost": 700_000, "land": 0, "days": 2, "weight": 3},
}

# --- Water and sewer utility ---------------------------------------------------
# Brawn's green (2026-10-22): the player places a water utility and sets its
# subsidy; its superintendent runs it like a small business and climbs a
# development tree on their own. Water and sewer bills go to the utility (a
# real US enterprise fund), not the city's general fund.

## Placing the utility: the office, its first well, and start-up capital
## (in real life a revenue bond) for the first water mains.
const WATER_UTILITY := {"cost": 900_000, "start_cash": 600_000}
## The manager decides this often, in ticks (6 game hours, a quarter month).
const WATER_DECIDE_EVERY := 360
## The player's subsidy, dollars a month: where a new utility starts, the
## most it can be, and each click of the panel's buttons.
const WATER_SUBSIDY := {"start": 5_000, "max": 60_000, "step": 1_000}
## Operators' wages and the office, dollars a month: a part-time certified
## operator for a village, plus more staff as the system grows (per home's
## worth served).
const WATER_STAFF := {"base": 4_000, "per_home": 8.0}
## The manager sets the water rate as a share of the usual bill, like a
## council-approved rate case: up when it loses money, down when it has a
## surplus, a step at a time and within these bounds. Each 10% over the usual
## bill cuts demand for homes by `demand` x 0.1.
const WATER_RATE := {"min": 0.7, "max": 1.6, "step": 0.02, "demand": 0.3}
## Share of sewer and treatment projects (and new sewer lines) paid by state
## and federal grants
## (USDA Rural Development and state revolving fund forgiveness for small towns).
const WATER_GRANT_SHARE := 0.5
## Laying pipe under an existing street, dollars a metre: an 8 inch ductile
## iron water main and an 8 inch PVC gravity sewer (US bid prices).
const WATER_MAIN_PER_M := 400
const SEWER_PER_M := 500
## Pipe upkeep, dollars a month per metre (flushing, valves, breaks).
const WATER_PIPE_UPKEEP_PER_M := 0.4
## How much water a town can draw without an elevated tower, in homes:
## pressure tanks only cover a village's peak hour.
const WATER_STORAGE_NO_TOWER := 800
## Most wells one wellfield holds before the aquifer is drawn down.
const WATER_MAX_WELLS := 6
## The development tree. `cost` and monthly `upkeep` in dollars, `edu` the
## manager's education (0 to 1) needed to take it on. `capacity` is homes of
## water (wells, tower, intake) or of sewage (lagoon, plant).
## Real practice: a 150 gpm well serves ~650 homes at 300 gal a day; a
## 500,000 gal tower stores a day for ~3,300; Indiana groundwater carries
## iron, so towns past a couple of wells add a filtration plant; small towns
## start with a facultative lagoon and move to an activated sludge plant.
const WATER_WORKS := {
	"well": {"cost": 300_000, "upkeep": 3_000, "edu": 0.0, "capacity": 650},
	"tower": {"cost": 2_000_000, "upkeep": 2_000, "edu": 0.0, "capacity": 3_300},
	"filtration": {"cost": 3_500_000, "upkeep": 12_000, "edu": 0.35},
	"intake": {"cost": 14_000_000, "upkeep": 45_000, "edu": 0.6, "capacity": 12_000},
	"lagoon": {"cost": 900_000, "upkeep": 3_000, "edu": 0.0, "capacity": 1_500},
	"plant": {"cost": 8_000_000, "upkeep": 25_000, "edu": 0.45, "capacity": 9_000},
	"nutrient": {"cost": 4_000_000, "upkeep": 10_000, "edu": 0.75},
	"meters": {"cost": 250_000, "upkeep": 1_500, "edu": 0.55},
	"training": {"cost": 900_000, "upkeep": 4_000, "edu": 0.5},
	"industrial_main": {"cost": 600_000, "upkeep": 1_000, "edu": 0.3},
	"wholesale": {"cost": 1_500_000, "upkeep": 2_000, "edu": 0.5},
	"biosolids": {"cost": 300_000, "upkeep": -2_000, "edu": 0.4},
	"reuse": {"cost": 5_000_000, "upkeep": 6_000, "edu": 0.8},
}
## Smart meters find leaks and slow meters: this much more billed water.
const WATER_METER_GAIN := 0.08
## The industrial main serves plants at a large-meter rate, this much more.
const WATER_INDUSTRY_GAIN := 0.5
## The interconnect with the next town: at most this many homes' worth of
## water offered to the region; a home uses about 9,000 gallons a month.
const WATER_WHOLESALE_MAX := 2_000
const WATER_KGAL_PER_HOME := 9.0
## Tap (connection) fees each new hookup pays the utility once, dollars per
## home's worth: typical small-town Indiana water and sewer tap fees.
const WATER_TAP_FEE := 4_000
const SEWER_TAP_FEE := 4_000
## Reclaimed water sold to farms within reach, dollars a month per farm.
const WATER_REUSE_PER_FARM := 1_500
## Farms within this many metres count as neighbours for biosolids and reuse.
const WATER_FARM_REACH := 3_000.0
## The water bill is half water, half sewer; homes on septic pay only half.
const WATER_SEWER_SHARE := 0.5
## Homes' worth of sewage before the town builds its first lagoon.
const WATER_SEWER_START := 40
## The manager's education follows the leaders the town can hire (its local
## graduates, Education.leader_education); a training center adds `training`.
## It drifts this share of the gap each step, as staff turn over.
const WATER_EDU := {"start": 0.25, "training": 0.12, "drift": 0.04}
## Condition (0 to 1) of pipes and plants. Full maintenance costs this share
## of running costs; a fully paid, fully educated manager keeps condition at
## 1, an uneducated one at `low` even fully paid; it moves this share of the
## way each step.
const WATER_MAINT := {"share": 0.25, "low": 0.45, "speed": 0.15}
## Under this condition the state orders a boil-water notice; overload adds to
## it (low pressure lets contamination in).
const WATER_BOIL_AT := 0.35
## Boil orders cut demand for homes by this much while they last.
const WATER_BOIL_DEMAND := 0.25
## Odor from a struggling sewer plant reaches this far and lowers land value
## (property tax) next door by up to this share.
const WATER_ODOR_REACH := 600.0
const WATER_ODOR_VALUE := 0.2
## Borrowing (revenue bonds, state revolving fund loans): a manager may owe up
## to this many months of bills and subsidy, times 0.3 to 1.0 by education;
## interest per month on what is owed.
const WATER_BOND_MONTHS := 60
const WATER_INTEREST := 0.004
## Cash kept in reserve, months of running costs (more for a cautious manager),
## and beyond this many months' worth the surplus goes back to the city.
const WATER_RESERVE_MONTHS := 2.0
const WATER_SURPLUS_MONTHS := 18.0
# --- Banks and lending ---------------------------------------------------------
# Brawn (2026-10-22, Best of CS pitch #20): a bank is a hub that lends to the
# other hubs. A farm borrows to buy the field next door, a company to put
# down another pad, a builder to put up a house, shop or factory. A cautious
# president lends slowly and safely; a bold one fuels fast growth and some
# failures. The player never touches a loan.
# Benchmarked against real small-town Indiana banking: a state-chartered
# community bank on the courthouse square (like the First National Bank of
# Petersburg, 1898, or German American Bank of Jasper) taking the town's
# deposits and lending them back, and a Farm Credit Mid-America branch office
# that lends only to farms and timber on the Farm Credit System's bonds.
# FDIC figures: community banks lend about 80 cents of each deposit dollar,
# need equity of 9% of assets to use the simple community bank leverage
# ratio, earn about a 3.5% net interest margin and charge off about 0.3% of
# loans in a normal year (several times that in a farm crisis).
## Per kind: `capital` the founders put up (equity), `cost` the city pays
## (the lot and a ribbon cutting; investors pay the rest), `block_cost` what
## the bank pays to buy and build one more block of its own premises,
## `max_blocks` the most it ever owns (a bank on the square is a building or
## two, with a drive-up and a lot), `staff` at opening, and what it lends to.
const BANKS := {
	"community": {"cost": 150_000, "capital": 4_000_000, "block_cost": 600_000, "max_blocks": 7, "staff": 6,
		"lends": ["farm", "company", "build"]},
	"farm_credit": {"cost": 75_000, "capital": 1_500_000, "block_cost": 400_000, "max_blocks": 5, "staff": 4,
		"lends": ["farm", "timber"]},
}
## Deposits a community bank can hope to gather: each resident keeps about
## this much in local banks (rural Indiana, FDIC deposit data), and each job
## brings business deposits too. Banks in town split it by reputation.
const BANK_DEPOSITS_PER_RESIDENT := 28_000.0
const BANK_DEPOSITS_PER_JOB := 12_000.0
## Share of the town's deposits that stays in banks in town (the rest sits
## in big-city banks and online).
const BANK_LOCAL_SHARE := 0.75
## Rates a year: loans, and what the bank pays on deposits. Farm Credit lends
## a little cheaper (the System's bonds, plus patronage dividends back to
## its borrowers), so farms borrow there first when both are in town.
const BANK_LOAN_RATE := 0.0725
const BANK_FARM_CREDIT_RATE := 0.0675
const BANK_DEPOSIT_RATE := 0.0225
## Farm Credit's lending limit: this share of the farmland value in reach
## (it doesn't take deposits; the System funds it).
const BANK_FARM_CREDIT_SHARE := 0.5
## What Farm Credit pays the System for the money it lends, a year.
const BANK_FARM_CREDIT_FUNDING := 0.045
## Loan to value: how much of a purchase a bank lends (the borrower puts
## down the rest). A cautious president lends the low end, a bold one the high.
const BANK_LTV := [0.65, 0.85]
## Loan-to-deposit ratio a president lends up to: cautious to bold.
const BANK_LTD := [0.7, 0.95]
## Equity the bank keeps against its loans (community bank leverage ratio),
## the level where regulators put it under an order to stop lending, and
## where the FDIC closes it and sells it to a healthier bank.
const BANK_WELL_CAPITALIZED := 0.09
const BANK_ORDER := 0.06
const BANK_FAILED := 0.02
## Debt service coverage (yearly profit over yearly loan payments) a
## president wants before saying yes: a bold one 0.75, a cautious one the
## textbook 1.25 or better. Short of that, a borrower can still borrow on the
## equity in its land, up to LTV x (1 - caution) of what the land is worth:
## a bold president lends most of it, a cautious one little (US farms
## average about 13% debt to assets).
const BANK_DSCR := [0.75, 1.3]
## Years to pay off each kind of loan: farmland, a company's pad, a builder's
## loan rolled into a mortgage or commercial mortgage.
const BANK_TERM_YEARS := {"farm": 25, "company": 10, "build": 25, "timber": 15}
## What one loan is for: a field or a pad (its value), or a building.
const BANK_BUILD_VALUE := {ZoneMap.Zone.RESIDENTIAL: 260_000, ZoneMap.Zone.COMMERCIAL: 650_000,
	ZoneMap.Zone.INDUSTRIAL: 1_800_000}
## Chance each lending round that a healthy bank says yes to one more
## purchase for a borrower who qualifies: bold to cautious. So a town with a
## bank grows up to about twice as fast.
const BANK_APPETITE := [0.8, 0.35]
## Each round a builder can get a construction loan for one more house, shop
## or factory on an empty zoned lot, at this chance times the zone's demand.
const BANK_BUILD_CHANCE := 0.6
## Default chance a month: the normal rate, plus this much for every point a
## borrower's coverage falls short of 1 (a farm losing money in a bad price
## year, or a builder with a house nobody wants).
const BANK_DEFAULT_BASE := 0.0003
const BANK_DEFAULT_STRESS := 0.01
## Share of a defaulted loan the bank gets back selling the collateral.
const BANK_RECOVERY := 0.6
## Each employee costs this a year (salary and benefits), and the bank adds
## one for about every this many dollars of loans (FDIC: ~$6M a head).
const BANK_SALARY := 70_000.0
const BANK_LOANS_PER_STAFF := 6_000_000.0
## Other running costs a year, per block of premises.
const BANK_PREMISES_COST := 45_000.0
## Share of each year's profit paid out to shareholders (the rest builds capital).
const BANK_DIVIDEND := 0.35
## Reputation (0 to 1) a new bank starts with, and how much of the gap to
## where its president and premises take it closes each month.
const BANK_START_REPUTATION := 0.35
const BANK_REPUTATION_PULL := 0.03
## Lending rounds run with the farms (every 6 game hours); the books close
## once a game day (a month).
const BANK_LEND_EVERY := 360
const BANK_DECIDE_EVERY := 1440
## Assessed value of a block of bank premises, for commercial property tax.
const BANK_PREMISES_VALUE := 900_000
