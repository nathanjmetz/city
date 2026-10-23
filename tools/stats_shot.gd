extends SceneTree
## Pictures of a top bar stat's panel (chart and details), for checking the
## look. Run: xvfb-run godot -s tools/stats_shot.gd -- population|jobs|traffic|demand|money|date|problems|towns out.png

var _frames := 0
var _mode := "population"
var _out := "stats.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0] if args.size() > 0 else "population"
	_out = args[1] if args.size() > 1 else "stats.png"
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Stats Shot")
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var main := current_scene
		var sim: CitySim = main.sim
		sim.economy.money = 2_000_000
		sim.require_utilities = false
		sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [140, 60], "end": [240, 60]})
		sim.apply({"type": "build_road", "start": [140, -60], "ctrl": [140, 60], "end": [140, 200]})
		for x in range(40, 241, 10):
			sim.apply({"type": "paint_zone", "center": [x, 35], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
			sim.apply({"type": "paint_zone", "center": [x, 85], "radius": 12, "zone": ZoneMap.Zone.COMMERCIAL})
		for z in range(-50, 200, 10):
			sim.apply({"type": "paint_zone", "center": [165, z], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
		for kind in [Services.Kind.WELL, Services.Kind.POWER_FEED]:
			var site := Services.site_near(sim.network, kind, Vector3(60 + kind * 20, 0, 100))
			if not site.is_empty():
				sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
		for i in 24 * 60 * 3:
			sim.tick()
		var hud: Hud = main.get_children().filter(func(n): return n is Hud)[0]
		hud.advisor.settings.welcomed = true
		hud.advisor.close_panel()
		var cam: CityCamera = hud.info_view.cam
		cam.set_view(0.6, 0.9, 520.0)
		cam.look_at_point(Vector3(1500, 0, 900))
		hud.road_tool.set_mode(RoadTool.Mode.NONE)
		if _mode == "towns":
			hud.call("_show_towns", true)
		elif _mode == "home":
			hud.jump.go_home()
		else:
			hud.open_stat(_mode)
	if _frames == 40 and _mode != "towns" and _mode != "home":
		# Hover the middle of the chart for its readout.
		var hud: Hud = current_scene.get_children().filter(func(n): return n is Hud)[0]
		var chart: StatChart = hud.stats_panel.get("_chart")
		var ev := InputEventMouseMotion.new()
		ev.position = chart.size * Vector2(0.6, 0.5)
		chart._gui_input(ev)
	if _frames == 160:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
