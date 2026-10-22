class_name WarehouseView
extends Node3D
## Draws warehouses (built by the art library's WarehouseBuilder). A
## warehouse is rebuilt when it builds up or adds a bay.

var sim: CitySim

var _nodes := {}  # warehouse id -> Node3D
var _shapes := {}  # warehouse id -> [kind, level, bays] it was drawn at
var _trees := TreeField.new()


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.warehouses_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for id in _nodes.keys():
		var w = sim.warehouses.buildings.get(id)
		if w == null or _shapes[id] != [w.kind, w.level, w.bays]:
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
			_shapes.erase(id)
	for id in sim.warehouses.buildings:
		if not _nodes.has(id) and not Warehouses.is_store(sim.warehouses.buildings[id]):
			var w: Dictionary = sim.warehouses.buildings[id]
			_nodes[id] = _spawn(id, w)
			_shapes[id] = [w.kind, w.level, w.bays]


func _spawn(id: int, w: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(Warehouses.center(w))
	# Local -Z faces the road.
	root.basis = Basis.looking_at(w.dir, Vector3.UP)
	var to_curb := Warehouses.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var seed := int(w.pos.x * 73.0) ^ int(w.pos.z * 151.0) ^ (id << 16)
	var built := WarehouseBuilder.build_warehouse(w, seed, to_curb)
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
	var key := "wh:%d" % id
	_trees.set_trees(key, trees)
	root.set_meta("tree_key", key)
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root
