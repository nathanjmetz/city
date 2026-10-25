extends SceneTree
## The title screen's backdrop, to judge the land out to the horizon.
## Run: xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 -s tools/menu_shot.gd -- OUT.png [frames]

var _menu: Node
var _frames := 0


func _initialize() -> void:
	_menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var wait := int(args[1]) if args.size() > 1 else 400
	if _frames == 2:
		for c in _menu.get_children():
			if c is CanvasLayer:
				c.visible = false
	if _frames == wait:
		root.get_texture().get_image().save_png(args[0])
		quit()
	return false
