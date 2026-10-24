extends SceneTree
## Public parking from the Roads menu: real stall sizes and ADA counts, the
## stalls fit the lot and each other, and drivers who can't park at their
## destination use the town's lots.
## Run: godot --headless -s tests/test_parking.gd


func _init() -> void:
	_layouts()
	_shops()
	_drivers()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _layouts() -> void:
	# The 2010 ADA Standards' table 208.2.
	var table := {1: 1, 25: 1, 26: 2, 50: 2, 75: 3, 100: 4, 101: 5, 150: 5, 200: 6, 300: 7, 400: 8, 500: 9, 600: 12}
	var wrong := []
	for n in table:
		if ParkingLots.ada_count(n) != table[n]:
			wrong.append("%d stalls: %d" % [n, ParkingLots.ada_count(n)])
	_check(wrong.is_empty(), "accessible stall counts follow ADA table 208.2 %s" % [wrong])

	for kind in Services.PARKING:
		for angled in [false, true]:
			var size: Vector2 = Services.KINDS[kind].size
			var lay := ParkingLots.layout(size, angled, kind == Services.Kind.PARKING_GARAGE)
			var name := "%s%s" % [Services.KINDS[kind].name, " (60 degree)" if lay.angled else ""]
			var ground: Array = lay.spots.filter(func(s): return int(s.level) == 0)
			var ada: Array = lay.spots.filter(func(s): return s.ada)
			var vans: Array = ada.filter(func(s): return s.van)
			_check(ada.size() >= ParkingLots.ada_count(lay.spots.size()) and vans.size() >= 1,
				"%s: %d stalls, %d accessible (%d van)" % [name, lay.spots.size(), ada.size(), vans.size()])
			# Every stall on the lot, clear of every other on the same deck.
			var boxes := []
			var bad := []
			for s in ground:
				var box := _stall_box(s)
				for q in box:
					if absf(q.x) > size.x * 0.5 + 0.01 or absf(q.y) > size.y * 0.5 + 0.01:
						bad.append("off the lot at %s" % [s.pos])
						break
				for o in boxes:
					var hit := Geometry2D.intersect_polygons(box, o)
					if not hit.is_empty() and _area(hit[0]) > 0.05:
						bad.append("overlap at %s" % [s.pos])
				boxes.append(box)
			_check(bad.is_empty(), "%s: stalls fit the lot and each other %s" % [name, bad.slice(0, 3)])
			# The way in starts at the driveway and the way out ends there.
			var gate: Vector2 = lay.gate
			var lost := []
			for s in ground:
				if s.via[0].distance_to(gate) > ParkingLots.EDGE + 0.1 or s.out[-1].distance_to(gate) > ParkingLots.EDGE + 0.1:
					lost.append(s.pos)
			_check(lost.is_empty(), "%s: every stall is reached from the driveway %s" % [name, lost.slice(0, 3)])
	var small := ParkingLots.layout(Services.KINDS[Services.Kind.PARKING_SMALL].size, true)
	_check(not small.angled, "a lot too narrow for a pair of one-way aisles stays at 90 degrees")
	var big := ParkingLots.layout(Services.KINDS[Services.Kind.PARKING_LARGE].size, true)
	var flows: Array = big.aisles.map(func(a): return a[1])
	_check(big.angled and flows.count(1) == flows.count(-1), "60 degree aisles run one way, in pairs %s" % [flows])


func _drivers() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	for i in 200:
		sim.tick()
	# A downtown lot in the middle of the shops.
	var site := []
	var placed := -1
	for at in [Vector3(30, 0, 70), Vector3(-30, 0, 70), Vector3(70, 0, 30), Vector3(70, 0, -30), Vector3(30, 0, -70)]:
		site = Services.site_near(sim.network, Services.Kind.PARKING_DOWNTOWN, at)
		if site.is_empty():
			continue
		var money := sim.economy.money
		if sim.apply({"type": "place_service", "kind": Services.Kind.PARKING_DOWNTOWN, "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z], "angled": true}):
			placed = sim.services.buildings.keys().max()
			_check(money - sim.economy.money == Services.KINDS[Services.Kind.PARKING_DOWNTOWN].cost,
				"the lot costs its build price")
			break
	_check(placed != -1, "a downtown lot fits among the shops")
	if placed == -1:
		return
	var b: Dictionary = sim.services.buildings[placed]
	# The placement hint: shops round the downtown lot are short of
	# parking; a lot among nothing but houses would sit empty.
	var down := sim.traffic.parking_need(b.pos + b.dir * Services.size_of(b).y * 0.5)
	_check(int(down.stalls) > 0, "the shops round the downtown lot are short of parking %s" % [down])
	var homes := sim.traffic.parking_need(Vector3(-1200, 0, -340))
	_check(int(homes.stalls) == 0, "a lot out in the country has no one to serve %s" % [homes])
	_check(ServiceTool.need_words(homes, 20).contains("mostly empty"), "the hint says it will sit mostly empty")
	_check(b.get("angled", false), "it keeps the 60 degree choice")
	# The town buys every parcel it paves over: no back yard (fence, yard
	# trees) is left under the stalls (Game critic round 28).
	sim.tick()
	var under := []
	for key in sim.lots:
		for piece in Geometry2D.intersect_polygons(sim.lots[key].corners, sim.services.footprint(placed)):
			if _area(piece) > 4.0:
				under.append(key)
	_check(under.is_empty(), "no lot is left under the paving %s" % [under])
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	_check(copy.services.buildings[placed].get("angled", false), "the 60 degree choice is saved")
	var t: TrafficSim = sim.traffic
	var gate: Vector3 = b.pos + b.dir * Services.size_of(b).y * 0.5
	var probe := {"ref": "probe", "door": gate}
	var early := t._parking_near(probe, 1)
	_check(early.is_empty() or str(early[0]) != "svc:%d" % placed, "nobody parks in it while it's being paved")
	if not early.is_empty():
		t._release(early[0], early[1], 1)
	sim.construction.sites.erase("svc:%d" % placed)
	var got := t._parking_near(probe, 1)
	_check(not got.is_empty() and str(got[0]) == "svc:%d" % placed, "drivers find its stalls %s" % [got])
	if not got.is_empty():
		var pl := t.place(got[0])
		_check(not pl.spots[got[1]].get("ada", false), "a driver without a placard skips the accessible stalls")
		t._release(got[0], got[1], 1)
	var with_placard := t._parking_near(probe, 16)
	_check(not with_placard.is_empty() and t.place(with_placard[0]).spots[with_placard[1]].get("ada", false),
		"a driver with a placard takes the accessible stall nearest the street")
	if not with_placard.is_empty():
		t._release(with_placard[0], with_placard[1], 16)
	# Drivers bound for the shops round it park there.
	var seen := 0
	var walks := 0
	var short := 0
	var reach := Services.size_of(b).length() * 0.5
	var circles := 0
	for i in 3000:
		sim.tick()
		# Nobody backs out of the lot, rounds the block and parks in it again
		# (Brawn watched a driver do it, bound for a shop beside the lot).
		for car in t.cars:
			if str(car.get("from_place", "")) == "svc:%d" % placed and str(car.get("to_place", "")) == "svc:%d" % placed \
					and int(car.get("circled", -1)) != int(car.trip):
				car.circled = car.trip
				circles += 1
		if i % 50 == 0:
			for car in t.parked:
				if str(car.get("at_place", "")) == "svc:%d" % placed:
					seen += 1
		# Everyone who gets out in the lot walks out by its walk to the
		# sidewalk and on to the door: nobody vanishes beside their car.
		for w in t.walkers:
			if w.pts[0].distance_to(b.pos) < reach and int(w.get("seen", -1)) != w.id:
				w.seen = w.id
				if w.len > 15.0 and w.pts[w.pts.size() - 1].distance_to(b.pos) > reach:
					walks += 1
				else:
					short += 1
	_check(seen > 0, "shoppers park in the town's lot (%d sightings)" % seen)
	_check(circles == 0, "nobody drives out of the lot only to park in it again (%d)" % circles)
	_check(Inspect.place_name(sim, "svc:%d" % placed).begins_with("Downtown"),
		"a car's card names the lot, not its id (%s)" % Inspect.place_name(sim, "svc:%d" % placed))
	_check(walks > 0 and short == 0, "drivers walk from the lot to their door (%d walks, %d cut short)" % [walks, short])
	# A driver whose car is in the lot, off to a shop beside it, walks there
	# and leaves the car parked; going home, they fetch it.
	var lot_pl := t.place("svc:%d" % placed)
	var shop_b := ""
	var best := INF
	for key in sim.lots:
		if sim.buildings.has(key) and sim.buildings[key].zone == ZoneMap.Zone.COMMERCIAL \
				and not t.place("lot:" + key).is_empty():
			var d: float = t.place("lot:" + key).door.distance_to(lot_pl.door)
			if d < best:
				best = d
				shop_b = "lot:" + key
	var pid := -1
	for id in sim.people.people:
		var person: Dictionary = sim.people.people[id]
		var c := t._vehicle_parked(int(person.car))
		if not c.is_empty() and person.at != "travel" and not c.has("pending"):
			pid = id
			break
	_check(pid != -1 and shop_b != "", "a driver with a parked car and a shop by the lot")
	if pid != -1 and shop_b != "":
		var person: Dictionary = sim.people.people[pid]
		var vid := int(person.car)
		var c := t._vehicle_parked(vid)
		var i := t._reserve(lot_pl, vid, false)
		t._release(c.at_place, c.spot, vid)
		t._park(c, lot_pl, i)
		if person.at == shop_b:
			person.at = ""  # at home, then
		var went := t.go(pid, shop_b, "shop", 50)
		var on_foot := false
		for w in t.walkers:
			if int(w.person) == pid and w.then.get("enter", "") == shop_b:
				on_foot = true
		_check(went and on_foot and str(c.get("at_place", "")) == lot_pl.ref,
			"a short hop past the lot is walked and the car stays parked (%s, %s)" % [went, on_foot])
	# Homes on the block: an extra car goes on the street out front, never in
	# the town's lot.
	var homers := 0
	for car in t.parked:
		if str(car.get("at_place", "")) == "svc:%d" % placed and str(car.get("purpose", "")) == "home":
			homers += 1
	_check(homers == 0, "nobody heading home parks in the town's lot (%d)" % homers)


## Shops park cars only in the stalls their art paints (Brawn saw cars nosed
## into the lawn and walk in front of a beauty shop): the dry run SiteLayout
## reads matches the real drawing, and no stall is under the building or
## off the lot.
func _shops() -> void:
	var differ := []
	var bad := []
	var kinds := {}
	for seed in 160:
		for w in [16.0, 22.0, 30.0]:
			var lot := {"width": w, "depth": 40.0, "corner": seed % 4 == 0}
			var plan := DenseBuilder.site_plan(seed * 7919 + 13, lot)
			var b := DenseBuilder._start(seed * 7919 + 13, lot)
			b._shop(3.9, lot, false)
			b._commit_house()
			if str(b.site) != str(plan):
				differ.append([seed, w])
			kinds[plan.stalls.size() > 0] = true
			for st in plan.stalls:
				var c: Vector2 = st[0]
				var box := Rect2(c - Vector2(1.3, 2.7), Vector2(2.6, 5.4))
				if absf(c.x) > w * 0.5 - 1.3 or c.y < 2.7:
					bad.append(["off the lot", seed, w, c])
				for m: Rect2 in HouseBuilder.last_masses:
					if m.size.y > 1.0 and m.intersects(box.grow(-0.2)):
						bad.append(["under the building", seed, w, c])
						break
	_check(differ.is_empty(), "the stalls cars use are the ones the shop art paints %s" % [differ.slice(0, 4)])
	_check(bad.is_empty(), "no shop stall is off the lot or under the building %s" % [bad.slice(0, 4)])
	_check(kinds.size() == 2, "some shops have their own stalls, some only the curb")
	# Offices: the lot out back has a drive in, stalls clear of the walls,
	# and they are the stalls cars use.
	var odiff := []
	var obad := []
	var with_lot := 0
	for seed in 80:
		for size in [[40.0, 55.0], [34.0, 45.0], [50.0, 60.0]]:
			var lot := {"width": size[0], "depth": size[1]}
			var plan := DenseBuilder.office_plan(seed * 31 + 7, lot, 2 + seed % 4)
			var built := DenseBuilder.build_office(seed * 31 + 7, 3.9, lot, 2 + seed % 4)
			var b := DenseBuilder._start(seed * 31 + 7, lot)
			b._office(3.9, b.half * 2.0, 2 + seed % 4)
			if str(b.site) != str(plan):
				odiff.append(seed)
			if not plan.stalls.is_empty():
				with_lot += 1
				if absf(plan.cut_x) > size[0] * 0.5 - 1.5:
					obad.append(["drive off the lot", seed, plan.cut_x])
			for st in plan.stalls:
				var c: Vector2 = st[0]
				var box := Rect2(c - Vector2(1.3, 2.7), Vector2(2.6, 5.4))
				if absf(c.x) > size[0] * 0.5 - 1.3 or c.y + 2.7 > size[1]:
					obad.append(["off the lot", seed, c])
				for m: Rect2 in HouseBuilder.last_masses:
					if m.size.y > 1.0 and m.grow(1.0).intersects(box):
						obad.append(["against the building", seed, c])
						break
				if absf(c.x - plan.cut_x) < 3.5 and c.y < plan.aisle_z:
					obad.append(["in the drive", seed, c])
			built.clear()
	_check(odiff.is_empty(), "office stalls cars use are the ones the art paints %s" % [odiff.slice(0, 4)])
	_check(obad.is_empty(), "office stalls sit on the lot, clear of the walls and the drive %s" % [obad.slice(0, 4)])
	_check(with_lot > 100, "most offices have a lot out back (%d of 240)" % with_lot)
	var flats := SiteLayout.for_building(ZoneMap.Zone.RESIDENTIAL, 5, {"width": 30.0, "depth": 40.0}, 3, "apartments")
	_check(flats.spots.is_empty(), "apartments with no drive drawn send residents to the curb")


## A stall's painted rectangle, a hair inside its lines.
func _stall_box(s: Dictionary) -> PackedVector2Array:
	var f: Vector2 = s.face
	var r := Vector2(-f.y, f.x) * ((ParkingLots.ADA_W if s.ada else float(s.w)) * 0.5 - 0.05)
	var c: Vector2 = s.pos
	var h := f * (ParkingLots.STALL_L * 0.5 - 0.05)
	return PackedVector2Array([c + h + r, c + h - r, c - h - r, c - h + r])


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
