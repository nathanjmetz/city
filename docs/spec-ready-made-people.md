# Ready-made people on the desktop: spec (2026-10-25)

**Purpose (one sentence Nathan would say aloud):** On my desktop app the people in town look like real people in real clothes, and the browser stays light.

**Nathan's words (2026-10-25):** "If we only use it on the desktop download version I think we should lean that direction in any way that makes sense. Not just with humans but with anything that improves the quality of the game while still keeping a high performance level." When asked whether the desktop app should start using ready-made people, he answered "Yes".

**Who uses it:** desktop players. The browser keeps the code-grown figures (WalkerView) as they are.

## Source and licence
- Bodies come from MakeHuman, through MPFB 2.0.18, the Blender extension at extensions.blender.org. Clothes, hair, skins and eyes come from MakeHuman's system asset pack (`makehuman_system_assets_cc0.zip`, CC0). People generated with MakeHuman are free to use in a game. Credit "MakeHuman" in art/LICENSES.md.
- The tools sit outside the repo on the build Mac: Blender 4.2.23 LTS runs from `~/Tools/Blender.app` (no admin rights needed), and MPFB with its assets lives in Blender's user data. The generator script is checked in at `tools/people/make_people.py`.

## The plan, in steps
1. **Generator** (`tools/people/make_people.py`):
   - Make 30 to 50 people from seeds: gender, age, weight, height, skin, hair, and outfits matched by gender and season (casual, work, office, kids).
   - Use MPFB's lower-poly proxy body, and keep textures at 512–1024 px.
   - Export each as a GLB.
   - A preview of three people was done on 2026-10-25. The arms came out bent wrongly (rotated about the wrong axis) and the man got a women's outfit (a substring match); fix both.
2. **Walking:**
   - Give each person the MPFB default rig and a free motion-capture walk cycle (for example the CMU motion capture library, free to use).
   - Bake the cycle into a vertex animation texture (VAT): N frames of vertex positions stored in a texture.
   - This is the standard way games draw big crowds. A MultiMesh plays the walk in its shader with no skeleton per person, so hundreds stay cheap.
3. **Desktop-only art pack:**
   - The people (meshes plus textures) go in the separately downloaded desktop art pack. Nathan said yes to "put the real-life art in its own download that only comes down when the art changes".
   - Budget about 200–400 MB for 30 to 50 people at reduced textures.
4. **In the game:**
   - WalkerView and AmbientLife draw ready-made people for the near detail levels on the desktop, when the art pack is present, and the code-grown figures farther out and in the browser.
   - Distances scale with GraphicsQuality.detail (REACH).
5. **Check:**
   - frame time and memory with 100, 400 and 800 walkers on the M5 Max, and an estimate for the 8 GB Mac mini
   - the detail floor at the 40 m zoom
   - screenshots against real photos of people on Indiana streets

## Beyond people (same approach, desktop only, with detail levels)
Cars, street trees, porch furniture, street furniture (benches, hydrants, mailboxes, signs) and building details, wherever a ready-made CC0 model looks clearly better and stays fast.

## Done when (Nathan can click through this himself)
1. Open the desktop app and zoom to a sidewalk at 40 m. The people walking read as real people in real clothes, with no two alike nearby.
2. Open the browser game. People look as before, and it is no slower.
3. The frame time with a busy downtown is within 1 ms of before on the desktop.
