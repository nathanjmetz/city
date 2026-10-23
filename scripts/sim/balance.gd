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
	# Variants, priced by their paved width against the roads above.
	RoadStyle.Type.STREET_NARROW: 180, RoadStyle.Type.STREET_BIKE: 250, RoadStyle.Type.STREET_ONEWAY: 260,
	RoadStyle.Type.MAIN_STREET: 380, RoadStyle.Type.ALLEY: 90, RoadStyle.Type.GRAVEL: 40, RoadStyle.Type.COUNTY: 150,
	RoadStyle.Type.AVENUE_TURN: 320, RoadStyle.Type.AVENUE_BIKE: 520, RoadStyle.Type.AVENUE_DIVIDED: 600,
	RoadStyle.Type.AVENUE_ONEWAY: 420, RoadStyle.Type.STRIP: 600, RoadStyle.Type.PARKWAY: 750,
	RoadStyle.Type.FREEWAY2: 900, RoadStyle.Type.FREEWAY4: 1500, RoadStyle.Type.DIVIDED_HWY: 1100,
	RoadStyle.Type.STATE_HWY: 300, RoadStyle.Type.RAMP2: 950, RoadStyle.Type.AVENUE_BUS: 480,
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
	# The town's share of bringing a cab company in (office, lot and its
	# first two cabs); after that it runs on its own fares.
	"taxi_company": {"cost": 150_000, "upkeep": 0},
	# A 25-bed critical access hospital with an ER, the kind most rural US
	# counties have. Its ambulances answer calls within about 6 road miles.
	# The city's upkeep is its county hospital levy; the hospital earns the
	# rest itself (see HOSPITAL_*).
	"hospital": {"cost": 8_000_000, "upkeep": 70_000, "reach": 9600.0},
	# A 60-bed skilled nursing home, the usual size in small Midwest towns.
	"nursing_home": {"cost": 3_500_000, "upkeep": 15_000, "reach": 4800.0},
	# A licensed daycare center for about 60 children; parents drive up to a
	# mile or so out of their way.
	"daycare": {"cost": 450_000, "upkeep": 4_000, "reach": 1600.0},
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
## Game ticks per real week of construction (see Construction). A real week
## is about 330 ticks on the calendar (a game day settles a month), which
## would leave a house going up for a quarter of an hour; this keeps real
## proportions between stages and kinds, about 11 times quicker than the
## calendar: a house takes about a minute and a half at normal speed.
const BUILD_TICKS_PER_WEEK := 30
## Share of residents who work (US labour force is about half of everyone).
const WORKER_SHARE := 0.5

# --- Building types ----------------------------------------------------------
# Brawn's "bright green" (2026-10-22): each lot's owner picks what to build
# from its surroundings, and each type has its own growth path (see
# scripts/sim/building_types.gd for the types themselves).

## Buildings counted within this many metres tell an owner how built-up and
## pricey the land is (about a two-minute walk).
const CORE_RADIUS := 200.0
## Row homes appear once this many buildings stand within CORE_RADIUS (land
## too dear for a detached house on every lot), apartments from DENSE_CORE.
const ROW_HOME_DENSITY := 30
const DENSE_CORE := 20
## Town size matters as much as the block (Census ACS: Petersburg, IN,
## about 2,300 people, is ~85% detached houses, ~6% small walk-ups and
## almost no row houses; townhouse rows are a metro type). Row homes start
## once the town has ROW_HOME_TOWN people and are fully in favour by
## ROW_HOME_CITY; apartments in a small town are rarer by SMALL_TOWN_FLATS,
## reaching their full share by FLATS_TOWN people.
const ROW_HOME_TOWN := 25_000
const ROW_HOME_CITY := 100_000
const SMALL_TOWN_FLATS := 0.15
const FLATS_TOWN := 25_000
## A street side becomes a Main Street once this many shops line it, and
## new shops there get flats upstairs (the classic Midwestern main street).
const MAIN_STREET_SHOPS := 2
## How often a grown building may move up its growth path (ticks), how long
## it must stand first (ticks; 4320 = three game days, a season), and the chance
## per check that the owner goes ahead.
const DEVELOP_EVERY := 40
const DEVELOP_AGE := 4320
const DEVELOP_CHANCE := 0.35
## Share of owners keen to build on: DEVELOP_KEEN plus DEVELOP_KEEN_WEALTH
## times the neighborhood's wealth (0 to 1), so about half at 0.5.
const DEVELOP_KEEN := 0.25
const DEVELOP_KEEN_WEALTH := 0.6

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
## How each kind spreads, after real operations (Brawn: everything against
## its real version):
## Oil: one producing well pad per spacing unit (Indiana's Illinois Basin
## fields drill on about 10-acre spacing; pads end up 200-400 m apart and
## offset, not on a grid), lease roads back to the tank battery.
const OIL_SPACING_CELLS := 3  # pads at least this many 80 m cells apart
## How far out a company's lease or timber reaches, in 80 m cells.
const LEASE_REACH_CELLS := 12
## Ore: one quarry that widens bench by bench beside its plant, never
## separate holes (Indiana limestone quarries, Iron Range pits).
## Forest: a few harvest units worked at a time inside the woods, each cut
## for a couple of years and then left to regrow (Indiana DNR selective
## harvests run on a 15-20 year cutting cycle). Game years are 12 days.
const FOREST_ACTIVE_UNITS := 6
const FOREST_CUT_DAYS := 24.0
const FOREST_REGROW_DAYS := 180.0

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
## A 69 kV line to the neighbors: wood poles about 300 ft apart (typical
## rural subtransmission spans), set back from the road right of way, with
## a cleared corridor about 50 ft wide (25 ft either side).
const POWER_TIE_SPAN := 90.0
const POWER_TIE_SETBACK := 3.0
const POWER_TIE_CLEAR := 7.5
const POWER_TIE_SAG := 1.5

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
## How a depot weighs a road with a bus lane when it plans routes: buses in
## their own lane run about 20% faster (NACTO Transit Street Design Guide),
## so it routes along those avenues when the detour is small.
const BUS_LANE_ROUTE_COST := 0.8

# --- Taxis --------------------------------------------------------------------
# A small-town cab company (Brawn, 2026-10-22): its owner sizes the fleet to
# ride demand and sets the meter. Rides are the real daily numbers; the cabs
# you see drive real trips.

## Cab rides a day per person, and extra per person in a home without a car
## (US: about 8% of households, more in poorer towns; carless people make
## most taxi trips outside big cities, TCRP Report 75).
const TAXI_TRIPS_PER_PERSON := 0.003
const TAXI_TRIPS_PER_CARLESS := 0.03
const TAXI_CARLESS_POOR := 0.15
const TAXI_CARLESS_RICH := 0.03
## Late-night rides home from bars and restaurants, per shop job.
const TAXI_TRIPS_PER_SHOP_JOB := 0.004
## Rides one cab gives in a day across its shifts (about 20 in smaller US
## cities, Schaller Consulting).
const TAXI_RIDES_PER_CAB := 20.0
## The meter: a flag drop plus a rate a mile (the owner sets the rate within
## these bounds), and the average ride's length.
const TAXI_FLAG := 3.0
const TAXI_RATE_MIN := 2.0
const TAXI_RATE_MAX := 3.25
const TAXI_START_RATE := 2.5
const TAXI_AVG_MILES := 4.0
## How riders respond to the fare (about -0.3, Schaller 1999).
const TAXI_ELASTICITY := -0.3
## Drivers keep about half the meter (commission or lease), and each cab
## costs this much a month in commercial insurance, fuel and repairs; the
## office and dispatcher cost the rest.
const TAXI_DRIVER_SHARE := 0.5
const TAXI_CAB_MONTHLY := 1400
const TAXI_OFFICE_MONTHLY := 4000
## A used sedan or minivan set up as a cab, and what it sells for later.
const TAXI_CAB_PRICE := 22_000
const TAXI_CAB_RESALE := 4_000
## The owner's own money at the start.
const TAXI_START_CASH := 40_000
## Share of the day's rides in each hour, midnight first: a morning bump, a
## steady day, and the late-night run home (Indiana bars close at 3 am).
const TAXI_HOURLY := [5.0, 5.0, 6.0, 3.0, 1.0, 1.5, 3.0, 5.0, 5.0, 4.0, 4.0, 4.0,
	4.5, 4.0, 4.0, 4.5, 5.0, 5.5, 5.0, 4.5, 4.5, 5.0, 5.0, 5.5]

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

# --- Pollution -------------------------------------------------------------------
# Brawn (2026-10-22): pollution must be easier to trace than in Cities:
# Skylines. Every number here is a real-world figure, so a player who looks
# one up finds the same thing.

## Which way the wind blows from, compass degrees. Indiana's prevailing wind
## is from the southwest (NOAA wind roses for Evansville and Indianapolis),
## so smoke drifts northeast.
const WIND_FROM_DEG := 225.0
## What each kind of source puts out:
## - smoke: fine particles (PM2.5) it adds 100 m downwind, in micrograms per
##   cubic metre. EPA's yearly limit is 9 and its daily limit 35.
## - noise: sound level 15 m (50 ft) away in dBA, the FHWA reference
##   distance. For roads it is the level beside a long straight stretch.
## - ground: how dirty it leaves the ground and shallow groundwater right
##   beside it, 0 (clean) to 1 (a cleanup site).
## - reach: how far dirty ground spreads, metres (it also seeps downhill).
## Industry companies emit `pad_share` of this from each well, pit or stand,
## and the full amount at the main yard.
const POLLUTION_SOURCES := {
	# FHWA traffic noise model: a 65 mph highway is 72-80 dBA at 50 ft.
	# Near-road PM2.5 runs 1-2 ug/m3 above background within 150 m.
	"highway": {"smoke": 1.5, "noise": 75.0, "ground": 0.0, "reach": 0.0},
	"ramp": {"smoke": 0.6, "noise": 68.0, "ground": 0.0, "reach": 0.0},
	"boulevard": {"smoke": 0.5, "noise": 70.0, "ground": 0.0, "reach": 0.0},
	# A small plant: stack and loading-dock dust, forklifts and fans, and
	# spills soaking into the yard.
	"factory": {"smoke": 6.0, "noise": 68.0, "ground": 0.3, "reach": 90.0},
	# Factories by the chain they serve (see CitySim.factory_chain), as a
	# multiple of "factory": a refinery's flares and a foundry's furnaces
	# smoke the most, a sawmill is the loudest, a grain mill is mostly dust.
	"factory_chains": {
		"mill": {"smoke": 0.8, "noise": 0.0, "ground": 0.5},
		"sawmill": {"smoke": 0.7, "noise": 6.0, "ground": 0.4},
		"refinery": {"smoke": 2.0, "noise": 2.0, "ground": 2.0},
		"metal": {"smoke": 1.6, "noise": 4.0, "ground": 1.4},
		"general": {"smoke": 1.0, "noise": 0.0, "ground": 1.0},
	},
	# Pump jacks hum about 60 dBA nearby; flaring, and brine spills (the
	# Illinois Basin's real groundwater problem).
	"oil": {"smoke": 4.0, "noise": 62.0, "ground": 0.5, "reach": 140.0, "pad_share": 0.5},
	# Limestone quarry: crusher and blasting noise, rock dust, muddy runoff.
	"ore": {"smoke": 8.0, "noise": 74.0, "ground": 0.35, "reach": 120.0, "pad_share": 0.4},
	# Logging: chainsaws and skidders (about 85 dBA up close), little else.
	"forest": {"smoke": 0.5, "noise": 66.0, "ground": 0.05, "reach": 60.0, "pad_share": 0.6},
	# Landfill: dust and odor, trucks and dozers, and leachate seeping out.
	"landfill": {"smoke": 4.0, "noise": 64.0, "ground": 0.7, "reach": 220.0},
	"recycling_1": {"smoke": 1.0, "noise": 64.0, "ground": 0.1, "reach": 80.0},
	"recycling_2": {"smoke": 0.6, "noise": 62.0, "ground": 0.05, "reach": 60.0},
	"recycling_3": {"smoke": 0.3, "noise": 58.0, "ground": 0.0, "reach": 0.0},
	# Power companies (see Power), per unit. An old coal boiler: stack soot
	# and the ash pond leaching into groundwater (Petersburg Generating
	# Station's real coal-ash problem), belts and fans about 70 dBA. A gas
	# engine hall is loud but burns clean. A wind turbine is about 45 dBA at
	# 300 m (the usual US siting limit); panels and dams are quiet.
	"power_coal": {"smoke": 14.0, "noise": 70.0, "ground": 0.4, "reach": 250.0},
	"power_gas": {"smoke": 1.5, "noise": 72.0, "ground": 0.0, "reach": 0.0},
	"power_wind": {"smoke": 0.0, "noise": 70.0, "ground": 0.0, "reach": 0.0},
	# A freight railroad: a few trains a day average about 65 dBA at 50 ft
	# (FTA noise manual; a line source like a road), plus diesel exhaust.
	"rail": {"smoke": 0.4, "noise": 64.0, "ground": 0.0, "reach": 0.0},
	# The horn at each grade crossing: 96-110 dBA for the long-long-short-long
	# (49 CFR 222.21), averaged over the day it adds about 75 dBA at 50 ft.
	"rail_horn": {"smoke": 0.0, "noise": 76.0, "ground": 0.0, "reach": 0.0},
	# Fertilizer washing off fields: nitrate in wells is a real Indiana issue.
	# Per field cell, so a big farm adds up.
	"farm": {"smoke": 0.0, "noise": 0.0, "ground": 0.03, "reach": 70.0},
}
## Smoke spreads out as it drifts: how wide the plume is at the source, how
## much wider it gets per metre downwind, and the distance over which it
## thins out to a third (EPA screening models).
const SMOKE_WIDTH := 30.0
const SMOKE_SPREAD := 0.22
const SMOKE_FADE_M := 1400.0
## Dirty ground seeps downhill this far, metres, on a 5% slope.
const GROUND_FLOW_M := 160.0

## What pollution does to land value, as a share (-0.006 = 0.6% lower).
## Noise: about 0.6% per decibel over 55 dBA (EPA's healthy-outdoors level),
## the usual figure in US home-price studies. Smoke: about 0.6% per ug/m3
## (hedonic studies of the Clean Air Act). Dirty ground: up to 20% next to a
## contaminated site (brownfield studies). Total is capped.
const NOISE_QUIET_DB := 55.0
const NOISE_VALUE_PER_DB := -0.006
const SMOKE_VALUE_PER_UG := -0.006
const GROUND_VALUE := -0.2
const POLLUTION_VALUE_FLOOR := -0.3
## Homes feel it fully; shops less; factories hardly at all.
const POLLUTION_ZONE_WEIGHT := {ZoneMap.Zone.RESIDENTIAL: 1.0, ZoneMap.Zone.COMMERCIAL: 0.5, ZoneMap.Zone.INDUSTRIAL: 0.15}
## A home counts as hurt by pollution above these levels: FHWA's noise
## abatement level for homes (67 dBA, with a margin), EPA's yearly PM2.5
## limit, and ground dirty enough to test wells.
const HURT_NOISE_DB := 62.0
const HURT_SMOKE := 9.0
const HURT_GROUND := 0.15
## Homes in pollution wear down (stained siding, peeling paint, unkept
## yards): half the gap closes in this many game days, and wear lowers land
## value by up to this share on top.
const WEAR_HALF_LIFE_DAYS := 6.0
const WEAR_VALUE := -0.08

## Cleaner equipment owners can buy, in order. Each level replaces the one
## before it: smoke and ground are multiplied, noise drops by `noise` dB.
const CLEAN_TECH := {
	"factory": [
		{"name": "dust filters", "cost": 150_000, "smoke": 0.5, "noise": 0.0, "ground": 0.8},
		{"name": "scrubbers and sealed floors", "cost": 400_000, "smoke": 0.25, "noise": -3.0, "ground": 0.4},
		{"name": "an enclosed, all-electric plant", "cost": 1_000_000, "smoke": 0.08, "noise": -8.0, "ground": 0.15},
	],
	"oil": [
		{"name": "vapor recovery units", "cost": 200_000, "smoke": 0.4, "noise": 0.0, "ground": 1.0},
		{"name": "lined pits and brine pipelines", "cost": 450_000, "smoke": 0.4, "noise": 0.0, "ground": 0.3},
		{"name": "electric pump motors", "cost": 600_000, "smoke": 0.2, "noise": -8.0, "ground": 0.3},
	],
	"ore": [
		{"name": "water dust sprays", "cost": 120_000, "smoke": 0.5, "noise": 0.0, "ground": 1.0},
		{"name": "settling ponds", "cost": 300_000, "smoke": 0.5, "noise": 0.0, "ground": 0.35},
		{"name": "enclosed crushers and conveyors", "cost": 800_000, "smoke": 0.2, "noise": -10.0, "ground": 0.35},
	],
	"forest": [
		{"name": "quieter, newer machines", "cost": 150_000, "smoke": 0.6, "noise": -6.0, "ground": 1.0},
		{"name": "silt fences on every stand", "cost": 60_000, "smoke": 0.6, "noise": -6.0, "ground": 0.3},
	],
	"farm": [
		{"name": "cover crops", "cost": 30_000, "smoke": 1.0, "noise": 0.0, "ground": 0.6},
		{"name": "grass buffer strips", "cost": 60_000, "smoke": 1.0, "noise": 0.0, "ground": 0.3},
	],
}
## What owners set aside a month toward the next level. A fully educated
## owner (Education.leader_education 1.0) saves the full amount, an
## uneducated one only CLEAN_UNEDUCATED of it; a school nearby makes an owner
## at least CLEAN_SCHOOL_EDUCATION educated. Each home their pollution hurts
## adds CLEAN_COMPLAINT_PER_HOME more (neighbors complain), up to
## CLEAN_COMPLAINT_MAX extra.
const CLEAN_SAVE_PER_MONTH := {"factory": 12_000, "oil": 20_000, "ore": 16_000, "forest": 8_000, "farm": 3_000}
const CLEAN_UNEDUCATED := 0.2
const CLEAN_SCHOOL_EDUCATION := 0.75
const CLEAN_COMPLAINT_PER_HOME := 0.05
const CLEAN_COMPLAINT_MAX := 2.0

## Highway noise walls the city can put up: what the city pays per metre of
## road (a wall costs about $2,500 a metre; federal aid pays 80% of one
## on a federal-aid highway), and how many decibels it takes off (FHWA: a
## wall that breaks the line of sight cuts 5 to 10 dBA).
## Smoke and breathing (EPA: each 10 ug/m3 more fine particles means a few
## percent more respiratory hospital visits; asthma ER visits rise most). As
## gameplay: a home over the smoke line is this much more likely to call an
## ambulance per HURT_SMOKE of smoke, and that share of its calls are
## breathing trouble, counted against the source.
const SMOKE_CALL_WEIGHT := 0.5
const SMOKE_BREATHING_SHARE := 0.5
## A quiet zone (49 CFR 222): the town adds supplementary safety measures
## (four-quadrant gates or raised medians) at every crossing so engineers
## stop sounding the horn. Real cost runs about $30k to $500k a crossing.
const QUIET_ZONE_PER_CROSSING := 250_000
const NOISE_WALL_PER_M := 500
const NOISE_WALL_DB := 8.0

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

## Regional projects: big shared assets no one town owns, each run by its
## board and built in stages that open when the one before is funded (no
## clock). Seeded at real sites near Petersburg, in region metres from the
## map's centre. Goals are in Trade goods ("money" in dollars). Shares
## count every pledge at TRADE_PRICE. Player interaction design owns what a
## finished stage does in each town; these goals are starting numbers for
## the balance thread (a game town starts with START_MONEY).
const REGION_PROJECTS := [
	{"id": "i69", "name": "I-69 extension", "kind": "interstate",
		"board": "I-69 Corridor Authority", "site": [3200.0, 0.0],
		"stages": [
			{"name": "Right of way and grading", "goal": {"money": 4_000_000.0}},
			{"name": "Interchange at the county highway", "goal": {"money": 6_000_000.0}},
			{"name": "Four lanes to the next county", "goal": {"money": 12_000_000.0}},
		]},
	{"id": "power", "name": "Regional generating station", "kind": "power",
		"board": "Pike County Power Cooperative", "site": [-2600.0, 600.0],
		"stages": [
			{"name": "Transmission tie to every town", "goal": {"money": 3_000_000.0}},
			{"name": "Gas turbine unit", "goal": {"money": 9_000_000.0}},
		]},
	{"id": "airport", "name": "International airport", "kind": "airport",
		"board": "Southwest Indiana Airport Authority", "site": [0.0, -9000.0],
		"stages": [
			{"name": "Land and a 7,000 ft runway", "goal": {"money": 8_000_000.0}},
			{"name": "Terminal and air cargo", "goal": {"money": 15_000_000.0}},
			{"name": "International service", "goal": {"money": 25_000_000.0}},
		]},
]

# --- Grow the metro (the long game) ------------------------------------------
# Agreed with Brawn 2026-10-23: the road-linked towns of a region count as
# one metro, ranked against real US metros. Ranks gate regional projects.

## Census (OMB) area types: a micropolitan area has an urban core of 10k to
## 50k people, a metropolitan area 50k or more.
const METRO_MICRO_MIN := 10_000
const METRO_METRO_MIN := 50_000
## Real US areas to pass, smallest first: [name, population]. These are 2020
## Census CBSA totals rounded to the thousand, from memory, so verify them
## before showing them as exact. Southern Indiana and nearby first, since
## the region sits near Petersburg, IN.
const METRO_LADDER := [
	["Connersville, IN", 23_000], ["Greensburg, IN", 26_000], ["North Vernon, IN", 28_000],
	["Wabash, IN", 31_000], ["Madison, IN", 33_000], ["Washington, IN", 33_000],
	["Vincennes, IN", 37_000], ["Logansport, IN", 38_000], ["Crawfordsville, IN", 38_000],
	["Seymour, IN", 45_000], ["Bedford, IN", 45_000], ["Jasper, IN", 56_000],
	["Richmond, IN", 66_000], ["Marion, IN", 66_000], ["Warsaw, IN", 80_000],
	["Columbus, IN", 82_000], ["Kokomo, IN", 84_000], ["Michigan City-La Porte, IN", 112_000],
	["Muncie, IN", 112_000], ["Owensboro, KY", 121_000], ["Bloomington, IN", 161_000],
	["Terre Haute, IN", 185_000], ["Elkhart-Goshen, IN", 207_000],
	["Lafayette-West Lafayette, IN", 223_000], ["Evansville, IN-KY", 315_000],
	["South Bend-Mishawaka, IN-MI", 324_000], ["Fort Wayne, IN", 420_000],
	["Lexington-Fayette, KY", 517_000], ["Louisville/Jefferson County, KY-IN", 1_285_000],
	["Indianapolis-Carmel-Anderson, IN", 2_111_000],
]
## Metro population each regional project needs before its first stage
## opens (later stages still open by funding). Real references: rural
## power co-ops serve micropolitan areas; an interstate link follows a
## metropolitan area; scheduled airline service in the Midwest starts
## around Evansville's size (Bloomington at 161k and Terre Haute at 185k
## have none today).
const REGION_PROJECT_GATES := {"power": METRO_MICRO_MIN, "i69": METRO_METRO_MIN, "airport": 300_000}
## Pacing check: a family region of this many active towns should become
## metropolitan in about a third of the solo hamlet-to-metropolis time
## (STAGE_TARGET_DAYS), and reach the airport gate in about that full time.
const METRO_PACING_TOWNS := 4

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

## A park's development tree (Brawn, 2026-10-22), in the shared Agency
## node format: past the basics above, its park board adds what the park
## can support, from what it already has, its neighborhood, the town and
## the region. Five branches. Each node: `branch`, `name`, `size` (width x
## depth, metres; ZERO for things that run through the whole park), build
## `cost` (a park is public: the board spends town money, keeping
## PARK_TREE_RESERVE in hand), `requires` (built first; basics count),
## `needs` and `effects` (`upkeep+` a month, `value+` and `happy+` added to
## the park's pull). Needs beyond Agency's own (population, link): `tier`
## (lowest neighborhood tier), `water` / `power` (town utilities), `school`
## (a school or high school within that many metres), `forest` (woods next
## to the park, 0 to 1, or a creek).
## Real costs: a splash pad $300-500k; an inclusive playground about $1M; a
## municipal pool $2-4M; a regional aquatic center $8-12M; ball-field
## lights about $300k a field (Indiana park department bids).
const PARK_TREE := [
	{"id": "splash_pad", "branch": "Play", "name": "Splash pad", "size": Vector2(16, 16), "cost": 400_000,
		"requires": ["playground"], "needs": {"tier": 2, "water": 1, "population": 1_000},
		"effects": {"upkeep+": 2_500, "value+": 0.01, "happy+": 0.03}},
	{"id": "all_abilities", "branch": "Play", "name": "All-abilities playground", "size": Vector2(30, 22),
		"cost": 1_000_000, "requires": ["splash_pad"], "needs": {"tier": 3, "population": 3_000},
		"effects": {"upkeep+": 3_000, "value+": 0.02, "happy+": 0.04}},
	{"id": "field_lights", "branch": "Sports", "name": "Field lights", "size": Vector2.ZERO, "cost": 300_000,
		"requires": ["ball_diamond"], "needs": {"power": 1}, "effects": {"upkeep+": 1_500, "happy+": 0.02}},
	{"id": "youth_complex", "branch": "Sports", "name": "Four-field youth complex", "size": Vector2(140, 136),
		"cost": 3_500_000, "requires": ["field_lights"], "needs": {"population": 2_500, "school": 1_600.0},
		"effects": {"upkeep+": 12_000, "value+": 0.02, "happy+": 0.05}},
	{"id": "tournament", "branch": "Sports", "name": "Tournament concessions and parking", "size": Vector2(44, 30),
		"cost": 1_500_000, "requires": ["youth_complex"], "needs": {"population": 5_000, "link": 1},
		"effects": {"upkeep+": 6_000, "happy+": 0.03}, "note": "teams drive in from neighbor towns"},
	{"id": "bandstand", "branch": "Gathering", "name": "Bandstand", "size": Vector2(12, 12), "cost": 200_000,
		"requires": ["pavilion"], "needs": {"tier": 1, "population": 800},
		"effects": {"upkeep+": 800, "value+": 0.01, "happy+": 0.03}},
	{"id": "walking_loop", "branch": "Nature", "name": "Walking loop", "size": Vector2.ZERO, "cost": 120_000,
		"requires": ["paths"], "needs": {"tier": 1}, "effects": {"upkeep+": 500, "value+": 0.01, "happy+": 0.02}},
	{"id": "pond", "branch": "Nature", "name": "Fishing pond", "size": Vector2(44, 30), "cost": 400_000,
		"requires": ["walking_loop"], "needs": {"tier": 1, "population": 1_200},
		"effects": {"upkeep+": 1_500, "value+": 0.02, "happy+": 0.02}},
	{"id": "nature_trail", "branch": "Nature", "name": "Nature trail", "size": Vector2.ZERO, "cost": 150_000,
		"requires": ["walking_loop"], "needs": {"forest": 0.3}, "effects": {"upkeep+": 600, "value+": 0.01, "happy+": 0.02}},
	{"id": "pool", "branch": "Water", "name": "Swimming pool", "size": Vector2(50, 36), "cost": 2_500_000,
		"needs": {"tier": 1, "population": 1_500, "water": 1}, "effects": {"upkeep+": 9_000, "happy+": 0.05}},
	{"id": "aquatic_center", "branch": "Water", "name": "Aquatic center", "size": Vector2(80, 60), "cost": 8_000_000,
		"requires": ["pool"], "needs": {"population": 6_000, "link": 1},
		"effects": {"upkeep+": 25_000, "value+": 0.02, "happy+": 0.06}, "note": "families come from neighbor towns"},
]
## Money a park board leaves in the town's account when it builds from its
## tree, scaled by how cautious its chair is (0.5x to 1.5x). Told to grow,
## it keeps only half.
const PARK_TREE_RESERVE := 500_000

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
	# The county fairgrounds: show barns, an exhibit hall, a grandstand and
	# open ground for the midway, about 40 acres at the start (Indiana
	# county fairgrounds run 30 to 100 acres).
	"fairgrounds": {"cost": 3_000_000, "upkeep": 12_000, "size": Vector2(240, 170),
		"value": 0.02, "value_reach": 500.0, "happy": 0.10, "happy_reach": 2500.0},
	# Businesses that open by themselves for visitors (Tourism): a motel, a
	# diner and a gas station on free road frontage near a venue. They are
	# private, so the town pays nothing for them and gets nothing back when
	# a road takes one.
	"motel": {"cost": 0, "upkeep": 0, "size": Vector2(46, 30), "value": 0.0, "value_reach": 1.0, "happy": 0.0, "happy_reach": 1.0},
	"diner": {"cost": 0, "upkeep": 0, "size": Vector2(26, 30), "value": 0.0, "value_reach": 1.0, "happy": 0.0, "happy_reach": 1.0},
	"gas_station": {"cost": 0, "upkeep": 0, "size": Vector2(40, 36), "value": 0.0, "value_reach": 1.0, "happy": 0.0, "happy_reach": 1.0},
	# A trailhead: a gravel lot for about 20 cars, a map kiosk, a bike rack
	# and a vault toilet, where the town's trails start (typical Indiana
	# rail-trail and greenway trailheads; about $300k to $500k built).
	"trailhead": {"cost": 350_000, "upkeep": 2_500, "size": Vector2(50, 36),
		"value": 0.01, "value_reach": 300.0, "happy": 0.03, "happy_reach": 1500.0},
}
# --- Tourism and events --------------------------------------------------------
# Brawn green-lit (2026-10-22): a fairgrounds hub whose fair board grows it
# and runs a county fair each summer, and the football field as a stadium
# hub for Friday-night football and concerts. Visitors drive in from the
# neighboring towns as real trips, and once enough come, a gas station, a
# diner and a motel open on their own nearby.

## What each venue puts on. `months` (1 to 12) it runs in, the `hours` of
## the day, `local` (share of the town who come) and `region` (share of the
## people in the neighboring towns), and the `ticket` price. `seats` caps a
## single event before the tree adds room. Real figures: an Indiana county
## fair draws 30,000 to 100,000 over a week in a county of 20,000 to 40,000;
## a small-town Friday game 1,000 to 3,000; gate about $5 to $10.
const VENUES := {
	"fairgrounds": {"seats": 15_000, "events": [
		{"name": "County fair", "months": [7], "hours": [9, 23], "local": 0.6, "region": 0.25, "ticket": 8.0}]},
	"football": {"seats": 2_500, "events": [
		{"name": "Friday night football", "months": [9, 10, 11], "hours": [18, 22], "local": 0.15, "region": 0.03,
			"ticket": 6.0}]},
}
## People in the county around a town that has no neighbors yet (solo
## play): Pike County, Indiana has about 12,000.
const TOURISM_COUNTY_POP := 12_000
## What a visitor from out of town spends in town (food, gas, a room), and
## the share the town keeps as its food-and-beverage and innkeeper's taxes
## (Indiana counties levy 1% to 5% each).
const TOURISM_SPEND := 35.0
const TOURISM_LOCAL_TAX := 0.04
## Visitors each car on the road stands for (about 2.5 to a car, and only a
## sample of the cars is driven, to keep the game light), and the most cars
## a venue sends out in an hour.
const TOURISM_VISITORS_PER_CAR := 120
const TOURISM_MAX_CARS_HOUR := 6
## What opens by itself for out-of-town visitors, in order, once a year's
## visitors from outside reach `visitors`: assessed value and jobs.
const TOURISM_BUSINESSES := [
	{"kind": "gas_station", "visitors": 4_000, "value": 900_000, "jobs": 6},
	{"kind": "diner", "visitors": 8_000, "value": 700_000, "jobs": 14},
	{"kind": "motel", "visitors": 15_000, "value": 2_000_000, "jobs": 8},
]
## How far from a venue they open, metres.
const TOURISM_BUSINESS_REACH := 900.0
## Venue development trees, in the Agency format (see agency.gd). The fair
## board or the boosters pay from the venue's own gate money. Effects:
## `draw+` (more come), `seats+` (room), `months+` (an extra event month).
const VENUE_TREES := {
	"fairgrounds": [
		{"id": "show_barns", "name": "4-H show barns", "cost": 400_000, "needs": {"local:farm": 1},
			"effects": {"draw+": 0.1}, "note": "farm kids show their animals"},
		{"id": "grandstand", "name": "Grandstand", "cost": 900_000, "needs": {"population": 1_500},
			"effects": {"seats+": 5_000.0, "draw+": 0.05}},
		{"id": "midway", "name": "Carnival midway contract", "cost": 250_000, "needs": {"link": 1},
			"effects": {"draw+": 0.15}, "note": "a traveling carnival brings rides"},
		{"id": "derby", "name": "Demolition derby pit", "cost": 300_000, "requires": ["grandstand"],
			"needs": {"profit": 60_000}, "effects": {"draw+": 0.1}},
		{"id": "harness", "name": "Harness racing track", "cost": 1_200_000, "requires": ["grandstand"],
			"needs": {"local:farm": 3, "region_makes:grain": 1}, "effects": {"draw+": 0.1, "months+": 1.0},
			"note": "spring races for the farm towns around"},
		{"id": "expo_hall", "name": "Exposition hall", "cost": 2_000_000, "requires": ["show_barns"],
			"needs": {"population": 4_000, "leader_edu": 0.4}, "effects": {"months+": 2.0, "seats+": 3_000.0},
			"note": "shows and auctions all year"},
	],
	"football": [
		{"id": "home_stands", "name": "Home grandstand", "cost": 800_000, "needs": {"population": 2_000},
			"effects": {"seats+": 2_000.0}},
		{"id": "turf", "name": "Artificial turf", "cost": 900_000, "needs": {"profit": 40_000},
			"effects": {"draw+": 0.05}},
		{"id": "track", "name": "Running track", "cost": 600_000, "needs": {"education": 0.3},
			"effects": {"months+": 1.0}, "note": "spring track meets"},
		{"id": "concerts", "name": "Summer concert stage", "cost": 500_000, "requires": ["home_stands"],
			"needs": {"link": 1}, "effects": {"months+": 1.0, "draw+": 0.1}, "note": "bands tour the county"},
		{"id": "playoffs", "name": "Regional playoff host", "cost": 1_500_000, "requires": ["home_stands", "turf"],
			"needs": {"population": 5_000, "link": 1}, "effects": {"draw+": 0.2, "seats+": 2_000.0},
			"note": "teams and fans from towns around"},
	],
}
## Months the tree's extra events fall in, in order: spring then summer.
const VENUE_EXTRA_MONTHS := [5, 6, 8, 4, 10]

# --- Walking and biking ----------------------------------------------------------
# A trailhead hub run by a parks-and-trails director grows the town's trails
# a month at a time: a greenway along the creek, connector trails out to the
# parks, bike lanes on nearby streets (through the permit bell, since they
# restripe the player's streets), and a longer county greenway once there
# is a road out to the region. Built like a 10 ft (3 m) shared-use path
# (AASHTO bike guide), about $1M a mile paved.
const TRAIL_TREE := [
	{"id": "greenway", "name": "Creek greenway", "cost": 600_000, "needs": {},
		"effects": {"length+": 1_600.0}, "note": "a paved path along the creek, about a mile"},
	{"id": "connectors", "name": "Park connector trails", "cost": 400_000, "needs": {"population": 1_000},
		"effects": {}, "note": "paths out to the town's parks"},
	{"id": "bike_lanes", "name": "Bike lanes", "cost": 150_000, "requires": ["greenway"],
		"needs": {"population": 1_500}, "effects": {"lanes+": 8.0}, "note": "restriped streets from the trail into town"},
	{"id": "county_greenway", "name": "County greenway extension", "cost": 1_500_000, "requires": ["greenway"],
		"needs": {"population": 3_000, "link": 1}, "effects": {"length+": 3_400.0},
		"note": "the creek path runs on toward the towns around"},
]
## Width of a trail (10 ft shared-use path) and the strip kept clear for it.
const TRAIL_WIDTH := 3.0
const TRAIL_CLEAR := 6.0
## How far a greenway grows each month, and its step along the bank.
const TRAIL_GROW_MONTH := 400.0
const TRAIL_STEP := 30.0
## How far from the trailhead a creek can be for a greenway.
const TRAIL_CREEK_REACH := 800.0
## Homes near a trail are worth more: about 3 to 5% within a few hundred feet
## in hedonic price studies of US trails. Value and happiness at the path,
## fading to nothing at the reach.
const TRAIL_VALUE := 0.03
const TRAIL_HAPPY := 0.04
const TRAIL_REACH := 200.0
## A trip between two places near the trails or bike lanes, shorter than
## WALK_MAX, goes on foot or by bike this often instead of by car (small
## towns with good trails see 10 to 20% of short trips walked or biked).
const WALK_NEAR := 400.0
const WALK_MAX := 3_000.0
const WALK_SHARE := 0.12
const WALK_SHARE_BIKE := 0.08
## Trail upkeep: about $3k to $5k a mile a year (sweeping, patching, mowing).
const TRAIL_UPKEEP_KM := 250.0

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

# --- Families and their businesses ---------------------------------------------
# Brawn (2026-10-22): every business has a believable name, printed on its
# sign, and a family behind it. A family that does well branches out the way
# real small-town families do (the one with the grain elevator also buys the
# diner and opens the hardware store), under one brand. It may only open on a
# lot the player zoned or buy a business that's already there, each move is a
# permit the player answers, and a family holds a few businesses at most in a
# town. Each new business then follows the normal hub rules (grows next door
# only).

## Most businesses one family may own in a town (real small-town family
## groups hold a handful: the elevator, the implement dealer, a restaurant).
const FAMILY_MAX_HUBS := 4
## Years in business before a family thinks of branching out.
const FAMILY_EXPAND_AFTER := 2
## Chance a month that a family ready to branch out asks, at full ambition.
const FAMILY_EXPAND_CHANCE := 0.25
## What the owners draw a month: a share of a farm's or company's profit,
## and per job at an open shop or factory. A 10-job shop pays its owners
## about $54,000 a year, near the median small-business owner's income (SBA).
const FAMILY_PROFIT_SHARE := 0.3
const FAMILY_PER_JOB := 450
## A new family's savings when it opens its first business.
const FAMILY_START_CASH := 50_000
## Opening a business on an empty zoned lot: a small-town restaurant or
## store costs about $175,000-$750,000 to open; a small plant more.
const FAMILY_START_COST := {"shop": 250_000, "factory": 900_000}
## Buying a going business: small businesses sell for 2-3x what they pay
## their owners (BizBuySell). Farms sell for their land.
const FAMILY_BUY_COST := {"shop": 180_000, "factory": 750_000, "company": 1_200_000}
## A new generation takes over after this many years.
const FAMILY_GENERATION_YEARS := 25
## After this many years a family redoes its look (new signs, modern
## lettering), for about this much.
const FAMILY_REBRAND_YEARS := 20
const FAMILY_REBRAND_COST := 40_000
## Signs read "SINCE 2031" once a business is this many years old.
const FAMILY_SINCE_SHOWN := 10

# --- Healthcare --------------------------------------------------------------
# Brawn's hub-with-a-leader model (2026-10-22): the hospital is run by its
# own administrator, whose schooling follows the town's schools. They grow
# it from a county hospital into a regional medical center through a tree of
# new buildings, each on land right next to what it has.

## Jobs the nursing home and the daycare offer (staff for 60 residents, and
## for 60 children at state ratios).
const NURSING_HOME_JOBS := 60
const DAYCARE_JOBS := 12
## What the hospital keeps each month for every person it serves, after
## paying its staff and supplies: its savings for new buildings. (About 7%
## of the ~$350 a month Americans spend per person on hospital care.)
const HOSPITAL_NET_PER_PERSON := 25.0
## Share of the neighboring towns' people who come here for care, plus this
## much more for each specialty center the hospital has built.
const HOSPITAL_REGION_SHARE := 0.2
const HOSPITAL_REGION_SHARE_PER_CENTER := 0.15
## Without neighbors, the countryside around town: people per region link
## (the county highway's ends) who come in for care.
const HOSPITAL_COUNTY_POP := 1500
## Fixed monthly running costs at each level, which a hospital too big for
## its town can't cover (it then closes its newest building).
const HOSPITAL_OVERHEAD := [0, 40_000, 140_000]
## Names, beds and staff at each level.
const HOSPITAL_LEVELS := [
	{"name": "County Hospital", "beds": 25, "jobs": 150, "floors": 2, "ambulances": 2},
	{"name": "Community Hospital", "beds": 100, "jobs": 450, "floors": 4, "ambulances": 3},
	{"name": "Regional Medical Center", "beds": 300, "jobs": 1200, "floors": 7, "ambulances": 4},
]
## The administrator's down payment before a project: this share of its
## cost, plus up to `CAUTION` more for a careful one (the rest is bonds and
## donors). A well educated one plans for up to `EDU_SAVING` less.
const HOSPITAL_DOWN_PAYMENT := 0.15
const HOSPITAL_DOWN_PAYMENT_CAUTION := 0.35
const HOSPITAL_EDU_SAVING := 0.15
## Buying out the homes or shops in the way costs their assessed value times this.
const HOSPITAL_BUYOUT_PREMIUM := 1.3
## Building up instead of out (when boxed in) costs this much more.
const HOSPITAL_BUILD_UP_COST := 1.25
## Ground a parking garage frees for later buildings, square metres.
const HOSPITAL_GARAGE_FREES := 3000.0
## The administrator weighs a project this often, in ticks (6 game hours).
const HOSPITAL_DECIDE_EVERY := 360
## Game days an administrator serves before retiring (a game day is a
## month: about 10 years).
const HOSPITAL_TENURE_DAYS := 120
## Ambulance calls a year per resident (US EMS: about 0.12), and minutes an
## ambulance crew spends with the patient before heading back.
const EMS_CALLS_PER_PERSON_YEAR := 0.12
const EMS_ON_SCENE_MINUTES := 15
## How much better care lifts the want to live here, at most (people stay,
## and families move in), and what the maternity ward adds to that.
const CARE_DEMAND := 0.15
const CARE_MATERNITY := 0.04
## The development tree, in the shared Agency format (scripts/sim/agency.gd).
## Hospital extras: `tier` is the hospital level it needs; `area` the new
## land it takes in square metres (0 builds on what it has); `height` in
## metres; `level` raises the hospital. Needs beyond Agency's own
## (education = homes near a school, leader_edu = the administrator's):
## pop (people its ambulances reach), catchment (those plus the region's),
## region_pop (people in neighboring towns), daycare / nursing_home (one in
## town), boxed (out of land). Effects: jobs+, ambulances+, staffing+
## (share of jobs locals fill), education+ (town education), region_care+
## (care it adds in neighboring towns), center+ (a specialty center that
## draws patients from the region).
const HOSPITAL_TREE := [
	{"id": "er", "name": "ER and ambulance bay", "tier": 0, "cost": 2_000_000, "area": 1200.0, "height": 5.0,
		"needs": {"pop": 800}, "effects": {"jobs+": 30, "ambulances+": 2}, "note": "more ambulances, faster"},
	{"id": "offices", "name": "Medical office building", "tier": 0, "cost": 3_000_000, "area": 1500.0, "height": 10.0,
		"needs": {"pop": 1500, "leader_edu": 0.3}, "effects": {"jobs+": 60}, "note": "doctors' offices next door"},
	{"id": "maternity", "name": "Maternity ward", "tier": 0, "cost": 2_500_000, "area": 1000.0, "height": 5.0,
		"needs": {"pop": 1200, "daycare": 1}, "effects": {"jobs+": 40}, "note": "young families move in"},
	{"id": "community", "name": "Community hospital tower", "tier": 0, "level": 1, "cost": 15_000_000, "area": 2500.0,
		"height": 16.0, "requires": ["er"], "needs": {"pop": 3000}, "effects": {}, "note": "100 beds"},
	{"id": "surgery", "name": "Outpatient surgery center", "tier": 1, "cost": 6_000_000, "area": 1800.0, "height": 6.0,
		"needs": {"pop": 3500}, "effects": {"jobs+": 80, "center+": 1}},
	{"id": "rehab", "name": "Rehab and therapy center", "tier": 1, "cost": 4_000_000, "area": 1500.0, "height": 5.0,
		"needs": {"nursing_home": 1}, "effects": {"jobs+": 50}, "note": "with the nursing home"},
	{"id": "nursing_school", "name": "Nursing school", "tier": 1, "cost": 7_000_000, "area": 2000.0, "height": 10.0,
		"needs": {"education": 0.5}, "effects": {"jobs+": 40, "staffing+": 0.15, "education+": 0.1},
		"note": "trains the town's own nurses"},
	{"id": "helipad", "name": "Helipad", "tier": 1, "cost": 2_000_000, "area": 900.0, "height": 0.0,
		"needs": {"region_pop": 3000}, "effects": {"jobs+": 12, "region_care+": 0.1},
		"note": "flies in patients from neighboring towns"},
	{"id": "garage", "name": "Parking garage", "tier": 1, "cost": 5_000_000, "area": 0.0, "height": 12.0,
		"needs": {"boxed": 1}, "effects": {"jobs+": 4}, "note": "frees the front lot for building"},
	{"id": "regional", "name": "Regional medical center tower", "tier": 1, "level": 2, "cost": 45_000_000, "area": 4000.0,
		"height": 30.0, "requires": ["surgery"], "needs": {"pop": 8000, "catchment": 15000}, "effects": {},
		"note": "300 beds"},
	{"id": "heart", "name": "Heart center", "tier": 2, "cost": 18_000_000, "area": 2500.0, "height": 12.0,
		"needs": {"pop": 8000}, "effects": {"jobs+": 150, "center+": 1, "region_care+": 0.05}},
	{"id": "cancer", "name": "Cancer center", "tier": 2, "cost": 25_000_000, "area": 3000.0, "height": 12.0,
		"needs": {"leader_edu": 0.6, "catchment": 20000}, "effects": {"jobs+": 200, "center+": 1, "region_care+": 0.1}},
	{"id": "teaching", "name": "Teaching hospital", "tier": 2, "cost": 40_000_000, "area": 4000.0, "height": 18.0,
		"requires": ["nursing_school"], "needs": {"leader_edu": 0.75, "catchment": 30000},
		"effects": {"jobs+": 400, "center+": 1, "staffing+": 0.1, "education+": 0.15, "region_care+": 0.05},
		"note": "trains doctors"},
]

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

# --- Phone, cell and internet ---------------------------------------------------
# Brawn greened it (2026-10-22, Best of CS #17): a local phone company the
# player places once. Its general manager runs it like a real rural
# telephone co-op trying to stay in business: fiber goes down the streets
# that pay back first (the densest), cell towers go up where too many
# households get one bar or none (each tower is a zoning request on the
# permit bell, as at a real county board of zoning appeals), and the
# office grows only into the land right next to it. Coverage draws people,
# remote workers and offices, and fiber lifts home values. Rural edges stay
# spotty unless the town pays to reach them. Benchmark: CS2's telecom
# (network quality drives offices) and real Indiana co-ops.

## The central office (the exchange building with its switch and fiber
## hut): what the player pays, and the city's standard monthly broadband
## grant (the player can set it from half to one and a half times, like
## Indiana's Next Level Connections grants).
const TELECOM_COST := 2_500_000
const TELECOM_GRANT := 15_000
const TELECOM_FUNDING_LEVELS := [0.5, 0.75, 1.0, 1.25, 1.5]
## People per household (US Census: 2.5).
const TELECOM_PEOPLE_PER_HOUSEHOLD := 2.5
## Fiber: build cost per metre of street (aerial on existing poles runs
## about $60,000 a mile), the drop to each home that signs up, upkeep per
## metre a year (about $1,000 a route mile), and what one crew strings in a
## month (a real aerial crew does about a kilometre a week).
const TELECOM_FIBER_PER_M := 38.0
const TELECOM_FIBER_DROP := 900.0
const TELECOM_FIBER_UPKEEP_M := 0.6
const TELECOM_FIBER_M_PER_CREW := 4_000.0
## Share of households passed that sign up for fiber (US average about 40%
## a few years in), and of businesses on a fiber street.
const TELECOM_FIBER_TAKE := 0.4
const TELECOM_BUSINESS_TAKE := 0.6
## A month's bill: home fiber (rural Indiana co-ops charge about $70),
## business fiber, fixed wireless home internet, and cell service per
## household on this carrier (about 2.5 lines at $50, with a third of the
## market against the national carriers).
const TELECOM_FIBER_ARPU := 70.0
const TELECOM_BUSINESS_ARPU := 150.0
const TELECOM_FIXED_ARPU := 55.0
const TELECOM_FIXED_TAKE := 0.25
const TELECOM_WIRELESS_ARPU := 40.0
## Running a tower a month: ground lease (about $1,500), power, backhaul
## and maintenance.
const TELECOM_TOWER_MONTH := 2_700.0
## The office's own overhead a month, before the land it grows into.
const TELECOM_OVERHEAD := 12_000.0
## How many years ahead a manager plans: TELECOM_HORIZON years plus up to
## TELECOM_HORIZON_EDU more for a well-schooled one. A build goes ahead when
## it pays back within that horizon.
const TELECOM_HORIZON := 4.0
const TELECOM_HORIZON_EDU := 8.0
## Most the company will owe (a rural utility loan) before it stops building.
const TELECOM_MAX_DEBT := 2_500_000.0
## A tower's site: the fenced compound's side, how near a road it must be
## for its gravel drive, and the least spacing between towers.
const TELECOM_COMPOUND := 24.0
const TELECOM_TOWER_ROAD := 90.0
const TELECOM_TOWER_SPACING := 900.0
## A household counts as poorly served below this signal (one bar).
const TELECOM_GOOD_SIGNAL := 0.55
## Share of workers who work from home when the house has fiber (about one
## in eight US workers is fully remote), or only good cell service.
const TELECOM_REMOTE_SHARE := 0.12
const TELECOM_REMOTE_CELL := 0.03
## Property value lift: about 3.1% for a home with fiber (FTTH Council /
## Molnar study), and up to 1% for a full cell signal.
const TELECOM_FIBER_LIFT := 0.031
const TELECOM_CELL_LIFT := 0.01
## Good coverage raises demand: for homes (people pick towns with good
## internet) and for shops and offices on fiber streets.
const TELECOM_HOME_DEMAND := 0.08
const TELECOM_OFFICE_DEMAND := 0.12
## Assessed value per tower and per metre of fiber, for property tax.
const TELECOM_TOWER_VALUE := 250_000
const TELECOM_FIBER_VALUE_M := 20.0
## Each block of land next to the office: what buying and building on it
## costs, and the most it will ever own.
const TELECOM_BLOCK_COST := 450_000
const TELECOM_MAX_BLOCKS := 8
## The company decides once a game day (a month).
const TELECOM_DECIDE_EVERY := 1440
# --- Rail -----------------------------------------------------------------------
# Brawn's model (2026-10-22): a rail depot is a hub whose leader runs it as a
# business on its own money. The town only places it and can subsidize it.

## What the town pays to place a depot (the land, station and yard grading).
const RAIL_DEPOT_COST := 400_000
## Money the railroad's investors put in when it opens.
const RAIL_START_CAPITAL := 6_000_000
## New track, dollars per metre: about $1M a mile for industry track and
## $1.5M a mile for main line (US short-line construction costs).
const RAIL_TRACK_PER_M := {"main": 930, "spur": 620}
## Share of new track that state and federal rail grants pay (Indiana's
## Industrial Rail Service Fund, federal CRISI grants), as public money pays
## for most new roads. The railroad pays the rest.
const RAIL_GRANT_SHARE := 0.75
## A turnout where a spur leaves the main line (a #10 turnout, installed).
const RAIL_TURNOUT_COST := 150_000
## A grade crossing's lights, bells and gates, about $300,000 (FHWA).
const RAIL_CROSSING_COST := 300_000
## Track upkeep, dollars per metre per month (about $20,000 a mile a year).
const RAIL_TRACK_UPKEEP_PER_M := 1.0
## The depot's crew, dispatcher and office, per month, and its jobs.
const RAIL_DEPOT_UPKEEP := 9_000
const RAIL_DEPOT_JOBS := 12
## What the railroad earns for each loaded car it hands to the region
## (US average revenue is about $3,500 a carload, AAR).
const RAIL_CAR_RATE := 3_500
## Truck loads that fill one rail car: a tank car holds about 3.5 tanker
## trucks of crude, an open hopper five dump trucks of ore, a bulkhead flat
## three log trucks, a covered hopper about 3,400 bushels of grain.
const RAIL_LOADS_PER_CAR := {"crude oil": 3.5, "ore": 5.0, "logs": 3.0, "grain": 3.4}
## Grain truck loads the co-op elevator holds for the railroad.
const RAIL_ELEVATOR_LOADS := 60
## Running a train, dollars per train-km (fuel), plus the crew for each run.
const RAIL_TRAIN_KM_COST := 60.0
const RAIL_CREW_PER_RUN := 900.0
## Passenger trains: rides each resident takes a month, the fare, the town
## size a leader starts them at, the trainset's lease and how often one runs.
const RAIL_RIDES_PER_RESIDENT := 0.3
const RAIL_FARE := 12
const RAIL_PASSENGER_MIN_POP := 800
const RAIL_TRAINSET_LEASE := 6_000
const RAIL_PAX_EVERY_HOURS := 6
## Game days a train spends in the region before it comes back.
const RAIL_REGION_DAYS := 0.4
const RAIL_PAX_AWAY_DAYS := 0.25
## A local freight leaves once this many cars wait at a siding, or once the
## first has waited this many game days.
const RAIL_TRAIN_MIN_CARS := 3
const RAIL_TRAIN_MAX_WAIT_DAYS := 2.0
## Metres of track a crew lays in a game day.
const RAIL_BUILD_M_PER_DAY := 600.0
## Leaders decide this often, in ticks (6 game hours).
const RAIL_DECIDE_EVERY := 360
## Years a leader waits for new track to pay off: a bold one, a modest one.
## Track lasts 40 years or more, so railroads accept long paybacks.
const RAIL_PAYBACK_YEARS := [25.0, 10.0]
## Share of a spur's cost the company it serves pays (in the US the shipper
## usually pays for its industry track; the railroad pays the rest).
const RAIL_SHIPPER_SHARE := 0.5
## Money a leader keeps in hand (scaled by caution).
const RAIL_CUSHION := 500_000.0
## Game days before a leader asks again about something the town turned
## down or never answered (the permit bell has its own waits too).
const RAIL_DENIED_DAYS := 24
## Game days in the red before a railroad closes.
const RAIL_BANKRUPT_DAYS := 6
## Most the town can subsidize a depot, per month.
const RAIL_MAX_SUBSIDY := 100_000
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

# --- Town policy sliders --------------------------------------------------------
# Brawn's rule (2026-10-22): money is a limiter, not the game. No tax sliders:
# taxes run at the normal rates above on their own. Instead every area and hub
# has two broad sliders, Funding (Lean to Generous) and Growth (Hold to
# Expand), five steps each, with Standard and "Your call" in the middle.
# Each list below has one value per step, Lean/Hold first.

## City-run things (utilities, public services, waste, cemetery): what they
## cost a month, times their upkeep...
const POLICY_UPKEEP := [0.7, 0.85, 1.0, 1.2, 1.4]
## ...and how far they reach, how much they serve and how many trucks they
## run. A lean department stretches thin; a generous one has slack.
const POLICY_EFFECT := [0.8, 0.9, 1.0, 1.1, 1.2]
## Homes, shops and factories: what the town spends on each building a month
## for street care, trees and inspections (negative: it saves that much)...
const POLICY_CARE_PER_BUILDING := [-12, -6, 0, 15, 30]
## ...and what that does to land value, and so to property tax.
const POLICY_LAND_VALUE := [0.94, 0.97, 1.0, 1.03, 1.05]
## Farms and resource companies are private. Funding is town support per acre
## a year: a fee the town charges on Lean, aid it pays on Generous (real
## counties do both: special assessments and ag or enterprise incentives).
const POLICY_SUPPORT_PER_ACRE := [-20.0, -8.0, 0.0, 15.0, 30.0]
## Growth for homes, shops and factories: how readily new buildings go up
## (times demand). Hold stops new ones; what's built stays.
const POLICY_BUILD_PACE := [0.0, 0.5, 1.0, 1.35, 1.7]
## Growth for farms and companies: the yearly profit, per acre, a new field or
## pad must clear before they buy it. Hold buys nothing; Expand takes thinner
## land. They still sell what keeps losing money.
const POLICY_BUY_MARGIN_PER_ACRE := [INF, 40.0, 0.0, -10.0, -20.0]
## Growth for waste sites: the share of trash left waiting that makes them
## take more land (HUB_GROW_BUSY_SHARE on "Your call")...
const POLICY_HUB_BUSY := [INF, 0.7, 0.5, 0.4, 0.3]
## ...and for the cemetery, times how much land it plans per resident.
const POLICY_CEMETERY_PACE := [0.0, 0.7, 1.0, 1.3, 1.6]
## Resource companies work in pads (80 m, about 1.6 acres) that earn far more
## than a field, so their support and buying margin are per pad a year.
const POLICY_SUPPORT_PER_PAD := [-4_000.0, -1_500.0, 0.0, 3_000.0, 6_000.0]
const POLICY_BUY_MARGIN_PER_PAD := [INF, 8_000.0, 0.0, -2_000.0, -4_000.0]
## Growth for parks: times how many people must live nearby before a park
## buys the strip next door (PARK_GROW_MIN_RESIDENTS). Hold buys none.
const POLICY_PARK_RESIDENTS := [INF, 2.0, 1.0, 0.7, 0.5]
## Hubs with their own money lever take it from their Funding step (Lean ..
## Generous): the water utility's monthly subsidy (Standard is where a new
## utility starts), and the post office's MAIL_FUNDING level (Standard is
## Basic). A bus depot's subsidy is BUS_FUNDING_LEVELS at the same step.
const POLICY_WATER_SUBSIDY := [0, 2_500, 5_000, 12_000, 25_000]
const POLICY_MAIL_FUNDING := [0, 0, 1, 2, 3]

# --- Growth pacing targets ---------------------------------------------------
# Metro scale plan (2026-10-23, approved direction): how long a steady player
# should take to reach each size, in game days at 1x (a day is about 2.5
# real minutes; fast-forward compresses these). Benchmarked on CS1/CS2
# player hours. The balance harness checks pacing against these; the early
# curve runs faster today and gets slowed once stage gates land.
const STAGE_TARGET_DAYS := {
	100: 8,       # Village, ~20 min
	500: 24,      # Town, ~1 h
	2000: 72,     # Large town, ~3 h
	8000: 144,    # Small city, ~6 h
	25000: 288,   # City, ~12 h
	80000: 660,   # Metropolis, ~25-30 h
	150000: 960,  # Manhattan-style core, 40 h and up
}
## How far from a target the harness tolerates before flagging it (0.5 =
## anywhere from half to one and a half times the target).
const STAGE_TARGET_SLACK := 0.5


# --- Town culture ------------------------------------------------------------
# Brawn's core idea (2026-10-22): a town's character drifts with its work and
# tilts which hubs thrive. Measured as location quotients (TownCulture).

## A town needs this many jobs before it has a character of its own.
const CULTURE_MIN_JOBS := 40
## How slowly culture follows the jobs: half the gap closes in this many game
## days (a game day is a month, so three years; a town's reputation for a
## trade outlasts the trade by years).
const CULTURE_HALF_LIFE_DAYS := 36.0
## The location quotient economic developers count as a specialisation.
const CULTURE_SPECIALISED_LQ := 1.25
## A known identity holds until another sector beats it by this much LQ.
const CULTURE_HOLD_LQ := 0.5
## The LQ where a sector's pull (or, at its inverse, its drag) is full.
const CULTURE_FULL_PULL_LQ := 4.0
## How much thinner a margin a town's own trade will buy land on, at full
## pull, a year: about a quarter of a growth-slider step (Balance POLICY_*).
const CULTURE_MARGIN_PER_ACRE := 5.0
const CULTURE_MARGIN_PER_PAD := 1_000.0
## A developer asks to rezone farm ground for a trade when its pull plus
## how fast it is rising passes this...
const CULTURE_DEVELOP_SCORE := 0.25
## ...and builders want that zone (its demand, 0 to 1)...
const CULTURE_DEVELOP_DEMAND := 0.6
## ...and fewer than this many zoned lots for it stand empty.
const CULTURE_DEVELOP_FREE_LOTS := 3
## What a developer pays for Indiana farm ground, $ per square metre (about
## $11,000 an acre, Purdue Farmland Value Survey 2023, before rezoning).
const CULTURE_FARMLAND_PER_M2 := 3
## How far back from the road a rezoning reaches (one deep commercial or
## industrial lot, metres) and the least road frontage worth asking for.
const CULTURE_FRONTAGE_DEPTH := 60.0
const CULTURE_FRONTAGE_MIN := 80.0
## How long (game days; a day is a month) the advisor mentions that the town
## has a new reputation (TownCulture identity).
const CULTURE_NEWS_DAYS := 12
