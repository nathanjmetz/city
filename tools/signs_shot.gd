extends "res://tools/screenshot.gd"
## A main street of named businesses, one family owning several, and a
## farm with its lane sign, for checking names and signs.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/signs_shot.gd -- out.png yaw pitch dist [x z]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.tick_count = 190 * 1440
	sim.apply({"type": "build_road", "start": [-160, 0], "ctrl": [0, 0], "end": [160, 0]})
	if OS.get_environment("SIGNS_FARM") == "1":
		# Just a farm and an oil company on the county road, for their signs.
		sim.apply({"type": "place_farmhouse", "pos": [60, -120], "dir": [0, 1], "crop": "corn"})
		for i in 3:
			sim.tick()
		print("farms ", sim.farms.farms.size(), " ", sim.families.owned)
		for c in _main.get_children():
			if c is FarmView:
				for ref in c._signs:
					var n: Node3D = c._signs[ref]
					print("sign ", ref, " at ", n.global_position, " facing ", -n.global_basis.z)
					for cam in _main.get_children():
						if cam is CityCamera:
							cam.look_at_point(n.global_position)
							var f := -n.global_basis.z
							cam.set_view(atan2(f.x, f.z), deg_to_rad(8.0), 9.0)
		return
	for x in range(-160, 161, 10):
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12,
			"zone": ZoneMap.Zone.COMMERCIAL if x < 60 else ZoneMap.Zone.INDUSTRIAL})
	for i in 3:
		sim.tick()
	var empty: Array = sim.lots.keys().filter(func(k): return sim.zones.zone_at(sim.lots[k].zone_pt) != ZoneMap.Zone.NONE)
	empty.sort()
	for key in empty:
		sim.found_business(key, sim.zones.zone_at(sim.lots[key].zone_pt))
	sim.apply({"type": "place_farmhouse", "pos": [100, -170], "dir": [0, 1], "crop": "corn"})
	# One family owns three of them, under one brand.
	var refs := sim.families.owned.keys()
	refs.sort()
	var fam: Dictionary = sim.families.family_of(refs[0])
	for i in [3, 6]:
		var ref: String = refs[i]
		var b: Dictionary = sim.families.owned[ref]
		var name := sim.families._name_for(fam, b.what, i)
		if name != "":
			sim.families._used.erase(b.name)
			b.formerly = [b.name]
			b.family = fam.id
			b.name = name
			sim.families._used[name] = ref
	sim.families._stale = true
	# Skip the building work: show the finished street.
	sim.construction.sites.clear()
	# An old business: "SINCE" on its sign.
	sim.families.owned[refs[1]].since = Seasons.year(sim.tick_count) - 20
	sim.families.changed.emit()
	for r in refs:
		print("  ", r, "  ", sim.families.name_of(r), "  (", sim.families.family_of(r).surname, ")")
	_aim_camera()
