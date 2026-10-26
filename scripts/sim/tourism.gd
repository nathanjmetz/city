class_name Tourism
extends RefCounted
## Events and visitors (Brawn green-lit, 2026-10-22). Two venues are hubs:
## the county fairgrounds, whose fair board puts on the county fair each
## July, and the football field, whose boosters run Friday-night football
## in the fall. Each has a leader (Agency.leader) and a development tree
## (Balance.VENUE_TREES) paid from its own gate money; what's open to it
## depends on the town (farms nearby, people, schooling) and the region
## (a road out, what neighbor towns make). Extra events from the tree
## (harness races, track meets, concerts) fill other months.
##
## Who comes: a share of the town and of the people in the neighboring
## towns (from the trade partners and region server, as Mail counts them;
## a solo town draws on its county). Some of them drive in as real trips,
## in from the county highway or out from homes, park at the venue and go
## home when it ends; only a sample is driven so the game stays light.
## Out-of-town visitors spend in town, which the town taxes, and once a
## year's visitors from outside are enough, a gas station, a diner and a
## motel open by themselves on free road frontage nearby (Parks sites of
## kinds gas_station, diner, motel). Benchmark: CS2's tourism and
## signature venues; real Indiana county fairs and high school football.

## site id -> {kind, leader, built, why, savings, profit (last year's gate
## less upkeep), gate (this year), outside (visitors from out of town this
## year), outside_last, visitors (this year), visitors_last, crowd (the
## event on now: {name, visitors, outside, cars, start, end}), months}
var venues := {}
## Calendar month this was last run in (1 to 12), to roll the year.
var _month := -1


static func is_venue(kind: String) -> bool:
	return Balance.VENUES.has(kind)


## Signs up new venues and drops ones that are gone. Called from
## Parks.decide (and once a game hour from tick()).
func sync(sim: CitySim) -> void:
	for id in sim.parks.sites:
		var s: Dictionary = sim.parks.sites[id]
		if is_venue(s.kind) and not venues.has(id):
			var l := Agency.leader(sim, hash([sim.city_seed, "venue", id]))
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([sim.city_seed, "venue", id, "name"])
			l.name = "%s %s" % [Education.FIRST[rng.randi() % Education.FIRST.size()],
				Education.LAST[rng.randi() % Education.LAST.size()]]
			venues[id] = {"kind": s.kind, "leader": l, "built": [], "why": "", "savings": 0.0, "profit": 0.0,
				"gate": 0.0, "outside": 0.0, "outside_last": 0.0, "visitors": 0.0, "visitors_last": 0.0, "crowd": {}}
	for id in venues.keys():
		if not sim.parks.sites.has(id) or not is_venue(sim.parks.sites[id].kind):
			venues.erase(id)


## Every tick while there are venues: crowds come and go on the hour,
## cars on their minute, and the books once a month.
func tick(sim: CitySim) -> void:
	var t := sim.tick_count
	var minute := (t * CitySim.MINUTES_PER_TICK) % (24 * 60)
	if minute % 60 == 0:
		# The books once a sim day ("a month", Balance); crowds by the
		# calendar's season, which is what the land shows.
		var pm := Seasons.pace_month(t)
		if pm != _month:
			if _month != -1:
				_monthly(sim, pm)
			_month = pm
		var m := Seasons.month(sim.calendar_tick())
		sync(sim)
		var ids := venues.keys()
		ids.sort()
		for id in ids:
			_crowd(sim, id, m, minute / 60)
	for id in venues:
		var c: Dictionary = venues[id].crowd
		if not c.is_empty():
			_cars(sim, id, c, minute)


## The event a venue puts on this month, or {}: its own, or one its tree
## added (in Balance.VENUE_EXTRA_MONTHS order, never on top of another).
func event_in(id: int, month: int) -> Dictionary:
	var v: Dictionary = venues[id]
	var spec: Dictionary = Balance.VENUES[v.kind]
	var taken := []
	for ev in spec.events:
		if month in ev.months:
			return ev
		taken.append_array(ev.months)
	var extra := int(Agency.effect(v, Balance.VENUE_TREES[v.kind], "months+"))
	var n := 0
	for em in Balance.VENUE_EXTRA_MONTHS:
		if n >= extra:
			break
		if em in taken:
			continue
		n += 1
		if em == month:
			var ev: Dictionary = spec.events[0].duplicate()
			ev.name = _extra_name(v, n)
			# Smaller than the main event.
			ev.local = float(ev.local) * 0.5
			ev.region = float(ev.region) * 0.5
			return ev
	return {}


static func _extra_name(v: Dictionary, n: int) -> String:
	var names: Array = []
	for node in Balance.VENUE_TREES[v.kind]:
		if node.id in v.built and float(node.get("effects", {}).get("months+", 0.0)) > 0.0:
			names.append({"harness": "Harness races", "expo_hall": "Farm show", "track": "Track meet",
				"concerts": "Summer concert"}.get(node.id, str(node.name)))
	if names.is_empty():
		return "Event"
	return names[(n - 1) % names.size()]


## Who would come to an event: {visitors, outside} for the whole event.
func attendance(sim: CitySim, id: int, ev: Dictionary) -> Dictionary:
	var v: Dictionary = venues[id]
	var tree: Array = Balance.VENUE_TREES[v.kind]
	var draw := 1.0 + Agency.effect(v, tree, "draw+")
	var near := sim.mail.neighbors_of(sim)
	var region_pop: int = near.population if int(near.towns) > 0 else Balance.TOURISM_COUNTY_POP
	var local := float(ev.local) * int(sim.stats.get("population", 0)) * draw
	var outside := float(ev.region) * region_pop * draw
	var seats := float(Balance.VENUES[v.kind].seats) + Agency.effect(v, tree, "seats+")
	var total := local + outside
	if total > seats:
		local *= seats / total
		outside *= seats / total
	return {"visitors": roundi(local + outside), "outside": roundi(outside)}


## On the hour: an event opens (its crowd and gate are counted) or closes.
func _crowd(sim: CitySim, id: int, month: int, hour: int) -> void:
	var v: Dictionary = venues[id]
	# No events until the grandstand is built.
	var ev := event_in(id, month) if sim.construction.state("park:%d" % id, sim.tick_count).is_empty() else {}
	if ev.is_empty():
		if not v.crowd.is_empty():
			v.crowd = {}
			sim.parks_changed.emit()
		return
	if hour == int(ev.hours[0]) and v.crowd.is_empty():
		var a := attendance(sim, id, ev)
		v.visitors += a.visitors
		v.outside += a.outside
		v.gate += a.visitors * float(ev.ticket)
		v.savings += a.visitors * float(ev.ticket)
		var cars := clampi(a.visitors / Balance.TOURISM_VISITORS_PER_CAR, 0,
			Balance.TOURISM_MAX_CARS_HOUR * (int(ev.hours[1]) - int(ev.hours[0])))
		v.crowd = {"name": ev.name, "visitors": a.visitors, "outside": a.outside, "cars": cars,
			"start": int(ev.hours[0]) * 60, "end": int(ev.hours[1]) * 60}
		sim.parks_changed.emit()
	elif hour == int(ev.hours[1]) + 2 and not v.crowd.is_empty():
		v.crowd = {}
		sim.parks_changed.emit()


## Car `i` of a crowd arrives a few minutes after the gates open and leaves
## when it ends: from the county highway for the out-of-town share, else
## from a home in town. Same minutes on every copy of the city.
func _cars(sim: CitySim, id: int, c: Dictionary, minute: int) -> void:
	var n: int = c.cars
	if n <= 0:
		return
	var come := minute - int(c.start)
	var go := minute - int(c.end)
	var gap := maxi(1, (int(c.end) - int(c.start)) / maxi(n, 1) / 2)
	var i := -1
	var leaving := false
	if come >= 0 and come % gap == 0 and come / gap < n:
		i = come / gap
	elif go >= 0 and go % 3 == 0 and go / 3 < n:
		i = go / 3
		leaving = true
	if i < 0:
		return
	var s: Dictionary = sim.parks.sites[id]
	var gate := {"ref": "venue:%d" % id, "pos": [s.pos.x + s.dir.x * s.size.y * 0.5, s.pos.z + s.dir.z * s.size.y * 0.5]}
	var there := _origin(sim, id, i, float(c.outside) / maxf(float(c.visitors), 1.0))
	if there.is_empty():
		return
	var cargo := {"event": c.name, "from": there.get("town", "town")}
	# Out-of-town visitors come as visitors (campers and RVs among them).
	var purpose := "visitor" if there.get("town", "") == "out of town" else "shopping"
	if leaving:
		sim.traffic.dispatch(gate, there, purpose, cargo)
	else:
		sim.traffic.dispatch(there, gate, purpose, cargo)


## Where car `i` comes from: the county highway (out of town) or a home.
func _origin(sim: CitySim, id: int, i: int, outside: float) -> Dictionary:
	var h := absi(hash([id, i, "visitor"]))
	if not sim.region_links.is_empty() and float(h % 1000) / 1000.0 < outside:
		var n: int = sim.region_links[h % sim.region_links.size()]
		if sim.network.nodes.has(n):
			return {"ref": "edge", "pos": [sim.network.nodes[n].x, sim.network.nodes[n].z], "town": "out of town"}
	var homes := []
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			homes.append(key)
	if homes.is_empty():
		return {}
	homes.sort()
	var home: String = homes[h % homes.size()]
	return {"ref": "home:" + home, "pos": [sim.lots[home].front.x, sim.lots[home].front.z], "town": "town"}


## Once a month: the year rolls over in January, the leaders look at their
## trees, and businesses open for the visitors.
func _monthly(sim: CitySim, month: int) -> void:
	var ids := venues.keys()
	ids.sort()
	for id in ids:
		var v: Dictionary = venues[id]
		var upkeep: float = sim.parks.site_upkeep(id)
		v.savings = maxf(v.savings - upkeep, 0.0)
		if month == 1:
			v.profit = v.gate - upkeep * 12.0
			v.outside_last = v.outside
			v.visitors_last = v.visitors
			v.gate = 0.0
			v.outside = 0.0
			v.visitors = 0.0
		var s: Dictionary = sim.parks.sites[id]
		var profit := minf(maxf(v.profit, v.gate - upkeep * 12.0), v.savings)
		var node := Agency.develop(sim, v, Balance.VENUE_TREES[v.kind], s.pos, profit)
		if not node.is_empty():
			v.savings = maxf(v.savings - float(node.cost), 0.0)
			v.why = "The %s built %s%s." % ["fair board" if v.kind == "fairgrounds" else "boosters",
				str(node.name).to_lower(), (": " + str(node.note)) if node.has("note") else ""]
			sim.parks_changed.emit()
	_open_businesses(sim)


## Out-of-town visitors in the last twelve months, all venues.
func outside_year() -> float:
	var total := 0.0
	for id in venues:
		total += maxf(venues[id].outside, venues[id].outside_last)
	return total


## The town's monthly take from visitors' spending (food, gas, rooms).
func monthly_tax() -> float:
	return outside_year() * Balance.TOURISM_SPEND * Balance.TOURISM_LOCAL_TAX / 12.0


## Assessed value of the businesses that opened for visitors.
static func taxable_value(sim: CitySim) -> float:
	var total := 0.0
	for id in sim.parks.sites:
		var b := business(sim.parks.sites[id].kind)
		if not b.is_empty():
			total += float(b.value)
	return total


static func business(kind: String) -> Dictionary:
	for b in Balance.TOURISM_BUSINESSES:
		if b.kind == kind:
			return b
	return {}


## Jobs at the visitor businesses (they count as shop jobs).
static func jobs(sim: CitySim) -> int:
	var n := 0
	for id in sim.parks.sites:
		n += int(business(sim.parks.sites[id].kind).get("jobs", 0))
	return n


## Opens the next visitor business once enough come from out of town, on
## free frontage near the busiest venue. One at a time, never twice.
func _open_businesses(sim: CitySim) -> void:
	if venues.is_empty():
		return
	var busiest := -1
	var most := -1.0
	var ids := venues.keys()
	ids.sort()
	for id in ids:
		var o := maxf(venues[id].outside, venues[id].outside_last)
		if o > most:
			most = o
			busiest = id
	for b in Balance.TOURISM_BUSINESSES:
		if sim.parks.has_kind(b.kind):
			continue
		if outside_year() < float(b.visitors):
			return
		var site := frontage(sim, b.kind, sim.parks.sites[busiest].pos)
		if site.is_empty():
			return
		var bid := sim.parks.add(sim, b.kind, site[0], site[1])
		sim.parks.sites[bid].name = _business_name(sim, b.kind, bid)
		sim._clear_zones_under(sim.parks.footprint(bid))
		sim.parks_changed.emit()
		return


## Free frontage for a business near `at`: on a road that takes lots, not
## zoned, not reserved, on buildable land. [centre, dir] or [].
static func frontage(sim: CitySim, kind: String, at: Vector3) -> Array:
	var best := []
	var best_d := INF
	var segs := sim.network.segments.keys()
	segs.sort()
	for sid in segs:
		var c := sim.network.curve_of(sid)
		for k in 9:
			var p := RoadNetwork.bezier(c[0], c[1], c[2], (k + 0.5) / 9.0)
			var d := p.distance_to(at)
			if d > Balance.TOURISM_BUSINESS_REACH or d >= best_d:
				continue
			for side in [1.0, -1.0]:
				var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], (k + 0.5) / 9.0)
				var hit: Vector3 = p + Vector3(-tan.z, 0.0, tan.x).normalized() * float(side) * 30.0
				var site := Parks.site_near(sim.network, kind, hit)
				if site.is_empty():
					continue
				var poly := Parks.corners(site[0], site[1], Parks.size_of(kind))
				if sim.parks.ground_problem(sim, poly) != "" or _zoned(sim, poly):
					continue
				best = site
				best_d = d
				break
	return best


static func _zoned(sim: CitySim, poly: PackedVector2Array) -> bool:
	for p in Parks._samples(poly):
		if sim.zones.zone_at(Vector3(p.x, 0.0, p.y)) != ZoneMap.Zone.NONE:
			return true
	return false


static func _business_name(sim: CitySim, kind: String, id: int) -> String:
	var words := {"motel": ["Fairway Motel", "Starlite Motel", "Hoosier Inn", "Country Hearth Inn", "Sunset Motor Lodge"],
		"diner": ["Main Street Diner", "Blue Ribbon Cafe", "Grandstand Grill", "County Line Diner", "Corner Kitchen"],
		"gas_station": ["Fairway Fuel", "County Line Gas", "Hoosier Stop", "Corner Fuel & Food", "Crossroads Gas"]}
	var list: Array = words.get(kind, ["Shop"])
	var n: String = list[absi(hash([id, kind, sim.city_seed])) % list.size()]
	return n


func to_dict() -> Dictionary:
	var out := {}
	for id in venues:
		var v: Dictionary = venues[id]
		out[str(id)] = {"kind": v.kind, "leader": v.leader, "built": v.built, "why": v.why,
			"savings": snappedf(v.savings, 0.01), "profit": snappedf(v.profit, 0.01), "gate": snappedf(v.gate, 0.01),
			"outside": v.outside, "outside_last": v.outside_last, "visitors": v.visitors,
			"visitors_last": v.visitors_last, "crowd": v.crowd}
	return {"venues": out, "month": _month}


func from_dict(d: Dictionary) -> void:
	venues.clear()
	for k in d.get("venues", {}):
		var e: Dictionary = d.venues[k]
		var l: Dictionary = e.get("leader", {})
		var crowd: Dictionary = e.get("crowd", {})
		if not crowd.is_empty():
			crowd = {"name": str(crowd.name), "visitors": int(crowd.visitors), "outside": int(crowd.outside),
				"cars": int(crowd.cars), "start": int(crowd.start), "end": int(crowd.end)}
		venues[int(k)] = {"kind": str(e.kind),
			"leader": {"name": str(l.get("name", "Pat Lee")), "edu": float(l.get("edu", 0.5)),
				"caution": float(l.get("caution", 0.5)), "ambition": float(l.get("ambition", 0.5))},
			"built": Array(e.get("built", [])).map(func(x): return str(x)), "why": str(e.get("why", "")),
			"savings": float(e.get("savings", 0.0)), "profit": float(e.get("profit", 0.0)),
			"gate": float(e.get("gate", 0.0)), "outside": float(e.get("outside", 0.0)),
			"outside_last": float(e.get("outside_last", 0.0)), "visitors": float(e.get("visitors", 0.0)),
			"visitors_last": float(e.get("visitors_last", 0.0)), "crowd": crowd}
	_month = int(d.get("month", -1))
