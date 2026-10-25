# The crop calendar (real-life details #1)

Built 2026-10-25. What every corn, soybean, wheat, hay and pasture field in the county looks like on any day of the year, grown from a few small facts and the date. Code: `scripts/farms/crop_calendar.gd` (the rules), `crop_fields.gd` (the town's farm fields), `crop_plants.gd` (plants near the camera), and the field part of `scripts/terrain/terrain_view.gd`'s shader (the county's fields). Tests: `tests/test_crop_calendar.gd`.

## What a field stores

Nothing new is saved. Each field's look is worked out from:

- **Its crop this year and last year.** The town's farms already save this (CropPlan). The county's fields get it from a hash of the field and the year: most are in a corn and soybean rotation, so a field swaps every year.
- **The farm's habits.** Tillage (no-till, chisel in the fall, or till before corn only) and a rye cover crop. Town farms take cover crops from CropPlan and tillage from the farm and its leader's schooling.
- **A timing seed.** How early in the county's planting and harvest this farmer gets to the field.
- **The year.** One spring in four is wet and planting runs late; some summers run warm or cool.

From those and the date, every field is a little different, and every player in a region sees the same field on the same day.

## The rules and the numbers

| What | Rule used | Source |
| --- | --- | --- |
| Field sizes | Each quarter section (160 acres) is farmed as one 160, two 80s or four 40s; rows along the long side | USDA aerials of Grant County |
| Crops in the county | about 52% corn, 45% soybeans, 2% wheat, 1% hay, 1% pasture; 9% of fields corn after corn | USDA NASS Grant County estimates (rounded) |
| Corn planting | 12% by Apr 28, 26% May 5, 42% May 12, 60% May 19, 71% May 26, 84% Jun 2, 93% Jun 9 | NASS Indiana Crop Progress, five-year averages (rounded from the weekly reports, e.g. 71% corn on May 26, 2024) |
| Soybean planting | 9% May 5, 22% May 12, 38% May 19, 60% May 26, 75% Jun 2, 86% Jun 9 | same (60% beans on May 26, 2024) |
| Wet springs | one year in four, planting 5 to 15 days late | Purdue planting-date notes; a guess at how often |
| Heat for corn | growing degree days (base 50 F, cap 86 F) from Marion's normal highs and lows by month (Jul 84/63, Apr 61/39, Jan 33/18) | NOAA 1991-2020 normals (Marion, Fort Wayne, Indianapolis) |
| Corn stages | emerges at 125 GDD; V6 475, V10 740, V14 1000, tassel 1350, dent 2300, black layer 2,420-2,680 (about 200 fewer when planted in June) | Iowa State PMR 1009; Purdue (Nielsen) and Ohio State AGF-0101 |
| Corn height | 0.4 m at V6, 1.1 m at V10, 2.0 m at V14, 2.55-2.85 m (8.4-9.4 ft) with tassels | same stages, Indiana hybrids |
| Canopy | 30 in rows close at V10-V12 (late June to mid July) | Purdue Corn and Soybean Field Guide |
| Corn drying | about 32% moisture at black layer; dries 0.8 points a day in September, 0.5 in October, 0.25 in November; harvested at 18-25% | Purdue grain drydown articles |
| Frost | first hard freeze mid to late October ends any corn still green | NOAA freeze dates, Grant County |
| Soybeans | 2-3 ft; rows close in July (15 in rows) or August (30 in); leaves yellow about Sep 13 (later for later planting), drop over 12 days, harvest 5 days after | Purdue soybean production; Iowa State soybean stages (maturity group 3) |
| Harvest | corn 18% by Oct 6, 33% Oct 13, 54% Oct 22, 76% Nov 5; beans 28% Oct 6, 45% Oct 13, 67% Oct 22, 88% Nov 5 | NASS Indiana five-year averages (Oct 13, 2024 and Oct 22, 2023 reports) |
| Residue | corn leaves 85% cover no-till (40% after a chisel pass), beans 35%, wheat straw 85%; a third rots by midsummer | Purdue residue estimates |
| Tillage | 30% no-till, 40% chisel corn stalks in the fall and cultivate before planting, 20% till before corn only, 10% no-till with cereal rye | Indiana tillage transect (about 60% of beans and 35-40% of corn no-tilled; cover crops on about one acre in ten) |
| Rye cover | drilled 2-6 days after harvest, up in a week, a low mat by December, greens up in March, sprayed 2 weeks before corn or right after beans are planted into it | Purdue / Midwest Cover Crops Council |
| Wheat | drilled in October, green over winter, heads late May, gold mid June, cut around July 1; no-till farms follow with double-crop beans | Purdue wheat calendar |
| Hay | alfalfa cut late May, early July, early August, mid September; regrows in about four weeks | Purdue forage notes |
| Row spacing | corn 30 in (0.762 m), about 6.5 in apart in the row (34,000 seeds an acre); beans 30 in, or 15 in on no-till farms | Purdue field guide |

Rounded numbers are marked as such. The weekly NASS PDFs could not be read directly, so the progress tables are rounded from the reports as quoted by Hoosier Ag Today and AgriNews. The wet-spring share and the tillage split are reasonable guesses from the sources, not measured for Grant County.

## What you see, by distance

- **Every machine (the browser too):** each field's colour from the air, its rows in stripes that blend to an even tone far off, tall plants hiding the soil when seen at a slant, standing stalk rows in the stubble, the chisel-plowed fields dark, snow with stubble poking through. The town's farm fields read the same rules. This replaced the old monthly colour table, and the farm field mesh is no longer rebuilt every month (only when the farms change or the year turns).
- **Desktop at High and above:** real corn and soybean plants within about 60 m of where the camera looks (80 m at Cinematic), at real row spacing and today's height: rows just up in May, corn closing its rows in June and 8-9 ft with tassels in July, lower leaves firing and the plant drying tan in September, beans turning yellow and dropping their leaves, 40 cm corn stalks after the combine standing through the snow until the field is worked or planted. Full plants within 30 m of the camera, a lighter plant past that; they thin out toward the edge, where the ground's stripes carry on. Corn casts shadows at Cinematic (shadows on every plant at Ultra tripled the triangles drawn; shadows only near the camera showed as a darker square).

## Cost (measured 2026-10-25, M5 Max, 1600 x 900)

Measured by switching the new look on and off 8 times in each view and comparing the median frame (`tools/crop_bench.gd --ab`), because other helpers' games and tests were running on the same machine; differences under about 0.3 ms are noise. Triangle counts are exact.

| View | Before | After | What it adds |
| --- | --- | --- | --- |
| County, 2.6 km up (desktop, High) | 5.3 ms, 116k triangles | 5.3 ms, 116k triangles | every field's stage, rows, stubble and tillage; no measurable cost |
| County (browser renderer) | 7.3 ms | 6.8 ms | the same look; within noise |
| Close over corn, 40 m (High) | 5.0 ms, 0.59 M triangles | 5.4 ms, 1.97 M | real corn plants in rows |
| Close over beans, 40 m (High) | 3.4 ms, 0.65 M | 3.4 ms, 1.30 M | real bean plants |
| Close over a farm and the fields round it, 60 m (High) | 3.4-3.6 ms, 2.0 M | 5.1-5.8 ms, 3.4 M | the worst case: plants on two farms and county fields at once |
| Corn stalks in winter (High) | 3.7 ms, 0.59 M | 3.9 ms, 0.78 M | stalks standing in the snow |
| Memory | | +32 KB texture, about +1-4 MB graphics and +3 MB RAM for the plants | |

CPU: the crop table is one 128 x 64 texture; a full pass takes about 2-4 ms, spread at 1 ms a frame, about every 5 seconds at normal speed (the farm field mesh used to be rebuilt every game month; now only when farms change or the year turns). Plants: about 0.3-0.5 ms a frame while tiles stream in; one 16 m tile takes 0.3 ms on average and 0.64 ms at worst, so no freeze. At Ultra, shadows from every plant tripled the triangles (6.6 to 14.9 M in the farm view), so plant shadows are corn only and Cinematic only.

## Sliders

- `CropPlants.RADIUS`, `NEAR` and `SHADOW_TIER`: how far plants reach, where the light plant starts, and from which tier they cast shadows.
- `CropPlants.off`: no close-up plants (the ground still shows every stage).
- The browser draws no plants; it has the full calendar on the ground.

## Not built yet (later lines on the list)

Combines and grain carts at harvest, leaf roll in drought, real rain delaying planting (there is no weather yet), silks and ears up close, straw bales after wheat, tramlines in young crops, and planting rows showing in freshly planted soil.
