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
var _trail_mesh: MeshInstance3D
var _trail_stamp := ""
var _plaza_mesh: MeshInstance3D
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
	_draw_trails()


## The town's trails, laid over the land, redrawn when they grow.
func _draw_trails() -> void:
	var t := sim.parks.trails
	var stamp := "%d|%d|%d|%d" % [t.paths.size(), int(t.length()), sim.network.segments.size(), t.plazas.size()]
	if stamp == _trail_stamp:
		return
	_trail_stamp = stamp
	if _trail_mesh == null:
		_trail_mesh = MeshInstance3D.new()
		_trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_trail_mesh)
	_draw_plazas(t)
	if t.paths.is_empty():
		_trail_mesh.mesh = null
		return
	t._roads.clear()
	var flat := ParkBuilder.trails_mesh(t.paths, func(p: Vector3) -> bool:
		return t._on_road(sim, Vector2(p.x, p.z), 0.5))
	t._roads.clear()
	_trail_mesh.mesh = Terrain.drape_local(_split(flat, 4.0, LIFT), Transform3D.IDENTITY)


## Plazas: pavers over the closed block, with benches, planters and cafe tables.
func _draw_plazas(t: Trails) -> void:
	if _plaza_mesh == null:
		_plaza_mesh = MeshInstance3D.new()
		add_child(_plaza_mesh)
	for c in _plaza_mesh.get_children():
		c.queue_free()
	var blocks := []
	for seg in t.plazas:
		if sim.network.segments.has(seg):
			blocks.append({"pts": sim.network.sample_segment(seg, 12),
				"w": RoadStyle.half_width(sim.network.segments[seg].type) * 2.0})
	if blocks.is_empty():
		_plaza_mesh.mesh = null
		_trees.remove("plazas")
		return
	var art := ParkBuilder.plaza_mesh(blocks)
	_plaza_mesh.mesh = Terrain.drape_local(_split(art[0], 4.0, LIFT + 0.04), Transform3D.IDENTITY)
	var things := MeshInstance3D.new()
	things.mesh = Terrain.drape_local(art[1], Transform3D.IDENTITY)
	_plaza_mesh.add_child(things)
	var trees := []
	for tr in art[2]:
		var tf := Transform3D(Basis(Vector3.UP, fposmod(tr[0].x * 7.3 + tr[0].z * 3.1, TAU)).scaled(Vector3.ONE * tr[3]), tr[0])
		tf.origin.y += Terrain.ground_y(tf.origin.x, tf.origin.z)
		trees.append([tf, tr[1], tr[2]])
	_trees.set_trees("plazas", trees)


func _stamp(id: int) -> String:
	var s: Dictionary = sim.parks.sites[id]
	var v: Dictionary = sim.parks.tourism.venues.get(id, {})
	return "%s|%s|%d|%d|%s|%s|%s|%d" % [s.pos, s.size, s.tier, s.features.size(), s.get("name", ""),
		v.get("built", []), not v.get("crowd", {}).is_empty(), hash(s.get("edge", {}))]


func _spawn(id: int, fresh: bool) -> Node3D:
	var s: Dictionary = sim.parks.sites[id]
	_stamps[id] = _stamp(id)
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(s.pos)
	root.basis = Basis.looking_at(s.dir, Vector3.UP)
	var to_curb := Parks.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var town_name := town if town != "" else (Session.current_name if Session.current_name != "" else "My Town")
	var v: Dictionary = sim.parks.tourism.venues.get(id, {})
	if not v.is_empty():
		s = s.duplicate()
		s["venue_built"] = v.get("built", [])
		s["event_on"] = not v.get("crowd", {}).is_empty()
	var built := ParkBuilder.build_site(s, id * 7919 + int(s.founded), to_curb, town_name)
	var xform := Transform3D(root.basis, root.position)
	# Paths and lawns lie on the land, following it, cut small enough to
	# bend over a big park's rises. A park's things stand on the ground under
	# them; a landmark stands level as one building. Everything rides LIFT
	# above the drawn ground, so the land's own triangles never poke through.
	var house: Mesh = Terrain.drape_local(_split(built[0], 8.0, LIFT), xform) if s.kind == "park" else built[0]
	var flat := Terrain.drape_local(_split(built[1], 6.0, LIFT), xform)
	var lawn := MeshInstance3D.new()
	lawn.mesh = Terrain.drape_local(_split(built[4], 6.0, LIFT), xform)
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lawn)
	var labels := Node3D.new()
	root.add_child(labels)
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
		labels.add_child(label)
	var ref := "park:%d" % id
	if sim.construction.sites.has(ref):
		# A landmark or business goes up stage by stage (ConstructionSite);
		# its lawn, signs and trees come in once it's done.
		lawn.visible = false
		labels.visible = false
		ConstructionSite.add_to(root, [house, flat, built[2]], Parks.profile_of(s.kind),
			func(): return sim.construction.state(ref, sim.tick_count), _open.bind(id, root, lawn, labels, built[2]))
		return root
	for m in [house, flat]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		if m != house:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_open(id, root, lawn, labels, built[2])
	if fresh:
		root.scale = Vector3(1.0, 0.01, 1.0)
		create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## The finished site: its lawn and signs show and its trees go in.
func _open(id: int, root: Node3D, lawn: Node3D, labels: Node3D, planted: Array) -> void:
	if not is_instance_valid(root) or _nodes.get(id, root) != root:
		return
	lawn.visible = true
	labels.visible = true
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in planted:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var tf := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		tf.origin.y = Terrain.ground_y(tf.origin.x, tf.origin.z)
		trees.append([tf, t[1], t[2]])
	_trees.set_trees("park:%d" % id, trees)


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
