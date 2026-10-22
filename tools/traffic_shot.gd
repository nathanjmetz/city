extends SceneTree
## Renders a busy test town to check how traffic looks.
## Run: godot -s tools/traffic_shot.gd -- out.png yaw pitch dist x z [ticks] [flow|town]

var _main: Node
var _frames := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	# After the Session autoload is up.
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_town()
	if _frames == 60:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "traffic.png")
		quit()
	return false


func _town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 1.0e9
	# Two avenues crossing at lights, a street grid, and a roundabout.
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [0, 0], "end": [400, 0], "road": 1})
	sim.apply({"type": "build_road", "start": [0, -400], "ctrl": [0, 0], "end": [0, 400], "road": 1})
	sim.apply({"type": "build_road", "start": [-300, -150], "ctrl": [-300, 0], "end": [-300, 150]})
	sim.apply({"type": "build_road", "start": [-150, -150], "ctrl": [-150, 0], "end": [-150, 150]})
	sim.apply({"type": "build_road", "start": [-300, 150], "ctrl": [-150, 150], "end": [0, 150]})
	sim.apply({"type": "build_road", "start": [200, -200], "ctrl": [200, 0], "end": [200, 200]})
	sim.apply({"type": "build_roundabout", "center": [200, 0], "radius": 24, "road": 1})
	sim.tick()
	var lots: Array = sim.lots.keys()
	lots.sort()
	_rng.seed = 3
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[6]) if args.size() > 6 else 1500
	var town := args.size() > 7 and args[7] == "town"
	if town:
		# Homes and shops that grow, with their people driving and walking.
		sim.economy.money = 1.0e9
		for k in range(-380, 380, 8):
			if absi(k) < 40:
				continue
			for side in [-18, 18]:
				sim.apply({"type": "paint_zone", "center": [k, side], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
				sim.apply({"type": "paint_zone", "center": [side, k], "radius": 10,
					"zone": ZoneMap.Zone.COMMERCIAL if k < 0 else ZoneMap.Zone.INDUSTRIAL})
		for kind in [Services.Kind.POWER_FEED, Services.Kind.WELL]:
			var site := Services.site_near(sim.network, kind, Vector3(-60 if kind == Services.Kind.WELL else -90, 0, -30))
			sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	for i in ticks:
		if i % 3 == 0 and not town:
			sim.traffic.add_trip(sim.lots[lots[_rng.randi() % lots.size()]], sim.lots[lots[_rng.randi() % lots.size()]], _rng)
		sim.tick()
	print("cars ", sim.traffic.cars.size(), " flow ", sim.traffic.flow, " gave up ", sim.traffic.gave_up,
		" parked ", sim.traffic.parked.size(), " walkers ", sim.traffic.walkers.size(), " people ", sim.people.people.size(),
		" buildings ", sim.buildings.size())
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(float(args[4]), 0, float(args[5])))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
	_main.set_speed(0)
	if args.size() > 7 and args[7] == "flow":
		for c in _main.get_children():
			if c is TrafficTool:
				c.set_mode(TrafficTool.Mode.SIGNAL)
