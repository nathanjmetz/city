extends SceneTree
## Grows the town the title screen flies over and saves it to
## res://art/menu/town.city: a county highway as Main Street with a downtown
## of two- and three-storey brick blocks around it (the square, a few streets
## deep), neighborhoods of homes all round, the usual services and a few
## farms out along the highway. Its people and cars are kept: the title
## screen runs them by the real hour (scripts/shell/menu_life.gd).
## Run: godot --headless -s tools/menu_town.gd -- [ticks]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[0]) if args.size() > 0 else 24000
	var sim := CitySim.new()
	sim.economy.money = 20_000_000
	# Main Street on the highway, side streets every 84 m (a short city
	# block), two blocks of homes deep each side.
	sim.apply({"type": "build_road", "start": [-540, 0], "ctrl": [0, 0], "end": [540, 0], "road": 2})
	sim.apply({"type": "build_grid", "a": [-420, -40], "b": [420, -40], "c": [-420, -376], "block": 84})
	sim.apply({"type": "build_grid", "a": [-420, 40], "b": [420, 40], "c": [-420, 376], "block": 84})
	for id in sim.network.segments.keys():
		var c := sim.network.curve_of(id)
		var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		for side in [-1, 1]:
			var zone := ZoneMap.Zone.RESIDENTIAL
			# Downtown: the highway and the streets round the square, three
			# blocks wide and a block either side of Main.
			if absf(mid.z) < 135.0 and absf(mid.x) < 260.0:
				zone = ZoneMap.Zone.COMMERCIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone})
	for entry in [[Services.Kind.WATER_TOWER, Vector3(-120, 0, 70)], [Services.Kind.SUBSTATION, Vector3(330, 0, 60)],
			[Services.Kind.FIRE, Vector3(120, 0, 50)], [Services.Kind.SCHOOL, Vector3(-240, 0, -200)],
			[Services.Kind.POLICE, Vector3(0, 0, 60)], [Services.Kind.CLINIC, Vector3(240, 0, 200)]]:
		# The first spot along the streets nearby that the plat allows.
		var placed := false
		var offsets := [Vector3.ZERO]
		for dx in range(-300, 301, 30):
			for dz in [0, 70, -70, 140, -140]:
				offsets.append(Vector3(dx, 0, dz))
		for off in offsets:
			var site := Services.site_near(sim.network, entry[0], entry[1] + off)
			if not site.is_empty() and sim.apply({"type": "place_service", "kind": entry[0],
					"pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]}):
				placed = true
				break
		print("service ", entry[0], ": ", placed)
	# Two farms out along the highway, so the county around the town has
	# working fields (crops on the calendar, farmsteads, barns).
	for entry in [[Vector3(520, 0, 90), Vector3(0, 0, -1)], [Vector3(-520, 0, -90), Vector3(0, 0, 1)],
			[Vector3(80, 0, -520), Vector3(0, 0, 1)]]:
		var ok := sim.apply({"type": "place_farmhouse", "pos": [entry[0].x, entry[0].z],
			"dir": [entry[1].x, entry[1].z], "crop": "corn"})
		print("farmhouse at ", entry[0], ": ", ok)
	for i in ticks:
		sim.tick()
	# The town stops growing where its demand does; this one is a picture
	# of a fuller place, so the lots still empty get built too, then a
	# little more time for the builders and the movers.
	var filled := 0
	for round in 3000:
		for z in sim.demand.keys():
			sim.demand[z] = 1.0
		if sim._grow_one(round + 1) != "":
			filled += 1
		elif sim.empty_zoned_lots().is_empty():
			break
		sim.tick_count += 1
	print("filled ", filled, " empty lots")
	for i in 4000:
		sim.tick()
	# Saved in the small hours with the streets empty and everyone home, so
	# the title screen starts from a still town and the real hour fills it.
	# People only start outings between 7 am and 9 pm, and walk at real
	# speed (minutes a block), so the days skip ahead to each evening and
	# the nights are lived through until the last walker is in.
	var guard := 0
	# People keep the sky's hours (CitySim.sky_hour: a game day is a month),
	# so the skip and the 3 am are on the sky's clock.
	while guard < 30000 and not (int(sim.sky_hour()) == 3 and sim.traffic.walkers.size() == 0
			and sim.traffic.cars.size() <= 6):
		var hour := sim.sky_hour()
		if hour >= 5.0 and hour < 21.0:
			sim.tick_count += maxi(int((21.0 - hour) * sim.sky_ticks_per_hour()), 1)
		sim.tick()
		guard += 1
	print("quiet after ", guard, " ticks: ", sim.traffic.cars.size(), " cars, ", sim.traffic.walkers.size(), " walkers")
	# Downtown: the shops on the square and Main Street are the old brick
	# blocks of a county seat, two and three storeys with flats over the
	# stores, and a few offices (the market for them takes a bigger town
	# than this to grow on its own). A few one-storey shops stay.
	var blocks := 0
	for key in sim.buildings.keys():
		var b: Dictionary = sim.buildings[key]
		var p: Vector3 = sim.lots[key].pos
		if int(b.zone) != ZoneMap.Zone.COMMERCIAL or absf(p.z) > 145.0 or absf(p.x) > 270.0:
			continue
		var r := absi(int(b.seed))
		var pick := r % 20
		if pick < 3:
			continue
		var type := "mixed_use"
		var level := 0 if pick < 12 else 1
		if pick >= 18:
			type = "office"
			level = 0
		sim.redevelop(key, type, level)
		blocks += 1
	print("downtown blocks: ", blocks)
	# Every building is old enough to be whole, whatever the calendar says.
	sim.update_stats()
	var path := "res://art/menu/town.city"
	# Only what the backdrop draws and runs: no history or timelapse (most
	# of the file).
	var town := sim.to_dict()
	for k in ["timelapse", "history"]:
		town.erase(k)
	root.get_node("Session").save_city(sim, ProjectSettings.globalize_path(path), var_to_bytes(town))
	print("menu town: ", sim.buildings.size(), " lots, pop ", sim.stats.population, ", ", sim.people.people.size(),
		" people, ", sim.traffic.cars.size(), " cars -> ", path)
	quit()
