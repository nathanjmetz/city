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

## Next

- Loop 3: parking, delivery trucks, and hooks for buses.
