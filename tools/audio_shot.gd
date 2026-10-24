extends SceneTree
## A picture of the pause menu's Audio page, for checking the look.
## Run: godot -s tools/audio_shot.gd -- out.png [picker]
## "picker" shows the Sound picker instead, plays option 2 of the click and
## checks it (serve web/sfx/ and set NEIGHBORS_SFX_URL to its address).

var _frames := 0
var _out := "audio.png"
var _picker := false
var _menu: Node  # untyped: a -s script can't name classes that use autoloads


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "audio.png"
	_picker = args.size() > 1 and args[1] == "picker"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Audio Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var hud: Hud = current_scene.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		SoundSettings.heard("ui/road", 0.4)
		SoundSettings.heard("world/birds_day", 0.2)
		SoundSettings.heard("world/car_engine", 0.3)
		var key := InputEventKey.new()
		key.keycode = KEY_N
		key.pressed = true
		Input.parse_input_event(key)
	if _frames == 40 and _picker:
		_menu = current_scene.find_children("*", "", true, false).filter(func(n): return n.has_method("_picker"))[0]
		_menu._picker()
	if _frames == 100 and _picker:
		var p = _menu.find_children("*", "", true, false).filter(func(n): return n.has_method("_option_data"))[0]
		var row: Dictionary = p._checks["ui/click"]
		row[1].get_parent().get_child(0).pressed.emit()
		row[1].button_pressed = true
	if _frames == (220 if _picker else 120):
		if _picker:
			print("click is now ", SoundSettings.picks.get("ui/click", {}), " stream ", SoundSettings.stream("ui/click"))
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
