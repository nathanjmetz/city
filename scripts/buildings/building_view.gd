class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown. Placeholder shapes for now;
## the realistic houses from the art library replace these later.

const SIDING := [
	Color(0.93, 0.92, 0.88), Color(0.86, 0.82, 0.72), Color(0.70, 0.76, 0.80),
	Color(0.62, 0.64, 0.63), Color(0.66, 0.71, 0.60), Color(0.80, 0.73, 0.62),
	Color(0.55, 0.30, 0.26),
]
const ROOFS := [Color(0.24, 0.24, 0.26), Color(0.33, 0.29, 0.26), Color(0.40, 0.40, 0.42)]
const BRICK := [Color(0.52, 0.27, 0.21), Color(0.62, 0.36, 0.26), Color(0.74, 0.66, 0.54)]
const AWNINGS := [Color(0.20, 0.35, 0.55), Color(0.55, 0.15, 0.15), Color(0.20, 0.42, 0.28)]
const METAL := [Color(0.72, 0.74, 0.75), Color(0.55, 0.60, 0.64), Color(0.80, 0.78, 0.72)]

var sim: CitySim
var _nodes := {}  # lot key -> Node3D
var _materials := {}


func setup(s: CitySim) -> void:
	sim = s
	sim.buildings_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for key in _nodes.keys():
		if not sim.buildings.has(key):
			_nodes[key].queue_free()
			_nodes.erase(key)
	for key in sim.buildings:
		if not _nodes.has(key) and sim.lots.has(key):
			_nodes[key] = _spawn(sim.lots[key], sim.buildings[key])


func _spawn(lot: Dictionary, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = lot.front
	# Local -Z faces the street, +Z runs back into the lot.
	root.basis = Basis.looking_at(-lot.normal, Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	match int(b.zone):
		ZoneMap.Zone.RESIDENTIAL: _house(root, rng)
		ZoneMap.Zone.COMMERCIAL: _shop(root, rng)
		ZoneMap.Zone.INDUSTRIAL: _factory(root, rng)
	# Grow in, like a new building going up.
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


func _house(root: Node3D, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(9.0, 13.0)
	var d := rng.randf_range(8.0, 10.5)
	var stories := 2 if rng.randf() < 0.35 else 1
	var wall_h := 2.8 * stories + 0.4
	var setback := 7.0
	var z := setback + d * 0.5
	_box(root, Vector3(w, wall_h, d), Vector3(0, wall_h * 0.5, z), _pick(rng, SIDING))
	var roof := _part(root, _gable_roof(w + 0.8, d + 0.8, d * 0.28), _pick(rng, ROOFS))
	roof.position = Vector3(0, wall_h, z)
	_box(root, Vector3(1.0, 2.1, 0.1), Vector3(0, 1.05, setback - 0.04), Color(0.35, 0.22, 0.15))
	# Driveway from the garage side out to the curb.
	var to_curb := RoadStyle.right_of_way_half() + 0.3 - RoadStyle.half_width()
	var drive_x := (w * 0.5 - 2.0) * (-1.0 if rng.randf() < 0.5 else 1.0)
	_flat(root, Vector2(3.4, setback + to_curb), Vector3(drive_x, 0.12, (setback - to_curb) * 0.5),
		Color(0.68, 0.67, 0.64))


func _shop(root: Node3D, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(14.0, 18.0)
	var d := rng.randf_range(12.0, 16.0)
	var h := 4.5 if rng.randf() < 0.6 else 7.5
	var setback := 9.0  # room for a small parking lot
	var z := setback + d * 0.5
	var wall := _pick(rng, BRICK)
	_box(root, Vector3(w, h, d), Vector3(0, h * 0.5, z), wall)
	_box(root, Vector3(w + 0.3, 0.6, d + 0.3), Vector3(0, h + 0.3, z), wall.darkened(0.15))
	_box(root, Vector3(w * 0.8, 2.6, 0.12), Vector3(0, 1.5, setback - 0.05), Color(0.25, 0.35, 0.42))
	var awning := _box(root, Vector3(w * 0.86, 0.15, 1.6), Vector3(0, 3.1, setback - 0.8), _pick(rng, AWNINGS))
	awning.rotation.x = deg_to_rad(-12.0)
	_box(root, Vector3(w * 0.5, 0.8, 0.2), Vector3(0, h - 0.8, setback - 0.12), Color(0.92, 0.90, 0.84))
	_flat(root, Vector2(w + 2.0, setback), Vector3(0, 0.03, setback * 0.5), Color(0.30, 0.30, 0.31))


func _factory(root: Node3D, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(15.0, 18.5)
	var d := rng.randf_range(16.0, 22.0)
	var h := rng.randf_range(6.0, 8.5)
	var setback := 6.0
	var z := setback + d * 0.5
	var metal := _pick(rng, METAL)
	_box(root, Vector3(w, h, d), Vector3(0, h * 0.5, z), metal)
	var roof := _part(root, _gable_roof(w + 0.6, d + 0.6, 1.4), metal.darkened(0.25))
	roof.position = Vector3(0, h, z)
	for i in 2:
		var x := (i - 0.5) * w * 0.45
		_box(root, Vector3(3.6, 4.0, 0.12), Vector3(x, 2.0, setback - 0.05), Color(0.40, 0.42, 0.44))
	if rng.randf() < 0.6:
		var stack := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.8
		cyl.height = h + 6.0
		stack.mesh = cyl
		stack.material_override = _mat(Color(0.45, 0.40, 0.38))
		stack.position = Vector3(w * 0.3, (h + 6.0) * 0.5, z + d * 0.3)
		root.add_child(stack)
	_flat(root, Vector2(w + 4.0, setback), Vector3(0, 0.03, setback * 0.5), Color(0.55, 0.54, 0.50))


func _box(root: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := _part(root, box, c)
	mi.position = pos
	return mi


func _flat(root: Node3D, size: Vector2, pos: Vector3, c: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := _part(root, plane, c)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _part(root: Node3D, mesh: Mesh, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	root.add_child(mi)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	if not _materials.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[c] = m
	return _materials[c]


static func _pick(rng: RandomNumberGenerator, list: Array) -> Color:
	return list[rng.randi() % list.size()]


## A simple gable roof with its ridge running left to right.
static func _gable_roof(w: float, d: float, h: float) -> ArrayMesh:
	var x := w * 0.5
	var z := d * 0.5
	var fl := Vector3(-x, 0, -z)
	var fr := Vector3(x, 0, -z)
	var bl := Vector3(-x, 0, z)
	var br := Vector3(x, 0, z)
	var rl := Vector3(-x, h, 0)
	var rr := Vector3(x, h, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [
		[fl, rl, rr], [fl, rr, fr],  # front slope
		[br, rr, rl], [br, rl, bl],  # back slope
		[bl, rl, fl], [fr, rr, br],  # gable ends
	]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
