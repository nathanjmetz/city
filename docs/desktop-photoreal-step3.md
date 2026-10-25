# Real-life look for the desktop app: spec (2026-10-25)

**Purpose (one sentence Nathan would say aloud):** On a strong computer, the desktop app looks like real life: every item in the game, including people, cars, houses, trees and the ground. The browser stays light.

**Who uses it:** Anyone playing the desktop app on a machine that can handle it. The game decides automatically, on Mac and Windows.

**The one main thing on the screen:** The same town, but the ground, roads, houses, trees, cars and people look real up close.

Nathan's words (2026-10-24): "it's actually everything. It's detail on every item in the game, including humans and cars and everything." And: "It should still have varying detail levels that adjust automatically based on what the computer can do for both Mac and Windows."

## How it ships

- **Its own download (Nathan, 2026-10-25).** The real-life art comes as a separate art pack, next to the game pack the app already downloads. It only comes down again when the art changes, so everyday fixes stay about 30 MB. The first art download is about 150 to 300 MB, and it grows as later rounds add more.
- **The art isn't kept in the code repository.** The build downloads it from free CC0 sites (ambientCG, Poly Haven and similar), using a list in the repo with each file's exact version and fingerprint. That keeps the repository small and fast to copy, and needs no paid storage. Every file's source and license is listed in `art/LICENSES.md`.
- **The browser never sees it.** The web build doesn't include the art pack, so the browser download doesn't grow.

## Who sees what (automatic, Mac and Windows)

| Graphics level the game picks | What it shows |
| --- | --- |
| Low, Medium (8 GB Mac mini, laptops) | Today's look, unchanged |
| High | Today's look, with the real ground and road surfaces |
| Ultra, Cinematic (Mac Studio, gaming PCs) | Everything real-life |

The game already picks the level from the hardware and steps it up or down while you play, so nobody has to choose. If the art pack hasn't downloaded yet, the game shows today's look until it has.

## Rounds (each one ships on its own, tested and live)

1. **The plumbing and the ground.** The separate art download, then real surfaces for grass, soil, fields, gravel, asphalt, concrete sidewalks and the woods floor.
2. **Houses and buildings.** Brick, siding, shingles, metal roofs, windows and concrete.
3. **Trees and plants.** Real tree models (oak, maple, sycamore and more), with simpler stand-ins at a distance so it stays fast.
4. **Cars and trucks.** Real-detail vehicles up close.
5. **People.** Real-detail people up close.
6. **Everything else.** Signs, fences, farm and factory equipment, water, and the closer zoom (handoff step 4).

## What it does NOT do (this round)

- No change to the browser.
- No change to the 8 GB Mac mini's look; it must stay smooth.
- No paid art, and no art from anywhere that isn't CC0.

## Data and access

- Art files only. No personal data. The art pack lives on the same free GitHub release as the app.

## States

- **Art not downloaded yet:** today's look, with a line on the title screen ("Downloading the real-life art...").
- **Downloaded:** real-life look at High and up.
- **Download failed:** today's look, and it tries again at the next launch.

## Done when (Nathan can click through this himself), round 1

1. Open the desktop app on the Mac Studio. The title screen says it's downloading the real-life art, then it's done.
2. In a town, zoom in on a street: the grass, dirt, gravel, road and sidewalk look like real materials.
3. Open the same town in the browser: it looks exactly like today.
4. On the Mac mini, it stays smooth, and its look changes only if the game moves it up to High.
5. Push a small fix: the next update downloads about 30 MB, not the art again.
