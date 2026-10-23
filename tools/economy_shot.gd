extends SceneTree
## Pictures of the Economy page and a hub's sliders, for checking the look.
## Run: godot -s tools/economy_shot.gd -- page|hub out.png

var _frames := 0
var _mode := "page"
var _out := "economy.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "page"
	_out = args[1] if args.size() > 1 else "economy.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Economy Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var main := current_scene
		var sim: CitySim = main.sim
		sim.economy.money = 20_000_000
		sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [140, 60], "end": [240, 60]})
		for x in range(40, 241, 10):
			sim.apply({"type": "paint_zone", "center": [x, 35], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply({"type": "paint_zone", "center": [x, 85], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
		for kind in [Services.Kind.WELL, Services.Kind.POWER_FEED, Services.Kind.FIRE]:
			var site := Services.site_near(sim.network, kind, Vector3(60 + kind * 20, 0, 100))
			if not site.is_empty():
				sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
		var f1 := sim.farms.add_farm(Vector3(-200, 0, 200), Vector3(0, 0, -1), "corn", [])
		sim.farms.add_farm(Vector3(-400, 0, 200), Vector3(0, 0, -1), "soybeans", [])
		var hs := CivicHubs.site_near(sim.network, Vector3(230, 0, 110))
		if not hs.is_empty():
			sim.apply({"type": "place_hub", "kind": "landfill", "pos": [hs[0].x, hs[0].z], "dir": [hs[1].x, hs[1].z]})
		for i in 600:
			sim.tick()
		sim.street_age.month(sim)  # the streets-coming-due forecast
		sim.apply({"type": "policy", "scope": "area:farms", "slider": "growth", "step": 3})
		sim.apply({"type": "policy", "scope": "farm:%d" % f1, "slider": "funding", "step": 4})
		sim.apply({"type": "policy", "scope": "area:homes", "slider": "funding", "step": 3})
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		var cam: CityCamera = hud.info_view.cam
		cam.set_view(0.6, 0.9, 520.0)
		cam.look_at_point(Vector3(0, 0, 100))
		hud.road_tool.set_mode(RoadTool.Mode.NONE)
		if _mode == "hub":
			hud.select_tool.select({"type": "farm", "id": f1})
		else:
			hud.call("_open", "budget")
	if _frames == 30 and _mode == "page":
		var hud: Hud = current_scene.get_children().filter(func(n): return n is Hud)[0]
		for area in ["farms", "utilities"]:
			hud.economy_page.get("_area_rows")[area].arrow.pressed.emit()
	if _frames == 120:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
