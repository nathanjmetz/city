class_name SubdivisionWorksView
extends Node3D
## A subdivision's site work on the ground (Subdivisions, Construction's
## "subdivision" profile), the way a real phase looks before any house goes
## up: the whole phase stripped to bare dirt behind a silt fence with the
## topsoil heaped at the back, then the streets graded, trenches dug down
## the street lines with sewer pipe, manholes and an excavator, then the
## water main and hydrants, and once the streets are paved the surveyor's
## stakes along the new lots while the bare ground is seeded.
##
## One mesh per subdivision, redrawn only when a phase moves to its next
## stage (checked twice a second), so it costs nothing per frame.

var sim: CitySim
var _nodes := {}  # subdivision id -> MeshInstance3D
var _stamps := {}  # subdivision id -> what it was drawn from
var _wait := 0.0

const POLL := 0.5
const DIRT := ConstructionSite.DIRT
## Straw mulch over new grass seed, then the grass coming through.
const SEEDED := Color("#8e9a5a")
const GRADED := Color("#87735a")
const TRENCH := Color("#4a3c2e")
const SEWER_PIPE := Color("#3f7a46")  # green PVC sanitary sewer (SDR-35)
const STORM_PIPE := Color("#a8a49b")  # reinforced concrete pipe
const WATER_PIPE := Color("#2e3236")  # ductile iron
const MACHINE := Color("#e0b21c")
const STAKE := Color("#e83e8c")  # survey flagging
const LIFT := 0.09


func setup(s: CitySim) -> void:
	sim = s
	sim.subdivisions.changed.connect(_sync)
	_sync()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = POLL
	_sync()


func _sync() -> void:
	var subs: Dictionary = sim.subdivisions.active
	for id in _nodes.keys():
		if not subs.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
			_stamps.erase(id)
	for id in subs:
		var a: Dictionary = subs[id]
		var stage := Subdivisions.works_stage(a, sim.tick_count)
		var stamp := "%d|%d|%d" % [int(a.phase), int(a.works.k) if a.has("works") else -1, stage]
		if _stamps.get(id, "") == stamp:
			continue
		_stamps[id] = stamp
		if not _nodes.has(id):
			var mi := MeshInstance3D.new()
			mi.material_override = _material()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_nodes[id] = mi
		_nodes[id].mesh = _draw(a, stage)


static var _mat: StandardMaterial3D


## Plain vertex colours, no shine: bare dirt and straw.
static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 1.0
	return _mat


func _draw(a: Dictionary, stage: int) -> Mesh:
	var site: Dictionary = a.site
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var any := false
	if a.has("works") and stage >= 0 and stage < Construction.STAGES.size():
		_works(st, site, int(a.works.k), stage)
		any = true
	if not any:
		return null
	return Terrain.drape_local(st.commit(), Transform3D.IDENTITY)


## One phase's site work at `stage` (Construction.STAGES index).
func _works(st: SurfaceTool, site: Dictionary, k: int, stage: int) -> void:
	var r: Array = Subdivisions.works_area(site, k).rect
	var paved := stage >= Subdivisions.STREETS_STAGE
	var seeded := stage >= Subdivisions.STAKE_STAGE
	var spine := Balance.SUBDIV_WIDTH * 0.5 - Balance.SUBDIV_SPINE_IN
	var row := Subdivisions.row_v(k)
	var cw := RoadStyle.right_of_way_half(Subdivisions.TYPE)
	var tint := func(u: float, v: float) -> Color:
		if seeded:
			return SEEDED
		var h := fposmod(sin(u * 0.37 + v * 0.71) * 43758.5453, 1.0)
		var base := DIRT.lightened(h * 0.03) if h > 0.5 else DIRT.darkened((0.5 - h) * 0.04)
		# From rough grading on, the street beds are cut and compacted.
		if stage >= 1 and _in_street(u, v, spine, row, cw, site, k):
			return GRADED
		return base
	_ground(st, site, r, tint, k, paved)
	var ang := atan2(float(site.t[1]), float(site.t[0]))
	var at := func(u: float, v: float, y: float) -> Vector3:
		return Subdivisions.local(site, u, v) + Vector3(0.0, y, 0.0)
	var box := func(size: Vector3, u: float, v: float, y: float, col: Color, turn: float) -> void:
		ConstructionSite._prop(st, size, at.call(u, v, y), col, Basis(Vector3.UP, -ang + turn))
	if stage <= 2:
		# Silt fence round the sides and back (the road side is the
		# construction entrance), and the stripped topsoil heaped at the back.
		var c := [[r[0] + 1.0, r[2] + 6.0], [r[0] + 1.0, r[3] - 1.0], [r[1] - 1.0, r[3] - 1.0], [r[1] - 1.0, r[2] + 6.0]]
		for i in 3:
			_fence(st, at.call(c[i][0], c[i][1], 0.0), at.call(c[i + 1][0], c[i + 1][1], 0.0))
		box.call(Vector3(14.0, 2.2, 8.0), spine * 0.5, r[3] - 9.0, 1.1, DIRT.darkened(0.2), 0.0)
		box.call(Vector3(9.0, 1.2, 5.0), spine * 0.5, r[3] - 9.0, 2.6, DIRT.darkened(0.15), 0.0)
	if stage <= 1:
		# A dozer at work.
		box.call(Vector3(3.4, 1.6, 4.8), -spine * 0.4, (r[2] + r[3]) * 0.5, 0.9, MACHINE, 0.0)
		box.call(Vector3(3.8, 1.2, 0.3), -spine * 0.4, (r[2] + r[3]) * 0.5 + 2.7, 0.6, Color("#5b5b55"), 0.0)
	elif stage <= 3:
		# Trenches down the street lines: the sewer down the middle first,
		# then the water main off to one side, with the pipe strung out
		# beside it and an excavator digging.
		var off := 0.0 if stage == 2 else 3.5
		var v0: float = r[2] if k == 0 else float(r[2]) - 10.0
		for s in [-1.0, 1.0]:
			_strip(st, at.call(s * spine + off, v0, 0.0), at.call(s * spine + off, row, 0.0), 1.4, TRENCH, 0.03)
		_strip(st, at.call(-spine, row + off, 0.0), at.call(spine, row + off, 0.0), 1.4, TRENCH, 0.03)
		var pipe: Color = SEWER_PIPE if stage == 2 else WATER_PIPE
		var vv: float = float(r[2]) + 12.0
		while vv < row - 6.0:
			box.call(Vector3(0.5, 0.5, 6.0), -spine + off - 2.4, vv, 0.25, pipe, 0.0)
			vv += 7.0
		if stage == 2:
			# Storm pipe and precast manhole barrels waiting at the corner.
			for i in 3:
				box.call(Vector3(1.0, 1.0, 2.4), spine - 8.0, row - 12.0 - i * 3.0, 0.5, STORM_PIPE, PI * 0.5)
			box.call(Vector3(1.5, 1.2, 1.5), spine - 12.0, row - 12.0, 0.6, STORM_PIPE, 0.0)
		else:
			# Hydrants set on the new main, a few hundred feet apart.
			for u in [-spine * 0.5, spine * 0.5]:
				box.call(Vector3(0.35, 0.9, 0.35), u, row + cw - 1.0, 0.45, Color("#c9302c"), 0.0)
		box.call(Vector3(3.0, 2.8, 4.6), -spine + off + 4.5, (r[2] + row) * 0.5, 1.4, MACHINE, 0.0)
		box.call(Vector3(0.6, 0.6, 6.0), -spine + off + 4.5, (r[2] + row) * 0.5 + 4.2, 3.0, MACHINE, 0.0)
	elif not seeded:
		# Stone for the street base, heaped by the entrance.
		box.call(Vector3(5.0, 1.4, 4.0), -spine + cw + 4.0, r[2] + 8.0, 0.7, Color("#8f8a80"), 0.0)
	else:
		# The surveyor's stakes at the lot corners along the new street.
		var back := cw + 0.6
		var u := -spine + cw + 2.0
		while u <= spine - cw - 2.0:
			for s in [-1.0, 1.0]:
				box.call(Vector3(0.05, 0.8, 0.05), u, row + s * back, 0.4, STAKE, 0.0)
			u += Balance.SUBDIV_LOT_W


## Bare or seeded ground over rect [u0, u1, v0, v1] of a site, in 6 m
## squares, leaving out the paved streets (`paved`, through phase `k`).
func _ground(st: SurfaceTool, site: Dictionary, r: Array, tint: Callable, k: int, paved: bool) -> void:
	var spine := Balance.SUBDIV_WIDTH * 0.5 - Balance.SUBDIV_SPINE_IN
	var cw := RoadStyle.right_of_way_half(Subdivisions.TYPE)
	var step := 6.0
	var nu := ceili((float(r[1]) - float(r[0])) / step)
	var nv := ceili((float(r[3]) - float(r[2])) / step)
	for i in nu:
		for j in nv:
			var u0 := float(r[0]) + (float(r[1]) - float(r[0])) * i / nu
			var u1 := float(r[0]) + (float(r[1]) - float(r[0])) * (i + 1) / nu
			var v0 := float(r[2]) + (float(r[3]) - float(r[2])) * j / nv
			var v1 := float(r[2]) + (float(r[3]) - float(r[2])) * (j + 1) / nv
			var cu := (u0 + u1) * 0.5
			var cv := (v0 + v1) * 0.5
			if paved and _street_through(cu, cv, spine, cw + step * 0.5, site, k):
				continue
			var col: Color = tint.call(cu, cv)
			var c := [Subdivisions.local(site, u0, v0), Subdivisions.local(site, u1, v0),
				Subdivisions.local(site, u1, v1), Subdivisions.local(site, u0, v1)]
			st.set_color(col)
			_tri(st, c[0], c[1], c[2])
			_tri(st, c[0], c[2], c[3])


## True where (u, v) is on a street bed of phase k (its spines and cross street).
static func _in_street(u: float, v: float, spine: float, row: float, cw: float, site: Dictionary, k: int) -> bool:
	if absf(v - row) < cw and absf(u) <= spine + cw:
		return true
	var top := row + (Balance.SUBDIV_STUB if k < int(site.phases) - 1 else 0.0)
	return absf(absf(u) - spine) < cw and v <= top + cw


## True where (u, v) is on any street of phases 0 to k (the seeded ground
## and paved phases leave these out: the road draws itself).
static func _street_through(u: float, v: float, spine: float, cw: float, site: Dictionary, k: int) -> bool:
	for j in k + 1:
		if _in_street(u, v, spine, Subdivisions.row_v(j), cw, site, j):
			return true
	return false


## A flat strip from a to b, w wide, lifted y above the pad.
static func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color, y: float) -> void:
	var d := (b - a)
	if d.length() < 0.5:
		return
	var side := Vector3(-d.z, 0.0, d.x).normalized() * w * 0.5
	var lift := Vector3(0.0, y, 0.0)
	st.set_color(col)
	_tri(st, a - side + lift, b - side + lift, b + side + lift)
	_tri(st, a - side + lift, b + side + lift, a + side + lift)


## A ground triangle lifted LIFT, wound to face up whichever way the site
## is laid out from its road.
static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	var up := Vector3(0.0, LIFT, 0.0)
	var pts := [p0, p1, p2] if (p1 - p0).cross(p2 - p0).y < 0.0 else [p0, p2, p1]
	for p in pts:
		st.add_vertex(p + up)


static func _fence(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 1.0:
		return
	var dir := d / len
	var basis := Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, dir)
	ConstructionSite._prop(st, Vector3(0.02, 0.6, len), (a + b) * 0.5 + Vector3(0, 0.3, 0), Color("#1b1b1c"), basis)
	var k := 0.0
	while k <= len:
		ConstructionSite._prop(st, Vector3(0.05, 0.9, 0.05), a + dir * k + Vector3(0, 0.45, 0), Color("#8a6b45"))
		k += 4.8
