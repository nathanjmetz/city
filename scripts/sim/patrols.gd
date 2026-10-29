class_name Patrols
extends RefCounted
## Police patrol beats, after Caesar III's walkers (Brawn, 2026-10-29): a
## police station keeps cruisers out on patrol around the clock, each one
## driving the streets in its station's reach that have gone longest
## without a car, so a street counts as patrolled once a cruiser has
## actually been down it lately. A real small-town department keeps one or
## two cars on the road a shift over three 8-hour shifts; a car parks at the
## station between shifts, and every leg of its beat is a real trip.
##
## The Police view and a clicked station show it: streets fade from bright
## green (driven this shift) to nothing as the days pass, and lined streets
## no cruiser has reached show red. The coverage that homes count (police
## within reach, Services) stays by road distance, the response time.

## Street (road segment) -> the tick a cruiser last drove down it.
var beats := {}
## Trip id -> {station, vid, seg (where it's headed: a street, or -1 for the
## station), ends (the tick its shift ends), route: [streets on the way]}.
var trips := {}

var _reach := {}  # station id -> [network revision, its spot, node -> metres]


## Whether a cruiser drove street `seg` within PATROL_FRESH_TICKS.
func patrolled(sim: CitySim, seg: int) -> bool:
	return freshness(sim, seg) >= 0.0


## 1.0 for a street driven just now, falling to 0.0 at PATROL_FRESH_TICKS;
## -1.0 if no cruiser has been down it in that long (or ever).
func freshness(sim: CitySim, seg: int) -> float:
	if not beats.has(seg):
		return -1.0
	var age := sim.tick_count - int(beats[seg])
	return -1.0 if age > Balance.PATROL_FRESH_TICKS else 1.0 - float(age) / Balance.PATROL_FRESH_TICKS


## The cruisers station `id` keeps on the road each shift: Funding adds or
## takes away a car.
static func cars(sim: CitySim, id: int) -> int:
	return maxi(1, roundi(Balance.PATROL_CARS * sim.services.funding(id, Balance.POLICY_CARS)))


## Cruisers out on patrol for station `id` now.
func out(id: int) -> int:
	var n := 0
	for t in trips.values():
		if int(t.station) == id:
			n += 1
	return n


func tick(sim: CitySim) -> void:
	if sim.simulate_traffic:
		for a in sim.traffic.arrivals:
			if trips.has(a.id):
				var t: Dictionary = trips[a.id]
				trips.erase(a.id)
				t.vid = int(a.vid)
				_arrive(sim, t)
		for f in sim.traffic.failed:
			if trips.has(f.id):
				var t: Dictionary = trips[f.id]
				trips.erase(f.id)
				if f.has("vid"):
					t.vid = int(f.vid)
				_next(sim, t, [int(t.seg)])
	# On the hour, each station tops up the cars it keeps out (a new
	# station's first shift, or a car that came in early); a shift's cars
	# head in at the next shift change.
	if sim.tick_count % CitySim.TICKS_PER_HOUR != 0:
		return
	var since := posmod(Mail.minute_of_day(sim.tick_count) - Balance.PATROL_FIRST_SHIFT * 60, Balance.PATROL_SHIFT_HOURS * 60)
	var ends := sim.tick_count + Balance.PATROL_SHIFT_HOURS * 60 - since
	var ids := _stations(sim)
	if sim.simulate_traffic:
		for id in ids:
			for i in cars(sim, id) - out(id):
				var t := {"station": id, "vid": -1, "seg": -1, "ends": ends, "route": []}
				_next(sim, t, [], _front(sim, id))
	elif since == 0:
		# With cars switched off (the balance harness), each shift's cars
		# simply drive their share of the beat.
		for id in ids:
			var picks := _beat(sim, id, _front(sim, id), cars(sim, id) * Balance.PATROL_STREETS_PER_SHIFT, [])
			for seg in picks:
				beats[seg] = sim.tick_count


## The town's police stations that are open (built), in id order.
func _stations(sim: CitySim) -> Array:
	var ids := []
	for id in sim.services.buildings:
		if int(sim.services.buildings[id].kind) == Services.Kind.POLICE and sim.construction.is_done("svc:%d" % id, sim.tick_count):
			ids.append(id)
	ids.sort()
	# A station torn down: its cars' trips are forgotten, so they stay parked.
	for tid in trips.keys():
		if not sim.services.buildings.has(int(trips[tid].station)):
			trips.erase(tid)
	return ids


func _front(sim: CitySim, id: int) -> Vector3:
	var b: Dictionary = sim.services.buildings[id]
	return b.pos + b.dir * Services.size_of(b).y * 0.5


## A cruiser got where it was headed: the streets on the way and the one it
## came for are patrolled; it goes on to the next, or home when the shift's
## over.
func _arrive(sim: CitySim, t: Dictionary) -> void:
	if not sim.services.buildings.has(int(t.station)):
		return  # its station was torn down: the car stays parked where it is
	if int(t.seg) == -1:
		return  # back at the station, parked till the next shift
	for seg in t.route:
		beats[int(seg)] = sim.tick_count
	beats[int(t.seg)] = sim.tick_count
	_next(sim, t, [])


## Sends a cruiser on its next leg: the street in reach that's gone longest
## without a car (of the few nearest it), or back to the station.
func _next(sim: CitySim, t: Dictionary, skip: Array, from := Vector3.INF) -> void:
	var id := int(t.station)
	if not sim.services.buildings.has(id):
		return
	var curbs := _curbs(sim)
	var at: Vector3 = from if from != Vector3.INF else curbs.get(int(t.seg), _front(sim, id))
	if sim.tick_count < int(t.ends):
		var taken := skip.duplicate()
		for o in trips.values():
			taken.append(int(o.seg))
		for seg in _beat(sim, id, at, Balance.PATROL_TRIES, taken):
			if _send(sim, t, seg, curbs[seg]):
				return
	t.seg = -1
	_send(sim, t, -1, _front(sim, id))


## Up to `n` streets for a cruiser at `at` to drive next, best first: of the
## lined streets in its station's reach, the ones gone longest without a
## car, the nearest of those first.
func _beat(sim: CitySim, id: int, at: Vector3, n: int, taken: Array) -> Array:
	var dist := _reach_of(sim, id)
	var reach := float(Services.KINDS[Services.Kind.POLICE].reach)
	var curbs := _curbs(sim)
	var rows := []
	for seg in curbs:
		if seg in taken or not sim.network.segments.has(seg):
			continue
		var s: Dictionary = sim.network.segments[seg]
		if minf(dist.get(s.a, INF), dist.get(s.b, INF)) > reach:
			continue
		# Streets driven within the same few hours count as one bunch, so a
		# car works through the oldest ones near it rather than crossing town.
		var age := floori(float(beats.get(seg, -Balance.PATROL_FRESH_TICKS * 4)) / (Balance.PATROL_BUNCH_HOURS * 60))
		rows.append([age, at.distance_to(curbs[seg]), seg])
	rows.sort()
	return rows.slice(0, n).map(func(r): return r[2])


func _send(sim: CitySim, t: Dictionary, seg: int, to: Vector3) -> bool:
	var to_ref := "police:%d" % t.station if seg == -1 else "street:%d" % seg
	var dest := {"ref": to_ref, "pos": [snappedf(to.x, 0.01), snappedf(to.z, 0.01)]}
	var trip := -1
	if int(t.vid) != -1:
		trip = sim.traffic.move(int(t.vid), dest, "police")
	if trip == -1:
		var front := _front(sim, int(t.station))
		trip = sim.traffic.dispatch({"ref": "police:%d" % t.station, "pos": [snappedf(front.x, 0.01), snappedf(front.z, 0.01)]},
			dest, "police")
	if trip == -1:
		return false
	t.seg = seg
	t.route = _route_of(sim, trip)
	trips[trip] = t
	return true


## The streets a trip drives down on the way, from its route.
static func _route_of(sim: CitySim, trip: int) -> Array:
	for c in sim.traffic.cars + sim.traffic._waiting:
		if int(c.get("trip", c.id)) == trip:
			var out := []
			for w in c.get("route", []):
				var seg := int(w) / 2
				if not seg in out:
					out.append(seg)
			return out
	return []


## Lined streets (with homes or businesses on them) -> a curb in front of one.
static func _curbs(sim: CitySim) -> Dictionary:
	var out := {}
	var keys := sim.lots.keys()
	keys.sort()
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		if not out.has(int(lot.seg)):
			out[int(lot.seg)] = lot.front
	return out


## Road distance from station `id` (node -> metres), kept until the roads
## change or it moves.
func _reach_of(sim: CitySim, id: int) -> Dictionary:
	var b: Dictionary = sim.services.buildings[id]
	var key := [sim.network.get_instance_id(), sim.network.revision, b.pos, b.dir, sim.services.funding(id, Balance.POLICY_EFFECT)]
	var e: Array = _reach.get(id, [])
	if e.is_empty() or e[0] != key:
		e = [key, sim.services.reach_of(sim.network, id, float(Services.KINDS[Services.Kind.POLICE].reach))]
		_reach[id] = e
	return e[1]


func to_dict() -> Dictionary:
	var b := {}
	for seg in beats:
		b[str(seg)] = beats[seg]
	var tr := {}
	for id in trips:
		tr[str(id)] = trips[id]
	return {"beats": b, "trips": tr}


func from_dict(d: Dictionary) -> void:
	beats.clear()
	for k in d.get("beats", {}):
		beats[int(k)] = int(d.beats[k])
	trips.clear()
	for k in d.get("trips", {}):
		var t: Dictionary = d.trips[k]
		trips[int(k)] = {"station": int(t.station), "vid": int(t.get("vid", -1)), "seg": int(t.seg),
			"ends": int(t.ends), "route": (t.get("route", []) as Array).map(func(s): return int(s))}
