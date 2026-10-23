class_name BigFactoryView
extends Node3D
## Draws the big local factories (built by BigFactoryBuilder). A plant is
## rebuilt when it adds a line or a bay.

var sim: CitySim

var _nodes := {}  # id -> Node3D
var _shapes := {}  # id -> [kind, level, bays] it was drawn at
var _trees := TreeField.new()


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.big_factories_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for id in _nodes.keys():
		var f = sim.big.sites.get(id)
		if f == null or _shapes[id] != [f.kind, f.level, f.bays, f.get("built", []).size()]:
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
			_shapes.erase(id)
	for id in sim.big.sites:
		if not _nodes.has(id):
			var f: Dictionary = sim.big.sites[id]
			_nodes[id] = _spawn(id, f)
			_shapes[id] = [f.kind, f.level, f.bays, f.get("built", []).size()]


func _spawn(id: int, f: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(BigFactories.center(f))
	# Local -Z faces the road.
	root.basis = Basis.looking_at(f.dir, Vector3.UP)
	var to_curb := BigFactories.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var seed := int(f.pos.x * 73.0) ^ int(f.pos.z * 151.0) ^ (id << 16)
	var built := BigFactoryBuilder.build_plant(f, seed, to_curb)
	var building := MeshInstance3D.new()
	building.mesh = built[0]
	root.add_child(building)
	var ground := MeshInstance3D.new()
	ground.mesh = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		trees.append([frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
	var key := "big:%d" % id
	_trees.set_trees(key, trees)
	root.set_meta("tree_key", key)
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root
