# Desktop photoreal: handoff

Started 2026-10-25 in the project thread "Go all out on the desktop map". This work is moving to the Claude on Brawn's other Mac to save this project's token budget.

## Goal

Brawn wants two games built from one codebase:

1. **Browser**: stays playable and light, with the current look, a 40 m closest zoom and Compatibility rendering.
2. **Desktop app**: photoreal across every visual, including buildings, vehicles, people, trees, terrain and the whole map. It should be preloaded, fast and zoomable up close. Next to it, the browser should look like a cartoon.

## Brawn's rules

- **Two things never change; two are sliders (Nathan, 2026-10-25).** What the game is never changes, and how it runs never changes: we set what it runs on, and each player's machine or browser picks what it can do automatically. What the game does (features) and how it looks (detail) are sliders that share one performance budget. In his words: "If there is a feature in the game or something that it does that is having a vast negative impact on performance and a minimal positive impact on experience, then we should discuss it. But if we are able to cut something in order to zoom all the way in on someone's button on their shirt, I'm not sure what value that has." So every feature and every detail is priced in frame time and memory, measured, next to what it adds to playing. Costly, low-value things go to Nathan before they are cut. Detail goes where a player notices it, not to extreme zoom.

- **Everything, auto-scaled (Nathan, 2026-10-24):** "It should still have varying detail levels that adjust automatically based on what the computer can do for both Mac and Windows… it's actually everything. It's detail on every item in the game, including humans and cars and everything." Photoreal is not a few materials: every item gets real detail, through the quality tiers and governor in `quality.gd`, on Mac and Windows.

- **Real world first.** Everything is designed against a real reference, such as real photos, real dimensions, US road standards (AASHTO/MUTCD) and real Grant County, Indiana data.
- **Textures are CC0 only.** Use sources like ambientCG or Poly Haven, and credit each one in `terrain/LICENSES.md` or a new `art/LICENSES.md`.
- **Desktop-only tiers.** Photoreal assets and settings load only in the desktop app (`not OS.has_feature("web")`) and only at the top quality tiers. The browser download must not grow.
- **Graphics scale with the machine.** The Mac Studio should look like real life, and the 8 GB Mac mini must stay smooth. Always auto-scale, and never cap full-strength desktop.
- **No manual steps for Brawn.** Fixes ship through the self-updating `.pck` pack, so avoid `project.godot` changes because reinstalling on the work Mac needs admin rights. Never help bypass employer device policy.
- **"Publish every loop" is the standing merge approval.** Merged is not the same as live: check that the web-preview and desktop workflows finished before saying something is live.

## Where the code lives

- **Quality tiers:** `scripts/shell/quality.gd` (class `GraphicsQuality`, autoload `Quality`). It has the tiers Low, Medium, High, Ultra and Cinematic (`TIERS`), each tier's detail budget (`BUDGETS`: how far and how many cars, walkers and trees), each machine's frame and memory budget (`MACHINES`: browser, small, shared, full), the governor, and `BROWSER_TOP`. Views read their share with `GraphicsQuality.knob("name")`, and count caps with `fit_reach()`; class scripts must not name autoloads. `tools/scale/quality_lab.gd` measures the governor in a real window (`--quality auto` leaves the player's saved setting alone and logs every 3-second window).
- **Self-update and packs:** `scripts/shell/updater.gd`, `tools/stamp_build.py`, and `.github/workflows/desktop.yml`.
- **Terrain:** `scripts/terrain/terrain.gd` holds the real data (`terrain/grant_in/`). `scripts/terrain/terrain_view.gd` streams chunks by level of detail (`STEPS`/`REACH`) and draws the far sheet (`FAR_REACH`) and the ground shader.
- **Backdrop towns and farmsteads:** `scripts/terrain/backdrop_view.gd` and `farmstead_view.gd`.
- **Camera:** `scripts/camera/city_camera.gd` sets `MIN_DIST` (40 m) and `MAX_DIST`. A desktop-only closer zoom would go here.
- **Close-up lab:** on branch `claude/project-thread-hwh8rt`, with `tools/closeup_lab.gd` and `tools/closeup/`. A blueprint sedan test lives in `/mnt/project-files/closeup-detail/`.

## Plan and status

1. **Done (PR #522):** no grey holes while scrolling. The far sheet reads a mask of built chunks (`chunk_built`), and the desktop builds land at 12 ms a frame (the browser stays at 6 ms). It has a test in `tests/test_terrain.gd`, and the shader compiles under Compatibility.
2. **Done (2026-10-24, branch `claude/desktop-preload`):** the desktop app preloads the whole county. In 3 ms of each settled frame (`PRELOAD_MS`) it builds LOD 4 and LOD 3 for every chunk, nearest first in ring order (`ring_order`, no sort), and keeps them; machines with 30 GB or more also keep LOD 2 (`preload_lods`). Only those coarse levels are cached, never LOD 0/1 (a LOD 0 chunk is about 0.7 MB, so the draft's keep-everything cache could reach gigabytes). A graded chunk is forgotten. Measured on the M5 Max (48 GB) in a real window: after a 10 km camera jump the land is ready in 0.6–0.95 s, against 1.2 s without the cache. Idle frames are unchanged (60 fps), and the cost is about +128 MB of RAM and +67 MB of graphics memory. Headless, the two coarse levels for the whole county are 2.8 s of work and about 144 MB. Not yet measured on the 8 GB Mac mini (step 5).
3. **Not started:** a photoreal tier on desktop. Use CC0 PBR textures (brick, siding, shingles, asphalt, concrete, bark, grass, soil) with normal and roughness maps, triplanar on terrain. Add real-model or impostor trees, and do vehicles and people next. Check whether to use the existing Ultra/Cinematic tiers or add a new top tier.
4. **Not started:** a closer zoom on desktop only, with the browser keeping 40 m. This needs the close-up detail from step 3 first.
5. **Not started:** check performance on the Mac Studio and the 8 GB Mac mini.
