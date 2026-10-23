extends SceneTree
## The game with a street of homes and a few shops going up, for checking
## construction sites in the real game (stages, crews at the curb, cost).
## Run: godot -s tools/construction_town.gd -- out.png [ticks] [yaw pitch dist]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == 2:
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		sim.traffic.cars.clear()
		sim.traffic._waiting.clear()
		sim.economy.money = 20_000_000
		sim.require_utilities = false
		sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
		sim.apply({"type": "build_county_road", "a": [-200, 0], "b": [-200, -1200], "links": [1]})
		for x in range(-190, 191, 10):
			sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply({"type": "paint_zone", "center": [x, -15], "radius": 10,
				"zone": ZoneMap.Zone.COMMERCIAL if x < -60 else ZoneMap.Zone.RESIDENTIAL})
		var ticks := int(args[1]) if args.size() > 1 else 600
		for i in ticks:
			sim.tick()
		print("sites ", sim.construction.sites.size(), " buildings ", sim.buildings.size(),
			" trips ", sim.construction.trips.size(), " parked ", sim.construction.parked_poses().size())
		for c in _main.get_children():
			if c is CityCamera:
				c.look_at_point(Vector3(-40, 0, 0))
				if args.size() > 4:
					c.set_view(deg_to_rad(float(args[2])), deg_to_rad(float(args[3])), float(args[4]))
	if _frames == 40:
		var out := args[0] if args.size() > 0 else "town.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		quit()
	return false
