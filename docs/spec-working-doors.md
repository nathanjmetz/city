# Working doors: spec (2026-10-29)

**Purpose (one sentence Nathan would say aloud):** When I zoom in, I can watch my town trade: trucks back into open docks and cars pull into open garages.

**Nathan's words (2026-10-29):** "it would also help if we had working doors and garage doors. they could open to black, allowing things to come in and out. this could also apply to barns, factories, etc. it is one way we could visualize trade, storage, selling and buying, etc." Also: "lets make this game look totally real. better than CS2" and "we should primarily only build the desktop download, not the browser."

**Who sees it:** desktop players at High graphics and up, zoomed in close (under about 150 m). **The one main thing:** a dock door rolled up, dark inside, with a truck backed against it.

## Door kinds, and how each one moves (from real buildings)
- **House garage (sectional door):** the panels roll up into the ceiling on tracks. A real opener takes 10 to 12 seconds. Cars in our game drive at real speed, so doors do too: about **10 seconds on screen**. That is 100 ticks of the town's clock, or about 2 hours on the calendar; nobody sees that, because the sky moves so slowly.
- **Dock door (warehouse, factory):** a 9 x 10 ft sectional door at truck-bed height. The truck backs up to the rubber bumpers first, then the door goes up (about 12 seconds) and the steel lip of the dock plate (a "dock leveler") drops onto the trailer floor. When the truck is done, the lip lifts, the door comes down, and the truck pulls away.
- **Factory and shop overhead doors (12 x 14 ft):** like a garage door, but taller and slower, about 14 seconds. A truck drives right inside.
- **Barn and machine shed sliders:** a big panel slides sideways along a track on the outside of the wall, by hand, in about 4 seconds. On a farm it stays open all working day.
- **Roll-up shutters (shop stockrooms):** steel slats wind up into the box over the door, about 12 seconds.
- **Man doors (people-size doors):** skipped. At 1 m wide they are too small to read past 40 m.

**"Opens to black":** the opening is a dark card with a fake room behind it. A shader paints it with depth: floor, side walls and a ceiling, all dim. (Teach: this trick is called *interior mapping*. A flat card looks like a room, and it costs about the same as a window.) If it's cheap, the card also shows a hint of what's inside: racks of pallets at a dock, shelves at a shop, hay at a barn, and in a garage the back of the car in its own paint. At night an open garage shows the opener's warm bulb.

## What opens them
Each door is worked out every frame from what the sim already knows and saves. **Door state is never saved,** and nothing here changes the save format.

| Event | Door | Sim knows it today? |
|---|---|---|
| A car coming home to its garage | garage opens about 10 s before it arrives, closes after it parks inside | **Yes**: the car's `to_spot` is a "garage" spot (TrafficSim `_reserve`, SiteLayout.house) |
| A car leaving its garage | opens, car backs out, closes | **Needs a small new signal**: today a car pulls out the same tick its trip starts. New: it waits about 8 s for the door (`door_t`, the tick its door started up, kept on the parked car's record, which is already saved; old saves just skip the wait) |
| A truck to a factory bay | overhead door opens, truck drives in out of sight | **Yes** for arriving (a "bay" spot, hidden). Leaving uses the same 8 s wait |
| A truck at a warehouse | dock door opens with the truck backed in | **Needs a small new signal**: today warehouse trucks stop at the curb out front. New: the warehouse's place gets one dock spot per dock door the art draws (plain math from `Warehouses.spec`, no dice). New spots go on the **end** of the list, so saved spot numbers still match |
| A delivery truck at a shop | stockroom roll-up opens while it's parked there | **Yes**: a truck parked for that shop |
| Ambulance, police cruiser, bus, line crew truck | their garage bays open as they leave and come back | **Yes**: all are real trips to and from their bays |
| Farm machines, planting and harvest | machine shed door open with the tractor out (April to November), the combine out at harvest, shut in winter | **Yes**: by month (FarmsteadParked) |
| A fire engine leaving the station | bay doors open | **No.** Fire calls don't exist yet. Leave it for its own feature |

**How trade shows:** every load in town rides a real truck (Logistics), every 3 seconds of play. A busy warehouse has more trucks backed in, so more of its docks stand open. A quiet one is shut. You can see who is busy from the street.

**Where doors are:** each art builder logs its doors through one shared helper, `_door_log(kind, centre, facing, width, height, colour)` on HouseBuilder. It works like the `_glass_log` they already keep for windows. That's one line in each door function (`_garage`, `_dock_door`, factory `_door`, civic `_overhead_door`, the roll-ups and shed doors), plus the list riding along on the finished mesh beside its "parts". Everything else is new files: `scripts/views/door_view.gd` (draws) and `scripts/sim/door_events.gd` (reads the traffic, matches each garage, bay or dock spot to the nearest door it faces, and works out how open each door is). The art session is busy in `scripts/art/`, so these lines go in as one small PR after theirs.

**Corner cut:** the closed door stays in the building's mesh. The dark card sits 10 cm in front of it and grows up from the bottom, with the door's bottom rail at its top edge. From a steep side angle you may catch a thin edge. A real hole would mean redrawing merged buildings, which is far costlier.

## Cost
- Drawn only near the camera: **150 m on High, 200 m on Ultra, 250 m on Cinematic** (new knobs `doors_m` and `doors` in `GraphicsQuality.BUDGETS`). Past that, every door is shut, as today.
- **At most 32 / 48 / 64 doors open or moving at once** (High / Ultra / Cinematic), nearest first.
- **3 draw calls** (dark cards, moving panels, dock lips), instanced. **Under 0.3 ms a frame** of CPU: it looks only at the cars near the camera and re-reads parked vehicles only when `parked_version` changes. **Under 4 MB** of memory (one small sheet of interior pictures).
- Low and Medium: off. **The browser: nothing new**, and it never loads the door view.

## Build order (each step a few hours for one builder)
1. **House garages (the most seen).** The shared `_door_log` helper and its line in `_garage`, the door view, door events, and the 8 s wait before backing out. Done when a car on screen waits, the door rolls up, it backs out, and the door rolls down.
2. **Trade: warehouse docks and factory bays.** The warehouse dock spots, trucks backing to the bumpers, the leveler lip, and factory overhead doors.
3. **Barns, sheds, shops and service garages.** Shed sliders by month, shop roll-ups on delivery, and the ambulance, police, bus and crew bays.
4. **Polish and measure.** Interior hints (racks, shelves, the car's rear), the night bulb, shot 11, and before-and-after times from `tools/look_round.gd`.

## In the 10 fixed shots (`tools/look_round.gd`, branch look-round-shots)
- 01 street, 02 40 m and 03 100 m are inside reach. They show a garage mid-roll only if the town happens to be doing one at tick 150 (the same each round).
- 07 night 100 m shows any open garage's warm bulb.
- 04 300 m, 05 1 km and 10 farm edge 300 m are past reach and must look **unchanged**. That checks that nothing pops in the distance.
- **Extra shot needed: `11_docks_60m`,** 60 m over the factory row on the big town's east edge, July 10:30, with trucks at the bays. The big test town has no warehouse, so step 2 adds one there and says so in that round's notes.

## Decisions for Nathan
1. **How long a truck stays at a dock.** My pick: **A, about 30 seconds**, so you see it sitting at the open door. Today trucks unload in 2 or 3 seconds and leave. Loads still count when the truck arrives, so money doesn't change; trucks are just busy a little longer. B: keep the quick stop (the door opens, the truck touches it, and the door shuts).

## Done when (Nathan can click this through himself)
1. On the desktop at High, zoom to about 50 m over a street of houses in the morning. A garage door rolls up in about 10 seconds, a car backs out, and the door rolls down.
2. Watch a house in the late afternoon. Its door opens before the car turns in, the car drives in, and the door shuts behind it.
3. Find a warehouse. Trucks back up to the docks, the doors go up onto a dark inside, and a busier warehouse has more doors open.
4. A farm in October has its shed door open and the combine out. In January the door is shut.
5. At night an open garage glows warm.
6. Zoom out past 250 m. Doors are shut, and nothing pops.
7. Switch graphics to Medium. No doors move.
