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

## id -> {kind, pos (gate: middle of the front edge), dir (unit, toward the
## road), cell (metres), cells: [Vector2i], built (tick), scar (game days the
## old landfill still weighs on the area), received (lb brought in), want,
## short, quiet (growth counters), boxed (no room to grow), ver}
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
var _next_id := 1
var _net_dirty := true
var _hooked: RoadNetwork


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


## Where a new hub goes when placed beside the road nearest `hit`: [gate,
## dir toward the road], or [] if no street is near.
static func site_near(network: RoadNetwork, hit: Vector3) -> Array:
	var near := network.find_segment_near(hit, 120.0, 1.0)
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
	for p in pts:
		if not sim.land_ok(p):
			return "Can't build in the water or on a slope that steep."
	for p in pts:
		if sim.reserves.kind_at(p) != "":
			return "That land is reserved for %s." % Reserves.KINDS[sim.reserves.kind_at(p)]
	if Services.road_clash(sim.network, poly):
		return "Too close to a road."
	for sid in sim.services.buildings:
		if not Geometry2D.intersect_polygons(poly, sim.services.footprint(sid)).is_empty():
			return "Overlaps the %s." % Services.KINDS[sim.services.buildings[sid].kind].name.to_lower()
	for p in pts:
		var other := at(p)
		if other != -1 and other != id:
			return "Overlaps the %s." % KINDS[hubs[other].kind].name.to_lower()
		if sim.farms.covers(p) or sim.farms.field_at(p) != -1:
			return "That ground is farmland."
		if sim.parks.covers(p):
			return "That ground is a park."
		if sim.industry.covers(p):
			return "That ground belongs to a company."
		if sim.warehouses.covers(p):
			return "That ground belongs to a warehouse."
		if sim.education.covers(p):
			return "That ground is a campus."
	if auto:
		for key in sim.lots:
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
	h.merge({"built": tick, "scar": 0.0, "received": 0.0, "want": 0, "short": 0, "quiet": 0, "dev": [],
		"boxed": false, "ver": 0})
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
	return [mid, r]


func trucks(id: int) -> int:
	var h: Dictionary = hubs[id]
	if not is_waste(h.kind):
		return 0
	return int(Balance.HUB_TRUCKS[h.kind]) + extra_pieces(h) / 2


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
		var h: Dictionary = hubs[id]
		var s: Dictionary = Balance.WASTE_SITES[h.kind]
		var size := 1.0 + Balance.HUB_PIECE_UPKEEP * extra_pieces(h)
		total += (float(s.upkeep) - sales(h)) * size
		for key in h.dev:
			total += float(Balance.HUB_DEVELOPMENTS[key].upkeep)
	return roundi(total)


## What a recycling hub sells a month (before its size), with any extra
## sorting lines.
static func sales(h: Dictionary) -> float:
	var lift := 1.0
	for key in h.dev:
		lift += float(Balance.HUB_DEVELOPMENTS[key].get("sales", 0.0))
	return float(Balance.WASTE_SITES[h.kind].get("sales", 0)) * lift


# --- Land value ---------------------------------------------------------------

## How much a place's land value is changed by the hubs around it: 1.0 is
## no change, 0.85 is 15% lower.
func value_factor(p: Vector3) -> float:
	var total := 0.0
	for id in hubs:
		var h: Dictionary = hubs[id]
		var d := distance(h, p)
		total += _effect(h.kind, d)
		for key in h.dev:
			var dv: Dictionary = Balance.HUB_DEVELOPMENTS[key]
			if dv.has("value"):
				var reach := float(Balance.WASTE_SITES[h.kind].reach) + float(dv.reach)
				total += float(dv.value) * maxf(0.0, 1.0 - d / reach)
		if h.scar > 0.0:
			total += _effect("landfill", d) * h.scar / Balance.LANDFILL_RECOVERY_DAYS
	return clampf(1.0 + total, 0.5, 1.5)


static func _effect(kind: String, d: float) -> float:
	var s: Dictionary = Balance.WASTE_SITES[kind]
	if float(s.reach) <= 0.0 or d >= float(s.reach):
		return 0.0
	return float(s.value) * (1.0 - d / float(s.reach))


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
	var f := value_factor(lot.pos)
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
	if sim.tick_count % EVERY == 0:
		_pile_up(sim)
		if sim.simulate_traffic:
			_send_trucks(sim)
		else:
			_collect_offstage()
	if sim.tick_count % Balance.HUB_DECIDE_EVERY == 0 and not hubs.is_empty():
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
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if not sim.lots.has(key):
			continue
		var b: Dictionary = sim.buildings[key]
		var lb := 0.0
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			lb = b.occ * Balance.GARBAGE_LB_PER_RESIDENT
		elif sim.utilities_ok(key):
			lb = b.cap * Balance.GARBAGE_LB_PER_JOB
		if lb <= 0.0:
			continue
		var seg: int = sim.lots[key].seg
		trash[seg] = minf(trash.get(seg, 0.0) + lb * share, Balance.GARBAGE_PILE_LB * 4.0)
	for seg in trash.keys():
		if not sim.network.segments.has(seg):
			trash.erase(seg)
			claimed.erase(seg)


## With cars switched off (the balance harness), each waste site just takes
## in what its trucks could have carried.
func _collect_offstage() -> void:
	var segs := trash.keys()
	segs.sort()
	var ids := _waste_ids()
	for id in ids:
		var room := float(trucks(id)) * Balance.GARBAGE_STOP_LB * 2.0
		for seg in segs:
			if room <= 0.0:
				break
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
		_dispatch(sim, {"hub": id, "load": 0.0, "stops": 0, "seg": seg, "prev": -1, "at": _xz(h.pos)}, curb[seg])


## Where trash waits on each street: the curb in front of its first building.
func _curbs(sim: CitySim) -> Dictionary:
	var out := {}
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if sim.lots.has(key) and not out.has(sim.lots[key].seg):
			out[sim.lots[key].seg] = sim.lots[key].front
	return out


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
# neighboring towns (Balance.HUB_DEVELOPMENTS).

## landfill, recycling or cemetery.
static func family(kind: String) -> String:
	return "recycling" if kind.begins_with("recycling") else kind


## The options this hub's tree offers, built or not, in order. A recycling
## centre on an old landfill keeps the landfill's options (a capped
## landfill still makes gas).
static func dev_options(h: Dictionary) -> Array:
	var out := []
	for key in Balance.HUB_DEVELOPMENTS:
		var f: String = Balance.HUB_DEVELOPMENTS[key]["for"]
		if f == family(h.kind) or (f == "landfill" and h.get("capped", false)):
			out.append(key)
	return out


## Why this hub can't add `key` yet, in a few plain words, or "".
func dev_problem(sim: CitySim, id: int, key: String) -> String:
	if not hubs.has(id) or not key in dev_options(hubs[id]):
		return "not for this site"
	var h: Dictionary = hubs[id]
	if key in h.dev:
		return "built"
	var dv: Dictionary = Balance.HUB_DEVELOPMENTS[key]
	var n: Dictionary = dv.needs
	if n.has("pieces") and h.cells.size() < int(n.pieces):
		return "needs a bigger site (%d of %d pieces)" % [h.cells.size(), int(n.pieces)]
	if n.has("tons") and h.received / 2000.0 < float(n.tons):
		return "needs %s tons in the mound" % CitySim.money_text(int(n.tons))
	if n.has("level") and (h.kind == "landfill" or h.kind == "cemetery" or int(str(h.kind).substr(10)) < int(n.level)):
		return "needs the %s" % KINDS["recycling_%d" % int(n.level)].name.to_lower()
	if n.has("dev") and not str(n.dev) in h.dev:
		return "needs the %s first" % Balance.HUB_DEVELOPMENTS[n.dev].name.to_lower()
	if n.has("farms") and sim.farms.farms.size() < int(n.farms):
		return "needs a farm in town to buy it"
	if n.has("factories") and sim.count_buildings(ZoneMap.Zone.INDUSTRIAL) < int(n.factories):
		return "needs %d factories in town" % int(n.factories)
	if n.has("school"):
		var school := false
		for sid in sim.services.buildings:
			school = school or sim.services.buildings[sid].kind == Services.Kind.SCHOOL
		if not school:
			return "needs a school for trained workers"
	if n.has("population") and sim.stats.population < int(n.population):
		return "needs %s residents" % CitySim.money_text(int(n.population))
	if n.has("region") and sim.region_links.is_empty():
		return "needs a county road out to neighbor towns"
	if n.has("forest"):
		var best := 0.0
		for c in h.cells:
			best = maxf(best, Resources.at(Resources.Kind.FOREST, cell_center(h, c)))
		if best < float(n.forest):
			return "needs woods next to it"
	if int(dv.cost) > sim.economy.money:
		return "costs $%s" % CitySim.money_text(int(dv.cost))
	return ""


func develop(sim: CitySim, id: int, key: String) -> bool:
	if dev_problem(sim, id, key) != "":
		return false
	sim.economy.money -= int(Balance.HUB_DEVELOPMENTS[key].cost)
	hubs[id].dev.append(key)
	_touch(hubs[id])
	return true


static func max_pieces(h: Dictionary) -> int:
	var grow := 1.0
	for key in h.dev:
		grow += float(Balance.HUB_DEVELOPMENTS[key].get("grow", 0.0))
	return int(BASE.size() * Balance.HUB_MAX_GROWTH * grow)


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
			trash[seg] *= keep
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
		for key in h.dev:
			var dv: Dictionary = Balance.HUB_DEVELOPMENTS[key]
			for g in totals:
				totals[g] += float(dv.get(g, 0.0))
	if brought > 0.0 and not dumps.is_empty():
		hubs[dumps[0]].received += brought * 2000.0
	for g in ["power", "compost", "scrap"]:
		sim.trade.offer(g, totals[g])
	sim.trade.offer("garbage", totals.garbage if not dumps.is_empty() else 0.0)
	var need := 0.0
	if dumps.is_empty():
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
		var stance: String = sim.permits.guidance("hub", id).stance
		if is_waste(h.kind):
			# The player's word to its leader: grow sooner, or hold off.
			var share := Balance.HUB_GROW_BUSY_SHARE * (0.5 if stance == "grow" else 1.0)
			grow = h.want > 0 and float(h.short) / h.want >= share
			h.quiet = h.quiet + 1 if h.want == 0 else 0
			if h.quiet >= Balance.HUB_SHRINK_QUIET and h.cells.size() > BASE.size():
				_shrink(h)
				h.quiet = 0
			h.want = 0
			h.short = 0
		else:
			var target := BASE.size() + int(sim.stats.population / Balance.CEMETERY_PEOPLE_PER_PIECE)
			grow = h.cells.size() < target
		if stance == "hold":
			grow = false
		if grow and h.cells.size() < max_pieces(h):
			var c := _best_piece(sim, id)
			h.boxed = c == Vector2i.MAX
			if not h.boxed:
				h.cells.append(c)
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


## Gives back the newest piece that leaves the rest in one piece.
func _shrink(h: Dictionary) -> void:
	for i in range(h.cells.size() - 1, BASE.size() - 1, -1):
		var rest: Array = h.cells.duplicate()
		rest.remove_at(i)
		if _connected(rest).size() == rest.size():
			h.cells = rest
			_touch(h)
			return


## Roads win: pieces a road now runs through go, and if that splits the
## hub, only the part with the most land (by the gate on a tie) stays.
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
			"built": h.built, "scar": h.scar, "received": h.received, "want": h.want, "short": h.short,
			"quiet": h.quiet, "capped": h.get("capped", false), "dev": h.dev}
	var t := {}
	for seg in trash:
		t[str(seg)] = trash[seg]
	var tr := {}
	for id in trips:
		tr[str(id)] = trips[id]
	return {"hubs": out, "next_id": _next_id, "trash": t, "trips": tr, "parked": parked,
		"claimed": claimed.keys()}


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
			"cells": cells, "built": int(s.get("built", 0)), "scar": float(s.get("scar", 0.0)),
			"received": float(s.get("received", 0.0)), "want": int(s.get("want", 0)),
			"short": int(s.get("short", 0)), "quiet": int(s.get("quiet", 0)), "boxed": false,
			"capped": bool(s.get("capped", false)), "ver": 0,
			"dev": Array(s.get("dev", [])).map(func(k): return str(k)).filter(func(k): return Balance.HUB_DEVELOPMENTS.has(k))}
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
