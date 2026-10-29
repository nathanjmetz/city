class_name RailView
extends Node3D
## Draws the railroad: each depot's yard (office, and what its tree has
## built: engine house, station canopy, car shop, elevator loading shed),
## track on crushed-rock ballast with ties and rails, embankments where it
## runs above the ground and steel girder bridges over water, survey stakes
## where crews are still laying track, crossing gates that drop with
## flashing lights, and the trains themselves.
##
## Track follows the graded base level (the same level the planner prices
## cut and fill against), climbing to clear water on a ramp no steeper than
## the line's ruling grade. The ground under it is graded flat like a road's.

const BALLAST := Color("#6a665f")
const BALLAST_DARK := Color("#55514b")
const RAIL := Color("#5a4d44")
const RAIL_TOP := Color("#b8b6b2")
const TIE := Color("#4a3f35")
## Fill slopes are seeded and grassed over, as on real embankments.
const EARTH := Color("#56663a")
const WEEDS := Color("#5f6e3c")
## Highest embankment drawn (m).
const MAX_FILL := 16.0
## The right of way graded level each side of the centreline (m): wider than
## the terrain's 8 m grid, so the drawn ground meets the ballast's toe.
const ROW_GRADE := 9.0
const GIRDER := Color("#3d4347")
const CONCRETE := Color("#a9a69d")
## Heights above the track's base level (m): ballast top, tie top, rail top.
const BALLAST_Y := 0.3
const TIE_Y := 0.48
const RAIL_Y := 0.65
const TIE_EVERY := 0.6
## Rail top above the road at a crossing panel (m), and the approach over
## which the bed eases down to it each side.
const CROSSING_RAIL := 0.09
const CROSSING_RAMP := 30.0
## Above the water at a bridge (m).
const FAR := 3200.0
## Whistle posts stand a quarter mile before each crossing (m).
const WHISTLE_POST := 402.0

var sim: CitySim
var terrain: TerrainView
## The Rail view (Views, top left): every line coloured by what it's doing,
## with what it carries, and the trains with their loads.
var show_lines := false:
	set(v):
		show_lines = v
		_overlay_sig = ""

var _track := MeshInstance3D.new()
var _ties := MultiMeshInstance3D.new()
var _yard := MeshInstance3D.new()
var _stakes := MeshInstance3D.new()
var _gates := MeshInstance3D.new()
var _lights := MeshInstance3D.new()
var _cars := {}     # stock kind -> MultiMeshInstance3D
var _overlay := MeshInstance3D.new()
var _labels := []   # Label3D pool for the Rail view
var _overlay_sig := ""
var _sig := ""
var _gate_sig := ""
var _wait := 0.0
var _h := {}        # 4 m cell -> height of the track's base level there
var _grades := {}   # chunk key -> [pts, inner, outer] for the terrain


func setup(s: CitySim, t: TerrainView = null) -> void:
	sim = s
	terrain = t
	var sounds := RailSounds.new()
	sounds.setup(s, height_at)
	add_child(sounds)
	if terrain != null:
		terrain.extra_grades = func() -> Dictionary: return _grades


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in [_track, _yard, _stakes, _gates]:
		mi.material_override = mat
		add_child(mi)
	var tie_mesh := BoxMesh.new()
	tie_mesh.size = Vector3(2.6, 0.18, 0.23)
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = TIE
	tie_mat.roughness = 1.0
	tie_mesh.material = tie_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tie_mesh
	_ties.multimesh = mm
	_ties.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ties)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#ff3020")
	glow.emission_enabled = true
	glow.emission = Color("#ff2010")
	glow.emission_energy_multiplier = 3.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lights.material_override = glow
	_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lights)
	var line_mat := StandardMaterial3D.new()
	line_mat.vertex_color_use_as_albedo = true
	line_mat.vertex_color_is_srgb = true
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.no_depth_test = true
	line_mat.disable_fog = true
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_overlay.material_override = line_mat
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.visible = false
	add_child(_overlay)
	var car_mat := StandardMaterial3D.new()
	car_mat.vertex_color_use_as_albedo = true
	car_mat.vertex_color_is_srgb = true
	car_mat.roughness = 0.55
	car_mat.metallic = 0.1
	car_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for kind in Rail.STOCK:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		# White instance colours: the browser's renderer multiplies vertex
		# COLOR by the instance colour even without use_colors (black).
		m.use_colors = true
		m.mesh = RailModels.build(kind)
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = m
		inst.material_override = car_mat
		add_child(inst)
		_cars[kind] = inst


func _process(delta: float) -> void:
	if sim == null:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = 0.25
		var sig := _signature()
		if sig != _sig:
			_sig = sig
			_draw_track()
			_draw_yards()
			_draw_stakes()
			if terrain != null:
				terrain.regrade()
	_draw_gates()
	_draw_trains()
	_draw_overlay()


## Changes whenever something drawn would: track laid, lines, the tree.
func _signature() -> String:
	var parts := [sim.rail.depots.size(), sim.rail.pieces.size(), sim.rail.crossings.size(), sim.rail.underpasses.size()]
	for pid in sim.rail.pieces:
		parts.append(floori(float(sim.rail.pieces[pid].built) / 20.0))
	for lid in sim.rail.lines:
		parts.append(sim.rail.lines[lid].state)
	for id in sim.rail.depots:
		parts.append(sim.rail.depots[id].get("built", []).size())
	parts.append(sim.pollution.quiet.size())
	return str(parts)


# --- Track -------------------------------------------------------------------

func _wet(p: Vector3) -> bool:
	return Terrain.is_water(p.x + Terrain.shift.x + Terrain.view_origin.x, p.z + Terrain.shift.y + Terrain.view_origin.y)


## The track's base level along a line of points (Rail.profile, as the sim
## sees it).
func _profile(pts: Array, grade: float) -> PackedFloat32Array:
	return Rail.profile(pts, grade, Terrain.shift + Terrain.view_origin)


## The roads this piece crosses at grade and passes over: [s, half width,
## underpass] each.
func _road_marks(pid: int) -> Array:
	var marks := []
	for c in sim.rail.crossings:
		if int(c.piece) == pid and sim.network.segments.has(c.seg):
			marks.append([float(c.s), RoadStyle.half_width(sim.network.segments[c.seg].type) + 2.0, false])
	for u in sim.rail.underpasses:
		if int(u.piece) == pid and sim.network.segments.has(u.seg):
			marks.append([float(u.s), RoadStyle.half_width(sim.network.segments[u.seg].type) + 1.5, true])
	return marks


## The points with extra ones at each road's edges and middle, so the mesh
## bends and breaks exactly there; and the distance along of each point.
func _split_at(pts: Array, marks: Array) -> Array:
	var along := [0.0]
	for i in range(1, pts.size()):
		along.append(float(along[i - 1]) + (pts[i] as Vector3).distance_to(pts[i - 1]))
	var want := []
	for m in marks:
		for o: float in [-m[1], 0.0, m[1]]:
			var at: float = m[0] + o
			if at > 0.0 and at < float(along[-1]):
				want.append(at)
	var out := []
	var out_s := []
	for i in pts.size():
		if i > 0:
			for at: float in want:
				if at > float(along[i - 1]) + 0.5 and at < float(along[i]) - 0.5:
					var f := (at - float(along[i - 1])) / (float(along[i]) - float(along[i - 1]))
					out.append([at, (pts[i - 1] as Vector3).lerp(pts[i], f)])
		out.append([float(along[i]), pts[i]])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return [out.map(func(e): return e[1]), out.map(func(e): return e[0])]


## Where the track crosses a road at grade the rails sit flush with the
## pavement in a crossing panel, the bed easing down over the approach (a
## vertical curve, AREMA ch. 5 / FHWA crossing handbook) at no more than 3%,
## or over 30 m where it's already low. Lowers `h` in place.
func _sink_to_crossings(pts: Array, along: Array, h: PackedFloat32Array, marks: Array) -> void:
	var drops := []
	for m in marks:
		if m[2]:
			continue
		var k := along.bsearch(float(m[0]))
		k = clampi(k, 0, pts.size() - 1)
		var p: Vector3 = pts[k]
		var need: float = h[k] + RAIL_Y - Terrain.base_y(p.x, p.z) - CROSSING_RAIL
		if need > 0.0:
			drops.append([m[0], m[1], need, maxf(CROSSING_RAMP, need / 0.03)])
	if drops.is_empty():
		return
	for i in pts.size():
		var most := 0.0
		for d in drops:
			var out := absf(float(along[i]) - float(d[0])) - float(d[1])
			most = maxf(most, float(d[2]) * (1.0 - clampf(out / float(d[3]), 0.0, 1.0)))
		h[i] -= most


func _draw_track() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ties := []
	_h.clear()
	_grades.clear()
	var any := false
	var pids := sim.rail.pieces.keys()
	pids.sort()
	for pid in pids:
		var pc: Dictionary = sim.rail.pieces[pid]
		var pts := _built_pts(pc)
		if pts.size() < 2:
			continue
		any = true
		var marks := _road_marks(pid)
		var split := _split_at(pts, marks)
		pts = split[0]
		var along: Array = split[1]
		var h := _profile(pts, Rail.grade_of(pc.kind))
		_sink_to_crossings(pts, along, h, marks)
		for i in pts.size():
			var p: Vector3 = pts[i]
			_h[Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))] = h[i]
		_grade_chunks(pid, pts)
		var left := []
		for i in pts.size():
			var a: Vector3 = pts[maxi(i - 1, 0)]
			var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
			var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			left.append(Vector3(-t.z, 0.0, t.x))
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var c0 := Vector3(p0.x, h[i], p0.z)
			var c1 := Vector3(p1.x, h[i + 1], p1.z)
			var n0: Vector3 = left[i]
			var n1: Vector3 = left[i + 1]
			var under := _over_road(marks, (float(along[i]) + float(along[i + 1])) * 0.5)
			if _wet((p0 + p1) * 0.5):
				_bridge_span(st, c0, c1, n0, n1, i)
			elif under:
				# A deck girder span over the road, on concrete abutments
				# holding back the fill each side.
				_bridge_span(st, c0, c1, n0, n1, 1)
				if i == 0 or not _over_road(marks, (float(along[i - 1]) + float(along[i])) * 0.5):
					_abutment(st, c0, n0)
				if i + 2 >= pts.size() or not _over_road(marks, (float(along[i + 1]) + float(along[i + 2])) * 0.5):
					_abutment(st, c1, n1)
			else:
				_ballast(st, c0, c1, n0, n1)
			for side: float in [-1.0, 1.0]:
				_rail(st, c0 + n0 * side * RailModels.GAUGE * 0.5, c1 + n1 * side * RailModels.GAUGE * 0.5, n0, n1)
			# Ties every 60 cm.
			var seg := c1 - c0
			var len := Vector2(seg.x, seg.z).length()
			var k := 0.0
			while k < len:
				var f := k / len
				var at := c0.lerp(c1, f) + Vector3(0, TIE_Y - 0.09, 0)
				ties.append(Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), at))
				k += TIE_EVERY
	for c in sim.rail.crossings:
		_crossing_pad(st, c)
		_whistle_posts(st, c)
	_track.visible = any
	if any:
		# Shared corners get one smooth normal, so the ballast doesn't shade
		# in stripes from quad to quad.
		st.index()
		st.generate_normals()
		_track.mesh = st.commit()
	var mm := _ties.multimesh
	mm.instance_count = ties.size()
	for i in ties.size():
		mm.set_instance_transform(i, ties[i])
	_ties.visible = not ties.is_empty()


## The points of a piece that crews have laid so far.
func _built_pts(pc: Dictionary) -> Array:
	var pts: Array = pc.pts
	var built: float = pc.built
	if built < 0.0:
		return pts  # laid in full (the yard)
	var out := []
	var run := 0.0
	for i in pts.size():
		if i > 0:
			var step: float = (pts[i] as Vector3).distance_to(pts[i - 1])
			if run + step > built + 0.01:
				var f := (built - run) / maxf(step, 0.001)
				if f > 0.05:
					out.append((pts[i - 1] as Vector3).lerp(pts[i], f))
				break
			run += step
		out.append(pts[i])
	return out


## The ground under the track, graded flat in ~100 m chunks (except over water).
func _grade_chunks(pid: int, pts: Array) -> void:
	var k := 0
	var chunk := 0
	while k < pts.size() - 1:
		var line := PackedVector3Array()
		var dry := true
		for j in range(k, mini(k + 11, pts.size())):
			line.append(pts[j])
			dry = dry and not _wet(pts[j])
		if dry and line.size() >= 2:
			_grades["rail:%d:%d" % [pid, chunk]] = [line, ROW_GRADE, ROW_GRADE + 6.0]
		k += 10
		chunk += 1


## Crushed rock in a trapezoid, and an earth embankment down to the ground
## where the track runs above it.
static func _ballast(st: SurfaceTool, c0: Vector3, c1: Vector3, n0: Vector3, n1: Vector3) -> void:
	# A low prism like real in-town track: a 3.2 m crown just wider than the
	# 2.6 m ties, shoulders falling about 2:1 to a weedy toe at ground level.
	var y := Vector3(0, BALLAST_Y, 0)
	var down := Vector3(0, -0.04, 0)
	_quad(st, c0 - n0 * 1.6 + y, c0 + n0 * 1.6 + y, c1 + n1 * 1.6 + y, c1 - n1 * 1.6 + y, BALLAST)
	for side: float in [-1.0, 1.0]:
		var a0 := c0 + n0 * side * 1.6 + y
		var a1 := c1 + n1 * side * 1.6 + y
		var b0 := c0 + n0 * side * 2.3 + down
		var b1 := c1 + n1 * side * 2.3 + down
		_quad(st, a0, b0, b1, a1, BALLAST_DARK)
		# Weeds and spilled rock fading into the grass.
		var f0 := c0 + n0 * side * 3.1 + down * 2.0
		var f1 := c1 + n1 * side * 3.1 + down * 2.0
		_quad(st, b0, f0, f1, b1, WEEDS)
		# Fill slopes at 2:1 (AREMA) down to the ground beside the track,
		# wherever the profile rides above it.
		var drop0 := minf(f0.y - Terrain.base_y(f0.x, f0.z), MAX_FILL)
		var drop1 := minf(f1.y - Terrain.base_y(f1.x, f1.z), MAX_FILL)
		if drop0 > 0.15 or drop1 > 0.15:
			var e0 := f0 + n0 * side * maxf(drop0, 0.0) * 2.0
			var e1 := f1 + n1 * side * maxf(drop1, 0.0) * 2.0
			e0.y = minf(f0.y, Terrain.ground_y(e0.x, e0.z)) - 0.3
			e1.y = minf(f1.y, Terrain.ground_y(e1.x, e1.z)) - 0.3
			_quad(st, f0, e0, e1, f1, EARTH)


func _over_road(marks: Array, at: float) -> bool:
	for m in marks:
		if m[2] and absf(at - float(m[0])) < float(m[1]):
			return true
	return false


## The concrete end of an underpass span: a wall shaped like the fill it
## holds back, narrow at the deck and as wide as the bank at its foot.
func _abutment(st: SurfaceTool, c: Vector3, n: Vector3) -> void:
	var g := Terrain.ground_y(c.x, c.z) - 0.3
	var foot := 3.1 + maxf(c.y - g, 0.0) * 2.0
	var top := c.y + BALLAST_Y
	var along := n.cross(Vector3.UP).normalized() * 0.3
	for k: float in [-1.0, 1.0]:
		# Both faces of a 60 cm wall, so it reads from either side.
		var o := along * k
		var a := c - n * 2.3 * k + o
		var b := c + n * 2.3 * k + o
		var bf := c + n * foot * k + o
		var af := c - n * foot * k + o
		_quad(st, Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(bf.x, g, bf.z), Vector3(af.x, g, af.z), CONCRETE)


## A deck girder span, with a concrete pier every third point (~30 m).
static func _bridge_span(st: SurfaceTool, c0: Vector3, c1: Vector3, n0: Vector3, n1: Vector3, i: int) -> void:
	var y := Vector3(0, BALLAST_Y, 0)
	_quad(st, c0 - n0 * 2.2 + y, c0 + n0 * 2.2 + y, c1 + n1 * 2.2 + y, c1 - n1 * 2.2 + y, BALLAST_DARK)
	for side: float in [-1.0, 1.0]:
		var t0 := c0 + n0 * side * 2.2 + y
		var t1 := c1 + n1 * side * 2.2 + y
		var d := Vector3(0, -2.0, 0)
		_quad(st, t0, t0 + d, t1 + d, t1, GIRDER)
		# Handrail.
		var r := Vector3(0, 1.1, 0)
		_quad(st, t0 + r, t0 + r * 0.9, t1 + r * 0.9, t1 + r, GIRDER)
	_quad(st, c0 - n0 * 2.2 + Vector3(0, -1.7, 0), c0 + n0 * 2.2 + Vector3(0, -1.7, 0),
		c1 + n1 * 2.2 + Vector3(0, -1.7, 0), c1 - n1 * 2.2 + Vector3(0, -1.7, 0), GIRDER)
	if i % 3 == 0:
		var bottom := Terrain.ground_y(c0.x, c0.z) - 2.0
		var fwd := (c1 - c0).normalized()
		var frame := Transform3D(Basis(n0, Vector3.UP, fwd.cross(n0).normalized()), Vector3(c0.x, (c0.y - 1.7 + bottom) * 0.5, c0.z))
		_box(st, frame, Vector3.ZERO, Vector3(4.6, maxf(c0.y - 1.7 - bottom, 0.5), 1.6), CONCRETE)


## One rail: a steel bar with a bright, worn running surface.
static func _rail(st: SurfaceTool, a: Vector3, b: Vector3, na: Vector3, nb: Vector3) -> void:
	var w := 0.036
	var top := Vector3(0, RAIL_Y, 0)
	var foot := Vector3(0, TIE_Y, 0)
	_quad(st, a - na * w + top, a + na * w + top, b + nb * w + top, b - nb * w + top, RAIL_TOP)
	for side: float in [-1.0, 1.0]:
		_quad(st, a + na * side * w + top, a + na * side * w + foot, b + nb * side * w + foot, b + nb * side * w + top, RAIL)


## Rubber crossing panels where the track crosses a road.
func _crossing_pad(st: SurfaceTool, c: Dictionary) -> void:
	if not sim.network.segments.has(c.seg):
		return
	var pose := sim.rail.pose_at(c.piece, c.s)
	var fwd: Vector3 = pose[1]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var n := Vector3(-fwd.z, 0.0, fwd.x)
	var hw := RoadStyle.half_width(sim.network.segments[c.seg].type)
	var p: Vector3 = c.pos
	var y := Terrain.base_y(p.x, p.z) + CROSSING_RAIL - 0.02
	# Along the road the pad is the track's width; across, the road's.
	var road := _road_dir(c)
	var q := [p - road * hw - fwd * 0.0, p + road * hw]
	var c0 := Vector3(q[0].x, y, q[0].z)
	var c1 := Vector3(q[1].x, y, q[1].z)
	var side := Vector3(-road.z, 0.0, road.x)
	if side.dot(fwd) < 0.0:
		side = -side
	_quad(st, c0 - side * 1.6, c0 + side * 1.6, c1 + side * 1.6, c1 - side * 1.6, Color("#3c3d3e"))
	for k: float in [-1.0, 1.0]:
		var o: Vector3 = n * k * RailModels.GAUGE * 0.5
		_quad(st, c0 + o - side * 0.04 + Vector3(0, 0.02, 0), c0 + o + side * 0.04 + Vector3(0, 0.02, 0),
			c1 + o + side * 0.04 + Vector3(0, 0.02, 0), c1 + o - side * 0.04 + Vector3(0, 0.02, 0), RAIL_TOP)


## Whistle posts: a white sign with a black W on the engineer's right, a
## quarter mile before each crossing in both directions, where the horn
## pattern starts (FRA 49 CFR 222.21; railroads' timetable instructions).
func _whistle_posts(st: SurfaceTool, c: Dictionary) -> void:
	if not sim.rail.pieces.has(int(c.piece)):
		return
	# A quiet zone takes its whistle posts down.
	if sim.pollution.quiet.has(int(sim.rail.pieces[int(c.piece)].depot)):
		return
	for dir: int in [-1, 1]:
		var at := _walk(int(c.piece), float(c.s), dir, WHISTLE_POST)
		if at.is_empty():
			continue
		var heading: Vector3 = -at[1]   # a train coming toward the crossing
		var right := Vector3(-heading.z, 0.0, heading.x)
		var p: Vector3 = at[0] + right * 3.4
		var f := Transform3D(Basis(right, Vector3.UP, -heading), Vector3(p.x, Terrain.ground_y(p.x, p.z), p.z))
		_box(st, f, Vector3(0, 1.3, 0), Vector3(0.1, 2.6, 0.1), Color("#8a8a86"))
		_box(st, f, Vector3(0, 2.25, 0.07), Vector3(0.7, 0.85, 0.04), Color("#f2f2ee"))
		for k in 4:
			var x := -0.18 + k * 0.12
			var lean := 0.32 if k % 2 == 0 else -0.32
			var stroke := f * Transform3D(Basis(Vector3.BACK, lean), Vector3(x, 2.25, 0.1))
			_box(st, stroke, Vector3.ZERO, Vector3(0.05, 0.5, 0.01), Color("#1e1e1e"))


## A point `dist` metres along the track from (piece, s), going `dir`,
## carrying on through joints: [pos, direction of travel], or [] at a dead end.
func _walk(pid: int, s: float, dir: int, dist: float) -> Array:
	var rail := sim.rail
	for guard in 12:
		var L := rail._length(pid)
		var room: float = (L - s) if dir > 0 else s
		if dist <= room:
			var pose := rail.pose_at(pid, s + dir * dist)
			return [pose[0], (pose[1] as Vector3) * dir]
		dist -= room
		var node: int = rail.pieces[pid].b if dir > 0 else rail.pieces[pid].a
		var next := -1
		for q in rail._pieces_at(node):
			if q != pid and rail._complete(q):
				next = q
				break
		if next == -1:
			return []
		pid = next
		dir = 1 if rail.pieces[pid].a == node else -1
		s = 0.0 if dir > 0 else rail._length(pid)
	return []


func _road_dir(c: Dictionary) -> Vector3:
	var near := sim.network.find_segment_near(c.pos, 20.0, 1.0)
	if near.is_empty():
		return Vector3.RIGHT
	var cv := sim.network.curve_of(near.seg)
	var t := RoadNetwork.bezier_tangent(cv[0], cv[1], cv[2], near.t)
	t.y = 0.0
	return t.normalized()


## The track's base level near a point (for trains and gates).
func height_at(p: Vector3) -> float:
	var c := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	if _h.has(c):
		return _h[c]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var k := c + Vector2i(dx, dy)
			if _h.has(k):
				return _h[k]
	return Terrain.base_y(p.x, p.z)


# --- Survey stakes for track still to lay -------------------------------------

func _draw_stakes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for lid in sim.rail.lines:
		var l: Dictionary = sim.rail.lines[lid]
		if l.state != "building":
			continue
		var route: Array = l.route
		var run := 0.0
		var next := float(l.built)
		for i in range(1, route.size()):
			var a: Vector3 = route[i - 1]
			var b: Vector3 = route[i]
			var seg := a.distance_to(b)
			while next < run + seg:
				var p := a.lerp(b, (next - run) / maxf(seg, 0.001))
				var n := (b - a).normalized()
				n = Vector3(-n.z, 0.0, n.x)
				for side: float in [-1.0, 1.0]:
					var q: Vector3 = p + n * side * 3.5
					var frame := Transform3D(Basis.IDENTITY, Vector3(q.x, Terrain.ground_y(q.x, q.z), q.z))
					_box(st, frame, Vector3(0, 0.6, 0), Vector3(0.06, 1.2, 0.06), Color("#c8b48a"))
					_box(st, frame, Vector3(0, 1.1, 0), Vector3(0.08, 0.18, 0.08), Color("#ff6a1a"))
				any = true
				next += 25.0
			run += seg
	_stakes.visible = any
	if any:
		st.generate_normals()
		_stakes.mesh = st.commit()


# --- Depots ------------------------------------------------------------------

func _draw_yards() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in sim.rail.depots:
		var d: Dictionary = sim.rail.depots[id]
		any = true
		var built: Array = d.get("built", [])
		var half := Rail.YARD_LEN * 0.5
		var y := Terrain.base_y(d.pos.x, d.pos.z)
		# No paved pad: grass and weeds between the tracks, as at a real
		# small-town siding, and a gravel lane alongside for the crews' trucks.
		var u := -half + 54.0
		while u < half - 12.0:
			var a := Rail._yard_pt(d, u, 12.0)
			var b := Rail._yard_pt(d, minf(u + 10.0, half - 12.0), 12.0)
			var n: Vector3 = -d.dir * 1.75
			var ya := Terrain.ground_y(a.x, a.z) + 0.08
			var yb := Terrain.ground_y(b.x, b.z) + 0.08
			_quad(st, Vector3(a.x, ya, a.z) - n, Vector3(a.x, ya, a.z) + n, Vector3(b.x, yb, b.z) + n,
				Vector3(b.x, yb, b.z) - n, Color("#7d776b"))
			u += 10.0
		# Office: a one-storey brick depot facing the road, at the yard's near end.
		var office := _frame(d, -half + 40.0, 7.0, y)
		_building(st, office, Vector3(20.0, 4.6, 9.0), Color("#6e3428"), Color("#3a3734"))
		# Gravel lot for the crews' trucks beside it.
		_box(st, _frame(d, -half + 66.0, 7.0, y), Vector3(0, 0.05, 0), Vector3(24.0, 0.1, 10.0), Color("#77736a"))
		if "station" in built:
			_station(st, d, y)
		if "engine_house" in built:
			# A two-stall engine house straddling the far yard track.
			var eh := _frame(d, half - 30.0, float(Rail.TRACK_V[2]) + 2.3, y)
			_building(st, eh, Vector3(36.0, 8.5, 13.0), Color("#683427"), Color("#3f3b36"), true)
		if "car_shop" in built:
			var cs := _frame(d, half - 85.0, float(Rail.TRACK_V[2]) + 4.0, y)
			_building(st, cs, Vector3(50.0, 10.0, 16.0), Color("#8d9290"), Color("#5c6265"), true)
		if "intermodal" in built:
			# Stacks of containers on a paved pad, between the crews' lot
			# and the station.
			var ix := _frame(d, -29.0, 6.0, y)
			_box(st, ix, Vector3(0, 0.05, 0), Vector3(38.0, 0.1, 10.0), Color("#5d5e5c"))
			# 40 ft boxes in two rows of three, stacked one or two high.
			for k in 6:
				for lvl in (k % 2) + 1:
					var col: Color = [Color("#a33a2c"), Color("#2c5d8a"), Color("#c9a13a"), Color("#4f7a47")][(k + lvl) % 4]
					_box(st, ix, Vector3(-11.5 + (k % 2) * 23.0, 1.3 + lvl * 2.6 - 2.6, -3.0 + (k / 2) * 3.0), Vector3(12.2, 2.6, 2.44), col)
		_depot_upgrades(st, d, y, built)
	_yard.visible = any
	if any:
		st.generate_normals()
		_yard.mesh = st.commit()


## A small-town Amtrak stop, like the Midwest's restored depots: a brick
## waiting room with wide bracketed eaves, a concrete platform long enough
## for the train (an 8 in. high platform with the ADA's 24 in. yellow
## tactile strip along the edge), a short canopy by the door, lamp posts,
## and a small paved lot with a drive in from the road.
func _station(st: SurfaceTool, d: Dictionary, y: float) -> void:
	var edge := float(Rail.TRACK_V[0]) - 1.6   # platform edge, clear of the train
	var plat := _frame(d, 0.0, edge - 2.0, y)
	_box(st, plat, Vector3(0, 0.1, 0), Vector3(122.0, 0.2, 4.0), CONCRETE)
	_box(st, plat, Vector3(0, 0.205, 1.7), Vector3(122.0, 0.01, 0.6), Color("#e3b51e"))
	for k in 9:
		var lamp := Vector3(-56.0 + k * 14.0, 0, -1.4)
		_box(st, plat, lamp + Vector3(0, 2.2, 0), Vector3(0.14, 4.4, 0.14), Color("#22262a"))
		_box(st, plat, lamp + Vector3(0, 4.35, 0.25), Vector3(0.3, 0.2, 0.6), Color("#22262a"))
	# The canopy: a short one over the door, not the whole platform.
	for x: float in [-10.0, 0.0, 10.0]:
		_box(st, plat, Vector3(x, 1.7, -0.6), Vector3(0.22, 3.4, 0.22), Color("#2f4a3a"))
	_box(st, plat, Vector3(0, 3.5, 0), Vector3(24.0, 0.16, 3.6), Color("#2f4a3a"))
	# The depot: waiting room and ticket office, door to the platform.
	var depot := _frame(d, 0.0, edge - 8.5, y)
	_building(st, depot, Vector3(16.0, 4.4, 7.0), Color("#7a3b2c"), Color("#3c3a37"))
	# A white station-name board on the platform side, like the old depots'.
	_box(st, depot, Vector3(0, 3.6, 3.56), Vector3(5.0, 0.6, 0.06), Color("#f2f2ee"))
	_box(st, depot, Vector3(0, 3.6, 3.6), Vector3(4.0, 0.22, 0.02), Color("#1e1e1e"))
	# Parking: a paved lot with 2.7 m stalls, opening straight off the road,
	# built up on fill where the ground falls away.
	var lot := _frame(d, 36.0, 5.0, y)
	_box(st, lot, Vector3(0, -0.7, 0), Vector3(36.0, 1.5, 9.0), Color("#4e4f4e"))
	for k in 13:
		_box(st, lot, Vector3(-16.2 + k * 2.7, 0.055, 1.5), Vector3(0.1, 0.01, 5.4), Color("#e8e8e2"))
	# A walk from the lot to the platform.
	_box(st, _frame(d, 16.0, (9.5 + edge - 4.0) * 0.5, y), Vector3(0, -0.6, 0),
		Vector3(2.0, 1.4, edge - 4.0 - 9.5), CONCRETE)


## The rest of the railroad's development tree (Rail.TREE), each where a
## real short line puts it (Brawn 2026-10-23: every upgrade shows). The
## strip behind the far track (v 30-40) holds the freight side; the station
## side gets the passenger steps.
func _depot_upgrades(st: SurfaceTool, d: Dictionary, y: float, built: Array) -> void:
	var steel := Color("#6b6f73")
	if "team_track" in built:
		# Team track: a gravel pad and a concrete end-loading ramp where
		# local businesses back trucks up to load their own cars.
		var t := _frame(d, -105.0, 35.0, y)
		_box(st, t, Vector3(0, 0.05, 0), Vector3(36.0, 0.1, 8.0), Color("#8d877c"))
		_box(st, t, Vector3(-14.0, 0.6, -2.0), Vector3(6.0, 1.2, 4.0), CONCRETE)
	if "grain_spur" in built:
		# The co-op elevator on its spur: three concrete silos, a headhouse
		# and a loading spout out over the track.
		for k in 3:
			var c := _frame(d, -76.0 + k * 7.4, 35.5, y)
			_cyl(st, c, 3.5, 26.0, Color("#c9c3b4"))
		_box(st, _frame(d, -68.6, 35.5, y), Vector3(0, 30.0, 0), Vector3(6.0, 8.0, 5.0), Color("#b9b3a4"))
		_box(st, _frame(d, -68.6, 30.0, y), Vector3(0, 10.0, 0), Vector3(0.6, 0.6, 7.0), steel)
	if "unit_loop" in built:
		# Shuttle loader for 100-car trains: two big steel bins and a tall
		# loading tower whose spout fills each hopper as it creeps under.
		for k in 2:
			_cyl(st, _frame(d, -42.0 + k * 10.0, 35.5, y), 4.4, 20.0, Color("#bfc3c4"))
		_box(st, _frame(d, -22.0, 34.0, y), Vector3(0, 16.0, 0), Vector3(4.0, 32.0, 4.0), Color("#a7aba9"))
		_box(st, _frame(d, -22.0, 29.0, y), Vector3(0, 8.0, 0), Vector3(1.2, 4.0, 1.2), steel)
	if "interchange" in built:
		# Interchange: a yardmaster's tower watching the swap tracks.
		var t := _frame(d, 5.0, 35.0, y)
		_box(st, t, Vector3(0, 3.0, 0), Vector3(5.0, 6.0, 5.0), Color("#6e3428"))
		_box(st, t, Vector3(0, 7.2, 0), Vector3(5.6, 2.4, 5.6), Color("#2a3438"))
		_box(st, t, Vector3(0, 8.6, 0), Vector3(6.4, 0.4, 6.4), Color("#3a3734"))
	if "classification" in built:
		# A busy classification yard works all night under high-mast lights.
		for k in 5:
			var t := _frame(d, -120.0 + k * 60.0, 39.0, y)
			_box(st, t, Vector3(0, 13.0, 0), Vector3(0.6, 26.0, 0.6), steel)
			_box(st, t, Vector3(0, 26.2, 0), Vector3(3.0, 0.8, 1.0), Color("#d8d6cf"))
	var edge := float(Rail.TRACK_V[0]) - 1.6
	if "intercity" in built and "station" in built:
		# Intercity trains are long: the platform runs on to 240 m.
		for s: float in [-1.0, 1.0]:
			var pl := _frame(d, s * 91.0, edge - 2.0, y)
			_box(st, pl, Vector3(0, 0.1, 0), Vector3(60.0, 0.2, 4.0), CONCRETE)
			_box(st, pl, Vector3(0, 0.205, 1.7), Vector3(60.0, 0.01, 0.6), Color("#e3b51e"))
	if "commuter" in built and "station" in built:
		# Commuter service: glass shelters down the platform with ticket
		# machines, and a park-and-ride lot beside the station lot.
		for u: float in [-40.0, 40.0, 75.0]:
			var sh := _frame(d, u, edge - 3.0, y)
			_box(st, sh, Vector3(0, 1.3, 0.9), Vector3(4.0, 2.4, 0.1), Color("#9fb4bd"))
			_box(st, sh, Vector3(0, 2.6, 0), Vector3(4.4, 0.15, 2.0), Color("#2f4a3a"))
			_box(st, sh, Vector3(2.6, 0.8, 0), Vector3(0.6, 1.6, 0.5), Color("#c43a2c"))
		var lot := _frame(d, 76.0, 5.0, y)
		_box(st, lot, Vector3(0, -0.7, 0), Vector3(36.0, 1.5, 9.0), Color("#4e4f4e"))
		for k in 13:
			_box(st, lot, Vector3(-16.2 + k * 2.7, 0.055, 1.5), Vector3(0.1, 0.01, 5.4), Color("#e8e8e2"))


## An upright cylinder (silos, bins) on the yard.
func _cyl(st: SurfaceTool, f: Transform3D, r: float, h: float, col: Color) -> void:
	var segs := 14
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var up := Vector3(0, h, 0)
		# Same winding as _box: outward faces front.
		for q in [p0, p1 + up, p1, p0, p0 + up, p1 + up]:
			st.set_color(col)
			st.add_vertex(f * (q as Vector3))
		for q in [p0 + up, Vector3(0, h + r * 0.4, 0), p1 + up]:
			st.set_color(col.darkened(0.1))
			st.add_vertex(f * (q as Vector3))


## A frame on the yard: x along the tracks, z away from the road (+z back).
func _frame(d: Dictionary, u: float, v: float, y: float) -> Transform3D:
	var p := Rail._yard_pt(d, u, v)
	var away: Vector3 = -d.dir
	return Transform3D(Basis(d.axis, Vector3.UP, away), Vector3(p.x, y, p.z))


## A simple building: walls, a darker roof with a low gable or a flat top,
## doors and windows on the road side.
func _building(st: SurfaceTool, f: Transform3D, size: Vector3, wall: Color, roof: Color, big_doors := false) -> void:
	_box(st, f, Vector3(0, size.y * 0.5, 0), size, wall)
	# A gable roof with wide eaves, like a small-town depot's.
	var eave := 1.2 if not big_doors else 0.4
	var hx := size.x * 0.5 + eave
	var hz := size.z * 0.5 + eave
	var rise := size.z * (0.3 if not big_doors else 0.2)
	var y0 := size.y - 0.2
	var ridge_a := f * Vector3(-hx, y0 + rise + eave * 0.3, 0)
	var ridge_b := f * Vector3(hx, y0 + rise + eave * 0.3, 0)
	for side: float in [-1.0, 1.0]:
		var ea := f * Vector3(-hx, y0, side * hz)
		var eb := f * Vector3(hx, y0, side * hz)
		_quad(st, ea, eb, ridge_b, ridge_a, roof)
	for e: float in [-1.0, 1.0]:
		var gx := size.x * 0.5 * e
		for p in [f * Vector3(gx, size.y, -size.z * 0.5), f * Vector3(gx, size.y, size.z * 0.5),
				f * Vector3(gx, size.y + rise * size.z * 0.5 / hz, 0)]:
			st.set_color(wall)
			st.add_vertex(p)
	if big_doors:
		for k in [-0.25, 0.25]:
			_box(st, f, Vector3(size.x * k, size.y * 0.4, -size.z * 0.5 - 0.03), Vector3(5.0, size.y * 0.75, 0.05), Color("#2c2a28"))
	else:
		_box(st, f, Vector3(-size.x * 0.3, 1.1, -size.z * 0.5 - 0.03), Vector3(1.1, 2.2, 0.05), Color("#3a2a20"))
		for k in 4:
			_box(st, f, Vector3(-size.x * 0.1 + k * size.x * 0.15, 2.0, -size.z * 0.5 - 0.03), Vector3(1.2, 1.4, 0.05), Color("#2a3438"))


# --- Gates -------------------------------------------------------------------

## Crossbucks, flashing lights and a gate arm on each approach. Arms lie
## across the lane when down and stand straight up when the way is clear.
func _draw_gates() -> void:
	var blink := int(Time.get_ticks_msec() / 500) % 2
	var sig := ""
	var xs := sim.all_crossings()
	for c in xs:
		sig += "1" if c.closed else "0"
	sig += str(blink) + str(xs.size()) + str(sim.county_trains.version) + _sig.substr(0, 40)
	if sig == _gate_sig:
		return
	_gate_sig = sig
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var any_lit := false
	for c in xs:
		if not sim.network.segments.has(c.seg):
			continue
		any = true
		var road := _road_dir(c)
		var across := Vector3(-road.z, 0.0, road.x)   # across the road
		var hw := RoadStyle.half_width(sim.network.segments[c.seg].type)
		for k: float in [-1.0, 1.0]:
			# On each approach: the post stands on the road's right, back from the track.
			var along: Vector3 = road * k
			var right := Vector3(along.z, 0.0, -along.x) * -1.0
			var base: Vector3 = c.pos - along * 6.0 + right * (hw + 1.2)
			var y := Terrain.ground_y(base.x, base.z)
			var f := Transform3D(Basis(right, Vector3.UP, along), Vector3(base.x, y, base.z))
			_box(st, f, Vector3(0, 2.2, 0), Vector3(0.18, 4.4, 0.18), Color("#d9d9d4"))
			# Crossbuck: two white boards crossed.
			for tilt: float in [0.7, -0.7]:
				var cb := f * Transform3D(Basis(Vector3.BACK, tilt), Vector3(0, 3.9, -0.12))
				_box(st, cb, Vector3.ZERO, Vector3(2.4, 0.22, 0.03), Color("#f2f2ee"))
			_box(st, f, Vector3(0, 3.1, -0.15), Vector3(1.4, 0.12, 0.08), Color("#1e1e1e"))
			for s: float in [-1.0, 1.0]:
				_box(st, f, Vector3(s * 0.6, 3.1, -0.22), Vector3(0.42, 0.42, 0.06), Color("#1e1e1e"))
				if c.closed and (blink == 0) == (s < 0.0):
					_box(lit, f, Vector3(s * 0.6, 3.1, -0.27), Vector3(0.3, 0.3, 0.02), Color.WHITE)
					any_lit = true
			# Gate arm: red and white, across the approach lanes when down.
			var arm_len: float = hw + 0.6
			if c.closed:
				var arm := f * Transform3D(Basis.IDENTITY, Vector3(-arm_len * 0.5 - 0.2, 1.1, 0.2))
				_stripes(st, arm, arm_len)
			else:
				var arm := f * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.2, 1.1 + arm_len * 0.5, 0.2))
				_stripes(st, arm, arm_len)
			_box(st, f, Vector3(0.15, 1.0, 0.2), Vector3(0.5, 0.6, 0.4), Color("#4a4a48"))  # counterweight
	_gates.visible = any
	if any:
		st.generate_normals()
		_gates.mesh = st.commit()
	_lights.visible = any_lit
	if any_lit:
		_lights.mesh = lit.commit()


func _stripes(st: SurfaceTool, f: Transform3D, length: float) -> void:
	var n := maxi(3, int(length / 0.9))
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * length / n
		_box(st, f, Vector3(x, 0, 0), Vector3(length / n, 0.12, 0.1), Color("#c8261e") if i % 2 == 0 else Color("#f2f2ee"))


# --- Trains ------------------------------------------------------------------

func _draw_trains() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var lists := {}
	var tids := sim.rail.trains.keys()
	tids.sort()
	for tid in tids:
		for car in sim.rail.car_poses(tid):
			var f: Vector3 = car[1]
			var b: Vector3 = car[2]
			if f.distance_to(eye) > FAR:
				continue
			var fy := height_at(f) + RAIL_Y
			var by := height_at(b) + RAIL_Y
			var front := Vector3(f.x, fy, f.z)
			var back := Vector3(b.x, by, b.z)
			var mid := (front + back) * 0.5
			var dir := front - back
			if dir.length() < 0.1:
				continue
			if not lists.has(car[0]):
				lists[car[0]] = []
			lists[car[0]].append(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), mid))
	# Cars left at the county interchange for the next through freight, from
	# the interchange track's far end back.
	for h in sim.county_trains.handoffs:
		var pid := int(h.piece)
		if not sim.rail.pieces.has(pid):
			continue
		var L: float = sim.rail._length(pid)
		var x := 0.5
		for car in h.cars:
			var k: String = car[0]
			var len: float = Rail.STOCK[k].len if Rail.STOCK.has(k) else 18.0
			var f: Vector3 = sim.rail.pose_at(pid, L - x)[0]
			var b: Vector3 = sim.rail.pose_at(pid, L - x - len + 1.0)[0]
			x += len + 1.0
			if f.distance_to(eye) > FAR or not _cars.has(k):
				continue
			var front := Vector3(f.x, height_at(f) + RAIL_Y, f.z)
			var back := Vector3(b.x, height_at(b) + RAIL_Y, b.z)
			if (front - back).length() < 0.1:
				continue
			if not lists.has(k):
				lists[k] = []
			lists[k].append(Transform3D(Basis.looking_at((front - back).normalized(), Vector3.UP), (front + back) * 0.5))
	for kind in _cars:
		var mm: MultiMesh = _cars[kind].multimesh
		var list: Array = lists.get(kind, [])
		if list.size() > mm.instance_count:
			mm.instance_count = maxi(list.size() * 2, 8)
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, Color.WHITE)
		mm.visible_instance_count = list.size()


# --- The Rail view -----------------------------------------------------------

const LINE_COLORS := {"open": Color("#2a9d8f"), "building": Color("#f4a261"), "permit": Color("#9be3c6"),
	"denied": Color("#9aa0a2"), "shelved": Color("#9aa0a2")}


func _draw_overlay() -> void:
	if not show_lines:
		_overlay.visible = false
		for l in _labels:
			l.visible = false
		return
	var labels := []
	for lid in sim.rail.lines:
		var l: Dictionary = sim.rail.lines[lid]
		var route: Array = l.route
		if route.size() < 2 or not l.state in LINE_COLORS:
			continue
		var mid: Vector3 = route[route.size() / 2]
		var what := "Main line to the region" if l.kind == "main" else "Spur to the %s" % str(l.target.name).to_lower()
		var line2: String = {"open": "open", "building": "crews laying track", "permit": "waiting on your permit",
			"denied": "you said no", "shelved": "shelved"}[l.state]
		if l.state == "open" and l.kind == "spur":
			line2 = "%d cars waiting" % int(l.cars) if int(l.cars) > 0 else "open"
		labels.append([Vector3(mid.x, height_at(mid) + 14.0, mid.z), "%s\n%s" % [what, line2]])
	for tid in sim.rail.trains:
		var t: Dictionary = sim.rail.trains[tid]
		var poses := sim.rail.car_poses(tid)
		if poses.is_empty():
			continue
		var p: Vector3 = poses[0][1]
		var load: String = "%d riders" % int(t.riders) if t.kind == "passenger" else (
			"%d cars of %s" % [int(t.cars), t.cargo] if str(t.cargo) != "" else "empty")
		labels.append([Vector3(p.x, height_at(p) + 9.0, p.z), "%s to %s\n%s" % [
			"Passenger" if t.kind == "passenger" else "Freight", str(t.to).to_lower() if str(t.to).begins_with("The") else t.to, load]])
	while _labels.size() < labels.size():
		var lb := Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lb.pixel_size = 0.0012
		lb.font_size = 22
		lb.outline_size = 6
		lb.modulate = Color.WHITE
		lb.outline_modulate = Color(0.1, 0.12, 0.14)
		add_child(lb)
		_labels.append(lb)
	for i in _labels.size():
		var lb: Label3D = _labels[i]
		lb.visible = i < labels.size()
		if lb.visible:
			lb.position = labels[i][0]
			lb.text = labels[i][1]
	# The ribbons only change when the lines do.
	var sig := _sig + str(sim.rail.lines.size())
	for lid in sim.rail.lines:
		sig += sim.rail.lines[lid].state
	if sig == _overlay_sig:
		return
	_overlay_sig = sig
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for lid in sim.rail.lines:
		var l: Dictionary = sim.rail.lines[lid]
		if not l.state in LINE_COLORS:
			continue
		var col: Color = LINE_COLORS[l.state]
		var route: Array = l.route
		for i in route.size() - 1:
			if l.state in ["permit", "shelved", "denied"] and i % 2 == 1:
				continue  # dashed: not built
			var a: Vector3 = route[i]
			var b: Vector3 = route[i + 1]
			var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
			if d.length() < 0.01:
				continue
			var n := Vector3(-d.z, 0.0, d.x).normalized() * 3.0
			var ya := Vector3(0, height_at(a) + 1.5, 0)
			var yb := Vector3(0, height_at(b) + 1.5, 0)
			_quad(st, Vector3(a.x, 0, a.z) - n + ya, Vector3(a.x, 0, a.z) + n + ya,
				Vector3(b.x, 0, b.z) + n + yb, Vector3(b.x, 0, b.z) - n + yb, Color(col, 0.85))
			any = true
	for id in sim.rail.depots:
		var poly := sim.rail.yard_poly(id)
		var g := []
		for p in poly:
			g.append(Vector3(p.x, Terrain.base_y(p.x, p.y) + 1.5, p.y))
		_quad(st, g[0], g[1], g[2], g[3], Color(LINE_COLORS.open, 0.35))
		any = true
	_overlay.visible = any
	if any:
		_overlay.mesh = st.commit()


# --- Mesh helpers --------------------------------------------------------------

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)


static func _box(st: SurfaceTool, frame: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1] * h
		var v: Vector3 = f[2] * h
		var o: Vector3 = c + n * h
		var q := [o - u - v, o + u - v, o + u + v, o - u + v]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(frame * (q[k] as Vector3))
