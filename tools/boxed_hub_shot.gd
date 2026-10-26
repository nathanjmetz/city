extends "res://tools/screenshot.gd"
## A landfill, recycling centre or cemetery boxed in by four streets, grown
## until no whole piece fits, and saves a picture. "before" leaves out its
## edge pieces (how it looked until 2026-10-26), "after" keeps them.
## Run: godot --resolution 1600x900 -s tools/boxed_hub_shot.gd -- out.png yaw_deg pitch_deg dist kind
## before|after [look_x look_z (from the block's middle)]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	var args := OS.get_cmdline_user_args()
	var kind: String = args[4] if args.size() > 4 else "landfill"
	var before := args.size() > 5 and args[5] == "before"
	var cem := kind == "cemetery"
	var x := 100 if cem else 180
	var d := 170 if cem else 260
	# Clear of the starter town's roads: the block's front street runs along
	# z = OZ, the block behind it.
	var oz := 700
	var ring := [[[-x, oz], [x, oz]], [[x, oz], [x, oz - d]], [[x, oz - d], [-x, oz - d]], [[-x, oz - d], [-x, oz]]]
	# Streets running on out of the block, with houses along them.
	var out := [[[x, oz], [x + 300, oz]], [[x, oz], [x, oz + 200]], [[-x, oz], [-x, oz + 200]], [[-x - 300, oz], [-x, oz]]]
	for r in ring + out:
		var a: Array = r[0]
		var b: Array = r[1]
		sim.apply({"type": "build_road", "start": a, "ctrl": [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5], "end": b})
	# Houses zoned along the streets running out (not the block's own).
	for p in [Vector3(x + 150, 0, oz + 30), Vector3(x + 30, 0, oz + 100), Vector3(-x - 30, 0, oz + 100),
			Vector3(-x - 150, 0, oz + 30), Vector3(0, 0, oz + 30)]:
		for r in range(-120, 121, 15):
			var q: Vector3 = p + (Vector3(r, 0, 0) if absf(p.z - oz - 30) < 1.0 else Vector3(0, 0, r * 0.6))
			sim.apply({"type": "paint_zone", "center": [q.x, q.z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var hub_kind := "landfill" if kind == "recycling_2" else kind
	var site := CivicHubs.site_near(sim.network, Vector3(0, 0, oz - 60))
	sim.apply({"type": "place_hub", "kind": hub_kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var hid: int = sim.hubs.hubs.keys()[0]
	var h: Dictionary = sim.hubs.hubs[hid]
	for i in 1500:
		sim.tick()
	sim.construction.sites.erase("hub:%d" % hid)
	sim.stats.population = maxi(sim.stats.population, Balance.CEMETERY_PEOPLE_PER_PIECE * 200)
	for i in 120:
		h.want = 10
		h.short = 10
		sim.hubs._decide(sim)
	if kind == "recycling_2":
		sim.hubs.upgrade(hid)
		sim.hubs.upgrade(hid)
	if before:
		h.edge = {}
		sim.hubs._touch(h)
	print("%s: %d whole pieces, %d edge pieces, %.1f acres" % [kind, h.cells.size(), h.edge.size(),
		CivicHubs.land_area(h) / 4046.86])
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			var off := Vector3(float(args[6]), 0, float(args[7])) if args.size() >= 8 else Vector3.ZERO
			c.look_at_point(Vector3(0, 0, oz - d * 0.5) + off)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
