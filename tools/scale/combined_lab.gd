extends SceneTree
## Combined load: the real game with a big grid town living (ScaleTown, N
## blocks), and a full stadium of fans beside it, timed together. Frame time
## includes the town's simulation, its traffic and drawing, and the crowd.
## Run: godot --resolution 1600x900 [--rendering-method gl_compatibility]
##        -s tools/scale/combined_lab.gd -- SAVE BLOCKS FANS OUT_DIR TAG
## SAVE is a throwaway save path: never a real town (it is cleared).
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
		# No tour gliding the camera, no cards or panels in the way.
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CanvasLayer:
				c.visible = false
		var span: float = int(a[1]) * 140.0
		_cam.look_at_point(Vector3(span * 0.5 + 100.0, 0, 0))
		_cam.set_view(deg_to_rad(270.0), deg_to_rad(28.0), 900.0)
	# Settle until the town is drawn, then time 600 frames at 1x, then 600 at 4x.
	if _frames == 2400:
		Perf.reset()
	if _frames > 2400 and _frames <= 3000 or _frames > 3200 and _frames <= 3800:
		_ms.append(d * 1000.0)
		var tk: Dictionary = Perf.stats.get("sim.tick", {})
		_tick_ms.append(float(tk.get("max", 0.0)))
	if _frames == 3000 or _frames == 3800:
		_ms.sort()
		var sum := 0.0
		for m in _ms:
			sum += m
		var key := "1x" if _frames == 3000 else "4x"
		var parts := {}
		for k in Perf.stats:
			parts[k] = snappedf(float(Perf.stats[k].sum) / 600.0, 0.1)
		var ks := parts.keys()
		ks.sort_custom(func(x, y): return parts[x] > parts[y])
		var top := {}
		for k in ks.slice(0, 10):
			top[k] = parts[k]
		_res[key] = {"frame_avg_ms": snappedf(sum / _ms.size(), 0.1), "frame_p95_ms": snappedf(_ms[int(_ms.size() * 0.95)], 0.1),
			"frame_worst_ms": snappedf(_ms[-1], 0.1), "fps": snappedf(1000.0 / (sum / _ms.size()), 0.1), "per_frame_ms": top}
		_ms.clear()
		if _frames == 3000:
			root.get_viewport().get_texture().get_image().save_png("%s/combined_%s.png" % [a[3], a[4]])
			_main.set_speed(3)
			Perf.reset()
	if _frames == 3800:
		_res["population"] = sim.stats.population
		_res["mem_mb"] = OS.get_static_memory_usage() / 1048576
		_res["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576
		print("COMBINED %s %s" % [a[4], JSON.stringify(_res)])
		quit()
		return true
	return false
