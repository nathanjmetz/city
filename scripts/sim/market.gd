class_name Market
extends RefCounted
## How big a market a developer sees from this town (Brawn 2026-10-24): not
## just the town's own people, but everyone within commuting reach. A remote
## hamlet is a small market however dense its few blocks are, so nobody
## builds apartments there; a new town beside a thriving one is a big market
## from day one, and developers come early.
##
## market = own people + sum of each neighbor town's people x reach
## reach  = 1 within MARKET_FULL (about 15 minutes' drive), fading to 0 at
##          MARKET_REACH (about 45 minutes, the edge of a commuting shed);
##          a funded I-69 stretches it.
##
## Each building type and tier needs a market of at least Balance.MARKET_MIN
## people before anyone builds it, and is fully in favour at twice that
## (ramp()). Real references are in balance.gd; the game never shows them.
## The region part comes from the region server (sync, hourly, like
## Regional) and is saved, so a reloaded town decides the same way.

## People in neighbor towns, weighted by reach (0 in a lone town).
var regional := 0
## How many neighbor towns are within reach.
var towns := 0


## Reads the neighbors' sizes and where they sit (called with the town's
## region view, like Regional).
func sync(region, me: String, sim) -> void:
	regional = 0
	towns = 0
	if not region.cities.has(me):
		return
	var at: Vector2 = region.cities[me].origin
	var far := reach_of(sim)
	var ids: Array = region.cities.keys()
	ids.sort()
	var sum := 0.0
	for id in ids:
		if id == me:
			continue
		var c: Dictionary = region.cities[id]
		var pop := int(region.ledger.populations.get(id, c.sim.stats.get("population", 0)))
		var w := weight(at.distance_to(c.origin), far)
		if w > 0.0 and pop > 0:
			sum += pop * w
			towns += 1
	regional = roundi(sum)


## How far (metres) people will drive here to work and shop: further with a
## funded interstate (Regional).
static func reach_of(sim) -> float:
	var far := Balance.MARKET_REACH
	if sim != null and sim.regional._stages("i69") >= 3:
		far *= 1.0 + Balance.MARKET_I69_REACH * sim.regional._benefit("i69")
	return far


## A neighbor's weight at `d` metres: 1 close by, fading to 0 at `far`.
static func weight(d: float, far := Balance.MARKET_REACH) -> float:
	if d <= Balance.MARKET_FULL:
		return 1.0
	return clampf(1.0 - (d - Balance.MARKET_FULL) / maxf(far - Balance.MARKET_FULL, 1.0), 0.0, 1.0)


## The market a developer sees: the town's own people plus its neighbors'.
func people(sim) -> int:
	return int(sim.stats.population) + regional


## The least market a type and stage needs (0 if any town will do).
static func min_for(type: String, level: int) -> int:
	var mins: Array = Balance.MARKET_MIN.get(type, [])
	return int(mins[clampi(level, 0, mins.size() - 1)]) if not mins.is_empty() else 0


## How far a market of `people` is along to a type and stage: 0 below its
## minimum, rising to 1 at twice that (rare at first, then common).
static func ramp(people: int, type: String, level := 0) -> float:
	var need := min_for(type, level)
	if need <= 0:
		return 1.0
	return clampf(float(people - need) / need, 0.0, 1.0) if people >= need else 0.0


## Whether a market this size supports the type and stage at all.
static func supports(people: int, type: String, level := 0) -> bool:
	return people >= min_for(type, level)


## Share of flats in apartment buildings standing empty. Lenders won't
## finance a new building while the existing ones sit this empty
## (Balance.MARKET_VACANCY).
static func flats_vacancy(sim) -> float:
	var cap := 0
	var occ := 0
	for b in sim.buildings.values():
		if b.get("type", "") == "apartments":
			cap += int(b.cap)
			occ += int(b.occ)
	return 1.0 - float(occ) / cap if cap > 0 else 0.0


func to_dict() -> Dictionary:
	return {"regional": regional, "towns": towns}


func from_dict(d: Dictionary) -> void:
	regional = int(d.get("regional", 0))
	towns = int(d.get("towns", 0))
