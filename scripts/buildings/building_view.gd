class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown, using the art library's
## HouseBuilder (homes) and CommercialBuilder (shops and factories).

var sim: CitySim
var _nodes := {}  # lot key -> Node3D
var _trees := TreeField.new()
static var _footing_mat: Material


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.buildings_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	_sync()


func _sync() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	_sync_all()
	Terrain.shift = Vector2.ZERO


func _sync_all() -> void:
	for key in _nodes.keys():
		# Gone, or its lot moved (the road was widened).
		if not sim.buildings.has(key) or not sim.lots.has(key) \
				or not _nodes[key].get_meta("front").is_equal_approx(sim.lots[key].front):
			_nodes[key].queue_free()
			_nodes.erase(key)
			_trees.remove(key)
	for key in sim.buildings:
		if not _nodes.has(key) and sim.lots.has(key):
			_nodes[key] = _spawn(key, sim.lots[key], sim.buildings[key])


func _spawn(key: String, lot: Dictionary, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.set_meta("front", lot.front)
	# On the land: the lot is graded level with the road at its middle.
	root.position = Vector3(lot.front.x, Terrain.base_y(lot.pos.x, lot.pos.z), lot.front.z)
	# Local -Z faces the street, +Z runs back into the lot.
	root.basis = Basis.looking_at(-lot.normal, Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var built := []
	var fit := _local_lot(lot, Transform3D(root.basis, root.position))
	match int(b.zone):
		ZoneMap.Zone.RESIDENTIAL: built = HouseBuilder.build(rng.randi(), lot.to_curb, fit)
		ZoneMap.Zone.COMMERCIAL: built = CommercialBuilder.build_shop(rng.randi(), lot.to_curb, fit)
		ZoneMap.Zone.INDUSTRIAL: built = CommercialBuilder.build_factory(rng.randi(), lot.to_curb, fit)
	if built.is_empty():
		return root
	_add_built(root, built)
	# Trees go to the shared tree field, placed in world space.
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		trees.append([at, t[1], t[2]])
	_trees.set_trees(key, trees)
	# Grow in, like a new building going up.
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## The lot as the art builders want it: width, depth, flag pad, and the
## outline in the building's own frame (x across, z back from the street).
static func _local_lot(lot: Dictionary, frame: Transform3D) -> Dictionary:
	var fit := {"width": lot.get("width", 20.0), "depth": lot.get("depth", 32.0), "pad": lot.get("pad", 0.0)}
	var corners: PackedVector2Array = lot.get("corners", PackedVector2Array())
	if corners.size() >= 3:
		var inv := frame.affine_inverse()
		var local := PackedVector2Array()
		for c in corners:
			var q := inv * Vector3(c.x, 0.0, c.y)
			local.append(Vector2(q.x, q.z))
		fit.outline = local
	return fit


## Adds a building from the art builders: the building, then its flat ground
## work (drives, lots, beds), which casts no shadow.
func _add_built(root: Node3D, meshes: Array) -> void:
	var building := MeshInstance3D.new()
	building.mesh = meshes[0]
	root.add_child(building)
	# A foundation down into the ground, for lots on a slope.
	var box := (meshes[0] as Mesh).get_aabb()
	if box.size.x > 0.5:
		var footing := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(box.size.x * 0.96, 3.0, box.size.z * 0.96)
		footing.mesh = cube
		footing.position = Vector3(box.get_center().x, -1.45, box.get_center().z)
		if _footing_mat == null:
			_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
		footing.material_override = _footing_mat
		footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(footing)
	var ground := MeshInstance3D.new()
	# Drives, walks and beds lie on the ground, following it.
	ground.mesh = Terrain.drape_local(meshes[1], root.transform)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
