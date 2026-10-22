class_name FarmView
extends Node3D
## Draws farmland: the fields each farm owns (crop rows that change with the
## seasons), farmsteads, and while the farm tool is out, the painted area
## tinted by how fertile its soil is.

var sim: CitySim
var show_area := false:
	set(v):
		show_area = v
		_draw_area()

var _fields := MeshInstance3D.new()
var _area := MeshInstance3D.new()
var _lanes := MeshInstance3D.new()
var _field_mat := StandardMaterial3D.new()
var _area_mat := StandardMaterial3D.new()
var _homes := {}  # farm id -> Node3D
var _mats := {}
var _month := -1


func setup(s: CitySim) -> void:
	sim = s
	sim.farms_changed.connect(_rebuild)
	_field_mat.albedo_texture = _rows_texture()
	_field_mat.roughness = 1.0
	_field_mat.vertex_color_use_as_albedo = true
	_area_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_area_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_area_mat.vertex_color_use_as_albedo = true
	_fields.material_override = _field_mat
	_area.material_override = _area_mat
	_lanes.material_override = RoadStyle.material(Color(0.6, 0.55, 0.46))  # crushed limestone
	for mi in [_fields, _area, _lanes]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_rebuild()


func _process(_delta: float) -> void:
	var month: int = sim.clock().month
	if month != _month:
		_month = month
		_draw_fields()


func _rebuild() -> void:
	_draw_fields()
	_draw_area()
	for id in _homes.keys():
		if not sim.farms.farms.has(id) or _homes[id].get_meta("look") != _look(sim.farms.farms[id]):
			_homes[id].queue_free()
			_homes.erase(id)
	for id in sim.farms.farms:
		if not _homes.has(id):
			_homes[id] = _farmstead(sim.farms.farms[id])


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


## Each farm's fields as one patch, square to its farmhouse and trimmed to
## the painted outline, with crop rows running back from the road.
func _draw_fields() -> void:
	if sim == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lanes := SurfaceTool.new()
	lanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var any_lane := false
	var outlines := []
	for a in sim.farms.area:
		if a.on:
			outlines.append(a.points)
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var col := _season_color(f.crop)
		for c in f.cells:
			var quad := Farms.cell_corners(f, c)
			for outline in outlines:
				for piece in Geometry2D.intersect_polygons(quad, outline):
					_add_poly(st, f, piece, 0.06, col)
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


## While farming: the painted farmland, tinted by how fertile it is.
func _draw_area() -> void:
	if sim == null:
		return
	_area.visible = show_area and not sim.farms.area.is_empty()
	if not _area.visible:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 20.0
	var box := Rect2()
	var first := true
	for a in sim.farms.area:
		for p in a.points:
			box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
			first = false
	var any := false
	for x in range(floori(box.position.x / step), ceili(box.end.x / step)):
		for z in range(floori(box.position.y / step), ceili(box.end.y / step)):
			var mid := Vector3((x + 0.5) * step, 0.0, (z + 0.5) * step)
			if not sim.farms.is_farmland(mid):
				continue
			# Poor soil shows brown, rich soil green.
			var fert := Farms.fertility_at(mid)
			var col := Color(0.62, 0.45, 0.25).lerp(Color(0.25, 0.75, 0.2), (fert - 0.45) / 0.55)
			col.a = 0.35
			var quad := PackedVector2Array([Vector2(x, z) * step, Vector2(x + 1, z) * step,
				Vector2(x + 1, z + 1) * step, Vector2(x, z + 1) * step])
			# Trim the square to the outline it sits in, so edges follow the nodes.
			var pieces := [quad]
			for a in sim.farms.area:
				if a.on and Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z), a.points):
					pieces = Geometry2D.intersect_polygons(quad, a.points)
					break
			for piece in pieces:
				var tris := Geometry2D.triangulate_polygon(piece)
				for k in tris:
					st.set_color(col)
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(piece[k].x, 0.3, piece[k].y))
			any = true
	_area.visible = any
	if any:
		_area.mesh = st.commit()


## Crop rows: light and dark stripes, multiplied by the season's colour.
static func _rows_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 8:
			var v := 0.9 if x % 4 < 2 else 0.74
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## A Midwestern farmstead: white farmhouse first, then a red barn, grain
## bins and a concrete silo as the farm grows. Its gravel lane is lined
## with a few shade trees.
func _farmstead(f: Dictionary) -> Node3D:
	var look := _look(f)
	var root := Node3D.new()
	root.set_meta("look", look)
	add_child(root)
	root.position = f.pos
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	_box(root, Vector3(36, 0.1, 40), Vector3.ZERO, Color(0.55, 0.52, 0.45))  # gravel yard
	# House: two storeys, white siding, dark roof.
	_box(root, Vector3(9, 6, 8), Vector3(-10, 3, -12), Color(0.93, 0.92, 0.88))
	_roof(root, Vector3(9.6, 2.6, 8.6), Vector3(-10, 6, -12), Color(0.25, 0.25, 0.27))
	if look >= 1:
		# Barn: red with a white-trimmed roof.
		_box(root, Vector3(14, 7, 20), Vector3(6, 3.5, 6), Color(0.58, 0.16, 0.13))
		_roof(root, Vector3(14.6, 4.5, 20.4), Vector3(6, 7, 6), Color(0.3, 0.3, 0.32))
		_box(root, Vector3(5, 5, 0.2), Vector3(6, 2.5, -4.1), Color(0.92, 0.9, 0.86))
	if look >= 2:
		for i in 2:
			_cyl(root, 3.2, 7.0, Vector3(-12 + i * 7.5, 3.5, 10), Color(0.75, 0.77, 0.78))
			_cone(root, 3.4, 2.4, Vector3(-12 + i * 7.5, 8.2, 10), Color(0.75, 0.77, 0.78))
	if look >= 3:
		_cyl(root, 2.6, 18.0, Vector3(15.5, 9.0, -6), Color(0.76, 0.74, 0.7))
	# Shade trees along the lane, alternating sides, the same every time.
	var drive: Array = f.drive
	var inv := root.transform.affine_inverse()
	var k := 0
	for i in range(2, drive.size() - 2, maxi(2, drive.size() / 4)):
		var a: Vector3 = drive[i]
		var b: Vector3 = drive[i + 1]
		var side := Vector3(-(b - a).z, 0.0, (b - a).x).normalized() * (5.5 if k % 2 == 0 else -5.5)
		_tree(root, inv * (a + side), 0.8 + 0.4 * Farms._hash01(Vector2i(roundi(a.x), roundi(a.z)), 3))
		k += 1
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## A broadleaf shade tree (oak or maple), placeholder until the art library.
func _tree(root: Node3D, at: Vector3, size: float) -> void:
	_cyl(root, 0.35 * size, 4.0 * size, at + Vector3(0, 2.0 * size, 0), Color(0.36, 0.27, 0.2))
	var crown := SphereMesh.new()
	crown.radius = 4.2 * size
	crown.height = 7.0 * size
	_add(root, crown, at + Vector3(0, 6.5 * size, 0), Color(0.24, 0.38, 0.17))


func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(root, m, pos, color)


func _roof(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := PrismMesh.new()
	m.size = size
	_add(root, m, pos + Vector3(0, size.y * 0.5, 0), color)


func _cyl(root: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	_add(root, m, pos, color)


func _cone(root: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = 0.3
	m.bottom_radius = r
	m.height = h
	_add(root, m, pos, color)


func _add(root: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if not _mats.has(color):
		_mats[color] = RoadStyle.material(color)
	mi.material_override = _mats[color]
	root.add_child(mi)
