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
	for mi in [_fields, _area]:
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
		if not sim.farms.farms.has(id):
			_homes[id].queue_free()
			_homes.erase(id)
	for id in sim.farms.farms:
		if not _homes.has(id):
			_homes[id] = _farmstead(sim.farms.farms[id])


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


func _draw_fields() -> void:
	if sim == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		var col := _season_color(f.crop)
		# Rows run along the farmhouse's road, one way per farm.
		var along_x := absf(f.dir.x) < absf(f.dir.z)
		for c in f.cells:
			_quad(st, c, 0.06, col, along_x, 1.5)
			any = true
	_fields.visible = any
	if any:
		_fields.mesh = st.commit()


func _draw_area() -> void:
	if sim == null:
		return
	_area.visible = show_area and not sim.farms.area.is_empty()
	if not _area.visible:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in sim.farms.area:
		# Poor soil shows brown, rich soil green.
		var fert := Farms.fertility(c)
		var col := Color(0.62, 0.45, 0.25).lerp(Color(0.25, 0.75, 0.2), (fert - 0.45) / 0.55)
		col.a = 0.35
		_quad(st, c, 0.3, col, true, 0.0, 1.5)
	_area.mesh = st.commit()


static func _quad(st: SurfaceTool, c: Vector2i, y: float, col: Color, along_x: bool, rows: float, inset := 0.5) -> void:
	var x0 := c.x * Farms.CELL + inset
	var z0 := c.y * Farms.CELL + inset
	var x1 := (c.x + 1) * Farms.CELL - inset
	var z1 := (c.y + 1) * Farms.CELL - inset
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var n := Farms.CELL / maxf(rows, 0.001) / 8.0
	var pts := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		var uv: Vector2 = uvs[i] * n
		st.set_uv(uv if along_x else Vector2(uv.y, uv.x))
		st.add_vertex(pts[i])


## Crop rows: light and dark stripes, multiplied by the season's colour.
static func _rows_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 8:
			var v := 0.9 if y % 4 < 2 else 0.74
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## A Midwestern farmstead: white farmhouse, red barn, grain bins and a silo.
func _farmstead(f: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = f.pos
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	_box(root, Vector3(36, 0.1, 40), Vector3.ZERO, Color(0.55, 0.52, 0.45))  # gravel yard
	# House: two storeys, white siding, dark roof.
	_box(root, Vector3(9, 6, 8), Vector3(-10, 3, -12), Color(0.93, 0.92, 0.88))
	_roof(root, Vector3(9.6, 2.6, 8.6), Vector3(-10, 6, -12), Color(0.25, 0.25, 0.27))
	# Barn: red with a white-trimmed gambrel-like roof.
	_box(root, Vector3(14, 7, 20), Vector3(6, 3.5, 6), Color(0.58, 0.16, 0.13))
	_roof(root, Vector3(14.6, 4.5, 20.4), Vector3(6, 7, 6), Color(0.3, 0.3, 0.32))
	_box(root, Vector3(5, 5, 0.2), Vector3(6, 2.5, -4.1), Color(0.92, 0.9, 0.86))
	# Grain bins and a concrete stave silo.
	for i in 2:
		_cyl(root, 3.2, 7.0, Vector3(-12 + i * 7.5, 3.5, 10), Color(0.75, 0.77, 0.78))
		_cone(root, 3.4, 2.4, Vector3(-12 + i * 7.5, 8.2, 10), Color(0.75, 0.77, 0.78))
	_cyl(root, 2.6, 18.0, Vector3(15.5, 9.0, -6), Color(0.76, 0.74, 0.7))
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


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
