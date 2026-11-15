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
		_meshes[id] = AssetLib.mesh(id)
	return _meshes[id]


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
