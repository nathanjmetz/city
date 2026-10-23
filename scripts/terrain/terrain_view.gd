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
## Past the last level the land goes on, one square per chunk, out to here,
## so from high up it fades into the haze instead of ending at an edge.
const FAR_REACH := 20000.0
## The far land is rebuilt once the camera has moved this far from where it
## was last built, a few rows each frame.
const FAR_MOVE := 2048.0
## The far land is cut away inside this share of the last level's reach,
## where the chunks are, and sits this far lower so they win where both draw.
const FAR_CUT := 0.97
const FAR_DROP := 3.0
const FAR_BUDGET_MS := 2
const HYST_OUT := 0.95
## Ground graded flat this far each side of a road with lots (curb, walk,
## and the 32 m lots), fading out over the next few metres.
const LOT_GRADE := 34.0
const GRADE_FADE := 14.0
## Mowed grass past a road's right of way before the wild cover starts.
const MOW_VERGE := 3.0
## How much of the woods floor a yard thins to lawn (see build_chunk).
const YARD_THIN := 0.6
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
// The season (Seasons.look, set by DayNight): snow cover, and (autumn, bare,
// spring, dry) for leaves, harvest, green-up and dormant grass.
global uniform float snow;
global uniform vec4 season_look;
uniform vec4 dormant : source_color = vec4(0.55, 0.49, 0.34, 1.0);
uniform vec4 stubble : source_color = vec4(0.56, 0.48, 0.32, 1.0);
uniform vec4 twigs : source_color = vec4(0.30, 0.27, 0.24, 1.0);
uniform vec4 fall_leaves : source_color = vec4(0.42, 0.27, 0.11, 1.0);
// The camera's x, height above the ground, z: level of detail is measured
// from it the way TerrainView picks chunk detail.
uniform vec3 lod_eye;
// The far land (TerrainView's far sheet) is cut away nearer than this, where
// the chunks draw the ground; 0 for the chunks themselves.
uniform float far_cut = 0.0;
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
	if (far_cut > 0.0) {
		vec2 e = p - lod_eye.xz;
		if (dot(e, e) + lod_eye.y * lod_eye.y < far_cut * far_cut) {
			discard;
		}
	}
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
	// Spring green-up, then cool-season grass going tan and dormant in the
	// late-summer dry spell and over winter (Indiana pasture).
	col = mix(col, col * vec3(0.92, 1.12, 0.78), season_look.z);
	float brown = clamp(season_look.w * 1.1 - (1.0 - dryness) * 0.3, 0.0, 0.85);
	col = mix(col, dormant.rgb * (0.85 + big * 0.3), brown);

	// Crop fields: whole fields of one crop, a quarter mile across, in green
	// beans, tan corn stubble or tilled soil, with rows running north-south
	// (the township grid) that fade with distance.
	vec2 field = floor(p / 402.0);
	float pick = fract(sin(dot(field, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 crop = pick < 0.45 ? crop_green.rgb : (pick < 0.8 ? crop_corn.rgb : (pick < 0.92 ? crop_tan.rgb : tilled.rgb));
	// The crop year: corn and beans ripen gold in the fall; after harvest
	// (November to April) fields lie in stubble, about a third fall-tilled;
	// spring planting turns the rest to bare soil before it greens again.
	vec3 ripe = pick < 0.45 ? vec3(0.58, 0.50, 0.27) : vec3(0.62, 0.53, 0.33);
	crop = mix(crop, ripe, season_look.x * step(pick, 0.8));
	float worked = fract(pick * 7.31);
	vec3 after = worked < 0.33 ? tilled.rgb : stubble.rgb * (pick < 0.45 ? vec3(0.9, 0.92, 0.95) : vec3(1.0));
	// About one field in ten is winter wheat or a cover crop, green all winter.
	after = fract(pick * 13.1) < 0.1 ? vec3(0.33, 0.40, 0.20) : after;
	crop = mix(crop, after, season_look.y);
	crop = mix(crop, tilled.rgb, season_look.z * (1.0 - season_look.y) * 0.6);
	crop *= 0.9 + 0.2 * mid;
	float rows = sin(p.x * 8.27) * 0.5 + 0.5;
	crop *= 1.0 - rows * 0.12 * clamp(1.0 - dist / 300.0, 0.0, 1.0);
	col = mix(col, crop, smoothstep(0.3, 0.7, cover.b) * 0.92);

	// Woods: leaf litter under the trees up close; from far off, where the
	// trees aren't drawn, the canopy itself, lumpy with crowns.
	float crowns = texture(noise_soft, p / 11.0).r * 0.6 + clump * 0.4;
	vec3 leaves = mix(canopy.rgb, fall_leaves.rgb * (0.8 + 0.5 * mid), season_look.x);
	leaves = mix(leaves, twigs.rgb, season_look.y);
	vec3 tops = leaves * (0.65 + 0.7 * crowns) * (0.85 + 0.3 * big);
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
	// Snow lies thinner under the woods and on steep banks, and drifts in
	// patches before it covers everything.
	float under = smoothstep(0.3, 0.65, cover.r) * (1.0 - painted) * 0.45 + smoothstep(0.2, 0.45, steep) * 0.4;
	float lies = smoothstep(0.05, 0.45, snow * 1.15 - clump * 0.35 - (1.0 - mid) * 0.15 + 0.1 - under);
	lies *= 1.0 - smoothstep(0.03, 0.3, cover.g) * 0.5;
	vec3 snowy = vec3(0.80, 0.83, 0.88) * (0.94 + big * 0.08) * (1.0 + (blades - 0.5) * 0.08 * fade);
	// Fields read through the snow from the air: corn stubble and tilled
	// clods poke through, and each field drifts a little differently.
	float in_field = smoothstep(0.3, 0.7, cover.b);
	vec3 poking = worked < 0.33 ? tilled.rgb : stubble.rgb;
	float through = (worked < 0.33 ? 0.22 : (pick < 0.8 && pick >= 0.45 ? 0.3 : 0.12)) * (0.6 + 0.8 * clump);
	snowy = mix(snowy * (0.95 + 0.06 * fract(pick * 3.7)), poking, through * in_field);
	// Far canopy shows dark trunks through the snow.
	snowy = mix(snowy, twigs.rgb * 1.3, smoothstep(0.3, 0.65, cover.r) * painted * 0.45);
	col = mix(col, snowy, lies);
	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.75, lies);
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

## More roads to grade besides the town's own: name -> [RoadNetwork,
## Vector2 offset where it is drawn, lots] for a neighbor's town, or
## [strips] (see add_strips) for the county highways out to the horizon.
var _others := {}

## Vector2i chunk -> {lod, ground: MeshInstance3D, water: MeshInstance3D}
var _chunks := {}
var _dirty := {}  # Vector2i chunk -> [Rect2] graded since it was built
var _graded := {}  # segment id -> [points, inner, outer, bounds]
var _first := true
var _far: MeshInstance3D
static var _far_mat: ShaderMaterial
var _far_centre := Vector2(INF, INF)
## The far land being built (see far_job), or empty.
var _far_job := {}


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
	var t0 := Perf.now()
	var eye := _eye()
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("lod_eye", Vector3(eye.x, eye.z, eye.y))
	if _far_mat != null:
		_far_mat.set_shader_parameter("lod_eye", Vector3(eye.x, eye.z, eye.y))
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
		var have = _chunks.get(key)
		if have != null and have.lod == want[key] and _dirty.has(key):
			# Graded under a new road: redo just that strip of the chunk.
			patch_chunk(have.data, _dirty[key])
			have.ground.mesh = have.data.ground
		else:
			_build(key, want[key])
		_dirty.erase(key)
		# Build everything at once the first time, so the land is there
		# when the game opens; then a little each frame.
		if not _first and Time.get_ticks_msec() - start > BUDGET_MS:
			break
	_update_far(flat_eye, _first)
	_first = false
	Perf.add("frame.terrain", t0)


## The far land: one coarse sheet around the camera out to FAR_REACH, cut
## away in the shader where the chunks are. Rebuilt in slices of
## FAR_BUDGET_MS a frame (all at once the first time), with no threads, so
## it runs the same on the web.
func _update_far(flat_eye: Vector2, all_now := false) -> void:
	var start := Time.get_ticks_msec()
	if _far_job.is_empty():
		if flat_eye.distance_to(_far_centre) < FAR_MOVE:
			return
		var c := (flat_eye / CHUNK).round()
		_far_job = far_job(c * CHUNK, ceili((FAR_REACH + FAR_MOVE) / CHUNK))
	while not far_step(_far_job):
		if not all_now and Time.get_ticks_msec() - start > FAR_BUDGET_MS:
			return
	if _far == null:
		_far = MeshInstance3D.new()
		_far.material_override = far_material()
		_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_far)
	_far.mesh = _far_job.mesh
	_far_centre = _far_job.centre
	_far_job = {}


static func far_material() -> ShaderMaterial:
	if _far_mat == null:
		_far_mat = ground_material().duplicate()
		_far_mat.set_shader_parameter("far_cut", REACH[REACH.size() - 1] * FAR_CUT)
	return _far_mat


## A job building the far sheet: (2r + 1) squares of CHUNK a side around
## `centre`. Run it with far_step until that returns true; the mesh is then
## in job.mesh.
static func far_job(centre: Vector2, r: int) -> Dictionary:
	var n := 2 * r + 1
	return {"centre": centre, "origin": centre - Vector2(r + 0.5, r + 0.5) * CHUNK, "n": n,
		"row": 0, "hs": PackedFloat32Array(), "verts": PackedVector3Array(),
		"normals": PackedVector3Array(), "colors": PackedColorArray(), "coarse": PackedFloat32Array()}


## One slice of a far job: a row of heights, then once they are all in, a
## row of vertices, then the mesh.
## True once the mesh is made.
static func far_step(job: Dictionary) -> bool:
	var n: int = job.n
	var m := n + 3
	var origin: Vector2 = job.origin
	var off := Terrain.shift + Terrain.view_origin
	if job.hs.size() < m * m:
		# A row of heights, with one extra all round for the normals. The raw
		# ground, not ground_y: grading near town is the chunks' to draw, and
		# none of it shows from 9 km.
		var j: int = job.hs.size() / m
		for i in m:
			job.hs.append(Terrain.height(origin.x + (i - 1) * CHUNK + off.x, origin.y + (j - 1) * CHUNK + off.y) - FAR_DROP)
		return false
	if job.row <= n:
		var hs: PackedFloat32Array = job.hs
		var j: int = job.row
		for i in n + 1:
			var x := origin.x + i * CHUNK
			var z := origin.y + j * CHUNK
			var c := (j + 1) * m + (i + 1)
			var nrm := Vector3(hs[c - 1] - hs[c + 1], 2.0 * CHUNK, hs[c - m] - hs[c + m]).normalized()
			job.verts.append(Vector3(x, hs[c], z))
			job.normals.append(nrm)
			job.coarse.append_array([hs[c], nrm.x, nrm.z, 0.0])
			job.colors.append(Terrain.cover(x + Terrain.view_origin.x, z + Terrain.view_origin.y))
		job.row += 1
		return false
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = job.verts
	arrays[Mesh.ARRAY_NORMAL] = job.normals
	arrays[Mesh.ARRAY_COLOR] = job.colors
	arrays[Mesh.ARRAY_CUSTOM0] = job.coarse
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	job.mesh = mesh
	return true


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
	var data := chunk_data(Vector2(key) * CHUNK, CHUNK, STEPS[lod], REACH[lod] if lod < STEPS.size() - 1 else 0.0)
	var meshes := [data.ground, data.water]
	var entry := {"lod": lod, "ground": null, "water": null, "data": data}
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
	var d := chunk_data(origin, size, step, reach)
	return [d.ground, d.water]


## A chunk's samples, vertices and meshes, kept so patch_chunk can redo only
## the part a new road grades.
static func chunk_data(origin: Vector2, size: float, step: float, reach := 0.0) -> Dictionary:
	var n := int(size / step)
	var m := n + 5  # two extra samples all round, for normals at both levels
	var count := (n + 1) * (n + 1)
	var d := {"origin": origin, "step": step, "reach": reach, "n": n, "m": m,
		"hs": PackedFloat32Array(), "verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"colors": PackedColorArray(), "coarse": PackedFloat32Array(), "wet": PackedFloat32Array(),
		"idx": PackedInt32Array(), "water": null}
	d.hs.resize(m * m)
	d.verts.resize(count)
	d.normals.resize(count)
	d.colors.resize(count)
	# Each vertex also carries where it sits on the next coarser level (its
	# height and normal there), for the shader to slide toward with distance.
	d.coarse.resize(count * 4)
	d.wet.resize(count)
	d.idx.resize(n * n * 6)
	_sample_heights(d, 0, m - 1, 0, m - 1)
	var any_water := _fill_vertices(d, 0, n, 0, n)
	_fill_squares(d, 0, n - 1, 0, n - 1)
	d.ground = _ground_mesh(d)
	if any_water:
		d.water = _water_mesh(d)
	return d


## Redoes a chunk's ground under `boxes` (view coordinates) after grading:
## the samples there, the vertices whose normals and coarser level read
## them, and the squares between, then the mesh once. The water stays.
static func patch_chunk(d: Dictionary, boxes: Array) -> void:
	var o: Vector2 = d.origin
	var step: float = d.step
	var n: int = d.n
	var m: int = d.m
	# Per row, the columns to redo (boxes along one road overlap; each
	# point is done once). Sample indices are grid indices plus 2.
	var samples := _spans(m)
	var verts := _spans(n + 1)
	var squares := _spans(n)
	for box: Rect2 in boxes:
		var i0 := floori((box.position.x - o.x) / step)
		var i1 := ceili((box.end.x - o.x) / step)
		var j0 := floori((box.position.y - o.y) / step)
		var j1 := ceili((box.end.y - o.y) / step)
		_widen(samples, i0 + 1, i1 + 3, j0 + 1, j1 + 3)
		_widen(verts, i0 - 3, i1 + 3, j0 - 3, j1 + 3)
		_widen(squares, i0 - 4, i1 + 3, j0 - 4, j1 + 3)
	var changed := false
	for j in m:
		if samples[0][j] <= samples[1][j]:
			_sample_heights(d, samples[0][j], samples[1][j], j, j)
	for j in n + 1:
		if verts[0][j] <= verts[1][j]:
			_fill_vertices(d, verts[0][j], verts[1][j], j, j)
			changed = true
	for j in n:
		if squares[0][j] <= squares[1][j]:
			_fill_squares(d, squares[0][j], squares[1][j], j, j)
	if changed:
		d.ground = _ground_mesh(d)


## Empty column spans for `size` rows: [lows, highs].
static func _spans(size: int) -> Array:
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	lo.resize(size)
	hi.resize(size)
	lo.fill(size)
	hi.fill(-1)
	return [lo, hi]


static func _widen(spans: Array, i0: int, i1: int, j0: int, j1: int) -> void:
	var lo: PackedInt32Array = spans[0]
	var hi: PackedInt32Array = spans[1]
	var size := lo.size()
	i0 = maxi(i0, 0)
	i1 = mini(i1, size - 1)
	if i0 > i1:
		return
	for j in range(maxi(j0, 0), mini(j1, size - 1) + 1):
		lo[j] = mini(lo[j], i0)
		hi[j] = maxi(hi[j], i1)
	spans[0] = lo
	spans[1] = hi


static func _sample_heights(d: Dictionary, a0: int, a1: int, b0: int, b1: int) -> void:
	var o: Vector2 = d.origin
	var step: float = d.step
	var m: int = d.m
	var hs: PackedFloat32Array = d.hs
	for j in range(b0, b1 + 1):
		for i in range(a0, a1 + 1):
			hs[j * m + i] = Terrain.ground_y(o.x + (i - 2) * step, o.y + (j - 2) * step)
	d.hs = hs


## Fills grid vertices i0..i1, j0..j1; true when any of them is wet.
static func _fill_vertices(d: Dictionary, i0: int, i1: int, j0: int, j1: int) -> bool:
	var o: Vector2 = d.origin
	var step: float = d.step
	var n: int = d.n
	var m: int = d.m
	var reach: float = d.reach
	var hs: PackedFloat32Array = d.hs
	var verts: PackedVector3Array = d.verts
	var normals: PackedVector3Array = d.normals
	var colors: PackedColorArray = d.colors
	var coarse: PackedFloat32Array = d.coarse
	var wet: PackedFloat32Array = d.wet
	var any_water := false
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * (n + 1) + i
			var x := o.x + i * step
			var z := o.y + j * step
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
			var mowed := Terrain.mow_weight(x, z)
			var keep := 1.0 - mowed
			# Yards (graded for lots but past the mowed verge) keep their trees,
			# but the ground under them is thin, patchy lawn with some leaves,
			# not the bare leaf litter of the woods.
			var yard := clampf(Terrain.flat_weight(x, z) - mowed, 0.0, 1.0)
			colors[k] = Color(cov.r * keep * (1.0 - YARD_THIN * yard), cov.g, cov.b * keep, cov.a * keep)
			wet[k] = cov.g
			any_water = any_water or cov.g > 0.02
	d.verts = verts
	d.normals = normals
	d.colors = colors
	d.coarse = coarse
	d.wet = wet
	return any_water


## Splits each square i0..i1, j0..j1 along the diagonal that follows the land.
static func _fill_squares(d: Dictionary, i0: int, i1: int, j0: int, j1: int) -> void:
	var n: int = d.n
	var verts: PackedVector3Array = d.verts
	var idx: PackedInt32Array = d.idx
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var a := j * (n + 1) + i
			var s := (j * n + i) * 6
			if absf(verts[a].y - verts[a + n + 2].y) < absf(verts[a + 1].y - verts[a + n + 1].y):
				idx[s] = a
				idx[s + 1] = a + 1
				idx[s + 2] = a + n + 2
				idx[s + 3] = a
				idx[s + 4] = a + n + 2
				idx[s + 5] = a + n + 1
			else:
				idx[s] = a
				idx[s + 1] = a + 1
				idx[s + 2] = a + n + 1
				idx[s + 3] = a + 1
				idx[s + 4] = a + n + 2
				idx[s + 5] = a + n + 1
	d.idx = idx


static func _ground_mesh(d: Dictionary) -> ArrayMesh:
	var n: int = d.n
	var step: float = d.step
	var reach: float = d.reach
	var count := (n + 1) * (n + 1)
	var verts: PackedVector3Array = d.verts.duplicate()
	var normals: PackedVector3Array = d.normals.duplicate()
	var colors: PackedColorArray = d.colors.duplicate()
	var coarse: PackedFloat32Array = d.coarse.duplicate()
	var idx: PackedInt32Array = d.idx.duplicate()
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
	return ground


## Water: a sheet at the water level over every square that touches water.
## The banks rise above it, so the shore draws itself where they meet.
static func _water_mesh(d: Dictionary) -> ArrayMesh:
	var n: int = d.n
	var verts: PackedVector3Array = d.verts
	var wet: PackedFloat32Array = d.wet
	var wverts := PackedVector3Array()
	var widx := PackedInt32Array()
	var index := {}
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			if maxf(maxf(wet[a], wet[a + 1]), maxf(wet[a + n + 1], wet[a + n + 2])) < 0.02:
				continue
			# Flat at the level of the wettest corner. The level is only known
			# on or by the water, so a dry corner read on its own could tilt
			# the sheet tens of metres up into the air on the coarser levels.
			var corners := [a, a + 1, a + n + 2, a + n + 1]
			var wettest: int = corners[0]
			for c in corners:
				if wet[c] > wet[wettest]:
					wettest = c
			if not index.has(wettest):
				var v := verts[wettest]
				index[wettest] = Terrain.water_level(v.x + Terrain.view_origin.x, v.z + Terrain.view_origin.y)
			var level: float = index[wettest]
			var base := wverts.size()
			for c in corners:
				wverts.append(Vector3(verts[c].x, level, verts[c].z))
			widx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if widx.is_empty():
		return null
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
	return water


# --- Grading under roads ----------------------------------------------------

## More strips to grade besides roads (the railroad's track): returns
## {key: [PackedVector3Array, inner, outer]}. Call regrade() when they change.
var extra_grades := Callable()


func regrade() -> void:
	_regrade()


## Grades the ground under another road network too, drawn moved over by
## `offset` (a neighbor's town); `lots` false grades only the road itself
## (no town lots along it). Setting a name again replaces it.
func add_network(name: String, net: RoadNetwork, offset := Vector2.ZERO, lots := true) -> void:
	remove_network(name, false)
	_others[name] = [net, offset, lots]
	if not net.changed.is_connected(_regrade):
		net.changed.connect(_regrade)
	_regrade()


## Grades strips that aren't part of any network: key -> [points (view
## coordinates), graded half width, fade-out half width, mowed half width].
## Setting a name again replaces them.
func add_strips(name: String, strips: Dictionary) -> void:
	remove_network(name, false)
	_others[name] = [strips]
	_regrade()


func remove_network(name: String, now := true) -> void:
	if not _others.has(name):
		return
	if _others[name][0] is RoadNetwork and _others[name][0].changed.is_connected(_regrade):
		_others[name][0].changed.disconnect(_regrade)
	_others.erase(name)
	if now:
		_regrade()


## Grades the ground under every road that changed, and marks those chunks
## to be rebuilt.
func _regrade() -> void:
	var now := {}
	if network != null:
		_grade_network(now, network, Vector2.ZERO, true, "")
	for name in _others:
		var o: Array = _others[name]
		if o[0] is RoadNetwork:
			_grade_network(now, o[0], o[1], o[2], name + ":")
		else:
			for key in o[0]:
				now[name + ":" + str(key)] = o[0][key]
	if extra_grades.is_valid():
		now.merge(extra_grades.call())
	var changed := []
	var changed_strips := []
	for id in _graded:
		if not now.has(id) or not _same(now[id], _graded[id]):
			changed.append(_bounds(_graded[id]))
			changed_strips.append(_graded[id])
	for id in now:
		if not _graded.has(id) or not _same(now[id], _graded[id]):
			changed.append(_bounds(now[id]))
			changed_strips.append(now[id])
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
	for g in changed_strips:
		_mark_dirty(g)


## Marks the chunks a graded strip runs through, with the boxes along it in
## each (a long diagonal road touches a thin band, not its whole bounds).
func _mark_dirty(g: Array) -> void:
	var pts: PackedVector3Array = g[0]
	var grow: float = g[2] + Terrain.FLAT_CELL
	var pieces := []
	if pts.size() == 1:
		pieces.append(Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO).grow(grow))
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var cuts := maxi(1, ceili(a.distance_to(b) / 64.0))
		for c in cuts:
			var p := a.lerp(b, float(c) / cuts)
			var q := a.lerp(b, float(c + 1) / cuts)
			pieces.append(Rect2(p, Vector2.ZERO).expand(q).grow(grow))
	for box: Rect2 in pieces:
		var c0 := Vector2i(floori(box.position.x / CHUNK), floori(box.position.y / CHUNK))
		var c1 := Vector2i(floori(box.end.x / CHUNK), floori(box.end.y / CHUNK))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cz)
				if not _dirty.has(key):
					_dirty[key] = []
				_dirty[key].append(box)


## The strips to grade under one network's roads, keyed by segment id
## (with `prefix` for networks other than the town's own).
static func _grade_network(now: Dictionary, net: RoadNetwork, offset: Vector2, lots: bool, prefix: String) -> void:
	var shift := Vector3(offset.x, 0.0, offset.y)
	for id in net.segments:
		var pts := _straightened(net.sample_segment(id, 24))
		var type: int = net.segments[id].type
		if absf(pts[0].y) > 3.0 and absf(pts[pts.size() - 1].y) > 3.0 and absf(pts[pts.size() / 2].y) > 3.0:
			continue  # bridges and tunnels leave the ground alone
		if offset != Vector2.ZERO:
			for i in pts.size():
				pts[i] += shift
		var inner := RoadStyle.right_of_way_half(type) + (LOT_GRADE if lots and RoadStyle.TYPES[type].lots else 2.0)
		# The verge is mowed a few metres past the shoulder; woods start there.
		now[id if prefix == "" else prefix + str(id)] = [pts, inner, inner + GRADE_FADE,
			RoadStyle.right_of_way_half(type) + MOW_VERGE]


## A straight road's samples cut down to its two ends (grading costs one
## pass over the ground per piece of line); curves keep every point.
static func _straightened(pts: PackedVector3Array) -> PackedVector3Array:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var dir := Vector2(b.x - a.x, b.z - a.z)
	var length := dir.length()
	if length < 1.0:
		return pts
	dir /= length
	for p in pts:
		if absf((p.y - a.y) - (b.y - a.y) * Vector2(p.x - a.x, p.z - a.z).dot(dir) / length) > 0.2:
			return pts
		if absf(Vector2(p.x - a.x, p.z - a.z).cross(dir)) > 0.25:
			return pts
	return PackedVector3Array([a, b])


static func _same(a: Array, b: Array) -> bool:
	return a[1] == b[1] and (a[0] as PackedVector3Array) == (b[0] as PackedVector3Array)


static func _bounds(g: Array) -> Rect2:
	var pts: PackedVector3Array = g[0]
	var r := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(g[2] + Terrain.FLAT_CELL)
