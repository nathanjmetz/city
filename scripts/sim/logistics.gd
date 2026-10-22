class_name Logistics
extends RefCounted
## Every load in the city rides a real truck, as in Cities: Skylines (Brawn's
## rule): grain leaves a farm for a mill, crude oil, ore and logs leave their
## company for a processor, and factories send goods to the shops. Factories
## with no local supply import theirs from the highway, and loads with no
## buyer in town leave by the highway for the region.
##
## Warehouses ("wh:<id>", see Warehouses) sit in between: a raw load no
## factory wants yet goes to the nearest one with room before it would leave
## town, factories draw on their stock before importing, and goods stop at
## one on the way to the shops when it is nearer than any shop.
##
## Trucks are Traffic's dispatched trips: they drive the real roads, and the
## load counts only when the truck arrives.

## Ticks between shipping rounds (half a game hour).
const EVERY := 30
## Most trucks sent in one round, so a backlog leaves as a steady stream.
const MAX_PER_ROUND := 6
## Loads of raw material a factory works through in a game day.
const FACTORY_INPUT_PER_DAY := 2.0
const TICKS_PER_YEAR := 12 * 24 * CitySim.TICKS_PER_HOUR

## Bushels waiting at each farm (farm id -> bushels).
var grain := {}
## Each factory's raw loads still wanted (lot key -> loads).
var need := {}
## Raw loads each factory has taken in, waiting to become goods (lot key -> loads).
var stock := {}
## Trucks on the road: traffic trip id -> {from, to, purpose, cargo, kind}.
var trips := {}
## Places whose truck found no route (ref -> true), cleared when one gets through.
var stuck := {}
## Origins that already sent a truck this round: one at a time out of each gate.
var _left := {}
## Running totals for panels.
var delivered := 0
var exported := 0
var imported := 0


func tick(sim: CitySim) -> void:
	for a in sim.traffic.arrivals:
		if trips.has(a.id):
			_arrive(sim, trips[a.id])
			trips.erase(a.id)
	sim.traffic.arrivals.clear()
	for f in sim.traffic.failed:
		if trips.has(f.id):
			_return(sim, trips[f.id])
			trips.erase(f.id)
	sim.traffic.failed.clear()
	if sim.tick_count % EVERY != 0:
		return
	_produce(sim)
	sim.traffic.background_freight = sim.farms.farms.is_empty() and sim.industry.sites.is_empty() \
		and sim.count_buildings(ZoneMap.Zone.INDUSTRIAL) == 0
	_left.clear()
	var sent := 0
	var ids := sim.industry.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = sim.industry.sites[id]
		if s.stock >= 1.0 and sent < MAX_PER_ROUND and not s.drive.is_empty():
			var k: Dictionary = Industry.KINDS[s.kind]
			if _send(sim, {"ref": "site:%d" % id, "pos": _xz(s.drive[-1]), "drive": _lane(s.drive)}, _buyer(sim, s.drive[-1], "raw", Industry.KINDS[s.kind].cargo),
					k.purpose, {"good": k.cargo, "amount": 1}, "site"):
				s.stock -= 1.0
				sent += 1
	ids = sim.farms.farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		if grain.get(id, 0.0) >= Balance.GRAIN_TRUCK_BUSHELS and sent < MAX_PER_ROUND and not f.drive.is_empty():
			if _send(sim, {"ref": "farm:%d" % id, "pos": _xz(f.drive[-1]), "drive": _lane(f.drive)}, _buyer(sim, f.drive[-1], "raw", f.crop),
					"grain", {"good": f.crop, "amount": int(Balance.GRAIN_TRUCK_BUSHELS)}, "farm"):
				grain[id] -= Balance.GRAIN_TRUCK_BUSHELS
				sent += 1
	var keys := need.keys()
	keys.sort()
	for key in keys:
		if not sim.buildings.has(key) or not sim.lots.has(key):
			need.erase(key)
			stock.erase(key)
			continue
		var lot: Dictionary = sim.lots[key]
		if stock.get(key, 0.0) >= Balance.FACTORY_LOADS_PER_GOODS and sent < MAX_PER_ROUND:
			if _send(sim, {"ref": "lot:" + key, "pos": _xz(lot.front)}, _buyer(sim, lot.front, "goods"),
					"goods", {"good": "goods", "amount": 1}, "factory"):
				stock[key] -= Balance.FACTORY_LOADS_PER_GOODS
				sent += 1
		# No local load on its way: take one from a warehouse, else import one
		# from the region. Warehouses hold mixed raw loads, so only a general
		# factory takes from them; the others import their own input.
		var input := input_of(sim, key)
		if need[key] >= 1.0 and sent < MAX_PER_ROUND and not _inbound(key) and input == "materials" \
				and _from_warehouse(sim, key, lot.front):
			sent += 1
		elif need[key] >= 1.0 and sent < MAX_PER_ROUND and not _inbound(key):
			var edge := _edge(sim, lot.front)
			var purpose := "grain" if input == "grain" else ("fuel" if input == "crude oil" else "raw")
			if not edge.is_empty() and _send(sim, edge, {"ref": "lot:" + key, "pos": _xz(lot.front)},
					purpose, {"good": input, "amount": 1}, "import"):
				sent += 1
	# Warehouses send their goods on to the shops.
	ids = sim.warehouses.buildings.keys()
	ids.sort()
	for id in ids:
		var w: Dictionary = sim.warehouses.buildings[id]
		if sent >= MAX_PER_ROUND:
			break
		var wh := {"ref": "wh:%d" % id, "pos": _xz(w.pos)}
		# Goods a neighbouring town bought (regional DC) go first.
		if int(w.get("owed", 0)) > 0 and Warehouses.stored(w, Warehouses.GOODS) >= 1:
			var sold := sim.warehouses.take_load(id, Warehouses.GOODS)
			if _send(sim, wh, _edge(sim, w.pos), "goods", sold, "regional"):
				w.owed = int(w.owed) - 1
				sent += 1
				continue
			sim.warehouses.put_back(id, sold, Warehouses.GOODS)
		# A trailer of online orders to the post office (fulfillment).
		if int(w.get("parcels", 0)) >= Balance.WAREHOUSE_PARCEL_TRUCK:
			var post: Dictionary = sim.mail.parcel_dropoff(w.pos)
			if not post.is_empty() and _send(sim, wh, {"ref": post.ref, "pos": post.pos}, "mail_freight",
					{"good": "parcels", "amount": Balance.WAREHOUSE_PARCEL_TRUCK}, "parcels"):
				w.parcels = int(w.parcels) - Balance.WAREHOUSE_PARCEL_TRUCK
				sent += 1
				continue
		if Warehouses.stored(w, Warehouses.GOODS) < 1:
			continue
		var shop := _buyer(sim, w.pos, "shop")
		if shop.is_empty() or shop.ref == "edge":
			continue  # no shop yet: the goods wait
		var cargo := sim.warehouses.take_load(id, Warehouses.GOODS)
		if _send(sim, wh, shop, "goods", cargo, "wh"):
			sent += 1
		else:
			sim.warehouses.put_back(id, cargo, Warehouses.GOODS)


## Grain grows on the farms and companies fill their yards.
func _produce(sim: CitySim) -> void:
	var share := float(EVERY) / TICKS_PER_YEAR
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var bushels := 0.0
		for c in f.cells:
			bushels += Balance.FARM_BUSHELS_PER_ACRE[f.crop] * Farms.ACRES_PER_CELL \
				* sim.farms.fertility_at(Farms.cell_center(f, c)) * sim.farms.share(id, c)
		grain[id] = grain.get(id, 0.0) + bushels * share * Agency.effect(f, Agency.TREES.farm, "output*")
	for id in grain.keys():
		if not sim.farms.farms.has(id):
			grain.erase(id)
	sim.industry.produce(EVERY / float(CitySim.TICKS_PER_HOUR))
	# Factories that are open want raw materials through the day.
	for key in sim.buildings:
		if sim.buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and sim.utilities_ok(key):
			need[key] = minf(need.get(key, 0.0) + FACTORY_INPUT_PER_DAY * EVERY / (24.0 * CitySim.TICKS_PER_HOUR), 3.0)


## Where a load goes: the nearest open factory that still wants raw
## materials, else the nearest warehouse with room, else out by the highway.
## Goods go to the nearest shop, or a warehouse when one is nearer ("shop":
## shops only, for goods leaving a warehouse).
func _buyer(sim: CitySim, from: Vector3, what: String, good := "") -> Dictionary:
	var zone := ZoneMap.Zone.INDUSTRIAL if what == "raw" else ZoneMap.Zone.COMMERCIAL
	var best := ""
	var best_d := INF
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if sim.buildings[key].zone != zone or not sim.lots.has(key) or not sim.utilities_ok(key):
			continue
		if zone == ZoneMap.Zone.INDUSTRIAL and (need.get(key, 0.0) < 0.5 or input_of(sim, key) != cargo_class(good)):
			continue
		var d: float = sim.lots[key].front.distance_to(from)
		if d < best_d:
			best_d = d
			best = key
	if what == "goods" or (what == "raw" and best == ""):
		var wid := sim.warehouses.take_room(from, good if good != "" else what)  # promised; released below if a shop is nearer
		if wid != -1:
			var w: Dictionary = sim.warehouses.buildings[wid]
			if best == "" or w.pos.distance_to(from) < best_d:
				return {"ref": "wh:%d" % wid, "pos": _xz(w.pos)}
			sim.warehouses.release_room(wid)
	if best != "":
		if zone == ZoneMap.Zone.INDUSTRIAL:
			need[best] -= 1.0  # spoken for
		return {"ref": "lot:" + best, "pos": _xz(sim.lots[best].front)}
	return _edge(sim, from)


## A factory's next raw load from the nearest warehouse holding one.
func _from_warehouse(sim: CitySim, key: String, front: Vector3) -> bool:
	var id := sim.warehouses.nearest_with(Warehouses.RAW, front, _left)
	if id == -1:
		return false
	var w: Dictionary = sim.warehouses.buildings[id]
	var cargo := sim.warehouses.take_load(id, Warehouses.RAW)
	if _send(sim, {"ref": "wh:%d" % id, "pos": _xz(w.pos)}, {"ref": "lot:" + key, "pos": _xz(front)},
			"raw", cargo, "wh"):
		return true
	sim.warehouses.put_back(id, cargo, Warehouses.RAW)
	return false


## The outside connection: the nearest of the town's region links, where
## the county highway runs on to the rest of the region. A town without one
## has no way out yet, so loads wait in the yard and nothing is imported.
func _edge(sim: CitySim, near := Vector3.ZERO) -> Dictionary:
	var best := -1
	var best_d := INF
	for n in sim.region_links:
		if sim.network.nodes.has(n) and sim.network.nodes[n].distance_to(near) < best_d - 0.01:
			best_d = sim.network.nodes[n].distance_to(near)
			best = n
	if best == -1:
		return {}
	return {"ref": "edge", "pos": _xz(sim.network.nodes[best])}


func _send(sim: CitySim, from: Dictionary, to: Dictionary, purpose: String, cargo: Dictionary, kind: String) -> bool:
	if to.is_empty() or from.is_empty() or _left.has(from.ref):
		return false
	var id: int = sim.traffic.dispatch(from, to, purpose, cargo)
	if id == -1:
		stuck[from.ref] = true
		if str(to.ref).begins_with("lot:") and kind in ["site", "farm"]:
			var key: String = str(to.ref).substr(4)
			if need.has(key):
				need[key] += 1.0  # give the order back
		_release(sim, to)
		return false
	trips[id] = {"from": from, "to": to, "purpose": purpose, "cargo": cargo, "kind": kind}
	_left[from.ref] = true
	return true


func _arrive(sim: CitySim, t: Dictionary) -> void:
	stuck.erase(t.from.ref)
	var to: String = t.to.ref
	if to == "edge":
		exported += 1
	elif to.begins_with("mail:"):
		sim.mail.receive_parcels(int(to.substr(5)), int(t.cargo.amount))
	elif to.begins_with("wh:"):
		sim.warehouses.receive(int(to.substr(3)), t.cargo, Warehouses.GOODS if t.purpose == "goods" else Warehouses.RAW)
	elif to.begins_with("lot:") and t.purpose != "goods":
		var key := to.substr(4)
		stock[key] = stock.get(key, 0.0) + 1.0
		if t.kind in ["import", "wh"]:
			if t.kind == "import":
				imported += 1
			need[key] = maxf(0.0, need.get(key, 0.0) - 1.0)
	delivered += 1


## Space a warehouse kept for a truck that never came.
func _release(sim: CitySim, to: Dictionary) -> void:
	if str(to.ref).begins_with("wh:"):
		sim.warehouses.release_room(int(str(to.ref).substr(3)))


## A truck that found no way through takes its load back.
func _return(sim: CitySim, t: Dictionary) -> void:
	stuck[t.from.ref] = true
	var ref: String = t.from.ref
	if ref.begins_with("site:"):
		var id := int(ref.substr(5))
		if sim.industry.sites.has(id):
			sim.industry.sites[id].stock += 1.0
	elif ref.begins_with("farm:"):
		var id := int(ref.substr(5))
		grain[id] = grain.get(id, 0.0) + float(t.cargo.amount)
	elif ref.begins_with("lot:") and t.kind == "factory":
		var key := ref.substr(4)
		stock[key] = stock.get(key, 0.0) + Balance.FACTORY_LOADS_PER_GOODS
	elif ref.begins_with("wh:") and sim.warehouses.buildings.has(int(ref.substr(3))):
		var w: Dictionary = sim.warehouses.buildings[int(ref.substr(3))]
		if t.kind == "parcels":
			w.parcels = int(w.get("parcels", 0)) + int(t.cargo.amount)
		else:
			sim.warehouses.put_back(int(ref.substr(3)), t.cargo, Warehouses.GOODS if t.purpose == "goods" else Warehouses.RAW)
			if t.kind == "regional":
				w.owed = int(w.get("owed", 0)) + 1
	_release(sim, t.to)
	if str(t.to.ref).begins_with("lot:") and t.kind in ["site", "farm"]:
		var key: String = str(t.to.ref).substr(4)
		if need.has(key):
			need[key] += 1.0


## The factory input a raw good counts as: crops are "grain".
static func cargo_class(good: String) -> String:
	return "grain" if Balance.FARM_BUSHELS_PER_ACRE.has(good) else good


## The cargo a factory works (see Balance.FACTORY_CHAINS).
static func input_of(sim: CitySim, key: String) -> String:
	return Balance.FACTORY_CHAINS[sim.buildings[key].get("chain", "general")].input


func _inbound(key: String) -> bool:
	for id in trips:
		if trips[id].to.ref == "lot:" + key:
			return true
	return false


## Trucks on the road now that left from or are headed to this place.
func trucks_for(ref: String) -> int:
	var n := 0
	for id in trips:
		if trips[id].from.ref == ref or trips[id].to.ref == ref:
			n += 1
	return n


## A private lane for Traffic, building end first: trucks drive up it and dock.
static func _lane(drive: Array) -> Array:
	var out := []
	for p in drive:
		out.append(_xz(p))
	return out


static func _xz(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]


func to_dict() -> Dictionary:
	var g := {}
	for id in grain:
		g[str(id)] = grain[id]
	var t := {}
	for id in trips:
		t[str(id)] = trips[id]
	return {"grain": g, "need": need, "stock": stock, "trips": t, "stuck": stuck.keys(),
		"delivered": delivered, "exported": exported, "imported": imported}


func from_dict(d: Dictionary) -> void:
	grain.clear()
	for id in d.get("grain", {}):
		grain[int(id)] = float(d.grain[id])
	need.clear()
	for key in d.get("need", {}):
		need[str(key)] = float(d.need[key])
	stock.clear()
	for key in d.get("stock", {}):
		stock[str(key)] = float(d.stock[key])
	trips.clear()
	for id in d.get("trips", {}):
		trips[int(id)] = d.trips[id]
	stuck.clear()
	for ref in d.get("stuck", []):
		stuck[str(ref)] = true
	delivered = int(d.get("delivered", 0))
	exported = int(d.get("exported", 0))
	imported = int(d.get("imported", 0))
