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
	["pole_close", Vector3(84, 0, 250), 30.0, 14.0, 18.0],
	["walk_close", Vector3(84, 0, 225), 200.0, 9.0, 22.0],
	["corner_close", Vector3(84, 0, 205), 135.0, 18.0, 26.0],
	["chip_close", Vector3(1560, 0, 330), 30.0, 16.0, 16.0],
	["main_close", Vector3(-39, 0, 110), 160.0, 12.0, 28.0],
	["lot_close", Vector3(-120, 0, 70), 140.0, 22.0, 30.0],
	["lid_close", Vector3(84, 0, 250), 20.0, 45.0, 5.0],
	["homes_100", Vector3(200, 0, 240), 230.0, 35.0, 100.0],
	["junction_top", Vector3(84, 0, 0), 180.0, 89.0, 40.0],
	["shop_cut", Vector3(-39, 0, 128), 200.0, 24.0, 40.0],
	["shop_cut_b", Vector3(-39, 0, 128), 20.0, 24.0, 40.0],
	["rr_county", Vector3(1601, 0, 150), 60.0, 14.0, 45.0],
	["rr_county_far", Vector3(1601, 0, 150), 200.0, 22.0, 110.0],
	["rr_town", Vector3(0, 0, 67), 120.0, 16.0, 40.0],
	["rr_active", Vector3(-1608, 0, -385), 150.0, 12.0, 32.0],
	["rr_active_b", Vector3(-1608, 0, -385), 330.0, 12.0, 32.0],
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
		GradeCrossingView.shut = OS.get_environment("SHUT_GATES") != ""
		DayNight.cycle_on = false
		# Late morning in July, unless SHOT_HOUR / SHOT_MONTH say otherwise.
		var month := float(OS.get_environment("SHOT_MONTH")) if OS.get_environment("SHOT_MONTH") != "" else 7.0
		var hour := float(OS.get_environment("SHOT_HOUR")) if OS.get_environment("SHOT_HOUR") != "" else 11.0
		# CHIP="x0,z0,x1,z1" lays a chip-seal road there first, to look at.
		if OS.get_environment("CHIP") != "":
			var c := OS.get_environment("CHIP").split_floats(",")
			var a := Vector3(c[0], 0.0, c[1])
			var b := Vector3(c[2], 0.0, c[3])
			print("chip seal road: ", _main.sim.network.build_road(a, (a + b) * 0.5, b, RoadStyle.Type.CHIP_SEAL))
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
		# Close-ups find the nearest wooden lamp pole or manhole lid to the
		# spot (the camera's own floor is off for them).
		_cam.ignore_floor = str(t[0]).ends_with("_close")
		if t[0] == "pole_close":
			p = _nearest(p, "StreetLights", "wood")
		elif t[0] == "lid_close":
			p = _nearest(p, "RoadView", "Lids")
		print("spot ", t[0], " at ", p)
		_cam.look_at_point(Vector3(p.x, Terrain.ground_y(p.x, p.z), p.z))
		_cam.set_view(deg_to_rad(t[2]), deg_to_rad(t[3]), t[4])
		_at = _frames + 25
	return false


## The nearest instance to `p` (on the ground) in `kind`'s MultiMeshes whose
## node or key name holds `part`, or `p` itself when there is none.
func _nearest(p: Vector3, kind: String, part: String) -> Vector3:
	var best := p
	var bd := INF
	for n in _main.find_children("*", "MultiMeshInstance3D", true, false):
		var up: Node = n.get_parent()
		var owned := false
		while up != null:
			if up.get_script() != null and up.get_script().get_global_name() == kind:
				owned = true
				break
			up = up.get_parent()
		if not owned:
			continue
		var name_ok: bool = str(n.name).contains(part)
		if not name_ok and up.get("_multis") is Dictionary:
			for k in up._multis:
				if up._multis[k] == n and str(k).contains(part):
					name_ok = true
		var mm: MultiMesh = n.multimesh
		if not name_ok or mm == null:
			continue
		for i in mm.instance_count:
			var g: Vector3 = n.global_transform * mm.get_instance_transform(i).origin
			var d := Vector2(g.x - p.x, g.z - p.z).length()
			if d < bd:
				bd = d
				best = g
	return best
