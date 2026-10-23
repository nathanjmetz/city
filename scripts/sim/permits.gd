class_name Permits
extends RefCounted
## Permit requests (Brawn): hubs run themselves, but they never wreck what
## the player built. A hub builds freely on empty land it owns. A big move
## (laying track through town, crossing the player's roads, or removing
## something the player built) goes to the player as a request instead. The
## bell up top lists them; the player approves, denies, or edits the route,
## and the hub's leader re-costs the edit and goes ahead if it can afford it.
##
## It never nags: only MAX_OPEN requests are open at once, one per hub, and
## a request nobody answers is shelved after SHELVE_AFTER, never forced.
##
## How a hub uses it (any hub: rail first, then buses and others):
##   var hits := sim.permits.check(sim, route, width)
##   if Permits.needs(hits):
##       sim.permits.file(sim, {"hub": "rail", "hub_id": id, "leader": name,
##           "title": "New track to the grain elevator", "why": "...",
##           "route": [[x, z], ...], "width": 8.0, "per_m": 900, "base": 0, "budget": 400000})
##   ...each decision step after that:
##   for req in sim.permits.approved("rail", id):
##       (build along req.route, which the player may have changed)
##       sim.permits.done(req.id)
## It works both ways: the player can click any hub and guide its leader
## (CitySim.apply {"type": "guide", "hub", "hub_id", "stance", "grant"}):
##   stance "grow"  - buy up land around you and grow (e.g. toward an
##                    international airport), within your own budget;
##   stance "steady"- your own judgment (the default);
##   stance "hold"  - hold off: no new land, no new requests.
##   grant (metres) - permits are pre-approved within this far of the hub,
##                    so requests there go straight through.
## A hub reads sim.permits.guidance("airport", id) in its decide step and
## acts on it over time with its own money and judgment. For "grant" to
## work it tells permits where it is: sim.permits.locators["airport"] =
## func(sim, id) -> Vector2.
## Land-use requests (Brawn: a city's identity can shift, say financial
## leaders buying up farmland, but only with the player's say-so): file
## with "area": [[x, z], ...] (an outline) instead of "route", plus
## "change": "Farmland to offices" and "per_m2". The player can drag every
## corner of the boundary; the leader re-prices the land it now covers.
## Check land with check(sim, outline, 0.0, true).
## A hub can price routes its own way: sim.permits.costers["rail"] =
## func(sim, req, route, hits) -> int. Filing and carrying out happen inside
## tick(), and the player's answers come through CitySim.apply, so every
## copy of the city (multiplayer) agrees.

signal changed

enum State { OPEN, APPROVED, DENIED, SHELVED, DONE, WITHDRAWN }

## Requests open at once, across the whole town.
const MAX_OPEN := 3
## An unanswered request is shelved after this long (game ticks: 7 days).
const SHELVE_AFTER := 7 * 24 * 60
## A hub waits this long after a "no" before asking again (30 days).
const DENY_WAIT := 30 * 24 * 60
## ...and this long after a request of theirs was shelved (10 days).
const SHELF_WAIT := 10 * 24 * 60
## Old answered requests kept for the record (and the panel's history).
const KEEP_CLOSED := 20
## Default extra cost per road crossed (a real at-grade rail crossing with
## gates and signals runs about $250k to $500k in the US).
const PER_CROSSING := 300000
## How often open requests are checked for shelving (ticks).
const CHECK_EVERY := 60
## What the player can tell a leader.
const STANCES := ["grow", "steady", "hold"]
## Pre-approved areas the player can grant around a hub (metres; 0 = none).
const GRANTS := [0, 250, 500, 1000]

var requests := {}   # id -> request Dictionary
var next_id := 1
## The tick each hub may ask again: "kind:id" -> tick.
var wait_until := {}
## Hub kind -> Callable(sim, req, route, hits) -> int. Set in code, never saved.
var costers := {}
## The player's word to each leader: "kind:id" -> {"stance", "grant", "set"}.
var guided := {}
## Hub kind -> Callable(sim, id) -> Vector2, where a hub stands. Set in code.
var locators := {}


## Files a request for a hub. Returns its id, or -1 if the hub must wait
## (it already has one open, the town has MAX_OPEN open, or it was told no
## or shelved lately). Call it only from tick-time code (a hub's decide).
func file(sim, plan: Dictionary) -> int:
	var hub := str(plan.get("hub", ""))
	var hub_id := int(plan.get("hub_id", 0))
	if not can_file(sim, hub, hub_id):
		return -1
	var shape := "area" if plan.has("area") else ("deal" if plan.has("deal") else "route")
	var route := _route(plan.get("area", plan.get("route", [])))
	if route.size() < {"area": 3, "route": 2, "deal": 0}[shape]:
		return -1
	var req := {
		"id": next_id,
		"hub": hub,
		"hub_id": hub_id,
		"leader": str(plan.get("leader", "")),
		"title": str(plan.get("title", "")),
		"why": str(plan.get("why", "")),
		"shape": shape,
		"change": str(plan.get("change", "")),
		"route": route,
		"asked": route.duplicate(true),
		"width": float(plan.get("width", 8.0)),
		"per_m": int(plan.get("per_m", 0)),
		"per_m2": int(plan.get("per_m2", 0)),
		"base": int(plan.get("base", 0)),
		"budget": int(plan.get("budget", 0)),
		"cost": 0,
		"hits": {},
		"state": State.OPEN,
		"filed": int(sim.tick_count),
		"decided": -1,
		"edits": 0,
		"note": "",
	}
	if shape == "deal":
		# A service deal with a neighbor town (Interlocal): {kind, fee, other}.
		req.deal = plan.deal
	_price(sim, req, route)
	next_id += 1
	requests[req.id] = req
	if _granted(sim, req) and (req.budget <= 0 or req.cost <= req.budget):
		# Inside land the player pre-approved: no need to ask.
		req.state = State.APPROVED
		req.decided = req.filed
		req.note = "Pre-approved by you."
	changed.emit()
	return req.id


## What the player told this hub's leader (stance "steady" if nothing).
func guidance(hub: String, hub_id: int) -> Dictionary:
	return guided.get(_key(hub, hub_id), {"stance": "steady", "grant": 0, "set": -1})


## The player's guidance, from CitySim.apply.
func guide(sim, cmd: Dictionary) -> bool:
	var stance := str(cmd.get("stance", "steady"))
	var grant := int(cmd.get("grant", 0))
	if not stance in STANCES or grant < 0:
		return false
	var key := _key(str(cmd.get("hub", "")), int(cmd.get("hub_id", 0)))
	if stance == "steady" and grant == 0:
		guided.erase(key)
	else:
		guided[key] = {"stance": stance, "grant": grant, "set": int(sim.tick_count)}
	if stance == "hold":
		# Holding off withdraws what they were still asking for.
		for id in _ids():
			var r: Dictionary = requests[id]
			if _key(r.hub, r.hub_id) == key and r.state in [State.OPEN, State.SHELVED]:
				r.state = State.WITHDRAWN
				r.decided = int(sim.tick_count)
		_trim()
	changed.emit()
	return true


## True when a request's whole route lies in land pre-approved for its hub.
func _granted(sim, req: Dictionary) -> bool:
	var g := guidance(req.hub, req.hub_id)
	if int(g.grant) <= 0 or not locators.has(req.hub) or not (locators[req.hub] as Callable).is_valid():
		return false
	var at: Vector2 = locators[req.hub].call(sim, req.hub_id)
	for p in req.route:
		if Vector2(p[0], p[1]).distance_to(at) > float(g.grant):
			return false
	return true


## True if this hub may file a request now.
func can_file(sim, hub: String, hub_id: int) -> bool:
	if guidance(hub, hub_id).stance == "hold":
		return false
	if int(sim.tick_count) < int(wait_until.get(_key(hub, hub_id), -1)):
		return false
	var open := 0
	for id in requests:
		var r: Dictionary = requests[id]
		if r.state == State.OPEN:
			open += 1
			if r.hub == hub and r.hub_id == hub_id:
				return false
	return open < MAX_OPEN


## What a route would run through: {"roads": [segment ids], "buildings":
## [{"what", "id", "name"}]}. Anything in it is the player's, so a request
## with any hit needs a permit (see needs()).
func check(sim, route: Array, width: float, area := false) -> Dictionary:
	var line := PackedVector2Array()
	for p in route:
		line.append(Vector2(float(p[0]), float(p[1])))
	var out := {"roads": [], "buildings": []}
	if line.size() < (3 if area else 2):
		return out
	var corr := [{"bounds": RoadWins._bounds(line).grow(width * 0.5),
		"polys": [line] if area else Geometry2D.offset_polyline(line, width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)}]
	var ids: Array = sim.network.segments.keys()
	ids.sort()
	for seg in ids:
		var road := PackedVector2Array()
		for p in sim.network.sample_segment(seg):
			road.append(Vector2(p.x, p.z))
		var half := RoadStyle.half_width(sim.network.segments[seg].type)
		if RoadWins.hits(corr, Geometry2D.offset_polyline(road, half, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)[0]):
			out.roads.append(seg)
	ids = sim.services.buildings.keys()
	ids.sort()
	for id in ids:
		if RoadWins.hits(corr, sim.services.footprint(id)):
			out.buildings.append({"what": "service", "id": id,
				"name": str(Services.KINDS[sim.services.buildings[id].kind].name).to_lower()})
	ids = sim.farms.farms.keys()
	ids.sort()
	for id in ids:
		if RoadWins.hits(corr, sim.farms._yard(sim.farms.farms[id])):
			out.buildings.append({"what": "farm", "id": id, "name": "farmhouse"})
	ids = sim.industry.sites.keys()
	ids.sort()
	for id in ids:
		if RoadWins.hits(corr, sim.industry._yard(sim.industry.sites[id])):
			out.buildings.append({"what": "industry", "id": id,
				"name": str(Industry.KINDS.get(sim.industry.sites[id].kind, {}).get("name", "company")).to_lower()})
	ids = sim.buildings.keys()
	ids.sort()
	for key in ids:
		if sim.lots.has(key) and RoadWins.hits(corr, sim.lots[key].corners):
			out.buildings.append({"what": "lot", "id": key,
				"name": ["building", "home", "shop", "workplace"][clampi(int(sim.buildings[key].zone), 0, 3)]})
	return out


## True when a route touches anything the player built.
static func needs(hits: Dictionary) -> bool:
	return not hits.get("roads", []).is_empty() or not hits.get("buildings", []).is_empty()


## What the hub would pay for this route: its own pricing if it has one,
## otherwise base + per_m for every metre + PER_CROSSING per road crossed,
## or for land, base + per_m2 for every square metre.
func cost_of(sim, req: Dictionary, route: Array, hits: Dictionary) -> int:
	if req.shape == "deal":
		return 0  # a service deal builds nothing; its monthly fee is on the card
	if costers.has(req.hub) and (costers[req.hub] as Callable).is_valid():
		return int(costers[req.hub].call(sim, req, route, hits))
	if req.shape == "area":
		return int(req.base) + roundi(area_of(route) * float(req.per_m2))
	return int(req.base) + roundi(length(route) * float(req.per_m)) + hits.roads.size() * PER_CROSSING


## Square metres inside an outline.
static func area_of(outline: Array) -> float:
	var poly := PackedVector2Array()
	for p in outline:
		poly.append(Vector2(p[0], p[1]))
	return RoadWins.area(poly) if poly.size() >= 3 else 0.0


static func length(route: Array) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += Vector2(route[i][0], route[i][1]).distance_to(Vector2(route[i - 1][0], route[i - 1][1]))
	return total


## A player's answer, from CitySim.apply: {"type": "permit", "id", "answer":
## "approve" | "deny" | "edit", "route" (for edit)}. Shelved requests can
## still be answered.
func answer(sim, cmd: Dictionary) -> bool:
	var req: Dictionary = requests.get(int(cmd.get("id", -1)), {})
	if req.is_empty() or not req.state in [State.OPEN, State.SHELVED]:
		return false
	match str(cmd.get("answer", "")):
		"approve":
			req.state = State.APPROVED
			req.note = ""
		"deny":
			req.state = State.DENIED
			wait_until[_key(req.hub, req.hub_id)] = int(sim.tick_count) + DENY_WAIT
		"edit":
			if req.shape == "deal":
				return false
			var route := _route(cmd.get("route", []))
			if route.size() < (3 if req.shape == "area" else 2):
				return false
			if req.shape == "route":
				# The ends are where the hub starts and where it's going.
				route[0] = req.route[0]
				route[-1] = req.route[-1]
			req.edits += 1
			req.route = route
			_price(sim, req, route)
			if req.budget > 0 and req.cost > req.budget:
				# Too dear: it comes back to the player with the numbers.
				req.state = State.OPEN
				req.filed = int(sim.tick_count)
				req.note = "That way costs $%s. We can spend $%s. Could you find us a cheaper way?" % [
					CitySim.money_text(req.cost), CitySim.money_text(req.budget)]
				changed.emit()
				return true
			req.state = State.APPROVED
			req.note = "Thanks. We'll go your way."
		_:
			return false
	req.decided = int(sim.tick_count)
	_trim()
	changed.emit()
	return true


## Approved requests a hub hasn't carried out yet, oldest first.
func approved(hub: String, hub_id: int) -> Array:
	var out := []
	for id in _ids():
		var r: Dictionary = requests[id]
		if r.state == State.APPROVED and r.hub == hub and r.hub_id == hub_id:
			out.append(r)
	return out


## The hub built it.
func done(id: int) -> void:
	if requests.has(id):
		requests[id].state = State.DONE
		_trim()
		changed.emit()


## The hub no longer wants it (it closed, or found another way).
func withdraw(id: int) -> void:
	if requests.has(id) and requests[id].state in [State.OPEN, State.SHELVED, State.APPROVED]:
		requests[id].state = State.WITHDRAWN
		_trim()
		changed.emit()


func state_of(id: int) -> int:
	return int(requests[id].state) if requests.has(id) else -1


## Requests in a state, oldest first.
func listed(state: int) -> Array:
	return _ids().filter(func(id): return requests[id].state == state).map(func(id): return requests[id])


## Shelves requests nobody answered. CitySim calls this every tick.
func tick(sim) -> void:
	if int(sim.tick_count) % CHECK_EVERY != 0:
		return
	var any := false
	for id in _ids():
		var r: Dictionary = requests[id]
		if r.state == State.OPEN and int(sim.tick_count) - int(r.filed) >= SHELVE_AFTER:
			r.state = State.SHELVED
			r.decided = int(sim.tick_count)
			wait_until[_key(r.hub, r.hub_id)] = int(sim.tick_count) + SHELF_WAIT
			any = true
	if any:
		changed.emit()


## Re-prices a request for a route and records what it runs through.
func _price(sim, req: Dictionary, route: Array) -> void:
	var hits := check(sim, route, req.width, req.shape == "area")
	req.hits = hits
	req.cost = cost_of(sim, req, route, hits)


## Keeps only the latest KEEP_CLOSED answered requests.
func _trim() -> void:
	var closed := _ids().filter(func(id): return requests[id].state in [State.DENIED, State.DONE, State.WITHDRAWN])
	while closed.size() > KEEP_CLOSED:
		requests.erase(closed.pop_front())


func _ids() -> Array:
	var ids := requests.keys()
	ids.sort()
	return ids


static func _key(hub: String, hub_id: int) -> String:
	return "%s:%d" % [hub, hub_id]


## A route as [[x, z], ...] floats, to the centimetre, so saves and
## every copy of the city match exactly.
static func _route(pts: Array) -> Array:
	var out := []
	for p in pts:
		var v: Vector2 = Vector2(p.x, p.z) if p is Vector3 else (p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
		out.append([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
	return out


func to_dict() -> Dictionary:
	var list := []
	for id in _ids():
		list.append(requests[id])
	return {"next": next_id, "requests": list, "wait": wait_until, "guided": guided}


func from_dict(d: Dictionary) -> void:
	requests.clear()
	wait_until.clear()
	guided.clear()
	next_id = int(d.get("next", 1))
	for r in d.get("requests", []):
		var hits: Dictionary = r.get("hits", {})
		var req := {
			"id": int(r.id), "hub": str(r.hub), "hub_id": int(r.hub_id), "leader": str(r.leader),
			"title": str(r.title), "why": str(r.why), "route": _route(r.route),
			"shape": str(r.get("shape", "route")), "change": str(r.get("change", "")),
			"per_m2": int(r.get("per_m2", 0)),
			"asked": _route(r.get("asked", r.route)), "width": float(r.width), "per_m": int(r.per_m),
			"base": int(r.get("base", 0)), "budget": int(r.budget), "cost": int(r.cost),
			"hits": {"roads": hits.get("roads", []).map(func(s): return int(s)),
				"buildings": hits.get("buildings", []).map(func(b): return {"what": str(b.what),
					"id": str(b.id) if str(b.what) == "lot" else int(b.id), "name": str(b.name)})},
			"state": int(r.state), "filed": int(r.filed), "decided": int(r.decided),
			"edits": int(r.edits), "note": str(r.get("note", "")),
		}
		if not r.get("deal", {}).is_empty():
			var dl: Dictionary = r.deal
			req.deal = {"kind": str(dl.get("kind", "")), "fee": int(dl.get("fee", 0)), "other": str(dl.get("other", ""))}
			if dl.get("pays", false):
				req.deal.pays = true
		requests[req.id] = req
	for k in d.get("wait", {}):
		wait_until[str(k)] = int(d.wait[k])
	for k in d.get("guided", {}):
		var g: Dictionary = d.guided[k]
		guided[str(k)] = {"stance": str(g.stance), "grant": int(g.grant), "set": int(g.set)}
	changed.emit()
