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
- `tools/traffic_shot.gd`: renders a busy test town for visual checks.

## Next

- Loop 2: traffic flow view (roads coloured by speed) and a junction tool to
  choose lights, stop signs or none, like TM:PE.
- Loop 3: parking, delivery trucks, and hooks for buses.
