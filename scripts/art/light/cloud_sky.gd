class_name CloudSky
extends RefCounted
## The desktop app's sky (Forward+ only; the browser keeps SkyLight's plain
## gradient). Benchmark: photos of a Grant County summer sky.
##   - Fair-weather cumulus (cumulus humilis): flat grey bases about
##     1,500 m up (the Midwest's summer cloud base, 1-2 km), sunlit
##     cauliflower tops, each a few hundred metres to a kilometre across,
##     with blue between them. They drift with the wind at their height
##     (about 8 m/s) and shrink toward the horizon, where they bunch up
##     and fade into the haze.
##   - How much of the sky is cloud follows Weather.cover: a few puffs on a
##     clear day, broken cloud on a partly cloudy one, a grey lid when it's
##     overcast.
##   - The open sky is deep blue overhead and pale toward the horizon, and
##     whiter around the sun (light scattered forward by the haze, Mie
##     scattering), bluer away from it.
##   - The sun is a real-size disc (0.53 degrees) with a tight glow.
## Clouds drift (TIME) only from High up: a sky that changes every frame
## re-renders the scene's skylight every frame. Below that they stand still.

const CODE := """
shader_type sky;
#MOVING

uniform vec3 top_color : source_color = vec3(0.17, 0.36, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.79, 0.84);
uniform float curve = 0.12;
uniform sampler2D stars : source_color, filter_linear;
uniform float stars_alpha = 0.0;
uniform float cover = 0.15;
uniform vec2 drift = vec2(0.0);
// Cloud base height and wind, in metres and metres per second.
uniform float base_m = 1500.0;
uniform vec2 wind = vec2(6.0, 5.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = r * p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Cloud at a point on the cloud layer (metres): x how much cloud (its
// edge), y how thick it is there. Billows a few hundred metres across,
// grouped into fields a few kilometres across.
vec2 cloud2(vec2 m, float c) {
	float big = noise(m / 5200.0);
	float n = fbm(m / 1400.0) * 0.8 + big * 0.35;
	// Calibrated so about `c` of the sky is cloud.
	float thr = mix(0.80, 0.28, c);
	return vec2(smoothstep(thr, thr + 0.05, n), smoothstep(thr + 0.02, thr + 0.2, n));
}

float cloud(vec2 m, float c) {
	return cloud2(m, c).x;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	// The open sky: SkyLight's gradient (same curve as its plain sky).
	float va = acos(clamp(up, 0.0, 1.0));
	float c = 1.0 - va / (PI * 0.5);
	vec3 col = mix(horizon_color, top_color, clamp(1.0 - pow(1.0 - c, 1.0 / curve), 0.0, 1.0));
	vec3 sun_c = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(0.0);
	float mu = LIGHT0_ENABLED ? dot(d, LIGHT0_DIRECTION) : 0.0;
	// Bluer and a touch deeper away from the sun, whiter toward it.
	col *= mix(0.92, 1.0, mu * 0.5 + 0.5);
	float day = LIGHT0_ENABLED ? smoothstep(-0.1, 0.15, LIGHT0_DIRECTION.y) : 0.0;
	col += sun_c * (0.10 * pow(max(mu, 0.0), 6.0) + 0.35 * pow(max(mu, 0.0), 120.0)) * 0.25 * day;
	// Stars, faded in at night.
	vec4 st = texture(stars, SKY_COORDS);
	col += st.rgb * st.a * stars_alpha;
	if (up > 0.0) {
		vec2 off = drift;
#ifdef MOVING
		off += wind * TIME;
#endif
		// Where this sight line meets the cloud base.
		float t = base_m / max(up, 0.035);
		vec2 m = d.xz * t + off;
		vec2 cl = cloud2(m, cover);
		float dens = cl.x;
		if (dens > 0.001) {
			// Thicker toward the sun = darker underside; a sample a little
			// toward the sun says how much cloud the light passes through.
			vec2 to_sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION.xz + vec2(1e-4)) : vec2(0.0);
			float thick = cloud(m + to_sun * 260.0, cover);
			float lit = clamp(1.0 - thick * 0.6 + dens * 0.25, 0.0, 1.0);
			// Seen from below, a thick cloud's middle is its flat grey base;
			// its thin edges let the sun through. Low in the sky its sunlit
			// sides show more.
			lit *= 1.0 - cl.y * mix(0.85, 0.45, smoothstep(0.65, 0.95, 1.0 - up));
			// Sunlit cloud is about as bright as a white wall in sun; the
			// shaded base is the sky's grey-blue.
			vec3 bright = sun_c * 0.62 + horizon_color * 0.35;
			vec3 base = mix(horizon_color, top_color, 0.35) * 0.5 + sun_c * 0.05;
			vec3 cc = mix(base, bright, lit);
			// Silver lining toward the sun.
			cc += sun_c * pow(max(mu, 0.0), 10.0) * (1.0 - dens) * 0.6 * day;
			// Overcast: one grey lid, darker the thicker it is.
			cc = mix(cc, mix(horizon_color, vec3(0.62, 0.64, 0.67), 0.5) * (0.85 + 0.15 * day), smoothstep(0.75, 1.0, cover) * 0.8);
			// Far clouds sink into the haze at the horizon.
			float far = 1.0 - exp(-t / 26000.0);
			cc = mix(cc, horizon_color, far * 0.85);
			float a = dens * smoothstep(0.0, 0.06, up);
			col = mix(col, cc, a);
		}
	}
	// The sun's disc, hidden by cloud in front of it.
	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {
		float r = acos(clamp(mu, -1.0, 1.0));
		float disc = 1.0 - smoothstep(0.0040, 0.0050, r);
		float clear = 1.0;
		if (up > 0.0) {
			vec2 off = drift;
#ifdef MOVING
			off += wind * TIME;
#endif
			clear = 1.0 - cloud(d.xz * (base_m / max(up, 0.035)) + off, cover);
		}
		col = mix(col, sun_c * 6.0, disc * clear * day);
	}
	COLOR = col;
}
"""


## A sky material; `moving` lets the clouds drift (High and up).
static func make(moving: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CODE.replace("#MOVING", "#define MOVING" if moving else "")
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
