extends SceneTree
## A row of the ready-made close-up people (NearPeople) dressed as the town
## dresses them for a month, beside their far figures (WalkerView), for
## judging that each person looks the same near and far.
## Run (in a window): godot -s tools/near_people_shot.gd -- out.png
## MONTH=1-12, SEED shifts who's in the row, N people (default 8).
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
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.55, 0.53)
	ground.material_override = gm
	root.add_child(ground)
	var month := int(OS.get_environment("MONTH")) if OS.get_environment("MONTH") != "" else 7
	var seed := int(OS.get_environment("SEED"))
	var count := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 8
	var np := NearPeople.new()
	root.add_child(np)
	np.setup(null, func(): return 0.0)
	# The walkers' shader, without a town to draw.
	var wv := WalkerView.new()
	wv._ready()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = WalkerView._person_mesh(0, 3)
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_colors = true
	mm2.use_custom_data = true
	mm2.mesh = WalkerView._person_mesh(1, 3)
	var rows := [[], []]
	for i in count:
		var person := seed + i * 37 + 5
		var worn := WalkerView.dress(person, month, 20 + (i * 11) % 60)
		var e := np._take(np._model_for(person, int(worn[1])))
		e.walker = person
		NearPeople._wear(e, worn)
		var x := (i - (count - 1) * 0.5) * 1.1
		(e.node as Node3D).position = Vector3(x, 0, 0)
		(e.node as Node3D).rotation.y = deg_to_rad(10.0)
		var c: Color = worn[0]
		c.a = 0.25 + float(worn[1])
		var body := WalkerView.build(person)
		body = Vector3(body.x, maxf(body.y, 0.95), body.z)
		rows[WalkerView.figure(person)].append([Transform3D(Basis(Vector3.UP, PI + deg_to_rad(10.0)).scaled(body), Vector3(x, 0, -2.2)), c])
	for k in 2:
		var m: MultiMesh = [mm, mm2][k]
		m.instance_count = rows[k].size()
		for i in rows[k].size():
			m.set_instance_transform(i, rows[k][i][0])
			m.set_instance_color(i, Color.WHITE)
			m.set_instance_custom_data(i, rows[k][i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = m
		mi.material_override = (wv.get_child(0) as MultiMeshInstance3D).material_override
		root.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.4, 9.5), Vector3(0, 0.9, -1.0), Vector3.UP)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 30:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "near_people.png")
		quit()
	return false
