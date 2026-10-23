extends SceneTree
## Measures how smoothly driving vehicles glide on screen: runs the town the
## way the game does (ticks at 10 a second against uneven frame times) and
## checks, frame by frame, how far each moving car's front axle is drawn to
## move against how far it should have. Prints the share of frames where a
## car stalls or jumps (more than half off its speed).
## Run: godot --headless -s tools/smooth_check.gd -- [size] [frames] [old] [fast]
## "old" draws on the view's own catch-up clock instead of the game's tick
## clock (what a neighbor's town uses), to compare. "fast" runs at 4x speed.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var size: String = args[0] if args.size() > 0 else "small"
	_frames = int(args[1]) if args.size() > 1 else 600
	_old = "old" in args
	_speed = 4.0 if "fast" in args else 1.0
	_sim = CitySim.new()
	PerfTown.build(_sim, size)
	for i in 600:
		_sim.tick()
	var cam := Camera3D.new()
	root.add_child(cam)
	var at: Vector3 = _sim.traffic.car_pose(_sim.traffic.cars[0], 0.0)[0] if _sim.traffic.cars.size() > 0 else Vector3.ZERO
	cam.position = at + Vector3(0, 300, 200)
	cam.current = true
	_view = TrafficView.new()
	_view.setup(_sim.traffic, func(): return 0.0 if _old else _tick_time * CitySim.TICKS_PER_SECOND)
	root.add_child(_view)


var _view: TrafficView
var _sim: CitySim
var _frames := 0
var _f := 0
var _old := false
var _speed := 1.0
var _tick_time := 0.0


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var step := 1.0 / CitySim.TICKS_PER_SECOND
	var last := {}
	var frames := 0
	var bad := 0
	for i in _frames:
		# Uneven frames, 60 down to 20 a second, as a busy browser gives.
		var delta := rng.randf_range(1.0 / 60.0, 1.0 / 20.0)
		_tick_time += delta * _speed
		while _tick_time >= step:
			_tick_time -= step
			_sim.tick()
		_tick_time = minf(_tick_time, step)
		_view._draw_cars(delta)
		var now := {}
		for car in _sim.traffic.cars:
			var info: Array = _view._info_of(car)
			var m: TrafficView.Motion = info[9]
			if m.rev1 or m.t1 < 0.0:
				continue
			var a := _view._axle_at(m)
			now[car.id] = [a, float(car.v)]
			if i < 20 or not last.has(car.id):
				continue
			var v: float = (float(last[car.id][1]) + float(car.v)) * 0.5
			if v < 4.0 or absf(float(car.v) - float(last[car.id][1])) > 1.0:
				continue  # slow or changing speed: no steady speed to judge
			var moved := Vector2(a.x - last[car.id][0].x, a.z - last[car.id][0].z).length()
			if moved > v * delta * _speed * 4.0:
				continue  # a fresh start somewhere else
			frames += 1
			if absf(moved / (v * delta * _speed) - 1.0) > 0.5:
				bad += 1
		last = now
	print("%s clock: %d car-frames judged, %.1f%% stall or jump" % ["old" if _old else "tick", frames, 100.0 * bad / maxf(frames, 1)])
	return true
