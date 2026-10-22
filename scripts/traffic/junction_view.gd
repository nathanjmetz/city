class_name JunctionView
extends Node3D
## Traffic lights on mast arms, stop signs and yield signs at every
## junction, drawn in a few batches. Lights change colour as they cycle.

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
	# Octagon, 30 in across (MUTCD R1-1); triangle, 36 in (R1-2).
	_stops = _batch(_plate(0.38, 8), red_sign)
	_yields = _batch(_plate(0.5, 3), red_sign)


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
	_head_ways.clear()
	var nodes := traffic.junctions.keys()
	nodes.sort()
	for n in nodes:
		var j: Dictionary = traffic.junctions[n]
		if j.control == TrafficSim.Rule.NONE:
			continue
		for wid in traffic.ways_into(n):
			var sl := traffic.stop_line(wid)
			var dir: Vector3 = sl.dir
			var right: Vector3 = sl.right
			var base: Vector3 = Terrain.lift(sl.pos + right * sl.curb - dir * 1.0)
			var face := Basis.looking_at(-dir, Vector3.UP)  # facing the drivers
			if j.control == TrafficSim.Rule.SIGNAL:
				poles.append(Transform3D(Basis().scaled(Vector3(1, POLE_H, 1)), base + Vector3(0, POLE_H * 0.5, 0)))
				# Mast arm out over the lanes, head above the middle lane.
				var head: Vector3 = Terrain.lift(sl.pos + right * sl.mid - dir * 1.0) + Vector3(0, POLE_H - 0.4, 0)
				var span: float = sl.curb - sl.mid
				arms.append(Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)).scaled(Vector3(span, 1, 1)),
					base + right * (-span * 0.5) + Vector3(0, POLE_H - 0.1, 0)))
				heads.append(Transform3D(face, head))
				_head_ways.append([n, wid])
			elif j.control == TrafficSim.Rule.ALL_STOP or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid)):
				poles.append(Transform3D(Basis().scaled(Vector3(0.5, 2.2, 0.5)), base + Vector3(0, 1.1, 0)))
				var sign_t := Transform3D(face, base + Vector3(0, 2.2, 0))
				if j.sign == "yield" and j.control == TrafficSim.Rule.PRIORITY:
					yields.append(sign_t)
				else:
					stops.append(sign_t)
	_fill(_poles, poles)
	_fill(_arms, arms)
	_fill(_heads, heads)
	_fill(_stops, stops)
	_fill(_yields, yields)


func _batch(mesh: Mesh, mat: Material, colors := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
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
