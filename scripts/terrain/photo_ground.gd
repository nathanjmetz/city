class_name PhotoGround
extends RefCounted
## Real-life ground for the desktop app (High and up): photographed CC0
## textures from Poly Haven (art/pbr/, see SOURCES.md) laid over the
## painted ground at their real size, so grass shows blades and clover,
## field soil its clods, woods their leaf litter and county gravel its
## stones, and each catches the sun through its own normal map.
##
## The painted ground keeps its colour (seasons, crops, dryness, snow): a
## photo only adds its fine detail, as its own colour over its own blur
## (ph_<k>), so a July pasture and a January one stay the colours they
## were measured against. From far off the mipmaps average a photo to 1
## and its detail fades by itself; it is gone by 520 m (ph_on).
##
## The browser never loads it: the Web export leaves art/pbr out, and its
## shader code (glsl()) compiles no samplers (Compatibility allows 16 a
## shader and the ground already uses most of them).

const DIR := "res://art/pbr/"
## Shader name -> [Poly Haven id]. Each has albedo.jpg and normal.jpg.
const TEXTURES := {
	"grass": "leafy_grass",
	"soil": "farm_soil",
	"litter": "leaves_forest_ground",
	"mud": "brown_mud",
	"gravel": "gravel_floor_02",
	"snowy": "snow_02",
}
## Metres one tile covers on the ground (Poly Haven's measured size).
const SIZE := {"grass": 2.0, "soil": 2.0, "litter": 1.3, "mud": 1.3, "gravel": 2.0, "snowy": 2.0}
## How strongly each photo's detail shows (a power on its ratio): the
## grass photo is an even lawn, softer than a pasture seen in the sun.
const GAIN := {"grass": 1.8, "soil": 1.3, "litter": 1.2, "mud": 1.0, "gravel": 1.0, "snowy": 1.0}

static var _tex := {}


## The shader code: samplers and, for each texture <k>, ph_<k>(p) (its
## colour over its own average) and ph_<k>_s(p) (its slope), with
## ph_on(dist) and ph_lean(); the browser gets neutral stand-ins with the
## same names and no samplers. Goes after the shader's own uniforms.
static func glsl() -> String:
	var web := not drawable()
	var code := "const float photo = 0.0;\n" if web else "uniform float photo = 0.0;\n" + COMMON
	for k in TEXTURES:
		if web:
			code += "vec3 ph_%s(vec2 p) { return vec3(1.0); }\nvec2 ph_%s_s(vec2 p) { return vec2(0.0); }\n" % [k, k]
			continue
		code += "uniform sampler2D ph_%s_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;\n" % k
		code += "uniform sampler2D ph_%s_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;\n" % k
		code += PER.replace("KEY", k).replace("SIZE", "%.2f" % SIZE[k]).replace("GAIN", "%.2f" % GAIN[k])
	return code + HELPERS


## "#define DESKTOP_DETAIL" where the desktop's extra ground detail is
## drawn (the crop table's soil look), before any code that asks.
static func defines() -> String:
	return "#define DESKTOP_DETAIL\n" if drawable() else ""


## One texture's two helpers. The second, larger, turned copy multiplied in
## keeps the tile from showing its repeat; the last mip is the average.
const PER := """
vec3 ph_KEY(vec2 p) {
	vec2 uv = p / SIZE;
	vec2 uv2 = ph_turn(uv) * 0.73 + 0.29;
	// High-passed: each sample over its own blur (mip 7, about a tenth of
	// the tile), so the tile's own light and dark sides never repeat as a
	// grid; the painted ground already carries the larger patches.
	vec3 a = texture(ph_KEY_c, uv).rgb / max(textureLod(ph_KEY_c, uv, 7.0).rgb, vec3(0.02));
	vec3 b = texture(ph_KEY_c, uv2).rgb / max(textureLod(ph_KEY_c, uv2, 7.0).rgb, vec3(0.02));
	// Mostly its light and shade; its own hues only a little, which
	// sharpened read as coloured static.
	vec3 r = mix(a, b, ph_mask(p, SIZE));
	float l = dot(r, vec3(0.3, 0.55, 0.15));
	return pow(max(mix(vec3(l), r, 0.35), vec3(0.0)), vec3(GAIN));
}
vec2 ph_KEY_s(vec2 p) {
	vec2 uv = p / SIZE;
	vec2 a = texture(ph_KEY_n, uv).xy * 2.0 - 1.0;
	// The turned copy's slope, turned back.
	vec2 b = ph_unturn(texture(ph_KEY_n, ph_turn(uv) * 0.73 + 0.29).xy * 2.0 - 1.0);
	return mix(a, b, ph_mask(p, SIZE));
}
"""

## Shared by every texture's helpers: a 2.2 rad turn (and back), and a soft
## blotchy mask a few tiles across that picks between a tile and its turned
## copy, so no tile's grid repeat lines up across a field.
const COMMON := """
vec2 ph_turn(vec2 v) { return vec2(v.x * -0.589 - v.y * 0.808, v.x * 0.808 - v.y * 0.589); }
vec2 ph_unturn(vec2 v) { return vec2(v.x * -0.589 + v.y * 0.808, -v.x * 0.808 - v.y * 0.589); }
float ph_hash(vec2 c) { return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453); }
float ph_mask(vec2 p, float size) {
	vec2 q = p / (size * 2.7);
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(mix(ph_hash(i), ph_hash(i + vec2(1.0, 0.0)), f.x), mix(ph_hash(i + vec2(0.0, 1.0)), ph_hash(i + 1.0), f.x), f.y);
	return smoothstep(0.35, 0.65, n);
}
"""

const HELPERS := """
float ph_on(float dist) {
	return photo * (1.0 - smoothstep(120.0, 520.0, dist));
}
// The ground's world normal leaned by a photo slope (GL normal maps: the
// image's up, green, is -z on the ground, where UV v runs with +z).
vec3 ph_lean(vec3 n, vec2 s, float k) {
	return normalize(n + vec3(s.x, 0.0, -s.y) * k);
}
"""


## Whether this renderer can draw it at all: not the browser, nor a
## desktop whose graphics chip only runs Compatibility (16 samplers).
static func drawable() -> bool:
	return not OS.has_feature("web") and RenderingServer.get_current_rendering_method() != "gl_compatibility"


## Whether this machine draws the photo ground now: the desktop app at
## a tier whose budget says so (High and up).
static func wanted() -> bool:
	return drawable() and bool(GraphicsQuality.knob("photo", false))


## Turns the photo ground on or off in `mat` for the current tier, and keeps
## it in step when the tier changes. Textures load the first time it's on.
static func apply(mat: ShaderMaterial) -> void:
	if not drawable():
		return
	_update(mat)
	if GraphicsQuality.current != null:
		GraphicsQuality.current.changed.connect(func(): _update(mat))


static func _update(mat: ShaderMaterial) -> void:
	var on := wanted() and _load()
	if on:
		for k in TEXTURES:
			mat.set_shader_parameter("ph_%s_c" % k, _tex[k][0])
			mat.set_shader_parameter("ph_%s_n" % k, _tex[k][1])
	mat.set_shader_parameter("photo", 1.0 if on else 0.0)


static func _load() -> bool:
	if not _tex.is_empty():
		return true
	for k in TEXTURES:
		var a: Texture2D = load(DIR + TEXTURES[k] + "/albedo.jpg") if ResourceLoader.exists(DIR + TEXTURES[k] + "/albedo.jpg") else null
		var n: Texture2D = load(DIR + TEXTURES[k] + "/normal.jpg") if ResourceLoader.exists(DIR + TEXTURES[k] + "/normal.jpg") else null
		if a == null or n == null:
			_tex.clear()
			return false
		_tex[k] = [a, n]
	return true
