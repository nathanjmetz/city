extends SceneTree
## Renders the game with a small demo town and saves a picture.
## Run: godot -s tools/screenshot.gd -- out.png [yaw_deg pitch_deg dist]

var _main: Node
var _frames := 0


func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_demo_town()
	if _frames == 40:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "shot.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false


func _demo_town() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	var roads := [
		[[-200, 0], [0, 0], [200, 0]],
		[[0, -150], [0, 0], [0, 150]],
		[[-200, -90], [0, -90], [200, -90]],
		[[100, 0], [140, 80], [60, 150]],
	]
	for r in roads:
		sim.apply({"type": "build_road", "start": r[0], "ctrl": r[1], "end": r[2]})
	for x in range(-190, 200, 8):
		for z in [-15, -75, -105]:
			sim.apply({"type": "paint_zone", "center": [x, z], "radius": 10, "zone": ZoneMap.Zone.RESIDENTIAL})
	for x in range(-190, 0, 8):
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.COMMERCIAL})
	for x in range(10, 100, 8):
		sim.apply({"type": "paint_zone", "center": [x, 15], "radius": 10, "zone": ZoneMap.Zone.INDUSTRIAL})
	var args := OS.get_cmdline_user_args()
	var overlay := args.size() >= 5 and args[4] == "zones"
	for i in (60 if overlay else 600):
		sim.tick()
	if overlay:
		for c in _main.get_children():
			if c is ZoneTool:
				c.set_zone(ZoneMap.Zone.RESIDENTIAL)
	# Leave a few lots empty to show the zone tint.
	sim.apply({"type": "paint_zone", "center": [-150, 15], "radius": 14, "zone": ZoneMap.Zone.NONE})
	sim.apply({"type": "paint_zone", "center": [-150, 15], "radius": 14, "zone": ZoneMap.Zone.COMMERCIAL})
	var cam: CityCamera
	for c in _main.get_children():
		if c is CityCamera:
			cam = c
	cam.look_at_point(Vector3(-20, 0, -30))
	if args.size() >= 4:
		cam._yaw = deg_to_rad(float(args[1]))
		cam._pitch = deg_to_rad(float(args[2]))
		cam._dist = float(args[3])
		cam._goal_dist = cam._dist
