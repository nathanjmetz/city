class_name Scenery
extends RefCounted
## Sky, sun and ground, shared by the game and the title screen.


static func add_sky_and_sun(parent: Node) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky_mat.ground_horizon_color = Color(0.72, 0.80, 0.88)
	sky_mat.ground_bottom_color = Color(0.30, 0.34, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.88)
	env.fog_density = 0.0004
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	parent.add_child(sun)


static func add_ground(parent: Node, size := 8000.0) -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	var grad := Gradient.new()
	grad.set_color(0, Color(0.20, 0.30, 0.12))
	grad.set_color(1, Color(0.30, 0.40, 0.17))
	tex.color_ramp = grad

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(size / 26.67, size / 26.67, 1)
	mat.roughness = 1.0

	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	parent.add_child(ground)
