extends SceneTree
## The price list's window half (docs/price-list.md): the real game with a
## PerfTown grid town (N blocks) living, timed in frame windows with each
## drawing feature on, and then with it hidden (not drawn, not updated), so
## the difference is that feature's whole cost, graphics chip included.
## Also: the game's own frame timers (Perf "frame.*"), draw calls and
## triangles, at normal speed, fast speed (4x) and paused, from far (900 m)
## and from close (120 m). At the end, each view is freed in turn and the
## memory and graphics memory let go are read.
## Run: godot --resolution 1600x900 --quality high
##        -s tools/scale/price_window.gd -- SAVE BLOCKS OUT.json [short]
## SAVE is a throwaway save path: never a real town (it is cleared).
const SETTLE := 90
const WINDOW := 300
## The views to hide one at a time, by class name, and what the player
## calls them.
const FEATURES := [
	["BuildingView", "buildings (and street trees)"],
	["TrafficView", "cars and trucks"],
	["WalkerView", "people walking"],
	["WildView", "woods and wild trees"],
	["FarmView", "farm fields and crops"],
	["FarmsteadView", "farmsteads"],
	["TerrainView", "the land"],
	["RoadView", "roads"],
	["JunctionView", "traffic lights and signs at junctions"],
	["StreetSignView", "street signs"],
	["DayNight", "day and night light"],
	["CityAudio", "town sounds"],
]
## A bigger town's shorter list (with "short").
const SHORT := ["BuildingView", "TrafficView", "WalkerView", "WildView", "FarmView", "TerrainView"]

var _main: Node
var _frames := 0
var _cam: CityCamera
var _phases := []
var _pi := -1
var _pf := 0
var _ms := []
var _calls := []
var _prims := []
var _rcpu := []
var _rgpu := []
var _res := {"phases": []}
var _span := 0.0
var _done := false
var _last_us := 0
var _settled := false
## The game's telemetry starts new Perf windows (reset_window) on its own, so
## each frame's share is read as the change in each sum since last frame.
var _acc := {}
var _prev_sum := {}
var _samples := []
var _free_i := -1
var _free_wait := 0
var _free_before := []


func _process(_d: float) -> bool:
	var a := OS.get_cmdline_user_args()
	# Wall-clock frame time: the engine's delta is capped at 150 ms.
	var now_us := Time.get_ticks_usec()
	var d := (now_us - _last_us) / 1e6
	_last_us = now_us
	if _main == null:
		root.get_node("/root/Session").save_path = a[0]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return false
	if _main.loading:
		return false
	if _done:
		return _free_step(OS.get_cmdline_user_args()[2])
	_frames += 1
	var sim: CitySim = _main.sim
	if _frames == 2:
		sim.apply({"type": "clear"})
		var t := Time.get_ticks_msec()
		PerfTown.build(sim, a[1])
		sim.require_utilities = false
		for i in 3000:
			sim.tick()
		_res["build_s"] = (Time.get_ticks_msec() - t) / 1000
		_res["population"] = sim.stats.population
		_res["buildings"] = sim.buildings.size()
		print("WINDOW built %d people, %d buildings" % [sim.stats.population, sim.buildings.size()])
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_span = int(a[1]) * 140.0
		_main.set_speed(1)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		_plan()
		return false
	if _frames == 3:
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		for c in _main.get_children():
			if c is CanvasLayer:
				c.visible = false
		_view("far")
	if not _settled:
		# The town is drawn the first time: wait until the draw calls hold
		# steady (BuildingView has merged its squares), at most 8,000 frames.
		if _frames % 100 == 0:
			_samples.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			var n := _samples.size()
			if _frames >= 1500 and n >= 4:
				var lo: float = minf(minf(_samples[n - 1], _samples[n - 2]), minf(_samples[n - 3], _samples[n - 4]))
				var hi: float = maxf(maxf(_samples[n - 1], _samples[n - 2]), maxf(_samples[n - 3], _samples[n - 4]))
				_settled = hi <= lo * 1.03 + 10
			_settled = _settled or _frames >= 8000
			if _settled:
				_res["settle_frames"] = _frames
		return false
	if _pi < 0 or _pf >= _settle_for() + WINDOW:
		if _pi >= 0:
			_finish_phase()
		_pi += 1
		_pf = 0
		if _pi >= _phases.size():
			_write(a[2])
			_free_i = 0
			_main.set_speed(0)
			_res["mem_window_mb"] = OS.get_static_memory_usage() / 1048576
			_res["video_window_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576
			_res["freed"] = {}
			_done = true
			return false
		_start_phase(_phases[_pi])
	_pf += 1
	if _pf == _settle_for():
		_acc.clear()
		_prev_sum.clear()
		for k in Perf.stats:
			_prev_sum[k] = float(Perf.stats[k].sum)
		_ms.clear()
		_calls.clear()
		_prims.clear()
		_rcpu.clear()
		_rgpu.clear()
	elif _pf > _settle_for():
		_ms.append(d * 1000.0)
		for k in Perf.stats:
			var cur := float(Perf.stats[k].sum)
			var pv := float(_prev_sum.get(k, 0.0))
			_acc[k] = float(_acc.get(k, 0.0)) + (cur - pv if cur >= pv else cur)
			_prev_sum[k] = cur
		_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		_prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		var vp := root.get_viewport_rid()
		_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		_rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	return false


func _plan() -> void:
	var short := OS.get_cmdline_user_args().size() > 3 and OS.get_cmdline_user_args()[3] == "short"
	for v in ["far", "near"]:
		_phases.append({"name": v + " normal", "view": v, "speed": 1, "hide": ""})
		_phases.append({"name": v + " fast", "view": v, "speed": 3, "hide": ""})
		_phases.append({"name": v + " paused", "view": v, "speed": 0, "hide": ""})
		for f in FEATURES:
			if short and not f[0] in SHORT:
				continue
			_phases.append({"name": v + " normal, no " + f[1], "view": v, "speed": 1, "hide": f[0]})
			# A baseline after each, so drift shows and each feature is
			# compared with the baselines on either side of it.
			_phases.append({"name": v + " normal (base)", "view": v, "speed": 1, "hide": ""})


## Frames to let a phase settle: longer after the camera moves (the
## buildings near it are made and merged then).
func _settle_for() -> int:
	if _pi > 0 and _pi < _phases.size() and _phases[_pi - 1].view != _phases[_pi].view:
		return 900
	return SETTLE


func _view(v: String) -> void:
	if v == "far":
		_cam.look_at_point(Vector3(_span * 0.1, 0, 0))
		_cam.set_view(deg_to_rad(270.0), deg_to_rad(28.0), 900.0)
	else:
		# A residential street a quarter of the way in.
		_cam.look_at_point(Vector3(-_span * 0.25, 0, -_span * 0.25 + 70.0))
		_cam.set_view(deg_to_rad(250.0), deg_to_rad(22.0), 120.0)


func _node(cls: String) -> Node:
	for c in _main.get_children():
		var s = c.get_script()
		if s != null and s.get_global_name() == cls:
			return c
	return null


func _start_phase(p: Dictionary) -> void:
	for f in FEATURES:
		var n := _node(f[0])
		if n == null:
			continue
		var hide: bool = f[0] == p.hide
		if n is Node3D:
			n.visible = not hide
		n.process_mode = Node.PROCESS_MODE_DISABLED if hide else Node.PROCESS_MODE_INHERIT
	_main.set_speed(p.speed)
	if _pi == 0 or _phases[_pi - 1].view != p.view:
		_view(p.view)


func _finish_phase() -> void:
	var p: Dictionary = _phases[_pi]
	var ms := _ms.duplicate()
	ms.sort()
	var sum := 0.0
	for m in ms:
		sum += m
	var parts := {}
	for k in _acc:
		if k.begins_with("frame.") or k.begins_with("sim.") and k.count(".") == 1:
			parts[k] = snappedf(float(_acc[k]) / WINDOW, 0.01)
	var row := {"name": p.name, "frame_avg_ms": snappedf(sum / ms.size(), 0.1),
		"frame_p95_ms": snappedf(ms[int(ms.size() * 0.95)], 0.1), "frame_worst_ms": snappedf(ms[-1], 0.1),
		"fps": snappedf(1000.0 / (sum / ms.size()), 0.1), "over_50ms": ms.filter(func(x): return x > 50.0).size(),
		"draw_calls": _avg(_calls), "render_cpu_ms": snappedf(_avgf(_rcpu), 0.1), "render_gpu_ms": snappedf(_avgf(_rgpu), 0.1), "triangles_k": snappedf(_avg(_prims) / 1000.0, 1), "per_frame_ms": parts,
		"counts": Perf.counts.duplicate(), "cars": _main.sim.traffic.cars.size(), "walkers": _main.sim.traffic.walkers.size(),
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576}
	_res.phases.append(row)
	print("PHASE ", JSON.stringify(row))


func _avgf(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(a.size(), 1)


func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return snappedf(s / maxf(a.size(), 1), 1)


func _write(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(_res, "  ", false))
	f.close()


## Frees each view in turn, a few frames apart, and reads what memory and
## graphics memory it let go.
func _free_step(path: String) -> bool:
	_free_wait += 1
	if _free_wait < 10:
		return false
	_free_wait = 0
	if not _free_before.is_empty():
		var cls: String = FEATURES[_free_i - 1][0]
		_res.freed[cls] = {"mem_mb": snappedf((_free_before[0] - OS.get_static_memory_usage()) / 1048576.0, 0.1),
			"video_mb": snappedf((_free_before[1] - Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1)}
		print("FREED ", cls, " ", _res.freed[cls])
		_write(path)
		_free_before = []
	if _free_i >= FEATURES.size():
		print("WINDOW done ", path)
		quit()
		return true
	var n := _node(FEATURES[_free_i][0])
	_free_i += 1
	if n != null:
		_free_before = [OS.get_static_memory_usage(), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)]
		_main.remove_child(n)
		n.queue_free()
	return false
