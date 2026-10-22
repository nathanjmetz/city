class_name TreeField
extends Node3D
## All the trees in town, drawn as one MultiMesh per species so a whole
## city of trees costs a handful of draw calls. Benchmark: photos of mature
## Midwestern streets, where big yard and street trees frame every block.
##   Species: sugar maple (round, dense), bur oak (broad, open), honey
##   locust (light, airy), Colorado spruce (dark cone) and crabapple (small,
##   front-yard ornamental).
## Canopies are clusters of leaf cards with a generated leaf texture. Normals
## point out from the canopy centre, so a crown shades like a soft volume,
## and the inside of the crown is darker. Leaves sway a little in the wind.
## Trees are grouped in square chunks. Each chunk has a full tree up close
## and a light version (a few big cards) far away, so a big city stays cheap
## for the web build.

enum Species { MAPLE, OAK, LOCUST, SPRUCE, CRABAPPLE }

## Summer leaf colours (sRGB) and how much each tree can vary from them.
const LEAF := [Color("#46661f"), Color("#3f5c1e"), Color("#627424"), Color("#2c4433"), Color("#4a6326")]

## Chunk size, and the distance where the full tree gives way to the light one.
const CHUNK := 256.0
const NEAR := 380.0

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaf_tex : filter_linear_mipmap;
// Set by DayNight: snow cover, and the season as (autumn, bare, spring, dry).
global uniform float snow;
global uniform vec4 season_look;
// Wild trees thin out and shrink toward the edge of where they're drawn
// (set by WildView as centre x, z and reach), so they never pop in or out.
global uniform vec4 tree_fade;
uniform bool fade_on = false;
varying float fade;
varying float inner;
varying float top;
varying vec3 tint;
varying vec3 crown_normal;
varying vec3 leaf_pos;
varying float species;
varying float tree_rand;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	fade = 1.0;
	if (fade_on) {
		fade = 1.0 - smoothstep(tree_fade.z * 0.72, tree_fade.z * 0.97, distance(origin.xz, tree_fade.xy));
	}
	VERTEX *= mix(0.4, 1.0, fade);
	leaf_pos = VERTEX;
	species = floor(INSTANCE_CUSTOM.a * 8.0);
	tree_rand = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = TIME * 1.1 + origin.x * 0.31 + origin.z * 0.17;
	float sway = sin(phase + VERTEX.y * 0.25) * 0.025 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
	inner = COLOR.r;
	top = COLOR.g;
	// Keep the crown normal on both sides of each card (no back-face flip),
	// so the whole crown shades like one soft volume.
	crown_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Each leaf cluster drifts a little toward yellow or blue-green.
	tint = lin(INSTANCE_CUSTOM.rgb) * mix(vec3(0.9, 0.98, 1.08), vec3(1.1, 1.04, 0.86), COLOR.b);
}
void fragment() {
	vec4 t = texture(leaf_tex, UV);
	// Mipmaps average the leaf alpha toward the gaps, so distant cards
	// would fall under the cut-off and vanish. Boost alpha with the mip level.
	vec2 texel = UV * 256.0;
	float lod = log2(max(max(length(dFdx(texel)), length(dFdy(texel))), 1.0));
	t.a *= 1.0 + lod * 0.3;
	NORMAL = crown_normal;
	// Inner leaves sit in the shade of outer ones; the top of the crown
	// catches the open sky.
	vec3 leaf = tint;
	float alpha = t.a;
	// Seasons (spruce, species 3, stays green). Each tree turns, drops and
	// leafs out a little earlier or later than its neighbours.
	if (abs(species - 3.0) > 0.5) {
		float turn = clamp(season_look.x * 1.5 - tree_rand * 0.5, 0.0, 1.0);
		float bare = clamp(season_look.y * 1.4 - tree_rand * 0.4, 0.0, 1.0);
		// Fall colour: sugar maples red to orange, bur oaks russet, honey
		// locusts gold, crabapples orange-red.
		vec3 fall = mix(vec3(0.5, 0.06, 0.01), vec3(0.78, 0.3, 0.02), tree_rand);
		if (tree_rand > 0.75) fall = vec3(0.7, 0.46, 0.03);
		if (species > 0.5) fall = vec3(0.24, 0.09, 0.02) * (0.8 + tree_rand * 0.4);
		if (species > 1.5) fall = vec3(0.6, 0.4, 0.03);
		if (species > 3.5) fall = vec3(0.55, 0.13, 0.015);
		// Green goes to yellow first, then to the tree's own colour.
		leaf = mix(leaf, vec3(0.32, 0.3, 0.03), smoothstep(0.0, 0.5, turn) * (1.0 - smoothstep(0.5, 1.0, turn)));
		leaf = mix(leaf, fall, smoothstep(0.35, 1.0, turn));
		// New leaves are a pale yellow-green; crabapples bloom pink first.
		vec3 fresh = leaf * vec3(1.25, 1.3, 0.7);
		if (species > 3.5) fresh = vec3(0.75, 0.32, 0.4);
		leaf = mix(leaf, fresh, season_look.z);
		// Leaves fall: the crown thins to a lace of bare twigs.
		float h = fract(sin(dot(floor(leaf_pos * 2.5), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		alpha *= step(bare * 0.88, h);
		leaf = mix(leaf, vec3(0.05, 0.042, 0.036), smoothstep(0.3, 0.9, bare));
	}
	// Snow resting on the tops of the crowns.
	leaf = mix(leaf, vec3(0.4, 0.42, 0.45), snow * smoothstep(0.35, 0.95, top) * 0.75);
	ALBEDO = leaf * t.rgb * mix(0.6, 1.15, inner) * mix(0.85, 1.2, top) * 2.0;
	ALPHA = alpha * mix(0.3, 1.0, fade);
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	// With MSAA, leaf edges become partial coverage instead of popping on
	// and off as the camera moves.
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * 128.0;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
}
"""

const BARK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
global uniform vec4 tree_fade;
uniform bool fade_on = false;
void vertex() {
	float fade = 1.0;
	if (fade_on) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		fade = 1.0 - smoothstep(tree_fade.z * 0.72, tree_fade.z * 0.97, distance(origin.xz, tree_fade.xy));
	}
	VERTEX *= fade;
}
void fragment() {
	float ridges = 0.85 + 0.15 * sin(UV.x * 40.0 + sin(UV.y * 6.0) * 2.0);
	ALBEDO = vec3(0.085, 0.07, 0.058) * ridges;
	ROUGHNESS = 0.95;
}
"""

static var _meshes := {}
static var _leaf_mat: ShaderMaterial
static var _bark_mat: ShaderMaterial

## True for wild trees: they fade out toward the edge of WildView's reach.
var fades := false

var _trees := {}  # owner key -> Array of [Transform3D, species, tint]
var _multis := {}  # "cx,cz,species,far" -> MultiMeshInstance3D
var _dirty := false


## Replaces the trees that belong to `key` (a lot). Each tree is
## [Transform3D (world), species, tint Color].
func set_trees(key: String, trees: Array) -> void:
	_trees[key] = trees
	_dirty = true


func remove(key: String) -> void:
	if _trees.erase(key):
		_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	var groups := {}  # "cx,cz,species" -> Array of trees
	for list in _trees.values():
		for t in list:
			var o: Vector3 = t[0].origin
			var g := "%d,%d,%d" % [floori(o.x / CHUNK), floori(o.z / CHUNK), t[1]]
			if not groups.has(g):
				groups[g] = []
			groups[g].append(t)
	for k in _multis:
		_multis[k].multimesh.instance_count = 0
	for g in groups:
		var parts: PackedStringArray = g.split(",")
		var centre := Vector3((int(parts[0]) + 0.5) * CHUNK, 0, (int(parts[1]) + 0.5) * CHUNK)
		for far in [false, true]:
			var multi := _chunk(g, int(parts[2]), far, centre).multimesh
			var list: Array = groups[g]
			multi.instance_count = list.size()
			for i in list.size():
				var xf: Transform3D = list[i][0]
				multi.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
				# Alpha carries the species, for the season colours.
				var custom: Color = list[i][2]
				custom.a = (float(parts[2]) + 0.5) / 8.0
				multi.set_instance_custom_data(i, custom)


## The MultiMesh for one species in one chunk, near or far. The node sits at
## the chunk centre so its visibility range is measured from there.
func _chunk(g: String, sp: int, far: bool, centre: Vector3) -> MultiMeshInstance3D:
	var key := g + ("f" if far else "n")
	if _multis.has(key):
		return _multis[key]
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = tree_mesh(sp, far, fades)
	mmi.multimesh = mm
	mmi.position = centre
	if far:
		mmi.visibility_range_begin = NEAR
		mmi.visibility_range_begin_margin = 20.0
	else:
		mmi.visibility_range_end = NEAR
		mmi.visibility_range_end_margin = 20.0
	add_child(mmi)
	_multis[key] = mmi
	return mmi


## Picks a species and colour for a yard tree.
static func pick(rng: RandomNumberGenerator, front := false) -> Array:
	var r := rng.randf()
	var sp: int
	if front and r < 0.2:
		sp = Species.CRABAPPLE
	elif r < 0.55:
		sp = Species.MAPLE
	elif r < 0.72:
		sp = Species.OAK
	elif r < 0.86:
		sp = Species.LOCUST
	else:
		sp = Species.SPRUCE
	var tint: Color = LEAF[sp]
	tint = tint.lightened(rng.randf_range(-0.08, 0.1)) if rng.randf() < 0.5 else tint.darkened(rng.randf_range(0.0, 0.12))
	return [sp, tint]


# ---------------------------------------------------------------- meshes

## The mesh for a species; `far` is the light version for distant chunks.
static func tree_mesh(sp: int, far := false, fades := false) -> ArrayMesh:
	var key := sp * 2 + (1 if far else 0) + (100 if fades else 0)
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + sp
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	match sp:
		Species.SPRUCE: _spruce(rng, leaves, wood, far)
		_: _broadleaf(sp, rng, leaves, wood, far)
	var mesh := ArrayMesh.new()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _leaf_material(fades))
	wood.commit(mesh)
	mesh.surface_set_material(1, _bark_material(fades))
	_meshes[key] = mesh
	return mesh


## Crown shape per species: crown centre height, radii, cluster count,
## card size and trunk radius. Sizes are mature trees, in metres. Real yard
## maples and oaks fork low, around 3 m, into a few big limbs.
static func _broadleaf(sp: int, rng: RandomNumberGenerator, leaves: SurfaceTool, wood: SurfaceTool, far := false) -> void:
	var shape: Array = {
		Species.MAPLE: [8.5, Vector3(6.0, 5.2, 6.0), 16, 3.2, 0.3],
		Species.OAK: [8.0, Vector3(7.5, 4.6, 7.0), 15, 3.4, 0.4],
		Species.LOCUST: [9.0, Vector3(6.0, 4.3, 5.5), 13, 2.6, 0.24],
		Species.CRABAPPLE: [3.4, Vector3(3.0, 2.2, 3.0), 9, 2.0, 0.12],
	}[sp]
	var hc: float = shape[0]
	var rad: Vector3 = shape[1]
	var clusters: int = shape[2]
	var card: float = shape[3]
	var trunk: float = shape[4]
	var center := Vector3(0, hc, 0)
	var fork := minf(hc - rad.y * 0.75, 3.2)
	_limb(wood, Vector3.ZERO, Vector3(0, fork, 0), trunk, trunk * 0.8)
	var cards_per := 6 if sp == Species.LOCUST else 7
	if far:
		# A few big cards keep the crown's outline and colour at a distance.
		clusters = maxi(clusters / 2, 5)
		cards_per = 3
		card *= 1.9
	for c in clusters:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.55, 1), rng.randf_range(-1, 1)).normalized()
		var cc := center + dir * rad * rng.randf_range(0.4, 0.75)
		if not far and c % 3 == 0:
			_limb(wood, Vector3(0, fork, 0), cc.lerp(center, 0.3), trunk * 0.6, trunk * 0.2)
		var hue := rng.randf()
		for i in cards_per:
			var p := cc + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.7), rng.randf_range(-1, 1)) * card * 0.6
			_card(leaves, rng, p, center, rad, card * rng.randf_range(0.8, 1.2), hue)


static func _spruce(rng: RandomNumberGenerator, leaves: SurfaceTool, wood: SurfaceTool, far := false) -> void:
	var h := 13.0
	var base_r := 3.6
	_limb(wood, Vector3.ZERO, Vector3(0, h, 0), 0.25, 0.04)
	var tiers := 6 if far else 11
	for t in tiers:
		var f := float(t) / tiers
		var y := 1.2 + f * (h - 1.6)
		var r := base_r * (1.0 - f) + 0.35
		var n := int(3 + r * (1.0 if far else 2.0))
		var hue := rng.randf() * 0.4
		for i in n:
			var a := TAU * (i + rng.randf()) / n
			var p := Vector3(cos(a) * r * rng.randf_range(0.45, 0.8), y, sin(a) * r * rng.randf_range(0.45, 0.8))
			_card(leaves, rng, p, Vector3(0, y + 0.8, 0), Vector3(r + 0.5, 1.5, r + 0.5), (1.8 + r * 0.45) * (1.5 if far else 1.0), hue)


## One leaf card, randomly turned, with normals out from the crown centre.
static func _card(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, center: Vector3, rad: Vector3, size: float, hue: float) -> void:
	var basis := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
	var u := basis.x * size * 0.5
	var v := basis.y * size * 0.5
	var corners := [p - u - v, p + u - v, p + u + v, p - u + v]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		var q: Vector3 = corners[i]
		var rel := (q - center) / rad
		var out := (rel + Vector3(0, 0.35, 0)).normalized()
		st.set_normal(out)
		# How far out in the crown: inner leaves are shaded by outer ones.
		st.set_color(Color(clampf(rel.length(), 0.0, 1.0), 0, 0))
		st.set_uv(uvs[i])
		st.add_vertex(q)


## A tapered six-sided branch from a to b.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var up := side.cross(axis)
	var n := 6
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var quad := [[a + d0 * r0, d0, Vector2(float(i) / n, 0)], [a + d1 * r0, d1, Vector2(float(i + 1) / n, 0)],
			[b + d1 * r1, d1, Vector2(float(i + 1) / n, 1)], [b + d0 * r1, d0, Vector2(float(i) / n, 1)]]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])


static var _wild_leaf_mat: ShaderMaterial
static var _wild_bark_mat: ShaderMaterial


static func _leaf_material(fades := false) -> ShaderMaterial:
	if _leaf_mat == null:
		var shader := Shader.new()
		shader.code = LEAF_SHADER
		_leaf_mat = ShaderMaterial.new()
		_leaf_mat.shader = shader
		_leaf_mat.set_shader_parameter("leaf_tex", _leaf_texture())
		_wild_leaf_mat = _leaf_mat.duplicate()
		_wild_leaf_mat.set_shader_parameter("fade_on", true)
	return _wild_leaf_mat if fades else _leaf_mat


static func _bark_material(fades := false) -> ShaderMaterial:
	if _bark_mat == null:
		var shader := Shader.new()
		shader.code = BARK_SHADER
		_bark_mat = ShaderMaterial.new()
		_bark_mat.shader = shader
		_wild_bark_mat = _bark_mat.duplicate()
		_wild_bark_mat.set_shader_parameter("fade_on", true)
	return _wild_bark_mat if fades else _bark_mat


## A square of overlapping leaves on transparency, drawn once at start-up.
static func _leaf_texture() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Leaves thin out toward the edge, so a card's outline is ragged.
	for k in 380:
		var c := Vector2(rng.randf_range(10, size - 10), rng.randf_range(10, size - 10))
		if (c - Vector2(size, size) * 0.5).length() > size * rng.randf_range(0.3, 0.52):
			continue
		var ang := rng.randf_range(0, TAU)
		var len := rng.randf_range(8.0, 13.0)
		var wid := len * rng.randf_range(0.45, 0.6)
		var shade := rng.randf_range(0.62, 1.0)
		var dir := Vector2(cos(ang), sin(ang))
		for y in range(int(c.y - len), int(c.y + len) + 1):
			for x in range(int(c.x - len), int(c.x + len) + 1):
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var d := Vector2(x, y) - c
				var along := d.dot(dir) / len
				var across := d.dot(Vector2(-dir.y, dir.x)) / wid
				if along * along + across * across <= 1.0:
					# Lighter toward the tip on the sunny side, a faint midrib.
					var l := shade * (0.88 + 0.12 * along) * (0.9 if absf(across) < 0.08 else 1.0)
					img.set_pixel(x, y, Color(l, l, l, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
