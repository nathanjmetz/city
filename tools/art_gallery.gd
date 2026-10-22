extends SceneTree
## Renders a row of generated buildings on a plain street for the art
## realism loop, so they can be compared side by side with real photos.
## Run: godot -s tools/art_gallery.gd -- out.png [house|shop|factory] [seed] [yaw pitch dist]

var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "house"
	var seed := int(args[2]) if args.size() > 2 else 1
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	# A street along x in front of the lots (lots face -z, toward it).
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 9.0)
	road.mesh = plane
	road.material_override = Surfaces.asphalt()
	road.position = Vector3(0, 0.09, -8.4)
	world.add_child(road)
	var trees := TreeField.new()
	world.add_child(trees)
	for i in 5:
		var meshes: Array
		match kind:
			"shop": meshes = CommercialBuilder.build_shop(seed * 100 + i, 3.9)
			"factory": meshes = CommercialBuilder.build_factory(seed * 100 + i, 3.9)
			_: meshes = HouseBuilder.build(seed * 100 + i, 3.9)
		var at := Vector3((i - 2) * 20.0, 0, 0)
		for m in meshes.slice(0, 2):
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.position = at
			world.add_child(mi)
		var planted := []
		for t in meshes[2]:
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), at + t[0])
			planted.append([xf, t[1], t[2]])
		trees.set_trees(str(i), planted)
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[3])) if args.size() > 5 else deg_to_rad(20.0)
	var pitch := deg_to_rad(float(args[4])) if args.size() > 5 else deg_to_rad(18.0)
	var dist := float(args[5]) if args.size() > 5 else 70.0
	var target := Vector3(0, 3, 8)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "gallery.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
