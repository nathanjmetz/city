# Trees that grow

Written 2026-10-25 (task 12). Nathan's question: "Can trees actually grow in the game?" Yes: every tree is now grown from three small facts, and yard trees start as saplings and grow over the game's years.

## How it works, in plain words

- **A tree is three facts:** its kind, a seed (where it stands) and its age. A yard tree's planting date is its building's build date, which saves already have, and its starting age comes from the lot's seed (see grown yards below); the one new thing a save keeps is the tick yards started coming in grown. A wild tree's age comes from its size, which the woods already work out from when the land was last cleared. So old saves load as before, and two copies of a town always agree.
- **Grown, not drawn.** Near the camera each tree is grown branch by branch by *space colonization* (Runions, Lane and Prusinkiewicz, 2007). Points of open air fill the crown shape the kind grows into. Each twig grows a step toward the points nearest it, and uses a point up once it reaches it. The crown grows year by year with the tree's real height, so the 10-year-old tree is the 60-year-old's younger self. As the crown lifts, the lowest limbs die off.
- **Limb thickness follows the pipe model.** A limb carries every twig beyond it, so its cross-section is the sum of theirs. The trunk is then scaled to the kind's real trunk thickness at chest height for that age.
- **The same seed always grows the same tree.** The seed comes from where the tree stands in the region (not on your screen), so every player sees the same tree in the same spot, whatever town they play from. Each kind has three variants, picked by the seed; the full and light versions of a tree use the same one, so the handover between them doesn't jump. Each tree is also turned and sized a little differently.
- **Seasons:** each kind keeps its own calendar on top of the game's seasons. Walnuts drop their leaves weeks before the oaks, maples turn scarlet to orange, oaks turn russet and hold their leaves, and sycamores turn brown early. Crabapples bloom pink, and red cedar bronzes in winter.
- **Wild woods get real Grant County kinds** by where they stand. Sycamore, silver maple, cottonwood and hackberry grow by creeks and rivers. White and red oak, sugar maple, black walnut, hackberry and honey locust grow on the uplands. Red cedar grows in old fields and fencerows.
- **Yards come in grown (2026-10-29).** Nathan, asked whether back-yard trees should start already grown in new neighbourhoods: "A. Yes, back-yard trees start grown; street trees still start small and grow". A finished home's yard trees (front, side and back; any lot tree that isn't in the parkway) start at the mixed ages of an established Indiana street, picked from the lot's seed so the same lot always gets the same trees (`TreeField.yard_age`): about one in seven young (nursery stock to 14 years), most 15 to 40 years, about one in eight a big old one (45 to 75). A tree is never older than its room allows (`HouseBuilder._yard_room`): at its starting age its crown stays off the walls as the planting already does, short of the shed, pool and garage, at most touching the next yard tree, and over the side and back lot lines by no more than a third. Shops', factories' and civic lots' trees have no room worked out, so they start no older than 40 years (the size their planter gave them). From there each grows on with the clock like any planted tree. **Old saves:** a town saved before this keeps every tree it had at the size it was (its homes were begun before `CitySim.grown_yards_from`, the tick after it is first loaded); only homes begun after that come in grown.
- **Yard trees** are sugar and silver maple, white and red oak, honey locust, blue spruce, and crabapple by the house. Before grown yards, and still for **street trees**, they go in as balled-and-burlapped nursery stock (ANSI Z60.1): a 2 to 3 inch caliper shade tree 12 to 14 ft (about 3.7 m) tall, a crabapple 8 to 10 ft, a spruce 6 to 7 ft (`TreeKinds.NURSERY_HEIGHT`), which is 5 to 10 years old on these growth curves depending on the kind. Most homes also get one or two **street trees** in the parkway between curb and sidewalk, about every 40 ft along the street, clear of driveways, mailboxes, streetlights, bus stops and the sight lines at corners: sugar and silver maple, honey locust, and red and white oak (the yards' own kinds, so they cost no more draw calls). After that they grow on the game's clock (a game year is 12 game days, about 29 minutes at normal speed).

## Detail by distance

| Distance (desktop, High quality) | What is drawn | Triangles per tree |
| --- | --- | --- |
| Under about 100 m | The full grown tree: limbs down to 2.5 cm, a leaf card at each twig | 5,000 to 12,000 |
| About 100 to 270 m | The light grown tree: big limbs only, one big card per cluster of twigs | 800 to 2,600 |
| About 270 to 530 m | The cheap card trees (TreeField), in each kind's real crown shape and size | about 300 |
| 530 m to the woods' reach (700 m low down, up to 1,600 m from higher up) | The light card trees: a few big cards, fitted to the same crown | about 60 |
| Wild trees past that, out to 3.5 km (2 km on Low, 2.6 km at most in the browser, 4.5 km on Cinematic) | The far woods (FarWoods): one quad facing the camera, the crown's size and colour, with a thin trunk | 2 |
| From high up | The ground's painted canopy | 0 |

**Trees to the horizon (2026-10-26).** Nathan: "it's pretty common to see a blank space a short distance ahead ... trees swell up out of the ground ... as I move around the trees, skip and flutter because they're changing drawing types." The wild woods used to stop at the cards' reach (700 m, 420 m on Low), shrinking toward that edge, so moving forward grew them up out of bare land; the edge was measured from a point ahead of the camera, so turning the camera grew and shrank them too; and each 256 m chunk switched from its full cards to its wider light cards all at once. Now every version of a tree stands at the same spot at the same size (the light cards are fitted to the full crown; the far quad is the crown's box), every hand-over is a dither by the tree's own distance from the camera (never from where it looks), the far woods carry every wild tree on out toward the haze, and a far tree drops out whole, each at its own distance, only where it is a few pixels across. The grown trees' lookup is aimed where a moving camera will be when it lands, so a fast camera no longer turns every grown tree back into a card. `tests/test_tree_lod.gd` checks the versions match and that a camera hovering at a hand-over never flips a tree; `tools/tree_lod_shot.gd` flies over the woods for pictures (`docs/tree-distance/`).

What it costs (2026-10-26, M5 Max, 1280x720, `tools/tree_lod_shot.gd`: 24 s low flight at about 140 m/s from the woods into the demo town, then parked; before and after run back to back). The desktop renderer is held to 60 frames a second on this Mac, so its frame times only show dropped frames.

| Setup | Frame ms while flying, average / 95th percentile | Draw calls (flying, median) | Triangles (flying) | Parked: frame ms, draw calls | Far trees |
| --- | --- | --- | --- | --- | --- |
| Desktop, High | 16.9 / 22.1 before, 17.2 / 22.7 after | 2,309 / 2,497 | 3.48 M / 3.75 M | 16.7, 2,711 / 16.7, 2,860 | 27,000 to 31,000 |
| Desktop, Low | 16.0 / 17.0, 16.0 / 17.3 | 972 / 1,032 | 0.54 M / 0.56 M | 16.7, 1,496 / 16.7, 1,542 | 9,000 |
| Browser renderer, Low (where the browser starts) | 12.1 / 19.6, 12.0 / 19.9 | 793 / 808 | 0.51 M / 0.53 M | 11.6, 799 / 10.8 to 12.9, 802 | 9,000 |
| Browser renderer, High (its top) | 15.2 / 24.0, 17.2 / 26.4 | 1,614 / 1,705 | 1.52 M / 1.74 M | 12.5, 1,403 / 12.3 to 14.0, 1,454 | 18,000 |

The far woods lay out a quarter chunk at a time, at most 1 ms a frame once the game is up (they may trail a fast camera at the horizon rather than slow it), and the loading screen waits for them only out to 1.5 km (about half a second more at the start). The extra triangles are mostly chunks drawing both their full and light cards across the hand-over. The browser at High costs about 2 ms more a frame while flying fast; at Low, where it starts, the cost is within run-to-run noise.

Every version is coloured and shaded the same way (`TreeLook.LEAF_SHADER`): summer leaves are a deep, slightly blue-grey green, as July photos of Indiana maples and oaks show (the kinds' leaf colours are turned less yellow in the shader), a crown is darker inside and on its underside and lighter on top, and the cards carry the same height-up-the-crown and cluster hue as the grown tree, so a near tree is not brighter or yellower than the same tree farther off (the look critic, 2026-10-29: near trees read "acid yellow-green" and "lit from inside").

The radii scale with the quality tier. The browser draws no full trees, and the light ones only from Medium up and nearer. A tree hands over from one level to the next with a dither, so nothing pops. A grown mesh is built on worker threads on the desktop, or in small slices on the main thread in the browser (each slice under about half a millisecond on this Mac; the grown trees get 1.5 ms of main-thread time a frame on the desktop and a tighter 1.0 ms in the browser). Meshes are kept by kind, variant and age bucket, up to 260; the ones drawn longest ago go first, and the ones in view stay (up to 520). Until a tree's mesh is ready, its card tree stands in. The bark and leaf shaders are got ready behind the loading screen, so the first grown tree on screen doesn't stall the game on the desktop (see below for the browser).

## What it costs (measured 2026-10-25, M5 Max MacBook Pro, 1600x900, Auto quality = Ultra)

| Test | Before | After | Notes |
| --- | --- | --- | --- |
| 16,000-person town, `tools/scale/combined_lab.gd` (PerfTown "20", camera 900 m out), normal speed | 62.7 ms a frame | 63.2 ms | Within run-to-run noise. Grown trees don't reach that far. |
| Same, fast speed | 115.6 ms | 115.6 ms | |
| Same, memory / graphics memory | 1,701 MB / 6,008 MB | 1,712 MB / 6,022 MB | |
| Same town after the review fixes, normal / fast speed (re-measured 2026-10-25 with other work on the machine, so all slower) | 84.0 / 130.5 ms (first version of grown trees) | 68.1 / 129.3 ms | No cost; the machine was noisier than the first measurement. |
| Same town, trees aged 30 years, camera at street level (`tools/trees/tree_lab.gd`), grown trees off and on in turns | 62.9 ms | 64.6 ms (+1.7 ms) | 58 grown trees, 155,000 triangles |
| Dense woods at the start, camera 60 m out (`tools/trees/grown_shot.gd`), off and on | 7.4 ms | 11.8 ms (+4.4 ms) | The worst case seen: 1,494 grown trees, 3.2 million triangles |
| Open country at the start, 60 m out | 6.9 ms | 5.8 ms | 34 grown trees: no measurable cost (noise) |

- The town's frames swing by about plus or minus 5 ms from run to run (most of the 60 ms is the town's own drawing). So trees were measured off and on in turns, in the same place.
- **Memory:** a grown mesh is 50 to 250 KB on the graphics card (16-bit compressed). The cache holds up to 260 of them, 2 to 3 MB in a typical view and under about 60 MB at most. The grown branches use about 3 MB of main memory. Graphics memory read by the engine swings by about 2 GB between runs of the same town, so it can't show a change this small.
- **Building them** happens on worker threads on the desktop: about 0.25 s for a kind's whole-life branches and 2 to 10 ms for a mesh, with nothing on the main thread except handing over the mesh (under half a millisecond each, within the frame's 1.5 ms). In the browser every step is cut into slices, each under about half a millisecond here: growing (scattering the points, each year's growth, straightening the limbs), cutting the tree to an age, building the bark and leaves, and handing the two halves of the mesh to the graphics card in different frames. Looking up which trees are near goes a few trees at a time (0.75 ms a frame on the desktop, 0.5 ms in the browser). The browser's way of building is timed in `tests/test_tree_growth.gd` against its 1.0 ms.
- **Slider:** the dense-woods case (+4.4 ms on the strongest Mac) is the one to watch on the Mac mini. The full-tree radius (TreeLook.NEAR) and the light-tree radius (MID) are the two dials, and both already scale with the quality tier.

### The worst frame: a camera jump into dense woods (`tools/trees/jump_lab.gd`)

The camera jumps 60 m over six far-apart woodlots it has never seen, grown trees on for half of them. Desktop at Ultra, browser renderer at High (its top). "Grown trees' own time" is the most the grown trees spent on the main thread in one frame.

| Setup | Worst frame before the review fixes | After | Grown trees' own time, before / after |
| --- | --- | --- | --- |
| Desktop renderer, worker threads | 937 ms (first grown trees on screen), then 125 to 134 ms on every jump | 95 ms, most jumps 31 to 45 ms | 194 ms / 3.3 ms |
| Desktop renderer, no threads (as the browser builds) | 163 ms, frames over 100 ms every half second while building | 36 ms | 129 ms / 2.6 ms |
| Browser renderer (`--rendering-method gl_compatibility`), no threads | 350 ms, then frames of 110 to 240 ms while building | 112 to 200 ms, once, when the first grown trees appear; otherwise 35 to 45 ms | 128 ms / 2.8 ms |

- What was fixed: the leaf and bark shaders were one copy per kind (each compiled when first seen); every wild tree's age took 30 steps to work out (a chunk of woods took 120 ms on a jump, grown trees or not); growing a kind's branches was one 110 to 130 ms block; and a new kind's first card mesh was made inside the lookup. The lookup also hit a script error when a chunk of woods was dropped while it ran (seen in these jumps); it now skips it.
- What is left: on the browser renderer the first grown trees on screen still cost one frame of about 110 to 200 ms (the graphics driver getting their drawing ready; the warm-up behind the loading screen didn't remove it there). And the browser now builds grown meshes more slowly (a handful in seven seconds after a jump, where it built 16 to 50 with the long frames), so card trees stand in longer.

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
- The same seed grows the same tree. Growing in the smallest slices gives the same tree as growing all at once: every node's place, parent, year, heading and children, the tree cut to an age (limb thickness, which limbs are kept, the trunk), and the mesh. Fewer than 1 in 100 slices of growing take over 1 ms. The 30-year-old keeps the 10-year-old's limbs. Limb thickness follows the pipe model. The light version is under a third of the full one.
- The stand-ins for exp, log, sin and cos match the maths library's to within about a millionth.
- A tree's seed is the same in a field moved and turned another way, and for a player whose own town sits elsewhere. A spot is the same kind (bottomland or upland too) and seed from three different towns' views.
- The mesh cache: over its size, exactly the oldest-drawn go; meshes in view stay (up to 520); exploring past 260 meshes, every newly made mesh is kept (the cache used to drop its newest first, so no new grown trees appeared once it was full).
- Known seeds give known variants and trees (whole numbers exact; sizes within a band). The full and light version of a tree are always the same variant, for every seed (they once used 3 and 2 variants, so a tree changed shape when it swapped), and stand within about 10% in height and 15% in width of each other.
- The grown trees keep to their frame budget: the browser's builder and lookup are timed against 1.0 ms and 0.5 ms.
- Each kind's own calendar: walnuts turn and drop first, oaks hold their leaves longest, evergreens stay green, crabapples bloom.
- Planted trees go in as saplings and grow with the clock. Wild trees are as old as their size. Brush is never grown.
- Grown yards: the same seed gives the same ages, in the mix above; a tree with little room starts young enough to fit and never smaller than nursery stock; a grown yard tree starts at its age and grows on from it without a jump (`test_tree_growth`). At its starting age no yard crown reaches a wall and two yard trees' crowns at most touch, and the same lot built twice gets the same trees and room (`test_house_lots`). In a built town yard trees start grown and street trees as nursery stock, a lot filed again gets the same trees, a save and load keeps them, and a save from before grown yards keeps every tree it had as it was while homes begun after it come in grown (`test_street_trees`).
- After a save and load, two copies of a town agree on every yard tree's planting date, and (the copy seen from another town's place in the region) on every wild tree's kind, seed, turn and age.
- This document describes every kind.

## What is the same on every computer

- **Exactly the same everywhere:** each tree's kind, seed and age, and so which variant and age bucket it is grown at. They come from whole-number hashes of where it stands in the region (rounded to the metre) and from sums and products of the growth curves (no maths-library functions), and the size-to-age table is built the same way. These are what players' games must agree on.
- **The same on the same kind of computer:** the branches themselves. The growth uses only the seeded random numbers, sums, products and square roots; plain stand-ins (TreeGrower.plain_exp_neg, plain_ln, plain_sin_cos) replace exp, log, sin and cos, whose last digits differ between maths libraries. But the engine's vector maths runs in 32-bit floats compiled for each processor, and an Apple chip, an Intel or AMD one and the browser may round the last bit differently (fused multiply-adds). A tiny difference can grow a slightly different twig layout. This changes only how a tree looks, never the game or a save.
- **Not exact:** limb thickness (a power law, `pow`), bark rings, leaf cards and leaf textures (sin, cos, atan2) can differ in their last digits between computers. Again, looks only.
- **Rounding at the metre:** two players' positions for one tree can differ in their last digits (each works in coordinates around their own town). A tree standing within about a millimetre of a whole-metre line could, rarely (about 1 in 1,000), be rounded differently for one of them and get another kind or variant there.

## Known limits

- The original "grown tree" from Nathan's other project was not on this machine, so this was built from the description: space colonization, the pipe model, and the same seed for the same tree.
- Only buildings' yard and street trees carry a planting date. Park, farm, median and other views' trees take their age from their size (mature), so they don't grow yet. Each needs a one-line hook like BuildingView's.
- A tree's branches change shape at its age buckets (2, 4, 6, 9, 13, 18, 25, 33, 43, 56, 72, 92 and 120 years). In between it grows by scaling. The bucket swap is a small jump in branch detail, once every few game years per tree.
- Leaf shapes are drawn from simple rules (lobed, oval, compound, needles, scales), not from photos. Bark is drawn by shader patterns, not textures.
