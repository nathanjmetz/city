class_name CampusView
extends Node3D
## Draws every campus: its first building and each block its head has
## bought, rebuilt only when a block changes (CampusBuilder makes the art).

var sim: CitySim
var _nodes := {}  # block key -> Node3D
var _trees := TreeField.new()


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.education_changed.connect(_sync)
	_sync()


static func _key(id: int, c: Dictionary, blk) -> String:
	if blk == null:
		return "%d:main:%s:%.1f:%.1f" % [id, c.kind, c.pos.x, c.pos.z]
	return "%d:%d,%d:%s:%d:%.1f:%.1f" % [id, blk.c.x, blk.c.y, blk.use, blk.levels, c.pos.x, c.pos.z]


func _sync() -> void:
	var want := {}
	for id in sim.education.campuses:
		var c: Dictionary = sim.education.campuses[id]
		want[_key(id, c, null)] = [c, null]
		for blk in c.blocks:
			want[_key(id, c, blk)] = [c, blk]
	for key in _nodes.keys():
		if not want.has(key):
			_trees.remove(key)
			_nodes[key].queue_free()
			_nodes.erase(key)
	for key in want:
		if not _nodes.has(key):
			_nodes[key] = _spawn(key, want[key][0], want[key][1])


func _spawn(key: String, c: Dictionary, blk) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	# Local -Z faces the campus's street.
	root.basis = Basis.looking_at(c.dir, Vector3.UP)
	var cell: Vector2i = Vector2i.ZERO if blk == null else blk.c
	root.position = Education.block_center(c, cell)
	var seed := absi(hash(key))
	var built: Array
	if blk == null:
		var to_curb := Services.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
		built = CampusBuilder.build_main(c.kind, seed, to_curb)
	else:
		built = CampusBuilder.build_block(Education.dev(c.kind, blk.use).get("art", "hall"), blk.levels, seed)
	var building := MeshInstance3D.new()
	building.mesh = built[0]
	root.add_child(building)
	var ground := MeshInstance3D.new()
	ground.mesh = built[1]
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		trees.append([frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
	_trees.set_trees(key, trees)
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root
