extends SceneTree
## Finds trucks whose drawn body jumps or snaps round between frames, on the
## small test town: each sim tick is drawn as 6 frames, and any rig whose
## front axle moves further than it could drive, or whose body turns more
## than 12 degrees in one frame, is printed with its trip. It also measures
## rear-end slide for every vehicle: the angle between the way the rear
## axle moved and the way the body points (real tyres can't slide
## sideways, so this should stay near zero).
## Run: godot --headless -s tools/motion_probe.gd -- [ticks]
var _view: TrafficView
var _sim: CitySim
var _frac := 0.0
var _f := 0
var _prev := {}
var _hits := 0
var _moves := 0
var _slides := 0
var _worst := 0.0
var _worst_at := ""

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
				var info: Array = _view._info.get(car.id, [])
				if info.is_empty():
					continue
				var m = info[9]
				var cur := [m.a, m.heading, m.rear]
				if _prev.has(car.id) and not m.rev1:
					var p: Array = _prev[car.id]
					var dr: Vector3 = cur[2] - p[2]
					dr.y = 0.0
					if dr.length() > 0.03 and dr.length() < 2.0:
						var axis := Vector3((p[0] - p[2]).x, 0.0, (p[0] - p[2]).z).normalized() \
							+ Vector3((cur[0] - cur[2]).x, 0.0, (cur[0] - cur[2]).z).normalized()
						var slide := rad_to_deg(absf(axis.signed_angle_to(dr, Vector3.UP)))
						slide = minf(slide, 180.0 - slide)
						_moves += 1
						if slide > 3.0:
							_slides += 1
							if OS.get_environment("PROBE_DEBUG") != "" and _slides <= 25:
								print("  slide %.1f tick %d.%d id %d %s v %.2f a %.2f dr %.3f front moved %.3f j=%s d=%.1f" % [slide, t, k, car.id, TrafficSim.vehicle_kind(car), car.v, float(car.a), dr.length(), (cur[0] - p[0]).length(), str(car.get("j") != null), float(car.get("d", -1))])
						if slide > _worst:
							_worst = slide
							_worst_at = "tick %d id %d %s v %.1f j=%s" % [t, car.id, TrafficSim.vehicle_kind(car), car.v, str(car.get("j") != null)]
				if float(car.get("len", 0.0)) < 6.5:
					_prev[car.id] = cur
					continue
				if _prev.has(car.id):
					var p: Array = _prev[car.id]
					var jump: float = (cur[0] - p[0]).length()
					var off: float = rad_to_deg(absf(Vector3(m.h1.x, 0, m.h1.z).normalized().angle_to(Vector3(cur[1].x, 0, cur[1].z))))
					if off > 90.0 and _hits < 40:
						_hits += 1
						print("tick %d id %d %s body %.0f deg off its path" % [t, car.id, TrafficSim.vehicle_kind(car), off])
					var turn: float = rad_to_deg(absf((p[1] as Vector3).signed_angle_to(cur[1], Vector3.UP)))
					var lim: float = maxf(float(car.v), 2.0) * TrafficSim.DT / N * 3.0 + 0.5
					if (jump > lim or turn > 12.0) and _hits < 40:
						_hits += 1
						print("tick %d id %d kind %s v %.1f jump %.2f (lim %.2f) turn %.1f purpose %s from %s to %s state d=%.1f way=%s" % [t, car.id, TrafficSim.vehicle_kind(car), car.v, jump, lim, turn, car.get("purpose", ""), car.get("from_ref", ""), car.get("to_ref", ""), float(car.get("d", -1)), str(car.get("route", [-1])[0]) if car.has("route") else "?"])
				_prev[car.id] = cur
	print("rear slides over 3 deg: %d of %d moving frames (%.1f%%), worst %.1f deg at %s" % [_slides, _moves, 100.0 * _slides / maxf(_moves, 1), _worst, _worst_at])
	print("done hits ", _hits)
	return true
