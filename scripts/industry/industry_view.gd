class_name IndustryView
extends Node3D
## Draws resource companies: the main building's yard and its access road,
## and every pad it has opened. Oil pads get a working pumpjack, ore pads a
## terraced pit with a stockpile (placeholders until the art library has
## them). Forestry comes from the art library's ForestryBuilder: a sawmill
## yard, logging stands cut into woods, and the woods around them.
##
## Each company is drawn as a handful of merged meshes (one per colour) and
## its pines go in the shared TreeField, so a big oil field or forest builds
## as fast as a street of houses.

const GRAVEL := Color(0.6, 0.57, 0.5)
const LANE := Color(0.58, 0.47, 0.33)

var sim: CitySim
var _sites := {}  # site id -> Node3D
var _beams := []  # pumpjack walking beams, rocked in _process
var _mats := {}
var _time := 0.0
var _trees := TreeField.new()
## While a site is built: colour -> SurfaceTool, every static piece merged.
var _batch := {}
## Companies already drawn once, so a reload doesn't replay the grow-in.
var _loaded := false


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.industry_changed.connect(_rebuild)
	_rebuild()
	_loaded = true


func _process(delta: float) -> void:
	_time += delta
	for i in _beams.size():
		var b = _beams[i]
		if is_instance_valid(b):
			b.rotation.z = sin(_time * 1.6 + i * 1.3) * 0.32


func _rebuild() -> void:
	for id in _sites.keys():
		var s = sim.industry.sites.get(id)
		if s == null or _sites[id].get_meta("pads") != s.pads.size():
			_sites[id].queue_free()
			_sites.erase(id)
			_trees.remove("site:%d" % id)
	_beams = _beams.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
	for id in sim.industry.sites:
		if not _sites.has(id):
			_sites[id] = _site(id, sim.industry.sites[id])


func _site(id: int, s: Dictionary) -> Node3D:
	_batch = {}
	var pines := []
	var root := Node3D.new()
	root.set_meta("pads", s.pads.size())
	add_child(root)
	# Flat things (yard, pads, lanes) in one mesh, in world space.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(LANE)
	if s.drive.size() >= 2:
		RoadMesh.add_strip(st, Terrain.densify(PackedVector3Array(s.drive), 6.0), -Farms.DRIVE_WIDTH * 0.5, Farms.DRIVE_WIDTH * 0.5, 0.12)
	# Each pad's track runs to the neighbour nearer the main building.
	for c in s.pads:
		var to: Vector2i = c
		for d in [Vector2i(-signi(c.x), 0), Vector2i(0, -signi(c.y))]:
			if d != Vector2i.ZERO and (c + d == Vector2i.ZERO or (c + d) in s.pads):
				to = c + d
				break
		if to == c:
			to = Vector2i.ZERO
		RoadMesh.add_strip(st, PackedVector3Array([Industry.pad_center(s, c), Industry.pad_center(s, to)]),
			-2.0, 2.0, 0.1)
	var flat := MeshInstance3D.new()
	flat.mesh = Terrain.drape(st.commit(), true, 8.0)
	flat.material_override = _mat(LANE)
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flat)
	var hq := Node3D.new()
	hq.set_meta("static", true)
	hq.position = Vector3(s.pos.x, Terrain.ground_y(s.pos.x, s.pos.z), s.pos.z)
	hq.basis = Basis.looking_at(s.dir, Vector3.UP)
	root.add_child(hq)
	if s.kind != "forest":
		# Gravel yard, graded level; its edge runs down into the ground on a slope.
		_box(hq, Vector3(Industry.HQ_SIZE.x, 3.0, Industry.HQ_SIZE.y), Vector3(0, -1.45, 0), GRAVEL)
		_box(hq, Vector3(14, 4.5, 10), Vector3(-8, 2.25, -10), Color(0.82, 0.8, 0.74))  # office
		_box(hq, Vector3(14.6, 0.5, 10.6), Vector3(-8, 4.75, -10), Color(0.3, 0.3, 0.32))
	match s.kind:
		"oil":
			for i in 3:  # tank battery
				_cyl(hq, 2.6, 7.0, Vector3(6 + i * 6.0, 3.5, 6), Color(0.55, 0.5, 0.36))
		"ore":
			_box(hq, Vector3(12, 10, 12), Vector3(8, 5, 4), Color(0.45, 0.47, 0.5))  # crusher house
			_cone(hq, 7.0, 6.0, Vector3(-8, 3, 10), Color(0.42, 0.33, 0.27))
	for c in s.pads:
		var pad := Node3D.new()
		pad.set_meta("static", true)
		var spot := Industry.pad_center(s, c)
		pad.position = Vector3(spot.x, Terrain.ground_y(spot.x, spot.z), spot.z)
		pad.basis = hq.basis
		root.add_child(pad)
		match s.kind:
			"oil":
				_box(pad, Vector3(26, 2.0, 22), Vector3(0, -0.95, 0), GRAVEL)
				_pumpjack(pad, Vector3(-3, 0, 0))
				_cyl(pad, 2.0, 5.0, Vector3(8, 2.5, 6), Color(0.55, 0.5, 0.36))
			"ore":
				# A terraced pit: rings stepping down to a dark floor.
				for i in 3:
					var w := 70.0 - i * 16.0
					_box(pad, Vector3(w, 0.1 + i * 0.02, w), Vector3(0, 0.05 + i * 0.02, 0),
						Color(0.52, 0.44, 0.36).darkened(i * 0.16))
				_cone(pad, 6.0, 5.0, Vector3(26, 2.5, -26), Color(0.4, 0.36, 0.33))
	# Merge every static piece: one mesh per colour for the whole company.
	for color in _batch:
		var mi := MeshInstance3D.new()
		mi.mesh = (_batch[color] as SurfaceTool).commit()
		mi.material_override = _mat(color)
		root.add_child(mi)
	_batch = {}
	if s.kind == "forest":
		_forest(s, root, pines)
	_trees.set_trees("site:%d" % id, pines)
	if not _loaded:
		return root
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## A beam pumpjack: base, samson post, and a walking beam with a horsehead.
func _pumpjack(root: Node3D, at: Vector3) -> void:
	var steel := Color(0.36, 0.38, 0.4)
	_box(root, Vector3(9, 0.8, 2.4), at + Vector3(0, 0.4, 0), steel)
	_box(root, Vector3(0.6, 5.0, 1.6), at + Vector3(0, 3.0, 0), steel)
	var beam := Node3D.new()
	beam.position = at + Vector3(0, 5.6, 0)
	root.add_child(beam)
	_box(beam, Vector3(9, 0.7, 0.7), Vector3.ZERO, Color(0.85, 0.66, 0.2))
	_box(beam, Vector3(1.0, 2.2, 0.9), Vector3(-4.6, -0.6, 0), Color(0.85, 0.66, 0.2))  # horsehead
	_box(root, Vector3(2.4, 2.4, 2.0), at + Vector3(3.6, 1.6, 0), steel)  # gearbox and crank
	_beams.append(beam)


## Forestry: the sawmill yard, each logging stand as a cut inside woods,
## and untouched woods on the forest land around them. Trees go to one
## shared TreeField, keyed by the company.
func _forest(s: Dictionary, root: Node3D, trees: Array) -> void:
	var basis := Basis.looking_at(s.dir, Vector3.UP)
	var merged := {}  # material -> SurfaceTool, every cell merged
	var seed0 := hash([roundi(s.pos.x), roundi(s.pos.z)])
	_put(merged, ForestryBuilder.mill(seed0, Industry.HQ_SIZE), Transform3D(basis, s.pos), trees)
	# Which cells are wooded: the stands, the mill's own cell, and every free
	# forest cell next to them.
	var wooded := {Vector2i.ZERO: true}
	for c in s.pads:
		wooded[c] = true
	var woods := []
	for c in s.pads + [Vector2i.ZERO]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if wooded.has(n):
				continue
			wooded[n] = false
			var mid := Industry.pad_center(s, n)
			if Industry.richness(s, n) >= Industry.MIN_RICHNESS * 0.6 \
					and sim.field_usable(mid, Industry.pad_corners(s, n)) and not _near_road(mid):
				wooded[n] = true
				woods.append(n)
	for c in wooded:
		if not wooded[c]:
			continue
		var frame := Transform3D(basis, Industry.pad_center(s, c))
		var open := []
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			open.append(not wooded.get(c + d, false))
		# Keep trees off the company's drive.
		var clear := []
		var inv := frame.affine_inverse()
		for i in s.drive.size() - 1:
			var a: Vector3 = inv * s.drive[i]
			var b: Vector3 = inv * s.drive[i + 1]
			clear.append([Vector2(a.x, a.z), Vector2(b.x, b.z), 6.0])
		var cseed := hash([seed0, c])
		if c == Vector2i.ZERO:
			# The mill's clearing.
			clear.append([Vector2(-6, 0), Vector2(6, 0), 34.0])
			_put(merged, ForestryBuilder.woods(cseed, Industry.PAD, 1.0, clear, open), frame, trees)
		elif c in s.pads:
			var dir: Vector3 = basis.inverse() * (Industry.pad_center(s, _track_to(s, c)) - Industry.pad_center(s, c))
			_put(merged, ForestryBuilder.stand(cseed, Industry.PAD, Vector2(dir.x, dir.z), clear, open), frame, trees)
		else:
			_put(merged, ForestryBuilder.woods(cseed, Industry.PAD, 1.0, clear, open), frame, trees)
	for mat in merged:
		var mi := MeshInstance3D.new()
		# On the land: ground work drapes over it, the rest stands on it.
		mi.mesh = Terrain.drape((merged[mat][0] as SurfaceTool).commit(), true, 8.0 if merged[mat][1] else 0.0)
		mi.material_override = mat
		if merged[mat][1]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## True when a public road runs through or beside this cell.
func _near_road(mid: Vector3) -> bool:
	return not sim.network.find_segment_near(mid, Industry.PAD * 0.75, 1.0).is_empty()


## The pad a stand's haul track runs to (as drawn in _site).
func _track_to(s: Dictionary, c: Vector2i) -> Vector2i:
	for d in [Vector2i(-signi(c.x), 0), Vector2i(0, -signi(c.y))]:
		if d != Vector2i.ZERO and (c + d == Vector2i.ZERO or (c + d) in s.pads):
			return c + d
	return Vector2i.ZERO


## Adds a builder's meshes at `frame` into `merged` (one surface per
## material; flat ground work casts no shadow), and its trees in world space.
func _put(merged: Dictionary, built: Array, frame: Transform3D, trees: Array) -> void:
	for k in 2:
		var mesh: ArrayMesh = built[k]
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if not merged.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				merged[mat] = [st, k == 1]
			(merged[mat][0] as SurfaceTool).append_from(mesh, i, frame)
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y += Terrain.ground_y(at.origin.x, at.origin.z)
		trees.append([at, t[1], t[2]])


func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(root, m, pos, color)


func _cyl(root: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	_add(root, m, pos, color)


func _cone(root: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = 0.3
	m.bottom_radius = r
	m.height = h
	_add(root, m, pos, color)


func _add(root: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	if root.has_meta("static"):
		if not _batch.has(color):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batch[color] = st
		(_batch[color] as SurfaceTool).append_from(mesh, 0, root.transform * Transform3D(Basis.from_euler(rot), pos))
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(color)
	root.add_child(mi)


func _mat(color: Color) -> Material:
	if not _mats.has(color):
		_mats[color] = RoadStyle.material(color)
	return _mats[color]
