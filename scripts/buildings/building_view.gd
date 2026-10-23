class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown, using the art library's
## HouseBuilder (homes), CommercialBuilder (shops), FactoryBuilder
## (factories, one design per industry chain) and
## DenseBuilder (row homes, apartments, Main Street blocks, offices). Each
## building is drawn for its type and stage, and redrawn when it grows. New
## ones go up stage by stage (ConstructionSite).

var sim: CitySim
var _nodes := {}  # lot key -> Node3D
var _trees := TreeField.new()
static var _footing_mat: Material


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.buildings_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	# A business renamed, bought or with a new look gets new signs.
	sim.families.changed.connect(_sync)
	_sync()


func _sync() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	var t := Perf.now()
	_sync_all()
	Perf.add("frame.buildings", t)
	Terrain.shift = Vector2.ZERO


func _sync_all() -> void:
	for key in _nodes.keys():
		# Gone, or its lot moved (the road was widened), or its sign changed.
		if not sim.buildings.has(key) or not sim.lots.has(key) \
				or not _nodes[key].get_meta("front").is_equal_approx(sim.lots[key].front) \
				or _nodes[key].get_meta("look") != _look(sim.buildings[key]) \
				or _nodes[key].get_meta("sign") != sim.families.sign_key(sim, "lot:" + key) \
				or _nodes[key].get_meta("chain") != sim.buildings[key].get("chain", ""):
			_nodes[key].queue_free()
			_nodes.erase(key)
			_trees.remove(key)
	for key in sim.buildings:
		if not _nodes.has(key) and sim.lots.has(key):
			_nodes[key] = _spawn(key, sim.lots[key], sim.buildings[key])


## What the drawing depends on: type, stage and size.
static func _look(b: Dictionary) -> Array:
	return [BuildingTypes.type_of(b), int(b.get("level", 0)), int(b.get("units", 1))]


func _spawn(key: String, lot: Dictionary, b: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.set_meta("look", _look(b))
	add_child(root)
	root.set_meta("front", lot.front)
	root.set_meta("sign", sim.families.sign_key(sim, "lot:" + key))
	var spec := sim.families.sign_of(sim, "lot:" + key)
	root.set_meta("chain", b.get("chain", ""))  # a factory's look follows its chain
	# On the land: the lot is graded level with the road at its middle.
	root.position = Vector3(lot.front.x, Terrain.base_y(lot.pos.x, lot.pos.z), lot.front.z)
	# Local -Z faces the street, +Z runs back into the lot.
	root.basis = Basis.looking_at(-lot.normal, Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var built := []
	var fit := _local_lot(lot, Transform3D(root.basis, root.position))
	var s := rng.randi()
	var storeys := BuildingTypes.storeys(b)
	match BuildingTypes.type_of(b):
		"house": built = HouseBuilder.build(s, lot.to_curb, fit, storeys)
		"row_home": built = DenseBuilder.build_row(s, lot.to_curb, fit, int(b.get("units", 2)), storeys)
		"apartments": built = DenseBuilder.build_apartments(s, lot.to_curb, fit, storeys)
		"shop": built = DenseBuilder.build_retail(s, lot.to_curb, fit, spec)
		"mixed_use": built = DenseBuilder.build_mixed(s, lot.to_curb, fit, storeys, spec)
		"office":
			# Eight storeys and up is a downtown tower, built for its era.
			if storeys >= 8:
				built = TowerBuilder.build_tower(s, lot.to_curb, fit, storeys, spec)
			else:
				built = DenseBuilder.build_office(s, lot.to_curb, fit, storeys, spec)
		_: built = FactoryBuilder.build_chain(b.get("chain", "general"), s, lot.to_curb, fit, spec)
	if built.is_empty():
		return root
	# Drives, walks and beds lie on the ground, following it.
	built[1] = Terrain.drape_local(built[1], root.transform)
	# It goes up stage by stage; the trees and the sign's lettering go in
	# once it's done.
	var ref := "lot:" + key
	var labels: Array = built[3] if built.size() > 3 else []
	ConstructionSite.add_to(root, built, CitySim.PROFILE_OF_ZONE.get(int(b.zone), "house"),
		func(): return sim.construction.state(ref, sim.tick_count), _plant.bind(key, root, built[2], labels),
		_footing(built[0]))
	return root


## Trees go to the shared tree field, placed in world space on the ground,
## and the business's name onto its sign.
func _plant(key: String, root: Node3D, planted: Array, labels := []) -> void:
	if not is_instance_valid(root) or _nodes.get(key, root) != root:
		return
	SignText.add(root, labels)
	var was := Terrain.shift
	Terrain.shift = Terrain.shift_for(self)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in planted:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z) + t[0].y
		trees.append([at, t[1], t[2]])
	Terrain.shift = was
	_trees.set_trees(key, trees)


## The lot as the art builders want it: width, depth, flag pad, and the
## outline in the building's own frame (x across, z back from the street).
static func _local_lot(lot: Dictionary, frame: Transform3D) -> Dictionary:
	var fit := {"width": lot.get("width", 20.0), "depth": lot.get("depth", 32.0), "pad": lot.get("pad", 0.0),
		"at": Vector2(frame.origin.x, frame.origin.z), "corner": lot.get("corner", false)}
	var corners: PackedVector2Array = lot.get("corners", PackedVector2Array())
	if corners.size() >= 3:
		var inv := frame.affine_inverse()
		var local := PackedVector2Array()
		for c in corners:
			var q := inv * Vector3(c.x, 0.0, c.y)
			local.append(Vector2(q.x, q.z))
		fit.outline = local
	return fit


## A foundation down into the ground, for lots on a slope (or null).
func _footing(building: Mesh) -> MeshInstance3D:
	var box := building.get_aabb()
	if box.size.x <= 0.5:
		return null
	var footing := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(box.size.x * 0.96, 3.0, box.size.z * 0.96)
	footing.mesh = cube
	footing.position = Vector3(box.get_center().x, -1.45, box.get_center().z)
	if _footing_mat == null:
		_footing_mat = Surfaces.concrete(Color(0.55, 0.54, 0.51))
	footing.material_override = _footing_mat
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return footing
