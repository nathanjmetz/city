extends Node3D
## Sets up the world: sky, sun, ground, roads, zones, buildings, camera and
## toolbar, and steps the simulation in fixed ticks. The town saves itself
## automatically (in the browser too).

signal speed_changed(speed: int)

const SAVE_PATH := "user://town.json"
## 0 = paused; 1, 2 and 3 run the clock at 1x, 2x and 4x.
const SPEEDS := [0.0, 1.0, 2.0, 4.0]

var sim := CitySim.new()
var _save_pending := false
var _tick_time := 0.0
var speed := 1
var _resume_speed := 1
var _save_wait := 0.0


func _ready() -> void:
	_build_environment()
	_build_ground()

	var roads := RoadView.new()
	add_child(roads)
	roads.setup(sim.network)

	var zone_view := ZoneView.new()
	zone_view.setup(sim)
	add_child(zone_view)

	var buildings := BuildingView.new()
	add_child(buildings)
	buildings.setup(sim)

	var service_view := ServiceView.new()
	add_child(service_view)
	service_view.setup(sim)
	sim.require_utilities = true

	var cars := TrafficView.new()
	cars.setup(sim.traffic, func(): return _tick_time * CitySim.TICKS_PER_SECOND)
	add_child(cars)

	var cam := CityCamera.new()
	add_child(cam)

	var road_tool := RoadTool.new()
	road_tool.setup(sim, cam)
	add_child(road_tool)

	var zone_tool := ZoneTool.new()
	zone_tool.setup(sim, cam, zone_view)
	add_child(zone_tool)

	var service_tool := ServiceTool.new()
	service_tool.setup(sim, cam, service_view)
	add_child(service_tool)

	# Only one tool is active at a time.
	var others := func(keep: Object):
		if keep != road_tool and road_tool.mode != RoadTool.Mode.NONE:
			road_tool.set_mode(RoadTool.Mode.NONE)
		if keep != zone_tool and zone_tool.zone != ZoneTool.OFF:
			zone_tool.set_zone(ZoneTool.OFF)
		if keep != service_tool and service_tool.kind != ServiceTool.OFF:
			service_tool.set_kind(ServiceTool.OFF)
	road_tool.mode_changed.connect(func(m): if m != RoadTool.Mode.NONE: others.call(road_tool))
	zone_tool.zone_changed.connect(func(z): if z != ZoneTool.OFF: others.call(zone_tool))
	service_tool.kind_changed.connect(func(k): if k != ServiceTool.OFF: others.call(service_tool))

	var hud := Hud.new()
	hud.setup(road_tool, zone_tool, sim, self)
	hud.service_tool = service_tool
	add_child(hud)

	if not _load():
		_starter_road()
	for sig in [sim.buildings_changed, sim.zones_changed, sim.network.changed, sim.stats_changed]:
		sig.connect(func(): _save_pending = true)


func _process(delta: float) -> void:
	_tick_time += delta * SPEEDS[speed]
	var step := 1.0 / CitySim.TICKS_PER_SECOND
	var guard := 0
	while _tick_time >= step and guard < 20:
		_tick_time -= step
		guard += 1
		sim.tick()
	_tick_time = minf(_tick_time, step)
	_save_wait -= delta
	if _save_pending and _save_wait <= 0.0:
		_save_pending = false
		_save_wait = 2.0
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(sim.to_dict()))


func set_speed(s: int) -> void:
	speed = clampi(s, 0, SPEEDS.size() - 1)
	if speed != 0:
		_resume_speed = speed
	speed_changed.emit(speed)


func _unhandled_input(event: InputEvent) -> void:
	# Space pauses and resumes, like Cities: Skylines.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_SPACE:
		set_speed(0 if speed != 0 else _resume_speed)


func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	sim.from_dict(data)
	return not sim.network.segments.is_empty()


## A road coming in from the edge of the map, like a highway exit.
func _starter_road() -> void:
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [-250, 0], "end": [-100, 0]})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})


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
