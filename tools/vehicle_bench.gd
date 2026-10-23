extends SceneTree
## Times TrafficView's per-frame work (placing and batching every vehicle)
## on the big test town (PerfTown), with the camera over the middle of town.
## Run: godot --headless -s tools/vehicle_bench.gd -- [size] [frames]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var size: String = args[0] if args.size() > 0 else "big"
	var frames := int(args[1]) if args.size() > 1 else 120
	var sim := CitySim.new()
	PerfTown.build(sim, size)
	for i in 600:
		sim.tick()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 300, 200)
	cam.current = true
	_view = TrafficView.new()
	_view.setup(sim.traffic, func(): return 0.5)
	root.add_child(_view)
	_sim = sim
	_frames = frames


var _view: TrafficView
var _sim: CitySim
var _frames := 0
var _f := 0


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var view := _view
	var sim := _sim
	var frames := _frames
	var t := Time.get_ticks_usec()
	for i in frames:
		view._draw_cars(1.0 / 60.0)
	var per := (Time.get_ticks_usec() - t) / float(frames) / 1000.0
	var n := 0
	for k in view._xf:
		n += view._xf[k].size()
	print("vehicles %d  drawn %d  %.3f ms/frame" % [sim.traffic.cars.size(), n, per])
	return true
