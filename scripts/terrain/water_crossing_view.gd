class_name WaterCrossingView
extends Node3D
## Draws where the county roads and state highways cross water
## (WaterCrossings), out to DRAW_TO: the road carried bank to bank on its
## fill, over a culvert with concrete headwalls or on a bridge (BridgeMesh:
## box beams or girders on bents by span, barrier rail and, on desktop
## detail, approach guardrail). A crossing a town has built over, or on a
## county mile it has taken over, is left to the town's own roads.

const DRAW_TO := 3500.0
const RESCAN_M := 256.0
## Time to spend finding crossings each frame, ms.
const BUDGET_MS := 2.0
## Fill slopes: 2 horizontal to 1 vertical (INDOT side slopes on fill).
const FILL := 2.0
## A bridge's barrier sits this far out past the travelled way.
const SHY := 0.6
## Surface of each kind of road on a bridge and on fill.
const DECK := {"county": "deck", "highway": "asphalt"}
const ON_FILL := {"county": "gravel", "highway": "asphalt"}

var sim: CitySim
var _origin := Vector2.INF
var _scan_at := Vector2.INF
var _queue: Array = []
var _jobs: Array = []
var _found: Array = []
var _built := {}  # crossing key -> [MeshInstance3D...]
var _mats := {}


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	_mats = {
		"asphalt": Surfaces.asphalt(),
		"gravel": Surfaces.gravel(),
		"concrete": BridgeMesh.concrete(),
		"deck": Surfaces.concrete(Color(0.66, 0.65, 0.62)),
		"fill": Ground.grass(),
		"steel": RoadView._galvanized(),
		"marker": RoadStyle.material(Color(0.95, 0.76, 0.1)),
		"dark": RoadStyle.material(Color(0.05, 0.05, 0.05)),
		"white": Surfaces.paint(RoadStyle.MARKING_WHITE),
		"yellow": Surfaces.paint(RoadStyle.MARKING_YELLOW),
	}


func _process(_delta: float) -> void:
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		for k in _built:
			for n in _built[k]:
				n.queue_free()
		_built.clear()
		_scan_at = Vector2.INF
	var cam := get_viewport().get_camera_3d()
	var c := _origin
	if cam != null:
		c = Vector2(cam.global_position.x, cam.global_position.z) + _origin
	if _scan_at == Vector2.INF or c.distance_to(_scan_at) > RESCAN_M:
		_scan_at = c
		_jobs = WaterCrossings.jobs(c, DRAW_TO, sim.county_removed if sim != null else {})
		_found = []
	# Walk the roads for crossings a few at a time, then draw them nearest
	# first, one a frame (each is a few hundred faces).
	var start := Time.get_ticks_usec()
	var budget := LoadGate.ms(BUDGET_MS)
	while not _jobs.is_empty() and (Time.get_ticks_usec() - start) / 1000.0 < budget:
		_found.append_array(WaterCrossings.run_job(_jobs.pop_back()))
		if _jobs.is_empty():
			_settle(c)
	if not _queue.is_empty():
		var x: Dictionary = _queue.pop_back()
		_built[x.key] = _show(x)


## With every road near walked: the crossings to draw, the nearest last in
## the queue (popped first), and those out of reach let go.
func _settle(c: Vector2) -> void:
	var want := []
	var keep := {}
	for x in _found:
		if x.mid.distance_to(c) > DRAW_TO:
			continue
		keep[x.key] = true
		if not _built.has(x.key) and not _town_has(x):
			want.append(x)
	for k in _built.keys():
		if not keep.has(k):
			for n in _built[k]:
				n.queue_free()
			_built.erase(k)
	want.sort_custom(func(a, b): return a.mid.distance_to(c) > b.mid.distance_to(c))
	_queue = want


## True where the town has built on the crossing's ground.
func _town_has(x: Dictionary) -> bool:
	if sim == null:
		return false
	for p: Vector2 in [x.pts[0], x.mid, x.pts[x.pts.size() - 1]]:
		var v := Vector3(p.x - _origin.x, 0.0, p.y - _origin.y)
		if sim.vegetation.is_occupied(Vegetation.cell_of(v)):
			return true
	return false


func _show(x: Dictionary) -> Array:
	var meshes := build(x, _origin, RoadMesh.raised_curbs)
	var out := []
	for k in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k]
		mi.material_override = _mats[k]
		mi.visibility_range_end = DRAW_TO + 500.0
		add_child(mi)
		out.append(mi)
	return out


## The meshes for one crossing, by material, in view coordinates (`o`, the
## view origin). `fine`: desktop detail.
static func build(x: Dictionary, o: Vector2, fine: bool) -> Dictionary:
	var parts := {}
	for k: String in ["deck", "fill", "concrete", "steel", "marker", "dark", "white", "yellow"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[k] = st
	var road: String = x.road
	var half: float = WaterCrossings.HALF[road] + SHY
	var pts := PackedVector3Array()
	for i in x.pts.size():
		pts.append(Vector3(x.pts[i].x - o.x, x.deck[i], x.pts[i].y - o.y))
	var ground := func(vx: float, vz: float) -> float:
		return Terrain.height(vx + o.x, vz + o.y)
	var on_bridge := []
	on_bridge.resize(pts.size())
	on_bridge.fill(false)
	if x.kind == "bridge":
		for r in BridgeMesh._runs(pts, ground):
			for i in range(r[0], r[1] + 1):
				on_bridge[i] = true
		BridgeMesh.build(pts, half, parts, ground, fine)
	var cul := {}
	if x.kind == "culvert":
		cul = _culvert_size(pts, int(x.wettest), ground)
	# The road's top, and its fill down to the ground off the bridge.
	for i in pts.size() - 1:
		var a := pts[i] + Vector3(0, 0.02, 0)
		var b := pts[i + 1] + Vector3(0, 0.02, 0)
		var sa := BridgeMesh._side(pts, i)
		var sb := BridgeMesh._side(pts, i + 1)
		BridgeMesh._quad(parts.deck, a - sa * half, b - sb * half, b + sb * half, a + sa * half)
		if road == "highway":
			# Edge lines at the lanes' outer edges and the double yellow (MUTCD).
			for off: Array in [[-3.66, "white"], [3.66, "white"], [-0.1, "yellow"], [0.1, "yellow"]]:
				var c := float(off[0])
				var y := Vector3(0, 0.03, 0)
				BridgeMesh._quad(parts[off[1]], a + sa * (c - 0.06) + y, b + sb * (c - 0.06) + y,
					b + sb * (c + 0.06) + y, a + sa * (c + 0.06) + y)
		if on_bridge[i] and on_bridge[i + 1]:
			continue
		for s: float in [-1.0, 1.0]:
			var ea := pts[i] + sa * half * s
			var eb := pts[i + 1] + sb * half * s
			var ta := _toe(ea, sa * s, ground, cul, pts)
			var tb := _toe(eb, sb * s, ground, cul, pts)
			if ea.y - ta.y < 0.05 and eb.y - tb.y < 0.05:
				continue
			BridgeMesh._quad(parts.fill, ea, eb, tb, ta)
	if x.kind == "culvert":
		_culvert(pts, cul, half, parts)
	var out := {}
	for k in parts:
		var arrays := (parts[k] as SurfaceTool).commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out[DECK[road] if k == "deck" and x.kind == "bridge" else ON_FILL[road] if k == "deck" else k] = mesh
	return out


## Where the fill slope off the road's edge `e` (going out along `out`)
## meets the ground, or the top of a culvert's headwall by the creek.
static func _toe(e: Vector3, out: Vector3, ground: Callable, cul: Dictionary, pts: PackedVector3Array) -> Vector3:
	var h := maxf(e.y - float(ground.call(e.x, e.z)), 0.0)
	if not cul.is_empty() and absf((e - pts[cul.at]).dot(cul.along)) < cul.size * 0.5 + 1.2:
		var top: float = cul.bed + cul.wall
		var drop := maxf(e.y - top, 0.0)
		return Vector3(e.x, top, e.z) + out * FILL * drop
	var t := e + out * FILL * h
	t.y = float(ground.call(t.x, t.z)) - 0.1
	return t


## A culvert at point `i`: the creek bed under it, the opening (under 0.6 m
## of cover at least; a corrugated pipe up to 1.2 m, a concrete box past
## it) and its headwall's height.
static func _culvert_size(pts: PackedVector3Array, i: int, ground: Callable) -> Dictionary:
	var p := pts[i]
	var bed := float(ground.call(p.x, p.z))
	var size := clampf(p.y - bed - 0.6, 0.6, 2.4)
	return {"at": i, "bed": bed, "size": size, "wall": size + 0.45, "along": BridgeMesh._along(pts, i)}


## The culvert through the fill: a concrete headwall and wingwalls where it
## comes out each side and the opening's dark mouth.
static func _culvert(pts: PackedVector3Array, cul: Dictionary, half: float, parts: Dictionary) -> void:
	var p := pts[cul.at]
	var side := BridgeMesh._side(pts, cul.at)
	var along: Vector3 = cul.along
	var size: float = cul.size
	var wall_h: float = cul.wall
	var bed: float = cul.bed
	for s: float in [-1.0, 1.0]:
		# The fill slope comes down to the headwall's top.
		var out := half + FILL * maxf(p.y - bed - wall_h, 0.0)
		var c := p + side * s * (out + 0.15)
		c.y = bed
		BridgeMesh._box(parts.concrete, c + Vector3(0, wall_h * 0.5, 0), side * 0.3, along * (size + 2.4), wall_h)
		for w: float in [-1.0, 1.0]:
			# Wingwalls flaring out along the creek bank.
			var wc := c + along * w * (size * 0.5 + 1.2) + side * s * 0.9
			BridgeMesh._box(parts.concrete, wc + Vector3(0, wall_h * 0.35, 0), side * 1.8, along * 0.25, wall_h * 0.7)
		var face := c + side * s * 0.16 + Vector3(0, 0.15 + size * 0.5, 0)
		if size > 1.2:
			BridgeMesh._quad(parts.dark, face - along * size * 0.5 - Vector3(0, size * 0.5, 0),
				face + along * size * 0.5 - Vector3(0, size * 0.5, 0), face + along * size * 0.5 + Vector3(0, size * 0.5, 0),
				face - along * size * 0.5 + Vector3(0, size * 0.5, 0))
		else:
			# The pipe stands out of the headwall a little, its mouth dark.
			for k in 12:
				var a0 := TAU * k / 12.0
				var a1 := TAU * (k + 1) / 12.0
				var d0 := along * cos(a0) * size * 0.5 + Vector3(0, sin(a0) * size * 0.5, 0)
				var d1 := along * cos(a1) * size * 0.5 + Vector3(0, sin(a1) * size * 0.5, 0)
				BridgeMesh._quad(parts.steel, face + d0, face + d1, face + d1 + side * s * 0.3, face + d0 + side * s * 0.3)
				BridgeMesh._quad(parts.dark, face, face + d0 * 0.95, face + d1 * 0.95, face)
