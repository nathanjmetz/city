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
	for car in traffic.cars:
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
