extends SceneTree
## Seated people (WalkerView.SEATED) on a bench and porch chairs, beside a
## standing one, for judging the sitting pose against photos.
## Run (in a window): godot -s tools/seated_shot.gd -- out.png
## MONTH=1-12; YAW camera angle round them in degrees (default 30).
var _frames := 0


func _init() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	_box(Vector3(0, -0.01, 0), Vector3(30, 0.02, 30), Color(0.55, 0.55, 0.53))
	var month := int(OS.get_environment("MONTH")) if OS.get_environment("MONTH") != "" else 7
	var wv := WalkerView.new()
	wv._ready()
	# A bench (as AmbientLife's) and two porch chairs, all facing +Z.
	_box(Vector3(-1.2, 0.22, 0), Vector3(1.8, 0.45, 0.5), Color(0.42, 0.3, 0.18))
	for x in [1.0, 1.9]:
		_box(Vector3(x, 0.22, 0.1), Vector3(0.55, 0.45, 0.5), Color(0.86, 0.85, 0.8))
		_box(Vector3(x, 0.7, -0.15), Vector3(0.55, 0.55, 0.05), Color(0.86, 0.85, 0.8))
	var spots := [[Vector3(-1.6, 0, -0.12), true], [Vector3(-0.8, 0, -0.12), true], [Vector3(1.0, 0, 0.0), true],
		[Vector3(1.9, 0, 0.0), true], [Vector3(3.2, 0, 0.0), false]]
	var rows := [[], []]
	for i in spots.size():
		var person := 11 + i * 37
		var worn := WalkerView.dress(person, month, 30 + i * 9)
		var c: Color = worn[0]
		c.a = float(int(worn[1]) | (WalkerView.SEATED if spots[i][1] else 0))
		rows[WalkerView.figure(person)].append([Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), spots[i][0]), c])
	for k in 2:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.use_custom_data = true
		m.mesh = WalkerView._person_mesh(k, 3)
		m.instance_count = rows[k].size()
		for i in rows[k].size():
			m.set_instance_transform(i, rows[k][i][0])
			m.set_instance_color(i, WalkerView.skin_tone(i * 5))
			m.set_instance_custom_data(i, rows[k][i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = m
		mi.material_override = (wv.get_child(0) as MultiMeshInstance3D).material_override
		root.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 30.0)
	cam.look_at_from_position(Vector3(sin(yaw) * 6.5, 1.8, cos(yaw) * 6.5) + Vector3(0.8, 0, 0), Vector3(0.8, 0.6, 0), Vector3.UP)


func _box(c: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = c
	root.add_child(mi)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 30:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "seated.png")
		quit()
	return false
