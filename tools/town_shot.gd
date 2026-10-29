extends SceneTree
## A saved town from a chosen spot, for judging the art against photos.
## Run: godot -s tools/town_shot.gd -- town.city out.png x z yaw pitch dist
## (pass a copy of the .city: the game autosaves into it). SHOT_FRAMES sets
## when it shoots (default 200); NOSHADOW=1 turns the sun's shadows off.
## SHOT_MONTH (1-12) and SHOT_HOUR (0-24) set the sky; NOHUD=1 hides the HUD.

var _main: Node
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.get_node("Session").save_path = args[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	var args := OS.get_cmdline_user_args()
	# Again later: the town's own saved view settles in after loading.
	if _frames == 2 or _frames == 120:
		DayNight.seasons_on = false
		if OS.get_environment("NOSHADOW") != "":
			for l in _main.find_children("*", "DirectionalLight3D", true, false):
				l.shadow_enabled = false
		_main.set_speed(0)
		if OS.get_environment("SHOT_HOUR") != "":
			var month := int(OS.get_environment("SHOT_MONTH")) if OS.get_environment("SHOT_MONTH") != "" else 7
			_main.sim.set_calendar(Seasons.tick_at(SkyClock.at(month, float(OS.get_environment("SHOT_HOUR")))))
		var x := float(args[2])
		var z := float(args[3])
		for c in _main.get_children():
			if c is RoadTool:
				c.process_mode = Node.PROCESS_MODE_DISABLED
				for k in c.get_children():
					if k is Node3D:
						k.visible = false
			if c is Hud and OS.get_environment("NOHUD") != "":
				c.visible = false
			if c is CityCamera:
				c.look_at_point(Vector3(x, Terrain.ground_y(x, z), z))
				c.set_view(deg_to_rad(float(args[4])), deg_to_rad(float(args[5])), float(args[6]))
	if _frames == int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 200:
		root.get_viewport().get_texture().get_image().save_png(args[1])
		quit()
	return false
