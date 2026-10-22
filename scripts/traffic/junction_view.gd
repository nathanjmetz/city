class_name JunctionView
extends Node3D
## Traffic lights on mast arms, stop signs and yield signs at every
## junction, drawn in a few batches. Lights change colour as they cycle.
## Signs follow MUTCD: a 30 in red octagon with a white border and STOP on a
## galvanised post, 7 ft to the bottom of the sign, green street-name blades
## on top, and a white stop bar and a crosswalk across each controlled
## approach.

const POLE_H := 5.8
const RED := Color(1.0, 0.12, 0.08)
const YELLOW := Color(1.0, 0.72, 0.05)
const GREEN := Color(0.15, 1.0, 0.45)

var traffic: TrafficSim
var _version := -1
var _poles: MultiMeshInstance3D
var _arms: MultiMeshInstance3D
var _heads: MultiMeshInstance3D
var _stops: MultiMeshInstance3D
var _yields: MultiMeshInstance3D
var _blades: MultiMeshInstance3D
var _paint := MeshInstance3D.new()
## [node, way] for each signal head, in instance order.
var _head_ways := []


func setup(t: TrafficSim) -> void:
	traffic = t


func _ready() -> void:
	var metal := RoadStyle.material(Color(0.42, 0.43, 0.42))
	metal.cull_mode = BaseMaterial3D.CULL_BACK
	_poles = _batch(_cylinder(0.12, 1.0, 8), metal)
	_arms = _batch(_box(Vector3(1.0, 0.18, 0.18)), metal)
	var lamp := StandardMaterial3D.new()
	lamp.vertex_color_use_as_albedo = true
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heads = _batch(_box(Vector3(0.45, 1.2, 0.45)), lamp, true)
	var red_sign := StandardMaterial3D.new()
	red_sign.albedo_color = Color(0.75, 0.05, 0.05)
	red_sign.emission_enabled = true
	red_sign.emission = Color(0.25, 0.0, 0.0)
	var stop_face := StandardMaterial3D.new()
	stop_face.albedo_texture = _stop_texture()
	stop_face.roughness = 0.5
	stop_face.cull_mode = BaseMaterial3D.CULL_BACK
	var back := RoadStyle.material(Color(0.6, 0.61, 0.6))
	# Octagon, 30 in across (MUTCD R1-1); triangle, 36 in (R1-2).
	_stops = _batch(_sign_mesh(0.38, stop_face, back), null)
	_yields = _batch(_plate(0.5, 3), red_sign)
	var green := RoadStyle.material(Color(0.05, 0.36, 0.2))
	_blades = _batch(_box(Vector3(0.9, 0.16, 0.03)), green)
	_paint.material_override = Surfaces.paint(RoadStyle.MARKING_WHITE)
	_paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paint)


func _process(_delta: float) -> void:
	if traffic == null:
		return
	if traffic.version != _version:
		_version = traffic.version
		_rebuild()
	for i in _head_ways.size():
		var hw: Array = _head_ways[i]
		var c := GREEN
		match traffic.light(hw[0], hw[1]):
			TrafficSim.Light.RED: c = RED
			TrafficSim.Light.YELLOW: c = YELLOW
		_heads.multimesh.set_instance_color(i, c)


func _rebuild() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	_rebuild_all()
	Terrain.shift = Vector2.ZERO


func _rebuild_all() -> void:
	var poles := []
	var arms := []
	var heads := []
	var stops := []
	var yields := []
	var blades := []
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_paint := false
	_head_ways.clear()
	var nodes := traffic.junctions.keys()
	nodes.sort()
	for n in nodes:
		var j: Dictionary = traffic.junctions[n]
		if j.control == TrafficSim.Rule.NONE:
			continue
		var named := false
		# How far back from the junction centre the cross street's sidewalk
		# runs: crosswalks line up with it, stop bars and signs sit behind it.
		var cross := 0.0
		for w2 in traffic.ways_into(n):
			cross = maxf(cross, RoadStyle.TYPES[traffic.ways[w2].type].width * 0.5)
		var walk := cross + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
		for wid in traffic.ways_into(n):
			var sl := traffic.stop_line(wid)
			var dir: Vector3 = sl.dir
			var right: Vector3 = sl.right
			var half: float = RoadStyle.TYPES[traffic.ways[wid].type].width * 0.5
			var back := walk + 1.8 + 1.2  # behind the crosswalk and the stop bar
			var base: Vector3 = sl.pos + right * sl.curb - dir * 1.0
			if not RoadStyle.TYPES[traffic.ways[wid].type].oneway:
				# On the near-side corner, in the grass strip beside the curb.
				base = sl.pos + right * (half + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5) - dir * back
			base = Terrain.lift(base)
			var face := Basis.looking_at(-dir, Vector3.UP)  # facing the drivers
			var stops_here: bool = j.control == TrafficSim.Rule.SIGNAL or j.control == TrafficSim.Rule.ALL_STOP \
				or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid) and j.sign != "yield")
			if stops_here and not RoadStyle.TYPES[traffic.ways[wid].type].oneway:
				_markings(paint, sl, half, walk)
				any_paint = true
			if j.control == TrafficSim.Rule.SIGNAL:
				poles.append(Transform3D(Basis().scaled(Vector3(1, POLE_H, 1)), base + Vector3(0, POLE_H * 0.5, 0)))
				# Mast arm out over the lanes, head above the middle lane.
				var out: float = (base - sl.pos).dot(right)
				var head: Vector3 = base + right * (sl.mid - out) + Vector3(0, POLE_H - 0.4, 0)
				var span: float = out - sl.mid
				arms.append(Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)).scaled(Vector3(span, 1, 1)),
					base + right * (-span * 0.5) + Vector3(0, POLE_H - 0.1, 0)))
				heads.append(Transform3D(face, head))
				_head_ways.append([n, wid])
			elif j.control == TrafficSim.Rule.ALL_STOP or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid)):
				var top := 2.13 + 0.38  # 7 ft to the bottom of the sign
				if not named:
					top = 3.35
				poles.append(Transform3D(Basis().scaled(Vector3(0.45, top, 0.45)), base + Vector3(0, top * 0.5, 0)))
				var sign_t := Transform3D(face, base + Vector3(0, 2.51, 0.0) + dir * -0.05)
				if not named:
					# Street-name blades crossing on top of the first post.
					named = true
					blades.append(Transform3D(Basis.looking_at(right, Vector3.UP), base + Vector3(0, 3.1, 0)))
					blades.append(Transform3D(Basis.looking_at(dir, Vector3.UP), base + Vector3(0, 3.3, 0)))
				if j.sign == "yield" and j.control == TrafficSim.Rule.PRIORITY:
					yields.append(sign_t)
				else:
					stops.append(sign_t)
	_fill(_poles, poles)
	_fill(_arms, arms)
	_fill(_heads, heads)
	_fill(_stops, stops)
	_fill(_yields, yields)
	_fill(_blades, blades)
	_paint.mesh = Terrain.drape(paint.commit(), false, 4.0) if any_paint else null


## A stop bar across the approach lanes and a pair of crosswalk lines across
## the whole street, just short of the junction.
## `walk` is the crosswalk's centre, metres back from the junction centre.
func _markings(st: SurfaceTool, sl: Dictionary, half: float, walk: float) -> void:
	var y := RoadStyle.Y_JUNCTION + 0.02
	var p: Vector3 = sl.pos
	var dir: Vector3 = sl.dir
	# Two 12 in lines, 6 ft apart (MUTCD 3B.18), then a 24 in stop bar 4 ft back.
	for k in [-0.9, 0.9]:
		var c: float = walk + k
		RoadMesh.add_strip(st, PackedVector3Array([p - dir * (c + 0.15), p - dir * (c - 0.15)]), -half, half, y)
	var bar := walk + 0.9 + 1.2
	RoadMesh.add_strip(st, PackedVector3Array([p - dir * (bar + 0.6), p - dir * bar]), 0.15, half - 0.2, y)


func _batch(mesh: Mesh, mat: Material, colors := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if mat != null:
		inst.material_override = mat
	add_child(inst)
	return inst


static func _fill(inst: MultiMeshInstance3D, xforms: Array) -> void:
	inst.multimesh.instance_count = xforms.size()
	for i in xforms.size():
		inst.multimesh.set_instance_transform(i, xforms[i])
		if inst.multimesh.use_colors:
			inst.multimesh.set_instance_color(i, GREEN)


static func _cylinder(r: float, h: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## A flat sign plate facing -Z with the given number of corners.
static func _plate(r: float, corners: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for k in corners:
		# Octagons sit flat on top; the yield triangle points down.
		var a := TAU * k / corners + (PI / corners if corners == 8 else -PI * 0.5)
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for k in corners:
		for face in [[Vector3.ZERO, pts[k], pts[(k + 1) % corners]], [Vector3.ZERO, pts[(k + 1) % corners], pts[k]]]:
			for v in face:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## The octagon: a textured face toward -Z and a grey back.
static func _sign_mesh(r: float, face: Material, back: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for side in [0, 1]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var z := 0.0 if side == 0 else 0.015
		var pts := []
		for k in 8:
			var a := TAU * k / 8 + PI / 8
			pts.append(Vector2(cos(a), sin(a)))
		for k in 8:
			var tri := [Vector2.ZERO, pts[k], pts[(k + 1) % 8]]
			if side == 0:
				tri = [Vector2.ZERO, pts[(k + 1) % 8], pts[k]]
			for v in tri:
				st.set_normal(Vector3(0, 0, -1) if side == 0 else Vector3(0, 0, 1))
				st.set_uv(Vector2(0.5 - v.x * 0.5, 0.5 - v.y * 0.5))
				st.add_vertex(Vector3(v.x * r, v.y * r, z))
		st.commit(mesh)
		mesh.surface_set_material(side, face if side == 0 else back)
	return mesh


## A 64 px STOP face: red octagon field, white border, white letters.
static func _stop_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var red := Color(0.72, 0.05, 0.06)
	var white := Color(0.95, 0.95, 0.93)
	for y in n:
		for x in n:
			var q := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			# Distance to the octagon's edge (apothem 0.924 of the radius).
			var d := maxf(maxf(absf(q.x), absf(q.y)), (absf(q.x) + absf(q.y)) * 0.7071)
			img.set_pixel(x, y, white if d > 0.84 else red)
	# Letters, 5 x 7 px each, scaled 2x, centred.
	var font := {
		"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	}
	var x0 := 32 - (4 * 6 * 2 - 2) / 2
	var y0 := 32 - 7
	var i := 0
	for ch in "STOP":
		var rows: Array = font[ch]
		for ry in 7:
			for rx in 5:
				if rows[ry][rx] == "1":
					for sy in 2:
						for sx in 2:
							img.set_pixel(x0 + i * 12 + rx * 2 + sx, y0 + ry * 2 + sy, white)
		i += 1
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
