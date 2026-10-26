extends "res://tools/screenshot.gd"
## The traffic management center on an avenue (Nathan, 2026-10-25: "a
## traffic flow building"), built and open.
## Run in a real window: godot --resolution 1600x900 -s tools/traffic_center_shot.gd -- out.png yaw pitch dist


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.charter.reached["city"] = 0  # a city: the center is open to build
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0], "road": RoadStyle.Type.AVENUE})
	sim.apply({"type": "build_road", "start": [60, -200], "ctrl": [60, 0], "end": [60, 200], "road": RoadStyle.Type.AVENUE})
	var site := Services.site_near(sim.network, Services.Kind.TRAFFIC_CENTER, Vector3(0, 0, 40))
	sim.apply({"type": "place_service", "kind": Services.Kind.TRAFFIC_CENTER, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]})
	sim.tick_count += 20 * 1440  # long since built
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(site[0])
			var args := OS.get_cmdline_user_args()
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
