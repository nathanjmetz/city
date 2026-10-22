# Terrain data and licenses

The map is built from real, free public data for the White River valley
near Petersburg, Pike County, Indiana. `tools/terrain/build_region.py`
downloads it and bakes the files in `terrain/white_river_in/`.

| Layer | Source | License |
| --- | --- | --- |
| Ground heights (`ground.bin`, `base.bin`, `wlevel.bin`) | USGS 3D Elevation Program (3DEP), 1/3 arc-second DEM (about 10 m), tile n39w088, from the USGS National Map bucket on AWS (`prd-tnm`) | Public domain (US Government work). Credit: "U.S. Geological Survey, 3D Elevation Program." |
| Land cover: woods, water, crops, bare ground (`cover.bin`) | ESA WorldCover 10 m 2021 v200, tile N36W090 | CC BY 4.0. Credit: "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium." |
| Resources (`resources.bin`) | Worked out from the two layers above (see `derive()` in the build script) | Same as above |

How the resources are worked out:

- **Fertility:** real cropland, gentle slopes and river bottoms score high; steep wooded hills, strip mines and wetlands score low. These are the same things USDA land capability classes use. USDA SSURGO soil data would be the next upgrade, once its host can be reached.
- **Forest:** real tree cover.
- **Ore (coal):** Pike County sits on Illinois Basin coal that is strip mined across its uplands. Ore lies under the uplands, and is richest where the land shows old mines: bare spoil and small pit lakes in the hills.
- **Oil:** the Illinois Basin's oil pools, in scattered clusters that get more common to the south-west, where the basin deepens. Approximate: well records from the Indiana Geological and Water Survey would make it exact.

Past the edges of the 32.8 km square, the land repeats as a mirror image so the map never ends.
