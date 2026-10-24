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
	# A flatbed heading back after a drop-off runs a bare deck.
	_check(VehicleModels.trailer_for("trailer_flat", {"good": "empty", "amount": 0}) == "trailer_flat_empty", "an emptied flatbed is drawn bare")
	_check(VehicleModels.trailer_for("trailer_flat", {}) == "trailer_flat_empty", "a flatbed with no cargo is drawn bare")
	_check(VehicleModels.trailer_for("trailer_flat", {"good": "steel", "amount": 1}) == "trailer_flat", "a loaded flatbed shows its load")
	_check(VehicleModels.trailer_for("trailer_box", {}) == "trailer_box", "closed trailers look the same either way")
	_check("trailer_flat_empty" in VehicleModels.mesh_keys(), "the bare flatbed has a batch")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true


## Bodies turn about their middles, not their bumpers: the rear axle runs
## in the front axle's tracks a wheelbase back, so on a 10 m corner the body
## lags the lane's direction by about 8 degrees, and is straight again once
## the rear wheels are round.
func _check_motion() -> void:
	var view := TrafficView.new()
	var m := TrafficView.Motion.new()
	var wb := 2.8
	var r := 10.0
	m.h1 = Vector3.FORWARD
	var worst_turn := 0.0
	var worst_lag := 0.0
	var last := Vector3.FORWARD
	# Straight up to the corner, a quarter circle left about (-10, 0, -20),
	# then straight on west.
	var pts := []
	for k in 40:
		pts.append([Vector3(0, 0, -k * 0.5), Vector3.FORWARD])
	for k in range(1, 63):
		var t := k / 62.0 * PI * 0.5
		pts.append([Vector3(-r + r * cos(t), 0, -20.0 - r * sin(t)), Vector3(-sin(t), 0, -cos(t))])
	for k in range(1, 70):
		pts.append([Vector3(-r - k * 0.25, 0, -30.0), Vector3.LEFT])
	var worst_slide := 0.0
	var inside := 0.0
	var outside := 0.0
	for p in pts:
		var was_rear := m.rear
		var was_axis := (m.a - m.rear).normalized()
		var h := view._steer(m, p[0], wb, wb + 1.0)
		var moved := Vector3(m.rear.x - was_rear.x, 0.0, m.rear.z - was_rear.z)
		# Against the body's mean heading over the step, as it turns.
		var mean := was_axis + (m.a - m.rear).normalized()
		if m.started and moved.length() > 0.01 and was_axis.length_squared() > 0.5:
			worst_slide = maxf(worst_slide, absf(mean.signed_angle_to(moved, Vector3.UP)))
		worst_turn = maxf(worst_turn, absf(last.signed_angle_to(h, Vector3.UP)))
		worst_lag = maxf(worst_lag, absf(h.signed_angle_to(p[1], Vector3.UP)))
		last = h
		m.heading = h
		if m.rear.z < -20.0 and m.rear.x > -r:
			var dist := Vector2(m.rear.x + r, m.rear.z + 20.0).length()
			inside = maxf(inside, r - dist)
			outside = maxf(outside, dist - r)
	# Real rear wheels roll, they don't slide: the rear axle only ever moves
	# the way the body points, and so cuts inside the front's line round a
	# corner, by r - sqrt(r^2 - wb^2) = 0.40 m here (AASHTO off-tracking).
	_check(absf(Vector2(pts[-1][0].x - m.rear.x, pts[-1][0].z - m.rear.z).length() - wb) < 0.01, "the rear axle stays a wheelbase back")
	_check(worst_slide < deg_to_rad(1.0), "the rear wheels never slide sideways (%.2f deg at most)" % rad_to_deg(worst_slide))
	_check(inside > 0.25 and inside < 0.45 and outside < 0.02, "the rear cuts inside the corner like a real car (%.2f m in, %.2f m out)" % [inside, outside])
	_check(worst_lag < deg_to_rad(18.0), "the body angles across the lane by about the steering angle, asin(wb/r) = 16 degrees (%.1f)" % rad_to_deg(worst_lag))
	_check(absf(last.signed_angle_to(Vector3.LEFT, Vector3.UP)) < 0.01, "the body is straight again after the corner")
	# A 0.25 m step on a 10 m curve turns a body about 1.4 degrees; pivoting
	# on the bumper would swing it far more at the start of the turn.
	_check(worst_turn < deg_to_rad(2.0), "the body swings round smoothly (%.2f deg a step at most)" % rad_to_deg(worst_turn))
	# A trailer follows its kingpin the same way.
	var t := TrafficView.Motion.new()
	t.h1 = Vector3.FORWARD
	var tl := 12.0
	var tslide := 0.0
	for p in pts:
		view._steer(t, p[0], 4.0, 4.0)
		var was := t.trailer
		var was_axis := (t.kp - t.trailer).normalized() if t.kp.is_finite() else Vector3.ZERO
		var back := view._trail(t, p[0], tl)
		var moved := Vector3(back.x - was.x, 0.0, back.z - was.z)
		if was_axis.length_squared() > 0.5 and moved.length() > 0.01:
			var mean := was_axis + (t.kp - t.trailer).normalized()
			tslide = maxf(tslide, absf(mean.signed_angle_to(moved, Vector3.UP)))
	_check(tslide < deg_to_rad(1.0) and absf(Vector2(pts[-1][0].x - t.trailer.x, pts[-1][0].z - t.trailer.z).length() - tl) < 0.01,
		"a trailer's axles follow the kingpin without sliding (%.2f deg)" % rad_to_deg(tslide))
	view.free()
