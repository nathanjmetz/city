class_name TownLaws
extends RefCounted
## Town laws (Brawn's pick, 2026-10-29: Frostpunk's Book of Laws and
## SimCity 4's ordinances, done the way a real Indiana town does it). Once
## the town incorporates it has a council, and a council passes ordinances
## (a settlement is run by the county, so it has none). Each law has a real
## trade-off, and none is ever forced: the council brings one to the bell
## when there's a real reason for it (residents petition, the plan
## commission asks), and the player says yes or no. The Economy page lists
## them too, so the player can adopt or repeal any of them at will.
##
## The laws, each after a real ordinance small Indiana towns pass:
##   truck_routes  Through trucks keep to the state and county roads,
##                 avenues and Main Street; neighborhood streets are for
##                 local deliveries only (towns post truck routes and "no
##                 trucks" signs under their power over local streets).
##                 Asked when through trucks are counted cutting down a
##                 neighborhood street. Trade-off: signs to buy, and trucks
##                 drive farther, so freight takes longer.
##   impact_fee    Every new home pays the town a fee for the parks and roads
##                 it will need (Indiana's impact fee law, IC 36-7-4-1300 on;
##                 park and road fees run about $1,000 to $4,000 a home).
##                 Asked by the plan commission after a year of fast home
##                 building. Trade-off: builders pass it on, so fewer homes
##                 start.
##   golf_carts    Golf carts may drive on town streets (Indiana lets a town
##                 allow them by ordinance; never along a state highway).
##                 Asked by a petition once the town has a good number of
##                 retirees. Trade-off: carts at 20 mph on the streets, and
##                 cars wait behind them; owners take short hops by cart
##                 instead of by car.
##
## Monthly and light: a few counts of trucks already on the road (the
## council's month) and one pass over the buildings. Deterministic.

signal changed

const HUB := "council"
const TICKS_PER_MONTH := 24 * CitySim.TICKS_PER_HOUR
## What the Economy page and the bell call each law. `does` is the tooltip.
const LAWS := {
	"truck_routes": {"name": "Truck routes",
		"does": "Through trucks keep to the highways, county roads, avenues and Main Street. Neighborhood streets are for deliveries only. Trucks take longer to get across town."},
	"impact_fee": {"name": "Impact fee on new homes",
		"does": "Every new home pays the town a fee for the parks and roads it will need. Builders pass it on, so homes go up a little slower."},
	"golf_carts": {"name": "Golf carts on town streets",
		"does": "Golf carts may use town streets, but not the highways. Some older residents buy one for short trips round town, and drivers wait behind them at 20 mph."},
}
## Road types a through truck stays off under truck_routes.
const LOCAL_STREETS := [RoadStyle.Type.STREET, RoadStyle.Type.STREET_NARROW, RoadStyle.Type.STREET_BIKE,
	RoadStyle.Type.STREET_ONEWAY, RoadStyle.Type.STREET_ONEWAY1, RoadStyle.Type.STREET_DIVIDED,
	RoadStyle.Type.BRICK, RoadStyle.Type.ALLEY]

## Laws in force: law -> the tick it was adopted.
var adopted := {}
## Bell requests: permit id -> law.
var asks := {}
## law -> the tick the council last took it up.
var last := {}
## Through trucks counted on neighborhood streets this month: segment ->
## count. Saved (the month's ask depends on it).
var through := {}


## True when a law is in force.
func has(law: String) -> bool:
	return adopted.has(law)


## True once the town has a council to pass laws.
static func can_pass(sim) -> bool:
	return sim.charter.status() != "settlement"


## Adopts or repeals a law (the Economy page, or a yes on the bell).
## Returns true if anything changed.
func set_law(sim, law: String, on: bool) -> bool:
	if not LAWS.has(law) or has(law) == on or (on and not can_pass(sim)):
		return false
	if on:
		adopted[law] = int(sim.tick_count)
		sim.economy.money -= cost(law)
	else:
		adopted.erase(law)
		if law == "golf_carts":
			_sell_carts(sim)
	if law == "truck_routes":
		sim.traffic.truck_routes = on
	changed.emit()
	return true


## What adopting a law costs the town once.
static func cost(law: String) -> int:
	return Balance.LAW_TRUCK_SIGNS if law == "truck_routes" else 0


## Sets everything that follows the laws in force (after a load).
func sync(sim) -> void:
	sim.traffic.truck_routes = has("truck_routes")


# ---------------------------------------------------------------- counting

## A look at the trucks on the road (CitySim, a few daytime hours a
## month): any truck whose route runs down a neighborhood street that is
## neither where it set out nor where it's going is passing through.
func count(sim) -> void:
	if has("truck_routes") or not can_pass(sim):
		return
	var t: TrafficSim = sim.traffic
	for list in [t.cars, t.flowing]:
		for car in list:
			if float(car.get("len", 0.0)) <= 6.5 or not car.has("route") or not car.has("leg"):
				continue
			var route: Array = car.route
			var seen := {}
			for i in range(maxi(int(car.leg), 1), route.size() - 1):
				var seg: int = int(route[i]) >> 1
				if seen.has(seg) or not sim.network.segments.has(seg) \
						or not int(sim.network.segments[seg].type) in LOCAL_STREETS:
					continue
				seen[seg] = true
				through[seg] = int(through.get(seg, 0)) + 1


# ----------------------------------------------------------------- the asks

## Once a game month: the council may take up one law.
func month(sim) -> void:
	var plans := []
	if can_pass(sim):
		for law in ["truck_routes", "impact_fee", "golf_carts"]:
			if has(law) or sim.tick_count - int(last.get(law, -1_000_000_000)) < Balance.LAW_ASK_COOLDOWN * TICKS_PER_MONTH:
				continue
			var plan: Dictionary = call("_plan_" + law, sim)
			if not plan.is_empty():
				plans.append(plan)
	through.clear()
	if plans.is_empty():
		return
	var plan: Dictionary = plans[0]
	var law := str(plan.law)
	if not sim.permits.can_file(sim, HUB, 1, true):
		return
	var req: int = sim.permits.file(sim, {"hub": HUB, "hub_id": 1, "leader": plan.leader,
		"title": plan.title, "why": plan.why, "area": plan.area, "change": "A new town law", "ask": "law",
		"yes": plan.yes, "no": plan.no})
	if req <= 0:
		return
	last[law] = int(sim.tick_count)
	asks[req] = law
	changed.emit()


## Residents of the street the most trucks cut through.
func _plan_truck_routes(sim) -> Dictionary:
	var best := -1
	for seg in through:
		if sim.network.segments.has(seg) and (best == -1 or int(through[seg]) > int(through[best])
				or int(through[seg]) == int(through[best]) and int(seg) < best):
			best = int(seg)
	if best == -1 or int(through[best]) < Balance.LAW_TRUCK_ASK_MIN:
		return {}
	var street: String = sim.streets.name_of(best)
	if street == "":
		street = "a neighborhood street"
	return {"law": "truck_routes", "leader": "Neighbors on %s" % street, "title": "Truck routes",
		"why": "Semis and dump trucks cut down %s on their way across town, past front yards and kids on bikes." % street,
		"area": LeaderAsks._corridor(sim.network.sample_segment(best), 14.0),
		"yes": "Truck route signs go up ($%s). Through trucks keep to the main roads; deliveries still come in. Trucks take a little longer to cross town." \
			% CitySim.money_text(Balance.LAW_TRUCK_SIGNS),
		"no": "Trucks keep taking any street."}


## The plan commission, after a year of fast home building.
func _plan_impact_fee(sim) -> Dictionary:
	var since: int = sim.tick_count - 12 * TICKS_PER_MONTH
	var n := 0
	var sum := Vector3.ZERO
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL and int(b.get("built", -1)) >= since and sim.lots.has(key):
			n += 1
			sum += sim.lots[key].pos
	if n < Balance.LAW_IMPACT_ASK_HOMES:
		return {}
	return {"law": "impact_fee", "leader": "The plan commission", "title": "An impact fee on new homes",
		"why": "%d new homes went up this year. Each one brings streets, parks and pipes the town will have to keep." % n,
		"area": LeaderAsks._square(sum / float(n), 120.0),
		"yes": "Every new home pays the town $%s. Builders pass it on, so homes go up a little slower." \
			% CitySim.money_text(Balance.LAW_IMPACT_FEE),
		"no": "New homes pay no fee."}


## A petition from the town's older residents.
func _plan_golf_carts(sim) -> Dictionary:
	if int(sim.stats.get("population", 0)) < Balance.CART_ASK_POP:
		return {}
	var older := 0
	var sum := Vector3.ZERO
	for id in sim.people.people:
		var p: Dictionary = sim.people.people[id]
		if int(p.age) >= Balance.CART_OWNER_AGE and sim.lots.has(str(p.home)):
			older += 1
			sum += sim.lots[str(p.home)].pos
	if older < Balance.CART_ASK_OLDER:
		return {}
	return {"law": "golf_carts", "leader": "A petition from %d residents" % older, "title": "Golf carts on town streets",
		"why": "Plenty of folks here would rather take a golf cart to the post office, the diner or a neighbor's than get the car out.",
		"area": LeaderAsks._square(sum / float(older), 150.0),
		"yes": "Golf carts may use town streets, never the highways. Some homes buy one, and drivers wait behind them now and then.",
		"no": "Golf carts stay off the streets."}


## Under golf_carts, a few more homes buy a cart each month, up to about
## one in Balance.CART_SHARE of those with someone old enough to want one.
func carts(sim) -> void:
	if not has("golf_carts"):
		return
	var have := {}
	var ids: Array = sim.people.people.keys()
	ids.sort()
	for id in ids:
		if int(sim.people.people[id].get("cart", -1)) != -1:
			have[str(sim.people.people[id].home)] = true
	var bought := 0
	for id in ids:
		if bought >= Balance.CART_PER_MONTH:
			break
		var p: Dictionary = sim.people.people[id]
		var home := str(p.home)
		if int(p.age) < Balance.CART_OWNER_AGE or have.has(home) \
				or absi(hash([home, "cart"])) % 1000 >= roundi(Balance.CART_SHARE * 1000.0):
			continue
		have[home] = true  # one try a home a month
		var vid: int = sim.traffic.new_vehicle("golf_cart", "lot:" + home, int(id))
		if vid != -1:
			p.cart = vid
			bought += 1


## The law's repealed: the carts go back in the garage for good.
func _sell_carts(sim) -> void:
	for id in sim.people.people:
		var p: Dictionary = sim.people.people[id]
		if int(p.get("cart", -1)) != -1:
			sim.traffic.retire_vehicle(int(p.cart))
			p.cart = -1


## Carries out the player's answers (CitySim, every game hour).
func carry_out(sim) -> void:
	if asks.is_empty():
		return
	var ids := asks.keys()
	ids.sort()
	for id in ids:
		var st: int = sim.permits.state_of(id)
		if st == Permits.State.OPEN or st == Permits.State.SHELVED:
			continue
		var law := str(asks[id])
		asks.erase(id)
		if st == Permits.State.APPROVED:
			sim.permits.done(id)
			if set_law(sim, law, true):
				sim.permits.requests[id].note = "Passed."
		changed.emit()


# ------------------------------------------------------------------ effects

## How readily homes start under the laws in force (times demand).
func home_pace() -> float:
	return Balance.LAW_IMPACT_PACE if has("impact_fee") else 1.0


## A new home started: the fee it pays the town.
func home_fee() -> int:
	return Balance.LAW_IMPACT_FEE if has("impact_fee") else 0


func to_dict() -> Dictionary:
	var as_ := {}
	for id in asks:
		as_[str(id)] = asks[id]
	var th := {}
	for seg in through:
		th[str(seg)] = through[seg]
	return {"adopted": adopted, "asks": as_, "last": last, "through": th}


func from_dict(d: Dictionary) -> void:
	adopted.clear()
	asks.clear()
	last.clear()
	through.clear()
	for k in d.get("adopted", {}):
		if LAWS.has(str(k)):
			adopted[str(k)] = int(d.adopted[k])
	for k in d.get("asks", {}):
		asks[int(k)] = str(d.asks[k])
	for k in d.get("last", {}):
		last[str(k)] = int(d.last[k])
	for k in d.get("through", {}):
		through[int(k)] = int(d.through[k])
	changed.emit()
