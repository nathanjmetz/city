class_name TerrainView
extends Node3D
## Draws the land: ground, rivers and lakes, in square chunks streamed in
## around the camera, finer up close and coarser far away, like Cities:
## Skylines 2's terrain. Detail falls off smoothly with distance, the way the
## eye sees it: each vertex slides toward the next coarser level as it gets
## farther from the camera (geomorphing), so by the time a chunk switches to
## the coarser mesh it already looks exactly like it, and nothing pops.
## Trees are WildView's; past them the ground paints the woods' canopy.
##
## Benchmark: aerial photos of the White River valley near Petersburg,
## Indiana: tan and green crop fields, dark wooded hills and creek bottoms,
## a muddy green-brown river with bare sandy banks.
##
## It also grades the ground flat under roads and the lots along them, so
## roads sit on the land instead of cutting into it.

const CHUNK := 512.0
## Grid spacing for each level of detail, and how far each one reaches.
const STEPS := [8.0, 16.0, 32.0, 64.0, 128.0]
const REACH := [700.0, 1400.0, 2800.0, 5600.0, 9000.0]
## A chunk goes finer once it is MORPH_END of its reach away, and coarser
## only past HYST_OUT; its vertices finish morphing by MORPH_END, so the
## switch is seamless both ways.
const MORPH_END := 0.9
const HYST_OUT := 0.95
## Ground graded flat this far each side of a road with lots (curb, walk,
## and the 32 m lots), fading out over the next few metres.
const LOT_GRADE := 34.0
const GRADE_FADE := 14.0
## Mowed grass past a road's right of way before the wild cover starts.
const MOW_VERGE := 3.0
## Milliseconds per frame spent building chunks after the first frame.
const BUDGET_MS := 6

const SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
uniform vec4 lush : source_color = vec4(0.29, 0.38, 0.17, 1.0);
uniform vec4 dry : source_color = vec4(0.46, 0.46, 0.27, 1.0);
uniform vec4 dark : source_color = vec4(0.20, 0.28, 0.12, 1.0);
uniform vec4 soil : source_color = vec4(0.46, 0.40, 0.29, 1.0);
uniform vec4 crop_green : source_color = vec4(0.36, 0.45, 0.17, 1.0);
uniform vec4 crop_corn : source_color = vec4(0.25, 0.37, 0.13, 1.0);
uniform vec4 crop_tan : source_color = vec4(0.55, 0.47, 0.30, 1.0);
uniform vec4 tilled : source_color = vec4(0.40, 0.33, 0.24, 1.0);
uniform vec4 litter : source_color = vec4(0.22, 0.20, 0.12, 1.0);
uniform vec4 canopy : source_color = vec4(0.13, 0.22, 0.09, 1.0);
uniform vec4 spoil : source_color = vec4(0.52, 0.49, 0.43, 1.0);
uniform vec4 mud : source_color = vec4(0.42, 0.37, 0.27, 1.0);
// Where wild trees are drawn (WildView): centre x, z and reach. Past them
// the woods are painted as canopy.
global uniform vec4 tree_fade;
// The camera's x, height above the ground, z: level of detail is measured
// from it the way TerrainView picks chunk detail.
uniform vec3 lod_eye;
// CUSTOM0: (height, normal x, normal z) on the next coarser level, and w the
// reach of this chunk's level (0 for the coarsest): vertices slide to the
// coarser level between MORPH_START and MORPH_END of that reach.

varying vec3 world_pos;
varying vec4 cover;
varying float steep;

vec2 turn(vec2 p, float a) {
	return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}

void vertex() {
	vec2 d = VERTEX.xz - lod_eye.xz;
	float morph = CUSTOM0.w > 0.0 ? smoothstep(CUSTOM0.w * 0.5, CUSTOM0.w * 0.9, sqrt(dot(d, d) + lod_eye.y * lod_eye.y)) : 0.0;
	VERTEX.y = mix(VERTEX.y, CUSTOM0.x, morph);
	vec3 coarse = vec3(CUSTOM0.y, sqrt(max(1.0 - CUSTOM0.y * CUSTOM0.y - CUSTOM0.z * CUSTOM0.z, 0.0)), CUSTOM0.z);
	NORMAL = normalize(mix(NORMAL, coarse, morph));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cover = COLOR;
	steep = 1.0 - NORMAL.y;
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(VERTEX);
	float big = texture(noise_soft, p / 900.0).r;
	float mid = texture(noise_soft, turn(p, 1.1) / 210.0 + 0.31).r;
	float clump = texture(noise_soft, turn(p, 2.3) / 19.0 + 0.62).r;
	float grain = texture(noise_grain, turn(p, 0.7) / 3.1).r;
	float blades = texture(noise_grain, turn(p, 2.9) / 0.6 + 0.5).r;
	float fade = clamp(1.0 - dist / 180.0, 0.0, 1.0);

	// Pasture and lawn: the grass of the old ground.
	float dryness = smoothstep(0.42, 0.78, big * 0.55 + mid * 0.45);
	vec3 col = mix(lush.rgb, dry.rgb, dryness * 0.75);
	col = mix(col, dark.rgb, smoothstep(0.35, 0.9, clump) * 0.35);

	// Crop fields: whole fields of one crop, a quarter mile across, in green
	// beans, tan corn stubble or tilled soil, with rows running north-south
	// (the township grid) that fade with distance.
	vec2 field = floor(p / 402.0);
	float pick = fract(sin(dot(field, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 crop = pick < 0.45 ? crop_green.rgb : (pick < 0.8 ? crop_corn.rgb : (pick < 0.92 ? crop_tan.rgb : tilled.rgb));
	crop *= 0.9 + 0.2 * mid;
	float rows = sin(p.x * 8.27) * 0.5 + 0.5;
	crop *= 1.0 - rows * 0.12 * clamp(1.0 - dist / 300.0, 0.0, 1.0);
	col = mix(col, crop, smoothstep(0.3, 0.7, cover.b) * 0.92);

	// Woods: leaf litter under the trees up close; from far off, where the
	// trees aren't drawn, the canopy itself, lumpy with crowns.
	float crowns = texture(noise_soft, p / 11.0).r * 0.6 + clump * 0.4;
	vec3 tops = canopy.rgb * (0.65 + 0.7 * crowns) * (0.85 + 0.3 * big);
	float painted = smoothstep(tree_fade.z * 0.72, tree_fade.z * 0.97, distance(p, tree_fade.xy));
	vec3 woods = mix(litter.rgb * (0.8 + 0.4 * clump), tops, painted);
	// A ragged edge, as real woods have, not the straight line between samples.
	col = mix(col, woods, smoothstep(0.3, 0.65, cover.r + (clump - 0.5) * 0.45 + (mid - 0.5) * 0.25));

	// Strip mine spoil and gravel.
	col = mix(col, spoil.rgb * (0.85 + 0.3 * clump), smoothstep(0.3, 0.7, cover.a));
	// Muddy, sandy banks by the water.
	col = mix(col, mud.rgb * (0.9 + 0.2 * grain), smoothstep(0.03, 0.3, cover.g));
	// Worn, bare soil on steep banks.
	col = mix(col, soil.rgb * 0.9, smoothstep(0.2, 0.45, steep) * 0.6);

	col *= 1.0 + (grain - 0.5) * 0.4 * fade + (blades - 0.5) * 0.3 * fade * fade;
	ALBEDO = col;
	ROUGHNESS = 0.93;
	SPECULAR = 0.25;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
// A Midwest river: silty, green-brown, darker where deep.
uniform vec4 shallow : source_color = vec4(0.30, 0.31, 0.21, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.16, 0.12, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * 0.02;
	float a = texture(noise_soft, p / 37.0 + vec2(t, t * 0.6)).r;
	float b = texture(noise_soft, p / 13.0 - vec2(t * 0.7, t * 1.3)).r;
	float c = texture(noise_soft, p / 160.0 + vec2(t * 0.2, 0.0)).r;
	vec3 n = normalize(vec3((a - 0.5) * 0.35 + (b - 0.5) * 0.2, 1.0, (b - 0.5) * 0.35 - (a - 0.5) * 0.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(shallow.rgb, deep.rgb, 0.45 + 0.4 * c);
	ROUGHNESS = 0.08;
	SPECULAR = 0.55;
	METALLIC = 0.0;
}
"""

## The ground was regraded inside this box (view coordinates).
signal graded(box: Rect2)

static var _ground_mat: ShaderMaterial
static var _water_mat: ShaderMaterial

## The camera the chunks follow.
var camera: Camera3D
var network: RoadNetwork

## Vector2i chunk -> {lod, ground: MeshInstance3D, water: MeshInstance3D}
var _chunks := {}
var _dirty := {}  # Vector2i chunks to rebuild for grading
var _graded := {}  # segment id -> [points, inner, outer, bounds]
var _first := true


static func ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_ground_mat.shader = sh
		_ground_mat.set_shader_parameter("noise_soft", Ground.noise(512, 0.012, 4, 11))
		_ground_mat.set_shader_parameter("noise_grain", Ground.noise(256, 0.09, 2, 23))
	return _ground_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water_mat.shader = sh
		_water_mat.set_shader_parameter("noise_soft", Ground.noise(256, 0.02, 3, 41))
	return _water_mat


func setup(cam: Camera3D, net: RoadNetwork = null) -> void:
	camera = cam
	network = net
	if network != null:
		network.changed.connect(_regrade)
		_regrade()


## Where the chunks centre: the ground the camera looks at.
func focus() -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	var t := camera.global_transform
	var fwd := -t.basis.z
	var p := t.origin
	var ground := Terrain.ground_y(p.x, p.z)
	var h := maxf(p.y - ground, 1.0)
	var flat := Vector2(fwd.x, fwd.z)
	var reach := 0.0
	if fwd.y < -0.05:
		reach = minf(h / -fwd.y * flat.length(), 2000.0)
	return Vector2(p.x, p.z) + flat.normalized() * reach if flat.length() > 0.001 else Vector2(p.x, p.z)


func _process(_delta: float) -> void:
	var eye := _eye()
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("lod_eye", Vector3(eye.x, eye.z, eye.y))
	var flat_eye := Vector2(eye.x, eye.y)
	var start := Time.get_ticks_msec()
	# Wanted level of detail for every chunk in reach: finer once well
	# inside a level's reach, coarser only once well past it.
	var want := {}
	var r := ceili(REACH[REACH.size() - 1] / CHUNK)
	var fc := Vector2i(floori(eye.x / CHUNK), floori(eye.y / CHUNK))
	for cz in range(fc.y - r, fc.y + r + 1):
		for cx in range(fc.x - r, fc.x + r + 1):
			var key := Vector2i(cx, cz)
			var d := _chunk_distance(key, flat_eye, eye.z)
			if d >= REACH[REACH.size() - 1]:
				continue
			var have = _chunks.get(key)
			for lod in REACH.size():
				var edge: float = REACH[lod] * (HYST_OUT if have != null and have.lod <= lod else MORPH_END)
				if d < edge or lod == REACH.size() - 1:
					want[key] = lod
					break
	for key in _chunks.keys():
		if not want.has(key):
			_drop(key)
	# Nearest first.
	var todo := []
	for key in want:
		var have = _chunks.get(key)
		if have == null or have.lod != want[key] or _dirty.has(key):
			todo.append([_chunk_distance(key, flat_eye, eye.z), key])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	for item in todo:
		var key: Vector2i = item[1]
		_build(key, want[key])
		_dirty.erase(key)
		# Build everything at once the first time, so the land is there
		# when the game opens; then a little each frame.
		if not _first and Time.get_ticks_msec() - start > BUDGET_MS:
			break
	_first = false


## The camera's ground position and its height above the land: x, z, height.
func _eye() -> Vector3:
	if camera == null or not camera.is_inside_tree():
		return Vector3.ZERO
	var p := camera.global_position
	return Vector3(p.x, p.z, maxf(p.y - Terrain.ground_y(p.x, p.z), 1.0))


## How far a chunk's nearest point is from the camera, counting its height.
func _chunk_distance(key: Vector2i, f: Vector2, height := 0.0) -> float:
	var r := Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))
	var dx := maxf(maxf(r.position.x - f.x, f.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - f.y, f.y - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz + height * height)


func _drop(key: Vector2i) -> void:
	var c: Dictionary = _chunks[key]
	for k in ["ground", "water"]:
		if c[k] != null:
			c[k].queue_free()
	_chunks.erase(key)


func _build(key: Vector2i, lod: int) -> void:
	if _chunks.has(key):
		_drop(key)
	var meshes := build_chunk(Vector2(key) * CHUNK, CHUNK, STEPS[lod], REACH[lod] if lod < STEPS.size() - 1 else 0.0)
	var entry := {"lod": lod, "ground": null, "water": null}
	var g := MeshInstance3D.new()
	g.mesh = meshes[0]
	g.material_override = ground_material()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod > 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(g)
	entry.ground = g
	if meshes[1] != null:
		var w := MeshInstance3D.new()
		w.mesh = meshes[1]
		w.material_override = water_material()
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		entry.water = w
	_chunks[key] = entry


## Where grid point (i, j) of a chunk sits on the next coarser level (twice
## the step): its height there and that level's normal (x, z), as the
## coarser mesh would draw it, including which way its squares are split.
## `hs` holds heights with two extra samples all round, `m` wide.
static func _coarse_at(hs: PackedFloat32Array, m: int, i: int, j: int, step: float) -> Vector3:
	var odd_i := i % 2 == 1
	var odd_j := j % 2 == 1
	var pts := []
	if not odd_i and not odd_j:
		pts = [Vector2i(i, j)]
	elif odd_i and not odd_j:
		pts = [Vector2i(i - 1, j), Vector2i(i + 1, j)]
	elif not odd_i and odd_j:
		pts = [Vector2i(i, j - 1), Vector2i(i, j + 1)]
	else:
		var a := hs[(j + 1) * m + (i + 1)]
		var b := hs[(j + 1) * m + (i + 3)]
		var c := hs[(j + 3) * m + (i + 1)]
		var d := hs[(j + 3) * m + (i + 3)]
		if absf(a - d) < absf(b - c):
			pts = [Vector2i(i - 1, j - 1), Vector2i(i + 1, j + 1)]
		else:
			pts = [Vector2i(i + 1, j - 1), Vector2i(i - 1, j + 1)]
	var y := 0.0
	var nrm := Vector3.ZERO
	for qv in pts:
		var q: Vector2i = qv
		var at := (q.y + 2) * m + (q.x + 2)
		y += hs[at]
		# The coarse level's slope, from samples two steps apart (fewer at
		# the edge of what was sampled).
		var x := q.x + 2
		var z := q.y + 2
		var l := mini(2, x)
		var r := mini(2, m - 1 - x)
		var u := mini(2, z)
		var dn := mini(2, m - 1 - z)
		var sx := (hs[at + r] - hs[at - l]) / ((l + r) * step)
		var sz := (hs[at + dn * m] - hs[at - u * m]) / ((u + dn) * step)
		nrm += Vector3(-sx, 1.0, -sz).normalized()
	nrm = nrm.normalized()
	return Vector3(y / pts.size(), nrm.x, nrm.z)


## The ground mesh and the water mesh (or null) for one square chunk with
## its corner at `origin`, a grid `step` metres apart. View coordinates.
static func build_chunk(origin: Vector2, size: float, step: float, reach := 0.0) -> Array:
	var n := int(size / step)
	var m := n + 5  # two extra samples all round, for normals at both levels
	var hs := PackedFloat32Array()
	hs.resize(m * m)
	for j in m:
		for i in m:
			hs[j * m + i] = Terrain.ground_y(origin.x + (i - 2) * step, origin.y + (j - 2) * step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# Each vertex also carries where it sits on the next coarser level (its
	# height and normal there), for the shader to slide toward with distance.
	var coarse := PackedFloat32Array()
	var wet := PackedFloat32Array()
	var count := (n + 1) * (n + 1)
	verts.resize(count)
	normals.resize(count)
	colors.resize(count)
	coarse.resize(count * 4)
	wet.resize(count)
	var any_water := false
	for j in n + 1:
		for i in n + 1:
			var k := j * (n + 1) + i
			var x := origin.x + i * step
			var z := origin.y + j * step
			var c := (j + 2) * m + (i + 2)
			verts[k] = Vector3(x, hs[c], z)
			normals[k] = Vector3(hs[c - 1] - hs[c + 1], 2.0 * step, hs[c - m] - hs[c + m]).normalized()
			var lo := _coarse_at(hs, m, i, j, step)
			coarse[k * 4] = lo.x
			coarse[k * 4 + 1] = lo.y
			coarse[k * 4 + 2] = lo.z
			coarse[k * 4 + 3] = reach
			var cov := Terrain.cover(x + Terrain.view_origin.x, z + Terrain.view_origin.y)
			# r trees, g water, b crops, a bare (as the shader reads them),
			# cleared off the road and its mowed verge.
			var keep := 1.0 - Terrain.mow_weight(x, z)
			colors[k] = Color(cov.r * keep, cov.g, cov.b * keep, cov.a * keep)
			wet[k] = cov.g
			any_water = any_water or cov.g > 0.02
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			# Split each square along the diagonal that follows the land.
			if absf(verts[a].y - verts[a + n + 2].y) < absf(verts[a + 1].y - verts[a + n + 1].y):
				idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
			else:
				idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	# A skirt hangs from each edge to hide cracks against coarser neighbours.
	var drop := step * 0.6 + 1.0
	var edges := [range(0, n + 1), range(n * (n + 1), count), range(0, count, n + 1), range(n, count, n + 1)]
	for e in edges.size():
		var line: Array = Array(edges[e])
		var base := verts.size()
		for k in line:
			verts.append(verts[k] - Vector3(0, drop, 0))
			normals.append(normals[k])
			colors.append(colors[k])
			coarse.append_array([coarse[k * 4] - drop, coarse[k * 4 + 1], coarse[k * 4 + 2], reach])
		for s in line.size() - 1:
			var a: int = line[s]
			var b: int = line[s + 1]
			idx.append_array([a, b, base + s + 1, a, base + s + 1, base + s])
			idx.append_array([a, base + s + 1, b, a, base + s, base + s + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = coarse
	arrays[Mesh.ARRAY_INDEX] = idx
	var ground := ArrayMesh.new()
	ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	if not any_water:
		return [ground, null]
	# Water: a sheet at the water level over every square that touches water.
	# The banks rise above it, so the shore draws itself where they meet.
	var wverts := PackedVector3Array()
	var widx := PackedInt32Array()
	var index := {}
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			if maxf(maxf(wet[a], wet[a + 1]), maxf(wet[a + n + 1], wet[a + n + 2])) < 0.02:
				continue
			var corners := [a, a + 1, a + n + 2, a + n + 1]
			var ids := []
			for c in corners:
				if not index.has(c):
					index[c] = wverts.size()
					var v := verts[c]
					wverts.append(Vector3(v.x, Terrain.water_level(v.x + Terrain.view_origin.x, v.z + Terrain.view_origin.y), v.z))
				ids.append(index[c])
			widx.append_array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
	if widx.is_empty():
		return [ground, null]
	var wn := PackedVector3Array()
	wn.resize(wverts.size())
	wn.fill(Vector3.UP)
	var warrays := []
	warrays.resize(Mesh.ARRAY_MAX)
	warrays[Mesh.ARRAY_VERTEX] = wverts
	warrays[Mesh.ARRAY_NORMAL] = wn
	warrays[Mesh.ARRAY_INDEX] = widx
	var water := ArrayMesh.new()
	water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warrays)
	return [ground, water]


# --- Grading under roads ----------------------------------------------------

## More strips to grade besides roads (the railroad's track): returns
## {key: [PackedVector3Array, inner, outer]}. Call regrade() when they change.
var extra_grades := Callable()


func regrade() -> void:
	_regrade()


## Grades the ground under every road that changed, and marks those chunks
## to be rebuilt.
func _regrade() -> void:
	var now := {}
	for id in network.segments:
		var pts := network.sample_segment(id, 24)
		var type: int = network.segments[id].type
		if absf(pts[0].y) > 3.0 and absf(pts[pts.size() - 1].y) > 3.0 and absf(pts[pts.size() / 2].y) > 3.0:
			continue  # bridges and tunnels leave the ground alone
		var inner := RoadStyle.right_of_way_half(type) + (LOT_GRADE if RoadStyle.TYPES[type].lots else 2.0)
		# The verge is mowed a few metres past the shoulder; woods start there.
		now[id] = [pts, inner, inner + GRADE_FADE, RoadStyle.right_of_way_half(type) + MOW_VERGE]
	if extra_grades.is_valid():
		now.merge(extra_grades.call())
	var changed := []
	for id in _graded:
		if not now.has(id) or not _same(now[id], _graded[id]):
			changed.append(_bounds(_graded[id]))
	for id in now:
		if not _graded.has(id) or not _same(now[id], _graded[id]):
			changed.append(_bounds(now[id]))
	_graded = now
	if changed.is_empty():
		return
	for box in changed:
		Terrain.clear_flat(box)
	for id in _graded:
		var g: Array = _graded[id]
		var b := _bounds(g)
		for box in changed:
			if b.intersects(box):
				# Cover is cleared to the mowed verge (or, without one, the graded strip).
				Terrain.stamp_flat(g[0], g[1], g[2], box, g[3] if g.size() > 3 else g[1])
	for box in changed:
		graded.emit(box)
		var c0 := Vector2i(floori(box.position.x / CHUNK), floori(box.position.y / CHUNK))
		var c1 := Vector2i(floori(box.end.x / CHUNK), floori(box.end.y / CHUNK))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				_dirty[Vector2i(cx, cz)] = true


static func _same(a: Array, b: Array) -> bool:
	return a[1] == b[1] and (a[0] as PackedVector3Array) == (b[0] as PackedVector3Array)


static func _bounds(g: Array) -> Rect2:
	var pts: PackedVector3Array = g[0]
	var r := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(g[2] + Terrain.FLAT_CELL)
