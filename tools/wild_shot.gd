extends SceneTree
## Pictures of an emptied street growing back wild, for checking the look.
## Run: godot -s tools/wild_shot.gd -- out.png years
## A street of homes is built on open land; half of it is dezoned, and the
## picture is taken `years` game years later.

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_scene()
	if _frames == 60:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "wild.png")
		print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"  primitives: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		quit()
	return false


func _scene() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	sim.require_utilities = false  # no power plant needed for a picture
	var o := Vector3(3000, 0, 3000)  # away from the starter road
	sim.apply({"type": "build_road", "start": [o.x - 160, o.z], "ctrl": [o.x, o.z], "end": [o.x + 160, o.z]})
	for x in range(-150, 151, 10):
		sim.apply({"type": "paint_zone", "center": [o.x + x, o.z - 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [o.x + x, o.z + 25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	for i in 4000:
		sim.tick()
	# The homes on the far side close and are torn down.
	sim.apply({"type": "paint_zone", "center": [o.x, o.z - 25], "radius": 150, "zone": ZoneMap.Zone.NONE})
	sim.tick()
	var args := OS.get_cmdline_user_args()
	var years := float(args[1]) if args.size() > 1 else 0.0
	sim.tick_count += int(years * Vegetation.TICKS_PER_YEAR)
	for c in _main.get_children():
		if c is CityCamera:
			c.look_at_point(o + Vector3(0, 0, -20))
			c.set_view(deg_to_rad(200.0), deg_to_rad(32.0), 150.0)
		if c is Hud:
			c.close_all()
