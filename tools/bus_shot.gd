extends SceneTree
## Renders a test town with a bus depot and a taxi company to check how they look.
## Run: godot -s tools/bus_shot.gd -- out.png yaw pitch dist x z [ticks] [view]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_town()  # after the game has loaded its last save
	if _frames == 79:
		for c in _main.get_children():
			if c is ServiceView:
				print("nodes ", c._nodes.keys())
				for n in c.get_children():
					print("svc node ", n.name, " at ", n.position, " visible ", n.visible, " kids ", n.get_child_count())
	if _frames == 80:
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
	for spot in [Vector3(-160, 0, 380), Vector3(160, 0, 220), Vector3(-260, 0, 220), Vector3(-600, 0, 620)]:
		var ts := Services.site_near(sim.network, Services.Kind.TAXI_COMPANY, spot)
		if not ts.is_empty() and sim.apply({"type": "place_service", "kind": Services.Kind.TAXI_COMPANY,
				"pos": [ts[0].x, ts[0].z], "dir": [ts[1].x, ts[1].z]}):
			print("taxi company at ", ts[0], " facing ", ts[1])
			for c in _main.get_children():
				if c is ServiceView:
					print("right after: ", c._nodes.keys())
			break
	# Skip the build-out so the finished depot and lot show.
	for ref in sim.construction.sites.keys():
		if str(ref).begins_with("svc:"):
			sim.construction.sites.erase(ref)
	var args := OS.get_cmdline_user_args()
	for t in (int(args[6]) if args.size() > 6 else 1200):
		sim.tick()
	for sid in sim.services.buildings:
		print("service ", sid, " kind ", sim.services.buildings[sid].kind, " at ", sim.services.buildings[sid].pos, " size ", Services.size_of(sim.services.buildings[sid]))
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(Vector3(float(args[4]), 0, float(args[5])))
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
		if c is BusView and args.size() > 7 and args[7] == "view":
			c.show_routes = true
	_main.set_speed(0)
