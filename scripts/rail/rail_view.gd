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
const EARTH := Color("#6f6a4c")
const GIRDER := Color("#3d4347")
const CONCRETE := Color("#a9a69d")
## Heights above the track's base level (m): ballast top, tie top, rail top.
const BALLAST_Y := 0.3
const TIE_Y := 0.48
const RAIL_Y := 0.65
const TIE_EVERY := 0.6
## Above the water at a bridge (m).
const BRIDGE_CLEAR := 5.5
const FAR := 3200.0

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
	var parts := [sim.rail.depots.size(), sim.rail.pieces.size(), sim.rail.crossings.size()]
	for pid in sim.rail.pieces:
		parts.append(floori(float(sim.rail.pieces[pid].built) / 20.0))
	for lid in sim.rail.lines:
		parts.append(sim.rail.lines[lid].state)
	for id in sim.rail.depots:
		parts.append(sim.rail.depots[id].get("built", []).size())
	return str(parts)


# --- Track -------------------------------------------------------------------

func _wet(p: Vector3) -> bool:
	return Terrain.is_water(p.x + Terrain.shift.x + Terrain.view_origin.x, p.z + Terrain.shift.y + Terrain.view_origin.y)


## The track's base level along a line of points: the graded base, lifted
## over water, with ramps no steeper than `grade`.
func _profile(pts: Array, grade: float) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(pts.size())
	for i in pts.size():
		var p: Vector3 = pts[i]
		var y := Terrain.base_y(p.x, p.z)
		if _wet(p):
			var wl := Terrain.water_level(p.x + Terrain.shift.x + Terrain.view_origin.x, p.z + Terrain.shift.y + Terrain.view_origin.y)
			y = maxf(y, wl + BRIDGE_CLEAR)
		h[i] = y
	for pass_dir in [1, -1]:
		var r := range(1, pts.size()) if pass_dir == 1 else range(pts.size() - 2, -1, -1)
		for i in r:
			var j: int = i - pass_dir
			var ds: float = (pts[i] as Vector3).distance_to(pts[j])
			h[i] = maxf(h[i], h[j] - grade * ds)
	return h


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
		var grade: float = RailPlanner.LIMITS.spur.grade if pc.kind == "spur" else RailPlanner.LIMITS.main.grade
		var h := _profile(pts, grade)
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
			var wet := _wet((p0 + p1) * 0.5)
			if wet:
				_bridge_span(st, c0, c1, n0, n1, i)
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
	_track.visible = any
	if any:
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
			_grades["rail:%d:%d" % [pid, chunk]] = [line, 4.0, 10.0]
		k += 10
		chunk += 1


## Crushed rock in a trapezoid, and an earth embankment down to the ground
## where the track runs above it.
func _ballast(st: SurfaceTool, c0: Vector3, c1: Vector3, n0: Vector3, n1: Vector3) -> void:
	var y := Vector3(0, BALLAST_Y, 0)
	var down := Vector3(0, -0.05, 0)
	_quad(st, c0 - n0 * 1.9 + y, c0 + n0 * 1.9 + y, c1 + n1 * 1.9 + y, c1 - n1 * 1.9 + y, BALLAST)
	for side: float in [-1.0, 1.0]:
		var a0 := c0 + n0 * side * 1.9 + y
		var a1 := c1 + n1 * side * 1.9 + y
		var b0 := c0 + n0 * side * 3.0 + down
		var b1 := c1 + n1 * side * 3.0 + down
		_quad(st, a0, b0, b1, a1, BALLAST_DARK)
		# Fill slopes at 2:1 to meet the ground.
		var g0 := Terrain.ground_y(b0.x, b0.z)
		var g1 := Terrain.ground_y(b1.x, b1.z)
		var drop0 := b0.y - g0
		var drop1 := b1.y - g1
		if drop0 > 0.15 or drop1 > 0.15:
			var e0 := b0 + n0 * side * maxf(drop0, 0.0) * 2.0
			var e1 := b1 + n1 * side * maxf(drop1, 0.0) * 2.0
			e0.y = Terrain.ground_y(e0.x, e0.z) - 0.2
			e1.y = Terrain.ground_y(e1.x, e1.z) - 0.2
			_quad(st, b0, e0, e1, b1, EARTH)


## A deck girder span, with a concrete pier every third point (~30 m).
func _bridge_span(st: SurfaceTool, c0: Vector3, c1: Vector3, n0: Vector3, n1: Vector3, i: int) -> void:
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
func _rail(st: SurfaceTool, a: Vector3, b: Vector3, na: Vector3, nb: Vector3) -> void:
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
	var y := Terrain.base_y(p.x, p.z) + 0.07
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
		# Gravel over the whole yard.
		var poly := Rail.yard_corners(d.pos, d.dir, d.axis)
		var g := []
		for p in poly:
			g.append(Vector3(p.x, Terrain.base_y(p.x, p.y) + 0.06, p.y))
		_quad(st, g[0], g[1], g[2], g[3], Color("#8a857a"))
		# Office: a one-storey brick depot facing the road, at the yard's near end.
		var office := _frame(d, -half + 40.0, 7.0, y)
		_building(st, office, Vector3(20.0, 4.6, 9.0), Color("#6e3428"), Color("#3a3734"))
		# Gravel lot for the crews' trucks beside it.
		_box(st, _frame(d, -half + 66.0, 7.0, y), Vector3(0, 0.05, 0), Vector3(24.0, 0.1, 10.0), Color("#77736a"))
		if "station" in built:
			# Platform and canopy beside the passenger track.
			var plat := _frame(d, 0.0, float(Rail.TRACK_V[0]) - 3.4, y)
			_box(st, plat, Vector3(0, 0.45, 0), Vector3(120.0, 0.9, 3.6), CONCRETE)
			for k in 7:
				_box(st, plat, Vector3(-48.0 + k * 16.0, 2.4, -0.8), Vector3(0.25, 3.2, 0.25), Color("#2f4a3a"))
			_box(st, plat, Vector3(0, 4.05, -0.3), Vector3(100.0, 0.18, 4.4), Color("#2f4a3a"))
		if "engine_house" in built:
			# A two-stall engine house straddling the far yard track.
			var eh := _frame(d, half - 30.0, float(Rail.TRACK_V[2]) + 2.3, y)
			_building(st, eh, Vector3(36.0, 8.5, 13.0), Color("#683427"), Color("#3f3b36"), true)
		if "car_shop" in built:
			var cs := _frame(d, half - 85.0, float(Rail.TRACK_V[2]) + 4.0, y)
			_building(st, cs, Vector3(50.0, 10.0, 16.0), Color("#8d9290"), Color("#5c6265"), true)
		if "intermodal" in built:
			# Stacks of containers on a paved pad.
			var ix := _frame(d, -half + 110.0, 6.0, y)
			_box(st, ix, Vector3(0, 0.05, 0), Vector3(60.0, 0.1, 10.0), Color("#5d5e5c"))
			for k in 6:
				for lvl in (k % 2) + 1:
					var col: Color = [Color("#a33a2c"), Color("#2c5d8a"), Color("#c9a13a"), Color("#4f7a47")][(k + lvl) % 4]
					_box(st, ix, Vector3(-25.0 + k * 10.0, 1.3 + lvl * 2.6, 0), Vector3(12.2, 2.6, 2.44), col)
	_yard.visible = any
	if any:
		st.generate_normals()
		_yard.mesh = st.commit()


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
	for c in sim.rail.crossings:
		sig += "1" if c.closed else "0"
	sig += str(blink) + str(sim.rail.crossings.size()) + _sig.substr(0, 40)
	if sig == _gate_sig:
		return
	_gate_sig = sig
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var any_lit := false
	for c in sim.rail.crossings:
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
	for kind in _cars:
		var mm: MultiMesh = _cars[kind].multimesh
		var list: Array = lists.get(kind, [])
		if list.size() > mm.instance_count:
			mm.instance_count = maxi(list.size() * 2, 8)
		for i in list.size():
			mm.set_instance_transform(i, list[i])
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
