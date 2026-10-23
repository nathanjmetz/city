extends SceneTree
## Every roundabout size in a row along a country road, with the size row open.
## Run: xvfb-run godot --rendering-driver opengl3 -s tools/roundabout_shot.gd -- out.png yaw_deg pitch_deg dist [x z]
## A sixth argument "parks" shows the three park sizes instead.

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
		_build()
	if _frames == 40:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "shot.png")
		quit()
	return false


func _build() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 50_000_000
	var args := OS.get_cmdline_user_args()
	var parks := args.size() >= 7 and args[6] == "parks"
	sim.apply({"type": "build_road", "start": [-700, 0], "ctrl": [0, 0], "end": [700, 0], "road": 1})
	if parks:
		var x := -450.0
		for i in Balance.PARK_SIZES.size():
			var ps: Dictionary = Balance.PARK_SIZES[i]
			x += ps.size.x * 0.5
			var site := Parks.site_near(sim.network, "park", Vector3(x, 0, 40), i)
			sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z],
				"dir": [site[1].x, site[1].z], "size": i})
			x += ps.size.x * 0.5 + 40.0
	else:
		for i in RoadShapes.ROUNDABOUT_SIZES.size():
			var rs: Dictionary = RoadShapes.ROUNDABOUT_SIZES[i]
			var x := -560.0 + i * 280.0
			sim.apply({"type": "build_road", "start": [x, -150], "ctrl": [x, 0], "end": [x, 150]})
			var ring := RoadShapes.ring_for_lanes(int(rs.lanes))
			sim.apply({"type": "build_roundabout", "center": [x, 0], "lanes": rs.lanes,
				"radius": RoadShapes.radius_for_icd(float(rs.icd) / RoadTool.FT, ring)})
	for c in _main.get_children():
		if c is Hud:
			c.close_all()
			if parks:
				c.call("_open", "parks")
				c.park_tool.set_size(1)
			else:
				c.call("_open", "roads")
				c.road_tool.set_roundabout_preset(0)
		if c is CityCamera:
			c.look_at_point(Vector3(float(args[4]), 0, float(args[5])) if args.size() >= 6 else Vector3.ZERO)
			c.set_view(deg_to_rad(float(args[1])), deg_to_rad(float(args[2])), float(args[3]))
