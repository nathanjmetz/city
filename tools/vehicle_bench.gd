extends SceneTree
## Times TrafficView's per-frame work (placing and batching every vehicle)
## on the big test town (PerfTown), with the camera over the middle of town.
## Run: godot --headless -s tools/vehicle_bench.gd -- [size] [frames] [ultra]
## "ultra" turns on the desktop Ultra tier and drops the camera low over a
## car, so close vehicles use the close-up models.

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
	if args.size() > 2 and args[2] == "ultra":
		_ultra = true
		var at: Vector3 = sim.traffic.car_pose(sim.traffic.cars[0], 0.0)[0] if sim.traffic.cars.size() > 0 else Vector3.ZERO
		cam.position = Terrain.lift(at) + Vector3(0, 25, 30)
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
var _ultra := false


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	if _ultra:
		# After the Quality autoload's own _ready, which would replace it.
		var q := GraphicsQuality.new()
		q.active = true
		q.tier = GraphicsQuality.ULTRA
		GraphicsQuality.current = q
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
	var close := 0
	for k in view._xf:
		if k.ends_with("2"):
			close += view._xf[k].size()
	print("vehicles %d  drawn %d  close-up %d  %.3f ms/frame" % [sim.traffic.cars.size(), n, close, per])
	return true
