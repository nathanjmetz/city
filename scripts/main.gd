extends Node3D
## Sets up the world: sky, sun, ground, roads, houses, camera and toolbar.
## The town saves itself automatically (in the browser too).

const SAVE_PATH := "user://town.json"

var network := RoadNetwork.new()
var _save_pending := false


func _ready() -> void:
	_build_environment()
	_build_ground()

	var roads := RoadView.new()
	add_child(roads)
	roads.setup(network)

	var houses := HouseSpawner.new()
	add_child(houses)
	houses.setup(network)

	var cam := CityCamera.new()
	add_child(cam)

	var tool := RoadTool.new()
	tool.setup(network, cam)
	add_child(tool)

	var hud := Hud.new()
	hud.setup(tool, network, houses)
	add_child(hud)

	if not _load():
		_starter_road()
	network.changed.connect(func(): _save_pending = true)


func _process(_delta: float) -> void:
	if _save_pending:
		_save_pending = false
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(network.to_dict()))


func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY or data.get("segments", {}).is_empty():
		return false
	network.from_dict(data)
	return true


## A road coming in from the edge of the map, like a highway exit.
func _starter_road() -> void:
	network.build_road(Vector3(-400, 0, 0), Vector3(-250, 0, 0), Vector3(-100, 0, 0))
	network.build_road(Vector3(-100, 0, 0), Vector3(-20, 0, 0), Vector3(40, 0, 60))


func _build_environment() -> void:
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
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)


func _build_ground() -> void:
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
	mat.uv1_scale = Vector3(300, 300, 1)
	mat.roughness = 1.0

	var plane := PlaneMesh.new()
	plane.size = Vector2(8000, 8000)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)
