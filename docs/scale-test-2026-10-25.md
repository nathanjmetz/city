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
