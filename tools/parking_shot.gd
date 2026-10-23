extends SceneTree
## Renders the town's parking (ParkingLots) with cars in most stalls, and
## the Roads menu's Parking row, and saves the pictures.
## Run: godot -s tools/parking_shot.gd -- out_prefix [yaw pitch dist] [lot index]

var _main: Node
var _frames := 0
var _ids := []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "parking"
	if _frames == 30:
		_demo()
	if _frames == 40 and not OS.get_cmdline_user_args().has("empty"):
		_fill()
	if _frames == 90:
		var at := int(args[4]) if args.size() > 4 else -1
		_look(at, args)
	if _frames == 130:
		root.get_viewport().get_texture().get_image().save_png(out + "_lots.png")
		_hud().close_all()
		for c in _main.get_children():
			if c is ServiceTool:
				c.set_kind(Services.Kind.PARKING_DOWNTOWN)
	if _frames == 150:
		root.get_viewport().get_texture().get_image().save_png(out + "_menu.png")
		quit()
	return false


func _hud() -> Hud:
	for c in _main.get_children():
		if c is Hud:
			return c
	return null


func _demo() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 500_000_000
	sim.build_county_road(Vector2(-2000, 0), Vector2(2000, 0), [0, 1])
	var x := -150.0
	for entry in [[Services.Kind.PARKING_SMALL, false], [Services.Kind.PARKING_DOWNTOWN, false],
			[Services.Kind.PARKING_DOWNTOWN, true], [Services.Kind.PARKING_LARGE, true], [Services.Kind.PARKING_GARAGE, false]]:
		var size: Vector2 = Services.KINDS[entry[0]].size
		x += size.x * 0.5 + 6.0
		var site := Services.site_near(sim.network, entry[0], Vector3(x, 0, 40))
		if sim.apply({"type": "place_service", "kind": entry[0], "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z], "angled": entry[1]}):
			var id: int = sim.services.buildings.keys().max()
			_ids.append(id)
			sim.construction.sites.erase("svc:%d" % id)
		x += size.x * 0.5
	sim.lots_changed.emit()


## Cars in about two stalls of three, as at a busy lunch hour.
func _fill() -> void:
	var sim: CitySim = _main.sim
	var kinds := ["sedan", "suv", "pickup", "crossover", "sedan"]
	var n := 0
	for id in _ids:
		var pl := sim.traffic.place("svc:%d" % id)
		for i in pl.spots.size():
			if (i * 7 + id) % 3 != 0:
				sim.traffic.new_vehicle(kinds[n % kinds.size()], "svc:%d" % id, -1)
				n += 1


func _look(at: int, args: Array) -> void:
	var sim: CitySim = _main.sim
	_hud().close_all()
	var mid := Vector3.ZERO
	if at >= 0 and at < _ids.size():
		mid = sim.services.buildings[_ids[at]].pos
	else:
		for id in _ids:
			mid += sim.services.buildings[id].pos / _ids.size()
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(mid)
			c.set_view(deg_to_rad(float(args[1]) if args.size() > 1 else 30.0),
				deg_to_rad(float(args[2]) if args.size() > 2 else 50.0), float(args[3]) if args.size() > 3 else 260.0)
