extends SceneTree
## Lines up every vehicle model in the game's own lighting, for checking
## them against real photos.
## Run: godot -s tools/vehicle_shot.gd -- out.png yaw pitch dist [lod] [x z] [filter]

var _main: Node
var _frames := 0


func _initialize() -> void:
	# After the Session autoload is up.
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	# The map loads over many frames in software rendering; wait for it.
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_lineup()
	if _frames == 40:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "vehicles.png")
		quit()
	return false


func _lineup() -> void:
	var args := OS.get_cmdline_user_args()
	var lod := int(args[4]) if args.size() > 4 else 0
	var filter: String = args[7] if args.size() > 7 else ""
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.traffic.cars.clear()
	# Late morning sun.
	sim.tick_count = int(8.0 * 60.0 / CitySim.MINUTES_PER_TICK)
	var x := 0.0
	var row := 0
	var i := 0
	for key in VehicleModels.mesh_keys():
		if filter != "" and not filter.split(",").has(key):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = VehicleModels.build(key, lod)
		mm.instance_count = 1
		var kind: String = key
		if key.begins_with("tractor_") or key.begins_with("trailer_"):
			kind = "semi"
		var paint := VehicleTypes.paint(kind, 7 + i * 3)
		if not VehicleTypes.LIVERY.has(kind):
			paint = VehicleTypes.CAR_COLORS[[0, 5, 9, 7, 3, 1, 10, 6, 2, 11][i % 10]][0]
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(paint.r, paint.g, paint.b, 2.0))
		var w: float = VehicleTypes.spec(kind).width if VehicleTypes.SPECS.has(kind) else 2.6
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(x, Terrain.ground_y(x, row * 26.0), row * 26.0)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = VehicleMaterial.get_material(lod == VehicleModels.LOD_ULTRA)
		_main.add_child(mi)
		x += maxf(w, 2.0) + 2.5
		i += 1
		if x > 40.0:
			x = 0.0
			row += 1
	var cx := float(args[5]) if args.size() > 6 else 30.0
	var cz := float(args[6]) if args.size() > 6 else 10.0
	for c in _main.get_children():
		if c is TrafficView:
			c.process_mode = Node.PROCESS_MODE_DISABLED
		if c is RoadTool:
			c.process_mode = Node.PROCESS_MODE_DISABLED
			for k in c.get_children():
				if k is Node3D:
					k.visible = false
		if c is CityCamera:
			c.look_at_point(Vector3(cx, Terrain.ground_y(cx, cz), cz))
			c.set_view(deg_to_rad(float(args[1]) if args.size() > 1 else 30.0),
				deg_to_rad(float(args[2]) if args.size() > 2 else 30.0), float(args[3]) if args.size() > 3 else 70.0)
	_main.set_speed(0)
