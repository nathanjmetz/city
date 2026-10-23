extends SceneTree
## Renders parks and landmarks for the art loop and saves a picture.
## Run: godot -s tools/park_shot.gd -- out.png scene yaw_deg pitch_deg dist
## scene: parks (a struggling and a thriving park side by side), courthouse,
## water_tower, grain_elevator, football, tree (a park with its whole
## development tree) or all.

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	# After the game shell has set up its own town.
	if _frames == 30:
		_build()
	if _frames == 150:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "parks.png")
		_count_trees(_main)
		print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		quit()
	return false


func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: String = args[1] if args.size() > 1 else "parks"
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	if OS.get_environment("SHOT_MONTH") != "":
		# Months from January, as in screenshot.gd (0.5 is mid-January snow).
		var m := float(OS.get_environment("SHOT_MONTH")) - Seasons.START_MONTH
		sim.tick_count = int(fposmod(m, 12.0) * Seasons.TICKS_PER_DAY)
	root.get_node("Session").set("current_name", "Petersburg")
	var look := Vector3.ZERO
	if scene == "trails":
		# A trailhead up from the creek south of town, with its greenway, a
		# connector to a park, and bike lanes on the street.
		sim.apply({"type": "build_road", "start": [-900, -300], "ctrl": [-300, -300], "end": [300, -300]})
		var th := _place(sim, "trailhead", Vector3(-300, 0, -340))
		_fill(sim, _place(sim, "park", Vector3(100, 0, -340)), 2)
		var t := sim.parks.trails
		for k in 8:
			sim.stats.population = 2_000
			t._month = -1
			t.decide(sim)
		for rid in t.asked.keys():
			sim.apply({"type": "permit", "id": rid, "answer": "approve"})
		t.decide(sim)
		look = sim.parks.sites[th].pos + Vector3(0, 0, -150)
		scene = "done"
	else:
		sim.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0], "road": 1})
	match scene:
		"done":
			pass
		"parks":
			# The same park in a struggling and a thriving neighborhood.
			for entry in [[-110.0, 0], [110.0, 3]]:
				var id := _place(sim, "park", Vector3(entry[0], 0, 60))
				_fill(sim, id, entry[1])
			look = Vector3(0, 0, 90)
		"tree":
			# A thriving park with its whole development tree built out.
			var id := _place(sim, "park", Vector3(0, 0, 60))
			_fill(sim, id, 3)
			_fill_tree(sim, id)
			look = sim.parks.sites[id].pos
		"sports":
			# The big items: a youth complex with lights and an aquatic center.
			var id := _place(sim, "park", Vector3(0, 0, 60))
			_fill_tree(sim, id, ["field_lights", "youth_complex", "tournament", "aquatic_center"])
			look = sim.parks.sites[id].pos
		"fair", "fair_on", "stadium":
			# The fairgrounds and the football field with their trees built,
			# and the businesses visitors bring.
			var on := scene != "fair"
			var f := _place(sim, "fairgrounds", Vector3(0, 0, 60))
			var fb := _place(sim, "football", Vector3(260, 0, 60))
			for id in [f, fb]:
				var v: Dictionary = sim.parks.tourism.venues[id]
				for node in Balance.VENUE_TREES[v.kind]:
					v.built.append(node.id)
				if on:
					v.crowd = {"name": "Event", "visitors": 9000, "outside": 3000, "cars": 0, "start": 0, "end": 0}
			sim.parks.tourism.venues[f].outside_last = 40_000.0
			for i in 3:
				sim.parks.tourism._open_businesses(sim)
			look = sim.parks.sites[fb if scene == "stadium" else f].pos
		"all":
			_place(sim, "courthouse", Vector3(-320, 0, 60))
			_place(sim, "water_tower", Vector3(-200, 0, 60))
			_place(sim, "grain_elevator", Vector3(-120, 0, 60))
			_place(sim, "football", Vector3(60, 0, 60))
			_fill(sim, _place(sim, "park", Vector3(260, 0, 60)), 2)
			look = Vector3(-40, 0, 60)
		_:
			_place(sim, scene, Vector3(0, 0, 60))
			look = Vector3(0, 0, 50)
	sim.parks_changed.emit()
	for i in 3:
		sim.tick()
	for id in sim.parks.sites:
		var pp: Vector3 = sim.parks.sites[id].pos
		print("wild plants in the middle of %s: %d" % [sim.parks.sites[id].name,
			sim.vegetation.plants_in(Rect2(Vector2(pp.x - 20, pp.z - 20), Vector2(40, 40)), sim.tick_count).size()])
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
		if c is CityCamera:
			c.look_at_point(look if args.size() < 7 else Vector3(float(args[5]), 0, float(args[6])))
			if args.size() >= 5:
				c.set_view(deg_to_rad(float(args[2])), deg_to_rad(float(args[3])), float(args[4]))


func _place(sim: CitySim, kind: String, at: Vector3) -> int:
	var site := Parks.site_near(sim.network, kind, at)
	sim.apply({"type": "place_park", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var ids := sim.parks.sites.keys()
	ids.sort()
	return ids[-1]


## Fills a park in as if years had passed, at the given tier.
func _fill(sim: CitySim, id: int, tier: int) -> void:
	var s: Dictionary = sim.parks.sites[id]
	s.tier = tier
	s.score = Neighborhood.TIERS[tier].min + 0.06
	for i in 20:
		sim.parks._fill_in(sim, id, 100 if tier > 0 else 0)


## Builds every item of the park tree, buying land as needed (skipping what
## the town would have to support, for the picture).
func _fill_tree(sim: CitySim, id: int, only := []) -> void:
	var s: Dictionary = sim.parks.sites[id]
	for t in Balance.PARK_TREE:
		var key: String = t.id
		if not only.is_empty() and not key in only:
			continue
		for i in 40:
			var spot = sim.parks._find_spot(id, key, t.size)
			if spot != null:
				s.features.append({"type": key, "pos": spot, "size": t.size})
				break
			if not sim.parks._grow(sim, id, t.size, t.size.x * t.size.y):
				print("no room for ", key)
				break


func _count_trees(n: Node) -> void:
	if n is TreeField:
		for key in n._trees:
			var inside := 0
			for t in n._trees[key]:
				var o: Vector3 = t[0].origin
				if _main.sim.parks.covers(o):
					inside += 1
			if key.begins_with("park"):
				print("park sites %s, first tree %s, field at %s" % [_main.sim.parks.sites.values().map(func(x): return [x.pos, x.size]), n._trees[key][0][0].origin, n.global_position])
	for c in n.get_children():
		_count_trees(c)
