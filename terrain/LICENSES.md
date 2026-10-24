# Terrain data and licenses

The map is built from real, free public data for Grant County, Indiana,
around Marion. `tools/terrain/build_region.py` downloads the land and bakes
the layers in `terrain/grant_in/`; `tools/terrain/build_roads.py` adds the
real roads, rail, towns and Marion's buildings.

| Layer | Source | License |
| --- | --- | --- |
| Ground heights (`ground.bin`, `base.bin`, `wlevel.bin`) | USGS 3D Elevation Program (3DEP), 1/3 arc-second DEM (about 10 m), tile n41w086, from the USGS National Map bucket on AWS (`prd-tnm`) | Public domain (US Government work). Credit: "U.S. Geological Survey, 3D Elevation Program." |
| Land cover: woods, water, crops, bare ground (`cover.bin`) | ESA WorldCover 10 m 2021 v200, tile N39W087 | CC BY 4.0. Credit: "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium." |
| Resources (`resources.bin`) | Worked out from the two layers above (see `derive()` in the build script) | Same as above |
| County and state roads (`county.bin`, `county.json`, `highways.bin`, `highways.json`), rail (`rail.json`), town limits and start towns (`places.json`), Marion, Gas City and Jonesboro buildings and streets (`backdrop.bin`) | Overture Maps Foundation, release 2026-10-21.0 (transportation, divisions and buildings themes), which carry OpenStreetMap data | ODbL 1.0. Credit: "© OpenStreetMap contributors, Overture Maps Foundation." Town populations: 2020 US Census (public domain). |

How the resources are worked out:

- **Fertility:** real cropland, gentle slopes and river bottoms score high; steep wooded banks, gravel pits and wetlands score low. These are the same things USDA land capability classes use. USDA SSURGO soil data would be the next upgrade, once its host can be reached.
- **Forest:** real tree cover.
- **Ore (sand, gravel and stone):** Grant County has no coal. What is dug here is glacial outwash sand and gravel in the river valleys, the pits and pit ponds along the Mississinewa, and Silurian limestone under thin till. Ore lies along the valleys, richest where the land already shows pits.
- **Oil and gas:** the Trenton field of Indiana's 1887 gas boom, which lay under almost the whole county (Gas City is named for it), with oil pools a little more common to the east. Approximate: well records from the Indiana Geological and Water Survey would make it exact.

How the roads are fitted:

- County roads follow the survey's one-mile sections (PLSS). A real road counts for a mile when it runs along that section line for at least half of it; the game draws it on the mile line, on average about 78 m from where it really runs, and keeps its real name (such as E 100 N).
- State and US roads and I-69 follow their real paths. I-69 is fenced: towns can't join it.
- Marion, Gas City and Jonesboro stand inside their real town limits as a finished backdrop that nobody plays.

Past the edges of the 36.9 km square, the land repeats as a mirror image so the map never ends, and county roads carry on in the same mile grid.
