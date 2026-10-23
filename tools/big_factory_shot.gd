extends SceneTree
## Renders a big local factory on a plain street, for the art realism loop
## (compare with the real plants in docs/big_factories.md).
## Run: godot -s tools/big_factory_shot.gd -- out.png kind [level] [yaw pitch dist]

var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "ethanol"
	var level := int(args[2]) if args.size() > 2 else 0
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	var f := {"kind": kind, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "level": level, "bays": 0}
	var d := BigFactories.site_depth(f)
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 9.0)
	road.mesh = plane
	road.material_override = Surfaces.asphalt()
	road.position = Vector3(0, 0.09, -d * 0.5 - 8.4)
	world.add_child(road)
	var built := BigFactoryBuilder.build_plant(f, 7, 3.9)
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = built[i]
		mi.position.y = 0.0 if i == 0 else 0.15  # clear of the ground's own relief
		world.add_child(mi)
	var trees := TreeField.new()
	world.add_child(trees)
	var planted := []
	for t in built[2]:
		planted.append([Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
	trees.set_trees("p", planted)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 3000.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[3])) if args.size() > 5 else deg_to_rad(-30.0)
	var pitch := deg_to_rad(float(args[4])) if args.size() > 5 else deg_to_rad(32.0)
	var dist := float(args[5]) if args.size() > 5 else d * 1.5
	var target := Vector3(0, 5, 0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "plant.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
