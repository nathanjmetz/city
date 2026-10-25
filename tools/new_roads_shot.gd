extends SceneTree
## Close pictures of the dirt, chip-seal, one-lane one-way, brick and
## divided streets, and the Street menu with their cards.
## Run: godot -s tools/new_roads_shot.gd -- out_prefix

var _main: Node
var _hud: Hud
var _frames := 0
const TYPES := [RoadStyle.Type.DIRT, RoadStyle.Type.CHIP_SEAL, RoadStyle.Type.STREET_ONEWAY1,
	RoadStyle.Type.BRICK, RoadStyle.Type.STREET_DIVIDED]


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
		for i in TYPES.size():
			var x := i * 60.0
			sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x, -120], "end": [x, -240], "road": TYPES[i]})
		# A street across, so the junctions show.
		sim.apply({"type": "build_road", "start": [-40, -120], "ctrl": [100, -120], "end": [280, -120], "road": RoadStyle.Type.STREET})
		_aim(Vector3(120, 0, -150), 0.0, 40.0, 260.0)
		_hud._open("roads")
		_hud._pick_road(RoadStyle.Type.STREET)
	var k := (_frames - 60) / 40
	if _frames >= 60 and (_frames - 60) % 40 == 0:
		if k == 0:
			_save(out + "_menu.png")
			_hud.close_all()
		else:
			_save(out + "_%s.png" % RoadStyle.TYPES[TYPES[k - 1]].short.replace(" ", "_"))
		if k < TYPES.size():
			_aim(Vector3(k * 60.0, 0, -80), 20.0, 35.0, 40.0)
		else:
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
