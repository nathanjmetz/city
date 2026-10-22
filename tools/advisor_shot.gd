extends SceneTree
## Pictures of the advisor for checking the look.
## Run: godot -s tools/advisor_shot.gd -- welcome|tips out.png
## "welcome" needs a fresh user folder (no user://advisor.json).

var _frames := 0
var _mode := "welcome"
var _out := "advisor.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "welcome"
	_out = args[1] if args.size() > 1 else "advisor.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Advisor Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _mode == "tips" and _frames == 20:
		var main := current_scene
		var sim: CitySim = main.sim
		sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [140, 60], "end": [240, 60]})
		for x in range(40, 241, 10):
			sim.apply({"type": "paint_zone", "center": [x, 35], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.update_stats()
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		hud.advisor.call("_refresh")
		hud.advisor.open_panel()
	if _frames == 90:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
