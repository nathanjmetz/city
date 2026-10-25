extends RefCounted
## Shaders and shared materials for the new drawing style. Every material is
## made once and shared by every building: colours that differ from building
## to building ride on the instances (MultiMesh custom data), never on a
## material of their own.
##
## Distances (metres from the camera): the grown close-up version shows
## within NEAR_A, cross-fades with a dither to NEAR_B; the lighter middle
## version's pieces show to MID_A and fade out by MID_B, leaving the plain
## shapes.

const NEAR_A := 90.0
const NEAR_B := 110.0
const MID_A := 280.0
const MID_B := 320.0

const COMMON := """
const float NEAR_A = 90.0;
const float NEAR_B = 110.0;
const float MID_A = 280.0;
const float MID_B = 320.0;
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
// A colour written in the shader (sRGB): the Compatibility renderer shows
// what it is given as is, the desktop one works in linear light.
vec3 const_rgb(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return lin(c);
#endif
}
// The main camera, even while drawing shadows (so a building fades the same
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
"""

## The close-up pieces fade in by the building's own distance (its node
## sits at its footprint's middle, so every piece of it fades together).
const NEAR_FADE_V := """
varying float near_w;
#define NEAR_VERTEX near_w = 1.0 - smoothstep(NEAR_A, NEAR_B, distance(NODE_POSITION_WORLD, MAIN_CAM))
"""
const NEAR_FADE_F := """
	if (near_w < 1.0 && dith(FRAGCOORD.xy) >= near_w) discard;
"""

## Brick (and concrete block): each unit's colour from its place in the
## world, a sand-struck face with pits and grit (as in the brick lab, 2026-10-25).
const BRICK := """shader_type spatial;
render_mode cull_back;
uniform bool block = false;
varying vec3 lp;
varying vec3 tint;
varying float pick;
// A Midwest red range, from a dark flashed red to a light salmon red.
const vec3 RED_DARK = vec3(0.369, 0.165, 0.133);
const vec3 RED_LIGHT = vec3(0.612, 0.329, 0.251);
""" + "%s" + """
void vertex() {
	NEAR_VERTEX;
	lp = VERTEX + vec3(hash3((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz * 3.0) * 17.0);
	vec3 centre = (MODEL_MATRIX * vec4(UV2.x, UV2.y, 0.0, 1.0)).xyz;
	pick = hash3(centre * 40.0);
	tint = INSTANCE_CUSTOM.rgb;
}
void fragment() {
""" + "%s" + """
	float fine = vnoise(lp * 900.0);
	float grit = vnoise(lp * 2600.0);
	float mott = vnoise(lp * 40.0);
	vec3 c;
	if (block) {
		c = inst_rgb(tint) * (0.86 + pick * 0.1) * (0.85 + grit * 0.25);
	} else {
		vec3 range = mix(RED_DARK, RED_LIGHT, pick) * mix(vec3(1.0), vec3(1.06, 0.97, 0.95), fract(pick * 13.0));
		c = const_rgb(range) * inst_rgb(tint) * (0.9 + mott * 0.16) * (0.93 + fine * 0.1);
		c *= 1.0 - fract(pick * 7.0) * 0.08;
		c = mix(c, vec3(dot(c, vec3(0.33))) * vec3(0.95, 0.9, 0.85), 0.18);
		c = mix(c, c * vec3(0.55, 0.5, 0.48), smoothstep(0.82, 0.95, grit) * 0.6);
	}
	ALBEDO = c;
	ROUGHNESS = 0.88 + fine * 0.1;
	SPECULAR = 0.3;
}
"""

## A plain finish in one colour: trim, mortar, house wrap, roof deck,
## concrete, lintels, coping, membrane.
const PLAIN := """shader_type spatial;
render_mode cull_back;
uniform vec3 colour : source_color = vec3(0.9);
uniform float rough = 0.6;
uniform float metal = 0.0;
uniform float grain = 0.0;
varying vec3 wp;
""" + "%s" + """
void vertex() { NEAR_VERTEX; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
""" + "%s" + """
	float n = grain > 0.0 ? vnoise(wp * 300.0) : 0.5;
	ALBEDO = colour * (1.0 - grain + grain * 2.0 * n);
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

## A finish in each instance's own colour (custom data): vinyl siding,
## metal panels, a door, ridge caps.
const INSTCOL := """shader_type spatial;
render_mode cull_back;
uniform float rough = 0.55;
uniform float metal = 0.0;
uniform float grain = 0.0;
varying vec3 col;
varying vec3 lp;
""" + "%s" + """
void vertex() { NEAR_VERTEX; col = inst_rgb(INSTANCE_CUSTOM.rgb); lp = VERTEX; }
void fragment() {
""" + "%s" + """
	// Vinyl's embossed wood grain runs along the board.
	float g = grain > 0.0 ? vnoise(vec3(lp.x * 60.0, lp.y * 900.0, 0.0)) : 0.5;
	ALBEDO = col * (1.0 - grain + grain * 2.0 * g);
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

## Three-tab asphalt shingles, 12 in tabs, courses 5 in to the weather,
## each course's slots staggered (custom alpha) and each tab a shade off.
const SHINGLE := """shader_type spatial;
render_mode cull_back;
varying vec3 col;
varying float off;
varying vec3 lp;
varying float len_m;
""" + "%s" + """
void vertex() {
	NEAR_VERTEX;
	col = inst_rgb(INSTANCE_CUSTOM.rgb);
	off = INSTANCE_CUSTOM.a;
	len_m = length(MODEL_MATRIX[0].xyz);
	lp = VERTEX;
}
void fragment() {
""" + "%s" + """
	float x = lp.x * len_m + off * 0.3048;
	float tab = floor(x / 0.3048);
	float slot = step(fract(x / 0.3048), 0.022) * step(lp.y, 0.11);
	float t = hash3(vec3(tab, off * 31.0, 0.0));
	float gran = vnoise(vec3(x * 500.0, lp.y * 500.0, off * 13.0));
	vec3 c = col * (0.85 + t * 0.25) * (0.8 + gran * 0.4);
	ALBEDO = mix(c, c * 0.25, slot);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
"""

const GLASS := """shader_type spatial;
render_mode cull_back;
""" + "%s" + """
void vertex() { NEAR_VERTEX; }
void fragment() {
""" + "%s" + """
	ALBEDO = vec3(0.05, 0.065, 0.08);
	METALLIC = 0.85;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
}
"""

## The plain shapes (and, nearer, the lighter middle version's walls and
## roofs). A unit box or roof, scaled per building: COLOR is the wall
## colour (alpha: the material code), custom the roof colour (alpha: the
## close-up version is ready). UV.x marks roof faces. Inside MID_B the faces
## pick up the real-size pattern of their material (brick courses, laps,
## shingle courses); outside it windows are painted on where the middle
## version had real ones.
const SHAPE := """shader_type spatial;
render_mode cull_back;
uniform bool hip = false;
uniform bool gable = false;
varying float show;
varying float mid;
varying vec3 wall_c;
varying vec3 roof_c;
varying float code;
varying vec3 lp;
varying vec3 ln;
varying float is_roof;
""" + COMMON + """
void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (hip && UV2.x > 0.5) {
		VERTEX.x = sign(VERTEX.x) * max(0.5 - 0.5 * sc.z / sc.x, 0.0);
	}
	if (gable) {
		// Eaves overhang 0.3 m, rakes 0.2 m; the gable triangle stands on
		// the wall below it.
		if (UV.x > 0.5) { VERTEX.x *= 1.0 + 0.4 / sc.x; }
		else {
			VERTEX.z *= 1.0 - 0.6 / sc.z;
			if (VERTEX.y < 0.01) { VERTEX.y = 0.6 / sc.z; }
		}
	}
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(o, MAIN_CAM);
	float ready = step(0.5, INSTANCE_CUSTOM.a);
	show = ready > 0.5 ? smoothstep(NEAR_A, NEAR_B, d) : 1.0;
	if (show <= 0.0) { VERTEX = vec3(0.0); }
	mid = 1.0 - smoothstep(MID_A - 40.0, MID_B, d);
	wall_c = inst_rgb(COLOR.rgb);
	roof_c = inst_rgb(INSTANCE_CUSTOM.rgb);
	code = floor(COLOR.a * 8.0);
	lp = VERTEX * sc;
	ln = NORMAL;
	is_roof = UV.x;
}
float lines(float x, float period, float width) {
	float f = abs(fract(x / period + 0.5) - 0.5) * period;
	float aa = fwidth(x) * 0.75;
	float l = 1.0 - smoothstep(width - aa, width + aa, f);
	// Lines finer than a pixel fade to their average, never shimmer.
	return l * (1.0 - smoothstep(period * 0.25, period * 0.6, aa * 2.0));
}
void fragment() {
	if (show < 1.0 && dith(FRAGCOORD.xy) >= show) discard;
	bool roof = is_roof > 0.5 || ln.y > 0.7;
	vec3 c;
	float rough = 0.85;
	if (roof) {
		c = roof_c;
		// Shingle courses, 5 in.
		float along = abs(ln.y) > 0.99 ? lp.z : length(vec2(lp.y, lp.z));
		c *= 1.0 - lines(along, 0.127, 0.01) * 0.25 * mid;
	} else {
		c = wall_c;
		float u = abs(ln.x) > 0.5 ? lp.z : lp.x;
		float v = lp.y - 1.25;
		if (v < 0.0 && !gable) { c = vec3(0.32, 0.31, 0.29); }
		else if (code < 0.5) {
			c *= 1.0 - lines(v, 0.1016, 0.006) * 0.3 * mid;
		} else if (code < 2.5) {
			// Brick: courses and head joints, mortar paler.
			float row = floor(v / 0.0677333);
			float hx = u + mod(row, 2.0) * 0.1016;
			float m = max(lines(v, 0.0677333, 0.005), lines(hx, 0.2032, 0.005));
			c = mix(c, vec3(0.25, 0.24, 0.22), m * 0.6 * mid);
		} else if (code > 3.5 && code < 4.5) {
			c *= 1.0 - lines(u, 0.3048, 0.02) * 0.3 * mid;
		} else {
			float m = max(lines(v, 0.2032, 0.005), lines(u + mod(floor(v / 0.2032), 2.0) * 0.2032, 0.4064, 0.005));
			c = mix(c, c * 0.7, m * mid);
		}
		// Far off, windows painted where the middle version had real ones.
		if (!gable && v > 0.0) {
			float glass = 0.0;
			float storey = code < 1.5 ? 2.8448 : 3.2512;
			if (code > 3.5 && code < 4.5 || code > 5.5) {
				glass = step(5.7, v) * step(v, 6.5) * step(fract(u / 3.25), 0.37);
			} else if (code > 4.5) {
				glass = step(0.4, fract(v / 3.6576)) * step(0.06, fract(u / 1.524));
			} else if (code > 1.5 && v < 4.0) {
				glass = step(0.4, v) * step(v, 3.25) * step(0.8, u) * step(u, 99.0);
			} else {
				float sv = fract(v / storey) * storey;
				glass = step(0.81, sv) * step(sv, 2.03) * step(0.35, fract(u / 2.44)) * step(fract(u / 2.44), 0.68);
			}
			c = mix(c, vec3(0.03, 0.04, 0.05), glass * (1.0 - mid) * 0.85);
			rough = mix(rough, 0.2, glass * (1.0 - mid));
		}
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
"""

## The lighter middle version's pieces: windows, doors, storefronts and
## overhead doors, each a unit quad set grown on the wall. Their frames keep
## their real width whatever the opening's size (UV2: metres from the
## corner each vertex is anchored to). UV.x: 0 frame, 1 glass, 2 door slab.
const EXTRA := """shader_type spatial;
render_mode cull_back;
varying float show;
varying float part;
varying vec3 col;
""" + COMMON + """
void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	VERTEX.xy += UV2 / sc.xy;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(o, MAIN_CAM);
	float ready = step(0.5, INSTANCE_CUSTOM.a);
	show = (1.0 - smoothstep(MID_A, MID_B, d)) * (ready > 0.5 ? smoothstep(NEAR_A, NEAR_B, d) : 1.0);
	if (show <= 0.0) { VERTEX = vec3(0.0); }
	part = UV.x;
	col = inst_rgb(INSTANCE_CUSTOM.rgb);
}
void fragment() {
	if (show < 1.0 && dith(FRAGCOORD.xy) >= show) discard;
	if (part > 0.5 && part < 1.5) {
		ALBEDO = vec3(0.05, 0.065, 0.08);
		METALLIC = 0.8;
		ROUGHNESS = 0.08;
	} else if (part > 1.5) {
		ALBEDO = col;
		ROUGHNESS = 0.5;
	} else {
		ALBEDO = col;
		ROUGHNESS = 0.5;
	}
}
"""

## Drives, walks and parking lots: concrete or asphalt, from the custom colour.
const PAVE := """shader_type spatial;
render_mode cull_back;
varying vec3 col;
varying vec3 wp;
""" + COMMON + """
void vertex() { col = inst_rgb(INSTANCE_CUSTOM.rgb); wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = col * (0.92 + vnoise(wp * 3.0) * 0.12);
	ROUGHNESS = 0.9;
}
"""

static var _cache := {}


static func _make(body: String, params := {}) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = body
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## A close-up shader: the common code and the distance fade spliced in.
static func _near(body: String) -> String:
	return body % [COMMON + NEAR_FADE_V, NEAR_FADE_F]


static var _shaders := {}


static func _near_shader(name: String, body: String) -> Shader:
	if not _shaders.has(name):
		var sh := Shader.new()
		sh.code = _near(body)
		_shaders[name] = sh
	return _shaders[name]


## Shared materials by name.
static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m := ShaderMaterial.new()
	match name:
		"brick":
			m.shader = _near_shader("brick", BRICK)
		"block":
			m.shader = _near_shader("brick", BRICK)
			m.set_shader_parameter("block", true)
		"glass":
			m.shader = _near_shader("glass", GLASS)
		"shingle":
			m.shader = _near_shader("shingle", SHINGLE)
		"siding":
			m.shader = _near_shader("instcol", INSTCOL)
			m.set_shader_parameter("grain", 0.06)
			m.set_shader_parameter("rough", 0.5)
		"metal_wall":
			m.shader = _near_shader("instcol", INSTCOL)
			m.set_shader_parameter("rough", 0.45)
			m.set_shader_parameter("metal", 0.35)
		"door":
			m.shader = _near_shader("instcol", INSTCOL)
			m.set_shader_parameter("rough", 0.35)
		"shape_box":
			m = _make(SHAPE)
		"shape_gable":
			m = get_mat("shape_box").duplicate()
			m.set_shader_parameter("gable", true)
		"shape_hip":
			m = get_mat("shape_box").duplicate()
			m.set_shader_parameter("hip", true)
		"extra":
			m = _make(EXTRA)
		"pave":
			m = _make(PAVE)
		_:
			m.shader = _near_shader("plain", PLAIN)
			var spec: Array = PLAINS.get(name, [Color(0.9, 0.9, 0.88), 0.6, 0.0, 0.0])
			m.set_shader_parameter("colour", spec[0])
			m.set_shader_parameter("rough", spec[1])
			m.set_shader_parameter("metal", spec[2])
			m.set_shader_parameter("grain", spec[3])
	_cache[name] = m
	return m


## The plain finishes: colour, roughness, metal, grain.
const PLAINS := {
	"trim": [Color("#ecebe6"), 0.5, 0.0, 0.0],
	"mortar": [Color(0.50, 0.48, 0.43), 0.97, 0.0, 0.25],
	"wrap": [Color(0.75, 0.76, 0.78), 0.8, 0.0, 0.0],
	"deck": [Color(0.18, 0.17, 0.16), 0.95, 0.0, 0.0],
	"concrete": [Color(0.58, 0.57, 0.53), 0.92, 0.0, 0.2],
	"dark": [Color(0.17, 0.17, 0.17), 0.6, 0.6, 0.0],
	"coping": [Color(0.62, 0.63, 0.62), 0.45, 0.6, 0.0],
	"membrane": [Color(0.78, 0.78, 0.75), 0.85, 0.0, 0.15],
	"alum": [Color(0.22, 0.2, 0.18), 0.4, 0.7, 0.0],
	"hvac": [Color(0.7, 0.71, 0.7), 0.5, 0.5, 0.0],
	"vinyl": [Color("#f1f0ec"), 0.45, 0.0, 0.0],
}
