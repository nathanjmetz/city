# Traffic

Benchmarks: Cities: Skylines 1 and 2, and the TM:PE mod for CS1. Real US
driving and road rules break ties.

## What CS does, and what we copy

- Cars are agents with a trip (home to work, shops, home again).
- Pathfinding runs over lanes, with costs for distance, speed, turns and
  junction delay. CS2 adds live congestion to the cost.
- Lane arrows at junctions decide which lane can make which turn.
- Junctions have lights, stop signs or yield signs.
- Traffic flow (% of the speed limit cars manage) is the player's score.

## Where we go further

CS cars pick their lanes when the trip starts and stick to them, which
causes the famous one-lane queues. Here:

- Cars follow each other with the Intelligent Driver Model, and each driver
  likes a slightly different speed (88% to 112% of the limit).
- Lane changes use MOBIL: a car moves over when the gain beats the cost to
  the car behind, so faster cars pass and queues even out across lanes.
  Needed changes (to reach a turn lane) get more urgent near the junction.
- Every 30 seconds of driving each car re-plans the rest of its trip with
  live travel times and switches if the new way is 10% faster.
- A car that misses its turn lane takes a turn its lane allows and
  re-plans from there, instead of blocking the road.

## Real rules used

- Lanes are 3.6 m (12 ft, AASHTO). Speed limits come from the road type,
  and curves slow cars to the AASHTO safe speed for their radius.
- Lights where two big roads (avenue or larger) meet. Yellow time from the
  ITE formula (1 s + v / 2a, 3 to 6 s), then 1.5 s all-red.
- Right on red after a full stop. Permissive lefts yield to oncoming traffic.
- Stop sign (MUTCD R1-1) on the smaller road; all-way stop when equal
  streets cross; first to stop goes first.
- Roundabouts run counter-clockwise; entering cars yield (MUTCD R1-2).
- Cars don't enter a junction unless there is room on the far side.

## Code

- `scripts/sim/traffic_sim.gd`: the whole simulation (deterministic, stepped
  by `CitySim.tick()`).
- `scripts/traffic/traffic_view.gd`: draws the cars.
- `scripts/traffic/junction_view.gd`: traffic lights and signs.
- `tests/test_traffic.gd`: tests.
- `scripts/traffic/flow_view.gd`, `scripts/traffic/traffic_tool.gd`: the
  traffic view and junction tool.
- `tools/traffic_shot.gd`: renders a busy test town for visual checks.

## Player tools

- Traffic category (or J): roads coloured green to red by traffic flow, like
  the CS2 traffic info view.
- Junction cards: Auto, Lights, All-way stop, Stop signs (on the smaller
  road), None. Click a junction to set it, like TM:PE. Saved with the city
  (`set_junction` command, "junctions" in the save).
- Traffic flow counts cars held up by the car ahead, so an empty road reads
  100% even with stop signs, and queues pull it down (closer to CS than a
  raw speed average).

## Trips with a purpose (loop 3)

Like CS, every vehicle is a real agent with a job. Other systems send one:

```gdscript
var id := sim.traffic.dispatch({"ref": "farm:1", "pos": [x, z]}, {"ref": "mill:2", "pos": [x, z]},
    "grain", {"good": "grain", "amount": 12})
```

- `purpose` picks the vehicle (`VehicleTypes.for_purpose`), and the car keeps
  `purpose` and `cargo` for the view.
- On arrival, `{id, purpose, cargo, from, to}` is appended to
  `traffic.arrivals`; if no route exists, or a road edit strands it, to
  `traffic.failed`. The caller reads and clears these lists.
- A dispatched vehicle waits at its gate until there is room to pull out, so
  it is never dropped.
- `traffic.background_freight` (on by default) adds generic trucks until real
  industry dispatches its own.
- Cars pull out of and into driveways on smooth curves (CS2 benchmark).
- Vehicle size, acceleration, top speed and lane preference come from
  `VehicleTypes.spec(kind)` (owned by the Vehicles work).
- Building or upgrading a road re-routes cars where they are instead of
  removing them (CS2 behaviour).
- In-flight trips are saved exactly (`"traffic"` in the save) and two copies
  loaded from the same save drive identically, as multiplayer needs.

## Parking, people and walkers (loop 4)

Benchmark: CS2's parking and citizens (cars park in real spaces, drivers walk
in, every citizen has a name, the vehicle info panel), with CS1's rule that a
vehicle only leaves the map at the map edge. Brawn's rule on top: **vehicles
never disappear**. Every trip ends parked in a stall, driveway, garage, at a
loading dock, at the curb, or inside a factory bay, and later drives back out.

- **Places** (`traffic.place(ref)`): a lot, a dispatch site or the county
  highway edge, with its spots. `SiteLayout` replays the art builders' first
  random draws, fitted to the lot's real width and depth, so the stalls,
  garages, driveways, bays and doors match what is painted. If the art
  builders change their first draws, update `scripts/sim/site_layout.gd`.
- **Parked vehicles** live in `traffic.parked` (`at_place`, `spot`, `pos`,
  `face`, `hidden` inside a garage or bay, `owner`, `base`). A vehicle keeps
  its `id` for life; `trip` is the id of its current trip.
- **dispatch()** reuses an idle, unowned vehicle already parked at `from`
  (a depot's truck, or one that just finished a leg), else makes one there.
  After unloading it returns to its base, unless the trip ends at its base.
  Arrivals now carry `vid`, the vehicle's id.
- **move(vid, to, purpose, cargo)** sends a parked vehicle one more leg with
  no return, for buses going stop to stop or trucks on a round of calls.
- **People** (`sim.people`, `scripts/sim/people.gd`): one named person per
  resident, households sharing a surname and up to two cars, jobs filled every
  30 ticks, and outings by the clock (work 6 to 10, home 15 to 18, shopping in
  between). Every home, shop, factory, farm, company and service gets a unique
  name (`scripts/sim/names.gd`).
- **Walkers** (`traffic.walkers`) follow the sidewalks, keep to the right and
  cross at corners. People walk if it's under 260 m or their car isn't there,
  otherwise they walk to the car, drive, park and walk to the door.
  Everyone is simulated; `WalkerView` draws only those within 320 m.
- **Clicking** a vehicle or a walker (`Inspect.pick`) shows what it is, where
  it's coming from and going, why, its cargo, driver and owner, with a
  Follow button for the camera (CS2's vehicle panel). Lots show their name and
  who lives there.
- A driver stuck in a lane that can't reach the place parks at the curb just
  ahead and walks, instead of stopping in the road.
- Saves: `"people"` in the city save, and `parked`, `walkers` inside
  `"traffic"`. Loaded copies run identically.

## Streets closed to cars (plazas)

`traffic.close_segment(seg, on, deliveries := "night")` closes a road piece to cars without
removing it, as for a pedestrian mall (benchmark: real downtown pedestrian malls such as
Boulder's Pearl Street, where delivery trucks get set hours). The lots along it keep their
frontage. Routing never drives onto it, people drive to a lot nearby (`_parking_near`) and walk
the rest, and trucks drive in only when `deliveries` allows: `"never"`, `"night"` (10 pm to
6 am) or `"always"`. `may_enter(seg, truck)` answers for one vehicle now. Closed streets are
saved with the traffic state.

## Railroad crossings

When the gates are down (`sim.rail.crossings[i].closed`), cars stop at a line
5.4 m before the track's centre, which is the MUTCD and Uniform Vehicle Code
15 ft from the nearest rail plus half the gauge. A car too close to stop even
at a hard brake goes on through, as a driver would at a late signal. Traffic
finds where each crossing sits on each way again when track or roads change.

## Crosswalks and Walk signals

People on foot find their way over a graph of sidewalk ends. They walk along
a block, round a corner to the next road's sidewalk, or cross a road on the
crosswalk at the junction, where the sidewalk stops at the stop line. They
never cross mid-block or through the middle of the junction. Each crossing
costs 10 m extra, so people don't zig-zag. At a signal, a walker waits at
the kerb until the cars coming in on the road they cross have a red (the
MUTCD's Walk with the parallel green). The lights run on a fixed cycle, so
the waits are worked out when the walk starts and stored as `holds`
([metres along, steps]) on the walker. No per-tick work is added.

## Walks on the trail

People at home go out for a walk on the trail now and then. In the daytime,
20% of outings are walks for people whose street the trail crosses or runs
beside (within 40 m of the sidewalk). They walk along their own sidewalk to
where the trail meets the street, follow it for 400 to 1,200 m, and come back
the same way, like neighbours on an Indiana greenway (the Monon Trail or a
small-town riverwalk). Each walk counts toward the trails' "walked" figure,
and the person panel says "Out for a walk on the trail".

## Big towns: traffic flows (past 25,000 residents)

Brawn's decision (2026-10-23). Once a town has `FLOW_FROM` (25,000) residents,
people's own cars no longer drive one by one. Each household trip is timed over
its planned route at the roads' current speeds and then joins `flowing`. The
car leaves its spot, counts on each road it turns onto, and parks at its
destination when the time is up (vehicles never vanish: if the place was
cleared away, it goes home).

Every `FLOW_WINDOW` (a minute of driving), the cars that turned onto a road
give its hourly volume. The FHWA BPR curve, t = t0 (1 + 0.15 (v/c)^4), with
c = 1,900 vehicles an hour per lane (HCM base saturation flow), then sets that
road's share of the limit. That share pulls the road's speed down, which
routing and the traffic view already use, so jams build where the player sends
too many cars.

Trucks, buses, taxis and service vehicles stay full agents. The view draws
flowing cars within 900 m of the camera at their place on the route
(`flow_pose`), and they can be clicked like any car. Everything is in the sim
and saved, so towns stay in lockstep.

## Performance

`tools/perf_run.gd -- big 300` is the benchmark (budget in `scripts/perf/perf_budget.gd`).
Route planning uses a packed-array heap with turn costs precomputed per way (`_tcost`) and road
costs refreshed with speeds (`_wcost`). At most `REPLANS_PER_TICK` drivers look for a better
route each tick. `CitySim.zone_keys(zone)` caches sorted lot keys per zone. The sim is lockstep,
so nothing in it may depend on a camera; detail by distance belongs in the views only.

## Next

- Parking garages in real sizes, grown where parking runs short or placed by
  the player; people riding buses (with the Bus depot work); service vehicles
  answering calls.
