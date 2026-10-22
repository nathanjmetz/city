class_name FlowView
extends MeshInstance3D
## The traffic info view, like Cities: Skylines: each side of every road
## coloured by how close cars get to the speed limit there. Green flows,
## yellow slows, red is jammed.

const GOOD := Color(0.2, 0.85, 0.35)
const SLOW := Color(1.0, 0.8, 0.15)
const BAD := Color(0.95, 0.2, 0.15)

var traffic: TrafficSim
var _wait := 0.0


func setup(t: TrafficSim) -> void:
	traffic = t


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(delta: float) -> void:
	if not visible or traffic == null:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.4
	_rebuild()


static func color_for(speed: float) -> Color:
	if speed >= 0.75:
		return GOOD.lerp(SLOW, (1.0 - speed) / 0.25 * 0.3)
	if speed >= 0.4:
		return SLOW.lerp(BAD, (0.75 - speed) / 0.35 * 0.6)
	return BAD


func _rebuild() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for wid in traffic.ways:
		var w: Dictionary = traffic.ways[wid]
		var pts: PackedVector3Array = w.pts
		var offs: PackedFloat32Array = w.offs
		var inner: float = offs[0] - TrafficSim.LANE_W * 0.4
		var outer: float = offs[offs.size() - 1] + TrafficSim.LANE_W * 0.4
		var col := color_for(traffic.way_speed(wid))
		col.a = 0.6
		st.set_color(col)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var dir := b - a
			dir.y = 0.0
			if dir.length() < 0.001:
				continue
			dir = dir.normalized()
			var right := Vector3(-dir.z, 0.0, dir.x)
			var lift := Vector3(0, 0.3, 0)
			var q := [a + right * inner + lift, a + right * outer + lift, b + right * inner + lift, b + right * outer + lift]
			for k in [0, 1, 2, 2, 1, 3]:
				st.add_vertex(q[k])
			any = true
	mesh = st.commit() if any else null
