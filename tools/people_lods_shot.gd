extends SceneTree
## The five levels of detail side by side (farthest version on the left),
## from a camera DIST metres off (default 40, the closest zoom).
## Run (in a window): godot --path . -s tools/people_lods_shot.gd -- out.png [dist]
var _frames := 0
var _wv: Node
var _mis := []

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dist := float(a[1]) if a.size() > 1 else 40.0
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.5, 0.25)
	ground.material_override = gm
	root.add_child(ground)
	_wv = WalkerView.new()
	root.add_child(_wv)
	_wv.set_process(false)
	for lod in 5:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = WalkerView._person_mesh(lod % 2, lod)
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis.looking_at(Vector3(0.3, 0, 1).normalized(), Vector3.UP), Vector3((lod - 2) * 1.1, 0, 0)))
		mm.set_instance_color(0, WalkerView.skin_tone(lod * 11 + 2))
		var c: Color = WalkerView.SHIRTS[lod * 3 % WalkerView.SHIRTS.size()]
		c.a = 0.2
		mm.set_instance_custom_data(0, c)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		root.add_child(mi)
		_mis.append(mi)
	var cam := Camera3D.new()
	var dir := Vector3(0, 0.5, 1).normalized()
	cam.fov = 45
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.9, 0) + dir * dist, Vector3(0, 0.9, 0), Vector3.UP)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		for mi in _mis:
			mi.material_override = (_wv.get_child(0) as MultiMeshInstance3D).material_override
	if _frames == 20:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "lods.png")
		quit()
	return false
