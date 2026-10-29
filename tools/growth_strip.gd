extends SceneTree
## Draws one growth path stage by stage, left to right, each on the lot it
## would have by then (towers assemble lots under the area's FAR,
## BuildingTypes.area_for), through the game's own builder pick
## (BuildingView.build_for). For the growth-stage art loop.
## Run: godot -s tools/growth_strip.gd -- out.png <ladder> [seed] [era] [yaw pitch dist [target_x [target_y]]]
## Ladders: office, apartments, main (shop to Main Street block), homes
## (house to row homes to walk-up), house (a house building on, then a
## duplex and a fourplex). Era: postwar (default), prewar or recent.

const LADDERS := {
	# [type, level, FAR it's built under]
	"office": [["office", 0, 7.0], ["office", 1, 7.0], ["office", 2, 7.0], ["office", 3, 12.0], ["office", 4, 16.0]],
	"apartments": [["apartments", 0, 2.0], ["apartments", 1, 2.0], ["apartments", 2, 2.0], ["apartments", 3, 4.4], ["apartments", 4, 6.6]],
	"main": [["shop", 0, 2.2], ["shop", 1, 2.2], ["mixed_use", 0, 3.0], ["mixed_use", 1, 5.0], ["mixed_use", 2, 5.0]],
	# One 30-storey office in every form, on the same assembled site.
	"forms": [["office", 4, 16.0, "chicago"], ["office", 4, 16.0, "deco"], ["office", 4, 16.0, "glass"], ["office", 4, 16.0, "pomo"], ["office", 4, 16.0, "podium"]],
	"homeforms": [["apartments", 4, 6.6, "glass"], ["apartments", 4, 6.6, "podium"], ["apartments", 4, 6.6, "balcony"], ["apartments", 3, 4.4, "balcony"], ["apartments", 3, 4.4, "glass"]],
	# One prewar office on a storefront lot and on sites bought up next door.
	# Modernist glass towers on bought-up sites (their plazas).
	"plazas": [["office", 3, 12.0, "glass", 50.0], ["office", 4, 16.0, "glass", 64.0], ["office", 4, 16.0, "glass", 72.0]],
	"sites": [["office", 3, 12.0, "chicago", 30.0], ["office", 3, 12.0, "chicago", 62.0], ["office", 4, 16.0, "deco", 36.0], ["office", 4, 16.0, "deco", 66.0]],
	# A row of houses bought for a strip center, then a grocer-anchored one.
	"retail": [["shop", 0, 2.2], ["shop", 1, 2.2], ["shopping_center", 0, 2.2, "", 70.0], ["shopping_center", 1, 2.2, "", 150.0]],
	"homes": [["house", 0, 0.9], ["house", 1, 0.9], ["row_home", 0, 1.2], ["row_home", 1, 1.2], ["apartments", 0, 2.0]],
	# A house building on, then turned into a duplex and a fourplex.
	# A corner store to shop with flats, then bought out next door: a
	# commercial block across both storefronts.
	"block": [["shop", 0, 2.2], ["mixed_use", 0, 3.0], ["mixed_use", 1, 3.0], ["commercial_block", 0, 3.0], ["commercial_block", 1, 5.0]],
	"house": [["house", 0, 0.9], ["house", 1, 0.9], ["house", 2, 0.9], ["duplex", 0, 0.9], ["duplex", 1, 0.9]],
}
const BASE_W := {"shopping_center": 60.0, "office": 30.0, "apartments": 30.0, "mixed_use": 20.0, "shop": 20.0, "house": 20.0, "duplex": 22.0, "commercial_block": 28.0, "row_home": 24.0}
const DEPTH := 55.0

var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var name := args[1] if args.size() > 1 else "office"
	var ladder: Array = LADDERS.get(name, LADDERS.office)
	# "form:pomo" (or "homeform:podium"): one form at 12, 16, 24 and 30 storeys.
	if name.contains(":"):
		var t := "apartments" if name.begins_with("home") else "office"
		ladder = []
		for lv in ([3, 3, 4, 4] if t == "apartments" else [3, 3, 4, 4]):
			ladder.append([t, lv, 16.0 if lv == 4 else 12.0, name.get_slice(":", 1)])
	var seed := int(args[2]) if args.size() > 2 else 1
	var era := args[3] if args.size() > 3 else "postwar"
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	var widths := []
	var total := 0.0
	for st in ladder:
		var need := BuildingTypes.area_for(st[0], st[1], st[2])
		var w := maxf(BASE_W[st[0]], (need if need != INF else 0.0) / DEPTH)
		if st.size() > 4:
			w = st[4]
		widths.append(w)
		total += w + 6.0
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(total + 120.0, 9.0)
	road.mesh = plane
	road.material_override = Surfaces.asphalt()
	road.position = Vector3(0, 0.09, -8.4)
	world.add_child(road)
	var trees := TreeField.new()
	world.add_child(trees)
	# Left to right as seen from the street (+x is on the left).
	var x := total * 0.5
	for i in ladder.size():
		var st: Array = ladder[i]
		var w: float = widths[i]
		var storeys := int(BuildingTypes.TYPES[st[0]].stages[st[1]].storeys)
		var units := maxi(2, floori(w / float(BuildingTypes.TYPES.row_home.unit_w)))
		var meshes: Array
		# SIGN=1 hands each building an owner (its name on signs and towers).
		var spec := {}
		if OS.get_environment("SIGN") == "1":
			spec = {"text": "Overman Mutual", "style": "franklin", "panel": Color("#1f4e8a"), "letter": Color("#f3efe4"), "since": -1}
		if st.size() > 3 and st[3] != "":
			meshes = TowerBuilder.build_tower(seed * 100 + i, 3.9, {"width": w, "depth": DEPTH, "era": era}, storeys, spec, st[3], st[0] == "apartments")
		else:
			meshes = BuildingView.build_for(st[0], storeys, seed * 100, 3.9, {"width": w, "depth": DEPTH, "era": era}, spec, units, "general", st[1])
		# FAR=1 draws each as the game's far version of its drawing.
		if OS.get_environment("FAR") == "1":
			var fm := BuildingView.far_version(meshes[0], HouseBuilder.last_masses, false, Color("#b8b2a6"), Color("#6f6c66"), meshes[1])
			fm.surface_set_material(0, HouseMaterials.get_mat("far"))
			meshes = [fm, ArrayMesh.new(), []]
		var at := Vector3(x - w * 0.5, 0, 0)
		x -= w + 6.0
		for m in meshes.slice(0, 2):
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.position = at
			world.add_child(mi)
		if meshes.size() > 3:
			var signs := Node3D.new()
			signs.position = at
			world.add_child(signs)
			SignText.add(signs, meshes[3])
		var planted := []
		for t in meshes[2]:
			planted.append([Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), at + t[0]), t[1], t[2]])
		trees.set_trees(str(i), planted)
		print(st[0], " ", st[1], " storeys ", storeys, " lot ", snappedf(w, 0.1), " m")
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = 4000.0
	world.add_child(cam)
	var yaw := deg_to_rad(float(args[4])) if args.size() > 6 else deg_to_rad(12.0)
	var pitch := deg_to_rad(float(args[5])) if args.size() > 6 else deg_to_rad(14.0)
	var dist := float(args[6]) if args.size() > 6 else total * 1.05
	var target := Vector3(float(args[7]) if args.size() > 7 else 0.0, float(args[8]) if args.size() > 8 else 18.0, 20)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	cam.basis = Basis.looking_at(target - cam.position)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "strip.png")
		quit()
	return false
