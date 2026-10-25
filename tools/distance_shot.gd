extends SceneTree
## The town at the distances it's played from: opens the real game with the
## test town (PerfTown), and from each play distance saves a picture and
## records draw calls, triangles and frame time, to judge how buildings read
## past their close-up meshes (BuildingView's far blocks).
## Run: xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 -s tools/distance_shot.gd -- [size] OUT_DIR [--quality=low]
## Frame times under a software renderer are not a real PC's; the counts are.

## [name, yaw, pitch, distance]: the default camera (260 m), a neighborhood
## (450 m) and a town-wide view (800 m), as zoned and built from, over the
## test town's homes (its north-west quarter; shops line the middle).
const AIM := Vector3(-430.0, 0.0, -330.0)
const VIEWS := [["play260", 35.0, 50.0, 260.0], ["play450", 35.0, 45.0, 450.0], ["play800", 35.0, 50.0, 800.0]]

var _main: Node
var _frames := 0
var _view := -1
var _view_frames := 0
var _rows := {}
var _cam: CityCamera
var _out := ""


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var args := OS.get_cmdline_user_args()
		_out = args[1] if args.size() > 1 else "."
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		PerfTown.build(sim, args[0] if args.size() > 0 else "big")
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
		_main.set_speed(0)
		# The picture is of the town: no panels, tour or status icons.
		for c in _main.get_children():
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		return false
	# Let every building go up and be merged before the first picture.
	if _frames < 60:
		return false
	if _view < 0:
		for c in _main.get_children():
			if c is BuildingView and not c.idle():
				return false
	if _view < 0:
		_next_view()
		return false
	_view_frames += 1
	if _view_frames > 40:
		var row: Dictionary = _rows[VIEWS[_view][0]]
		row.draw_calls = maxf(row.draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		row.primitives = maxf(row.primitives, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		row.objects = maxf(row.objects, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		row.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 / 30.0
	if _view_frames == 70:
		root.get_texture().get_image().save_png(_out.path_join(VIEWS[_view][0] + ".png"))
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
	_cam.look_at_point(AIM)
	_cam.set_view(deg_to_rad(v[1]), deg_to_rad(v[2]), v[3])


func _finish() -> void:
	var report := {"buildings": _main.sim.buildings.size(), "views": _rows,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
	print(JSON.stringify(report, "  "))
	FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	quit()
