# Buses

Brawn's rule (2026-10-22): the player places a hub and gives it land and
money. The hub decides everything else. Benchmark: Cities: Skylines 2 buses,
with line drawing replaced by the depot's own planning. Numbers come from the
FTA National Transit Database and TCRP reports (see `Balance`, "Buses").

## What the player does

- Places a **Bus depot** (Services > Transit) beside a street. It costs the
  city's 20% share of a garage and two buses.
- Sets its **funding** (click the depot, then − / +): None, Lean, Standard,
  Generous or Lavish, each a monthly subsidy paid through the services budget.
  These are broad steps, not dollar sliders (Brawn: no penny-pinching).
- Bulldozes things to make room, if they want. That's all. There's no route
  drawing and no nudges.

## What the depot does

- **Stops:** wherever at least 80 residents or workers live within a
  quarter-mile walk, at least 300 m apart (2 to 3 blocks). Stops stay put while
  people use them and follow the road if it's rebuilt.
- **Routes:** "pulse" loops out from the busiest downtown stop (the transfer
  point) through one slice of town and back, about 12 stops each. They're
  re-planned every half game day as the town grows.
- **Fleet:** enough buses for one every 30 minutes on each route (plus one
  where trips would be crowded), limited by its money (subsidy, fares and the
  FTA's 50% operating grant) and by the bays in its yard.
- **Fare:** kept within what riders earn ($1 plus up to $2 in the best-off
  areas). An educated director picks the lowest fare that keeps the depot in
  business, allowing for riders leaving as fares rise (elasticity −0.4). A
  self-taught director nudges the fare after each month. Education comes from
  how much of the town its schools reach (the agency code will take over).
- **Land:** when the yard is full and it can afford it, the depot buys a strip
  of free land directly behind or beside it. That land can be empty lots, but
  not built homes, farms, companies or reserves. It never opens a second site,
  and it grows to at most `HUB_MAX_GROWTH` times its first size.
- **School buses:** each elementary school keeps Type C buses for pupils who
  live more than about a mile away. On school days (not in June or July) they leave at 6:40 am and
  3:05 pm and park at the school.

## Code

- `scripts/transit/bus_net.gd`: the planning, money, buses and saving.
- `scripts/transit/bus_view.gd`: stop signs, shelters, standing buses and the
  Bus view.
- Hooks: `CitySim.buses` (ticked before logistics, saved as `"buses"`), the
  `set_bus_subsidy` command, and `Services.Kind.BUS_DEPOT` (its `size` grows,
  and its `subsidy` is part of the services budget).
- Buses drive on `TrafficSim.dispatch` trips (purpose `transit` or `school`).
  Traffic hands back arrivals, and only the buses' own reports are taken off
  its lists.
- `tests/test_transit.gd`, `tools/bus_shot.gd`.

## The director and development tree

The depot's director is an Agency leader (`scripts/sim/agency.gd`): their
schooling follows the town's education spending, and their caution sets how
much cash they keep in reserve. With the depot's own money they build from
`BusNet.TREE` as the town and region allow:

- Shelters and benches (busy stops get a shelter in the game world).
- Downtown transfer center, natural gas buses, electric buses.
- Park-and-ride, dial-a-ride vans, a school bus contract.
- Intercity coach: once the town has a neighbor and a county highway link,
  a coach drives out to the link (the map edge), spends a while in the
  neighboring towns, and comes home with riders. Fares and running costs go
  in the depot's books.
- Regional routes shared with two or more neighbors.

Land: free land beside the yard is bought outright. When homes or shops
stand there, the director files a land permit (`scripts/sim/permits.gd`) and
buys them out only after the player approves. The player's word on the
depot's panel (grow, your call, hold off) sets how eager it is to grow.

## Next

A taxi company hub, and switching to Traffic's round-trip `move()` once it lands.
