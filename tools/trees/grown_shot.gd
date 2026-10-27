extends SceneTree
## The real game, looking at the woods near the start from close, middle
## and far, with the grown trees on and off: pictures of each, and how long
## frames took. Run in a window:
##   godot --resolution 1600x900 -s tools/trees/grown_shot.gd -- OUT_DIR [MONTH]
## MONTH (as Seasons counts, 6.5 = mid July) moves the clock: 9.6 for fall
## colour, 0.5 for winter.

## [name, yaw, pitch, distance]
const VIEWS := [["close", 200.0, 14.0, 60.0], ["street", 120.0, 12.0, 160.0], ["middle", 200.0, 24.0, 260.0],
	["far", 200.0, 35.0, 700.0]]
const SETTLE := 300
const TIME := 120

var _main: Node
var _frames := 0
var _view := -1
var _phase := 0  # 0 grown on, 1 off
var _view_frames := 0
var _cam: CityCamera
var _out := ""
var _ms := []
var _res := {}


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var a := OS.get_cmdline_user_args()
		_out = a[0]
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		if a.size() > 1:
			var sim: CitySim = _main.sim
			sim.set_calendar(Seasons.tick_at(float(a[1])))
			DayNight.seasons_on = true  # whatever this computer's settings say
		_main.set_speed(0)
		return false
	if _frames < 30:
		return false
	if _view < 0:
		_next_view()
		return false
	_view_frames += 1
	if _view_frames > SETTLE and _view_frames <= SETTLE + TIME:
		_ms.append(delta * 1000.0)
	if _view_frames == SETTLE + TIME:
		var name: String = VIEWS[_view][0] + ("_grown" if _phase == 0 else "_cards")
		root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
		_ms.sort()
		var sum := 0.0
		for m in _ms:
			sum += m
		var g: GrownTrees = _grown()
		_res[name] = {"avg_ms": snappedf(sum / _ms.size(), 0.01), "p95_ms": snappedf(_ms[int(_ms.size() * 0.95)], 0.01),
			"grown": g.stats() if g else {}}
		_ms.clear()
		if _phase == 0:
			_phase = 1
			GrownTrees.enabled = false
			_view_frames = SETTLE - 60
		else:
			_phase = 0
			GrownTrees.enabled = true
			_next_view()
	return false


func _grown() -> GrownTrees:
	for n in _main.find_children("*", "GrownTrees", true, false):
		return n
	return null


func _next_view() -> void:
	_view += 1
	_view_frames = 0
	if _view >= VIEWS.size():
		print("GROWN_SHOT ", JSON.stringify(_res))
		quit()
		return
	var v: Array = VIEWS[_view]
	_cam.set_view(deg_to_rad(v[1]), deg_to_rad(v[2]), v[3])
