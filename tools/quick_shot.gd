extends SceneTree
## A picture of the bottom-left search box and recent tools.
## Run: godot -s tools/quick_shot.gd -- out.png [controls]

var _frames := 0
var _out := "quick.png"
var _hud: Hud
var _controls := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	_controls = args.size() > 1 and args[1] == "controls"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Quick Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_hud = get_first_node_in_group("pad_hud")
		if _controls:
			for c in current_scene.get_children():
				if c.has_method("_controls"):
					c.open()
					c._controls()
			return false
		for q in ["park", "school", "well"]:
			_hud.press_card(_hud.search_cards(q)[0])
		(_hud._quick.get_child(0) as Button).button_pressed = true
		_hud._search.text = "sch"
		_hud._find("sch")
	if _frames == 60:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
