extends SceneTree
## Pictures of the placement hints (wind arrows, smoke plume, noise rings).
## Run: godot -s tools/hints_shot.gd -- industry|homes|coal out.png

var _frames := 0
var _mode := "industry"
var _out := "hints.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "industry"
	_out = args[1] if args.size() > 1 else "hints.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Hints Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	var main := current_scene
	if _frames == 20:
		var sim: CitySim = main.sim
		sim.economy.money = 50_000_000
		sim.apply({"type": "build_road", "start": [-300, 300], "ctrl": [0, 300], "end": [300, 300]})
		sim.apply({"type": "build_road", "start": [-300, 300], "ctrl": [0, 0], "end": [300, -300]})
		for x in range(-300, 301, 10):
			sim.apply({"type": "paint_zone", "center": [x, 275], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply({"type": "paint_zone", "center": [x, 325], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.simulate_traffic = false
		for i in 30:
			sim.tick()
		sim.pollution.rebuild(sim)
		var cam: CityCamera = main.get_children().filter(func(n): return n is CityCamera)[0]
		cam.set_view(deg_to_rad(0.0), deg_to_rad(60.0), 1500.0)
		cam.look_at_point(Vector3(-200, 0, 450))
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		match _mode:
			"industry": hud.zone_tool.set_zone(ZoneMap.Zone.INDUSTRIAL)
			"homes": hud.zone_tool.set_zone(ZoneMap.Zone.RESIDENTIAL)
			"coal": hud.industry_tool.set_kind("power")
			"police":
				# Two stations on a long road, so their coverage shows its edge.
				sim.apply({"type": "build_road", "start": [-5600, 300], "ctrl": [-2650, 300], "end": [300, 300]})
				for x in [-2400.0, -800.0]:
					var at := Vector3(x, 0, 300 - 32)
					print("police at ", x, ": ", sim.services.site_problem(sim.network, Services.Kind.POLICE, at, Vector3(0, 0, 1)),
						sim.apply({"type": "place_service", "kind": Services.Kind.POLICE, "pos": [at.x, at.z], "dir": [0, 1]}))
				for i in 5:
					sim.tick()
				cam.set_view(deg_to_rad(0.0), deg_to_rad(70.0), 2900.0)
				cam.look_at_point(Vector3(-1500, 0, 300))
				hud.service_tool.set_kind(Services.Kind.POLICE)
	if _frames == 60 and _mode == "police":
		# After the guided tour's own camera glide.
		var cam: CityCamera = main.get_children().filter(func(n): return n is CityCamera)[0]
		cam.glide_to(Vector3(-4000, 0, 300), 2900.0)
	if _frames > 20 and _frames < 200:
		Input.warp_mouse(root.get_viewport().get_visible_rect().size * 0.5)
	if _frames == 200:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
