extends SceneTree
## A picture of the pause menu's Audio page, for checking the look.
## Run: godot -s tools/audio_shot.gd -- out.png

var _frames := 0
var _out := "audio.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "audio.png"
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
	if _frames == 120:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
