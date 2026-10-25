# Desktop photoreal: handoff

Started 2026-10-25 in the project thread "Go all out on the desktop map". This work is moving to the Claude on Brawn's other Mac to save this project's token budget.

## Goal

Brawn wants two games built from one codebase:

1. **Browser**: stays playable and light, with the current look, a 40 m closest zoom and Compatibility rendering.
2. **Desktop app**: photoreal across every visual, including buildings, vehicles, people, trees, terrain and the whole map. It should be preloaded, fast and zoomable up close. Next to it, the browser should look like a cartoon.

## Brawn's rules

- **Real world first.** Everything is designed against a real reference, such as real photos, real dimensions, US road standards (AASHTO/MUTCD) and real Grant County, Indiana data.
- **Textures are CC0 only.** Use sources like ambientCG or Poly Haven, and credit each one in `terrain/LICENSES.md` or a new `art/LICENSES.md`.
- **Desktop-only tiers.** Photoreal assets and settings load only in the desktop app (`not OS.has_feature("web")`) and only at the top quality tiers. The browser download must not grow.
- **Graphics scale with the machine.** The Mac Studio should look like real life, and the 8 GB Mac mini must stay smooth. Always auto-scale, and never cap full-strength desktop.
- **No manual steps for Brawn.** Fixes ship through the self-updating `.pck` pack, so avoid `project.godot` changes because reinstalling on the work Mac needs admin rights. Never help bypass employer device policy.
- **"Publish every loop" is the standing merge approval.** Merged is not the same as live: check that the web-preview and desktop workflows finished before saying something is live.

## Where the code lives

- **Quality tiers:** `scripts/shell/quality.gd` (class `GraphicsQuality`, autoload `Quality`). It has the tiers Low, Medium, High, Ultra and Cinematic (`TIERS`), the governor, and `BROWSER_TOP`. Views read the static `GraphicsQuality.current` and `.detail`; class scripts must not name autoloads.
- **Self-update and packs:** `scripts/shell/updater.gd`, `tools/stamp_build.py`, and `.github/workflows/desktop.yml`.
- **Terrain:** `scripts/terrain/terrain.gd` holds the real data (`terrain/grant_in/`). `scripts/terrain/terrain_view.gd` streams chunks by level of detail (`STEPS`/`REACH`) and draws the far sheet (`FAR_REACH`) and the ground shader.
- **Backdrop towns and farmsteads:** `scripts/terrain/backdrop_view.gd` and `farmstead_view.gd`.
- **Camera:** `scripts/camera/city_camera.gd` sets `MIN_DIST` (40 m) and `MAX_DIST`. A desktop-only closer zoom would go here.
- **Close-up lab:** on branch `claude/project-thread-hwh8rt`, with `tools/closeup_lab.gd` and `tools/closeup/`. A blueprint sedan test lives in `/mnt/project-files/closeup-detail/`.

## Plan and status

1. **Done (PR #522):** no grey holes while scrolling. The far sheet reads a mask of built chunks (`chunk_built`), and the desktop builds land at 12 ms a frame (the browser stays at 6 ms). It has a test in `tests/test_terrain.gd`, and the shader compiles under Compatibility.
2. **Parked:** preload the whole county on desktop. The draft is in `docs/desktop-photoreal-preload.patch`. It keeps built chunks in a cache (`CACHE_MAX` 8000), builds LOD 4 and LOD 3 for the whole county in spare frame time, and forgets a chunk when it is graded. It is not verified: its test built 0 chunks in the first step because the one-time sort of about 10k keys uses up the frame budget. Sort once outside the budget, or measure time from after the sort.
3. **Not started:** a photoreal tier on desktop. Use CC0 PBR textures (brick, siding, shingles, asphalt, concrete, bark, grass, soil) with normal and roughness maps, triplanar on terrain. Add real-model or impostor trees, and do vehicles and people next. Check whether to use the existing Ultra/Cinematic tiers or add a new top tier.
4. **Not started:** a closer zoom on desktop only, with the browser keeping 40 m. This needs the close-up detail from step 3 first.
5. **Not started:** check performance on the Mac Studio and the 8 GB Mac mini.
