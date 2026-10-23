extends SceneTree
## Renders a row of generated buildings on a plain street for the art
## realism loop, so they can be compared side by side with real photos.
## Run: godot -s tools/art_gallery.gd -- out.png [kind] [seed] [yaw pitch dist]
## Kinds: house, shop, factory, row, apartments, mixed, office, main (a
## Main Street of mixed blocks, storeys 2 to 4), types (one of each type).

var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "house"
	# "house:bungalow" draws one house type.
	if kind.begins_with("house:"):
		HouseBuilder.force_kind = kind.get_slice(":", 1)
		kind = "house"
	elif kind.begins_with("shop:"):
		CommercialBuilder.force_shop = kind.get_slice(":", 1)
		kind = "shop"
	var seed := int(args[2]) if args.size() > 2 else 1
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	# A street along x in front of the lots (lots face -z, toward it).
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(260, 9.0)
	road.mesh = plane
	road.material_override = Surfaces.asphalt()
	road.position = Vector3(0, 0.09, -8.4)
	world.add_child(road)
	var trees := TreeField.new()
	world.add_child(trees)
	if kind in ["oil", "ore"]:
		# A company's main yard on the left, one of its pads on the right.
		var parts := [[IndustryBuilder.build_hq(kind, seed), Vector3(-25, 0, 20)],
			[IndustryBuilder.build_pad(kind, seed), Vector3(30, 0, 20)]]
		if kind == "oil":
			parts.append([[IndustryBuilder.build_beam(seed)], Vector3(27, 5.6, 20)])
		for part in parts:
			for m in part[0]:
				var mi := MeshInstance3D.new()
				mi.mesh = m
				mi.position = part[1]
				world.add_child(mi)
	var x := -50.0
	for i in (0 if kind in ["oil", "ore"] else 5):
		var meshes: Array
		var k := kind
		if kind == "types":
			k = ["house", "row", "apartments", "mixed", "office"][i]
		var w: float = {"row": 22.0, "apartments": 36.0, "mixed": 22.0, "main": 16.0 + 4.0 * (i % 3), "office": 40.0}.get(k, 20.0)
		var sd := seed * 100 + i
		match k:
			"shop": meshes = CommercialBuilder.build_shop(sd, 3.9)
			"factory": meshes = CommercialBuilder.build_factory(sd, 3.9)
			"row": meshes = DenseBuilder.build_row(sd, 3.9, {"width": w, "depth": 45.0}, 3, 2 + i % 2)
			"apartments": meshes = DenseBuilder.build_apartments(sd, 3.9, {"width": w, "depth": 45.0}, [2, 3, 5][i % 3])
			"mixed", "main": meshes = DenseBuilder.build_mixed(sd, 3.9, {"width": w, "depth": 45.0}, 2 + i % 3)
			"office": meshes = DenseBuilder.build_office(sd, 3.9, {"width": w, "depth": 55.0}, [3, 5, 8][i % 3])
			_: meshes = HouseBuilder.build(sd, 3.9)
		var at := Vector3(x + w * 0.5, 0, 0)
		x += w
		for m in meshes.slice(0, 2):
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.position = at
			world.add_child(mi)
		var planted := []
		for t in meshes[2]:
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), at + t[0])
			planted.append([xf, t[1], t[2]])
		trees.set_trees(str(i), planted)
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[3])) if args.size() > 5 else deg_to_rad(20.0)
	var pitch := deg_to_rad(float(args[4])) if args.size() > 5 else deg_to_rad(18.0)
	var dist := float(args[5]) if args.size() > 5 else 70.0
	var target := Vector3(0, 3, 8)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "gallery.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
