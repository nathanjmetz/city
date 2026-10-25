extends SceneTree
## Zoom test: as combined_lab.gd, then a dive from 3 km to 40 m and a sweep
## across town at 40 m, counting stutters. Combined load: the real game with a big grid town living (ScaleTown, N
## blocks), and a full stadium of fans beside it, timed together. Frame time
## includes the town's simulation, its traffic and drawing, and the crowd.
## Run: godot --resolution 1600x900 [--rendering-method gl_compatibility]
##        -s tools/scale/zoom_lab.gd -- SAVE BLOCKS FANS OUT_DIR TAG
var _main: Node
var _frames := 0
var _phase := 0
var _ms := []
var _tick_ms := []
var _res := {}
var _cam: CityCamera
func _process(d: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
		root.get_node("/root/Session").save_path = a[0]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return false
	if _main.loading:
		return false
	_frames += 1
	var sim: CitySim = _main.sim
	if _frames == 2:
		sim.apply({"type": "clear"})
		var t := Time.get_ticks_msec()
		PerfTown.build(sim, a[1])
		sim.require_utilities = false
		for i in 3000:
			sim.tick()
		print("COMBINED built %d people, %d buildings in %d s" % [sim.stats.population, sim.buildings.size(), (Time.get_ticks_msec() - t) / 1000])
		var n := int(a[2])
		if n > 0:
			var st: Node3D = load("res://tools/scale/crowd_node.gd").new()
			# Beside the town, east of the grid.
			var span: float = int(a[1]) * 140.0
			st.position = Terrain.lift(Vector3(span * 0.5 + 300.0, 0, 0))
			_main.add_child(st)
			st.build(n)
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_main.set_speed(1)
		return false
	if _frames == 3 or _frames == 2300:
		_main.set_speed(1)
		# No tour gliding the camera, no cards or panels in the way.
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CanvasLayer:
				c.visible = false
		var span: float = int(a[1]) * 140.0
		_cam.look_at_point(Vector3(span * 0.5 + 100.0, 0, 0))
		_cam.set_view(deg_to_rad(270.0), deg_to_rad(28.0), 900.0)
	# Settle until the town is drawn, then dive from 3 km to 40 m over 10 s
	# (600 frames at 60), then sweep at street level across town for 20 s.
	var span: float = int(a[1]) * 140.0
	if _frames > 2400 and _frames <= 3000:
		var t := float(_frames - 2400) / 600.0
		_cam.look_at_point(Vector3(0, 0, 0))
		_cam.set_view(deg_to_rad(45.0), deg_to_rad(lerpf(60.0, 22.0, t)), lerpf(3000.0, 40.0, t * t * (3.0 - 2.0 * t)))
	elif _frames > 3000 and _frames <= 4200:
		var t := float(_frames - 3000) / 1200.0
		_cam.look_at_point(Vector3(lerpf(-span * 0.45, span * 0.45, t), 0, lerpf(-span * 0.2, span * 0.3, t)))
		_cam.set_view(deg_to_rad(45.0 + t * 90.0), deg_to_rad(22.0), 40.0)
	if _frames > 2400 and _frames <= 4200:
		_ms.append(d * 1000.0)
	if _frames in [2550, 2800, 3000, 3300, 3900]:
		root.get_viewport().get_texture().get_image().save_png("%s/zoom_%s_%d.png" % [a[3], a[4], _frames])
	if _frames == 3000 or _frames == 4200:
		var key := "dive" if _frames == 3000 else "sweep"
		var hitch := 0
		for m in _ms:
			hitch += 1 if m > 50.0 else 0
		_ms.sort()
		var sum := 0.0
		for m in _ms:
			sum += m
		_res[key] = {"frame_avg_ms": snappedf(sum / _ms.size(), 0.1), "frame_p95_ms": snappedf(_ms[int(_ms.size() * 0.95)], 0.1),
			"frame_worst_ms": snappedf(_ms[-1], 0.1), "stutters_over_50ms": hitch}
		_ms.clear()
	if _frames == 4200:
		print("ZOOM %s %s" % [a[4], JSON.stringify(_res)])
		quit()
		return true
	return false
