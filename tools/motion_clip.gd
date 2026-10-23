extends SceneTree
## Films a vehicle driving in the real game, to check how it moves.
## Picks a car about to do something worth watching (back out of a drive,
## turn at a corner) in the small test town and keeps it in the middle of
## the shot.
## Run: xvfb-run godot --rendering-driver opengl3 --fixed-fps 30
##      --write-movie out.png -s tools/motion_clip.gd -- [backout|turn|semi] [seconds] [seed]

var _main: Node
var _cam: CityCamera
var _frames := 0
var _car := {}
var _end := 0
var _what := "backout"


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == 2:
		_what = args[0] if args.size() > 0 else "backout"
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		PerfTown.build(sim, "small")
		# Late morning sun.
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		var skip := int(args[2]) if args.size() > 2 else 0
		for i in 3000:
			sim.tick()
			var car := _pick(sim.traffic)
			if not car.is_empty():
				if skip == 0:
					_car = car
					break
				skip -= 1
				for k in 40:
					sim.tick()
		call_group("first_town_tour", "stop")
		print("filming car ", _car.get("id", -1), " ", _car.get("kind", ""))
		_end = _frames + int(float(args[1] if args.size() > 1 else "10") * 30.0)
		_main.set_speed(1)
		if not _car.is_empty():
			var p: Vector3 = sim.traffic.car_pose(_car)[0]
			_cam.look_at_point(p)
			_cam.set_view(deg_to_rad(35.0), deg_to_rad(52.0), 26.0 if _what != "semi" else 50.0)
		return false
	if _frames < 2:
		return false
	if not _car.is_empty():
		var sim: CitySim = _main.sim
		if sim.traffic.cars.has(_car):
			var p: Vector3 = sim.traffic.car_pose(_car)[0]
			_cam.look_at_point(_cam.focus().lerp(p, 0.05))
	return _frames >= _end


func _pick(t: TrafficSim) -> Dictionary:
	for car in t.cars:
		var c = car.get("j")
		if _what != "semi" and not TrafficSim.vehicle_kind(car) in ["sedan", "pickup", "suv", "crossover", "minivan", "hatchback"]:
			continue
		match _what:
			"backout":
				if c != null and float(c.get("rev", 0.0)) > 0.0 and car.jd < 0.5:
					return car
			"turn":
				if c != null and c.get("node", -1) >= 0 and int(c.turn) != TrafficSim.Turn.STRAIGHT and car.jd < 0.5 \
						and not VehicleModels.ARTIC.has(TrafficSim.vehicle_kind(car)):
					return car
			"semi":
				if c != null and c.get("node", -1) >= 0 and int(c.turn) != TrafficSim.Turn.STRAIGHT \
						and VehicleModels.ARTIC.has(TrafficSim.vehicle_kind(car)):
					return car
	return {}
