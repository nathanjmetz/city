extends SceneTree
## Pictures of the town's story for checking the look: the Town panel, a
## leader's ask on the bell, a historical marker up close, and the timelapse.
## Run: godot -s tools/heritage_shot.gd -- town|ask|marker|timelapse out.png

var _frames := 0
var _mode := "town"
var _out := "heritage.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "town"
	_out = args[1] if args.size() > 1 else "heritage.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Heritage Shot")
	session.current_name = "Lyons Mill"
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var main := current_scene
		var sim: CitySim = main.sim
		sim.simulate_traffic = false
		sim.require_utilities = false
		sim.apply({"type": "build_road", "start": [-160, 60], "ctrl": [0, 60], "end": [160, 60], "road": RoadStyle.Type.MAIN_STREET})
		sim.apply({"type": "build_road", "start": [0, -120], "ctrl": [0, -30], "end": [0, 60]})
		for x in range(-160, 161, 10):
			sim.apply({"type": "paint_zone", "center": [x, 35], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply({"type": "paint_zone", "center": [x, 85], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
		for i in 900:
			sim.tick()
		for key in sim.empty_zoned_lots():
			var z: int = sim.zones.zone_at(sim.lots[key].zone_pt)
			if z != ZoneMap.Zone.RESIDENTIAL:
				sim.found_business(key, z)
		for i in 900:
			sim.tick()
		# Years go by, a month at a time, for the record.
		sim.stats.population = 400
		for m in 140:
			sim.tick_count += 24 * CitySim.TICKS_PER_HOUR
			if m == 70:
				for k in sim.buildings.keys():
					if BuildingTypes.type_of(sim.buildings[k]) == "shop" and hash(k) % 2 == 0:
						sim.redevelop(k, "mixed_use", 0)
			sim.town_month()
		sim.buildings_changed.emit()
		main.set_speed(0)  # hold still for the picture
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		var cam: CityCamera = hud.info_view.cam
		cam.set_view(0.6, 0.9, 300.0)
		cam.look_at_point(Vector3(0, 0, 60))
		match _mode:
			"town":
				for id in sim.heritage.districts:
					if sim.heritage.districts[id].state == "eligible":
						sim.apply({"type": "heritage", "district": id, "protect": true})
						break
				hud.town.open_panel()
			"ask":
				# Months went by unanswered above: bring the asks back.
				for r in sim.permits.listed(Permits.State.SHELVED):
					r.state = Permits.State.OPEN
					r.filed = sim.tick_count
				hud.permits.open_panel()
				var open := sim.permits.listed(Permits.State.OPEN)
				if not open.is_empty():
					hud.permits.call("_select", int(open[0].id))
			"marker":
				var m: Dictionary = sim.markers.markers[0]
				cam.set_view(0.35, 0.25, 14.0)
				cam.look_at_point(Vector3(float(m.pos[0]), 1.5, float(m.pos[1])))
			"timelapse":
				hud.timelapse.open(sim)
				hud.timelapse.show_month(sim.timelapse.months * 0.6)
	if _frames == 120:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
