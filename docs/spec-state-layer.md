# The state layer: spec (2026-10-29)

**Purpose (one sentence Nathan would say aloud):** When a street is looked after, its yards, shops and sidewalks show it, and when the town lets it slip, you can see it slipping, so no two blocks look the same.

**Nathan's words (2026-10-29):** "i love the feel of an ideal city but it doesnt feel real. every intersection is exactly the same shape. every lawn is the same color. etc. etc. is it possible that we could add a layer in the game of items which indicate state. as an area improves, its "state layer" makes it look better. as an area gets worse, its state items degrade. a state item might be a car on cinder blocks in the front yard. or it might be an overflowing dumpster. get it?" Also: "lets make this game look totally real. better than CS2" and "we should primarily only build the desktop download, not the browser."

**Who sees it:** every desktop player who zooms in to a street (40 to 150 m up).
**The one main thing:** the small things in yards and on sidewalks that tell you, at a glance, how a street is doing.

## Part A: the state layer (props that show condition)

- **Homes, shops and apartments** already have a condition (0 to 1) and a tier (-2 derelict to 2 showpiece) from `PropertyCare` (`docs/property-care.md`). The builders already draw paint, weeds, boards, sheds and pools from it. The state layer adds the *things* on top: what sits in the yard, at the curb and by the door.
- **Streets get their own condition.** New `scripts/state/street_state.gd` works it out once a game month, in slices like PropertyCare, for each road piece (lots know their road piece as `lot.seg`):
  - 50% the average condition of the lots on both sides
  - 20% the pavement: 1 when just resurfaced, 0 at 25 years (`StreetAge`, `Balance.STREET_LIFE_YEARS`)
  - 15% trash picked up: 1, or 0 when trash has piled up on that street (`CivicHubs.trash[seg]` at `Balance.GARBAGE_PILE_LB`)
  - 15% the area's Funding slider (the same one PropertyCare reads)
  - A road with no lots (a county road) uses only pavement and Funding. The tier uses the same lines as buildings (`Balance.CARE_TIERS`). A busy street (traffic count) gets more litter and wear at the same tier.
  - **A block** uses the 80 m neighbourhood average PropertyCare already keeps (`_cell_avg`), for things that sit between lots: alley dumpsters, graffiti, sidewalk repairs.
- **Only the town's service decides condition.** The inputs are utilities, services, pavement, trash pickup, Funding and upkeep: never who lives there. No item makes fun of anyone. A car on blocks is somebody's stalled project, drawn plainly, not as a joke.
- **This round it is the look only.** Street condition does not change land value or taxes yet.

## Part B: plain variety (not tied to condition)

- **Lawns.** Today every lawn is one colour: a single `lawn` shade in the grass shader (`scripts/art/ground.gd`, `house_materials.gd`) plus noise. Real yards differ: one owner waters and it stays green in August, the next goes tan; shade under a big maple is darker and thinner; a showpiece has mow stripes; a dog run or a path to the mailbox is worn bare. The state view draws a **lawn wash** per lot: a flat tint over the grass (the way `WornPathView` rides just above the land), picked from the lot's seed, plus the date and rain.
- **Tree ages.** Today yard trees are sized 0.75 to 1.15 at random (`HouseBuilder._yard_trees`), so a new subdivision has the same big trees as a 1920s street. Real: staked saplings in a new subdivision, big maples over a 1950s block. Size should follow the building's age.
- **Driveways.** Today every drive is the same concrete. Marion has poured concrete (most homes after 1950), asphalt (darker, cracked), gravel (old homes and the edge of town), two-strip ribbon drives (pre-war homes), and brick pavers on a showpiece. Picked by era and seed.
- **Intersections.** Why they all look the same: `scripts/roads/junction.gd` gives every corner the same curb radius by road type (`RETURN_RADIUS`: street 6 m, avenue 9 m, boulevard 12 m), the same curb ramp with red domes (`DOMES_COLOR`), and `junction_marks.gd` paints the same two-line crosswalk at every marked corner. Real variety, all picked from the corner's node id and the town seed:
  - corner radius: old-town plats tight (3 to 4.5 m), newer streets 7.5 to 9 m, one bigger corner where trucks turn
  - curb ramps: none on an old corner never rebuilt, one diagonal ramp at the corner, or two newer ramps; domes red, yellow or grey iron
  - crosswalks: none on quiet streets, two lines, or the wide "ladder" by schools and downtown; paint fades from white to a grey ghost with street age
  - signs: a stop sign on one street or all four; green name blades, brown in a historic district; a post that leans
- Tree ages and driveways live in the house builder, which another session is changing now. The state layer works out each lot's kind (`LotLook`); the art builder reads it later, a one-line hook each, after that session is done.

**Everything is deterministic.** Every pick comes from a hash of the town seed, the lot key (or road piece or node id) and the item's name, plus sim facts. No random draws while drawing. Each lot ranks its items by its own hash, so as condition drops, items appear in that same order and stay put (the car that showed up last month is still there).

## The item list

Tiers: -2 derelict, -1 run-down, 1 improved, 2 showpiece. Triangles are rough guesses, to measure. Priority 1 goes in first.

| # | Item | Tier | Where | What you'd really see in Marion | Tris | Pri |
|---|---|---|---|---|---|---|
| 1 | Car on cinder blocks, wheels off, faded paint | -2, -1 | homes | A stalled repair on the drive or side yard | 450 | 1 |
| 2 | Overflowing dumpster, lid propped open, bags beside it | -2, -1 | shops, apartments | Missed pickups behind a strip center | 300 | 1 |
| 3 | Trash cans overflowing at the curb | -1, -2, or trash piled | homes | Garbage day missed, cans left out | 160 | 1 |
| 4 | Old couch or mattress at the curb | -2, -1 | homes, apartments | Bulk pickup that never came | 180 | 1 |
| 5 | Litter in the gutter and on the walk | street -1, -2 | street | Cups, bags, bottles; more on busy streets | 60 a patch | 1 |
| 6 | Potholes and lumpy cold patch | street -1, -2 | street | Freeze-thaw on old pavement, Feb to Mar | 20 | 1 |
| 7 | Cracked, heaved sidewalk slabs, weeds in the joints | street -1, -2 | street | Tree roots and frost lift the slabs | 40 | 1 |
| 8 | "For Lease" banner, soaped shop windows | -2 | shops | An empty storefront downtown | 30 | 1 |
| 9 | Pile of old tires by the garage | -1, -2 | homes | Tires cost money to get rid of | 220 | 2 |
| 10 | Sagging chain-link fence with a gap | -1, -2 | homes | Fence not fixed after a post rots | 200 | 2 |
| 11 | Faded "For Sale" sign, left up | -1, -2 (empty) | homes | A house that has not sold in months | 30 | 2 |
| 12 | Posted unsafe-building notice on the door | -2 (empty) | homes, shops | Indiana Code 36-7-9 orders are posted | 12 | 2 |
| 13 | Volunteer saplings along the fence and foundation | -2 | homes, shops | Mulberry and tree-of-heaven move in | 250 | 2 |
| 14 | Graffiti tags on blank side walls and dumpsters | block -2, -1 | shops, street | Plain spray tags facing an alley, no symbols | 8 | 2 |
| 15 | Faded or missing crosswalk paint | street -1, -2 | street | Paint lasts 1 to 3 years unless redone | 0 (paint) | 2 |
| 16 | Shopping cart left on the walk | street -1 | street | Near a grocery, walked home and left | 150 | 3 |
| 17 | Dead shrubs in a cracked planter by a shop door | -1 | shops | Nobody watering out front | 120 | 3 |
| 18 | Blue tarp on the roof | -1 | homes | Waiting on a roofer after a storm | 40 | 3 |
| 19 | Fresh mulch flower beds along the walk | 1, 2 | homes | Spring planting from the garden center | 150 | 1 |
| 20 | Flag on a porch bracket | 1, 2 | homes | Common on kept-up Grant County porches | 40 | 1 |
| 21 | Roll-off dumpster and a contractor's truck | moving up a tier | homes, shops | A re-roof or remodel under way | 350 | 1 |
| 22 | Big planters flanking a shop door | 1, 2 | shops | Main Street groups plant these each May | 150 | 1 |
| 23 | Lamp-post banners | street 1, 2 | street (avenues) | Downtown Marion's seasonal pole banners | 30 | 1 |
| 24 | New sidewalk slabs and new curb ramps, bright concrete | street 1 | street | Repair season; new slabs read whiter | 20 | 1 |
| 25 | Hanging flower baskets on the porch | 1, 2 | homes, apartments | Summer baskets on hooks | 80 | 2 |
| 26 | Raised vegetable beds out back | 1, 2 | homes | Tomatoes in after the May frost date | 120 | 2 |
| 27 | New mailbox on a post (brick at a showpiece) | 1, 2 | homes | Replaced after the plow knocked it down | 60 | 2 |
| 28 | Swing set or trampoline with a net | 1, 2 | homes | Back yards on a family street | 400 | 2 |
| 29 | Patio set and grill on the back deck | 1, 2 | homes | Summer evenings out back | 300 | 2 |
| 30 | Bistro tables and a bench out front | 2 | shops | A coffee shop or diner with sidewalk seats | 250 | 2 |
| 31 | "Now Open" banner, fresh awning | 1 (new) | shops | A new business's first weeks | 40 | 2 |
| 32 | Young street trees, staked, in tree grates | street 1, 2 | street | A streetscape grant's new plantings | 120 | 2 |
| 33 | Bike rack and lidded trash can at the corner | street 1, 2 | street | Downtown corner furniture | 100 | 2 |
| 34 | Black crack-seal lines and a clean hot patch | street 1 | street | The crew came through last summer | 0 (decal) | 2 |
| 35 | Hanging baskets on lamp posts | street 2 | street (downtown) | Watered by the city in summer | 80 | 3 |
| 36 | Solar lights along the front walk | 2 | homes | Small lights, lit at dusk | 40 | 3 |

Decline: 18 items (1 to 18). Improvement: 18 items (19 to 36).

## Cost

- **Where:** the desktop download only, at High, Ultra and Cinematic (`not OS.has_feature("web")` and tier at least `GraphicsQuality.HIGH`). The browser gets nothing new. The street condition math still runs everywhere (it is tiny and keeps every copy of the town the same).
- **How far:** props within 150 m of the camera, fading out from 130 to 150 m, like the near ring (`NearDetail`). Past that the builders' own tier look carries it. The lawn wash is flat and cheap, drawn to 400 m.
- **How:** one `MultiMesh` per item kind per 128 m square (the near ring's squares), placed a few jobs a frame. Props use the shared materials, so they get snow and night light.
- **Where in the yard:** only in safe spots: the curb strip, beside the drive, the back corners. The state view needs each lot's yard plan (drive, door, front of house) that the builder already works out. If BuildingView does not keep it today, keeping it is a one-line change for whoever owns `scripts/art/`.
- **Budget, measured with `tools/look_round.gd` (`frames.json`), Cinematic, shots 01 to 03:** at most +0.5 ms `draw_ms`, +40 draw calls, +250,000 triangles, +30 MB video memory; placing props at most 1 ms in any frame; the sim at most 1 ms per half-hour slice. Shots 04 to 10: at most +0.2 ms (the lawn wash only).

**Waiting on Nathan (one question):** should Medium (the 8 GB Mac mini) get a light version, the 8 priority-1 items within 100 m? My pick: yes, measured against the same budget at half size. Without it, the Mac mini sees none of this.

## The test town

`tools/look_round.gd` only (lives on the `look-round-shots` branch). After the warm ticks, with the game paused, it sets every built lot's condition by its 80 m square: tier = [-2, -1, 0, 1, 2] picked by `posmod(cx * 2 + cz * 3, 5)`. That puts several tiers in every shot from 40 to 100 m. It sets each lot to the middle of its tier band in `sim.care.cond` and `sim.care.tier`, marks those buildings changed so they redraw, piles trash on the two streets nearest shot 01, and ages the pavement on streets in derelict squares. The shot list stays the same. The round that adds this takes a fresh "before" set and says so in its notes, as the tool's own rule asks.

## Build order (each step a few hours for one builder)

1. **Yard props for homes and shops (most visible).** `scripts/state/lot_state.gd` (pure: lot key, tier, seed to a list of items and spots), `scripts/state/state_view.gd` (near ring, instanced, desktop High and up), the 8 priority-1 lot items (1 to 4, 8, 19 to 22), the look round's mixed test town, and a test that the same town gives the same items twice. Shots 01 and 02 show it.
2. **Street and block condition.** `street_state.gd`, then items 5 to 7, 14 to 16, 23, 24 and 32 to 35 along curbs and sidewalks. Clicking a home also shows its street, e.g. "Street: Run-down (potholes, litter)".
3. **Lawns, trees and drives (Part B).** The lawn wash per lot, and `LotLook` (tree age, drive kind) with the one-line hooks handed to the art owner. The rest of the priority-2 and 3 lot items.
4. **Intersections.** Corner radius, ramps, crosswalk style and wear, and signs in `scripts/roads/junction.gd`, `junction_marks.gd` and `street_sign_view.gd`.

## Done when (Nathan can click through this himself)

1. Open the desktop game at High or above. Zoom to a home street about 40 m up.
2. Cut that street's power and water (bulldoze the line that feeds it) and turn the area's Funding slider all the way down. Play fast for about 5 game days (a game day is a month). Click a home: Condition reads Run-down. You see overflowing cans at the curb, a couch or a car on blocks in a few yards, potholes and litter in the street. Not every yard: each one differs.
3. Put the power and water back, turn Funding up, add a park. Upkeep comes back slower than it fell, as in real towns: after about 20 game days you see a contractor's dumpster on a drive or two, then flower beds, flags and planters, bright new sidewalk slabs.
4. Zoom out to 300 m: the props are gone, the frame rate is the same.
5. Look at three corners and three lawns: different corner sizes, crosswalks fresh on one and faded on another; one lawn green, one tan, one darker under its tree.
