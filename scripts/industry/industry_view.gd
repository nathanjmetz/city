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
	# Each pad's lease road or skid trail joins the nearest pad that's nearer
	# the main building, so they branch like real lease roads.
	for c in s.pads:
		if s.kind == "ore":
			break  # the strip mine's haul road is its track
		RoadMesh.add_strip(st, Industry.track(s, c), -2.0, 2.0, 0.1)
	var flat := MeshInstance3D.new()
	flat.mesh = Terrain.drape(st.commit(), true, 8.0)
	flat.material_override = Surfaces.lane(LANE)
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flat)
	if s.kind == "forest":
		_forest(id, s, root, pines)
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
## One strip mine cut and its spoil ridge, metres across.
const STRIP_PITCH := 30.0


func _mine(id: int, s: Dictionary, root: Node3D) -> void:
	var merged := {}
	var none := []
	var hq := Transform3D(Basis.looking_at(s.dir, Vector3.UP), s.pos)
	_hq(id, s, root, IndustryBuilder.build_hq(s.kind, id), [])
	if s.kind == "ore" and not s.pads.is_empty():
		_strip_mine(s, hq, root)
	for c in s.pads:
		if s.kind == "ore":
			break
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
		mi.material_override = merged[mat][2]
		if merged[mat][1]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Forestry: the sawmill yard, each logging stand as a cut inside woods,
## and untouched woods on the forest land around them. Trees go to one
## shared TreeField, keyed by the company.
func _forest(id: int, s: Dictionary, root: Node3D, trees: Array) -> void:
	var basis := Basis.looking_at(s.dir, Vector3.UP)
	var merged := {}  # material -> SurfaceTool, every cell merged
	var seed0 := hash([roundi(s.pos.x), roundi(s.pos.z)])
	_hq(id, s, root, ForestryBuilder.mill(seed0, Industry.HQ_SIZE), trees)
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
	var tracks := []
	for c in s.pads:
		tracks.append(Industry.track(s, c))
	for c in wooded:
		if not wooded[c]:
			continue
		var frame := Transform3D(basis, Industry.pad_center(s, c))
		var open := []
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			open.append(not wooded.get(c + d, false))
		# Keep trees off the company's drive and its logging roads.
		var clear := []
		var inv := frame.affine_inverse()
		for i in s.drive.size() - 1:
			var a: Vector3 = inv * s.drive[i]
			var b: Vector3 = inv * s.drive[i + 1]
			clear.append([Vector2(a.x, a.z), Vector2(b.x, b.z), 6.0])
		for road in tracks:
			for i in road.size() - 1:
				var a: Vector3 = inv * road[i]
				var b: Vector3 = inv * road[i + 1]
				var reach := Industry.PAD * 0.5 + 8.0
				if minf(absf(a.x), absf(b.x)) < reach and minf(absf(a.z), absf(b.z)) < reach:
					clear.append([Vector2(a.x, a.z), Vector2(b.x, b.z), 5.0])
		var cseed := hash([seed0, c])
		if c == Vector2i.ZERO:
			# The mill's clearing.
			clear.append([Vector2(-6, 0), Vector2(6, 0), 34.0])
			_put(merged, ForestryBuilder.woods(cseed, Industry.PAD, 1.0, clear, open), frame, trees)
		elif c in s.pads:
			var dir: Vector3 = basis.inverse() * (Industry.pad_center(s, Industry.track_to(s, c)) - Industry.pad_center(s, c))
			_put(merged, ForestryBuilder.stand(cseed, Industry.PAD, Vector2(dir.x, dir.z), clear, open), frame, trees)
		else:
			_put(merged, ForestryBuilder.woods(cseed, Industry.PAD, 1.0, clear, open), frame, trees)
	for mat in merged:
		var mi := MeshInstance3D.new()
		# On the land: ground work drapes over it, the rest stands on it.
		mi.mesh = Terrain.drape((merged[mat][0] as SurfaceTool).commit(), true, 8.0 if merged[mat][1] else 0.0)
		mi.material_override = merged[mat][2]
		if merged[mat][1]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## The map's ore is Pike County coal, so a mining company is a surface
## strip mine (Brawn: everything against its real version; benchmark:
## aerial photos of Pike and Warrick County, Indiana strip mines). One mine
## over all its ground, never a pit per cell: long parallel cuts across the
## seam, the open cut with its dark coal face where the newest ground is,
## grey-brown spoil ridges behind it, older cuts left as lakes, and the
## oldest ground reclaimed to grass.
func _strip_mine(s: Dictionary, hq: Transform3D, root: Node3D) -> void:
	var inv := hq.affine_inverse()
	var union := []
	for i in s.pads.size():
		var sq := PackedVector2Array()
		for p in Industry.pad_corners(s, s.pads[i]):
			var q: Vector3 = inv * Vector3(p.x, 0.0, p.y)
			sq.append(Vector2(q.x, q.z))
		if Geometry2D.is_polygon_clockwise(sq):
			sq.reverse()
		union = _merge(union, Geometry2D.offset_polygon(sq, 0.5)[0])
	var outlines := []
	var lo := INF
	var hi := -INF
	var x0 := INF
	var x1 := -INF
	for poly in union:
		# Round it off like ground dug along a seam, not cut on a grid.
		for q in Geometry2D.offset_polygon(poly, -26.0, Geometry2D.JOIN_ROUND):
			for o in Geometry2D.offset_polygon(q, 18.0, Geometry2D.JOIN_ROUND):
				if not Geometry2D.is_polygon_clockwise(o):
					outlines.append(o)
					for p in o:
						lo = minf(lo, p.y)
						hi = maxf(hi, p.y)
						x0 = minf(x0, p.x)
						x1 = maxf(x1, p.x)
	if outlines.is_empty():
		return
	# How new the ground under each cut is: the newest pad it crosses.
	var n: int = s.pads.size()
	var rows := []
	var z := lo
	while z < hi:
		var mid := z + STRIP_PITCH * 0.5
		var newest := -1
		for i in n:
			var c: Vector3 = inv * Industry.pad_center(s, s.pads[i])
			if absf(c.z - mid) <= Industry.PAD * 0.5:
				newest = maxi(newest, i)
		rows.append([z, float(n - 1 - newest)])  # 0: the pad opened last
		z += STRIP_PITCH
	var merged := {}
	var none := []
	_put(merged, IndustryBuilder.build_strip_mine(hash(s.pos), outlines, rows, STRIP_PITCH) + [none], hq, none)
	for mat in merged:
		var mi := MeshInstance3D.new()
		mi.mesh = Terrain.drape((merged[mat][0] as SurfaceTool).commit(), true, 8.0 if merged[mat][1] else 0.0)
		mi.material_override = merged[mat][2]
		if merged[mat][1]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Adds a polygon into a set of merged outlines.
static func _merge(polys: Array, add: PackedVector2Array) -> Array:
	var out := []
	var cur := add
	for p in polys:
		var m := Geometry2D.merge_polygons(p, cur)
		var outer := m.filter(func(q): return not Geometry2D.is_polygon_clockwise(q))
		if outer.size() == 1:
			cur = outer[0]  # joined (holes dropped: a quarry has none)
		else:
			out.append(p)
	out.append(cur)
	return out


## True when a public road runs through or beside this cell.
func _near_road(mid: Vector3) -> bool:
	return not sim.network.find_segment_near(mid, Industry.PAD * 0.75, 1.0).is_empty()


## Adds a builder's meshes at `frame` into `merged` (one surface per
## material; flat ground work casts no shadow), and its trees in world space.
## The company's main building on its own node, so it goes up stage by
## stage (ConstructionSite) like any steel-frame plant.
func _hq(id: int, s: Dictionary, root: Node3D, built: Array, trees: Array) -> void:
	var node := Node3D.new()
	root.add_child(node)
	node.transform = Transform3D(Basis.looking_at(s.dir, Vector3.UP),
		Vector3(s.pos.x, Terrain.ground_y(s.pos.x, s.pos.z), s.pos.z))
	var parts := [built[0], Terrain.drape_local(built[1], node.transform)]
	if built.size() > 2:
		_put({}, [ArrayMesh.new(), ArrayMesh.new(), built[2]], Transform3D(node.basis, s.pos), trees)
	var ref := "ind:%d" % id
	ConstructionSite.add_to(node, parts, "factory", func(): return sim.construction.state(ref, sim.tick_count),
		func(): pass)


func _put(merged: Dictionary, built: Array, frame: Transform3D, trees: Array) -> void:
	for k in 2:
		var mesh: ArrayMesh = built[k]
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			# Ground work and buildings stay apart even with one material:
			# only ground work is cut finer to follow the land.
			var key := [mat, k == 1]
			if not merged.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				merged[key] = [st, k == 1, mat]
			(merged[key][0] as SurfaceTool).append_from(mesh, i, frame)
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y += Terrain.ground_y(at.origin.x, at.origin.z)
		trees.append([at, t[1], t[2]])


func _mat(color: Color) -> Material:
	if not _mats.has(color):
		_mats[color] = RoadStyle.material(color)
	return _mats[color]
