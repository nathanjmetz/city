class_name CountryProps
extends Node3D
## The odds and ends of the open county near the camera, from the free
## asset library's photo scans (AssetLib, desktop only): fallen logs, stumps
## and dead branches on the woods floor, and fieldstone piles and glacial
## boulders along the fencerows, where Grant County farmers have dumped
## the stones their plows turned up for 150 years (the till plain is full
## of glacial erratics). Scenery only: nothing in the sim knows about them,
## each spot always gets the same thing, and none lands on land the town
## has built on, in the water, or on the railroad.
##
## The browser, and a desktop app that hasn't downloaded the art yet, have
## no scans: then nothing is drawn (the woods and fencerows are whole
## without them).

## Squares this many metres across are filled near the camera.
const SQUARE := 64.0
## How far out the props are drawn (scans are heavy; past this they are
## smaller than a few pixels anyway).
const REACH := 170.0
## Squares to fill each frame.
const PER_FRAME := 2
## Spot spacing on the woods floor, metres.
const WOODS_STEP := 6.0
## Stockpile spot spacing on a gravel pit's worked floor, metres.
const PILE_STEP := 12.0
## Spot spacing along wooded water edges for driftwood, metres.
const DRIFT_STEP := 10.0

## [asset id, metres long it is scanned at, scale range]
const LOG := ["dead_tree_trunk", 2.2, 3.0]
const BIG_LOG := ["dead_tree_trunk_02", 1.0, 1.4]
const STUMPS := ["tree_stump_01", "tree_stump_02"]
const BRANCHES := "dry_branches_medium_01"
const STONES := ["rock_moss_set_01", "rock_moss_set_02"]
const BOULDER := "boulder_01"

var sim: CitySim
var _origin := Vector2.INF
var _built := {}
var _meshes := {}
var _scan_at := Vector2.INF
var _queue: Array = []


func setup(s: CitySim) -> void:
	sim = s


static func drawn() -> bool:
	return not OS.has_feature("web") and bool(GraphicsQuality.knob("understory", false)) \
		and AssetLib.has(LOG[0])


func _process(_delta: float) -> void:
	if not drawn():
		if not _built.is_empty():
			_clear()
		return
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		_clear()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	# Only near the ground: from high up they're specks.
	if cam.global_position.y - Terrain.base(c.x + _origin.x, c.y + _origin.y) > REACH * 1.2:
		return
	if _scan_at == Vector2.INF or c.distance_to(_scan_at) > SQUARE * 0.5:
		_rescan(c)
	for k in PER_FRAME:
		if _queue.is_empty():
			break
		var b: Vector2i = _queue.pop_back()
		_built[b] = _fill(b)


func _clear() -> void:
	for b in _built:
		for n in _built[b]:
			n.queue_free()
	_built.clear()
	_queue.clear()
	_scan_at = Vector2.INF


func _rescan(c: Vector2) -> void:
	_scan_at = c
	var r := ceili(REACH / SQUARE) + 1
	var cb := Vector2i((c / SQUARE).floor())
	var want := []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var b := cb + Vector2i(dx, dz)
			if not _built.has(b) and _dist(b, c) < REACH + SQUARE:
				want.append(b)
	for b in _built.keys():
		if _dist(b, c) > REACH + SQUARE * 2.0:
			for n in _built[b]:
				n.queue_free()
			_built.erase(b)
	want.sort_custom(func(a, b): return _dist(a, c) > _dist(b, c))
	_queue = want


static func _dist(b: Vector2i, c: Vector2) -> float:
	return ((Vector2(b) + Vector2(0.5, 0.5)) * SQUARE).distance_to(c)


func _mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		if id == "stacker":
			_meshes[id] = _stacker_mesh()
		elif id.begins_with("pile_"):
			_meshes[id] = _pile_mesh(id)
		else:
			_meshes[id] = AssetLib.mesh(id)
	return _meshes[id]


## A stockpile a metre across at the foot: sorted sand or washed gravel
## heaped by the conveyor and the loader at its angle of repose (about 34
## degrees). Not a clean cone: the sides slump in lobes, the toe wanders,
## the crest is a rounded ridge, and one side is a loader's bite (a steep
## cut face where the trucks are filled). Dressed in the gravel photo, the
## damp toe darker.
static func _pile_mesh(id: String) -> Mesh:
	var seed := 3.0 if id == "pile_sand" else 7.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	var rings := 16
	var bite := _pile_bite(id)
	var pts := []
	for k in rings + 1:
		var t := float(k) / rings
		var row := []
		for i in segs:
			var ang := TAU * i / segs
			# Lobes and the bite at the toe, fading up the slope to a round crest.
			var toe := 1.0 - t
			var lobe := 1.0 + toe * (0.06 * sin(3.0 * ang + seed) + 0.035 * sin(7.0 * ang + seed * 2.3))
			var d := absf(wrapf(ang - bite, -PI, PI))
			var cut := 1.0 - 0.3 * (1.0 - smoothstep(0.25, 0.8, d)) * toe
			var rad := (1.0 - t) * lobe * cut
			# Straight repose slope (about 34 degrees), rounded over at the top.
			var h := 0.7 * (t - 0.35 * pow(t, 4.0)) + 0.015 * sin(5.0 * ang + seed) * t * toe
			row.append(Vector3(cos(ang) * rad, h, sin(ang) * rad))
		pts.append(row)
	for k in rings:
		for i in segs:
			var a0: Vector3 = pts[k][i]
			var a1: Vector3 = pts[k][(i + 1) % segs]
			var b0: Vector3 = pts[k + 1][i]
			var b1: Vector3 = pts[k + 1][(i + 1) % segs]
			for v: Vector3 in [a0, a1, b0, a1, b1, b0]:
				var damp := 1.0 - smoothstep(0.0, 0.08, v.y)
				st.set_color(Color(1.0 - 0.3 * damp, 1.0 - 0.32 * damp, 1.0 - 0.35 * damp))
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.8, 0.72, 0.6) if id == "pile_sand" else Color(0.74, 0.71, 0.66)
	mat.roughness = 0.95
	var tex := PhotoGround.DIR + "gravel_floor_02/albedo.jpg"
	if ResourceLoader.exists(tex):
		mat.albedo_texture = load(tex)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * (0.5 if id == "pile_sand" else 0.35)
		var nrm := PhotoGround.DIR + "gravel_floor_02/normal.jpg"
		if ResourceLoader.exists(nrm):
			mat.normal_enabled = true
			mat.normal_texture = load(nrm)
			mat.normal_scale = 0.6 if id == "pile_sand" else 1.0
	mesh.surface_set_material(0, mat)
	return mesh


## The angle of a pile's loader bite in its own frame (_pile_mesh).
static func _pile_bite(id: String) -> float:
	return 1.1 + (3.0 if id == "pile_sand" else 7.0) * 0.4


## How far out from a pile's middle its stacker's tail sits (metres).
const STACKER_REACH := 18.8
## The stacker's belt: 20 m long, rising at 20 degrees.
const STACKER_LEN := 20.0
const STACKER_RISE := 0.35


## A radial stacking conveyor (like the 80-100 ft portable stackers at
## every Indiana sand and gravel plant), 20 m long, from its tail hopper on
## the ground (the origin) along +x up to the head pulley over the pile:
## a box-girder frame under a black belt, a wheeled undercarriage on two
## raking legs, a tail hopper. Faded safety-yellow paint.
static func _stacker_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := Color(0.62, 0.5, 0.16)
	var steel := Color(0.22, 0.22, 0.21)
	var belt := Color(0.05, 0.05, 0.05)
	var ang := STACKER_RISE
	var d := Vector3(cos(ang), sin(ang), 0.0)
	var a := Vector3(0.0, 0.9, 0.0)
	var b := a + d * STACKER_LEN
	# The frame: two side girders and the belt between them.
	for side in [-0.5, 0.5]:
		_beam(st, a + Vector3(0, 0, side), b + Vector3(0, 0, side), 0.12, 0.45, paint)
	_beam(st, a + Vector3(0, 0.26, 0), b + Vector3(0, 0.26, 0), 0.85, 0.05, belt)
	# Cross struts under the belt, every 2 m.
	var k := 1.0
	while k < STACKER_LEN:
		_beam(st, a + d * k + Vector3(0, -0.15, -0.5), a + d * k + Vector3(0, -0.15, 0.5), 0.08, 0.08, paint)
		k += 2.0
	# Undercarriage at 60% along: two raking legs to an axle and wheels.
	var m := a + d * (STACKER_LEN * 0.6)
	var axle := Vector3(m.x - 1.2, 0.55, 0.0)
	for side in [-1.0, 1.0]:
		_beam(st, m + Vector3(0, -0.2, side * 0.5), axle + Vector3(0, 0, side * 1.1), 0.18, 0.18, paint)
		_beam(st, axle + Vector3(0, 0, side * 1.1), axle + Vector3(0, 0, side * 1.45), 1.05, 1.05, steel)
		# A brace back to the tail.
		_beam(st, axle + Vector3(0, 0.1, side * 1.0), a + d * 4.0 + Vector3(0, -0.2, side * 0.5), 0.1, 0.1, paint)
	_beam(st, axle + Vector3(0, 0, -1.2), axle + Vector3(0, 0, 1.2), 0.12, 0.12, steel)
	# Tail hopper and its feet; head pulley housing.
	_beam(st, Vector3(-0.6, 1.2, 0), Vector3(1.0, 1.7, 0), 1.6, 0.9, paint)
	_beam(st, Vector3(-0.3, 0.0, 0), Vector3(-0.3, 1.0, 0), 1.0, 0.3, paint)
	_beam(st, b - d * 0.4, b + d * 0.3, 1.1, 0.6, paint)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	mat.metallic = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


## A box from p to q, `w` wide and `h` deep across it, with flat faces.
static func _beam(st: SurfaceTool, p: Vector3, q: Vector3, w: float, h: float, c: Color) -> void:
	var d := (q - p).normalized()
	var ref := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
	var sv := d.cross(ref).normalized() * w * 0.5
	var uv := sv.cross(d).normalized() * h * 0.5
	var corners := []
	for e in [p, q]:
		for cs in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			corners.append(e + sv * cs[0] + uv * cs[1])
	var faces := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	st.set_color(c)
	for f in faces:
		var v0: Vector3 = corners[f[0]]
		var v1: Vector3 = corners[f[1]]
		var v2: Vector3 = corners[f[2]]
		var v3: Vector3 = corners[f[3]]
		var n := (v1 - v0).cross(v2 - v0).normalized()
		# Face outward from the box's middle.
		if n.dot((v0 + v2) * 0.5 - (p + q) * 0.5) < 0.0:
			n = -n
		st.set_normal(n)
		for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
			st.add_vertex(v)


## True where a prop may lie: open or wooded land, not water, the railroad
## or anything the town has built.
func _free(p: Vector3) -> bool:
	var r := Vector2(p.x + _origin.x, p.z + _origin.y)
	if Terrain.water(r.x, r.y) > 0.03 or CountyRail.clears(r.x, r.y):
		return false
	if Terrain.mow_weight(p.x, p.z) > 0.05 or Terrain.flat_weight(p.x, p.z) > 0.05:
		return false
	return sim == null or not sim.vegetation.is_occupied(Vegetation.cell_of(p))


func _at(p: Vector3, yaw: float, s: float, sink: float) -> Transform3D:
	var y := Terrain.base(p.x + _origin.x, p.z + _origin.y) - sink * s
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, y, p.z))


## Every prop in one square, as one MultiMesh for each scan.
func _fill(b: Vector2i) -> Array:
	var by_id := {}
	var o := _origin
	var lo := Vector2(b) * SQUARE
	# The woods floor: logs fallen every which way, stumps, dead branches.
	var n := int(SQUARE / WOODS_STEP)
	for j in n:
		for i in n:
			var g := Vector2i(floori((lo.x + o.x) / WOODS_STEP) + i, floori((lo.y + o.y) / WOODS_STEP) + j)
			var h := CropCalendar.h01(g.x, g.y, 91)
			var p := Vector3((g.x + 0.2 + 0.6 * CropCalendar.h01(g.x, g.y, 92)) * WOODS_STEP - o.x, 0.0,
				(g.y + 0.2 + 0.6 * CropCalendar.h01(g.x, g.y, 93)) * WOODS_STEP - o.y)
			var t := Terrain.trees(p.x + o.x, p.z + o.y)
			if t < 0.55 or h > 0.32:
				continue
			if not _free(p):
				continue
			var yaw := CropCalendar.h01(g.x, g.y, 94) * TAU
			var k := CropCalendar.h01(g.x, g.y, 95)
			var sz := CropCalendar.h01(g.x, g.y, 96)
			if h < 0.08:
				# Big old trees down (oak and ash, the ash all killed by the
				# emerald ash borer since 2010), most a third sunk in the leaves.
				if k < 0.75:
					_add(by_id, LOG[0], _at(p, yaw, lerpf(LOG[1], LOG[2], sz), 0.3 * 0.29))
				else:
					_add(by_id, BIG_LOG[0], _at(p, yaw, lerpf(BIG_LOG[1], BIG_LOG[2], sz), 0.25))
			elif h < 0.13:
				_add(by_id, STUMPS[int(k * 2.0) % 2], _at(p, yaw, lerpf(0.7, 1.05, sz), 0.05))
			else:
				_add(by_id, BRANCHES, _at(p, yaw, lerpf(1.4, 2.4, sz), 0.04))
	# A working gravel pit's floor: conical stockpiles of washed gravel and
	# sand by the plant (Grant County pits sell pea gravel, #53 stone and
	# fill sand off piles 5-10 m high), a few to a pit.
	var np := int(SQUARE / PILE_STEP) + 1
	var piles: Array[Vector3] = []
	for j in np:
		for i in np:
			var g := Vector2i(floori((lo.x + o.x) / PILE_STEP) + i, floori((lo.y + o.y) / PILE_STEP) + j)
			var r := Vector2((g.x + 0.3 + 0.4 * CropCalendar.h01(g.x, g.y, 61)) * PILE_STEP,
				(g.y + 0.3 + 0.4 * CropCalendar.h01(g.x, g.y, 62)) * PILE_STEP)
			var p := Vector3(r.x - o.x, 0.0, r.y - o.y)
			if p.x < lo.x or p.x >= lo.x + SQUARE or p.z < lo.y or p.z >= lo.y + SQUARE:
				continue
			if CropCalendar.h01(g.x, g.y, 63) > 0.4:
				continue
			if Terrain.bare(r.x, r.y) < 0.55:
				continue
			var near := false
			for q in piles:
				if q.distance_to(Vector3(r.x - o.x, 0.0, r.y - o.y)) < 24.0:
					near = true
			if near:
				continue
			if Terrain.water(r.x, r.y) > 0.03 or CountyRail.clears(r.x, r.y):
				continue
			if sim != null and sim.vegetation.is_occupied(Vegetation.cell_of(p)):
				continue
			var rad := lerpf(6.0, 11.0, CropCalendar.h01(g.x, g.y, 64))
			# Beside the haul road, not on it: the loader works off its edge.
			if TerrainView.on_haul(r.x, r.y, rad * 0.75):
				continue
			var xf := Transform3D(Basis(Vector3.UP, CropCalendar.h01(g.x, g.y, 65) * TAU).scaled(Vector3(rad, rad, rad)),
				Vector3(p.x, Terrain.base(r.x, r.y) - 0.2, p.z))
			piles.append(p)
			var pid := "pile_sand" if CropCalendar.h01(g.x, g.y, 66) < 0.4 else "pile_gravel"
			_add(by_id, pid, xf)
			# Most piles are built by a radial stacker: a conveyor on a
			# wheeled undercarriage reaching up over the crest, its tail
			# hopper on the ground, on the side away from the loader's bite.
			if CropCalendar.h01(g.x, g.y, 67) < 0.75:
				for turn in [0.0, 0.9, -0.9]:
					var phi: float = _pile_bite(pid) + PI + turn - CropCalendar.h01(g.x, g.y, 65) * TAU
					var out := Vector2(cos(phi), sin(phi))
					var tail := r + out * STACKER_REACH
					var mid := r + out * STACKER_REACH * 0.4
					if Terrain.water(tail.x, tail.y) > 0.03 or Terrain.water(mid.x, mid.y) > 0.03 \
							or CountyRail.clears(tail.x, tail.y) or Terrain.trees(tail.x, tail.y) > 0.4:
						continue
					var yaw := atan2(out.y, -out.x)
					_add(by_id, "stacker", Transform3D(Basis(Vector3.UP, yaw),
						Vector3(tail.x - o.x, Terrain.base(tail.x, tail.y) - 0.1, tail.y - o.y)))
					break
	# Driftwood: trees the river undercut, lying from the bank into the
	# water or stranded at the edge (the Mississinewa and its creeks are
	# full of these strainers and small log jams below wooded banks).
	var nd := int(SQUARE / DRIFT_STEP)
	for j in nd:
		for i in nd:
			var g := Vector2i(floori((lo.x + o.x) / DRIFT_STEP) + i, floori((lo.y + o.y) / DRIFT_STEP) + j)
			var h := CropCalendar.h01(g.x, g.y, 81)
			if h > 0.4:
				continue
			var r := Vector2((g.x + 0.5) * DRIFT_STEP, (g.y + 0.5) * DRIFT_STEP)
			var wv := Terrain.water(r.x, r.y)
			if wv < 0.12 or wv > 0.55 or CountyRail.clears(r.x, r.y):
				continue
			if maxf(Terrain.trees(r.x + 12.0, r.y), maxf(Terrain.trees(r.x - 12.0, r.y),
					maxf(Terrain.trees(r.x, r.y + 12.0), Terrain.trees(r.x, r.y - 12.0)))) < 0.5:
				continue
			var p := Vector3(r.x - o.x, 0.0, r.y - o.y)
			if sim != null and sim.vegetation.is_occupied(Vegetation.cell_of(p)):
				continue
			var big := h < 0.08
			var kind: Array = BIG_LOG if big else LOG
			var sc := lerpf(kind[1], kind[2], CropCalendar.h01(g.x, g.y, 82))
			# Waterlogged: half under the surface, or lying on the bank.
			var wy := minf(Terrain.base(r.x, r.y), Terrain.water_level(r.x, r.y)) - (0.45 if big else 0.6 * 0.29) * sc
			var xf := Transform3D(Basis(Vector3.UP, CropCalendar.h01(g.x, g.y, 83) * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, wy, p.z))
			_add(by_id, kind[0], xf)
	# Fencerows on the survey's eighth-mile lines (Vegetation.FENCE_GRID): a
	# fieldstone pile now and then, a boulder at a corner.
	var grid := Vegetation.FENCE_GRID
	for axis in 2:
		var a0: float = lo.x if axis == 0 else lo.y
		var b0: float = lo.y if axis == 0 else lo.x
		for k in range(floori(a0 / grid), floori((a0 + SQUARE) / grid) + 1):
			var across := k * grid
			if across < a0 or across >= a0 + SQUARE:
				continue
			# One spot every 50 m along the line.
			for m in range(floori(b0 / 50.0), floori((b0 + SQUARE) / 50.0) + 1):
				var along := m * 50.0 + 25.0
				if along < b0 or along >= b0 + SQUARE:
					continue
				var id := Vector2i(k * 2 + axis, m)
				var h := CropCalendar.h01(id.x, id.y, 97)
				if h > 0.08:
					continue
				var off := (CropCalendar.h01(id.x, id.y, 98) - 0.5) * 3.0
				var p := Vector3(across + off, 0.0, along) if axis == 0 else Vector3(along, 0.0, across + off)
				if Terrain.trees(p.x + o.x, p.z + o.y) > 0.6 or not _free(p):
					continue
				var yaw := CropCalendar.h01(id.x, id.y, 99) * TAU
				if h < 0.06:
					_add(by_id, STONES[id.y % 2], _at(p, yaw, lerpf(0.45, 0.75, h / 0.06), 0.1))
				else:
					_add(by_id, BOULDER, _at(p, yaw, lerpf(0.8, 1.2, (h - 0.06) / 0.02), 0.2))
	var out := []
	for id in by_id:
		var mesh := _mesh(id)
		if mesh == null:
			continue
		var list: Array = by_id[id]
		# The node stands at the square's middle, on the ground: its
		# visibility range is measured from there, not from the instances.
		var mid := Vector3(lo.x + SQUARE * 0.5, 0.0, lo.y + SQUARE * 0.5)
		mid.y = Terrain.base(mid.x + o.x, mid.z + o.y)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var xf: Transform3D = list[i]
			xf.origin -= mid
			mm.set_instance_transform(i, xf)
		var mi := MultiMeshInstance3D.new()
		mi.name = id
		mi.multimesh = mm
		mi.position = mid
		mi.visibility_range_end = REACH
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		out.append(mi)
	return out


static func _add(by_id: Dictionary, id: String, xf: Transform3D) -> void:
	if not by_id.has(id):
		by_id[id] = []
	by_id[id].append(xf)
