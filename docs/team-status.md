# Team status (start here)

Updated 2026-10-26 (night) by the month-is-a-day session. This file is the state, not a diary: rewrite it at each stop.

## Look loop (2026-10-29 to 10-31, desktop first)

Nathan: "lets make this game look totally real. better than CS2." On 2026-10-30: "keep running the critic through the game to find them least realistic thing and fix it and keep looping." On 2026-10-31: "Stop asking about trees growing... Make smart choices."

**How it runs:** `tools/look_round.gd` shoots the same 10 spots at Cinematic and Medium. A critic scores 1-10 against real Indiana towns and CS2; builders take the worst gap. Each fix: all web-preview tests pass locally, a second reviewer reads the diff, before/after shots, ms cost, and game-day numbers for any sim change. Scores: round 0 3.55, round 1 3.62, **round 3 4.02** (2026-10-30, on feaacfad). Vehicles and people are still the weakest (2.0).

**Rules learned:**
- Godot windows are OK during the loop (Nathan, 2026-10-30: "A"), one at a time.
- Every saved town is test data; old towns moved to `Neighbors-old-towns-2026-10-29/`. Loads must not crash; no rescue code.
- Decide look choices (tree ages, colours, timings) without asking; ask only the stop-list items.

**Merged 2026-10-29 to 10-31:** #920 shot tool; #917 #918 #919 #924 road options; #925 tree greens; #926 dusk and night; #923 cars on drives; #927 garage doors; #936 sky-lit shade; #935 yard trees grown; #929 lawns; #930 wet roads, streetlight pools; #931 junctions vary; #932 tree shadows; #938 state layer step 1; #937 dock doors; #939 All roads screen; #940 overlap auditor; #944 curb claims; #943 rail first; #942 road treatments step 1 (main streets 25 mph, Nathan: A); #945 #947 #951 ground map steps 1-3 (Ground view: press O; lot-on-lot 31 -> 3); #946 doors step 3 (factory, shop, police, bus and barn doors; factory trucks wait 8 s, Nathan: A); #948 weathered sidewalks and wet rain shot; #949 drive concrete matches the walk; #950 street trees grown (canopy at 300 m 4.0% -> 5.9%); #952 shop lots fill by the hour.

**Specs (docs only, drafts):** #921 state layer, #922 working doors, #934 road treatments, #941 ground map.

**Next, most useful first:**
- Ground map step 4 (who gives way: move, shrink, remove through one path with undo) and step 5 (bus stops claim the curb). 46 factory buildings in the big town still stand partly on a neighbour's lot (audit pair "building vs lot").
- The 400-car traffic cap keeps people from work (887 vs 1,220 at work when raised to 1,600, but sim cost doubles). Needs a cheaper traffic model before the cap can rise.
- Critic round 4 to score the last five merges; the rain shot now shows wet roads, so 08 will jump.
- Canopy is still about 6% at 300 m (a real town is 25-33%): shop streets plant no trees, and there is no small street-tree kind for under wires.
- Teal juniper mounds in run-down yards (`HouseBuilder._back_yard`, owned by the art session).
- State layer step 2 (street condition); snow blotches; pavement all one age.

**Still open, Nathan said later:** #915 test PIN for playtests.
## Standing orders from Nathan (2026-10-25)

- "i want you to begin the work and continue without asking me anything. i wont be here to approve so i dont want you to stop."
- Merge to main when each step is verified, meaning every web-preview test passes and a second reviewer has checked the diff. Then confirm the web and desktop builds finish before calling anything live.
- What the game is and how it runs never change. What it does and how it looks are sliders on one performance budget (see `docs/desktop-photoreal-handoff.md`). Every feature and every detail is priced in measured ms and memory, next to what it adds. Costly, low-value things go to Nathan, not cut silently.
- **Neighbor towns are a living picture (Nathan chose A, 2026-10-25).** In a shared region, your game no longer keeps every neighbor's whole town (about 1 GB each). It shows their buildings, roads, night lights and some traffic, updated about once a minute, and fills in full detail only when you fly over to look. This is the price list's item #1: it's what lets browser players and 8+ players share a region.
- Still waits for Nathan: anything touching sign-in, paid services, data loss, big downloads (the real county map data and its OpenStreetMap credit line), or deleting things.

## Waiting on Nathan

When a helper hits a wall it writes its question here and stops. That task waits, and the next task in the queue starts. Answer any time; the task picks up from the answer.

- **Month is a day, the pace calendar (from the second review of #619):** the county fair, banks' new year and trails run on the old pace calendar (a "year" is about 29 minutes). So a fair's "July" can land in calendar winter, under snow. Festival asks follow the calendar, so they only come in September and October. "Since 2027" signs read 2027 for the town's whole first calendar year. Should fairs and festivals follow the calendar's real months instead? Until you answer, it stays as built.
- **Day and night off (from the daylight work, PR #541):** when the day-and-night cycle is turned off, should the game show a real summer moment (for example June 21 at 1:40 pm), or keep today's tuned sun from the southwest, which a real summer day never has? Until you answer, it keeps today's look.

## Critic and fixer loop (2026-10-27)

Nathan: "send an agent to play the game ... take a screenshot of errors or the "worst thing it sees" ... give that error to an agent to fix ... only run two of these at the same time ... stop when i reach 23% of my weekly tokens." Each fix had a second reviewer before it merged. The critic's playtests and drivers are in the session scratchpad (`loop/critic1-3`).

**Merged:**
- #622 a new town opens at mid-morning on May 7, not a dark dawn
- #623, #625, #627 a saved and reloaded town parks its cars exactly like the live one: curb spaces, dropped trips, cars of people who left town; two cars no longer back out of one drive at once
- #624, #626 drawing a street over the same street no longer secretly cuts it (thousands of errors), and any road cut now refreshes lots
- #628 hover cards stay off the toolbar and panels; a/an, plurals and capitals fixed in tooltips
- #629 undo brings back what a new road bulldozed (a water tower, farm, company, park), its family and its money

**Found, not fixed yet (most serious first):**
- Undo doesn't bring back zoned homes and shops a road ran through, nor rail lines, bank loans, leader asks or markers (#629 notes).
- Console error flood with a mini roundabout built after a normal one (road_view.gd `_build_roundabouts`, `_add_ring` apron has no UV; repro `loop/critic3/mini_repro.gd`).
- Traffic jams at T-junction stop signs, and a left turn that blocks a one-lane highway (traffic_sim.gd `_may_enter`).
- A school won't fit in the game's own 120 m blocks (services.gd SCHOOL 80x100, `site_problem`).
- White wind arrows show when the plain Homes zone is picked (placement_hints.gd).
- A gap in the Economy panel; a hard-edged green rectangle under the town at about 1 km.
- Words: "Town age 0 years, 1 months"; a county road named "West North 00 S"; heritage.gd "a row homes".
- No redo (Ctrl+Shift+Z does nothing).

## Where everything stands (2026-10-26, night)

**Merged 2026-10-26, night:**
- #619 A month is a day (`docs/spec-month-is-a-day.md`). The sky runs one day and night per calendar month: a 50-minute day, then a 10-minute night. The top bar shows weekday, month and year. There's one speed plus Pause. Money and timers read in days, and `tests/test_month_words.gd` catches leftover "month" words. Old towns keep their past dates (save keys `calendar`, `calendar_from`). There were two second reviews, and all medium-or-worse findings were fixed. Named corners:
  - No leap years.
  - The pace calendar runs fairs, the census and families (see Waiting on Nathan).
  - School buses and weekends use the sim clock's weekday, so the top bar can say "Sat" while school buses run.
  - The clock hour jumps at dawn on March 1 and November 1.
  - The Day and night switch is now on for everyone.
- #614 grown trees' shadows cost a third: 26M to 11M triangles from the street on Cinematic.
- #618 Roads, step 1 of 6: a big one-way boulevard, plus the CS2 road options chart (`docs/road-options.md`). Steps 2-6 (car-free street, turn bans, S-curve, snapping switches, removing a crosswalk) are built and reviewed on the road session's branches. **Next session (Nathan, 2026-10-27): "Yes. Next session, run the full tests, web build and last review, then merge the five road options in order."** The branches, in order, each built on the one before: `road-scurve`, `road-snap`, `road-carfree`, `road-turnbans2`, `road-crosswalks2` (pictures in `docs/road-options/`). The last review round was cut off, so run it again on the final code. Small follow-ups:
  - A car-free street cut in two counts as two plazas.
  - Curb ramps stay after a crosswalk is removed.
  - A thin blue strip shows along some curbs up close (it was already in the game).

**Walkers (the question below) may be settled by #619:** a sky hour is now about a minute, not 6 seconds, so a 150 m walk lasts about 2 sky hours on screen, not 19. Not checked in the game yet. Look before asking Nathan again.

## Earlier (2026-10-26, evening)

**Admin (Nathan, 2026-10-26):** a crown button in the top bar, seen only by the host, opens Admin: people waiting to join, every player and their PIN, and the Sound mixer (desktop app; Cmd/Ctrl+Shift+F12 still opens it). New admin tools go in as sections of `scripts/ui/admin_panel.gd`. No sign-in: the region server decides who is host and refuses host actions from anyone else (#615).

**Merged 2026-10-26, afternoon and evening:**
- #615 Admin button for the host (players and PINs, Sound mixer)
- #613 fuller towns: parkway street trees, nursery-size yard trees, a real roof mix
- #612 home screen opens at once (a still of the town, then the live town a piece a frame)
- #609 trees drawn out to the horizon, handed over where they stand (Nathan: no blank spaces, no trees swelling up, no flutter)
- #605 green lights: queues pull away about 2 s a car (test_green_light.gd is now in CI)
- #606, #607 UI critique fixes and building icons in one bold line style
- #602, #603 far buildings no longer blink out; neighbor building squares sit on their ground
- #604, #608 boxed-in park, bank, campus and phone company fill their blocks
- #610 money keeps to the dollar across a save; #611 critic's small fixes (fair first day, fewer grey days, green Novembers)
- #600 ambient life: snowmen, sledding, lemonade, bikes, hoops, yard sales, costumes

**Merged 2026-10-26, morning:**
- #583-#585, #592, #599 traffic control, all four stages: your own light timing, green waves, smart lights, and engineers who retime the lights. The engineers come with a Traffic Management Center (unlocked with the city charter) or a university's Transportation research center.
- #587, #595, #598 weather: overcast, rain, winter snow and morning fog by Indiana's odds, with an on/off switch. The home screen shows Marion's real weather from the National Weather Service (KMZZ).
- #588 houses vary their distance from the curb; a car's stop saves the same before and after loading
- #590 cars stop at the stop line, not 2.5 m short of it
- #589, #594 boxed-in landfills, recycling, cemeteries and post offices fill their block to the sidewalk
- #593 levels follow needs: a building moves up only with half its needs met, and drops a level after two days without power or water
- #596 people get the car they should have (those who moved in before their drive was built never got one); #597 fewer short walks (1 in 8 in a small town)
- #586 builders and recess; (next) snowmen, sledding, lemonade, bikes, hoops, yard sales and costumes

**For Nathan to decide:** the streets still look busy with walkers. The real reason is time: a game hour is about 6 seconds of traffic, so a 150 m walk lasts about 19 game hours on screen. Options: make walkers stride faster than real (a time-lapse look), make fewer short trips, or accept it.

**Known gaps:** family rides for children were tried and dropped (bugs found in review; little effect). At phone width the top bar clips its right end, so Help and the Admin crown can be cut off.

**Earlier (2026-10-25/26):** #567 cars drive the limit, #568 roundabouts as a whole, #569-#578 people (skins, figures, five detail levels, ready-made desktop people), #579 faster four-way stops, #580 load until drawn, #581 admin sound mixer, #582 detail floor, #552 live home screen, #555 automatic quality, #551 new building drawing (minor items listed on #551), #557-#566 green lights, signal heads, people sizes, fewer walkers, solid county roads, strides, dirt farm lanes, slower farms, levels 1-100.

**Ready but waiting:**
- #556 roads age: profile in real Chrome first.
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
