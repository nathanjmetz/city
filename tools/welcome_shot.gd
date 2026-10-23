extends "res://tools/screenshot.gd"
## The welcome sign at the edge of town, for checking it.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/welcome_shot.gd -- out.png yaw pitch dist [x z]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	root.get_node("Session").current_name = "Petersburg"
	sim.build_county_road(Vector2(-900, 0), Vector2(900, 0), [0, 1])
	sim.apply({"type": "build_road", "start": [0, -150], "ctrl": [0, 0], "end": [0, 150]})
	sim.nicknames.current = {"text": "Corn Capital of Pike County", "sector": "farm", "since": 2031}
	sim.nicknames.changed.emit()
	await process_frame
	for c in _main.get_children():
		if c is WelcomeSignView:
			print("signs ", c._signs.size(), " ", c._key)
			var n: Node3D = c._signs[0]
			for cam in _main.get_children():
				if cam is CityCamera:
					cam.look_at_point(n.global_position + Vector3(0, 1.6, 0))
					var f := -n.global_basis.z
					cam.set_view(atan2(f.x, f.z) + 0.35, deg_to_rad(6.0), 10.0)
