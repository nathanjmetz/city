extends SceneTree
## Crowd lab: a football stadium bowl filled with N people, every one dressed
## from their own seed (shirt, trousers, skin, hair, cap), cheering. Near
## people are a shaped body; far ones a few triangles with the same colours.
## Times the frame on the GPU and CPU from three camera spots.
## Run: godot [--rendering-method gl_compatibility] --resolution 1600x900
##        -s tools/scale/crowd_lab.gd -- N OUT_DIR TAG

const SEAT_W := 0.5      # 20 in seats
const ROW_D := 0.85      # row to row
const ROW_RISE := 0.38
const NEAR := 60.0       # metres: past this a person is the simple shape
const SHIRTS := [Color("#b3261e"), Color("#1d3f8f"), Color("#f2f2f2"), Color("#222222"), Color("#2e6b34"), Color("#e8a317"),
	Color("#6a2c86"), Color("#7a8a99"), Color("#c25d2a"), Color("#103a5c"), Color("#d6c7a8"), Color("#9c1b2f")]
const PANTS := [Color("#1e2a44"), Color("#2b2b2b"), Color("#5b4a3a"), Color("#3a4f6e"), Color("#7b6f5a"), Color("#1a1a1a")]
const SKIN := [Color("#f1c9a5"), Color("#e0ac85"), Color("#c68863"), Color("#8d5a3b"), Color("#5c3a24"), Color("#f6d9c0")]
const HAIR := [Color("#1b1410"), Color("#4a2e1a"), Color("#8a5a2b"), Color("#c9a464"), Color("#9a9a9a"), Color("#3a2414")]

const SHADER := """shader_type spatial;
// Vertex colour r marks the part: 0 legs, 0.33 body, 0.66 skin (head, hands), 1 hair/cap.
// INSTANCE_CUSTOM: shirt (rgb), trousers packed with skin and hair index in a.
uniform vec3 pants[6];
uniform vec3 skin[6];
uniform vec3 hair[6];
varying vec3 col;
vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
void vertex() {
	float part = COLOR.r;
	float code = INSTANCE_CUSTOM.a * 255.0;
	int pi = int(mod(code, 6.0));
	int si = int(mod(floor(code / 6.0), 6.0));
	int hi = int(mod(floor(code / 36.0), 6.0));
	vec3 shirt = INSTANCE_CUSTOM.rgb;
	col = part < 0.15 ? pants[pi] : part < 0.5 ? shirt : part < 0.8 ? skin[si] : hair[hi];
	col = lin(col);
	// Cheering: people stand and sit, arms up now and then, each on their own beat.
	float seed = INSTANCE_CUSTOM.r * 13.1 + INSTANCE_CUSTOM.g * 7.3 + code * 0.17;
	float beat = sin(TIME * 2.0 + seed * 6.28);
	if (COLOR.g > 0.5) { VERTEX.y += max(beat, 0.0) * 0.45; }
	VERTEX.y += max(sin(TIME * 0.7 + seed * 3.1), 0.0) * 0.08;
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
"""

var _n := 0
var _out := ""
var _tag := ""
var _frames := 0
var _spot := 0
var _times := []
var _cam: Camera3D
var _results := {}
const SPOTS := [["stands", Vector3(0, 30, 120), Vector3(0, 8, 0)], ["field", Vector3(30, 2, 15), Vector3(60, 12, 20)],
	["blimp", Vector3(0, 260, 220), Vector3(0, 0, 0)]]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_n = int(a[0])
	_out = a[1]
	_tag = a[2]
	var world := Node3D.new()
	root.add_child(world)
	_env(world)
	_field(world)
	var seats := _seats(_n)
	var near_mm := MultiMesh.new()
	var far_mm := MultiMesh.new()
	for mm in [near_mm, far_mm]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
	near_mm.mesh = _person(true)
	far_mm.mesh = _person(false)
	# Split by distance from the main camera spot (a real game re-splits as
	# the camera moves; here it's fixed per run, the cost is what we measure).
	var near := []
	var far := []
	var eye: Vector3 = SPOTS[0][1]
	for s in seats:
		(near if s[0].origin.distance_to(eye) < NEAR else far).append(s)
	near_mm.instance_count = near.size()
	far_mm.instance_count = far.size()
	for i in near.size():
		near_mm.set_instance_transform(i, near[i][0])
		near_mm.set_instance_custom_data(i, near[i][1])
	for i in far.size():
		far_mm.set_instance_transform(i, far[i][0])
		far_mm.set_instance_custom_data(i, far[i][1])
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("pants", PackedVector3Array(PANTS.map(func(c): return Vector3(c.r, c.g, c.b))))
	mat.set_shader_parameter("skin", PackedVector3Array(SKIN.map(func(c): return Vector3(c.r, c.g, c.b))))
	mat.set_shader_parameter("hair", PackedVector3Array(HAIR.map(func(c): return Vector3(c.r, c.g, c.b))))
	for mm in [near_mm, far_mm]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	world.add_child(_cam)
	_look(0)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("CROWD seats %d near %d far %d" % [seats.size(), near.size(), far.size()])


func _look(i: int) -> void:
	_cam.look_at_from_position(SPOTS[i][1], SPOTS[i][2], Vector3.UP)
	_cam.current = true


## Seats in an oval bowl around a 120 x 53 yd field (with end zones), rows
## stepping back and up, nearest rows first, until N people are seated.
func _seats(n: int) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var a0 := 70.0   # half length to the first row (m)
	var b0 := 42.0   # half width
	var row := 0
	while out.size() < n:
		var a := a0 + row * ROW_D
		var b := b0 + row * ROW_D
		var y := 2.0 + row * ROW_RISE + (6.0 if row > 40 else 0.0)  # an upper deck past row 40
		var per := int(PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b))) / SEAT_W)
		for k in per:
			if out.size() >= n:
				break
			var t := TAU * float(k) / per
			var p := Vector3(cos(t) * a, y, sin(t) * b)
			var face := -Vector3(p.x, 0, p.z).normalized()
			var xf := Transform3D(Basis.looking_at(face, Vector3.UP), p)
			# Their own clothes, from their own seed.
			var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
			if rng.randf() < 0.35:
				shirt = Color("#a0202a")  # home team colours
			var code := (rng.randi() % 6) + 6 * (rng.randi() % 6) + 36 * (rng.randi() % 6)
			out.append([xf, Color(shirt.r, shirt.g, shirt.b, code / 255.0)])
		row += 1
	return out


## A seated fan: legs, body, arms, head with hair. Near: shaped (about 300
## triangles); far: a handful of boxes (about 40).
func _person(near: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8 if near else 4
	_box(st, Vector3(0.36, 0.14, 0.45), Vector3(0, 0.45, -0.2), 0.0, false)       # thighs
	_box(st, Vector3(0.32, 0.45, 0.14), Vector3(0, 0.22, -0.4), 0.0, false)       # shins
	_box(st, Vector3(0.4, 0.55, 0.24), Vector3(0, 0.82, 0.0), 0.33, false)        # body
	for s in [-1.0, 1.0]:
		_box(st, Vector3(0.1, 0.5, 0.1), Vector3(s * 0.25, 0.82, -0.02), 0.33, true)  # arms (raise when cheering)
	_ball(st, Vector3(0, 1.22, 0.0), 0.11, 0.66, seg)                              # head
	_ball(st, Vector3(0, 1.28, 0.02), 0.115, 1.0, seg, true)                       # hair or cap
	return st.commit()


func _box(st: SurfaceTool, s: Vector3, c: Vector3, part: float, lifts: bool) -> void:
	var col := Color(part, 1.0 if lifts else 0.0, 0)
	var h := s * 0.5
	var faces := [[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(q[i])


func _ball(st: SurfaceTool, c: Vector3, r: float, part: float, seg: int, cap := false) -> void:
	var col := Color(part, 0, 0)
	for i in seg:
		for j in seg:
			var p := []
			for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + d[0]) / seg * (0.5 if cap else 1.0)
				var ph := TAU * float(j + d[1]) / seg
				p.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_normal(p[k])
				st.add_vertex(c + p[k] * r)


func _env(world: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)


func _field(world: Node3D) -> void:
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(110, 49)
	f.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#3d7a2e")
	f.material_override = m
	world.add_child(f)
	var bowl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	bowl.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("#8c8a85")
	bowl.material_override = bm
	bowl.scale = Vector3(68, 1.5, 40)
	bowl.position = Vector3(0, -0.8, 0)
	world.add_child(bowl)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames > 40 and _frames <= 160:
		var rid := root.get_viewport_rid()
		_times.append([RenderingServer.viewport_get_measured_render_time_gpu(rid),
			RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(), _d * 1000.0])
	if _frames == 160:
		var g := 0.0
		var c := 0.0
		var fr := 0.0
		for t in _times:
			g += t[0]
			c += t[1]
			fr += t[2]
		var name: String = SPOTS[_spot][0]
		_results[name] = {"gpu_ms": snappedf(g / _times.size(), 0.01), "cpu_ms": snappedf(c / _times.size(), 0.01),
			"frame_ms": snappedf(fr / _times.size(), 0.1)}
		root.get_viewport().get_texture().get_image().save_png("%s/crowd_%s_%d_%s.png" % [_out, _tag, _n, name])
		_times.clear()
		_spot += 1
		if _spot >= SPOTS.size():
			print("CROWD %s %d %s" % [_tag, _n, JSON.stringify(_results)])
			quit()
			return true
		_look(_spot)
		_frames = 0
	return false
