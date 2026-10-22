extends SceneTree
## Pictures of the Move It tool: a street picked up and dragged (the live
## preview), then where it landed with its homes and the fire station
## shifted out of its way.
## Run: godot -s tools/move_shot.gd -- out_prefix

var _main: Node
var _frames := 0
var _tool: MoveTool
var _seg := -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "move"
	var sim: CitySim = _main.sim
	if _frames == 2:
		_main.set_speed(0)
		sim.apply({"type": "clear"})
		sim.economy.money = 20_000_000
		sim.require_utilities = false
		sim.simulate_traffic = false
		sim.apply({"type": "build_road", "start": [-200, 0], "ctrl": [0, 0], "end": [200, 0]})
		sim.apply({"type": "build_road", "start": [-200, 120], "ctrl": [0, 120], "end": [200, 120]})
		for x in range(-200, 201, 8):
			sim.apply({"type": "paint_zone", "center": [x, -22], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
		var site := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(-60, 0, 100))
		sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [site[0].x, site[0].z],
			"dir": [site[1].x, site[1].z]})
		for i in 1500:
			sim.tick()
		_tool = _find(_main)
		_tool.set_active(true)
		_seg = sim.network.find_segment_near(Vector3(0, 0, 0), 2.0).seg
		_tool.selection = [{"type": "road", "id": _seg}]
		_aim(Vector3(0, 0, 50), 15.0, 55.0, 420.0)
	if _frames == 40:
		_save(out + "_picked.png")
		# Mid-drag: 70 m south, onto the fire station's block.
		_tool.set_process(false)
		_tool._drag_from = Vector3.ZERO
		_tool._offset = Vector3(0, 0, 70)
		_tool._plan = MoveIt.plan(sim, MoveIt.command(_tool.selection, MoveIt.centre(sim, _tool.selection), _tool._offset, 10.0))
		_tool._problem = _tool._plan.problem
		_tool._redraw()
	if _frames == 70:
		_save(out + "_drag.png")
		_tool._drag_from = null
		_tool._commit(Vector3(0, 0, 70), 0.0, 0.0)
		_tool._commit(Vector3.ZERO, 10.0, 0.0)
		print("problem: ", _tool._problem)
		_tool._redraw()
	if _frames == 110:
		_save(out + "_after.png")
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


func _find(n: Node) -> MoveTool:
	if n is MoveTool:
		return n
	for c in n.get_children():
		var t := _find(c)
		if t != null:
			return t
	return null
