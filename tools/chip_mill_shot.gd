extends SceneTree
## Renders the logging company's yard with its wood chip mill, for the art
## realism loop (compare with a real chip mill: chipper, chip pile, chip van).
## Run: godot -s tools/chip_mill_shot.gd -- out.png [yaw pitch dist]

var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	var built := ForestryBuilder.mill(7, Industry.HQ_SIZE, ["log_yard", "chip_plant"])
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = built[i]
		mi.position.y = 0.0 if i == 0 else 0.15
		world.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 3000.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[1])) if args.size() > 3 else deg_to_rad(-30.0)
	var pitch := deg_to_rad(float(args[2])) if args.size() > 3 else deg_to_rad(32.0)
	var dist := float(args[3]) if args.size() > 3 else 110.0
	var target := Vector3(0, 3, 0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "chip_mill.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
