# Airports

Brawn's airport hub (green-lit 2026-10-22). The player places a grass strip and a manager runs it like a small business. It grows only into the land right around it. Benchmark: Cities: Skylines 2 airports for gameplay, and the FAA's design rules for land.

## Sizes and land (FAA AC 150/5300-13B, runway lengths from AC 150/5325-4B)

| Size | Runway | Design code | Object free area | Protection zone (each end) |
| --- | --- | --- | --- | --- |
| Grass strip | 2,500 x 120 ft turf | A-I small | 250 ft wide, 240 ft past ends | 1,000 ft long, 250 to 450 ft wide |
| Paved airfield | 3,800 x 75 ft | B-II small | 500 ft wide, 300 ft past ends | 1,000 ft, 500 to 700 ft |
| Regional | 6,500 x 150 ft | C-III | 800 ft wide, 1,000 ft past ends | 1,700 ft, 500 to 1,010 ft |
| International | 10,000 x 150 ft | D-V | 800 ft wide, 1,000 ft past ends | 2,500 ft, 1,000 to 1,750 ft |

A town's airport grows as far as regional. An international airport is a regional asset (Brawn, 2026-10-23): it sits on open land, its own board runs it, and every town pays in. Its sizes are kept in `Airports.TIERS` for that work, which the Player interaction design thread leads.

The airport owns the runway's object free area plus a building area beside it. No buildings or lots may sit in the protection zones; farming may, as at real airports. Brawn's concern that a new player can't know how much room an airport needs is handled in three ways:

1. **See it.** While placing, the land for every size up to regional is drawn: green if clear today, amber with what's in the way.
2. **Give it land.** Reserve (kind `airport`) keeps roads and zoning off land for it.
3. **Tell the manager.** The selection panel's "Your word to the leader" (Permits) sets grow / your call / hold off. Buying land through the player's things with permits is step 2.

If a spot can't grow, the player can open a new airport out of town and connect it by road.

## Planes

Every plane is a real trip. It taxis, takes off into the prevailing south-westerly wind, and flies for a reason: spraying a farm in season (May to September), a day trip to a real nearby town (Vincennes, Jasper, Evansville and others), a visit, or a delivery from its factory town. It comes back by flying the pattern, a 3 degree final and a rollout, then parks. Planes leave only at the edge of the map, flying on to their town. Paths are worked out from a flight's few saved parameters, so every copy of the city flies the same planes.

## Development tree (shared with Brawn)

The manager unlocks these from its money and education and from the town and its neighbors:

- **Grass strip:** tie-downs, T-hangar, fuel. Crop duster base (farms nearby), skydiving drop zone (open farmland and people in reach).
- **Paved:** FBO and lounge, repair shop, flight school (education), charter (a wealthy area), air ambulance (a clinic).
- **Regional:** passenger terminal, rental cars and parking, air cargo center, control tower and airport fire station (FAA Part 139), hotel.
- **International:** customs, cargo sort hub, airline maintenance base.

Passengers and cargo come from your town plus neighboring towns in reach (regional trade API). The airport lifts them in turn: crop dusting, tourism, and shipping out by air.

## Code

- `scripts/sim/airports.gd`: sizes, land, manager, planes, flight paths, saving.
- `scripts/airport/airport_tool.gd`: placing, with the plan of every size.
- `scripts/airport/airport_view.gd`: the strip, hangar, windsock and planes.
- Numbers: `Balance.AIRPORT_*`.
- `tools/airport_shot.gd`: screenshots.
