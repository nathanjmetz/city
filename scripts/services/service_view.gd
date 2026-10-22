class_name ServiceView
extends Node3D
## Draws service buildings (placeholder shapes until the art library has
## them) and, while placing one, which roads it would cover.

var sim: CitySim
## The kind whose coverage to show on the roads, or -1 for none.
var show_kind := -1:
	set(v):
		show_kind = v
		_draw_coverage()

var _nodes := {}  # service id -> Node3D
var _coverage := MeshInstance3D.new()
var _cover_mat := StandardMaterial3D.new()
var _mats := {}


func setup(s: CitySim) -> void:
	sim = s
	sim.lots_changed.connect(_sync)
	sim.stats_changed.connect(_draw_coverage)
	_cover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cover_mat.albedo_color = Color(0.35, 0.85, 0.45, 0.45)
	_cover_mat.no_depth_test = true
	_coverage.material_override = _cover_mat
	_coverage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coverage)
	_sync()


func _sync() -> void:
	for id in _nodes.keys():
		if not sim.services.buildings.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id in sim.services.buildings:
		if not _nodes.has(id):
			_nodes[id] = _spawn(sim.services.buildings[id])
	_draw_coverage()


## Roads within reach of the shown kind turn green; utilities light up every
## road they flow along.
func _draw_coverage() -> void:
	_coverage.visible = show_kind != -1 and sim.services.reach_by_kind.has(show_kind)
	if not _coverage.visible:
		return
	var dist: Dictionary = sim.services.reach_by_kind[show_kind]
	var reach: float = Services.KINDS[show_kind].get("reach", INF)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in sim.network.segments:
		var s: Dictionary = sim.network.segments[id]
		if dist.get(s.a, INF) <= reach or dist.get(s.b, INF) <= reach:
			var hw := RoadStyle.half_width(s.type)
			RoadMesh.add_strip(st, sim.network.sample_segment(id), -hw, hw, 0.35)
			any = true
	_coverage.visible = any
	if any:
		_coverage.mesh = st.commit()


func _spawn(b: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = b.pos
	# Local -Z faces the road.
	root.basis = Basis.looking_at(b.dir, Vector3.UP)
	var size: Vector2 = Services.KINDS[b.kind].size
	_box(root, Vector3(size.x, 0.12, size.y), Vector3.ZERO, Color(0.55, 0.55, 0.52))  # paved site
	match int(b.kind):
		Services.Kind.SUBSTATION:
			_box(root, Vector3(26, 0.2, 26), Vector3(0, 0.1, 0), Color(0.6, 0.58, 0.54))  # gravel yard
			for x in [-7.0, 0.0, 7.0]:
				_box(root, Vector3(3.5, 3.2, 3.0), Vector3(x, 1.7, 2), Color(0.45, 0.5, 0.48))
				_box(root, Vector3(0.4, 7.0, 0.4), Vector3(x, 3.5, -6), Color(0.6, 0.62, 0.64))
			_fence(root, 26.0, 26.0)
		Services.Kind.WATER_TOWER:
			# The classic Midwestern tank on legs, about 40 m tall.
			for a in 4:
				var p := Vector3(cos(a * PI * 0.5 + PI * 0.25), 0, sin(a * PI * 0.5 + PI * 0.25)) * 6.0
				_box(root, Vector3(0.8, 32.0, 0.8), p + Vector3(0, 16, 0), Color(0.72, 0.74, 0.76))
			_cyl(root, 1.4, 32.0, Vector3(0, 16, 0), Color(0.72, 0.74, 0.76))
			_sphere(root, 9.0, Vector3(0, 37, 0), Color(0.82, 0.85, 0.88))
			_box(root, Vector3(8, 4, 6), Vector3(8, 2, 8), Color(0.62, 0.36, 0.26))  # pump house
		Services.Kind.POWER_FEED:
			for x in [-4.0, 4.0]:
				_cyl(root, 0.18, 11.0, Vector3(x, 5.5, 0), Color(0.42, 0.33, 0.24))  # wood poles
				_cyl(root, 0.55, 1.4, Vector3(x, 8.5, 0.5), Color(0.55, 0.58, 0.6))   # transformers
			_box(root, Vector3(9.5, 0.15, 0.15), Vector3(0, 10.6, 0), Color(0.42, 0.33, 0.24))
		Services.Kind.WELL:
			_box(root, Vector3(7, 3.5, 6), Vector3(-4, 1.75, 2), Color(0.62, 0.36, 0.26))
			_roof_box(root, Vector3(7.4, 0.4, 6.4), Vector3(-4, 3.7, 2))
			_cyl(root, 1.6, 5.0, Vector3(5, 2.5, 3), Color(0.8, 0.82, 0.84))  # pressure tank
		Services.Kind.FIRE:
			_box(root, Vector3(24, 8, 22), Vector3(0, 4, 2), Color(0.58, 0.24, 0.2))
			for x in [-5.5, 5.5]:
				_box(root, Vector3(4.6, 4.6, 0.3), Vector3(x, 2.3, -9.1), Color(0.88, 0.88, 0.86))
			_box(root, Vector3(5, 12, 5), Vector3(-9, 6, 9), Color(0.55, 0.22, 0.18))  # hose tower
		Services.Kind.POLICE:
			_box(root, Vector3(24, 7, 18), Vector3(0, 3.5, 2), Color(0.78, 0.76, 0.7))
			_box(root, Vector3(24.4, 1.0, 18.4), Vector3(0, 6.5, 2), Color(0.2, 0.3, 0.5))
			_box(root, Vector3(0.3, 9, 0.3), Vector3(10, 4.5, -10), Color(0.8, 0.8, 0.8))  # flagpole
		Services.Kind.CLINIC:
			_box(root, Vector3(22, 6, 16), Vector3(0, 3, 3), Color(0.9, 0.9, 0.88))
			_box(root, Vector3(6, 1.6, 0.3), Vector3(0, 4.5, -5.1), Color(0.8, 0.15, 0.15))
			_box(root, Vector3(1.6, 6, 0.3), Vector3(0, 4.5, -5.1), Color(0.8, 0.15, 0.15))
		Services.Kind.SCHOOL:
			_box(root, Vector3(60, 7, 18), Vector3(0, 3.5, -12), Color(0.62, 0.36, 0.26))
			_box(root, Vector3(18, 7, 30), Vector3(-21, 3.5, 10), Color(0.62, 0.36, 0.26))
			_box(root, Vector3(40, 0.15, 30), Vector3(10, 0.1, 30), Color(0.33, 0.5, 0.25))  # playing field
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


func _roof_box(root: Node3D, size: Vector3, pos: Vector3) -> void:
	_box(root, size, pos, Color(0.25, 0.25, 0.27))


func _fence(root: Node3D, w: float, d: float) -> void:
	var c := Color(0.5, 0.52, 0.54)
	_box(root, Vector3(w, 2.2, 0.1), Vector3(0, 1.1, -d * 0.5), c)
	_box(root, Vector3(w, 2.2, 0.1), Vector3(0, 1.1, d * 0.5), c)
	_box(root, Vector3(0.1, 2.2, d), Vector3(-w * 0.5, 1.1, 0), c)
	_box(root, Vector3(0.1, 2.2, d), Vector3(w * 0.5, 1.1, 0), c)


func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(root, m, pos, color)


func _cyl(root: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	_add(root, m, pos, color)


func _sphere(root: Node3D, r: float, pos: Vector3, color: Color) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 1.6
	_add(root, m, pos, color)


func _add(root: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if not _mats.has(color):
		_mats[color] = RoadStyle.material(color)
	mi.material_override = _mats[color]
	root.add_child(mi)
