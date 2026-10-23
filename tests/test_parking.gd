extends SceneTree
## Public parking from the Roads menu: real stall sizes and ADA counts, the
## stalls fit the lot and each other, and drivers who can't park at their
## destination use the town's lots.
## Run: godot --headless -s tests/test_parking.gd


func _init() -> void:
	_layouts()
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
	_check(b.get("angled", false), "it keeps the 60 degree choice")
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
	for i in 3000:
		sim.tick()
		if i % 50 == 0:
			for car in t.parked:
				if str(car.get("at_place", "")) == "svc:%d" % placed:
					seen += 1
	_check(seen > 0, "shoppers park in the town's lot (%d sightings)" % seen)


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
