# Team status (start here)

Updated 2026-10-26 by the coordinating session ("Desktop photoreal handoff"). This file is the state, not a diary: rewrite it at each stop.

## Standing orders from Nathan (2026-10-25)

- "i want you to begin the work and continue without asking me anything. i wont be here to approve so i dont want you to stop."
- Merge to main when each step is verified, meaning every web-preview test passes and a second reviewer has checked the diff. Then confirm the web and desktop builds finish before calling anything live.
- What the game is and how it runs never change. What it does and how it looks are sliders on one performance budget (see `docs/desktop-photoreal-handoff.md`). Every feature and every detail is priced in measured ms and memory, next to what it adds. Costly, low-value things go to Nathan, not cut silently.
- **Neighbor towns are a living picture (Nathan chose A, 2026-10-25).** In a shared region, your game no longer keeps every neighbor's whole town (about 1 GB each). It shows their buildings, roads, night lights and some traffic, updated about once a minute, and fills in full detail only when you fly over to look. This is the price list's item #1: it's what lets browser players and 8+ players share a region.
- Still waits for Nathan: anything touching sign-in, paid services, data loss, big downloads (the real county map data and its OpenStreetMap credit line), or deleting things.

## Waiting on Nathan

When a helper hits a wall it writes its question here and stops. That task waits, and the next task in the queue starts. Answer any time; the task picks up from the answer.

- **Day and night off (from the daylight work, PR #541):** when the day-and-night cycle is turned off, should the game show a real summer moment (for example June 21 at 1:40 pm), or keep today's tuned sun from the southwest, which a real summer day never has? Until you answer, it keeps today's look.

## Where everything stands (2026-10-26, early morning)

**Merged 2026-10-26:**
- #583-#585 traffic control stages 1-3: your own light timing, green waves (Ctrl-click), smart lights with sensors
- #586 ambient life: builders at work on house sites, recess at schools
- #587 weather: overcast days and rain by Indiana's odds, with an on/off switch beside seasons; on the home screen too (made-up odds for now, not Marion's real weather)
- #588 houses vary their distance from the curb; a car's stop now saves the same before and after loading (copies had drifted)
- #590 cars stop at the stop line, not 2.5 m short of it. The old "7.9 m short at the highway" figure was a measuring fault; it's 1.7 m now.

**Waiting on a second reviewer, then merge:**
- #589 boxed-in landfills, recycling and cemeteries fill their block up to the sidewalk. Other hub kinds (post office first, it's the easiest) come after; the helper's notes on each are in #589.
- `traffic-center` branch: stage 4, the Traffic Management Center (Civic > Traffic). Its engineers count cars at each light and retime the greens every three game hours; lights you time stay yours.

**Earlier (2026-10-25/26):** #567 cars drive the limit, #568 roundabouts as a whole, #569-#578 people (skins, figures, five detail levels, ready-made desktop people), #579 faster four-way stops, #580 load until drawn, #581 admin sound mixer, #582 detail floor, #552 live home screen, #555 automatic quality, #551 new building drawing (minor items listed on #551), #557-#566 green lights, signal heads, people sizes, fewer walkers, solid county roads, strides, dirt farm lanes, slower farms, levels 1-100.

**Ready but waiting:**
- #556 roads age: profile in real Chrome first.
- `wip/price-list` and `wip/browser-measure`: paused.

**Known test gaps:** tests/test_green_light.gd is not in CI. Its stop-line and all-way-stop checks pass, but 2.6 s between cars on green (target 2.3 s) and the start-up ripple still fail.

## The queue, in order

A few helpers run at a time, never two on the same files.

*Running now:* 1 town speed, 2 shared region, 3 new drawing style measured.

*Make it smooth everywhere*
- Freeze: the farm field mesh rebuilds all at once when farms change (about 150 ms); spread it over frames (found 2026-10-25).
4. Drawing speed: building drawing cost and graphics memory (6.7 GB to under 2 GB).
5. Automatic quality levels for the browser, Mac mini and Mac Studio, each with a detail budget.
6. The detail-by-distance system (near, middle, far; fades in; built a little each frame).
7. A browser measurement: the web build timed in a real browser.
8. Long-haul test: hours at top speed, memory creep, autosave and big-edit freezes.
9. Shared-region stress test: several players with big towns.
9a. Neighbor towns as a living picture (Nathan chose A): starts when the region fixes land; then re-run the region stress test with a browser player.
9b. The price list: every feature's measured cost in ms and memory next to what it adds, so the costly, low-value ones go to Nathan one at a time.

*How it looks*
10. Houses grown in code (brick, siding, roofs, windows, trim), checked against real photos.
11. Shops, civic buildings and factories grown the same way.
12. Trees that grow (Grant County kinds, seasons, cheap far versions).
13. Ground surfaces: grass, soil, gravel, crop fields by season, roads that age, crack and get patched.
14. Ground wear and desire paths.
15. People's clothes and bodies from who they are (age, job, income, weather).
16. People's behavior up close: walking styles, groups, kids, dogs.
17. Cars and trucks: real detail up close, dirt, rust and salt by age and season.
18. Crowds and events up to 100,000: real fan behavior, players, referees, cheerleaders, band, camera crews, lights, scoreboard.
19. Night and light: porch lights, streetlights, stadium lights.
20. Closer zoom step 1: 40 m to 20 m on the desktop.
21. Closer zoom step 2: to 10 m, then standing on the sidewalk (no shirt buttons).

*Life you discover:* `docs/real-life-details.md`, now ranked by impact (Nathan, 2026-10-25: "organize that list by what we have the most dramatic impact on the game and work on those things first"). Work it from the Top 50 down, a few ideas a helper, numbers checked before they become rules.

*Next up (Nathan, 2026-10-25)*
- Fix the new building drawing's review findings (posted on PR #551), then merge #549 and #551.
- Home screen weather, part 2: the game now draws cloud and rain (#587) by made-up odds. Next, feed in Marion's live conditions from the National Weather Service (api.weather.gov: free, no key, official; falls back to the odds when offline). Only Marion's fixed location is sent, never the player's. MenuLife.conditions is the hook. Snow and fog still to draw.
- Traffic: a 2,700-person town growing along the highway drops to about 45% flow; queues back up at the all-way stops where highway streets enter the grid.

- Traffic control that grows with the town (`docs/spec-traffic-control.md`): stages 1-3 live, stage 4 (Traffic Management Center) waiting on review. Still to do: the university civil engineering wing as a second way in, and plans by time of day shown in the light's panel.

- People (Nathan, 2026-10-25):
  - Partly fixed in #560 (car owners drive most short trips: 51 -> 36 walking at once in a 145-person town). Still left: children never ride with family, so their trips are all walks; add family rides. Nathan's words: "there are SO many people walking. I had a town of a couple hundred and the streets were flooded with pedestrians." Find what sends so many walkers (people.gd strolls, STROLL_SHARE 0.2; balance.gd WALK_SHARE 0.12 and WALK_NEAR; traffic_sim MAX_WALKERS 800) and match real small-town walking rates.
  - "could their walking styles be different?" Vary stride, arm swing and pace per person in walker_view.gd's shader (it needs a spare per-instance channel; mind the browser's instance-colour quirk noted there).

- Nathan's list (2026-10-25, evening), in his words:
  1. "when i first open the game, i see a nice road that i assume i am supposed to use and a weird gray line that may or may not be a road running like a dashed line perpendicular to it". Check the starting map: county road vs the dashed grey line. Likely the terrain shader's painted real county roads (terrain_view.gd hw_col, "hw_paved"), which read as a faint dashed line from afar and can't be used. Not the rail overlay (no lines at start) or city lines (single player). Confirm with a new-city screenshot: the shot tools load the local save, so start a fresh city or move the save aside. Then make painted roads read clearly, as real but not yours, or let the player connect to them.
  2. "when homes are being constructed, a full semitruck load of what looks like rolled metal shows up at every house… semitrucks [shouldn't] be driving on residential streets… homes dont need semi loads of anything. one concrete truck should come. and then a contractor truck should sit on the curb until its done." Findings so far:
     - The "house" profile already sends no flatbed (construction.gd:43-46).
     - Suspects: the "subdivision" profile (construction.gd:102-109 sends flatbeds with a bulldozer, sewer pipe and water main), and sites saved before #529 that still hold old trips or parked flatbeds.
     - The flatbed model always draws steel coils (vehicle_models.gd `_trailer_flat`), whatever the cargo.
     - Reproduce in Nathan's real save, or a town grown with the zone tool (PerfTown showed no construction trucks), before changing anything.
     - Checked on 2026-10-25 in the playtester's saved town on today's code: the only construction trips were crew pickups, with no flatbeds. Likely an old-version region or a shop's steel flatbed. Ask Nathan for a screenshot if he sees it again.
  3. "at some distances, the ground looks correct. at closer distances, there is a very clear lined pattern on it." Later: "The lines only happened in grass. Or Fields." In fields this may be the crop rows (crop_calendar.gd crop_look: 30 in rows, shown when a row spans over about 3 px); check whether they are too sharp. Grass should have no rows (rowed=0), so grass lines are a separate bug. A 60 m desktop shot of town lawns looked clean; ask for a screenshot and check the browser renderer. The near-ground grass texture or detail tiling. #548 fixed the shadow stripes, so this is a different cause. Compare TerrainView's near LOD shader and grass detail at 40–100 m.

- Hubs boxed in by roads (Nathan, 2026-10-25): "when a hub with leader is 'trapped' inside a road area, it should nicely fill in that area up to the edge (sidewalk) so that it looks like its using its space well." Landfills, recycling and cemeteries: #589. Next, by ease: post office, then parks, banks, campuses, the phone company, factories and warehouses (lawn, parking or grounds only), hospitals, farms last.
- Levels, next steps (spec: docs/spec-building-levels.md):
  - Live: the panel shows Level 1-100 (stage milestones plus needs met), and arrows on stage changes.
  - Next: needs actually drive level up and down in the sim, with hysteresis.
  - Then small visual signs between milestones in house_builder (owner_care exists): yard extras by level (flowers, fence, swing set, deck, a pool around 60), paint freshness, porch lights, and decline signs.

- **Ready-made people on the desktop (Nathan chose yes, 2026-10-25):** docs/spec-ready-made-people.md. Next: fix the generator (arm pose, outfits by gender, proxy body, smaller textures), then walking baked into a vertex animation texture, then the desktop art pack.

*Waits for Nathan*
30. The real Grant County map from public data (big downloads; OpenStreetMap credit line).
31. Measuring on the Mac mini and Mac Studio themselves.

## Results so far

- `docs/scale-test-2026-10-25.md`: the measurements and the plan.
- `docs/look-check.md` (PR #547): the playtester's ranked list of what looks wrong. Re-run the playtester after each visible merge.
