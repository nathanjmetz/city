extends SceneTree
## One county farmstead close up on a flat test field, built the way
## FarmsteadNear builds it, in seconds rather than a whole county's load:
## for checking the close-up against photos of real farmsteads.
## Run: godot -s tools/farmsteads/farmstead_shot.gd -- out.png [kind] [n] [yaw pitch dist] [photo]
##   kind: grain, hog, dairy, retired or home; n: the n-th farmstead of that
##   kind (with a dryer, for grain) going through seeds; yaw, pitch in
##   degrees and dist in metres about the yard's middle. "photo" turns on
##   the desktop High+ photo ground; a month (1-12) after it parks the
##   machines for that month (FarmsteadParked); "house", "shed" or "barn"
##   after that looks at the farmhouse, the first machine shed or the barn
##   instead of the yard.

var _frames := 0


func _init() -> void:
	pass


## Built on the second frame, once the graphics tier has been picked, so
## "photo" can lift it to Ultra.
func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "grain"
	var n := int(args[2]) if args.size() > 2 else 0
	if args.size() > 6 and args[6] == "photo":
		if GraphicsQuality.current != null:
			GraphicsQuality.current.tier = GraphicsQuality.ULTRA
			GraphicsQuality.current.apply()
		GraphicsQuality.budget["photo"] = true
	var plan := {}
	for seed in 4000:
		var p := FarmsteadPlan.grow(Vector2(1000.0 + seed * 37.0, 2000.0), true, 0.0, seed % 256)
		if p.kind != kind:
			continue
		if kind == "grain" and not p.parts.any(func(q): return q.kind == "dryer"):
			continue
		if n == 0:
			plan = p
			break
		n -= 1
	print("farmstead: ", plan.kind, " ", plan.house.get("type", ""), " ", plan.parts.map(func(q): return q.kind))
	RenderingServer.global_shader_parameter_set("snow", 0.0)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	var b := FarmBuilder.county(plan)
	for i in b.steps():
		b.step(i)
	var meshes := b.commit()
	var node := Node3D.new()
	world.add_child(node)
	for i in meshes.size():
		if meshes[i] != null and meshes[i].get_surface_count() > 0:
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[i]
			node.add_child(mi)
	var month := int(args[7]) if args.size() > 7 else 7
	FarmsteadParked.add_to(node, plan, month, func(_q): return 0.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.5
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[3]) if args.size() > 5 else 200.0)
	var pitch := deg_to_rad(float(args[4]) if args.size() > 5 else 20.0)
	var dist := float(args[5]) if args.size() > 5 else 70.0
	var ext: Rect2 = plan.extent
	var target := Vector3(ext.get_center().x, 3.0, ext.get_center().y)
	if args.size() > 8 and args[8] == "house":
		target = Vector3(plan.house.x, 3.0, plan.house.d * 0.5)
	elif args.size() > 8 and args[8] in ["shed", "barn", "quonset"]:
		var kinds: Array = ["shed", "quonset"] if args[8] != "barn" else ["barn"]
		for q in plan.parts:
			if q.kind in kinds:
				target = Vector3(q.pos.x, 3.0, q.pos.y)
				break
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_build()
	if _frames == 40:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "farmstead.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
