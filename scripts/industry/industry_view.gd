class_name IndustryView
extends Node3D
## Draws resource companies: the main building's yard and its access road,
## and every pad it has opened. Oil and ore come from the art library's
## IndustryBuilder: an office yard with a tank battery or crusher, pumpjack
## well pads (the walking beams rock) and stepped quarry pits. Forestry comes
## from ForestryBuilder: a sawmill yard, logging stands cut into woods, and
## the woods around them.
##
## Each company is drawn as a handful of merged meshes (one per material) and
## its pines go in the shared TreeField, so a big oil field or forest builds
## as fast as a street of houses.

const LANE := Color(0.58, 0.47, 0.33)

var sim: CitySim
var _sites := {}  # site id -> Node3D
var _beams := []  # pumpjack walking beams, rocked in _process
var _mats := {}
var _time := 0.0
var _trees := TreeField.new()
static var _beam_mesh: ArrayMesh
## Companies already drawn once, so a reload doesn't replay the grow-in.
var _loaded := false
var _signs := {}  # "site:<id>" -> the company's gate sign


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	sim.industry_changed.connect(_rebuild)
	sim.families.changed.connect(_sync_signs)
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
	_sync_signs()


## The company's sign at the gate where its road meets the street, like a
## quarry's or an oil lease's.
func _sync_signs() -> void:
	var lanes := {}
	for id in sim.industry.sites:
		lanes["site:%d" % id] = sim.industry.sites[id].drive
	SignText.sync_lanes(self, _signs, sim, lanes, true)


func _site(id: int, s: Dictionary) -> Node3D:
	var pines := []
	var root := Node3D.new()
	root.set_meta("pads", s.pads.size())
	add_child(root)
	# Lanes in one mesh, in world space.
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
	if s.kind == "forest":
		_forest(s, root, pines)
	else:
		_mine(id, s, root)
	_trees.set_trees("site:%d" % id, pines)
	if not _loaded:
		return root
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return root


## Oil and ore: the office yard and every pad from IndustryBuilder, merged
## into one mesh per material. Pumpjack walking beams stay separate nodes.
func _mine(id: int, s: Dictionary, root: Node3D) -> void:
	var merged := {}
	var none := []
	var hq := Transform3D(Basis.looking_at(s.dir, Vector3.UP), s.pos)
	_put(merged, IndustryBuilder.build_hq(s.kind, id) + [none], hq, none)
	for c in s.pads:
		var at := Transform3D(hq.basis, Industry.pad_center(s, c))
		_put(merged, IndustryBuilder.build_pad(s.kind, hash([id, c])) + [none], at, none)
		if s.kind == "oil":
			if _beam_mesh == null:
				_beam_mesh = IndustryBuilder.build_beam(7)
			var beam := MeshInstance3D.new()
			beam.mesh = _beam_mesh
			beam.transform = at * Transform3D(Basis.IDENTITY, Vector3(-3, 5.6, 0))
			beam.position.y += Terrain.ground_y(beam.position.x, beam.position.z)
			root.add_child(beam)
			_beams.append(beam)
	for mat in merged:
		var mi := MeshInstance3D.new()
		# On the land: ground work drapes over it, the rest stands on it.
		mi.mesh = Terrain.drape((merged[mat][0] as SurfaceTool).commit(), true, 8.0 if merged[mat][1] else 0.0)
		mi.material_override = mat
		if merged[mat][1]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


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


func _mat(color: Color) -> Material:
	if not _mats.has(color):
		_mats[color] = RoadStyle.material(color)
	return _mats[color]
