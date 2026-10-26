extends "res://tools/screenshot.gd"
## A park boxed in by four streets, filled in, and saves a picture. "before"
## leaves out its edge pieces (how it looked until 2026-10-26), "after"
## keeps them.
## Run: godot --resolution 1600x900 -s tools/boxed_parks_shot.gd -- out.png yaw_deg pitch_deg dist
## before|after [look_x look_z (from the block's middle)]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	var args := OS.get_cmdline_user_args()
	var before := args.size() > 4 and args[4] == "before"
	var x := 55
	var d := 80
	# Clear of the starter town's roads: the block's front street runs along
	# z = OZ, the block behind it.
	var oz := 700
	var ring := [[[-x, oz], [x, oz]], [[x, oz], [x, oz - d]], [[x, oz - d], [-x, oz - d]], [[-x, oz - d], [-x, oz]]]
	# Streets running on out of the block, with houses along them.
	var out := [[[x, oz], [x + 250, oz]], [[x, oz], [x, oz + 160]], [[-x, oz], [-x, oz + 160]], [[-x - 250, oz], [-x, oz]],
		[[x, oz - d], [x + 250, oz - d]], [[-x - 250, oz - d], [-x, oz - d]]]
	for r in ring + out:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})
	for p in [Vector3(x + 120, 0, oz + 25), Vector3(x + 25, 0, oz + 80), Vector3(-x - 25, 0, oz + 80),
			Vector3(-x - 120, 0, oz + 25), Vector3(0, 0, oz + 25), Vector3(x + 120, 0, oz - 40), Vector3(-x - 120, 0, oz - 40)]:
		for r in range(-100, 101, 15):
			var q: Vector3 = p + (Vector3(r, 0, 0) if absf(p.z - oz - 80) > 1.0 else Vector3(0, 0, r * 0.6))
			sim.apply({"type": "paint_zone", "center": [q.x, q.z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := Parks.site_near(sim.network, "park", Vector3(0, 0, oz - 30))
	sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	# A few houses inside the block too, along its east street.
	for z in range(oz - 15, oz - 66, -10):
		sim.apply({"type": "paint_zone", "center": [x - 8, z], "radius": 9, "zone": ZoneMap.Zone.RESIDENTIAL})
	var pid: int = sim.parks.sites.keys()[0]
	var s: Dictionary = sim.parks.sites[pid]
	sim.require_utilities = false
	for i in 1500:
		sim.tick()
	# A comfortable neighborhood's park, filled in.
	s.score = 0.7
	s.tier = 2
	for k in 12:
		s.next_feature = 0
		sim.parks.decide(sim)
		s.tier = 2
	if before:
		s.edge = {}
	sim.parks_changed.emit()
	# Midday, clear of the morning fog; no tour moving the camera.
	sim.tick_count += 360
	_main.set_speed(0)
	for n in _main.find_children("*", "FirstTownTour", true, false):
		n.stop()
	print("park: %s, %d features, %d edge pieces, %.2f acres" % [s.size, s.features.size(), s.edge.size(),
		sim.parks.land_acres(pid)])
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			var off := Vector3(float(args[5]), 0, float(args[6])) if args.size() >= 7 else Vector3.ZERO
			c.look_at_point(Vector3(0, 0, oz - d * 0.5) + off)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
