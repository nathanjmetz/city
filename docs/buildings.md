# Building types

Benchmarks: real Midwestern towns first (reality wins), then CS2's building
levels.

The player still zones street frontage for homes, shops or industry. What
goes up on each lot is the owner's call (`scripts/sim/building_types.gd`),
made from what is around the lot:

| Zone | Type | When an owner picks it |
|---|---|---|
| Homes | House | Room for a yard; less likely in a crowded core |
| Homes | Row homes | 30+ buildings within 200 m: land is dear |
| Homes | Apartments | 20+ buildings within 200 m, or on an avenue |
| Shops | Shop | The usual neighborhood store |
| Shops | Shop with flats | The street side is a Main Street (2+ shops on it) |
| Shops | Offices | The town's college graduates support office jobs no office holds yet |
| Industry | Factory | Always |

Wealthier areas (`CitySim.wealth_at`) lean to detached houses and away from
row homes and apartments. Row homes take the whole lot as a row of narrow
homes, one per 7.5 m of frontage; Main Street blocks are built wall to wall
with a shopfront every 7-8 m. No re-platting is needed.

## Growth paths

Each type has stages (`BuildingTypes.TYPES`), and some turn into another
type at the top of theirs:

- House: family home, then two-storey home. In a very built-up area it can
  make way for row homes.
- Row homes: two storeys, then three.
- Apartments: walk-up, three storeys, mid-rise (5).
- Shop: corner store, then retail store. On a Main Street it gains flats
  upstairs and becomes a Main Street block.
- Shop with flats: two, three and four storeys.
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
