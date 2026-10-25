# Roads that age and get repaired (real-life details #22 and #36)

Built 2026-10-25. Every street, avenue, county road and highway in town now shows its age the way Grant County roads do, from facts the game already had. Code: `scripts/roads/surface/` (`road_wear.gd` the rules and numbers, `road_shaders.gd` the drawing, `road_surface.gd` the materials and the wear map, `gravel_dust.gd` the dust), wired into `scripts/roads/road_view.gd` and `road_mesh.gd`. Pictures and cost: `tools/roads_age_shot.gd`. Test: `tests/test_road_wear.gd`.

## What a road stores

Nothing new is saved. A road's look comes from:

- **Its type** (RoadStyle): the surface (asphalt, chip seal, gravel, concrete), its lanes and width, and the traffic a road of its class carries.
- **When it was paved or last resurfaced**: StreetAge already keeps this for every 40 m square of the town (and resurfaces each street about 25 years after it was built). Read only.
- **The date**, from the tick count.
- **The town's purse**: a town in debt skips crack sealing and is slow to patch (part of #38, "a town with less money has more potholes").

Everything else (which cracks, which potholes, when the crew came) is worked out from those with a fixed hash of the square, so every player in a region sees the same road on the same day.

## The rules and the numbers

| What | Rule used | Source |
| --- | --- | --- |
| How long a street lasts | resurfaced about 25 years after paving (already in StreetAge) | FHWA pavement life, 20-30 years for a mill and overlay |
| Black to grey | jet black when new, charcoal by year 3 to 5, paler still as the fines wear off and the limestone shows (to about year 25) | general experience; the sun oxidises the binder |
| Thermal cracks | straight across the road; the first from about year 3, one every 9 m (30 ft) by about year 21 | cold-climate thermal cracking, 15-60 ft spacing |
| Centre-joint crack | where the two paving passes meet, from year 5 to 10 | common on two-lane streets |
| Fatigue cracks | lengthwise cracks along the wheel paths, then alligator cracking in them: from about year 10 on heavy truck routes to about year 22 on quiet streets | fatigue under truck axles |
| Ruts and wheel-path polish | darker, smoother wheel paths, more under trucks | |
| Block cracking | big polygons where the binder has aged worst, from about year 11 | |
| Crack sealing | first 3.5 to 5 years after paving, then every 4 years, until about year 17 (then the street waits for its overlay). Fresh sealer is glossy black and dulls over about half a year | FHWA pavement preservation; INDOT: $1 of crack or chip sealing saves $6-14 later |
| Potholes | open in February and March (freeze-thaw), more each year as the road ages, more under trucks: about 30% of 5 m wheel-path stretches over a truck route's life, about 15% on a quiet street | INDOT and county superintendents: February to early April is pothole season |
| Cold patch | black cold mix within 2 to 4 weeks, lumpy and a little bigger than the hole | |
| Hot patch | a square saw-cut patch once the asphalt plants open, mid May to September; it ages from that day | hot mix needs about 40-50 F (FHWA HMA guide, table 402-2) |
| Utility cuts | the odd strip across part of the road, cut in some year after paving, with its own age | |
| Lane paint | waterborne paint, bright after its repaint, duller and patchy after one winter of plows and salt, gone in a few years if nobody repaints. Repainted between early June and August: 60% of stretches every year, the rest every other year; new paint with every resurfacing | INDOT repaints at least yearly, April to October; Iowa and Vermont: paint lasts about a year, one winter |
| Chip seal | liquid asphalt with limestone chips, redone every 5 to 7 summers in July: dark the week it goes down, pale and stony after; chips work into the binder in the wheel paths (darkest in summer heat) and the old layer shows where chips have gone | INDOT: a chip seal adds 3 to 5 years; counties stretch the cycle (a guess) |
| Edge breakup | narrow county roads (paved and chip seal) crumble into the gravel shoulder, more each year | |
| Gravel roads | crushed limestone, two packed tire tracks about 1.7 m apart, loose stone between and outside, grass up the crown on a quiet road; graded in mid April, mid June, mid August and late October, leaving a windrow of stone at the edge; tracks back in about two weeks; washboard ripples about 0.75 m apart on some stretches; puddled potholes in spring before the first grading | FHWA / SD LTAP Gravel Roads Manual (crown about 4%, grading "as needed"); the four gradings a year are a guess |
| Dust | cars over about 20 mph on gravel and dirt roads trail a pale plume for about 6 seconds, none on snow or in the spring thaw (March and April) | the game has no rain yet, so dry means no snow and not spring |
| Concrete | 15 ft slabs with longitudinal joints at the lane lines, light grey going darker with grime; more panels cracked across or broken at a corner each decade, under trucks; on old ones a broken panel patched in asphalt | INDOT Design Manual ch. 52, 15 ft joints (JTRP-2011/20) |
| Which roads are concrete | interstate mainline (the three freeway types) and alleys; everything else asphalt, chip seal, gravel, dirt or brick | INDOT builds much of its interstate in jointed concrete |

**Traffic.** The game keeps no count of cars per road, so each road type stands in for its class, with rough INDOT figures: local streets 500 to 1,500 a day (3% trucks), collectors and avenues 4,000 to 12,000, arterials 12,000 to 20,000, rural I-69 25,000 to 45,000 (a fifth to a quarter trucks), paved county roads about 800 (10% farm trucks), chip seal about 250, gravel about 60 (`RoadWear.TRAFFIC`). Real counts per road would be a later step for the traffic team.

Numbers marked as guesses are reasonable from the sources but not measured in Grant County.

## What you see, by distance

- **Every machine (the browser too):** the colour by age, the patches and potholes, the sealed cracks across the road (they show from the air, as real ones do), the paint by its last repaint, chip seal, gravel tracks and crown grass, concrete slabs. Lines thinner than a pixel are drawn by how much of the pixel they cover, so a road far off is its plain average colour and nothing shimmers.
- **Desktop (Medium and up):** also the alligator and block crack networks up close, and the dust behind cars.
- **Not yet:** the crews themselves (patching trucks, the paving train, the grader, the paint truck), winter-by-winter weather (the game has none), and real traffic counts.

## Cost

See the PR for the measured frame time and memory, and `tools/roads_age_shot.gd --ab` to measure again.

## Corners cut

- The town's budget pays for resurfacing only (StreetAge). Crack sealing, patching, re-chip-sealing and repainting are drawn but not billed. Billing them is sim work.
- A street's age is its 40 m square's, so a long street resurfaced in one job looks the same all along, and two streets crossing in one square share an age.
- Potholes come from age and trucks, not from how hard each winter was.
