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
	// Weathering that still reads from across the street: soft patches of
	// older and newer brick and repointing, and rain-washed streaks run
	// down from sills and the coping (photos of 1890s Main Street walls).
	float patch = texture(noise_soft, (world_pos.xz + world_pos.y * 0.7) / 9.0).r;
	float streak = smoothstep(0.68, 0.9, texture(noise_soft, vec2((world_pos.x + world_pos.z) / 2.3, world_pos.y / 38.0)).r);
	col *= (0.9 + patch * 0.2) * (1.0 - streak * 0.1);
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
	// Weathering: big soft patches and the odd dark algae streak. Streaks
	// run down the slope (UV.y climbs from the eave), wander a little, and
	// only show on some stretches of roof, as real ones do; drawn in world
	// x/y they read as metal-roof seams or bands along the ridge.
	float w = texture(noise_soft, world_pos.xz / 14.0).r;
	float wander = texture(noise_soft, vec2(UV.y / 9.0, UV.x / 23.0)).r;
	float streak = smoothstep(0.66, 0.86, texture(noise_soft, vec2(UV.x / 1.4 + wander * 0.6, UV.y / 22.0)).r);
	streak *= smoothstep(0.45, 0.7, texture(noise_soft, world_pos.xz / 31.0 + 0.37).r);
	vec3 col = vcol(COLOR.rgb) * s * (0.9 + w * 0.2) * (1.0 - streak * 0.14);
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
// Office glass is UV.x in 4..5 (lit a floor at a time after dark).
// A shop window (UV.x in 2..3, set by the builders' `shopfront` on the
// desktop): a lit sales floor behind the glass, found by casting the view
// ray into a box room the width of the pane, from the floor below the
// bulkhead to a ceiling above the head, 6 m deep. Shelves of stock or racks
// of clothes on the walls, tile floor, lay-in ceiling with light panels;
// after dark most stay lit, as Main Street windows do.
const vec3 CLOTH[12] = vec3[](vec3(0.06, 0.08, 0.16), vec3(0.03, 0.03, 0.035), vec3(0.16, 0.16, 0.17),
	vec3(0.42, 0.42, 0.42), vec3(0.12, 0.2, 0.34), vec3(0.45, 0.38, 0.25), vec3(0.75, 0.74, 0.7),
	vec3(0.2, 0.24, 0.14), vec3(0.3, 0.06, 0.08), vec3(0.06, 0.08, 0.16), vec3(0.55, 0.08, 0.08), vec3(0.75, 0.6, 0.15));
// The ray's entry into a box (1e9 if it misses), and which slab it came
// through (the top when `top` is 1).
float box_t(vec3 o, vec3 rd, vec3 bmin, vec3 bmax, out float top) {
	vec3 inv = 1.0 / rd;
	vec3 t0 = (bmin - o) * inv;
	vec3 t1 = (bmax - o) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float tin = max(max(tn.x, tn.y), tn.z);
	float tout = min(min(tf.x, tf.y), tf.z);
	top = step(max(tn.x, tn.z), tn.y);
	return (tin > 0.0 && tin < tout) ? tin : 1e9;
}

bool shop_room(vec2 uv, vec3 vw, bool diner, float sill, out vec3 col, out float glow) {
	vec3 n = normalize(world_normal);
	vec3 inw = dot(vw, n) > 0.0 ? n : -n;
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), inw));
	float px = dot(world_pos, rt);
	float gx = dFdx(uv.x) * dFdx(uv.x) + dFdy(uv.x) * dFdy(uv.x);
	float gy = dFdx(uv.y) * dFdx(uv.y) + dFdy(uv.y) * dFdy(uv.y);
	if (gx < 1e-12 || gy < 1e-12) {
		return false;
	}
	float sx = (dFdx(px) * dFdx(uv.x) + dFdy(px) * dFdy(uv.x)) / gx;
	float sy = (dFdx(world_pos.y) * dFdx(uv.y) + dFdy(world_pos.y) * dFdy(uv.y)) / gy;
	float a = px - (uv.x - 2.0) * sx;
	float xl = min(a, a + sx) - 1.2;
	float xr = max(a, a + sx) + 1.2;
	float yb = world_pos.y - uv.y * sy;
	float yf = yb - sill;
	float yc = yb + abs(sy) + 0.5;
	vec3 rd = vec3(dot(vw, rt), vw.y, max(dot(vw, inw), 0.02));
	float tx = abs(rd.x) < 1e-4 ? 1e9 : ((rd.x > 0.0 ? xr : xl) - px) / rd.x;
	float ty = abs(rd.y) < 1e-4 ? 1e9 : ((rd.y > 0.0 ? yc : yf) - world_pos.y) / rd.y;
	float tz = 6.0 / rd.z;
	float t = min(min(tx, ty), tz);
	vec3 h = vec3(px, world_pos.y, 0.0) + rd * t;
	float sid = hash(vec2(floor(xl * 2.0), floor(dot(world_pos, inw) * 2.0) + floor(yb)));
	vec3 wallc = mix(vec3(0.56, 0.52, 0.46), vec3(0.46, 0.50, 0.53), hash(vec2(sid, 1.0)));
	glow = 0.0;
	float hy = h.y - yf;
	if (t == ty && rd.y < 0.0) {
		vec2 f = vec2(h.x, h.z) / 0.6;
		float chk = mod(floor(f.x) + floor(f.y), 2.0);
		vec3 tile = mix(vec3(0.50, 0.48, 0.45), vec3(0.58, 0.56, 0.52), chk);
		vec3 wood = vec3(0.42, 0.30, 0.20) * (0.85 + 0.3 * hash(vec2(floor(h.x / 0.15), floor(h.z / 1.2))));
		col = mix(tile, wood, step(0.55, hash(vec2(sid, 2.0))));
		if (diner) {
			// Black and white checkerboard tile, 30 cm squares.
			vec2 q = floor(vec2(h.x, h.z) / 0.3);
			col = mix(vec3(0.06), vec3(0.78, 0.77, 0.74), mod(q.x + q.y, 2.0));
		}
	} else if (t == ty) {
		vec2 f = fract(vec2(h.x, h.z) / 1.2);
		float panel = step(0.25, f.x) * step(f.x, 0.75) * step(0.05, f.y) * step(f.y, 0.95);
		col = mix(vec3(0.62), vec3(1.0, 0.97, 0.9), panel);
		glow = panel;
	} else {
		// A wall: the back one (along x) or a side one (along depth).
		float u = t == tz ? h.x : h.z;
		col = wallc;
		bool racks = hash(vec2(sid, 3.0)) > 0.72;
		if (diner) {
			// The lunch counter along the back: formica front, a chrome
			// edge, the pie case on it; a menu board on the wall above.
			// Side walls get a wood wainscot.
			vec3 fronts[3] = vec3[3](vec3(0.45, 0.06, 0.07), vec3(0.08, 0.36, 0.36), vec3(0.72, 0.66, 0.52));
			vec3 front = fronts[clamp(int(hash(vec2(sid, 8.0)) * 3.0), 0, 2)];
			if (t == tz) {
				col = mix(col, front, step(hy, 1.0));
				col = mix(col, vec3(0.8, 0.81, 0.82), step(abs(hy - 1.03), 0.03));
				float pie = step(1.06, hy) * step(hy, 1.45) * step(0.6, fract(u / 3.1));
				col = mix(col, vec3(0.55, 0.5, 0.42) + 0.25 * step(0.5, fract(hy * 8.0)), pie);
				float board = step(1.75, hy) * step(hy, 2.45) * step(0.15, fract(u / 4.0)) * step(fract(u / 4.0), 0.85);
				// Rows of white letters on the dark board, short items and prices.
				float row = floor((hy - 1.75) / 0.14);
				float fu = fract(u / 4.0);
				float line = step(0.6, fract((hy - 1.75) / 0.14)) * step(0.5, row) * step(row, 3.5)
					* step(fu, 0.25 + 0.4 * hash(vec2(row, sid)) + 0.15 * step(0.78, fu) * 2.0) * step(0.2, fu);
				col = mix(col, mix(vec3(0.12, 0.1, 0.09), vec3(0.75, 0.72, 0.62), line * 0.8), board);
			} else {
				col = mix(col, vec3(0.36, 0.24, 0.15), step(hy, 1.0));
			}
		} else if (racks) {
			if (hy > 0.75 && hy < 1.75) {
				float g = floor(u / 0.09);
				float c = hash(vec2(g, sid));
				// What a real rack holds: mostly navy, black, greys, denim,
				// khaki and white, with the odd bright piece.
				vec3 cloth = CLOTH[clamp(int(hash(vec2(g, 5.0 + sid)) * 12.0), 0, 11)];
				float len = 0.75 + 0.5 * hash(vec2(g, 11.0));
				col = mix(col, cloth, step(1.75 - len, hy) * step(0.12, c));
			}
			col = mix(col, vec3(0.6), step(abs(hy - 1.78), 0.025));
		} else if (hy > 0.1 && hy < 2.1) {
			float row = floor(hy / 0.42);
			float fy = fract(hy / 0.42);
			float g = floor(u / 0.22);
			float p = hash(vec2(g, row) + sid * 7.0);
			vec3 stock = mix(vec3(hash(vec2(g, row + 1.0)), hash(vec2(g + 3.0, row)), hash(vec2(row, g + 5.0))), vec3(0.55), 0.45);
			vec3 c = mix(wallc * 0.8, stock, step(0.18, p) * step(fy, 0.1 + 0.75 * hash(vec2(g, row + 9.0))));
			col = mix(c, vec3(0.30, 0.27, 0.24), step(fy, 0.07));
		}
	}
	// A display table in the middle of the floor (or a low gondola), stock
	// on its top: the slab test of the ray against its box.
	vec3 o = vec3(px, world_pos.y, 0.0);
	vec3 o0 = o;
	if (diner) {
		// Window booths, a table between two high-backed vinyl benches every
		// 1.9 m (the classic 24 in bench, 30 in table), walked along the
		// ray's way across the room.
		vec3 vinyls[4] = vec3[4](vec3(0.42, 0.05, 0.06), vec3(0.05, 0.28, 0.28), vec3(0.28, 0.15, 0.09), vec3(0.3, 0.04, 0.1));
		vec3 vinyl = vinyls[clamp(int(hash(vec2(sid, 9.0)) * 4.0), 0, 3)];
		float c0 = floor(px / 1.9);
		float dir = rd.x >= 0.0 ? 1.0 : -1.0;
		for (int k = 0; k < 5; k++) {
			float xc = (c0 + dir * float(k) + 0.5) * 1.9;
			if (xc < xl - 1.0 || xc > xr + 1.0) {
				continue;
			}
			float top;
			for (int b = 0; b < 5; b++) {
				vec3 lo;
				vec3 hi;
				vec3 bc = vinyl;
				if (b < 2) {
					float sgn = b == 0 ? -1.0 : 1.0;
					lo = vec3(xc + sgn * 0.95, yf, 0.25);
					hi = vec3(xc + sgn * 0.8, yf + 1.22, 1.85);
				} else if (b < 4) {
					float sgn = b == 2 ? -1.0 : 1.0;
					lo = vec3(xc + sgn * 0.8, yf, 0.25);
					hi = vec3(xc + sgn * 0.38, yf + 0.46, 1.85);
				} else {
					lo = vec3(xc - 0.35, yf + 0.71, 0.3);
					hi = vec3(xc + 0.35, yf + 0.76, 1.5);
					bc = vec3(0.8, 0.77, 0.68);
				}
				float tb = box_t(o0, rd, min(lo, hi), max(lo, hi), top);
				if (tb < t) {
					t = tb;
					glow = 0.0;
					// Tops catch the light; the tufted backs read in rows.
					vec3 bp = o0 + rd * tb;
					col = bc * mix(0.75 + 0.1 * step(0.5, fract(bp.z / 0.4)), 1.15, top);
				}
			}
		}
		col *= mix(1.0, 0.72, clamp(t * rd.z / 6.0, 0.0, 1.0));
		return true;
	}
	vec3 bmin = vec3((xl + xr) * 0.5 - 0.8, yf, 2.0);
	vec3 bmax = vec3((xl + xr) * 0.5 + 0.8, yf + mix(0.8, 1.4, step(0.5, hash(vec2(sid, 4.0)))), 3.4);
	vec3 inv = 1.0 / rd;
	vec3 t0 = (bmin - o) * inv;
	vec3 t1 = (bmax - o) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float tin = max(max(tn.x, tn.y), tn.z);
	float tout = min(min(tf.x, tf.y), tf.z);
	if (tin > 0.0 && tin < tout && tin < t) {
		vec3 b = o + rd * tin;
		vec3 fix = mix(vec3(0.42, 0.30, 0.20), vec3(0.85, 0.84, 0.8), step(0.5, hash(vec2(sid, 6.0))));
		if (tin == tn.y) {
			// The top: folded stock in rows.
			float g = floor(b.x / 0.3) + floor(b.z / 0.35) * 7.0;
			col = mix(fix, CLOTH[clamp(int(hash(vec2(g, sid)) * 12.0), 0, 11)] + 0.08, step(0.3, hash(vec2(g, 2.0 + sid))));
		} else {
			col = fix * 0.7;
		}
		t = tin;
		glow = 0.0;
	}
	// Further in, a little dimmer; and the corners darker.
	col *= mix(1.0, 0.72, clamp(t * rd.z / 6.0, 0.0, 1.0));
	return true;
}

void fragment() {
	bool shop = false;
	// UV.x in 2..4: a shop's room behind its glass; 6..8: a diner's, its
	// windows high over the booths (6..7) or low on Main Street (7..8).
	bool diner = UV.x >= 6.0 && UV.x < 8.0;
	if ((UV.x >= 2.0 && UV.x < 4.0) || diner) {
		vec3 vw = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
		vec3 inside;
		float glow;
		float low = step(7.0, UV.x);
		if (shop_room(UV - vec2(diner ? 4.0 + low : 0.0, 0.0), vw, diner, diner ? 0.9 - 0.45 * low : 0.45, inside, glow)) {
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
			vec3 sky = mix(vec3(0.20, 0.26, 0.34), vec3(0.45, 0.52, 0.60), UV.y) * (1.0 - night * 0.85);
			float blinds = step(1.0 - COLOR.a, UV.y);
			inside = mix(inside, vcol(COLOR.rgb) * 0.3, blinds);
			float open = mix(1.0, step(hash(floor(world_pos.xz / 4.0)), 0.75), smoothstep(0.2, 0.6, night));
			float k = 0.12 + 0.5 * fres;
			ALBEDO = mix(inside * 0.16, sky, k);
			ROUGHNESS = 0.08;
			SPECULAR = 0.6;
			EMISSION = (inside * (0.07 + 0.8 * night) + vec3(1.0, 0.95, 0.85) * glow * (0.35 + 1.4 * night)) * open * (1.0 - k);
			shop = true;
		}
	}
	if (!shop) {
	// UV.x in 4..5: office glass (the builders' `office_glass`, desktop).
	float office = step(4.0, UV.x) * step(UV.x, 5.0);
	float ux = fract(UV.x);
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
	float side = max(1.0 - smoothstep(0.17, 0.24, ux), smoothstep(0.76, 0.83, ux));
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
	if (office > 0.5) {
		// Offices after hours go dark a floor at a time: a few whole floors
		// still lit (late workers, the cleaning crew) in cool LED white, a
		// stray desk lamp elsewhere.
		float fl = floor(world_pos.y / 3.6);
		float bld = hash(floor(world_pos.xz / 45.0));
		float floor_on = step(hash(vec2(fl * 1.7, bld * 53.0)), 0.2);
		float lit = mix(step(0.96, hash(cell + 9.1)), step(hash(cell + 4.4), 0.88), floor_on);
		lit *= smoothstep(0.2, 0.6, night);
		EMISSION = vec3(0.82, 0.9, 1.0) * lit * mix(1.8, 1.0, blinds) * (0.85 + 0.3 * UV.y);
	}
	}
}
"""

## Ground work, by vertex alpha: concrete drives and walks (0), asphalt
## lots (0.4), painted lines (0.72, colour in rgb), mulch or gravel (1).
const YARD := """
uniform vec4 concrete : source_color = vec4(0.67, 0.66, 0.62, 1.0);
uniform vec4 asphalt : source_color = vec4(0.30, 0.30, 0.30, 1.0);
// Block cracks, as on the streets (Surfaces.ASPHALT) but closer set: a lot
// gets no traffic to knead it and cracks worse. Metres to the nearest edge.
float lot_crack_edge(vec2 p) {
	vec2 q = vec2(p.x * 0.825 - p.y * 0.565, p.x * 0.565 + p.y * 0.825) / 3.5;
	vec2 qi = floor(q);
	float f1 = 9.0;
	float f2 = 9.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = qi + vec2(float(i), float(j));
			vec2 o = fract(sin(vec2(dot(g, vec2(127.1, 311.7)), dot(g, vec2(269.5, 183.3)))) * 43758.5453);
			vec2 d = g + 0.15 + o * 0.7 - q;
			float l = dot(d, d);
			if (l < f1) { f2 = f1; f1 = l; } else if (l < f2) { f2 = l; }
		}
	}
	return (sqrt(f2) - sqrt(f1)) * 0.5 * 3.5 + (texture(noise_grain, p / 1.7).r - 0.5) * 0.05;
}
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
	// Desktop High and up: the photo scans' own stones and broom marks take
	// over from the drawn speckle up close (Surfaces.PHOTO).
	float near_lot = lotph * clamp(1.0 - length(VERTEX) / 220.0, 0.0, 1.0);
	float near_walk = walkph * clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float is_lot = step(0.2, COLOR.a) * (1.0 - step(0.86, COLOR.a));
	float is_walk = 1.0 - step(0.2, COLOR.a);
	vec2 tilt = vec2(0.0);
	float rough = 0.9;
	float shade_lot = 1.0;
	if (near_lot > 0.0 && is_lot > 0.0) {
		vec4 ph = lotph_at(p, near_lot);
		shade_lot = ph.x;
		rough = mix(rough, 0.82 + ph.y * 0.18, near_lot);
		tilt = ph.zw;
	}
	if (near_walk > 0.0 && is_walk > 0.0) {
		vec4 ph = walkph_at(p, near_walk);
		drive *= ph.x;
		rough = mix(rough, 0.75 + ph.y * 0.25, near_walk);
		tilt = ph.zw;
	}
	// A lot ages to a warm grey in the sun, a little darker where it was
	// sealcoated more lately, with saw-cut patches where a bad spot was dug
	// out and repaved: dark rectangles with straight edges.
	float seal = smoothstep(0.3, 0.7, texture(noise_soft, p / 160.0 + 0.37).r);
	vec2 pc = floor(p / 13.0);
	float ph1 = fract(sin(dot(pc, vec2(41.3, 289.1))) * 43758.5453);
	vec2 pf = p / 13.0 - pc;
	vec2 lo = vec2(fract(ph1 * 17.0), fract(ph1 * 29.0)) * 0.45 + 0.05;
	vec2 hi = lo + vec2(0.2 + fract(ph1 * 7.0) * 0.3, 0.15 + fract(ph1 * 11.0) * 0.3);
	vec2 e = fwidth(pf);
	vec2 inside = smoothstep(lo - e, lo, pf) * (1.0 - smoothstep(hi, hi + e, pf));
	float repave = step(0.8, ph1) * inside.x * inside.y;
	seal = max(seal * 0.7, repave);
	vec3 lot = asphalt.rgb * mix(vec3(1.22, 1.2, 1.15), vec3(0.85), seal)
		* (0.85 + texture(noise_soft, p / 20.0).r * 0.3) * (1.0 - stain * 0.15)
		* (1.0 + (texture(noise_grain, p / 0.3).r - 0.5) * 0.25 * close * (1.0 - near_lot) * (1.0 - seal * 0.6))
		* mix(shade_lot, 1.0, seal * 0.5);
	// Sealed cracks show on the worn stretches; fresh seal hides them.
	if (is_lot > 0.0 && close > 0.0) {
		float footprint = length(fwidth(p));
		float run = smoothstep(0.42, 0.5, texture(noise_soft, p / 6.0 + 0.5).r) * (1.0 - seal);
		float crack = (1.0 - smoothstep(0.03, 0.03 + footprint, lot_crack_edge(p))) * run
			* close * clamp(0.06 / max(footprint, 1e-4), 0.0, 1.0);
		lot = mix(lot, vec3(0.11), crack * 0.7);
		rough -= crack * 0.3;
		tilt *= 1.0 - crack;
	}
	float wear = smoothstep(0.4, 0.7, texture(noise_grain, p / 1.1).r);
	// Paint lies in the pavement's texture, so it takes some of its grain.
	vec3 line = mix(vcol(COLOR.rgb), asphalt.rgb, wear * 0.45) * mix(1.0, shade_lot, 0.6);
	float chips = texture(noise_grain, p / 0.12).r;
	// Wheel-worn and fresh-spread patches, so a big lot isn't one flat colour.
	vec3 loose = vcol(COLOR.rgb) * (0.6 + chips * 0.8) * (0.84 + texture(noise_soft, p / 14.0).r * 0.3);
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
	ROUGHNESS = mix(rough, 0.75, cover);
	SPECULAR = 0.25;
	// Flat ground only, like the sidewalks: a sloped face keeps its own.
	if (dot(tilt, tilt) > 0.0 && world_normal.y > 0.95) {
		NORMAL = lotph_normal_view(tilt * (1.0 - cover), VIEW_MATRIX);
	}
}
"""

## Slip-formed concrete (grain silos and their headhouse): faint lift lines
## 1.2 m apart, dark rain streaks running down the height of the bins, and
## splash grime at the foot. UV.y is the height up the wall in metres.
const SLIPFORM := """
void fragment() {
	float h = world_pos.y;
	float across = world_pos.x * 0.7 + world_pos.z * 0.7;
	float streak = smoothstep(0.45, 0.85, texture(noise_grain, vec2(across / 1.4, h / 60.0)).r);
	float wash = texture(noise_soft, vec2(across / 10.0, h / 35.0)).r;
	float lift = abs(fract(h / 1.2) - 0.5) * 1.2;
	float line = (1.0 - smoothstep(0.0, 0.02 + fwidth(h) * 1.5, lift)) * clamp(0.03 / max(fwidth(h), 0.0001), 0.0, 1.0);
	float grime = 1.0 - 0.12 * (1.0 - smoothstep(0.0, 2.5, UV.y));
	vec3 c = vcol(COLOR.rgb) * (0.96 + wash * 0.08) * (1.0 - streak * 0.1) * (1.0 - line * 0.05) * grime;
	float cover = snow_cover(0.8, 0.95);
	ALBEDO = mix(c, vec3(0.86, 0.88, 0.92), cover);
	ROUGHNESS = 0.8;
	SPECULAR = 0.4;
}
"""

## A farm's crushed-limestone yard, lane and drive (the #53 stone county
## farmsteads are graveled with). UV is metres inside the gravelled piece,
## UV2 the piece's size, so the shader knows its edges and which way a lane
## runs: grass creeps in raggedly at the edges; a lane (anything under
## 8 m across) has the two wheel tracks pressed dark and smooth with a
## crown of grass tufts between them; a yard has darker worn patches where
## trucks turn and park. Loose stones up close (on the desktop at High and
## up, the gravel photo, art/pbr gravel_floor_02); from afar the average
## matches the far farmstead's flat gravel.
const GRAVEL := """
uniform vec4 lawn : source_color = vec4(0.31, 0.42, 0.18, 1.0);
uniform sampler2D gph : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float gph_on = 0.0;
void fragment() {
	vec2 p = world_pos.xz;
	vec2 at = UV;
	vec2 size = UV2;
	float close = clamp(1.0 - length(VERTEX) / 120.0, 0.0, 1.0);
	float fine = texture(noise_grain, p / 0.18).r;
	float pebble = texture(noise_grain, p / 0.7).r;
	float patch = texture(noise_soft, p / 7.0).r;
	float broad = texture(noise_soft, p / 31.0 + 0.17).r;
	vec3 stone = vcol(COLOR.rgb) * (0.84 + patch * 0.2) * (0.9 + broad * 0.16) * (1.0 + (pebble - 0.5) * 0.22);
	stone *= 1.0 + (fine - 0.5) * 0.35 * close;
	if (gph_on > 0.5) {
		vec3 ph = texture(gph, p / 2.0).rgb;
		vec3 avg = textureLod(gph, vec2(0.5), 12.0).rgb;
		stone *= mix(vec3(1.0), ph / max(avg, vec3(0.05)), 0.8 * clamp(1.0 - length(VERTEX) / 90.0, 0.0, 1.0));
	}
	float worn = 0.0;
	float tuft = 0.0;
	if (size.x < 8.0 || size.y < 8.0) {
		// A lane: across it, its wheel tracks and the crown between.
		float across = (size.x < size.y ? at.x - size.x * 0.5 : at.y - size.y * 0.5);
		float along = (size.x < size.y ? at.y : at.x);
		float wob = (texture(noise_soft, vec2(along / 25.0, 0.3)).r - 0.5) * 0.5;
		float c = abs(across + wob);
		worn = 1.0 - smoothstep(0.18, 0.34, abs(c - 0.85));
		tuft = (1.0 - smoothstep(0.2, 0.4, c)) * smoothstep(0.5, 0.7, texture(noise_grain, p / 0.9).r);
	} else {
		worn = smoothstep(0.35, 0.85, texture(noise_soft, p / 22.0 + 0.4).r) * 0.6;
	}
	// Packed by the wheels: darker (the fines and a film of dirt), smoother.
	stone = mix(stone, vcol(COLOR.rgb) * vec3(0.66, 0.65, 0.62) * (0.95 + patch * 0.1), worn * 0.75);
	// Grass in from the edges, ragged.
	float edge = min(min(at.x, size.x - at.x), min(at.y, size.y - at.y));
	float rag = texture(noise_grain, p / 1.3).r * 1.2 + texture(noise_soft, p / 6.0).r * 0.8;
	float grass = 1.0 - smoothstep(0.0, 0.35, edge - rag * 0.9 + 0.2);
	grass = max(grass, tuft * 0.85);
	vec3 g = lawn.rgb * (0.85 + texture(noise_grain, p / 0.4).r * 0.3);
	float cover = snow_cover(0.8, 0.95);
	ALBEDO = mix(mix(stone, g, grass), vec3(0.86, 0.88, 0.92), cover);
	ROUGHNESS = mix(0.95, 0.85, worn);
	SPECULAR = 0.25;
}
"""

## A corrugated steel grain bin (GSI, Sukup and Brock bins on Indiana
## farms), UV in metres: x around, y up the wall (or up the roof's slope
## from the eave). The wall is rolled 2.66 in corrugations running round
## the bin in rings of 44 in sheets, bolted at each ring's lap, with a
## vertical stiffener every sheet length (9 ft 4 in) round it; the roof
## is ribbed panels running up to the peak. Galvanized: a soft sheen, a
## spangle of brighter and duller grains, weathering dull and streaked
## down from the eave, darker at the foot where rain splashes. From afar
## the fine lines blend into the average, never shimmer.
const BIN := """
void fragment() {
	float roof = step(0.35, world_normal.y);
	float h = UV.y;
	float around = UV.x;
	// Corrugations: a light and a dark band each 2.66 in, fading out as they
	// shrink below a pixel.
	float c = h / 0.0676;
	float corr = sin(c * 6.2832) * (1.0 - smoothstep(0.25, 0.6, fwidth(c)));
	// Ring laps every 44 in, and stiffeners round the wall.
	float ring = abs(fract(h / 1.118) - 0.5) * 2.0;
	float lap = (1.0 - smoothstep(0.0, 0.03 + fwidth(h / 1.118) * 2.0, 1.0 - ring)) * clamp(0.02 / max(fwidth(h / 1.118), 0.0001), 0.0, 1.0);
	float st = abs(fract(around / 2.845) - 0.5) * 2.0;
	float stiff = (1.0 - smoothstep(0.0, 0.04 + fwidth(around / 2.845) * 2.0, 1.0 - st)) * clamp(0.03 / max(fwidth(around / 2.845), 0.0001), 0.0, 1.0);
	// Roof ribs every 0.6 m round the eave, closing in toward the peak.
	float r = around / 0.6;
	float rib = abs(fract(r) - 0.5) * 2.0;
	float ribs = (1.0 - smoothstep(0.75, 0.95, rib)) * clamp(0.25 / max(fwidth(r), 0.0001), 0.0, 1.0);
	float spangle = texture(noise_grain, world_pos.xy * 1.7 + world_pos.zy * 1.3).r;
	float streak = texture(noise_soft, vec2(around / 9.0, h / 40.0)).r;
	float grime = 1.0 - 0.14 * (1.0 - smoothstep(0.0, 1.4, h)) * (1.0 - roof);
	float wall_s = (1.0 + corr * 0.07) * (1.0 - lap * 0.22) * (1.0 + stiff * 0.12) * (0.94 + spangle * 0.1)
		* (1.0 - smoothstep(0.55, 0.85, streak) * 0.12) * grime;
	float roof_s = (1.0 - ribs * 0.16) * (0.95 + spangle * 0.08);
	float s = mix(wall_s, roof_s, roof);
	float cover = snow_cover(0.6, 0.85);
	ALBEDO = mix(vcol(COLOR.rgb) * 0.82 * s, vec3(0.86, 0.88, 0.92), cover);
	METALLIC = mix(0.55, 0.0, cover);
	ROUGHNESS = mix(0.42 + streak * 0.12, 0.7, cover);
	SPECULAR = 0.5;
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
## sign, UV.y runs 0..1 up it, and vertex alpha carries the width / 60
## (0: real lettering by SignText; 0.5-0.99: unlit letters painted on an
## awning, width (a - 0.5) * 60; 1: neon tubing or a lamp lens).
const SIGN := """
// Stand-in lettering: a trade word (no names) in 3x5 block capitals, so a
// sign with no business name yet still reads as lettering, not noise.
const int GLYPHS[27] = int[](27306, 23530, 15083, 25166, 15211, 29391, 4815, 27470, 23533, 29847, 11044, 23277, 29257, 23549, 23407, 11114, 4843, 26474, 23275, 14478, 9367, 31597, 11117, 24557, 23213, 9389, 29351);
const int LETTERS[331] = int[](4, 9, 14, 5, 18, 3, 1, 6, 5, 16, 9, 26, 26, 1, 2, 1, 14, 11, 19, 1, 12, 15, 14, 14, 1, 9, 12, 19, 20, 1, 24, 4, 5, 12, 9, 19, 21, 2, 19, 12, 9, 17, 21, 15, 18, 16, 1, 23, 14, 20, 1, 3, 15, 19, 4, 18, 21, 7, 19, 8, 1, 18, 4, 23, 1, 18, 5, 22, 9, 4, 5, 15, 19, 8, 15, 5, 19, 6, 12, 15, 23, 5, 18, 19, 2, 1, 11, 5, 18, 25, 2, 15, 15, 11, 19, 20, 15, 25, 19, 7, 9, 6, 20, 19, 13, 21, 19, 9, 3, 16, 5, 20, 19, 20, 9, 18, 5, 19, 12, 15, 1, 14, 19, 4, 5, 14, 20, 1, 12, 9, 14, 19, 21, 18, 1, 14, 3, 5, 13, 1, 18, 11, 5, 20, 7, 18, 9, 12, 12, 4, 15, 14, 21, 20, 19, 6, 21, 18, 14, 9, 20, 21, 18, 5, 15, 16, 20, 9, 3, 1, 12, 3, 12, 5, 1, 14, 5, 18, 19, 2, 1, 18, 2, 5, 18, 20, 8, 18, 9, 6, 20, 20, 1, 22, 5, 18, 14, 1, 14, 20, 9, 17, 21, 5, 19, 2, 9, 11, 5, 19, 3, 1, 14, 4, 25, 19, 16, 15, 18, 20, 19, 8, 15, 2, 2, 25, 18, 5, 1, 12, 20, 25, 16, 1, 9, 14, 20, 17, 21, 9, 12, 20, 19, 1, 16, 16, 12, 9, 1, 14, 3, 5, 10, 5, 23, 5, 12, 18, 25, 6, 1, 2, 18, 9, 3, 3, 5, 12, 12, 21, 12, 1, 18, 6, 9, 20, 14, 5, 19, 19, 19, 5, 23, 9, 14, 7, 7, 18, 15, 3, 5, 18, 25, 6, 15, 15, 4, 19, 4, 9, 19, 3, 15, 21, 14, 20, 16, 8, 1, 18, 13, 1, 3, 25, 19, 21, 16, 5, 18, 3, 5, 14, 20, 5, 18, 15, 21, 20, 12, 5, 20);
const int WSTART[56] = int[](0, 5, 9, 14, 18, 23, 28, 31, 35, 39, 45, 49, 54, 59, 67, 72, 77, 84, 90, 95, 99, 104, 109, 113, 118, 123, 129, 138, 144, 149, 155, 164, 171, 179, 185, 191, 197, 205, 210, 215, 221, 226, 232, 237, 243, 252, 259, 265, 273, 280, 286, 293, 298, 306, 314, 325);
const int WLEN[56] = int[](5, 4, 5, 4, 5, 5, 3, 4, 4, 6, 4, 5, 5, 8, 5, 5, 7, 6, 5, 4, 5, 5, 4, 5, 5, 6, 9, 6, 5, 6, 9, 7, 8, 6, 6, 6, 8, 5, 5, 6, 5, 6, 5, 6, 9, 7, 6, 8, 7, 6, 7, 5, 8, 8, 11, 6);
void fragment() {
	// Alpha 1: neon tubing or a lamp lens, bright after dark, a little by day.
	float neon = step(0.99, COLOR.a);
	// Alpha 0.5-0.99: letters painted on canvas (awnings), never lit.
	float painted = step(0.5, COLOR.a) * (1.0 - neon);
	float wdt = max(mix(COLOR.a * 60.0, (COLOR.a - 0.5) * 60.0, painted), 0.1);
	// Which word: from the sign's colour and width, the same all across it.
	// (Rounded first: the hash would turn interpolation's last-bit wobble
	// into a different word from one pixel to the next.)
	vec4 qc = floor(COLOR * 255.0 + 0.5);
	vec2 at = floor(MODEL_MATRIX[3].xz);
	int wi = clamp(int(hash(vec2(qc.r * 0.97 + qc.a * 4.13 + at.x * 0.013, qc.g * 0.31 + qc.b * 0.57 + at.y * 0.017)) * 50.0), 0, 49);  // the first 50: trades
	// A builder can name the word instead, so a shop's board and awning
	// agree: UV.y then runs from 2 * (word + 1), and vy is its 0..1.
	float slot = floor(UV.y * 0.5);
	float vy = UV.y - 2.0 * slot;
	wi = slot > 0.5 ? clamp(int(slot) - 1, 0, 55) : wi;
	int len = WLEN[wi];
	float pitch = min(0.42, wdt * 0.78 / float(len));
	// Read left to right on screen whichever way the sign's UVs run.
	float u = dFdx(UV.x) < 0.0 ? wdt - UV.x : UV.x;
	float start = (wdt - float(len) * pitch) * 0.5;
	float fi = floor((u - start) / pitch);
	float band = step(0.0, fi) * step(fi, float(len) - 1.0);
	int li = clamp(int(fi), 0, len - 1);
	vec2 q = (vec2(fract((u - start) / pitch), vy) - vec2(0.15, 0.25)) / vec2(0.7, 0.53);
	float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	ivec2 cell = ivec2(clamp(floor(q * vec2(3.0, 5.0)), vec2(0.0), vec2(2.0, 4.0)));
	int glyph = GLYPHS[LETTERS[WSTART[wi] + li]];
	float on = float((glyph >> ((4 - cell.y) * 3 + cell.x)) & 1);
	// Alpha 0: the business's real name is lettered on (SignText).
	float text = inside * on * band * step(0.0001, COLOR.a) * (1.0 - neon);
	float aa = smoothstep(0.08, 0.3, fwidth(u / pitch));
	text = mix(text, 0.3 * band * step(0.25, vy) * step(vy, 0.78) * step(0.0001, COLOR.a), aa);
	ALBEDO = mix(vcol(COLOR.rgb), vec3(0.86, 0.84, 0.79), text);
	ROUGHNESS = 0.4;
	SPECULAR = 0.5;
	// Lit signs after dark: bright letters on a softly glowing panel.
	EMISSION = mix(vcol(COLOR.rgb) * 0.5, vec3(1.0, 0.95, 0.85) * 2.0, text) * smoothstep(0.3, 0.6, night);
	EMISSION = mix(EMISSION, vcol(COLOR.rgb) * (0.25 + 3.5 * smoothstep(0.2, 0.6, night)), neon) * (1.0 - painted);
	ROUGHNESS = mix(0.4, 0.85, painted);
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
	vec3 dormant = lin(vec3(0.52, 0.48, 0.33)) * (0.85 + big * 0.3);
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
		"yard": mat = _yard()
		"metal": mat = _shader(METAL)
		"sign": mat = _shader(SIGN)
		"chain": mat = _shader(CHAIN)
		"pasture": mat = _shader(PASTURE)
		"far": mat = _shader(FAR)
		"membrane": mat = _shader(MEMBRANE)
		"slipform": mat = _shader(SLIPFORM)
		"bin": mat = _shader(BIN)
		"farm_gravel": mat = _gravel()
		"pool": mat = _pool()
		"foliage": mat = _plain(1.0)
		_: mat = _plain(0.55)  # paint, shutters, trim
	_cache[key] = mat
	return mat


## The name a shared material was made under, or "" for one of its own.
static func name_of(mat: Material) -> String:
	for k in _cache:
		if _cache[k] == mat:
			return k
	return ""


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


## The yard draws two photo scans (Surfaces.PHOTOS): asphalt for lots and
## concrete for drives and walks, each under its own uniform names.
static func _yard() -> ShaderMaterial:
	var turn := "vec2 turn(vec2 p, float a) {\n\treturn vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));\n}\n"
	var mat := _shader(turn + Surfaces.photo_code("lotph") + Surfaces.photo_code("walkph") + YARD)
	Surfaces.with_photo(mat, "asphalt", "lotph")
	return Surfaces.with_photo(mat, "concrete", "walkph")


static func _gravel() -> ShaderMaterial:
	var mat := _shader(GRAVEL)
	# The photo on the desktop at High and up (PhotoGround's own textures).
	if PhotoGround.wanted() and ResourceLoader.exists(PhotoGround.DIR + "gravel_floor_02/albedo.jpg"):
		mat.set_shader_parameter("gph", load(PhotoGround.DIR + "gravel_floor_02/albedo.jpg"))
		mat.set_shader_parameter("gph_on", 1.0)
	return mat


## Light thrown by a lot's own lamps after dark (parking-lot LEDs, sign
## goosenecks): an additive glow, brightest in the middle of the quad and
## gone by its edge, in the vertex colour; nothing by day. Desktop only.
const POOL := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float f = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * COLOR.rgb * f * 0.7 * smoothstep(0.25, 0.6, night);
}
"""


static func _pool() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = POOL
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = -1
	return mat


static func _plain(roughness: float) -> ShaderMaterial:
	var m := _shader(PLAIN)
	m.set_shader_parameter("rough", roughness)
	return m
