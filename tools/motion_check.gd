extends SceneTree
## Checks how vehicles look while they drive, without drawing: bodies that
## overlap (parked or moving), and how fast bodies swing round (a body that
## pivots on its front bumper swings much faster than a real one).
## Run: godot --headless -s tools/motion_check.gd -- [size] [ticks]

var _t: TrafficSim


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var size: String = args[0] if args.size() > 0 else "small"
	var ticks := int(args[1]) if args.size() > 1 else 1200
	var sim := CitySim.new()
	PerfTown.build(sim, size)
	for i in 300:
		sim.tick()
	var t: TrafficSim = sim.traffic
	_t = t
	var pp := 0
	var mp := 0
	var mm := 0
	var samples := 0
	var where := {}
	for i in ticks:
		sim.tick()
		if i % 10 != 0:
			continue
		samples += 1
		var boxes := []
		for car in t.parked:
			if not car.get("hidden", false):
				boxes.append([_box(car.pos, car.face, car), false, car])
		for car in t.cars:
			var pose: Array = t.car_pose(car)
			boxes.append([_box(pose[0], pose[1], car), true, car])
		for a in boxes.size():
			for b in range(a + 1, boxes.size()):
				if _hit(boxes[a][0], boxes[b][0]):
					var moving := int(boxes[a][1]) + int(boxes[b][1])
					if moving == 0:
						pp += 1
					elif moving == 1:
						mp += 1
					else:
						mm += 1
					var k := "%s/%s %s+%s" % [_what(boxes[a]), _what(boxes[b]), boxes[a][2].get("kind", "car"), boxes[b][2].get("kind", "car")]
					where[k] = int(where.get(k, 0)) + 1
	print("samples %d  parked-parked %d  moving-parked %d  moving-moving %d" % [samples, pp, mp, mm])
	var keys := where.keys()
	keys.sort_custom(func(x, y): return where[x] > where[y])
	for k in keys.slice(0, 15):
		print("  ", k, ": ", where[k])
	quit()


func _what(b: Array) -> String:
	var car: Dictionary = b[2]
	if not b[1]:
		var pl: Dictionary = _t.place(str(car.get("at_place", "")))
		return "parked(%s)" % (pl.spots[car.spot].kind if not pl.is_empty() and car.spot < pl.spots.size() else "?")
	if car.get("j") != null:
		if int(car.j.get("node", -1)) < 0:
			return "lot path" if float(car.j.get("rev", 0.0)) <= float(car.jd) else "backing"
		return "junction"
	if car.get("lc_t", 1.0) < 1.0:
		return "lanechange"
	return "lane"


## Footprint corners on the ground, from the front bumper back.
func _box(front: Vector3, face: Vector3, car: Dictionary) -> PackedVector2Array:
	var s := VehicleTypes.spec(TrafficSim.vehicle_kind(car))
	var f := Vector2(face.x, face.z).normalized()
	var r := Vector2(-f.y, f.x) * float(s.width) * 0.45
	var p := Vector2(front.x, front.z) - f * 0.1
	var q := p - f * (float(s.len) - 0.2)
	return PackedVector2Array([p + r, p - r, q - r, q + r])


func _hit(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()
