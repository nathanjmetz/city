# Look check: does it look like a real Indiana town?

Playtest on 2026-10-25, against main at `6eb2ed2`.

**How it was played**
- **Browser:** the live site, https://nathanjmetz.github.io/city/, in headed Chrome at 1600×900. The game picked its own quality: "Auto: Low" (after an unclean close the log said "starting safe at Low"). I ran the `?playtest=240` mode, which built a 4×4 grid, joined a county road and the state highway, zoned it, and ran at top speed. Then I drove the camera by hand: wheel zoom, right-drag pan, and T/G tilt.
- **Desktop:** a Godot 4.7.2 window at `--quality high`, 1600×900. A throwaway script built a 3×3 grid off the state highway, ran two grid streets onto the highway, laid a road to a county mile, and added a player-built county road, a gravel road, a county-road crossing and a gravel T. It placed the builder's yard, power, water, a substation, a water tower and a police station, then grew the town to about 1,650 people. It shot 40 m, 100 m, 300 m, 1 km and 3 km views, plus night, dusk and October.

Shot names: `w…` are browser shots (Low), `d…` and `e…` are desktop shots (High). Desktop `e…` shots have the HUD hidden.

The yardstick is MUTCD (road markings), the AASHTO Green Book (road shape), and photos of Grant County roads and towns.

---

## Ranked defects (most visible to a player first)

### 1. A plain round disc where a road meets the highway or a county road (Nathan's "circle node")
- **Shots:** `e07-countyjoin-top`, `e08-countyjoin-low`, `d15-countyjoin-60m`, `d16-countyjoin-200m`, `e04-rural-tee-top`, `w9-junction-close`, `w15-circle-node`
- **Where:** where a built road joins a county mile or the state highway, and at T junctions of two country roads. Visible at 40–200 m.
- **What's wrong:** the road ends in a round asphalt (or gravel) cap that sticks out past both edges, like a cul-de-sac bulb. On the gravel T it is a lumpy blob that spills over the shoulders. Where a paved road meets a gravel county mile, the paved road ends in a half circle and the gravel strip runs on, so the two don't line up.
- **Real life:** a T or crossing of two country roads is square. Each edge flares into the other with a 25–50 ft (7.5–15 m) radius, and the pavement corners are filled. Nothing round shows unless it is a real cul-de-sac.
- **Code:** `scripts/roads/road_view.gd`, which calls `RoadMesh.add_disc` at about line 484 for nodes `Junction.plan` skips. `scripts/roads/junction.gd` says "Only junctions of curbed two-way streets are shaped here; highways, ramps, roundabouts and country roads keep their own joins". Country, highway and gravel joins never get a shaped junction, so they fall back to the disc.

### 2. Edge lines run straight into the junction and cross into "+" and "T" marks (Nathan's "white lines intersect to a T")
- **Shots:** `e01-rural-cross-40m`, `e02-rural-cross-top`, `d04-hwyjoin-40m`, `d06-hwyjoin-top-80m`, `w12-hwy-junction-40m`
- **Where:** every junction on a county road or the state highway. Visible from 40 to 100 m.
- **What's wrong:** each road's solid white edge line runs right to the middle of the junction, so the lines of two roads cross and leave white crosses at all four corners. On the highway through town, the highway's edge lines run straight across the mouth of every side street.
- **Real life:** MUTCD 3B.06 and 3B.08 say edge lines stop at the junction, or carry across a side road only as a dotted extension. They never cross each other. The corner is clean asphalt.
- **Code:** `scripts/roads/road_mesh.gd` `_rural()` (about line 213) paints the `white` layer for the segment's full length with no `gaps`. `road_view.gd` doesn't pass a trim for country nodes. `scripts/roads/junction_marks.gd` only handles shaped town junctions.

### 3. Shoulder strips cross over the highway pavement where two road pieces meet (Nathan's "gravel goes onto the highway")
- **Shots:** `w12-hwy-junction-40m`, `w9-junction-close`, `w14-county-far`
- **Where:** the Y where the state highway piece the town joins meets the town road. Browser, Low, at 60–150 m. I didn't re-shoot this Y on desktop, but desktop uses the same mesh code.
- **What's wrong:** each piece draws its own full-width shoulders, so the pale shoulder strips and edge lines of one piece cut across the other piece's asphalt in an X or diamond.
- **Real life:** where two roads merge, the pavement is one surface. The shoulder runs only along the outside edge, and the gore between them is painted chevrons or grass.
- **Code:** `scripts/roads/road_mesh.gd` `_rural()` and the highway profile (about line 316). There's no junction shaping for these nodes (see #1). The gore logic in `scripts/roads/ramp_merge.gd` only runs on ramps.

### 4. The gravel shoulders don't look like gravel (Nathan's "gravel doesn't look like gravel")
- **Shots:** `d12-county-mine-40m`, `d13-county-mine-top`, `d14-gravel-40m`, `e03-rural-tee-40m`, `crops/e03-grass-crop.png`
- **Where:** every county-road shoulder and every gravel road. Strongest at 40–100 m.
- **What's wrong:** the shoulder is near-white, almost the colour of a sidewalk, with sharp green camouflage blobs. It reads as a terrazzo floor or a snowy sidewalk. It is the same width and brightness the whole way, with a hard straight edge into perfect lawn. From 300 m to 1 km the shoulders look like twin white sidewalks (`d21-town-1km`).
- **Real life:** Indiana county-road shoulders are crushed limestone (#53 stone), a mid grey-tan a little lighter than the asphalt. They're darker where tyres run, with tufts of grass and a ragged, uneven edge into the ditch grass. There is usually a grass ditch slope beyond.
- **Code:** `scripts/art/surfaces.gd` `GRAVEL` (about line 206). The colour range 0.50–0.62 renders much lighter than intended at High, the weed blotches are large and hard-edged, and there's no edge breakup. The layer is in `road_mesh.gd` `_rural()` (`["gravel", … hw + 1.8]`).

### 5. Ghost lines across the land: painted county roads that fade, blur and run on past the real road (Nathan's "lines on the ground through the grass and across the road")
- **Shots:** `d15-countyjoin-60m`, `d16-countyjoin-200m`, `e07-countyjoin-top`, `e08-countyjoin-low`, `w14-county-far`, `e18-farm-200m`, `d21-town-1km`, `d22-county-3km`
- **Where:** everywhere a county mile is painted on the land rather than built. Seen at 60 m to 3 km.
- **What's wrong:** the county roads are a blurry pale smear in the ground texture. Where a built road joins one, the paint carries on as a soft streak across the grass and fades out mid-field (`e08`: a pale smear running off to the right). In `w14` a painted mile fades out about 100 m before it reaches the highway. In `e18` woods grow right on top of the painted road. From 1–3 km there are also thin straight pale lines across fields and woods that line up with nothing (`d21` top right, `d22`).
- **Real life:** a county road is a crisp strip with shoulders, a cleared right of way and fence or tree lines along it. It never fades into a field, and trees don't grow on it.
- **Code:** `scripts/terrain/terrain_view.gd` (the painted county-road layer; `surfaces.gd` says "TerrainView gravel"). Tree clearing along painted miles is in `scripts/terrain/county_grid.gd` and `scripts/art/tree_field.gd`. Some of the straight far lines may be the town-land outline or long pole runs; I couldn't tell which from the shots.

### 6. The power lines make no sense (Nathan's point)
- **Shots:** `d08-hwyjoin2-60m`, `d14-gravel-40m`, `d16-countyjoin-200m`, `e01-rural-cross-40m`, `e03-rural-tee-40m`, `e11-hwy-rural-low`, `d04-hwyjoin-40m`
- **What's wrong:**
  - Wires run over the roof of a store (`d08`).
  - Wires cut diagonally across open fields, far from any road, with no poles between (`d14`, `d16`).
  - At a rural crossing there are two poles side by side on one corner, and each road's line stops at the junction instead of carrying through (`e01`).
  - At the gravel T the line jumps from one side of the road to the other at the junction (`e03`).
  - Wires pass through tree crowns (`e11`).
  - A pole stands in a parking-lot corner (`d04`).
  - No house has a service drop from a pole or transformer.
- **Real life:** one pole line per road, on one side, inside the right of way, with poles every 40–60 m. It carries on through junctions and crosses a road only at a pole on each side, square to the road. A triplex service drop runs from a pole transformer to each house's mast. Lines never pass over buildings (NESC clearance), and tree crowns are trimmed back from them.
- **Code:** the per-segment pole runs are in `scripts/roads/road_mesh.gd` (about line 246, "crossarm, three insulators and the wires") and `scripts/roads/road_view.gd` (`_pole_cache`, `_poles_later`). Each segment draws its own run, which explains the doubled poles and broken runs at junctions. Town poles are in `scripts/art/street_lights.gd` (about line 237, crossarm). The feed line is in `scripts/power/power_view.gd` and `scripts/sim/power.gd` (about line 656).

### 7. The browser shows Low quality, and Low is what feels like "the old game"
- **Shots:** `w5-int-40m`, `w6-town-1km`, `w10-low-angle`, `w9-junction-close`, `w1-tour-*`
- **What's wrong:** the live site logged "Auto: Low" and, after an unclean close, "starting safe at Low". At Low:
  - Shadows have stair-step edges (`w10`, bottom left).
  - Snow and lawn ground show banding stripes (`w10`).
  - Winter lawns are noisy beige.
  - Roofs are speckled.
  - Shoulders break up into dashes (`w9`).
  - The town reads flat and plastic next to the desktop High shots (`d07`, `e19`).
- **Real life / goal:** the first impression should look like the desktop High shots.
- **Code:** `scripts/shell/quality.gd` sets the browser's Auto start at Low, and the crash step-back holds it there. It's worth checking how fast it climbs, and whether it ever reaches High on a Mac browser.

### 8. Convoys of identical white box trucks, and a jammed town of 1,600 people
- **Shots:** `w12-hwy-junction-40m`, `w15-circle-node`, `w14-county-far`, `d19-houses-40m`, `e06-grid-meets-county-top`, `e09-hwy-end-into-paint-100m`, `e10-hwy-end-top-200m`
- **What's wrong:** long lines of the same white box truck with a red stripe (it reads as an ambulance) queue bumper to bumper along the highway and county road. In `w15` a dozen are parked nose to tail on a gravel shoulder. The HUD says flow is 42–50%, so a small town is gridlocked all day.
- **Real life:** a 1,600-person Indiana town has free-flowing streets with a car every few hundred feet. Delivery and construction trucks come in ones and twos, in a mix of liveries.
- **Code:** construction trips in `scripts/sim/construction.gd` (the trucks each stage sends). The model is in `scripts/vehicles/vehicle_models.gd` (`_box_truck`, about line 925). Queueing is in `scripts/sim/traffic_sim.gd`.

### 9. Problem icons pile up into a pink caterpillar floating over the town
- **Shots:** `d17-power-low`, `d22-county-3km`, `d23-horizon`, `e11-hwy-rural-low`, `e12-wires-street-low`, `e13-trees-40m`
- **What's wrong:** dozens of water-drop alert icons in pink rings stack into one long overlapping smear above the houses. It shows even in the HUD-hidden shots and from 3 km.
- **Real life / goal:** one alert per area (clustered), or a count badge, faded out when the camera is far.
- **Code:** `scripts/zones/lot_alerts.gd`

### 10. The state highway through town is still a rural road
- **Shots:** `d04-hwyjoin-40m`, `d05-hwyjoin-100m`, `d08-hwyjoin2-60m`, `d09-hwy-shoulder-40m`, `e09`, `e10`
- **What's wrong:** where the town has grown along the highway, it keeps its gravel shoulders and white edge lines. Then there's a grass gap, then the town's sidewalk. Houses and driveways front onto it with no curb, and the joining streets have curbs and crosswalks right up to a curbless highway.
- **Real life:** inside town limits Indiana state routes (for example SR 18 and SR 9 through Marion) become curb-and-gutter streets with sidewalks, parking or a turn lane, and a lower speed.
- **Code:** `scripts/sim/city_sim.gd` `_join_highway` lays `STATE_HWY`, and `RoadStyle` has the rural profile. Nothing changes the highway's profile when lots line it.

### 11. Roads that stop square in the grass
- **Shots:** `w15-circle-node` (centre), `e06-grid-meets-county-top`
- **What's wrong:** the highway or county piece the town gets ends abruptly in a field, with a square-cut end and full shoulders. In `e06` a county road I drew ends in someone's back yard, and the grid street it was meant to join is about 40 m away.
- **Real life:** a road ends at a junction, a cul-de-sac or a barricaded stub (MUTCD Type III barricade). It doesn't stop in a lawn.
- **Code:** the join pieces stop at "the edge of its land" in `scripts/sim/city_sim.gd` `_join_highway` (about line 3890) and the county join. Road placement is in `scripts/roads/road_network.gd`.

### 12. Fine stripes and moiré on grass and fields
- **Shots:** `e04-rural-tee-top`, `crops/e04-grass-crop.png`, `e14-field-40m`, `w10-low-angle`
- **What's wrong:** at top-down and steep views the grass is covered in fine vertical stripes, a screen-space moiré. The crop rows in `e14` are evenly spaced brown-and-green bands, like a striped carpet. They start and stop with a soft blend into lawn instead of a field edge.
- **Real life:** crop rows (30 in) aren't readable from 40 m up. A field looks like a textured green or brown surface with a crisp edge, a turn row and a fence line.
- **Code:** `scripts/farms/farm_view.gd` (field rows) and `scripts/art/ground.gd` / `terrain_view.gd`. The rows need a mip or fade with distance.

### 13. Dark brown rings around every woodlot
- **Shots:** `e18-farm-200m`, `e17-farm-60m`, `d07-hwyjoin-300m`, `e19-october-town-300m`
- **What's wrong:** every patch of woods sits on a dark brown halo of bare dirt that sticks out past the crowns like a stain. In October this becomes large brown blotches across the fields (`e19`).
- **Real life:** a woods edge is grass and brush, and the leaf litter is hidden under the crowns. From the air it's a green edge.
- **Code:** `scripts/terrain/terrain_view.gd` (woods floor paint) and `scripts/art/tree_field.gd`

### 14. Farmsteads are two plain boxes, hidden in the woods
- **Shots:** `e17-farm-60m`, `e18-farm-200m`, `d16-countyjoin-200m`, `d28-edge`
- **What's wrong:** a "farmstead" is a white box with a brown roof next to a second box. There's no barn, grain bins or lane to the road, and it sits in the middle of woods with no drive.
- **Real life:** the file header itself names the benchmark: a white two-storey farmhouse facing the road, a red bank barn, a steel machine shed and grain bins on a gravel lane, set in the open with a windbreak.
- **Code:** `scripts/terrain/farmstead_view.gd`

### 15. People walk on lawns, not sidewalks
- **Shots:** `d09-hwy-shoulder-40m`, `d10-hwy-shoulder-low`
- **What's wrong:** a line of pedestrians walks through the front-lawn grass parallel to the street, with the sidewalk a few metres away. One stands alone in the middle of a big lawn.
- **Real life:** people walk on the sidewalk, and on the shoulder where there's no sidewalk.
- **Code:** walking paths in `scripts/sim/traffic_sim.gd` (`_walk_between`, `_sidewalks`, about line 3527). The desktop log also showed this error 3 times while growing: `Out of bounds get index '149'` in `TrafficSim._seg_node` (traffic_sim.gd:3635), called from `_walk_steps` / `_sidewalks`. A stale segment id in the walk path may be part of why people end up off the sidewalks.

---

## Smaller things noticed
- **Night has no car lights** (`d31-night-hwyjoin-60m`): at 10 pm the cars show no headlights or tail lights, and most highway poles are dark. The game was paused when the clock was moved, so this may be a paused-state issue; it needs a recheck while running. Code: `scripts/art/headlights.gd`, `street_lights.gd`.
- **The clock says night while the sun is up** (`w9` "2:49 AM", `w10` "5:20 AM" in full daylight; day/night is off by default). A player reads this as a bug. Code: `scripts/ui/hud.gd` clock, `scripts/art/day_night.gd`.
- **The camera dips into tree crowns** at low tilt (`e11`), so the view fills with leaves. Code: `scripts/camera/city_camera.gd` `_apply` only keeps the camera off the ground.
- **The gravel road meets the highway as a separate gravel disc** that touches but doesn't join (`w9`).
- **Hard straight edges where ground textures meet**, for example a lighter-green field rectangle against grass (`e18`, top right).
- **The service sites didn't place** in both runs. The playtest's school and fire station were refused, and so were the water tower, school, fire station and police station in mine. That left 87 buildings without water and fed the icon pile-up (#9). It's gameplay, not looks, but a new player will hit it.

## What I didn't test
- I didn't verify the browser at Medium or High (Auto never climbed during my run), and I didn't test phone or tablet sizes.
- I didn't watch a construction site mid-build up close. The site I found had already finished (`e15`, `e16`), so I couldn't judge the trucks at a single site.
- I didn't shoot a ramp interchange, the backdrop towns (Marion and Gas City), or rail.
- I didn't try multiplayer or regions, on purpose.
