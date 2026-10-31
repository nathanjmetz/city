class_name DoorEvents
extends RefCounted
## Which garage doors are going up, or are up, for the cars going in and
## out of them (docs/spec-working-doors.md, step 1: house garages). Worked
## out from what the traffic already knows and saves, so it is the same on
## every computer and after a load; nothing here is saved, and nothing
## feeds back into the simulation. DoorView draws it.
##
## A door goes up for:
##   - a car about to back out of its garage: from door_t, timed by the
##     simulation while its driver walks out to it so the door is most of
##     the way up as they get in (TrafficSim._open_door; the trip leaves
##     when it always did), taking door_n ticks to go all the way; how far
##     up it is is exact;
##   - that car while it backs down the drive (it comes down once the car
##     is out in the street);
##   - a car coming home to its garage, from about LEAD seconds out on its
##     own street, while it turns in and drives in (it comes down once the
##     car is parked).
## A car TrafficView draws out on the drive, not in the garage
## (TrafficView.out_front), opens nothing: the garage looks shut with the
## car outside.
##
## Warehouse docks (step 2): a dock door goes up once a truck has backed up
## to it (the truck's dock_t, the tick it got there: DOCK_TICKS to go all
## the way, exactly), stays up while it sits there being unloaded
## (TrafficSim.DOCK_DWELL) and while it pulls off the dock, and comes down
## once it is out in the street. A truck simply parked at a dock with
## nowhere to go (one based there) leaves its door shut. The busier the
## warehouse, the more of its doors stand open.
##
## Step 3: plants, shops, service garages and machine sheds, with the doors
## their views drew (`doors_of`; without it these stay shut):
##   - a factory's overhead door ("bay") goes up for a truck bound for one
##     of its bays from about BAY_LEAD seconds out (the door is slow), while
##     it drives in, while it stands in the bay with a trip ahead of it, and
##     while it pulls out; it comes down once the truck is in the street.
##     The door opened is the one the builder drew nearest the bay.
##   - a shop's stockroom roll-up ("rollup") goes up while a delivery truck
##     is coming within SHOP_NEAR metres, parked for the shop, or pulling
##     away (until SHOP_NEAR on).
##   - a service garage's bay ("bay": an ER's ambulance bays, a police
##     station's sally port, a bus garage's doors) goes up for its own
##     ambulance, cruiser or bus leaving it or coming back, while within
##     SVC_NEAR metres: the door nearest the vehicle. A fire station's stay
##     shut (fire calls don't exist yet).
##   - a farmstead's machine shed by the month (`more`: FarmsteadNear.open_doors).
## A truck still leaves the moment its trip starts, as it always did: its
## door starts up as it pulls out (nothing here waits, so no trip changes).

## Ticks a garage door takes to go all the way up or down (10 s, as a real
## opener does; a tick is TrafficSim.DT).
const OPEN_TICKS := TrafficSim.DOOR_TICKS
## Ticks past a door's full travel that a parked car's door_t still counts:
## a driver who never got in (it closes then).
const STALE := 60
## Seconds out a car coming home presses the opener, at the speed it is
## driving (at least LEAD_V m/s); turning in and up the drive takes a few
## seconds more, so the door is about up as it gets there.
const LEAD := 6.0
const LEAD_V := 4.0
## Ticks a warehouse's dock door takes to go all the way up or down (about
## 12 s, as a real dock door's opener does).
const DOCK_TICKS := 120
## Ticks a factory's or a service garage's 12 x 14 ft overhead door takes
## (about 14 s), a shop's roll-up shutter (about 12 s), and a shed's
## sliding leaves pushed by hand (about 4 s).
const BAY_TICKS := 140
const ROLL_TICKS := 120
const SLIDE_TICKS := 40
## A police sally port's, an ER's and a bus garage's doors are the fast
## kind those buildings fit (about 2 ft a second: 7 s), so they are up as
## the vehicle that set off from out front goes by.
const GARAGE_TICKS := 70
## Seconds out a truck bound for a factory bay presses the opener.
const BAY_LEAD := 12.0
## Metres from a shop its delivery truck keeps the roll-up up, coming and
## going; from a service garage, its own vehicles.
const SHOP_NEAR := 40.0
const SVC_NEAR := 45.0
## A bay's door is the builder's nearest within this many metres of it.
const BAY_MATCH := 25.0

var traffic: TrafficSim
## The town the traffic belongs to, for its lots (else the one the traffic
## last stepped with).
var town: CitySim
## (car, leaving) -> true for a car drawn out on the drive instead of in
## its garage (TrafficView.out_front); unset, every car is in its garage.
var out_front := Callable()
## [place ref, spot] -> [the place it was matched in, door index or -1].
var _match := {}
## Lot ref -> where its front is, or null for a ref that isn't a lot.
var _fronts := {}
## The doors a view drew for a place: ref ("lot:<key>" for a shop or a
## plant, "svc:<id>" for a service) -> DoorLog list in its frame ([] when
## it isn't drawn). Unset, plants, shops and service garages stay shut.
var doors_of := Callable()
## More doors open now, worked out elsewhere: (eye, reach) -> [[ref, door
## index, door in the world, exact], ...] (the farmsteads' sheds).
var more := Callable()
## The plants and shops (lot refs) with a door that opens and the service
## garages near the camera, looked up again once it has moved NEAR_AGAIN
## metres or after NEAR_TICKS (a shop just built or drawn): trucks are
## looked for there only, never through every vehicle in town.
var _near_lots := []
var _near_set := {}
var _near_svcs := {}
var _near_eye := Vector3.INF
var _near_tick := -1
const NEAR_AGAIN := 16.0
const NEAR_TICKS := 300
## The vehicles a service garage keeps: its ambulances, cruisers and buses.
const GARAGE_KINDS := {"ambulance": true, "police": true, "city_bus": true, "school_bus": true, "coach": true}


func _init(t: TrafficSim, sim: CitySim = null) -> void:
	traffic = t
	town = sim


## The garage doors that should be up now within `reach` metres (flat) of
## `eye`: door key ("ref#door") -> [place ref, door index, lot-frame door
## (DoorLog), exact], where exact is how far up the door is (0 to 1) when
## the simulation says so (a car waiting for it), or -1 when it is simply
## going up at its own pace. Doors not listed are coming down, or shut.
func open_near(eye: Vector3, reach: float) -> Dictionary:
	var out := {}
	var r2 := reach * reach
	var tick: int = traffic._tick
	# Parked in the garage, its driver on the way out to it (or in it,
	# waiting for a gap): only these have door_t.
	for vid in traffic._doored:
		var car: Dictionary = traffic._doored[vid]
		if not car.has("door_t") or not car.has("at_place") or tick < int(car.door_t):
			continue
		if not car.has("pending") and tick > int(car.door_t) + int(car.door_n) + STALE:
			continue
		if _far(car.pos, eye, r2) or _out(car, true):
			continue
		_put(out, car.at_place, int(car.spot), up(car, tick))
	_docks(out, eye, reach)
	var works := doors_of.is_valid() and _works(out, eye, reach)
	if more.is_valid():
		for e in more.call(eye, reach):
			out["%s#%d" % [e[0], e[1]]] = e
	for car in traffic.cars:
		# A truck or a service garage's own vehicle, with plants, shops or
		# garages near (most are cars and pickups: passed over at a glance).
		if works and (float(car.len) > 6.5 or GARAGE_KINDS.has(car.kind)):
			_work_car(out, car, eye, r2)
		var j = car.get("j")
		if j != null and int(j.get("node", 0)) == -1:
			if int(j.wi) == -1 and car.has("dock_t"):
				_off_dock(out, car, eye, reach)  # pulling off a warehouse dock
				continue
			if int(j.wi) == -1:
				# Backing out of where it was parked, down the drive.
				if car.jd < float(j.get("rev", 0.0)):
					_leaving(out, car, eye, r2)
				continue
			if int(j.wo) == -1:
				_coming(out, car, eye, r2)  # turning in and up the drive
			continue
		# On its own street, nearly home.
		if j == null and car.has("route") and int(car.leg) == car.route.size() - 1 \
				and float(car.end_d) - float(car.d) < maxf(float(car.v), LEAD_V) * LEAD:
			_coming(out, car, eye, r2)
	return out


func _leaving(out: Dictionary, car: Dictionary, eye: Vector3, r2: float) -> void:
	var ref: String = car.get("from_place", "")
	if _far_lot(ref, eye, r2):
		return
	var pl := _place(ref)
	if pl.is_empty():
		return
	# The spot it backs out of is where its path starts (the car forgets
	# its spot number as it sets off): its front bumper there.
	if not car.has("door_t"):
		return  # (set off from a save made before doors: it stays shut)
	var start: Vector3 = car.j.pts[0]
	var spot := -1
	for i in pl.spots.size():
		var s: Dictionary = pl.spots[i]
		if s.kind == "garage" and (s.pos + s.face * float(car.len) * 0.5).distance_squared_to(start) < 0.25:
			spot = i
			break
	if not TrafficSim._behind_door(pl, spot) or _out(car, true):
		return
	_put(out, ref, spot, up(car, traffic._tick))


func _coming(out: Dictionary, car: Dictionary, eye: Vector3, r2: float) -> void:
	var ref: String = car.get("to_place", "")
	var spot: int = car.get("to_spot", -1)
	if spot < 0 or _far_lot(ref, eye, r2):
		return
	var pl := _place(ref)
	if not TrafficSim._behind_door(pl, spot) or _out(car, false):
		return
	_put(out, ref, spot, -1.0)


func _put(out: Dictionary, ref: String, spot: int, exact: float) -> void:
	var pl := _place(ref)
	if pl.is_empty():
		return
	var i := _door_of(pl, spot)
	if i < 0:
		return
	var key := "%s#%d" % [ref, i]
	var had: Array = out.get(key, [])
	if not had.is_empty():
		# Two cars, one door (a wide two-car door): a car already going in
		# or out under it keeps it going up; else the further up wins.
		had[3] = -1.0 if exact < 0.0 or had[3] < 0.0 else maxf(exact, had[3])
		return
	out[key] = [ref, i, pl.lay.doors[i], exact]


## The dock doors of the warehouses near the camera with a truck backed up
## to them, being unloaded or about to leave, exactly as far up as the time
## since it got there says.
func _docks(out: Dictionary, eye: Vector3, reach: float) -> void:
	var sim: CitySim = town if town != null else traffic._sim
	if sim == null:
		return
	var tick: int = traffic._tick
	for id in sim.warehouses.buildings:
		var w: Dictionary = sim.warehouses.buildings[id]
		if Warehouses.is_store(w):
			continue
		var r := reach + Warehouses.site_width(w) * 0.5
		if _far(w.pos, eye, r * r):
			continue
		var ref := Warehouses.traffic_ref(id, w)
		var at: Array = traffic._parked_at.get(ref, [])
		if at.is_empty():
			continue  # no truck there
		var pl := _place(ref)
		if pl.is_empty():
			continue
		for car in at:
			if not car.has("dock_t") or (int(car.until) < 0 and not car.get("pending", false)):
				continue
			var i: int = car.spot
			if i >= 0 and i < pl.spots.size() and pl.spots[i].get("rear", false):
				_put_dock(out, ref, w, int(pl.spots[i].door), clampf(float(tick - int(car.dock_t)) / DOCK_TICKS, 0.0, 1.0))


## A truck pulling off a warehouse dock: its door stays up until it is out
## in the street.
func _off_dock(out: Dictionary, car: Dictionary, eye: Vector3, reach: float) -> void:
	var ref: String = car.get("from_place", "")
	var sim: CitySim = town if town != null else traffic._sim
	if not ref.begins_with("wh:") or sim == null:
		return
	var w = sim.warehouses.buildings.get(int(ref.substr(3).get_slice("@", 0)))
	if w == null:
		return
	var pl := _place(ref)
	var r := reach + Warehouses.site_width(w) * 0.5
	if _far(w.pos, eye, r * r):
		return
	# The dock it pulls off is where its path starts (the truck forgets its
	# spot number as it sets off): its front bumper there.
	var start: Vector3 = car.j.pts[0]
	for s in pl.spots:
		if s.get("rear", false) and TrafficSim._nose(s, float(car.len)).distance_squared_to(start) < 0.25:
			_put_dock(out, ref, w, int(s.door), -1.0)
			return


func _put_dock(out: Dictionary, ref: String, w: Dictionary, door: int, exact: float) -> void:
	var doors := Warehouses.dock_doors(w)
	if door < 0 or door >= doors.size():
		return
	var key := "%s#%d" % [ref, door]
	var had: Array = out.get(key, [])
	if not had.is_empty():
		had[3] = -1.0 if exact < 0.0 or had[3] < 0.0 else maxf(exact, had[3])
		return
	out[key] = [ref, door, doors[door], exact]


## How many ticks a door of `kind` (of place `ref`) takes to go all the
## way up or down.
static func ticks_of(kind: String, ref := "") -> int:
	if kind == "bay" and ref.begins_with("svc:"):
		return GARAGE_TICKS
	match kind:
		"dock": return DOCK_TICKS
		"bay": return BAY_TICKS
		"rollup": return ROLL_TICKS
		"slider": return SLIDE_TICKS
	return OPEN_TICKS


## Factory bays, shop roll-ups and service garages (step 3): the doors up
## for trucks parked at them. True when there are any near the camera, so
## the vehicles on the road want a look too (_work_car).
func _works(out: Dictionary, eye: Vector3, reach: float) -> bool:
	var sim: CitySim = town if town != null else traffic._sim
	if sim == null:
		return false
	var r2 := reach * reach
	var tick: int = traffic._tick
	if _flat(eye, _near_eye) > NEAR_AGAIN or tick - _near_tick > NEAR_TICKS or tick < _near_tick:
		_near_eye = eye
		_near_tick = tick
		_near_lots.clear()
		var r := reach + 40.0
		var keys: Array = sim.lots.keys() if r > 4000.0 else sim.lots_near(Rect2(eye.x - r, eye.z - r, r * 2.0, r * 2.0))
		for key in keys:
			var z := _zone(sim, "lot:" + key)
			if z != ZoneMap.Zone.INDUSTRIAL and z != ZoneMap.Zone.COMMERCIAL:
				continue
			# Only those drawn with a door that opens (most shops have none).
			for d in doors_of.call("lot:" + key):
				if d[0] == "bay" or d[0] == "rollup":
					_near_lots.append("lot:" + key)
					break
		_near_lots.sort()
		_near_set.clear()
		for ref in _near_lots:
			_near_set[ref] = true
		_near_svcs = _garages_near(sim, eye, reach)
	# Parked: a truck in a factory's bay with a trip ahead of it, or one
	# stopped at a shop with somewhere to go next (one simply based there
	# opens nothing).
	for ref in _near_lots:
		for car in traffic._parked_at.get(ref, []):
			if float(car.len) <= 6.5 or int(car.until) < 0 and not car.get("pending", false) or _far_lot(ref, eye, r2):
				continue
			match _zone(sim, ref):
				ZoneMap.Zone.INDUSTRIAL:
					var pl := traffic.cached_place(ref)
					var i := int(car.get("spot", -1))
					if i >= 0 and i < pl.get("spots", []).size() and pl.spots[i].kind == "bay":
						_put_site(out, ref, _bay_door(ref, pl.spots[i].local))
				ZoneMap.Zone.COMMERCIAL:
					_put_site(out, ref, _rollup(ref, car))
	return not _near_lots.is_empty() or not _near_svcs.is_empty()


## A truck coming to or going from a plant or a shop near the camera, or a
## service garage's own vehicle leaving it or coming back.
func _work_car(out: Dictionary, car: Dictionary, eye: Vector3, r2: float) -> void:
	var sim: CitySim = town if town != null else traffic._sim
	var from: String = car.get("from_place", "")
	var to: String = car.get("to_place", "")
	if float(car.len) > 6.5 and (_near_set.has(from) or _near_set.has(to)):
		_lot_truck(out, sim, car, from, to, eye, r2)
	if not _near_svcs.is_empty() and GARAGE_KINDS.has(car.kind):
		var id := _garage_of(sim, car, from, to)
		if _near_svcs.has(id):
			_put_garage(out, sim, car, id, _near_svcs[id])


## A truck coming to or going from a factory's bay or a shop.
func _lot_truck(out: Dictionary, sim: CitySim, car: Dictionary, from: String, to: String, eye: Vector3, r2: float) -> void:
	var j = car.get("j")
	var off_road: bool = j != null and int(j.get("node", 0)) == -1
	if to.begins_with("lot:") and not _far_lot(to, eye, r2):
		var z := _zone(sim, to)
		var near: bool = off_road and int(j.wo) == -1  # turning in
		if j == null and car.has("route") and int(car.leg) == car.route.size() - 1:
			var left := float(car.end_d) - float(car.d)
			near = left < (maxf(float(car.v), LEAD_V) * BAY_LEAD if z == ZoneMap.Zone.INDUSTRIAL else SHOP_NEAR)
		if near and z == ZoneMap.Zone.INDUSTRIAL:
			var pl := traffic.cached_place(to)
			var i := int(car.get("to_spot", -1))
			if i >= 0 and i < pl.get("spots", []).size() and pl.spots[i].kind == "bay":
				_put_site(out, to, _bay_door(to, pl.spots[i].local))
		elif near and z == ZoneMap.Zone.COMMERCIAL:
			_put_site(out, to, _rollup(to, car))
	if from.begins_with("lot:") and not _far_lot(from, eye, r2):
		var pulling: bool = off_road and int(j.wi) == -1
		match _zone(sim, from):
			ZoneMap.Zone.INDUSTRIAL:
				# Pulling out of its bay (it forgets its spot as it sets off:
				# the bay is where its path starts), until it is in the street.
				if pulling:
					var pl := traffic.cached_place(from)
					var start: Vector3 = j.pts[0]
					var best := -1
					var gap := 15.0 * 15.0
					for i in pl.get("spots", []).size():
						var s: Dictionary = pl.spots[i]
						if s.kind == "bay" and (s.pos as Vector3).distance_squared_to(start) < gap:
							gap = (s.pos as Vector3).distance_squared_to(start)
							best = i
					if best >= 0:
						_put_site(out, from, _bay_door(from, pl.spots[best].local))
			ZoneMap.Zone.COMMERCIAL:
				var going: bool = j == null and car.has("route") and int(car.leg) == 0
				if pulling or going and _flat(traffic.car_pose(car)[0], _fronts[from]) < SHOP_NEAR:
					_put_site(out, from, _rollup(from, car))


## The door of `ref` (a plant's lot) its bay at `local` (the lot's frame)
## goes in by: the builder's nearest overhead door, or -1.
func _bay_door(ref: String, local: Vector2) -> int:
	var best := -1
	var gap := BAY_MATCH
	var doors: Array = doors_of.call(ref)
	for i in doors.size():
		var c: Vector3 = doors[i][1]
		var d := Vector2(c.x - local.x, c.z - local.y).length()
		if doors[i][0] == "bay" and d < gap:
			gap = d
			best = i
	return best


## The stockroom roll-up of shop `ref` that `car` delivers to (one of them,
## the same each time for the same truck), or -1.
func _rollup(ref: String, car: Dictionary) -> int:
	var doors: Array = doors_of.call(ref)
	var ups := []
	for i in doors.size():
		if doors[i][0] == "rollup":
			ups.append(i)
	return -1 if ups.is_empty() else ups[posmod(int(car.id), ups.size())]


func _put_site(out: Dictionary, ref: String, door: int) -> void:
	if door < 0:
		return
	var key := "%s#%d" % [ref, door]
	if not out.has(key):
		out[key] = [ref, door, doors_of.call(ref)[door], -1.0]


## The service garages near the camera with bay doors drawn: id -> [its
## frame, the bay doors' indices]. Only those whose vehicles drive real
## trips from them: a hospital's ambulances, a police station's cruisers,
## a bus depot's buses.
func _garages_near(sim: CitySim, eye: Vector3, reach: float) -> Dictionary:
	var out := {}
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if not (int(b.kind) == Services.Kind.POLICE or int(b.kind) == Services.Kind.BUS_DEPOT or sim.healthcare.hubs.has(id)):
			continue
		var r := reach + Services.size_of(b).length() * 0.5
		if _far(b.pos, eye, r * r):
			continue
		var doors: Array = doors_of.call("svc:%d" % id)
		var bays := []
		for i in doors.size():
			if doors[i][0] == "bay":
				bays.append(i)
		if not bays.is_empty():
			out[id] = [Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos), bays]
	return out


## The service garage `car` is the ambulance, cruiser or bus of, leaving
## it or coming back to it (its trip starts or ends there), or -1.
func _garage_of(sim: CitySim, car: Dictionary, from: String, to: String) -> int:
	for ref: String in [from, to]:
		var id := -1
		if ref.begins_with("police:") or ref.begins_with("hospital:"):
			id = int(ref.get_slice(":", 1).get_slice("@", 0))
		elif ref.begins_with("bus:"):
			var bus = sim.buses.buses.get(int(ref.get_slice(":", 1).get_slice("@", 0)))
			id = int(bus.depot) if bus != null else -1
		else:
			continue
		var b = sim.services.buildings.get(id)
		if b == null or ref.find("@") < 0:
			continue
		# A bus's trip ends at each stop too: only one to or from its depot.
		var at := ref.get_slice("@", 1)
		var p := Vector3(float(at.get_slice(",", 0)), 0.0, float(at.get_slice(",", 1)))
		if _flat(p, b.pos) <= Services.size_of(b).length() * 0.5 + 15.0:
			return id
	return -1


## Opens the bay door of garage `id` nearest `car`, while it is within SVC_NEAR.
func _put_garage(out: Dictionary, sim: CitySim, car: Dictionary, id: int, g: Array) -> void:
	var at: Vector3 = traffic.car_pose(car)[0]
	var b: Dictionary = sim.services.buildings.get(id, {})
	if b.is_empty() or _flat(at, b.pos) > SVC_NEAR + Services.size_of(b).length() * 0.5:
		return
	var local: Vector3 = (g[0] as Transform3D).affine_inverse() * at
	var doors: Array = doors_of.call("svc:%d" % id)
	var best := -1
	var gap := INF
	for i in g[1]:
		var c: Vector3 = doors[i][1]
		var d := Vector2(c.x - local.x, c.z - local.z).length_squared()
		if d < gap:
			gap = d
			best = i
	_put_site(out, "svc:%d" % id, best)


func _zone(sim: CitySim, ref: String) -> int:
	return int(sim.buildings.get(ref.substr(4), {}).get("zone", -1))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## door_for, kept per place and spot.
func _door_of(pl: Dictionary, spot: int) -> int:
	var k := [pl.ref, spot]
	var had: Array = _match.get(k, [])
	if not had.is_empty() and is_same(had[0], pl):
		return had[1]
	if _match.size() > 4096:
		_match.clear()
	var best := door_for(pl, spot)
	_match[k] = [pl, best]
	return best


## How far up (0 to 1) the garage door of a car with door_t is at `tick`.
static func up(car: Dictionary, tick: int) -> float:
	return clampf(float(tick - int(car.door_t)) / maxf(float(car.get("door_n", OPEN_TICKS)), 1.0), 0.0, 1.0)


## The door place `pl`'s garage spot `spot` faces: the nearest across of
## its logged doors that face out the way a car backs out (-1 if none is in
## front of it). The simulation asks too, before it opens one.
static func door_for(pl: Dictionary, spot: int) -> int:
	if spot < 0 or spot >= pl.get("spots", []).size():
		return -1
	var best := -1
	var s: Dictionary = pl.spots[spot]
	var at: Vector2 = s.local
	var doors: Array = pl.get("lay", {}).get("doors", [])
	var gap := INF
	for i in doors.size():
		var d: Array = doors[i]
		var c: Vector3 = d[1]
		var f: Vector3 = d[2]
		if d[0] != "garage" or f.z > -0.5 or c.z > at.y:
			continue  # not facing the street, or behind the car
		var off := absf(c.x - at.x)
		if off < float(d[3]) * 0.5 + 0.5 and off < gap:
			gap = off
			best = i
	return best


## True unless `ref` is a lot whose front is within the reach: looked at
## before the place, which a car bound for work also has.
func _far_lot(ref: String, eye: Vector3, r2: float) -> bool:
	if not _fronts.has(ref):
		if _fronts.size() > 8192:
			_fronts.clear()
		var sim: CitySim = town if town != null else traffic._sim
		var lot = sim.lots.get(ref.substr(4)) if ref.begins_with("lot:") and sim != null else null
		_fronts[ref] = lot.front if lot != null else null
	var f = _fronts[ref]
	return f == null or _far(f, eye, r2)


## The traffic's place for `ref` as it has it (place() checks the building
## is the same each call, more than a look every tick needs; a place it
## hasn't laid out yet is laid out).
func _place(ref: String) -> Dictionary:
	var pl = traffic._places.get(ref)
	return pl if pl != null else traffic.place(ref)


func _out(car: Dictionary, leaving: bool) -> bool:
	return out_front.is_valid() and bool(out_front.call(car, leaving))


static func _far(p: Vector3, eye: Vector3, r2: float) -> bool:
	return (p.x - eye.x) * (p.x - eye.x) + (p.z - eye.z) * (p.z - eye.z) > r2
