extends SceneTree
## Pictures of the guided first town, step by step, for checking the look.
## Run: godot -s tools/tour_shot.gd -- out_dir
## Needs a fresh user folder (no user://first_town.json).

var _frames := 0
var _out := "."
var _shot := 0
var _main: Node
var _hud: Hud
var _sim: CitySim
var _spot := []
## [frame, what to do, picture name or ""]
var _plan := [
	[60, "plan", "1-plan"],
	[80, "go", ""],
	[120, "", "2-open-roads"],
	[125, "roads", ""],
	[150, "", "3-pick-grid"],
	[155, "grid", ""],
	[180, "", "4-pick-town"],
	[185, "town", ""],
	[230, "", "5-draw-grid"],
	[235, "build_grid", ""],
	[280, "", "6-open-services"],
	[285, "power_tool", ""],
	[330, "", "7-place-power"],
	[335, "place_power", ""],
	[420, "", "8-power-wait"],
	[425, "finish_power", ""],
	[470, "", "9-water"],
	[475, "place_water", ""],
	[560, "", "10-water-wait"],
	[565, "finish_water", ""],
	[600, "zones", ""],
	[640, "", "11-homes"],
	[645, "zone_homes", ""],
	[760, "", "12-builders"],
	[765, "finish_homes", ""],
	[820, "", "13-done"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "."
	var session := root.get_node("Session")
	session.save_path = session.new_save_path("Tour Shot %d" % Time.get_ticks_usec())
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _main == null and current_scene != null and _frames > 30:
		_main = current_scene
		_sim = _main.sim
		_hud = _main.get_children().filter(func(n): return n is Hud)[0]
	for step in _plan:
		if step[0] != _frames:
			continue
		_do(step[1])
		if step[2] != "":
			root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, step[2]])
			print("saved ", step[2], "  step=", _hud.tour._step, "  ", _hud.tour._body.text)
	if _frames > 830:
		quit()
	return false


func _do(what: String) -> void:
	var p: Dictionary = GridFill.PRESETS[FirstTown.GRID_PRESET]
	match what:
		"plan":
			if not _hud.tour.running:
				_hud.tour.start()
		"go":
			_hud.tour._on_go()
		"roads":
			_hud._open("roads")
			_hud.road_tool.set_mode(RoadTool.Mode.STRAIGHT)
		"grid":
			_hud.road_tool.set_mode(RoadTool.Mode.GRID)
		"town":
			_hud.road_tool.set_grid_preset(FirstTown.GRID_PRESET)
		"build_grid":
			var s := FirstTown.grid_spot(_sim)
			_spot = s
			_sim.apply({"type": "build_grid_shape", "points": [[s[0].x, s[0].z], [s[1].x, s[0].z],
				[s[1].x, s[1].z], [s[0].x, s[1].z]], "block": p.block, "across": p.across, "side": 0,
				"road": RoadStyle.Type.STREET})
			_hud.close_all()
		"power_tool":
			_hud._open("services")
			_hud.service_tool.set_kind(Services.Kind.POWER_FEED)
		"place_power", "place_water":
			var u := "power" if what == "place_power" else "water"
			var kind: int = Services.Kind.POWER_FEED if u == "power" else Services.Kind.WELL
			var site := Services.site_near(_sim.network, kind, FirstTown.site_spot(_sim, u, (_spot[0] + _spot[1]) * 0.5))
			_sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
			_hud.close_all()
			_sim.update_stats()
		"finish_power", "finish_water":
			for i in Construction.duration("power_feed" if what == "finish_power" else "well") + 20:
				_sim.tick()
		"zones":
			_hud._open("zones")
		"zone_homes":
			var s := _spot
			var mid: Vector3 = (s[0] + s[1]) * 0.5
			for dx in range(-120, 121, 10):
				for dz in [-100, -10, 10, 100]:
					_sim.apply({"type": "paint_zone", "center": [mid.x + dx, mid.z + dz], "radius": 14,
						"zone": ZoneMap.Zone.RESIDENTIAL})
			_hud.close_all()
			for i in 300:
				_sim.tick()
		"finish_homes":
			for i in 3000:
				_sim.tick()
				if _sim.stats.population > 0:
					break
