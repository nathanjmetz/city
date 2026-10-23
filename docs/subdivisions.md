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

## What a project needs (ProjectNeeds)

Every phase checks with the town's other leaders before it starts. Shortages cost the builder and slow the job, never the town's money.

- **Gravel:** about 400 tons a home (NSSGA) at about $16 a ton (USGS), with the price doubling every 30 miles. With a quarry (an ore company) in town it's local. Without one it's trucked about 40 miles: the builder pays more and the job takes 25% longer. Concrete rides the same line: about 45 cubic yards a home, poured within 90 minutes of batching (ASTM C94), so ready-mix plants sit by quarries; without one the builder pays a haul charge of about $1 a yard a mile.
- **Water ahead of time:** once the water system is three quarters full and the utility can't pay for its next well, intake or tower, the superintendent asks the town to pay for it on the bell (plan at 75%, build by 90%: Texas's 75/90 rule; big utility projects go to the council). A yes builds it now; a no lets it save up, and a full system stops new hookups.
- **Builders:** about one crew per 1,500 people (at least 2), each with about 6 houses going up. Past that, labor costs climb and the phase takes longer.
- **Water and power:** a warning past 90% of capacity (the Texas 75/90 rule). At 100% there are no new hookups, a moratorium, and the next phase waits.
- **Winter:** paving season closes December through February, so new phases wait for spring.

The card shows these needs for each phase. The bell's PROJECTS list shows each subdivision still building, what it is waiting on, and what shortages have cost the builder so far. The numbers are the `NEEDS_*` constants in Balance. A phase that ran short waits that much longer before the next one opens. It is a handful of sums once a month per project, so there is no per-frame work.

## The land use plan (LandPlan)

In Zoning, the player can outline big, soft areas as a future land use map: homes, shops, jobs or farms, plus Erase. It is a plan, not zoning, so nothing is blocked. Builders never propose homes on land planned for something else. They look at land planned for homes first. A subdivision inside the plan opens each phase in 75% of the time (`PLAN_FASTER`), because a plat that matches the comprehensive plan is routine for the plan commission. Real reference: Indiana's comprehensive plan and its future land use map (IC 36-7-4-500). A new area is cut out of the older ones, so the map stays a handful of pieces. The command is `paint_plan` {points, kind}, it is saved as `land_plan`, and the screenshot is `tools/permit_shot.gd -- plan out.png`.

## Streets wear out (StreetAge)

Every paved street is resurfaced about 25 game years (`STREET_LIFE_YEARS`) after it is built or last resurfaced. The town pays then, about $130 a lane-metre: a mill and overlay at INDOT prices, with a 20 to 30 year asphalt life per FHWA. A builder's streets are free today and a bill in 25 years. A town that grew fast meets the whole bill at once, which is Strong Towns' warning.

- Ages are kept on 40 m squares, so a street split by a new junction keeps its age. The county's roads a town starts on get spread-out ages.
- The builder card shows the repair bill.
- The Economy page shows STREETS COMING DUE: what was paid this past year, and a forecast in five-year bars.
- It runs once a month: about 3 ms on a huge town, and about 22 ms the first month after loading, when every street is measured.

## The builder's park

A subdivision of 60 homes or more sets aside a pocket park halfway through, on the middle of that phase's cross street, at the builder's cost (Indiana subdivision rules ask for park land dedication or a fee in lieu). The town keeps it up after, and the park board grows it like any other park. Nothing new on the card.

## The city engineer (CityEngineer)

The engineer takes a traffic count at four rush hours each game month (`ENGINEER_COUNT_HOURS`): every car on the roads, whether that road is moving under 40% of its speed limit (Highway Capacity Manual level of service E or F), and whether a car on a hub's own road has any business with that hub. Once a month the worst problem goes to the bell, one at a time, each with a ghost, an argument for why, and what the town pays:

- **A hub road used as a shortcut** (from 2,000 people): a farm lane or an oil company's lease road with through cars. Choose between paving it as a town street or "local traffic only", with signs and a gate arm that let the hub's trucks through (`TrafficSim.close_segment(seg, true, "always")`). This is Brawn's tension between hub leaders and the mayor.
- **A jammed two-lane road** (from 10,000 people): widen the jammed stretch to four lanes, or add a centre turn lane.
- **A busy alley**: pave it into a narrow street.

The town pays on approval. When the money isn't there, the job waits. Counts are saved. The cost is four counts and one look a month. `tools/permit_shot.gd -- engineer` shows the card.

A neighborhood with more than 30 homes and only one road in (a road whose removal cuts it off) comes first: the engineer proposes a new street from it to a public road at least 150 m from the first way in, through open ground only. The fire code asks for two separate ways in past 30 homes (International Fire Code D107), and subdivision rules make builders stub streets to the next parcel for the same reason. A neighborhood the town turned down, or that has no room for one, comes up again after three years. The network walk (Tarjan's bridges) runs only in a month after the roads change.

## Code

- Logic is in `scripts/sim/subdivisions.gd` (`Subdivisions`, `sim.subdivisions`). Numbers are in Balance under `SUBDIV_*`. The test is `tests/test_subdivisions.gd`.
- Permits gained `options` (sites), `pick` (the site approved, sent with the `permit` command), `effects` (the "If you say yes" lines, shown for any request that has them) and `who`. A request with options can't be redrawn.
- `PermitView` draws a request's `ghost` (`[x, z, angle, w, d, h]` houses with gable roofs) and `streets`, only while the card is open.
- The screenshots are `tools/permit_shot.gd -- homes out.png` (the card) and `-- projects out.png` (one under way).

## Performance

- Search: once a game month, and only when a builder may ask, it starts scouting for land.
  - It looks at a few roads each game hour (`SUBDIV_SEGS_PER_HOUR`, or `SUBDIV_TRIES_PER_HOUR` closer looks) over a window of the town's roads (`SUBDIV_SEGS_PER_MONTH`).
  - Where the scouting has got to is saved, so a loaded copy carries on the same way.
  - Cost: up to about 8 ms an hour in the big test town and 17 ms in the huge one. Starting costs about 12 ms in the huge town.
- Running subdivisions: a monthly count of lots sold. A new phase checks its street lines against nearby roads only.
- Ghosts and streets are drawn only while the card is open, as one ImmediateMesh.
