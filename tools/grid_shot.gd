extends SceneTree
## Pictures of the smart grid tool, for checking it against Brawn's report
## (a grid dropped over old roads must not double them).
## Run: godot -s tools/grid_shot.gd -- out_prefix

var _main: Node
var _frames := 0
var _tool: RoadTool


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "grid"
	var sim: CitySim = _main.sim
	if _frames == 2:
		sim.apply({"type": "clear"})
		sim.economy.money = 20_000_000
		for c in _main.get_children():
			if c is Hud:
				c.close_all()
		_tool = _find_tool(_main)
		# Brawn's case: a grid, then a second one over it, shifted and turned.
		sim.apply({"type": "build_grid_shape", "points": [[-180, -120], [180, -120], [180, 126], [-180, 126]], "block": 120})
		var turn := deg_to_rad(-25.0)
		var pts := []
		for p in [Vector2(-60, -200), Vector2(330, -200), Vector2(400, 60), Vector2(200, 280), Vector2(-40, 200)]:
			pts.append([p.x * cos(turn) - p.y * sin(turn), p.x * sin(turn) + p.y * cos(turn)])
		sim.apply({"type": "build_grid_shape", "points": pts, "block": 100})
		_aim(Vector3(80, 0, 20), 30.0, 55.0, 700.0)
	if _frames == 40:
		_save(out + "_top.png")
		_aim(Vector3(170, 0, -60), 35.0, 35.0, 260.0)
	if _frames == 70:
		_save(out + "_close.png")
		# Rectangle mode beside a diagonal county road, like Brawn's try:
		# the side is dragged a little off and still lines up exactly.
		sim.apply({"type": "clear"})
		sim.apply({"type": "build_road", "start": [-400, -260], "ctrl": [0, 0], "end": [400, 260]})
		_tool.set_mode(RoadTool.Mode.GRID)
		_tool.set_grid_free(false)
		var a := Vector3(-150, 0, -60)
		_tool._points.append(a)
		_tool._points.append(_tool._grid_corner(a + Vector3(cos(0.62), 0, sin(0.62)) * 320.0))
		_tool._update_hint()
		_tool.set_process(false)
		_tool._show_grid(_tool._points[1] + Vector3(-120, 0, 200))
		_aim(Vector3(0, 0, 60), 20.0, 55.0, 650.0)
	if _frames == 100:
		_save(out + "_preview.png")
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


func _find_tool(n: Node) -> RoadTool:
	if n is RoadTool:
		return n
	for c in n.get_children():
		var t := _find_tool(c)
		if t != null:
			return t
	return null
