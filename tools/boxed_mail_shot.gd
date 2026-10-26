extends "res://tools/screenshot.gd"
## A post office boxed in by four streets, grown until no whole piece fits,
## and saves a picture. "before" leaves out its edge pieces (how it looked
## until 2026-10-26), "after" keeps them.
## Run: godot --resolution 1600x900 -s tools/boxed_mail_shot.gd -- out.png yaw_deg pitch_deg dist
## before|after [look_x look_z (from the block's middle)]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	var args := OS.get_cmdline_user_args()
	var before := args.size() > 4 and args[4] == "before"
	var x := 80
	var d := 110
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
	for p in [Vector3(x + 150, 0, oz + 30), Vector3(x + 30, 0, oz + 100), Vector3(-x - 30, 0, oz + 100),
			Vector3(-x - 150, 0, oz + 30), Vector3(0, 0, oz + 30)]:
		for r in range(-120, 121, 15):
			var q: Vector3 = p + (Vector3(r, 0, 0) if absf(p.z - oz - 30) < 1.0 else Vector3(0, 0, r * 0.6))
			sim.apply({"type": "paint_zone", "center": [q.x, q.z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	# A few houses inside the block too, along its east street.
	for z in range(oz - 20, oz - 91, -10):
		sim.apply({"type": "paint_zone", "center": [x - 20, z], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := CivicHubs.site_near(sim.network, Vector3(-10, 0, oz - 30))
	sim.apply({"type": "place_post_office", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var id: int = sim.mail.offices.keys()[0]
	var h: Dictionary = sim.mail.offices[id]
	# A sorting room out back, as a busy town's office has.
	var pieces := []
	for k in int(Balance.MAIL_TREE.sorting_room.land):
		var c: Vector2i = sim.mail._best_piece(sim, id, pieces)
		if c != Vector2i.MAX:
			pieces.append(c)
	h.cells.append_array(pieces)
	h.lands.sorting_room = pieces
	h.built.append("sorting_room")
	sim.require_utilities = false
	for i in 1500:
		sim.tick()
	sim.construction.sites.erase("mail:%d" % id)
	for i in 60:
		h.want = 10
		h.short = 10
		sim.mail._decide(sim)
	if before:
		h.edge = {}
		sim.mail._touch(h)
	print("post office: %d whole pieces, %d edge pieces, %.1f acres" % [h.cells.size(), h.edge.size(),
		CivicHubs.land_area(h) / 4046.86])
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			var off := Vector3(float(args[5]), 0, float(args[6])) if args.size() >= 7 else Vector3.ZERO
			c.look_at_point(Vector3(0, 0, oz - d * 0.5) + off)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
