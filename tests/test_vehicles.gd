extends SceneTree
## Run: godot --headless -s tests/test_vehicles.gd

func _init() -> void:
	# Every model builds at both levels of detail, and far ones are lighter.
	for key in VehicleModels.mesh_keys():
		var near := VehicleModels.build(key, 0).get_faces().size() / 3
		var far := VehicleModels.build(key, 1).get_faces().size() / 3
		_check(near > 20 and far > 0 and far < near, "%s builds (%d / %d triangles)" % [key, near, far])
	# Sizes are real: a semi is 72 ft, a pickup longer than a sedan.
	_check(absf(VehicleTypes.spec("semi").len - 21.9) < 0.1, "semi is 72 ft")
	_check(VehicleTypes.spec("pickup").len > VehicleTypes.spec("sedan").len, "pickup longer than sedan")
	_check(VehicleTypes.spec("nonsense") == VehicleTypes.spec("sedan"), "unknown kinds drive like a sedan")
	# Purposes give the right vehicle.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_check(VehicleTypes.for_purpose("fire", rng) == "fire_engine", "fire call sends a fire engine")
	_check(VehicleTypes.for_purpose("milk", rng) == "tanker", "milk goes by tanker")
	_check(VehicleTypes.for_purpose("livestock", rng) == "livestock_truck", "cattle go by livestock trailer")
	_check(VehicleTypes.spec("buggy").top_speed < 6.0, "a buggy goes at a horse's trot")
	_check(VehicleTypes.for_cargo({"good": "lumber"}) == "lumber_truck", "lumber leaves the mill on a flatbed")
	var wagons := 0
	for i in 200:
		if VehicleTypes.for_purpose("grain", rng, {"good": "corn"}) == "tractor_wagon":
			wagons += 1
	_check(wagons > 10 and wagons < 100, "some farmers haul corn by wagon (%d of 200)" % wagons)
	for key in ["sedan", "pickup", "school_bus"]:
		var near := VehicleModels.build(key, VehicleModels.LOD_NEAR).get_faces().size()
		var ultra := VehicleModels.build(key, VehicleModels.LOD_ULTRA).get_faces().size()
		_check(ultra > near, "%s has more detail for Ultra close-ups (%d > %d)" % [key, ultra / 3, near / 3])
	var campers := 0
	for i in 400:
		if VehicleTypes.for_purpose("visitor", rng) in ["rv", "motorhome", "pickup_camper"]:
			campers += 1
	_check(campers > 4 and campers < 60, "some visitors come camping (%d of 400)" % campers)
	_check(VehicleTypes.for_purpose("power_line", rng) in ["bucket_truck", "work_pickup"], "line crews take bucket trucks")
	_check(VehicleTypes.for_cargo({"good": "hogs"}) == "livestock_truck", "hogs ride a livestock trailer")
	_check(VehicleTypes.for_purpose("raw", rng, {"good": "logs"}) == "log_truck", "logs go on a log truck")
	_check(VehicleTypes.for_purpose("raw", rng, {"good": "ore"}) == "ore_truck", "ore goes in an end-dump")
	_check(VehicleTypes.for_purpose("fuel", rng, {"good": "crude oil"}) == "tanker", "crude oil goes by tanker")
	for p in VehicleTypes.PURPOSE:
		for k in VehicleTypes.PURPOSE[p]:
			_check(VehicleTypes.SPECS.has(k), "%s uses a real kind (%s)" % [p, k])
	# The fleet mix: pickups lead, and picking is deterministic.
	var count := {}
	rng.seed = 7
	for i in 4000:
		var k := VehicleTypes.pick(ZoneMap.Zone.RESIDENTIAL, 12, rng)
		count[k] = count.get(k, 0) + 1
	_check(count.get("pickup", 0) > count.get("sedan", 0), "pickups outnumber sedans")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 9
	b.seed = 9
	_check(VehicleTypes.pick(ZoneMap.Zone.INDUSTRIAL, 10, a) == VehicleTypes.pick(ZoneMap.Zone.INDUSTRIAL, 10, b), "pick is deterministic")
	_check(VehicleTypes.paint("school_bus", 5) == VehicleTypes.paint("school_bus", 99), "school buses are all yellow")
	_check_motion()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true


## Bodies turn about their rear wheels, not their bumpers: the rear axle
## trails the front one a wheelbase back and cuts inside on a corner (the
## AASHTO off-tracking of a car on a 10 m turn is about 0.4 m).
func _check_motion() -> void:
	var view := TrafficView.new()
	var m := TrafficView.Motion.new()
	var wb := 2.8
	var r := 10.0
	m.h1 = Vector3.FORWARD
	var worst_turn := 0.0
	var inside := r
	var last := Vector3.FORWARD
	# Straight up to the corner, then a quarter circle left about (-10, 0, -20).
	var pts := []
	for k in 40:
		pts.append(Vector3(0, 0, -k * 0.5))
	for k in range(1, 63):
		var t := k / 62.0 * PI * 0.5
		pts.append(Vector3(-r + r * cos(t), 0, -20.0 - r * sin(t)))
	for p in pts:
		var h := view._steer(m, p, wb)
		worst_turn = maxf(worst_turn, absf(last.signed_angle_to(h, Vector3.UP)))
		last = h
		m.heading = h
		if p.z < -20.0:
			inside = minf(inside, Vector2(m.rear.x + r, m.rear.z + 20.0).length())
	_check(absf(Vector2(pts[-1].x - m.rear.x, pts[-1].z - m.rear.z).length() - wb) < 0.01, "the rear axle stays a wheelbase back")
	_check(r - inside > 0.25 and r - inside < 0.6, "a car's rear wheels cut inside a 10 m turn (%.2f m)" % (r - inside))
	# A 0.25 m step on a 10 m curve turns a body about 1.4 degrees; pivoting
	# on the bumper would swing it far more at the start of the turn.
	_check(worst_turn < deg_to_rad(2.0), "the body swings round smoothly (%.2f deg a step at most)" % rad_to_deg(worst_turn))
	view.free()
