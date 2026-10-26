extends SceneTree
## Ready-made people playing their walk (skeleton + animation from the GLB),
## four copies at different points of the stride.
## Run (in a window): godot --path . -s tools/people_anim_shot.gd -- out.png person.glb [dist]
var _frames := 0
var _players := []

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dist := float(a[2]) if a.size() > 2 else 6.0
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
	for k in 4:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_file(a[1], state)
		var node := doc.generate_scene(state) as Node3D
		node.position = Vector3((k - 1.5) * 1.2, 0, 0)
		node.rotation.y = PI * 0.5
		root.add_child(node)
		var ap := node.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			_players.append([ap[0], k])
	var cam := Camera3D.new()
	cam.fov = 45
	root.add_child(cam)
	var dir := Vector3(0, 0.25, 1).normalized()
	cam.look_at_from_position(Vector3(0, 0.9, 0) + dir * dist, Vector3(0, 0.9, 0), Vector3.UP)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		for pk in _players:
			var p: AnimationPlayer = pk[0]
			var names := p.get_animation_list()
			print("ANIMS ", names)
			if not names.is_empty():
				p.play(names[0])
				p.seek(p.current_animation_length * pk[1] / 4.0, true)
				p.pause()
	if _frames == 20:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
