extends SceneTree
## Street-level pictures of a grown town with its traffic running, for
## judging roads, markings, curbs, lots and cars against real photos.
## Several spots per run, so the town loads once.
## Run: godot -s tools/street_critic_shot.gd -- town.city OUT_DIR [--quality=ultra]
## (pass a copy of the .city: the game autosaves into it). SPOTS=name,name
## picks some of them.

## [name, look at, yaw, pitch, distance]
const SPOTS := [
	["main_40", Vector3(0, 0, 0), 30.0, 28.0, 40.0],
	["main_low", Vector3(60, 0, 4), 80.0, 12.0, 45.0],
	["corner_40", Vector3(84, 0, 40), 220.0, 35.0, 40.0],
	["side_street", Vector3(168, 0, 120), 10.0, 22.0, 45.0],
	["lot_60", Vector3(-120, 0, 70), 140.0, 40.0, 60.0],
	["town_150", Vector3(0, 0, 60), 200.0, 38.0, 150.0],
	["curb_low", Vector3(170, 0, 100), 300.0, 12.0, 30.0],
	["homes_40", Vector3(126, 0, 210), 150.0, 30.0, 40.0],
	["homes_low", Vector3(84, 0, 250), 20.0, 14.0, 42.0],
	["homes_100", Vector3(200, 0, 240), 230.0, 35.0, 100.0],
	["junction_top", Vector3(84, 0, 0), 180.0, 89.0, 40.0],
	["shop_cut", Vector3(-39, 0, 128), 200.0, 24.0, 40.0],
	["shop_cut_b", Vector3(-39, 0, 128), 20.0, 24.0, 40.0],
]

var _main: Node
var _frames := 0
var _cam: CityCamera
var _todo := []
var _spot := -1
var _at := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.get_node("Session").save_path = args[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	var only := OS.get_environment("SPOTS").split(",", false)
	for s in SPOTS:
		if only.is_empty() or s[0] in only:
			_todo.append(s)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == 2:
		DayNight.seasons_on = false
		DayNight.cycle_on = false
		# Late morning in July, unless SHOT_HOUR / SHOT_MONTH say otherwise.
		var month := float(OS.get_environment("SHOT_MONTH")) if OS.get_environment("SHOT_MONTH") != "" else 7.0
		var hour := float(OS.get_environment("SHOT_HOUR")) if OS.get_environment("SHOT_HOUR") != "" else 11.0
		_main.sim.set_calendar(Seasons.tick_at(SkyClock.at(int(month), hour)))
		# The clock jumped: the hour's workers at work, cars in the lots.
		_main.sim.people.settle(_main.sim, _main.sim.traffic)
		for c in _main.find_children("*", "CanvasLayer", true, false):
			c.visible = false
		for c in _main.get_children():
			if c is CityCamera:
				_cam = c
			if c is RoadTool:
				c.process_mode = Node.PROCESS_MODE_DISABLED
				for k in c.get_children():
					if k is Node3D:
						k.visible = false
	# Let the traffic get going before the first picture.
	var warm := int(OS.get_environment("WARM")) if OS.get_environment("WARM") != "" else 250
	if _frames < warm:
		return false
	if _spot < 0 or _frames == _at:
		if _spot >= 0:
			var s: Array = _todo[_spot]
			var out: String = args[1].path_join(s[0] + ".png")
			root.get_viewport().get_texture().get_image().save_png(out)
			print("saved ", out)
		_spot += 1
		if _spot >= _todo.size():
			quit()
			return false
		var t: Array = _todo[_spot]
		var p: Vector3 = t[1]
		_cam.look_at_point(Vector3(p.x, Terrain.ground_y(p.x, p.z), p.z))
		_cam.set_view(deg_to_rad(t[2]), deg_to_rad(t[3]), t[4])
		_at = _frames + 25
	return false
