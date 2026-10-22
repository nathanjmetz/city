class_name HouseMaterials
extends RefCounted
## Shared materials for HouseBuilder. One material per kind for every house;
## each house's own colours ride in the vertex colours, so a whole street
## costs a handful of materials. Patterns (lap siding, brick courses, shingle
## tabs) are drawn in the shader and fade to their average colour with
## distance, so they never shimmer.

const COMMON := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
varying vec3 world_pos;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
"""

## Vinyl lap siding and garage door panels: boards with a shadowed lip.
const SIDING := """
void fragment() {
	// Vertex alpha 1: 8 in siding laps; alpha 0: garage door panels.
	float lap = mix(0.53, 0.2, COLOR.a);
	float depth = mix(0.16, 0.24, COLOR.a);
	float t = UV.y / lap;
	float f = fract(t);
	float s = mix(1.0 - depth * 0.5, 1.03, smoothstep(0.0, 0.85, f));
	s *= 1.0 - depth * (1.0 - smoothstep(0.0, 0.07, f));
	// Fade the pattern out before it gets smaller than two pixels, so it
	// never shimmers while the camera moves.
	s = mix(s, 1.0 - depth * 0.4, smoothstep(0.12, 0.45, fwidth(t)));
	// Dirt splashed up near the ground, and faint weathering.
	float grime = 1.0 - 0.12 * (1.0 - smoothstep(0.3, 1.5, UV.y));
	float n = texture(noise_soft, world_pos.xz / 9.0 + world_pos.y / 13.0).r;
	ALBEDO = lin(COLOR.rgb) * s * grime * (0.95 + n * 0.1);
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
}
"""

## Modular brick: 2 2/3 in courses, running bond, light mortar.
const BRICK := """
uniform vec4 mortar : source_color = vec4(0.70, 0.68, 0.63, 1.0);
void fragment() {
	float t = UV.y / 0.0677;
	float row = floor(t);
	float x = UV.x / 0.2032 + 0.5 * mod(row, 2.0);
	float fx = fract(x);
	float fy = fract(t);
	float aa = smoothstep(0.12, 0.45, max(fwidth(t), fwidth(x)));
	float joint = max(1.0 - smoothstep(0.0, 0.14, fy), 1.0 - smoothstep(0.0, 0.05, min(fx, 1.0 - fx)));
	joint = mix(joint, 0.16, aa);
	float tint = mix(0.84 + hash(vec2(row, floor(x))) * 0.3, 1.0, aa);
	vec3 col = mix(lin(COLOR.rgb) * tint, mortar.rgb, joint);
	col *= 0.93 + texture(noise_grain, UV * 2.0).r * 0.14;
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

## Three-tab asphalt shingles: 5 5/8 in courses, 12 in tabs, colour blend
## from tab to tab, shadow lines, and weathering streaks.
const ROOF := """
void fragment() {
	float t = UV.y / 0.143;
	float row = floor(t);
	float x = UV.x / 0.333 + 0.5 * mod(row, 2.0) + hash(vec2(row, 3.0)) * 0.2;
	float fx = fract(x);
	float fy = fract(t);
	float aa = smoothstep(0.12, 0.45, max(fwidth(t), fwidth(x)));
	float tint = 0.86 + hash(vec2(row, floor(x))) * 0.26;
	float edge = mix(0.62, 1.0, smoothstep(0.0, 0.16, fy));
	float slot = 1.0 - (1.0 - smoothstep(0.0, 0.025, min(fx, 1.0 - fx))) * 0.35;
	float s = mix(tint * edge * slot, 0.93, aa);
	// Weathering: big soft patches and the odd dark algae streak.
	float w = texture(noise_soft, world_pos.xz / 14.0).r;
	float streak = smoothstep(0.62, 0.8, texture(noise_soft, vec2(world_pos.x / 2.0, world_pos.y / 30.0)).r);
	vec3 col = lin(COLOR.rgb) * s * (0.9 + w * 0.2) * (1.0 - streak * 0.18);
	col *= 0.94 + texture(noise_grain, UV * 3.0).r * 0.12 * (1.0 - aa);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
"""

## Window glass: dark rooms behind, blinds pulled to different heights
## (vertex alpha), and sky reflected more strongly at grazing angles.
const GLASS := """
void fragment() {
	vec3 room = vec3(0.018, 0.02, 0.022);
	float blinds = step(1.0 - COLOR.a, UV.y);
	float slat = 0.85 + 0.15 * smoothstep(0.3, 0.5, fract(UV.y * 28.0));
	vec3 col = mix(room, lin(COLOR.rgb) * 0.3 * slat, blinds);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 sky = mix(vec3(0.20, 0.26, 0.34), vec3(0.45, 0.52, 0.60), UV.y);
	ALBEDO = mix(col, sky, 0.12 + 0.55 * fres);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
"""

## Ground work, by vertex alpha: concrete drives and walks (0), asphalt
## lots (0.4), painted lines (0.72, colour in rgb), mulch or gravel (1).
const YARD := """
uniform vec4 concrete : source_color = vec4(0.67, 0.66, 0.62, 1.0);
uniform vec4 asphalt : source_color = vec4(0.30, 0.30, 0.30, 1.0);
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 150.0, 0.0, 1.0);
	float along = UV.y * 4.0;
	float d = abs(fract(along / 3.0 + 0.5) - 0.5) * 3.0;
	float joint = 1.0 - smoothstep(0.01, 0.01 + fwidth(along) * 1.5, d);
	joint *= clamp(0.02 / max(fwidth(along), 0.0001), 0.0, 1.0);  // thinner than a pixel: fade
	float stain = smoothstep(0.55, 0.85, texture(noise_soft, p / 4.0).r);
	float grain = texture(noise_grain, p / 0.6).r;
	vec3 drive = concrete.rgb * (1.0 - stain * 0.12) * (1.0 - joint * 0.4 * close) * (0.95 + grain * 0.1);
	vec3 lot = asphalt.rgb * (0.85 + texture(noise_soft, p / 20.0).r * 0.3) * (1.0 - stain * 0.15)
		* (1.0 + (texture(noise_grain, p / 0.3).r - 0.5) * 0.25 * close);
	float wear = smoothstep(0.4, 0.7, texture(noise_grain, p / 1.1).r);
	vec3 line = mix(lin(COLOR.rgb), asphalt.rgb, wear * 0.45);
	float chips = texture(noise_grain, p / 0.12).r;
	vec3 loose = lin(COLOR.rgb) * (0.6 + chips * 0.8);
	vec3 col = drive;
	col = mix(col, lot, step(0.2, COLOR.a));
	col = mix(col, line, step(0.6, COLOR.a));
	col = mix(col, loose, step(0.86, COLOR.a));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
"""

## Ribbed metal panels (walls and roofs of metal buildings): ribs every 12 in
## across UV.x, catching light on one side.
const METAL := """
void fragment() {
	float t = UV.x / 0.305;
	float f = fract(t);
	float rib = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.16, 0.24, f));
	float s = 1.0 - 0.18 * (1.0 - smoothstep(0.24, 0.3, f)) + rib * 0.12;
	s = mix(s, 0.97, smoothstep(0.12, 0.45, fwidth(t)));
	float streak = texture(noise_soft, vec2(world_pos.x + world_pos.z, world_pos.y * 0.15) / 6.0).r;
	float grime = 1.0 - 0.1 * (1.0 - smoothstep(0.2, 1.2, world_pos.y));
	ALBEDO = lin(COLOR.rgb) * s * grime * (0.93 + streak * 0.12);
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
}
"""

## Store signs: a coloured panel (vertex colour) with a line of pale block
## letters that reads as a name from the street. UV.x is metres along the
## sign, UV.y runs 0..1 up it, and vertex alpha carries the width / 30.
const SIGN := """
void fragment() {
	float nx = UV.x / max(COLOR.a * 30.0, 0.1);
	float pitch = 0.42;
	float i = floor(UV.x / pitch);
	vec2 q = (vec2(fract(UV.x / pitch), UV.y) - vec2(0.15, 0.25)) / vec2(0.7, 0.53);
	float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	vec2 cell = floor(q * vec2(3.0, 5.0));
	float on = step(0.4, hash(vec2(i * 7.0 + cell.x, cell.y + COLOR.r * 97.0)));
	float gap = step(0.12, hash(vec2(i, 3.3 + COLOR.g * 31.0)));
	float band = step(0.12, nx) * step(nx, 0.88);
	float text = inside * on * gap * band;
	float aa = smoothstep(0.08, 0.3, fwidth(UV.x / pitch));
	text = mix(text, 0.3 * band * step(0.25, UV.y) * step(UV.y, 0.78), aa);
	ALBEDO = mix(lin(COLOR.rgb), vec3(0.86, 0.84, 0.79), text);
	ROUGHNESS = 0.4;
	SPECULAR = 0.5;
}
"""

static var _cache := {}
static var _soft: NoiseTexture2D
static var _grain: NoiseTexture2D


static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var mat: Material
	match key:
		"siding": mat = _shader(SIDING)
		"brick": mat = _shader(BRICK)
		"roof": mat = _shader(ROOF)
		"glass": mat = _shader(GLASS)
		"yard": mat = _shader(YARD)
		"metal": mat = _shader(METAL)
		"sign": mat = _shader(SIGN)
		"foliage": mat = _plain(1.0)
		_: mat = _plain(0.55)  # paint, shutters, trim
	_cache[key] = mat
	return mat


static func _shader(body: String) -> ShaderMaterial:
	if _soft == null:
		_soft = Ground.noise(512, 0.012, 4, 71)
		_grain = Ground.noise(256, 0.09, 2, 83)
	var shader := Shader.new()
	shader.code = COMMON + body
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_soft", _soft)
	mat.set_shader_parameter("noise_grain", _grain)
	return mat


static func _plain(roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
