extends SceneTree
## Renders one building of a kind at every stage of going up, side by side,
## for checking ConstructionSite against photos of real job sites.
## Run: godot -s tools/construction_shot.gd -- out.png [house|shop|tower|factory|civic|warehouse|barn|paving|landfill|cemetery]
##      [seed] [t] [yaw pitch dist] [only stage]

var _frames := 0


func _init() -> void:
	# After the Quality autoload has read --quality, so tier-gated looks
	# (the photographed ground) come out as the game draws them.
	_build.call_deferred()


func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "house"
	var seed := int(args[2]) if args.size() > 2 else 1
	var t := float(args[3]) if args.size() > 3 else 0.6
	var only := int(args[7]) if args.size() > 7 else -1
	var world := Node3D.new()
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	var gap := 20.0 if kind == "house" or kind == "shop" else (30.0 if kind == "paving" else (75.0 if kind == "tower" else 60.0))
	var stages := range(Construction.STAGES.size()) if only < 0 else [only]
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(gap * (stages.size() + 1), 9.0)
	road.mesh = plane
	road.material_override = Surfaces.asphalt()
	road.position = Vector3(0, 0.09, -8.4)
	world.add_child(road)
	var profile := "shop" if kind in ["landfill", "cemetery", "recycling", "tower"] else kind
	for n in stages.size():
		var i: int = stages[n]
		var built: Array
		match kind:
			"shop": built = CommercialBuilder.build_shop(seed * 100 + i, 3.9)
			"tower": built = TowerBuilder.build_tower(seed * 100, 3.9, {"width": 44.0, "depth": 60.0, "era": "recent"}, 16)
			"factory": built = CommercialBuilder.build_factory(seed * 100 + i, 3.9)
			"civic": built = CivicBuilder.build_service(Services.KINDS.keys()[seed % Services.KINDS.size()],
				seed, Services.KINDS[Services.KINDS.keys()[seed % Services.KINDS.size()]].size, 3.9)
			"warehouse": built = WarehouseBuilder.build_warehouse({"kind": Warehouses.KINDS.keys()[seed % Warehouses.KINDS.size()],
				"level": 0, "bays": 0, "pos": Vector3.ZERO, "dir": Vector3.FORWARD}, seed, 3.9)
			"barn": built = FarmBuilder.build_farmstead(seed, 1)
			"paving": built = ParkingBuilder.build_lot({"kind": Services.Kind.PARKING_SMALL, "pos": Vector3.ZERO,
				"dir": Vector3.FORWARD}, seed, 6.6)
			"landfill", "cemetery", "recycling":
				var hubs := CivicHubs.new()
				var hid := hubs.add(kind, Vector3.ZERO, Vector3.FORWARD, 0)
				built = HubBuilder.build_hub(hubs.hubs[hid], seed, 3.9)
				built.resize(3)
			_: built = HouseBuilder.build(seed * 100 + 7, 3.9)
		var holder := Node3D.new()
		holder.position = Vector3((n - (stages.size() - 1) * 0.5) * gap, 0, 0)
		world.add_child(holder)
		var p: Dictionary = Construction.PROFILES[profile]
		var st := {"stage": i, "name": Construction.STAGES[i], "t": t, "total": 0.5, "profile": profile,
			"frame": p.frame, "words": p.words[i], "found": p.found}
		var site := ConstructionSite.new()
		holder.add_child(site)
		site.setup(built, profile, func(): return st)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 1.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[4])) if args.size() > 6 else deg_to_rad(20.0)
	var pitch := deg_to_rad(float(args[5])) if args.size() > 6 else deg_to_rad(22.0)
	var dist := float(args[6]) if args.size() > 6 else gap * stages.size() * 0.75
	var target := Vector3(0, 3, 8)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	# Into the tree last: the sites stay flat (no Terrain to drape on here).
	root.add_child(world)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "construction.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
