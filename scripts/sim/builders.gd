class_name Builders
extends RefCounted
## The town's home builder (Brawn, 2026-10-24: "When you start do you get a
## free construction company that is built inside the city. It could be a
## hub and leader situation"). The player places its yard, free, right after
## the first streets; its owner does the rest:
##
## - Sends a crew in the contractor's pickup (ladder rack on top) and a
##   concrete truck to each new house (Construction books them). The pickup
##   stays out front until the house is done; the concrete truck through the
##   foundation. Done, they go straight on to the next house waiting.
## - Is paid for each house it finishes, and pays its crews, drivers and
##   office every month (a game day is a month of books, as for the cabs).
## - Buys another pickup or concrete truck when houses are waiting for one,
##   as far as its money and its lot go, and grows into the land next door
##   when the lot is full.
##
## The trucks are counted here; where each one is (at a house, on the way,
## back at the yard) is Construction's, so the two never disagree.

## Ticks between the owner's books (one game day: a month of books), and
## between its looks at whether houses are waiting for another truck.
const DECIDE_EVERY := 1440
const BUY_EVERY := 60
## Truck stalls (12 ft by 36 ft, room for a 30 ft mixer) on a two-way aisle,
## behind an office this deep.
const STALL_W := 3.7
const STALL_D := 11.0
const AISLE := 8.0
const OFFICE_D := 14.0
const GROW_STEP := AISLE + STALL_D
## What each truck kind brings to a house, and what it costs.
const CARGO := {"work_pickup": "building crew", "concrete_mixer": "ready-mix concrete"}
const PRICE := {"work_pickup": Balance.BUILDER_PICKUP_PRICE, "concrete_mixer": Balance.BUILDER_MIXER_PRICE}
const MONTHLY := {"work_pickup": Balance.BUILDER_CREW_MONTHLY, "concrete_mixer": Balance.BUILDER_MIXER_MONTHLY}

var companies := {}  # yard (service id) -> company state (see _new_company)


## The yard was just placed: its owner, name, money and first trucks.
func on_placed(sim: CitySim, id: int) -> void:
	var b: Dictionary = sim.services.buildings[id]
	b.size = Services.KINDS[b.kind].size
	companies[id] = _new_company(sim, id)


func _new_company(sim: CitySim, id: int) -> Dictionary:
	var seed := hash([id, sim.city_seed, "builders"])
	var family := Names.surname(seed)
	return {"cash": Balance.BUILDER_START_CASH, "fleet": Balance.BUILDER_START_FLEET.duplicate(),
		"name": "%s Builders" % family, "owner": Names.person(seed, family), "leader": Agency.leader(sim, seed),
		"jobs": 0, "done": 0, "paid": 0, "month": {}, "log": [], "strip": []}


## Daily books and decisions. Returns the yards that bought land this tick,
## so the city can clear lots and zoning under them.
func tick(sim: CitySim) -> Array:
	if not sim.permits.locators.has("builders"):
		# Lets the player guide the owner (land permits) from the yard's panel.
		sim.permits.locators["builders"] = func(s: CitySim, id: int) -> Vector2:
			var b: Dictionary = s.services.buildings.get(id, {})
			return Vector2(b.pos.x, b.pos.z) if not b.is_empty() else Vector2.ZERO
	_sync(sim)
	var grown := []
	if companies.is_empty() or sim.tick_count % BUY_EVERY != 0:
		return grown
	var ids := companies.keys()
	ids.sort()
	for id in ids:
		if sim.tick_count % DECIDE_EVERY == 0:
			_books(id)
		if _decide(sim, id):
			grown.append(id)
	return grown


## The month's books: paid for each house finished, wages and fuel out.
func _books(id: int) -> void:
	var co: Dictionary = companies[id]
	var cost := Balance.BUILDER_OFFICE_MONTHLY
	for kind in co.fleet:
		cost += int(co.fleet[kind]) * int(MONTHLY.get(kind, 0))
	var income := int(co.paid)
	co.month = {"jobs": co.jobs, "income": income, "cost": cost, "net": income - cost}
	co.jobs = 0
	co.paid = 0
	co.cash -= cost


## Companies come and go with their yards.
func _sync(sim: CitySim) -> void:
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if b.kind == Services.Kind.BUILDER_YARD and not companies.has(id):
			if not b.has("size"):
				b.size = Services.KINDS[b.kind].size
			companies[id] = _new_company(sim, id)
	for id in companies.keys():
		if not sim.services.buildings.has(id):
			companies.erase(id)


## Work started on a house: the first draw.
func started(id: int) -> void:
	if companies.has(id):
		_pay(companies[id], roundi(Balance.BUILDER_FEE_HOUSE * Balance.BUILDER_FIRST_DRAW))


## A house the company built is done: the rest of its fee.
func paid(id: int) -> void:
	if companies.has(id):
		companies[id].jobs += 1
		companies[id].done += 1
		_pay(companies[id], Balance.BUILDER_FEE_HOUSE - roundi(Balance.BUILDER_FEE_HOUSE * Balance.BUILDER_FIRST_DRAW))


func _pay(co: Dictionary, dollars: int) -> void:
	co.cash += dollars
	co.paid += dollars


## The yard, as a trip end, and its id; {} with -1 when the town has none.
## Trucks pull out of its gate straight onto the street (as a truck coming
## in off the map does) and turn straight in coming back, rather than
## backing out of a stall one at a time.
func yard(sim: CitySim) -> Array:
	var id := sim.services.yard()
	if id == -1 or not companies.has(id):
		return [{}, -1]
	var g := gate(sim.services.buildings[id])
	return [{"ref": "edge", "pos": [snappedf(g.x, 0.01), snappedf(g.z, 0.01)]}, id]


## Trucks of `kind` the company owns.
func owned(id: int, kind: String) -> int:
	return int(companies.get(id, {}).get("fleet", {}).get(kind, 0))


func _decide(sim: CitySim, id: int) -> bool:
	var co: Dictionary = companies[id]
	var b: Dictionary = sim.services.buildings[id]
	# Two months of the office in hand, more for a careful owner.
	var reserve := roundi(Balance.BUILDER_OFFICE_MONTHLY * (2.0 + 2.0 * float(co.leader.caution)))
	var stalls := stalls_for(Services.size_of(b))
	var trucks := 0
	for kind in co.fleet:
		trucks += int(co.fleet[kind])
	var waiting: Dictionary = sim.construction.waiting_for(id)
	var away: Dictionary = sim.construction.away_from(id)
	var bought_land := false
	var bought := {"work_pickup": 0, "concrete_mixer": 0}
	var short := false
	while true:
		# Houses waiting beyond the trucks already free in the yard.
		var need := {}
		for kind in bought:
			need[kind] = int(waiting.get(CARGO[kind], 0)) - maxi(owned(id, kind) - int(away.get(kind, 0)), 0) - int(bought[kind])
		if need.work_pickup <= 0 and need.concrete_mixer <= 0:
			break
		# A concrete truck for about every three crews: a mixer pours one
		# foundation and drives on while the crews take months on a house.
		var crews := owned(id, "work_pickup")
		var mixers := owned(id, "concrete_mixer")
		var kind := "concrete_mixer"
		if need.work_pickup > 0 and (need.concrete_mixer <= 0 or crews < 3 * mixers) and crews < 3 * mixers + 3:
			kind = "work_pickup"
		if trucks >= stalls or co.cash < int(PRICE[kind]) + reserve:
			short = true
			break
		co.fleet[kind] = int(co.fleet[kind]) + 1
		co.cash -= int(PRICE[kind])
		trucks += 1
		bought[kind] += 1
	for kind in bought:
		var got: int = bought[kind]
		if got > 0:
			_note(co, "Bought %d %s: %d houses were waiting." % [got,
				("pickups for more crews" if got > 1 else "pickup for another crew") if kind == "work_pickup"
				else ("concrete trucks" if got > 1 else "concrete truck"), int(waiting.get(CARGO[kind], 0))])
	if sim.tick_count % DECIDE_EVERY == 0 and waiting.is_empty():
		# No houses waiting: an idle pickup or two more than it needs is sold.
		for kind in ["work_pickup", "concrete_mixer"]:
			# Never below the trucks it started with.
			var idle := mini(owned(id, kind) - int(away.get(kind, 0)),
				owned(id, kind) - int(Balance.BUILDER_START_FLEET.get(kind, 0)))
			if idle > 0:
				co.fleet[kind] = int(co.fleet[kind]) - idle
				co.cash += roundi(idle * int(PRICE[kind]) * Balance.BUILDER_RESALE)
				_note(co, "Sold %d idle %s." % [idle, "pickups" if kind == "work_pickup" else "concrete trucks"])
	var stance := str(sim.permits.guidance("builders", id).stance)
	if short and trucks >= stalls and sim.tick_count % DECIDE_EVERY == 0 and stance != "hold" \
			and co.cash >= _grow_cost(b) + reserve:
		# Every stall taken and houses still waiting: more lot.
		var got := HubLot.grow(sim, id, GROW_STEP)
		if got[0] == "ok":
			co.cash -= _grow_cost(b)
			bought_land = true
			_note(co, "Bought the land next door for more truck stalls.")
		elif got[0] == "built":
			co.strip = [got[1], got[2]]
			_ask_for_land(sim, id)
	for req in sim.permits.approved("builders", id):
		if _take_strip(sim, id, req):
			co.cash -= int(req.cost)
			bought_land = true
			_note(co, "Bought the lot next door, as you approved, for more truck stalls.")
		sim.permits.done(req.id)
	return bought_land


func _grow_cost(b: Dictionary) -> int:
	return roundi(GROW_STEP * Services.size_of(b).x * Balance.BUS_LAND_PER_M2)


## Homes or shops stand where the lot would grow: ask the player, through a
## land permit, to let the owner buy them out.
func _ask_for_land(sim: CitySim, id: int) -> void:
	var co: Dictionary = companies[id]
	if co.strip.is_empty() or not sim.permits.can_file(sim, "builders", id):
		return
	var b: Dictionary = sim.services.buildings[id]
	var area := []
	for p in Services.corners(b.kind, Vector3(co.strip[0][0], 0.0, co.strip[0][1]), b.dir,
			Vector2(co.strip[1][0], co.strip[1][1])):
		area.append([p.x, p.z])
	sim.permits.file(sim, {"hub": "builders", "hub_id": id, "leader": "The builder",
		"title": "Buy the lot next to the builder's yard",
		"why": "Every truck stall is full and houses are waiting for a crew.",
		"area": area, "change": "Homes and shops to builder's yard", "per_m2": roundi(Balance.BUS_LAND_PER_M2 * 6.0),
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


func _note(co: Dictionary, text: String) -> void:
	co.log.push_front(text)
	if co.log.size() > 6:
		co.log.resize(6)


# --- The lot --------------------------------------------------------------------

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


## Where trucks leave and come back: the yard's gate on its street.
static func gate(b: Dictionary) -> Vector3:
	return b.pos + b.dir * (Services.size_of(b).y * 0.5 + Services.SETBACK)


## Trucks parked in the yard, for the view: [kind, front of the truck,
## facing, load, false], as TaxiCo.standing.
func standing(sim: CitySim) -> Array:
	var out := []
	var ids := companies.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = sim.services.buildings.get(id, {})
		if b.is_empty():
			continue
		var away: Dictionary = sim.construction.away_from(id)
		var slots := stall_slots(Services.size_of(b))
		var frame := Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos)
		var n := 0
		for kind in ["concrete_mixer", "work_pickup"]:
			for i in maxi(owned(id, kind) - int(away.get(kind, 0)), 0):
				if n >= slots.size():
					break
				var slot: Array = slots[n]
				out.append([kind, Terrain.stand(frame * slot[0]), frame.basis * slot[1], 0, false])
				n += 1
	return out


# --- Panel ----------------------------------------------------------------------

func describe(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
	var k: Dictionary = Services.KINDS[b.kind]
	if not companies.has(id):
		companies[id] = _new_company(sim, id)
	var co: Dictionary = companies[id]
	var away: Dictionary = sim.construction.away_from(id)
	var waiting: Dictionary = sim.construction.waiting_for(id)
	var rows := []
	rows.append(["Owner", "%s, %s" % [co.owner, Education.leader_style(co.leader)]])
	for kind in ["work_pickup", "concrete_mixer"]:
		var what := "Crews (pickups)" if kind == "work_pickup" else "Concrete trucks"
		rows.append([what, "%d: %d out at houses or on the way" % [owned(id, kind), int(away.get(kind, 0))]])
	rows.append(["Houses built", "%d" % int(co.done)])
	var waits := int(waiting.get("building crew", 0))
	if waits > 0:
		rows.append(["Waiting for a crew", "%d houses" % waits])
	var m: Dictionary = co.month
	if not m.is_empty():
		rows.append(["Last month", "%d houses: $%s paid, $%s in wages and fuel" % [int(m.jobs),
			CitySim.money_text(int(m.income)), CitySim.money_text(int(m.cost))]])
	rows.append(["Company's cash", ("-$%s" if co.cash < 0 else "$%s") % CitySim.money_text(absi(int(co.cash)))])
	var problems := []
	var linked := not sim.network.find_segment_near(gate(b), 80.0, 1.0).is_empty()
	if not linked:
		problems.append("Not beside a road, so its trucks can't get out.")
	return {"title": co.name, "kind": k.name, "icon": k.icon, "ok": linked,
		"status": "Building %d houses" % maxi(int(away.get("work_pickup", 0)), 0) if linked else "Not running",
		"rows": rows, "problems": problems, "log": co.log.duplicate()}


# --- Saving ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {}
	for id in companies:
		d[str(id)] = companies[id].duplicate(true)
	return {"companies": d}


func from_dict(sim: CitySim, d: Dictionary) -> void:
	companies.clear()
	var cs: Dictionary = d.get("companies", {})
	for k in cs:
		var v: Dictionary = cs[k]
		var co := _new_company(sim, int(k))
		for f in ["cash", "jobs", "done", "paid"]:
			co[f] = int(v.get(f, co[f]))
		for f in ["name", "owner", "leader", "month", "log", "strip"]:
			if v.has(f):
				co[f] = v[f]
		var fleet: Dictionary = v.get("fleet", co.fleet)
		co.fleet = {}
		for kind in fleet:
			co.fleet[str(kind)] = int(fleet[kind])
		companies[int(k)] = co
