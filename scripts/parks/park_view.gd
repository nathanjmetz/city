class_name ParkView
extends Node3D
## Draws parks and landmarks (built by the art library's ParkBuilder). A
## park is redrawn whenever it fills in, grows or its neighborhood changes
## tier, so the player watches it come together.

var sim: CitySim
## The town's name, painted on the water tower ("" = the city's save name).
var town := ""

var _nodes := {}  # site id -> Node3D
var _stamps := {}  # site id -> what it was drawn from
var _trees := TreeField.new()
## How far a park's ground cover rides above the drawn land, metres.
const LIFT := 0.12


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.parks_changed.connect(_sync)
	_sync()


func _sync() -> void:
	for id in _nodes.keys():
		var gone: bool = not sim.parks.sites.has(id)
		if gone or _stamp(id) != _stamps[id]:
			_trees.remove("park:%d" % id)
			_nodes[id].queue_free()
			_nodes.erase(id)
			if not gone:
				_nodes[id] = _spawn(id, false)
	for id in sim.parks.sites:
		if not _nodes.has(id):
			_nodes[id] = _spawn(id, true)


func _stamp(id: int) -> String:
	var s: Dictionary = sim.parks.sites[id]
	return "%s|%s|%d|%d" % [s.pos, s.size, s.tier, s.features.size()]


func _spawn(id: int, fresh: bool) -> Node3D:
	var s: Dictionary = sim.parks.sites[id]
	_stamps[id] = _stamp(id)
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(s.pos)
	root.basis = Basis.looking_at(s.dir, Vector3.UP)
	var to_curb := Parks.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var town_name := town if town != "" else (Session.current_name if Session.current_name != "" else "My Town")
	var built := ParkBuilder.build_site(s, id * 7919 + int(s.founded), to_curb, town_name)
	var xform := Transform3D(root.basis, root.position)
	for i in [0, 1, 4]:
		var mi := MeshInstance3D.new()
		# Paths and lawns lie on the land, following it, cut small enough
		# to bend over a big park's rises. A park's things stand on the
		# ground under them; a landmark stands level as one building.
		# Everything rides LIFT above the drawn ground, so the land's own
		# triangles never poke through a lawn.
		if i == 0:
			mi.mesh = Terrain.drape_local(_split(built[i], 8.0, LIFT), xform) if s.kind == "park" else built[i]
		else:
			mi.mesh = Terrain.drape_local(_split(built[i], 6.0, LIFT), xform)
		if i != 0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	for l in built[3]:
		var label := Label3D.new()
		label.text = l.text
		label.modulate = l.color
		label.outline_size = 0
		label.font_size = 64
		label.pixel_size = float(l.height) / 48.0
		label.double_sided = false
		label.shaded = true
		label.position = l.pos
		label.basis = Basis.looking_at(-l.normal, Vector3.UP)
		root.add_child(label)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var tf := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		tf.origin.y = Terrain.ground_y(tf.origin.x, tf.origin.z)
		trees.append([tf, t[1], t[2]])
	_trees.set_trees("park:%d" % id, trees)
	if fresh:
		root.scale = Vector3(1.0, 0.01, 1.0)
		create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## A copy of a mesh with no triangle edge longer than `edge` metres, raised
## by `dy`.
static func _split(mesh: ArrayMesh, edge: float, dy := 0.0) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := Terrain._split(mesh.surface_get_arrays(i), edge)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for k in verts.size():
			verts[k].y += dy
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out
