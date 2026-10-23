extends "res://tools/screenshot.gd"
## A few blocks of named streets, for checking street names and signs.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/streets_shot.gd -- out.png yaw pitch dist [x z]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0], "road": RoadStyle.Type.MAIN_STREET})
	for x in [-100, 0, 100]:
		sim.apply({"type": "build_road", "start": [x, -120], "ctrl": [x, 0], "end": [x, 120]})
	for z in [-100, 100]:
		sim.apply({"type": "build_road", "start": [-200, z], "ctrl": [0, z], "end": [200, z]})
	for id in sim.network.segments:
		print("  ", id, "  ", sim.streets.name_of(id))
	_aim_camera()
	if OS.get_environment("SIGN_CLOSE") == "1":
		await process_frame
		for c in _main.get_children():
			if c is StreetSignView:
				var keys: Array = c._signs.keys()
				keys.sort()
				var n: Node3D = c._signs[keys[0]]
				for cam in _main.get_children():
					if cam is CityCamera:
						cam.look_at_point(n.global_position + Vector3(0, 2.6, 0))
						cam.set_view(-2.4, deg_to_rad(6.0), 7.0)
