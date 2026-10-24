class_name WalkerView
extends Node3D
## Draws people out walking: on the sidewalk, crossing at corners, from the
## car to the door. Everyone is simulated; only those near the camera are
## drawn, like Cities: Skylines' pedestrians. Legs and arms swing in the
## vertex shader, in step with the distance walked, so feet don't slide.

## Metres from the camera beyond which walkers aren't drawn.
const FAR := 320.0
## Metres a person covers in one full walk cycle (two steps). A typical adult
## step is about 0.7 m at 1.3-1.4 m/s (Fruin, Pedestrian Planning and Design).
const STRIDE := 1.4
const SHIRTS := [Color(0.62, 0.16, 0.14), Color(0.16, 0.3, 0.55), Color(0.85, 0.82, 0.74),
	Color(0.24, 0.42, 0.26), Color(0.9, 0.62, 0.2), Color(0.35, 0.35, 0.38), Color(0.55, 0.38, 0.6),
	Color(0.12, 0.12, 0.14), Color(0.7, 0.75, 0.82), Color(0.78, 0.45, 0.42)]

var traffic: TrafficSim
var tick_fraction: Callable
var _mm: MultiMesh


func setup(t: TrafficSim, fraction: Callable) -> void:
	traffic = t
	tick_fraction = fraction


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	# White instance colours: the browser's renderer multiplies vertex COLOR
	# by the instance colour even without use_colors, and that is black.
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _person_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	# The shirt (vertex alpha 0) takes each person's own colour. Each limb
	# swings about its hip or shoulder (UV.y) one way or the other (UV.x),
	# by the walk phase in the instance's custom alpha. The body dips as the
	# legs spread, so the feet stay on the ground.
	mat.shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 tint;
// The Compatibility renderer (the browser) hands INSTANCE_CUSTOM's rgb
// over as if it were an sRGB colour, already turned linear (alpha comes
// through as is); undo that so custom data reads as on the desktop.
vec4 custom_data(vec4 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c.rgb = mix(c.rgb * 12.92, 1.055 * pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c.rgb));
#endif
	return c;
}
void vertex() {
	vec4 custom = custom_data(INSTANCE_CUSTOM);
	tint = mix(custom.rgb, COLOR.rgb, COLOR.a);
	float ph = custom.a * 6.2831853;
	float a = UV.x * 0.42 * sin(ph);
	float c = cos(a);
	float s = sin(a);
	float y = VERTEX.y - UV.y;
	VERTEX.yz = vec2(UV.y + y * c - VERTEX.z * s, y * s + VERTEX.z * c);
	NORMAL.yz = vec2(NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
	VERTEX.y -= 0.84 * (1.0 - cos(0.42 * sin(ph)));  // keeps the feet on the ground
}
void fragment() { ALBEDO = tint; ROUGHNESS = 0.9; }
"""
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(_delta: float) -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	_draw_walkers()
	Terrain.shift = Vector2.ZERO


func _draw_walkers() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var frac: float = tick_fraction.call()
	var n := 0
	for w in traffic.walkers:
		var pose := traffic.walker_pose(w, frac)
		var p: Vector3 = Terrain.lift(pose[0])
		if p.distance_to(eye) > FAR:
			continue
		if n >= _mm.instance_count:
			_mm.instance_count = maxi(n * 2, 64)
		var dir: Vector3 = pose[1]
		if dir.length() < 0.5:
			dir = Vector3.FORWARD
		_mm.set_instance_transform(n, Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, dir.z).normalized(), Vector3.UP), p))
		_mm.set_instance_color(n, Color.WHITE)
		# Standing at the kerb, the phase stays put: feet together if it's 0.
		var shirt: Color = SHIRTS[int(w.person) % SHIRTS.size()]
		shirt.a = fposmod(float(pose[2]), STRIDE) / STRIDE
		_mm.set_instance_custom_data(n, shirt)
		n += 1
	_mm.visible_instance_count = n


## A person about 1.7 m tall: legs, arms, body and head, coloured by the
## shirt. Each arm swings with the opposite leg, as people walk.
static func _person_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trousers := Color(0.2, 0.22, 0.3)
	var skin := Color(0.85, 0.68, 0.55)
	var shirt := Color(1, 1, 1, 0)
	const HIP := 0.84
	const SHOULDER := 1.38
	_box(st, Vector3(-0.11, 0.42, 0.0), Vector3(0.08, 0.42, 0.09), trousers, Vector2(1.0, HIP))
	_box(st, Vector3(0.11, 0.42, 0.0), Vector3(0.08, 0.42, 0.09), trousers, Vector2(-1.0, HIP))
	_box(st, Vector3(0.0, 1.13, 0.0), Vector3(0.21, 0.3, 0.12), shirt)
	_box(st, Vector3(0.0, 1.57, 0.0), Vector3(0.1, 0.12, 0.11), skin)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.265
		_box(st, Vector3(x, 1.22, 0.0), Vector3(0.05, 0.16, 0.055), shirt, Vector2(side, SHOULDER))  # sleeve
		_box(st, Vector3(x, 0.93, 0.0), Vector3(0.045, 0.13, 0.05), skin, Vector2(side, SHOULDER))
	st.generate_normals()
	return st.commit()


## A box; `swing` is the limb's swing direction (0 for none) and pivot height.
static func _box(st: SurfaceTool, c: Vector3, h: Vector3, col: Color, swing := Vector2.ZERO) -> void:
	var corners := []
	for i in 8:
		corners.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for t in [[0, 1, 2], [0, 2, 3]]:
			for k in t:
				st.set_color(col)
				st.set_uv(swing)
				st.add_vertex(corners[f[k]])
