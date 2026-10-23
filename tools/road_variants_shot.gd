extends SceneTree
## Pictures of every road variant side by side, and of the Roads and
## Industry menus, for checking them against real street photos.
## Run: godot -s tools/road_variants_shot.gd -- out_prefix

var _main: Node
var _hud: Hud
var _frames := 0
const GAP := 70.0
var _x := {}  # road type -> x of its road


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "roads"
	var sim: CitySim = _main.sim
	if _frames == 2:
		sim.apply({"type": "clear"})
		sim.economy.money = 50_000_000
		for c in _main.get_children():
			if c is Hud:
				_hud = c
		_hud.close_all()
		# Each menu's roads side by side, running north, with a street across.
		var x := 0.0
		for g in RoadStyle.GROUPS:
			for t in RoadStyle.variants(g):
				_x[t] = x
				sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, -120], "end": [x, -240], "road": t})
				x += GAP
			x += GAP * 0.5
		_aim(Vector3(GAP * 4, 0, -120), 0.0, 50.0, 520.0)
		_hud._open("roads")
		_hud._pick_road(RoadStyle.Type.STREET)
	if _frames == 50:
		_save(out + "_streets.png")
		_hud._pick_road(RoadStyle.Type.AVENUE_TURN)
		_aim(Vector3(GAP * 10.5, 0, -120), 0.0, 50.0, 430.0)
	if _frames == 90:
		_save(out + "_avenues.png")
		_hud._pick_road(RoadStyle.Type.DIVIDED_HWY)
		_aim(Vector3(GAP * 17.5, 0, -120), 0.0, 50.0, 560.0)
	if _frames == 130:
		_save(out + "_highways.png")
		_hud.traffic_tool.set_mode(TrafficTool.Mode.ALL_STOP)
		_aim(Vector3(_x[RoadStyle.Type.MAIN_STREET], 0, -100), 15.0, 35.0, 60.0)
	if _frames == 170:
		_save(out + "_main_street.png")
		_hud.close_all()
		_aim(Vector3(_x[RoadStyle.Type.AVENUE_DIVIDED], 0, -100), 15.0, 35.0, 70.0)
	if _frames == 210:
		_save(out + "_divided.png")
		_aim(Vector3(_x[RoadStyle.Type.DIVIDED_HWY], 0, -100), 15.0, 35.0, 90.0)
	if _frames == 250:
		_save(out + "_divided_hwy.png")
		_aim(Vector3(_x[RoadStyle.Type.GRAVEL] - GAP * 0.5, 0, -100), 15.0, 35.0, 80.0)
	if _frames == 290:
		_save(out + "_gravel.png")
		_hud._open("industry")
	if _frames == 320:
		_save(out + "_industry_menu.png")
		# Brawn's report: zoomed far out, the road being drawn must still show.
		_hud.close_all()
		_hud._open("roads")
		_hud._pick_road(RoadStyle.Type.STREET)
		var tool: RoadTool = _hud.road_tool
		tool.set_mode(RoadTool.Mode.STRAIGHT)
		tool._points.append(Vector3(-900, 0, 300))
		_aim(Vector3(-400, 0, 0), 20.0, 45.0, 2200.0)
		root.get_viewport().warp_mouse(Vector2(1000, 350))
	if _frames == 360:
		_save(out + "_ghost_far.png")
		var tool: RoadTool = _hud.road_tool
		tool.set_mode(RoadTool.Mode.GRID)
		for p in [Vector3(-1200, 0, 200), Vector3(-700, 0, 300)]:
			tool._points.append(p)
	if _frames == 400:
		_save(out + "_grid_far.png")
		quit()
	return false


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _aim(at: Vector3, yaw: float, pitch: float, dist: float) -> void:
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(at)
			c.set_view(deg_to_rad(yaw), deg_to_rad(pitch), dist)
