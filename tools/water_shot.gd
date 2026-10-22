extends SceneTree
## Renders a small town whose water utility has grown a yard and laid pipe,
## with the utility selected so its mains and sewers show.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/water_shot.gd -- out.png [yaw pitch dist]

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
		_town()
	if _frames == 30:
		for c in _main.get_children():
			if c is SelectTool:
				c.select({"type": "water", "id": _main.sim.services.water.utilities.keys()[0]})
	if _frames == 60:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "water.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false


func _town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	sim.simulate_traffic = false
	for z in [0, 200]:
		sim.apply({"type": "build_road", "start": [-300, z], "ctrl": [0, z], "end": [300, z]})
	for x in [-300, 0, 300]:
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 100], "end": [x, 200]})
	for x in range(-280, 281, 40):
		for z in [20, 180]:
			sim.apply({"type": "paint_zone", "center": [x, z], "radius": 25, "zone": ZoneMap.Zone.RESIDENTIAL})
	var feed := Services.site_near(sim.network, Services.Kind.SUBSTATION, Vector3(-150, 0, 120))
	sim.apply({"type": "place_service", "kind": Services.Kind.SUBSTATION, "pos": [feed[0].x, feed[0].z], "dir": [feed[1].x, feed[1].z]})
	var site := Services.site_near(sim.network, Services.Kind.WATER_UTILITY, Vector3(150, 0, -40))
	sim.apply({"type": "place_service", "kind": Services.Kind.WATER_UTILITY, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var id: int = sim.services.water.utilities.keys()[0]
	sim.services.water.utilities[id].leader.edu = 0.9
	for i in 12000:
		sim.tick()
	# Show the whole tree's yard pieces, as a grown utility would have them.
	var u: Dictionary = sim.services.water.utilities[id]
	for key in ["tower", "lagoon", "filtration", "wholesale"]:
		if not sim.services.water.has_work(id, key):
			for c in sim.services.water._frontier(id):
				if sim.yard_usable(WaterUtility.cell_corners(sim.services.buildings[id], c)):
					u.works.append([key, c])
					u.built.append(key)
					break
	sim.water_changed.emit()
	for c in _main.get_children():
		if c is RoadTool:
			c.set_mode(RoadTool.Mode.NONE)
		if c is SelectTool:
			c.select({"type": "water", "id": id})
		if c is CityCamera:
			var args := OS.get_cmdline_user_args()
			c.look_at_point(Vector3(150, 0, -60))
			c.set_view(deg_to_rad(float(args[1]) if args.size() > 1 else 30.0),
				deg_to_rad(float(args[2]) if args.size() > 2 else 45.0), float(args[3]) if args.size() > 3 else 420.0)
