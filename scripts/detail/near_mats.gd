class_name NearMats
extends RefCounted
## Shaders for the close-up detail (NearDetail): brick by brick, lap by lap
## and course by course. Made once and shared by every building; each
## building's colours ride on its instances (MultiMesh custom data), never
## on a material of its own.
##
## The detail shows within `near_a` of the camera and dissolves out by
## `near_b` (a dither on the screen, in both renderers and in shadows too),
## over the building's own drawing, which is whole underneath: the walls'
## and roofs' painted-on pattern shows through where the detail has gone.
## The distances follow the graphics tier (set_reach). With less than 4x
## antialiasing the detail also dissolves where a pixel covers more than
## `px_full` metres of wall (gone by `px_none`): laps and courses finer than
## a couple of pixels would only shimmer, and the drawing underneath has
## them painted on, fading as they should.
## From the lab: tools/scale/new_drawing/mats.gd.

const COMMON := """
uniform float near_a = 90.0;
uniform float near_b = 110.0;
uniform float px_full = 100.0;
uniform float px_none = 200.0;
global uniform float snow;
vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
// Instance colours are given in sRGB: the Compatibility renderer (the
// browser's) shows them as given, the desktop one works in linear light.
vec3 inst_rgb(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return lin(c);
#endif
}
// The main camera, even while drawing shadows (so a piece fades the same
// in its shadow as on screen).
#define MAIN_CAM MAIN_CAM_INV_VIEW_MATRIX[3].xyz
float dith(vec2 fc) { return fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715)))); }
uint hash_u(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return v.x ^ v.y ^ v.z;
}
float hash3(vec3 p) { return float(hash_u(uvec3(ivec3(floor(p)) + 1048576)) & 65535u) / 65535.0; }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x), mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x), mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
varying float near_w;
// Each piece fades by its own distance; past near_b it isn't drawn at all.
#define NEAR_VERTEX near_w = 1.0 - smoothstep(near_a, near_b, distance(MODEL_MATRIX[3].xyz, MAIN_CAM)); if (near_w <= 0.0) { VERTEX = vec3(0.0); }
#define NEAR_FRAGMENT float near_px = near_w * (1.0 - smoothstep(px_full, px_none, length(fwidth(VERTEX)))); if (near_px < 1.0 && dith(FRAGCOORD.xy) >= near_px) { discard; }
"""

## Brick: each brick a shade of the wall's own brick colour (custom RGB),
## from its place in the world, with a sand-struck face, pits and grit.
const BRICK := """shader_type spatial;
render_mode cull_back;
varying vec3 lp;
varying vec3 tint;
varying float pick;
""" + COMMON + """
void vertex() {
	NEAR_VERTEX;
	lp = VERTEX + vec3(hash3(MODEL_MATRIX[3].xyz * 3.0) * 17.0);
	vec3 centre = (MODEL_MATRIX * vec4(UV2.x, UV2.y, 0.0, 1.0)).xyz;
	pick = hash3(centre * 40.0);
	tint = inst_rgb(INSTANCE_CUSTOM.rgb);
}
void fragment() {
	NEAR_FRAGMENT;
	float fine = vnoise(lp * 900.0);
	float grit = vnoise(lp * 2600.0);
	float mott = vnoise(lp * 40.0);
	// A brick order runs a range of shades around its colour: darker
	// flashed ends, lighter salmon ones, a few a little off in hue.
	vec3 c = tint * mix(0.74, 1.18, pick) * mix(vec3(1.0), vec3(1.06, 0.96, 0.93), step(0.7, fract(pick * 13.0)));
	c *= (0.9 + mott * 0.16) * (0.93 + fine * 0.1);
	c = mix(c, c * vec3(0.55, 0.5, 0.48), smoothstep(0.82, 0.95, grit) * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.88 + fine * 0.1;
	SPECULAR = 0.3;
}
"""

## The mortar behind the bricks, set back in the joints.
const MORTAR := """shader_type spatial;
render_mode cull_back;
uniform vec3 colour : source_color = vec3(0.70, 0.68, 0.63);
varying vec3 wp;
""" + COMMON + """
void vertex() { NEAR_VERTEX; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	NEAR_FRAGMENT;
	float n = vnoise(wp * 300.0);
	ALBEDO = colour * (0.8 + 0.3 * n);
	ROUGHNESS = 0.97;
}
"""

## Vinyl lap siding in each wall's own colour, the embossed grain along the
## board, a little grime splashed up near the ground.
const BOARD := """shader_type spatial;
render_mode cull_back;
varying vec3 col;
varying vec3 lp;
varying float wy;
""" + COMMON + """
void vertex() {
	NEAR_VERTEX;
	col = inst_rgb(INSTANCE_CUSTOM.rgb);
	lp = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), 1.0, 1.0);
	wy = INSTANCE_CUSTOM.a + VERTEX.y;
}
void fragment() {
	NEAR_FRAGMENT;
	float g = vnoise(vec3(lp.x * 60.0, lp.y * 900.0, 0.0));
	float grime = 1.0 - 0.12 * (1.0 - smoothstep(0.3, 1.5, wy));
	// The shadow each lap's butt throws on the face below it (too fine for
	// the sun's shadow map to draw).
	float f = fract(lp.y / 0.1016);
	float shade = mix(1.0, 0.74, smoothstep(0.72, 1.0, f));
	ALBEDO = col * (0.95 + 0.1 * g) * grime * shade;
	ROUGHNESS = 0.5;
	SPECULAR = 0.4;
}
"""

## Three-tab asphalt shingles, 12 in tabs, each course's slots staggered
## (custom alpha) and each tab a shade off; snow lies on them in winter as
## on the roof's own drawing.
const SHINGLE := """shader_type spatial;
render_mode cull_back;
varying vec3 col;
varying float off;
varying vec3 lp;
varying float len_m;
varying vec3 wp;
varying float up;
""" + COMMON + """
void vertex() {
	NEAR_VERTEX;
	col = inst_rgb(INSTANCE_CUSTOM.rgb);
	off = INSTANCE_CUSTOM.a;
	len_m = length(MODEL_MATRIX[0].xyz);
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
void fragment() {
	NEAR_FRAGMENT;
	float x = lp.x * len_m + off * 0.3048;
	float tx = x / 0.3048;
	float tab = floor(tx);
	// The slots between tabs, fading out before they're finer than a pixel
	// (never a shimmer of dots far off).
	float fw = fwidth(tx);
	float edge = min(fract(tx), 1.0 - fract(tx));
	float slot = (1.0 - smoothstep(0.012, 0.012 + fw, edge)) * step(lp.y, 0.115) * (1.0 - smoothstep(0.03, 0.12, fw));
	float t = hash3(vec3(tab, off * 31.0, 0.0));
	// Granules: a soft mottle, with grit only where it's big enough to see.
	float mott = vnoise(vec3(x * 6.0, lp.y * 6.0, off * 13.0));
	float grit = mix(vnoise(vec3(x * 300.0, lp.y * 300.0, off * 7.0)), 0.5, smoothstep(0.004, 0.02, fwidth(x)));
	vec3 c = col * (0.86 + t * 0.24) * (0.92 + mott * 0.16) * (0.9 + grit * 0.2);
	// The shadow under the next course's butt.
	c *= mix(1.0, 0.7, smoothstep(0.085, 0.127, lp.y));
	c = mix(c, c * 0.3, slot);
	float cover = smoothstep(0.35, 0.6, up) * smoothstep(0.15, 0.55, snow * 0.9 + vnoise(wp / 6.0) * 0.35 - 0.1);
	ALBEDO = mix(c, vec3(0.86, 0.88, 0.92), cover);
	ROUGHNESS = mix(0.95, 0.7, cover);
	SPECULAR = 0.25;
}
"""

static var _cache := {}
static var _a := 90.0
static var _b := 110.0
static var _px := Vector2(100.0, 200.0)


## The shared material for an instance kind.
static func get_mat(kind: String) -> ShaderMaterial:
	var name := "brick" if kind.begins_with("brick_") else kind
	if _cache.has(name):
		return _cache[name]
	var sh := Shader.new()
	match name:
		"brick": sh.code = BRICK
		"mortar": sh.code = MORTAR
		"board": sh.code = BOARD
		_: sh.code = SHINGLE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("near_a", _a)
	m.set_shader_parameter("near_b", _b)
	m.set_shader_parameter("px_full", _px.x)
	m.set_shader_parameter("px_none", _px.y)
	_cache[name] = m
	return m


## How far the detail reaches: shown within `a` metres, gone by `b`; and
## how big a pixel may be on the wall (metres) before it dissolves.
static func set_reach(a: float, b: float, px := Vector2(100.0, 200.0)) -> void:
	_a = a
	_b = b
	_px = px
	for k in _cache:
		_cache[k].set_shader_parameter("near_a", a)
		_cache[k].set_shader_parameter("near_b", b)
		_cache[k].set_shader_parameter("px_full", px.x)
		_cache[k].set_shader_parameter("px_none", px.y)
