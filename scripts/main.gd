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
var _snapshot: TownSnapshot  # an autosave under way
## Online, a copy of your town goes to the region this often, in seconds.
const TOWN_SEND_EVERY := 10.0
## Played offline, the town saves itself this often, in seconds, when it
## changed (a save stops play for about 0.1 s in a small town, 0.4 s in a
## big one). The pause menu's Save, Main menu and Quit save at once.
const SAVE_EVERY := 30.0
## True until the whole town is built and drawn; the clock waits for it.
var loading := true


func _ready() -> void:
	if Session.online():
		sim = Session.client.my_sim()
	sim.require_utilities = true
	var sky := SkyLight.new()
	add_child(sky)
	var terrain := TerrainView.new()
	add_child(terrain)
	# Bulldozed county miles stop being painted. (A joined one stays: the
	# town's gravel road covers it as far as it runs.)
	var hide_county := func() -> void:
		TerrainView.set_county_hidden(sim.county_removed.keys())
	hide_county.call()
	sim.county_changed.connect(hide_county)

	var roads := RoadView.new()
	add_child(roads)
	roads.setup(sim.network, sim)
	var street_signs := StreetSignView.new()
	add_child(street_signs)
	street_signs.setup(sim)
	var welcome := WelcomeSignView.new()
	add_child(welcome)
	welcome.setup(sim)
	# Roadside historical markers for the town's firsts.
	var markers := MarkerView.new()
	add_child(markers)
	markers.setup(sim)

	var zone_view := ZoneView.new()
	zone_view.setup(sim)
	add_child(zone_view)

	var buildings := BuildingView.new()
	add_child(buildings)
	buildings.setup(sim)

	var wild := WildView.new()
	add_child(wild)
	wild.setup(sim)

	var lot_alerts := LotAlerts.new()
	lot_alerts.setup(sim)
	add_child(lot_alerts)

	var service_view := ServiceView.new()
	add_child(service_view)
	service_view.setup(sim)

	var park_view := ParkView.new()
	add_child(park_view)
	park_view.setup(sim)

	var farm_view := FarmView.new()
	add_child(farm_view)
	farm_view.setup(sim)

	var industry_view := IndustryView.new()
	add_child(industry_view)
	industry_view.setup(sim)
	var power_view := PowerView.new()
	add_child(power_view)
	power_view.setup(sim)

	var warehouse_view := WarehouseView.new()
	add_child(warehouse_view)
	warehouse_view.setup(sim)
	var big_view := BigFactoryView.new()
	add_child(big_view)
	big_view.setup(sim)

	var campus_view := CampusView.new()
	add_child(campus_view)
	campus_view.setup(sim)

	var telecom_view := TelecomView.new()
	add_child(telecom_view)
	telecom_view.setup(sim)
	var bank_view := BankView.new()
	add_child(bank_view)
	bank_view.setup(sim)

	var cars := TrafficView.new()
	cars.setup(sim.traffic, _tick_fraction)
	cars.parked = func(): return sim.construction.parked_poses()
	add_child(cars)

	var bus_view := BusView.new()
	bus_view.setup(sim)
	add_child(bus_view)

	var rail_view := RailView.new()
	rail_view.setup(sim, terrain)
	add_child(rail_view)
	var walkers := WalkerView.new()
	walkers.setup(sim.traffic, _tick_fraction)
	add_child(walkers)

	var look := DayNight.new()
	look.setup(sim, sky, _tick_fraction)
	add_child(look)

	var signals := JunctionView.new()
	signals.setup(sim.traffic)
	signals.roads = roads
	add_child(signals)

	var flow_view := FlowView.new()
	flow_view.setup(sim.traffic)
	add_child(flow_view)

	var cam := CityCamera.new()
	add_child(cam)
	terrain.setup(cam.camera, sim.network)
	terrain.graded.connect(wild.regraded)
	# The county highways run on past the town's links to the horizon.
	var exits := ExitRoads.new()
	add_child(exits)
	exits.setup(sim, terrain, "exits")
	# Wild trees and brush (WildView) grow from the real land cover; past
	# where they're drawn, the ground paints the woods' canopy.
	Vegetation.cover_source = func(p: Vector3) -> Array:
		var x := p.x + sim.terrain_offset.x
		var z := p.z + sim.terrain_offset.y
		return Terrain.wild_cover(x, z) + [Terrain.crops(x, z)]

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

	var hub_view := HubView.new()
	hub_view.setup(sim)
	add_child(hub_view)

	var mail_view := MailView.new()
	mail_view.setup(sim)
	add_child(mail_view)

	var service_tool := ServiceTool.new()
	service_tool.setup(sim, cam, service_view)
	add_child(service_tool)

	var farm_tool := FarmTool.new()
	farm_tool.setup(sim, cam, info_view)
	add_child(farm_tool)

	var industry_tool := IndustryTool.new()
	industry_tool.setup(sim, cam, info_view)
	add_child(industry_tool)

	var warehouse_tool := WarehouseTool.new()
	warehouse_tool.setup(sim, cam)
	add_child(warehouse_tool)
	var big_tool := BigFactoryTool.new()
	big_tool.setup(sim, cam)
	add_child(big_tool)
	var park_tool := ParkTool.new()
	park_tool.setup(sim, cam)
	add_child(park_tool)

	var campus_tool := CampusTool.new()
	campus_tool.setup(sim, cam)
	add_child(campus_tool)

	var telecom_tool := TelecomTool.new()
	telecom_tool.setup(sim, cam)
	add_child(telecom_tool)
	var bank_tool := BankTool.new()
	bank_tool.setup(sim, cam)
	add_child(bank_tool)

	var traffic_tool := TrafficTool.new()
	traffic_tool.setup(sim, cam, flow_view)
	add_child(traffic_tool)

	var move_tool := MoveTool.new()
	move_tool.setup(sim, cam)
	add_child(move_tool)
	var neighborhood_tool := NeighborhoodTool.new()
	neighborhood_tool.setup(sim, cam)
	add_child(neighborhood_tool)

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
		if keep != campus_tool and campus_tool.kind != "":
			campus_tool.set_kind("")
		if keep != telecom_tool and telecom_tool.kind != "":
			telecom_tool.set_kind("")
		if keep != bank_tool and bank_tool.kind != "":
			bank_tool.set_kind("")
		if keep != warehouse_tool and warehouse_tool.kind != "":
			warehouse_tool.set_kind("")
		if keep != big_tool and big_tool.kind != "":
			big_tool.set_kind("")
		if keep != traffic_tool and traffic_tool.mode != TrafficTool.Mode.NONE:
			traffic_tool.set_mode(TrafficTool.Mode.NONE)
		if keep != park_tool and park_tool.kind != "":
			park_tool.set_kind("")
		if keep != move_tool and move_tool.active:
			move_tool.set_active(false)
		if keep != neighborhood_tool and neighborhood_tool.kind != "":
			neighborhood_tool.set_kind("")
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
	campus_tool.kind_changed.connect(func(k): if k != "": picked.call(campus_tool))
	telecom_tool.kind_changed.connect(func(k): if k != "": picked.call(telecom_tool))
	bank_tool.kind_changed.connect(func(k): if k != "": picked.call(bank_tool))
	warehouse_tool.kind_changed.connect(func(k): if k != "": picked.call(warehouse_tool))
	big_tool.kind_changed.connect(func(k): if k != "": picked.call(big_tool))
	park_tool.kind_changed.connect(func(k): if k != "": picked.call(park_tool))
	move_tool.active_changed.connect(func(on): if on: picked.call(move_tool))
	neighborhood_tool.kind_changed.connect(func(k): if k != "": picked.call(neighborhood_tool))

	# Consequences before you commit: a polluting tool shows the wind and the
	# smoke and noise it would make; zoning homes or shops shows what is
	# already in the air there (PlacementHints).
	var hints := PlacementHints.new()
	hints.setup(sim, cam, func() -> Dictionary:
		if industry_tool.kind == "power":
			return {"source": "power_" + industry_tool.likely} if industry_tool.likely != "" else {"wind": true}
		if industry_tool.kind != "":
			return {"source": industry_tool.kind}
		if zone_tool.zone == ZoneMap.Zone.INDUSTRIAL:
			return {"source": "factory"}
		if zone_tool.zone == ZoneMap.Zone.RESIDENTIAL or zone_tool.zone == ZoneMap.Zone.COMMERCIAL:
			return {"spot": true}
		if Balance.POLLUTION_SOURCES.has(CivicHubs.TOOL_KINDS.get(service_tool.kind, "")):
			return {"source": CivicHubs.TOOL_KINDS[service_tool.kind]}
		if info_view.mode == InfoView.Mode.SMOKE:
			return {"wind": true}
		return {})
	add_child(hints)

	var select_tool := SelectTool.new()
	select_tool.setup(sim, cam, func(): return road_tool.mode != RoadTool.Mode.NONE \
		or zone_tool.zone != ZoneTool.OFF or service_tool.kind != ServiceTool.OFF \
		or farm_tool.mode != FarmTool.Mode.NONE or traffic_tool.mode != TrafficTool.Mode.NONE \
		or industry_tool.kind != "" or warehouse_tool.kind != "" or park_tool.kind != "" or campus_tool.kind != "" or bank_tool.kind != "" or telecom_tool.kind != "" or move_tool.active \
		or neighborhood_tool.kind != "" or big_tool.kind != "")
	add_child(select_tool)

	var water_view := WaterView.new()
	add_child(water_view)
	water_view.setup(sim, select_tool, service_tool)

	var hud := Hud.new()
	hud.setup(road_tool, zone_tool, sim, self)
	hud.service_tool = service_tool
	hud.farm_tool = farm_tool
	hud.industry_tool = industry_tool
	hud.campus_tool = campus_tool
	hud.telecom_tool = telecom_tool
	hud.bank_tool = bank_tool
	hud.warehouse_tool = warehouse_tool
	hud.big_tool = big_tool
	hud.park_tool = park_tool
	hud.traffic_tool = traffic_tool
	hud.move_tool = move_tool
	hud.neighborhood_tool = neighborhood_tool
	hud.info_view = info_view
	hud.service_view = service_view
	hud.bus_view = bus_view
	hud.rail_view = rail_view
	hud.select_tool = select_tool
	hud.lot_alerts = lot_alerts
	add_child(hud)

	# Hidden performance readout (F3).
	add_child(PerfOverlay.new())

	var menu := GameMenu.new()
	menu.game = self
	hud.nothing_to_close.connect(menu.toggle)
	add_child(menu)
	_progress(0.35, "Laying out the land")
	await get_tree().process_frame
	if Session.online():
		var region := RegionView.new()
		region.setup(Session.client, cam, road_tool)
		region.terrain = terrain
		region.exits = exits
		add_child(region)
		var chat := ChatPanel.new()
		chat.setup(cam, region)
		add_child(chat)
		hud.add_top_button(chat.make_button())
		await _settle()
		return
	_progress(0.5, "Opening your town")
	await get_tree().process_frame
	if not _load():
		_starter_road()
	await _settle()
	for sig in [sim.buildings_changed, sim.zones_changed, sim.network.changed, sim.stats_changed, sim.farms_changed, sim.water_changed,
			sim.industry_changed, sim.warehouses_changed, sim.parks_changed, sim.education_changed, sim.power_changed, sim.banks_changed,
			sim.telecom_changed, sim.big_factories_changed]:
		sig.connect(func(): _save_pending = true)


## The loading screen (the branding thread's LoadingScreen), if one is up.
func _progress(fraction: float, status := "") -> void:
	var screen := get_tree().root.get_node_or_null("LoadingScreen")
	if screen != null and screen.has_method("set_progress"):
		screen.set_progress(fraction, status)


## Gives every view a few frames to finish drawing the town (houses, farms,
## industry, trees), then lifts the loading screen and starts the clock.
func _settle() -> void:
	_progress(0.75, "Building the town")
	await get_tree().process_frame
	_progress(0.9, "Planting trees")
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := get_tree().root.get_node_or_null("LoadingScreen")
	if screen != null and screen.has_method("finish"):
		screen.finish()
	loading = false
	# A brand-new town gets the guided first town.
	get_tree().call_group("first_town_tour", "maybe_start")


func _process(delta: float) -> void:
	if loading:
		return
	_tick_time += delta * SPEEDS[speed]
	var step := 1.0 / CitySim.TICKS_PER_SECOND
	var guard := 0
	var t := Perf.now()
	# (A town being saved holds still for a few frames: see TownSnapshot.)
	while _tick_time >= step and guard < 20 and not sim.held:
		_tick_time -= step
		guard += 1
		sim.tick()
	Perf.add("frame.sim", t)
	_tick_time = minf(_tick_time, step)
	_save_wait -= delta
	if Session.online():
		# Your town runs here; the region keeps a copy for the neighbors.
		if _save_wait <= 0.0:
			_save_wait = TOWN_SEND_EVERY
			Session.client.send_town()
	elif _snapshot:
		# A save a few parts per frame, so a big town never freezes.
		if _snapshot.step():
			Session.save_city(sim, Session.save_path, _snapshot.bytes())
			_snapshot = null
	elif _save_pending and _save_wait <= 0.0:
		_save_pending = false
		_save_wait = SAVE_EVERY
		_snapshot = TownSnapshot.new(sim)


## How far through the current tick the clock is, 0 to 1.
func _tick_fraction() -> float:
	return _tick_time * CitySim.TICKS_PER_SECOND


func set_speed(s: int) -> void:
	speed = clampi(s, 0, SPEEDS.size() - 1)
	if speed != 0:
		_resume_speed = speed
	speed_changed.emit(speed)


## Pauses, or resumes at the last speed.
func toggle_pause() -> void:
	set_speed(0 if speed != 0 else _resume_speed)


func _unhandled_input(event: InputEvent) -> void:
	# Space pauses and resumes, like Cities: Skylines.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_SPACE:
		toggle_pause()


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
