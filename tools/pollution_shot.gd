extends SceneTree
## Renders the pollution views over a small town with factories beside homes
## and a highway, with a polluted home's panel open, and saves a picture.
## Run: godot -s tools/pollution_shot.gd -- out.png view [select] [yaw pitch dist]
## view: smoke, noise or ground. select: home (the most polluted home),
## source (the factory hurting the most homes), spot (open ground), or none.

var _main: Node
var _frames := 0
var _hud: Hud


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_build()
	if _frames == 160:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "pollution.png")
		print("saved")
		quit()
	return false


func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[1] if args.size() > 1 else "noise"
	var what: String = args[2] if args.size() > 2 else "home"
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	sim.require_utilities = false
	sim.simulate_traffic = false
	# An avenue with homes to the west and factories to the east, and a
	# highway along the north edge of town.
	sim.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0], "road": 1})
	sim.apply({"type": "build_road", "start": [-200, -260], "ctrl": [-200, 0], "end": [-200, 260]})
	sim.apply({"type": "build_road", "start": [-900, -320], "ctrl": [0, -320], "end": [900, -320], "road": RoadStyle.Type.HIGHWAY})
	for id in sim.network.segments.keys():
		if int(sim.network.segments[id].type) == RoadStyle.Type.HIGHWAY:
			continue
		var c := sim.network.curve_of(id)
		var mid: Vector3 = RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		for side in [-1, 1]:
			var zone := ZoneMap.Zone.INDUSTRIAL if mid.x > 150.0 else ZoneMap.Zone.RESIDENTIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone})
	for x in range(160, 501, 10):
		for zc in [-25, 25]:
			sim.apply({"type": "paint_zone", "center": [x, zc], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	var t0 := Time.get_ticks_msec()
	for i in 2500:
		sim.tick()
	# Fill every zoned lot, like years of growth.
	var n := 0
	for key in sim.empty_zoned_lots():
		var z := sim.zones.zone_at(sim.lots[key].zone_pt)
		n += 1
		sim.buildings[key] = {"zone": z, "seed": n * 7919, "built": 0, "cap": CitySim.capacity(z, n * 7919), "occ": 2}
	print("grew %d buildings in %d ms" % [sim.buildings.size(), Time.get_ticks_msec() - t0])
	sim.pollution.rebuild(sim)
	sim.pollution.measure_lots(sim)
	for day in 12:
		sim.pollution._daily(sim)
	sim.buildings_changed.emit()
	for c in _main.get_children():
		if c is Hud:
			_hud = c
			c.close_all()
			c._show_view(view)
		if c is CityCamera:
			var look := Vector3(150, 0, -60)
			c.look_at_point(look)
			if args.size() >= 6:
				c.set_view(deg_to_rad(float(args[3])), deg_to_rad(float(args[4])), float(args[5]))
			else:
				c.set_view(deg_to_rad(20.0), deg_to_rad(58.0), 1250.0)
	var sel := {}
	match what:
		"home":
			var worst := 1.0
			for key in sim.buildings:
				if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
					var f := sim.pollution.lot_factor(sim, key)
					if f < worst:
						worst = f
						sel = {"type": "lot", "id": key}
		"source":
			var most := -1
			for ref in sim.pollution.hurts:
				if ref.begins_with("lot:") and int(sim.pollution.hurts[ref].homes) > most:
					most = int(sim.pollution.hurts[ref].homes)
					sel = sim.pollution.sources[ref].select
		"spot":
			sel = {"type": "spot", "id": [120.0, -150.0]}
	if not sel.is_empty() and _hud:
		_hud.select_tool.select(sel)
