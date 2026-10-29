class_name Stations
extends RefCounted
## Fire and police stations grow with their town (Brawn 2026-10-29: "when a
## building or hub expands, it needs a lot of options"). A small town's
## two-bay firehouse and marshal's office get what real departments add as
## their towns grow: a drill tower, a crew's living quarters, a raised bay
## for a ladder truck, a sally port, an evidence garage, a 911 dispatch
## center. The chief picks from Balance.STATION_TREES as the town passes
## each need, paying from the department's cumulative fund (Indiana lets a
## town levy a cumulative fire fund and a cumulative capital development
## fund for exactly this, IC 36-8-14 and IC 36-9-14.5: a separate property
## tax, so the city's budget doesn't pay for it). A big piece is bonded,
## as towns do: with part of its cost in the fund, the rest is borrowed and
## the levy pays it back (the fund runs below zero until then). A piece that needs land
## grows the station's lot back from the street, onto free land only:
## nothing the player built is taken. When homes or shops stand there, the
## chief asks the player through the permits bell to buy them out, as a
## real town buys the lots next to its station; a yes clears them, a no
## leaves the station as it is (Permits waits before it asks again).

## The chief looks at the fund and the town once a game day (a month).
const DECIDE_EVERY := 1440
const TREE_OF := {Services.Kind.FIRE: "fire", Services.Kind.POLICE: "police", Services.Kind.CLINIC: "clinic",
	Services.Kind.SCHOOL: "school", Services.Kind.NURSING_HOME: "nursing", Services.Kind.DAYCARE: "daycare"}

## The permits bell's name for these hubs.
const PERMIT_KIND := "station"

## service id -> {built: [ids, in the order built], fund, why, ask}. `ask`
## is a land request out to the player: {req, node, pos: [x, z], size: [w, d]}.
var depts := {}


static func tree(kind: int) -> Array:
	return Balance.STATION_TREES.get(TREE_OF.get(kind, ""), [])


static func node(kind: int, id: String) -> Dictionary:
	for n in tree(kind):
		if n.id == id:
			return n
	return {}


## Steps the departments. Returns the ids of stations whose lots grew, so
## the city can clear zoning under them.
func tick(sim: CitySim) -> Array:
	if not sim.permits.locators.has(PERMIT_KIND):
		sim.permits.locators[PERMIT_KIND] = func(s: CitySim, id: int) -> Vector2:
			var b: Dictionary = s.services.buildings.get(id, {})
			return Vector2(b.pos.x, b.pos.z) if not b.is_empty() else Vector2.ZERO
	_sync(sim)
	if sim.tick_count % DECIDE_EVERY != 0 or depts.is_empty():
		return []
	var grown := []
	var ids := depts.keys()
	ids.sort()
	var facts := _facts(sim)
	for id in ids:
		if _decide(sim, id, facts):
			grown.append(id)
	_boost(sim)
	return grown


## Departments come and go with their stations.
func _sync(sim: CitySim) -> void:
	for id in sim.services.buildings:
		if TREE_OF.has(int(sim.services.buildings[id].kind)) and not depts.has(id):
			depts[id] = {"built": [], "fund": 0.0, "why": "", "ask": {}}
	for id in depts.keys():
		if not sim.services.buildings.has(id) or not TREE_OF.has(int(sim.services.buildings[id].kind)):
			depts.erase(id)


## What the town has that a node can need.
static func _facts(sim: CitySim) -> Dictionary:
	var tall := 0
	for key in sim.buildings:
		if BuildingTypes.storeys(sim.buildings[key]) >= 3:
			tall += 1
	return {"population": int(sim.stats.population), "tall": tall,
		"city": 1 if sim.charter.reached.has("city") else 0}


## A day's levy goes into the fund; then the chief builds the next piece
## the town needs and the fund covers. True if the lot grew.
func _decide(sim: CitySim, id: int, facts: Dictionary) -> bool:
	var d: Dictionary = depts[id]
	var b: Dictionary = sim.services.buildings[id]
	d.fund = roundf(float(d.fund) + float(facts.population)
		* float(Balance.STATION_LEVY_OF.get(TREE_OF[int(b.kind)], Balance.STATION_LEVY_PER_PERSON)))
	if not d.ask.is_empty():
		return _answer(sim, id)
	for n in open(int(b.kind), d.built, facts):
		if float(n.cost) * Balance.STATION_BOND_DOWN > float(d.fund):
			continue  # saving up for it
		var grow := float(n.get("grow", 0.0))
		if grow > 0.0 and not _grow(sim, id, grow):
			if _ask(sim, id, n):
				return false
			d.why = "No free land behind the station for the %s." % str(n.name).to_lower()
			continue
		_add(sim, id, n, 0.0)
		return grow > 0.0
	return false


func _add(sim: CitySim, id: int, n: Dictionary, land: float) -> void:
	var d: Dictionary = depts[id]
	d.fund = float(d.fund) - float(n.cost) - land
	d.built.append(n.id)
	d.why = "The chief added the %s: %s." % [str(n.name).to_lower(), n.note]
	sim.buildings_changed.emit()


## The lot `metres` deeper: [pos, size].
static func _deeper(b: Dictionary, metres: float) -> Array:
	return [b.pos - b.dir * metres * 0.5, Services.size_of(b) + Vector2(0.0, metres)]


## Only homes or shops stand behind the station: ask the player to let the
## department buy them (true if a request went out).
func _ask(sim: CitySim, id: int, n: Dictionary) -> bool:
	var b: Dictionary = sim.services.buildings[id]
	var to := _deeper(b, float(n.grow))
	if BusNet.land_free(sim, id, to[0], b.dir, to[1]) != "built" or not sim.permits.can_file(sim, PERMIT_KIND, id):
		return false
	var area := []
	for p in Services.corners(int(b.kind), to[0], b.dir, to[1]):
		area.append([p.x, p.z])
	var homes := 0
	for h in sim.permits.check(sim, area, 0.0, true).get("buildings", []):
		if h.what == "lot":
			homes += 1
	var kind_name := str(Services.KINDS[int(b.kind)].name).to_lower()
	var req: int = sim.permits.file(sim, {"hub": PERMIT_KIND, "hub_id": id, "leader": _head(int(b.kind)),
		"title": "Buy %d building%s behind the %s" % [homes, "" if homes == 1 else "s", kind_name],
		"why": "The %s needs room for the %s: %s." % [kind_name, str(n.name).to_lower(), n.note],
		"area": area, "change": "Homes and shops to %s" % kind_name,
		"per_m2": roundi(Balance.STATION_LAND_PER_M2), "base": int(n.cost), "budget": roundi(maxf(float(depts[id].fund), 0.0))})
	if req == -1:
		return false
	depts[id].ask = {"req": req, "node": n.id, "pos": [to[0].x, to[0].z], "size": [to[1].x, to[1].y]}
	depts[id].why = "Asked to buy the land behind the station for the %s." % str(n.name).to_lower()
	return true


## The player answered (or not yet): on a yes, the buildings on the land
## they agreed to are bought and cleared and the piece goes up there.
func _answer(sim: CitySim, id: int) -> bool:
	var d: Dictionary = depts[id]
	var state: int = sim.permits.state_of(int(d.ask.req))
	if state == Permits.State.OPEN:
		return false
	var n := node(int(sim.services.buildings[id].kind), str(d.ask.node))
	if state != Permits.State.APPROVED or n.is_empty() or n.id in d.built:
		d.why = "Was told no on the land behind the station." if state == Permits.State.DENIED else d.why
		d.ask = {}
		return false
	var req: Dictionary = sim.permits.requests[int(d.ask.req)]
	var outline := PackedVector2Array()
	for p in req.route:
		outline.append(Vector2(float(p[0]), float(p[1])))
	for key in sim.buildings.keys():
		if sim.parcel_under(key, outline):
			sim.buildings.erase(key)
	var b: Dictionary = sim.services.buildings[id]
	var pos := Vector3(float(d.ask.pos[0]), 0.0, float(d.ask.pos[1]))
	var size := Vector2(float(d.ask.size[0]), float(d.ask.size[1]))
	sim.permits.done(int(d.ask.req))
	d.ask = {}
	if BusNet.land_free(sim, id, pos, b.dir, size) != "":
		d.why = "The land agreed to wasn't enough for the %s." % str(n.name).to_lower()
		return false
	b.pos = pos
	b.size = size
	_add(sim, id, n, float(n.grow) * size.x * Balance.STATION_LAND_PER_M2)
	return true


## Who runs it, for the bell.
static func _head(kind: int) -> String:
	match kind:
		Services.Kind.FIRE: return "The fire chief"
		Services.Kind.POLICE: return "The police chief"
		Services.Kind.SCHOOL: return "The principal"
		Services.Kind.NURSING_HOME: return "The administrator"
		Services.Kind.DAYCARE: return "The director"
	return "The clinic manager"


## Nodes whose needs the town meets, in tree order.
static func open(kind: int, built: Array, facts: Dictionary) -> Array:
	var out := []
	for n in tree(kind):
		if n.id in built:
			continue
		var ok := true
		for r in n.get("requires", []):
			ok = ok and r in built
		for k in n.get("needs", {}):
			ok = ok and int(facts.get(k, 0)) >= int(n.needs[k])
		if ok:
			out.append(n)
	return out


## Grows the lot `metres` further back from the street, if that land is
## free (an empty lot or open ground, never a home or shop).
static func _grow(sim: CitySim, id: int, metres: float) -> bool:
	var b: Dictionary = sim.services.buildings[id]
	var to := _deeper(b, metres)
	if BusNet.land_free(sim, id, to[0], b.dir, to[1]) != "":
		return false
	b.pos = to[0]
	b.size = to[1]
	return true


## Each station's reach, as its pieces lengthen it (Services.boosts).
func _boost(sim: CitySim) -> void:
	var boosts := {}
	for id in depts:
		if not sim.services.buildings.has(id):
			continue
		var m := 1.0
		for key in depts[id].built:
			m += float(node(int(sim.services.buildings[id].kind), key).get("effects", {}).get("reach*", 0.0))
		if m != 1.0:
			boosts[id] = m
	sim.services.boosts = boosts


func built_of(id: int) -> Array:
	return depts.get(id, {}).get("built", [])


## Rows for the station's panel: what it has added, its fund, its next step.
func rows(sim: CitySim, id: int) -> Array:
	if not depts.has(id):
		return []
	var d: Dictionary = depts[id]
	var kind := int(sim.services.buildings[id].kind)
	var names := []
	for key in d.built:
		names.append(node(kind, key).name)
	var out := [["Added", ", ".join(names) if not names.is_empty() else "Nothing yet"],
		["Cumulative fund", "$%s" % CitySim.money_text(roundi(float(d.fund)))]]
	var next := open(kind, d.built, _facts(sim))
	if float(d.fund) < 0.0:
		out[1] = ["Bond owed", "$%s" % CitySim.money_text(roundi(-float(d.fund)))]
	elif not next.is_empty():
		out.append(["Saving for", "%s ($%s)" % [next[0].name, CitySim.money_text(int(next[0].cost))]])
	if str(d.why) != "":
		out.append(["Latest", d.why])
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id in depts:
		out[str(id)] = {"built": depts[id].built, "fund": depts[id].fund, "why": depts[id].why, "ask": depts[id].ask}
	return out


func from_dict(sim: CitySim, d: Dictionary) -> void:
	depts = {}
	for k in d:
		depts[int(k)] = {"built": Array(d[k].get("built", [])), "fund": float(d[k].get("fund", 0.0)),
			"why": str(d[k].get("why", "")), "ask": Dictionary(d[k].get("ask", {}))}
	_boost(sim)
