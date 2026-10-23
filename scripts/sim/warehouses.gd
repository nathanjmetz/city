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
##
## Its leader (Agency.leader) also builds from the warehouse's development
## tree (TREE, via Agency.develop): cold storage, a tank farm, a truck yard,
## cross-docking, a regional distribution center and more, each opened by
## the leader's schooling and profit, what's nearby in town, and what the
## neighbouring towns buy. Each one that needs ground is a real annex on the
## warehouse's own land, behind the building (`land` metres deep).

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
## The month whose trade sales the regional DCs last took on.
var trade_month := -1


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


## The development tree (Agency format). `land` is the annex depth it adds
## behind the building, in metres (0 for changes inside the building).
## Effects: "cap*" storage, "fee*" what each load handled earns, "jobs+".
## "regional" sells goods to neighbouring towns through Trade; "parcels"
## hands online orders to the post office as parcels.
const TREE := [
	{"id": "truck_yard", "name": "Truck yard", "cost": 150_000, "land": 20.0, "needs": {},
		"effects": {"fee*": 0.05, "jobs+": 4}, "note": "its own trucks park here"},
	{"id": "repair_shop", "name": "Truck repair shop", "cost": 250_000, "land": 16.0, "requires": ["truck_yard"],
		"needs": {"profit": 60_000}, "effects": {"fee*": 0.05, "jobs+": 6}},
	{"id": "fuel_island", "name": "Fuel island", "cost": 180_000, "land": 14.0, "requires": ["repair_shop"],
		"needs": {"local:refinery": 1}, "effects": {"fee*": 0.05, "jobs+": 2}, "note": "fuel from the plastics plant down the road"},
	{"id": "cold_storage", "name": "Cold storage", "cost": 600_000, "land": 24.0, "needs": {"local:farm": 1},
		"effects": {"cap*": 0.15, "fee*": 0.2, "jobs+": 6}, "note": "keeps the farms' produce fresh"},
	{"id": "freezer", "name": "Freezer warehouse", "cost": 900_000, "land": 18.0, "requires": ["cold_storage"],
		"needs": {"population": 2000}, "effects": {"fee*": 0.2, "jobs+": 8}, "note": "frozen food for the town's grocers"},
	{"id": "tank_farm", "name": "Tank farm", "cost": 700_000, "land": 26.0, "needs": {"local:oil": 1},
		"effects": {"cap*": 0.2, "fee*": 0.1, "jobs+": 3}, "note": "stores crude from the oil field"},
	{"id": "cross_dock", "name": "Cross-dock", "cost": 800_000, "land": 30.0, "requires": ["truck_yard"],
		"needs": {"local:general": 2, "link": 1}, "effects": {"fee*": 0.2, "jobs+": 10},
		"note": "docks out back too, so loads go straight from truck to truck"},
	{"id": "sortation", "name": "Automated sortation", "cost": 1_200_000, "land": 0.0, "requires": ["cross_dock"],
		"needs": {"leader_edu": 0.5, "education": 0.4}, "effects": {"fee*": 0.2, "jobs+": 5}},
	{"id": "robotics", "name": "Robotic storage", "cost": 2_500_000, "land": 0.0, "requires": ["sortation"],
		"needs": {"leader_edu": 0.7, "profit": 400_000}, "effects": {"cap*": 0.3, "fee*": 0.15, "jobs+": 3},
		"note": "robots pick from racks packed twice as dense"},
	{"id": "co_packing", "name": "Co-packing line", "cost": 500_000, "land": 20.0, "requires": ["cross_dock"],
		"needs": {"population": 3000}, "effects": {"fee*": 0.15, "jobs+": 15}, "note": "boxes and labels goods for the stores"},
	{"id": "regional_dc", "name": "Regional distribution center", "cost": 1_500_000, "land": 30.0, "requires": ["cross_dock"],
		"needs": {"region_buys:goods": 1, "link": 1}, "effects": {"fee*": 0.25, "jobs+": 20, "regional+": 1.0},
		"note": "stocks the shops in the neighbouring towns"},
	{"id": "fulfillment", "name": "Online order fulfillment", "cost": 1_800_000, "land": 0.0, "requires": ["sortation"],
		"needs": {"population": 5000, "leader_edu": 0.6}, "effects": {"fee*": 0.3, "jobs+": 25, "parcels+": 1.0},
		"note": "packs online orders; the post office delivers them"},
]
## A registered store has no footprint of its own here.
const _NO_SITE := {"w": 0.0, "d": 1.0, "court": 0.0, "docks": 0, "cost": 0, "jobs": 0, "value": 0.0}


static func spec(w: Dictionary) -> Dictionary:
	return Balance.WAREHOUSE.get(w.kind, _NO_SITE)


## The building's depth now, with any bays added at the back.
static func building_depth(w: Dictionary) -> float:
	return float(spec(w).d) + Balance.WAREHOUSE_BAY * int(w.bays)


## Ground its built annexes take behind the building.
static func annex_depth(w: Dictionary) -> float:
	var total := 0.0
	for node in TREE:
		if node.id in w.get("built", []):
			total += float(node.land)
	return total


## The whole site, front to back: truck court, building, annexes, fire lane.
static func site_depth(w: Dictionary) -> float:
	return float(spec(w).court) + building_depth(w) + annex_depth(w) + REAR


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


## The strip of land the next bay (or an annex this deep) would take,
## behind the site.
static func next_bay(w: Dictionary, depth := Balance.WAREHOUSE_BAY) -> PackedVector2Array:
	var side := Vector3(-w.dir.z, 0.0, w.dir.x)
	var hw := site_width(w) * 0.5
	var back: Vector3 = w.pos - w.dir * site_depth(w)
	var out := PackedVector2Array()
	for p in [back - side * hw, back + side * hw, back + side * hw - w.dir * depth,
			back - side * hw - w.dir * depth]:
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
	return int(floor_m2 * tall * Agency.effect(w, TREE, "cap*") / Balance.WAREHOUSE_M2_PER_LOAD)


## Its yearly profit: what it earns per load handled, less running the
## building (about $0.75 a sq ft a year).
static func yearly_profit(w: Dictionary) -> float:
	if is_store(w):
		return 0.0
	var per_year := float(w.get("flow", 0.0)) * 12.0 * 24.0 * CitySim.TICKS_PER_HOUR / Balance.WAREHOUSE_DECIDE_EVERY
	var floor_m2: float = float(spec(w).w) * building_depth(w)
	return per_year * Balance.WAREHOUSE_FEE * Agency.effect(w, TREE, "fee*") - floor_m2 * Balance.WAREHOUSE_UPKEEP_M2


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
func decide(sim: CitySim) -> bool:
	var changed := false
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		var w: Dictionary = buildings[id]
		if is_store(w):
			continue  # its owner grows it
		if not w.has("leader"):
			w.leader = Agency.leader(sim, hash([sim.city_seed, "warehouse", id]))
		var f := fill(w)
		var stance: String = sim.permits.guidance("warehouse", id).stance
		w.busy = int(w.busy) + 1 if f >= Balance.WAREHOUSE_BUSY else 0
		w.idle = int(w.idle) + 1 if f <= Balance.WAREHOUSE_IDLE and int(w.handled) == 0 else 0
		w.flow = snappedf(0.8 * float(w.get("flow", 0.0)) + 0.2 * int(w.handled), 0.01)
		w.handled = 0
		w.erase("boxed")
		# Told to grow, it builds out as soon as it's full.
		if int(w.busy) >= (1 if stance == "grow" else 2):
			w.busy = 0
			if int(w.level) < Balance.WAREHOUSE_HEIGHTS.size() - 1:
				w.level = int(w.level) + 1
				changed = true
			elif stance == "hold":
				w.boxed = "You asked its owner to hold off buying land."
			elif not can_extend(w):
				w.boxed = "It's as big as the zoning allows."
			elif not sim.warehouse_ground_ok(next_bay(w), id):
				w.boxed = "No free land behind it to grow into."
			else:
				w.bays = int(w.bays) + 1
				changed = true
		elif int(w.idle) >= Balance.WAREHOUSE_IDLE_STREAK and int(w.bays) > 0:
			w.idle = 0
			w.bays = int(w.bays) - 1
			changed = true
		# The owner's next step from its tree: an annex on free land behind
		# it (none while held off), or an upgrade inside.
		var tree := TREE.filter(func(node): return float(node.land) <= 0.0 or (stance != "hold"
			and can_extend(w, float(node.land)) and sim.warehouse_ground_ok(next_bay(w, float(node.land)), id)))
		if not Agency.develop(sim, w, tree, w.pos, yearly_profit(w)).is_empty():
			changed = true
		# Online order fulfillment packs the town's orders into parcels.
		if Agency.effect(w, TREE, "parcels+") > 0.0:
			w.parcels = int(w.get("parcels", 0)) + roundi(sim.stats.population * Balance.WAREHOUSE_PARCELS_PER_PERSON
				* Balance.WAREHOUSE_DECIDE_EVERY / (24.0 * CitySim.TICKS_PER_HOUR))
	_regional(sim)
	return changed


## Regional distribution centers stock the shops in the neighbouring towns:
## they offer the goods they hold through Trade, and each month's sales go
## out to the region link by truck ("owed" loads, see Logistics).
func _regional(sim: CitySim) -> void:
	var dcs := []
	for id in buildings:
		if not is_store(buildings[id]) and Agency.effect(buildings[id], TREE, "regional+") > 0.0:
			dcs.append(id)
	dcs.sort()
	var month := int(sim.tick_count / (24 * CitySim.TICKS_PER_HOUR))
	if month != trade_month:
		trade_month = month
		var sold := int(sim.trade.sold("goods"))
		var i := 0
		var tries := sold * maxi(1, dcs.size())
		while sold > 0 and i < tries:
			var w: Dictionary = buildings[dcs[i % dcs.size()]]
			if int(w.get("owed", 0)) < stored(w, GOODS):
				w.owed = int(w.get("owed", 0)) + 1
				sold -= 1
			i += 1
	var spare := 0
	for id in dcs:
		var w: Dictionary = buildings[id]
		spare += clampi(stored(w, GOODS) - int(w.get("owed", 0)), 0, Balance.WAREHOUSE_REGIONAL_LOADS)
	sim.trade.offer("goods", float(spare))


## True while one more bay keeps the site inside the caps: the industrial
## lot size, and Balance.HUB_MAX_GROWTH times the first building.
static func can_extend(w: Dictionary, annex := 0.0) -> bool:
	var s := spec(w)
	var more := Balance.WAREHOUSE_BAY if annex <= 0.0 else annex
	var first: float = float(s.w) * float(s.d)
	return site_width(w) * (site_depth(w) + more) <= MAX_SITE_M2 \
		and (annex > 0.0 or float(s.w) * (building_depth(w) + more) <= first * Balance.HUB_MAX_GROWTH)


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
		total += job_count(w)
	return total


static func job_count(w: Dictionary) -> int:
	if is_store(w):
		return 0
	var s := spec(w)
	return int(round(float(s.jobs) * building_depth(w) / float(s.d) + Agency.effect(w, TREE, "jobs+")))


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
			"busy": w.busy, "idle": w.idle, "accepts": w.get("accepts", []), "cap": w.get("cap", 0),
			"leader": w.get("leader", {}), "built": w.get("built", []), "flow": w.get("flow", 0.0), "why": w.get("why", ""),
			"owed": w.get("owed", 0), "parcels": w.get("parcels", 0)}
	return {"buildings": out, "next_id": _next_id, "trade_month": trade_month}


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
		if not (w.get("leader", {}) as Dictionary).is_empty():
			buildings[int(k)].leader = w.leader.duplicate()
		buildings[int(k)].built = (w.get("built", []) as Array).map(func(b): return str(b))
		buildings[int(k)].flow = float(w.get("flow", 0.0))
		buildings[int(k)].owed = int(w.get("owed", 0))
		buildings[int(k)].parcels = int(w.get("parcels", 0))
		if str(w.get("why", "")) != "":
			buildings[int(k)].why = str(w.why)
		if str(w.kind) == "store":
			buildings[int(k)].cap = int(w.get("cap", 0))
	_next_id = int(d.get("next_id", 1))
	trade_month = int(d.get("trade_month", -1))
