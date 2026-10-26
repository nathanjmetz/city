class_name CivicHubs
extends RefCounted
## Landfills, recycling centres and cemeteries, the way Brawn asked
## (2026-10-22):
##   - They never fill up (Cities: Skylines players modded that away).
##   - A landfill makes the land around it worth less; a cemetery lifts it.
##   - A landfill can be replaced by recycling, and recycling upgraded twice.
##   - Each is a hub: placed once, it grows by itself into free land directly
##     next to what it has when it's busy (waste) or the town grows
##     (cemetery). It never opens a second site, and roads always win: a
##     road built through it cuts its land back to the piece by the gate.
##   - Boxed in by roads, it fills its block up to the sidewalk (Nathan,
##     2026-10-26: "when a hub with leader is "trapped" inside a road area,
##     it should nicely fill in that area up to the edge (sidewalk) so that
##     it looks like its using its space well."): edge pieces, see below.
## Every load of trash rides a real garbage truck (Traffic's dispatch): the
## truck leaves its hub, stops on streets where trash is out at the curb, and
## drives back to unload. Idle trucks wait inside the hub.
##
## Plain data stepped by the city, so every copy of the simulation agrees.

## Kinds the player can place, and what each upgrades to.
const KINDS := {
	"landfill": {"name": "Landfill", "icon": "landfill", "cell": 50.0, "waste": true, "next": "recycling_1"},
	"recycling_1": {"name": "Recycling drop-off yard", "icon": "recycling", "cell": 40.0, "waste": true, "next": "recycling_2"},
	"recycling_2": {"name": "Recycling sorting plant", "icon": "recycling", "cell": 40.0, "waste": true, "next": "recycling_3"},
	"recycling_3": {"name": "Materials recovery plant", "icon": "recycling", "cell": 40.0, "waste": true, "next": ""},
	"cemetery": {"name": "Cemetery", "icon": "cemetery", "cell": 30.0, "waste": false, "next": ""},
}
## Every hub starts on three pieces along the road and two deep, in its own
## frame (x along the road, y back from it).
const BASE := [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
## Gap kept between the hub's front and the road's edge.
const SETBACK := 2.0
## Ticks between garbage rounds (half a game hour), as for freight.
const EVERY := 30
const TICKS_PER_DAY := 24 * CitySim.TICKS_PER_HOUR
## Service tool kinds for the HUD (ServiceTool takes ints).
const TOOL_KINDS := {100: "landfill", 101: "recycling_1", 102: "cemetery"}
## A truck looks this far from its last stop for the next street.
const NEXT_STOP_REACH := 800.0
## An edge piece (a piece cut back to the road) is kept only if at least
## this share of a whole piece is left.
const EDGE_MIN := 0.25
## Edge outlines are kept in 1/64 m steps: exact in a JSON save, so a loaded
## copy of the city has exactly the same land.
const EDGE_SNAP := 1.0 / 64.0

## id -> {kind, pos (gate: middle of the front edge), dir (unit, toward the
## road), cell (metres), cells: [Vector2i], built (tick), scar (game days the
## old landfill still weighs on the area), received (lb brought in), want,
## short, quiet (growth counters), boxed (no room to grow), ver, edge}
## `edge` holds the hub's edge pieces: piece -> its outline cut back to the
## road, in the hub's own frame (x along the road, z back from it, metres;
## see edge_poly). They aren't in `cells`: they count as the hub's land
## (at, covers) but not as pieces for upkeep, trucks or the growth limit.
var hubs := {}
## Trash out at the curb on each street: road segment id -> lb.
var trash := {}
## Garbage trucks on the road: traffic trip id -> {hub, load, stops, seg (the
## street it's headed to, or -1 going home), at: [x, z] where it left from}.
var trips := {}
## Trucks that couldn't find a way and wait where they are for the next round.
var parked := []
## Streets a truck is already on its way to.
var claimed := {}
## Bumped whenever any hub's land or kind changes (the view redraws).
var version := 0
## The town's sliders: Funding sets upkeep and trucks, Growth how soon it
## takes more land (see Policies).
var policies: Policies
var _next_id := 1
var _net_dirty := true
var _hooked: RoadNetwork
var _vf_tick := -1
var _vf_sig := []
var _vf_cache := {}  # lot key -> [its spot, value_factor there]


static func is_waste(kind: String) -> bool:
	return KINDS.has(kind) and KINDS[kind].waste


static func right(h: Dictionary) -> Vector3:
	return Vector3(-h.dir.z, 0.0, h.dir.x)


static func cell_center(h: Dictionary, c: Vector2i) -> Vector3:
	var p: Vector3 = h.pos + right(h) * (c.x * h.cell) - h.dir * ((c.y + 0.5) * h.cell)
	return Vector3(p.x, 0.0, p.z)


static func cell_poly(h: Dictionary, c: Vector2i, shrink := 0.0) -> PackedVector2Array:
	var mid := cell_center(h, c)
	var half: float = h.cell * 0.5 - shrink
	var r: Vector3 = right(h) * half
	var b: Vector3 = -h.dir * half
	var out := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = mid + r * k.x + b * k.y
		out.append(Vector2(p.x, p.z))
	return out


## A point of the hub's own frame (x along the road, z back from it) on the
## ground (x, z), and back.
static func to_world(h: Dictionary, q: Vector2) -> Vector2:
	var p: Vector3 = h.pos + right(h) * q.x - h.dir * q.y
	return Vector2(p.x, p.z)


static func to_local(h: Dictionary, p: Vector2) -> Vector2:
	var d: Vector3 = Vector3(p.x, 0.0, p.y) - Vector3(h.pos.x, 0.0, h.pos.z)
	return Vector2(d.dot(right(h)), -d.dot(h.dir))


## Edge piece `c`'s outline on the ground (x, z).
static func edge_poly(h: Dictionary, c: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in h.get("edge", {}).get(c, PackedVector2Array()):
		out.append(to_world(h, q))
	return out


## All the ground a hub holds, as outlines (x, z): each whole piece, then
## each edge piece.
static func land_polys(h: Dictionary) -> Array:
	var out := []
	for c in h.cells:
		out.append(cell_poly(h, c))
	for c in h.get("edge", {}):
		out.append(edge_poly(h, c))
	return out


## Square metres of land a hub holds, edge pieces included.
static func land_area(h: Dictionary) -> float:
	var a: float = h.cells.size() * h.cell * h.cell
	for c in h.get("edge", {}):
		a += area(h.edge[c])
	return a


static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## Where a new hub goes when placed beside the road nearest `hit`: [gate,
## dir toward the road], or [] if no street is near.
static func site_near(network: RoadNetwork, hit: Vector3) -> Array:
	var near := RoadIndex.segment_near(network, hit, 120.0, 1.0)
	if near.is_empty() or not RoadStyle.TYPES[network.segments[near.seg].type].lots:
		return []
	var c := network.curve_of(near.seg)
	var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
	tan.y = 0.0
	tan = tan.normalized()
	var normal := Vector3(-tan.z, 0.0, tan.x)
	var p: Vector3 = near.point
	if (hit - p).dot(normal) < 0.0:
		normal = -normal
	var front := RoadStyle.right_of_way_half(network.segments[near.seg].type) + SETBACK
	return [Vector3(p.x, 0.0, p.z) + normal * front, -normal]


## A hub laid out at a gate, before it exists (for checks and the ghost).
static func draft(kind: String, pos: Vector3, dir: Vector3) -> Dictionary:
	return {"kind": kind, "pos": pos, "dir": dir, "cell": float(KINDS[kind].cell), "cells": BASE.duplicate()}


## Why a new hub can't go here, or "" if it can.
func site_problem(sim: CitySim, kind: String, pos: Vector3, dir: Vector3) -> String:
	var h := draft(kind, pos, dir)
	for c in BASE:
		var p := _cell_problem(sim, h, c, -1, false)
		if p != "":
			return p
	return ""


## Why a piece of land can't join hub `id` (-1 for a new one), or "". A new
## hub placed by the player clears zoning, as any building does; a hub
## growing by itself only takes land nobody is using.
func _cell_problem(sim: CitySim, h: Dictionary, c: Vector2i, id: int, auto: bool) -> String:
	var poly := cell_poly(h, c, 1.0)
	var mid := cell_center(h, c)
	var pts := [mid]
	for q in poly:
		pts.append(mid.lerp(Vector3(q.x, 0.0, q.y), 0.9))
	return _ground_problem(sim, poly, pts, id, auto)


## Why ground `poly` (x, z), looked at through the points `pts`, can't join
## hub `id`, or "". `road` false skips the road check (an edge piece is
## already cut back clear of the roads).
func _ground_problem(sim: CitySim, poly: PackedVector2Array, pts: Array, id: int, auto: bool,
		road := true) -> String:
	for p in pts:
		if not sim.land_ok(p):
			return "Can't build in the water or on a slope that steep."
	for p in pts:
		if sim.reserves.kind_at(p) != "":
			return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(p)]
	if road and Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for sid in sim.services.buildings:
		if not Geometry2D.intersect_polygons(poly, sim.services.footprint(sid)).is_empty():
			return "Overlaps the %s." % Services.KINDS[sim.services.buildings[sid].kind].name.to_lower()
	for p in pts:
		var other := at(p)
		if other != -1 and other != id:
			return "Overlaps the %s." % KINDS[hubs[other].kind].name.to_lower()
		var owner := Capital.owner_of(sim, p)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if sim.parks.covers(p):
			return "That ground is a park."
		if owner.begins_with("site:"):
			return "That ground belongs to a company."
		if sim.warehouses.covers(p):
			return "That ground belongs to a warehouse."
		if sim.education.covers(p):
			return "That ground is a campus."
		if id != -2 and sim.mail.covers(p):
			return "Overlaps the post office."
		if sim.telecom.covers(p):
			return "That ground belongs to the phone company."
		if sim.banks.covers(p):
			return "That ground is a bank."
	if auto:
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		for key in sim.lots_near(box):
			var lot: Dictionary = sim.lots[key]
			if not sim.buildings.has(key) and sim.zones.zone_at(lot.zone_pt) == ZoneMap.Zone.NONE:
				continue
			for p in [lot.pos, lot.front, lot.zone_pt]:
				if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
					return "Zoned or built on."
	return ""


func add(kind: String, pos: Vector3, dir: Vector3, tick: int) -> int:
	var id := _next_id
	_next_id += 1
	var h := draft(kind, pos, dir)
	h.merge({"since": tick, "scar": 0.0, "received": 0.0, "want": 0, "short": 0, "quiet": 0, "built": [],
		"boxed": false, "ver": 0, "edge": {}})
	hubs[id] = h
	version += 1
	return id


func remove(id: int) -> bool:
	if not hubs.erase(id):
		return false
	# Its trucks on the road finish their trip and park where they are.
	for i in range(parked.size() - 1, -1, -1):
		if parked[i].hub == id:
			parked.remove_at(i)
	version += 1
	return true


## Replaces a landfill with recycling, or steps recycling up a level. The
## old landfill keeps weighing on the area for a while as it's capped.
func upgrade(id: int) -> bool:
	if not hubs.has(id) or KINDS[hubs[id].kind].next == "":
		return false
	var h: Dictionary = hubs[id]
	if h.kind == "landfill":
		h.scar = Balance.LANDFILL_RECOVERY_DAYS
		h.capped = true
	h.kind = KINDS[h.kind].next
	_touch(h)
	return true


static func upgrade_cost(kind: String) -> int:
	var next: String = KINDS[kind].next
	return 0 if next == "" else int(Balance.WASTE_SITES[next].cost)


## The hub whose land holds this point, or -1.
func at(p: Vector3) -> int:
	for id in hubs:
		var h: Dictionary = hubs[id]
		var d: Vector3 = p - h.pos
		var c := Vector2i(roundi(d.dot(right(h)) / h.cell), floori(-d.dot(h.dir) / h.cell))
		if c in h.cells:
			return id
		var e: Dictionary = h.get("edge", {})
		if e.has(c) and Geometry2D.is_point_in_polygon(Vector2(d.dot(right(h)), -d.dot(h.dir)), e[c]):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1


## The middle of a hub's land and a radius around it (for the selection ring).
func extent(id: int) -> Array:
	var h: Dictionary = hubs[id]
	var mid := Vector3.ZERO
	for c in h.cells:
		mid += cell_center(h, c)
	mid /= maxf(h.cells.size(), 1.0)
	var r := 0.0
	for c in h.cells:
		r = maxf(r, cell_center(h, c).distance_to(mid) + h.cell * 0.71)
	for c in h.get("edge", {}):
		for q in edge_poly(h, c):
			r = maxf(r, Vector2(mid.x, mid.z).distance_to(q))
	return [mid, r]


func trucks(id: int) -> int:
	var h: Dictionary = hubs[id]
	if not is_waste(h.kind):
		return 0
	var n := int(Balance.HUB_TRUCKS[h.kind]) + extra_pieces(h) / 2
	return maxi(1, roundi(n * policy_funding(id, Balance.POLICY_EFFECT)))


## The Economy page area a hub belongs to.
static func area_of(kind: String) -> String:
	return "waste" if is_waste(kind) else "cemetery"


## A Balance list's value for hub `id`'s Funding step.
func policy_funding(id: int, list: Array) -> float:
	if policies == null or not hubs.has(id):
		return float(list[Policies.STANDARD])
	return policies.pick(list, "funding", area_of(hubs[id].kind), "hub:%d" % id)


## A Balance list's value for hub `id`'s Growth step.
func policy_growth(id: int, list: Array) -> float:
	if policies == null or not hubs.has(id):
		return float(list[Policies.STANDARD])
	return policies.pick(list, "growth", area_of(hubs[id].kind), "hub:%d" % id)


## Hub `id`'s monthly upkeep at its size and Funding, less what it sells.
func cost_of(id: int) -> int:
	var h: Dictionary = hubs[id]
	var s: Dictionary = Balance.WASTE_SITES[h.kind]
	var size := 1.0 + Balance.HUB_PIECE_UPKEEP * extra_pieces(h)
	var total := (float(s.upkeep) * policy_funding(id, Balance.POLICY_UPKEEP) - sales(h)) * size
	for node in tree(h):
		if node.id in h.built:
			total += float(node.get("upkeep", 0))
	return roundi(total)


func trucks_out(id: int) -> int:
	var n := 0
	for t in trips:
		if trips[t].hub == id:
			n += 1
	for p in parked:
		if p.hub == id:
			n += 1
	return n


static func extra_pieces(h: Dictionary) -> int:
	return maxi(0, h.cells.size() - BASE.size())


## What the hubs cost the city a month: upkeep (more for each piece grown),
## less what recycling sells.
func monthly_cost() -> int:
	var total := 0.0
	var ids := hubs.keys()
	ids.sort()
	for id in ids:
		total += cost_of(id)
	return roundi(total)


## What a recycling hub sells a month (before its size), with any extra
## sorting lines.
static func sales(h: Dictionary) -> float:
	return float(Balance.WASTE_SITES[h.kind].get("sales", 0)) * Agency.effect(h, tree(h), "sales*")


# --- Land value ---------------------------------------------------------------

## How much a place's land value is changed by the hubs around it: 1.0 is
## no change, 0.85 is 15% lower.
## `key` (a lot's) files the measurements for that spot, as _near_cell says.
func value_factor(p: Vector3, key := "") -> float:
	var total := 0.0
	for id in hubs:
		var h: Dictionary = hubs[id]
		var d: float = _near_cell(id, h, p, key) * h.cell if key != "" else distance(h, p)
		total += _effect(h.kind, d)
		# Its tree's built nodes that lift land, in tree order: [value, reach].
		for vr in _value_nodes(id, h):
			total += float(vr[0]) * maxf(0.0, 1.0 - d / float(vr[1]))
		if h.scar > 0.0:
			total += _effect("landfill", d) * h.scar / Balance.LANDFILL_RECOVERY_DAYS
	return clampf(1.0 + total, 0.5, 1.5)


static func _effect(kind: String, d: float) -> float:
	var s: Dictionary = Balance.WASTE_SITES[kind]
	if float(s.reach) <= 0.0 or d >= float(s.reach):
		return 0.0
	return float(s.value) * (1.0 - d / float(s.reach))


## distance(h, p) before the last * h.cell, kept for each lot (by key, with
## its spot: a lot that moves is measured again) a hub's land value is asked
## about: worked out again only when the hub moves or gives up land, and
## when it takes more, only the new pieces are measured (the nearest of all
## the pieces is the nearer of the old nearest and the new). The same
## numbers as distance(). Lots that are gone are dropped (_prune_near).
func _near_cell(id: int, h: Dictionary, p: Vector3, key: String) -> float:
	var e: Array = _near_cells.get(id, [])
	# (Checked again only after some hub was touched: version.)
	if e.is_empty() or e[5] != version:
		if e.is_empty() or e[0] != h.pos or e[1] != h.dir or e[2] != h.cell:
			e = [h.pos, h.dir, h.cell, (h.cells as Array).duplicate(), {}, version]
			_near_cells[id] = e
		elif e[3] != h.cells:
			var old: Array = e[3]
			var now: Array = h.cells
			# Pieces only added (at the end): each point folds them in when
			# it's next asked for. Otherwise every point is measured afresh.
			if not (now.size() > old.size() and now.slice(0, old.size()) == old):
				e[4] = {}
			e[3] = now.duplicate()
		e[5] = version
	var cells: Array = e[3]
	var got = e[4].get(key)
	if got == null or got[2] != p:
		got = [_cells_near(h, p, cells), cells.size(), p]
		e[4][key] = got
	elif int(got[1]) < cells.size():
		got[0] = minf(float(got[0]), _cells_near(h, p, cells.slice(int(got[1]))))
		got[1] = cells.size()
	return float(got[0])


## The built nodes of a hub's tree that lift land values, in tree order:
## [value, reach], kept until it builds something or its kind changes.
func _value_nodes(id: int, h: Dictionary) -> Array:
	var e: Array = _value_of.get(id, [])
	var built: Array = h.get("built", [])
	if not e.is_empty() and e[0] == h.kind and e[1] == h.get("capped", false) and e[2] == built:
		return e[3]
	var out := []
	for node in tree(h):
		var fx: Dictionary = node.get("effects", {})
		if node.id in h.built and fx.has("value"):
			out.append([float(fx.value), float(Balance.WASTE_SITES[h.kind].reach) + float(fx.reach)])
	_value_of[id] = [h.kind, h.get("capped", false), built.duplicate(), out]
	return out


var _value_of := {}  # hub id -> [kind, capped, built, _value_nodes]


## The cells part of distance(): the nearest of these cells, in cells.
static func _cells_near(h: Dictionary, p: Vector3, cells: Array) -> float:
	var d: Vector3 = p - h.pos
	var x: float = d.dot(right(h)) / h.cell
	var y: float = -d.dot(h.dir) / h.cell - 0.5
	var best := INF
	for c in cells:
		var ex := maxf(absf(x - c.x) - 0.5, 0.0)
		var ey := maxf(absf(y - c.y) - 0.5, 0.0)
		best = minf(best, Vector2(ex, ey).length())
	return best


var _near_cells := {}  # hub id -> [pos, dir, cell, cells, {lot key: [nearest, pieces looked at, spot]}, version]


## Drops what's kept for lots that are gone and hubs that are gone, once
## the keeping has grown well past the lots there are: memory stays in step
## with the town, not with every lot it ever had. (Dropped lots would be
## measured afresh, to the same numbers.)
func _prune_near(sim: CitySim) -> void:
	var most := sim.lots.size() * 2 + 256
	if _vf_cache.size() > most:
		for k in _vf_cache.keys():
			if not sim.lots.has(k):
				_vf_cache.erase(k)
	for id in _near_cells.keys():
		if not hubs.has(id):
			_near_cells.erase(id)
			continue
		var pts: Dictionary = _near_cells[id][4]
		if pts.size() > most:
			for k in pts.keys():
				if not sim.lots.has(k):
					pts.erase(k)


## Metres from a point to the nearest edge of a hub's land (0 inside).
static func distance(h: Dictionary, p: Vector3) -> float:
	var d: Vector3 = p - h.pos
	var x: float = d.dot(right(h)) / h.cell
	var y: float = -d.dot(h.dir) / h.cell - 0.5
	var best := INF
	for c in h.cells:
		var ex := maxf(absf(x - c.x) - 0.5, 0.0)
		var ey := maxf(absf(y - c.y) - 0.5, 0.0)
		best = minf(best, Vector2(ex, ey).length())
	return best * h.cell


## A lot's land value factor: the hubs nearby and any trash left piling up.
func lot_factor(sim: CitySim, key: String) -> float:
	if not sim.lots.has(key):
		return 1.0
	var lot: Dictionary = sim.lots[key]
	# The hubs' pull on a spot only changes with their land, what they've
	# built and an old landfill's scar, so each lot's is kept until then.
	if _vf_tick != sim.tick_count:
		_vf_tick = sim.tick_count
		var sig := [version]
		for id in hubs:
			sig.append([id, Array(hubs[id].get("built", [])).duplicate(), hubs[id].scar])
		if sig != _vf_sig:
			_vf_sig = sig
			_vf_cache.clear()
		_prune_near(sim)
	var row: Array = _vf_cache.get(key, [])
	if row.is_empty() or row[0] != lot.pos:
		row = [lot.pos, value_factor(lot.pos, key)]
		_vf_cache[key] = row
	var f: float = row[1]
	if trash.get(lot.seg, 0.0) >= Balance.GARBAGE_PILE_LB:
		f += Balance.GARBAGE_PILE_VALUE
	return f


## What's wrong with a lot's trash service, in plain words, or "".
func lot_problem(sim: CitySim, key: String) -> String:
	if not sim.lots.has(key) or trash.get(sim.lots[key].seg, 0.0) < Balance.GARBAGE_PILE_LB:
		return ""
	for id in hubs:
		if is_waste(hubs[id].kind):
			return "Trash is piling up at the curb: every garbage truck is busy."
	return "Trash is piling up at the curb. Build a landfill or recycling centre in Services."


# --- Stepping -------------------------------------------------------------------

func tick(sim: CitySim) -> void:
	if _hooked != sim.network:
		_hooked = sim.network
		sim.network.changed.connect(func(): _net_dirty = true)
	if _net_dirty:
		_net_dirty = false
		_prune(sim)
	if sim.tick_count % CitySim.TICKS_PER_HOUR == 0:
		for id in hubs:
			var h: Dictionary = hubs[id]
			if h.scar > 0.0:
				h.scar = maxf(0.0, h.scar - 1.0 / 24.0)
	if sim.simulate_traffic:
		for a in sim.traffic.arrivals:
			if trips.has(a.id):
				var t: Dictionary = trips[a.id]
				trips.erase(a.id)
				_arrive(sim, t)
		for f in sim.traffic.failed:
			if trips.has(f.id):
				var t: Dictionary = trips[f.id]
				trips.erase(f.id)
				_stuck(sim, t)
	if sim.tick_count % EVERY == Balance.ROUND_AT.hub_round:
		_pile_up(sim)
		if sim.simulate_traffic:
			_send_trucks(sim)
		else:
			_collect_offstage()
	if sim.tick_count % Balance.HUB_DECIDE_EVERY == Balance.ROUND_AT.hubs and not hubs.is_empty():
		_decide(sim)
	if sim.tick_count % TICKS_PER_DAY == 0:
		_trade(sim)
	if not sim.permits.locators.has("hub"):
		# Lets the player guide each hub's leader from its panel.
		sim.permits.locators["hub"] = func(s: CitySim, id: int) -> Vector2:
			var at: Vector3 = s.hubs.extent(id)[0] if s.hubs.hubs.has(id) else Vector3.ZERO
			return Vector2(at.x, at.z)


## Every home and business puts trash out at the curb of its street.
func _pile_up(sim: CitySim) -> void:
	var share := float(EVERY) / TICKS_PER_DAY
	# Each street's day of trash is added up first, then put out at once.
	var put := {}
	var lots: Dictionary = sim.lots
	var buildings: Dictionary = sim.buildings
	# (sim.utilities_ok, read straight from the services' rows.)
	var all_ok: bool = not sim.require_utilities
	var served: Dictionary = sim.services.served
	for key in sim.ledger().sorted:
		var lot = lots.get(key)
		if lot == null:
			continue
		var b: Dictionary = buildings[key]
		var lb := 0.0
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			lb = b.occ * Balance.GARBAGE_LB_PER_RESIDENT
		else:
			var s = served.get(key)
			if all_ok or (s != null and s.power and s.water):
				lb = b.cap * Balance.GARBAGE_LB_PER_JOB
		if lb <= 0.0:
			continue
		var seg: int = lot.seg
		put[seg] = put.get(seg, 0.0) + lb
	for seg in put:
		trash[seg] = _snap(minf(trash.get(seg, 0.0) + put[seg] * share, Balance.GARBAGE_PILE_LB * 4.0))
	for seg in trash.keys():
		if not sim.network.segments.has(seg):
			trash.erase(seg)
			claimed.erase(seg)


## With cars switched off (the balance harness), each waste site just takes
## in what its trucks could have carried.
func _collect_offstage() -> void:
	for id in _waste_ids():
		_collect_unseen(id, float(trucks(id)) * Balance.GARBAGE_STOP_LB * 2.0)


## Hub `id` takes in up to `room` lb from the fullest unclaimed streets
## without a truck on the road: the harness's cars-off mode, and a round
## whose truck found no route (so trash never piles up for a routing gap).
func _collect_unseen(id: int, room: float) -> void:
	var segs := trash.keys()
	segs.sort_custom(func(a, b): return trash[a] > trash[b] or trash[a] == trash[b] and a < b)
	for seg in segs:
		if room <= 0.0:
			break
		if claimed.has(seg):
			continue
		var take := minf(trash[seg], room)
		trash[seg] -= take
		room -= take
		hubs[id].received += take


func _waste_ids() -> Array:
	var ids := []
	for id in hubs:
		if is_waste(hubs[id].kind):
			ids.append(id)
	ids.sort()
	return ids


## Each waste site sends out one truck a round, to the fullest street it is
## nearest to, while it has trucks in.
func _send_trucks(sim: CitySim) -> void:
	# Trucks that got stuck try again to get home.
	var waiting := parked.duplicate()
	parked.clear()
	for p in waiting:
		if hubs.has(p.hub):
			_head_home(sim, p)
	var ids := _waste_ids()
	if ids.is_empty():
		return
	# A street is only claimed while a truck is really on its way to it (a
	# claim left by a lost trip would keep trucks off that street for good).
	claimed.clear()
	for t in trips.values():
		if int(t.seg) != -1:
			claimed[int(t.seg)] = true
	var curb := _curbs(sim)
	var best := {}  # hub id -> [lb, seg]
	var segs := trash.keys()
	segs.sort()
	for seg in segs:
		if trash[seg] < Balance.GARBAGE_STOP_LB or claimed.has(seg) or not curb.has(seg):
			continue
		var id := _nearest_hub(ids, curb[seg])
		if not best.has(id) or trash[seg] > best[id][0]:
			best[id] = [trash[seg], seg]
	for id in ids:
		if not best.has(id):
			continue
		var h: Dictionary = hubs[id]
		h.want += 1
		if trucks_out(id) >= trucks(id):
			h.short += 1
			continue
		var seg: int = best[id][1]
		if not _dispatch(sim, {"hub": id, "load": 0.0, "stops": 0, "seg": seg, "prev": -1, "at": _xz(h.pos)}, curb[seg]):
			_collect_unseen(id, Balance.GARBAGE_TRUCK_LB * 0.5)


## Where trash waits on each street: the curb in front of its first building.
## Kept until a building comes or goes or the lots change (the ledger's
## sorted keys are the buildings' keys sorted).
func _curbs(sim: CitySim) -> Dictionary:
	var ledger := sim.ledger()
	var key := [ledger.sig, sim.lots.size(), sim._lot_rev]
	if key == _curbs_key and is_same(sim.lots, _curbs_lots):
		return _curbs_out
	var out := {}
	var lots: Dictionary = sim.lots
	for k in ledger.sorted:
		if lots.has(k) and not out.has(lots[k].seg):
			out[lots[k].seg] = lots[k].front
	_curbs_key = key
	_curbs_lots = lots
	_curbs_out = out
	return out


var _curbs_key := []
var _curbs_lots := {}
var _curbs_out := {}


func _nearest_hub(ids: Array, p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for id in ids:
		var d: float = hubs[id].pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


## Sends truck `t` from where it is to a street (t.seg) or home (t.seg = -1).
func _dispatch(sim: CitySim, t: Dictionary, to: Vector3) -> bool:
	var h: Dictionary = hubs[t.hub]
	var from_ref := "hub:%d" % t.hub if t.stops == 0 else "trash:%d" % t.prev
	var to_ref := "hub:%d" % t.hub if t.seg == -1 else "trash:%d" % t.seg
	var good := "trash" if h.kind == "landfill" else "recyclables"
	var trip: int = sim.traffic.dispatch({"ref": from_ref, "pos": t.at}, {"ref": to_ref, "pos": _xz(to)},
		"garbage", {"good": good, "amount": int(t.load)})
	if trip == -1:
		return false
	trips[trip] = t
	if t.seg != -1:
		claimed[t.seg] = true
	return true


func _arrive(sim: CitySim, t: Dictionary) -> void:
	if not hubs.has(t.hub):
		return  # its hub was demolished: the truck stays parked where it is
	if t.seg == -1:
		hubs[t.hub].received += t.load
		return  # back inside, unloaded
	var seg: int = t.seg
	claimed.erase(seg)
	var take := minf(trash.get(seg, 0.0), Balance.GARBAGE_TRUCK_LB - t.load)
	if trash.has(seg):
		trash[seg] -= take
	t.load += take
	t.stops += 1
	t.prev = seg
	t.at = _xz(_curbs(sim).get(seg, Vector3(t.at[0], 0.0, t.at[1])))
	# A real route works the whole neighborhood: the truck also picks up the
	# streets close around this stop on its way through.
	var at := Vector3(t.at[0], 0.0, t.at[1])
	var around := _curbs(sim)
	var near := trash.keys()
	near.sort()
	for s in near:
		if t.load >= Balance.GARBAGE_TRUCK_LB:
			break
		if s == seg or claimed.has(s) or not around.has(s) or around[s].distance_to(at) > Balance.GARBAGE_SWEEP_REACH:
			continue
		var more := minf(trash[s], Balance.GARBAGE_TRUCK_LB - t.load)
		trash[s] -= more
		t.load += more
	# Room for more and stops left: the next street nearby with trash out.
	if t.load < Balance.GARBAGE_TRUCK_LB * 0.9 and t.stops < Balance.GARBAGE_STOPS_PER_RUN:
		var here := Vector3(t.at[0], 0.0, t.at[1])
		var curb := _curbs(sim)
		var next := -1
		var next_d := NEXT_STOP_REACH
		var segs := trash.keys()
		segs.sort()
		for s in segs:
			if trash[s] < Balance.GARBAGE_STOP_LB * 0.5 or claimed.has(s) or not curb.has(s):
				continue
			var d: float = curb[s].distance_to(here)
			if d < next_d:
				next_d = d
				next = s
		if next != -1:
			t.seg = next
			if _dispatch(sim, t, curb[next]):
				return
	_head_home(sim, t)


func _head_home(sim: CitySim, t: Dictionary) -> void:
	t.seg = -1
	if not _dispatch(sim, t, hubs[t.hub].pos):
		parked.append(t)


## A truck that found no way through tries for home from where it set out.
func _stuck(sim: CitySim, t: Dictionary) -> void:
	if t.seg != -1:
		claimed.erase(t.seg)
	if not hubs.has(t.hub):
		return
	if t.seg == -1:
		parked.append(t)  # try again next round
	else:
		_head_home(sim, t)


# --- Development tree --------------------------------------------------------------
# Brawn (2026-10-22): each hub has its own tree of buildings and options,
# unlocked by what the town can do and what is around it, in town and in
# neighboring towns. The hub's leader picks from it on its own, through the
# shared Agency API (Balance.HUB_TREES).

## landfill, recycling or cemetery.
static func family(kind: String) -> String:
	return "recycling" if kind.begins_with("recycling") else kind


## This hub's whole tree, built or not. A recycling centre on an old
## landfill keeps the landfill's tree too (a capped landfill still makes gas).
static func tree(h: Dictionary) -> Array:
	var out: Array = Balance.HUB_TREES[family(h.kind)].duplicate()
	if h.get("capped", false) and family(h.kind) != "landfill":
		out.append_array(Balance.HUB_TREES.landfill)
	return out


## What the site itself lacks for a node ("site_" needs), in plain words, or "".
func _site_problem(h: Dictionary, node: Dictionary) -> String:
	var n: Dictionary = node.get("needs", {})
	if n.has("site_pieces") and h.cells.size() < int(n.site_pieces):
		return "needs a bigger site (%d of %d pieces)" % [h.cells.size(), int(n.site_pieces)]
	if n.has("site_tons") and h.received / 2000.0 < float(n.site_tons):
		return "needs %s tons in the mound" % CitySim.money_text(int(n.site_tons))
	if n.has("site_level") and (family(h.kind) != "recycling" or int(str(h.kind).substr(10)) < int(n.site_level)):
		return "needs the %s" % KINDS["recycling_%d" % int(n.site_level)].name.to_lower()
	if n.has("site_forest"):
		var best := 0.0
		for c in h.cells:
			best = maxf(best, Resources.at(Resources.Kind.FOREST, cell_center(h, c)))
		if best < float(n.site_forest):
			return "needs woods next to it"
	return ""


## The tree as Agency sees it: nodes the site can't take yet are left out,
## and the "site_" needs of the rest (already met) are dropped.
func _open_tree(h: Dictionary) -> Array:
	var out := []
	for node in tree(h):
		if _site_problem(h, node) != "":
			continue
		var n := {}
		for k in node.get("needs", {}):
			if not str(k).begins_with("site_"):
				n[k] = node.needs[k]
		var copy: Dictionary = node.duplicate()
		copy.needs = n
		out.append(copy)
	return out


## The city funds a civic hub: its leader plans against a few years of upkeep.
static func funding(h: Dictionary) -> float:
	var site: Dictionary = Balance.WASTE_SITES[h.kind]
	return float(site.get("plan", site.upkeep)) * 12.0 * Balance.HUB_PLAN_YEARS


## Why this hub's leader can't build `id` yet, in a few plain words, or "".
func dev_problem(sim: CitySim, hub_id: int, id: String) -> String:
	if not hubs.has(hub_id):
		return "not for this site"
	var h: Dictionary = hubs[hub_id]
	var node := {}
	for nd in tree(h):
		if nd.id == id:
			node = nd
	if node.is_empty():
		return "not for this site"
	if id in h.built:
		return "built"
	for r in node.get("requires", []):
		if not r in h.built:
			for nd in tree(h):
				if nd.id == r:
					return "needs the %s first" % str(nd.name).to_lower()
	var site := _site_problem(h, node)
	if site != "":
		return site
	var n: Dictionary = node.get("needs", {})
	for k in n:
		if str(k).begins_with("site_") or Agency.holds(sim, h, h.pos, funding(h), k, n[k]):
			continue
		match str(k):
			"local:farm": return "needs a farm nearby to buy it"
			"local:metal": return "needs a metal works nearby"
			"education": return "needs schools for trained workers"
			"population": return "needs %s residents" % CitySim.money_text(int(n[k]))
			"link": return "needs a county road out to neighbor towns"
			"region_buys:garbage": return "needs a neighbor town that sends its trash out"
		return "not yet"
	if int(node.cost) > sim.economy.money:
		return "the town needs $%s for it" % CitySim.money_text(int(node.cost))
	return ""


## The leader's next step up the tree, if any. The town pays for it.
func _develop(sim: CitySim, id: int, stance: String) -> void:
	var h: Dictionary = hubs[id]
	if not h.has("leader"):
		h.leader = Agency.leader(sim, hash([sim.city_seed, "civic", id]))
	var plan := funding(h) * (1.5 if stance == "grow" else 1.0)
	var why: String = h.get("why", "")
	var node := Agency.develop(sim, h, _open_tree(h), h.pos, plan)
	if node.is_empty():
		return
	if int(node.cost) > sim.economy.money:
		h.built.erase(node.id)
		h.why = why
		return
	sim.economy.money -= int(node.cost)
	_touch(h)


static func max_pieces(h: Dictionary) -> int:
	return int(BASE.size() * Balance.HUB_MAX_GROWTH * (1.0 + Agency.effect(h, tree(h), "grow")))


## Once a month, before trade settles: what the hubs can sell (power from
## landfill gas, compost, scrap, room for a neighbor's trash) and, for a town
## with no waste site of its own, trash it pays a neighbor (or, at a higher
## price, a hauler from outside) to take away.
func _trade(sim: CitySim) -> void:
	# Last month's trash taken away by someone else left the curbs.
	var taken := sim.trade.got("garbage")
	var wanted: float = sim.trade.wants.get("garbage", {}).get("amount", 0.0)
	if taken > 0.0 and wanted > 0.0:
		var keep := 1.0 - clampf(taken / wanted, 0.0, 1.0)
		for seg in trash:
			trash[seg] = _snap(trash[seg] * keep)
	# What neighbors' trash came in raises the mound.
	var brought := sim.trade.sold("garbage")
	var totals := {"power": 0.0, "compost": 0.0, "scrap": 0.0, "garbage": 0.0}
	var ids := hubs.keys()
	ids.sort()
	var dumps := []
	for id in ids:
		var h: Dictionary = hubs[id]
		if is_waste(h.kind):
			dumps.append(id)
			totals.garbage += Balance.GARBAGE_BASE_TAKE_TONS
		for g in totals:
			totals[g] += Agency.effect(h, tree(h), g)
	if brought > 0.0 and not dumps.is_empty():
		hubs[dumps[0]].received += brought * 2000.0
	for g in ["power", "compost", "scrap"]:
		sim.trade.offer(g, totals[g])
	sim.trade.offer("garbage", totals.garbage if not dumps.is_empty() else 0.0)
	var need := 0.0
	# A neighbor's trucks under a signed deal take it instead (Interlocal).
	if dumps.is_empty() and not sim.interlocal.serves("trash"):
		var out := 0.0
		for seg in trash:
			out += trash[seg]
		# What's out at the curbs now, plus the month to come.
		if out >= Balance.GARBAGE_STOP_LB:
			need = out / 2000.0 + sim.stats.population * Balance.GARBAGE_TONS_PER_RESIDENT_MONTH
	sim.trade.want("garbage", need)


# --- Growing --------------------------------------------------------------------

## Busy waste sites and the cemetery of a growing town take one more piece
## of free land right next to what they have. A waste site that stays quiet
## gives its newest piece back. Nothing ever opens a second site.
func _decide(sim: CitySim) -> void:
	var ids := hubs.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = hubs[id]
		var grow := false
		# Growth on the Economy page; its leader hears it as this stance.
		var stance := Policies.stance(roundi(policy_growth(id, [0, 1, 2, 3, 4])))
		if is_waste(h.kind):
			# Growth (also your word to its leader): Hold never takes land,
			# Expand at the first sign of being busy.
			grow = h.want > 0 and float(h.short) / h.want >= policy_growth(id, Balance.POLICY_HUB_BUSY)
			h.quiet = h.quiet + 1 if h.want == 0 else 0
			if h.quiet >= Balance.HUB_SHRINK_QUIET and h.cells.size() > BASE.size():
				_shrink(h)
				h.quiet = 0
			h.want = 0
			h.short = 0
		else:
			var target := BASE.size() + int(sim.stats.population / Balance.CEMETERY_PEOPLE_PER_PIECE
				* policy_growth(id, Balance.POLICY_CEMETERY_PACE))
			grow = h.cells.size() < target
		# The town pays for the land, so a town in the red can't grow its hubs.
		if sim.economy.money < 0 or stance == "hold":
			grow = false
		if stance != "hold":
			_develop(sim, id, stance)
		if grow and h.cells.size() < max_pieces(h):
			var c := _best_piece(sim, id)
			h.boxed = c == Vector2i.MAX
			if not h.boxed:
				# An edge piece the road has since let go of becomes whole.
				h.edge.erase(c)
				h.cells.append(c)
				_touch(h)
				sim.zones_changed.emit()
			elif _take_edge(sim, id):
				_touch(h)
				sim.zones_changed.emit()
		elif not grow:
			h.boxed = false
	_landfill_height()


## The free piece touching the hub that keeps it most compact.
func _best_piece(sim: CitySim, id: int) -> Vector2i:
	var h: Dictionary = hubs[id]
	var mid := Vector2.ZERO
	for c in h.cells:
		mid += Vector2(c)
	mid /= h.cells.size()
	var best := Vector2i.MAX
	var best_d := INF
	var seen := {}
	for c in h.cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n in h.cells or seen.has(n):
				continue
			seen[n] = true
			var dist := Vector2(n).distance_to(mid)
			if dist > best_d + 0.001 or (absf(dist - best_d) <= 0.001 and _less(best, n)):
				continue
			if _cell_problem(sim, h, n, id, true) == "":
				best = n
				best_d = dist
	return best


static func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


# --- Edge pieces ------------------------------------------------------------------
# A hub boxed in by roads (no whole piece fits) fills the rest of its block
# up to the sidewalk: it takes a piece next to its land cut back to each
# road's right of way plus SETBACK, the same gap its front keeps from the
# street. Kept only when at least EDGE_MIN of a piece is left and nothing
# else (another owner, a zoned or built lot, water, a reserve) is on it.
# Roads still win: a road built later through an edge piece cuts it back
# again, or takes it (_prune).

## Takes the edge piece next to hub `id` that keeps it most compact, if one
## fits. True when it took one.
func _take_edge(sim: CitySim, id: int) -> bool:
	var h: Dictionary = hubs[id]
	return take_edge(sim, h, func(world: PackedVector2Array) -> String:
		return _ground_problem(sim, world, _inner_pts(world, h.cell * 0.2), id, true, false))


## Takes the edge piece next to `h`'s land that keeps it most compact, if
## one fits: shared by the hubs and the post office (Mail), which use the
## same pieces and frame. `problem` says why ground (an outline, x, z) can't
## be the owner's, or "". True when it took one.
static func take_edge(sim: CitySim, h: Dictionary, problem: Callable) -> bool:
	var mid := Vector2.ZERO
	for c in h.cells:
		mid += Vector2(c)
	mid /= h.cells.size()
	var tries := []
	var seen := {}
	for c in h.cells + h.edge.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n in h.cells or h.edge.has(n) or seen.has(n):
				continue
			seen[n] = true
			tries.append([Vector2(n).distance_to(mid), n])
	tries.sort_custom(func(a, b): return a[0] < b[0] - 0.001 or (absf(a[0] - b[0]) <= 0.001 and _less(a[1], b[1])))
	for t in tries:
		var shape := edge_shape(sim, h, t[1], h.edge, problem)
		if not shape.is_empty():
			h.edge[t[1]] = shape
			return true
	return false


## Piece `c` of `h` cut back to the roads, in its frame, if what's left is
## big enough, touches its land (its whole pieces and the edge pieces in
## `edges`) and is free (`problem`, as take_edge); else empty. `from` is an
## edge piece's outline (x, z) to cut back again: land it already holds, so
## only its size and touch are checked.
static func edge_shape(sim: CitySim, h: Dictionary, c: Vector2i, edges: Dictionary, problem: Callable,
		from := PackedVector2Array()) -> PackedVector2Array:
	# Cut a few centimetres wider than the roads need, so the outline kept in
	# EDGE_SNAP steps never pokes back over them.
	var parts := _cut_by_roads(sim.network, cell_poly(h, c) if from.is_empty() else from, EDGE_SNAP * 3.0)
	if parts.is_empty():
		return PackedVector2Array()
	var best := PackedVector2Array()
	var best_a := 0.0
	for part in parts:
		var a := area(part)
		if a > best_a + 0.01 and _touches_land(h, c, part, edges):
			best = part
			best_a = a
	var full: float = h.cell * h.cell
	# Not cut at all: the piece was turned down for something other than a road.
	if best.is_empty() or best_a < full * EDGE_MIN or (from.is_empty() and best_a > full * 0.98):
		return PackedVector2Array()
	var local := PackedVector2Array()
	for q in best:
		var l := to_local(h, q)
		l = Vector2(snappedf(l.x, EDGE_SNAP), snappedf(l.y, EDGE_SNAP))
		if local.is_empty() or l.distance_to(local[-1]) > 0.05:
			local.append(l)
	if local.size() > 1 and local[0].distance_to(local[-1]) <= 0.05:
		local.remove_at(local.size() - 1)
	if local.size() < 3:
		return PackedVector2Array()
	var world := PackedVector2Array()
	for l in local:
		world.append(to_world(h, l))
	if from.is_empty() and problem.call(world) != "":
		return PackedVector2Array()
	return local


## `poly` (x, z) less every road's right of way and the SETBACK gap (and
## `extra` metres): the pieces left, or [] when a road's whole band sits
## inside it (it would leave a hole).
static func _cut_by_roads(network: RoadNetwork, poly: PackedVector2Array, extra := 0.0) -> Array:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	var parts := [poly]
	for band in _road_bands(network, box, extra):
		var next := []
		for p in parts:
			var inside := true
			for q in band:
				if not Geometry2D.is_point_in_polygon(q, p):
					inside = false
					break
			if inside:
				return []
			next.append_array(Geometry2D.clip_polygons(p, band))
		parts = next
	return parts


## Each road near `box` widened to its right of way plus SETBACK (and
## `extra`), as outlines (x, z), in road id order.
static func _road_bands(network: RoadNetwork, box: Rect2, extra := 0.0) -> Array:
	var out := []
	var ix := RoadIndex.of(network)
	var ids: Array = ix.near(box.grow(SETBACK + 1.0)) if ix != null else network.segments.keys()
	ids.sort()
	for id in ids:
		var w := RoadStyle.right_of_way_half(network.segments[id].type) + SETBACK + extra
		var c := network.curve_of(id)
		var reach := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)) \
			.expand(Vector2(c[2].x, c[2].z)).grow(w + 1.0)
		if not reach.intersects(box):
			continue
		var length: float = c[0].distance_to(c[1]) + c[1].distance_to(c[2])
		var line := PackedVector2Array()
		for p in network.sample_segment(id, clampi(int(length / 4.0), 8, 128)):
			line.append(Vector2(p.x, p.z))
		out.append_array(Geometry2D.offset_polyline(line, w, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	return out


## True when `part` (x, z) runs along a side of the land next to piece `c`
## (hub `h`'s whole pieces, or the edge pieces in `edges`) for a good
## stretch: a fifth of a piece.
static func _touches_land(h: Dictionary, c: Vector2i, part: PackedVector2Array, edges: Dictionary) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		var other := PackedVector2Array()
		if n in h.cells:
			other = cell_poly(h, n)
		elif edges.has(n):
			for q in edges[n]:
				other.append(to_world(h, q))
		else:
			continue
		var touch := 0.0
		for grown in Geometry2D.offset_polygon(other, 0.5):
			for q in Geometry2D.intersect_polygons(part, grown):
				touch += area(q)
		if touch >= 0.5 * h.cell * 0.2:
			return true
	return false


## Points to look at ground `poly` (x, z) through: a grid `step` apart
## inside it, and its corners pulled a metre and a half in.
static func _inner_pts(poly: PackedVector2Array, step: float) -> Array:
	var box := Rect2(poly[0], Vector2.ZERO)
	var mid := Vector2.ZERO
	for q in poly:
		box = box.expand(q)
		mid += q
	mid /= poly.size()
	var out := []
	var nx := maxi(1, ceili(box.size.x / step))
	var ny := maxi(1, ceili(box.size.y / step))
	for i in nx:
		for j in ny:
			var q := box.position + Vector2((i + 0.5) * box.size.x / nx, (j + 0.5) * box.size.y / ny)
			if Geometry2D.is_point_in_polygon(q, poly):
				out.append(Vector3(q.x, 0.0, q.y))
	for q in poly:
		var p: Vector2 = q + (mid - q).limit_length(1.5)
		if Geometry2D.is_point_in_polygon(p, poly):
			out.append(Vector3(p.x, 0.0, p.y))
	return out


## Roads win over edge pieces too: each is cut back to the roads as they
## are now (or goes, if too little is left), and any no longer joined to
## the hub's whole pieces goes. True when anything changed.
static func prune_edges(sim: CitySim, h: Dictionary) -> bool:
	var changed := false
	for c in h.edge.keys():
		var now := edge_poly(h, c)
		var parts := _cut_by_roads(sim.network, now)
		var left := 0.0
		for part in parts:
			left = maxf(left, area(part))
		if left >= area(now) - 0.5:
			continue
		changed = true
		var shape := edge_shape(sim, h, c, h.edge, Callable(), now) if left > 0.0 else PackedVector2Array()
		if shape.is_empty():
			h.edge.erase(c)
		else:
			h.edge[c] = shape
	# Only edge pieces still joined to the whole pieces stay.
	var joined := {}
	var grew := true
	while grew:
		grew = false
		for c in h.edge:
			if not joined.has(c) and _touches_land(h, c, edge_poly(h, c), joined):
				joined[c] = h.edge[c]
				grew = true
	for c in h.edge.keys():
		if not joined.has(c):
			h.edge.erase(c)
			changed = true
	return changed


## Gives back the newest piece that leaves the rest in one piece.
func _shrink(h: Dictionary) -> void:
	if not h.edge.is_empty():
		h.edge.erase(h.edge.keys()[-1])
		_touch(h)
		return
	for i in range(h.cells.size() - 1, BASE.size() - 1, -1):
		var rest: Array = h.cells.duplicate()
		rest.remove_at(i)
		if _connected(rest).size() == rest.size():
			h.cells = rest
			_touch(h)
			return


## Roads win: pieces a road now runs through go, and if that splits the
## hub, only the part with the most land (by the gate on a tie) stays.
## Edge pieces are cut back to the new roads (prune_edges).
func _prune(sim: CitySim) -> void:
	var ids := hubs.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = hubs[id]
		var keep := []
		for c in h.cells:
			if not Services.road_clash(sim.network, cell_poly(h, c, 1.0)):
				keep.append(c)
		if keep.size() == h.cells.size():
			if not h.edge.is_empty() and prune_edges(sim, h):
				_touch(h)
			continue
		var parts := []
		var left := keep.duplicate()
		while not left.is_empty():
			var part := _connected(left)
			parts.append(part)
			left = left.filter(func(c): return not c in part)
		var best := []
		for part in parts:
			if part.size() > best.size() or (part.size() == best.size() and _gate_side(part) < _gate_side(best)):
				best = part
		h.cells = h.cells.filter(func(c): return c in best)
		prune_edges(sim, h)
		_touch(h)
		if h.cells.is_empty():
			remove(id)


static func _gate_side(part: Array) -> int:
	var m := 1 << 30
	for c in part:
		m = mini(m, c.y * 100 + absi(c.x))
	return m


## The pieces joined to the first one, side to side.
static func _connected(cells: Array) -> Array:
	if cells.is_empty():
		return []
	var out := [cells[0]]
	var i := 0
	while i < out.size():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = out[i] + d
			if n in cells and not n in out:
				out.append(n)
		i += 1
	return out


## Landfills build up before they spread: the mound rises a metre for each
## 2,000 tons brought in (redrawn in whole metres).
func _landfill_height() -> void:
	for id in hubs:
		var h: Dictionary = hubs[id]
		if h.kind == "landfill":
			var m := mound_height(h)
			if m != h.get("drawn_height", -1.0):
				h.drawn_height = m
				_touch(h)


static func mound_height(h: Dictionary) -> float:
	return clampf(6.0 + floorf(h.received / 4_000_000.0), 6.0, 24.0)


func _touch(h: Dictionary) -> void:
	h.ver = int(h.get("ver", 0)) + 1
	version += 1


static func _xz(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]


# --- Saving -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for id in hubs:
		var h: Dictionary = hubs[id]
		var cells := []
		for c in h.cells:
			cells.append([c.x, c.y])
		out[str(id)] = {"kind": h.kind, "pos": [h.pos.x, h.pos.z], "dir": [h.dir.x, h.dir.z], "cells": cells,
			"since": h.since, "scar": h.scar, "received": h.received, "want": h.want, "short": h.short,
			"quiet": h.quiet, "capped": h.get("capped", false), "built": h.built,
			"leader": h.get("leader", {}), "why": h.get("why", "")}
		if not h.edge.is_empty():
			out[str(id)].edge = edge_to_save(h.edge)
	var t := {}
	for seg in trash:
		t[str(seg)] = trash[seg]
	var tr := {}
	for id in trips:
		tr[str(id)] = trips[id]
	return {"hubs": out, "next_id": _next_id, "trash": t, "trips": tr, "parked": parked,
		"claimed": claimed.keys()}


## Edge pieces as a save keeps them: [[x, y, [outline x, z, x, z, ...]]],
## in the order they were taken (the hubs and the post office alike).
static func edge_to_save(edge: Dictionary) -> Array:
	var out := []
	for c in edge:
		var pts := []
		for q in edge[c]:
			pts.append_array([q.x, q.y])
		out.append([c.x, c.y, pts])
	return out


## And back (older saves have none).
static func edge_from_save(saved) -> Dictionary:
	var out := {}
	if not saved is Array:
		return out
	for e in saved:
		if not e is Array or e.size() < 3 or not e[2] is Array:
			continue
		var poly := PackedVector2Array()
		for i in range(0, e[2].size() - 1, 2):
			poly.append(Vector2(float(e[2][i]), float(e[2][i + 1])))
		if poly.size() >= 3:
			out[Vector2i(int(e[0]), int(e[1]))] = poly
	return out


func from_dict(d: Dictionary) -> void:
	hubs.clear()
	for k in d.get("hubs", {}):
		var s: Dictionary = d.hubs[k]
		if not KINDS.has(str(s.kind)):
			continue
		var cells := []
		for c in s.cells:
			cells.append(Vector2i(int(c[0]), int(c[1])))
		hubs[int(k)] = {"kind": str(s.kind), "pos": Vector3(s.pos[0], 0.0, s.pos[1]),
			"dir": Vector3(s.dir[0], 0.0, s.dir[1]).normalized(), "cell": float(KINDS[str(s.kind)].cell),
			"cells": cells, "since": int(s.get("since", 0)), "scar": float(s.get("scar", 0.0)),
			"received": float(s.get("received", 0.0)), "want": int(s.get("want", 0)),
			"short": int(s.get("short", 0)), "quiet": int(s.get("quiet", 0)), "boxed": false,
			"capped": bool(s.get("capped", false)), "ver": 0, "why": str(s.get("why", "")), "edge": {}}
		var h: Dictionary = hubs[int(k)]
		h.edge = edge_from_save(s.get("edge", []))
		if s.get("leader", {}) is Dictionary and not s.get("leader", {}).is_empty():
			h.leader = s.leader
		# Older saves kept the build tick in "built" and the tree in "dev".
		var built = s.get("built", [])
		if not built is Array:
			h.since = int(built)
			built = s.get("dev", [])
		var ids := []
		for node in tree(h):
			ids.append(node.id)
		h.built = Array(built).map(func(x): return str(x)).filter(func(x): return x in ids)
		# A recycling centre on an old landfill keeps the landfill's land size.
		if hubs[int(k)].capped:
			hubs[int(k)].cell = float(KINDS.landfill.cell)
	_next_id = int(d.get("next_id", 1))
	trash.clear()
	for seg in d.get("trash", {}):
		trash[int(seg)] = float(d.trash[seg])
	trips.clear()
	for id in d.get("trips", {}):
		trips[int(id)] = _truck(d.trips[id])
	parked.clear()
	for p in d.get("parked", []):
		parked.append(_truck(p))
	claimed.clear()
	for seg in d.get("claimed", []):
		claimed[int(seg)] = true
	_net_dirty = true
	version += 1


static func _truck(t: Dictionary) -> Dictionary:
	return {"hub": int(t.hub), "load": float(t.load), "stops": int(t.stops), "seg": int(t.seg),
		"prev": int(t.get("prev", -1)), "at": [float(t.at[0]), float(t.at[1])]}


## Pounds of trash in 1/1024 lb steps: exact in a JSON save, so a loaded copy
## of the city carries on exactly the same.
static func _snap(lb: float) -> float:
	return snappedf(lb, 1.0 / 1024.0)
