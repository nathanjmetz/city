extends SceneTree
## Run: godot --headless -s tests/test_vehicles.gd

func _init() -> void:
	# Every model builds at both levels of detail, and far ones are lighter.
	for key in VehicleModels.mesh_keys():
		var near := VehicleModels.build(key, 0).get_faces().size() / 3
		var far := VehicleModels.build(key, 1).get_faces().size() / 3
		_check(near > 20 and far > 0 and far < near, "%s builds (%d / %d triangles)" % [key, near, far])
	# Each work truck reads as itself, even far off and from above (a line of
	# ambulances read as box trucks, look check 2026-10-25): the ambulance
	# wears its red band and Star of Life at both levels of detail, the box
	# truck's box takes its fleet's colour, and they come in more than white.
	for lod in [0, 1]:
		var amb := _colors(VehicleModels.build("ambulance", lod))
		_check(_has(amb, VehicleModels.EMS_RED) and _has(amb, VehicleModels.EMS_BLUE) and _has(amb, VehicleModels.BEACON_RED),
			"the ambulance has its red band, Star of Life and lights (detail %d)" % lod)
		var star_up := false
		var m := VehicleModels.build("ambulance", lod)
		var arr := m.surface_get_arrays(0)
		for i in arr[Mesh.ARRAY_COLOR].size():
			if _near(arr[Mesh.ARRAY_COLOR][i], VehicleModels.EMS_BLUE) and arr[Mesh.ARRAY_NORMAL][i].y > 0.9:
				star_up = true
		_check(star_up, "and a Star of Life on the roof, seen from the air (detail %d)" % lod)
		_check(not _has(_colors(VehicleModels.build("box_truck", lod)), VehicleModels.EMS_RED), "a box truck carries no ambulance red")
	var box_paint := 0
	var box := VehicleModels.build("box_truck", 0).surface_get_arrays(0)
	for c in box[Mesh.ARRAY_COLOR]:
		box_paint += 1 if c.a == 0.0 else 0
	_check(box_paint > 40, "the box truck's box takes its fleet colour (%d painted vertices)" % box_paint)
	var hues := {}
	for id in 200:
		hues[VehicleTypes.paint("box_truck", id).to_html()] = true
		hues["g" + VehicleTypes.paint("garbage_truck", id).to_html()] = true
	_check(hues.size() >= 8, "box and garbage trucks come in several liveries (%d)" % hues.size())
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
	_check_driveways()
	# A flatbed heading back after a drop-off runs a bare deck.
	_check(VehicleModels.trailer_for("trailer_flat", {"good": "empty", "amount": 0}) == "trailer_flat_empty", "an emptied flatbed is drawn bare")
	_check(VehicleModels.trailer_for("trailer_flat", {}) == "trailer_flat_empty", "a flatbed with no cargo is drawn bare")
	_check(VehicleModels.trailer_for("trailer_flat", {"good": "steel", "amount": 1}) == "trailer_flat", "a loaded flatbed shows its load")
	_check(VehicleModels.trailer_for("trailer_box", {}) == "trailer_box", "closed trailers look the same either way")
	_check("trailer_flat_empty" in VehicleModels.mesh_keys(), "the bare flatbed has a batch")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)

var _failed := false


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) < 0.02


static func _has(colors: Dictionary, c: Color) -> bool:
	for k in colors:
		if _near(k, c):
			return true
	return false


static func _colors(m: ArrayMesh) -> Dictionary:
	var out := {}
	for c in m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		out[c] = true
	return out

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


## Household cars aren't all shut in the garage (look critic round 0,
## 2026-10-29: "empty driveways and shop lots"): about two in three the
## simulation parks in a home's garage are drawn out on the drive in front
## of its bay, the same ones on every computer and after a load, clear of
## every other car and back from the sidewalk. Only the drawing changes:
## the simulation and its save still have them in the garage.
func _check_driveways() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	for i in 30:
		sim.tick()
	var t: TrafficSim = sim.traffic
	var saved := var_to_bytes(t.to_dict())
	var view := TrafficView.new()
	view.setup(t, func(): return 0.0)
	view._rebuild_parked()
	var drawn := {}  # x,z of every front bumper drawn
	for item in view._parked:
		drawn[_xz(item[0])] = item[0]
	var garaged := 0
	var shown := 0
	var visible := 0
	var bad_spot := []
	for car in t.parked:
		var key := _xz(Terrain.stand(car.pos))
		if not car.hidden:
			visible += 1
			continue
		var res: bool = car.at_place.begins_with("lot:") and int(sim.buildings[car.at_place.substr(4)].zone) == ZoneMap.Zone.RESIDENTIAL
		if drawn.has(key):
			bad_spot.append(car.id)  # drawn inside the garage
		var out := _xz(Terrain.stand(car.pos - car.face * TrafficView.DRIVE_OUT))
		if res and car.kind != "golf_cart":
			garaged += 1
			if drawn.has(out):
				shown += 1
				var lot: Dictionary = sim.lots[car.at_place.substr(4)]
				var mid: Vector3 = SiteLayout.frame(lot).affine_inverse() * (car.pos - car.face * (TrafficView.DRIVE_OUT + car.len * 0.5))
				if mid.z < TrafficView.DRIVE_MIN_Z:
					bad_spot.append(car.id)  # over the sidewalk
		elif drawn.has(out):
			bad_spot.append(car.id)  # a bay or deck opened up
	_check(garaged > 50, "the small town parks its household cars in their garages (%d)" % garaged)
	var share := float(shown) / maxf(garaged, 1)
	_check(share > 0.5 and share < 0.75, "about two in three of them are drawn out on the drive (%d of %d)" % [shown, garaged])
	_check(view._parked.size() >= visible + shown, "the cars on drives, at stalls and at the curb still are (%d)" % visible)
	_check(bad_spot.is_empty(), "none is drawn in a garage, a bay or over the sidewalk %s" % [bad_spot.slice(0, 5)])
	var crowded := []
	var fronts: Array = drawn.values()
	for i in fronts.size():
		for j in range(i + 1, fronts.size()):
			if Vector2(fronts[i].x - fronts[j].x, fronts[i].z - fronts[j].z).length() < 2.0:
				crowded.append(fronts[i])
	_check(crowded.is_empty(), "no two cars are drawn on top of each other %s" % [crowded.slice(0, 3)])
	_check(var_to_bytes(t.to_dict()) == saved and t.parked.all(func(c): return c.spot >= 0),
		"the simulation and its save are untouched (the cars are still in the garage there)")
	# Every computer, and the town loaded again, shows the same ones.
	var copy := CitySim.new()
	copy.from_dict(sim.to_dict())
	copy.traffic._sim = copy  # as its first tick does
	var again := TrafficView.new()
	again.setup(copy.traffic, func(): return 0.0)
	again._rebuild_parked()
	var same := again._parked.size() == view._parked.size()
	for item in again._parked:
		same = same and drawn.has(_xz(item[0]))
	_check(same, "a loaded copy draws the very same cars on the very same drives (%d)" % again._parked.size())
	# Drawn in batches of their own, filled when the camera moves.
	view._ready()
	var eye: Vector3 = fronts[0] + Vector3(0, 60, 0)
	view._reach_far = TrafficView.FAR
	view._reach_near = TrafficView.NEAR
	view._fill_parked(eye, -1.0, true)
	var in_batches := 0
	for key in view._pmm:
		for mi in view._pmm[key]:
			if mi != null:
				in_batches += mi.multimesh.visible_instance_count
	_check(in_batches == view._parked_drawn and in_batches == view._parked.size(),
		"every parked car in reach is in the batches (%d of %d)" % [in_batches, view._parked.size()])
	# Far off, every body style is drawn as its kind's one simple model, so
	# every kind with body styles has a batch for it (far sedans had none and
	# weren't drawn, 2026-10-29).
	var keys := VehicleModels.mesh_keys()
	_check(VehicleModels.VARIANTS.keys().all(func(k): return keys.has(k)), "every kind's far model has a batch")
	view.free()
	again.free()


static func _xz(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))
