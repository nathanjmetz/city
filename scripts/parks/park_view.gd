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
	var built := ParkBuilder.build_site(s, id * 7919 + int(s.built), to_curb, town_name)
	for i in [0, 1, 4]:
		var mi := MeshInstance3D.new()
		# Paths and lawns lie on the land, following it.
		mi.mesh = built[i] if i == 0 else Terrain.drape_local(built[i], Transform3D(root.basis, root.position))
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
		trees.append([frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0]), t[1], t[2]])
	_trees.set_trees("park:%d" % id, trees)
	if fresh:
		root.scale = Vector3(1.0, 0.01, 1.0)
		create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root
