extends SceneTree
## A row of people up close, for judging how they look.
## Run (in a window): godot --path . -s tools/people_shot.gd -- out.png
var _frames := 0
var _mi: MultiMeshInstance3D
var _wv: Node

func _init() -> void:
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
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.5, 0.25)
	ground.material_override = gm
	root.add_child(ground)
	var wv := WalkerView.new()
	root.add_child(wv)
	wv.set_process(false)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = WalkerView._person_mesh(int(OS.get_environment("FIGURE")) if OS.get_environment("FIGURE") != "" else 0)
	mm.instance_count = 5
	for i in 5:
		var b := WalkerView.build(i * 7 + 3)
		var face := Vector3(0.6 * (i - 2) * 0.3, 0, 1).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(face, Vector3.UP).scaled(b), Vector3((i - 2) * 0.9, 0, 0)))
		mm.set_instance_color(i, Color.WHITE)
		var c: Color = WalkerView.SHIRTS[i * 3 % WalkerView.SHIRTS.size()]
		c.a = [0.0, 0.25, 0.5, 0.75, 0.1][i]
		mm.set_instance_custom_data(i, c)
	_mi = MultiMeshInstance3D.new()
	_mi.multimesh = mm
	_wv = wv
	root.add_child(_mi)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 4.2)
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0), Vector3.UP)
	cam.fov = 45
	root.add_child(cam)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		_mi.material_override = (_wv.get_child(0) as MultiMeshInstance3D).material_override
	if _frames == 20:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "people.png")
		quit()
	return false
