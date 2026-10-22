class_name Warehouses
extends RefCounted
## Warehouses, after Cities: Skylines' storage buildings (Brawn's ask): they
## buffer raw loads and goods between farms, companies, factories, shops and
## the highway. A load nobody needs yet goes into the nearest warehouse with
## room instead of leaving town, and a factory that wants raw material gets
## it from a warehouse before importing it. Goods stop at a distribution
## warehouse on their way to the shops when it's nearer. Every load moves on
## a real truck (see Logistics, ref "wh:<id>").
##
## Each warehouse is a hub with its own agency: when it stays full it builds
## up (taller racks) and then out, one structural bay at a time into the free
## land right behind it. It never opens a second site. When it sits empty for
## months it gives the extra bays back.

## Sizes in Balance.WAREHOUSE; names here.
const KINDS := {
	"small": {"name": "Small warehouse", "area": "10,000 sq ft"},
	"medium": {"name": "Warehouse", "area": "32,000 sq ft"},
	"large": {"name": "Regional warehouse", "area": "100,000 sq ft"},
	"dc": {"name": "Distribution center", "area": "270,000 sq ft"},
}
const ORDER := ["small", "medium", "large", "dc"]
## Gap between the site's front and the road's right of way (as Services).
const SETBACK := 2.0
## Space kept behind the building for a fire lane.
const REAR := 6.0
## Industrial zoning caps (real Midwest codes): 200 m of frontage and
## 80,000 m² (about 20 acres) on one lot.
const MAX_SITE_M2 := 80_000.0
## What each load is stored as: raw materials or finished goods.
const RAW := "raw"
const GOODS := "goods"

## id -> {kind, pos: Vector3 (middle of the site's front edge), dir: Vector3
## (unit, toward the road), level: 0.., bays: 0.., stock: {"raw": {good:
## loads}, "goods": {good: loads}}, units: {good: amount per load}, incoming:
## loads promised, handled: loads in and out since the last decision,
## busy: decisions in a row it was full, idle: decisions in a row it sat empty,
## accepts: goods it takes, [] for anything}
##
## Other threads' buildings can store loads the same way (a grain elevator,
## a cold store): add_store() registers one with kind "store", a fixed
## capacity and its own accepts list. It is not drawn, placed or grown here;
## its owner removes it with buildings.erase(id).
var buildings := {}
var _next_id := 1


func add(kind: String, pos: Vector3, dir: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	buildings[id] = {"kind": kind, "pos": pos, "dir": dir, "level": 0, "bays": 0,
		"stock": {RAW: {}, GOODS: {}}, "units": {}, "incoming": 0, "handled": 0, "busy": 0, "idle": 0, "accepts": []}
	return id


## Registers another thread's storage building. `pos` is its gate on the
## road (where trucks stop), `accepts` the goods it takes (for example
## ["corn", "soybeans"]), or [] for anything. Returns its id ("wh:<id>").
func add_store(pos: Vector3, cap: int, accepts: Array) -> int:
	var id := add("store", pos, Vector3.FORWARD)
	buildings[id].cap = cap
	buildings[id].accepts = accepts.duplicate()
	return id


static func is_store(w: Dictionary) -> bool:
	return w.kind == "store"


## True when it takes this good ("raw" or "goods" match anything with no list).
static func takes(w: Dictionary, good: String) -> bool:
	return w.get("accepts", []).is_empty() or good in w.accepts


## A registered store has no footprint of its own here.
const _NO_SITE := {"w": 0.0, "d": 1.0, "court": 0.0, "docks": 0, "cost": 0, "jobs": 0, "value": 0.0}


static func spec(w: Dictionary) -> Dictionary:
	return Balance.WAREHOUSE.get(w.kind, _NO_SITE)


## The building's depth now, with any bays added at the back.
static func building_depth(w: Dictionary) -> float:
	return float(spec(w).d) + Balance.WAREHOUSE_BAY * int(w.bays)


## The whole site, front to back: truck court, building, fire lane.
static func site_depth(w: Dictionary) -> float:
	return float(spec(w).court) + building_depth(w) + REAR


static func site_width(w: Dictionary) -> float:
	return float(spec(w).w) + 12.0  # a drive lane down one side


## The middle of the site.
static func center(w: Dictionary) -> Vector3:
	return w.pos - w.dir * site_depth(w) * 0.5


## The site's four corners, `extra` bays deeper than it is now.
static func corners(w: Dictionary, extra := 0) -> PackedVector2Array:
	var side := Vector3(-w.dir.z, 0.0, w.dir.x)
	var hw := site_width(w) * 0.5
	var depth := site_depth(w) + Balance.WAREHOUSE_BAY * extra
	var out := PackedVector2Array()
	for p in [w.pos - side * hw, w.pos + side * hw, w.pos + side * hw - w.dir * depth, w.pos - side * hw - w.dir * depth]:
		out.append(Vector2(p.x, p.z))
	return out


## The strip of land the next bay would take, behind the site.
static func next_bay(w: Dictionary) -> PackedVector2Array:
	var side := Vector3(-w.dir.z, 0.0, w.dir.x)
	var hw := site_width(w) * 0.5
	var back: Vector3 = w.pos - w.dir * site_depth(w)
	var out := PackedVector2Array()
	for p in [back - side * hw, back + side * hw, back + side * hw - w.dir * Balance.WAREHOUSE_BAY,
			back - side * hw - w.dir * Balance.WAREHOUSE_BAY]:
		out.append(Vector2(p.x, p.z))
	return out


## Where a warehouse goes when placed beside the road nearest `hit`: [front
## middle, dir toward the road, seg], or [] if no road with lots is near.
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
	return [Vector3(p.x, 0.0, p.z) + normal * front, -normal, near.seg]


## Loads it can hold at its height and floor area.
static func capacity(w: Dictionary) -> int:
	if is_store(w):
		return int(w.cap)
	var floor_m2: float = float(spec(w).w) * building_depth(w)
	var tall: float = Balance.WAREHOUSE_HEIGHTS[int(w.level)] / Balance.WAREHOUSE_HEIGHTS[0]
	return int(floor_m2 * tall / Balance.WAREHOUSE_M2_PER_LOAD)


static func stored(w: Dictionary, what := "") -> int:
	var n := 0
	for cat in ([what] if what != "" else [RAW, GOODS]):
		for good in w.stock[cat]:
			n += int(w.stock[cat][good])
	return n


static func free_space(w: Dictionary) -> int:
	return capacity(w) - stored(w) - int(w.incoming)


static func fill(w: Dictionary) -> float:
	return float(stored(w) + int(w.incoming)) / maxf(1.0, float(capacity(w)))


## The nearest warehouse to `from` with room for one more load of `good`,
## or -1. Promises the space: the truck is on its way.
func take_room(from: Vector3, good := "") -> int:
	var best := -1
	var best_d := INF
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		var w: Dictionary = buildings[id]
		if free_space(w) < 1 or not takes(w, good):
			continue
		var d: float = w.pos.distance_to(from)
		if d < best_d:
			best_d = d
			best = id
	if best != -1:
		buildings[best].incoming += 1
	return best


## Gives back space promised to a truck that never arrived.
func release_room(id: int) -> void:
	if buildings.has(id):
		buildings[id].incoming = maxi(0, int(buildings[id].incoming) - 1)


## A truck unloads: one load of `cargo` into stock.
func receive(id: int, cargo: Dictionary, what: String) -> void:
	if not buildings.has(id):
		return
	var w: Dictionary = buildings[id]
	w.incoming = maxi(0, int(w.incoming) - 1)
	var good := str(cargo.get("good", what))
	w.stock[what][good] = int(w.stock[what].get(good, 0)) + 1
	w.units[good] = cargo.get("amount", 1)
	w.handled += 1


## Takes one load out for a truck: the good it holds most of, as cargo, or {}.
func take_load(id: int, what: String) -> Dictionary:
	var w: Dictionary = buildings[id]
	var best := ""
	var goods: Array = w.stock[what].keys()
	goods.sort()
	for good in goods:
		if int(w.stock[what][good]) > 0 and (best == "" or int(w.stock[what][good]) > int(w.stock[what][best])):
			best = good
	if best == "":
		return {}
	w.stock[what][best] = int(w.stock[what][best]) - 1
	if int(w.stock[what][best]) <= 0:
		w.stock[what].erase(best)
	w.handled += 1
	return {"good": best, "amount": w.units.get(best, 1)}


## A truck that couldn't get through brings its load back.
func put_back(id: int, cargo: Dictionary, what: String) -> void:
	if not buildings.has(id):
		return
	var w: Dictionary = buildings[id]
	var good := str(cargo.get("good", what))
	w.stock[what][good] = int(w.stock[what].get(good, 0)) + 1
	w.handled = maxi(0, int(w.handled) - 1)


## The nearest warehouse holding a load of `what`, or -1.
func nearest_with(what: String, from: Vector3, skip: Dictionary = {}) -> int:
	var best := -1
	var best_d := INF
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		if skip.has("wh:%d" % id) or stored(buildings[id], what) < 1:
			continue
		var d: float = buildings[id].pos.distance_to(from)
		if d < best_d:
			best_d = d
			best = id
	return best


## Every warehouse takes a step. Full twice in a row: it builds up to the
## next clear height, or once at the tallest, adds a bay at the back if
## that land is free (`usable(poly, id)` comes from the city) and the site
## stays within the zoning caps. Empty and idle for months: it gives back a
## bay. Returns true when any building changed shape.
func decide(usable: Callable) -> bool:
	var changed := false
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		var w: Dictionary = buildings[id]
		if is_store(w):
			continue  # its owner grows it
		var f := fill(w)
		w.busy = int(w.busy) + 1 if f >= Balance.WAREHOUSE_BUSY else 0
		w.idle = int(w.idle) + 1 if f <= Balance.WAREHOUSE_IDLE and int(w.handled) == 0 else 0
		w.handled = 0
		w.erase("why")
		if int(w.busy) >= 2:
			w.busy = 0
			if int(w.level) < Balance.WAREHOUSE_HEIGHTS.size() - 1:
				w.level = int(w.level) + 1
				changed = true
			elif not can_extend(w):
				w.why = "It's as big as the zoning allows."
			elif not usable.call(next_bay(w), id):
				w.why = "No free land behind it to grow into."
			else:
				w.bays = int(w.bays) + 1
				changed = true
		elif int(w.idle) >= Balance.WAREHOUSE_IDLE_STREAK and int(w.bays) > 0:
			w.idle = 0
			w.bays = int(w.bays) - 1
			changed = true
	return changed


## True while one more bay keeps the site inside the caps: the industrial
## lot size, and Balance.HUB_MAX_GROWTH times the first building.
static func can_extend(w: Dictionary) -> bool:
	var s := spec(w)
	var depth := site_depth(w) + Balance.WAREHOUSE_BAY
	var first: float = float(s.w) * float(s.d)
	return site_width(w) * depth <= MAX_SITE_M2 \
		and float(s.w) * (building_depth(w) + Balance.WAREHOUSE_BAY) <= first * Balance.HUB_MAX_GROWTH


## The warehouse whose site holds this point, or -1.
func at(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	for id in buildings:
		if not is_store(buildings[id]) and Geometry2D.is_point_in_polygon(q, corners(buildings[id])):
			return id
	return -1


func covers(p: Vector3) -> bool:
	return at(p) != -1


func footprint(id: int) -> PackedVector2Array:
	return corners(buildings[id])


func jobs() -> int:
	var total := 0
	for id in buildings:
		var w: Dictionary = buildings[id]
		var s := spec(w)
		total += int(round(float(s.jobs) * building_depth(w) / float(s.d)))
	return total


## Assessed value the city taxes (bays and taller racks add to it).
func taxable_value() -> float:
	var total := 0.0
	for id in buildings:
		total += value(buildings[id])
	return total


static func value(w: Dictionary) -> float:
	var s := spec(w)
	return float(s.value) * building_depth(w) / float(s.d) * (1.0 + 0.15 * int(w.level))


func to_dict() -> Dictionary:
	var out := {}
	for id in buildings:
		var w: Dictionary = buildings[id]
		out[str(id)] = {"kind": w.kind, "pos": [w.pos.x, w.pos.z], "dir": [w.dir.x, w.dir.z], "level": w.level,
			"bays": w.bays, "stock": w.stock, "units": w.units, "incoming": w.incoming, "handled": w.handled,
			"busy": w.busy, "idle": w.idle, "accepts": w.get("accepts", []), "cap": w.get("cap", 0)}
	return {"buildings": out, "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	buildings.clear()
	for k in d.get("buildings", {}):
		var w: Dictionary = d.buildings[k]
		var stock := {RAW: {}, GOODS: {}}
		for cat in stock:
			var saved: Dictionary = w.get("stock", {}).get(cat, {})
			for good in saved:
				stock[cat][str(good)] = int(saved[good])
		buildings[int(k)] = {"kind": str(w.kind), "pos": Vector3(w.pos[0], 0.0, w.pos[1]),
			"dir": Vector3(w.dir[0], 0.0, w.dir[1]).normalized(), "level": int(w.get("level", 0)),
			"bays": int(w.get("bays", 0)), "stock": stock, "units": w.get("units", {}),
			"incoming": int(w.get("incoming", 0)), "handled": int(w.get("handled", 0)),
			"busy": int(w.get("busy", 0)), "idle": int(w.get("idle", 0)), "accepts": w.get("accepts", []).duplicate()}
		if str(w.kind) == "store":
			buildings[int(k)].cap = int(w.get("cap", 0))
	_next_id = int(d.get("next_id", 1))
