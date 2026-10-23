extends SceneTree
## Renders a company yard or a farmstead with every step of its development
## tree built, for the art realism loop (compare each add-on with its real
## example in UpgradeKits). Kinds: oil, ore, forest, farm, rail.
## Run: godot -s tools/upgrade_shot.gd -- out.png kind [yaw pitch dist]

var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "oil"
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	if kind == "rail":
		_rail(world, args)
		return
	var built: Array = Agency.TREES[kind].map(func(n): return n.id)
	var s := {"kind": kind, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "addons": {}}
	var ind := Industry.new()
	ind.sites[1] = s
	for n in built:
		ind.place_addon(1, n, func(_p): return true)
	var parts: Array
	match kind:
		"farm": parts = FarmBuilder.build_farmstead(7, 3, built)
		"forest": parts = ForestryBuilder.mill(7, Industry.HQ_SIZE, built, s.addons)
		_: parts = IndustryBuilder.build_hq(kind, 7, built, s.addons)
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = parts[i]
		mi.position.y = 0.0 if i == 0 else 0.15
		world.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 3000.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[2])) if args.size() > 4 else deg_to_rad(-30.0)
	var pitch := deg_to_rad(float(args[3])) if args.size() > 4 else deg_to_rad(35.0)
	var dist := float(args[4]) if args.size() > 4 else (70.0 if kind == "farm" else 150.0)
	var target := Vector3(0, 3, 0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


## A railroad depot beside a county highway with its whole tree built.
func _rail(world: Node3D, args: Array) -> void:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var site := Rail.site_near(sim.network, Vector3(0, 0, 60))
	sim.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z],
		"axis": [site[2].x, site[2].z]})
	var d: Dictionary = sim.rail.depots.values()[0]
	d.built = Rail.TREE.map(func(n): return n.id)
	var view := RailView.new()
	world.add_child(view)
	view.sim = sim
	view._draw_yards()
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 3000.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[2])) if args.size() > 4 else deg_to_rad(160.0)
	var pitch := deg_to_rad(float(args[3])) if args.size() > 4 else deg_to_rad(30.0)
	var dist := float(args[4]) if args.size() > 4 else 220.0
	var c: Vector3 = Rail._yard_pt(d, 0.0, 25.0)
	var target := Vector3(c.x, Terrain.base_y(c.x, c.z) + 5.0, c.z)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "upgrade.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
