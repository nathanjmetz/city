# Scale test and the plan forward (2026-10-25)

Measured on the M5 Max MacBook Pro (48 GB). Weaker machines (the 8 GB Mac mini, the browser on an ordinary laptop) will be slower. Those numbers are estimates until they are measured there.

Nathan's goal, in his words: "a visually stunning game that automatically scales with browser or desktop capacity and scales with different variations of a desktop capacity". The city can reach 250,000 people, and the largest gathering is 100,000 ("There will never be a gathering more than 100,000 people").

## What we measured

### The town's thinking (headless, no drawing)

| Town | People | Buildings | Per game step | Worst single step | Memory | Time to build |
| --- | --- | --- | --- | --- | --- | --- |
| 12 blocks | 5,300 | 2,800 | 3.7 ms | 0.2 s | 0.4 GB | 10 s |
| 20 blocks | 16,400 | 7,700 | 11.3 ms | 0.7 s | 0.6 GB | 41 s |
| 30 blocks | 38,400 | 16,800 | 18.4 ms | 1.3 s | 1.1 GB | 2 min |
| 40 blocks | 68,800 | 29,600 | 36 ms | 3.0 s | 1.8 GB | 6 min |
| 50 blocks | ~100,000 | | | | | over 40 min (gave up) |

The game runs 10 steps a second at normal speed. At this rate, 250,000 people would need about 150 ms a step and about 6 GB of memory. That's too slow to play even here, and too big for a browser. The worst single steps, which show up as freezes, grow fastest of all. Most of the time goes to re-checking every lot (`sim.lots.revalidate`), people's plans (`sim.people`) and the town's statistics (`sim.stats`).

### Drawing a crowd

A stadium bowl of fans, each dressed differently, as simple stand-in figures:

| Fans | Desktop renderer | Browser renderer |
| --- | --- | --- |
| 100,000 | 4 to 5 ms a frame | 6 to 8 ms a frame |
| 200,000 | 10 ms | 13 to 15 ms |
| 400,000 | 17 to 20 ms | 24 to 27 ms |

Drawing 100,000 people is affordable. These were plain stand-ins, though: real fans need varied poses, groups, movement and reactions, and the field needs players, lights, cheerleaders and camera crews. That costs more, and only near the camera.

### Everything at once: a real game window

A 16,000-person town, running, drawn in a real game window:

| | Frame time | Frames a second |
| --- | --- | --- |
| Town, normal speed | 58 ms | 17 |
| Town, fast speed | 117 ms | 8.5 |
| Town plus a 100,000-fan stadium | 64 ms | 16 |
| Diving from 3 km to 40 m | 74 ms, 470 of 600 frames stuttered (over 50 ms) | |
| Sweeping across town at 40 m | 48 ms, 369 of 1,200 frames stuttered | |

Of a 58 ms frame, the game's own measured parts add up to about 18 ms (buildings 11.5, the town's thinking 3.2, cars 2.4, land 1.3). The other ~40 ms is the graphics card. Graphics memory used: 6.4 to 6.7 GB. That alone would not fit on an 8 GB Mac mini.

**Which drawing these numbers describe (Nathan's catch):** the town's frame times, graphics memory and stutters come from today's drawing, not the new style. They show what the new style has to beat, not what it will cost. The town's thinking (the step times and freezes) doesn't depend on drawing, so those numbers stand. The crowd test already drew people the new way. Next: a 16,000-person town drawn the new way (simple shapes far, lighter middle, brick-level detail within about 100 m), measured the same way.

**Bottom line:** drawing a crowd is easy. Today's town is the problem. It thinks too slowly at size, it draws too much, it uses far too much graphics memory, and it stutters when you move. These have to be fixed before stunning detail, or the detail will make it worse.

## How the game should be built (the rules every piece follows)

1. **Store small facts.** A tree is its kind, a seed and the date it was planted. A person is age, job, income and tastes. A patch of grass is how often it's walked on. A building is its outline, height, roof, age and material. All of it is saved, and it's the same for every player in a region.
2. **Grow what you see from the facts, by rules from real life.** Real measurements (brick 7⅝ × 2¼ in, lane 12 ft) and real behavior (freeze-thaw potholes, how trees branch). Each grower is checked against real photos until it passes, with tests that hold it there (the thrive tree method).
3. **Detail by distance.** Full detail within about 100 m of the camera, a lighter version grown from the same facts farther out, and plain shapes or numbers beyond. The camera's distance and the machine's strength decide which, automatically. Detail fades in, never pops.
4. **Think by distance too.** People and cars near the camera are individuals; far ones are counts and flows. Slow things (seasons, tree growth, wear) update once a day, not every step.
5. **One game, scaled to the machine.** The browser and the desktop share the facts and the rules. Each machine gets the most detail it can carry smoothly, adjusted as you play. Nobody picks settings.
6. **Never a freeze.** Big work (a new highway, an autosave, a flood) is spread over many frames.

## The work, split for a team

Each piece runs in its own session, on its own branch, owning its own files, so nobody overwrites anyone. Claude coordinates: briefs, checks results against tests and a second reviewer, merges in order, and confirms what's live.

**First wave:**

| # | Piece | Owns | Done when |
| --- | --- | --- | --- |
| A | Town speed | `scripts/sim/` (except construction and builders), `scripts/traffic/traffic_sim.gd` | A 69,000-person town under 15 ms a step, with no single step over 100 ms. Town builds in under a minute. |
| B | Drawing speed and automatic quality | `scripts/buildings/building_view.gd`, `scripts/shell/quality.gd`, vehicle drawing | The 16,000 town at 60 fps here at normal speed, under 2 GB of graphics memory, no stutters over 50 ms while sweeping. Quality levels set for the browser, the Mac mini and the Mac Studio. |
| C | The detail framework and houses grown in code | new `scripts/detail/`, `scripts/art/` | Near-camera detail swaps in and out by distance. Brick, siding and roofs grown at real size, checked against real photos. |
| D | Trees that grow | `scripts/buildings/wild_view.gd`, tree code | Trees grown from kind, seed and age (as the thrive oak), seen growing over the years, with cheap stand-ins far away. |
| E | Ground wear and desire paths | `scripts/terrain/`, walker footsteps | Grass wears to dirt where people walk most, in both versions. |
| F | Shared region fix | region and session code | The automated shared-region play-through passes. |

**Later waves:** people and crowds (varied clothes, real fan behavior, players, lights, cheerleaders, camera crews); closer zoom in steps (40 m to 20 m to 10 m to eye level), after the detail exists; the real Grant County map from public data (needs Nathan's OK on the downloads and the OpenStreetMap credit line); and the 713 ideas in `docs/real-life-details.md`, built a few at a time for Nathan to discover.

**Budget:** each helper uses tokens quickly. Start with six, add more as they finish, and stop starting new work when about 5% of the week's budget is left.

## Shared region under load

Measured 2026-10-25 on the same M5 Max MacBook Pro (48 GB), with other helpers' programs running at the same time (the machine's load average was 6 to 20 throughout, on 18 cores). The bots, the region server and the measuring tools all ran on this one machine, so the network between them cost no time. The bots ran without a window (no drawing), so every freeze below is the game's own thinking and networking; a real window would only add to it. Tools: `tools/scale/region_stress.sh` (with `region_stress_region.gd`, `_proxy.py`, `_probe.py`, `_monitor.py`, `_report.py`) plus `region_stress_welcome.gd` and `region_stress_lines.gd` for two separate measurements. The numbers are kept in `tools/scale/results/region-stress-2026-10-25/`.

**The test:** each bot is a player (the `tools/playtest` bot, at top speed, adding a street a minute) who joins a region with a PIN and already owns a big town built by `PerfTown`. A counting go-between sat between every bot and the server and wrote down bytes and message times. A separate probe asked the server a harmless question every 2 seconds. Three runs: 4 players with 20-block towns (about 16,000 people each when made), 20 minutes, plus two late joiners; 8 players with 16-block towns (about 10,000 each), 15 minutes of play, plus two late joiners; and 8 players with 20-block towns, which could not start.

### What broke first, in order

1. **Eight 16,000-person towns can't join at all.** The "welcome" the server sends a player (their own town in full, every neighbor as a small copy) was 17.3 MB for eight towns; the server's message buffer is 16.8 MB. The send fails (server log: `ERR_OUT_OF_MEMORY` from `_send` in `region_server.gd`), nothing tells the player, and their game sits on the loading screen. All eight bots gave up after 300 seconds. With towns this size about seven players fit; each extra player adds about 1.7 MB, and each town grows with its people. With four players the welcome was 10.1 MB, which is fine.
2. **Every player's game freezes in the city-line drawing.** That's the cream dashed line between neighbors (`scripts/net/city_lines.gd`). It redraws on the main thread whenever any neighbor changes (at most every 15 seconds) and checks every pair of towns against every other town. Timed on its own on the 4-player region: two towns 0.09 s, three towns 0.34 s, four towns 14 s (and it found no line to draw). In the live runs, frames that froze in it added up to 43% of the 4-player run time (547 s of 1,278 s, single freezes up to 107 s) and 96% of the 8-player run (985 s of 1,028 s, single freezes of 4 minutes). With 8 players the median frame was 280 ms and every bot had 28 to 35 freezes over a second. Even a new player with a tiny town froze for 62 to 260 seconds because of their big neighbors. This is the first thing to fix. It is game code, so I did not touch it.
3. **The server stalls for about a second every 10 seconds, and for 5 to 8 seconds when a brand-new player first joins.** The save writes the whole region as text every 10 seconds, on the same thread that answers players (the saved file was 90 to 108 MB). The probe's median answer time was 13 ms, but the slowest 5% took 0.7 s (4 players) to 1.1 s (8 players), and the worst were 7.6 s and 5.3 s. The worst ones line up with a new player joining. From reading the code, the likely cause is that making a town first makes the server unpack every neighbor's town (`Region.add_city` calls `load_stale`). The new player waited 5 to 8 seconds for their welcome; an existing player coming back waited 0.3 to 1.3 s. Nobody was disconnected, so the stalls were short enough to survive, but each is a pause in everyone's sync.
4. **Neighbors' towns reach screens late.** On the wire, the median delay from a player's update going in to a neighbor's copy coming out was 0.15 s with 4 players (95% under 5.9 s). With 8 players it was 48 s, because the receiving games were frozen in the city-line drawing and not reading their connections (worst: 4 minutes). On top of that, a game turns a neighbor's new copy into a drawn town for only one neighbor per 60 seconds (`NEIGHBOR_EVERY`), so with 7 neighbors a town can be shown up to 7 minutes behind, by design. At the end of the runs the neighbors' towns on screen were behind their owners by 23 buildings on average (4 players) and 258 (8 players).

Not seen: no player was dropped or had to reconnect in any run, and the server's CPU never stayed busy (below).

### The numbers

| | 4 players, 20-block towns | 8 players, 16-block towns |
| --- | --- | --- |
| Server CPU, one core = 100 | mean 9, over 90 for 14 s in all | mean 9, over 90 for 14 s in all |
| Server memory | 2.9 GB loaded, 3.9 GB peak, 2.6 GB at end | 3.9 GB loaded, 6.7 GB peak, 2.7 GB at end |
| Server answer time (median / 95% / worst) | 13 ms / 0.7 s / 7.6 s | 13 ms / 1.1 s / 5.3 s |
| Into the server, per second (steady / peak) | 198 KB / 5.4 MB | 88 KB / 3.8 MB |
| Out of the server, per second (steady / peak) | 505 KB / 26.9 MB | 480 KB / 16.1 MB |
| Per player, up / down (steady) | 50 KB / 111 KB | 10 KB / 52 KB |
| Whole run, in / out | 281 MB / 728 MB | 158 MB / 869 MB |
| Welcome a joiner is sent | 10 MB | 12 MB |
| Late joiner with a new town: welcome wait / game's load time | 6 to 8 s / 14 to 16 s | 5 s / 13 s |
| Player coming back with a big town: welcome wait / load time | 0.3 to 1.3 s / 24 to 31 s | 0.4 to 0.5 s / 24 to 31 s |
| Each bot's frame time: median / worst | 220 to 250 ms / 107 to 131 s | 280 to 340 ms / 244 to 256 s |
| Each bot's freezes over 1 s | 85 to 92 | 28 to 35 |
| Each bot's memory (resident) | 4.5 to 5.0 GB | 3.5 to 4.3 GB |
| Reconnects or failures | none | none |

Bytes in the 8-player run look lighter than they should, because the frozen games hardly sent anything; the 4-player run is the better picture of the traffic. A player sends a small copy of their town every 20 to 120 seconds, one copy of a 16,000-person town is 1.6 MB packed, and the server sends it to every other player. If it goes every 20 seconds, that is 80 KB a second per neighbor. This is an estimate from the code, not a measurement: 10 such players would be about 7 MB a second out of the server, and 20 players about 30 MB a second (240 megabits), far past a home internet upload. The measured rates are lower because towns did not always change in a way that made the game send.

The bots' towns lost most of their people during the runs (from about 16,000 to between 4,500 and 6,200 in the 4-player run, from about 10,000 to about 900 in the 8-player run), while buildings stayed or grew (about 8,300 and 5,300). I did not look into why; it may be the seeded towns, the long freezes, or the town's thinking. Frame times with a window will be worse than these.

### The biggest risks, in plain words

1. **A region of four or more players with grown towns would be unplayable on the first day**, because of the city-line drawing alone. Two towns are fine; four already freeze for seconds to minutes. Fix this before anything else in the region, for example by tracing one pair of towns at a time over many frames and only when a town's edge really moved.
2. **A busy region can lock new players out without telling them.** The welcome has a fixed size limit, and when it is passed the player waits on the loading screen forever. It needs a smaller welcome (own town in full, neighbors in a lighter form or one at a time) and a clear message when sending fails.
3. **The server does the save, the unpacking and the sending on one thread.** A 5-second stall for a new player is survivable now, but it grows with every town. The save should be written in pieces or off the main thread, and the first-join unpacking spread out.
4. **Memory is too big for a browser and for a small host.** Each player's game held 3.5 to 5 GB with three to seven big neighbors (about 1 GB a neighbor, close to the 0.6 GB a 16,000-person town took alone plus its copies). The server held 3 to 7 GB for four to eight towns. A browser tab (roughly 4 GB at most) and a small cloud server (1 to 2 GB) can't carry this. Neighbors need to be held as light pictures, not running towns, unless the player is looking at them.
5. **Traffic grows with the square of the number of players.** Everyone's update goes to everyone. That is fine for 4 to 8 players on a home connection and not for 20.
6. **Neighbors' towns show on screen minutes behind, by design** (one neighbor refreshed a minute). Not a break, but a player will see a neighbor's new street long after it was built.

### What this test did not cover

- No window, so no drawing cost or graphics memory. Real players will freeze more, not less.
- The towns were made by the test builder, not played; the bots then added a street a minute. Real players edit more, in bigger bursts.
- The server and all the players shared one machine that other programs were also using. The server's CPU numbers are low because it mostly waited. Its stalls come from one thread doing too much, so a weaker machine makes them longer.
- Sync lag "on the wire" is when the go-between saw the bytes, which includes time the receiving game was frozen and not reading. The "on screen" figure is only a comparison at the end of each run, not a continuous measurement; the one-neighbor-a-minute rule comes from reading the code, not from a measurement.
- The city-line cost is measured (stage timers in the live runs and a separate timing of that code), but why it jumps from 0.34 s to 14 s at four towns is not explained.
- Why the people in the bots' towns fell so far was not investigated.
- No browser player was in these runs. The tools support one (`tools/playtest/soak.sh` with a web export), but the browser's cost for unpacking a 10 to 12 MB welcome on its one thread was not measured here.

### Questions for Nathan

None. Nothing here touches sign-in, paid services or data; everything ran on this machine.

## The new drawing style, measured

Nathan's catch, in his words: "you can't really measure how the game will perform with your drawing style by looking at the old drawing style." So the same 20-block PerfTown (16,300 people, 7,713 buildings), simulating, was drawn the new way and timed exactly as today's was.

**What was built** (a measuring tool, not a game feature; the game still draws with BuildingView): `tools/scale/new_drawing_lab.gd` and the helpers in `tools/scale/new_drawing/`. The real game runs with its real sim, land, roads, trees, cars and people; only today's BuildingView is taken out.

- **Small facts** (`facts.gd`): each building is its outline, height, roof, age and wall material, laid out on the mason's 16-inch grid, plus rules that place its doors and windows.
- **Far** (everywhere, the only thing past about 300 m): every building is one box and one roof, instanced from its facts (a few draw calls per 256 m square, one shared material), windows painted on.
- **Middle** (about 100 to 300 m): the same boxes pick up real-size brick courses, siding laps and shingle courses in the shader, and real window, door and storefront pieces (instanced) where the facts' rules put them.
- **Near** (within about 100 m): every building grown in code at real size: brick by brick (7⅝ × 2¼ in, ⅜ in joints, mortar set back, beveled and chipped, soldier courses over openings, rowlock sills), or 4-inch vinyl laps with casings and corner boards, or 12-inch metal ribs; double-hung windows, six-panel doors, storefronts; shingle courses 5 inches to the weather with staggered tabs, fascia, soffits and rakes. It is grown a few small jobs a frame (3 ms budget, 2 ms in the browser) from 130 m out, shown inside 90 m with a dithered fade to 110 m, and let go past 160 m. All the bricks are instances of a handful of shared 16-inch masonry cells, so growing a house is filling a few thousand positions, not building geometry.

**How it was measured.** Same machine (M5 Max), same frame windows as `combined_lab.gd` and `zoom_lab.gd`. Both styles ran in the same lab, back to back (the lab's `today` switch keeps BuildingView), with the graphics tier pinned (`--quality high` on the desktop renderer, `low` in the browser's renderer). Pinning matters: the game's automatic quality changes the tier and render scale while it runs, and other helpers' runs on this Mac move it too, so earlier unpinned runs switched between Low and Cinematic. The Mac was shared with other helpers' tests the whole time (load 4 to 20), so expect about 10% wobble: two pinned rounds agreed within 3 ms for the new style and 6 ms for today's.

### Desktop renderer (High tier)

| | Today | New style |
| --- | --- | --- |
| Town at 1x, frame avg / p95 / worst | 56 to 62 / 117 to 133 / 150 ms (16 to 18 fps) | **17 to 20 / 28 to 39 / 145 ms (50 to 57 fps)** |
| Town at 4x, frame avg | 112 to 117 ms | 57 to 67 ms |
| Graphics memory | 6.1 GB (3.1 GB of it mesh buffers) | **1.07 GB** (0.39 GB buffers) |
| Dive 3 km to 40 m: avg, frames over 50 ms (of 600) | 74 to 96 ms, 463 to 528 | **28 ms, 28 to 33** |
| Sweep at 40 m: avg, frames over 50 ms (of 1,200) | 35 to 38 ms, 191 to 231 | **24 to 25 ms, 41 to 45** |
| Triangles drawn: overview / dive / sweep | 4.0 M / 17.8 M / 8.5 M | 3.3 M / 4.3 M / 5.0 M |
| Draw calls: overview / dive / sweep | 3,300 / 16,700 / 5,100 | 1,600 / 6,800 / 3,600 |

The first section's numbers (58 ms, 6.4 to 6.7 GB, 470 and 369 stutters) were taken under automatic quality; the original `combined_lab.gd`, rerun today, gave 57 ms and 6.0 GB.

### Browser renderer (Compatibility, Low tier)

| | Today | New style |
| --- | --- | --- |
| Town at 1x, frame avg / p95 / worst | 26.0 / 47 / 134 ms | 25.6 / 42 / 122 ms |
| Town at 4x, frame avg | 103 ms | 96 ms |
| Graphics memory | 3.2 GB | **0.46 GB** |
| Dive: avg, frames over 50 ms | 43.0 ms, 93 | 42.2 ms, 103 |
| Sweep: avg, frames over 50 ms | 35.3 ms, 106 | 34.8 ms, 103 |

### Where the time goes

- **Desktop, today:** BuildingView itself averages 7 to 35 ms of CPU a frame at 1x (building, merging and swapping meshes) and is the biggest part of every slow frame (33 to 63 ms in each). Up close it sends 17.8 million triangles in 16,700 draw calls.
- **Desktop, new style:** the buildings cost about 0.1 ms of CPU a frame from afar and 0.4 to 1.5 ms while diving or sweeping (growing and releasing). A 17 ms frame is mostly the rest of the game: the town's thinking (about 4 ms), cars and people (about 4 ms), the land (about 4 ms), and drawing (about 6 ms). **Nearly every remaining slow frame is a sim tick** (42 to 109 ms of town thinking in those frames: lots, stats, people), not drawing. Fixing the town's speed (piece A) is now what stands between this and smooth.
- **Memory:** today keeps a full mesh for every building plus merged copies per square. The new style keeps one small instance record per building, and full detail only for the 40 to 60 buildings near the camera.
- **Browser renderer:** at its Low tier, today's drawing is already mostly far boxes, so both styles cost about the same per frame. There the frame is the town's thinking, cars, land, and the driver handing over about 5,600 draw calls in the dive (18 ms of CPU just to submit them). The new style wins on memory (7 times less), not on speed, yet.

### What it costs, and where it is slower

- **Draw calls up close.** Each grown building is 15 to 25 small batches (each brick cell kind, boards, shingles, windows by size, trim). With about 60 grown buildings that is most of the dive's 6,800 draw calls. The desktop shrugs it off; in the browser it is why the new style isn't faster. Next step: merge the near ring's batches by kind across buildings (one brick batch for the whole ring).
- **One long growth job.** Growth is budgeted, but one job is a whole wall, and a big building's wall overran once per dive (15 to 27 ms, one frame). Next step: split walls into rows.
- **Fast sweeps outrun it a little.** Sweeping at about 130 m/s, 740 buildings were grown and released in 20 s; about 1% of the time a building inside 100 m was still on its middle version, and 29 swaps happened inside 95 m (a visible pop, not a stutter). At normal camera speeds the dive had none.
- **The browser renderer had near-black bricks** at first: it shows a shader's colours as given, while the desktop renderer works in linear light, and the brick shader converted for the desktop only. Fixed for this lab; the same care is needed in every new shader.

### What it can't do yet

It is a measuring prototype: houses, row homes, apartments, shops, offices and factories get boxes, gable or hip roofs and real-size walls, but no porches, garages, chimneys, signs, gutters, construction stages, night lighting, wear by age, or the art builders' many house plans. The shapes come from the lot and seed, not from today's drawings, so it doesn't look like today's town building for building. It hasn't been checked against real photos or run on the Mac mini, a Mac Studio or a real browser. Graphics-chip time couldn't be read on this Mac (the engine reports 0), so "drawing" above is what's left after the measured parts.

### Pictures

Far, middle, a street of homes at eye height, a roofline and a brick wall close up, in both renderers, were saved by `new_drawing_lab.gd ... shots` (not kept in the repo; rerun it to make them).


## In the game, step 1: houses (2026-10-25)

The lab's style, brought into BuildingView for houses (shops, civic buildings and factories follow). Houses keep their builder's plans (I-house, foursquare, bungalow, cape, ranch, colonial, split-level), porches, garages, chimneys, yards and wear: what changed is how they are kept and drawn, in three rings.

- **Far:** every house's far version (its walls, roofs, windows and drives as drawn, about a hundred triangles), merged for each 256 m square (`scripts/detail/far_squares.gd`). That's all that's kept for a house far away.
- **Middle:** within 600 m (360 m on Low, 420 m on Medium), each 128 m square's houses in full, merged into one mesh per material (`batch_square.gd`). The builder hands its drawing over as plain arrays (`HouseBuilder.keep_arrays`), so nothing is read back off the graphics chip; once merged, the arrays are let go. Past the ring the square goes back to its far versions and its full drawing is freed, so memory follows the camera, not the size of the town.
- **Near:** within 90 m on High (more on Ultra and Cinematic), laid over each house's own walls and roofs a few jobs a frame (`near_detail.gd`): "double 4" vinyl siding panels, modular brick in running bond with the mortar set back, three-tab shingles in 5 in courses with staggered slots. Merged by kind across each 64 m of street (one brick batch, not one per house). With less than 4x antialiasing (the browser) it only shows where it's a few pixels big, because finer relief would shimmer.

**Measured** with `tools/house_shots.gd` (the real game, the 12-block PerfTown, 2,860 buildings, sim paused, 1600x900, a real window), main and the branch back to back. The Mac was shared with other helpers' runs (load 10 to 17), so expect about 10% wobble.

| | Desktop, main | Desktop, branch | Browser renderer, main | Browser renderer, branch |
| --- | --- | --- | --- | --- |
| Graphics memory | 2,402 MB | **1,258 MB** | 1,240 MB | **606 MB** |
| Other memory | 1,059 MB | **997 MB** | 893 MB | **879 MB** |
| 40 m, frame avg | 16.7 ms | 16.7 ms | 18.6 ms | 17.8 ms |
| 100 m | 16.7 ms | 16.7 ms | 13.1 ms | 11.5 ms |
| 300 m | 16.8 ms | 16.7 ms | 14.1 ms | 12.7 ms |
| Dive 2 km to 40 m: avg, frames over 50 ms | 19.2 ms, 6 | 18.1 ms, 1 | 18.1 ms, 2 | 17.8 ms, 2 |
| Sweep at 40 m: avg, frames over 50 ms | 16.8 ms, 1 | 16.7 ms, 0 | 19.8 ms, 0 | 17.9 ms, 0 |

Desktop is the High tier; the browser's renderer (Compatibility) is Low. On the desktop the graphics driver held both runs to 60 frames a second, so those frame times say both keep up, not by how much. An earlier uncapped pair, before the last fixes, had the branch 1 to 3 ms slower while diving and sweeping (squares coming near are drawn again), the same at the three distances.

**Pictures:** `docs/house-drawing/` (before and after, both renderers, 40, 100 and 300 m, and a brick split-level close up).

**Not done yet:** the near detail has no soldier courses over windows or rowlock sills (the builder's windows sit on top of the walls), and odd-shaped brick faces keep their painted brick. Checked against standard dimensions (modular brick, 4 in laps, 5 in shingle exposure), not side by side with photos. Not run on the Mac mini, a Mac Studio or a real browser.
