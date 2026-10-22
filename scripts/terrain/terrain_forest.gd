class_name TerrainForest
extends Node3D
## The real woods: wherever the land cover data shows tree cover, trees stand
## close enough for their crowns to touch, as in the oak-hickory woods of
## southern Indiana's hills and the sycamore and maple of its creek bottoms.
## Drawn in chunks around the camera, one MultiMesh each; farther than
## REACH the ground shader paints the canopy instead.
##
## Trees never stand in water or on the ground graded for roads and lots, and
## `blocked` (set by the game) clears them off fields, yards and the like.

const CHUNK := 256.0
const REACH := 1100.0
## Up close, crowns are built from a few lumps; farther out, one.
const NEAR := 380.0
## Metres between trees in full woods.
const SPACING := 9.5

const SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
varying vec3 tint;
varying vec3 world_pos;
varying float shade;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void vertex() {
	tint = lin(INSTANCE_CUSTOM.rgb);
	shade = COLOR.r;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Clumps of leaves catch the light; gaps between them are dark.
	float leaves = texture(noise_soft, world_pos.xz / 2.3 + world_pos.y / 3.1).r;
	float fine = texture(noise_soft, world_pos.xy / 0.9 + world_pos.z / 1.7).r;
	ALBEDO = tint * shade * (0.7 + 0.45 * leaves + 0.2 * fine) * 2.6;
	BACKLIGHT = ALBEDO * 0.45;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
"""

static var _mat: ShaderMaterial
static var _meshes := {}

var camera: Camera3D
## Optional: func(x, z) -> bool, true where trees must not grow (view coordinates).
var blocked := Callable()

var _chunks := {}  # Vector2i -> {near: bool, node: MultiMeshInstance3D}
var _first := true
var _refresh_pending := false


func setup(cam: Camera3D) -> void:
	camera = cam


## Clears and regrows the trees in a box (view coordinates).
func refresh(box: Rect2) -> void:
	for key in _chunks.keys():
		if Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK)).intersects(box):
			_chunks[key].node.queue_free()
			_chunks.erase(key)


## Regrows all the woods next frame (after many changes at once).
func refresh_soon() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		refresh_all.call_deferred()


func refresh_all() -> void:
	_refresh_pending = false
	for key in _chunks.keys():
		_chunks[key].node.queue_free()
	_chunks.clear()


func _process(_delta: float) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var f := _focus()
	var start := Time.get_ticks_msec()
	var r := ceili(REACH / CHUNK)
	var fc := Vector2i(floori(f.x / CHUNK), floori(f.y / CHUNK))
	var want := {}
	for cz in range(fc.y - r, fc.y + r + 1):
		for cx in range(fc.x - r, fc.x + r + 1):
			var key := Vector2i(cx, cz)
			var d := (Vector2(key) * CHUNK + Vector2(CHUNK, CHUNK) * 0.5).distance_to(f)
			if d < REACH:
				want[key] = d < NEAR
	for key in _chunks.keys():
		if not want.has(key):
			_chunks[key].node.queue_free()
			_chunks.erase(key)
	var todo := []
	for key in want:
		if not _chunks.has(key) or _chunks[key].near != want[key]:
			todo.append([(Vector2(key) * CHUNK).distance_to(f), key])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	for item in todo:
		_build(item[1], want[item[1]])
		# All at once the first time, so the woods are there when the game opens.
		if not _first and Time.get_ticks_msec() - start > 5:
			break
	_first = false


func _focus() -> Vector2:
	var t := camera.global_transform
	var fwd := -t.basis.z
	var h := maxf(t.origin.y - Terrain.ground_y(t.origin.x, t.origin.z), 1.0)
	var flat := Vector2(fwd.x, fwd.z)
	if fwd.y < -0.05 and flat.length() > 0.001:
		return Vector2(t.origin.x, t.origin.z) + flat.normalized() * minf(h / -fwd.y * flat.length(), 1500.0)
	return Vector2(t.origin.x, t.origin.z)


func _build(key: Vector2i, near: bool) -> void:
	if _chunks.has(key):
		_chunks[key].node.queue_free()
	var xforms := []
	var tints := []
	var kinds := []
	var o := Vector2(key) * CHUNK
	var n := int(CHUNK / SPACING)
	var vo := Terrain.view_origin
	for j in n:
		for i in n:
			# The same trees every time, on every machine.
			var gx := floori((o.x + vo.x) / SPACING) + i
			var gz := floori((o.y + vo.y) / SPACING) + j
			var h1 := _hash(gx, gz, 1)
			var x := o.x + (i + 0.15 + 0.7 * _hash(gx, gz, 2)) * SPACING
			var z := o.y + (j + 0.15 + 0.7 * _hash(gx, gz, 3)) * SPACING
			var cov := Terrain.cover(x + vo.x, z + vo.y)
			if h1 > smoothstep(0.2, 0.7, cov.r) or cov.g > 0.12:
				continue
			if Terrain.flat_weight(x, z) > 0.05:
				continue
			if blocked.is_valid() and blocked.call(x, z):
				continue
			var y := Terrain.ground_y(x, z)
			var s := 0.75 + 0.55 * _hash(gx, gz, 4)
			var conifer := _hash(gx, gz, 5) < 0.06
			var b := Basis(Vector3.UP, _hash(gx, gz, 6) * TAU).scaled(Vector3(s, s * (0.9 + 0.25 * _hash(gx, gz, 7)), s))
			xforms.append(Transform3D(b, Vector3(x, y - 0.3, z)))
			# Summer greens, from deep oak to the yellower green of sycamore.
			var g := _hash(gx, gz, 8)
			var tint := Color("#47662a").lerp(Color("#6b8530"), g) if not conifer else Color("#33503a")
			tints.append(tint.darkened(0.15 * _hash(gx, gz, 9)))
			kinds.append(conifer)
	var node := Node3D.new()
	add_child(node)
	_chunks[key] = {"near": near, "node": node}
	for conifer in [false, true]:
		var count := 0
		for k in kinds:
			if k == conifer:
				count += 1
		if count == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = tree_mesh(conifer, near)
		mm.instance_count = count
		var at := 0
		for k in kinds.size():
			if kinds[k] != conifer:
				continue
			mm.set_instance_transform(at, xforms[k])
			mm.set_instance_custom_data(at, tints[k])
			at += 1
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)


static func _hash(x: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h % 100003) / 100002.0


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_mat.shader = sh
		_mat.set_shader_parameter("noise_soft", Ground.noise(256, 0.05, 3, 53))
	return _mat


## A woodland tree about 18 m tall with a crown 10 m across. Shade (vertex
## colour) darkens the underside and inside of the crown and the trunk.
static func tree_mesh(conifer: bool, near: bool) -> ArrayMesh:
	var key := [conifer, near]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if conifer else 3
	# Trunk (too thin to see from far off).
	if near:
		_prism(st, Vector3.ZERO, Vector3(0, 9.0 if not conifer else 4.0, 0), 0.35, 0.22, 5, 0.25)
	if conifer:
		# Eastern red cedar: a narrow dark cone.
		_cone(st, Vector3(0, 1.5, 0), 13.0, 2.6, 10 if near else 6)
	else:
		var lumps := [[Vector3(0, 12.5, 0), Vector3(4.8, 4.2, 4.8)]]
		if near:
			lumps = []
			for k in 4:
				var a := TAU * k / 4.0 + rng.randf() * 0.5
				var c := Vector3(cos(a) * 2.4, 11.0 + rng.randf() * 2.5, sin(a) * 2.4)
				lumps.append([c, Vector3(3.2, 2.8, 3.2) * (0.85 + rng.randf() * 0.3)])
			lumps.append([Vector3(0, 14.5, 0), Vector3(3.0, 2.6, 3.0)])
		for l in lumps:
			_blob(st, l[0], l[1], 1)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## A lumpy ellipsoid from a subdivided octahedron, normals pointing out.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, subdiv: int) -> void:
	var tris := [
		[Vector3.UP, Vector3.FORWARD, Vector3.RIGHT], [Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.UP, Vector3.BACK, Vector3.LEFT], [Vector3.UP, Vector3.LEFT, Vector3.FORWARD],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD], [Vector3.DOWN, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.LEFT, Vector3.BACK], [Vector3.DOWN, Vector3.FORWARD, Vector3.LEFT]]
	for s in subdiv:
		var out := []
		for t in tris:
			var ab: Vector3 = (t[0] + t[1]).normalized()
			var bc: Vector3 = (t[1] + t[2]).normalized()
			var ca: Vector3 = (t[2] + t[0]).normalized()
			out.append_array([[t[0], ab, ca], [ab, t[1], bc], [ca, bc, t[2]], [ab, bc, ca]])
		tris = out
	for t in tris:
		for v in t:
			var d: Vector3 = v
			var bump := 1.0 + 0.12 * sin(d.x * 7.0 + d.z * 5.0) * cos(d.y * 6.0)
			# Darker underneath, where the crown shades itself.
			st.set_color(Color(lerpf(0.55, 1.05, clampf(d.y * 0.5 + 0.5, 0.0, 1.0)), 0, 0))
			st.set_normal(Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized())
			st.add_vertex(c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * bump)


static func _cone(st: SurfaceTool, base: Vector3, h: float, r: float, sides: int) -> void:
	var top := base + Vector3(0, h, 0)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var n := Vector3(cos((a0 + a1) * 0.5), r / h, sin((a0 + a1) * 0.5)).normalized()
		st.set_normal(n)
		st.set_color(Color(1.0, 0, 0))
		st.add_vertex(top)
		st.set_color(Color(0.6, 0, 0))
		st.add_vertex(p1)
		st.add_vertex(p0)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(base + Vector3(0, -0.5, 0))


static func _prism(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, shade: float) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		st.set_color(Color(shade, 0, 0))
		st.set_normal((d0 + d1).normalized())
		for v in [a + d0 * r0, b + d0 * r1, a + d1 * r0, a + d1 * r0, b + d0 * r1, b + d1 * r1]:
			st.add_vertex(v)
