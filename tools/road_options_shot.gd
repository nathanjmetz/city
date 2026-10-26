extends SceneTree
## Pictures of the road options added to match CS2's (docs/road-options.md),
## one scene per step, in the real game.
## Run: godot -s tools/road_options_shot.gd -- <step> <out_prefix>
## Steps: oneway (the one-way boulevard and the Boulevard menu).

var _main: Node
var _hud: Hud
var _frames := 0
var _shots := []  # [file suffix, Callable that sets the scene up]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var step: String = args[0] if args.size() > 0 else "oneway"
	var out: String = args[1] if args.size() > 1 else "road_options"
	var sim: CitySim = _main.sim
	if _frames == 2:
		sim.apply({"type": "clear"})
		sim.economy.money = 50_000_000
		for c in _main.get_children():
			if c is Hud:
				_hud = c
		_hud.close_all()
		# Midday, paused, and no tour moving the camera.
		sim.tick_count += 360
		_main.set_speed(0)
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		match step:
			"oneway": _oneway(sim)
		if not _shots.is_empty():
			_shots[0][1].call()
	# Each shot gets 90 frames to settle, then is saved and the next set up.
	if _frames >= 60 and (_frames - 60) % 90 == 0:
		var k := (_frames - 60) / 90
		if k < _shots.size():
			_save("%s_%s.png" % [out, _shots[k][0]])
		if k + 1 < _shots.size():
			_shots[k + 1][1].call()
		else:
			quit()
	return false


func _oneway(sim: CitySim) -> void:
	var big := RoadStyle.Type.BOULEVARD_ONEWAY
	# A one-way boulevard with an avenue and two streets across it.
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -150], "end": [0, -300], "road": big})
	sim.apply({"type": "build_road", "start": [-120, -100], "ctrl": [0, -100], "end": [120, -100], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [-120, -200], "ctrl": [0, -200], "end": [120, -200], "road": RoadStyle.Type.STREET})
	_shots = [
		["menu", func():
			_aim(Vector3(0, 0, -150), 30.0, 45.0, 230.0)
			_hud._open("roads")
			_hud._pick_road(big)
			_hud._kinds_open = true
			_hud._sync()],
		["close", func():
			_hud.close_all()
			_aim(Vector3(0, 0, -135), 25.0, 30.0, 45.0)],
	]


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _aim(at: Vector3, yaw: float, pitch: float, dist: float) -> void:
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(at)
			c.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)
