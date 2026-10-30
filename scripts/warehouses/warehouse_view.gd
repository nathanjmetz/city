class_name WarehouseView
extends Node3D
## Draws warehouses (built by the art library's WarehouseBuilder). A
## warehouse is rebuilt when it builds up, adds a bay or an annex.

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
		if w == null or _shapes[id] != [w.kind, w.level, w.bays, w.get("built", []).size()]:
			_trees.remove(_nodes[id].get_meta("tree_key"))
			_nodes[id].queue_free()
			_nodes.erase(id)
			_shapes.erase(id)
	for id in sim.warehouses.buildings:
		if not _nodes.has(id) and not Warehouses.is_store(sim.warehouses.buildings[id]):
			var w: Dictionary = sim.warehouses.buildings[id]
			_nodes[id] = _spawn(id, w)
			_shapes[id] = [w.kind, w.level, w.bays, w.get("built", []).size()]


## Where warehouse `ref` ("wh:<id>" or its traffic ref "wh:<id>@x,z") is
## drawn, or null while it isn't (yet, or still going up): DoorView puts its
## dock doors there.
func xf_of(ref: String) -> Variant:
	var id := int(ref.substr(3).get_slice("@", 0))
	var node: Node3D = _nodes.get(id)
	if node == null or not sim.construction.is_done("wh:%d" % id, sim.tick_count):
		return null
	return Transform3D(node.basis, node.position)


func _spawn(id: int, w: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(Warehouses.center(w))
	# Local -Z faces the road.
	root.basis = Basis.looking_at(w.dir, Vector3.UP)
	var to_curb := Warehouses.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var seed := int(w.pos.x * 73.0) ^ int(w.pos.z * 151.0) ^ (id << 16)
	var built := WarehouseBuilder.build_warehouse(w, seed, to_curb)
	built[1] = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	var key := "wh:%d" % id
	root.set_meta("tree_key", key)
	# Concrete tilt-up, stage by stage (ConstructionSite); trees go in at the end.
	ConstructionSite.add_to(root, built, "warehouse", func(): return sim.construction.state(key, sim.tick_count),
		func():
			if not is_instance_valid(root):
				return
			var frame := Transform3D(root.basis, root.position)
			var trees := []
			for t in built[2]:
				var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
				var at: Transform3D = frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
				at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z)
				trees.append([at, t[1], t[2]])
			_trees.set_trees(key, trees))
	return root
