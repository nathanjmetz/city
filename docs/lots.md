# Lots and zoning

Benchmarks: Midwestern plats and county parcel maps first (reality wins),
then the zoning of Cities: Skylines 2.

## How players zone

The player zones **street frontage**, not lots. In the Zoning panel, click a
street side to zone that whole block face (Shift does both sides), or drag
along streets. Tab switches to the round brush for odd spots. Unzoned land
shows no lot lines.

## How the game plats lots (`scripts/sim/lot_planner.gd`)

For every zoned street side, survey lines run square to the street every
3 m. Each line runs back until another road is as close as its own street,
so every bit of a block goes to its nearest street and the backs of the lots
meet in the middle. Lines along a curve fan out, so lots on bends come out
pie-shaped. The frontage is then cut into lots:

- Widths vary within real ranges per zone (`SIZES`; homes and shops 15 to
  24 m, 50 to 80 ft), scaled by neighbourhood
  wealth (`CitySim.wealth_at`, 0.85x to 1.3x).
- Corner lots are platted wider, and the two halves of a corner join into one
  lot with frontage on both streets. It fronts the busier street.
- Lots run to the middle of the block. Blocks too deep for one row get flag
  lots: a rear lot reached by a 6 m (20 ft) drive strip between two front
  lots. In open land with no street behind, lots stop at the usual depth.

The survey is cached per street side and redone only near changed roads,
zones or parcels. The same roads, zones and parcels always give the same
lots (needed for multiplayer).

## Parcels

A lot with a building is a **parcel**. It is saved under `parcels` in the
city save, keeps its exact shape, and isn't re-platted. A new road through it
trims it to the road edge, or drops it if more than a quarter is lost.
`CitySim.parcels_lost(keys)` reports the dropped ones.

## Lot fields

`key, seg, side, at_frac, front, road, zone_pt, dir, normal, to_curb, pos,
corners` (any number of points, counter-clockwise in x/z), `width, depth,
area, corner, flag, pad, plat_zone, sig`.

For a flag lot, `front` is the rear building pad and `to_curb` covers the
whole drive out to the street.

## Agency helpers (static, deterministic)

- `LotPlanner.can_merge(sim, a, b)`: same zone, sharing at least 3 m of lot
  line, within `MAX_LOT` for the zone and road.
- `LotPlanner.merge_lots(sim, a, b) -> a`: `a` keeps its key, and `b` is gone.
- `LotPlanner.split_lot(sim, key) -> [key, key + "/1"]`
- `LotPlanner.enlarge_lot(sim, key, polygon)`: adds only free, touching
  land. Hubs never jump to a second location.
- `LotPlanner.block_face(sim, key)`: the lots along the same street side,
  in order.

## Seeing it

`godot --headless -s tools/lot_map.gd -- grid out.png` draws a plat. The
scenes are `grid`, `curves` and `mixed`; add `-old` to see the old fixed
lots.

## Stress test (`tools/zoning_stress.gd`)

Zones 1000 made-up towns (grids, rotated grids, grids on odd land, skewed
crossings, triangles, curves, rounded blocks, deep blocks, T-junctions,
arterials, radial streets, cul-de-sacs, back lanes) in random orders of
clicks, Shift-clicks, drags, brush strokes and erases, with homes going up
between clicks in a third of them. Every lot is scored against Brawn's four
rules: odd shapes possible where the land forces them, nonsensical shapes
(overlaps, lots on roads, bowties, slivers, necks, tiny, landlocked, jagged)
impossible, plain rectangles the easy default on square streets, and odd
shapes where the street is straight and the corner square rare. It also
checks zoned frontage that got no lots, unused land between lots, that the
same zoning in reverse order gives the same lots, and that a save and reload
keeps them.

    godot --headless -s tools/zoning_stress.gd -- --count=1000 --out=out --pngs=2
    godot --headless -s tools/zoning_stress.gd -- --only=123 --out=out   # one town, its commands and a plat

`out/report.md` ranks the problems by how many towns show them, with an
example town for each; `--pngs` draws plats with the problem lots in red.
The Zoning stress workflow runs it on every change to the lot code and fails
when a problem shows up in more towns than `tools/zoning_stress_budgets.json`
allows. Lower a budget when a fix brings a problem down.
