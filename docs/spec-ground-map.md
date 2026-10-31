# The ground map: spec (2026-10-29)

**Purpose (one sentence Nathan would say aloud):** Everything in my town knows what ground is already taken, so nothing gets built on top of something else, and when I add a bus stop the curb around it fixes itself.

**Nathan's words (2026-10-29):** "railroad tracks running right through the city like they're just a part of the ground. They run right underneath the buildings. I also noticed street signs in the middle of driveways... We need to get good at it though because we haven't yet implemented things like bus stops and items that will need to immediately make changes to the immediate environment like adjustments to the curb. These are things that are common and city skylines and should be very smooth and simple in our game."

**Why it happens today:** there is no shared "this ground is taken" map. Each thing that places itself checks only a few others. `CitySim._lot_blocked` asks 14 different `covers()` checks, each testing just three points of a lot, and none of them is the county railroad. Mailboxes (`mail_view.gd`), street lights (`street_lights.gd`), stop signs (`junction_view.gd`), trees and bus stops (`bus_net.gd _place_stop`) check nothing at all. The overlap auditor (PR #940) counted the result: 773 mailboxes in driveways, 510 lots and 194 buildings on the tracks, 339 lots on top of other lots.

## What it is

One shared map of **ground claims** (`GroundMap`, kept on the sim as `sim.ground`). Everything that takes ground registers a **footprint** (its outline on the ground), a **kind** and a **priority**:

| Priority | Kinds |
|---|---|
| 0. Ground facts | water, land too steep to build on (only bridges and cuts may cross) |
| 1. Rail | rail beds (town and county), grade crossings, the railroad's right of way |
| 2. Roads | right of way, pavement, curbs, medians, parkway, sidewalks, curb ramps, crosswalks, and **curb zones** (bus stops, loading zones, hydrant zones, bulb-outs) |
| 3. Public sites | services, hubs, parks, schools, warehouses, factories, docks and aprons on them |
| 4. Lots and fields | house and shop lots, farm fields |
| 5. Buildings | every building's walls |
| 6. Drives | drives, curb cuts, front walks, parking stalls, garage aprons, truck docks |
| 7. Posts | signals and stop signs first, then street lights and utility poles, then street-name signs, bus-stop signs and mailboxes |
| 8. Props | tree trunks, yard props, cars on drives |

**Before anything is placed, it asks the map first.** A lower claim that lands on a higher one is **refused**, and its placer tries the next spot (a mailbox steps along the curb until it's clear of the drive). A higher claim that lands on a lower one wins, and the lower one gives way by its own rule:

- **Moves:** posts and props slide along the curb to the nearest clear spot, up to a few metres. If none, they're left out.
- **Shrinks:** lots, fields and parking lots are cut back to the edge, like `road_wins.gd` does to fields today.
- **Removed:** a building in the way is bulldozed and paid back. Undo (`UndoLog`, 30 s) puts it all back, the way it already does when a road takes a water tower.
- **The player is told** in one line when something that cost money, or that the player placed, was moved or removed ("The new street took 3 homes on Elm St. Paid back $41,000. Ctrl+Z to undo."). Small things the game placed for itself (mailboxes, trees) move quietly.

## Curb edits: the model case

The curb is where most clashes happen, so each street side also gets a **curb ledger**: a sorted list of stretches along that curb (drive cuts, ramps, crosswalks, parking spaces, posts, curb zones). Asking "is there 30 m of free curb near here?" is a short walk down one list. This is the small shared curb helper the curb-clutter fix is making now, grown up.

**A bus stop** (the depot places them today, `bus_net.gd`; it draws a pole and sometimes a shelter, and claims nothing) would claim:

- **Curb:** about 100 ft (30 m) for a far-side stop, just past the crosswalk. A near-side stop needs about 100 to 125 ft, and a mid-block stop about 150 ft (TCRP Report 19). That stretch is red curb, no parking.
- **A boarding pad:** 5 ft along the curb by 8 ft deep (1.5 x 2.4 m), level and clear, as the ADA requires.
- **A shelter**, if it has one: about 5 x 12 ft behind the sidewalk, keeping 4 ft of sidewalk clear.

Then the things around it adjust. Curb parking (`TrafficSim._new_curb`) skips that stretch. Mailboxes, trees and street lights in it slide out. If a home's driveway sits in the stretch, **the stop slides** along the street until it fits, or takes a shorter stretch. It never closes a driveway.

**The same pattern serves:** loading zones (40 to 60 ft), fire hydrants (no parking within 15 ft each way, the UVC rule the code already cites), bike corrals (one parking space), a bulb-out (a curb extension the width of the parking lane, at a corner or a stop), and a crosswalk you add (no parking within 20 ft of it). Each is just a new curb zone kind with its own size.

## Data and cost

- **A sparse grid of 16 m cells:** cell -> the claims that touch it. Only cells with something in them are stored. Why 16 m: about one narrow lot or one street's width, so a post or mailbox touches 1 to 4 cells, and a 100 m road band touches about 7 to 14. Smaller cells (4 m) would need about 16 times the memory for long roads. Bigger cells (64 m) would make a mailbox look through hundreds of claims on a busy block. Step 1 times 12, 16 and 24 m (the auditor uses 24) and keeps the best.
- **Per claim:** owner key and part (`lot:322:1:1107/drive`), kind, priority, box, outline points, and for curb claims the street side plus start and end along it. Stored in packed arrays, about 100 bytes each.
- **Memory:** the big test town has about 83,000 footprints (the auditor's count). Roads stored as one band per road, not 31,000 sidewalk pieces, makes it about 60,000 claims, roughly 10 to 20 MB. Step 1 measures it.
- **Query cost:** one placement looks at 1 to 4 cells and a few dozen boxes, then does an exact outline test on the 1 to 3 that touch. That's well under a tenth of a millisecond.
- **Update on change only:** when an owner changes (a road built, a lot built, a stop moved), it takes back its old claims and files new ones. Nothing is scanned every frame. A full rebuild runs only on load, a few steps per frame, like `save_steps`.
- **The same answer on every copy:** no random draws. Claims are named by owner key, not by the order they came in. Ties go to priority, then kind, then owner key. The map changes only through the sim's commands, so every player's copy and every reload builds the same map.
- **What's saved: nothing new.** Everything it holds comes from things already saved (`roads`, `buildings`, `parcels`, `services`, `rail`, `buses`...; see `CitySim.save_steps`), so it's rebuilt from the sim on load. Curb edits the player places by hand (step 6) are saved by their owner, not by the map.
- **Shared regions:** each town's map holds its own claims, plus the region's claims that cross its land (county rail, state highway and county road rights of way), converted with `terrain_offset`. It never holds a neighbor town's claims. The region server needs nothing new. One catch: today the browser leaves county rail out (`CountyRail.drawn()`, `sim.county_rail`). Rail claims change where lots go, so both versions must agree (question 4).

## How we get there without breaking things

- **One placer at a time,** each behind the overlap test (`tests/test_overlaps.gd`). Its `KNOWN` counts may only go down. When a placer moves over, its rows go to zero and stay there.
- **Most visible first:** the auditor's visibility score orders the work. Rail under buildings and buildings on buildings (5), then posts in driveways, rail across lots and roads (4), then trees, stalls and props (2 to 3).
- **The two fixes in flight** (`fix-rail-overlaps`, `fix-curb-clutter`) become the map's first users. Their checks move into it, unchanged in result.
- **Corner cut, named:** once the auditor and the map share the same footprint code, the test proves "placers obey the map", not "the footprints match the art". The art still drifts unless the look-check screenshots catch it.

## Build order (each a few hours for one builder)

1. **The map itself.** `GroundMap` with claims, the grid, the curb ledger, ask and register. It's filled on load from the auditor's footprint code (`tools/overlap_audit.gd collect`), moved into `scripts/sim/`. Tests: it matches the auditor's shapes, the same town gives the same map twice, and the load time and memory in the big town are written down.
2. **First users: rail and curb clutter.** The two fixes ask the map. County rail is a claim for `_lot_blocked`. Mailboxes, stop signs, lights and trees ask the curb ledger. Lower `KNOWN`. Add a **Ground view** (a view that tints each claim by kind, and outlines clashes in red) so Nathan can see it.
3. **Lots and buildings.** `_lot_blocked` asks the map once instead of 14 `covers()` checks. Lot on lot and building on building go to zero.
4. **Who gives way.** Move, shrink and remove all go through one path in the map, wired to `UndoLog` and the one-line notice. `road_wins.gd` asks the map who's in the way.
5. **Bus stops claim the curb.** Each stop gets a red curb stretch, a pad, a no-parking sign, and a shelter claim. Curb parking, mailboxes and trees step aside, and the stop slides off driveways.
6. **Curb edits by hand.** Add a loading zone, a hydrant, a bulb-out and a crosswalk, each a curb zone kind, placed from the road tools, saved with the streets.

## What to decide

1. **Old towns with buildings on the tracks:** buy them out once on load, paid back, with one card saying how many *(pick)*, or leave them until they're rebuilt?
2. **A bus stop that lands on a driveway:** the stop slides along the street *(pick)*, or the driveway closes?
3. **Telling you when things move:** only for things that cost money or that you placed *(pick)*, or every change?
4. **Railroads in the browser version:** add them, so a town plans the same lots on both *(pick)*, or keep the browser without them and accept that towns differ?

## Done when (Nathan can click through this himself)

1. Open the big test town. Go to the worst rail spot from the audit (-718, -162). The tracks run clear, with no house or lot on them.
2. Drive down any home street. No mailbox, stop sign or street light stands in a driveway.
3. Turn on the Ground view. Claims show tinted by kind, with no red clash outlines on the streets you visited.
4. Build a bus depot and wait a game day. Click a stop. It has a red curb about 100 ft long, a pad and a no-parking sign. No car is parked there and no mailbox stands in it.
5. Draw a street through a row of houses. A one-line notice says how many homes it took and what was paid back. Ctrl+Z puts them all back.

**Depends on:** the overlap auditor (PR #940) and its test, and the two fixes in flight.
