# Farmsteads (real-life details #11, with #35 and #41)

Built 2026-10-25. The county's 5,098 farmsteads and country homes (from the land cover in `terrain/grant_in/farmsteads.bin`) now look like real east-central Indiana farmsteads. Each is grown from a few small facts by rules from real life, and seen mostly from far away, so the far version came first. Code: `scripts/art/farmsteads/farmstead_plan.gd` (the facts and rules), `farmstead_far.gd` (the far drawing), `farmstead_near.gd` (the close-ups), the close-up builder in `scripts/art/farm_builder.gd`, and `scripts/terrain/farmstead_view.gd` (which shows them). Tests: `tests/test_farmsteads.gd`. Bench and pictures: `tools/farmsteads/farmstead_bench.gd`.

## What a farmstead stores

Nothing new is saved. Each place already has its spot, which way it faces its road, whether the land cover shows a farm or a country home, and an 8-bit seed. A seeded generator grows the rest from those, the same on every computer, so every player in a region sees the same farm:

- **Its kind.** Farm sites are 37% working grain farms, 54% farmsteads whose land is rented to a neighbour ("retired": the barn and a few old bins stand, little used), 8% hog farms and 1% dairies. Country homes stay homes.
- **Its size** in acres, for working farms (Grant County's 2022 census spread, below).
- **When it was settled** (1835-1880), and **when its house and barn were built**, so the house type and barn style come from the era.
- **How well the barn is kept**: kept, weathered, sagging or fallen in.

## The rules and the numbers

| What | Rule used | Source |
| --- | --- | --- |
| Farms in the county | 457 farms in 2022, averaging 349 acres; 139 of 50-179 acres, 86 of 180-499, 41 of 1,000 or more. About 1,700 farmsteads show in the land cover, so most no longer farm their own land | USDA NASS 2022 Census of Agriculture, Grant County profile |
| Farm size | working farms 125 to 3,500 acres, a long tail of big ones | same, weighted toward farms that keep bins |
| Farmhouse by era | I-house 1845-1890 (two storeys, one room deep, side gable, rear ell), gabled-ell farmhouse 1870-1910, American foursquare 1900-1930 (hip roof), ranch 1950-1980, two-storey builder home 1990-2020. Country homes are mostly ranches and newer homes | general Midwest architectural history (from memory, not checked against one document); the close-up draws the house builder's own plans of each type |
| Empty farmhouses | about one old farmhouse in twelve, boarded and weathered, grass gone long | farm consolidation; a guess at how often |
| Barn style | bank barn 1855-1910 (fieldstone lower storey, gable roof, an earthen ramp to the loft doors), gambrel hay barn 1905-1945; 36-44 ft wide, 50-120 ft long, 16-22 ft to the eave | general barn history and common plan sizes (from memory, not checked against one document) |
| Barn paint | red 60%, white 18%, bare boards gone grey 22% | a judgement from county aerials and photos |
| Barn upkeep | kept 58%, weathered 28% (faded paint, rusting roof), sagging 10% (ridge bowed, walls leaning), fallen in 4% | a guess; tune by eye |
| Grain bins | round corrugated steel, 18-48 ft across, eave 16-38 ft (more rings on wider bins); bushels = 0.628 x D² x H (feet). A farm stores 35-80% of a year's crop: 118 bu an acre (corn about 180, soybeans about 55, half and half). Bins stand in rows of four | University of Nebraska CropWatch, "How to estimate bushels of grain in a bin"; yields from NASS Indiana |
| Dryer and leg | on grain farms of 700 acres or more with three bins or more: a column dryer and a bucket elevator leg with a spout to each bin | common practice (the 700-acre line is a judgement) |
| Machine sheds | post-frame pole barns since the 1960s, 40x60 to 60x120 ft, 14-22 ft eaves, 4-in-12 steel roofs; tan, white, grey, stone, green, red or brown walls; one per 700 acres or so. A few 1950s-70s Quonsets | post-frame builders' standard sizes (from memory) |
| Hog farms | one or two tunnel-ventilated finishing barns, 41 x 204 ft (1,200 head each), bulk feed bins at the end | the town's own livestock barns (FarmBuilder) |
| Silos | concrete stave silos 1910s-1960s, 12-16 ft across, 36-60 ft tall, on 40% of farms with a barn; most unused, about half with their dome gone. Dairies keep theirs, some a blue Harvestore | San Juan Islands historic barn survey (stave silos 12-14 ft by 35-40 ft), The Henry Ford's 1914 Smith silo, Iowa Barn Foundation silo history |
| Old windmill | one old farmstead in ten: an 8 ft (sometimes 10 ft) wheel of 18 blades on a 28-40 ft four-legged steel tower by the house well, some blades missing | tower and wheel sizes from Aermotor-type mills (Farm Show 2014; Gas Engine Magazine) |
| Windbreak | on the north and west sides (the winter wind's), 65-100 ft out from what it shelters (2 to 5 times its height), 1 to 3 rows 12-20 ft apart, trees 8-16 ft apart, most planted 1940-1985; a gap where a tree died. When the road is on the windward side, a row stands between road and house with a gap for the lane | NRCS Conservation Practice 380 (Farmstead windbreak); Purdue Extension FNR-189 and its county notes |
| Shade trees | sugar and silver maples, oaks, a black walnut or spruce by the house, at least a crown's reach from walls, drive, buildings and gravel | trees code (TreeField kinds) |
| Lane and yard | crushed limestone, the lane 12 ft wide from the road to the yard; the work yard between the house and the buildings | common practice (a judgement) |
| Mailbox | at the road on the drive's side, a standard rural box about 42 in up, its door to the road | USPS rural mailbox guidance |
| Yard light | on 92% of farms and 55% of country homes: a lamp on a wooden pole about 25 ft up, on from dusk to dawn: old mercury vapour (blue-white), sodium (orange) or LED (white) | rural co-op dusk-to-dawn lights; the shares are a guess |

Rounded and judged numbers are marked as such. Where a share is a guess, it is one place to tune in `farmstead_plan.gd`.

## What you see, by distance

- **Far (the whole county, every machine):** a few hundred triangles a farmstead, batched 2 km at a time: the white house and its roof (windows from a grid, lit at night unless it stands empty), the barn under its gambrel or gable, the bank ramp, the bins and the leg over them, the pole barns, silos, windmill, the windbreak as dark rows, the gravel yard and lane, the grounds' mown grass (tan in a dry or cold spell), and at night the yard light as a glow a few pixels across, dimmed by the haze. Snow lies on roofs in winter.
- **Near the camera:** the windbreak and shade trees become real trees (TreeField, so the trees code grows them), within about 0.9 km on desktop High. Within about 0.3 km the buildings are grown in full in the town's own materials: the farmhouse from the house builder's plan book, the bank or gambrel barn with its doors, cupola and trim, hooped stave silos, bins with their fans, the dryer and leg with spouts, pole barns with sliding or overhead doors, a working windmill tower, the mailbox, the yard light and its pool of light at night. The far version dithers out as the close-up comes in (they share sizes and places, so only detail changes).
- **Browser:** the same far version with fewer windbreak stand-ins and fewer sides; close-ups reach 0.6 as far and at most two at a time.

Crops (CropPlants) and wild trees (WildView) now keep off the farmsteads' grounds and buildings.

## Cost (measured 2026-10-25, M5 Max, 1600 x 900, High)

Measured with `tools/farmsteads/farmstead_bench.gd` on the Vulkan driver (it reports the graphics card's time; Metal does not here), switching the farmsteads off and on 8 times in each view, the same views on main ("before") and on this branch. Other helpers' games and tests ran on the same machine all day, so frame times swing by several ms between runs; graphics-time differences under about 0.5 ms are noise.

| View | Triangles the farmsteads add, before | After | Graphics time, farmsteads off vs on (after) |
| --- | --- | --- | --- |
| County, 2.6 km up | 8,600 | 27,000 | 3.20 vs 3.02 ms |
| Low over the county toward the horizon | 15,600 | 98,000 | 4.54 vs 4.48 ms |
| Close to a grain farm (110 m) | 17,800 | 129,000 | 4.85 vs 4.70 ms |
| Close to an old farm | 17,400 | 78,000 | 4.48 vs 4.63 ms |
| Close to a hog farm | 10,500 | 73,000 | 3.90 vs 4.14 ms |
| Night, county | 15,400 | 48,000 | 3.47 vs 3.80 ms |

So the farmsteads cost at most about 0.3 ms of graphics time in any view, within the noise (three runs agreed to within about 0.5 ms).

- **The game's own time:** 0.04 ms a frame on average high up, about 0.1 ms near farmsteads. The county's far farmsteads fill in over the first 5-6 s (3 ms a frame, one farmstead at a time; about 12 ms per 2 km block in all). The slowest single frame of this view was about 8 ms; the slowest close-up step 2-4 ms (a house from the plan book). No freeze. (The window's own worst frames, 30-65 ms, came with the farmsteads off as often as on: other programs on the machine, load average 12.)
- **Graphics memory:** +40 MB of vertex buffers (144 to 184 MB) for the whole county's far farmsteads, after making the mesh indexed and the windbreak stand-ins lighter (the first version used about 120 MB).
- **Main memory:** 1.7 MB for the places; up to 14 MB of kept plans and yards if every corner of the county is visited (a few MB in a normal session).
- **Sliders:** `FarmsteadNear.BUILD_R` and `TREE_R` (how far close-ups and real trees reach, scaled by the quality tier), `MAX_BUILT`, `FarmsteadNear.off` (no close-ups), `FarmsteadView.DRAW_TO` (9 km), and in `FarmsteadFar` the sides and windbreak thinning (`light`).

## Changes to other helpers' files (one line each)

- `scripts/farms/crop_plants.gd`: crops keep off a farmstead's grounds (`FarmsteadPlan.covers`), besides the 55 m round the house they kept off before.
- `scripts/buildings/wild_view.gd`: wild trees keep off farmsteads' buildings and gravel (`FarmsteadPlan.solids_in`, once a chunk, then `on_solid` per tree). The land cover puts woods right on many farm yards.
- `.github/workflows/web-preview.yml`: runs `tests/test_farmsteads.gd`.

## Not built yet

- Modern wind turbines (the second half of #41). None stand in the mapped part of Grant County that we know of; the nearest, the Wildcat Wind Farm (about 125 turbines in eastern Tipton and northern Madison counties), is at or past the map's south-west edge. Placing them right needs the USGS U.S. Wind Turbine Database (a small public download).
- Bins that fill in the fall, barn quilts, lilacs by old houses, basketball hoops on barns, farm dogs and barn cats, machinery parked in the yard, the town's own farms grown the same way (they keep their look).
- The far drawing's windows and lit rooms are a grid, not the house plan's real windows.
