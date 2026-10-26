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
- The city-line cost is measured (stage timers in the live runs and a separate timing of that code). Why it jumps from 0.34 s to 14 s at four towns is explained below, under "After the fixes".
- Why the people in the bots' towns fell so far was not investigated.
- No browser player was in these runs. The tools support one (`tools/playtest/soak.sh` with a web export), but the browser's cost for unpacking a 10 to 12 MB welcome on its one thread was not measured here.

### Questions for Nathan

None. Nothing here touches sign-in, paid services or data; everything ran on this machine.

### After the fixes (2026-10-25, branch `claude/region-load-fixes`)

The three problems above were fixed and the test run again on the same machine, the same day, with the same tools and towns. The runs were shorter than before (10 minutes of play instead of 15 to 20, late joiners at 4 and 6 minutes), and the machine was again shared with other helpers' programs. The numbers come from commit `67783f8`; a reviewer's fixes after it (catch-up waits for the neighbors to arrive, the order of queued copies, a cap on a stalled player's queue, a "first part" mark) touch only rare cases and were checked with the tests, not run again under load.

**What changed:**
1. **City lines no longer freeze the game.** They are traced a little each frame (2 ms of work), only for pairs of towns near a town whose edge really moved (building inside a town doesn't count), and the old lines stay up until the new ones are ready. *Why four towns took 14 s:* the line starts where two towns come nearest, but only at a spot no third town is nearer. In the 4-town region two towns sat 13 km apart with the other two between them, so no such spot existed. The search had no way to give up, so it checked every one of the first town's 18,000 points, each needing a slow far-off lookup into the other town and the two in between: 11 s for that pair alone. With three towns no pair was blocked like that. Now a pair too far apart is skipped, and a blocked pair gives up after 48 tries and starts instead from where three towns meet. A second bug: county roads count as part of a town, and two joined towns' roads meet in the middle, so the gap between them was 0 m and no line was ever drawn. The roads out of town no longer count.
2. **Joiners get in, however many towns there are.** The welcome is now the region and the player's own town only; each neighbor follows in its own message as a *picture*: a postcard with its lots packed to the centimetre, about half the size (0.8 to 1.0 MB for a 16,000-person town, was 1.6 to 2.0 MB). Big messages also go in 1 MB parts, so nothing can outgrow the connection's buffer again. If a message still can't be sent, the server writes it in its log, and a player still joining is told *"The region couldn't send you your town. Try again in a minute"* instead of waiting. A game that hears nothing for 90 seconds after saying hello gives up and says so too.
3. **The server no longer stalls.** The save is written on another core from the copies as they came in (same file format; old saves load). Incoming copies are unpacked and made into pictures on other cores, and old copies are freed there too. A new town is placed without unpacking any neighbor: its neighbors' halves of the county roads are built by their owners' own games (at once if they're playing, else when they come back).

**Before and after** (before: the runs above; after: `tools/scale/results/region-stress-2026-10-25-after/`):

| | 4 players, 20-block towns | 8 players, 16-block towns | 8 players, 20-block towns |
| --- | --- | --- | --- |
| Could they join? | yes / yes | yes / yes | **no / yes** |
| Welcome a player is sent | 10 MB / 5.1 to 5.4 MB (then 3 pictures) | 12 MB / 3.4 to 4.6 MB (then 7 pictures) | 17.3 MB, too big / 5.1 to 6.3 MB (then 7 pictures, 6.5 MB) |
| Server answer time, median / 95% / worst | 13 ms / 0.7 s / 7.6 s → 13 ms / 16 ms / 44 ms | 13 ms / 1.1 s / 5.3 s → 13 ms / 17 ms / 140 ms | – / 13 ms / 17 ms / 0.6 s |
| Server loop steps over 0.1 s (worst) | not measured → 3 (0.2 s) | not measured → 6 (0.4 s) | – / 18 (0.7 s, a new player's join) |
| New player: hello to welcome / game's load | 6 to 8 s / 14 to 16 s → 0.13 to 0.17 s / 8 to 9 s | 5 s / 13 s → 0.27 to 0.35 s / 8 s | – / 0.3 to 0.6 s / 8 to 11 s |
| Most city lines added to any slow frame | 107 to 131 s → 3 ms (7 ms for the late joiners) | 4 minutes → 4 ms (8 ms for the late joiners) | – / 3 ms |
| Each bot's worst frame | 107 to 131 s → 13 s | 244 to 256 s → 8 to 10 s | – / 11 to 16 s |
| Sync on the wire, median / 95% | 0.15 s / 5.9 s → 0.35 s / 0.5 s | 48 s / 214 s → 0.28 s / 0.43 s | – / 0.4 s / 0.64 s |
| Server memory, start / peak | 2.9 / 3.9 GB → 3.2 / 3.4 GB | 3.9 / 6.7 GB → 4.1 / 4.4 GB | – / 6.0 / 6.3 GB |
| Out of the server, steady | 505 KB/s → 450 KB/s | 480 KB/s → 1.2 MB/s | – / 1.2 MB/s |
| Reconnects or failures | none → none | none → none | – / none |

The city lines timed on their own (`region_stress_lines.gd`): four towns took 14 s in one go; now 0.2 s of work spread over 82 frames, at most 4 ms in a frame. Eight 20-block towns: 1.7 s of work over 631 frames, at most 12 to 18 ms in a frame on the busy machine (the slowest single step is under 5 ms; the rest is the machine being shared).

**What this means:** nothing in the region freezes for minutes any more, and nobody is locked out. The bots' remaining freezes (8 to 16 s at worst) are their own towns' thinking at top speed (laying out lots and moving people, `sim.lots.plan` and `sim.people`), and drawing a neighbor's town when it arrives (`net.neighbor_load`, up to 8 s with four players and 15 s with eight 20-block towns on this busy machine). Traffic out of the server went *up* with 8 players (480 KB/s to 1.2 MB/s): the games aren't frozen any more, so they send and receive what they always meant to. That is the "traffic grows with the square of the players" risk above, now visible.

**Still to do, in order of risk:**
1. **A neighbor's town is still a whole running town in your game** (3 to 8 GB per bot here). The next job, Nathan's decision (2026-10-25): "Neighbors show as a living picture, with full detail only when I fly there." The picture is built for it (see `Region.picture_of`): it already holds what's needed to draw a neighbor (roads, buildings, the lots they stand on, how they look), it goes to each player on its own, the server keeps it packed and ready, and a newer one replaces an older one still waiting to go. That job adds night lights and a sample of traffic to it, draws from it without making a town, and sends it about once a minute.
2. **Drawing a neighbor's town as it arrives** took up to 15 s on this machine (8 big towns). It's part of the same job.
3. **Traffic grows with the square of the players.** Pictures halve it; sending a neighbor's picture once a minute instead of on every change would cut it much further.
4. **A brand-new town's half of a county road into a neighbor waits for that neighbor's player.** Until they come back, others don't see that half of the road. It's in the region's save (`pending`), but a server from before this change reading a newer save drops it.

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


## In the game, step 2: every building BuildingView draws (2026-10-25)

Shops, strip centres, Main Street blocks, offices and towers, row homes, apartments and factories now go the same way as houses. BuildingView's old path is gone: it no longer keeps every building's own meshes, its far boxes and merged copies. Signs ride with their square's drawing. Brick commercial blocks and the mills get real brick up close. Big brick walls far off or seen edge on used to shimmer, so the close-up detail now dissolves where a pixel covers more than about 9 cm of wall, even with 4x antialiasing. Civic buildings (fire, police, schools, clinics, parks, warehouses, big plants) are drawn by their own views and haven't moved over yet.

Measured as in step 1 (12-block PerfTown, 2,860 buildings, sim paused, main and branch back to back, the desktop held to 60 frames a second by the driver):

| | Desktop, main | Desktop, branch | Browser renderer, main | Browser renderer, branch |
| --- | --- | --- | --- | --- |
| Graphics memory | 2,422 MB | **844 MB** | 1,250 MB | **438 MB** |
| Other memory | 1,073 MB | **937 MB** | 909 MB | **833 MB** |
| Houses 40 / 100 / 300 m | 16.8 / 16.7 / 17.3 ms | 16.8 / 16.7 / 16.7 ms | 20.8 / 11.9 / 14.6 ms | 20.5 / 11.3 / 13.7 ms |
| Shops at 40 m | 16.3 ms | 16.7 ms | 16.4 ms | 16.4 ms |
| Mills at 90 m | 16.7 ms | 16.8 ms | 10.8 ms | 13.3 ms |
| Dive: avg, frames over 50 ms | 20.7 ms, 5 | 19.2 ms, 2 | 19.5 ms, 6 | 19.3 ms, 2 |
| Sweep: avg, frames over 50 ms | 16.9 ms, 3 | 17.2 ms, 2 | 21.2 ms, 1 | 19.7 ms, 0 |

The mills at 90 m were 2.5 ms slower in the browser renderer, in one run, with more triangles drawn (1.17 M vs 1.08 M). That wasn't looked into yet.

**Pictures:** `docs/building-drawing/`.


## Where the triangles go, and the grown trees' shadows (2026-10-26)

The critic's item 9: a 1,500-person town drew 5,214 draw calls and 6.2 million triangles (the desktop budget in `PerfBudget.RENDER` is 4 million), the demo town 13.3 million, and 14 to 20 million from 100 m up once the street trees came in.

**How it was measured.** `tools/render_budget.gd` opens the real game in a window (1600x900) with a built-out test town (PerfTown, 5 blocks: 784 people, 753 buildings), mid-July, the sim paused, the tier pinned. It times the street, 100 m and 300 m views, then hides one part at a time (grown trees, card trees, buildings, the land, roads, each view, sun shadows, each screen effect) and reads what each one adds. Run with `--years=25` for a town whose planted trees are 25 years old. On this Mac the frame rate is held to 60 even with vsync off, so frames under 16.7 ms read as 16.7, and the graphics chip's own time reads 0: the frame times only show a difference once a view is over budget.

**What was costing most:** the grown trees' sun shadows. On Cinematic, from the street, 17 of 26 million triangles (grown town; 13 of 21 million as planted) were grown trees drawn into the shadow map. Each group of grown trees spans the whole circle round the camera (up to 475 m on Cinematic), so the engine can't cull it: every tree goes into every one of the four shadow splits, and trees behind the camera too. The light grown trees (175 to 475 m on Cinematic, 98 to 266 m on High) were the largest share, then the full ones.

**The change** (`GrownTrees`, `TreeLook`): the groups that draw grown trees cast no shadow. Shadow-only groups cast it instead:
- within 60 m of the camera, a full tree's own mesh (the sun still comes through its leaves in flecks);
- out to the full trees' reach, its light tree (a fifth of the triangles, the same limbs and crown);
- past that, the full card at the tree's spot, which was drawn into the shadow map anyway.

Back to back, main then the branch (draw calls / triangles / frame median, p95):

| Renderer, tier, trees | View | Main | Branch |
| --- | --- | --- | --- |
| Desktop Cinematic, grown 25 years | street | 5,780 / 26.2 M / 16.7, 17.0 ms | 5,019 / 11.0 M / 16.7, 16.9 ms |
| | 100 m | 4,082 / 23.0 M / **22.6 to 22.9, 25.2 to 25.5 ms** | 3,496 / 9.2 M / **19.3 to 20.2, 22.7 to 22.8 ms** |
| | 300 m | 5,535 / 8.9 M / 16.7, 17.0 ms | 4,962 / 6.0 M / 16.7, 16.9 ms |
| Desktop Cinematic, as planted | street | 5,932 / 20.9 M / 16.6, 16.9 ms | 5,094 / 9.1 M / 16.7, 17.0 ms |
| | 100 m | 4,209 / 16.9 M / 17.7, 20.5 ms | 3,567 / 7.2 M / 16.7, 18.3 ms |
| | 300 m | 5,671 / 6.8 M / 16.7, 16.9 ms | 5,050 / 5.5 M / 16.7, 16.9 ms |
| Desktop High, grown 25 years | street | 5,138 / 13.1 M | 4,685 / 7.3 M |
| | 100 m | 3,384 / 7.4 M | 2,928 / 4.5 M |
| | 300 m | 4,490 / 3.8 M | 4,129 / 3.8 M |
| Desktop High, as planted | street | 5,241 / 10.1 M | 4,703 / 6.2 M |
| | 100 m | 3,388 / 5.4 M | 2,930 / 4.1 M |
| Browser renderer High, as planted | street | 3,806 / 5.4 M / 19.7 to 21.1, 24.7 to 26.7 ms | 3,590 / 4.8 M / 20.1 to 20.3, 24.9 ms |
| | 100 m | 1,996 / 4.3 M / 14.6 to 16.3, 21.5 to 23.4 ms | 1,867 / 3.8 M / 12.8 to 14.3, 19.8 to 21.2 ms |
| Browser renderer Low | all | no change (no grown trees, no tree shadows) | |

High's frames were 16.7 ms (held to 60) before and after. Graphics memory is the same (1,569 MB on Cinematic, 875 MB on High, 495 MB browser High, 438 MB browser Low, at the end of a run).

**Pictures:** `docs/render-budget/` (before on the left, after on the right). Measured against two runs of the same code (the trees sway, so no two pictures match): from the street 1 to 3% of pixels changed by more than a shade (under 1% run to run), in the flecks of sun under trees past 60 m; from 100 m in a grown town 9 to 10% (about 2.5% run to run), in the shapes of tree shadows on the ground 100 to 475 m off, where a lighter tree's or a card's shadow now stands in. Looked at side by side, they read the same; nothing is missing or added. As planted the change is about run-to-run size; from 300 m, 0.1 to 2.4% of pixels.

**Still over budget, for next time** (measured by hiding each part on Cinematic, grown town, 100 m, about 1 ms of noise): the wild woods' cards (2.6 M triangles, about 5 ms; most of the triangles are their shadows), the light grown trees themselves (3.4 M, about 3.5 ms), SDFGI (about 3.7 ms), all sun shadows (about 4 to 6 ms). Draw calls are still about twice the 2,500 budget from the street on the desktop (5,000), and the triangles 1.5 to 2.7 times the 4 million budget on Cinematic. The land's background preloading (`frame.terrain`, 3.3 ms of every frame on the main thread while it fills its cache) was also over its 1 ms budget in every run.
