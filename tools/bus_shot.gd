extends SceneTree
## Renders a test town with a bus depot to check how buses look.
## Run: godot -s tools/bus_shot.gd -- out.png yaw pitch dist x z [ticks] [view]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_town()
	if _frames == 60:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "buses.png")
		quit()
	return false


func _town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 1.0e9
	sim.require_utilities = false
	for z in range(0, 801, 200):
		sim.apply({"type": "build_road", "start": [-1000, z], "ctrl": [0, z], "end": [1000, z]})
	for x in range(-1000, 1001, 250):
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, 400], "end": [x, 800]})
	# Zone every block face: shops downtown, homes around.
	var segs := sim.network.segments.keys()
	segs.sort()
	for seg in segs:
		var c := sim.network.curve_of(seg)
		var mid: Vector3 = (c[0] + c[2]) * 0.5
		var z := ZoneMap.Zone.COMMERCIAL if absf(mid.x) < 300.0 and absf(mid.z - 400.0) < 250.0 else ZoneMap.Zone.RESIDENTIAL
		sim.apply({"type": "zone_frontage", "seg": seg, "side": 1, "both": true, "zone": z})
	sim.tick()
	var keys := sim.lots.keys()
	keys.sort()
	var i := 0
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		var zone: int = sim.zones.zone_at(lot.zone_pt)
		if zone == ZoneMap.Zone.NONE:
			continue
		var cap := CitySim.capacity(zone, i)
		sim.buildings[key] = {"zone": zone, "seed": i, "built": 0, "cap": cap, "occ": cap if zone == ZoneMap.Zone.RESIDENTIAL else 0}
		i += 1
	sim.buildings_changed.emit()
	sim.update_stats()
	var site := Services.site_near(sim.network, Services.Kind.BUS_DEPOT, Vector3(-40, 0, 220))
	sim.apply({"type": "place_service", "kind": Services.Kind.BUS_DEPOT, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	var args := OS.get_cmdline_user_args()
	for t in (int(args[6]) if args.size() > 6 else 1200):
		sim.tick()
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(float(args[4]), 0, float(args[5])))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
		if c is BusView and args.size() > 7 and args[7] == "view":
			c.show_routes = true
	_main.set_speed(0)
