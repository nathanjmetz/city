class_name Surfaces
extends RefCounted
## Road and pavement materials, benchmarked against photos of real
## Midwestern residential streets:
##   - asphalt is a mid grey that varies by age from block to block, with
##     darker repair patches, crack sealer across the lanes, oil drips and a
##     speckled aggregate grain up close
##   - sidewalks are weathered grey concrete slabs with a joint every 5 ft
##     and different tints from slab to slab; on the desktop also the odd
##     newer or patched slab and dirt along both grassy edges
##   - paint is worn: brightest at the edges of the wheel paths, faded and
##     patchy elsewhere
## All shaders are cheap world-space ones that run in the Compatibility renderer.
## Ribbon meshes from RoadMesh carry the distance along the road in UV.y / 4.
## On the desktop (LampLight.GLSL) they also take the streetlights' light,
## and in and after rain at High and up (Weather) they go wet: darker and
## glossy, with puddles in the low spots and along the curbs, the wheel
## paths drying first. The browser draws them dry and lit by flat pools.

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

## Photo detail for the desktop's High tier and up: a CC0 photo scan of real
## pavement (art/textures/roads, see art/LICENSES.md) laid over the drawn
## colours as grain, bumps and roughness. It only changes the brightness
## around the photo's own average, so the age, patches, cracks and paint
## drawn above it still decide the look; two samples at different sizes and
## angles, blended by soft noise, hide the photo's repeat. `photo` is 0 in
## the browser and on Low and Medium (Surfaces.photo_level), which skips it.
const PHOTO := """
uniform float photo = 0.0;
uniform float photo_size = 2.1;
uniform float photo_bump = 1.0;
uniform sampler2D photo_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D photo_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D photo_rough : filter_linear_mipmap_anisotropic, repeat_enable;
// [brightness factor, roughness, normal x, normal y] from the photo at p.
vec4 photo_at(vec2 p, float near) {
	vec2 u0 = p / photo_size;
	vec2 u1 = turn(p, 1.13) / (photo_size * 1.37) + 0.31;
	float w = smoothstep(0.35, 0.65, texture(noise_soft, p / 23.0 + 0.17).r);
	vec3 a = mix(texture(photo_albedo, u0).rgb, texture(photo_albedo, u1).rgb, w);
	vec3 mean = textureLod(photo_albedo, vec2(0.5), 12.0).rgb;
	float lum = dot(a, vec3(0.3, 0.59, 0.11)) / max(dot(mean, vec3(0.3, 0.59, 0.11)), 1e-3);
	float r = mix(texture(photo_rough, u0).g, texture(photo_rough, u1).g, w);
	vec2 n0 = texture(photo_normal, u0).rg * 2.0 - 1.0;
	// The second sample is turned, so its bumps are turned back to match.
	vec2 n1 = texture(photo_normal, u1).rg * 2.0 - 1.0;
	n1 = turn(n1, -1.13);
	vec2 n = mix(n0, n1, w) * photo_bump * near;
	return vec4(mix(1.0, lum, near), r, n);
}
// Tilts the flat, upward surface by the photo's bumps (OpenGL normal maps:
// green points up the image, which is -z here since the photo lies on x/z).
vec3 photo_normal_view(vec2 n, mat4 view) {
	vec3 world = normalize(vec3(n.x, 1.0, -n.y));
	return normalize((view * vec4(world, 0.0)).xyz);
}
"""


## Fields lie on the land like a sheet of paint, hundreds of metres across.
## The land under them is drawn from a grid (8 m near, coarser and morphing
## farther off, see TerrainView) while the field follows the true ground, so
## on a rolling field the land bulged through it in pale blotches. Every
## field vertex is drawn a little nearer the camera along its own line of
## sight (it stays exactly where it is on screen), more the farther off it
## is, so the field always wins against the land it lies on.
const FIELD_COMMON := """
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
	vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(eye.xyz);
	float pull = 0.35 + dist * 0.004 + max(dist - 350.0, 0.0) * 0.006;
	eye.xyz *= 1.0 - min(pull, dist * 0.5) / max(dist, 1.0);
	POSITION = PROJECTION_MATRIX * eye;
}
"""

const ASPHALT := PHOTO + """
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
	// Block cracking only where a street has aged worst.
	float cracked = smoothstep(0.58, 0.72, texture(noise_soft, p / 90.0 + 0.2).r);
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
	// Transverse cracks, the commonest on a Midwest street: the pavement
	// shrinks in winter and splits straight across a lane or the whole road
	// every 8 to 20 m, wandering a little on the way.
	float tcell = floor(along / 11.0);
	float th = fract(sin(tcell * 41.37 + block.x * 7.13 + block.y * 3.71) * 43758.5453);
	float th2 = fract(th * 57.3);
	float wob = (texture(noise_soft, vec2(across * 0.7, tcell * 0.37)).r - 0.5) * 1.6
		+ (texture(noise_grain, p / 1.3).r - 0.5) * 0.08;
	float dt = abs(along - tcell * 11.0 - 2.0 - th * 7.0 - wob);
	float from = th2 * 0.5;
	float span = step(0.3, th) * smoothstep(from - 0.03, from, across) * smoothstep(from + 0.5 + th * 0.5, from + 0.47 + th * 0.5, across);
	// Sealed with a 3 in band of sealant, so they show from the air.
	crack = max(crack, (1.0 - smoothstep(0.04, 0.04 + footprint, dt)) * span);
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
	float rough = 0.9;
	if (photo > 0.0) {
		// Up close the photo's own stones take over from the drawn speckle.
		float near = photo * clamp(1.0 - length(VERTEX) / 260.0, 0.0, 1.0);
		vec4 ph = photo_at(p, near);
		col /= mix(1.0, 1.0 + (g - 0.5) * 0.28 * close, near);
		col *= mix(1.0, ph.x, 1.0 - crack * 0.8);
		rough = mix(rough, 0.7 + ph.y * 0.3, near);
		NORMAL = photo_normal_view(ph.zw * (1.0 - packed) * (1.0 - crack), VIEW_MATRIX);
	}
	rough -= crack * 0.4 + packed * 0.15;
	float spec = 0.3;
	// Rain, benchmarked against photos of wet Indiana streets: the asphalt
	// goes much darker and glossy and mirrors the sky; water stands in the
	// low spots, in settled patches and along the curb; once it stops, the
	// wheel paths dry first, then the rest, the puddles last.
	vec4 wl = wet_now();
	// Screen-space slopes, taken outside any branch: how fast the ground
	// and UV.x run across the screen.
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float dax = dFdx(across);
	float day = dFdy(across);
	if (wl.x > 0.0) {
		// Metres across from the road's middle, from how fast UV.x runs
		// over the ground (junction pads carry no across: no paths there).
		float det = dpx.x * dpy.y - dpx.y * dpy.x;
		vec2 ga = vec2(0.0);
		if (abs(det) > 1e-9) {
			ga = vec2(dax * dpy.y - day * dpx.y, dpx.x * day - dpy.x * dax) / det;
		}
		float width = 1.0 / max(length(ga), 1e-4);
		float valid = step(3.0, width) * step(width, 40.0);
		float x = (across - 0.5) * width;
		float to_edge = (0.5 - abs(across - 0.5)) * width;
		// Tyres run 0.9 m either side of each 3.6 m lane's middle.
		float wheel = abs(mod(abs(x), 1.8) - 0.9);
		float track = (1.0 - smoothstep(0.2, 0.42, wheel + (texture(noise_grain, p / 2.1).r - 0.5) * 0.12))
			* smoothstep(1.0, 1.6, to_edge) * valid * clamp(0.5 / max(footprint, 1e-3) - 0.5, 0.0, 1.0);
		float low = texture(noise_soft, p / 13.0 + 0.61).r * 0.65 + texture(noise_soft, turn(p, 2.1) / 4.3).r * 0.35;
		low += (1.0 - smoothstep(0.15, 0.9, to_edge)) * 0.32 * valid + in_patch * 0.08 + crack * 0.12;
		float t = 0.06 + 0.42 * track - 0.22 * smoothstep(0.5, 0.72, low);
		float film = smoothstep(t, t + 0.18, wl.x);
		float lvl = 0.8 - 0.16 * wl.x;
		float pud = smoothstep(lvl, lvl + 0.02, low) * smoothstep(0.12, 0.4, wl.x);
		// The film keeps the stones' texture; standing water is a mirror.
		col *= mix(1.0, 0.42, film) * mix(1.0, 0.85, pud);
		rough = mix(mix(rough, 0.38, film), 0.02, pud);
		spec = mix(mix(spec, 0.36, film), 0.5, pud);
		vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec3 water = up;
		if (wl.y > 0.01) {
			// Raindrops ringing the water.
			vec2 q1 = p * 2.3 + vec2(TIME * 0.31, TIME * 0.17);
			vec2 q2 = turn(p, 1.0) * 2.9 - vec2(TIME * 0.23, TIME * 0.29);
			vec2 rip = vec2(texture(noise_grain, q1).r - texture(noise_grain, q2).r,
				texture(noise_grain, q1 + 0.37).r - texture(noise_grain, q2 + 0.61).r);
			water = normalize(up + (VIEW_MATRIX * vec4(rip.x, 0.0, rip.y, 0.0)).xyz * 0.35 * wl.y * close);
		}
		NORMAL = normalize(mix(mix(NORMAL, up, film * 0.5), water, pud));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, spec);
}
"""

const CONCRETE := PHOTO + """
uniform vec4 base : source_color = vec4(0.70, 0.69, 0.65, 1.0);
uniform float joints = 1.0;
global uniform float snow;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float along = UV.y * 4.0;
	float slab = floor(along / %f);
	float pick = fract(sin(slab * 12.9898 + 3.1) * 43758.5453);
	// Slabs smaller than a few pixels blend to their average, so they don't
	// shimmer while the camera moves.
	float blend = smoothstep(0.1, 0.35, fwidth(along) / %f);
	float tint = mix(pick, 0.5, blend);
	vec3 col = base.rgb * (0.94 + tint * 0.09);
	// Weathering stains and grit.
	float stain = texture(noise_soft, turn(p, 0.5) / 9.0).r;
	float grit = texture(noise_grain, p / 0.5).r;
	col *= 1.0 - smoothstep(0.55, 0.85, stain) * 0.06;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (joints > 0.0) {
		// An old town's walks (desktop only: the browser draws them plain):
		// slabs poured in different years, so the grey spreads wider; about
		// one in fifteen replaced in newer, paler concrete and one in twenty
		// a darker patch; more stains; and dirt and moss along both edges,
		// where the grass meets the walk. All of it per slab or fixed in
		// the ground, so it never moves, and far off it blends to its average.
		col = base.rgb * (0.88 + tint * 0.2);
		float second = fract(pick * 91.7 + 0.37);
		float newer = step(0.93, second) * (1.0 - blend);
		float patched = step(second, 0.05) * (1.0 - blend);
		col *= mix(vec3(1.0), vec3(1.1, 1.11, 1.13), newer);
		col *= mix(vec3(1.0), vec3(0.76, 0.75, 0.72), patched);
		col *= 1.0 - smoothstep(0.5, 0.85, stain) * 0.1 * (1.0 - newer);
		// The walk's width from how fast UV.x crosses it: a street's walk
		// runs 0 to 1 across, but a junction's pieces carry their own
		// position (one a metre), which says nothing about their edges.
		float across = UV.x * 4.0;
		vec2 px = dFdx(p);
		vec2 py = dFdy(p);
		float ax = dFdx(across);
		float ay = dFdy(across);
		float det = px.x * py.y - px.y * py.x;
		det = abs(det) < 1e-10 ? 1e-10 : det;
		vec2 g = vec2(ax * py.y - ay * px.y, ay * px.x - ax * py.x) / det;
		float width = 1.0 / max(length(g), 1e-4);
		float street = step(0.08, abs(width - 1.0));
		float edge = min(across, 1.0 - across) * width + (grit - 0.5) * 0.16;
		float grime = (1.0 - smoothstep(0.02, 0.3, edge)) * street;
		// Once a pixel is wider than the dirty band, its average instead,
		// on every piece (so far corners don't read paler than the walks).
		grime = mix(grime, 0.18, smoothstep(0.05, 0.3, fwidth(across) * width));
		col *= mix(vec3(1.0), vec3(0.62, 0.64, 0.55), grime);
	}
#endif
	col *= 1.0 + (grit - 0.5) * 0.16 * close;
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
	float rough = 0.88;
	if (photo > 0.0) {
		// The broom finish and the odd chip, in the slab's own colour.
		float near = photo * close;
		vec4 ph = photo_at(p, near);
		col *= mix(1.0, ph.x, 1.0 - cover);
		rough = mix(rough, 0.75 + ph.y * 0.25, near);
		// Flat tops only: a curb's face and back keep their own slope.
		if (dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) > 0.95) {
			NORMAL = photo_normal_view(ph.zw * (1.0 - cover), VIEW_MATRIX);
		}
	}
	float spec = 0.3;
	// Rain: concrete darkens and takes a sheen, the joints and stains
	// staying wet longest; it dries ahead of the street.
	vec4 wl = wet_now();
	if (wl.x > 0.0) {
		float low = texture(noise_soft, p / 7.0 + 0.23).r + stain * 0.15 + joint * 0.2;
		float film = smoothstep(0.2 - low * 0.18, 0.4 - low * 0.18, wl.x) * (1.0 - cover);
		col *= mix(1.0, 0.68, film);
		rough = mix(rough, 0.42, film);
		spec = mix(spec, 0.4, film);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, spec);
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
	// Wet paint darkens a little and shines; worn spots like the asphalt.
	float wf = smoothstep(0.08, 0.3, wet_now().x);
	col *= mix(1.0, mix(0.85, 0.6, smoothstep(0.42, 0.68, wear)), wf);
	float rough = mix(0.7, 0.25, wf);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, 0.35);
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
	// The same crushed limestone as the county roads painted on the land
	// (TerrainView gravel), so a joined stretch runs on into the paint.
	// Mid grey-tan, a little lighter than old asphalt (it read as a pale
	// sidewalk at 0.5-0.6: Nathan 2026-10-25, "doesn't look like gravel").
	vec3 col = mix(vec3(0.39, 0.37, 0.33), vec3(0.48, 0.46, 0.41), patch);
	col *= 1.0 + (grain - 0.5) * 0.35 * close;
	col *= 0.94 + texture(noise_grain, p / 1.6).r * 0.12;
	// The odd tuft of grass, small and soft-edged.
	float weeds = smoothstep(0.72, 0.86, texture(noise_soft, turn(p, 1.7) / 1.8).r);
	col = mix(col, vec3(0.18, 0.23, 0.10) * (0.8 + grain * 0.4), weeds * 0.5);
	float wf = smoothstep(0.1, 0.4, wet_now().x);
	col *= mix(1.0, 0.72, wf);
	float rough = mix(0.95, 0.6, wf);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, 0.2);
}
"""

## Gravel shoulders on country roads, benchmarked against photos of
## Indiana county and state roads (SR 18, SR 26, CR 600 N in Grant County):
## #53 crushed limestone, a mix of pale and mid grey stones with brown
## fines between them, darker and packed where wheels drop off the
## pavement, loose and paler further out, then thinning into the grass in
## a ragged line with tufts coming through. Stones are a few cm: drawn as
## a speckle at two sizes that blends into an even grain before it is
## small enough to shimmer, so from 300 m the shoulder still reads as
## stone, not a pale stripe. UV.x * 4 runs 0 at the pavement to 1 at the
## shoulder's outer edge; past the ragged line the ground shows through.
const SHOULDER := """
global uniform float snow;
void fragment() {
	vec2 p = world_pos.xz;
	float w = UV.x * 4.0;
	float fp = length(fwidth(p));  // metres per pixel
	// The ragged edge into the grass: wanders a metre or so along the
	// road, with single tufts and gaps finer than that.
	float wander = texture(noise_soft, p / 6.0).r;
	float tufts = texture(noise_grain, p / 2.4).r;
	float edge = 0.5 + wander * 0.45 + (tufts - 0.5) * 0.3;
	if (w > edge) {
		discard;
	}
	// Stones: two sizes of speckle, fading to their average once a stone
	// is under about two pixels.
	float s1 = texture(noise_grain, p / 0.09).r;
	float s2 = texture(noise_grain, turn(p, 0.8) / 0.23).r;
	float fine = clamp(0.06 / max(fp, 1e-4) - 0.5, 0.0, 1.0);
	float mid = clamp(0.18 / max(fp, 1e-4) - 0.5, 0.0, 1.0);
	float stones = (s1 - 0.5) * 0.55 * fine + (s2 - 0.5) * 0.45 * mid;
	// Limestone grey, warmer and darker where the fines and dirt show.
	float dirt = texture(noise_soft, p / 2.3).r;
	vec3 stone = mix(vec3(0.36, 0.355, 0.335), vec3(0.47, 0.46, 0.43), texture(noise_soft, p / 17.0).r);
	vec3 col = mix(stone, vec3(0.33, 0.30, 0.25), smoothstep(0.45, 0.8, dirt) * 0.6);
	col *= 1.0 + stones;
	// Packed and darker along the pavement where wheels run off it.
	col *= 1.0 - 0.14 * (1.0 - smoothstep(0.0, 0.35, w));
	// Grass coming through toward the outer edge, and the odd tuft.
	float grass = smoothstep(edge - 0.3, edge, w) * smoothstep(0.35, 0.65, tufts);
	col = mix(col, vec3(0.20, 0.25, 0.11) * (0.85 + s2 * 0.3), grass * 0.75);
	// Even from far off, the stone reads a little mottled, never flat.
	col *= 0.94 + texture(noise_grain, p / 1.6).r * 0.12;
	col = mix(col, vec3(0.86, 0.88, 0.9), snow * 0.85);
	float wf = smoothstep(0.1, 0.4, wet_now().x) * (1.0 - snow);
	col *= mix(1.0, 0.72, wf);
	float rough = mix(0.97, 0.6, wf);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.15;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, 0.15);
}
"""


## Historic brick street, benchmarked against photos of Indiana brick
## streets: 4 x 8 in red-brown paving brick laid across the street in
## running bond, sand-filled joints, each brick a little different, darker
## worn paths. Bricks under a couple of pixels blend to their average so
## they don't shimmer. UV.y * 4 is metres along; UV.x * 4 is the fraction
## across, and brick streets are 9 m (RoadStyle Brick street).
const BRICK := """
uniform vec4 base : source_color = vec4(0.42, 0.24, 0.18, 1.0);
global uniform float snow;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float along = UV.y * 4.0 / 0.1;
	float course = floor(along);
	float across = UV.x * 4.0 * 9.0 / 0.2 + mod(course, 2.0) * 0.5;
	vec2 cell = vec2(floor(across), course);
	float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec2 f = vec2(fract(across), fract(along));
	vec2 fw = fwidth(vec2(across, along));
	vec2 inside = smoothstep(vec2(0.0), fw + vec2(0.04, 0.08), min(f, 1.0 - f));
	float joint = 1.0 - inside.x * inside.y;
	float fine = clamp(2.0 - max(fw.x, fw.y) * 2.0, 0.0, 1.0);
	vec3 brick = base.rgb * (0.8 + h * 0.32);
	vec3 col = mix(base.rgb * 0.96, mix(brick, vec3(0.40, 0.36, 0.31), joint * 0.75), fine);
	col *= 0.88 + texture(noise_soft, p / 14.0).r * 0.18;
	col *= 1.0 + (texture(noise_grain, p / 0.5).r - 0.5) * 0.12 * close;
	float cover = smoothstep(0.2, 0.6, snow + texture(noise_soft, p / 6.0).r * 0.3 - 0.15);
	col = mix(col, vec3(0.80, 0.83, 0.88), cover * 0.9);
	// Wet brick: deeper red, the worn tops glossy, the sand joints dark.
	float wf = smoothstep(0.08, 0.35, wet_now().x) * (1.0 - cover);
	col *= mix(1.0, mix(0.66, 0.5, joint), wf);
	float rough = mix(0.85, mix(0.25, 0.6, joint), wf);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, 0.3);
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
	// Wet: darker dirt, water standing in the wheel ruts.
	float wf = smoothstep(0.1, 0.4, wet_now().x) * (1.0 - cover);
	float pool = rut * smoothstep(0.55, 0.7, patch) * smoothstep(0.3, 0.6, wet_now().x);
	col *= mix(1.0, 0.7, wf) * mix(1.0, 0.75, pool);
	float rough = mix(mix(0.95, 0.65, wf), 0.05, pool);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
	EMISSION = lamp_light(world_pos, col, rough, NORMAL, VIEW, VIEW_MATRIX, 0.2);
}
"""

## Vertex colours are sRGB. The browser's renderer (Compatibility) hands
## these meshes' colours over already made linear; vtx() undoes that, so
## the colours and the numbers packed in them read the same everywhere.
const VTX := """
vec4 vtx(vec4 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c.rgb = mix(c.rgb * 12.92, 1.055 * pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c.rgb));
#endif
	return c;
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
const FIELD := VTX + """
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
	vec3 crop = lin(vtx(COLOR).rgb) * 1.45 * (0.8 + patch * 0.34 + (mid - 0.5) * 0.14);
	// Soil shows through the crop the way it does from the air over Pike
	// County: thinner, yellower growth on eroded knobs (light Alford and
	// Wellston silt loams) and darker, lusher crop down the wet swales.
	float knob = smoothstep(0.55, 0.85, texture(noise_soft, turn(p, 0.4) / 95.0 + 0.17).r);
	float swale = smoothstep(0.6, 0.9, texture(noise_soft, turn(p, 2.0) / 140.0 + 0.71).r);
	crop = mix(crop, crop * vec3(1.25, 1.12, 0.8), knob * 0.55);
	crop *= 1.0 - swale * 0.18;
	crop *= 1.0 - gap * 0.22 - tram * 0.12;
	crop *= 0.96 + grain * 0.08;
	// Fencerow verge: rough grass with brushy darker clumps.
	vec3 verge = mix(vec3(0.15, 0.21, 0.07), vec3(0.21, 0.22, 0.1), mid);
	verge *= 0.85 + grain * 0.3;
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
const QUARRY := VTX + """
void fragment() {
	vec2 p = world_pos.xz;
	float s = UV.x;
	float floor_at = vtx(COLOR).r * 100.0;
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
	float ramp = (1.0 - step(0.5, vtx(COLOR).g)) * step(s, floor_at + 4.0);
	col = mix(col, vec3(0.56, 0.53, 0.46) * (0.95 + patch * 0.1), ramp);
	col *= 1.0 + (grain - 0.5) * 0.25 * close;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

static var _cache := {}
static var _soft: Texture2D
static var _grain: Texture2D


## The photo scans and their real size across in metres (Poly Haven).
const PHOTO_DIR := "res://art/textures/roads/"
const PHOTOS := {
	"asphalt": ["clean_asphalt", 2.1, 1.6],
	"concrete": ["brushed_concrete", 2.5, 0.6],
}
static var _photo_mats := {}  # material -> {uniform prefix: photo key}
static var _photo_hooked := false


static func asphalt() -> ShaderMaterial:
	return with_photo(_make("asphalt", ASPHALT, {}), "asphalt")


## Sidewalk slabs with joints, or plain cast concrete (curbs, bridges).
static func concrete(color: Color, slabs := false) -> ShaderMaterial:
	return with_photo(_make("concrete %s %s" % [color, slabs], CONCRETE,
			{"base": color, "joints": 1.0 if slabs else 0.0}), "concrete")


## How strongly the photo scans show: on the desktop's High tier and up
## only. The browser leaves art/textures out of its download.
static func photo_level() -> float:
	var q := GraphicsQuality.current
	if q == null or not q.active or q.browser or q.tier < GraphicsQuality.HIGH:
		return 0.0
	return 1.0


static func with_photo(mat: ShaderMaterial, key: String, prefix := "photo") -> ShaderMaterial:
	if not _photo_mats.has(mat):
		_photo_mats[mat] = {}
	if _photo_mats[mat].has(prefix):
		return mat
	_photo_mats[mat][prefix] = key
	_photo_apply(mat, key, photo_level(), prefix)
	if not _photo_hooked and GraphicsQuality.current:
		_photo_hooked = true
		GraphicsQuality.current.changed.connect(func():
			var level := photo_level()
			for m in _photo_mats:
				for pre in _photo_mats[m]:
					_photo_apply(m, _photo_mats[m][pre], level, pre))
	return mat


## The photo block under another name, for a shader that lays two scans
## (a lot's asphalt beside its concrete walks). Needs turn() defined.
static func photo_code(prefix: String) -> String:
	return PHOTO.replace("photo", prefix)


## The scans load the first time a tier shows them, so Low and Medium
## machines never hold them in memory.
static func _photo_apply(mat: ShaderMaterial, key: String, level: float, prefix := "photo") -> void:
	var spec: Array = PHOTOS[key]
	var base: String = PHOTO_DIR + spec[0]
	if level > 0.0 and mat.get_shader_parameter(prefix + "_albedo") == null:
		if not ResourceLoader.exists(base + "_diff.jpg"):
			return
		mat.set_shader_parameter(prefix + "_albedo", load(base + "_diff.jpg"))
		mat.set_shader_parameter(prefix + "_normal", load(base + "_nor_gl.jpg"))
		mat.set_shader_parameter(prefix + "_rough", load(base + "_rough.jpg"))
		mat.set_shader_parameter(prefix + "_size", spec[1])
		mat.set_shader_parameter(prefix + "_bump", spec[2])
	mat.set_shader_parameter(prefix, level if mat.get_shader_parameter(prefix + "_albedo") != null else 0.0)


## Down the middle of every lane, where no tyre runs, a darker strip of oil
## and drips from passing cars, patchy along its length; the wheel paths
## either side stay a touch darker than the shoulder of the lane. Laid over
## the asphalt as a multiply on desktop High and up (RoadMesh._lane_wear).
const LANE_WEAR := """
void fragment() {
	// UV.x * 4 runs 0..1 across the lane.
	float a = UV.x * 4.0;
	vec2 p = world_pos.xz;
	float fade = clamp(1.0 - length(VERTEX) / 350.0, 0.0, 1.0);
	float patchy = smoothstep(0.25, 0.75, texture(noise_soft, p / 11.0 + 0.3).r);
	float drip = exp(-pow((a - 0.5) / 0.12, 2.0)) * (0.35 + 0.65 * patchy);
	drip *= 0.7 + 0.6 * texture(noise_grain, p / 0.8).r;
	float tyre = exp(-pow((a - 0.22) / 0.07, 2.0)) + exp(-pow((a - 0.78) / 0.07, 2.0));
	ALBEDO = vec3(1.0 - fade * (0.3 * drip + 0.07 * tyre));
}
"""


static func lane_wear() -> ShaderMaterial:
	return _make("lane wear", LANE_WEAR, {}, COMMON.replace("render_mode cull_disabled;",
		"render_mode cull_disabled, blend_mul, unshaded, depth_draw_never, shadows_disabled, fog_disabled;"))


static func gravel() -> ShaderMaterial:
	return _make("gravel", GRAVEL, {})


## A country road's gravel shoulder (drawn out from the pavement's edge).
static func shoulder() -> ShaderMaterial:
	return _make("shoulder", SHOULDER, {})


## The county highways drawn on past the town to the horizon (ExitRoads)
## run for miles over land drawn coarser and coarser, and with the roads'
## own light pull the hills showed through them, so from afar a road read
## as a grey dashed line (Nathan, 2026-10-25). These draw with the fields'
## stronger pull, so the road always wins against the land it lies on.
static func far_road(kind: String, color := Color.WHITE) -> ShaderMaterial:
	match kind:
		"asphalt": return _make("far asphalt", ASPHALT, {}, FIELD_COMMON)
		"shoulder": return _make("far shoulder", SHOULDER, {}, FIELD_COMMON)
		"concrete": return _make("far concrete %s" % color, CONCRETE, {"base": color, "joints": 0.0}, FIELD_COMMON)
	return _make("far paint %s" % color, PAINT, {"paint": color}, FIELD_COMMON)


## Chip seal: the asphalt shader in the grey-tan of the stone chips.
static func chip_seal() -> ShaderMaterial:
	return _make("chip seal", ASPHALT, {"fresh": Color(0.30, 0.29, 0.27), "faded": Color(0.42, 0.40, 0.37),
		"tar": Color(0.2, 0.19, 0.18)})


static func brick() -> ShaderMaterial:
	return _make("brick", BRICK, {})


static func quarry() -> ShaderMaterial:
	return _make("quarry", QUARRY, {})


static func lane(color: Color) -> ShaderMaterial:
	return _make("lane %s" % color, LANE, {"base": color})


static func field() -> ShaderMaterial:
	return _make("field", FIELD, {}, FIELD_COMMON)


static func paint(color: Color) -> ShaderMaterial:
	return _make("paint %s" % color, PAINT, {"paint": color})


static func _make(key: String, body: String, params: Dictionary, common := COMMON) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	LampLight.ensure_globals()
	var shader := Shader.new()
	shader.code = common + LampLight.GLSL + body
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
