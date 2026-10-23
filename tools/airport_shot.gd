extends SceneTree
## Pictures of the airport: a grass strip on a county road with a farm, a
## plane taxiing and one on final, and the placing tool's plan of every size.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/airport_shot.gd -- out.png yaw pitch dist [plan|select] [x z]

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _frames == 0 and _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		_setup()
	if _frames == 50:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "airport.png")
		print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		quit()
	return false


func _setup() -> void:
	var sim: CitySim = _main.sim
	var args := OS.get_cmdline_user_args()
	var mode := args[4] if args.size() > 4 else ""
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.apply({"type": "build_road", "start": [-1500, 0], "ctrl": [0, 0], "end": [1500, 0]})
	sim.apply({"type": "build_road", "start": [-700, 0], "ctrl": [-700, -300], "end": [-700, -600]})
	for x in range(-180, 200, 20):
		sim.apply({"type": "paint_zone", "center": [x - 600, 20], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var cam: CityCamera
	var tool: AirportTool
	for c in _main.get_children():
		if c is CityCamera:
			cam = c
		if c is AirportTool:
			tool = c
	if mode == "plan":
		tool.set_active(true)
		tool._site = {"pos": Vector3(0, 0, 150), "dir": Vector3.RIGHT, "side": -1, "tier": 0}
		tool._check()
		tool._draw_plan()
		tool.set_process(false)
	else:
		sim.apply({"type": "place_airport", "pos": [0, 150], "dir": [1, 0], "side": -1})
		var fid := sim.farms.add_farm(Vector3(-500, 0, -200), Vector3(0, 0, 1), "corn", [])
		for x in range(-6, 7):
			for y in range(1, 9):
				sim.farms.farms[fid].cells.append(Vector2i(x, y))
		sim.farms.farms[fid].barn = true
		sim.farms_changed.emit()
		for i in 2 * 1440 + 400:
			sim.tick()
		for pid in sim.airports.planes:
			var p: Dictionary = sim.airports.planes[pid]
			print(pid, " ", p.type, " ", p.state, " ", p.flight.get("kind", ""))
		if mode == "select":
			for c in _main.get_children():
				if c is Hud:
					c.close_all()
			for c in _main.get_children():
				if c is SelectTool:
					c.select({"type": "airport", "id": sim.airports.sites.keys()[0]})
	cam.look_at_point(Vector3(float(args[5]), 0, float(args[6])) if args.size() >= 7 else Vector3(0, 0, 150))
	cam.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
