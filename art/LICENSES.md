
## People (art/people/*.glb)
Generated with MakeHuman (MPFB 2.0.18 for Blender, https://static.makehumancommunity.org/mpfb.html), using
the MakeHuman system assets (CC0: skins, eyes, eyebrows, hair, clothes, shoes). MakeHuman's output is
free to use; the assets are CC0. Made by tools/people/make_people.py. Desktop app only: the Web export
leaves art/people out. tools/people/make_masks.py painted the MakeHuman logo off the T-shirt and the
body suit off the "special suit" skins, and drew art/people/masks (where each outfit's top and bottoms
are, for recolouring).

## Road and sidewalk photo scans (art/textures/roads/*.jpg)
From Poly Haven (https://polyhaven.com), CC0: "Clean Asphalt" by Dimitrios Savva
(https://polyhaven.com/a/clean_asphalt) and "Brushed Concrete" by Dario Barresi and Dimitrios Savva
(https://polyhaven.com/a/brushed_concrete), 2k colour, normal (OpenGL) and roughness maps. Used as
close-up grain on streets, curbs and sidewalks on the desktop's High tier and up (Surfaces.PHOTOS).
Desktop app only: the Web export leaves art/textures out.

## Ground textures (art/pbr/)
Photographed CC0 textures from Poly Haven for the desktop app's ground at High and up; each one's author, size and use are in art/pbr/SOURCES.md. Fetched by tools/textures/fetch.py. Desktop app only: the Web export leaves art/pbr out.

## Free asset library (art/assets/)
Photo-scanned models, tiling photo surfaces and skies, every one CC0 or CC-BY 4.0 (free for any use,
forever; no purchases or subscriptions). The list and each asset's real-world match are in
tools/assets/catalog.json; authors, licences and links are in art/assets/CREDITS.md. Fetched by
tools/assets/fetch.py (not committed), loaded by AssetLib (scripts/art/asset_lib.gd). Desktop app only:
each asset ships as its own download pack (GameUpdater); the Web export leaves art/assets out.
Not used: Quixel Megascans (Fab Standard License forbids standalone redistribution, which a public repo is).
