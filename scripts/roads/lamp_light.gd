class_name LampLight
extends SubViewport
## Streetlight on the ground, the desktop way (Nathan, 2026-10-29: "lets make
## this game look totally real"). The look critic found each lamp's light was
## a flat yellow disc added over whatever lay under it, as bright on a lawn
## as on the road. Real cobra-head lights (IES RP-8, type II and III) throw a
## long, soft pool along the street and across it, little behind the pole,
## fading fast past about twice the mounting height; the light falls on what
## is there, so dark asphalt, pale concrete, grass and car roofs each show it
## in their own colour, and wet pavement mirrors it in a streak.
##
## Every lamp is drawn once, from above, into a map of the town (this
## viewport, 2D and float): per spot, the light falling on the ground (r),
## how strongly the lamps' heads shine on it from any angle, for their
## gleam on wet pavement (a), and, weighted by that, which way they are
## (g, b: metres to the lamp; where two overlap, a spot between). The
## road, sidewalk, land and car shaders read one spot of the map (GLSL), so
## the cost is the same for ten lamps or ten thousand. The map is drawn again
## only when the lamps move. Desktop only (Forward+): the browser keeps
## StreetLights' flat pools.
##
## Also carries the wet look's shared value (`weather_wet`, set by Weather):
## Shader values are added here at run time, not in the project settings.

## The map's size in pixels: about 1.7 m a pixel over a 1.7 km town.
const SIZE_HIGH := 2048
const SIZE_LOW := 1024
## Room round the lamps, metres.
const MARGIN := 80.0
## Lamp heads, metres up, for which way their light comes from (the map
## keeps no height; poles run 9 to 12 m).
const HEAD := 10.0
## 3000 K LED (StreetLights.LAMP), and how bright the brightest spot under a
## lamp is, against the game's own night light.
const STRENGTH := 1.4

## [name, type, default] of the shared shader values.
const GLOBALS := [
	["lamp_map", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null],
	["lamp_rect", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 0, 0)],
	["lamp_on", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 0, 0)],
	["weather_wet", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 0, 0)],
]

## Draws one lamp's light into the map. Local x runs along the road and y
## out over it (toward the street), both -1..1 over the stamp; custom data:
## half length along, half depth across, where the middle sits across, and
## the mounting height (metres).
const STAMP := """
shader_type canvas_item;
render_mode blend_add, unshaded;
varying vec2 local;
varying vec2 uv_m;
varying vec2 side;
varying vec2 fwd;
varying float height;
void vertex() {
	local = VERTEX;
	vec4 c = INSTANCE_CUSTOM;
	uv_m = vec2(VERTEX.x * c.x, VERTEX.y * c.y + c.z);
	side = normalize(MODEL_MATRIX[0].xy);
	fwd = normalize(MODEL_MATRIX[1].xy);
	height = c.w;
}
void fragment() {
	float h = height;
	float u = uv_m.x;
	float v = uv_m.y;
	// The pool: long along the road and out over it, short behind the pole
	// (the head is shielded on the house side), fading fast past about two
	// mounting heights; a little brighter right under the lens.
	float lu = u / (1.9 * h);
	float lv = v / ((v > 0.0 ? 1.3 : 0.4) * h);
	float r = length(vec2(u, v));
	float c3 = pow(h * h / (r * r + h * h), 1.5);
	float e = 0.82 * exp(-(lu * lu + lv * lv) * 2.0) + 0.18 * c3 * c3 * c3;
	// The gleam: how bright the lens looks from here. A street head throws
	// its strongest light out at 60 to 75 degrees (a "batwing", to spread
	// it down the road) and nothing past its cutoff or behind the pole, so
	// on wet pavement its reflection reaches several heights toward you.
	float w = sqrt(h * h / (r * r + h * h)) * (1.0 - smoothstep(3.0 * h, 4.4 * h, r))
		* smoothstep(-1.2 * h, -0.3 * h, v);
	// Nothing at the stamp's own edge.
	vec2 a = abs(local);
	float edge = 1.0 - smoothstep(0.8, 1.0, max(a.x, a.y));
	e *= edge;
	w *= edge;
	// Metres from this spot to under the lens, in the map's directions.
	vec2 to = -(side * u + fwd * v);
	// Added in, alpha squared (blend_add), so alpha is the root of the gleam
	// and the colour is divided by it.
	float k = sqrt(max(w, 1e-4));
	COLOR = vec4(vec3(e, w * to.x, w * to.y) / k, k);
}
"""

## The lamp light and the wet look, for the shaders that show them (put it
## before fragment()). In the browser it is two functions that do nothing.
## lamp_light(world position, albedo, roughness, view-space normal, VIEW,
## VIEW_MATRIX, specular 0-1): light to add to EMISSION.
## wet_now(): (how wet, how hard it rains, 0, 0).
const GLSL := """
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
vec4 wet_now() { return vec4(0.0); }
vec3 lamp_light(vec3 wpos, vec3 albedo, float rough, vec3 n, vec3 view, mat4 view_m, float spec) { return vec3(0.0); }
#else
global uniform sampler2D lamp_map : filter_linear;
global uniform vec4 lamp_rect;
global uniform vec4 lamp_on;
global uniform vec4 weather_wet;
vec4 wet_now() { return weather_wet; }
vec3 lamp_light(vec3 wpos, vec3 albedo, float rough, vec3 n, vec3 view, mat4 view_m, float spec) {
	if (lamp_on.x <= 0.0) {
		return vec3(0.0);
	}
	vec2 uv = (wpos.xz - lamp_rect.xy) * lamp_rect.z;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec3(0.0);
	}
	vec4 m = texture(lamp_map, uv);
	float e = m.r;
	float w = m.a;
	if (w < 0.003) {
		return vec3(0.0);
	}
	// Toward the lamp: the gleam-weighted way to the lens, 10 m up.
	vec2 to = m.gb / w;
	vec3 lw = normalize(vec3(to.x, %.1f, to.y));
	vec3 l = normalize((view_m * vec4(lw, 0.0)).xyz);
	float ndl = max(dot(n, l), 0.0);
	// The map holds the light on flat ground; a face turned toward the lamp
	// gets more, one turned away less.
	float en = e * ndl / max(lw.y, 0.25);
	vec3 col = albedo * en;
	// Its gleam: GGX, so a wet road's streak runs toward the eye. The lens
	// is half a metre across and its place is a blend where lamps overlap,
	// so a mirror-smooth puddle gleams no sharper than slightly rough water.
	vec3 hv = normalize(l + view);
	float ndh = max(dot(n, hv), 0.0);
	float ndv = max(dot(n, view), 0.02);
	float a = max(rough, 0.22);
	a *= a;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (3.14159 * dd * dd);
	float k = a * 0.5;
	float g = ndv / (ndv * (1.0 - k) + k) / (ndl * (1.0 - k) + k);
	float f0 = 0.16 * spec * spec;
	float f = f0 + (1.0 - f0) * pow(1.0 - max(dot(hv, view), 0.0), 5.0);
	col += vec3(min(d * g * f / (4.0 * ndv), 12.0) * w * ndl / max(lw.y, 0.25));
	return col * lamp_on.yzw;
}
#endif
""" % HEAD

static var _added := false

var _mm: MultiMesh
var _rect := Vector4.ZERO


## Adds the shared shader values (lamp_map, lamp_rect, lamp_on and
## weather_wet) if they are not there yet. Every shader that uses GLSL is
## made after this, or it would not compile.
static func ensure_globals() -> void:
	if _added or not wanted():
		return
	_added = true
	for g in GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + g[0]):
			RenderingServer.global_shader_parameter_add(g[0], g[1], g[2])


## True where this renderer draws the lamp map (the desktop's Forward+);
## the browser's Compatibility renderer keeps the flat pools.
static func wanted() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## How wet the ground is (0-1) and how hard it rains (0-1), for every shader
## with GLSL.
static func set_wet(wet: float, rain: float) -> void:
	ensure_globals()
	if not _added:
		return
	RenderingServer.global_shader_parameter_set("weather_wet", Vector4(wet, rain, 0.0, 0.0))


func _init() -> void:
	ensure_globals()
	var q := GraphicsQuality.current
	var big := q == null or q.tier >= GraphicsQuality.HIGH
	var n := SIZE_HIGH if big else SIZE_LOW
	size = Vector2i(n, n)
	disable_3d = true
	transparent_bg = true
	use_hdr_2d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var sh := Shader.new()
	sh.code = STAMP
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.mesh = quad
	var mi := MultiMeshInstance2D.new()
	mi.multimesh = _mm
	mi.material = mat
	add_child(mi)


func _ready() -> void:
	RenderingServer.global_shader_parameter_set("lamp_map", get_texture())


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("lamp_on", Vector4.ZERO)


## How strong the lamps are now (0 by day, 1 at night).
func set_amount(amount: float) -> void:
	var c := StreetLights.LAMP
	var k := amount * STRENGTH
	RenderingServer.global_shader_parameter_set("lamp_on", Vector4(amount, c.r * k, c.g * k, c.b * k))


## The square of ground the map covers for these lamps: [x, z of its
## corner, its side] in metres.
static func cover(lamps: Array) -> Array:
	if lamps.is_empty():
		return [0.0, 0.0, 1.0]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for l in lamps:
		var p: Vector3 = l[1]
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var side := maxf(hi.x - lo.x, hi.y - lo.y) + MARGIN * 2.0
	var mid := (lo + hi) * 0.5
	return [mid.x - side * 0.5, mid.y - side * 0.5, side]


## Draws the map again for these lamps (StreetLights.place: [mesh key,
## base, direction to the road, arm reach, mounting height]).
func draw(lamps: Array) -> void:
	var c := cover(lamps)
	var scale := float(size.x) / float(c[2])
	_rect = Vector4(c[0], c[1], 1.0 / float(c[2]), 0.0)
	_mm.instance_count = lamps.size()
	for i in lamps.size():
		var l: Array = lamps[i]
		var base: Vector3 = l[1]
		var dir: Vector3 = l[2]
		var h: float = l[4]
		var head := base + dir * float(l[3])
		var fwd := Vector2(dir.x, dir.z).normalized()
		var side := Vector2(fwd.y, -fwd.x)
		# Out to 4.5 heights along the road and over it, 1.2 behind (the
		# gleam reaches farthest).
		var half_u := 4.5 * h
		var back := 1.2 * h
		var front := 4.5 * h
		var half_v := (back + front) * 0.5
		var mid_v := (front - back) * 0.5
		var centre := Vector2(head.x, head.z) + fwd * mid_v
		var px := (centre - Vector2(c[0], c[1])) * scale
		_mm.set_instance_transform_2d(i, Transform2D(side * half_u * scale, fwd * half_v * scale, px))
		_mm.set_instance_custom_data(i, Color(half_u, half_v, mid_v, h))
	RenderingServer.global_shader_parameter_set("lamp_rect", _rect)
	render_target_update_mode = SubViewport.UPDATE_ONCE
