class_name People
extends RefCounted
## Everyone in town, by name, like the citizens of Cities: Skylines: each
## person has a home, maybe a job, an age, and is somewhere right now (at
## home, out at a named place, or on the way). Households own their cars.
##
## The buildings' head counts (buildings[key].occ) say how many live where;
## this keeps a real person for each of them, and names every place.

## Share of adults with a driver's licence and a car of their own, up to
## two cars a household (the US averages about 1.9).
const MAX_CARS := 2
## Furthest anyone walks instead of driving, in metres.
const WALK_MAX := 260.0
const WORK_AGE := [18, 66]
## sync() goes over every building and resident (16 ms in a 3,000-building
## town), so it runs once every SYNC_EVERY ticks, off the move-in tick:
## people move in, out and lose closed jobs within a few game minutes.
const SYNC_EVERY := 10
const SYNC_AT := 5

## id -> {id, first, last, age, home (lot key), job ("lot:key" or ""),
## car (vehicle id or -1), at ("" at home, a place ref while out, "travel"),
## until (tick to head off again, or -1)}
var people := {}
## Place ref ("lot:key", "farm:3"...) -> its name. Unique across the town.
var names := {}
var _taken := {}   # name -> true
var _homes := {}   # lot key -> [person ids], oldest first
var _staff := {}   # job ref -> number of people working there
var _next := 1
var _families: Families  # names on the signs, set each sync
## Share of daytime outings that are a walk on the trail, for people who
## live where it crosses or runs along their street.
const STROLL_SHARE := 0.2
var _due := {}   # tick -> ids of people who may head off then (set_until)
var _ids := []  # people.keys(), kept until someone moves in or out
var _ids_sig := []
## Working-age people without a job, so hiring looks only at them, not the
## whole town. Kept as people move in, lose a job or are hired; rebuilt from
## `people` after a load (not saved).
var _seekers := {}  # id -> true
var _seekers_ok := false


## Keeps a person for every resident, fills open jobs, names new places.
func sync(sim: CitySim, traffic: TrafficSim, rng: RandomNumberGenerator) -> void:
	_families = sim.families
	if sim.tick_count % SYNC_EVERY != SYNC_AT:
		return
	var keys: Array = sim.ledger().sorted
	for key in keys:
		var b: Dictionary = sim.buildings[key]
		var ref: String = "lot:" + key
		if b.zone == ZoneMap.Zone.RESIDENTIAL:
			var list: Array = _homes.get(key, [])
			while list.size() < b.occ:
				list.append(_move_in(key, list, traffic, rng, Names.surname(hash([int(b.seed), "home"]))))
			while list.size() > b.occ:
				_move_out(list.pop_back(), traffic)
			_homes[key] = list
			if not names.has(ref) and not list.is_empty():
				_name(ref, b.zone, rng, people[list[0]].last)
		elif not names.has(ref):
			_name(ref, b.zone, rng)
	# Farms, companies and city services get names too.
	var others := {}
	for id in sim.farms.farms:
		others["farm:%d" % id] = "farm"
	for id in sim.industry.sites:
		others["site:%d" % id] = str(sim.industry.sites[id].kind)
	for id in sim.services.buildings:
		others["service:%d" % id] = Services.KINDS[sim.services.buildings[id].kind].name
	var refs := others.keys()
	refs.sort()
	for ref in refs:
		if not names.has(ref):
			var n := PersonNames.other(others[ref], rng, _taken)
			names[ref] = n
			_taken[n] = true
	for ref in names.keys():
		if not ref.begins_with("lot:") and not others.has(ref):
			_forget(0, ref)
	# People whose home is gone have moved away.
	for key in _homes.keys():
		if not sim.buildings.has(key):
			for id in _homes[key]:
				_move_out(id, traffic)
			_homes.erase(key)
			_forget(ZoneMap.Zone.RESIDENTIAL, "lot:" + key)
	# Places that closed lose their staff and their name.
	for ref in names.keys():
		if ref.begins_with("lot:") and not sim.buildings.has(ref.substr(4)):
			_forget(0, ref)
	# Only when a workplace has closed are the people looked through.
	var shut := []
	for ref in _staff:
		if not _job_open(sim, ref):
			shut.append(ref)
	if not shut.is_empty():
		for id in people:
			var p: Dictionary = people[id]
			if p.job != "" and not _job_open(sim, p.job):
				_staff[p.job] = _staff.get(p.job, 1) - 1
				p.job = ""
				_seek(p)
		for ref in shut:
			if _staff.get(ref, 0) <= 0:
				_staff.erase(ref)
	if sim.tick_count % (SYNC_EVERY * 3) == SYNC_AT:
		_hire(sim, keys, rng)


## Sends people out and brings them home, by the time of day: to work in
## the morning, home in the evening, errands in between. Each outing is
## carried out by Traffic: a walk, or a walk to the car and a drive.
func plan(sim: CitySim, traffic: TrafficSim, rng: RandomNumberGenerator) -> void:
	if people.is_empty():
		return
	var now := sim.tick_count
	# Time to head home (or back to work after an errand).
	# Each is filed under the tick they're due (set_until), so only those
	# are looked at; taken in id order, as a loaded town would.
	if now % 5 == 0 and not _due.is_empty():
		var ids := []
		for t in _due.keys():
			if t <= now:
				for id in _due[t]:
					if people.has(id) and people[id].until == t:
						ids.append(id)
				_due.erase(t)
		ids.sort()
		var last := -1
		for id in ids:
			if id == last:
				continue
			last = id
			var p: Dictionary = people[id]
			if p.at != "" and p.at != "travel" and p.until >= 0 and p.until <= now:
				if not traffic.go(id, "lot:" + p.home, "home", -1):
					set_until(p, now + 30)  # try again in a while
	var hour: int = sim.clock().hour
	var rate := 0.15
	if hour >= 6 and hour < 9 or hour >= 16 and hour < 19:
		rate = 0.6
	elif hour >= 22 or hour < 5:
		rate = 0.03
	# At rush hour, about one outing a second for every 200 people.
	if rng.randf() > rate * people.size() / 1200.0:
		return
	if _ids_sig != [people.size(), _next]:
		_ids_sig = [people.size(), _next]
		_ids = people.keys()
	var ids := _ids
	for attempt in 6:
		var p: Dictionary = people[ids[rng.randi() % ids.size()]]
		if p.at != "" or p.age < 12:
			continue  # out already, or too young to go alone
		var work: bool = p.job != "" and hour >= 6 and hour < 10
		if work:
			var end_hour := rng.randi_range(15, 18)
			var stay: int = ((end_hour - hour) * 60 + rng.randi_range(-20, 20)) * CitySim.MINUTES_PER_TICK
			traffic.go(p.id, p.job, "commute", maxi(stay, 60))
			return
		if hour < 7 or hour >= 21:
			continue
		# Out for a walk on the trail, if it comes by (greenway counts in
		# Indiana run highest in the daytime on nice days).
		if not sim.parks.trails.paths.is_empty() and rng.randf() < STROLL_SHARE and traffic.stroll(p.id):
			return
		var shop := _shop_for(sim, p, rng)
		if shop != "":
			traffic.go(p.id, shop, "shopping", rng.randi_range(20, 90))
			return


## A shop to go to: usually one of the closer ones.
func _shop_for(sim: CitySim, p: Dictionary, rng: RandomNumberGenerator) -> String:
	var home: Dictionary = sim.lots.get(p.home, {})
	if home.is_empty():
		return ""
	var best := ""
	var best_score := INF
	for key in sim.zone_keys(ZoneMap.Zone.COMMERCIAL):
		var d: float = home.pos.distance_to(sim.lots[key].pos)
		var score := d * (0.5 + rng.randf())
		if score < best_score:
			best_score = score
			best = key
	return "" if best == "" else "lot:" + best


func person_name(id: int) -> String:
	if not people.has(id):
		return ""
	return "%s %s" % [people[id].first, people[id].last]


## A place's name: the business's own (Families, as on its sign) where it
## has one, else the one people here call it.
func place_name(ref: String) -> String:
	if _families != null and _families.name_of(ref) != "":
		return _families.name_of(ref)
	return names.get(ref, "")


func residents(key: String) -> Array:
	return _homes.get(key, [])


## When a person who is out heads off again (-1: not until sent).
func set_until(p: Dictionary, tick: int) -> void:
	p.until = tick
	if tick >= 0:
		if not _due.has(tick):
			_due[tick] = []
		_due[tick].append(p.id)


func staff(ref: String) -> int:
	return _staff.get(ref, 0)


## `family` is the household the house is known by (Families.home_name),
## so the first to move in carry that name.
func _move_in(key: String, household: Array, traffic: TrafficSim, rng: RandomNumberGenerator, family := "") -> int:
	var id := _next
	_next += 1
	var last := PersonNames.last(rng)
	if household.is_empty() and family != "":
		last = family
	elif not household.is_empty() and rng.randf() < 0.8:
		last = people[household[0]].last  # same family
	var adults := 0
	for h in household:
		if people[h].age >= 18:
			adults += 1
	var age := rng.randi_range(22, 78) if adults < 2 else rng.randi_range(0, 17)
	if adults >= 2 and rng.randf() < 0.3:
		age = rng.randi_range(18, 30)  # a grown child or a lodger
	var p := {"id": id, "first": PersonNames.first(rng), "last": last, "age": age, "home": key, "job": "",
		"car": -1, "at": "", "until": -1}
	people[id] = p
	_seek(p)
	var cars := 0
	for h in household:
		if people[h].car != -1:
			cars += 1
	if age >= 16 and cars < MAX_CARS and traffic != null:
		var kind := VehicleTypes.household(hash([key, id]))
		p.car = traffic.new_vehicle(kind, "lot:" + key, id)
	return id


func _move_out(id: int, traffic: TrafficSim) -> void:
	if not people.has(id):
		return
	var p: Dictionary = people[id]
	_seekers.erase(id)
	if p.job != "":
		_staff[p.job] = _staff.get(p.job, 1) - 1
	if p.car != -1 and traffic != null:
		traffic.retire_vehicle(p.car)
	if traffic != null:
		traffic.forget_person(id)
	people.erase(id)


func _name(ref: String, zone: int, rng: RandomNumberGenerator, family := "") -> void:
	var n := PersonNames.place(zone, rng, _taken, family)
	names[ref] = n
	_taken[n] = true


func _forget(_zone: int, ref: String) -> void:
	if names.has(ref):
		_taken.erase(names[ref])
		names.erase(ref)


func _seek(p: Dictionary) -> void:
	if p.job == "" and p.age >= WORK_AGE[0] and p.age <= WORK_AGE[1]:
		_seekers[p.id] = true


func _job_open(sim: CitySim, ref: String) -> bool:
	return ref.begins_with("lot:") and sim.buildings.has(ref.substr(4))


## Working-age people without a job take one where there are openings.
func _hire(sim: CitySim, keys: Array, rng: RandomNumberGenerator) -> void:
	var open := []
	for key in keys:
		var b: Dictionary = sim.buildings[key]
		if b.zone != ZoneMap.Zone.RESIDENTIAL and staff("lot:" + key) < b.cap:
			open.append("lot:" + key)
	if open.is_empty():
		return
	if not _seekers_ok:
		_seekers.clear()
		for id in people:
			_seek(people[id])
		_seekers_ok = true
	var ids := _seekers.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = people[id]
		if p.job != "" or p.age < WORK_AGE[0] or p.age > WORK_AGE[1]:
			_seekers.erase(id)
			continue
		var ref: String = open[rng.randi() % open.size()]
		p.job = ref
		_seekers.erase(id)
		_staff[ref] = staff(ref) + 1
		if staff(ref) >= sim.buildings[ref.substr(4)].cap:
			open.erase(ref)
			if open.is_empty():
				return


func to_dict() -> Dictionary:
	return {"bin": Marshalls.variant_to_base64({"people": people, "names": names, "homes": _homes, "staff": _staff,
		"next": _next})}


func from_dict(d: Dictionary) -> void:
	people.clear()
	names.clear()
	_taken.clear()
	_homes.clear()
	_staff.clear()
	_due.clear()
	_seekers.clear()
	_seekers_ok = false
	_next = 1
	if not d.has("state") and not d.has("bin"):
		return
	var s = TrafficSim._unpack(d)  # binary, so every number comes back exactly
	if typeof(s) != TYPE_DICTIONARY:
		return
	people = s.people
	names = s.names
	_homes = s.homes
	_staff = s.staff
	_next = s.next
	for id in people:
		if people[id].until >= 0:
			set_until(people[id], people[id].until)
	for ref in names:
		_taken[names[ref]] = true
