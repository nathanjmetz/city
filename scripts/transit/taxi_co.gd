class_name TaxiCo
extends RefCounted
## Cab companies that run themselves (Brawn, 2026-10-22: a taxi company hub
## whose owner sizes the fleet to ride demand). The player places the
## company; its owner does the rest:
##
## - Works out the town's cab rides a day: a few from everyone, many more
##   from people without a car (more of them in poorer towns), and the
##   late-night run home from the bars and restaurants.
## - Buys cabs to carry them (about 20 rides a cab a day), as many as the
##   lot holds and the money allows, and sells them when it can't keep them.
## - Sets the meter: a flag drop plus a rate a mile, within what riders here
##   can pay. An educated owner picks the lowest rate that keeps the company
##   in business; a less educated one nudges it after each month.
## - Grows only into the land next door, through a permit when homes stand
##   there.
## - Builds out its own development tree (TREE) with its own money.
##
## Money and rides are the real daily numbers (a game day is a month of
## books). The cabs you see each drive real trips through Traffic: out to a
## pickup, on to the drop-off, and back to their stall. Shifts follow the
## hour, so more cabs are out at the morning bump and at bar close.

## Ticks between the owner's decisions (one game day: a month of books).
const DECIDE_EVERY := 1440
## Ticks between an idle cab's looks at the dispatch board.
const LOOK_EVERY := 60
## The rate changes at most every few days.
const RATE_EVERY_DAYS := 3
## Ticks a cab stops at the curb to pick up and to drop off.
const PICKUP_TICKS := 40
const DROPOFF_TICKS := 25
const RETRY_TICKS := 300
## The lot: real parking stalls (9 ft by 18 ft) on a two-way aisle (24 ft),
## behind a storefront office this deep.
const STALL_W := 2.7
const STALL_D := 5.5
const AISLE := 7.3
const OFFICE_D := 12.0
const GROW_STEP := AISLE + STALL_D

## The owner's development tree (Agency nodes). Custom needs, checked here:
## "clinic" (a clinic in town), "college" (a campus), "neighbors" (towns it
## trades with). Effects: riders* more rides, cost* running costs, income+
## dollars a month from a contract.
const TREE := [
	{"id": "radio", "name": "Two-way radio dispatch", "cost": 12_000, "needs": {},
		"effects": {"riders*": 0.05}, "note": "calls get a cab sooner"},
	{"id": "late_night", "name": "Late-night shift", "cost": 20_000, "requires": ["radio"],
		"needs": {"population": 4000}, "effects": {"riders*": 0.1},
		"note": "cabs wait outside the bars at closing time"},
	{"id": "wheelchair_van", "name": "Wheelchair-accessible van", "cost": 55_000, "requires": ["radio"],
		"needs": {"clinic": 1}, "effects": {"income+": 4000.0},
		"note": "Medicaid rides to the clinic (non-emergency medical transport)"},
	{"id": "hybrids", "name": "Hybrid cabs", "cost": 150_000, "requires": ["radio"],
		"needs": {"leader_edu": 0.5, "profit": 30_000}, "effects": {"cost*": -0.15},
		"note": "half the fuel of the old sedans"},
	{"id": "campus", "name": "Campus pickups", "cost": 30_000, "requires": ["radio"],
		"needs": {"college": 1}, "effects": {"riders+": 25.0}, "note": "students without cars"},
	{"id": "app", "name": "Ride-booking app", "cost": 200_000, "requires": ["radio"],
		"needs": {"leader_edu": 0.65, "education": 0.45}, "effects": {"riders*": 0.2},
		"note": "book and pay from a phone"},
	{"id": "airport", "name": "Airport runs", "cost": 80_000, "requires": ["radio"],
		"needs": {"link": 1, "neighbors": 1}, "effects": {"income+": 9000.0},
		"note": "long fares to the regional airport, about $60 each"},
]

var companies := {}  # service id -> company state (see _new_company)
var cabs := {}       # cab id -> {id, co, state, leg, at, dir, stall, to, load, until, retire}
var trips := {}      # traffic trip id -> cab id
var _next_cab := 1
var _homes: Array = []  # lot keys, refreshed each day
var _shops: Array = []


# --- The city's side ----------------------------------------------------------

## A company was just placed: its owner, starting cash and first two cabs.
func on_placed(sim: CitySim, id: int) -> void:
	var b: Dictionary = sim.services.buildings[id]
	b.size = Services.KINDS[b.kind].size
	companies[id] = _new_company(sim, id)
	for i in 2:
		_add_cab(sim, id)
	_decide(sim, id)


## Steps every cab. Returns the ids of companies that bought land this tick,
## so the city can clear lots and zoning under them.
func tick(sim: CitySim) -> Array:
	if not sim.permits.locators.has("taxi"):
		# Lets the player guide the owner from the company's panel.
		sim.permits.locators["taxi"] = func(s: CitySim, id: int) -> Vector2:
			var b: Dictionary = s.services.buildings.get(id, {})
			return Vector2(b.pos.x, b.pos.z) if not b.is_empty() else Vector2.ZERO
	_sync(sim)
	var grown := []
	if companies.is_empty() and cabs.is_empty():
		return grown
	_arrivals(sim)
	if sim.tick_count % DECIDE_EVERY == 0:
		var ids := companies.keys()
		ids.sort()
		for id in ids:
			if _decide(sim, id):
				grown.append(id)
	_drive(sim)
	return grown


## Companies come and go with their buildings; a bulldozed company sells its
## parked cabs at once, those on a trip finish it first.
func _sync(sim: CitySim) -> void:
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if b.kind == Services.Kind.TAXI_COMPANY and not companies.has(id):
			if not b.has("size"):
				b.size = Services.KINDS[b.kind].size
			companies[id] = _new_company(sim, id)
	for id in companies.keys():
		if not sim.services.buildings.has(id):
			companies.erase(id)
	for cid in cabs.keys():
		if not sim.services.buildings.has(cabs[cid].co) and cabs[cid].state != "driving":
			_drop(sim, cid)


func _new_company(sim: CitySim, id: int) -> Dictionary:
	return {"cash": Balance.TAXI_START_CASH, "rate": Balance.TAXI_START_RATE, "rate_day": -99,
		"rides": 0, "served": 0, "wanted": 2, "month": {}, "log": [], "wealth": 0.5,
		"leader": Agency.leader(sim, hash([id, "taxi"])), "built": [], "why": "", "strip": []}


# --- Rides and money ----------------------------------------------------------

## Cab rides the town wants a day at this rate a mile.
func rides_wanted(sim: CitySim, id: int, rate: float) -> float:
	var co: Dictionary = companies[id]
	var pop := float(sim.stats.population)
	var carless := lerpf(Balance.TAXI_CARLESS_POOR, Balance.TAXI_CARLESS_RICH, float(co.wealth))
	var rides := pop * (Balance.TAXI_TRIPS_PER_PERSON + carless * Balance.TAXI_TRIPS_PER_CARLESS)
	rides += _shop_jobs(sim) * Balance.TAXI_TRIPS_PER_SHOP_JOB
	rides *= Agency.effect(co, TREE, "riders*")
	rides += Agency.effect(co, TREE, "riders+")
	var fare := _fare(rate) / _fare(Balance.TAXI_START_RATE)
	return rides * pow(fare, Balance.TAXI_ELASTICITY)


static func _fare(rate: float) -> float:
	return Balance.TAXI_FLAG + rate * Balance.TAXI_AVG_MILES


func _shop_jobs(sim: CitySim) -> float:
	var jobs := 0.0
	for key in _shops:
		if sim.buildings.has(key):
			jobs += float(sim.buildings[key].cap)
	return jobs


## A month of books for a fleet at a rate: rides, fares, costs and net.
func _month(sim: CitySim, id: int, rate: float, fleet: int) -> Dictionary:
	var co: Dictionary = companies[id]
	var rides := rides_wanted(sim, id, rate)
	var served := minf(rides, fleet * Balance.TAXI_RIDES_PER_CAB)
	var fares := roundi(served * 30.0 * _fare(rate))
	var cost := roundi(fares * Balance.TAXI_DRIVER_SHARE
		+ fleet * Balance.TAXI_CAB_MONTHLY * Agency.effect(co, TREE, "cost*") + Balance.TAXI_OFFICE_MONTHLY)
	var contract := roundi(Agency.effect(co, TREE, "income+"))
	return {"rides": roundi(rides), "served": roundi(served), "fares": fares, "cost": cost,
		"contract": contract, "net": fares + contract - cost}


## The owner's day (a month of books): settle up, size the fleet, maybe grow,
## build from the tree and set the rate. True if it bought land.
func _decide(sim: CitySim, id: int) -> bool:
	var co: Dictionary = companies[id]
	var b: Dictionary = sim.services.buildings[id]
	_refresh_lots(sim)
	co.wealth = _wealth(sim)
	var fleet := fleet_of(id)
	var m := _month(sim, id, co.rate, fleet)
	co.month = m
	co.rides = m.rides
	co.served = m.served
	co.cash += m.net
	var stance := str(sim.permits.guidance("taxi", id).stance)
	var stalls := stalls_for(Services.size_of(b))
	co.wanted = maxi(1, ceili(float(m.rides) / Balance.TAXI_RIDES_PER_CAB))
	var reserve := roundi(Balance.TAXI_OFFICE_MONTHLY * (1.0 + float(co.leader.caution)))
	var bought_land := false
	if fleet < co.wanted and fleet < stalls and co.cash >= Balance.TAXI_CAB_PRICE + reserve \
			and _month(sim, id, co.rate, fleet + 1).net > m.net:
		_add_cab(sim, id)
		co.cash -= Balance.TAXI_CAB_PRICE
		_note(co, "Bought a cab: %d on the road now." % (fleet + 1))
	elif fleet > 1 and (fleet > co.wanted + 1 or co.cash < 0 and _month(sim, id, co.rate, fleet - 1).net > m.net):
		if _retire_one(id):
			co.cash += Balance.TAXI_CAB_RESALE
			_note(co, "Sold a cab: %d is more than the rides need." % fleet)
	elif stance != "hold" and fleet >= stalls and (co.wanted > stalls or stance == "grow") \
			and co.cash >= _grow_cost(b) + reserve:
		var got := _grow(sim, id)
		if got == "ok":
			co.cash -= _grow_cost(b)
			bought_land = true
			_note(co, "Bought the land next door for more cab stalls.")
		elif got == "built":
			_ask_for_land(sim, id)
	for req in sim.permits.approved("taxi", id):
		if _take_strip(sim, id, req):
			co.cash -= int(req.cost)
			bought_land = true
			_note(co, "Bought the lot next door, as you approved, for more cab stalls.")
		sim.permits.done(req.id)
	var node := Agency.develop(sim, co, _open_tree(sim, id), _gate(b), float(m.net) * 12.0)
	if not node.is_empty():
		co.cash -= int(node.cost)
		_note(co, str(co.why))
	var day := sim.tick_count / DECIDE_EVERY
	if day - int(co.rate_day) >= RATE_EVERY_DAYS:
		_set_rate(sim, id)
		co.rate_day = day
	return bought_land


## The rate a mile, within what riders here can pay. An educated owner knows
## riders drop off as fares rise and picks the lowest rate that turns a
## profit; a less educated one nudges it after each month.
func _set_rate(sim: CitySim, id: int) -> void:
	var co: Dictionary = companies[id]
	var top := Balance.TAXI_RATE_MIN + (Balance.TAXI_RATE_MAX - Balance.TAXI_RATE_MIN) * (0.4 + 0.6 * float(co.wealth))
	top = snappedf(top, 0.25)
	var old: float = co.rate
	if float(co.leader.edu) >= 0.5:
		var fleet := maxi(fleet_of(id), 1)
		co.rate = top
		var r := Balance.TAXI_RATE_MIN
		while r <= top + 0.001:
			var m := _month(sim, id, r, fleet)
			if m.net >= m.fares * 0.05:
				co.rate = r
				break
			r += 0.25
	else:
		var net := int(co.month.get("net", 0))
		if net < 0:
			co.rate = minf(old + 0.25, top)
		elif net > int(co.month.get("fares", 0)) * 0.15:
			co.rate = maxf(old - 0.25, Balance.TAXI_RATE_MIN)
		co.rate = minf(co.rate, top)
	if not is_equal_approx(old, co.rate):
		_note(co, "Set the meter to $%.2f a mile." % co.rate)


## How well off the town is (0 to 1), from its homes' services and jobs.
func _wealth(sim: CitySim) -> float:
	var w: Dictionary = Balance.HOOD_WEALTH_WEIGHTS
	var employment := float(sim.stats.employed) / maxf(sim.stats.workers, 1.0)
	var cover := 0.0
	var occ := 0.0
	var n := 0
	for key in _homes:
		if not sim.buildings.has(key):
			continue
		var b: Dictionary = sim.buildings[key]
		n += 1
		cover += sim.services.coverage(key)
		occ += float(b.occ) / maxf(b.cap, 1.0)
	if n == 0:
		return 0.5
	return clampf((w.land_value + w.services) * cover / n + w.employment * employment + w.occupancy * occ / n, 0.0, 1.0)


## The homes and shops cabs run between, sorted so every copy picks alike.
func _refresh_lots(sim: CitySim) -> void:
	_homes = []
	_shops = []
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if not sim.lots.has(key):
			continue
		match int(sim.buildings[key].zone):
			ZoneMap.Zone.RESIDENTIAL:
				_homes.append(key)
			ZoneMap.Zone.COMMERCIAL:
				_shops.append(key)


func fleet_of(id: int) -> int:
	var n := 0
	for cid in cabs:
		if cabs[cid].co == id and not cabs[cid].get("retire", false):
			n += 1
	return n


func _note(co: Dictionary, text: String) -> void:
	co.log.append(text)
	while co.log.size() > 4:
		co.log.pop_front()


# --- The development tree -----------------------------------------------------

## Tree nodes whose TaxiCo-only needs hold, with those needs taken out so
## Agency checks the rest.
func _open_tree(sim: CitySim, id: int) -> Array:
	var clinics := 0
	for sid in sim.services.buildings:
		if sim.services.buildings[sid].kind == Services.Kind.CLINIC:
			clinics += 1
	var have := {"clinic": clinics, "college": sim.education.campuses.size(), "neighbors": BusNet.neighbors(sim)}
	var out := []
	for node in TREE:
		var needs: Dictionary = node.get("needs", {}).duplicate()
		var ok := true
		for k in have:
			if needs.has(k):
				ok = ok and int(have[k]) >= int(needs[k])
				needs.erase(k)
		if ok:
			var n: Dictionary = node.duplicate()
			n.needs = needs
			out.append(n)
	return out


# --- The lot --------------------------------------------------------------------

## Cab stalls in a lot of this size, in the site's local frame (centre at the
## origin, -z toward the road): [front of the stall, facing]. Rows of stalls
## behind the office, each nosed in off its aisle.
static func stall_slots(size: Vector2) -> Array:
	var out := []
	var per_row := int((size.x - 2.0) / STALL_W)
	var z := -size.y * 0.5 + OFFICE_D
	while z + AISLE + STALL_D <= size.y * 0.5 - 0.5:
		for i in per_row:
			var x := -size.x * 0.5 + 1.0 + (i + 0.5) * STALL_W
			out.append([Vector3(x, 0.0, z + AISLE + 0.3), Vector3(0, 0, -1)])
		z += AISLE + STALL_D
	return out


static func stalls_for(size: Vector2) -> int:
	return stall_slots(size).size()


static func _gate(b: Dictionary) -> Vector3:
	return b.pos + b.dir * (Services.size_of(b).y * 0.5 + Services.SETBACK)


## A cab in its stall, in world space: [front of the cab, facing].
func stall_pose(sim: CitySim, cab: Dictionary) -> Array:
	var b: Dictionary = sim.services.buildings.get(cab.co, {})
	if b.is_empty():
		return [cab.at, cab.dir]
	var slots := stall_slots(Services.size_of(b))
	if slots.is_empty():
		return [_gate(b), -b.dir]
	var frame := Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos)
	var slot: Array = slots[int(cab.stall) % slots.size()]
	return [frame * slot[0], frame.basis * slot[1]]


func _grow_cost(b: Dictionary) -> int:
	return roundi(GROW_STEP * Services.size_of(b).x * Balance.BUS_LAND_PER_M2)


## Buys a strip of free land behind the lot, or beside it once it's deep:
## never more than Balance.HUB_MAX_GROWTH times the first site. "ok" if it
## grew, "built" if only homes or shops stand in the way, else "no".
func _grow(sim: CitySim, id: int) -> String:
	var b: Dictionary = sim.services.buildings[id]
	var size := Services.size_of(b)
	var first: Vector2 = Services.KINDS[b.kind].size
	var side := Vector3(-b.dir.z, 0.0, b.dir.x)
	var tries := [[Vector2(0, GROW_STEP), -b.dir * GROW_STEP * 0.5],
		[Vector2(GROW_STEP, 0), side * GROW_STEP * 0.5], [Vector2(GROW_STEP, 0), -side * GROW_STEP * 0.5]]
	if size.y >= size.x * 2.0:
		tries = [tries[1], tries[2], tries[0]]
	var built := []
	for t in tries:
		var new_size: Vector2 = size + t[0]
		if new_size.x * new_size.y > first.x * first.y * Balance.HUB_MAX_GROWTH:
			continue
		var pos: Vector3 = b.pos + t[1]
		var why := BusNet.land_free(sim, id, pos, b.dir, new_size)
		if why == "":
			b.pos = pos
			b.size = new_size
			sim.buildings_changed.emit()
			return "ok"
		if why == "built" and built.is_empty():
			built = [pos, new_size]
	if not built.is_empty():
		companies[id].strip = [[built[0].x, built[0].z], [built[1].x, built[1].y]]
		return "built"
	return "no"


## Homes or shops stand where the lot would grow: ask the player, through a
## land permit, to let the owner buy them out.
func _ask_for_land(sim: CitySim, id: int) -> void:
	var co: Dictionary = companies[id]
	if co.strip.is_empty() or not sim.permits.can_file(sim, "taxi", id):
		return
	var b: Dictionary = sim.services.buildings[id]
	var area := []
	for p in Services.corners(b.kind, Vector3(co.strip[0][0], 0.0, co.strip[0][1]), b.dir,
			Vector2(co.strip[1][0], co.strip[1][1])):
		area.append([p.x, p.z])
	sim.permits.file(sim, {"hub": "taxi", "hub_id": id, "leader": "The cab company's owner",
		"title": "Buy the lot next to the taxi company",
		"why": "Every stall is full; more cabs would carry the rides people are calling for.",
		"area": area, "change": "Homes and shops to cab lot", "per_m2": roundi(Balance.BUS_LAND_PER_M2 * 6.0),
		"base": _grow_cost(b), "budget": int(co.cash)})


## Carries out an approved land permit: what stands there is bought and
## cleared, and the lot grows over it.
func _take_strip(sim: CitySim, id: int, req: Dictionary) -> bool:
	var co: Dictionary = companies[id]
	var b: Dictionary = sim.services.buildings.get(id, {})
	if b.is_empty() or co.strip.is_empty():
		return false
	var pos := Vector3(co.strip[0][0], 0.0, co.strip[0][1])
	var size := Vector2(co.strip[1][0], co.strip[1][1])
	var outline := PackedVector2Array()
	for p in req.route:
		outline.append(Vector2(float(p[0]), float(p[1])))
	for key in sim.buildings.keys():
		if sim.parcel_under(key, outline):
			sim.buildings.erase(key)
	co.strip = []
	if BusNet.land_free(sim, id, pos, b.dir, size) != "":
		return false
	b.pos = pos
	b.size = size
	sim.buildings_changed.emit()
	return true


# --- Cabs on the road -----------------------------------------------------------

func _add_cab(sim: CitySim, co: int) -> int:
	var used := {}
	for cid in cabs:
		if cabs[cid].co == co:
			used[cabs[cid].stall] = true
	var stall := 0
	while used.has(stall):
		stall += 1
	var id := _next_cab
	_next_cab += 1
	var cab := {"id": id, "co": co, "state": "parked", "leg": "", "at": Vector3.ZERO, "dir": Vector3.FORWARD,
		"stall": stall, "to": Vector3.ZERO, "load": 0, "until": 0}
	cabs[id] = cab
	var pose := stall_pose(sim, cab)
	cab.at = pose[0]
	cab.dir = pose[1]
	return id


## A cab leaves the books, and its car leaves the road if it's parked.
func _drop(sim: CitySim, cid: int) -> void:
	var cab: Dictionary = cabs.get(cid, {})
	if int(cab.get("vid", -1)) != -1 and cab.get("state", "") != "driving":
		sim.traffic.retire_vehicle(int(cab.vid))
	cabs.erase(cid)


func _retire_one(co: int) -> bool:
	var ids := cabs.keys()
	ids.sort()
	ids.reverse()
	for cid in ids:
		if cabs[cid].co == co and not cabs[cid].get("retire", false):
			cabs[cid].retire = true
			return true
	return false


## Cabs on shift this hour: the busiest hours have the whole fleet out.
func on_shift(id: int, hour: int) -> int:
	var top := 0.0
	for w in Balance.TAXI_HOURLY:
		top = maxf(top, w)
	return ceili(fleet_of(id) * Balance.TAXI_HOURLY[hour % 24] / top)


## Picks up Traffic's reports for our cabs and leaves the rest alone.
func _arrivals(sim: CitySim) -> void:
	if trips.is_empty():
		return
	for list in [sim.traffic.arrivals, sim.traffic.failed]:
		var ok: bool = list == sim.traffic.arrivals
		var i := 0
		while i < list.size():
			var tid := int(list[i].get("trip", list[i].get("id", -1)))
			if not trips.has(tid):
				i += 1
				continue
			var cid: int = trips[tid]
			var a: Dictionary = list[i]
			trips.erase(tid)
			list.remove_at(i)
			if cabs.has(cid):
				if a.has("vid"):
					cabs[cid].vid = int(a.vid)
				_arrived(sim, cabs[cid], ok)


func _arrived(sim: CitySim, cab: Dictionary, ok: bool) -> void:
	if not ok:
		cab.state = "wait"
		cab.leg = "home"
		cab.load = 0
		cab.until = sim.tick_count + RETRY_TICKS
		return
	match str(cab.leg):
		"pickup":
			cab.at = cab.pickup
			cab.state = "dwell"
			cab.load = 1 + int(_roll(cab, sim.tick_count, 7) < 0.3)
			cab.until = sim.tick_count + PICKUP_TICKS
		"dropoff":
			cab.at = cab.to
			cab.state = "dwell"
			cab.load = 0
			cab.until = sim.tick_count + DROPOFF_TICKS
		_:
			# Back in the lot: its car leaves the road for its stall.
			if int(cab.get("vid", -1)) != -1:
				sim.traffic.retire_vehicle(int(cab.vid))
				cab.vid = -1
			if cab.get("retire", false) or not sim.services.buildings.has(cab.co):
				_drop(sim, cab.id)
				return
			var pose := stall_pose(sim, cab)
			cab.at = pose[0]
			cab.dir = pose[1]
			cab.state = "parked"
			cab.leg = ""
			cab.until = sim.tick_count + LOOK_EVERY


## Each cab's next move: an idle cab on shift takes a call when the board has
## one; a cab at the curb carries on with its fare or heads back to the lot.
func _drive(sim: CitySim) -> void:
	var ids := cabs.keys()
	ids.sort()
	var hour := int(sim.clock().hour)
	var ranks := {}
	for cid in ids:
		if not cabs.has(cid):
			continue
		var cab: Dictionary = cabs[cid]
		var rank: int = ranks.get(cab.co, 0)
		ranks[cab.co] = rank + 1
		if cab.state == "driving" or sim.tick_count < int(cab.until):
			continue
		match str(cab.state):
			"parked":
				cab.until = sim.tick_count + LOOK_EVERY
				if cab.get("retire", false) or not companies.has(cab.co):
					_drop(sim, cid)
					continue
				if rank >= on_shift(cab.co, hour) or _roll(cab, sim.tick_count, 1) > _busy(cab.co):
					continue
				var fare := _call(sim, cab, hour)
				if fare.is_empty():
					continue
				cab.pickup = fare[0]
				cab.to = fare[1]
				_send(sim, cab, "pickup", fare[0])
			"dwell":
				if cab.leg == "pickup":
					_send(sim, cab, "dropoff", cab.to)
				else:
					_home(sim, cab)
			_:
				_home(sim, cab)


func _home(sim: CitySim, cab: Dictionary) -> void:
	var b: Dictionary = sim.services.buildings.get(cab.co, {})
	if b.is_empty():
		_drop(sim, cab.id)
		return
	_send(sim, cab, "home", _gate(b))


## Share of a cab's shift spent carrying fares: rides served over what the
## fleet could carry.
func _busy(id: int) -> float:
	var co: Dictionary = companies.get(id, {})
	var fleet := maxi(fleet_of(id), 1)
	return clampf(float(co.get("served", 0)) / (fleet * Balance.TAXI_RIDES_PER_CAB), 0.1, 1.0)


## A call off the board: [pickup, drop-off]. Late at night it's the run home
## from a bar or restaurant; by day a trip between a home and a shop or job,
## either way round.
func _call(sim: CitySim, cab: Dictionary, hour: int) -> Array:
	if _homes.is_empty():
		_refresh_lots(sim)
	if _homes.is_empty():
		return []
	var home: String = _homes[int(_roll(cab, sim.tick_count, 2) * _homes.size()) % _homes.size()]
	var other: String = home
	if not _shops.is_empty():
		other = _shops[int(_roll(cab, sim.tick_count, 3) * _shops.size()) % _shops.size()]
	if not sim.lots.has(home) or not sim.lots.has(other) or home == other:
		return []
	var a: Vector3 = sim.lots[home].front
	var b: Vector3 = sim.lots[other].front
	var night := hour >= 21 or hour < 4
	if night or _roll(cab, sim.tick_count, 4) < 0.5:
		return [b, a]
	return [a, b]


## A repeatable random number for a cab at a tick (every copy rolls alike).
static func _roll(cab: Dictionary, t: int, salt: int) -> float:
	return float(hash([int(cab.id), t, salt]) & 0xffff) / 65536.0


func _send(sim: CitySim, cab: Dictionary, leg: String, to: Vector3) -> bool:
	var from: Vector3 = cab.at
	if cab.state == "parked":
		from = _gate(sim.services.buildings[cab.co])
	var tid := BusNet.leg(sim.traffic, cab, "taxi:%d" % cab.id, from, {"ref": "taxi:%d" % cab.id, "pos": [to.x, to.z]},
		"taxi", {"riders": cab.load, "cab": cab.id}, cab_kind(cab.co))
	if tid == -1:
		cab.until = sim.tick_count + RETRY_TICKS
		if cab.state != "parked":
			cab.state = "wait"
			cab.leg = "home"
		return false
	trips[tid] = cab.id
	cab.leg = leg
	cab.state = "driving"
	return true


## The car a company's cabs are: old Crown Victorias until it buys hybrids.
func cab_kind(co: int) -> String:
	return "taxi" if "hybrids" in companies.get(co, {}).get("built", []) else "taxi_old"


## Cabs standing still, for the view: [kind, front of the cab, facing, riders].
func standing(sim: CitySim) -> Array:
	var out := []
	var ids := cabs.keys()
	ids.sort()
	for cid in ids:
		var cab: Dictionary = cabs[cid]
		if cab.state == "driving":
			continue
		if cab.state == "parked":
			var pose := stall_pose(sim, cab)
			out.append([cab_kind(cab.co), pose[0], pose[1], 0, int(cab.get("vid", -1)) != -1])
		else:
			out.append([cab_kind(cab.co), cab.at, cab.dir if cab.dir.length() > 0.5 else Vector3.FORWARD, cab.load,
				int(cab.get("vid", -1)) != -1])
	return out


# --- Panel ------------------------------------------------------------------------

func describe(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
	var k: Dictionary = Services.KINDS[b.kind]
	if not companies.has(id):
		companies[id] = _new_company(sim, id)
	var co: Dictionary = companies[id]
	var fleet := fleet_of(id)
	var stalls := stalls_for(Services.size_of(b))
	var rows := []
	rows.append(["Cabs", "%d of %d stalls" % [fleet, stalls]])
	rows.append(["Rides", "%d a day of %d called in" % [int(co.served), int(co.rides)]])
	rows.append(["Meter", "$%.2f plus $%.2f a mile (set by the owner)" % [Balance.TAXI_FLAG, co.rate]])
	var m: Dictionary = co.month
	if not m.is_empty():
		rows.append(["Fares", "$%s / day" % CitySim.money_text(int(m.fares))])
		rows.append(["Running costs", "$%s / day" % CitySim.money_text(int(m.cost))])
	rows.append(["Company's cash", ("-$%s" if co.cash < 0 else "$%s") % CitySim.money_text(absi(int(co.cash)))])
	rows.append_array(Inspect._development(sim, co, _open_tree(sim, id), _gate(b), float(m.get("net", 0)) * 12.0))
	var problems := []
	var linked := not sim.network.find_segment_near(_gate(b), 80.0, 1.0).is_empty()
	var status := "Running %d cab%s" % [fleet, "" if fleet == 1 else "s"]
	if not linked:
		problems.append("Not beside a road, so its cabs can't get out.")
		status = "Not running"
	elif int(co.rides) > int(co.served) and fleet >= stalls:
		problems.append("The lot is full: it will buy the land next door when it's free and it can afford it.")
	return {"title": k.name, "kind": "Transit", "icon": k.icon, "ok": linked and problems.is_empty(),
		"status": status, "rows": rows, "problems": problems, "log": co.log.duplicate()}


# --- Saving -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {"next_cab": _next_cab, "companies": {}, "cabs": [], "trips": {}}
	for id in companies:
		var co: Dictionary = companies[id]
		d.companies[str(id)] = {"cash": co.cash, "rate": co.rate, "rate_day": co.rate_day, "rides": co.rides,
			"served": co.served, "wanted": co.wanted, "month": co.month, "log": co.log, "wealth": co.wealth,
			"leader": co.leader, "built": co.built, "why": co.why, "strip": co.strip}
	var ids := cabs.keys()
	ids.sort()
	for cid in ids:
		var c: Dictionary = cabs[cid]
		var p: Vector3 = c.get("pickup", Vector3.ZERO)
		d.cabs.append({"id": cid, "co": c.co, "state": c.state, "leg": c.leg, "at": [c.at.x, c.at.z],
			"dir": [c.dir.x, c.dir.z], "stall": c.stall, "to": [c.to.x, c.to.z], "pickup": [p.x, p.z],
			"load": c.load, "until": c.until, "retire": c.get("retire", false), "vid": c.get("vid", -1)})
	for tid in trips:
		d.trips[str(tid)] = trips[tid]
	return d


func from_dict(sim: CitySim, d: Dictionary) -> void:
	_next_cab = int(d.get("next_cab", 1))
	companies.clear()
	for k in d.get("companies", {}):
		var v: Dictionary = d.companies[k]
		var co := _new_company(sim, int(k))
		for f in ["cash", "rate_day", "rides", "served", "wanted"]:
			co[f] = int(v.get(f, co[f]))
		co.rate = float(v.get("rate", co.rate))
		co.wealth = float(v.get("wealth", co.wealth))
		co.month = v.get("month", {})
		co.log = v.get("log", [])
		co.leader = v.get("leader", co.leader)
		co.built = v.get("built", [])
		co.why = str(v.get("why", ""))
		co.strip = v.get("strip", [])
		companies[int(k)] = co
	cabs.clear()
	for a in d.get("cabs", []):
		cabs[int(a.id)] = {"id": int(a.id), "co": int(a.co), "state": str(a.state), "leg": str(a.leg),
			"at": Vector3(a.at[0], 0.0, a.at[1]), "dir": Vector3(a.dir[0], 0.0, a.dir[1]), "stall": int(a.stall),
			"to": Vector3(a.to[0], 0.0, a.to[1]), "pickup": Vector3(a.pickup[0], 0.0, a.pickup[1]),
			"load": int(a.load), "until": int(a.until), "retire": bool(a.get("retire", false)),
			"vid": int(a.get("vid", -1))}
	trips.clear()
	for k in d.get("trips", {}):
		trips[int(k)] = int(d.trips[k])
	_refresh_lots(sim)
	_sync(sim)
