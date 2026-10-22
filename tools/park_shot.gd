extends SceneTree
## Renders parks and landmarks for the art loop and saves a picture.
## Run: godot -s tools/park_shot.gd -- out.png scene yaw_deg pitch_deg dist
## scene: parks (a struggling and a thriving park side by side), courthouse,
## water_tower, grain_elevator, football or all.

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_build()
	if _frames == 50:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "parks.png")
		print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		quit()
	return false


func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: String = args[1] if args.size() > 1 else "parks"
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	root.get_node("Session").set("current_name", "Petersburg")
	sim.apply({"type": "build_road", "start": [-500, 0], "ctrl": [0, 0], "end": [500, 0], "road": 1})
	var look := Vector3.ZERO
	match scene:
		"parks":
			# The same park in a struggling and a thriving neighborhood.
			for entry in [[-110.0, 0], [110.0, 3]]:
				var id := _place(sim, "park", Vector3(entry[0], 0, 60))
				_fill(sim, id, entry[1])
			look = Vector3(0, 0, 90)
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
