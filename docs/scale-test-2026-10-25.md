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
