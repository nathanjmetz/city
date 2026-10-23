extends SceneTree
## Pictures of the game controller's cursor, prompts and tool wheel.
## Run: godot -s tools/pad_shot.gd -- xbox|playstation|nintendo out.png [wheel|ring2 [menu]]

var _frames := 0
var _out := "pad.png"
var _wheel := false
var _ring2 := ""  # a menu whose second ring of tools to show
var _pad: Gamepad


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[1] if args.size() > 1 else "pad.png"
	_wheel = args.size() > 2 and args[2] == "wheel"
	if args.size() > 2 and args[2] == "ring2":
		_ring2 = args[3] if args.size() > 3 else "roads"
	_pad = Gamepad.find()
	_pad.style = {"xbox": 0, "playstation": 1, "nintendo": 2}.get(args[0] if args.size() > 0 else "xbox", 0)
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Pad Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_pad.call("_set_active", true)
		_pad.cursor = Vector2(700, 520)
		_pad.call("_move", Vector2.ZERO)
		if _ring2 != "":
			_pad.call("_wheel_picked", _ring2)
			_pad.get("_wheel").aim(Vector2(1, -0.4))
		elif _wheel:
			_pad.call("_open_wheel")
			_pad.get("_wheel").aim(Vector2(1, -0.4))
		else:
			_pad.get_tree().get_first_node_in_group("pad_hud").pad_wheel_pick("roads")
	if _frames == 32:
		_pad.get("_prompts").refresh(_pad.get_tree().get_first_node_in_group("pad_hud"), _pad.style)
	if _frames == 90:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
