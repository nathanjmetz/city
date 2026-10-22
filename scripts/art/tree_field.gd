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

enum Species { MAPLE, OAK, LOCUST, SPRUCE, CRABAPPLE }

## Summer leaf colours (sRGB) and how much each tree can vary from them.
const LEAF := [Color("#46661f"), Color("#3f5c1e"), Color("#627424"), Color("#2c4433"), Color("#4a6326")]

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaf_tex : filter_linear_mipmap;
varying float inner;
varying vec3 tint;
varying vec3 crown_normal;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 1.1 + origin.x * 0.31 + origin.z * 0.17;
	float sway = sin(phase + VERTEX.y * 0.25) * 0.025 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
	inner = COLOR.r;
	// Keep the crown normal on both sides of each card (no back-face flip),
	// so the whole crown shades like one soft volume.
	crown_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = lin(INSTANCE_CUSTOM.rgb);
}
void fragment() {
	vec4 t = texture(leaf_tex, UV);
	NORMAL = crown_normal;
	ALBEDO = tint * t.rgb * mix(0.5, 1.15, inner) * 2.0;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
}
"""

const BARK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
void fragment() {
	float ridges = 0.85 + 0.15 * sin(UV.x * 40.0 + sin(UV.y * 6.0) * 2.0);
	ALBEDO = vec3(0.085, 0.07, 0.058) * ridges;
	ROUGHNESS = 0.95;
}
"""

static var _meshes := {}
static var _leaf_mat: ShaderMaterial
static var _bark_mat: ShaderMaterial

var _trees := {}  # owner key -> Array of [Transform3D, species, tint]
var _multis := {}  # species -> MultiMeshInstance3D
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
	var by_species := {}
	for list in _trees.values():
		for t in list:
			if not by_species.has(t[1]):
				by_species[t[1]] = []
			by_species[t[1]].append(t)
	for sp in Species.values():
		var list: Array = by_species.get(sp, [])
		if not _multis.has(sp):
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = tree_mesh(sp)
			mmi.multimesh = mm
			add_child(mmi)
			_multis[sp] = mmi
		var multi: MultiMesh = _multis[sp].multimesh
		multi.instance_count = list.size()
		for i in list.size():
			multi.set_instance_transform(i, list[i][0])
			multi.set_instance_custom_data(i, list[i][2])


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

static func tree_mesh(sp: int) -> ArrayMesh:
	if _meshes.has(sp):
		return _meshes[sp]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + sp
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	match sp:
		Species.SPRUCE: _spruce(rng, leaves, wood)
		_: _broadleaf(sp, rng, leaves, wood)
	var mesh := ArrayMesh.new()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _leaf_material())
	wood.commit(mesh)
	mesh.surface_set_material(1, _bark_material())
	_meshes[sp] = mesh
	return mesh


## Crown shape per species: height to crown centre, radii, cluster count,
## card size and trunk radius. Sizes are mature trees, in metres.
static func _broadleaf(sp: int, rng: RandomNumberGenerator, leaves: SurfaceTool, wood: SurfaceTool) -> void:
	var shape: Array = {
		Species.MAPLE: [9.5, Vector3(6.0, 5.5, 6.0), 26, 2.4, 0.3],
		Species.OAK: [9.0, Vector3(7.5, 4.8, 7.0), 22, 2.6, 0.38],
		Species.LOCUST: [10.0, Vector3(6.0, 4.5, 5.5), 18, 1.9, 0.24],
		Species.CRABAPPLE: [3.6, Vector3(3.0, 2.3, 3.0), 12, 1.5, 0.12],
	}[sp]
	var hc: float = shape[0]
	var rad: Vector3 = shape[1]
	var clusters: int = shape[2]
	var card: float = shape[3]
	var trunk: float = shape[4]
	var center := Vector3(0, hc, 0)
	var fork := hc - rad.y * 0.45
	_limb(wood, Vector3.ZERO, Vector3(0, fork, 0), trunk, trunk * 0.75)
	var cards_per := 9 if sp == Species.LOCUST else 12
	for c in clusters:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.55, 1), rng.randf_range(-1, 1)).normalized()
		var cc := center + dir * rad * rng.randf_range(0.45, 0.85)
		if c % 3 == 0:
			_limb(wood, Vector3(0, fork, 0), cc.lerp(center, 0.25), trunk * 0.55, trunk * 0.2)
		for i in cards_per:
			var p := cc + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.7), rng.randf_range(-1, 1)) * card * 0.75
			_card(leaves, rng, p, center, rad, card * rng.randf_range(0.8, 1.2))


static func _spruce(rng: RandomNumberGenerator, leaves: SurfaceTool, wood: SurfaceTool) -> void:
	var h := 13.0
	var base_r := 3.6
	_limb(wood, Vector3.ZERO, Vector3(0, h, 0), 0.25, 0.04)
	var tiers := 16
	for t in tiers:
		var f := float(t) / tiers
		var y := 1.2 + f * (h - 1.6)
		var r := base_r * (1.0 - f) + 0.35
		var n := int(4 + r * 3.0)
		for i in n:
			var a := TAU * (i + rng.randf()) / n
			var p := Vector3(cos(a) * r * rng.randf_range(0.45, 0.85), y, sin(a) * r * rng.randf_range(0.45, 0.85))
			_card(leaves, rng, p, Vector3(0, y + 0.8, 0), Vector3(r + 0.5, 1.5, r + 0.5), 1.4 + r * 0.35)


## One leaf card, randomly turned, with normals out from the crown centre.
static func _card(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, center: Vector3, rad: Vector3, size: float) -> void:
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


static func _leaf_material() -> ShaderMaterial:
	if _leaf_mat == null:
		var shader := Shader.new()
		shader.code = LEAF_SHADER
		_leaf_mat = ShaderMaterial.new()
		_leaf_mat.shader = shader
		_leaf_mat.set_shader_parameter("leaf_tex", _leaf_texture())
	return _leaf_mat


static func _bark_material() -> ShaderMaterial:
	if _bark_mat == null:
		var shader := Shader.new()
		shader.code = BARK_SHADER
		_bark_mat = ShaderMaterial.new()
		_bark_mat.shader = shader
	return _bark_mat


## A square of overlapping leaves on transparency, drawn once at start-up.
static func _leaf_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 70:
		var c := Vector2(rng.randf_range(12, size - 12), rng.randf_range(12, size - 12))
		var ang := rng.randf_range(0, TAU)
		var len := rng.randf_range(9.0, 15.0)
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
