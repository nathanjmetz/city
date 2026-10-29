# Road treatments and the bigger road menu: spec (2026-10-29)

**Purpose (one sentence Nathan would say aloud):** A street dresses for what's built on it, so a factory street gets tough and plain and a main street gets wide walks and lanterns, and I can pick from a whole screen of real road types.

**Nathan's words (2026-10-29):** "I would love it if we had lots of different kinds of roads with all kinds of different functions and features... it might be better in our game if we instead had road treatments. If you build a road and then put factories on it then the factory treatment might get applied to the road... you'll have to figure out how to treat spaces where there are different things on either side of the road." Asked whether a treatment changes only looks or also a few rules, he picked **A: looks plus a few real rules, shown in numbers.**

**Who uses it:** every player, every time something gets built along a road. The catalog, every time they draw one.
**The one main thing:** each side of a street changes to fit what's built along it.

A **treatment** is the curb, sidewalk, trees, lights, wires and parking a street side gets from what fronts it. It never changes the road's width, lanes or lots: it only re-cuts the 3.6 m each side already has behind the curb line (curb, grass strip, walk in `RoadStyle.right_of_way_half`).

## Part 1: treatments

### The kinds (each side; the "middle" is the shared pavement)

| Kind | Real basis | Each side gets | Middle gets |
|---|---|---|---|
| **Factory** | GM's Marion stamping plant on the west side; the warehouses by the I-69 exits | Plain curb, narrow concrete walk, mowed grass and no trees, **no parking** (MUTCD R7-1 signs), wide 40 ft truck drives, cobra-head lights on tall wood poles, overhead wires | Jointed concrete (heavy, lasts longer), double yellow, the big truck corner at junctions |
| **Main street** | Marion's courthouse square; Gas City's Main Street | Walk paved from curb to storefront (the grass strip becomes paving with brick bands), trees in iron grates, **parking with painted stalls, no driveway cuts** (shops use the alley), black acorn lanterns, wires buried, benches, bins, bike racks | Asphalt with brick crosswalk bands, ladder crosswalks |
| **Strip shops** | The gas stations and drive-throughs at the I-69 exits and along the state highways | Walk at the curb, mowed strip, few trees, **no curb parking** (customers use the front lots), a wide drive per lot, steel davit lights, wires on tall poles, a bus bench | Heavy asphalt, keeps its turn lane if it has one |
| **Wealthy homes** | Indianapolis's Meridian-Kessler; Carmel's newer streets | A full row of matching shade trees every 35 ft, wide grass strip, concrete or brick walk, parking allowed, one narrow drive per house, black post-top lanterns, **wires buried** | Smooth fresh asphalt, no center line on 2-lane streets |
| **Ordinary homes** | Most Marion and Gas City blocks (today's look) | Curb and gutter, grass strip, the odd street tree, concrete walk, parking, one drive per house, cobra-head on a wood pole, overhead wires | Asphalt |
| **Struggling** | Older Marion blocks that lost jobs when the big plants closed | What cheap fixes look like: walk slabs patched with asphalt, stumps where trees came down, a parking pad cut into the grass strip, same lights and wires | Asphalt with overlay patches |
| **Farm** | Grant County's numbered county roads through corn and beans | No curb, gravel shoulder and ditch, field entrances over culvert pipes, mailboxes on posts, no lights except at crossroads, wires on wood poles (`PoleLine`) | Chip seal or asphalt with edge lines (the road type decides) |
| **School or campus** | Indiana Wesleyan's frontage on South Washington Street | Wide 8 ft walk for groups, trees, lanterns, bike racks, a **buses-only curb** at the door, school zone signs with flashers (MUTCD S5-1) | Ladder crosswalks, "SCHOOL" painted in the lane |
| **Hospital** | Marion General Hospital | **No parking**; an ambulance-only curb at the entrance, wide drives, tall lights, blue "H" signs (MUTCD D9-2) | Heavy asphalt, ladder crosswalks |

Highways, ramps and alleys face no lots, so get none. A side with too little built keeps today's look. Junction looks (PR #931) read the treatment at each corner: big truck corners on factory streets, ladder crosswalks downtown and at schools.

### The few real rules

| Rule | Who gets it | What the sim does (`TrafficSim`) | Expected direction |
|---|---|---|---|
| **Truck route** | The middle, when either side is Factory | Counts as a truck route under the Truck routes law (no extra time for through trucks there, even on a Street) | Deliveries up, trucks off home streets, a little more noise for homes facing it |
| **Parking off** | Factory, strip, hospital sides; a school side in school hours | That side has no curb to park on (`_curb_line` returns nothing); drivers use lots and walk | Traffic flows a little better; a few more walking minutes |
| **More parking** | Main street sides | No driveway cuts, so more curb stalls fit (`_new_curb` skips aprons) | More shoppers find a space near the door; fewer give up downtown |
| **Slower** | Main street: 20 mph on streets, 25 on avenues. School zone: 20 mph at arrival and dismissal | Lower speed limit on that piece (`TrafficSim.limit`) | Through trips move to parallel streets; trips there take a bit longer |
| **Tougher pavement** | Factory (concrete), strip and hospital (heavy asphalt) | Repaving costs more but comes due later (`StreetAge`) | Bigger, rarer repave bills on the Economy page |

Clicking a road shows it plainly: "Left: Factory · Right: Strip shops · Truck route · No parking on the left · 25 mph."

**Measure it** as PR #931 did: one game day of PerfTown small (36,968 ticks, headless), before and after: trips, flow, deliveries, shopping arrivals, gave up, money gained. Deliveries should rise with factory streets, shopping arrivals with main streets. If money moves more than 3%, stop and look.

### How a side picks its kind

1. **Count frontage.** For each road piece (junction to junction, a block in town) and side, add up built lots' frontage by kind (lots know `lot.seg` and `lot.side`). Corner lots count on both streets. Step 1 judges whole pieces; long country pieces get 100 m stretches in step 3.
2. **What counts as what.** Industrial lots, warehouses and big factories are Factory. Shops, flats over shops and commercial blocks are Main street when the block already counts as a main street or downtown (`BuildingTypes`: 2 or more shops on the block face, or downtown density); otherwise Strip shops. Homes are Wealthy, Ordinary or Struggling by the neighborhood tier there (Thriving, Working class or Comfortable, Struggling), which already moves slowly. Schools, campuses and hospitals are their own. Farms are Farm.
3. **Most frontage wins, if it's enough.** The biggest kind takes the side only if it covers at least **40%** of the side's length. Empty lots count as length but not as a kind. One gas station on a 120 m block of homes is about 17%, so nothing flips.
4. **Ties** keep what the side has now; otherwise the heavier use wins (the order below).
5. **No flicker.** A side keeps its kind until another beats it by **15 points** of the side's length, and changes at most once a game month.
6. **Fixtures outlast the money.** A new kind arrives right away when a building is built (real towns make the builder redo the frontage with the site plan). When a business closes or a neighborhood slides, the lanterns and brick walks stay and wear. A side drops to a lighter kind only after a game year, or when the road is redrawn.
7. **The player can lock or pick.** Click a road side: "Auto" (the default), or any kind. A locked side never changes on its own.

### The middle, when the sides differ

The middle follows the **heavier use**: Factory, then Strip shops, then Hospital or School, then Main street, then Farm, then homes. Factories on one side and shops on the other give a concrete truck route; the shop side still gets its own walk, lights and (if Main street) parking. Speed is the **lower** of the two sides' limits. Parking is always per side. The middle gets heavier at once, and lighter only when the street is next repaved.

### Ties to the state layer (street condition)

The treatment is what a street was **built as**; condition (state layer step 2, `street_state.gd`) is **how it's kept**. A Wealthy side in run-down condition shows cracked brick walks, a lantern out and a shaggy grass strip, but stays a wealthy street until the fixtures are replaced. The treatment picks what's there; condition picks the wear.

### Saves

The look and rules are **worked out** from the buildings. Two small things are **stored**, since every copy must agree and a reload must not flip a side: each side's current kind (and when it changed) and the player's locks. They go in a new item in the `.city` file (like car-free closures), not on the road's saved line, so old towns load as before and work it out fresh. A cut road piece passes its treatment to both halves (the `split` signal). A test loads an old town.

### Cost

- **Sim:** a side is re-checked only when a building on it is built, removed, upgraded or changes care tier. That is a sum over 5 to 10 lots. Budget: under 0.02 ms per tick on average, 2 ms at most (a neighbor's whole town arriving).
- **Drawing:** the road mesh already lays every strip as a left part and a right part (`RoadMesh._town`), so a per-side look is new numbers in the same mesh, and only that one road piece is redrawn. New looks (concrete, brick bands, patched walks) ride on the **existing** pavement and walk materials, not new ones, because a new material is one more draw call for every road piece that uses it. Lanterns are new kinds in `StreetLights` (one MultiMesh each). Benches, grates, mailboxes and culverts sit in the state layer's near ring: within 150 m of the camera, desktop High and up.
- **Budget, measured with `tools/look_round.gd`, Cinematic, shots 01 to 03:** at most +10 draw calls, +60,000 triangles, +0.3 ms draw time. Zoomed out to 300 m: no change. The browser gets the pavement and walk changes (free) but none of the props.

## Part 2: the bigger road menu

### How many types can link

Every road is the same parts: 3.6 m lanes, a median or turn lane, parking, bike and bus lanes, shoulders, a surface, sidewalks. A new type is one more row in `RoadStyle.TYPES` (added at the end; saves store the type by number). At a junction any type joins any other: lanes take turns by their arrows (lefts keep left, rights keep right, straight lines up from the right: `TrafficSim._out_lane`), and the bigger road shapes the corner. The weak spot is a **change mid-road**: a 4-lane avenue running on as a 2-lane street just stops at the node today (`RoadView._end_to_end`), a step in the curb. Fix: a taper like the ramps' (`RampMerge`), MUTCD length L = W x S² / 60 under 45 mph (about 75 m at 35 mph).

### What's already done from the chart

Since the 2026-10-26 chart, the large one-way (One-way boulevard), car-free streets (#919), S-curves (#917) and snap switches (#918) are built. The menu has 30 types.

### New types to add first

| # | Type | Real basis | Saves change? |
|---|---|---|---|
| 1 | Avenue with parking (4 lanes, parking both sides) | Old downtown four-lane streets | No |
| 2 | Concrete street | Indiana's 1950s to 70s subdivisions and industrial parks | No |
| 3 | Gravel alley | Older Marion and Gas City blocks | No |
| 4 | Seven-lane strip (3 each way and a turn lane) | The biggest suburban strips in Indianapolis and Fort Wayne | No |
| 5 | Three-lane state highway (turn lane, shoulders) | Indiana state roads where they near a town | No |
| 6 | Street and avenue with protected bike lanes (curb or posts) | Indianapolis's downtown protected lanes | No |
| 7 | Cul-de-sac end (a 96 ft round turnaround) | Every postwar subdivision; the fire code size (IFC D103.4) | No (a dead-end option) |
| 8 | Mid-road taper (see above) | MUTCD lane reduction | No |
| 9 | Trees on any road (none, some, a full row) | Any street a town replanted | Yes |
| 10 | Wider sidewalk on any road | Downtown and campus walks | Yes |
| 11 | Sound wall along a road | I-465 around Indianapolis | Yes |
| 12 | Trail you draw (10 to 12 ft, walkers and bikes) | The Cardinal Greenway, a rail-trail into Marion | Yes (new paths) |
| 13 | Hill wall and riverfront wall | A road cut into a slope; a riverwalk along the Mississinewa | Yes |

Items 9 to 13 change saves, so they go the chart's safe way (a new item; a test loads an old town). Trams stay later.

### "A whole screen of roads" without a mess

- **Keep the bottom bar** for the five road menus and the kinds last used (the 1000 px limit in `tests/test_build_menus.gd` stays).
- **Add an "All roads" card** that opens a big catalog over the map.
- **Left: categories.** Streets, Avenues, Big roads, Highways and ramps, Country, Paths and trails, Add-ons (trees, walls, wider walks).
- **Middle: a picture card per road.** A drawn cross-section (lanes, parking, trees, walk) from the road's own numbers, the way `Icon._road_type` already draws road icons, so no image files. Under it: name, lanes, mph, cost per 100 m.
- **Top: filters and search.** Chips for lanes (1-2, 3-4, 5+), one-way, parking, bike, bus, trees, trucks OK, country. The search box the HUD already has.

### What costs speed and what doesn't

- **Free:** more types. A type costs nothing until it's drawn.
- **Draw calls:** a new **material** costs one per road piece using it, so new types reuse today's materials.
- **Triangles:** walls, trees and posts, drawn as MultiMesh or merged per 128 m square.
- **Sim time:** trails (a walker and bike network to route on).
- **To measure:** catalog opens in under 50 ms first time, 5 ms after; redrawing a 1.2 km grid within 5% of today; +0 draw calls for new types without walls or trees; trail routing under 0.05 ms per tick.

## Build order (each step a few hours for one builder)

1. **Factory and main street, per side (most visible).** `scripts/sim/road_treatments.gd` (frontage share, the 40% and 15-point rules, the saved memory), per-side looks in `RoadMesh._town`, the three rules (truck route, parking off, main street 20 mph), and the road's click card. Tests: same town gives the same treatments twice; a street with factories on one side and shops on the other gets the right sides and middle; an old save loads. Before and after numbers for one game day.
2. **Homes: wealthy, ordinary, struggling.** From neighborhood tiers; tree rows, lanterns, buried wires; "fixtures outlast the money". Hooks into the state layer's street condition if it has merged.
3. **Strip, school or campus, hospital and farm.** The school zone, the hospital curb, field entrances and mailboxes. Long country pieces judged in 100 m stretches.
4. **Lock or pick.** Click a road side: Auto or any kind. Saved, kept across splits and undo.
5. **The road catalog.** Categories, picture cards, filters, search, and recents on the bar.
6. **First new types.** Items 1 to 8 above (no save change). Items 9 to 13 come after, one at a time.

## What to decide

1. When a building is built, should its side change right away, or wait for the next repaving? **My pick: right away** (the builder pays for the frontage, as real towns require).
2. When the money leaves a wealthy street, do the lanterns and brick stay and wear, or get swapped out? **My pick: they stay and wear**, and drop to Struggling only after a game year.
3. Should picking a different treatment yourself cost money? **My pick: locking what's there is free; changing it costs about what repaving that stretch costs.**
4. Should treatments change land value this round? **My pick: no.** Just the traffic and repaving rules, measured. Land value waits for the state layer.
5. Should the catalog replace the bar's row of kinds? **My pick: no.** Keep the bar for quick picks, and add "All roads" for the full screen.

## A check Nathan can click through himself

1. Open the desktop game at High or above. Draw a Street about 300 m long with two cross streets.
2. Zone Industrial along the left side of one block and Commercial along the right. Play fast until both sides fill.
3. Zoom to 40 m. Left: concrete, no trees, "No Parking" signs, wide truck drives. Right: walk at the curb, steel lights, no parked cars. The middle is concrete. Click the road: it says "Left: Factory · Right: Strip shops · Truck route."
4. Zone shops on both sides of a block next to the town's first shops. Once they fill: walks paved to the storefronts, trees in grates, lanterns, painted stalls. Click: "Main street · 20 mph."
5. Put one shop on a block of homes. That block doesn't change.
6. Bulldoze the factories. The concrete and truck drives stay, as they do in real towns.
7. Click a road side and lock it as Main street. Save, quit, load: it's still Main street.
8. Open Roads, then All roads. A full screen of picture cards by category. Tap the "bike" chip: only roads with bike lanes show.
9. Zoom out to 300 m. The frame rate is the same as before.
