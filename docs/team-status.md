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

## Working now (end of 2026-10-25; tokens nearly used for the week)

Unfinished work is always saved on a branch. A new session restarts a helper from its branch (read its diff first).

| Work | Branch | State |
| --- | --- | --- |
| New building drawing in the game (the biggest visible change) | `claude/building-drawing` (WIP also on `wip/building-drawing`) | Running. Houses first, then shops, civic, factories |
| Nathan's road list + power lines, then roads age | `claude/road-look-fixes`, then `claude/roads-age` (`wip/roads-age`) | Running. Playtest items 1-6, 10, 11 |
| Automatic quality (browser picked Low on a fast Mac) | `claude/auto-quality` (`wip/auto-quality`) | Running |
| Town life: jammed white trucks, alert-icon smear, walkers on lawns, a walking-code error | `claude/town-life-fixes` | Running |
| Region under load (city-line freezes, welcome too big, server stalls) | `claude/region-load-fixes` | Running. Welcome uses a light neighbor form for choice A |
| Farmsteads | PR #546 | Live once the build finishes |
| The price list (cost of each feature) | `wip/price-list` | Paused to save tokens |
| Browser measured | `wip/browser-measure` | Paused to save tokens |
| Playtest look check | PR #547 (`docs/look-check.md`) | Done; findings handed out |

Live on 2026-10-25: #527 land preload, #528-#530 construction trucks and the builder's yard, #535 region play-through, #537 crop calendar, #541 daylight, #545 farm field freeze, #542 trees that grow, #544 town speed (about 2x), #548 ground lines, #546 farmsteads, #547 playtest list.

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

*Waits for Nathan*
30. The real Grant County map from public data (big downloads; OpenStreetMap credit line).
31. Measuring on the Mac mini and Mac Studio themselves.

## Results so far

- `docs/scale-test-2026-10-25.md`: the measurements and the plan.
- `docs/look-check.md` (PR #547): the playtester's ranked list of what looks wrong. Re-run the playtester after each visible merge.
