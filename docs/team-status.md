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

**Live:** #527 land preload, #528-#530 construction trucks and the builder's yard, #535, #537 crop calendar, #541 daylight, #542 trees, #544 town speed, #545 farm freeze, #546 farmsteads, #547 playtest list, #548 ground lines, #550 town life, #553 shared region (the host backs up the region before every update), #554 country road look.

**Ready but waiting:**
- #549 + #551 new building drawing: fix the 8 review findings posted on #551 first.
- #556 roads age: profile in real Chrome first (browser 300 m frame 9.1-9.4 ms vs 6.5-9.0 ms).
- #555 automatic quality: the review fixes are partly done on `wip/auto-quality-fixes`. Finish those, then merge. It's the fix for the browser always starting on Low.
- #552 home screen: Nathan chose the new one, live. The rest is on `wip/home-screen-live`: Marion's real time and season, traffic and people by the hour, night lights, a slow 360° orbit and a fuller downtown. Weather comes later, with a hook left for it.

**Started, saved on branches:**
- `wip/green-light-flow`: drivers hesitate at green lights, so only 3 cars get through a green. The target is 1 car every 2 s per lane. Comes before the traffic control spec.
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

*Waits for Nathan*
30. The real Grant County map from public data (big downloads; OpenStreetMap credit line).
31. Measuring on the Mac mini and Mac Studio themselves.

## Results so far

- `docs/scale-test-2026-10-25.md`: the measurements and the plan.
- `docs/look-check.md` (PR #547): the playtester's ranked list of what looks wrong. Re-run the playtester after each visible merge.
