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
## The development tree: add-ons a leader builds on its own once it has the
## skill, the money and the surroundings (Brawn 2026-10-22: every hub gets a
## thick tree that depends on the town and its neighbors). `edu` is the
## leader's minimum education, `cost` comes out of the company's savings.
const POWER_UPGRADES := {
	"scrubbers": {"name": "Smokestack scrubbers", "cost": 2_000_000, "edu": 0.3, "plants": ["coal"],
		"needs": "", "about": "Halves the smoke."},
	"repower": {"name": "Switch to gas", "cost": 6_000_000, "edu": 0.45, "plants": ["coal"],
		"needs": "oil", "about": "Turns the coal units into gas engines on the oil field's gas."},
	"battery": {"name": "Battery yard", "cost": 1_500_000, "edu": 0.6, "plants": ["solar", "wind"],
		"needs": "", "about": "Stores power for the evening: each unit covers a quarter more homes."},
	"training": {"name": "Training center", "cost": 800_000, "edu": 0.0, "plants": [],
		"needs": "school", "about": "Trains the next leader: they start better educated."},
	"steam": {"name": "Waste-heat line", "cost": 1_000_000, "edu": 0.35, "plants": ["coal", "gas"],
		"needs": "industry", "about": "Sells steam to factories next door."},
	"blade_yard": {"name": "Wind blade service yard", "cost": 1_200_000, "edu": 0.5, "plants": ["wind"],
		"needs": "turbines", "about": "Services turbines, its own and the region's."},
	"tie_line": {"name": "Line to a neighbor", "cost": 3_000_000, "edu": 0.4, "plants": [],
		"needs": "neighbor_short", "about": "Sells spare power straight to a neighbor that's short, at the town price."},
	"lab": {"name": "Grid research lab", "cost": 2_500_000, "edu": 0.7, "plants": [],
		"needs": "university", "about": "Cuts running costs by a tenth."},
}
## Order the leader considers the tree in.
const POWER_UPGRADE_ORDER := ["training", "scrubbers", "repower", "battery", "steam", "blade_yard", "tie_line", "lab"]
## Steam sales and blade-yard work, dollars a year.
const POWER_STEAM_SALES := 300_000.0
const POWER_BLADE_YARD_SALES := 200_000.0
## Savings a new company starts with (its investors), and the share of
## profit it keeps toward the tree.
const POWER_START_SAVINGS := 500_000.0
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
const TRADE_PRICE := {}
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
