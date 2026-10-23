extends SceneTree
## Renders a test town with a rail depot, its main line and a spur to a mine
## (permits approved, a bold leader), to check how the railroad looks.
## Run: xvfb-run godot -s tools/rail_shot.gd -- out.png yaw pitch dist [focus] [days]
## focus: yard (default), crossing, whistle, train, pax, or x,z. Add "pax" after days
## for passenger service and a station ("-" for none), then "view" for the Rail view.

var _main: Node
var _frames := 0
var _focus := Vector3.ZERO
var _shot_at := 80


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 12:
		_town()
	if _frames == _shot_at - 20:
		_aim()
	if _frames == _shot_at:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "rail.png")
		for c in _main.get_children():
			if c is RailView:
				var q: Vector3 = Rail._yard_pt(_main.sim.rail.depots.values()[0], 0.0, 22.6)
				print("yard pt ", q, " base ", Terrain.base_y(q.x, q.z), " ground ", Terrain.ground_y(q.x, q.z), " flat ", Terrain.flat_weight(q.x + Terrain.shift.x, q.z + Terrain.shift.y), " grades ", c._grades.size())
				print("track aabb ", c._track.get_aabb(), " visible ", c._track.visible, " ties ", c._ties.multimesh.instance_count)
		quit()
	return false


func _town() -> void:
	var sim: CitySim = _main.sim
	var args := OS.get_cmdline_user_args()
	sim.apply({"type": "clear"})
	sim.economy.money = 1.0e9
	sim.require_utilities = false
	sim.simulate_traffic = false
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var site := Rail.site_near(sim.network, Vector3(0, 0, 60))
	sim.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z],
		"axis": [site[2].x, site[2].z]})
	var did: int = sim.rail.depots.keys()[0]
	var d: Dictionary = sim.rail.depots[did]
	var hq := Vector3.ZERO
	var best := 0.0
	for x in range(900, 2400, 50):
		for z in range(300, 2400, 50):
			var r := Resources.at(Resources.Kind.ORE, Vector3(x, 0, z))
			if r > best and sim.land_ok(Vector3(x, 0, z), 60.0):
				best = r
				hq = Vector3(x, 0, z)
	var street_x := hq.x - 400.0
	sim.apply({"type": "build_road", "start": [street_x, 0], "ctrl": [street_x, 1000], "end": [street_x, 2000]})
	var sid := sim.industry.add_site("ore", hq, Vector3(-1, 0, 0), [hq, Vector3(street_x, 0, hq.z)])
	for x in range(-3, 4):
		for y in range(1, 6):
			sim.industry.sites[sid].pads.append(Vector2i(x, y))
	d.leader.ambition = 1.0
	d.leader.caution = 0.1
	var days := int(args[5]) if args.size() > 5 else 20
	var pax := args.size() > 6 and args[6] == "pax"
	for i in 24 * 60 * days:
		if pax and i == 24 * 60 * 9 and not d.pax:
			# Passenger service and a station, as a bigger town would have.
			d.pax = true
			d.pax_train = sim.rail._new_train(did, "passenger")
			d.built.append("station")
		sim.tick()
		if i % 60 == 0:
			for lid in sim.rail.open_requests():
				sim.apply({"type": "permit", "id": sim.rail.lines[lid].permit, "answer": "approve"})
			d.skip.clear()
		if sim.industry.sites[sid].stock < 6.0:
			sim.industry.sites[sid].stock = 12.0
	sim.industry_changed.emit()
	var focus := args[4] if args.size() > 4 else "yard"
	match focus:
		"yard":
			_focus = d.pos
		"crossing", "whistle":
			_focus = sim.rail.crossings[0].pos if not sim.rail.crossings.is_empty() else d.pos
		"pax":
			var poses := sim.rail.car_poses(d.pax_train)
			_focus = poses[0][1] if not poses.is_empty() else d.pos
		"train":
			var poses := sim.rail.car_poses(d.freight_train)
			_focus = poses[0][1] if not poses.is_empty() else d.pos
		_:
			var xz := focus.split(",")
			_focus = Vector3(float(xz[0]), 0, float(xz[1]))
	print("rail shot: lines ", sim.rail.lines.size(), " pieces ", sim.rail.pieces.size(), " crossings ",
		sim.rail.crossings.size(), " focus ", _focus, " why ", d.why)
	_main.set_speed(0)


func _aim() -> void:
	var args := OS.get_cmdline_user_args()
	for c in _main.get_children():
		if c is RailView and args.size() > 4 and args[4] == "whistle" and not _main.sim.rail.crossings.is_empty():
			var cr: Dictionary = _main.sim.rail.crossings[0]
			var at: Array = c._walk(int(cr.piece), float(cr.s), 1, RailView.WHISTLE_POST)
			if at.is_empty():
				at = c._walk(int(cr.piece), float(cr.s), -1, RailView.WHISTLE_POST)
			if not at.is_empty():
				_focus = at[0]
	for c in _main.get_children():
		if c is RailView and args.size() > 7 and args[7] == "view":
			c.show_lines = true
		if c is CityCamera:
			c.look_at_point(_focus)
			c.set_view(deg_to_rad(float(args[1]) if args.size() > 1 else 30.0),
				deg_to_rad(float(args[2]) if args.size() > 2 else 40.0), float(args[3]) if args.size() > 3 else 250.0)
