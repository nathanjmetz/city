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
// Set by DayNight: how dark it is, how much snow lies, and the share of
// rooms with a light on.
global uniform float night;
global uniform float snow;
global uniform float windows_lit;
varying vec3 world_pos;
varying vec3 world_normal;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
// Vertex colours are sRGB. The browser's renderer (Compatibility) hands
// these meshes' colours over already made linear, so only Forward+ converts.
vec3 vcol(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return lin(c);
#endif
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
// Snow lying on anything that faces up: thickest on gentle slopes, thinning
// in patches where it has slid or melted.
float snow_cover(float slope_from, float slope_to) {
	float up = smoothstep(slope_from, slope_to, world_normal.y);
	float patchy = texture(noise_soft, world_pos.xz / 6.0).r;
	return up * smoothstep(0.15, 0.55, snow * 0.9 + patchy * 0.35 - 0.1);
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
	ALBEDO = vcol(COLOR.rgb) * s * grime * (0.95 + n * 0.1);
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
	vec3 col = mix(vcol(COLOR.rgb) * tint, mortar.rgb, joint);
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
	vec3 col = vcol(COLOR.rgb) * s * (0.9 + w * 0.2) * (1.0 - streak * 0.18);
	col *= 0.94 + texture(noise_grain, UV * 3.0).r * 0.12 * (1.0 - aa);
	// Winter: snow on the roof, with the tab lines showing faintly through.
	float cover = snow_cover(0.35, 0.6);
	col = mix(col, vec3(0.86, 0.88, 0.92) * (0.95 + s * 0.05), cover);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.7, cover);
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
	vec3 col = mix(room, vcol(COLOR.rgb) * 0.3 * slat, blinds);
	// Curtains drawn back to the sides in about half the windows, in
	// whites, creams and the odd colour, and a glimpse of the room's back
	// wall lower down: a window in daylight reads as a dim room, not a hole.
	vec2 wcell = vec2(floor(dot(world_pos.xz, vec2(0.7071, 0.7071)) / 1.3), floor(world_pos.y / 2.9));
	wcell += floor(dot(world_pos.xz, vec2(-0.7071, 0.7071)) / 1.3) * 17.0;
	float h1 = hash(wcell + 11.3);
	vec3 drape = mix(vec3(0.62, 0.58, 0.50), vec3(0.75, 0.74, 0.70), hash(wcell + 2.7));
	drape = mix(drape, vec3(0.30, 0.34, 0.42), step(0.85, hash(wcell + 5.1)));
	float side = max(1.0 - smoothstep(0.17, 0.24, UV.x), smoothstep(0.76, 0.83, UV.x));
	col = mix(col, lin(drape) * 0.55, side * step(h1, 0.6) * (1.0 - blinds * 0.7));
	col += vec3(0.022, 0.02, 0.017) * (1.0 - UV.y) * (1.0 - blinds);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 sky = mix(vec3(0.20, 0.26, 0.34), vec3(0.45, 0.52, 0.60), UV.y);
	sky *= 1.0 - night * 0.85;
	ALBEDO = mix(col, sky, 0.18 + 0.5 * fres);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	// After dark some rooms have a light on: one pick per window-sized patch
	// of wall and per floor, warm lamps mostly, the odd cool TV glow.
	vec2 cell = vec2(floor(dot(world_pos.xz, vec2(0.7071, 0.7071)) / 2.6), floor(world_pos.y / 2.9));
	cell += floor(dot(world_pos.xz, vec2(-0.7071, 0.7071)) / 2.6) * 17.0;
	float pick = hash(cell);
	float on = step(pick, windows_lit) * smoothstep(0.2, 0.6, night);
	vec3 warm = mix(vec3(1.0, 0.62, 0.3), vec3(1.0, 0.78, 0.5), hash(cell + 3.1));
	vec3 lamp = mix(warm, vec3(0.55, 0.7, 1.0), step(0.9, hash(cell + 7.7)));
	// Light through blinds is dimmer and softer.
	EMISSION = lamp * on * mix(2.2, 1.1, blinds) * (0.8 + 0.4 * UV.y);
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
	vec3 line = mix(vcol(COLOR.rgb), asphalt.rgb, wear * 0.45);
	float chips = texture(noise_grain, p / 0.12).r;
	vec3 loose = vcol(COLOR.rgb) * (0.6 + chips * 0.8);
	vec3 col = drive;
	col = mix(col, lot, step(0.2, COLOR.a));
	col = mix(col, line, step(0.6, COLOR.a));
	col = mix(col, loose, step(0.86, COLOR.a));
	// Winter: gravel, mulch and the woods floor keep their snow like the
	// lawn does; paved drives and lots are plowed, leaving packed snow in
	// the low patches and wheel-polished bare ground between.
	float is_loose = step(0.86, COLOR.a);
	float cover = snow_cover(0.8, 0.95);
	float packed = smoothstep(0.68, 0.88, texture(noise_soft, p / 9.0).r) * 0.45;
	cover *= mix(packed, 0.85 + chips * 0.15, is_loose);
	vec3 snowy = vec3(0.80, 0.83, 0.88) * mix(0.82, 0.97, is_loose) * (0.95 + grain * 0.07);
	ALBEDO = mix(col, snowy, cover);
	ROUGHNESS = mix(0.9, 0.75, cover);
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
	float cover = snow_cover(0.8, 0.95);
	ALBEDO = mix(vcol(COLOR.rgb) * s * grime * (0.93 + streak * 0.12), vec3(0.86, 0.88, 0.92), cover);
	ROUGHNESS = mix(0.45, 0.7, cover);
	SPECULAR = 0.5;
}
"""

## Chain-link fabric: 2 in diamonds of 9-gauge galvanised wire (about a
## sixth of each diamond is wire), UV in metres along and up the fence. Up
## close the wires show; once they are thinner than a pixel the fabric
## becomes an even stipple of the same coverage, the faint grey veil chain
## link makes in photos, never empty air between the posts.
const CHAIN := """
void fragment() {
	vec2 d = vec2(UV.x + UV.y, UV.x - UV.y) / 0.072;
	vec2 f = abs(fract(d) - 0.5) * 2.0;
	vec2 px = max(fwidth(d) * 2.0, vec2(0.0001));
	float wire = max(1.0 - smoothstep(0.0, 0.11 + px.x, f.x), 1.0 - smoothstep(0.0, 0.11 + px.y, f.y));
	float far = smoothstep(0.08, 0.2, max(px.x, px.y));
	float stipple = step(hash(floor(FRAGCOORD.xy)), 0.22);
	ALPHA = mix(wire, stipple, far);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Round wire is half in its own shade: as a haze it reads darker than
	// the flat posts and rails.
	ALBEDO = vcol(COLOR.rgb) * mix(1.0, 0.5, far);
	ROUGHNESS = 0.7;
	SPECULAR = 0.4;
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
	// Alpha 0: the business's real name is lettered on (SignText).
	float text = inside * on * gap * band * step(0.0001, COLOR.a);
	float aa = smoothstep(0.08, 0.3, fwidth(UV.x / pitch));
	text = mix(text, 0.3 * band * step(0.25, UV.y) * step(UV.y, 0.78) * step(0.0001, COLOR.a), aa);
	ALBEDO = mix(vcol(COLOR.rgb), vec3(0.86, 0.84, 0.79), text);
	ROUGHNESS = 0.4;
	SPECULAR = 0.5;
	// Lit signs after dark: bright letters on a softly glowing panel.
	EMISSION = mix(vcol(COLOR.rgb) * 0.5, vec3(1.0, 0.95, 0.85) * 2.0, text) * smoothstep(0.3, 0.6, night);
}
"""

## Plain vertex colour (paint, trim, flat membrane roofs, shrubs), with snow
## on whatever faces straight up.
const PLAIN := """
uniform float rough = 0.55;
void fragment() {
	float cover = snow_cover(0.88, 0.97);
	// Vertex alpha under 0.5 marks foliage (shrubs and hedges share this
	// surface to save draw calls): matte, broken up into leaf clumps.
	float leafy = step(COLOR.a, 0.5);
	float clumps = texture(noise_grain, world_pos.xz / 0.35 + world_pos.y * 0.7).r;
	vec3 base = vcol(COLOR.rgb) * mix(1.0, 0.7 + clumps * 0.6, leafy);
	ALBEDO = mix(base, vec3(0.86, 0.88, 0.92), cover * mix(1.0, smoothstep(0.35, 0.7, clumps), leafy));
	ROUGHNESS = mix(mix(rough, 1.0, leafy), 0.7, cover);
	SPECULAR = mix(0.4, 0.1, leafy);
}
"""

## Reclaimed pasture and hay ground laid as a flat (strip mine grading):
## vertex colour as the grass, with the lawn's seasons and snow, no sheen.
## Low-slope commercial roofs (alpha picks the kind): single-ply membrane
## (alpha 1, weathered white TPO or black EPDM by colour) laid in 10 ft
## sheets with lapped seams, or tar and gravel built-up roof (alpha 0.5).
## Dirt and ponding stains, and snow in winter. Benchmark: aerial photos
## of Indiana Main Street blocks and strip centres.
const MEMBRANE := """
void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = vcol(COLOR.rgb);
	float big = texture(noise_soft, p / 18.0).r;
	float spot = texture(noise_soft, p / 4.0 + 0.37).r;
	float grain = texture(noise_grain, p / 0.6).r;
	if (COLOR.a > 0.75) {
		// Sheets 3.05 m wide with a lapped, welded seam; a lighter line on
		// dark rubber, a darker one on white.
		float sx = fract(p.x / 3.05);
		float seam = 1.0 - smoothstep(0.0, 0.03, min(sx, 1.0 - sx));
		seam *= 1.0 - smoothstep(0.3, 0.8, fwidth(p.x / 3.05) * 15.0);
		float dark = step(dot(col, vec3(0.33)), 0.1);
		col *= 1.0 + seam * mix(-0.12, 0.35, dark);
		col *= 0.92 + grain * 0.08;
	} else {
		// Gravel ballast: speckled stone.
		col *= 0.75 + grain * 0.5;
	}
	// Dirt washed toward the drains, and dried ponding rings.
	col *= 1.0 - smoothstep(0.55, 0.85, big) * 0.18;
	col *= 1.0 - smoothstep(0.7, 0.78, spot) * (1.0 - smoothstep(0.78, 0.86, spot)) * 0.12;
	float cover = snow_cover(0.8, 0.95);
	col = mix(col, vec3(0.86, 0.88, 0.92), cover);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.7, cover);
	SPECULAR = 0.25;
}
"""
const PASTURE := """
global uniform vec4 season_look;
void fragment() {
	vec2 p = world_pos.xz;
	float big = texture(noise_soft, p / 40.0).r;
	float clump = texture(noise_soft, p / 5.0).r;
	float fade = clamp(1.0 - length(VERTEX) / 180.0, 0.0, 1.0);
	vec3 col = vcol(COLOR.rgb) * (0.85 + big * 0.3) * (1.0 + (texture(noise_grain, p / 0.8).r - 0.5) * 0.3 * fade);
	col = mix(col, col * vec3(0.92, 1.12, 0.78), season_look.z);
	vec3 dormant = lin(vec3(0.55, 0.48, 0.33)) * (0.85 + big * 0.3);
	col = mix(col, dormant, clamp(season_look.w * 1.1 - clump * 0.2, 0.0, 0.85));
	float cover = smoothstep(0.05, 0.45, snow * 1.15 - clump * 0.35 + 0.1) * smoothstep(0.6, 0.9, world_normal.y);
	ALBEDO = mix(col, vec3(0.80, 0.83, 0.88), cover);
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
"""

## Distant buildings (BuildingView's far versions): the wall colour with a
## window grid drawn from UVs in metres (x along the wall, y up it), the
## share of glass in vertex alpha; UV zero draws the plain colour.
## Lit rooms after dark, as on near windows.
const FAR := """
void fragment() {
	float fy = fract(UV.y / 3.7);
	float fx = fract(UV.x / 2.0);
	float aa = clamp(1.0 / max(fwidth(UV.x) * 2.0, 0.001), 0.0, 1.0);
	// Punched windows in masonry; a curtain wall (alpha 1) is all glass
	// but thin mullions and floor lines.
	float curtain = step(0.97, COLOR.a);
	float ylo = mix(0.3, 0.06, curtain);
	float xlo = mix(0.12, 0.04, curtain);
	float win = step(ylo, fy) * step(fy, 0.86 + curtain * 0.1) * step(xlo, fx) * step(fx, 1.0 - xlo) * step(0.01, COLOR.a);
	win = mix(COLOR.a * 0.55, win, aa);  // too small to draw: an even darkening
	vec3 glass = vec3(0.025, 0.03, 0.035) + vec3(0.06, 0.08, 0.1) * (1.0 - night * 0.85);
	// Winter: snow on roofs and flat tops, as on the close-up roofs.
	float cover = snow_cover(0.35, 0.6) * (1.0 - win);
	ALBEDO = mix(mix(vcol(COLOR.rgb), glass, win), vec3(0.86, 0.88, 0.92), cover);
	ROUGHNESS = mix(mix(0.85, 0.15, win), 0.7, cover);
	SPECULAR = mix(0.3, 0.6, win);
	vec2 cell = vec2(floor(UV.x / 2.0), floor(UV.y / 3.7));
	float on = step(hash(cell + floor(world_pos.xz / 50.0)), windows_lit) * smoothstep(0.2, 0.6, night);
	EMISSION = vec3(1.0, 0.7, 0.42) * on * win * 1.6;
}
"""

static var _cache := {}
static var _soft: Texture2D
static var _grain: Texture2D


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
		"chain": mat = _shader(CHAIN)
		"pasture": mat = _shader(PASTURE)
		"far": mat = _shader(FAR)
		"membrane": mat = _shader(MEMBRANE)
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


static func _plain(roughness: float) -> ShaderMaterial:
	var m := _shader(PLAIN)
	m.set_shader_parameter("rough", roughness)
	return m
