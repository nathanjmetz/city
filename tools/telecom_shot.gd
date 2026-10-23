extends SceneTree
## Renders the phone company: its office with grown blocks, a monopole, a
## lattice tower and a monopine, fiber marker posts, and (with "view") the
## Cell and fiber map view.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/telecom_shot.gd -- out.png yaw pitch dist x z [view]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_demo()
	if _frames == 60:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "telecom.png")
		quit()
	return false


func _demo() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 500_000_000
	sim.build_county_road(Vector2(-3000, 0), Vector2(3000, 0), [0, 1])
	sim.apply({"type": "build_grid", "a": [-400, -40], "b": [0, -40], "c": [-400, -400], "block": 120})
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := Telecom.site_near(sim.network, Vector3(120, 0, 60))
	sim.apply({"type": "place_telecom", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var c: Dictionary = sim.telecom.companies.values()[0]
	var corr := RoadWins.corridors(sim.network, 2.0)
	for use in ["garage", "cable_yard", "store"]:
		c.built.append(use)
		sim.telecom._buy_block(sim, 1, c, use, corr)
	c.built.append("lte_5g")
	# Fiber down every street of the grid.
	for seg in sim.network.segments:
		var p0: Vector3 = sim.network.nodes[sim.network.segments[seg].a]
		if p0.z < -20.0 or p0.x < -20.0:
			c.fiber.append({"seg": seg, "pts": Telecom._seg_pts(sim, seg)})
	# A lattice out in the country and a monopine by the homes.
	c.towers.append({"pos": [900.0, 70.0], "kind": "lattice", "built": 0})
	c.towers.append({"pos": [-480.0, -230.0], "kind": "monopine", "built": 0})
	sim.telecom.mark_dirty()
	sim.telecom_changed.emit()
	var args := OS.get_cmdline_user_args()
	for n in _main.get_children():
		if n is Hud:
			n.close_all()
			if args.size() >= 7 and args[6] == "view":
				n._show_view("network")
		if n is CityCamera:
			n.look_at_point(Vector3(float(args[4]), 0, float(args[5])) if args.size() >= 6 else site[0])
			n.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
