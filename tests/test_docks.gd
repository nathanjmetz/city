extends SceneTree
## Warehouse docks that work (docs/spec-working-doors.md, step 2). Nathan,
## 2026-10-29: "it would also help if we had working doors and garage doors.
## they could open to black, allowing things to come in and out. this could
## also apply to barns, factories, etc. it is one way we could visualize
## trade, storage, selling and buying, etc." Asked how long a truck should
## sit at a warehouse dock with the door open, "A. About 30 seconds", he
## answered: "A".
##
## The art logs each dock door where the sim puts its dock; a box truck
## bound for a warehouse drives into the court, backs up to a dock door
## (its load counted as it gets there, as at the curb before), and sits
## there 30 s of play (TrafficSim.DOCK_DWELL) with its door up, exactly as
## far as the time since it docked says; the door stays up while it pulls
## away and comes down once it is gone. Saved and loaded mid-dwell, and on
## every computer, it carries on the same; a save from before docks loads
## with its spot numbers meaning what they did; and the door view draws a
## dock door near the camera at High, never at Medium.
## Run: godot --headless -s tests/test_docks.gd

var _failed := false


func _init() -> void:
	_logged()
	_docking()
	_same_everywhere()
	_old_save()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true


## Every kind of warehouse logs one dock door per door it draws, where the
## sim's plain math (Warehouses.dock_doors) puts them; logging takes no
## random numbers, so the building is drawn the same.
func _logged() -> void:
	var to_curb := Warehouses.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var bad := []
	var counts := []
	for kind in Warehouses.ORDER:
		var whs := Warehouses.new()
		var w: Dictionary = whs.buildings[whs.add(kind, Vector3(100, 0, 50), Vector3(0, 0, -1))]
		var b := WarehouseBuilder.new()
		b.rng = RandomNumberGenerator.new()
		b.rng.seed = 77
		b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
		b._warehouse(w, to_curb)
		var logged: Array = b.get_meta("door_log", [])
		var want := Warehouses.dock_doors(w)
		counts.append(logged.size())
		if logged.size() != want.size() or logged.size() != int(Warehouses.spec(w).docks):
			bad.append([kind, logged.size(), want.size()])
			continue
		for i in logged.size():
			var a: Array = logged[i]
			var e: Array = want[i]
			if a[0] != "dock" or (a[1] as Vector3).distance_to(e[1]) > 0.001 or a[2] != e[2] \
					or absf(float(a[3]) - float(e[3])) > 0.001 or absf(float(a[4]) - float(e[4])) > 0.001:
				bad.append([kind, i, a, e])
	_check(bad.is_empty(), "each warehouse logs its dock doors where the sim puts its docks %s %s" % [counts, bad.slice(0, 2)])
	var whs := Warehouses.new()
	var w: Dictionary = whs.buildings[whs.add("medium", Vector3.ZERO, Vector3(0, 0, -1))]
	var x := WarehouseBuilder.build_warehouse(w, 4242, to_curb)
	var y := WarehouseBuilder.build_warehouse(w, 4242, to_curb)
	_check(x[0].get_faces().size() == y[0].get_faces().size(), "a warehouse is drawn the same with its doors logged")


## PerfTown small with a medium warehouse by the factories (as the game-day
## measurement has it), finished building.
static func town() -> CitySim:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	sim.require_utilities = false
	for z in [-210.0, -140.0, -70.0, 0.0, 70.0, 140.0]:
		for x in [330.0, 380.0, 430.0]:
			var site := Warehouses.site_near(sim.network, Vector3(x, 0, z))
			if site.is_empty() or sim.warehouse_problem("medium", site[0], site[1]) != "":
				continue
			if sim.apply({"type": "place_warehouse", "kind": "medium", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
				var ids := sim.warehouses.buildings.keys()
				ids.sort()
				sim.construction.sites.erase("wh:%d" % ids[-1])
				return sim
	return sim


static func wh_id(sim: CitySim) -> int:
	var ids := sim.warehouses.buildings.keys()
	ids.sort()
	return ids[-1] if not ids.is_empty() else -1


## Sends a truck of `kind` with a load from the factory nearest the
## warehouse to it, as Logistics does (its trip on Logistics' books, room
## promised): the trip id.
static func send(sim: CitySim, kind: String, purpose := "goods") -> int:
	var wid := wh_id(sim)
	var w: Dictionary = sim.warehouses.buildings[wid]
	var best := ""
	var bd := INF
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.INDUSTRIAL and sim.lots.has(key):
			var d: float = sim.lots[key].front.distance_to(w.pos)
			if d < bd and d > 60.0:
				bd = d
				best = key
	var from := {"ref": "lot:" + best, "pos": [snappedf(sim.lots[best].front.x, 0.01), snappedf(sim.lots[best].front.z, 0.01)]}
	var to := {"ref": "wh:%d" % wid, "pos": [snappedf(w.pos.x, 0.01), snappedf(w.pos.z, 0.01)]}
	var cargo := {"good": "goods" if purpose == "goods" else "steel", "amount": 1}
	var id := sim.traffic.dispatch(from, to, purpose, cargo, kind)
	if id >= 0:
		sim.logistics.trips[id] = {"from": from, "to": to, "purpose": purpose, "cargo": cargo, "kind": "factory"}
		w.incoming = int(w.incoming) + 1
	return id


static func truck_of(sim: CitySim, trip: int) -> Dictionary:
	for c in sim.traffic.cars + sim.traffic._waiting:
		if c.get("trip", -1) == trip:
			return c
	for c in sim.traffic.parked:
		if c.get("trip", -1) == trip:
			return c
	return {}


## A box truck backs up to a dock door, its load counts as it gets there,
## the door goes up exactly as far as the time since it docked says, it
## sits 30 s of play (300 ticks), and the door stays up while it pulls away
## and comes down after.
func _docking() -> void:
	var sim := town()
	var wid := wh_id(sim)
	_check(wid >= 0, "a medium warehouse stands by the factories")
	if wid < 0:
		return
	var w: Dictionary = sim.warehouses.buildings[wid]
	var ref := Warehouses.traffic_ref(wid, w)
	var trip := send(sim, "box_truck")
	_check(trip >= 0, "a box truck sets off for it (trip %d)" % trip)
	var t: TrafficSim = sim.traffic
	var ev := DoorEvents.new(t, sim)
	var vid: int = truck_of(sim, trip).get("id", -1)
	var stored0 := Warehouses.stored(w)
	var most := 0
	var backing_at := -1
	var counted_at := -1
	var docked_at := -1
	var left_at := -1
	var gone_at := -1
	var shut_at := -1
	var rear_ok := false
	var exact_ok := true
	var exact_seen := 0
	var up_while_leaving := 0
	var key := ""
	var view := _view(sim)
	var drawn := 0
	for i in 6000:
		sim.tick()
		var car := {}
		for c in t.cars:
			if c.id == vid:
				car = c
		var parked: Dictionary = t._by_vid.get(vid, {})
		if backing_at < 0 and car.get("backing", false):
			backing_at = t._tick
			_check(car.j.rev >= car.j.len - 0.001, "it backs the whole way from where it stopped to the dock")
		if counted_at < 0 and Warehouses.stored(w) > stored0:
			counted_at = t._tick
		if counted_at >= 0 and left_at < 0:
			most = maxi(most, Warehouses.stored(w) - stored0)
		if docked_at < 0 and not parked.is_empty() and parked.has("dock_t"):
			docked_at = t._tick
			var pl := t.place(ref)
			var s: Dictionary = pl.spots[parked.spot]
			key = "%s#%d" % [ref, int(s.door)]
			rear_ok = s.get("rear", false) and (parked.pos - parked.face * parked.len).distance_to(s.pos) < 0.05 \
				and parked.face.dot(w.dir) > 0.99
		var open := ev.open_near(w.pos, 300.0)
		if docked_at >= 0 and left_at < 0 and not parked.is_empty():
			var want := clampf(float(t._tick - docked_at) / DoorEvents.DOCK_TICKS, 0.0, 1.0)
			exact_ok = exact_ok and open.has(key) and absf(float(open[key][3]) - want) < 1e-6
			exact_seen += 1
		if docked_at >= 0 and left_at < 0 and parked.is_empty():
			left_at = t._tick
		if left_at >= 0 and gone_at < 0:
			if not car.is_empty() and car.get("j") != null and int(car.j.wi) == -1:
				up_while_leaving += 1 if open.has(key) else 0
			else:
				gone_at = t._tick
		if gone_at >= 0 and shut_at < 0 and not open.has(key):
			shut_at = t._tick
		if docked_at >= 0 and left_at < 0 and t._tick - docked_at == 150:
			view.step(w.pos + Vector3(0, 40, 0))
			drawn = view.drawn
		if shut_at >= 0:
			break
	print("docks: backing at %d, counted at %d, docked at %d, left at %d, out at %d, shut at %d" % [backing_at, counted_at,
		docked_at, left_at, gone_at, shut_at])
	_check(backing_at > 0 and docked_at > backing_at, "it stops in the court and backs up to a dock door")
	_check(counted_at >= backing_at and counted_at <= backing_at + 1 and counted_at < docked_at,
		"its load counts as it gets there, before it backs in (as at the curb before)")
	_check(most == 1, "once (%d stored while it sits there)" % most)
	_check(rear_ok, "parked with its back bumper at the dock, facing the road")
	_check(exact_ok and exact_seen > 290, "the door goes up as it docks, exactly as far as the time says (%d ticks)" % exact_seen)
	_check(left_at - docked_at >= TrafficSim.DOCK_DWELL and left_at - docked_at <= TrafficSim.DOCK_DWELL + 40,
		"it sits 30 s of play (300 ticks) at the open door (%d)" % [left_at - docked_at])
	_check(up_while_leaving > 0, "the door stays up while it pulls away (%d ticks)" % up_while_leaving)
	_check(shut_at >= gone_at and gone_at > 0, "and comes down once it is out in the street")
	_check(drawn >= 1, "at High the door view draws the open dock door (%d)" % drawn)
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.MEDIUM)
	view.step(w.pos + Vector3(0, 40, 0))
	_check(view.drawn == 0, "at Medium no door moves")
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.HIGH)
	view.free()
	# Rigs loaded from the top or side stop out front, as before.
	var flat := send(sim, "flatbed", "raw")
	for i in 3000:
		sim.tick()
		var c: Dictionary = truck_of(sim, flat)
		if c.has("at_place") and str(c.at_place) == ref:
			var s: Dictionary = t.place(ref).spots[c.spot]
			_check(not s.get("rear", false) and not c.has("dock_t"), "a flatbed stops out front, not at a dock (%s)" % s.kind)
			break


func _view(sim: CitySim) -> DoorView:
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.HIGH)
	var view := DoorView.new()
	view.setup(sim.traffic, sim, func(_c, _l): return false, func(_k): return null, func(r: String):
		var w: Dictionary = sim.warehouses.buildings[int(r.substr(3).get_slice("@", 0))]
		return Warehouses.frame(w))
	view._ready()
	return view


## Saved and loaded while the truck backs in, and again while it sits at
## the dock, and on a second computer: it docks and leaves on the same
## ticks, and every dock door is as far up on each, tick for tick.
func _same_everywhere() -> void:
	var a := town()
	var b := town()
	var ta := send(a, "box_truck")
	var tb := send(b, "box_truck")
	_check(ta == tb and ta >= 0, "the same truck sets off on both (%d, %d)" % [ta, tb])
	var vid: int = truck_of(a, ta).id
	var c: CitySim = null
	var d: CitySim = null
	for i in 6000:
		a.tick()
		b.tick()
		var car: Dictionary = truck_of(a, ta)
		if c == null and car.get("backing", false) and car.jd > 3.0:
			c = _reload(a)
		var p: Dictionary = a.traffic._by_vid.get(vid, {})
		if d == null and p.has("dock_t") and a.traffic._tick - int(p.dock_t) >= 100:
			d = _reload(a)
			break
	_check(c != null and d != null, "saved while it backs in, and while it sits at the dock")
	if c == null or d == null:
		return
	# c runs on to where d was saved, then all four together.
	while c.tick_count < d.tick_count:
		c.tick()
	var sims := [a, b, c, d]
	var ref := Warehouses.traffic_ref(wh_id(a), a.warehouses.buildings[wh_id(a)])
	var evs := sims.map(func(s): return DoorEvents.new(s.traffic, s))
	var left := [-1, -1, -1, -1]
	var apart := -1
	var opened := 0
	for i in 500:
		var seen := []
		for k in 4:
			sims[k].tick()
			if left[k] < 0 and not sims[k].traffic._by_vid.has(vid):
				left[k] = sims[k].traffic._tick
			seen.append(_canon(evs[k].open_near(Vector3.ZERO, 1e6), ref))
		opened += 1 if not seen[0].is_empty() else 0
		if apart < 0 and (seen[0] != seen[1] or seen[0] != seen[2] or seen[0] != seen[3]):
			apart = i
	_check(left[0] > 0 and left.all(func(x): return x == left[0]), "it leaves the dock on the same tick everywhere and after a load %s" % [left])
	_check(apart < 0 and opened > 100, "every dock door is as far up on each, tick for tick (%d open ticks)%s" % [opened,
		"" if apart < 0 else " apart at %d" % apart])
	_check(a.economy.money == d.economy.money and a.logistics.delivered == c.logistics.delivered,
		"and the books agree")


static func _reload(sim: CitySim) -> CitySim:
	var out := CitySim.new()
	out.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	return out


static func _canon(open: Dictionary, ref: String) -> Array:
	var keys := open.keys().filter(func(k): return str(k).begins_with(ref))
	keys.sort()
	return keys.map(func(k): return [k, snappedf(float(open[k][3]), 1e-6)])


## A save from before docks: the warehouse's place had its curb space and
## the curb spaces added out front, numbered from 1, and no docks. Loaded,
## those keep their numbers (the docks go on the end), the trucks parked
## there stay where they are, and the next box truck backs up to a dock.
func _old_save() -> void:
	var sim := town()
	var wid := wh_id(sim)
	var w: Dictionary = sim.warehouses.buildings[wid]
	var ref := Warehouses.traffic_ref(wid, w)
	# (Off Logistics' books, so the warehouse has nothing to send on and
	# no truck there is taken for another job.)
	var f1 := send(sim, "flatbed", "raw")
	sim.logistics.trips.erase(f1)
	var f2 := -1
	var both := false
	for i in 6000:
		sim.tick()
		var p1 := truck_of(sim, f1)
		if f2 < 0 and p1.has("at_place") and str(p1.at_place) == ref:
			sim.traffic._due_at(p1, sim.tick_count + 3000)  # it waits out front while the next comes
			f2 = send(sim, "flatbed", "raw")
			sim.logistics.trips.erase(f2)
		var p2 := truck_of(sim, f2) if f2 >= 0 else {}
		if p2.has("at_place") and str(p2.at_place) == ref:
			both = true
			break
	_check(both, "two flatbeds stand out front of the warehouse")
	if not both:
		return
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var st: Dictionary = TrafficSim._unpack(saved.traffic)
	var extra: Array = st.extra.get(ref, [])
	var docks := extra.filter(func(e): return e.get("rear", false))
	var kerb := extra.filter(func(e): return not e.get("rear", false))
	_check(docks.size() == Warehouses.dock_xs(w).size() and kerb.size() >= 1, "its docks are saved with its place (%d), then the curb space added out front" % docks.size())
	# As the older game saved it: no docks, its added curb spaces from 1.
	var base := 1
	var first := base + docks.size()
	var where := {}
	for car in st.parked:
		if str(car.get("at_place", "")) == ref:
			if int(car.spot) >= first:
				car.spot = int(car.spot) - docks.size()
			where[car.id] = [int(car.spot), car.pos]
	st.extra[ref] = kerb
	saved.traffic = {"bin": Marshalls.variant_to_base64(st)}
	var old := CitySim.new()
	old.from_dict(saved)
	old.tick()
	var pl := old.traffic.place(ref)
	var ok := true
	for vid in where:
		var car: Dictionary = old.traffic._by_vid.get(vid, {})
		var s: Dictionary = pl.spots[where[vid][0]]
		ok = ok and car.spot == where[vid][0] and not s.get("rear", false) and (car.pos as Vector3).distance_to(where[vid][1]) < 0.01
	_check(ok and where.size() == 2, "loaded, its trucks keep their spot numbers and stand where they stood")
	var tail: Array = pl.spots.slice(pl.spots.size() - docks.size())
	_check(tail.size() == docks.size() and tail.all(func(s): return s.get("rear", false)), "the docks go on the end of its list")
	var trip := send(old, "box_truck")
	var docked := false
	for i in 4000:
		old.tick()
		var c := truck_of(old, trip)
		if c.has("dock_t"):
			docked = true
			break
	_check(docked, "and the next box truck backs up to a dock")
