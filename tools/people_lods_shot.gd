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
	# Ready-made people (glTF files), if given: GLB=path1,path2 in the env.
	var glbs := OS.get_environment("GLB")
	var gi := 0
	for path in (glbs.split(",") if glbs != "" else []):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			continue
		var node := doc.generate_scene(state) as Node3D
		var only := OS.get_environment("ONLY_GLB") != ""
		node.position = Vector3((gi - 2.5) * 1.0 if only else 3.0 + gi * 1.0, 0, 0)
		node.rotation.y = 0.3
		root.add_child(node)
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var mi3 := m as MeshInstance3D
			if mi3.get_active_material(0) == null or OS.get_environment("SKIN") != "":
				var sm := StandardMaterial3D.new()
				sm.albedo_color = Color(0.78, 0.6, 0.5)
				sm.roughness = 0.7
				mi3.material_override = sm
		gi += 1
	var cam := Camera3D.new()
	var dir := Vector3(0, 0.5, 1).normalized()
	cam.fov = 45
	root.add_child(cam)
	var aim := Vector3(0.0 if OS.get_environment("ONLY_GLB") != "" else 1.4 if glbs != "" else 0.0, 0.9, 0)
	if OS.get_environment("ONLY_GLB") != "":
		for mi in _mis:
			mi.visible = false
	cam.look_at_from_position(aim + dir * dist, aim, Vector3.UP)

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
