extends SceneTree
## Grows the small town the title screen flies over and saves it to
## res://art/menu/town.city: a county highway as Main Street with brick
## shops, a grid of homes either side, and the usual services.
## Run: godot --headless -s tools/menu_town.gd -- [ticks]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[0]) if args.size() > 0 else 6000
	var sim := CitySim.new()
	sim.economy.money = 20_000_000
	# Main Street on the highway, side streets every 120 m (a real plat's
	# block), two blocks of homes deep each side.
	sim.apply({"type": "build_road", "start": [-420, 0], "ctrl": [0, 0], "end": [420, 0], "road": 2})
	sim.apply({"type": "build_grid", "a": [-300, -40], "b": [300, -40], "c": [-300, -280], "block": 120})
	sim.apply({"type": "build_grid", "a": [-300, 40], "b": [300, 40], "c": [-300, 280], "block": 120})
	for x in [-300, -180, -60, 60, 180, 300]:
		sim.apply({"type": "build_road", "start": [x, -40], "ctrl": [x, 0], "end": [x, 40]})
	for id in sim.network.segments.keys():
		var c := sim.network.curve_of(id)
		var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		for side in [-1, 1]:
			var zone := ZoneMap.Zone.RESIDENTIAL
			# Downtown: the highway's frontage in the middle blocks.
			if absf(mid.z) < 45.0 and absf(mid.x) < 200.0:
				zone = ZoneMap.Zone.COMMERCIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone})
	for entry in [[Services.Kind.WATER_TOWER, Vector3(-120, 0, 70)], [Services.Kind.SUBSTATION, Vector3(330, 0, 60)],
			[Services.Kind.FIRE, Vector3(120, 0, 50)], [Services.Kind.SCHOOL, Vector3(-240, 0, -200)],
			[Services.Kind.POLICE, Vector3(0, 0, 60)], [Services.Kind.CLINIC, Vector3(240, 0, 200)]]:
		var site := Services.site_near(sim.network, entry[0], entry[1])
		if not site.is_empty():
			sim.apply({"type": "place_service", "kind": entry[0], "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z]})
	for i in ticks:
		sim.tick()
	# Summer, whatever month it grew to.
	sim.tick_count -= sim.tick_count % (12 * Seasons.TICKS_PER_DAY)
	sim.tick_count += int((7.2 - Seasons.START_MONTH) * Seasons.TICKS_PER_DAY)
	var path := "res://art/menu/town.city"
	# Only what the backdrop draws: the menu never runs the clock, so no
	# cars, people or history (most of the file).
	var town := sim.to_dict()
	for k in ["traffic", "people", "timelapse", "history"]:
		town.erase(k)
	root.get_node("Session").save_city(sim, ProjectSettings.globalize_path(path), var_to_bytes(town))
	print("menu town: ", sim.buildings.size(), " lots, pop ", sim.stats.population, " -> ", path)
	quit()
