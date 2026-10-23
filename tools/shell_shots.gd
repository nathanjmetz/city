extends SceneTree
## Pictures of the game shell for checking the look.
## Run: godot -s tools/shell_shots.gd -- menu|together|online|neighbor|neighborhood|pause out.png

var _frames := 0
var _mode := "menu"
var _out := "shot.png"
var _friend: RegionClient


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "menu"
	_out = args[1] if args.size() > 1 else "shot.png"
	if _mode in ["online", "neighbor", "neighborhood"]:
		_start_online.call_deferred()
	elif _mode == "pause":
		(func(): root.get_node("Session").new_city("Shots")).call_deferred()
	else:
		change_scene_to_file("res://scenes/menu.tscn")


func _start_online() -> void:
	var session := root.get_node("Session")
	session.profile.name = "Brawn"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://hosted-region.json"))
	var code: String = session.host_region(19580)
	var c: RegionClient = session.join_region("ws://127.0.0.1:19580", code)
	c.requests_changed.connect(func():
		for n in c.requests:
			c.approve(n, true))
	c.joined.connect(func():
		# A friend joins too and says hello.
		_friend = RegionClient.new()
		root.add_child(_friend)
		_friend.joined.connect(func():
			var fs := _friend.my_sim()
			fs.apply_now({"type": "build_grid", "a": [-150, -100], "b": [150, -100], "c": [150, 120], "block": 80})
			for x in range(-150, 151, 20):
				for z in range(-100, 121, 20):
					fs.apply_now({"type": "paint_zone", "center": [x, z], "radius": 14, "zone": 1})
			_friend.send_town(true)
			_friend.send_chat("Hey! I started my town just east of yours")
			_friend.send_cursor(c.region.cities[c.my_city].origin + Vector2(60, 40)))
		_friend.join("ws://127.0.0.1:19580", code, "friend-1", "Sam")
		session.enter_region())


func _process(_delta: float) -> bool:
	_frames += 1
	if _mode == "neighbor" and _frames == 700:
		var main := current_scene
		for n in main.get_children():
			if n is CityCamera:
				var rv: RegionView = main.get_children().filter(func(x): return x is RegionView)[0]
				var target := rv.city_position(_friend.my_city)
				if OS.get_cmdline_user_args().size() > 2:
					# A wide view between the two cities, to see the city line.
					target *= 0.5
					n.fly_to(target)
					n._goal_dist = float(OS.get_cmdline_user_args()[2])
				else:
					n.fly_to(target)
	if _mode == "pause" and _frames in [100, 120, 130, 140, 150, 160]:
		# Escape puts the road tool down, then with nothing to close opens the pause menu.
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		root.push_input(esc)
	if _mode == "neighborhood" and _frames == 600:
		# The Neighborhood tool in hand, pointing at open land.
		for n in current_scene.get_children():
			if n is Hud:
				n.neighborhood_tool.set_kind("found")
	if _mode == "online" and _frames == 860 and "open" in OS.get_cmdline_user_args():
		# The region chat opened from its top bar button.
		for n in current_scene.get_children():
			if n is CanvasLayer and n.has_method("make_button"):
				n._set_open(true)
	if _mode == "together" and _frames == 5:
		current_scene.call("_show", "code")
	if _frames == (900 if _mode in ["online", "neighbor", "neighborhood"] else 180 if _mode == "pause" else 60):
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
