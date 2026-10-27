extends SceneTree
## Pictures of the road options added to match CS2's (docs/road-options.md),
## one scene per step, in the real game.
## Run: godot -s tools/road_options_shot.gd -- <step> <out_prefix>
## Steps: oneway (the one-way boulevard and the Boulevard menu), scurve (an
## S-curve built, and the Draw tools), snap (the snap switches, Roads off),
## carfree (a street made car-free, close up and with the tool), turns (no
## left and no right turn signs at a junction, and the Traffic tools).

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
			"scurve": _scurve(sim)
			"snap": _snap(sim)
			"carfree": _car_free(sim)
			"turns": _turns(sim)
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


func _scurve(sim: CitySim) -> void:
	# A street drawn as an S-curve between two avenues, the way it's drawn:
	# start, a bend, a bend back, end.
	sim.apply({"type": "build_road", "start": [-60, 0], "ctrl": [100, 0], "end": [260, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [-60, -260], "ctrl": [100, -260], "end": [260, -260], "road": RoadStyle.Type.AVENUE})
	var tool: RoadTool = _main.find_children("*", "RoadTool", false, false)[0]
	tool.road_type = RoadStyle.Type.STREET
	tool.mode = RoadTool.Mode.SCURVE
	tool._points = [Vector3(0, 0, 0), Vector3(0, 0, -130), Vector3(200, 0, -130)]
	for curve in tool._pending_curves(Vector3(200, 0, -260)):
		tool._build(curve)
	tool._points.clear()
	_shots = [
		["menu", func():
			_aim(Vector3(100, 0, -130), 0.0, 55.0, 330.0)
			_hud._open("roads")
			tool.set_mode(RoadTool.Mode.SCURVE)],
		["close", func():
			_hud.close_all()
			_aim(Vector3(100, 0, -130), 20.0, 32.0, 120.0)],
	]


func _snap(sim: CitySim) -> void:
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [0, -100], "end": [0, -200]})
	var tool: RoadTool = _main.find_children("*", "RoadTool", false, false)[0]
	_shots = [
		["menu", func():
			_aim(Vector3(0, 0, -80), 0.0, 55.0, 260.0)
			_hud._open("roads")
			tool.set_mode(RoadTool.Mode.STRAIGHT)
			tool.set_snap("roads", false)],
	]


func _car_free(sim: CitySim) -> void:
	# A block of town streets with the middle one made car-free.
	sim.apply({"type": "build_road", "start": [-150, 0], "ctrl": [0, 0], "end": [150, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [-150, -120], "ctrl": [0, -120], "end": [150, -120]})
	for x in [-100, 0, 100]:
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, -60], "end": [x, -120]})
	var seg: int = sim.network.find_segment_near(Vector3(0, 0, -60), 1.0).seg
	sim.apply({"type": "car_free", "seg": seg, "on": true})
	var traffic: TrafficTool = _main.find_children("*", "TrafficTool", false, false)[0]
	_shots = [
		["menu", func():
			_aim(Vector3(0, 0, -60), 0.0, 55.0, 230.0)
			_hud._open("roads")
			traffic.set_mode(TrafficTool.Mode.CAR_FREE)],
		["close", func():
			traffic.set_mode(TrafficTool.Mode.NONE)
			_hud.close_all()
			_aim(Vector3(0, 0, -60), 30.0, 28.0, 45.0)],
	]


func _turns(sim: CitySim) -> void:
	# An avenue crossing a street, with no left and no right turn signs, on
	# open ground clear of the state highway.
	var o := Vector3(0, 0, -320)
	sim.apply({"type": "build_road", "start": [o.x - 200, o.z], "ctrl": [o.x, o.z], "end": [o.x + 200, o.z],
		"road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [o.x, o.z - 150], "ctrl": [o.x, o.z], "end": [o.x, o.z + 150]})
	sim.tick()
	var c := sim.network.find_node_near(o, 1.0)
	sim.apply({"type": "turn_ban", "node": c, "turn": "left", "on": true})
	sim.apply({"type": "turn_ban", "node": c, "turn": "right", "on": true})
	var traffic: TrafficTool = _main.find_children("*", "TrafficTool", false, false)[0]
	# The signs facing the drivers coming in from the west.
	var west := -1
	for wi in sim.traffic.ways_into(c):
		if sim.traffic.ways[wi].pts[0].x < o.x - 1.0:
			west = wi
	var sl := sim.traffic.stop_line(west)
	var sign_at: Vector3 = sl.pos + sl.right * (RoadStyle.half_width(RoadStyle.Type.AVENUE) + 1.2) - sl.dir * 7.0
	_shots = [
		["menu", func():
			_aim(o, 0.0, 55.0, 160.0)
			_hud._open("roads")
			traffic.set_mode(TrafficTool.Mode.NO_LEFT)],
		["close", func():
			traffic.set_mode(TrafficTool.Mode.NONE)
			_hud.close_all()
			# From up the road the drivers come in on, just past the sign.
			_aim(sign_at + Vector3(2.0, 0, 0), 250.0, 30.0, 16.0)],
	]


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _aim(at: Vector3, yaw: float, pitch: float, dist: float) -> void:
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(at)
			c.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)
