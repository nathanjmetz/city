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

	var farm_view := FarmView.new()
	add_child(farm_view)
	farm_view.setup(sim)

	var cars := TrafficView.new()
	cars.setup(sim.traffic, func(): return _tick_time * CitySim.TICKS_PER_SECOND)
	add_child(cars)

	var signals := JunctionView.new()
	signals.setup(sim.traffic)
	add_child(signals)

	var flow_view := FlowView.new()
	flow_view.setup(sim.traffic)
	add_child(flow_view)

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

	var farm_tool := FarmTool.new()
	farm_tool.setup(sim, cam, farm_view)
	add_child(farm_tool)

	var traffic_tool := TrafficTool.new()
	traffic_tool.setup(sim, cam, flow_view)
	add_child(traffic_tool)

	# Only one tool is active at a time.
	var others := func(keep: Object):
		if keep != road_tool and road_tool.mode != RoadTool.Mode.NONE:
			road_tool.set_mode(RoadTool.Mode.NONE)
		if keep != zone_tool and zone_tool.zone != ZoneTool.OFF:
			zone_tool.set_zone(ZoneTool.OFF)
		if keep != service_tool and service_tool.kind != ServiceTool.OFF:
			service_tool.set_kind(ServiceTool.OFF)
		if keep != farm_tool and farm_tool.mode != FarmTool.Mode.NONE:
			farm_tool.set_mode(FarmTool.Mode.NONE)
		if keep != traffic_tool and traffic_tool.mode != TrafficTool.Mode.NONE:
			traffic_tool.set_mode(TrafficTool.Mode.NONE)
	road_tool.mode_changed.connect(func(m): if m != RoadTool.Mode.NONE: others.call(road_tool))
	zone_tool.zone_changed.connect(func(z): if z != ZoneTool.OFF: others.call(zone_tool))
	service_tool.kind_changed.connect(func(k): if k != ServiceTool.OFF: others.call(service_tool))
	farm_tool.mode_changed.connect(func(m): if m != FarmTool.Mode.NONE: others.call(farm_tool))
	traffic_tool.mode_changed.connect(func(m): if m != TrafficTool.Mode.NONE: others.call(traffic_tool))

	var hud := Hud.new()
	hud.setup(road_tool, zone_tool, sim, self)
	hud.service_tool = service_tool
	hud.farm_tool = farm_tool
	hud.traffic_tool = traffic_tool
	add_child(hud)

	if not _load():
		_starter_road()
	for sig in [sim.buildings_changed, sim.zones_changed, sim.network.changed, sim.stats_changed, sim.farms_changed]:
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
## The highway link is free, as in Cities: Skylines.
func _starter_road() -> void:
	var money := sim.economy.money
	sim.apply({"type": "build_road", "start": [-400, 0], "ctrl": [-250, 0], "end": [-100, 0]})
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	sim.economy.money = money


func _build_environment() -> void:
	add_child(SkyLight.new())


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
