# Team status (start here)

Updated 2026-10-25 by the coordinating session ("Desktop photoreal handoff"). This file is the state, not a diary: rewrite it at each stop.

## Standing orders from Nathan (2026-10-25)

- "i want you to begin the work and continue without asking me anything. i wont be here to approve so i dont want you to stop."
- Merge to main when each step is verified, meaning every web-preview test passes and a second reviewer has checked the diff. Then confirm the web and desktop builds finish before calling anything live.
- What the game is and how it runs never change. What it does and how it looks are sliders on one performance budget (see `docs/desktop-photoreal-handoff.md`). Every feature and every detail is priced in measured ms and memory, next to what it adds. Costly, low-value things go to Nathan, not cut silently.
- **Neighbor towns are a living picture (Nathan chose A, 2026-10-25).** In a shared region, your game no longer keeps every neighbor's whole town (about 1 GB each). It shows their buildings, roads, night lights and some traffic, updated about once a minute, and fills in full detail only when you fly over to look. This is the price list's item #1: it's what lets browser players and 8+ players share a region.
- Still waits for Nathan: anything touching sign-in, paid services, data loss, big downloads (the real county map data and its OpenStreetMap credit line), or deleting things.

## Waiting on Nathan

When a helper hits a wall it writes its question here and stops. That task waits, and the next task in the queue starts. Answer any time; the task picks up from the answer.

- **Day and night off (from the daylight work, PR #541):** when the day-and-night cycle is turned off, should the game show a real summer moment (for example June 21 at 1:40 pm), or keep today's tuned sun from the southwest, which a real summer day never has? Until you answer, it keeps today's look.

## Where everything stands (end of 2026-10-25)

Nothing is running. Every unfinished piece is saved on a branch. To restart one, read its diff against main first; the PR or branch says what's left.

**Also merged tonight:** #563 dirt farm lanes, #564 farms grow half as fast, #565 levels, needs panel, level arrows, lanes dirt to stone to paved, #566 levels 1-100. Earlier: #557 green lights (8 to 12 cars a green), #558 real signal heads, #559 people of different sizes and colours, #560 fewer walkers, #561 county roads to the horizon draw solid (Nathan's grey dashed line), #562 walkers step to their own stride.

**Live:** #527 land preload, #528-#530 construction trucks and the builder's yard, #535, #537 crop calendar, #541 daylight, #542 trees, #544 town speed, #545 farm freeze, #546 farmsteads, #547 playtest list, #548 ground lines, #550 town life, #553 shared region (the host backs up the region before every update), #554 country road look.

**Ready but waiting:**
- #549 + #551 new building drawing: fix the 8 review findings posted on #551 first.
- #556 roads age: profile in real Chrome first (browser 300 m frame 9.1-9.4 ms vs 6.5-9.0 ms).
- #555 automatic quality: the review fixes are partly done on `wip/auto-quality-fixes`. Finish those, then merge. It's the fix for the browser always starting on Low.
- #552 home screen: Nathan chose the new one, live. The rest is on `wip/home-screen-live`: Marion's real time and season, traffic and people by the hour, night lights, a slow 360° orbit and a fuller downtown. Weather comes later, with a hook left for it.

**Started, saved on branches:**
- `wip/green-light-flow` **(Nathan: "the traffic is so slow it makes the game unplayable"; do this first)**. tests/test_green_light.gd on that branch measures it. On main today:
  - green: 3.9 s between cars crossing the line, 8 per 30 s (target 2 s, 12+), the first car starts at once, nobody stops at the line
  - all-way stop: 6.9 s a car (target 4-5)
  - cars stop 7.9 m behind the line where a street meets the highway

  Ruled out: HEADWAY 1.4 to 1.0 barely helps (3.6 s), and the "room on the far side" rule in `_may_enter` makes no difference. The likely cause is queue discharge in the car-following model (`_idm`, traffic_sim.gd about :4292, acc about 2 m/s^2 from vehicle_types.gd): cars pull away one by one. Look at start-up anticipation, so cars begin moving as the car ahead does, or an IIDM/ACC-style model, plus the per-turn speed cap at :4337.
- `wip/detail-floor`: a closest zoom per quality tier, set by screenshot judging and enforced with a test. Nathan: "impossible to see poorly drawn things up close".
- `wip/load-until-drawn`: the loading screen holds until the starting view is drawn (cap 20 s desktop, 30 s browser).
- `wip/admin-audio`: Nathan's admin sound mixer. Desktop only, behind a hidden key combo. One row per sound, voice caps, and "Save for everyone" to data/audio_mix.json.
- `wip/price-list` and `wip/browser-measure`: paused.

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
- Home screen weather: "instead of just time and day and season you include the weather." The game draws no weather yet, so build overcast skies, rain, snow and fog (these serve the game too), then feed in Marion's live conditions from the National Weather Service (api.weather.gov: free, no key, official; falls back to clear when offline). Only Marion's fixed location is sent, never the player's. Must have a simple on/off switch in settings, like day and night (Nathan, 2026-10-25: "will it be easy to turn off with a simple toggle switch still?"); off means always clear.
- Traffic: a 2,700-person town growing along the highway drops to about 45% flow; queues back up at the all-way stops where highway streets enter the grid.

- Traffic control that grows with the town: `docs/spec-traffic-control.md` (Nathan, 2026-10-25). Starts after the green-light fix: own light timing, then green waves, sensors, and a Traffic Management Center or a university engineering wing. Design rule for the whole game: "Early on the traffic issues are mine to deal with because they are simple. Later in the game, they become more complicated and so we provide more sophisticated solutions, just like in real life."

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

- Hubs boxed in by roads (Nathan, 2026-10-25): "when a hub with leader is 'trapped' inside a road area, it should nicely fill in that area up to the edge (sidewalk) so that it looks like its using its space well." Each hub kind keeps its own land: healthcare.gd (a rect in the hub's street frame: x0, x1, depth; `boxed`), plus mail, telecom, warehouses and civic_hubs (grid cells; `boxed` when `_best_piece` finds none). When boxed by roads, not by homes, extend the grounds (lawn, parking, landscaping) to the surrounding road edges. Never take land a lot stands on. Test with a hospital in a block enclosed by four streets.
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
