class_name BuildingView
extends Node3D
## Draws the buildings the simulation has grown, using the art library's
## HouseBuilder (homes) and CommercialBuilder (shops and factories).

var sim: CitySim
var _nodes := {}  # lot key -> Node3D


func setup(s: CitySim) -> void:
	sim = s
	sim.buildings_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for key in _nodes.keys():
		# Gone, or its lot moved (the road was widened).
		if not sim.buildings.has(key) or not sim.lots.has(key) \
				or not _nodes[key].position.is_equal_approx(sim.lots[key].front):
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
		ZoneMap.Zone.RESIDENTIAL: _add_built(root, HouseBuilder.build(rng.randi(), lot.to_curb))
		ZoneMap.Zone.COMMERCIAL: _add_built(root, CommercialBuilder.build_shop(rng.randi(), lot.to_curb))
		ZoneMap.Zone.INDUSTRIAL: _add_built(root, CommercialBuilder.build_factory(rng.randi(), lot.to_curb))
	# Grow in, like a new building going up.
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## Adds a building from the art builders: the building, then its flat ground
## work (drives, lots, beds), which casts no shadow.
func _add_built(root: Node3D, meshes: Array) -> void:
	var building := MeshInstance3D.new()
	building.mesh = meshes[0]
	root.add_child(building)
	var ground := MeshInstance3D.new()
	ground.mesh = meshes[1]
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
