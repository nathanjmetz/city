class_name VehicleMaterial
extends RefCounted
## One shader for every vehicle. Vertex alpha picks the surface (see
## VehicleModels); per-instance custom data carries the body colour (sRGB) in
## rgb and, in alpha, 1 while braking plus 2 while running emergency lights
## plus OFF (4) for a parked one with its engine off: no lamps lit.
## Cheap enough for the Compatibility renderer. The Ultra version (desktop,
## Forward+) adds a clear coat over metallic flake paint, road grime that
## builds toward the sills and wheels, and tinted, sharper glass.

const SHADER := """
shader_type spatial;
render_mode cull_back;
global uniform float night;
global uniform float snow;
uniform bool ultra = false;
varying vec4 v_custom;
varying float v_side;
varying float v_y;
varying vec3 v_local;
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
// The Compatibility renderer (the browser) hands INSTANCE_CUSTOM's rgb
// over as if it were an sRGB colour, already turned linear (alpha comes
// through as is); undo that so custom data reads as on the desktop.
vec4 custom_data(vec4 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c.rgb = mix(c.rgb * 12.92, 1.055 * pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c.rgb));
#endif
	return c;
}
varying vec3 v_world;
void vertex() {
	v_custom = custom_data(INSTANCE_CUSTOM);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_side = VERTEX.x;
	v_y = VERTEX.y;
	v_local = VERTEX;
}
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
// Smooth value noise (0 to 1), for soft-edged patches.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void fragment() {
	float code = COLOR.a;
	// Flags, rounded first: custom data comes through a hair under a whole
	// number (2.0 as 1.9999 would read as braking).
	int flags = int(v_custom.a + 0.5);
	float brake = float(flags & 1);
	float siren = float((flags >> 1) & 1);
	float running = 1.0 - float((flags >> 2) & 1);
	vec3 col = lin(COLOR.rgb);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	float snowed = 0.0;
	if (code < 0.05) {          // body paint
		col = lin(v_custom.rgb);
		rough = 0.28;
		metal = 0.12;
		spec = 0.6;
	} else if (code < 0.15) {   // glass
		rough = 0.04;
		spec = 0.9;
	} else if (code < 0.25) {   // chrome, steel
		rough = 0.28;
		metal = 0.85;
	} else if (code < 0.35) {   // black plastic, rubber
		rough = 0.85;
		spec = 0.25;
	} else if (code < 0.45) {   // fixed colours (decals, liveries)
		rough = 0.45;
	} else if (code < 0.55) {   // headlights, on full after dark
		rough = 0.1;
		emit = col * (0.35 + smoothstep(0.3, 0.7, night) * 5.0) * running;
	} else if (code < 0.65) {   // tail lights, bright when braking
		rough = 0.2;
		emit = vec3(1.0, 0.04, 0.02) * (0.15 + smoothstep(0.3, 0.7, night) * 1.2 + brake * 2.5) * running;
	} else if (code < 0.75) {   // red and blue emergency lights
		float on = siren;
		float flash = step(0.5, fract(TIME * 1.6 + (v_side > 0.0 ? 0.5 : 0.0)));
		col *= 0.5;
		emit = lin(COLOR.rgb) * on * flash * 4.0;
	} else {                    // amber beacons always turn
		float flash = step(0.55, fract(TIME * 1.1));
		col *= 0.6;
		emit = lin(COLOR.rgb) * flash * 3.0 * running;
	}
	if (ultra) {
		if (code < 0.05) {
			// Metallic paint on most colours, solid on whites and blacks;
			// a glossy clear coat over both.
			float sat = max(max(v_custom.r, v_custom.g), v_custom.b) - min(min(v_custom.r, v_custom.g), v_custom.b);
			float lum = dot(v_custom.rgb, vec3(0.3, 0.59, 0.11));
			float flake = step(0.12, sat) + step(0.25, lum) * step(lum, 0.8);
			metal = mix(0.1, 0.55, clamp(flake, 0.0, 1.0));
			rough = 0.32;
		} else if (code < 0.15) {
			// Glass mirrors what is around it, not just the sky: the road
			// and verges below the horizon, a dark tree line along it, pale
			// haze just above and deeper blue overhead, strongest at a
			// glancing angle (Fresnel). Face on, the dark cabin shows.
			vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
			float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
			vec3 env = mix(vec3(0.05, 0.05, 0.045), vec3(0.09, 0.1, 0.07), smoothstep(-0.4, 0.0, r.y));
			env = mix(env, vec3(0.05, 0.07, 0.04), smoothstep(-0.01, 0.01, r.y));
			env = mix(env, vec3(0.62, 0.68, 0.74), smoothstep(0.05, 0.16, r.y));
			env = mix(env, vec3(0.32, 0.45, 0.68), smoothstep(0.25, 0.9, r.y));
			emit = env * mix(0.12, 1.0, fres) * (1.0 - 0.9 * night);
			col = vec3(0.01, 0.012, 0.014);
			rough = 0.02;
			spec = 0.15;
		} else if (code > 0.55 && code < 0.65) {
			// Tail lamp lenses are moulded and ribbed: a soft sheen, so
			// screen-space reflections don't sparkle on them.
			rough = 0.4;
		} else if (code < 0.35 && code > 0.25) {
			// Rubber and plastic aren't one flat black.
			col *= 0.9 + 0.2 * hash(floor(VERTEX * 40.0));
		}
		// Road grime: dust and spray, heaviest on the sills and wheels.
		float grime = (1.0 - smoothstep(0.2, 0.9, v_y)) * (0.6 + 0.4 * hash(floor(VERTEX * 6.0)));
		if (code < 0.45 && code > 0.15 || code < 0.05) {
			col = mix(col, vec3(0.16, 0.13, 0.10), grime * 0.35);
			rough = mix(rough, 0.85, grime * 0.6);
			// In winter the spray is road salt: a dull grey-white crust up
			// the doors and fenders of everything that drives (INDOT salts
			// state roads all winter; every car in Indiana wears it by
			// January).
			col = mix(col, vec3(0.42, 0.41, 0.39), grime * grime * smoothstep(0.2, 0.7, snow) * 0.75);
		}
	}
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// Snow on the desktop: while snow lies on the ground it lies on what
	// faces up too. A car parked with its engine off is under a full blanket
	// on roof, hood, trunk and windshield; one being driven has had its
	// glass scraped and keeps only patches on the roof and trunk lid, as
	// people leave it (benchmark: Indiana street and lot photos after a
	// snowfall, January). Lamps on a moving car are brushed clear.
	if (snow > 0.05) {
		float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		float lay = smoothstep(0.45, 0.8, up);
		float n = vnoise(v_local * 1.3 + v_custom.rgb * 17.0) * 0.7 + vnoise(v_local * 5.0) * 0.3;
		float parked = 1.0 - running;
		// Parked: the whole top, broken only where it curves away. Driven:
		// a few soft patches left on the roof, none on the glass.
		float s = parked * smoothstep(0.15, 0.6, snow) * smoothstep(0.35, 0.6, lay * (0.7 + 0.6 * n));
		s += running * smoothstep(0.5, 0.9, snow) * lay * smoothstep(0.58, 0.68, n) * step(0.9, v_y)
			* (code > 0.05 && code < 0.15 ? 0.0 : 0.9);
		s = clamp(s, 0.0, 1.0);
		if (code < 0.45 || parked > 0.5) {
			col = mix(col, vec3(0.78, 0.8, 0.84), s);
			rough = mix(rough, 0.75, s);
			metal = mix(metal, 0.0, s);
			spec = mix(spec, 0.35, s);
			emit *= 1.0 - s;
			snowed = s;
		}
	}
#endif
	if (ultra && code < 0.05) {
		// A glossy clear coat, except under snow.
		CLEARCOAT = 1.0 - snowed;
		CLEARCOAT_ROUGHNESS = 0.06;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	// Streetlight on roofs, bonnets and the near side (LampLight; desktop).
	EMISSION = emit + lamp_light(v_world, col * (1.0 - metal), rough, NORMAL, VIEW, VIEW_MATRIX, mix(spec, 1.0, metal));
}
"""

## Custom-data alpha flag for a vehicle parked with its engine off.
const OFF := 4.0

static var _mat: ShaderMaterial
static var _ultra: ShaderMaterial


## The shared material; `ultra` gives the desktop Ultra tier's version.
static func get_material(ultra := false) -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		LampLight.ensure_globals()
		sh.code = SHADER.replace("void vertex() {", LampLight.GLSL + "void vertex() {")
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_ultra = ShaderMaterial.new()
		_ultra.shader = sh
		_ultra.set_shader_parameter("ultra", true)
	return _ultra if ultra else _mat
