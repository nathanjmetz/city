extends SceneTree
## Renders a row of generated buildings on a plain street for the art
## realism loop, so they can be compared side by side with real photos.
## Run: godot -s tools/art_gallery.gd -- out.png [kind] [seed] [yaw pitch dist]
## Kinds: house, shop, factory, row, apartments, mixed, office, main (a
## Main Street of mixed blocks, storeys 2 to 4), types (one of each type),
## care (one house from derelict to showpiece, PropertyCare's tiers -2..2)
## careshop (the same for a shop), grown (a house up its growth path: family
## home, two storeys, then three with an addition out back) and duplex (an
## up-and-down, a double, a ranch and a two-storey duplex, and a fourplex),
## rows (recent townhomes, 1970s mansard rows and brick rows), garden
## (garden apartments, 1960s-70s and recent, two and three storeys).
## "far:<kind>" draws the same
## buildings as their far versions (BuildingView.far_version). GALLERY_HOUR
## (0-24) sets the time of day.

var _frames := 0
var _sky: SkyLight


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := args[1] if args.size() > 1 else "house"
	var far := kind.begins_with("far:")
	if far:
		kind = kind.trim_prefix("far:")
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
	_sky = SkyLight.new()
	world.add_child(_sky)
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
	for i in (0 if kind in ["oil", "ore"] else (8 if kind.begins_with("tract") else (7 if kind == "growth" else 5))):
		var meshes: Array
		var k := kind
		if kind == "types":
			k = ["house", "row", "apartments", "mixed", "office"][i]
		if kind in ["care", "careshop"]:
			HouseBuilder.owner_care = i - 2
		var w: float = {"care": 24.0, "careshop": 26.0, "retailgrown": 20.0, "shopsgrown": 24.0, "gasgrown": [26.0, 26.0, 34.0, 34.0, 30.0][i % 5], "row": 22.0, "apartments": 36.0, "mixed": 22.0, "main": 16.0 + 4.0 * (i % 3), "mainold": 16.0 + 4.0 * (i % 3), "mainrestored": 16.0 + 4.0 * (i % 3), "office": 40.0, "towers": 44.0, "hometowers": 54.0, "towerfar": 44.0, "flats": 24.0, "courtyard": 48.0, "walkup": 26.0, "garage": 44.0, "growth": [40.0, 40.0, 44.0, 56.0, 64.0, 64.0, 72.0][i % 7], "oddlots": [26.0, 22.0, 20.0, 26.0, 18.0][i % 5],
			"grown": 22.0, "grownold": 22.0, "carriage": 24.0, "cornergrown": [18.0, 18.0, 20.0, 20.0, 18.0][i % 5], "rows": 22.0, "garden": 40.0, "walkups": 32.0, "plexes": 22.0, "infill": [16.0, 20.0, 24.0, 18.0, 26.0][i % 5], "duplex": [16.0, 20.0, 24.0, 24.0, 22.0][i % 5],
			"corner": [14.0, 13.0, 12.0, 22.0, 20.0][i % 5], "cottage": [16.0, 20.0, 22.0, 18.0, 24.0][i % 5], "cornerflats": [14.0, 18.0, 12.0, 16.0, 16.0][i % 5]}.get(k, 20.0)
		var sd := seed * 100 + i
		match k:
			"shop": meshes = CommercialBuilder.build_shop(sd, 3.9)
			"factory": meshes = CommercialBuilder.build_factory(sd, 3.9)
			"row": meshes = DenseBuilder.build_row(sd, 3.9, {"width": w, "depth": 45.0}, 3, 2 + i % 2)
			"apartments": meshes = DenseBuilder.build_apartments(sd, 3.9, {"width": w, "depth": 45.0}, [2, 3, 5][i % 3])
			"mixed", "main": meshes = DenseBuilder.build_mixed(sd, 3.9, {"width": w, "depth": 45.0}, 2 + i % 3)
			"mainold", "mainrestored":
				HouseBuilder.restored = k == "mainrestored"
				meshes = DenseBuilder.build_mixed(sd, 3.9, {"width": w, "depth": 45.0, "era": "prewar"}, 2 + i % 3)
				HouseBuilder.restored = false
			"office": meshes = DenseBuilder.build_office(sd, 3.9, {"width": w, "depth": 55.0}, [3, 5, 8][i % 3])
			"growth":
				# One office's stages left to right, drawn as BuildingView does.
				var st: int = [3, 5, 8, 16, 30, 48, 100][i % 7]
				if st >= 8:
					meshes = TowerBuilder.build_tower(seed * 100, 3.9, {"width": w, "depth": 60.0}, st)
				else:
					meshes = DenseBuilder.build_office(seed * 100, 3.9, {"width": w, "depth": 60.0}, st)
			"towers": meshes = TowerBuilder.build_tower(sd, 3.9, {"width": w, "depth": 55.0}, [12, 22, 24, 10, 16][i],
				{}, ["chicago", "deco", "glass", "chicago", "glass"][i])
			"hometowers": meshes = TowerBuilder.build_tower(sd, 3.9, {"width": w, "depth": 55.0}, [12, 22, 24, 10, 16][i],
				{}, ["glass", "glass", "deco", "glass", "chicago"][i], true)
			"towerfar": meshes = [TowerBuilder.build_far(sd, 3.9, {"width": w, "depth": 55.0}, [12, 22, 24, 10, 16][i],
				["chicago", "deco", "glass", "chicago", "glass"][i]), ArrayMesh.new(), []]
			"flats": meshes = MetroBuilder.build_row(sd * 7 + 1, 3.9, {"width": w, "depth": 45.0, "era": "prewar"}, 3, 2 + i % 2)
			"courtyard": meshes = MetroBuilder.build_apartments(sd, 3.9, {"width": w, "depth": 55.0, "era": "prewar"}, 3)
			"walkup": meshes = MetroBuilder.build_apartments(sd, 3.9, {"width": w, "depth": 40.0, "era": "prewar"}, 5)
			"garage": meshes = MetroBuilder.build_garage(sd, 3.9, {"width": w, "depth": 60.0}, 4 + i % 3)
			"tract", "tractold": meshes = HouseBuilder.build(sd, 3.9, {"width": w, "depth": 40.0, "at": Vector2(x, 0) + (Vector2(seed * 400.0, 0)),
				"era": "postwar" if k == "tract" else "prewar"})
			"oddlots":
				# A skewed, a tapering and a pie lot, lot lines drawn in white.
				var poly := _odd_lot(i, w)
				meshes = HouseBuilder.build(sd, 3.9, {"width": w, "depth": 36.0, "outline": poly,
					"at": Vector2(x, 0) + Vector2(seed * 400.0, 0)}, 1 + i % 2)
				var line := ImmediateMesh.new()
				line.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				for e in poly.size():
					var a := Vector3(poly[e].x, 0.12, poly[e].y)
					var b := Vector3(poly[(e + 1) % poly.size()].x, 0.12, poly[(e + 1) % poly.size()].y)
					var side := (b - a).cross(Vector3.UP).normalized() * 0.15
					for q in [a - side, b - side, b + side, a - side, b + side, a + side]:
						line.surface_add_vertex(q)
				line.surface_end()
				var lines := MeshInstance3D.new()
				lines.mesh = line
				var white := StandardMaterial3D.new()
				white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				white.cull_mode = BaseMaterial3D.CULL_DISABLED
				lines.material_override = white
				lines.position = Vector3(x + w * 0.5, 0, 0)
				world.add_child(lines)
			"care": meshes = HouseBuilder.build(seed * 100, 3.9, {"width": w, "depth": 48.0}, 1)
			"rows":
				# Row homes of each kind, two storeys and three.
				MetroBuilder.force_row = ["colonial", "urban", "mansard", "colonial", "row"][i]
				meshes = MetroBuilder.build_row(sd, 3.9, {"width": w, "depth": 45.0}, 3, 2 + i % 2)
				MetroBuilder.force_row = ""
			"infill":
				# Main Street shops with flats built new: postwar, then recent.
				var era: String = ["postwar", "postwar", "recent", "recent", "recent"][i]
				for t in 40:
					sd = seed * 100 + i * 50 + t
					var probe := DenseBuilder._start(sd, {"width": w, "depth": 40.0, "era": era})
					if MainInfill.wanted(probe, 3):
						break
				meshes = DenseBuilder.build_mixed(sd, 3.9, {"width": w, "depth": 40.0, "era": era}, [2, 3, 2, 3, 4][i])
			"walkups":
				# Postwar walk-ups: split-entry, mansard and the plain block.
				MetroBuilder.force_row = ["split", "walkmodern", "walkmansard", "walkmodern", "plain"][i]
				meshes = MetroBuilder.build_apartments(sd, 3.9, {"width": w, "depth": 50.0, "era": ["postwar", "recent", "postwar", "recent", "postwar"][i]}, [2, 3, 2, 2, 3][i])
				MetroBuilder.force_row = ""
			"garden":
				MetroBuilder.force_row = "garden"
				meshes = MetroBuilder.build_apartments(sd, 3.9, {"width": w, "depth": 50.0, "era": ["postwar", "recent"][i % 2]}, [2, 2, 3, 3, 2][i])
				MetroBuilder.force_row = ""
			"grown", "grownold":
				HouseBuilder.grown = 1 if i >= 2 else 0
				meshes = HouseBuilder.build(seed * 100 + maxi(0, i - 2) * 17, 3.9, {"width": w, "depth": 45.0, "era": "recent" if k == "grown" else "prewar"},
					[0, 2, 2, 2, 2][i])
				HouseBuilder.grown = 0
			"carriage":
				# Old houses with an addition, then a flat over the garage.
				HouseBuilder.grown = [1, 2, 1, 2, 2][i]
				meshes = HouseBuilder.build(seed * 100 + (i / 2) * 17, 3.9, {"width": w, "depth": 45.0, "era": "prewar"}, 2)
				HouseBuilder.grown = 0
			"plexes":
				# Fourplexes: prewar, postwar, then three recent big-house plexes.
				meshes = DuplexBuilder.build(sd, 3.9, {"width": w, "depth": 45.0, "era": ["prewar", "postwar", "recent", "recent", "recent"][i]}, 1)
			"duplex":
				DuplexBuilder.force_style = ["updown", "double", "ranch", "two", ""][i]
				meshes = DuplexBuilder.build(sd, 3.9, {"width": w, "depth": 45.0, "era": ["prewar", "prewar", "postwar", "recent", "postwar"][i]},
					1 if i == 4 else 0)
				DuplexBuilder.force_style = ""
			"cornerflats":
				# Corner stores grown into stores with flats, a Main Street
				# block beside each.
				if i % 2 == 0:
					meshes = CornerStore.build_grown(seed * 100 + i * 3 + 1, 3.9, {"width": w, "depth": 36.0, "era": "prewar", "corner": true,
						"side": [1.0, -1.0, 1.0][i / 2]}, 2)
				if i % 2 == 1 or meshes.is_empty():
					meshes = DenseBuilder.build_mixed(sd, 3.9, {"width": w, "depth": 36.0, "era": "prewar"}, 2)
			"cottage":
				# Homes with a backyard cottage, each era.
				HouseBuilder.grown = 2
				meshes = HouseBuilder.build(sd, 3.9, {"width": w, "depth": 45.0, "era": ["prewar", "postwar", "recent", "prewar", "postwar"][i]}, 2)
				HouseBuilder.grown = 0
			"raised":
				# A cape and a bungalow as built, then grown to two storeys.
				HouseBuilder.force_kind = ["cape", "cape", "bungalow", "bungalow", "foursquare"][i]
				meshes = HouseBuilder.build(seed * 100 + (i / 2) * 7, 3.9, {"width": w, "depth": 45.0, "era": "prewar"},
					[0, 2, 0, 2, 2][i])
				HouseBuilder.force_kind = ""
			"corner":
				# Corner stores: prewar on a corner (side street right, then
				# left), mid-block, then postwar ones.
				CommercialBuilder.force_shop = "corner"
				meshes = DenseBuilder.build_retail(sd, 3.9, {"width": w, "depth": 36.0, "era": ["prewar", "prewar", "prewar", "postwar", "postwar"][i],
					"corner": i != 2 and i != 4, "side": [1.0, -1.0, 0.0, 1.0, 0.0][i]}, {}, 0)
				CommercialBuilder.force_shop = ""
			"cornergrown":
				# Corner stores as built, then grown: prewar on a corner, postwar, prewar mid-block.
				CommercialBuilder.force_shop = "corner"
				meshes = DenseBuilder.build_retail(seed * 100 + (i / 2) * 7, 3.9, {"width": w, "depth": 36.0, "era": ["prewar", "prewar", "postwar", "postwar", "prewar"][i],
					"corner": i < 4, "side": 1.0 if i < 4 else 0.0}, {}, [0, 1, 0, 1, 1][i])
				CommercialBuilder.force_shop = ""
			"careshop": meshes = DenseBuilder.build_retail(seed * 100, 3.9, {"width": w, "depth": 40.0})
			"gasgrown":
				# Gas stations as built, then grown (a car wash on a wide lot).
				CommercialBuilder.force_shop = "gas"
				meshes = DenseBuilder.build_retail(seed * 100 + (i / 2) * 7, 3.9, {"width": w, "depth": 40.0, "era": "recent", "corner": true}, {}, i % 2)
				CommercialBuilder.force_shop = ""
			"shopsgrown":
				# A diner and a bank as built, then grown (a wing on the back).
				CommercialBuilder.force_shop = ["diner", "diner", "bank", "bank", "retail"][i]
				meshes = DenseBuilder.build_retail(seed * 100 + (i / 2) * 7, 3.9, {"width": w, "depth": 45.0, "era": "postwar"}, {}, i % 2)
				CommercialBuilder.force_shop = ""
			"retailgrown":
				# A store as built, then grown (stockroom out back, wares out front).
				CommercialBuilder.force_shop = "retail"
				meshes = DenseBuilder.build_retail(seed * 100 + (i / 2) * 7, 3.9, {"width": w, "depth": 45.0, "era": ["postwar", "recent"][(i / 2) % 2]}, {}, i % 2)
				CommercialBuilder.force_shop = ""
			_: meshes = HouseBuilder.build(sd, 3.9)
		HouseBuilder.owner_care = 0
		if far:
			var fm := BuildingView.far_version(meshes[0], HouseBuilder.last_masses, k == "factory", Color.WHITE, Color("#9c9a95"), meshes[1])
			fm.surface_set_material(0, HouseMaterials.get_mat("far"))
			meshes = [fm, ArrayMesh.new(), []]
		var at := Vector3(x + w * 0.5, 0, 0)
		x += w + (12.0 if k == "oddlots" else (10.0 if k == "corner" else 0.0))
		for m in meshes.slice(0, 2):
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.position = at
			world.add_child(mi)
		var planted := []
		for t in meshes[2]:
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), at + t[0])
			planted.append([xf, t[1], t[2]])
		if not "--notrees" in OS.get_cmdline_user_args():
			trees.set_trees(str(i), planted)
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[3])) if args.size() > 5 else deg_to_rad(20.0)
	var pitch := deg_to_rad(float(args[4])) if args.size() > 5 else deg_to_rad(18.0)
	var dist := float(args[5]) if args.size() > 5 else 70.0
	var target := Vector3(0, 3, 8)
	if args.size() > 7:
		target = Vector3(float(args[6]), float(args[7]), 8)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


## Lot i of the "oddlots" row: skewed 30 degrees either way, tapering to the
## back (the outside of a curve) or a pie lot (the inside of one).
static func _odd_lot(i: int, w: float) -> PackedVector2Array:
	var d := 36.0
	match i % 3:
		0:
			var k := d * tan(deg_to_rad(30.0)) * (1.0 if i == 0 else -1.0) * 0.5
			return PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2 + k, d), Vector2(-w / 2 + k, d)])
		1:
			return PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w * 0.25, d), Vector2(-w * 0.25, d)])
	return PackedVector2Array([Vector2(-w * 0.35, 0), Vector2(w * 0.35, 0), Vector2(w * 0.7, d), Vector2(-w * 0.7, d)])


func _process(_delta: float) -> bool:
	_frames += 1
	# GALLERY_HOUR=21 lights the row for that time of day (night signs, lit windows).
	if _frames == 2 and OS.get_environment("GALLERY_HOUR") != "":
		var hour := float(OS.get_environment("GALLERY_HOUR"))
		_sky.set_time(hour, 6.5)
		RenderingServer.global_shader_parameter_set("night", _sky.darkness)
		RenderingServer.global_shader_parameter_set("windows_lit", DayNight.window_share(hour))
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var out := args[0] if args.size() > 0 else "gallery.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
	return false
