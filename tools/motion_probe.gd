extends SceneTree
## Finds trucks whose drawn body jumps or snaps round between frames, on the
## small test town: each sim tick is drawn as 6 frames, and any rig whose
## front axle moves further than it could drive, or whose body turns more
## than 12 degrees in one frame, is printed with its trip.
## Run: godot --headless -s tools/motion_probe.gd -- [ticks]
var _view: TrafficView
var _sim: CitySim
var _frac := 0.0
var _f := 0
var _prev := {}
var _hits := 0

func _initialize() -> void:
	_sim = CitySim.new()
	PerfTown.build(_sim, "small")
	for i in 300:
		_sim.tick()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 300, 200)
	cam.current = true
	_view = TrafficView.new()
	_view.setup(_sim.traffic, func(): return _frac)
	root.add_child(_view)

func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var N := 6
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[0]) if args.size() > 0 else 1500
	for t in ticks:
		_sim.tick()
		for k in N:
			_frac = float(k + 1) / N
			_view._draw_cars(TrafficSim.DT / N)
			for car in _sim.traffic.cars:
				if float(car.get("len", 0.0)) < 6.5:
					continue
				var info: Array = _view._info.get(car.id, [])
				if info.is_empty():
					continue
				var m = info[9]
				var cur := [m.a, m.heading, m.rear]
				if _prev.has(car.id):
					var p: Array = _prev[car.id]
					var jump: float = (cur[0] - p[0]).length()
					var turn: float = rad_to_deg(absf((p[1] as Vector3).signed_angle_to(cur[1], Vector3.UP)))
					var lim: float = maxf(float(car.v), 2.0) * TrafficSim.DT / N * 3.0 + 0.5
					if (jump > lim or turn > 12.0) and _hits < 40:
						_hits += 1
						print("tick %d id %d kind %s v %.1f jump %.2f (lim %.2f) turn %.1f purpose %s from %s to %s state d=%.1f way=%s" % [t, car.id, TrafficSim.vehicle_kind(car), car.v, jump, lim, turn, car.get("purpose", ""), car.get("from_ref", ""), car.get("to_ref", ""), float(car.get("d", -1)), str(car.get("route", [-1])[0]) if car.has("route") else "?"])
				_prev[car.id] = cur
	print("done hits ", _hits)
	return true
