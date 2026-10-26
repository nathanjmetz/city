extends SceneTree
## The title screen's backdrop, to judge the land out to the horizon.
## Run: xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 -s tools/menu_shot.gd -- OUT.png [frames] [orbit angle in radians | camera x, height above the town, z, then look-at x z]

var _menu: Node
var _frames := 0


func _initialize() -> void:
	_menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(_menu)
	var args := OS.get_cmdline_user_args()
	if args.size() > 2 and args.size() < 7:
		_menu._angle = float(args[2])


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var wait := int(args[1]) if args.size() > 1 else 400
	if args.size() > 6:
		# A look at one spot: the camera stands still there.
		_menu.set_process(false)
		_menu._cam.position = Vector3(float(args[2]), Terrain.ground_y(0.0, 0.0) + float(args[3]), float(args[4]))
		_menu._cam.look_at(Vector3(float(args[5]), Terrain.ground_y(0.0, 0.0) + 3.0, float(args[6])))
	if _frames == 2:
		for c in _menu.get_children():
			if c is CanvasLayer:
				c.visible = false
	if _frames == wait:
		root.get_texture().get_image().save_png(args[0])
		print("saved ", args[0], " (", RenderingServer.get_current_rendering_method(), "), crop table date ",
			CropCalendar.today(), " busy: ", CropCalendar.busy())
		quit()
	return false
