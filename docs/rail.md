# Rail

A rail depot is a hub with its own leader and money (Brawn's hub model). The
player places it and can set a subsidy. The leader does the rest. Benchmark:
CS2 trains, with track drawing replaced by the leader's own planning.

## How it works

- **Place:** Services > Rail. The depot goes beside a road with about 420 m of
  fairly straight frontage. It costs $400k and starts with $6M of its own capital.
- **Plan:** the leader surveys a main line to the region first, then spurs to
  industry that would pay back its track (`RailPlanner`, a hybrid A* search
  over 40 m arcs).
- **Limits (FRA and AREMA):**
  - Curves: a spur bends no tighter than 146 m radius (12°), a main line no
    tighter than 291 m (6°).
  - Grades: 3% on a spur, 1.5% on a main line.
  - Cut and fill: up to 8 m. Over water, track goes on a bridge at 4× the cost.
  - Road crossings: at 70° or more, never at grade with a highway, and at least
    30 m from junctions.
  - What track avoids: built lots, farms, industry and reserves. Empty zoned
    lots can be crossed for a price.
- **Permits:** every new line is filed on the Permit bell (`scripts/sim/permits.gd`)
  with its route, cost and crossings. The player can approve, deny or edit it.
  Nothing is built without a yes. After a no, the leader backs off for a while.
- **Building:** crews lay 600 m a day, paid from the railroad's money.
  Grants cover 75% of new track, and the shipper pays half of a spur.
- **Trains:**
  - Movement: trains run on track warrants and reverse only at the start of a
    leg. Speeds come from FRA track classes and the curve formula.
  - Gates come down within v×25 s + 30 m of a crossing (49 CFR 234.225
    requires at least 20 s of warning).
  - Freight trips: the yard, then the siding, then the yard, then the region,
    and back. Passenger trains run from the platform to the region and back.
    Nothing vanishes.
- **Development tree** (`Rail.TREE`, on `Agency`): team track, then engine
  house, grain elevator spur, station, car shop, intercity stop, commuter
  trains, unit-train loop, intermodal yard, interchange and classification yard.
  - Each step is gated on the leader's schooling and profit, on the town
    (population, farms) and on the region (what neighbors buy and make, and
    links to them).

## Hooks for other systems

- **Traffic:** `sim.rail.crossings` is a list of `{seg, pos, closed}`, and
  `sim.rail.gate_down_near(p)` returns true while the gates are down at a crossing.
- **Ground:** `sim.rail.covers(p)` marks track and yards. Lots, fields, pads and
  zoning stay off them, and the trees are cleared (`Vegetation.sources`).
- **Grading:** `TerrainView.extra_grades` grades the ground under the track,
  and `RailView` fills it in.
- **Freight:** `sim.rail.ships_by_rail(sim, "site:N")` tells Logistics to skip
  trucks for that site.

## Files

- Sim: `scripts/sim/rail.gd`, `scripts/sim/rail_planner.gd`, plus the Rail
  section of `balance.gd`.
- Views and panels: `scripts/rail/rail_view.gd`, `rail_models.gd` and
  `rail_info.gd`.
- Tests and screenshots: `tests/test_rail.gd` and `tools/rail_shot.gd`.
