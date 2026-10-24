extends SceneTree
## The woods at overview heights, where the drawn trees give way to the
## ground's painted canopy (WildView / TreeField / TerrainView): one picture
## per view, to judge the ring where they meet.
## Run: xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 -s tools/woods_shot.gd -- OUT_DIR [--quality=low]

## [name, yaw, pitch, distance]: a neighborhood view, a town-wide view and
## a high one, as Brawn plays at (2026-10-24).
const VIEWS := [["woods700", 200.0, 35.0, 700.0], ["woods1200", 200.0, 38.0, 1200.0], ["woods2000", 200.0, 40.0, 2000.0],
	["street55", 120.0, 12.0, 160.0]]

var _main: Node
var _frames := 0
var _view := -1
var _view_frames := 0
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
		_out = OS.get_cmdline_user_args()[0]
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is CanvasLayer or c is LotAlerts:
				c.visible = false
		_main.set_speed(0)
		return false
	if _frames < 30:
		return false
	if _view < 0:
		_next_view()
		return false
	_view_frames += 1
	# Woods stream in a few chunks a frame.
	if _view_frames == 240:
		root.get_texture().get_image().save_png(_out.path_join(VIEWS[_view][0] + ".png"))
		_next_view()
	return false


func _next_view() -> void:
	_view += 1
	_view_frames = 0
	if _view >= VIEWS.size():
		quit()
		return
	var v: Array = VIEWS[_view]
	_cam.set_view(deg_to_rad(v[1]), deg_to_rad(v[2]), v[3])
