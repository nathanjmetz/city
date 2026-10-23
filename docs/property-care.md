# Property care and redevelopment

Brawn (2026-10-23): every owner responds to what the town gives it. Served
well, a property looks better and better; denied what it needs for too long,
it declines. As an area grows, developers ask (on the permit bell) to replace
houses with apartments, apartments with a high-rise, and a row of homes with
a shopping center. The player's job is to approve wisely and build the roads
and utilities that density needs.

## Condition (`scripts/sim/property_care.gd`)

Each building has a condition from 0 to 1 and a tier the art draws:

| Tier | Condition | Looks like |
|---|---|---|
| -2 Derelict | < 0.18 | boarded ground-floor windows, the lawn gone to weeds, brush, chalky faded paint, bleached roof; families leave |
| -1 Run-down | < 0.38 | faded paint, weedy patches |
| 0 Kept up | < 0.70 | as built |
| 1 Improved | < 0.88 | fresh paint, a new roof, a shed out back |
| 2 Showpiece | >= 0.88 | also an in-ground pool and a privacy fence |

Once a game month, a 48th of the town every half game hour, each owner
weighs what it gets and moves toward it: up at most 0.03 a month, down at
most 0.09. The needs (each 0-1, weighted):

- power and water (without them the target is capped at 0.1)
- safe tap water (no boil notice), sewer (past a small town, and for anything
  bigger than a house)
- fire, police, clinic and school cover (past 300 people)
- a street that moves (traffic speed on its own street)
- land value (parks, landfills, pollution, heritage; not its own condition)
- homes: jobs in town and being lived in; shops: customers; factories: workers
- kept-up neighbours (its 80 m grid cell and the eight around it; blight spreads)
- the Economy page's Funding slider for its area

Effects: land value by tier (0.75 to 1.08), so taxes follow; nobody moves
into a derelict building; a run-down owner doesn't build on; a vacant
derelict building stands 24 months, then is ordered down as unsafe (Indiana
Code 36-7-9). The inspector shows "Condition" and "Needs most".

## Developers' asks (`scripts/sim/redevelopment.gd`)

Monthly, one at a time, on the permit bell:

- **apartments**: 3-4 houses side by side, close in or on an avenue, in a
  town of 2,500+ that needs homes, become a three-storey walk-up.
- **highrise**: a full mid-rise in a city core (25,000+) buys the lots next
  door and goes to 12 storeys (rezoned to FAR 4.4).
- **shopping**: 4+ houses in a row on a busy road, in a town of 5,000+ with
  shop demand, are rezoned commercial for a strip or neighborhood shopping
  center (ICSC sizes).

Each card says what the project adds: power and water load (and a warning if
the town's supply is nearly full) and car trips a day on the street (ITE
trip rates), with how freely that street moves now. A yes assembles the lots
(`LotPlanner.merge_lots(..., cap_kind)`), repaints the zone for a rezoning,
and starts construction. Saying yes without the infrastructure shows up as
outages, boil notices, gridlock and then decline.

## Art and performance

`HouseBuilder.owner_care` (set by `BuildingView` around each build) drives it for
every builder, since all of them extend `HouseBuilder`. Colours ride in the
vertex colours and add-ons join the shared surfaces, so a property costs no
extra draw calls at any tier. Measured: a house is about 1,980 triangles and
6 surfaces; a showpiece adds about 100 triangles, a derelict house about 440
(boards and brush) plus about 1,000 flat ground triangles of weeds. A rebuild
takes about 9-10 ms on the main thread, so at most 3 buildings change look
per slice. See `tools/art_gallery.gd -- out.png care` and
`careshop`.
