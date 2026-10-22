class_name Surfaces
extends RefCounted
## Road and pavement materials, benchmarked against photos of real
## Midwestern residential streets:
##   - asphalt is a mid grey that varies by age from block to block, with
##     darker repair patches, black crack-sealer squiggles, oil drips and a
##     speckled aggregate grain up close
##   - sidewalks are pale concrete slabs with a joint every 5 ft and slightly
##     different tints from slab to slab
##   - paint is worn: brightest at the edges of the wheel paths, faded and
##     patchy elsewhere
## All shaders are cheap world-space ones that run in the Compatibility renderer.
## Ribbon meshes from RoadMesh carry the distance along the road in UV.y / 4.

## Sidewalk slabs are 5 ft long (the usual US contraction-joint spacing).
const SLAB := 1.524

const COMMON := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D noise_soft : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : filter_linear_mipmap, repeat_enable;
varying vec3 world_pos;
vec2 turn(vec2 p, float a) {
	return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
"""

const ASPHALT := """
uniform vec4 fresh : source_color = vec4(0.28, 0.27, 0.27, 1.0);
uniform vec4 faded : source_color = vec4(0.42, 0.41, 0.39, 1.0);
uniform vec4 tar : source_color = vec4(0.10, 0.10, 0.10, 1.0);
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 220.0, 0.0, 1.0);
	// Streets were paved in different years, so the grey drifts block to block.
	float age = texture(noise_soft, p / 170.0).r;
	vec3 col = mix(fresh.rgb, faded.rgb, smoothstep(0.2, 0.8, age) * 0.8 + 0.1);
	// Utility cuts: the odd newer, darker rectangle across part of the road.
	float along = UV.y * 4.0;
	float across = UV.x * 4.0;
	float cell = floor(along / 9.0);
	vec2 block = floor(p / 60.0);
	float h = fract(sin(cell * 78.233 + block.x * 12.989 + block.y * 4.141) * 43758.5453);
	float h2 = fract(h * 91.7);
	float in_cut = step(0.86, h) * step(h2 * 0.6, across) * step(across, h2 * 0.6 + 0.35)
		* step(2.0, mod(along, 9.0)) * step(mod(along, 9.0), 2.0 + 1.5 + h2 * 3.0);
	col = mix(col, fresh.rgb * 0.92, in_cut * 0.8);
	// Crack sealer: thin black squiggles along noise contour lines, only in
	// older stretches.
	float c = texture(noise_soft, turn(p, 2.0) / 23.0 + 0.7).r;
	float crack = 1.0 - smoothstep(0.0, fwidth(c) * 0.9 + 0.0008, abs(c - 0.5));
	float cracked = smoothstep(0.66, 0.74, texture(noise_soft, p / 90.0 + 0.2).r);
	col = mix(col, tar.rgb, crack * cracked * close * 0.6);
	// Oil drips and tyre grime.
	float oil = smoothstep(0.70, 0.86, texture(noise_grain, turn(p, 1.4) / 3.3).r);
	col *= 1.0 - oil * 0.1 * close;
	// Aggregate speckle up close.
	float g = texture(noise_grain, p / 0.31).r;
	col *= 1.0 + (g - 0.5) * 0.28 * close;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
"""

const CONCRETE := """
uniform vec4 base : source_color = vec4(0.70, 0.69, 0.65, 1.0);
uniform float joints = 1.0;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float along = UV.y * 4.0;
	float slab = floor(along / %f);
	float tint = fract(sin(slab * 12.9898 + 3.1) * 43758.5453);
	vec3 col = base.rgb * (0.94 + tint * 0.09);
	// Weathering stains and grit.
	float stain = texture(noise_soft, turn(p, 0.5) / 9.0).r;
	col *= 1.0 - smoothstep(0.55, 0.85, stain) * 0.06;
	col *= 1.0 + (texture(noise_grain, p / 0.5).r - 0.5) * 0.16 * close;
	// A tooled joint line every slab.
	float d = abs(fract(along / %f + 0.5) - 0.5) * %f;
	float joint = 1.0 - smoothstep(0.012, 0.012 + fwidth(along) * 1.5, d);
	col *= 1.0 - joint * joints * 0.45 * close;
	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
}
""" % [SLAB, SLAB, SLAB]

const PAINT := """
uniform vec4 paint : source_color = vec4(0.88, 0.88, 0.86, 1.0);
uniform vec4 under : source_color = vec4(0.36, 0.36, 0.36, 1.0);
void fragment() {
	vec2 p = world_pos.xz;
	float wear = texture(noise_grain, turn(p, 0.9) / 1.3).r * 0.6
		+ texture(noise_soft, p / 40.0).r * 0.4;
	vec3 col = mix(paint.rgb, under.rgb, smoothstep(0.42, 0.68, wear) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	SPECULAR = 0.35;
}
"""

static var _cache := {}
static var _soft: NoiseTexture2D
static var _grain: NoiseTexture2D


static func asphalt() -> ShaderMaterial:
	return _make("asphalt", ASPHALT, {})


## Sidewalk slabs with joints, or plain cast concrete (curbs, bridges).
static func concrete(color: Color, slabs := false) -> ShaderMaterial:
	return _make("concrete %s %s" % [color, slabs], CONCRETE,
			{"base": color, "joints": 1.0 if slabs else 0.0})


static func paint(color: Color) -> ShaderMaterial:
	return _make("paint %s" % color, PAINT, {"paint": color})


static func _make(key: String, body: String, params: Dictionary) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var shader := Shader.new()
	shader.code = COMMON + body
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if _soft == null:
		_soft = Ground.noise(512, 0.012, 4, 41)
		_grain = Ground.noise(256, 0.09, 2, 57)
	mat.set_shader_parameter("noise_soft", _soft)
	mat.set_shader_parameter("noise_grain", _grain)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	_cache[key] = mat
	return mat
