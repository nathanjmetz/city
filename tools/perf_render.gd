extends SceneTree
## The drawing half of the performance benchmark: opens the real game with
## the test town (PerfTown) and records draw calls, triangles, objects and
## frame time from three camera views, against PerfBudget.RENDER.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/perf_render.gd -- [size] [out.json]
## Frame times under a software renderer are not a real PC's; the counts are.

const VIEWS := [["overview", 30.0, 55.0, 1800.0], ["neighborhood", 30.0, 40.0, 450.0], ["street", 30.0, 18.0, 120.0]]

var _main: Node
var _frames := 0
var _view := -1
var _view_frames := 0
var _rows := {}
var _cam: CityCamera


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var args := OS.get_cmdline_user_args()
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		PerfTown.build(sim, args[0] if args.size() > 0 else "small")
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_main.set_speed(1)
		_next_view()
		return false
	if _view < 0:
		return false
	_view_frames += 1
	# Let the view settle, then sample frames.
	if _view_frames > 30:
		var row: Dictionary = _rows[VIEWS[_view][0]]
		row.draw_calls = maxf(row.draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		row.primitives = maxf(row.primitives, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		row.objects = maxf(row.objects, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		row.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 / 30.0
	if _view_frames == 60:
		# --shots DIR saves each view as a picture, to check what was drawn.
		var args := OS.get_cmdline_user_args()
		var at := args.find("--shots")
		if at >= 0 and at + 1 < args.size():
			root.get_texture().get_image().save_png(args[at + 1].path_join(VIEWS[_view][0] + ".png"))
		_next_view()
	return false


func _next_view() -> void:
	_view += 1
	_view_frames = 0
	if _view >= VIEWS.size():
		_finish()
		return
	var v: Array = VIEWS[_view]
	_rows[v[0]] = {"draw_calls": 0.0, "primitives": 0.0, "objects": 0.0, "process_ms": 0.0}
	_cam.look_at_point(Vector3.ZERO)
	_cam.set_view(deg_to_rad(v[1]), deg_to_rad(v[2]), v[3])


func _finish() -> void:
	var sim: CitySim = _main.sim
	var report := {"buildings": sim.buildings.size(), "population": sim.stats.population,
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "views": _rows, "frame": {}}
	for key in Perf.stats:
		if key.begins_with("frame."):
			report.frame[key] = {"mean": Perf.mean(key), "max": Perf.stats[key].max}
	var lines := PackedStringArray()
	lines.append("Drawing: %d buildings, %.0f MB, %d nodes" % [report.buildings, report.memory_mb, report.nodes])
	for v in _rows:
		var r: Dictionary = _rows[v]
		lines.append("  %-13s draw calls %5d (%s)  triangles %8d (%s)  objects %5d (%s)" % [v,
			r.draw_calls, PerfBudget.grade(r.draw_calls, PerfBudget.RENDER.draw_calls.web),
			r.primitives, PerfBudget.grade(r.primitives, PerfBudget.RENDER.primitives.web),
			r.objects, PerfBudget.grade(r.objects, PerfBudget.RENDER.objects.web)])
	for k in report.frame:
		lines.append("  %-16s mean %.2f ms  worst %.1f ms" % [k, report.frame[k].mean, report.frame[k].max])
	print("\n".join(lines))
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	quit()
