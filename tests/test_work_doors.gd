extends SceneTree
## Working doors, step 3 (docs/spec-working-doors.md): factory bays, shop
## roll-ups, service garages and machine sheds. Nathan, 2026-10-29: "it
## would also help if we had working doors and garage doors. they could
## open to black, allowing things to come in and out. this could also apply
## to barns, factories, etc." Each builder logs the doors it draws; a
## plant's overhead door goes up for a truck going into or out of its bay,
## a shop's roll-up for its delivery truck, a police station's sally port
## and a bus garage's doors for their own cruisers and buses, and a farm's
## machine shed stands open in the farm months and shut in winter. The
## same town opens the same doors, tick for tick; the doors cost no trip
## anything; and the door view draws each kind going up and coming down
## near the camera at High, never at Medium.
## Run: godot --headless -s tests/test_work_doors.gd

const Docks := preload("res://tests/test_docks.gd")

var _failed := false


func _init() -> void:
	_logged()
	_sheds()
	_sheds_near()
	_bay_wait()
	var a := _town()
	var b := _town()
	_trade(a, b)
	_no_cost()
	_view(_town())
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true


## The game-day town (PerfTown small with a warehouse by the plants, as
## tests/test_docks.gd has it), with its shops grown a stage (a grown shop
## has a stockroom roll-up), its police stations grown a sally port, and a
## bus depot and a hospital with its ER out along the county road.
func _town() -> CitySim:
	var sim: CitySim = Docks.town()
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) == ZoneMap.Zone.COMMERCIAL and BuildingTypes.type_of(b) == "shop":
			b.level = 1
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if int(b.kind) == Services.Kind.POLICE:
			sim.stations.depts[id] = {"built": ["sally_port"], "fund": 0.0, "why": "", "ask": {}}
			var to := Stations._deeper(b, float(Stations.node(int(b.kind), "sally_port").grow))
			b.pos = to[0]
			b.size = to[1]
	for x in [-480.0, -400.0, 400.0, 480.0, -560.0]:
		var site := Services.site_near(sim.network, Services.Kind.BUS_DEPOT, Vector3(x, 0, -360))
		if not site.is_empty() and sim.apply({"type": "place_service", "kind": Services.Kind.BUS_DEPOT,
				"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
			var ids := sim.services.buildings.keys()
			ids.sort()
			sim.construction.sites.erase("svc:%d" % ids[-1])
			break
	for x in [480.0, -640.0, 640.0, -800.0, 800.0]:
		var site := Services.site_near(sim.network, Services.Kind.HOSPITAL, Vector3(x, 0, -360))
		if not site.is_empty() and sim.apply({"type": "place_service", "kind": Services.Kind.HOSPITAL,
				"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
			var id := _of_kind(sim, Services.Kind.HOSPITAL)
			sim.construction.sites.erase("svc:%d" % id)
			sim.healthcare.decide(sim)
			var cost: Dictionary = sim.healthcare.project_cost(sim, id, "er")
			if cost.has("rect"):
				sim.healthcare._build(sim, id, "er", cost)  # the ER and its ambulance bays
			break
	return sim


## The newest service of `kind` in `sim`, or -1.
static func _of_kind(sim: CitySim, kind: int) -> int:
	var ids := sim.services.buildings.keys().filter(func(id): return int(sim.services.buildings[id].kind) == kind)
	ids.sort()
	return ids[-1] if not ids.is_empty() else -1


## An ambulance call from the hospital to the home nearest it, as
## Healthcare sends one.
static func _ambulance(sim: CitySim) -> void:
	var id := _of_kind(sim, Services.Kind.HOSPITAL)
	if id < 0:
		return
	var door: Vector3 = sim.healthcare._door(sim, id)
	var best := ""
	var bd := INF
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			var d: float = sim.lots[key].front.distance_to(door)
			if d < bd and d > 150.0:
				bd = d
				best = key
	var f: Vector3 = sim.lots[best].front
	sim.traffic.dispatch({"ref": "hospital:%d" % id, "pos": [snappedf(door.x, 0.01), snappedf(door.z, 0.01)]},
		{"ref": "lot:" + best, "pos": [snappedf(f.x, 0.01), snappedf(f.z, 0.01)]}, "medical", {"good": "patient care"})


## What kind of service garage door `ref` ("svc:<id>") is.
static func _svc_kind(sim: CitySim, ref: String) -> String:
	var b: Dictionary = sim.services.buildings.get(int(ref.substr(4)), {})
	if b.is_empty():
		return "?"
	return {Services.Kind.HOSPITAL: "hospital", Services.Kind.BUS_DEPOT: "bus", Services.Kind.POLICE: "police"}.get(int(b.kind), "?")


## The shops in `sim` with a stockroom roll-up drawn, in order.
func _rollup_shops(sim: CitySim, doors_of: Callable) -> Array:
	var out := []
	var keys := sim.buildings.keys()
	keys.sort()
	for key in keys:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.COMMERCIAL and sim.lots.has(key) \
				and (doors_of.call("lot:" + key) as Array).any(func(d): return d[0] == "rollup"):
			out.append(key)
	return out


## The plants in `sim` with an overhead door drawn by a bay, the nearest
## the warehouse first (their trucks get there soonest).
func _bay_plants(sim: CitySim, ev: DoorEvents) -> Array:
	var out := []
	for key in sim.buildings:
		if int(sim.buildings[key].zone) != ZoneMap.Zone.INDUSTRIAL or not sim.lots.has(key):
			continue
		var pl := sim.traffic.place("lot:" + key)
		if pl.get("spots", []).any(func(s): return s.kind == "bay" and ev._bay_door("lot:" + key, s.local) >= 0):
			out.append(key)
	var w: Dictionary = sim.warehouses.buildings[Docks.wh_id(sim)]
	out.sort_custom(func(a, b): return sim.lots[a].front.distance_to(w.pos) < sim.lots[b].front.distance_to(w.pos))
	return out


## A delivery from the warehouse to shop or plant `key`, as Logistics sends one.
static func _deliver(sim: CitySim, key: String) -> void:
	var wid := Docks.wh_id(sim)
	var w: Dictionary = sim.warehouses.buildings[wid]
	var f: Vector3 = sim.lots[key].front
	sim.traffic.dispatch({"ref": "wh:%d" % wid, "pos": [snappedf(w.pos.x, 0.01), snappedf(w.pos.z, 0.01)]},
		{"ref": "lot:" + key, "pos": [snappedf(f.x, 0.01), snappedf(f.z, 0.01)]}, "goods", {"good": "goods", "amount": 1},
		"box_truck")


func _doors_of(sim: CitySim) -> Callable:
	var cache := {}
	return func(ref: String) -> Array:
		if not cache.has(ref):
			if ref.begins_with("lot:") and sim.buildings.has(ref.substr(4)):
				cache[ref] = BuildingView.doors_drawn(sim, ref.substr(4))
			elif ref.begins_with("svc:") and sim.services.buildings.has(int(ref.substr(4))):
				cache[ref] = ServiceView.doors_drawn(sim, int(ref.substr(4)))
			else:
				cache[ref] = []
		return cache[ref]


## Each builder logs the doors it draws, where it draws them; logging
## takes no random numbers, so every building is drawn as before.
func _logged() -> void:
	var sim := _town()
	var plants := 0
	var with_bays := 0
	var shops := 0
	var with_rollups := 0
	var bad := []
	var same := true
	var checked := 0
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL or not sim.lots.has(key):
			continue  # (a home's garages ride on its plan: tests/test_doors.gd)
		var doors := BuildingView.doors_drawn(sim, key)
		if int(b.zone) == ZoneMap.Zone.INDUSTRIAL:
			plants += 1
			with_bays += 1 if doors.any(func(d): return d[0] == "bay") else 0
		elif int(b.zone) == ZoneMap.Zone.COMMERCIAL and BuildingTypes.type_of(b) == "shop":
			shops += 1
			with_rollups += 1 if doors.any(func(d): return d[0] == "rollup") else 0
		for d in doors:
			var c: Vector3 = d[1]
			# Standing on the ground, inside the lot, facing level.
			if c.y - float(d[4]) * 0.5 < -0.05 or c.y - float(d[4]) * 0.5 > 1.5 or absf(c.x) > float(sim.lots[key].get("width", 20.0)) * 0.5 + 1.0 \
					or c.z < -1.0 or absf((d[2] as Vector3).y) > 0.01 or absf((d[2] as Vector3).length() - 1.0) > 0.01:
				bad.append([key, d])
		# The dry run logs the doors the drawing does.
		if not doors.is_empty() and checked < 6:
			checked += 1
			var lot: Dictionary = sim.lots[key]
			var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), Vector3(lot.front.x, 0.0, lot.front.z))
			var rng := RandomNumberGenerator.new()
			rng.seed = b.seed
			var fit := BuildingView.fit_for(sim, key, xf)
			HouseBuilder.owner_care = sim.care.tier_of(key)
			var spec := sim.families.sign_of(sim, "lot:" + key)
			var drawn := DoorLog.collect(func(): BuildingView.build_for(BuildingTypes.type_of(b), BuildingTypes.storeys(b),
				rng.randi(), lot.to_curb, fit, spec, int(b.get("units", 2)), b.get("chain", "general"), int(b.get("level", 0))))
			HouseBuilder.owner_care = 0
			same = same and str(drawn) == str(doors)
	_check(plants > 3 and with_bays * 2 >= plants, "most plants log their overhead doors (%d of %d)" % [with_bays, plants])
	# (Only a grown store's back room has one: most shops here are Main
	# Street fronts, diners and banks.)
	_check(shops > 3 and with_rollups >= 3, "grown stores log their stockroom roll-ups (%d of %d shops)" % [with_rollups, shops])
	_check(bad.is_empty(), "every door stands on the ground on its lot, facing level %s" % [bad.slice(0, 2)])
	_check(checked > 0 and same, "the dry run logs the very doors the drawing does (%d lots)" % checked)
	# Service garages: a bus garage's doors onto its yard, a sally port.
	var kinds := {}
	for id in sim.services.buildings:
		var n := ServiceView.doors_drawn(sim, id).filter(func(d): return d[0] == "bay").size()
		var k := int(sim.services.buildings[id].kind)
		kinds[k] = maxi(kinds.get(k, 0), n)
	_check(kinds.get(Services.Kind.HOSPITAL, 0) >= 2, "a hospital's ER logs its ambulance bays (%d)" % kinds.get(Services.Kind.HOSPITAL, 0))
	_check(kinds.get(Services.Kind.BUS_DEPOT, 0) >= 2, "a bus garage logs its doors onto the yard (%d)" % kinds.get(Services.Kind.BUS_DEPOT, 0))
	_check(kinds.get(Services.Kind.POLICE, 0) >= 1, "a police station's sally port logs its door (%d)" % kinds.get(Services.Kind.POLICE, 0))
	_check(kinds.get(Services.Kind.FIRE, 0) >= 2, "a fire station's apparatus doors are logged (they stay shut) (%d)" % kinds.get(Services.Kind.FIRE, 0))
	var a := CommercialBuilder.build_factory(4242, 8.0, {"width": 24.0, "depth": 40.0})
	var c := CommercialBuilder.build_factory(4242, 8.0, {"width": 24.0, "depth": 40.0})
	_check(a[0].get_faces().size() == c[0].get_faces().size(), "a plant is drawn the same with its doors logged")


## A farmstead's machine shed stands open while its machines are out (the
## tractor from spring to fall, the combine at harvest) and shut in winter;
## the shed's big door is logged where the builder draws it.
func _sheds() -> void:
	var grain := []
	for seed in 3000:
		var p := FarmsteadPlan.grow(Vector2(500.0 + seed * 41.0, 900.0), true, 0.0, seed % 256)
		if p.kind == "grain" and p.parts.any(func(q): return q.kind == "shed" or q.kind == "quonset"):
			grain.append(p)
		if grain.size() >= 10:
			break
	var oct := 0
	var jan := 0
	var logged := 0
	var kinds := {}
	for p in grain:
		oct += 1 if not FarmsteadParked.sheds_out(p, 10).is_empty() else 0
		jan += FarmsteadParked.sheds_out(p, 1).size()
		var b := FarmBuilder.county(p)
		for i in b.steps():
			b.step(i)
		FarmsteadParked.month = 10
		var open := FarmsteadNear._sheds_open(p, b.get_meta("door_log", []))
		logged += 1 if not open.is_empty() else 0
		for d in open:
			kinds[d[0]] = true
	_check(grain.size() >= 8, "grain farms with machine sheds (%d)" % grain.size())
	_check(oct >= grain.size() - 1, "in October their sheds stand open, the machines out (%d of %d)" % [oct, grain.size()])
	_check(jan == 0, "in January every shed is shut (%d open)" % jan)
	_check(logged >= grain.size() - 1, "the open shed's big door is the one the builder drew (%d of %d)" % [logged, grain.size()])
	_check(kinds.has("slider"), "older sheds slide their leaves aside %s" % [kinds.keys()])
	FarmsteadParked.month = 7


## A grain farm whose open shed slides its leaves in October, and where its
## close-up stands in view: [plan, anchor].
static func _slider_farm() -> Array:
	for seed in 3000:
		var p := FarmsteadPlan.grow(Vector2(500.0 + seed * 41.0, 900.0), true, 0.0, seed % 256)
		if p.kind != "grain" or FarmsteadParked.sheds_out(p, 10).is_empty():
			continue
		var b := FarmBuilder.county(p)
		for i in b.steps():
			b.step(i)
		FarmsteadParked.month = 10
		var open := FarmsteadNear._sheds_open(p, b.get_meta("door_log", []))
		FarmsteadParked.month = 7
		if open.any(func(d): return d[0] == "slider"):
			return [p, Vector3(p.at.x, Terrain.height(p.at.x, p.at.y), p.at.y)]
	return []


## Builds farm `f` close up in `near` (as FarmsteadView does, a frame at a
## time) for `month`; returns the most doors open_doors gave before the
## close-up had faded in.
static func _build_near(near: FarmsteadNear, f: Array, month: int) -> int:
	FarmsteadParked.month = month
	var early := 0
	for i in 400:
		near.update(f[1] + Vector3(0, 40, 0), [f], Vector2.ZERO, 0.05)
		var k := Vector2i(int(f[0].at.x), int(f[0].at.y))
		if near._built.has(k) and float(near._built[k].fade) < 1.0:
			early = maxi(early, near.open_doors(f[1], 150.0).size())
		if near._built.has(k) and float(near._built[k].fade) >= 1.0:
			break
	return early


## The farmstead close-up itself (FarmsteadNear, the game's own path): no
## shed door listed while it fades in; once in, the October shed's big
## door in the world where the shed stands; built again for January, none.
func _sheds_near() -> void:
	var f := _slider_farm()
	_check(not f.is_empty(), "a grain farm with an old sliding shed door")
	if f.is_empty():
		return
	var near := FarmsteadNear.new()
	near._ready()  # (outside the tree, as a test runs)
	var early := _build_near(near, f, 10)
	var open := near.open_doors(f[1], 150.0)
	var k := Vector2i(int(f[0].at.x), int(f[0].at.y))
	_check(near._built.has(k) and early == 0, "no shed door is listed while the close-up fades in (%d)" % early)
	_check(not open.is_empty() and open.all(func(e): return float(e[3]) < 0.0),
		"once in, the October shed's door is listed, to go up at its own pace (%d)" % open.size())
	var in_shed := false
	if near._built.has(k) and not open.is_empty():
		var xf: Transform3D = near._built[k].node.transform
		var local: Vector3 = xf.affine_inverse() * (open[0][2][1] as Vector3)
		for q in FarmsteadParked.sheds_out(f[0], 10):
			in_shed = in_shed or FarmsteadPlan._extent(q).grow(1.0).has_point(Vector2(local.x, local.z))
		in_shed = in_shed and (open[0][2][1] as Vector3).distance_to(xf.origin) > 1.0  # (placed, not left at the origin)
	_check(in_shed, "and it stands in the world on the shed the tractor came out of")
	near._drop_all()
	_build_near(near, f, 1)
	_check(near._built.has(k) and near.open_doors(f[1], 150.0).is_empty(), "built in January, every shed is shut")
	FarmsteadParked.month = 7
	near.free()


## Nathan, 2026-10-30, asked whether a truck leaving a factory should
## wait inside for its door: "A". It waits while the door rolls up, the
## door exactly as far up as the wait says, and pulls out as it gets all
## the way up. A truck from a save made before (no bay_t) leaves at once.
func _bay_wait() -> void:
	var sim: CitySim = Docks.town()
	var ev := DoorEvents.new(sim.traffic, sim)
	ev.doors_of = _doors_of(sim)
	var plants := _bay_plants(sim, ev)
	var wid := Docks.wh_id(sim)
	var w: Dictionary = sim.warehouses.buildings[wid]
	var to := {"ref": "wh:%d" % wid, "pos": [snappedf(w.pos.x, 0.01), snappedf(w.pos.z, 0.01)]}
	var waits := []
	var ups := []
	for n in 2:
		var key: String = plants[n]
		var f: Vector3 = sim.lots[key].front
		var trip := sim.traffic.dispatch({"ref": "lot:" + key, "pos": [snappedf(f.x, 0.01), snappedf(f.z, 0.01)]}, to,
			"goods", {"good": "goods", "amount": 1}, "box_truck")
		var car: Dictionary = Docks.truck_of(sim, trip)
		var in_bay := not car.is_empty() and car.has("at_place") \
			and TrafficSim.in_bay(sim.traffic.place(car.at_place), int(car.get("spot", -1)))
		if n == 1:
			car.erase("bay_t")  # as on a truck from a save made before
		elif not car.has("bay_t"):
			in_bay = false
		var t0: int = sim.traffic._tick
		var last := -2.0
		var out := -1
		for i in 400:
			sim.tick()
			if sim.traffic.cars.any(func(c): return c.get("trip", -1) == trip):
				out = sim.traffic._tick
				break
			var open := ev.open_near(Vector3.ZERO, 1e6)
			for k in open:
				if open[k][0] == "lot:" + key:
					last = float(open[k][3])
		waits.append([in_bay, out - t0 if out >= 0 else -1])
		ups.append(last)
	print("work doors: ticks inside before pulling out %s, door up just before %s" % [waits, ups])
	_check(waits[0][0] and waits[0][1] >= TrafficSim.BAY_WAIT and waits[0][1] <= TrafficSim.BAY_WAIT + 20,
		"a truck leaving a plant's bay waits inside about 8 s for its door (%s ticks)" % [waits[0]])
	_check(ups[0] > 0.95, "its door is all the way up as it pulls out (%.2f)" % ups[0])
	_check(waits[1][0] and waits[1][1] >= 0 and waits[1][1] < TrafficSim.BAY_WAIT,
		"one from a save made before doors leaves at once (%s ticks)" % [waits[1]])


## The same town opens the same doors, tick for tick, on every computer:
## plants' bays as trucks go in and out, shops' roll-ups for their
## deliveries, and the sally port and bus garage for their own vehicles.
func _trade(a: CitySim, b: CitySim) -> void:
	var ea := DoorEvents.new(a.traffic, a)
	ea.doors_of = _doors_of(a)
	var eb := DoorEvents.new(b.traffic, b)
	eb.doors_of = _doors_of(b)
	var shops := _rollup_shops(a, ea.doors_of)
	_check(shops.size() >= 3 and shops == _rollup_shops(b, eb.doors_of), "shops with roll-ups (%d)" % shops.size())
	var plants := _bay_plants(a, ea).slice(0, 4)
	_check(plants.size() >= 2 and plants == _bay_plants(b, eb).slice(0, 4), "plants with a door by a bay (%d)" % plants.size())
	var seen := {}  # kind -> times seen
	var apart := -1
	for i in 6000:
		if i % 300 == 10 and not shops.is_empty():
			for s in [a, b]:
				_deliver(s, shops[(i / 300) % shops.size()])
				_deliver(s, plants[(i / 300) % plants.size()])
		if i % 300 == 150:
			for s in [a, b]:
				_ambulance(s)
		a.tick()
		b.tick()
		var oa := ea.open_near(Vector3.ZERO, 1e6)
		var ob := eb.open_near(Vector3.ZERO, 1e6)
		if apart < 0 and _canon(oa) != _canon(ob):
			apart = i
		for key in oa:
			var ref: String = oa[key][0]
			var k := "%s %s" % [ref.get_slice(":", 0), oa[key][2][0]]
			seen[k] = seen.get(k, 0) + 1
			if ref.begins_with("svc:"):
				k = "garage " + _svc_kind(a, ref)
				seen[k] = seen.get(k, 0) + 1
		if seen.get("lot bay", 0) > 100 and seen.get("lot rollup", 0) > 10 and seen.has("garage hospital") \
				and seen.has("garage bus") and i > 1500:
			break
	print("work doors: ticks open by kind %s" % seen)
	_check(seen.get("lot bay", 0) > 100, "a plant's overhead door goes up for a truck (%d)" % seen.get("lot bay", 0))
	_check(seen.get("lot rollup", 0) > 10, "a shop's roll-up goes up for its delivery (%d)" % seen.get("lot rollup", 0))
	for k in ["hospital", "bus"]:
		_check(seen.get("garage " + k, 0) > 0, "the %s garage's door goes up for its own vehicle (%d)" % [k, seen.get("garage " + k, 0)])
	_check(not seen.has("garage ?"), "no other service's door opens")
	_check(apart < 0, "the same town opens the same doors, tick for tick" + ("" if apart < 0 else " (apart at %d)" % apart))


static func _canon(open: Dictionary) -> Array:
	var keys := open.keys()
	keys.sort()
	return keys.map(func(k): return [k, snappedf(float(open[k][3]), 1e-6)])


## Doors are looks only: a town watched by the door events runs exactly as
## one that isn't.
func _no_cost() -> void:
	var a := _town()
	var b := _town()
	var ev := DoorEvents.new(a.traffic, a)
	ev.doors_of = _doors_of(a)
	for i in 1500:
		a.tick()
		b.tick()
		ev.open_near(Vector3.ZERO, 1e6)
	_check(a.economy.money == b.economy.money and a.traffic._next_trip == b.traffic._next_trip
		and a.traffic.cars.size() == b.traffic.cars.size(),
		"watching the doors changes no money and no trip (%d, %d trips)" % [a.economy.money, a.traffic._next_trip])


## The door view: at High each kind is drawn going up and coming down,
## watched from 40 m over it as a player would; at Medium nothing moves.
## Prints what a frame of it costs (a measurement, not a check: CI's
## machines vary).
func _view(sim: CitySim) -> void:
	var was: Dictionary = GraphicsQuality.budget
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.HIGH)
	var view := DoorView.new()
	view.setup(sim.traffic, sim, func(_c, _l): return false, func(key: String):
		var lot: Dictionary = sim.lots[key]
		var xf := SiteLayout.frame(lot)
		xf.origin.y = Terrain.base_y(lot.pos.x, lot.pos.z)
		return xf)
	# A farmstead built close up in October, its shed open; it goes when
	# the camera leaves (its close-up fades out and the shed shuts).
	var f := _slider_farm()
	var near := FarmsteadNear.new()
	near._ready()  # (outside the tree, as a test runs)
	_build_near(near, f, 10)
	var keep := [true]
	view.sites(_doors_of(sim), func(id: int):
		var b: Dictionary = sim.services.buildings[id]
		return Transform3D(Basis.looking_at(b.dir, Vector3.UP), b.pos), near.open_doors)
	view._ready()
	var first_up := -1.0
	var before := {}
	var shops := _rollup_shops(sim, view.events.doors_of)
	var plants := _bay_plants(sim, view.events).slice(0, 4)
	var done := {}  # kind -> how far up it got before it came back down
	var target := ""
	var kind := ""
	var peak := 0.0
	var since := 0
	var eye := Vector3(0, 40, 0)
	var us := 0
	var frames := 0
	var most := 0
	var mid_slide := false
	for i in 9000:
		if i % 300 == 10 and not shops.is_empty():
			_deliver(sim, shops[(i / 300) % shops.size()])
			_deliver(sim, plants[(i / 300) % plants.size()])
		sim.tick()
		near.update(f[1] + Vector3(0, 40, 0), [f] if keep[0] else [], Vector2.ZERO, 0.1)
		var open := view.events.open_near(Vector3.ZERO, 1e6)
		var started := open.keys().filter(func(k): return not before.has(k))
		before = open
		if target == "":
			# Fly over to a door just starting up somewhere, of a kind not
			# yet seen (one already part way up is shown from shut).
			for key in started:
				var k: String = "%s %s" % [str(open[key][0]).get_slice(":", 0), open[key][2][0]]
				var xf = view._xf(str(open[key][0]))
				if k in ["lot bay", "svc bay", "lot rollup", "farm slider"] and not done.has(k) and xf != null:
					target = key
					kind = k
					peak = 0.0
					since = i
					eye = (xf as Transform3D) * (open[key][2][1] as Vector3) + Vector3(0, 40, 0)
					break
		var t0 := Time.get_ticks_usec()
		view.step(eye)
		us += Time.get_ticks_usec() - t0
		frames += 1
		most = maxi(most, view.drawn)
		if target == "":
			continue
		if view._shown.has(target):
			var u: float = view._shown[target][0]
			if kind == "farm slider" and first_up < 0.0:
				first_up = u
			peak = maxf(peak, u)
			if kind == "farm slider" and peak >= 1.0:
				keep[0] = false  # the camera leaves: the close-up fades out
				if u > 0.2 and u < 0.8 and view._panels.multimesh.visible_instance_count >= 2 \
						and view._cards.multimesh.visible_instance_count >= 1:
					mid_slide = true
		elif peak > 0.0:
			if peak > 0.5:
				done[kind] = peak
			target = ""
		elif i - since > 600:
			target = ""  # its building isn't drawn here: another
		if done.size() >= 4:
			break
	print("work doors: a frame of the door view took %.3f ms on average (%d frames, at most %d doors); up and down again: %s"
		% [us / 1000.0 / frames, frames, most, done])
	for k in ["lot bay", "svc bay", "lot rollup", "farm slider"]:
		_check(done.has(k), "a %s door goes up and comes back down (%.2f up)" % [k, done.get(k, 0.0)])
	_check(mid_slide, "a shed's leaves slide back together over the dark shed")
	_check(first_up >= 0.0 and first_up < 0.2, "a shed coming into view slides open from shut, never pops in open (%.2f)" % first_up)
	_check(most <= int(GraphicsQuality.knob("doors", 0)), "no more doors than High allows (%d)" % most)
	_check(done.get("svc bay", 0.0) > 0.9, "a service garage's fast door is all the way up as its vehicle goes by (%.2f)" % done.get("svc bay", 0.0))
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.MEDIUM)
	for i in 50:
		sim.tick()
		view.step(eye)
	_check(view.drawn == 0 and view._cards.multimesh.visible_instance_count == 0, "at Medium no door moves")
	GraphicsQuality.budget = was
	view.free()
	near.free()
