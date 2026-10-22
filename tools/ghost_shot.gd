extends SceneTree
## Pictures of the road being drawn, near and far: the ghost road, the
## clicked-point dots and the small readout must all stay easy to see.
## Run: godot -s tools/ghost_shot.gd -- out_prefix

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "ghost"
	var hud: Hud
	for c in _main.get_children():
		if c is Hud:
			hud = c
	if _frames == 2:
		hud.close_all()
		hud._open("roads")
		hud.road_tool.set_mode(RoadTool.Mode.STRAIGHT)
		hud.road_tool._points.append(Vector3(-300, 0, 200))
		_aim(Vector3(-150, 0, 100), 20.0, 45.0, 600.0)
		root.get_viewport().warp_mouse(Vector2(1000, 350))
	if _frames == 30:
		_save(out + "_mid.png")
		hud.road_tool.set_mode(RoadTool.Mode.GRID)
		for p in [Vector3(-400, 0, 100), Vector3(-200, 0, 150)]:
			hud.road_tool._points.append(p)
		_aim(Vector3(-200, 0, 100), 20.0, 45.0, 1800.0)
	if _frames == 60:
		_save(out + "_grid_far.png")
		quit()
	return false


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _aim(at: Vector3, yaw: float, pitch: float, dist: float) -> void:
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(at)
			c.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)
