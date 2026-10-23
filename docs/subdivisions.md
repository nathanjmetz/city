# Home builders and subdivisions

Brawn (2026-10-23): the game starts as a classic city builder, and as the town grows it shifts to big decisions. You play more like a mayor, answering proposals from leaders and developers. Home builders are the first of these.

## What the player sees

- When the town is big enough (300 people) and wants homes, but has fewer than 8 empty home lots, a home builder asks on the permit bell.
- The card offers two or three sites at the edge of town. Each tab shows the site on the map with a ghost of its streets and homes.
- The card says what the builder pays, and "If you say yes": new residents, school-age kids, car trips (daily and at rush hour), water and power load against what the town has, the yearly upkeep of the streets the town takes over, and the property tax it brings in.
- **Build site X** approves the site shown. **Say no** makes the builder wait 30 days.
- The builder lays the first phase's streets (two entrances) at its own cost and zones them for homes. The lots fill with the town's ordinary growth.
- The next phase opens once 70% of the last one is built, and no sooner than 9 game months.

## Real references

- The process follows Indiana's: purchase options on several farms, then a primary plat to the plan commission, then the secondary plat, built in phases of 20 to 60 lots.
- Streets are dedicated to the town, which maintains them from then on (Strong Towns).
- International Fire Code Appendix D107 requires two separate access roads for more than 30 homes.
- Stub streets for the next phase.
- Indiana annexation contiguity (IC 36-4-3-13): sites must touch the built town.
- What a yes means:
  - 2.5 people per household (US Census)
  - 0.6 school-age kids per new house (pupil-yield studies)
  - 9.4 car trips a day and 1 at rush hour per house (ITE Trip Generation, code 210)
- Builder size by town size: a local builder (2 phases), a regional developer (4 phases), then a master-planned builder (6 phases).

## Code

- Logic is in `scripts/sim/subdivisions.gd` (`Subdivisions`, `sim.subdivisions`). Numbers are in Balance under `SUBDIV_*`. The test is `tests/test_subdivisions.gd`.
- Permits gained `options` (sites), `pick` (the site approved, sent with the `permit` command), `effects` (the "If you say yes" lines, shown for any request that has them) and `who`. A request with options can't be redrawn.
- `PermitView` draws a request's `ghost` (`[x, z, angle, w, d, h]` houses with gable roofs) and `streets`, only while the card is open.
- The screenshot is `tools/permit_shot.gd -- homes out.png`.

## Performance

- Search: once a game month, and only when a builder may ask, it starts scouting for land.
  - It looks at a few roads each game hour (`SUBDIV_SEGS_PER_HOUR`, or `SUBDIV_TRIES_PER_HOUR` closer looks) over a window of the town's roads (`SUBDIV_SEGS_PER_MONTH`).
  - Where the scouting has got to is saved, so a loaded copy carries on the same way.
  - Cost: up to about 8 ms an hour in the big test town and 17 ms in the huge one. Starting costs about 12 ms in the huge town.
- Running subdivisions: a monthly count of lots sold. A new phase checks its street lines against nearby roads only.
- Ghosts and streets are drawn only while the card is open, as one ImmediateMesh.
