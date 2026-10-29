# Building types

Benchmarks: real Midwestern towns first (reality wins), then CS2's building
levels.

The player still zones street frontage for homes, shops or industry. What
goes up on each lot is the owner's call (`scripts/sim/building_types.gd`),
made from what is around the lot:

| Zone | Type | When an owner picks it |
|---|---|---|
| Homes | House | Room for a yard; less likely in a crowded core |
| Homes | Duplex | 15+ buildings within 200 m: a few doubles among the houses |
| Homes | Row homes | 30+ buildings within 200 m: land is dear |
| Homes | Apartments | 20+ buildings within 200 m, or on an avenue |
| Shops | Shop | The usual neighborhood store |
| Shops | Shop with flats | The street side is a Main Street (2+ shops on it) |
| Shops | Offices | The town's college graduates support office jobs no office holds yet |
| Industry | Factory | Always |

## The market decides what can appear

Before any of that, a type and stage must be one the market supports
(`Market`, Brawn 2026-10-24). The market is the town's own people plus the
people of every neighbor town within commuting reach: full within 15 km,
fading to nothing at 50 km (about a 45-minute drive), further with a funded
I-69. Each type and stage needs at least `Balance.MARKET_MIN` people and is
fully in favour at twice that:

| Type | Stages (market needed) |
|---|---|
| Apartments | walk-up 10k, three-storey 25k, mid-rise 100k, high-rise 150k, tower 400k |
| Duplex | 1.5k, fourplex 5k |
| Row homes | 50k, three-storey 100k |
| Shop with flats | two-storey any, three 5k, four 15k |
| Commercial block | three storeys 5k, four 15k |
| Offices | three storeys 10k, five 25k, eight 50k, 16 150k, 30 1M |
| Shopping center | strip 5k, neighborhood center 10k |

So a remote hamlet gets houses and a Main Street however dense its blocks
are, and a new town beside a big one draws apartments and bigger home
builders early. No new apartment building starts, and none grows, while 10%
of the town's flats stand empty (`MARKET_VACANCY`). The developers' asks on
the bell (`Redevelopment`) and the home builders (`Subdivisions`) follow the
same market. Buildings already standing are never torn down for it. The
real references (Census ACS housing mix by place size, ICSC trade areas,
real Indiana skylines) are in `balance.gd`; the game never shows them.

Wealthier areas (`CitySim.wealth_at`) lean to detached houses and away from
row homes and apartments. Row homes take the whole lot as a row of narrow
homes, one per 7.5 m of frontage; Main Street blocks are built wall to wall
with a shopfront every 7-8 m. No re-platting is needed.

## Growth paths

Each type has stages (`BuildingTypes.TYPES`), and some turn into another
type at the top of theirs:

- House: family home, then two-storey home, then home with addition (a
  family room, sunroom or two-storey wing built on out back, where the area
  is well-off enough). Near the middle of town it can become a duplex; in a
  very built-up area it can make way for row homes.
- Duplex: a two-family house drawn for its street's era (an up-and-down
  with a two-deck porch or an Indianapolis double before the war, a ranch
  duplex after it, a two-storey one lately), then a fourplex. It can make
  way for row homes or apartments.
- Row homes: two storeys, then three.
- Apartments: walk-up, three storeys, mid-rise (5).
- Shop: corner store, then retail store. On a Main Street it gains flats
  upstairs and becomes a Main Street block.
- Shop with flats: two, three, then four storeys. On a busy Main Street its
  owner can buy the lot next door along the street (an empty lot, a vacant
  building or a one-storey shop, never a protected or charming one) and
  build a Commercial block across both, three then four storeys
  (`BuildingTypes.wider_stage`, `assemble`).
- Offices: three storeys, five, then an office tower (8), as graduates allow.

A building can move up once it has stood a season (`DEVELOP_AGE`), is full
or wanted, and its owner is keen (`ambition`, from its seed; well-off areas
have more keen owners). One building a check, chosen the same on every copy
of the city. `CitySim.redevelop(key, type, level)` is the hook for agency.

## Building fields

`zone, seed, built, changed, cap, occ, type, level, units, flats, focc,
why`. `cap`/`occ` are residents for homes, jobs for businesses. `flats` and
`focc` are residents above a shop (they count as homes). `units` is the
number of row homes. `why` is the owner's reason, shown in the info panel.

## Offices and graduates

Education (`scripts/sim/education.gd`) works out the office jobs the town's
graduates support. Office buildings house those jobs: they count as jobs and
pay tax themselves, and only the rest stay abstract.

## Seeing them

`godot -s tools/art_gallery.gd -- out.png types` draws one of each;
`main` draws a Main Street. Looks are in `scripts/art/dense_builder.gd`
(first pass; the art thread refines them).
