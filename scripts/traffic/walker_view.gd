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
	Color(0.12, 0.12, 0.14), Color(0.7, 0.75, 0.82), Color(0.78, 0.45, 0.42),
	Color(0.95, 0.95, 0.93), Color(0.2, 0.55, 0.62), Color(0.82, 0.74, 0.3), Color(0.45, 0.28, 0.18),
	Color(0.9, 0.5, 0.62), Color(0.3, 0.2, 0.42), Color(0.5, 0.6, 0.35), Color(0.75, 0.2, 0.3)]

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
		var p: Vector3 = Terrain.stand(pose[0])
		if p.distance_to(eye) > FAR:
			continue
		if n >= _mm.instance_count:
			_mm.instance_count = maxi(n * 2, 64)
		var dir: Vector3 = pose[1]
		if dir.length() < 0.5:
			dir = Vector3.FORWARD
		var body := build(int(w.person))
		_mm.set_instance_transform(n, Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, dir.z).normalized(), Vector3.UP).scaled(body), p))
		_mm.set_instance_color(n, skin_tone(int(w.person)))
		# Standing at the kerb, the phase stays put: feet together if it's 0.
		var shirt: Color = SHIRTS[(hash(int(w.person)) >> 4) % SHIRTS.size()]
		# Stride grows with height (about 0.41 of it in a walk), and each
		# person's own gait a little longer or shorter, so a crowd doesn't
		# step in time.
		var stride: float = STRIDE * body.y * (0.92 + float((hash(int(w.person)) >> 12) & 15) / 15.0 * 0.16)
		shirt.a = fposmod(float(pose[2]), stride) / stride
		_mm.set_instance_custom_data(n, shirt)
		n += 1
	_mm.visible_instance_count = n


## Skin tones as a tint on the figure (it darkens or lightens the skin; the
## clothes a touch with it), weighted roughly like Grant County, Indiana
## (Census 2020: about 85% white, 8% Black, 5% Hispanic, 2% other).
const SKIN_TONES := [[Color(1.22, 1.18, 1.15), 30], [Color(1.12, 1.06, 1.02), 30], [Color(1.0, 1.0, 1.0), 25],
	[Color(0.86, 0.82, 0.8), 6], [Color(0.66, 0.6, 0.58), 5], [Color(0.48, 0.43, 0.42), 4]]


static func skin_tone(person: int) -> Color:
	var roll := (hash([person, "skin"]) & 0xffff) % 100
	for t in SKIN_TONES:
		roll -= int(t[1])
		if roll < 0:
			return t[0]
	return Color.WHITE


## Each person's own height and build, the same every time they're seen:
## adults from short to tall and slight to heavy, and about one in eight a
## child (US adults run roughly 1.5 to 1.9 m; the mesh is 1.7 m).
static func build(person: int) -> Vector3:
	var h := hash(person)
	var tall := 0.9 + float(h & 255) / 255.0 * 0.2
	var wide := 0.85 + float((h >> 8) & 255) / 255.0 * 0.45
	if (h >> 16) % 8 == 0:
		tall = 0.6 + float((h >> 20) & 15) / 15.0 * 0.15
		wide = 0.75 + float((h >> 24) & 15) / 15.0 * 0.15
	return Vector3(wide, tall, lerpf(wide, 1.0, 0.4))


## A person about 1.7 m tall: legs, arms, body and head, coloured by the
## shirt. Each arm swings with the opposite leg, as people walk.
static func _person_mesh() -> Mesh:
	# A person about 1.7 m tall in real proportions (step one away from
	# toy blocks, Nathan 2026-10-25: "they currently look like Legos or
	# Roblox"): tapered round limbs, a pelvis and a chest broader at the
	# shoulders, a neck, an oval head with hair, hands and shoes.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trousers := Color(0.2, 0.22, 0.3)
	var skin := Color(0.66, 0.47, 0.36)
	var hair := Color(0.16, 0.11, 0.07)
	var shoe := Color(0.12, 0.11, 0.1)
	var shirt := Color(1, 1, 1, 0)
	const HIP := 0.88
	const SHOULDER := 1.4
	for side in [-1.0, 1.0]:
		var x: float = side * 0.095
		var leg := Vector2(-side, HIP)  # each leg swings opposite its arm
		_limb(st, Vector3(x, HIP, 0.0), Vector3(x, 0.47, 0.0), Vector2(0.078, 0.082), Vector2(0.055, 0.058), trousers, leg)
		_limb(st, Vector3(x, 0.47, 0.0), Vector3(x, 0.08, 0.0), Vector2(0.052, 0.056), Vector2(0.038, 0.042), trousers, leg)
		_box(st, Vector3(x, 0.04, -0.035), Vector3(0.048, 0.04, 0.12), shoe, leg)
		var ax: float = side * 0.215
		var arm := Vector2(side, SHOULDER)
		_limb(st, Vector3(ax, SHOULDER, 0.0), Vector3(side * 0.235, 1.12, 0.0), Vector2(0.05, 0.052), Vector2(0.043, 0.045), shirt, arm)
		_limb(st, Vector3(side * 0.235, 1.12, 0.0), Vector3(side * 0.245, 0.86, -0.01), Vector2(0.04, 0.042), Vector2(0.032, 0.034), skin, arm)
		_blob(st, Vector3(side * 0.247, 0.81, -0.012), Vector3(0.032, 0.05, 0.042), skin, arm, 6, 4)
	# Hips and pelvis in the trousers, then the shirt up to the shoulders.
	_limb(st, Vector3(0.0, 0.84, 0.0), Vector3(0.0, 1.0, 0.0), Vector2(0.175, 0.112), Vector2(0.158, 0.104), trousers)
	_limb(st, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.27, 0.0), Vector2(0.158, 0.104), Vector2(0.19, 0.115), shirt)
	_limb(st, Vector3(0.0, 1.27, 0.0), Vector3(0.0, 1.41, 0.0), Vector2(0.19, 0.115), Vector2(0.215, 0.105), shirt, Vector2.ZERO, 8)
	_limb(st, Vector3(0.0, 1.41, 0.0), Vector3(0.0, 1.46, 0.0), Vector2(0.215, 0.105), Vector2(0.09, 0.07), shirt, Vector2.ZERO, 8)  # shoulders slope in to the neck
	_limb(st, Vector3(0.0, 1.45, 0.0), Vector3(0.0, 1.54, 0.0), Vector2(0.05, 0.052), Vector2(0.046, 0.048), skin)
	_blob(st, Vector3(0.0, 1.625, -0.005), Vector3(0.082, 0.108, 0.098), skin, Vector2.ZERO, 8, 6)
	# Hair over the crown and back of the head; the face stays bare.
	_blob(st, Vector3(0.0, 1.665, 0.022), Vector3(0.091, 0.092, 0.1), hair, Vector2.ZERO, 8, 6)
	st.generate_normals()
	return st.commit()


## A tapered round limb (an elliptical frustum) from `a` to `b`, with radii
## `ra` and `rb` (x across, z front to back), capped at both ends.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, col: Color,
		swing := Vector2.ZERO, sides := 6) -> void:
	var ring_a := []
	var ring_b := []
	for i in sides:
		var t := TAU * i / sides
		ring_a.append(a + Vector3(cos(t) * ra.x, 0.0, sin(t) * ra.y))
		ring_b.append(b + Vector3(cos(t) * rb.x, 0.0, sin(t) * rb.y))
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, [ring_a[i], ring_b[i], ring_b[j]], col, swing)
		_tri(st, [ring_a[i], ring_b[j], ring_a[j]], col, swing)
		_tri(st, [a, ring_a[i], ring_a[j]], col, swing)
		_tri(st, [b, ring_b[j], ring_b[i]], col, swing)


## A rounded blob (an ellipsoid) for heads, hair, hands and shoulders.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, swing := Vector2.ZERO,
		around := 8, up := 6) -> void:
	for i in up:
		var v0 := PI * i / up - PI * 0.5
		var v1 := PI * (i + 1) / up - PI * 0.5
		for k in around:
			var u0 := TAU * k / around
			var u1 := TAU * (k + 1) / around
			var p := func(u: float, v: float) -> Vector3:
				return c + Vector3(cos(v) * cos(u) * r.x, sin(v) * r.y, cos(v) * sin(u) * r.z)
			_tri(st, [p.call(u0, v0), p.call(u0, v1), p.call(u1, v1)], col, swing)
			_tri(st, [p.call(u0, v0), p.call(u1, v1), p.call(u1, v0)], col, swing)


static func _tri(st: SurfaceTool, pts: Array, col: Color, swing: Vector2) -> void:
	for q in pts:
		st.set_color(col)
		st.set_uv(swing)
		st.add_vertex(q)


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
