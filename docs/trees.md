# Trees that grow

Written 2026-10-25 (task 12). Nathan's question: "Can trees actually grow in the game?" Yes: every tree is now grown from three small facts, and yard trees start as saplings and grow over the game's years.

## How it works, in plain words

- **A tree is three facts:** its kind, a seed (where it stands) and its age. Nothing new is saved. A yard tree's planting date is its building's build date, which saves already have. A wild tree's age comes from its size, which the woods already work out from when the land was last cleared. So old saves load as before, and two copies of a town always agree.
- **Grown, not drawn.** Near the camera each tree is grown branch by branch by *space colonization* (Runions, Lane and Prusinkiewicz, 2007). Points of open air fill the crown shape the kind grows into. Each twig grows a step toward the points nearest it, and uses a point up once it reaches it. The crown grows year by year with the tree's real height, so the 10-year-old tree is the 60-year-old's younger self. As the crown lifts, the lowest limbs die off.
- **Limb thickness follows the pipe model.** A limb carries every twig beyond it, so its cross-section is the sum of theirs. The trunk is then scaled to the kind's real trunk thickness at chest height for that age.
- **The same seed always grows the same tree.** Each kind has three variants (two for the middle-distance version), picked by the seed. Each one is also turned and sized a little differently.
- **Seasons:** each kind keeps its own calendar on top of the game's seasons. Walnuts drop their leaves weeks before the oaks, maples turn scarlet to orange, oaks turn russet and hold their leaves, and sycamores turn brown early. Crabapples bloom pink, and red cedar bronzes in winter.
- **Wild woods get real Grant County kinds** by where they stand. Sycamore, silver maple, cottonwood and hackberry grow by creeks and rivers. White and red oak, sugar maple, black walnut, hackberry and honey locust grow on the uplands. Red cedar grows in old fields and fencerows.
- **Yard trees** are sugar and silver maple, white and red oak, honey locust, blue spruce, and crabapple by the house. They go in as nursery stock: a 2-inch, 10 to 12 ft tree, about 7 years old on these growth curves. After that they grow on the game's clock (a game year is 12 game days, about 29 minutes at normal speed).

## Detail by distance

| Distance (desktop, High quality) | What is drawn | Triangles per tree |
| --- | --- | --- |
| Under about 100 m | The full grown tree: limbs down to 2.5 cm, a leaf card at each twig | 5,000 to 12,000 |
| About 100 to 270 m | The light grown tree: big limbs only, one big card per cluster of twigs | 800 to 2,600 |
| Past that | The cheap card trees (TreeField), in each kind's real crown shape and size | about 300 |
| From high up | The ground's painted canopy | 0 |

The radii scale with the quality tier. The browser draws no full trees, and the light ones only from Medium up and nearer. A tree hands over from one level to the next with a dither, so nothing pops. A grown mesh is built on worker threads on the desktop, or a slice per frame in the browser. Meshes are kept by kind, variant and age bucket. Until a tree's mesh is ready, its card tree stands in.

## What it costs (measured 2026-10-25, M5 Max MacBook Pro, 1600x900, Auto quality = Ultra)

| Test | Before | After | Notes |
| --- | --- | --- | --- |
| 16,000-person town, `tools/scale/combined_lab.gd` (PerfTown "20", camera 900 m out), normal speed | 62.7 ms a frame | 63.2 ms | Within run-to-run noise. Grown trees don't reach that far. |
| Same, fast speed | 115.6 ms | 115.6 ms | |
| Same, memory / graphics memory | 1,701 MB / 6,008 MB | 1,712 MB / 6,022 MB | |
| Same town, trees aged 30 years, camera at street level (`tools/trees/tree_lab.gd`), grown trees off and on in turns | 62.9 ms | 64.6 ms (+1.7 ms) | 58 grown trees, 155,000 triangles |
| Dense woods at the start, camera 60 m out (`tools/trees/grown_shot.gd`), off and on | 7.4 ms | 11.8 ms (+4.4 ms) | The worst case seen: 1,494 grown trees, 3.2 million triangles |
| Open country at the start, 60 m out | 6.9 ms | 5.8 ms | 34 grown trees: no measurable cost (noise) |

- The town's frames swing by about plus or minus 5 ms from run to run (most of the 60 ms is the town's own drawing). So trees were measured off and on in turns, in the same place.
- **Memory:** a grown mesh is 50 to 250 KB on the graphics card (16-bit compressed). The cache holds up to 260 of them, 2 to 3 MB in a typical view and under about 60 MB at most. The grown branches use about 3 MB of main memory. Graphics memory read by the engine swings by about 2 GB between runs of the same town, so it can't show a change this small.
- **Building them** happens on worker threads on the desktop: about 0.2 s for a kind's whole-life branches and 2 to 10 ms for a mesh, with nothing on the main thread except handing over the mesh. In the browser it's a slice per frame (2.5 ms), with card trees standing in until it's done.
- **Slider:** the dense-woods case (+4.4 ms on the strongest Mac) is the one to watch on the Mac mini. The full-tree radius (TreeLook.NEAR) and the light-tree radius (MID) are the two dials, and both already scale with the quality tier.

## The reference each kind is checked against

Heights are open-grown trees on a fair Indiana site, counted from seed. Sources: USDA Forest Service, *Silvics of North America* (Burns and Honkala, 1990); Purdue Extension forestry notes; Morton Arboretum and Indiana DNR tree guides. The numbers live in `scripts/art/trees/tree_kinds.gd`. `tests/test_tree_growth.gd` grows every kind and checks it against them: height at 10, 30 and 60 years, trunk thickness, crown width against height at 60, and the angle side limbs leave at (measured 1.5 m out).

### sugar maple
Dense, rounded to oval crown, about 0.7 as wide as tall. Limbs ascend at 40 to 60 degrees. Bark is smooth grey when young, later grey with long, irregular, curling plates. Leaves have 5 lobes and are 8 to 13 cm, medium green. In fall they turn brilliant orange to scarlet or yellow, varying tree to tree, at their peak in mid to late October. Grows slowly to moderately: 4.5 m at 10 years, 13 m at 30, 21 m at 60. Trunk 22 cm across at 30 years and 45 cm at 60.

### white oak
Broad, wide-spreading crown when open-grown, as wide as tall or more (about 1.15), with massive near-horizontal limbs (55 to 85 degrees). Bark is light ash-grey, in shallow scaly plates that loosen. Leaves are 10 to 20 cm with 7 to 9 rounded lobes, dark green. In fall they turn russet to wine-brown, late (November), and dead leaves often hang on into winter. Slow growing: 3.5 m at 10, 11 m at 30, 18 m at 60. Trunk 21 and 48 cm.

### red oak
Rounded, symmetrical crown, about 0.9 as wide as tall. Stout limbs at 45 to 65 degrees. Bark is dark grey-brown, with flat-topped ridges that look like shiny stripes up the trunk. Leaves are 12 to 20 cm with 7 to 11 bristle-tipped lobes. In fall they turn russet to bright red, late October into November. Fast for an oak: 5 m at 10, 14 m at 30, 22 m at 60. Trunk 28 and 55 cm.

### silver maple
Broad, irregular vase. Several big upright stems fork low at narrow angles (25 to 45 degrees), and the outer twigs droop. Bark is smooth silver-grey when young, later shaggy, in long strips loose at the ends. Leaves are deeply 5-lobed, 10 to 15 cm, green above and silvery below. In fall they turn pale yellow. Leafs out early. Very fast: 8 m at 10, 18 m at 30, 24 m at 60. Trunk 45 and 80 cm. Grows by water and was a common 1950s to 70s yard tree.

### sycamore
Massive, broad, open crown with crooked limbs at 45 to 70 degrees, about 0.85 as wide as tall. Bark is the giveaway: brown-grey outer bark flakes off in patches, showing cream, white and pale green. Upper limbs are almost all white, ghostly in winter. Leaves are very large, 10 to 25 cm, shallowly lobed and light green. In fall they turn dull tan-brown, early. Fast: 7 m at 10, 18 m at 30, 27 m at 60. Trunk 40 and 80 cm. A creek and river tree.

### black walnut
Open, airy, rounded crown, about 0.8 as wide as tall, with stout ascending limbs (40 to 60 degrees) and few coarse twigs. Bark is dark brown to near black, deeply furrowed into narrow ridges that cross in a diamond net. Leaves are compound, 30 to 60 cm, with 15 to 23 leaflets of 6 to 12 cm, yellow-green. In fall they turn yellow and drop early (late September to early October). Leafs out late (May). Fast: 5.5 m at 10, 15 m at 30, 22 m at 60. Trunk 28 and 55 cm.

### hackberry
Rounded to vase-shaped, broad, irregular crown, about 0.9 as wide as tall. Limbs at 40 to 60 degrees, with zigzag twigs. Bark is grey, smooth, with corky warts and short ridges. Leaves are 5 to 12 cm, ovate and lopsided at the base, medium green. In fall they turn dull yellow. Moderate: 4.5 m at 10, 12 m at 30, 18 m at 60. Trunk 22 and 45 cm. Grows in bottomlands, fencerows and towns.

### cottonwood
Tall, broad, open vase of massive ascending limbs (30 to 50 degrees), about 0.7 as wide as tall. Bark is smooth yellow-grey when young, later very thick, ash-grey and deeply furrowed. Leaves are triangular, 7 to 15 cm, coarsely toothed and glossy, and flutter in the wind. In fall they turn bright gold. The fastest tree here: 11 m at 10, 24 m at 30, 30 m at 60. Trunk 55 and 95 cm. Short-lived. A river tree.

### honey locust
Open, broad, flat-topped to spreading crown, about 0.95 as wide as tall, with light, dappled shade. Limbs at 45 to 65 degrees. Bark is grey-brown to blackish, in long narrow plates curling at the edges. Wild trees carry clusters of big thorns, and yard cultivars are thornless. Leaves are compound, with tiny leaflets of 1.5 to 3 cm, bright green and feathery. In fall they turn clear yellow and drop early. Leafs out late. Fast: 6.5 m at 10, 15 m at 30, 21 m at 60. Trunk 28 and 50 cm.

### eastern red cedar
Dense, narrow spire or column, about a third as wide as tall, broadening when old, with a central leader. Branches leave at 40 to 65 degrees. Bark is thin, reddish-brown, and shreds in long fibrous strips. Foliage is tiny scale leaves, dark green, turning bronze to brownish in winter. Evergreen. Slow to moderate: 3 m at 10, 8 m at 30, 13 m at 60. Trunk 15 and 30 cm. The first tree in old fields and along fencerows.

### blue spruce
A yard and windbreak tree. Dense, symmetrical cone, about 0.45 as wide as tall, with whorls of near-horizontal branches (70 to 95 degrees) that droop at the tips. Bark is grey and scaly. Needles are 2 to 3 cm, stiff and blue-green, evergreen. 3 m at 10, 10 m at 30, 17 m at 60. Trunk 22 and 40 cm.

### crabapple
A small front-yard ornamental. Rounded to spreading crown, as wide as tall or wider. Bark is grey-brown and scaly. Leaves are 5 to 8 cm. It blooms pink to white in late April, and in fall turns yellow to orange-red, with red fruit. 3.5 m at 10, 6 m at 30, 7 m at 60.

## What the tests hold

`tests/test_tree_growth.gd` (on every web preview) checks:

- Every growth curve passes through its reference heights and always rises.
- Every kind, grown, against its reference: height at 10, 30 and 60 years (within about 20% under to 12% over), trunk thickness (5%), crown width against height at 60 (within 0.65 to 1.3 times), and the side-limb angle (within 8 degrees of the reference range). Also: cedar and spruce are narrow, white oak spreads widest, and cottonwood grows fastest.
- The same seed grows the same tree. Growing in slices gives the same tree as growing all at once. The 30-year-old keeps the 10-year-old's limbs. Limb thickness follows the pipe model. The light version is under a third of the full one.
- Each kind's own calendar: walnuts turn and drop first, oaks hold their leaves longest, evergreens stay green, crabapples bloom.
- Planted trees go in as saplings and grow with the clock. Wild trees are as old as their size. Brush is never grown.
- After a save and load, two copies of a town agree on every yard tree's planting date and every wild tree's kind, place and age.
- This document describes every kind.

## Known limits

- The original "grown tree" from Nathan's other project was not on this machine, so this was built from the description: space colonization, the pipe model, and the same seed for the same tree.
- Only buildings' yard and street trees carry a planting date. Park, farm, median and other views' trees take their age from their size (mature), so they don't grow yet. Each needs a one-line hook like BuildingView's.
- A tree's branches change shape at its age buckets (2, 4, 6, 9, 13, 18, 25, 33, 43, 56, 72, 92 and 120 years). In between it grows by scaling. The bucket swap is a small jump in branch detail, once every few game years per tree.
- Leaf shapes are drawn from simple rules (lobed, oval, compound, needles, scales), not from photos. Bark is drawn by shader patterns, not textures.
