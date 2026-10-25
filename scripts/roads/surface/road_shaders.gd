class_name RoadShaders
extends RefCounted
## The shader code for roads that age (RoadSurface makes the materials).
## Benchmarked against photos of Grant County streets, county roads and
## I-69: new asphalt jet black, greying over a few years; thermal cracks
## straight across, a centre-joint crack, then alligator cracking in the
## wheel paths of busy old roads; crack sealer glossy black, then dull;
## potholes in late winter, black cold patch, then a square saw-cut hot
## patch; lane paint bright after its spring repaint, worn by the next;
## chip seal stony and pale; gravel with two packed tire tracks and grass
## up the crown; concrete in 15 ft slabs with the odd cracked panel.
##
## Detail by distance: every line is drawn at its true width and, once it
## is thinner than a pixel, by how much of the pixel it covers, so far off
## a road shows its plain average colour and nothing shimmers. `detail` 0
## (the browser and Low) leaves out the two crack-pattern loops.
## Ribbon meshes from RoadMesh carry metres along the road in UV.y * 4 and
## the fraction across in UV.x * 4; junction pads carry one UV, so they get
## the colour and the cracks but no wheel paths or patches.

## Shared by every road surface: the wear map and the day's date.
static func header() -> String:
	return Surfaces.COMMON + """
uniform sampler2D wear_map : filter_nearest;
uniform vec4 map_rect = vec4(0.0);
uniform float cell = 40.0;
uniform vec2 origin = vec2(0.0);
uniform float has_map = 0.0;
uniform float now_years = 1.0;
uniform float upkeep = 1.0;
uniform float detail = 1.0;
uniform float width = 9.0;
uniform float lane_start = 1.8;
uniform float lane_w = 3.6;
uniform float lane_count = 0.0;
uniform float mirror = 1.0;
uniform float fatigue = 0.3;
uniform float traffic = 0.4;
uniform float edge_break = 0.0;
global uniform float snow;
global uniform vec4 season_look;

const float OXIDISE = %f;
const float SEAL_FIRST = %f;
const float SEAL_SPREAD = %f;
const float SEAL_EVERY = %f;
const float SEAL_LAST = %f;
const float SEAL_DULL = %f;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Years since the 40 m square under lp was paved or resurfaced (StreetAge).
// A square not on the map yet is a street drawn since the last month: new.
// Views with no town behind them (sim-less) get a steady age from the square.
float wear_age(vec2 lp, out float seed) {
	vec2 c = floor(lp / cell);
	seed = h21(c + 0.5);
	vec2 t = c - map_rect.xy;
	if (has_map > 0.5 && t.x >= 0.0 && t.y >= 0.0 && t.x < map_rect.z && t.y < map_rect.w) {
		vec4 d = texelFetch(wear_map, ivec2(t), 0);
		if (d.a > 0.5) {
			float paved = (d.r * 65280.0 + d.g * 255.0) / 256.0 - 64.0;
			return max(now_years - paved, 0.0);
		}
	}
	return has_map > 0.5 ? 0.0 : 2.0 + seed * 22.0;
}

// One number per paving job (every square paved the same day): the crews
// that seal, repaint, re-chip and grade work a whole job at once.
float job_seed(float a) {
	return h21(vec2(fract((now_years - a) * 13.7) * 91.0, 0.37));
}

// The street's age at its last crack sealing, or -1 before the first.
// A town out of money skips the latest one.
float last_seal(float a, float seed) {
	float s0 = SEAL_FIRST + seed * SEAL_SPREAD;
	if (a < s0) {
		return -1.0;
	}
	float s = s0 + min(floor((a - s0) / SEAL_EVERY), SEAL_LAST) * SEAL_EVERY;
	if (upkeep < 0.5 && a - s < 1.0) {
		s -= SEAL_EVERY;
	}
	return s >= s0 ? s : -1.0;
}

// Asphalt by age: black, charcoal by year 3 to 5, then paler as the fines
// wear off and the limestone shows.
vec3 asphalt_col(float a) {
	float ox = 1.0 - exp(-a / OXIDISE);
	vec3 c = mix(vec3(0.07, 0.07, 0.075), vec3(0.21, 0.205, 0.20), ox);
	return mix(c, vec3(0.31, 0.30, 0.285), smoothstep(6.0, 26.0, a) * 0.8);
}

// 1 in a wheel path, 0 between. lane: which lane (signed, two-way), dc: the
// fragment's offset from that lane's centre, in metres.
float wheel_path(float x, out float lane, out float dc) {
	lane = 0.0;
	dc = 9.0;
	if (lane_count < 0.5) {
		return 0.0;
	}
	float xs = mirror > 0.5 ? abs(x) : x;
	float k = clamp(floor((xs - lane_start) / lane_w + 0.5), 0.0, lane_count - 1.0);
	dc = xs - (lane_start + lane_w * k);
	lane = (mirror > 0.5 && x < 0.0) ? -1.0 - k : k;
	return 1.0 - smoothstep(0.22, 0.42, abs(abs(dc) - lane_w * 0.25));
}

// A line `w` metres either side of distance `d`, at most one pixel soft, and
// by coverage once thinner than a pixel (aa: metres a pixel).
float hairline(float d, float w, float aa) {
	return (1.0 - smoothstep(w, w + aa, d)) * min(1.0, (2.0 * w + 0.002) / aa);
}

// Distance to the nearest cell edge of a jittered grid (crack networks).
float cells(vec2 q) {
	vec2 qi = floor(q);
	float f1 = 9.0;
	float f2 = 9.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = qi + vec2(float(i), float(j));
			vec2 o = vec2(h21(g), h21(g + 17.3));
			vec2 d = g + 0.15 + o * 0.7 - q;
			float l = dot(d, d);
			if (l < f1) { f2 = f1; f1 = l; } else if (l < f2) { f2 = l; }
		}
	}
	return (sqrt(f2) - sqrt(f1)) * 0.5;
}

vec3 winter(vec3 col, vec2 p, float g, out float packed) {
	// Plowed and salted: chalky grey with salt streaks, packed snow between
	// the wheel paths.
	float salt = snow * (0.55 + 0.45 * texture(noise_soft, turn(p, 0.3) / 18.0).r);
	col = mix(col, vec3(0.50, 0.50, 0.49) * (0.95 + g * 0.1), salt * 0.55);
	packed = smoothstep(0.72, 0.9, texture(noise_soft, turn(p, 1.2) / 11.0 + 0.7).r) * snow;
	return mix(col, vec3(0.72, 0.74, 0.77) * (0.92 + g * 0.1), packed * 0.45);
}
""" % [RoadWear.OXIDISE_YEARS, RoadWear.SEAL_FIRST, RoadWear.SEAL_SPREAD, RoadWear.SEAL_EVERY,
		float(RoadWear.SEAL_LAST), RoadWear.SEAL_DULL]


static func asphalt() -> String:
	return header() + """
const float THERMAL_FROM = %f;
const float THERMAL_SPREAD = %f;
const float THERMAL_EVERY = %f;
const float FATIGUE_LATE = %f;
const float FATIGUE_SPAN = %f;
const float HOLE_FROM = %f;
const float HOLE_SPAN = %f;
const float HOLE_SHARE = %f;
const float HOT_AT = %f;
const float HOT_SPREAD = %f;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 240.0, 0.0, 1.0);
	float aa = max(length(fwidth(p)), 1e-4);
	float seed;
	float a = wear_age(p - origin, seed);
	float paved = now_years - a;
	float along = UV.y * 4.0;
	float u = UV.x * 4.0;
	float x = (u - 0.5) * width;
	float ribbon = step(1e-6, fwidth(along) + fwidth(u));
	float lane;
	float dc;
	float wheel = wheel_path(x, lane, dc) * ribbon;
	float g = texture(noise_grain, p / 0.31).r;
	vec3 col = asphalt_col(a) * (0.96 + texture(noise_soft, p / 60.0).r * 0.08);
	// Wheel paths: tire grime and, on old truck routes, ruts.
	float rut = wheel * smoothstep(0.5, 3.0, a) * (0.25 + 0.75 * smoothstep(2.0, 20.0, a) * fatigue);
	col *= 1.0 - rut * 0.07;
	float job = job_seed(a);
	float seal = last_seal(a, job);
	float fresh = seal >= 0.0 ? exp(-(a - seal) / SEAL_DULL) : 0.0;
	float worn = seal >= 0.0 ? smoothstep(1.0, 5.0, a - seal) : 0.0;
	float tar = 0.0;    // crack sealer
	float open = 0.0;   // open cracks
	// Thermal cracks straight across, one per 9 m stretch at most.
	if (ribbon > 0.5) {
		float tc = floor(along / THERMAL_EVERY);
		float th = h21(vec2(tc, seed * 97.0));
		float onset = THERMAL_FROM + th * THERMAL_SPREAD;
		if (a > onset) {
			float wob = (texture(noise_soft, vec2(u * 0.7, tc * 0.37)).r - 0.5) * 1.2
				+ (texture(noise_grain, p / 0.8).r - 0.5) * 0.025;
			float d = abs(along - tc * THERMAL_EVERY - 1.5 - fract(th * 7.0) * 6.0 - wob);
			float from = step(0.5, fract(th * 13.0)) * fract(th * 31.0) * 0.4;
			float to = 1.0 - step(0.6, fract(th * 17.0)) * fract(th * 23.0) * 0.4;
			float span = smoothstep(from - 0.02, from, u) * smoothstep(to + 0.02, to, u);
			if (seal >= onset) {
				tar = max(tar, hairline(d, 0.045, aa) * span);
			} else {
				open = max(open, hairline(d, 0.004 + 0.01 * smoothstep(0.0, 10.0, a - onset), aa) * span);
			}
		}
		// The joint between the two paving passes opens along the centre line.
		if (mirror > 0.5) {
			float j_on = 5.0 + seed * 5.0;
			float rc = floor(along / 6.0);
			if (a - j_on > h21(vec2(rc, seed * 53.0)) * 12.0) {
				float d = abs(x + (texture(noise_soft, p / 14.0).r - 0.5) * 0.35
					+ (texture(noise_grain, p / 0.8).r - 0.5) * 0.02);
				if (seal >= j_on) {
					tar = max(tar, hairline(d, 0.05, aa));
				} else {
					open = max(open, hairline(d, 0.006, aa));
				}
			}
		}
	}
	// Fatigue: lengthwise cracks along the wheel paths, then alligator
	// cracking in them, on busy old roads.
	float f_on = FATIGUE_LATE - FATIGUE_SPAN * fatigue;
	if (wheel > 0.01 && a > f_on - 3.0) {
		float rc = floor(along / 6.0);
		if (a - (f_on - 3.0) > h21(vec2(rc, seed * 29.0 + lane)) * 8.0) {
			float d = abs(abs(dc) - lane_w * 0.25 + (texture(noise_soft, p / 12.0).r - 0.5) * 0.25
				+ (texture(noise_grain, p / 0.8).r - 0.5) * 0.02);
			open = max(open, hairline(d, 0.006, aa));
		}
		// In patches a metre or few long, spreading as the road ages.
		float sev = smoothstep(f_on, f_on + 8.0, a) * wheel
			* smoothstep(0.62, 0.72, texture(noise_soft, p / 3.5 + seed).r + smoothstep(f_on, f_on + 14.0, a) * 0.25);
		if (sev > 0.01) {
			if (detail > 0.5 && aa < 0.05) {
				float e = cells(turn(p, 0.3) / 0.3) * 0.3 + (texture(noise_grain, p / 0.4).r - 0.5) * 0.02;
				open = max(open, hairline(e, 0.004, aa) * sev * 0.7);
			} else {
				open = max(open, sev * 0.08);
			}
		}
	}
	// Block cracking where the binder has aged worst (big polygons).
	float block = smoothstep(11.0, 22.0, a) * smoothstep(0.55, 0.7, texture(noise_soft, p / 90.0 + 0.2).r);
	if (block > 0.01) {
		if (detail > 0.5 && aa < 0.15) {
			float e = cells(turn(p, 0.6) / 4.5) * 4.5 + (texture(noise_grain, p / 1.7).r - 0.5) * 0.05;
			float l = hairline(e, seal >= 11.0 ? 0.04 : 0.006, aa) * block;
			if (seal >= 11.0) { tar = max(tar, l); } else { open = max(open, l); }
		} else {
			tar = max(tar, block * 0.03);
		}
	}
	col = mix(col, vec3(0.045), open * 0.85);
	// Sealer: glossy black, dull in months, worn grey by tires in years.
	col = mix(col, mix(mix(vec3(0.13), col * 0.75, worn * 0.6), vec3(0.03), fresh), tar * 0.85);
	// Utility cuts: a strip across part of the road, cut in years after
	// the paving, with its own age.
	float cut_rough = (texture(noise_grain, p / 0.9).r - 0.5) * 0.12;
	{
		float cc = floor(along / 14.0);
		float ch = h21(vec2(cc, seed * 7.0 + 3.0));
		float c_on = 2.0 + fract(ch * 91.7) * 20.0;
		if (ribbon > 0.5 && ch > 0.93 && a > c_on) {
			float h2 = fract(ch * 57.3);
			float a0 = h2 * 0.6;
			float s0 = 3.0 + h2 * 4.0;
			float s = mod(along, 14.0);
			float m = smoothstep(a0 - aa, a0, u) * smoothstep(a0 + 0.35, a0 + 0.35 - aa, u)
				* smoothstep(s0 - aa, s0, s) * smoothstep(s0 + 2.5, s0 + 2.5 - aa, s);
			col = mix(col, asphalt_col(a - c_on) * 0.95, m);
		}
	}
	// Potholes, cold patch, hot patch: one site per 5 m of each wheel lane;
	// more sites open as the road ages, faster under trucks.
	float hole = 0.0;
	float cold = 0.0;
	if (ribbon > 0.5 && lane_count > 0.5) {
		float pc = floor(along / 5.0);
		float ph = h21(vec2(pc, seed * 61.0 + lane * 3.1));
		float share = HOLE_SHARE * (0.35 + 0.65 * fatigue);
		if (ph < share) {
			float ap = HOLE_FROM + HOLE_SPAN * sqrt(ph / share);
			float j = h21(vec2(pc + 0.5, seed * 17.0 + lane));
			// It opens in the February or March after that age.
			float form = floor(paved + ap) + 0.10 + j * 0.15;
			form += step(form, paved + ap);
			float since = now_years - form;
			if (since > 0.0) {
				float short_of_money = (upkeep < 0.5 && since < 1.0) ? 1.0 : 0.0;
				float open_for = (0.04 + 0.08 * fract(j * 5.0)) * (1.0 + 3.0 * short_of_money);
				float hot_at = floor(form) + HOT_AT + HOT_SPREAD * fract(j * 3.0) + 0.6 * short_of_money;
				float side = j < 0.5 ? -1.0 : 1.0;
				vec2 q = vec2(along - (pc * 5.0 + 1.4 + fract(j * 11.0) * 2.2), dc - side * lane_w * 0.25);
				if (now_years < form + open_for) {
					float r = 0.22 + 0.3 * fract(j * 7.0);
					float d = length(q * vec2(0.8, 1.0)) + (texture(noise_grain, p / 0.5).r - 0.5) * 0.18;
					hole = 1.0 - smoothstep(r - aa, r + aa, d);
					float rim = (1.0 - smoothstep(r, r + 0.12 + aa, d)) * (1.0 - hole);
					col = mix(col, col * 1.25, rim * 0.6);
					col = mix(col, mix(vec3(0.09, 0.085, 0.08), vec3(0.03), smoothstep(r, 0.0, d)), hole);
				} else if (now_years < hot_at) {
					float r = (0.3 + 0.32 * fract(j * 7.0));
					float d = length(q * vec2(0.75, 1.0)) + (texture(noise_soft, p / 0.7).r - 0.5) * 0.3;
					cold = 1.0 - smoothstep(r - aa, r + aa, d);
					float lump = texture(noise_grain, p / 0.12).r;
					col = mix(col, mix(vec3(0.06), vec3(0.14), smoothstep(0.0, 0.5, now_years - form))
						* (0.85 + lump * 0.3 * close), cold);
				} else {
					vec2 hs = vec2(0.7 + fract(j * 13.0) * 0.6, 0.55 + fract(j * 17.0) * 0.3);
					vec2 e = hs - abs(q);
					float m = smoothstep(0.0, aa, e.x) * smoothstep(0.0, aa, e.y);
					float seam = hairline(min(abs(e.x), abs(e.y)), 0.02, aa) * step(-0.03, min(e.x, e.y));
					col = mix(col, asphalt_col(now_years - hot_at) * 0.97, m);
					col = mix(col, vec3(0.06), seam * 0.6);
				}
			}
		}
	}
	// County roads crumble at the edge into the gravel shoulder.
	if (edge_break > 0.5 && ribbon > 0.5) {
		float e = width * 0.5 - abs(x);
		float rag = texture(noise_soft, p / 3.0).r * 0.6 + texture(noise_grain, p / 0.6).r * 0.4;
		float eat = (0.08 + smoothstep(4.0, 25.0, a) * 0.55) * rag;
		float broken = 1.0 - smoothstep(eat - aa, eat + aa, e);
		col = mix(col, vec3(0.55, 0.52, 0.46) * (0.85 + g * 0.3), broken);
	}
	// Oil drips and grime, aggregate speckle up close.
	float oil = smoothstep(0.70, 0.86, texture(noise_grain, turn(p, 1.4) / 3.3).r);
	col *= 1.0 - oil * 0.1 * close;
	col *= 1.0 + (g - 0.5) * 0.28 * close;
	float packed;
	col = winter(col, p, g, packed);
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.92, smoothstep(0.0, 4.0, a)) - rut * 0.12 - tar * fresh * 0.6 - packed * 0.15;
	SPECULAR = 0.3 + tar * fresh * 0.25;
}
""" % [RoadWear.THERMAL_FROM, RoadWear.THERMAL_SPREAD, RoadWear.THERMAL_EVERY, RoadWear.FATIGUE_LATE,
		RoadWear.FATIGUE_SPAN, RoadWear.HOLE_FROM, RoadWear.HOLE_SPAN, RoadWear.HOLE_SHARE,
		RoadWear.HOT_PATCH_AT, RoadWear.HOT_PATCH_SPREAD]


## Lane lines: bright after the spring repaint, duller and patchy through
## the next winter's plowing, gone in a few years if nobody repaints.
static func paint() -> String:
	return header() + """
uniform vec4 paint : source_color = vec4(0.88, 0.88, 0.86, 1.0);
const float PAINT_FROM = %f;
const float PAINT_SPREAD = %f;
const float PAINT_YEARLY = %f;
void fragment() {
	vec2 p = world_pos.xz;
	float seed;
	float a = wear_age(p - origin, seed);
	float paved = now_years - a;
	float job = job_seed(a);
	float off = PAINT_FROM + job * PAINT_SPREAD;
	float every = job < PAINT_YEARLY ? 1.0 : 2.0;
	every *= upkeep < 0.5 ? 2.0 : 1.0;
	float last = max(floor((now_years - off) / every) * every + off, paved);
	float winters = floor(now_years - 0.08) - floor(last - 0.08);
	float w = (now_years - last) * 0.2 + max(winters, 0.0) * 0.25;
	float pat = texture(noise_grain, turn(p, 0.9) / 1.3).r * 0.6 + texture(noise_soft, p / 40.0).r * 0.4;
	float gone = smoothstep(0.75 - w * 0.8, 1.05 - w * 0.8, pat) * smoothstep(0.05, 0.6, w);
	vec3 under = asphalt_col(a);
	vec3 col = mix(paint.rgb, mix(paint.rgb, under, 0.45), smoothstep(0.0, 1.2, w));
	col = mix(col, under, gone * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.8, smoothstep(0.0, 1.0, w));
	SPECULAR = 0.35;
}
""" % [RoadWear.PAINT_FROM, RoadWear.PAINT_SPREAD, RoadWear.PAINT_YEARLY]


## Chip seal county roads: limestone chips rolled into a coat of liquid
## asphalt, redone every few summers. Dark the week it goes down, pale and
## stony after, and the chips work into the binder in the wheel paths.
static func chip() -> String:
	return header() + """
const float CHIP_EVERY = %f;
const float CHIP_SPREAD = %f;
const float CHIP_MONTH = %f;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float aa = max(length(fwidth(p)), 1e-4);
	float seed;
	float a = wear_age(p - origin, seed);
	float paved = now_years - a;
	float along = UV.y * 4.0;
	float u = UV.x * 4.0;
	float x = (u - 0.5) * width;
	float ribbon = step(1e-6, fwidth(along) + fwidth(u));
	float lane;
	float dc;
	float wheel = wheel_path(x, lane, dc) * ribbon;
	float cyc = CHIP_EVERY + job_seed(a) * CHIP_SPREAD;
	float k = floor(a / cyc);
	float last = k < 0.5 ? paved : floor(paved + k * cyc) + CHIP_MONTH;
	if (last > now_years) {
		last = k < 1.5 ? paved : floor(paved + (k - 1.0) * cyc) + CHIP_MONTH;
	}
	float ca = max(now_years - last, 0.0);
	vec3 stone = vec3(0.37, 0.355, 0.32);
	vec3 binder = vec3(0.08, 0.075, 0.07);
	float soft = texture(noise_soft, p / 9.0).r;
	vec3 col = mix(binder, stone, 0.35 + 0.45 * (1.0 - exp(-ca / 0.25))) * (0.9 + soft * 0.16);
	// Chips work down into the binder where the tires run, darker each year
	// and darkest in summer heat; the old layer shows where chips have gone.
	float summer = smoothstep(0.4, 0.55, fract(now_years)) * smoothstep(0.75, 0.6, fract(now_years));
	float flush = wheel * smoothstep(0.5, 5.0, ca) * (0.25 + 0.15 * summer);
	float lost = smoothstep(0.62 - ca * 0.03, 0.75 - ca * 0.03, texture(noise_soft, p / 2.5 + seed).r) * smoothstep(1.0, 4.0, ca);
	col = mix(col, binder * 1.8, max(flush, lost * 0.15));
	// Chips themselves: about 1 cm, blended to their average when smaller
	// than a pixel; loose ones lie bright on the crown and edges at first.
	float chips = texture(noise_grain, p / 0.06).r;
	col *= 1.0 + (chips - 0.5) * 0.45 * clamp(0.02 / aa, 0.0, 1.0);
	float loose = exp(-ca / 0.03) * (1.0 - wheel) * smoothstep(0.55, 0.75, texture(noise_grain, p / 0.4).r);
	col = mix(col, stone * 1.15, loose * 0.5);
	float g = texture(noise_grain, p / 0.31).r;
	col *= 1.0 + (g - 0.5) * 0.2 * close;
	if (ribbon > 0.5) {
		float e = width * 0.5 - abs(x);
		float rag = texture(noise_soft, p / 3.0).r * 0.6 + texture(noise_grain, p / 0.6).r * 0.4;
		float eat = (0.1 + smoothstep(3.0, 20.0, a) * 0.5) * rag;
		col = mix(col, vec3(0.55, 0.52, 0.46) * (0.85 + g * 0.3), 1.0 - smoothstep(eat - aa, eat + aa, e));
	}
	float packed;
	col = winter(col, p, g, packed);
	ALBEDO = col;
	ROUGHNESS = 0.92 - flush * summer * 0.4 - packed * 0.1;
	SPECULAR = 0.25 + flush * summer * 0.2;
}
""" % [RoadWear.CHIP_EVERY, RoadWear.CHIP_SPREAD, RoadWear.CHIP_MONTH]


## Gravel county roads: crushed limestone with two packed tire tracks, loose
## stone and a grassy crown between them, grass creeping in at the edges.
## The county grader smooths it a few times a year (tracks gone, a ridge of
## stone left at the edge); the tracks are back in about two weeks, the
## crown greens over the summer, washboard ripples where cars brake, and
## spring brings puddled potholes.
static func gravel() -> String:
	return header() + """
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 200.0, 0.0, 1.0);
	float aa = max(length(fwidth(p)), 1e-4);
	float seed;
	float a = wear_age(p - origin, seed);
	float along = UV.y * 4.0;
	float u = UV.x * 4.0;
	float x = (u - 0.5) * width;
	float ribbon = step(1e-6, fwidth(along) + fwidth(u));
	float yf = fract(now_years);
	// Graded in mid April, mid June, mid August and late October.
	float job = job_seed(a);
	float j = job * 0.04;
	float g4 = yf < 0.29 + j ? yf + 1.0 - (0.80 + j)
		: yf < 0.45 + j ? yf - (0.29 + j)
		: yf < 0.62 + j ? yf - (0.45 + j)
		: yf < 0.80 + j ? yf - (0.62 + j) : yf - (0.80 + j);
	float patch = texture(noise_soft, p / 11.0).r;
	float grain = texture(noise_grain, p / 0.35).r;
	float drift = (texture(noise_soft, p / 23.0).r - 0.5) * 0.3;
	float tracks = (1.0 - smoothstep(0.18, 0.38, abs(abs(x + drift) - 0.85))) * ribbon;
	tracks *= smoothstep(0.0, 0.035, g4);
	float crown = (1.0 - smoothstep(0.25, 0.55, abs(x + drift))) * ribbon;
	float edge = smoothstep(width * 0.5 - 0.9, width * 0.5, abs(x) + (patch - 0.5) * 0.5) * ribbon;
	vec3 loose = mix(vec3(0.38, 0.36, 0.32), vec3(0.47, 0.45, 0.40), patch);
	loose *= 1.0 + (grain - 0.5) * 0.45 * close;
	vec3 col = mix(loose, vec3(0.56, 0.535, 0.48) * (0.95 + patch * 0.08), tracks * 0.85);
	// The grader's windrow of stone along one edge, spread out by traffic.
	float side = job < 0.5 ? -1.0 : 1.0;
	float wr = (1.0 - smoothstep(0.15, 0.35, abs(x * side - (width * 0.5 - 0.7)))) * exp(-g4 / 0.06) * ribbon;
	col = mix(col, loose * 0.8, wr * 0.7);
	// Washboard where cars brake and pull away: ripples about 0.75 m apart.
	float wb = step(h21(vec2(floor(along / 40.0), seed * 13.0)), 0.35) * smoothstep(0.03, 0.15, g4) * tracks;
	float rip = 0.5 + 0.5 * sin(along / 0.75 * 6.2832);
	col *= 1.0 - wb * rip * 0.08 * patch * clamp(0.25 / max(fwidth(along), 1e-4), 0.0, 1.0);
	// Grass up the crown on a quiet road, regrowing after each grading;
	// green in summer, tan after frost.
	vec3 weed = mix(vec3(0.20, 0.26, 0.10), vec3(0.42, 0.37, 0.25), max(season_look.w, season_look.y));
	weed *= 0.8 + grain * 0.4;
	float grass = crown * smoothstep(0.02, 0.1, g4) * (1.0 - traffic) * 1.4
		* smoothstep(0.4, 0.65, texture(noise_soft, turn(p, 1.3) / 2.0).r + 0.15);
	col = mix(col, weed, clamp(max(grass, edge), 0.0, 1.0) * 0.85);
	// Spring: puddled potholes in the tracks until the first grading.
	float wet = 0.0;
	if (yf > 0.15 && yf < 0.29 + j && ribbon > 0.5) {
		float pc = floor(along / 6.0);
		float h = h21(vec2(pc, seed * 41.0 + sign(x)));
		if (h < 0.18) {
			vec2 q = vec2(along - pc * 6.0 - 3.0, abs(x) - 0.85);
			float d = length(q * vec2(0.6, 1.0)) + (patch - 0.5) * 0.2;
			wet = 1.0 - smoothstep(0.3 + h - aa, 0.3 + h + aa, d);
			col = mix(col, vec3(0.20, 0.21, 0.21), wet);
		}
	}
	float cover = smoothstep(0.15, 0.55, snow * 0.9 + patch * 0.35 - 0.1) * mix(1.0, 0.45, tracks);
	col = mix(col, vec3(0.80, 0.83, 0.88) * (0.93 + grain * 0.07), cover);
	ALBEDO = col;
	ROUGHNESS = 0.95 - tracks * 0.1 - wet * 0.8;
	SPECULAR = 0.2 + wet * 0.3;
}
"""


## Jointed concrete: 15 ft slabs (INDOT), longitudinal joints at the lane
## lines, light grey going darker with grime; the odd panel cracked across
## or broken at a corner, and on old ones a panel patched in asphalt.
static func concrete() -> String:
	return header() + """
const float SLAB = %f;
void fragment() {
	vec2 p = world_pos.xz;
	float close = clamp(1.0 - length(VERTEX) / 220.0, 0.0, 1.0);
	float aa = max(length(fwidth(p)), 1e-4);
	float seed;
	float a = wear_age(p - origin, seed);
	float along = UV.y * 4.0;
	float u = UV.x * 4.0;
	float x = (u - 0.5) * width;
	float ribbon = step(1e-6, fwidth(along) + fwidth(u));
	float lane;
	float dc;
	float wheel = wheel_path(x, lane, dc) * ribbon;
	float x0 = (mirror > 0.5 ? -lane_start - lane_w * (lane_count - 0.5) : lane_start - lane_w * 0.5);
	vec2 sl = vec2(along / SLAB, (x - x0) / lane_w);
	vec2 id = floor(sl);
	vec2 f = sl - id;
	float sh = h21(id + seed * 41.0);
	vec3 col = mix(vec3(0.72, 0.71, 0.68), vec3(0.57, 0.56, 0.53), smoothstep(0.0, 22.0, a));
	col *= 0.95 + sh * 0.07 * ribbon;
	col *= 1.0 - smoothstep(0.55, 0.85, texture(noise_soft, turn(p, 0.5) / 9.0).r) * 0.05;
	col *= 1.0 - wheel * 0.07 * smoothstep(0.0, 10.0, a);
	float g = texture(noise_grain, p / 0.5).r;
	col *= 1.0 + (g - 0.5) * 0.14 * close;
	if (ribbon > 0.5) {
		// Sealed joints.
		vec2 dj = min(f, 1.0 - f) * vec2(SLAB, lane_w);
		float joint = max(hairline(dj.x, 0.008, aa),
			hairline(dj.y, 0.008, aa) * step(0.0, id.y) * step(id.y, lane_count * (mirror > 0.5 ? 2.0 : 1.0) - 1.0));
		col = mix(col, vec3(0.2, 0.2, 0.2), joint * 0.8);
		// Cracked panels: more with age and trucks.
		float share = 0.3 * smoothstep(8.0, 35.0, a) * (0.5 + fatigue);
		if (sh < share) {
			float t = fract(sh * 13.0);
			vec2 m = f * vec2(SLAB, lane_w);
			float wob = (texture(noise_soft, p / 3.0).r - 0.5) * 0.5;
			float d = t < 0.5 ? abs(m.x - SLAB * 0.45 - wob)
				: abs((m.x + m.y) - 1.6 - wob) * 0.707 + step(1.8, m.x + m.y) * 9.0;
			col = mix(col, vec3(0.16), hairline(d, 0.006 + 0.008 * smoothstep(10.0, 30.0, a), aa) * 0.85);
			if (sh < share * 0.12 && a > 15.0) {
				col = mix(col, asphalt_col(a * 0.4), 1.0);  // a broken panel patched in asphalt
			}
		}
	}
	float packed;
	col = winter(col, p, g, packed);
	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
}
""" % [RoadWear.SLAB]
