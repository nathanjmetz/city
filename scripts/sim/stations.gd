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
## nothing the player built is taken.

## The chief looks at the fund and the town once a game day (a month).
const DECIDE_EVERY := 1440
const TREE_OF := {Services.Kind.FIRE: "fire", Services.Kind.POLICE: "police", Services.Kind.CLINIC: "clinic",
	Services.Kind.SCHOOL: "school"}

var depts := {}  # service id -> {built: [ids, in the order built], fund, why}


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
			depts[id] = {"built": [], "fund": 0.0, "why": ""}
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
	for n in open(int(b.kind), d.built, facts):
		if float(n.cost) * Balance.STATION_BOND_DOWN > float(d.fund):
			continue  # saving up for it
		var grow := float(n.get("grow", 0.0))
		if grow > 0.0 and not _grow(sim, id, grow):
			d.why = "No free land behind the station for the %s." % str(n.name).to_lower()
			continue
		d.fund = float(d.fund) - float(n.cost)
		d.built.append(n.id)
		d.why = "The chief added the %s: %s." % [str(n.name).to_lower(), n.note]
		sim.buildings_changed.emit()
		return grow > 0.0
	return false


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
	var size := Services.size_of(b) + Vector2(0.0, metres)
	var pos: Vector3 = b.pos - b.dir * metres * 0.5
	if BusNet.land_free(sim, id, pos, b.dir, size) != "":
		return false
	b.pos = pos
	b.size = size
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
		out[str(id)] = {"built": depts[id].built, "fund": depts[id].fund, "why": depts[id].why}
	return out


func from_dict(sim: CitySim, d: Dictionary) -> void:
	depts = {}
	for k in d:
		depts[int(k)] = {"built": Array(d[k].get("built", [])), "fund": float(d[k].get("fund", 0.0)),
			"why": str(d[k].get("why", ""))}
	_boost(sim)
