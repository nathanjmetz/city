class_name FarmView
extends Node3D
## Draws farms: the fields each farm owns (crop rows that change with the
## seasons), farmsteads and their gravel lanes. (The Fertility view shows
## the soil; see InfoView.)

var sim: CitySim
var _fields := MeshInstance3D.new()
var _lanes := MeshInstance3D.new()
var _field_mat := StandardMaterial3D.new()
var _homes := {}  # farm id -> Node3D
var _trees := TreeField.new()
var _mats := {}
var _month := -1


func setup(s: CitySim) -> void:
	sim = s
	sim.farms_changed.connect(_rebuild)
	_field_mat.albedo_texture = _rows_texture()
	_field_mat.roughness = 1.0
	_field_mat.vertex_color_use_as_albedo = true
	_fields.material_override = _field_mat
	_lanes.material_override = RoadStyle.material(Color(0.58, 0.47, 0.33))  # tan crushed limestone and dirt
	for mi in [_fields, _lanes]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	add_child(_trees)
	_rebuild()


func _process(_delta: float) -> void:
	var month: int = sim.clock().month
	if month != _month:
		_month = month
		_draw_fields()


func _rebuild() -> void:
	_draw_fields()
	for id in _homes.keys():
		if not sim.farms.farms.has(id) or _homes[id].get_meta("look") != _look(sim.farms.farms[id]):
			_homes[id].queue_free()
			_homes.erase(id)
			_trees.remove(str(id))
	for id in sim.farms.farms:
		if not _homes.has(id):
			_homes[id] = _farmstead(id, sim.farms.farms[id])


## What the farmstead has built so far: house, then barn, then grain bins
## and a silo as the farm grows.
static func _look(f: Dictionary) -> int:
	if not f.barn:
		return 0
	return 1 + (1 if f.cells.size() >= 30 else 0) + (1 if f.cells.size() >= 100 else 0)


## What a field looks like this month in the Midwest.
func _season_color(crop: String) -> Color:
	var m := maxi(_month, 1)
	if m <= 3 or m == 12:
		return Color(0.6, 0.52, 0.38)  # winter stubble
	if m == 4:
		return Color(0.36, 0.27, 0.19)  # tilled black soil
	if m == 5:
		return Color(0.42, 0.42, 0.24)  # rows just up
	if m <= 8:
		return Color(0.2, 0.38, 0.13) if crop == "corn" else Color(0.26, 0.42, 0.18)
	if m == 9:
		return Color(0.62, 0.58, 0.3) if crop == "corn" else Color(0.68, 0.6, 0.25)
	return Color(0.66, 0.56, 0.36)  # harvested


## Each farm's fields as one patch, square to its farmhouse, with crop rows
## running back from the road.
func _draw_fields() -> void:
	if sim == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lanes := SurfaceTool.new()
	lanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var any_lane := false
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var col := _season_color(f.crop)
		for c in f.cells:
			_add_poly(st, f, Farms.cell_corners(f, c), 0.06, col)
			any = true
		if f.drive.size() >= 2:
			var pts := PackedVector3Array()
			for p in f.drive:
				pts.append(p)
			RoadMesh.add_strip(lanes, pts, -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.05)
			any_lane = true
	_fields.visible = any
	if any:
		_fields.mesh = st.commit()
	_lanes.visible = any_lane
	if any_lane:
		_lanes.mesh = lanes.commit()


func _add_poly(st: SurfaceTool, f: Dictionary, poly: PackedVector2Array, y: float, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	var right := Vector2(-f.dir.z, f.dir.x)
	var back := Vector2(-f.dir.x, -f.dir.z)
	var origin := Vector2(f.pos.x, f.pos.z)
	for k in range(0, tris.size(), 3):
		var a := poly[tris[k]]
		var b := poly[tris[k + 1]]
		var c := poly[tris[k + 2]]
		var order := [a, b, c] if (b - a).cross(c - a) > 0.0 else [a, c, b]
		for p in order:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			# Rows run back from the road: about one stripe per 2 m.
			var d: Vector2 = p - origin
			st.set_uv(Vector2(d.dot(right), d.dot(back)) / 16.0)
			st.add_vertex(Vector3(p.x, y, p.y))


## Crop rows: light and dark stripes, multiplied by the season's colour.
static func _rows_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 8:
			var v := 0.9 if x % 4 < 2 else 0.74
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## A Midwestern farmstead: white farmhouse first, then a red barn, grain
## bins and a concrete silo as the farm grows (see FarmBuilder). Its gravel
## lane is lined with a few shade trees.
func _farmstead(id: Variant, f: Dictionary) -> Node3D:
	var look := _look(f)
	var root := Node3D.new()
	root.set_meta("look", look)
	add_child(root)
	root.position = f.pos
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	var built := FarmBuilder.build_farmstead(hash(str(id)), look)
	var house := MeshInstance3D.new()
	house.mesh = built[0]
	root.add_child(house)
	var ground := MeshInstance3D.new()
	ground.mesh = built[1]
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var xf := Transform3D(root.basis, root.position)
	var planted := []
	for t in built[2]:
		planted.append([xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
	# Shade trees along the lane, alternating sides, the same every time.
	var drive: Array = f.drive
	var k := 0
	for i in range(2, drive.size() - 2, maxi(2, drive.size() / 4)):
		var a: Vector3 = drive[i]
		var b: Vector3 = drive[i + 1]
		var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * (5.5 if k % 2 == 0 else -5.5)
		var h := Farms._hash01(Vector2i(roundi(a.x), roundi(a.z)), 3)
		var sp: int = TreeField.Species.OAK if h < 0.5 else TreeField.Species.MAPLE
		var size := 0.9 + 0.35 * h
		planted.append([Transform3D(Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * size), a + side), sp, TreeField.LEAF[sp]])
		k += 1
	_trees.set_trees(str(id), planted)
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root
