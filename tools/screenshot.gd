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
	# A main road with a roundabout, and a grid neighborhood beside it.
	sim.apply({"type": "build_road", "start": [-300, 0], "ctrl": [0, 0], "end": [300, 0]})
	sim.apply({"type": "build_road", "start": [120, 0], "ctrl": [160, 80], "end": [120, 180]})
	sim.apply({"type": "build_roundabout", "center": [120, 0], "radius": 20})
	sim.apply({"type": "build_grid", "a": [-240, -40], "b": [40, -40], "c": [-240, -210], "block": 140})
	sim.apply({"type": "build_road", "start": [-100, -40], "ctrl": [-100, -20], "end": [-100, 0]})
	for lot in sim.lots.values():
		var p: Vector3 = lot.zone_pt
		var zone := ZoneMap.Zone.RESIDENTIAL
		if p.z > -10.0 and p.z < 30.0 and p.x < 100.0:
			zone = ZoneMap.Zone.COMMERCIAL
		elif p.x > 130.0:
			zone = ZoneMap.Zone.INDUSTRIAL
		sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": 3, "zone": zone})
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
	cam.look_at_point(Vector3(-40, 0, -60))
	if args.size() >= 4:
		cam.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
