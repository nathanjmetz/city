class_name Surfaces
extends RefCounted
## Road and pavement materials, benchmarked against photos of real
## Midwestern residential streets:
##   - asphalt is a mid grey that varies by age from block to block, with
##     darker repair patches, crack sealer across the lanes, oil drips and a
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
	// Far off, the land is drawn coarser (TerrainView) and the depth buffer
	// gets coarse too, so a road lying on the land could sink into it. Past
	// 400 m each vertex is drawn a little nearer the camera (0.4% of the way)
	// along its own line of sight: it stays exactly where it was on screen,
	// but always wins against the land under it.
	vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(eye.xyz);
	float pull = max(dist - 400.0, 0.0) * 0.004;
	eye.xyz *= 1.0 - pull / max(dist, 1.0);
	POSITION = PROJECTION_MATRIX * eye;
}
"""

const ASPHALT := """
uniform vec4 fresh : source_color = vec4(0.28, 0.27, 0.27, 1.0);
uniform vec4 faded : source_color = vec4(0.42, 0.41, 0.39, 1.0);
uniform vec4 tar : source_color = vec4(0.13, 0.13, 0.13, 1.0);
global uniform float snow;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 220.0, 0.0, 1.0);
	// Streets were paved in different years, so the grey drifts block to block.
	float age = texture(noise_soft, p / 320.0).r;
	vec3 col = mix(fresh.rgb, faded.rgb, smoothstep(0.15, 0.85, age) * 0.5 + 0.3);
	// Patches: the odd strip across part of the road, only a little darker
	// than the pavement around it, with ragged sealed edges.
	float along = UV.y * 4.0;
	float across = UV.x * 4.0;
	float cell = floor(along / 14.0);
	vec2 block = floor(p / 80.0);
	float h = fract(sin(cell * 78.233 + block.x * 12.989 + block.y * 4.141) * 43758.5453);
	float h2 = fract(h * 91.7);
	float ragged = (texture(noise_grain, p / 0.9).r - 0.5) * 0.12;
	float a0 = h2 * 0.7;
	float s0 = 3.0 + h2 * 4.0;
	float in_patch = step(0.93, h)
		* smoothstep(a0, a0 + 0.02, across + ragged) * smoothstep(a0 + 0.3, a0 + 0.28, across + ragged)
		* smoothstep(s0, s0 + 0.1, mod(along, 14.0) + ragged * 4.0)
		* smoothstep(s0 + 2.5 + h2 * 2.0, s0 + 2.4 + h2 * 2.0, mod(along, 14.0) + ragged * 4.0);
	col *= 1.0 - in_patch * 0.13;
	// Crack sealer ("tar snakes"), an inch or two wide whatever the view:
	// the straight, branching block cracks of an ageing street, sealed in
	// some places and not others. Sealant is dark and a little glossy, not
	// ink black. Drawn in world space from a jittered cell pattern.
	float footprint = length(fwidth(p));  // metres per pixel
	float cracked = smoothstep(0.35, 0.55, texture(noise_soft, p / 90.0 + 0.2).r);
	vec2 q = turn(p, 0.6) / 4.5;
	vec2 qi = floor(q);
	float f1 = 9.0;
	float f2 = 9.0;
	vec2 c1 = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = qi + vec2(float(i), float(j));
			vec2 o = fract(sin(vec2(dot(g, vec2(127.1, 311.7)), dot(g, vec2(269.5, 183.3)))) * 43758.5453);
			vec2 d = g + 0.15 + o * 0.7 - q;
			float l = dot(d, d);
			if (l < f1) { f2 = f1; f1 = l; c1 = d; } else if (l < f2) { f2 = l; }
		}
	}
	float edge = (sqrt(f2) - sqrt(f1)) * 0.5 * 4.5;  // metres to the nearest cell edge
	edge += (texture(noise_grain, p / 1.7).r - 0.5) * 0.05;
	float run = smoothstep(0.46, 0.52, texture(noise_soft, p / 7.0 + 0.5).r);
	float wide = 0.025;
	float crack = (1.0 - smoothstep(wide, wide + footprint, edge)) * run * cracked;
	crack *= close * clamp(wide * 2.0 / max(footprint, 1e-4), 0.0, 1.0);  // thins out with distance
	col = mix(col, tar.rgb, crack * 0.75);
	// Oil drips and tyre grime.
	float oil = smoothstep(0.70, 0.86, texture(noise_grain, turn(p, 1.4) / 3.3).r);
	col *= 1.0 - oil * 0.1 * close;
	// Aggregate speckle up close.
	float g = texture(noise_grain, p / 0.31).r;
	col *= 1.0 + (g - 0.5) * 0.28 * close;
	// Winter: plowed and salted. Indiana streets go a chalky pale grey
	// with white road-salt residue drying in streaks, and a skim of packed
	// snow survives in patches between the wheel paths.
	float salt = snow * (0.55 + 0.45 * texture(noise_soft, turn(p, 0.3) / 18.0).r);
	col = mix(col, vec3(0.50, 0.50, 0.49) * (0.95 + g * 0.1), salt * 0.55);
	float packed = smoothstep(0.72, 0.9, texture(noise_soft, turn(p, 1.2) / 11.0 + 0.7).r) * snow;
	col = mix(col, vec3(0.72, 0.74, 0.77) * (0.92 + g * 0.1), packed * 0.45);
	ALBEDO = col;
	ROUGHNESS = 0.9 - crack * 0.4 - packed * 0.15;
	SPECULAR = 0.3;
}
"""

const CONCRETE := """
uniform vec4 base : source_color = vec4(0.70, 0.69, 0.65, 1.0);
uniform float joints = 1.0;
global uniform float snow;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float along = UV.y * 4.0;
	float slab = floor(along / %f);
	float tint = fract(sin(slab * 12.9898 + 3.1) * 43758.5453);
	// Slabs smaller than a few pixels blend to their average, so they don't
	// shimmer while the camera moves.
	tint = mix(tint, 0.5, smoothstep(0.1, 0.35, fwidth(along) / %f));
	vec3 col = base.rgb * (0.94 + tint * 0.09);
	// Weathering stains and grit.
	float stain = texture(noise_soft, turn(p, 0.5) / 9.0).r;
	col *= 1.0 - smoothstep(0.55, 0.85, stain) * 0.06;
	col *= 1.0 + (texture(noise_grain, p / 0.5).r - 0.5) * 0.16 * close;
	// A tooled joint line every slab.
	float d = abs(fract(along / %f + 0.5) - 0.5) * %f;
	float joint = 1.0 - smoothstep(0.012, 0.012 + fwidth(along) * 1.5, d);
	joint *= clamp(0.024 / max(fwidth(along), 0.0001), 0.0, 1.0);  // thinner than a pixel: fade
	col *= 1.0 - joint * joints * 0.45 * close;
	// Winter: some owners shovel their stretch of walk and some don't, so
	// snow lies in runs of whole slabs with thin trodden traces between.
	float unshoveled = step(0.5, texture(noise_soft, p / 30.0 + 0.4).r);
	float cover = snow * mix(0.25 * smoothstep(0.5, 0.8, texture(noise_soft, p / 2.0).r), 0.95, unshoveled);
	col = mix(col, vec3(0.80, 0.83, 0.88) * (0.95 + tint * 0.05), cover);
	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
}
""" % [SLAB, SLAB, SLAB, SLAB]

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

## Gravel road shoulders on rural roads, benchmarked against photos of
## Indiana county roads: crushed grey-tan limestone, darker where it's worn
## into the soil, with grass creeping in at random.
const GRAVEL := """
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 180.0, 0.0, 1.0);
	float patch = texture(noise_soft, p / 11.0).r;
	float grain = texture(noise_grain, p / 0.35).r;
	vec3 col = mix(vec3(0.42, 0.39, 0.34), vec3(0.55, 0.52, 0.46), patch);
	col *= 1.0 + (grain - 0.5) * 0.35 * close;
	float weeds = smoothstep(0.62, 0.78, texture(noise_soft, turn(p, 1.7) / 4.0).r);
	col = mix(col, vec3(0.16, 0.22, 0.08) * (0.8 + grain * 0.4), weeds * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

## Dirt and crushed-limestone lanes (logging roads, lease roads), benchmarked
## against photos of Indiana farm lanes and skid roads: two darker packed
## wheel paths 1.8 m apart, a looser crown between them with weeds coming
## through, and ragged grassy edges. Snow lies on them in winter, packed
## thin in the wheel paths. UV.x runs 0..0.25 across (RoadMesh ribbons).
const LANE := """
uniform vec4 base : source_color = vec4(0.58, 0.47, 0.33, 1.0);
global uniform float snow;
global uniform vec4 season_look;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 160.0, 0.0, 1.0);
	float x = UV.x * 4.0 - 0.5;
	float grain = texture(noise_grain, p / 0.4).r;
	float patch = texture(noise_soft, p / 9.0).r;
	float drift = (texture(noise_soft, p / 23.0).r - 0.5) * 0.08;
	float rut = 1.0 - smoothstep(0.05, 0.12, abs(abs(x + drift) - 0.22));
	float crown = 1.0 - smoothstep(0.05, 0.13, abs(x + drift));
	float edge = smoothstep(0.34, 0.5, abs(x) + (patch - 0.5) * 0.14);
	vec3 col = base.rgb * (0.85 + patch * 0.3) * (1.0 + (grain - 0.5) * 0.3 * close);
	col = mix(col, base.rgb * 0.66, rut * 0.7);
	// Weeds: green in summer, dead tan after frost.
	vec3 weed = mix(vec3(0.20, 0.25, 0.11), vec3(0.42, 0.37, 0.25), max(season_look.w, season_look.y));
	weed *= 0.8 + grain * 0.4;
	float weeds = smoothstep(0.45, 0.7, texture(noise_soft, turn(p, 1.3) / 3.0).r);
	col = mix(col, weed, max(edge, crown * weeds * 0.8) * 0.85);
	float cover = smoothstep(0.15, 0.55, snow * 0.9 + patch * 0.35 - 0.1) * mix(1.0, 0.45, rut);
	col = mix(col, vec3(0.80, 0.83, 0.88) * (0.93 + grain * 0.07), cover);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

## Crop fields, benchmarked against aerial photos of Iowa and Illinois
## farmland. UV is metres across and back from the farmhouse, / 16; the
## vertex colour is this month's crop colour (sRGB). Vertex alpha 0 marks
## the grassy, brushy fencerow verge along a farm's edge.
##   - 30 in (0.76 m) crop rows that blend to an even tone before they get
##     small enough to shimmer
##   - big soft patches where the soil is wetter, drier or richer
##   - a faint sprayer tramline every 36 m
const FIELD := """
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void fragment() {
	vec2 p = world_pos.xz;
	vec2 m = UV * 16.0;
	float patch = texture(noise_soft, p / 160.0).r;
	float mid = texture(noise_soft, turn(p, 1.1) / 38.0).r;
	float grain = texture(noise_grain, p / 1.7).r;
	// Rows: the gaps between them show more soil and shade.
	float r = m.x / 0.76;
	float gap = smoothstep(0.3, 0.95, abs(fract(r) - 0.5) * 2.0);
	gap = mix(gap, 0.4, smoothstep(0.12, 0.45, fwidth(r)));
	float t = abs(mod(m.x, 36.0) - 18.0);
	float tram = (1.0 - smoothstep(0.25, 0.45, t)) * clamp(0.5 / max(fwidth(m.x), 0.001), 0.0, 1.0);
	vec3 crop = lin(COLOR.rgb) * 1.45 * (0.8 + patch * 0.34 + (mid - 0.5) * 0.14);
	crop *= 1.0 - gap * 0.22 - tram * 0.12;
	crop *= 0.96 + grain * 0.08;
	// Fencerow verge: rough grass with brushy darker clumps.
	vec3 verge = mix(vec3(0.11, 0.16, 0.05), vec3(0.17, 0.17, 0.08), mid);
	verge *= 0.75 + grain * 0.45;
	ALBEDO = mix(verge, crop, COLOR.a);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
"""

## Limestone quarries, benchmarked against aerial photos of Indiana crushed
## stone quarries. UV.x is metres in from the pit's rim (negative out on
## the berm); COLOR.r is where the floor starts (/ 100 m) and COLOR.g how
## far off the haul ramp's centre line (/ 14 m).
##   - near-vertical faces every 15 m, lit or in shadow by which way they
##     face, with thin bedding lines and a pale lip along the top
##   - benches greyer and dustier the deeper they are
##   - a floor of blasted rock with rain water standing in the low spots
##   - a grassed berm of stripped overburden round the rim
const QUARRY := """
void fragment() {
	vec2 p = world_pos.xz;
	float s = UV.x;
	float floor_at = COLOR.r * 100.0;
	if (s < -9.0) {
		discard;
	}
	float close = clamp(1.0 - length(VERTEX) / 400.0, 0.0, 1.0);
	float grain = texture(noise_grain, p / 0.9).r;
	float patch = texture(noise_soft, p / 25.0).r;
	// Which way the ground falls, in world space, from the slope of s.
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	float sx = dFdx(s);
	float sy = dFdy(s);
	float det = dx.x * dy.y - dx.y * dy.x;
	vec2 g = vec2(0.0);
	if (abs(det) > 1e-9) {
		g = vec2(sx * dy.y - sy * dx.y, dx.x * sy - dy.x * sx) / det;
	}
	vec3 stone = vec3(0.60, 0.57, 0.50);
	vec3 col;
	if (s < 0.0) {
		col = mix(vec3(0.27, 0.23, 0.16), vec3(0.17, 0.21, 0.08), smoothstep(0.3, 0.7, patch));
	} else {
		float cycle = 15.0;
		float level = min(floor(s / cycle), 5.0);
		float t = s - floor(s / cycle) * cycle;
		vec3 bench = stone * (1.0 - level * 0.05) * (0.92 + patch * 0.16);
		{
			float aa = fwidth(s);
			float face = 1.0 - smoothstep(5.0 - aa, 5.0 + aa, t);
			float lit = 0.0;
			if (length(g) > 0.01) {
				lit = dot(-normalize(g), normalize(vec2(0.55, 0.83)));
			}
			vec3 wall = vec3(0.46, 0.42, 0.35) * (0.62 + lit * 0.3) * (1.0 - level * 0.04);
			float bed = smoothstep(0.35, 0.65, fract(t * 1.4 + texture(noise_soft, p / 30.0).r * 2.0));
			wall *= 0.9 + bed * 0.12;
			float lip = 1.0 - smoothstep(0.0, 0.7 + aa, t);
			col = mix(bench, wall, face);
			col = mix(col, stone * 1.08, lip * 0.6);
		}
		// The floor: blasted rock, with rain water standing in the low spots.
		vec3 rock = bench * 0.85;
		float wet = smoothstep(0.56, 0.62, texture(noise_soft, p / 60.0 + 0.3).r);
		rock = mix(rock, vec3(0.14, 0.22, 0.20), wet);
		col = mix(col, rock, smoothstep(floor_at, floor_at + 3.0, s));
	}
	float ramp = (1.0 - step(0.5, COLOR.g)) * step(s, floor_at + 4.0);
	col = mix(col, vec3(0.56, 0.53, 0.46) * (0.95 + patch * 0.1), ramp);
	col *= 1.0 + (grain - 0.5) * 0.25 * close;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
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


static func gravel() -> ShaderMaterial:
	return _make("gravel", GRAVEL, {})


static func quarry() -> ShaderMaterial:
	return _make("quarry", QUARRY, {})


static func lane(color: Color) -> ShaderMaterial:
	return _make("lane %s" % color, LANE, {"base": color})


static func field() -> ShaderMaterial:
	return _make("field", FIELD, {})


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
