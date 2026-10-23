extends "res://tools/screenshot.gd"
## Livestock on farms in July (Livestock): hog barns, turkey barns and a
## dairy beside their farmyards, and a beef herd on pasture.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/livestock_shot.gd -- out.png yaw pitch dist [x z]


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.tick_count = 190 * 1440  # mid July
	sim.apply({"type": "build_road", "start": [-1600, 0], "ctrl": [0, 0], "end": [1600, 0]})
	sim.apply({"type": "paint_farmland", "points": [[-1550, 30], [1550, 30], [1550, 900], [-1550, 900]]})
	var kinds := ["hogs", "cattle", "turkeys", "dairy"]
	for i in kinds.size():
		sim.apply({"type": "place_farmhouse", "pos": [-1100 + i * 700, 60], "dir": [0, -1], "crop": "corn"})
	sim.farms.price = 1.1
	for i in 300:
		sim.farms.decide(sim.field_usable)
	var ids := sim.farms.farms.keys()
	ids.sort()
	for i in ids.size():
		var f: Dictionary = sim.farms.farms[ids[i]]
		f.leader = {"edu": 0.8, "caution": 0.2, "ambition": 0.8}
		var st := Livestock.stock(f)
		st.kind = kinds[i]
		if kinds[i] == "cattle":
			f.fields = {}
			for c in f.cells:
				f.fields[CropPlan.field_of(c)] = {"crop": "pasture" if c.y > 2 else "corn", "prev": "", "years": 1,
					"health": 0.5, "cover": false, "cover_prev": false, "why": ""}
		else:
			for n in (2 if kinds[i] != "dairy" else 1):
				var s := Livestock.best_site(f, kinds[i], [Vector3.INF], [])
				if s != Vector2i.MAX:
					Livestock._build(sim, ids[i], f, s)
		print(kinds[i], " cells ", f.cells.size(), " head ", Livestock.head(f), " sites ", Livestock.sites(f))
	DayNight.seasons_on = false
	sim.farms_changed.emit()
	var args := OS.get_cmdline_user_args()
	var which := int(args[4]) if args.size() >= 5 else 0
	var f: Dictionary = sim.farms.farms[ids[mini(which, ids.size() - 1)]]
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(f.pos - f.dir * 60.0)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
