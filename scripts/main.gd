extends Node3D
## Sets up the world: sky, sun, ground, roads, zones, buildings, camera and
## toolbar, and steps the simulation in fixed ticks. A solo city saves itself
## automatically (in the browser too). In a shared region the server steps
## the city instead, and neighbors' cities and the chat appear.

signal speed_changed(speed: int)

## 0 = paused; 1, 2 and 3 run the clock at 1x, 2x and 4x.
const SPEEDS := [0.0, 1.0, 2.0, 4.0]

var sim := CitySim.new()
var _save_pending := false
var _tick_time := 0.0
var speed := 1
var _resume_speed := 1
var _save_wait := 0.0


func _ready() -> void:
	if Session.online():
		sim = Session.client.my_sim()
		sim.send_command = Session.client.send_command
	sim.require_utilities = true
	add_child(SkyLight.new())
	var terrain := TerrainView.new()
	add_child(terrain)

	var roads := RoadView.new()
	add_child(roads)
	roads.setup(sim.network)

	var zone_view := ZoneView.new()
	zone_view.setup(sim)
	add_child(zone_view)

	var buildings := BuildingView.new()
	add_child(buildings)
	buildings.setup(sim)

	var lot_alerts := LotAlerts.new()
	lot_alerts.setup(sim)
	add_child(lot_alerts)

	var service_view := ServiceView.new()
	add_child(service_view)
	service_view.setup(sim)

	var farm_view := FarmView.new()
	add_child(farm_view)
	farm_view.setup(sim)

	var industry_view := IndustryView.new()
	add_child(industry_view)
	industry_view.setup(sim)

	var cars := TrafficView.new()
	cars.setup(sim.traffic, _tick_fraction)
	add_child(cars)

	var signals := JunctionView.new()
	signals.setup(sim.traffic)
	add_child(signals)

	var flow_view := FlowView.new()
	flow_view.setup(sim.traffic)
	add_child(flow_view)

	var cam := CityCamera.new()
	add_child(cam)
	terrain.setup(cam.camera, sim.network)
	var forest := TerrainForest.new()
	forest.setup(cam.camera)
	# Woods clear off farm fields, farmyards and service sites, and grow back
	# when those go.
	forest.blocked = func(x: float, z: float) -> bool:
		var p := Vector3(x, 0.0, z)
		return sim.farms.field_at(p) != -1 or sim.farms.covers(p) or sim.services.covers(p)
	terrain.graded.connect(forest.refresh)
	sim.farms_changed.connect(forest.refresh_soon)
	add_child(forest)

	var audio := CityAudio.new()
	audio.setup(sim, cam.camera, func(): return _tick_time * CitySim.TICKS_PER_SECOND)
	add_child(audio)

	var ui_sounds := UiSounds.new()
	ui_sounds.setup(sim)
	add_child(ui_sounds)

	var info_view := InfoView.new()
	add_child(info_view)
	info_view.setup(sim, cam)

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
	farm_tool.setup(sim, cam, info_view)
	add_child(farm_tool)

	var industry_tool := IndustryTool.new()
	industry_tool.setup(sim, cam, info_view)
	add_child(industry_tool)

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
		if keep != industry_tool and industry_tool.kind != "":
			industry_tool.set_kind("")
		if keep != traffic_tool and traffic_tool.mode != TrafficTool.Mode.NONE:
			traffic_tool.set_mode(TrafficTool.Mode.NONE)
	# Picking a tool also plays the tool sound.
	var picked := func(tool: Object):
		others.call(tool)
		ui_sounds.play("tool")
	road_tool.mode_changed.connect(func(m): if m != RoadTool.Mode.NONE: picked.call(road_tool))
	zone_tool.zone_changed.connect(func(z): if z != ZoneTool.OFF: picked.call(zone_tool))
	service_tool.kind_changed.connect(func(k): if k != ServiceTool.OFF: picked.call(service_tool))
	farm_tool.mode_changed.connect(func(m): if m != FarmTool.Mode.NONE: picked.call(farm_tool))
	traffic_tool.mode_changed.connect(func(m): if m != TrafficTool.Mode.NONE: picked.call(traffic_tool))
	industry_tool.kind_changed.connect(func(k): if k != "": picked.call(industry_tool))

	var select_tool := SelectTool.new()
	select_tool.setup(sim, cam, func(): return road_tool.mode != RoadTool.Mode.NONE \
		or zone_tool.zone != ZoneTool.OFF or service_tool.kind != ServiceTool.OFF \
		or farm_tool.mode != FarmTool.Mode.NONE or traffic_tool.mode != TrafficTool.Mode.NONE \
		or industry_tool.kind != "")
	add_child(select_tool)

	var hud := Hud.new()
	hud.setup(road_tool, zone_tool, sim, self)
	hud.service_tool = service_tool
	hud.farm_tool = farm_tool
	hud.industry_tool = industry_tool
	hud.traffic_tool = traffic_tool
	hud.info_view = info_view
	hud.service_view = service_view
	hud.select_tool = select_tool
	hud.lot_alerts = lot_alerts
	add_child(hud)

	var menu := GameMenu.new()
	menu.game = self
	hud.nothing_to_close.connect(menu.toggle)
	add_child(menu)
	if Session.online():
		var region := RegionView.new()
		region.setup(Session.client, cam, road_tool)
		add_child(region)
		var chat := ChatPanel.new()
		chat.setup(cam, region)
		add_child(chat)
		return
	if not _load():
		_starter_road()
	for sig in [sim.buildings_changed, sim.zones_changed, sim.network.changed, sim.stats_changed, sim.farms_changed, sim.industry_changed]:
		sig.connect(func(): _save_pending = true)


func _process(delta: float) -> void:
	if Session.online():
		return  # The region's server steps the city.
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
		Session.save_city(sim)


## How far through the current tick the clock is, 0 to 1.
func _tick_fraction() -> float:
	if Session.online():
		return minf(Session.client.since_tick * CitySim.TICKS_PER_SECOND, 1.0)
	return _tick_time * CitySim.TICKS_PER_SECOND


func set_speed(s: int) -> void:
	if Session.online():
		return  # Everyone in a region shares one clock.
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
	if Session.save_path == "":
		# Started straight into the game (not from the title screen).
		var saves := Session.list_saves()
		Session.save_path = saves[0].path if not saves.is_empty() else Session.new_save_path("My Town")
		Session.current_name = Session.city_name()
	var data := Session._read(Session.save_path)
	if data.is_empty():
		return false
	sim.from_dict(data)
	return not sim.network.segments.is_empty()


## A road coming in from the edge of the map, like a highway exit.
## The highway link is free, as in Cities: Skylines.
func _starter_road() -> void:
	if Session.new_city_difficulty != "":
		sim.apply({"type": "set_difficulty", "difficulty": Session.new_city_difficulty})
		Session.new_city_difficulty = ""
	# A county highway runs through town and on to the region both ways.
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var money := sim.economy.money
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	sim.economy.money = money
